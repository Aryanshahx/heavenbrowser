package com.hypertechlabs.heavenbrowser;

import android.annotation.SuppressLint;
import android.content.Context;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import io.flutter.plugin.common.MethodChannel;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Unpacks and runs real Desktop Chrome Extensions (.crx v2/v3, Chrome Web Store URLs, and .zip
 * unpacked MV2/MV3 bundles) inside Android WebView with:
 * - Isolated per-extension lexical chrome.* & browser.* WebExtension API polyfill
 * - Live offscreen MV2/MV3 background worker/page execution & runtime.sendMessage/Port bridge
 * - Stage-aware DOCUMENT_START and DOCUMENT_IDLE content_scripts + late DOMContentLoaded dispatch
 * - Native MV3 declarativeNetRequest block-rule enforcement
 * - https://chrome-ext.heaven.local/<extId>/... virtual HTTPS origin + CORS proxy
 */
public final class HeavenChromeExtManager {

  public interface ActiveTabExtensionBridge {
    void evalInActiveTab(String jsCode);

    void openNewTab(String url);

    String getActiveTabUrl();

    String getActiveTabTitle();
  }

  public static final String EXT_VIRTUAL_HOST = "chrome-ext.heaven.local";
  private static final String REGISTRY_FILE = "registry.json";
  private static final String STORAGE_FILE = "__heaven_storage.json";
  private static final String POLYFILL_PATH = "/__heaven_chrome_polyfill.js";
  private static final String BG_HOST_PATH = "/__heaven_bg.html";
  private static final String EXT_FETCH_PATH = "/__heaven_ext_fetch";
  private static final Pattern EXT_ID_PATTERN = Pattern.compile("([a-p]{32})");

  private static final class DnrBlockRule {
    final String urlSubstring;
    final List<String> domains;
    final List<String> excludedDomains;

    DnrBlockRule(String urlSubstring, List<String> domains, List<String> excludedDomains) {
      this.urlSubstring = urlSubstring;
      this.domains = domains;
      this.excludedDomains = excludedDomains;
    }

    boolean matches(String fullUrlLower, String reqHost, String pageHost) {
      if (urlSubstring == null || urlSubstring.isEmpty()) {
        return false;
      }
      if (!fullUrlLower.contains(urlSubstring) && !reqHost.contains(urlSubstring)) {
        return false;
      }
      String pHost = pageHost != null ? pageHost.toLowerCase(Locale.US) : "";
      if (!excludedDomains.isEmpty() && !pHost.isEmpty()) {
        for (String ex : excludedDomains) {
          if (pHost.equals(ex) || pHost.endsWith("." + ex)) {
            return false;
          }
        }
      }
      if (!domains.isEmpty()) {
        if (pHost.isEmpty()) {
          return false;
        }
        boolean domainMatch = false;
        for (String dm : domains) {
          if (pHost.equals(dm) || pHost.endsWith("." + dm)) {
            domainMatch = true;
            break;
          }
        }
        if (!domainMatch) {
          return false;
        }
      }
      return true;
    }
  }

  private final Context appContext;
  private final File rootDir;
  private final ExecutorService ioPool = Executors.newCachedThreadPool();
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final Object lock = new Object();

  private JSONArray registryArray = new JSONArray();
  private volatile List<DnrBlockRule> compiledDnrRules = Collections.emptyList();
  private final Map<String, WebView> bgWebViews = new ConcurrentHashMap<>();
  private final Map<String, MethodChannel.Result> pendingBgCallbacks = new ConcurrentHashMap<>();
  private volatile ActiveTabExtensionBridge activeTabBridge;

  public HeavenChromeExtManager(Context context) {
    this.appContext = context.getApplicationContext();
    this.rootDir = new File(this.appContext.getFilesDir(), "chrome_extensions");
    if (!this.rootDir.exists()) {
      //noinspection ResultOfMethodCallIgnored
      this.rootDir.mkdirs();
    }
    loadRegistry();
    ioPool.execute(this::rebuildDnrRulesAndBootBackgrounds);
  }

  public void setActiveTabBridge(ActiveTabExtensionBridge bridge) {
    this.activeTabBridge = bridge;
  }

  public static String extractWebStoreExtensionId(String rawUrlOrId) {
    if (rawUrlOrId == null) {
      return null;
    }
    String clean = rawUrlOrId.trim().toLowerCase(Locale.US);
    if (clean.matches("^[a-p]{32}$")) {
      return clean;
    }
    if (clean.contains("chromewebstore.google.com")
        || clean.contains("chrome.google.com/webstore")
        || clean.contains("clients2.google.com/service/update2/crx")
        || clean.contains("update.googleapis.com/service/update2/crx")) {
      Matcher m = EXT_ID_PATTERN.matcher(clean);
      String lastMatch = null;
      while (m.find()) {
        lastMatch = m.group(1);
      }
      return lastMatch;
    }
    return null;
  }

  private void loadRegistry() {
    synchronized (lock) {
      File reg = new File(rootDir, REGISTRY_FILE);
      if (!reg.exists()) {
        registryArray = new JSONArray();
        return;
      }
      try {
        String txt = readUtf8File(reg);
        registryArray = new JSONArray(txt);
      } catch (Throwable ignored) {
        registryArray = new JSONArray();
      }
    }
  }

  private void saveRegistryLocked() {
    File reg = new File(rootDir, REGISTRY_FILE);
    try (FileOutputStream fos = new FileOutputStream(reg, false)) {
      fos.write(registryArray.toString().getBytes(StandardCharsets.UTF_8));
    } catch (IOException ignored) {
    }
  }

  public List<Map<String, Object>> listInstalledExtensions() {
    synchronized (lock) {
      List<Map<String, Object>> out = new ArrayList<>(registryArray.length());
      for (int i = 0; i < registryArray.length(); i++) {
        JSONObject item = registryArray.optJSONObject(i);
        if (item != null) {
          out.add(extensionJsonToSummaryMap(item));
        }
      }
      return out;
    }
  }

  public void installFromWebStore(final String urlOrId, final MethodChannel.Result callback) {
    final String extId = extractWebStoreExtensionId(urlOrId);
    if (extId == null) {
      Map<String, Object> err = new HashMap<>();
      err.put("ok", false);
      err.put(
          "error",
          "Enter a valid Chrome Web Store extension link or 32-character Chrome Extension ID.");
      callback.success(err);
      return;
    }

    ioPool.execute(
        () -> {
          try {
            byte[] crxBytes = downloadExtensionCrxMultiStage(extId);
            if (crxBytes == null || crxBytes.length < 32) {
              postFailure(
                  callback,
                  "Chrome Web Store returned an empty CRX package for ID " + extId + ".");
              return;
            }
            Map<String, Object> installed = unpackAndRegisterPackage(extId, crxBytes, "webstore");
            rebuildDnrRulesAndBootBackgrounds();
            bootBackgroundWorker(extId, true);
            mainHandler.post(() -> callback.success(installed));
          } catch (Throwable t) {
            postFailure(
                callback,
                "Failed to download Chrome extension: "
                    + (t.getMessage() != null ? t.getMessage() : t.getClass().getSimpleName()));
          }
        });
  }

  public void installFromLocalBytes(
      final String fileName, final byte[] bytes, final MethodChannel.Result callback) {
    if (bytes == null || bytes.length < 22) {
      postFailure(callback, "Selected .crx / .zip package is empty or invalid.");
      return;
    }
    ioPool.execute(
        () -> {
          try {
            String seed =
                (fileName != null ? fileName : "ext") + "_" + System.currentTimeMillis();
            String generatedId = generateSyntheticExtId(seed);
            Map<String, Object> installed =
                unpackAndRegisterPackage(generatedId, bytes, "local_crx");
            rebuildDnrRulesAndBootBackgrounds();
            bootBackgroundWorker(generatedId, true);
            mainHandler.post(() -> callback.success(installed));
          } catch (Throwable t) {
            postFailure(
                callback,
                "Invalid Chrome .crx/.zip package: "
                    + (t.getMessage() != null ? t.getMessage() : "corrupt archive"));
          }
        });
  }

  public boolean setExtensionEnabled(String extId, boolean enabled) {
    boolean ok = false;
    synchronized (lock) {
      for (int i = 0; i < registryArray.length(); i++) {
        JSONObject item = registryArray.optJSONObject(i);
        if (item != null && extId.equals(item.optString("id"))) {
          try {
            item.put("enabled", enabled);
            saveRegistryLocked();
            ok = true;
            break;
          } catch (Throwable ignored) {
            return false;
          }
        }
      }
    }
    if (ok) {
      ioPool.execute(
          () -> {
            rebuildDnrRulesAndBootBackgrounds();
            if (!enabled) {
              stopBackgroundWorker(extId);
            } else {
              bootBackgroundWorker(extId, false);
            }
          });
    }
    return ok;
  }

  public boolean uninstallExtension(String extId) {
    boolean removed = false;
    synchronized (lock) {
      JSONArray updated = new JSONArray();
      for (int i = 0; i < registryArray.length(); i++) {
        JSONObject item = registryArray.optJSONObject(i);
        if (item != null && extId.equals(item.optString("id"))) {
          removed = true;
        } else if (item != null) {
          updated.put(item);
        }
      }
      registryArray = updated;
      saveRegistryLocked();
      File extDir = new File(rootDir, sanitizeId(extId));
      deleteRecursively(extDir);
    }
    stopBackgroundWorker(extId);
    ioPool.execute(this::rebuildDnrRulesAndBootBackgrounds);
    return removed;
  }

  public void shutdown() {
    for (String id : new ArrayList<>(bgWebViews.keySet())) {
      stopBackgroundWorker(id);
    }
    ioPool.shutdownNow();
  }

  private void stopBackgroundWorker(final String extId) {
    final String cleanId = sanitizeId(extId);
    mainHandler.post(
        () -> {
          WebView wv = bgWebViews.remove(cleanId);
          if (wv != null) {
            try {
              wv.stopLoading();
              wv.destroy();
            } catch (Throwable ignored) {
            }
          }
        });
  }

  private void rebuildDnrRulesAndBootBackgrounds() {
    List<JSONObject> enabledExts = new ArrayList<>();
    synchronized (lock) {
      for (int i = 0; i < registryArray.length(); i++) {
        JSONObject item = registryArray.optJSONObject(i);
        if (item != null && item.optBoolean("enabled", true)) {
          enabledExts.add(item);
        }
      }
    }

    List<DnrBlockRule> nextRules = new ArrayList<>();
    for (JSONObject ext : enabledExts) {
      String extId = sanitizeId(ext.optString("id", ""));
      File extDir = new File(rootDir, extId);
      if (!extDir.isDirectory()) {
        continue;
      }
      JSONArray dnrPaths = ext.optJSONArray("dnrRulePaths");
      if (dnrPaths != null) {
        for (int r = 0; r < dnrPaths.length(); r++) {
          String rel = dnrPaths.optString(r, "");
          String rawRules = safeReadAssetUtf8(extDir, rel);
          parseDnrRuleFile(rawRules, nextRules);
        }
      }
      if (hasBackgroundConfig(ext)) {
        bootBackgroundWorker(extId, false);
      }
    }
    compiledDnrRules = nextRules;
  }

  private static boolean hasBackgroundConfig(JSONObject ext) {
    if (ext == null) return false;
    if (!ext.optString("bgWorker", "").isEmpty()) return true;
    if (!ext.optString("bgPage", "").isEmpty()) return true;
    JSONArray scripts = ext.optJSONArray("bgScripts");
    return scripts != null && scripts.length() > 0;
  }

  private static void parseDnrRuleFile(String rawJson, List<DnrBlockRule> sink) {
    if (rawJson == null || rawJson.isEmpty() || sink.size() >= 2500) {
      return;
    }
    try {
      JSONArray arr = new JSONArray(rawJson);
      for (int i = 0; i < arr.length() && sink.size() < 2500; i++) {
        JSONObject rule = arr.optJSONObject(i);
        if (rule == null) continue;
        JSONObject action = rule.optJSONObject("action");
        if (action == null || !"block".equalsIgnoreCase(action.optString("type"))) {
          continue;
        }
        JSONObject cond = rule.optJSONObject("condition");
        if (cond == null) continue;
        String filter = cond.optString("urlFilter", "").trim().toLowerCase(Locale.US);
        while (filter.startsWith("|")) {
          filter = filter.substring(1);
        }
        while (filter.endsWith("^") || filter.endsWith("|") || filter.endsWith("*")) {
          filter = filter.substring(0, filter.length() - 1);
        }
        if (filter.length() < 4 || filter.contains("*")) {
          continue;
        }
        List<String> doms = jsonStringListLower(cond.optJSONArray("initiatorDomains"));
        if (doms.isEmpty()) {
          doms = jsonStringListLower(cond.optJSONArray("domains"));
        }
        List<String> exDoms = jsonStringListLower(cond.optJSONArray("excludedInitiatorDomains"));
        if (exDoms.isEmpty()) {
          exDoms = jsonStringListLower(cond.optJSONArray("excludedDomains"));
        }
        sink.add(new DnrBlockRule(filter, doms, exDoms));
      }
    } catch (Throwable ignored) {
    }
  }

  private static List<String> jsonStringListLower(JSONArray arr) {
    if (arr == null || arr.length() == 0) {
      return Collections.emptyList();
    }
    List<String> out = new ArrayList<>(arr.length());
    for (int i = 0; i < arr.length(); i++) {
      String s = arr.optString(i, "").trim().toLowerCase(Locale.US);
      if (!s.isEmpty()) {
        out.add(s);
      }
    }
    return out;
  }

  public boolean shouldBlockByExtensionDnr(Uri reqUri, String pageHost) {
    List<DnrBlockRule> rules = this.compiledDnrRules;
    if (rules.isEmpty() || reqUri == null) {
      return false;
    }
    String host = reqUri.getHost() != null ? reqUri.getHost().toLowerCase(Locale.US) : "";
    String full = reqUri.toString().toLowerCase(Locale.US);
    for (DnrBlockRule rule : rules) {
      if (rule.matches(full, host, pageHost)) {
        return true;
      }
    }
    return false;
  }

  private JSONObject findExtensionLocked(String extId) {
    String clean = sanitizeId(extId);
    for (int i = 0; i < registryArray.length(); i++) {
      JSONObject item = registryArray.optJSONObject(i);
      if (item != null && clean.equals(sanitizeId(item.optString("id")))) {
        return item;
      }
    }
    return null;
  }

  private final class ExtensionBgJsBridge {
    private final String extId;

    ExtensionBgJsBridge(String extId) {
      this.extId = extId;
    }

    @JavascriptInterface
    public void postMessage(String rawJson) {
      if (rawJson == null || rawJson.isEmpty()) {
        return;
      }
      try {
        JSONObject msg = new JSONObject(rawJson);
        String op = msg.optString("op", "");
        JSONObject data = msg.optJSONObject("data");
        if ("storage_patch".equals(op) && data != null) {
          updateExtensionStorage(extId, data.toString());
        } else if ("bg_reply".equals(op) && data != null) {
          String reqId = data.optString("reqId", "");
          String replyJson = data.optString("replyJson", "{}");
          MethodChannel.Result cb = pendingBgCallbacks.remove(reqId);
          if (cb != null) {
            mainHandler.post(() -> cb.success(replyJson));
          }
        } else if ("tabs_create".equals(op) && data != null) {
          final String url = data.optString("url", "");
          final ActiveTabExtensionBridge bridge = activeTabBridge;
          if (!url.isEmpty() && bridge != null) {
            mainHandler.post(() -> bridge.openNewTab(url));
          }
        } else if ("tabs_reload".equals(op)) {
          final ActiveTabExtensionBridge bridge = activeTabBridge;
          if (bridge != null) {
            mainHandler.post(() -> bridge.evalInActiveTab("location.reload();"));
          }
        } else if ("tabs_send_message".equals(op) && data != null) {
          final String payloadJson = JSONObject.quote(data.optString("messageJson", "{}"));
          final ActiveTabExtensionBridge bridge = activeTabBridge;
          if (bridge != null) {
            final String js =
                "(function(){try{var p=JSON.parse("
                    + payloadJson
                    + ");if(window.__hbExtDeliverMessage)window.__hbExtDeliverMessage('"
                    + extId
                    + "',p);}catch(e){}})();";
            mainHandler.post(() -> bridge.evalInActiveTab(js));
          }
        } else if ("scripting_insert_css".equals(op) && data != null) {
          String css = data.optString("css", "");
          JSONArray files = data.optJSONArray("files");
          if (css.isEmpty() && files != null) {
            File extDir = new File(rootDir, extId);
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < files.length(); i++) {
              sb.append(safeReadAssetUtf8(extDir, files.optString(i, ""))).append('\n');
            }
            css = sb.toString();
          }
          final String finalCss = css;
          final ActiveTabExtensionBridge bridge = activeTabBridge;
          if (!finalCss.isEmpty() && bridge != null) {
            final String js =
                "(function(){var s=document.createElement('style');s.textContent="
                    + JSONObject.quote(finalCss)
                    + ";(document.head||document.documentElement).appendChild(s);})();";
            mainHandler.post(() -> bridge.evalInActiveTab(js));
          }
        } else if ("scripting_exec".equals(op) && data != null) {
          handleExecuteScriptOnActiveTab(extId, data);
        }
      } catch (Throwable ignored) {
      }
    }
  }

  private void handleExecuteScriptOnActiveTab(String extId, JSONObject data) {
    final ActiveTabExtensionBridge bridge = activeTabBridge;
    if (bridge == null || data == null) {
      return;
    }
    File extDir = new File(rootDir, sanitizeId(extId));
    StringBuilder codeBuilder = new StringBuilder();
    JSONArray files = data.optJSONArray("files");
    if (files != null) {
      for (int i = 0; i < files.length(); i++) {
        String rel = files.optString(i, "").trim();
        while (rel.startsWith("/")) rel = rel.substring(1);
        String content = safeReadAssetUtf8(extDir, rel);
        if (!content.isEmpty()) {
          codeBuilder.append(content).append(";\n");
        }
      }
    }
    String rawCode = data.optString("code", "");
    if (!rawCode.isEmpty()) {
      codeBuilder.append(rawCode).append(";\n");
    }
    String funcSrc = data.optString("funcSource", "");
    String argsJson = data.optString("argsJson", "[]");
    if (!funcSrc.isEmpty()) {
      codeBuilder
          .append("(")
          .append(funcSrc)
          .append(").apply(window, ")
          .append(argsJson)
          .append(");\n");
    }
    if (codeBuilder.length() == 0) {
      return;
    }
    String factoryJs =
        buildExtensionChromeFactoryJs(
            sanitizeId(extId),
            extDir,
            bridge.getActiveTabUrl(),
            bridge.getActiveTabTitle());
    final String wrapped =
        "(function(){try{var __c="
            + factoryJs
            + ";(function(chrome,browser){\n"
            + codeBuilder
            + "\n})(__c,__c);}catch(e){}})();";
    mainHandler.post(() -> bridge.evalInActiveTab(wrapped));
  }

  @SuppressLint({"SetJavaScriptEnabled", "JavascriptInterface"})
  private void bootBackgroundWorker(final String rawExtId, final boolean emitInstalledEvent) {
    final String extId = sanitizeId(rawExtId);
    final JSONObject extMeta;
    synchronized (lock) {
      extMeta = findExtensionLocked(extId);
    }
    if (extMeta == null || !extMeta.optBoolean("enabled", true) || !hasBackgroundConfig(extMeta)) {
      return;
    }

    mainHandler.post(
        () -> {
          if (bgWebViews.containsKey(extId) && !emitInstalledEvent) {
            return;
          }
          WebView prev = bgWebViews.remove(extId);
          if (prev != null) {
            try {
              prev.destroy();
            } catch (Throwable ignored) {
            }
          }
          try {
            final WebView bgWv = new WebView(appContext);
            WebSettings s = bgWv.getSettings();
            s.setJavaScriptEnabled(true);
            s.setDomStorageEnabled(true);
            s.setUserAgentString(CRX_DESKTOP_UA);
            bgWv.addJavascriptInterface(new ExtensionBgJsBridge(extId), "HeavenChromeExtChannel");
            bgWv.setWebViewClient(
                new WebViewClient() {
                  @Override
                  public WebResourceResponse shouldInterceptRequest(
                      WebView view, WebResourceRequest request) {
                    if (request != null && request.getUrl() != null) {
                      ActiveTabExtensionBridge br = activeTabBridge;
                      String tUrl = br != null ? br.getActiveTabUrl() : "https://www.google.com";
                      String tTitle = br != null ? br.getActiveTabTitle() : "Google";
                      WebResourceResponse res =
                          interceptExtensionRequest(request.getUrl(), tUrl, tTitle);
                      if (res != null) {
                        return res;
                      }
                    }
                    return super.shouldInterceptRequest(view, request);
                  }

                  @Override
                  public void onPageFinished(WebView view, String url) {
                    super.onPageFinished(view, url);
                    if (emitInstalledEvent) {
                      view.evaluateJavascript(
                          "try{if(window.chrome&&chrome.runtime&&chrome.runtime.onInstalled)"
                              + "chrome.runtime.onInstalled._emit({reason:'install'});}catch(e){}",
                          null);
                    }
                  }
                });
            bgWebViews.put(extId, bgWv);
            String bgPage = extMeta.optString("bgPage", "");
            String targetPath = !bgPage.isEmpty() ? ("/" + bgPage) : BG_HOST_PATH;
            bgWv.loadUrl(
                "https://"
                    + EXT_VIRTUAL_HOST
                    + "/"
                    + extId
                    + targetPath
                    + (emitInstalledEvent ? "?installed=1" : ""));
          } catch (Throwable ignored) {
          }
        });
  }

  public void dispatchRuntimeMessageToBackground(
      final String rawExtId,
      final String messageJson,
      final String senderUrl,
      final MethodChannel.Result result) {
    final String extId = sanitizeId(rawExtId);
    mainHandler.post(
        () -> {
          WebView bgWv = bgWebViews.get(extId);
          if (bgWv == null) {
            bootBackgroundWorker(extId, false);
            bgWv = bgWebViews.get(extId);
          }
          if (bgWv == null) {
            result.success("{}");
            return;
          }
          final String reqId = "req_" + System.nanoTime();
          pendingBgCallbacks.put(reqId, result);
          mainHandler.postDelayed(
              () -> {
                MethodChannel.Result stale = pendingBgCallbacks.remove(reqId);
                if (stale != null) {
                  stale.success("{}");
                }
              },
              2800L);

          String quotedMsg = JSONObject.quote(messageJson != null ? messageJson : "{}");
          String quotedUrl = JSONObject.quote(senderUrl != null ? senderUrl : "");
          String js =
              "(function(){"
                  + "try{"
                  + "var msg=JSON.parse("
                  + quotedMsg
                  + ");"
                  + "var sender={id:'"
                  + extId
                  + "',url:"
                  + quotedUrl
                  + ",tab:{id:1,active:true,url:"
                  + quotedUrl
                  + "}};"
                  + "var replied=false;"
                  + "function done(resp){"
                  + "  if(replied)return;replied=true;"
                  + "  var out='{}';try{out=JSON.stringify(resp===undefined?{}:resp);}catch(e){}"
                  + "  HeavenChromeExtChannel.postMessage(JSON.stringify({extId:'"
                  + extId
                  + "',op:'bg_reply',data:{reqId:'"
                  + reqId
                  + "',replyJson:out}}));"
                  + "}"
                  + "if(window.chrome&&chrome.runtime&&chrome.runtime.onMessage){"
                  + "  var ls=chrome.runtime.onMessage._listeners||[];"
                  + "  if(ls.length===0){done({});return;}"
                  + "  var asyncHold=false;"
                  + "  for(var i=0;i<ls.length;i++){"
                  + "    try{"
                  + "      var r=ls[i](msg,sender,done);"
                  + "      if(r===true){asyncHold=true;}"
                  + "      else if(r&&typeof r.then==='function'){asyncHold=true;r.then(done).catch(function(){done({});});}"
                  + "    }catch(e){}"
                  + "  }"
                  + "  if(!asyncHold)setTimeout(function(){done({});},40);"
                  + "}else{done({});}"
                  + "}catch(e){"
                  + "  HeavenChromeExtChannel.postMessage(JSON.stringify({extId:'"
                  + extId
                  + "',op:'bg_reply',data:{reqId:'"
                  + reqId
                  + "',replyJson:'{}'}}));"
                  + "}"
                  + "})();";
          bgWv.evaluateJavascript(js, null);
        });
  }

  public void dispatchExtensionActionClicked(
      final String rawExtId, final String tabUrl, final String tabTitle) {
    final String extId = sanitizeId(rawExtId);
    bootBackgroundWorker(extId, false);
    mainHandler.postDelayed(
        () -> {
          WebView bgWv = bgWebViews.get(extId);
          String qUrl = JSONObject.quote(tabUrl != null ? tabUrl : "https://www.google.com");
          String qTitle = JSONObject.quote(tabTitle != null ? tabTitle : "Tab");
          if (bgWv != null) {
            String js =
                "(function(){try{"
                    + "var tab={id:1,index:0,windowId:1,active:true,highlighted:true,url:"
                    + qUrl
                    + ",title:"
                    + qTitle
                    + "};"
                    + "if(window.chrome&&chrome.action&&chrome.action.onClicked)chrome.action.onClicked._emit(tab);"
                    + "if(window.chrome&&chrome.browserAction&&chrome.browserAction.onClicked)chrome.browserAction.onClicked._emit(tab);"
                    + "}catch(e){}})();";
            bgWv.evaluateJavascript(js, null);
          }
          ActiveTabExtensionBridge br = activeTabBridge;
          if (br != null && tabUrl != null && tabUrl.startsWith("http")) {
            ioPool.execute(
                () -> {
                  String bundle = buildContentScriptsBundleForUrl(tabUrl, "all", true);
                  if (!bundle.isEmpty()) {
                    mainHandler.post(() -> br.evalInActiveTab(bundle));
                  }
                });
          }
        },
        120L);
  }

  public void updateExtensionStorage(String extId, String patchJson) {
    if (extId == null || extId.isEmpty() || patchJson == null) {
      return;
    }
    final String cleanId = sanitizeId(extId);
    JSONObject changedItems = null;
    synchronized (lock) {
      File extDir = new File(rootDir, cleanId);
      if (!extDir.exists()) {
        return;
      }
      File storeFile = new File(extDir, STORAGE_FILE);
      JSONObject current = new JSONObject();
      if (storeFile.exists()) {
        try {
          current = new JSONObject(readUtf8File(storeFile));
        } catch (Throwable ignored) {
        }
      }
      try {
        JSONObject patch = new JSONObject(patchJson);
        String op = patch.optString("op", "set");
        changedItems = new JSONObject();
        if ("clear".equals(op)) {
          current = new JSONObject();
        } else if ("remove".equals(op)) {
          JSONArray keys = patch.optJSONArray("keys");
          if (keys != null) {
            for (int i = 0; i < keys.length(); i++) {
              String k = keys.optString(i);
              Object oldVal = current.opt(k);
              current.remove(k);
              JSONObject diff = new JSONObject();
              diff.put("oldValue", oldVal);
              changedItems.put(k, diff);
            }
          }
        } else {
          JSONObject items = patch.optJSONObject("items");
          if (items != null) {
            Iterator<String> it = items.keys();
            while (it.hasNext()) {
              String k = it.next();
              Object oldVal = current.opt(k);
              Object newVal = items.opt(k);
              current.put(k, newVal);
              JSONObject diff = new JSONObject();
              if (oldVal != null) diff.put("oldValue", oldVal);
              diff.put("newValue", newVal);
              changedItems.put(k, diff);
            }
          }
        }
        try (FileOutputStream fos = new FileOutputStream(storeFile, false)) {
          fos.write(current.toString().getBytes(StandardCharsets.UTF_8));
        }
      } catch (Throwable ignored) {
      }
    }

    if (changedItems != null && changedItems.length() > 0) {
      final String quotedChanges = JSONObject.quote(changedItems.toString());
      final String syncJs =
          "(function(){try{var ch=JSON.parse("
              + quotedChanges
              + ");if(window.__hbExtSyncStorage)window.__hbExtSyncStorage('"
              + cleanId
              + "',ch);}catch(e){}})();";
      mainHandler.post(
          () -> {
            WebView bgWv = bgWebViews.get(cleanId);
            if (bgWv != null) {
              bgWv.evaluateJavascript(syncJs, null);
            }
            ActiveTabExtensionBridge br = activeTabBridge;
            if (br != null) {
              br.evalInActiveTab(syncJs);
            }
          });
    }
  }

  private JSONObject readExtensionStorageLocked(File extDir) {
    File storeFile = new File(extDir, STORAGE_FILE);
    if (!storeFile.exists()) {
      return new JSONObject();
    }
    try {
      return new JSONObject(readUtf8File(storeFile));
    } catch (Throwable ignored) {
      return new JSONObject();
    }
  }

  /**
   * Serves unpacked Chrome extension assets over https://chrome-ext.heaven.local/<extId>/<path>
   * so extension popups, options pages, background workers, ES modules, CSS, and
   * web_accessible_resources run with a genuine HTTPS origin inside WebView.
   */
  public WebResourceResponse interceptExtensionRequest(
      Uri uri, String activeTabUrl, String activeTabTitle) {
    if (uri == null || !EXT_VIRTUAL_HOST.equalsIgnoreCase(uri.getHost())) {
      return null;
    }
    List<String> segments = uri.getPathSegments();
    if (segments == null || segments.isEmpty()) {
      return buildTextResponse("text/plain", 404, "Missing extension ID");
    }
    String extId = sanitizeId(segments.get(0));
    File extDir = new File(rootDir, extId);
    if (!extDir.exists()) {
      return buildTextResponse("text/plain", 404, "Extension not installed");
    }

    String subPath = uri.getPath();
    if (subPath == null) {
      return buildTextResponse("text/plain", 404, "Invalid path");
    }
    String prefix = "/" + segments.get(0);
    String relPath = subPath.startsWith(prefix) ? subPath.substring(prefix.length()) : subPath;
    if (relPath.isEmpty() || "/".equals(relPath)) {
      relPath = "/popup.html";
    }

    if (POLYFILL_PATH.equals(relPath)) {
      String js = buildChromePagePolyfillJs(extId, extDir, activeTabUrl, activeTabTitle);
      return buildTextResponse("application/javascript", 200, js);
    }

    if (BG_HOST_PATH.equals(relPath)) {
      String bgHtml = buildBackgroundHostHtml(extId);
      return buildTextResponse("text/html", 200, bgHtml);
    }

    if (EXT_FETCH_PATH.equals(relPath)) {
      String targetUrl = uri.getQueryParameter("u");
      return handleExtensionCorsFetch(targetUrl);
    }

    try {
      String cleanRel = relPath.startsWith("/") ? relPath.substring(1) : relPath;
      File target = new File(extDir, cleanRel);
      String canonicalRoot = extDir.getCanonicalPath() + File.separator;
      String canonicalTarget = target.getCanonicalPath();
      if (!canonicalTarget.startsWith(canonicalRoot) || !target.isFile()) {
        return buildTextResponse("text/plain", 404, "Asset not found");
      }

      String mime = guessMimeType(cleanRel);
      if ("text/html".equals(mime)) {
        String html = readUtf8File(target);
        String polyfillTag =
            "<script src=\"https://"
                + EXT_VIRTUAL_HOST
                + "/"
                + extId
                + POLYFILL_PATH
                + "\"></script>";
        String patched;
        int headIdx = html.toLowerCase(Locale.US).indexOf("<head>");
        if (headIdx >= 0) {
          patched = html.substring(0, headIdx + 6) + polyfillTag + html.substring(headIdx + 6);
        } else {
          patched = polyfillTag + html;
        }
        return buildTextResponse("text/html", 200, patched);
      }

      Map<String, String> headers = new HashMap<>();
      headers.put("Access-Control-Allow-Origin", "*");
      headers.put("Cache-Control", "no-cache");
      return new WebResourceResponse(
          mime, "UTF-8", 200, "OK", headers, new FileInputStream(target));
    } catch (Throwable t) {
      return buildTextResponse("text/plain", 500, "Extension read error");
    }
  }

  private String buildBackgroundHostHtml(String extId) {
    JSONObject extMeta;
    synchronized (lock) {
      extMeta = findExtensionLocked(extId);
    }
    StringBuilder html = new StringBuilder(512);
    html.append("<!doctype html><html><head><meta charset=\"utf-8\">");
    html.append("<script src=\"https://")
        .append(EXT_VIRTUAL_HOST)
        .append("/")
        .append(extId)
        .append(POLYFILL_PATH)
        .append("\"></script>");
    if (extMeta != null) {
      String worker = extMeta.optString("bgWorker", "");
      boolean isModule = extMeta.optBoolean("bgIsModule", false);
      if (!worker.isEmpty()) {
        html.append("<script ")
            .append(isModule ? "type=\"module\" " : "")
            .append("src=\"https://")
            .append(EXT_VIRTUAL_HOST)
            .append("/")
            .append(extId)
            .append("/")
            .append(worker)
            .append("\"></script>");
      } else {
        JSONArray scripts = extMeta.optJSONArray("bgScripts");
        if (scripts != null) {
          for (int i = 0; i < scripts.length(); i++) {
            String s = scripts.optString(i, "");
            if (!s.isEmpty()) {
              html.append("<script src=\"https://")
                  .append(EXT_VIRTUAL_HOST)
                  .append("/")
                  .append(extId)
                  .append("/")
                  .append(s)
                  .append("\"></script>");
            }
          }
        }
      }
    }
    html.append("</head><body></body></html>");
    return html.toString();
  }

  private WebResourceResponse handleExtensionCorsFetch(String targetUrl) {
    if (targetUrl == null
        || (!targetUrl.startsWith("https://") && !targetUrl.startsWith("http://"))) {
      return buildTextResponse("application/json", 400, "{\"error\":\"invalid_url\"}");
    }
    try {
      byte[] data =
          HeavenNetHelper.downloadBytesFollowingRedirects(
              appContext, targetUrl, CRX_DESKTOP_UA, false, 4, 4 * 1024 * 1024);
      Map<String, String> headers = new HashMap<>();
      headers.put("Access-Control-Allow-Origin", "*");
      headers.put("Cache-Control", "no-store");
      return new WebResourceResponse(
          "application/octet-stream", "UTF-8", 200, "OK", headers, new ByteArrayInputStream(data));
    } catch (Throwable t) {
      return buildTextResponse("text/plain", 502, "Extension fetch error");
    }
  }

  public String buildContentScriptsBundleForUrl(String pageUrl) {
    return buildContentScriptsBundleForUrl(pageUrl, "all", false);
  }

  public String buildContentScriptsBundleForUrl(String pageUrl, String stageFilter) {
    return buildContentScriptsBundleForUrl(pageUrl, stageFilter, false);
  }

  /**
   * Builds the isolated per-extension JS + CSS bundle for all enabled Desktop Chrome Extensions
   * whose manifest content_scripts match the given page URL (including Google Search, DuckDuckGo,
   * Brave, Bing, Startpage, YouTube, and every website).
   */
  public String buildContentScriptsBundleForUrl(
      String pageUrl, String stageFilter, boolean forceReRun) {
    if (pageUrl == null
        || (!pageUrl.startsWith("http://") && !pageUrl.startsWith("https://"))
        || pageUrl.contains(EXT_VIRTUAL_HOST)) {
      return "";
    }

    List<JSONObject> activeList = new ArrayList<>();
    synchronized (lock) {
      for (int i = 0; i < registryArray.length(); i++) {
        JSONObject ext = registryArray.optJSONObject(i);
        if (ext != null && ext.optBoolean("enabled", true)) {
          activeList.add(ext);
        }
      }
    }
    if (activeList.isEmpty()) {
      return "";
    }

    String stage = stageFilter != null ? stageFilter : "all";
    StringBuilder bundle = new StringBuilder(4096);
    bundle.append("(function(){");
    bundle.append("window.__hbInjectedExtStage=window.__hbInjectedExtStage||{};");
    bundle.append(
        "if(!window.__hbReadyShimInstalled){window.__hbReadyShimInstalled=true;"
            + "var origDocAdd=Document.prototype.addEventListener;"
            + "Document.prototype.addEventListener=function(type,fn,opts){"
            + "  origDocAdd.apply(this,arguments);"
            + "  if(type==='DOMContentLoaded'&&document.readyState!=='loading'&&typeof fn==='function'){"
            + "    setTimeout(function(){try{fn(new Event('DOMContentLoaded'));}catch(e){}},0);"
            + "  }"
            + "};"
            + "}");

    for (JSONObject ext : activeList) {
      String extId = sanitizeId(ext.optString("id", ""));
      File extDir = new File(rootDir, extId);
      if (!extDir.isDirectory()) {
        continue;
      }
      JSONArray contentScripts = ext.optJSONArray("contentScripts");
      if (contentScripts == null || contentScripts.length() == 0) {
        continue;
      }

      boolean anyMatched = false;
      StringBuilder extBlock = new StringBuilder(2048);

      for (int c = 0; c < contentScripts.length(); c++) {
        JSONObject cs = contentScripts.optJSONObject(c);
        if (cs == null) {
          continue;
        }
        String runAt = cs.optString("runAt", "document_idle");
        if ("document_start".equals(stage) && !"document_start".equals(runAt)) {
          continue;
        }
        if ("document_idle".equals(stage) && "document_start".equals(runAt)) {
          continue;
        }

        JSONArray matches = cs.optJSONArray("matches");
        JSONArray excludeMatches = cs.optJSONArray("excludeMatches");
        if (!matchesAnyPattern(pageUrl, matches) || matchesAnyPattern(pageUrl, excludeMatches)) {
          continue;
        }

        anyMatched = true;
        String guardKey = extId + "_" + c;

        JSONArray cssFiles = cs.optJSONArray("css");
        if (cssFiles != null) {
          for (int k = 0; k < cssFiles.length(); k++) {
            String relCss = cssFiles.optString(k, "");
            String cssContent = safeReadAssetUtf8(extDir, relCss);
            if (!cssContent.isEmpty()) {
              String styleId = "hb-ext-css-" + extId + "-" + c + "-" + k;
              extBlock
                  .append("(function(){if(document.getElementById('")
                  .append(styleId)
                  .append("'))return;var s=document.createElement('style');s.id='")
                  .append(styleId)
                  .append("';s.textContent=")
                  .append(JSONObject.quote(cssContent))
                  .append(";(document.head||document.documentElement).appendChild(s);})();");
            }
          }
        }

        JSONArray jsFiles = cs.optJSONArray("js");
        if (jsFiles != null && jsFiles.length() > 0) {
          extBlock.append("(function(){");
          if (!forceReRun) {
            extBlock
                .append("var gk='")
                .append(guardKey)
                .append(":'+location.href;")
                .append("if(window.__hbInjectedExtStage[gk])return;")
                .append("window.__hbInjectedExtStage[gk]=true;");
          }
          for (int j = 0; j < jsFiles.length(); j++) {
            String relJs = jsFiles.optString(j, "");
            String jsContent = safeReadAssetUtf8(extDir, relJs);
            if (!jsContent.isEmpty()) {
              extBlock.append("try{\n").append(jsContent).append("\n}catch(e){}\n");
            }
          }
          extBlock.append("})();");
        }
      }

      if (anyMatched && extBlock.length() > 0) {
        String factoryJs = buildExtensionChromeFactoryJs(extId, extDir, pageUrl, "");
        bundle
            .append("(function(){try{var __extChrome=")
            .append(factoryJs)
            .append(";(function(chrome,browser){\n")
            .append(extBlock)
            .append("\n})(__extChrome,__extChrome);}catch(_e){}})();");
      }
    }
    bundle.append("})();");
    return bundle.toString();
  }

  private String buildChromePagePolyfillJs(
      String extId, File extDir, String activeTabUrl, String activeTabTitle) {
    String factoryJs = buildExtensionChromeFactoryJs(extId, extDir, activeTabUrl, activeTabTitle);
    return "(function(){var c="
        + factoryJs
        + ";window.chrome=c;window.browser=c;self.chrome=c;self.browser=c;"
        + "var origFetch=window.fetch;"
        + "if(origFetch&&location.hostname==='"
        + EXT_VIRTUAL_HOST
        + "'){"
        + "  window.fetch=function(input,init){"
        + "    var u=typeof input==='string'?input:(input&&input.url?input.url:'');"
        + "    if(u&&(u.indexOf('https://')===0||u.indexOf('http://')===0)&&u.indexOf('"
        + EXT_VIRTUAL_HOST
        + "')===-1&&(!init||!init.method||init.method.toUpperCase()==='GET')){"
        + "      return origFetch.call(window,input,init).catch(function(){"
        + "        return origFetch.call(window,'https://"
        + EXT_VIRTUAL_HOST
        + "/"
        + extId
        + EXT_FETCH_PATH
        + "?u='+encodeURIComponent(u));"
        + "      });"
        + "    }"
        + "    return origFetch.apply(this,arguments);"
        + "  };"
        + "}"
        + "})();";
  }

  /**
   * Builds a complete, isolated Chrome MV2/MV3 API runtime object for a specific extension ID so
   * multiple extensions can coexist on the same page (including www.google.com) without colliding.
   */
  private String buildExtensionChromeFactoryJs(
      String extId, File extDir, String activeTabUrl, String activeTabTitle) {
    JSONObject storageSnap;
    synchronized (lock) {
      storageSnap = readExtensionStorageLocked(extDir);
    }
    String manifestRaw = safeReadAssetUtf8(extDir, "manifest.json");
    if (manifestRaw.isEmpty()) {
      manifestRaw = "{}";
    }
    String messagesRaw = loadLocaleMessagesRawJson(extDir);

    String safeTabUrl =
        (activeTabUrl != null && !activeTabUrl.isEmpty()) ? activeTabUrl : "https://www.google.com";
    String safeTabTitle =
        (activeTabTitle != null && !activeTabTitle.isEmpty()) ? activeTabTitle : "Active Tab";

    return "(function(){"
        + "window.__hbExtRuntimes=window.__hbExtRuntimes||{};"
        + "if(window.__hbExtRuntimes['"
        + extId
        + "'])return window.__hbExtRuntimes['"
        + extId
        + "'];"
        + "var EXT_ID="
        + JSONObject.quote(extId)
        + ";"
        + "var BASE='https://"
        + EXT_VIRTUAL_HOST
        + "/'+EXT_ID+'/';"
        + "var store={};try{store="
        + storageSnap.toString()
        + ";}catch(e){store={};}"
        + "var manifest={};try{manifest="
        + manifestRaw
        + ";}catch(e){manifest={};}"
        + "var i18nMap={};try{i18nMap="
        + messagesRaw
        + ";}catch(e){i18nMap={};}"
        + "function postNative(op,payload){"
        + "  try{"
        + "    if(window.HeavenChromeExtChannel&&window.HeavenChromeExtChannel.postMessage){"
        + "      window.HeavenChromeExtChannel.postMessage(JSON.stringify({extId:EXT_ID,op:op,data:payload}));"
        + "    }"
        + "  }catch(e){}"
        + "}"
        + "function mkEvt(){"
        + "  var ls=[];"
        + "  return {"
        + "    _listeners:ls,"
        + "    addListener:function(fn){if(typeof fn==='function'&&ls.indexOf(fn)===-1)ls.push(fn);},"
        + "    removeListener:function(fn){var i=ls.indexOf(fn);if(i>=0)ls.splice(i,1);},"
        + "    hasListener:function(fn){return ls.indexOf(fn)>=0;},"
        + "    hasListeners:function(){return ls.length>0;},"
        + "    _emit:function(){var a=arguments;for(var i=0;i<ls.length;i++){try{ls[i].apply(null,a);}catch(e){}}}"
        + "  };"
        + "}"
        + "var onStorageChanged=mkEvt();"
        + "var onRuntimeMsg=mkEvt();"
        + "var onRuntimeConnect=mkEvt();"
        + "var onInstalledEvt=mkEvt();"
        + "var onStartupEvt=mkEvt();"
        + "var onActionClicked=mkEvt();"
        + "function mkArea(areaName){"
        + "  return {"
        + "    QUOTA_BYTES:10485760,"
        + "    get:function(keys,cb){"
        + "      var res={};"
        + "      if(keys===null||keys===undefined){Object.assign(res,store);}"
        + "      else if(typeof keys==='string'){if(keys in store)res[keys]=store[keys];}"
        + "      else if(Array.isArray(keys)){for(var i=0;i<keys.length;i++){var k=keys[i];if(k in store)res[k]=store[k];}}"
        + "      else if(typeof keys==='object'){for(var k in keys){res[k]=(k in store)?store[k]:keys[k];}}"
        + "      if(typeof cb==='function')setTimeout(function(){cb(res);},0);"
        + "      return Promise.resolve(res);"
        + "    },"
        + "    set:function(items,cb){"
        + "      var changes={};"
        + "      if(items&&typeof items==='object'){"
        + "        for(var k in items){changes[k]={oldValue:store[k],newValue:items[k]};store[k]=items[k];}"
        + "        postNative('storage_patch',{op:'set',items:items});"
        + "        onStorageChanged._emit(changes,areaName);"
        + "      }"
        + "      if(typeof cb==='function')setTimeout(cb,0);"
        + "      return Promise.resolve();"
        + "    },"
        + "    remove:function(keys,cb){"
        + "      var arr=Array.isArray(keys)?keys:[String(keys)];"
        + "      var changes={};"
        + "      for(var i=0;i<arr.length;i++){var k=arr[i];if(k in store){changes[k]={oldValue:store[k]};delete store[k];}}"
        + "      postNative('storage_patch',{op:'remove',keys:arr});"
        + "      onStorageChanged._emit(changes,areaName);"
        + "      if(typeof cb==='function')setTimeout(cb,0);"
        + "      return Promise.resolve();"
        + "    },"
        + "    clear:function(cb){"
        + "      store={};"
        + "      postNative('storage_patch',{op:'clear'});"
        + "      if(typeof cb==='function')setTimeout(cb,0);"
        + "      return Promise.resolve();"
        + "    },"
        + "    getBytesInUse:function(k,cb){if(typeof cb==='function')setTimeout(function(){cb(0);},0);return Promise.resolve(0);},"
        + "    onChanged:onStorageChanged"
        + "  };"
        + "}"
        + "var activeTabObj={id:1,index:0,windowId:1,active:true,highlighted:true,pinned:false,"
        + "url:(location.hostname==='"
        + EXT_VIRTUAL_HOST
        + "'?"
        + JSONObject.quote(safeTabUrl)
        + ":location.href),"
        + "title:(location.hostname==='"
        + EXT_VIRTUAL_HOST
        + "'?"
        + JSONObject.quote(safeTabTitle)
        + ":(document.title||'Tab')),status:'complete'};"
        + "var pendingRuntimeReq={};var reqSeq=1;"
        + "window.__hbExtRuntimeReply=window.__hbExtRuntimeReply||function(eid,rid,jsonStr){"
        + "  var rt=window.__hbExtRuntimes&&window.__hbExtRuntimes[eid];"
        + "  if(rt&&rt.__resolveReq)rt.__resolveReq(rid,jsonStr);"
        + "};"
        + "window.__hbExtDeliverMessage=window.__hbExtDeliverMessage||function(eid,msg){"
        + "  var rt=window.__hbExtRuntimes&&window.__hbExtRuntimes[eid];"
        + "  if(rt&&rt.runtime&&rt.runtime.onMessage)rt.runtime.onMessage._emit(msg,{id:eid},function(){});"
        + "};"
        + "window.__hbExtSyncStorage=window.__hbExtSyncStorage||function(eid,changes){"
        + "  var rt=window.__hbExtRuntimes&&window.__hbExtRuntimes[eid];"
        + "  if(rt&&rt.__applyStorageDiff)rt.__applyStorageDiff(changes);"
        + "};"
        + "var actionApi={"
        + "  setBadgeText:function(d,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "  getBadgeText:function(d,cb){if(typeof cb==='function')cb('');return Promise.resolve('');},"
        + "  setBadgeBackgroundColor:function(d,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "  setIcon:function(d,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "  setTitle:function(d,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "  setPopup:function(d,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "  enable:function(id,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "  disable:function(id,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "  onClicked:onActionClicked"
        + "};"
        + "var chromeObj={"
        + "  __resolveReq:function(rid,raw){"
        + "    var fn=pendingRuntimeReq[rid];delete pendingRuntimeReq[rid];"
        + "    if(fn){var v={};try{v=JSON.parse(raw||'{}');}catch(e){}fn(v);}"
        + "  },"
        + "  __applyStorageDiff:function(changes){"
        + "    if(!changes)return;"
        + "    for(var k in changes){if('newValue' in changes[k])store[k]=changes[k].newValue;else delete store[k];}"
        + "    onStorageChanged._emit(changes,'local');"
        + "  },"
        + "  runtime:{"
        + "    id:EXT_ID,"
        + "    lastError:null,"
        + "    getManifest:function(){return manifest;},"
        + "    getURL:function(p){var clean=String(p||'').replace(/^\\/+/,'');return BASE+clean;},"
        + "    getPlatformInfo:function(cb){var info={os:'android',arch:'arm64',nacl_arch:'arm'};if(typeof cb==='function')setTimeout(function(){cb(info);},0);return Promise.resolve(info);},"
        + "    sendMessage:function(){"
        + "      var a=Array.prototype.slice.call(arguments);"
        + "      var cb=typeof a[a.length-1]==='function'?a.pop():null;"
        + "      var msg=a.length>1?a[1]:a[0];"
        + "      return new Promise(function(resolve){"
        + "        var settled=false;"
        + "        function finish(val){if(settled)return;settled=true;if(cb)try{cb(val);}catch(e){}resolve(val);}"
        + "        if(onRuntimeMsg.hasListeners()){"
        + "          onRuntimeMsg._emit(msg,{id:EXT_ID,tab:activeTabObj},finish);"
        + "        }"
        + "        var rid='r_'+(reqSeq++)+'_'+Date.now();"
        + "        pendingRuntimeReq[rid]=finish;"
        + "        var mStr='{}';try{mStr=JSON.stringify(msg===undefined?{}:msg);}catch(e){}"
        + "        postNative('runtime_send_message',{reqId:rid,messageJson:mStr,senderUrl:location.href});"
        + "        setTimeout(function(){delete pendingRuntimeReq[rid];finish({});},1800);"
        + "      });"
        + "    },"
        + "    connect:function(extOrInfo, maybeInfo){"
        + "      var info=(typeof extOrInfo==='object'&&extOrInfo)?extOrInfo:(maybeInfo||{});"
        + "      var portMsg=mkEvt();var portDisc=mkEvt();"
        + "      var port={name:(info&&info.name)||'',sender:{id:EXT_ID,tab:activeTabObj},onMessage:portMsg,onDisconnect:portDisc,"
        + "        postMessage:function(m){"
        + "          chromeObj.runtime.sendMessage(m).then(function(r){if(r&&Object.keys(r).length>0)portMsg._emit(r,port);});"
        + "        },"
        + "        disconnect:function(){portDisc._emit(port);}"
        + "      };"
        + "      setTimeout(function(){onRuntimeConnect._emit(port);},0);"
        + "      return port;"
        + "    },"
        + "    openOptionsPage:function(cb){"
        + "      var op=(manifest.options_ui&&manifest.options_ui.page)||manifest.options_page||'';"
        + "      if(op)postNative('tabs_create',{url:BASE+String(op).replace(/^\\/+/,'')});"
        + "      if(typeof cb==='function')cb();return Promise.resolve();"
        + "    },"
        + "    setUninstallURL:function(u,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "    onMessage:onRuntimeMsg,"
        + "    onConnect:onRuntimeConnect,"
        + "    onInstalled:onInstalledEvt,"
        + "    onStartup:onStartupEvt"
        + "  },"
        + "  extension:{getURL:function(p){var clean=String(p||'').replace(/^\\/+/,'');return BASE+clean;},inIncognitoContext:false},"
        + "  storage:{local:mkArea('local'),sync:mkArea('sync'),session:mkArea('session'),managed:mkArea('managed'),onChanged:onStorageChanged},"
        + "  i18n:{"
        + "    getUILanguage:function(){return navigator.language||'en';},"
        + "    getMessage:function(k,subs){"
        + "      var item=i18nMap[k];"
        + "      if(!item){var lk=String(k||'').toLowerCase();for(var mk in i18nMap){if(mk.toLowerCase()===lk){item=i18nMap[mk];break;}}}"
        + "      if(!item||!item.message)return '';"
        + "      var out=String(item.message);"
        + "      if(subs){var arr=Array.isArray(subs)?subs:[subs];for(var i=0;i<arr.length;i++){out=out.split('$'+(i+1)).join(String(arr[i]));}}"
        + "      return out;"
        + "    }"
        + "  },"
        + "  tabs:{"
        + "    query:function(q,cb){var list=[activeTabObj];if(typeof cb==='function')setTimeout(function(){cb(list);},0);return Promise.resolve(list);},"
        + "    getCurrent:function(cb){if(typeof cb==='function')setTimeout(function(){cb(activeTabObj);},0);return Promise.resolve(activeTabObj);},"
        + "    get:function(id,cb){if(typeof cb==='function')setTimeout(function(){cb(activeTabObj);},0);return Promise.resolve(activeTabObj);},"
        + "    create:function(props,cb){if(props&&props.url)postNative('tabs_create',{url:props.url});if(typeof cb==='function')setTimeout(function(){cb(activeTabObj);},0);return Promise.resolve(activeTabObj);},"
        + "    update:function(id,props,cb){var p=(typeof id==='object')?id:props;if(p&&p.url)postNative('tabs_update',{url:p.url});var fn=typeof cb==='function'?cb:(typeof props==='function'?props:null);if(fn)setTimeout(function(){fn(activeTabObj);},0);return Promise.resolve(activeTabObj);},"
        + "    reload:function(id,props,cb){postNative('tabs_reload',{});var fn=typeof cb==='function'?cb:(typeof props==='function'?props:(typeof id==='function'?id:null));if(fn)setTimeout(fn,0);return Promise.resolve();},"
        + "    sendMessage:function(tabId,msg,opts,cb){"
        + "      var fn=typeof cb==='function'?cb:(typeof opts==='function'?opts:null);"
        + "      var mStr='{}';try{mStr=JSON.stringify(msg===undefined?{}:msg);}catch(e){}"
        + "      postNative('tabs_send_message',{tabId:tabId,messageJson:mStr});"
        + "      if(fn)setTimeout(function(){fn({});},20);"
        + "      return Promise.resolve({});"
        + "    },"
        + "    executeScript:function(tabId,details,cb){"
        + "      var det=(typeof tabId==='object')?tabId:details;"
        + "      var fn=typeof cb==='function'?cb:(typeof details==='function'?details:null);"
        + "      if(det)postNative('scripting_exec',{files:det.file?[det.file]:[],code:det.code||''});"
        + "      if(fn)setTimeout(function(){fn([null]);},20);"
        + "      return Promise.resolve([null]);"
        + "    },"
        + "    insertCSS:function(tabId,details,cb){"
        + "      var det=(typeof tabId==='object')?tabId:details;"
        + "      if(det)postNative('scripting_insert_css',{css:det.code||'',files:det.file?[det.file]:[]});"
        + "      var fn=typeof cb==='function'?cb:(typeof details==='function'?details:null);"
        + "      if(fn)setTimeout(fn,10);"
        + "      return Promise.resolve();"
        + "    },"
        + "    onUpdated:mkEvt(),onActivated:mkEvt(),onRemoved:mkEvt(),onCreated:mkEvt()"
        + "  },"
        + "  windows:{WINDOW_ID_CURRENT:-2,getCurrent:function(o,cb){var w={id:1,focused:true,type:'normal',state:'maximized',tabs:[activeTabObj]};var fn=typeof o==='function'?o:cb;if(fn)setTimeout(function(){fn(w);},0);return Promise.resolve(w);},getAll:function(o,cb){var ws=[{id:1,focused:true,tabs:[activeTabObj]}];var fn=typeof o==='function'?o:cb;if(fn)setTimeout(function(){fn(ws);},0);return Promise.resolve(ws);},onFocusChanged:mkEvt()},"
        + "  scripting:{"
        + "    executeScript:function(inj,cb){"
        + "      var payload={files:(inj&&inj.files)||[],funcSource:(inj&&typeof inj.func==='function')?inj.func.toString():'',argsJson:JSON.stringify((inj&&inj.args)||[])};"
        + "      postNative('scripting_exec',payload);"
        + "      var r=[{frameId:0,result:null}];if(typeof cb==='function')setTimeout(function(){cb(r);},20);return Promise.resolve(r);"
        + "    },"
        + "    insertCSS:function(inj,cb){if(inj)postNative('scripting_insert_css',{css:inj.css||'',files:inj.files||[]});if(typeof cb==='function')setTimeout(cb,10);return Promise.resolve();},"
        + "    removeCSS:function(inj,cb){if(typeof cb==='function')setTimeout(cb,10);return Promise.resolve();},"
        + "    registerContentScripts:function(s,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "    getRegisteredContentScripts:function(f,cb){var fn=typeof f==='function'?f:cb;if(fn)fn([]);return Promise.resolve([]);}"
        + "  },"
        + "  declarativeNetRequest:{"
        + "    updateDynamicRules:function(o,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "    getDynamicRules:function(cb){if(typeof cb==='function')cb([]);return Promise.resolve([]);},"
        + "    updateSessionRules:function(o,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "    getSessionRules:function(cb){if(typeof cb==='function')cb([]);return Promise.resolve([]);},"
        + "    updateEnabledRulesets:function(o,cb){if(typeof cb==='function')cb();return Promise.resolve();},"
        + "    getEnabledRulesets:function(cb){if(typeof cb==='function')cb([]);return Promise.resolve([]);}"
        + "  },"
        + "  action:actionApi,"
        + "  browserAction:actionApi,"
        + "  pageAction:actionApi,"
        + "  commands:{getAll:function(cb){if(typeof cb==='function')cb([]);return Promise.resolve([]);},onCommand:mkEvt()},"
        + "  alarms:{create:function(){},clear:function(n,cb){if(typeof cb==='function')cb(true);return Promise.resolve(true);},clearAll:function(cb){if(typeof cb==='function')cb(true);return Promise.resolve(true);},get:function(n,cb){if(typeof cb==='function')cb(null);return Promise.resolve(null);},getAll:function(cb){if(typeof cb==='function')cb([]);return Promise.resolve([]);},onAlarm:mkEvt()},"
        + "  permissions:{contains:function(p,cb){if(typeof cb==='function')setTimeout(function(){cb(true);},0);return Promise.resolve(true);},request:function(p,cb){if(typeof cb==='function')setTimeout(function(){cb(true);},0);return Promise.resolve(true);},getAll:function(cb){var r={permissions:manifest.permissions||[],origins:manifest.host_permissions||[]};if(typeof cb==='function')cb(r);return Promise.resolve(r);},onAdded:mkEvt(),onRemoved:mkEvt()},"
        + "  contextMenus:{create:function(){return 1;},update:function(){},remove:function(){},removeAll:function(cb){if(typeof cb==='function')cb();},onClicked:mkEvt()},"
        + "  notifications:{create:function(id,opt,cb){var fn=typeof opt==='function'?opt:cb;if(fn)fn(String(id||'n1'));return Promise.resolve('n1');},clear:function(id,cb){if(typeof cb==='function')cb(true);return Promise.resolve(true);},onClicked:mkEvt()},"
        + "  webNavigation:{onCommitted:mkEvt(),onCompleted:mkEvt(),onDOMContentLoaded:mkEvt(),onHistoryStateUpdated:mkEvt()}"
        + "};"
        + "if(!window.chrome)window.chrome=chromeObj;"
        + "else{for(var ck in chromeObj){if(!(ck in window.chrome))try{window.chrome[ck]=chromeObj[ck];}catch(e){}}}"
        + "if(!window.browser)window.browser=chromeObj;"
        + "window.__hbExtRuntimes[EXT_ID]=chromeObj;"
        + "return chromeObj;"
        + "})()";
  }

  private static boolean matchesAnyPattern(String url, JSONArray patterns) {
    if (patterns == null || patterns.length() == 0) {
      return false;
    }
    for (int i = 0; i < patterns.length(); i++) {
      String pat = patterns.optString(i, "");
      if (matchesChromePattern(url, pat)) {
        return true;
      }
    }
    return false;
  }

  public static boolean matchesChromePattern(String rawUrl, String rawPattern) {
    if (rawUrl == null || rawPattern == null) {
      return false;
    }
    String p = rawPattern.trim();
    if ("<all_urls>".equals(p) || "*://*/*".equals(p) || "http://*/*".equals(p) || "https://*/*".equals(p)) {
      return rawUrl.startsWith("http://") || rawUrl.startsWith("https://");
    }
    try {
      Uri u = Uri.parse(rawUrl);
      String scheme = u.getScheme() != null ? u.getScheme().toLowerCase(Locale.US) : "";
      String host = u.getHost() != null ? u.getHost().toLowerCase(Locale.US) : "";
      String pathAndQuery =
          (u.getEncodedPath() != null && !u.getEncodedPath().isEmpty() ? u.getEncodedPath() : "/")
              + (u.getEncodedQuery() != null ? "?" + u.getEncodedQuery() : "");

      int schemeSep = p.indexOf("://");
      if (schemeSep < 0) {
        return false;
      }
      String patScheme = p.substring(0, schemeSep).toLowerCase(Locale.US);
      if ("*".equals(patScheme)) {
        if (!"http".equals(scheme) && !"https".equals(scheme)) {
          return false;
        }
      } else if (!patScheme.equals(scheme)) {
        return false;
      }

      String rest = p.substring(schemeSep + 3);
      int slashIdx = rest.indexOf('/');
      String patHost = (slashIdx >= 0 ? rest.substring(0, slashIdx) : rest).toLowerCase(Locale.US);
      String patPath = slashIdx >= 0 ? rest.substring(slashIdx) : "/*";

      if (!"*".equals(patHost)) {
        if (patHost.startsWith("*.")) {
          String root = patHost.substring(2);
          if (!host.equals(root) && !host.endsWith("." + root)) {
            return false;
          }
        } else if (!host.equals(patHost)) {
          return false;
        }
      }

      if ("/*".equals(patPath) || "*".equals(patPath)) {
        return true;
      }
      StringBuilder regex = new StringBuilder("^");
      for (int i = 0; i < patPath.length(); i++) {
        char ch = patPath.charAt(i);
        if (ch == '*') {
          regex.append(".*");
        } else if ("\\.[]{}()+?^$|".indexOf(ch) >= 0) {
          regex.append('\\').append(ch);
        } else {
          regex.append(ch);
        }
      }
      regex.append("$");
      return Pattern.compile(regex.toString()).matcher(pathAndQuery).matches();
    } catch (Throwable ignored) {
      return false;
    }
  }

  /**
   * Unpacks CRX2, CRX3, or standard ZIP extension archives safely (blocking Zip-Slip), parses
   * manifest.json (MV2 & MV3), resolves _locales/__MSG_...__ names, extracts background workers,
   * options_ui, and declarativeNetRequest rulesets, and registers the extension.
   */
  public Map<String, Object> unpackAndRegisterPackage(
      String rawExtId, byte[] packageBytes, String source) throws Exception {
    int zipOffset = findZipPayloadOffset(packageBytes);
    if (zipOffset < 0 || zipOffset >= packageBytes.length - 16) {
      throw new IOException("No valid ZIP payload inside CRX/ZIP archive");
    }

    String extId = sanitizeId(rawExtId);
    File extDir = new File(rootDir, extId);
    JSONObject preservedStorage = null;
    synchronized (lock) {
      if (extDir.exists()) {
        preservedStorage = readExtensionStorageLocked(extDir);
        deleteRecursively(extDir);
      }
      if (!extDir.mkdirs() && !extDir.isDirectory()) {
        throw new IOException("Unable to create extension directory");
      }
    }

    String canonicalRoot = extDir.getCanonicalPath() + File.separator;
    try (ZipInputStream zis =
        new ZipInputStream(
            new ByteArrayInputStream(packageBytes, zipOffset, packageBytes.length - zipOffset))) {
      ZipEntry entry;
      byte[] buf = new byte[16384];
      while ((entry = zis.getNextEntry()) != null) {
        String name = entry.getName();
        if (name == null || name.isEmpty() || name.startsWith("__MACOSX/")) {
          continue;
        }
        File outFile = new File(extDir, name);
        String canonicalOut = outFile.getCanonicalPath();
        if (!canonicalOut.startsWith(canonicalRoot)) {
          continue;
        }
        if (entry.isDirectory()) {
          //noinspection ResultOfMethodCallIgnored
          outFile.mkdirs();
        } else {
          File parent = outFile.getParentFile();
          if (parent != null && !parent.exists()) {
            //noinspection ResultOfMethodCallIgnored
            parent.mkdirs();
          }
          try (FileOutputStream fos = new FileOutputStream(outFile)) {
            int n;
            while ((n = zis.read(buf)) > 0) {
              fos.write(buf, 0, n);
            }
          }
        }
        zis.closeEntry();
      }
    }

    File manifestFile = new File(extDir, "manifest.json");
    if (!manifestFile.isFile()) {
      File[] children = extDir.listFiles();
      if (children != null && children.length == 1 && children[0].isDirectory()) {
        File nestedManifest = new File(children[0], "manifest.json");
        if (nestedManifest.isFile()) {
          moveDirectoryChildrenUp(children[0], extDir);
          deleteRecursively(children[0]);
        }
      }
    }
    if (!manifestFile.isFile()) {
      deleteRecursively(extDir);
      throw new IOException("manifest.json missing in extension archive");
    }

    JSONObject manifest = new JSONObject(readUtf8File(manifestFile));
    JSONObject localeMessages = new JSONObject(loadLocaleMessagesRawJson(extDir));

    String name = resolveI18nPlaceholder(manifest.optString("name", "Chrome Extension"), localeMessages);
    String desc = resolveI18nPlaceholder(manifest.optString("description", ""), localeMessages);
    String version = manifest.optString("version", "1.0.0");
    int manifestVersion = manifest.optInt("manifest_version", 3);

    String popupPath = extractPopupPath(manifest);
    while (popupPath.startsWith("/")) {
      popupPath = popupPath.substring(1);
    }
    String popupUrl =
        !popupPath.isEmpty()
            ? ("https://" + EXT_VIRTUAL_HOST + "/" + extId + "/" + popupPath)
            : "";

    String optionsPath = extractOptionsPath(manifest);
    while (optionsPath.startsWith("/")) {
      optionsPath = optionsPath.substring(1);
    }
    String optionsUrl =
        !optionsPath.isEmpty()
            ? ("https://" + EXT_VIRTUAL_HOST + "/" + extId + "/" + optionsPath)
            : "";

    String iconRel = extractBestIconPath(manifest);
    String iconBase64 = "";
    if (!iconRel.isEmpty()) {
      while (iconRel.startsWith("/")) {
        iconRel = iconRel.substring(1);
      }
      File iconFile = new File(extDir, iconRel);
      if (iconFile.isFile() && iconFile.length() <= 512 * 1024) {
        byte[] iconBytes = readFileBytes(iconFile);
        iconBase64 = Base64.encodeToString(iconBytes, Base64.NO_WRAP);
      }
    }

    JSONObject bgObj = manifest.optJSONObject("background");
    String bgWorker = "";
    boolean bgIsModule = false;
    String bgPage = "";
    JSONArray bgScripts = new JSONArray();
    if (bgObj != null) {
      bgWorker = normalizeSingleRelPath(bgObj.optString("service_worker", ""));
      bgIsModule = "module".equalsIgnoreCase(bgObj.optString("type", ""));
      bgPage = normalizeSingleRelPath(bgObj.optString("page", ""));
      bgScripts = normalizeRelArray(bgObj.optJSONArray("scripts"));
    }

    JSONArray dnrRulePaths = extractDnrRulePaths(manifest);
    JSONArray parsedContentScripts = extractContentScriptsArray(manifest);
    JSONArray permissions = extractPermissionsList(manifest);

    JSONObject record = new JSONObject();
    record.put("id", extId);
    record.put("name", name);
    record.put("description", desc);
    record.put("version", version);
    record.put("manifestVersion", manifestVersion);
    record.put("enabled", true);
    record.put("source", source);
    record.put("popupPath", popupPath);
    record.put("popupUrl", popupUrl);
    record.put("optionsPath", optionsPath);
    record.put("optionsUrl", optionsUrl);
    record.put("bgWorker", bgWorker);
    record.put("bgIsModule", bgIsModule);
    record.put("bgPage", bgPage);
    record.put("bgScripts", bgScripts);
    record.put("dnrRulePaths", dnrRulePaths);
    record.put("iconBase64", iconBase64);
    record.put("contentScripts", parsedContentScripts);
    record.put("permissions", permissions);
    record.put("installedAtMs", System.currentTimeMillis());

    synchronized (lock) {
      if (preservedStorage != null && preservedStorage.length() > 0) {
        File sf = new File(extDir, STORAGE_FILE);
        try (FileOutputStream fos = new FileOutputStream(sf, false)) {
          fos.write(preservedStorage.toString().getBytes(StandardCharsets.UTF_8));
        }
      }
      JSONArray next = new JSONArray();
      boolean replaced = false;
      for (int i = 0; i < registryArray.length(); i++) {
        JSONObject existing = registryArray.optJSONObject(i);
        if (existing != null && extId.equals(existing.optString("id"))) {
          next.put(record);
          replaced = true;
        } else if (existing != null) {
          next.put(existing);
        }
      }
      if (!replaced) {
        next.put(record);
      }
      registryArray = next;
      saveRegistryLocked();
    }

    Map<String, Object> response = extensionJsonToSummaryMap(record);
    response.put("ok", true);
    return response;
  }

  public static int findZipPayloadOffset(byte[] data) {
    if (data == null || data.length < 16) {
      return -1;
    }
    if (data[0] == 'P' && data[1] == 'K' && data[2] == 3 && data[3] == 4) {
      return 0;
    }
    if (data[0] == 'C' && data[1] == 'r' && data[2] == '2' && data[3] == '4') {
      ByteBuffer bb = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);
      int version = bb.getInt(4);
      if (version == 2 && data.length >= 16) {
        int pubKeyLen = bb.getInt(8);
        int sigLen = bb.getInt(12);
        int offset = 16 + pubKeyLen + sigLen;
        if (offset >= 16 && offset < data.length - 4) {
          return offset;
        }
      } else if (version == 3 && data.length >= 12) {
        int headerLen = bb.getInt(8);
        int offset = 12 + headerLen;
        if (offset >= 12 && offset < data.length - 4) {
          return offset;
        }
      }
    }
    for (int i = 0; i < Math.min(data.length - 4, 65536); i++) {
      if (data[i] == 'P' && data[i + 1] == 'K' && data[i + 2] == 3 && data[i + 3] == 4) {
        return i;
      }
    }
    return -1;
  }

  private static String extractPopupPath(JSONObject manifest) {
    String[] keys = new String[] {"action", "browser_action", "page_action"};
    for (String k : keys) {
      JSONObject obj = manifest.optJSONObject(k);
      if (obj != null) {
        String p = obj.optString("default_popup", "").trim();
        if (!p.isEmpty()) {
          return p;
        }
      }
    }
    return "";
  }

  private static String extractOptionsPath(JSONObject manifest) {
    JSONObject optUi = manifest.optJSONObject("options_ui");
    if (optUi != null) {
      String p = optUi.optString("page", "").trim();
      if (!p.isEmpty()) {
        return p;
      }
    }
    return manifest.optString("options_page", "").trim();
  }

  private static JSONArray extractDnrRulePaths(JSONObject manifest) {
    JSONArray out = new JSONArray();
    JSONObject dnr = manifest.optJSONObject("declarative_net_request");
    if (dnr == null) {
      return out;
    }
    JSONArray res = dnr.optJSONArray("rule_resources");
    if (res == null) {
      return out;
    }
    for (int i = 0; i < res.length(); i++) {
      JSONObject item = res.optJSONObject(i);
      if (item != null && item.optBoolean("enabled", true)) {
        String path = normalizeSingleRelPath(item.optString("path", ""));
        if (!path.isEmpty()) {
          out.put(path);
        }
      }
    }
    return out;
  }

  private static String normalizeSingleRelPath(String raw) {
    String p = raw != null ? raw.trim() : "";
    while (p.startsWith("/") || p.startsWith("./")) {
      p = p.startsWith("./") ? p.substring(2) : p.substring(1);
    }
    return p;
  }

  private static String extractBestIconPath(JSONObject manifest) {
    JSONObject icons = manifest.optJSONObject("icons");
    if (icons != null) {
      String[] preferred = new String[] {"128", "64", "48", "32", "16"};
      for (String sz : preferred) {
        String p = icons.optString(sz, "").trim();
        if (!p.isEmpty()) {
          return p;
        }
      }
      Iterator<String> it = icons.keys();
      if (it.hasNext()) {
        return icons.optString(it.next(), "").trim();
      }
    }
    String[] actionKeys = new String[] {"action", "browser_action"};
    for (String ak : actionKeys) {
      JSONObject act = manifest.optJSONObject(ak);
      if (act != null) {
        Object defIcon = act.opt("default_icon");
        if (defIcon instanceof String) {
          return ((String) defIcon).trim();
        } else if (defIcon instanceof JSONObject) {
          JSONObject dio = (JSONObject) defIcon;
          Iterator<String> it = dio.keys();
          if (it.hasNext()) {
            return dio.optString(it.next(), "").trim();
          }
        }
      }
    }
    return "";
  }

  private static JSONArray extractContentScriptsArray(JSONObject manifest) {
    JSONArray out = new JSONArray();
    JSONArray rawArr = manifest.optJSONArray("content_scripts");
    if (rawArr == null) {
      return out;
    }
    for (int i = 0; i < rawArr.length(); i++) {
      JSONObject raw = rawArr.optJSONObject(i);
      if (raw == null) {
        continue;
      }
      try {
        JSONObject item = new JSONObject();
        item.put(
            "matches",
            raw.optJSONArray("matches") != null ? raw.optJSONArray("matches") : new JSONArray());
        item.put(
            "excludeMatches",
            raw.optJSONArray("exclude_matches") != null
                ? raw.optJSONArray("exclude_matches")
                : new JSONArray());
        item.put("js", normalizeRelArray(raw.optJSONArray("js")));
        item.put("css", normalizeRelArray(raw.optJSONArray("css")));
        item.put("runAt", raw.optString("run_at", "document_idle"));
        out.put(item);
      } catch (Throwable ignored) {
      }
    }
    return out;
  }

  private static JSONArray normalizeRelArray(JSONArray arr) {
    JSONArray out = new JSONArray();
    if (arr == null) {
      return out;
    }
    for (int i = 0; i < arr.length(); i++) {
      String p = normalizeSingleRelPath(arr.optString(i, ""));
      if (!p.isEmpty()) {
        out.put(p);
      }
    }
    return out;
  }

  private static JSONArray extractPermissionsList(JSONObject manifest) {
    JSONArray out = new JSONArray();
    JSONArray perms = manifest.optJSONArray("permissions");
    if (perms != null) {
      for (int i = 0; i < perms.length(); i++) {
        String s = perms.optString(i, "").trim();
        if (!s.isEmpty()) {
          out.put(s);
        }
      }
    }
    JSONArray hostPerms = manifest.optJSONArray("host_permissions");
    if (hostPerms != null) {
      for (int i = 0; i < hostPerms.length(); i++) {
        String s = hostPerms.optString(i, "").trim();
        if (!s.isEmpty()) {
          out.put(s);
        }
      }
    }
    return out;
  }

  private static String loadLocaleMessagesRawJson(File extDir) {
    String defaultLocale = "en";
    File mf = new File(extDir, "manifest.json");
    if (mf.isFile()) {
      try {
        JSONObject m = new JSONObject(readUtf8File(mf));
        defaultLocale = m.optString("default_locale", "en");
      } catch (Throwable ignored) {
      }
    }
    String[] candidates = new String[] {defaultLocale, "en", "en_US", "en_GB"};
    for (String loc : candidates) {
      if (loc == null || loc.isEmpty()) {
        continue;
      }
      File f = new File(extDir, "_locales/" + loc + "/messages.json");
      if (f.isFile()) {
        try {
          return readUtf8File(f);
        } catch (Throwable ignored) {
        }
      }
    }
    return "{}";
  }

  private static String resolveI18nPlaceholder(String text, JSONObject messages) {
    if (text == null || !text.startsWith("__MSG_") || !text.endsWith("__")) {
      return text != null ? text : "";
    }
    String key = text.substring(6, text.length() - 2);
    JSONObject entry = messages.optJSONObject(key);
    if (entry == null) {
      Iterator<String> it = messages.keys();
      while (it.hasNext()) {
        String k = it.next();
        if (k.equalsIgnoreCase(key)) {
          entry = messages.optJSONObject(k);
          break;
        }
      }
    }
    if (entry != null) {
      String msg = entry.optString("message", "");
      if (!msg.isEmpty()) {
        return msg;
      }
    }
    return key;
  }

  private static Map<String, Object> extensionJsonToSummaryMap(JSONObject obj) {
    Map<String, Object> m = new HashMap<>();
    m.put("id", obj.optString("id", ""));
    m.put("name", obj.optString("name", "Chrome Extension"));
    m.put("description", obj.optString("description", ""));
    m.put("version", obj.optString("version", "1.0"));
    m.put("manifestVersion", obj.optInt("manifestVersion", 3));
    m.put("enabled", obj.optBoolean("enabled", true));
    m.put("source", obj.optString("source", "webstore"));
    m.put("popupPath", obj.optString("popupPath", ""));
    m.put("popupUrl", obj.optString("popupUrl", ""));
    m.put("optionsPath", obj.optString("optionsPath", ""));
    m.put("optionsUrl", obj.optString("optionsUrl", ""));
    m.put("hasBackground", hasBackgroundConfig(obj));
    m.put("iconBase64", obj.optString("iconBase64", ""));

    List<String> perms = new ArrayList<>();
    JSONArray pArr = obj.optJSONArray("permissions");
    if (pArr != null) {
      for (int i = 0; i < pArr.length(); i++) {
        perms.add(pArr.optString(i, ""));
      }
    }
    m.put("permissions", perms);

    List<String> matches = new ArrayList<>();
    JSONArray csArr = obj.optJSONArray("contentScripts");
    if (csArr != null) {
      for (int i = 0; i < csArr.length(); i++) {
        JSONObject cs = csArr.optJSONObject(i);
        if (cs != null) {
          JSONArray ma = cs.optJSONArray("matches");
          if (ma != null) {
            for (int j = 0; j < ma.length(); j++) {
              String pat = ma.optString(j, "");
              if (!pat.isEmpty() && !matches.contains(pat)) {
                matches.add(pat);
              }
            }
          }
        }
      }
    }
    m.put("matches", matches);
    m.put("contentScriptCount", csArr != null ? csArr.length() : 0);
    JSONArray dnrArr = obj.optJSONArray("dnrRulePaths");
    m.put("dnrRulesetCount", dnrArr != null ? dnrArr.length() : 0);
    return m;
  }

  private static final String CRX_DESKTOP_UA =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
          + "(KHTML, like Gecko) Chrome/134.0.6998.89 Safari/537.36";
  private static final int MAX_CRX_BYTES = 28 * 1024 * 1024;

  private static String[] buildCrxUpdateEndpoints(String extId) {
    String query =
        "?response=redirect&os=win&arch=x64&os_arch=x86_64&nacl_arch=x86-64"
            + "&prod=chromecrx&prodchannel=stable&prodversion=134.0.6998.89"
            + "&acceptformat=crx2,crx3&x=id%3D"
            + extId
            + "%26installsource%3Dondemand%26uc";
    return new String[] {
      "https://update.googleapis.com/service/update2/crx" + query,
      "https://clients2.google.com/service/update2/crx" + query
    };
  }

  private byte[] downloadExtensionCrxMultiStage(String extId) throws Exception {
    String[] endpoints = buildCrxUpdateEndpoints(extId);
    Throwable lastError = null;

    for (String endpoint : endpoints) {
      try {
        byte[] bytes =
            HeavenNetHelper.downloadBytesFollowingRedirects(
                appContext, endpoint, CRX_DESKTOP_UA, false, 6, MAX_CRX_BYTES);
        if (bytes != null && bytes.length >= 32) {
          return bytes;
        }
      } catch (Throwable t) {
        lastError = t;
      }
    }

    if (HeavenNetHelper.findBestPhysicalNonVpnNetwork(appContext) != null) {
      for (String endpoint : endpoints) {
        try {
          byte[] bytes =
              HeavenNetHelper.downloadBytesFollowingRedirects(
                  appContext, endpoint, CRX_DESKTOP_UA, true, 6, MAX_CRX_BYTES);
          if (bytes != null && bytes.length >= 32) {
            return bytes;
          }
        } catch (Throwable t) {
          lastError = t;
        }
      }
    }

    try {
      byte[] wvBytes = downloadCrxViaChromiumWebView(endpoints[0]);
      if (wvBytes != null && wvBytes.length >= 32) {
        return wvBytes;
      }
    } catch (Throwable t) {
      lastError = t;
    }

    if (lastError instanceof Exception) {
      throw (Exception) lastError;
    }
    throw new IOException(
        lastError != null ? lastError.getMessage() : "Unable to reach Chrome Web Store CDN");
  }

  private static final class CrxWebViewBridge {
    final ByteArrayOutputStream buffer = new ByteArrayOutputStream(65536);
    final AtomicReference<String> errorRef;
    final CountDownLatch latch;

    CrxWebViewBridge(AtomicReference<String> errorRef, CountDownLatch latch) {
      this.errorRef = errorRef;
      this.latch = latch;
    }

    @JavascriptInterface
    public void onChunk(String base64Chunk) {
      if (base64Chunk == null || base64Chunk.isEmpty()) {
        return;
      }
      try {
        byte[] decoded = Base64.decode(base64Chunk, Base64.DEFAULT);
        if (buffer.size() + decoded.length > MAX_CRX_BYTES) {
          errorRef.set("Extension package exceeds 28 MB safety limit");
          latch.countDown();
          return;
        }
        buffer.write(decoded);
      } catch (Throwable t) {
        errorRef.set("Base64 decode error: " + t.getMessage());
        latch.countDown();
      }
    }

    @JavascriptInterface
    public void onDone() {
      latch.countDown();
    }

    @JavascriptInterface
    public void onError(String message) {
      errorRef.set(message != null ? message : "Chromium fetch failed");
      latch.countDown();
    }
  }

  @SuppressLint({"SetJavaScriptEnabled", "JavascriptInterface"})
  private byte[] downloadCrxViaChromiumWebView(final String crxRedirectUrl) throws Exception {
    final CountDownLatch latch = new CountDownLatch(1);
    final AtomicReference<String> errorRef = new AtomicReference<>(null);
    final CrxWebViewBridge bridge = new CrxWebViewBridge(errorRef, latch);
    final AtomicReference<WebView> wvHolder = new AtomicReference<>(null);

    mainHandler.post(
        () -> {
          try {
            final WebView wv = new WebView(appContext);
            wvHolder.set(wv);
            WebSettings s = wv.getSettings();
            s.setJavaScriptEnabled(true);
            s.setDomStorageEnabled(true);
            s.setUserAgentString(CRX_DESKTOP_UA);
            wv.addJavascriptInterface(bridge, "HeavenCrxSink");
            wv.setWebViewClient(
                new WebViewClient() {
                  @Override
                  public void onReceivedError(
                      WebView view, WebResourceRequest request, WebResourceError error) {
                    if (request != null && request.isForMainFrame()) {
                      errorRef.set("Chromium network error loading CRX");
                      latch.countDown();
                    }
                  }
                });
            wv.setDownloadListener(
                (blobUrl, userAgent, contentDisposition, mimetype, contentLength) -> {
                  if (blobUrl == null || blobUrl.isEmpty()) {
                    errorRef.set("Empty CRX redirect URL");
                    latch.countDown();
                    return;
                  }
                  Uri parsed = Uri.parse(blobUrl);
                  String origin =
                      (parsed.getScheme() != null && parsed.getHost() != null)
                          ? (parsed.getScheme() + "://" + parsed.getHost() + "/")
                          : "https://clients2.googleusercontent.com/";
                  String escapedUrl = blobUrl.replace("\\", "\\\\").replace("'", "\\'");
                  String html =
                      "<!doctype html><html><body><script>"
                          + "(async function(){"
                          + "try{"
                          + "var r=await fetch('"
                          + escapedUrl
                          + "',{credentials:'omit'});"
                          + "if(!r.ok){HeavenCrxSink.onError('HTTP '+r.status);return;}"
                          + "var ab=await r.arrayBuffer();"
                          + "var u8=new Uint8Array(ab);"
                          + "var step=24576;"
                          + "for(var i=0;i<u8.length;i+=step){"
                          + "  var sub=u8.subarray(i,Math.min(i+step,u8.length));"
                          + "  var bin='';"
                          + "  for(var j=0;j<sub.length;j++){bin+=String.fromCharCode(sub[j]);}"
                          + "  HeavenCrxSink.onChunk(btoa(bin));"
                          + "}"
                          + "HeavenCrxSink.onDone();"
                          + "}catch(e){HeavenCrxSink.onError(String(e));}"
                          + "})();"
                          + "</script></body></html>";
                  wv.loadDataWithBaseURL(origin, html, "text/html", "UTF-8", null);
                });
            wv.loadUrl(crxRedirectUrl);
          } catch (Throwable t) {
            errorRef.set(t.getMessage());
            latch.countDown();
          }
        });

    boolean completed = latch.await(26, TimeUnit.SECONDS);
    mainHandler.post(
        () -> {
          WebView wv = wvHolder.getAndSet(null);
          if (wv != null) {
            try {
              wv.stopLoading();
              wv.destroy();
            } catch (Throwable ignored) {
            }
          }
        });

    if (!completed) {
      throw new IOException("Timed out downloading extension package");
    }
    if (errorRef.get() != null) {
      throw new IOException(errorRef.get());
    }
    return bridge.buffer.toByteArray();
  }

  private void postFailure(final MethodChannel.Result callback, final String message) {
    Map<String, Object> err = new HashMap<>();
    err.put("ok", false);
    err.put("error", message);
    mainHandler.post(() -> callback.success(err));
  }

  private static WebResourceResponse buildTextResponse(String mime, int status, String body) {
    Map<String, String> headers = new HashMap<>();
    headers.put("Access-Control-Allow-Origin", "*");
    headers.put("Cache-Control", "no-cache");
    byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
    return new WebResourceResponse(
        mime,
        "UTF-8",
        status,
        status == 200 ? "OK" : "Error",
        headers,
        new ByteArrayInputStream(bytes));
  }

  private static String guessMimeType(String path) {
    String lower = path.toLowerCase(Locale.US);
    if (lower.endsWith(".html") || lower.endsWith(".htm")) return "text/html";
    if (lower.endsWith(".js") || lower.endsWith(".mjs")) return "application/javascript";
    if (lower.endsWith(".css")) return "text/css";
    if (lower.endsWith(".json")) return "application/json";
    if (lower.endsWith(".png")) return "image/png";
    if (lower.endsWith(".svg")) return "image/svg+xml";
    if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
    if (lower.endsWith(".webp")) return "image/webp";
    if (lower.endsWith(".gif")) return "image/gif";
    if (lower.endsWith(".woff2")) return "font/woff2";
    if (lower.endsWith(".woff")) return "font/woff";
    if (lower.endsWith(".ttf")) return "font/ttf";
    if (lower.endsWith(".wasm")) return "application/wasm";
    return "application/octet-stream";
  }

  private static String safeReadAssetUtf8(File extDir, String relPath) {
    if (relPath == null || relPath.isEmpty()) {
      return "";
    }
    try {
      File target = new File(extDir, relPath);
      String canonicalRoot = extDir.getCanonicalPath() + File.separator;
      if (target.isFile() && target.getCanonicalPath().startsWith(canonicalRoot)) {
        return readUtf8File(target);
      }
    } catch (Throwable ignored) {
    }
    return "";
  }

  private static String readUtf8File(File file) throws IOException {
    return new String(readFileBytes(file), StandardCharsets.UTF_8);
  }

  private static byte[] readFileBytes(File file) throws IOException {
    try (FileInputStream fis = new FileInputStream(file);
        ByteArrayOutputStream bos = new ByteArrayOutputStream()) {
      byte[] buf = new byte[8192];
      int n;
      while ((n = fis.read(buf)) > 0) {
        bos.write(buf, 0, n);
      }
      return bos.toByteArray();
    }
  }

  private static String sanitizeId(String raw) {
    if (raw == null || raw.isEmpty()) {
      return "ext";
    }
    return raw.toLowerCase(Locale.US).replaceAll("[^a-z0-9_]", "");
  }

  private static String generateSyntheticExtId(String seed) {
    char[] out = new char[32];
    int h = seed.hashCode();
    for (int i = 0; i < 32; i++) {
      h = h * 31 + i + (i < seed.length() ? seed.charAt(i) : 7);
      out[i] = (char) ('a' + (Math.abs(h) % 16));
    }
    return new String(out);
  }

  private static void moveDirectoryChildrenUp(File srcDir, File dstDir) {
    File[] files = srcDir.listFiles();
    if (files == null) {
      return;
    }
    for (File f : files) {
      File dest = new File(dstDir, f.getName());
      //noinspection ResultOfMethodCallIgnored
      f.renameTo(dest);
    }
  }

  private static void deleteRecursively(File file) {
    if (file == null || !file.exists()) {
      return;
    }
    if (file.isDirectory()) {
      File[] children = file.listFiles();
      if (children != null) {
        for (File c : children) {
          deleteRecursively(c);
        }
      }
    }
    //noinspection ResultOfMethodCallIgnored
    file.delete();
  }
}
