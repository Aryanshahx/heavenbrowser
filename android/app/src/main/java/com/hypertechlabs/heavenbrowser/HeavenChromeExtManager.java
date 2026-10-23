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
import java.util.Set;
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
 * - Direct Java JavascriptInterface bridge (HeavenExtNative) on every tab and background worker
 * - Bidirectional chrome.runtime.sendMessage & chrome.tabs.sendMessage with sendResponse callbacks
 * - Synchronous importScripts() polyfill for MV3 service_worker scripts
 * - Full chrome-extension://<id>/... URL translation without redirect blocks
 * - CSP-immune DOCUMENT_START + DOCUMENT_IDLE content_scripts & CSS (adoptedStyleSheets + style)
 * - Native MV3 declarativeNetRequest block-rule enforcement
 */
public final class HeavenChromeExtManager {

  public interface ActiveTabExtensionBridge {
    void evalInActiveTab(String jsCode);

    void evalInAllWebViews(String jsCode);

    void evalInWebView(long webViewId, String jsCode);

    void openNewTab(String url);

    void navigateTargetTab(String url);

    void onWebStoreInstalledFromPage(Map<String, Object> result);

    String getActiveTabUrl();

    String getActiveTabTitle();
  }

  public static final String EXT_VIRTUAL_HOST = "chrome-ext.heaven.local";
  public static final String EXT_HOME_PATH = "/__heaven_ext_home.html";
  private static final String REGISTRY_FILE = "registry.json";
  private static final String STORAGE_FILE = "__heaven_storage.json";
  private static final String POLYFILL_PATH = "/__heaven_chrome_polyfill.js";
  private static final String BG_HOST_PATH = "/__heaven_bg.html";
  private static final String EXT_FETCH_PATH = "/__heaven_ext_fetch";
  private static final Pattern EXT_ID_PATTERN = Pattern.compile("([a-p]{32})");
  private static final Pattern META_CSP_PATTERN =
      Pattern.compile(
          "<meta[^>]*http-equiv\\s*=\\s*[\"']?Content-Security-Policy[\"']?[^>]*>",
          Pattern.CASE_INSENSITIVE);

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

  private static final class PendingReplyTarget {
    final MethodChannel.Result channelResult;
    final long callerWebViewId;
    final String extId;
    final String jsReqId;

    PendingReplyTarget(
        MethodChannel.Result channelResult, long callerWebViewId, String extId, String jsReqId) {
      this.channelResult = channelResult;
      this.callerWebViewId = callerWebViewId;
      this.extId = extId;
      this.jsReqId = jsReqId;
    }
  }

  private final Context appContext;
  private final File rootDir;
  private final ExecutorService ioPool = Executors.newCachedThreadPool();
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final Object lock = new Object();

  private JSONArray registryArray = new JSONArray();
  private volatile List<DnrBlockRule> compiledDnrRules = Collections.emptyList();
  private volatile String cachedDocStartExtJs = "";
  private final Map<String, WebView> bgWebViews = new ConcurrentHashMap<>();
  private final Set<String> readyBgWorkers =
      Collections.newSetFromMap(new ConcurrentHashMap<>());
  private final Map<String, List<Runnable>> pendingBgTasks = new ConcurrentHashMap<>();
  private final Map<String, PendingReplyTarget> pendingBgCallbacks = new ConcurrentHashMap<>();
  private volatile ActiveTabExtensionBridge activeTabBridge;
  private volatile Runnable onExtensionsChangedListener;

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

  public void setOnExtensionsChangedListener(Runnable listener) {
    this.onExtensionsChangedListener = listener;
  }

  public Object createWebViewJsBridge(long webViewId) {
    return new WebViewExtNativeBridge(webViewId);
  }

  public String getDocumentStartExtensionsJs() {
    return this.cachedDocStartExtJs;
  }

  /**
   * Translates chrome-extension://<id>/path or relative extension paths into the HTTPS virtual
   * host https://chrome-ext.heaven.local/<id>/path so WebView never blocks extension redirects.
   */
  public static String normalizeExtensionUrl(String rawUrl, String defaultExtId) {
    if (rawUrl == null) {
      return "";
    }
    String trimmed = rawUrl.trim();
    if (trimmed.isEmpty()) {
      return "";
    }
    String lower = trimmed.toLowerCase(Locale.US);
    if (lower.startsWith("chrome-extension://")) {
      String rest = trimmed.substring("chrome-extension://".length());
      int slash = rest.indexOf('/');
      String hostId = slash >= 0 ? sanitizeId(rest.substring(0, slash)) : sanitizeId(rest);
      String path = slash >= 0 ? rest.substring(slash) : EXT_HOME_PATH;
      if (path.isEmpty() || "/".equals(path)) {
        path = EXT_HOME_PATH;
      }
      return "https://" + EXT_VIRTUAL_HOST + "/" + hostId + path;
    }
    if (lower.startsWith("moz-extension://")) {
      String rest = trimmed.substring("moz-extension://".length());
      int slash = rest.indexOf('/');
      String hostId =
          defaultExtId != null && !defaultExtId.isEmpty()
              ? sanitizeId(defaultExtId)
              : (slash >= 0 ? sanitizeId(rest.substring(0, slash)) : sanitizeId(rest));
      String path = slash >= 0 ? rest.substring(slash) : EXT_HOME_PATH;
      return "https://" + EXT_VIRTUAL_HOST + "/" + hostId + path;
    }
    if (!lower.startsWith("http://")
        && !lower.startsWith("https://")
        && !lower.startsWith("about:")
        && !lower.startsWith("data:")
        && !lower.startsWith("blob:")
        && defaultExtId != null
        && !defaultExtId.isEmpty()) {
      String cleanRel = normalizeSingleRelPath(trimmed);
      return "https://" + EXT_VIRTUAL_HOST + "/" + sanitizeId(defaultExtId) + "/" + cleanRel;
    }
    return trimmed;
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
      if (callback != null) {
        callback.success(err);
      }
      return;
    }

    ioPool.execute(
        () -> {
          try {
            byte[] crxBytes = downloadExtensionCrxMultiStage(extId);
            if (crxBytes == null || crxBytes.length < 32) {
              if (callback != null) {
                postFailure(
                    callback,
                    "Chrome Web Store returned an empty CRX package for ID " + extId + ".");
              }
              return;
            }
            Map<String, Object> installed = unpackAndRegisterPackage(extId, crxBytes, "webstore");
            rebuildDnrRulesAndBootBackgrounds();
            bootBackgroundWorker(extId, true);
            notifyExtensionsChanged();
            mainHandler.post(
                () -> {
                  if (callback != null) {
                    callback.success(installed);
                  }
                  ActiveTabExtensionBridge br = activeTabBridge;
                  if (br != null && callback == null) {
                    br.onWebStoreInstalledFromPage(installed);
                  }
                });
          } catch (Throwable t) {
            String msg =
                "Failed to download Chrome extension: "
                    + (t.getMessage() != null ? t.getMessage() : t.getClass().getSimpleName());
            if (callback != null) {
              postFailure(callback, msg);
            } else {
              Map<String, Object> err = new HashMap<>();
              err.put("ok", false);
              err.put("error", msg);
              mainHandler.post(
                  () -> {
                    ActiveTabExtensionBridge br = activeTabBridge;
                    if (br != null) {
                      br.onWebStoreInstalledFromPage(err);
                    }
                  });
            }
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
            notifyExtensionsChanged();
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
            notifyExtensionsChanged();
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
    ioPool.execute(
        () -> {
          rebuildDnrRulesAndBootBackgrounds();
          notifyExtensionsChanged();
        });
    return removed;
  }

  private void notifyExtensionsChanged() {
    Runnable r = this.onExtensionsChangedListener;
    if (r != null) {
      mainHandler.post(r);
    }
  }

  public void shutdown() {
    for (String id : new ArrayList<>(bgWebViews.keySet())) {
      stopBackgroundWorker(id);
    }
    ioPool.shutdownNow();
  }

  private void stopBackgroundWorker(final String extId) {
    final String cleanId = sanitizeId(extId);
    readyBgWorkers.remove(cleanId);
    pendingBgTasks.remove(cleanId);
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
    cachedDocStartExtJs = compileDocumentStartExtensionsBundle(enabledExts);
  }

  /**
   * Pre-compiles enabled document_start content scripts & CSS so WebViewCompat
   * addDocumentStartJavaScript can execute them before page scripts (bypassing page CSP).
   */
  private String compileDocumentStartExtensionsBundle(List<JSONObject> enabledExts) {
    if (enabledExts == null || enabledExts.isEmpty()) {
      return "";
    }
    StringBuilder out = new StringBuilder(4096);
    boolean hasAny = false;
    out.append("(function(){try{");
    out.append(
        "if(location.protocol!=='http:'&&location.protocol!=='https:')return;"
            + "if(location.hostname==='"
            + EXT_VIRTUAL_HOST
            + "'||location.hostname==='chromewebstore.google.com')return;"
            + "window.__hbInjectedExtStage=window.__hbInjectedExtStage||{};"
            + "function __hbMatchPat(u,p){"
            + "  if(!p)return false;"
            + "  if(p==='<all_urls>'||p==='*://*/*'||p==='http://*/*'||p==='https://*/*')return true;"
            + "  var sep=p.indexOf('://');if(sep<0)return false;"
            + "  var ps=p.slice(0,sep).toLowerCase();"
            + "  if(ps!=='*'&&(ps+':')!==location.protocol)return false;"
            + "  var rest=p.slice(sep+3);var sl=rest.indexOf('/');"
            + "  var ph=(sl>=0?rest.slice(0,sl):rest).toLowerCase();"
            + "  var pp=sl>=0?rest.slice(sl):'/*';"
            + "  var h=location.hostname.toLowerCase();"
            + "  if(ph!=='*'){"
            + "    if(ph.indexOf('*.')===0){var r=ph.slice(2);if(h!==r&&h.slice(-(r.length+1))!=='.'+r)return false;}"
            + "    else if(h!==ph)return false;"
            + "  }"
            + "  if(pp==='/*'||pp==='*')return true;"
            + "  var rx='^'+pp.replace(/[.+?^${}()|[\\]\\\\]/g,'\\\\$&').replace(/\\*/g,'.*')+'$';"
            + "  return new RegExp(rx).test(location.pathname+location.search);"
            + "}"
            + "function __hbMatchAny(u,arr){if(!arr||!arr.length)return false;for(var i=0;i<arr.length;i++){if(__hbMatchPat(u,arr[i]))return true;}return false;}"
            + "function __hbAddCss(id,cssTxt){"
            + "  if(document.getElementById(id))return;"
            + "  try{var s=document.createElement('style');s.id=id;s.textContent=cssTxt;(document.head||document.documentElement).appendChild(s);}catch(e){}"
            + "  try{if(document.adoptedStyleSheets&&typeof CSSStyleSheet!=='undefined'){var sh=new CSSStyleSheet();sh.replaceSync(cssTxt);document.adoptedStyleSheets=[].concat(Array.from(document.adoptedStyleSheets),[sh]);}}catch(e){}"
            + "}");

    for (JSONObject ext : enabledExts) {
      String extId = sanitizeId(ext.optString("id", ""));
      File extDir = new File(rootDir, extId);
      if (!extDir.isDirectory()) continue;
      JSONArray csArr = ext.optJSONArray("contentScripts");
      if (csArr == null || csArr.length() == 0) continue;

      StringBuilder extChunk = new StringBuilder();
      for (int c = 0; c < csArr.length(); c++) {
        JSONObject cs = csArr.optJSONObject(c);
        if (cs == null || !"document_start".equals(cs.optString("runAt", "document_idle"))) {
          continue;
        }
        JSONArray matches = cs.optJSONArray("matches");
        JSONArray exMatches = cs.optJSONArray("excludeMatches");
        if (matches == null || matches.length() == 0) continue;

        StringBuilder body = new StringBuilder();
        JSONArray cssFiles = cs.optJSONArray("css");
        if (cssFiles != null) {
          for (int k = 0; k < cssFiles.length(); k++) {
            String cssContent = safeReadAssetUtf8(extDir, cssFiles.optString(k, ""));
            if (!cssContent.isEmpty()) {
              body.append("__hbAddCss('hb-ext-css-")
                  .append(extId)
                  .append("-")
                  .append(c)
                  .append("-")
                  .append(k)
                  .append("',")
                  .append(JSONObject.quote(cssContent))
                  .append(");");
            }
          }
        }
        JSONArray jsFiles = cs.optJSONArray("js");
        if (jsFiles != null && jsFiles.length() > 0) {
          body.append("(function(){var gk='")
              .append(extId)
              .append("_")
              .append(c)
              .append(":'+location.href;if(window.__hbInjectedExtStage[gk])return;window.__hbInjectedExtStage[gk]=true;");
          for (int j = 0; j < jsFiles.length(); j++) {
            String jsContent = safeReadAssetUtf8(extDir, jsFiles.optString(j, ""));
            if (!jsContent.isEmpty()) {
              body.append("try{\n").append(jsContent).append("\n}catch(e){}\n");
            }
          }
          body.append("})();");
        }
        if (body.length() > 0) {
          extChunk
              .append("if(__hbMatchAny(location.href,")
              .append(matches.toString())
              .append(")&&!__hbMatchAny(location.href,")
              .append(exMatches != null ? exMatches.toString() : "[]")
              .append(")){")
              .append(body)
              .append("}");
        }
      }
      if (extChunk.length() > 0) {
        hasAny = true;
        String factoryJs = buildExtensionChromeFactoryJs(extId, extDir, "", "");
        out.append("(function(){try{var __extC=")
            .append(factoryJs)
            .append(";(function(chrome,browser){\n")
            .append(extChunk)
            .append("\n})(__extC,__extC);}catch(_e){}})();");
      }
    }
    out.append("}catch(_){}})();");
    return hasAny ? out.toString() : "";
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
    if (EXT_VIRTUAL_HOST.equalsIgnoreCase(host)) {
      return false;
    }
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

  /**
   * Direct synchronous + asynchronous JavascriptInterface attached to EVERY BrowserTab WebView
   * and offscreen background worker WebView as window.HeavenExtNative.
   */
  public final class WebViewExtNativeBridge {
    private final long webViewId;

    WebViewExtNativeBridge(long webViewId) {
      this.webViewId = webViewId;
    }

    @JavascriptInterface
    public String getStorageJson(String extId) {
      if (extId == null || extId.isEmpty()) return "{}";
      synchronized (lock) {
        File extDir = new File(rootDir, sanitizeId(extId));
        return readExtensionStorageLocked(extDir).toString();
      }
    }

    @JavascriptInterface
    public void patchStorage(String extId, String patchJson) {
      updateExtensionStorage(extId, patchJson);
    }

    @JavascriptInterface
    public String getTargetTabJson() {
      ActiveTabExtensionBridge br = activeTabBridge;
      String u = br != null ? br.getActiveTabUrl() : "https://www.google.com";
      String t = br != null ? br.getActiveTabTitle() : "Google";
      if (u == null || u.isEmpty()) u = "https://www.google.com";
      if (t == null || t.isEmpty()) t = "Active Tab";
      try {
        JSONObject tab = new JSONObject();
        tab.put("id", 1);
        tab.put("index", 0);
        tab.put("windowId", 1);
        tab.put("active", true);
        tab.put("highlighted", true);
        tab.put("pinned", false);
        tab.put("status", "complete");
        tab.put("url", u);
        tab.put("pendingUrl", u);
        tab.put("title", t);
        return tab.toString();
      } catch (Throwable ignored) {
        return "{\"id\":1,\"active\":true,\"url\":\"https://www.google.com\"}";
      }
    }

    @JavascriptInterface
    public void sendRuntimeMessage(
        final String extId,
        final String jsReqId,
        final String messageJson,
        final String senderUrl,
        final boolean fromBg) {
      final String cleanId = sanitizeId(extId);
      if (fromBg) {
        // Background worker sending to active tab content script
        final ActiveTabExtensionBridge br = activeTabBridge;
        if (br != null) {
          final String qMsg = JSONObject.quote(messageJson != null ? messageJson : "{}");
          final String js =
              "(function(){try{var p=JSON.parse("
                  + qMsg
                  + ");if(window.__hbExtDeliverMessage)window.__hbExtDeliverMessage('"
                  + cleanId
                  + "',p);}catch(e){}})();";
          mainHandler.post(() -> br.evalInActiveTab(js));
        }
        return;
      }
      dispatchRuntimeMessageInternal(
          cleanId,
          messageJson,
          senderUrl,
          new PendingReplyTarget(null, webViewId, cleanId, jsReqId != null ? jsReqId : ""));
    }

    @JavascriptInterface
    public void onBgRuntimeReply(String internalReqId, String replyJson) {
      resolvePendingBgReply(internalReqId, replyJson);
    }

    @JavascriptInterface
    public void sendTabMessage(
        final String extId, final String jsReqId, final String messageJson) {
      final String cleanId = sanitizeId(extId);
      final ActiveTabExtensionBridge br = activeTabBridge;
      if (br == null) {
        return;
      }
      final String qMsg = JSONObject.quote(messageJson != null ? messageJson : "{}");
      final String safeReq = jsReqId != null ? jsReqId.replace("'", "") : "";
      final String js =
          "(function(){try{"
              + "var msg=JSON.parse("
              + qMsg
              + ");"
              + "if(window.__hbExtDeliverTabMsg){"
              + "  window.__hbExtDeliverTabMsg('"
              + cleanId
              + "','"
              + safeReq
              + "',"
              + webViewId
              + ",msg);"
              + "}else if(window.HeavenExtNative){"
              + "  window.HeavenExtNative.replyTabMessage('"
              + cleanId
              + "','"
              + safeReq
              + "',"
              + webViewId
              + ",'{}');"
              + "}"
              + "}catch(e){}})();";
      mainHandler.post(() -> br.evalInActiveTab(js));
    }

    @JavascriptInterface
    public void replyTabMessage(
        final String extId,
        final String jsReqId,
        final long callerWvId,
        final String replyJson) {
      final String cleanId = sanitizeId(extId);
      final String qReply = JSONObject.quote(replyJson != null ? replyJson : "{}");
      final String safeReq = jsReqId != null ? jsReqId.replace("'", "") : "";
      final String js =
          "(function(){try{if(window.__hbExtRuntimeReply)window.__hbExtRuntimeReply('"
              + cleanId
              + "','"
              + safeReq
              + "',"
              + qReply
              + ");}catch(e){}})();";
      if (callerWvId == -100L) {
        mainHandler.post(
            () -> {
              WebView bgWv = bgWebViews.get(cleanId);
              if (bgWv != null) {
                bgWv.evaluateJavascript(js, null);
              }
            });
      } else {
        final ActiveTabExtensionBridge br = activeTabBridge;
        if (br != null) {
          mainHandler.post(() -> br.evalInWebView(callerWvId, js));
        }
      }
    }

    @JavascriptInterface
    public void createTab(final String extId, final String rawUrl) {
      final String normalized = normalizeExtensionUrl(rawUrl, extId);
      final ActiveTabExtensionBridge br = activeTabBridge;
      if (!normalized.isEmpty() && br != null) {
        mainHandler.post(() -> br.openNewTab(normalized));
      }
    }

    @JavascriptInterface
    public void updateTab(final String extId, final String rawUrl) {
      final String normalized = normalizeExtensionUrl(rawUrl, extId);
      final ActiveTabExtensionBridge br = activeTabBridge;
      if (!normalized.isEmpty() && br != null) {
        mainHandler.post(() -> br.navigateTargetTab(normalized));
      }
    }

    @JavascriptInterface
    public void reloadTab() {
      final ActiveTabExtensionBridge br = activeTabBridge;
      if (br != null) {
        mainHandler.post(() -> br.evalInActiveTab("location.reload();"));
      }
    }

    @JavascriptInterface
    public void executeScript(final String extId, final String payloadJson) {
      try {
        JSONObject data = new JSONObject(payloadJson != null ? payloadJson : "{}");
        handleExecuteScriptOnActiveTab(sanitizeId(extId), data);
      } catch (Throwable ignored) {
      }
    }

    @JavascriptInterface
    public void insertCss(final String extId, final String payloadJson) {
      try {
        JSONObject data = new JSONObject(payloadJson != null ? payloadJson : "{}");
        handleInsertCssOnActiveTab(sanitizeId(extId), data);
      } catch (Throwable ignored) {
      }
    }

    @JavascriptInterface
    public void triggerAction(final String extId) {
      ActiveTabExtensionBridge br = activeTabBridge;
      String u = br != null ? br.getActiveTabUrl() : "https://www.google.com";
      String t = br != null ? br.getActiveTabTitle() : "Google";
      dispatchExtensionActionClicked(extId, u, t);
    }

    @JavascriptInterface
    public void installWebStore(final String urlOrId) {
      installFromWebStore(urlOrId, null);
    }
  }

  private void resolvePendingBgReply(String internalReqId, String replyJson) {
    if (internalReqId == null) return;
    final PendingReplyTarget target = pendingBgCallbacks.remove(internalReqId);
    if (target == null) return;
    final String safeReply = replyJson != null ? replyJson : "{}";
    if (target.channelResult != null) {
      mainHandler.post(() -> target.channelResult.success(safeReply));
    } else if (target.callerWebViewId >= 0) {
      final ActiveTabExtensionBridge br = activeTabBridge;
      if (br != null) {
        final String js =
            "(function(){try{if(window.__hbExtRuntimeReply)window.__hbExtRuntimeReply('"
                + target.extId
                + "','"
                + target.jsReqId.replace("'", "")
                + "',"
                + JSONObject.quote(safeReply)
                + ");}catch(e){}})();";
        mainHandler.post(() -> br.evalInWebView(target.callerWebViewId, js));
      }
    }
  }

  private void handleInsertCssOnActiveTab(String cleanId, JSONObject data) {
    final ActiveTabExtensionBridge bridge = activeTabBridge;
    if (bridge == null || data == null) return;
    String css = data.optString("css", "");
    JSONArray files = data.optJSONArray("files");
    if (css.isEmpty() && files != null) {
      File extDir = new File(rootDir, cleanId);
      StringBuilder sb = new StringBuilder();
      for (int i = 0; i < files.length(); i++) {
        sb.append(safeReadAssetUtf8(extDir, normalizeSingleRelPath(files.optString(i, ""))))
            .append('\n');
      }
      css = sb.toString();
    }
    final String finalCss = css;
    if (!finalCss.isEmpty()) {
      final String quoted = JSONObject.quote(finalCss);
      final String js =
          "(function(){var c="
              + quoted
              + ";try{var s=document.createElement('style');s.textContent=c;(document.head||document.documentElement).appendChild(s);}catch(e){}"
              + "try{if(document.adoptedStyleSheets&&typeof CSSStyleSheet!=='undefined'){var sh=new CSSStyleSheet();sh.replaceSync(c);document.adoptedStyleSheets=[].concat(Array.from(document.adoptedStyleSheets),[sh]);}}catch(e){}"
              + "})();";
      mainHandler.post(() -> bridge.evalInActiveTab(js));
    }
  }

  private void handleExecuteScriptOnActiveTab(String cleanId, JSONObject data) {
    final ActiveTabExtensionBridge bridge = activeTabBridge;
    if (bridge == null || data == null) {
      return;
    }
    File extDir = new File(rootDir, cleanId);
    StringBuilder codeBuilder = new StringBuilder();
    JSONArray files = data.optJSONArray("files");
    if (files != null) {
      for (int i = 0; i < files.length(); i++) {
        String rel = normalizeSingleRelPath(files.optString(i, ""));
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
            cleanId, extDir, bridge.getActiveTabUrl(), bridge.getActiveTabTitle());
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
          readyBgWorkers.remove(extId);
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
            bgWv.addJavascriptInterface(new WebViewExtNativeBridge(-100L), "HeavenExtNative");
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
                    readyBgWorkers.add(extId);
                    if (emitInstalledEvent) {
                      view.evaluateJavascript(
                          "try{if(window.chrome&&chrome.runtime&&chrome.runtime.onInstalled)"
                              + "chrome.runtime.onInstalled._emit({reason:'install'});}catch(e){}",
                          null);
                    }
                    List<Runnable> queued = pendingBgTasks.remove(extId);
                    if (queued != null) {
                      for (Runnable task : queued) {
                        try {
                          task.run();
                        } catch (Throwable ignored) {
                        }
                      }
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
    dispatchRuntimeMessageInternal(
        extId, messageJson, senderUrl, new PendingReplyTarget(result, -1L, extId, ""));
  }

  private void dispatchRuntimeMessageInternal(
      final String extId,
      final String messageJson,
      final String senderUrl,
      final PendingReplyTarget replyTarget) {
    mainHandler.post(
        () -> {
          final JSONObject meta;
          synchronized (lock) {
            meta = findExtensionLocked(extId);
          }
          if (meta == null || !hasBackgroundConfig(meta)) {
            if (replyTarget.channelResult != null) {
              replyTarget.channelResult.success("{}");
            } else if (replyTarget.callerWebViewId >= 0) {
              ActiveTabExtensionBridge br = activeTabBridge;
              if (br != null) {
                br.evalInWebView(
                    replyTarget.callerWebViewId,
                    "if(window.__hbExtRuntimeReply)window.__hbExtRuntimeReply('"
                        + extId
                        + "','"
                        + replyTarget.jsReqId.replace("'", "")
                        + "','{}');");
              }
            }
            return;
          }

          if (!bgWebViews.containsKey(extId)) {
            bootBackgroundWorker(extId, false);
          }

          final String internalReqId = "bgreq_" + System.nanoTime();
          pendingBgCallbacks.put(internalReqId, replyTarget);
          mainHandler.postDelayed(() -> resolvePendingBgReply(internalReqId, "{}"), 3200L);

          Runnable evalTask =
              () -> {
                WebView bgWv = bgWebViews.get(extId);
                if (bgWv == null) {
                  resolvePendingBgReply(internalReqId, "{}");
                  return;
                }
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
                        + "  if(window.HeavenExtNative)window.HeavenExtNative.onBgRuntimeReply('"
                        + internalReqId
                        + "',out);"
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
                        + "  if(!asyncHold)setTimeout(function(){done({});},35);"
                        + "}else{done({});}"
                        + "}catch(e){"
                        + "  if(window.HeavenExtNative)window.HeavenExtNative.onBgRuntimeReply('"
                        + internalReqId
                        + "','{}');"
                        + "}"
                        + "})();";
                bgWv.evaluateJavascript(js, null);
              };

          if (readyBgWorkers.contains(extId)) {
            evalTask.run();
          } else {
            pendingBgTasks.computeIfAbsent(extId, k -> new ArrayList<>()).add(evalTask);
          }
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
        100L);
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
              br.evalInAllWebViews(syncJs);
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

  public WebResourceResponse interceptExtensionRequest(
      Uri uri, String activeTabUrl, String activeTabTitle) {
    if (uri == null) {
      return null;
    }
    String scheme = uri.getScheme() != null ? uri.getScheme().toLowerCase(Locale.US) : "";
    String extId;
    String relPath;

    if ("chrome-extension".equals(scheme) || "moz-extension".equals(scheme)) {
      extId = sanitizeId(uri.getHost());
      relPath = uri.getPath() != null && !uri.getPath().isEmpty() ? uri.getPath() : "/";
    } else if (EXT_VIRTUAL_HOST.equalsIgnoreCase(uri.getHost())) {
      List<String> segments = uri.getPathSegments();
      if (segments == null || segments.isEmpty()) {
        return buildTextResponse("text/plain", 404, "Missing extension ID");
      }
      extId = sanitizeId(segments.get(0));
      String subPath = uri.getPath() != null ? uri.getPath() : "/";
      String prefix = "/" + segments.get(0);
      relPath = subPath.startsWith(prefix) ? subPath.substring(prefix.length()) : subPath;
    } else {
      return null;
    }

    File extDir = new File(rootDir, extId);
    if (!extDir.exists()) {
      return buildTextResponse("text/plain", 404, "Extension not installed");
    }

    if (relPath.isEmpty() || "/".equals(relPath)) {
      JSONObject meta;
      synchronized (lock) {
        meta = findExtensionLocked(extId);
      }
      String pop = meta != null ? meta.optString("popupPath", "") : "";
      String opt = meta != null ? meta.optString("optionsPath", "") : "";
      if (!pop.isEmpty()) {
        relPath = "/" + pop;
      } else if (!opt.isEmpty()) {
        relPath = "/" + opt;
      } else {
        relPath = EXT_HOME_PATH;
      }
    }

    if (POLYFILL_PATH.equals(relPath)) {
      String js = buildChromePagePolyfillJs(extId, extDir, activeTabUrl, activeTabTitle);
      return buildTextResponse("application/javascript", 200, js);
    }

    if (BG_HOST_PATH.equals(relPath)) {
      String bgHtml = buildBackgroundHostHtml(extId);
      return buildTextResponse("text/html", 200, bgHtml);
    }

    if (EXT_HOME_PATH.equals(relPath)) {
      String homeHtml = buildExtensionHomeHtml(extId, activeTabUrl);
      return buildTextResponse("text/html", 200, homeHtml);
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
        if (cleanRel.endsWith(".html")) {
          return buildTextResponse("text/html", 200, buildExtensionHomeHtml(extId, activeTabUrl));
        }
        return buildTextResponse("text/plain", 404, "Asset not found");
      }

      String mime = guessMimeType(cleanRel);
      if ("text/html".equals(mime)) {
        String html = readUtf8File(target);
        // Remove restrictive <meta http-equiv="Content-Security-Policy"> so extension scripts & polyfill execute cleanly
        html = META_CSP_PATTERN.matcher(html).replaceAll("");
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

  private String buildExtensionHomeHtml(String extId, String activeTabUrl) {
    JSONObject meta;
    synchronized (lock) {
      meta = findExtensionLocked(extId);
    }
    String name = meta != null ? escapeHtml(meta.optString("name", "Extension")) : "Extension";
    String ver = meta != null ? escapeHtml(meta.optString("version", "1.0")) : "1.0";
    String desc = meta != null ? escapeHtml(meta.optString("description", "")) : "";
    String optUrl = meta != null ? meta.optString("optionsUrl", "") : "";
    String safeTarget =
        escapeHtml(activeTabUrl != null && !activeTabUrl.isEmpty() ? activeTabUrl : "Active Tab");

    return "<!doctype html><html><head><meta charset=\"utf-8\">"
        + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        + "<title>"
        + name
        + "</title>"
        + "<script src=\"https://"
        + EXT_VIRTUAL_HOST
        + "/"
        + extId
        + POLYFILL_PATH
        + "\"></script>"
        + "<style>"
        + "body{margin:0;padding:24px;font-family:system-ui,-apple-system,sans-serif;background:#040B16;color:#F8FAFC;}"
        + ".card{max-width:520px;margin:0 auto;background:#0B162C;border:1px solid rgba(96,165,250,.22);border-radius:18px;padding:22px;}"
        + "h1{margin:0 0 4px;font-size:20px;} .sub{color:#94A3B8;font-size:13px;margin-bottom:16px;}"
        + ".pill{display:inline-block;padding:4px 10px;border-radius:99px;background:rgba(16,185,129,.15);color:#34D399;font-size:12px;font-weight:600;margin-bottom:14px;}"
        + "button{width:100%;padding:12px 16px;border-radius:12px;border:none;background:#2563EB;color:#fff;font-weight:700;font-size:14px;cursor:pointer;margin-top:10px;}"
        + "button.sec{background:rgba(255,255,255,.08);color:#E2E8F0;}"
        + "pre{background:#040B16;padding:12px;border-radius:10px;font-size:12px;overflow:auto;max-height:200px;color:#93C5FD;}"
        + "</style></head><body><div class=\"card\">"
        + "<div class=\"pill\">Active in Heaven</div>"
        + "<h1>"
        + name
        + " <span style=\"font-weight:400;font-size:13px;color:#94A3B8\">v"
        + ver
        + "</span></h1>"
        + "<div class=\"sub\">"
        + desc
        + "</div>"
        + "<div style=\"font-size:12px;color:#94A3B8;margin-bottom:8px;\">Target Website Tab: <strong style=\"color:#E2E8F0\">"
        + safeTarget
        + "</strong></div>"
        + "<button id=\"runBtn\">Run Extension on Website Tab</button>"
        + (!optUrl.isEmpty()
            ? "<button class=\"sec\" id=\"optBtn\">Open Extension Options</button>"
            : "")
        + "<div style=\"margin-top:18px;font-size:12px;font-weight:600;color:#94A3B8;\">Extension Storage (chrome.storage.local)</div>"
        + "<pre id=\"stBox\">{}</pre>"
        + "</div><script>"
        + "function refreshStore(){chrome.storage.local.get(null,function(items){document.getElementById('stBox').textContent=JSON.stringify(items||{},null,2);});}"
        + "refreshStore();"
        + "document.getElementById('runBtn').onclick=function(){"
        + "  if(window.HeavenExtNative)window.HeavenExtNative.triggerAction('"
        + extId
        + "');"
        + "  this.textContent='Executed on Website Tab!';"
        + "  setTimeout(()=>{this.textContent='Run Extension on Website Tab';refreshStore();},1200);"
        + "};"
        + (!optUrl.isEmpty()
            ? "document.getElementById('optBtn').onclick=function(){location.href='"
                + optUrl
                + "';};"
            : "")
        + "</script></body></html>";
  }

  private static String escapeHtml(String s) {
    if (s == null) return "";
    return s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;");
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
              appContext, targetUrl, CRX_DESKTOP_UA, false, 5, 8 * 1024 * 1024);
      if (data == null) {
        return buildTextResponse("text/plain", 502, "");
      }
      Map<String, String> headers = new HashMap<>();
      headers.put("Access-Control-Allow-Origin", "*");
      headers.put("Cache-Control", "no-cache");
      return new WebResourceResponse(
          "application/octet-stream", "UTF-8", 200, "OK", headers, new ByteArrayInputStream(data));
    } catch (Throwable t) {
      return buildTextResponse("text/plain", 502, "");
    }
  }

  public String buildContentScriptsBundleForUrl(String pageUrl) {
    return buildContentScriptsBundleForUrl(pageUrl, "all", false);
  }

  public String buildContentScriptsBundleForUrl(
      String pageUrl, String stageFilter, boolean forceReRun) {
    if (pageUrl == null || (!pageUrl.startsWith("http://") && !pageUrl.startsWith("https://"))) {
      return "";
    }
    try {
      Uri parsed = Uri.parse(pageUrl);
      if (EXT_VIRTUAL_HOST.equalsIgnoreCase(parsed.getHost())) {
        return "";
      }
    } catch (Throwable ignored) {
    }

    List<JSONObject> activeList = new ArrayList<>();
    synchronized (lock) {
      for (int i = 0; i < registryArray.length(); i++) {
        JSONObject item = registryArray.optJSONObject(i);
        if (item != null && item.optBoolean("enabled", true)) {
          activeList.add(item);
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
    bundle.append(
        "function __hbInjectCss(id,c){"
            + "if(document.getElementById(id))return;"
            + "try{var s=document.createElement('style');s.id=id;s.textContent=c;(document.head||document.documentElement).appendChild(s);}catch(e){}"
            + "try{if(document.adoptedStyleSheets&&typeof CSSStyleSheet!=='undefined'){var sh=new CSSStyleSheet();sh.replaceSync(c);document.adoptedStyleSheets=[].concat(Array.from(document.adoptedStyleSheets),[sh]);}}catch(e){}"
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
                  .append("__hbInjectCss('")
                  .append(styleId)
                  .append("',")
                  .append(JSONObject.quote(cssContent))
                  .append(");");
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
    return "(function(){"
        + "var BASE='https://"
        + EXT_VIRTUAL_HOST
        + "/"
        + extId
        + "/';"
        + "window.importScripts=self.importScripts=function(){"
        + "  for(var i=0;i<arguments.length;i++){"
        + "    var p=String(arguments[i]||'');"
        + "    if(!p)continue;"
        + "    var u=(p.indexOf('https://')===0||p.indexOf('http://')===0)?p:(BASE+p.replace(/^\\/+/,''));"
        + "    var x=new XMLHttpRequest();"
        + "    x.open('GET',u,false);"
        + "    x.send(null);"
        + "    if(x.status>=200&&x.status<300&&x.responseText){(0,eval)(x.responseText);}"
        + "  }"
        + "};"
        + "self.skipWaiting=function(){return Promise.resolve();};"
        + "self.clients=self.clients||{claim:function(){return Promise.resolve();},matchAll:function(){return Promise.resolve([]);}};"
        + "var c="
        + factoryJs
        + ";"
        + "window.chrome=c;window.browser=c;self.chrome=c;self.browser=c;"
        + "window.open=function(u){"
        + "  if(u&&window.HeavenExtNative)window.HeavenExtNative.createTab('"
        + extId
        + "',String(u));"
        + "  return null;"
        + "};"
        + "document.addEventListener('click',function(ev){"
        + "  var a=ev.target&&ev.target.closest?ev.target.closest('a[href]'):null;"
        + "  if(!a)return;"
        + "  var h=a.getAttribute('href')||'';"
        + "  if(h.indexOf('chrome-extension://')===0){"
        + "    ev.preventDefault();"
        + "    var rest=h.slice('chrome-extension://'.length);"
        + "    var sl=rest.indexOf('/');"
        + "    var id=sl>=0?rest.slice(0,sl):rest;"
        + "    var pt=sl>=0?rest.slice(sl):'/';"
        + "    location.href='https://"
        + EXT_VIRTUAL_HOST
        + "/'+id+pt;"
        + "  }else if(a.target==='_blank'&&h&&h.indexOf('#')!==0&&h.indexOf('javascript:')!==0){"
        + "    ev.preventDefault();"
        + "    if(window.HeavenExtNative)window.HeavenExtNative.createTab('"
        + extId
        + "',a.href||h);"
        + "  }"
        + "},true);"
        + "var origFetch=window.fetch;"
        + "if(origFetch&&location.hostname==='"
        + EXT_VIRTUAL_HOST
        + "'){"
        + "  window.fetch=function(input,init){"
        + "    var u=typeof input==='string'?input:(input&&input.url?input.url:'');"
        + "    if(u&&u.indexOf('chrome-extension://')===0){"
        + "      u='https://"
        + EXT_VIRTUAL_HOST
        + "/'+u.slice('chrome-extension://'.length);"
        + "      input=u;"
        + "    }"
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
        + "var IS_BG=(location.pathname.indexOf('"
        + BG_HOST_PATH
        + "')!==-1);"
        + "var BASE='https://"
        + EXT_VIRTUAL_HOST
        + "/'+EXT_ID+'/';"
        + "var store={};try{store="
        + storageSnap.toString()
        + ";}catch(e){store={};}"
        + "function syncReadStore(){"
        + "  try{"
        + "    if(window.HeavenExtNative&&window.HeavenExtNative.getStorageJson){"
        + "      var raw=window.HeavenExtNative.getStorageJson(EXT_ID);"
        + "      if(raw)store=JSON.parse(raw);"
        + "    }"
        + "  }catch(e){}"
        + "}"
        + "syncReadStore();"
        + "var manifest={};try{manifest="
        + manifestRaw
        + ";}catch(e){manifest={};}"
        + "var i18nMap={};try{i18nMap="
        + messagesRaw
        + ";}catch(e){i18nMap={};}"
        + "function getLiveTargetTab(){"
        + "  if(location.hostname==='"
        + EXT_VIRTUAL_HOST
        + "'){"
        + "    try{"
        + "      if(window.HeavenExtNative&&window.HeavenExtNative.getTargetTabJson){"
        + "        return JSON.parse(window.HeavenExtNative.getTargetTabJson());"
        + "      }"
        + "    }catch(e){}"
        + "    return {id:1,index:0,windowId:1,active:true,highlighted:true,pinned:false,status:'complete',url:"
        + JSONObject.quote(safeTabUrl)
        + ",title:"
        + JSONObject.quote(safeTabTitle)
        + "};"
        + "  }"
        + "  return {id:1,index:0,windowId:1,active:true,highlighted:true,pinned:false,status:'complete',url:location.href,title:document.title||'Tab'};"
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
        + "      syncReadStore();"
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
        + "        try{if(window.HeavenExtNative)window.HeavenExtNative.patchStorage(EXT_ID,JSON.stringify({op:'set',items:items}));}catch(e){}"
        + "        onStorageChanged._emit(changes,areaName);"
        + "      }"
        + "      if(typeof cb==='function')setTimeout(cb,0);"
        + "      return Promise.resolve();"
        + "    },"
        + "    remove:function(keys,cb){"
        + "      var arr=Array.isArray(keys)?keys:[String(keys)];"
        + "      var changes={};"
        + "      for(var i=0;i<arr.length;i++){var k=arr[i];if(k in store){changes[k]={oldValue:store[k]};delete store[k];}}"
        + "      try{if(window.HeavenExtNative)window.HeavenExtNative.patchStorage(EXT_ID,JSON.stringify({op:'remove',keys:arr}));}catch(e){}"
        + "      onStorageChanged._emit(changes,areaName);"
        + "      if(typeof cb==='function')setTimeout(cb,0);"
        + "      return Promise.resolve();"
        + "    },"
        + "    clear:function(cb){"
        + "      store={};"
        + "      try{if(window.HeavenExtNative)window.HeavenExtNative.patchStorage(EXT_ID,JSON.stringify({op:'clear'}));}catch(e){}"
        + "      if(typeof cb==='function')setTimeout(cb,0);"
        + "      return Promise.resolve();"
        + "    },"
        + "    getBytesInUse:function(k,cb){if(typeof cb==='function')setTimeout(function(){cb(0);},0);return Promise.resolve(0);},"
        + "    onChanged:onStorageChanged"
        + "  };"
        + "}"
        + "var pendingRuntimeReq={};var reqSeq=1;"
        + "window.__hbExtRuntimeReply=window.__hbExtRuntimeReply||function(eid,rid,jsonStr){"
        + "  var rt=window.__hbExtRuntimes&&window.__hbExtRuntimes[eid];"
        + "  if(rt&&rt.__resolveReq)rt.__resolveReq(rid,jsonStr);"
        + "};"
        + "window.__hbExtDeliverMessage=window.__hbExtDeliverMessage||function(eid,msg){"
        + "  var rt=window.__hbExtRuntimes&&window.__hbExtRuntimes[eid];"
        + "  if(rt&&rt.runtime&&rt.runtime.onMessage)rt.runtime.onMessage._emit(msg,{id:eid},function(){});"
        + "};"
        + "window.__hbExtDeliverTabMsg=window.__hbExtDeliverTabMsg||function(eid,rid,callerWv,msg){"
        + "  var rt=window.__hbExtRuntimes&&window.__hbExtRuntimes[eid];"
        + "  var replied=false;"
        + "  function sendResp(val){"
        + "    if(replied)return;replied=true;"
        + "    var s='{}';try{s=JSON.stringify(val===undefined?{}:val);}catch(e){}"
        + "    if(window.HeavenExtNative)window.HeavenExtNative.replyTabMessage(eid,rid,callerWv,s);"
        + "  }"
        + "  if(!rt||!rt.runtime||!rt.runtime.onMessage||!rt.runtime.onMessage.hasListeners()){sendResp({});return;}"
        + "  var ls=rt.runtime.onMessage._listeners||[];var asyncHold=false;"
        + "  for(var i=0;i<ls.length;i++){"
        + "    try{"
        + "      var r=ls[i](msg,{id:eid},sendResp);"
        + "      if(r===true)asyncHold=true;"
        + "      else if(r&&typeof r.then==='function'){asyncHold=true;r.then(sendResp).catch(function(){sendResp({});});}"
        + "    }catch(e){}"
        + "  }"
        + "  if(!asyncHold)setTimeout(function(){sendResp({});},30);"
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
        + "      var msg=(a.length>1&&typeof a[0]==='string')?a[1]:a[0];"
        + "      return new Promise(function(resolve){"
        + "        var settled=false;"
        + "        function finish(val){if(settled)return;settled=true;if(cb)try{cb(val);}catch(e){}resolve(val);}"
        + "        if(!IS_BG&&onRuntimeMsg.hasListeners()){"
        + "          var ls=onRuntimeMsg._listeners||[];"
        + "          for(var i=0;i<ls.length;i++){try{var lr=ls[i](msg,{id:EXT_ID,tab:getLiveTargetTab()},finish);if(lr&&typeof lr.then==='function')lr.then(finish);}catch(e){}}"
        + "        }"
        + "        if(window.HeavenExtNative&&window.HeavenExtNative.sendRuntimeMessage){"
        + "          var rid='r_'+(reqSeq++)+'_'+Date.now();"
        + "          pendingRuntimeReq[rid]=finish;"
        + "          var mStr='{}';try{mStr=JSON.stringify(msg===undefined?{}:msg);}catch(e){}"
        + "          window.HeavenExtNative.sendRuntimeMessage(EXT_ID,rid,mStr,location.href,IS_BG);"
        + "          setTimeout(function(){if(pendingRuntimeReq[rid]){delete pendingRuntimeReq[rid];finish({});}},2400);"
        + "        }else{finish({});}"
        + "      });"
        + "    },"
        + "    connect:function(extOrInfo,maybeInfo){"
        + "      var info=(typeof extOrInfo==='object'&&extOrInfo)?extOrInfo:(maybeInfo||{});"
        + "      var portMsg=mkEvt();var portDisc=mkEvt();"
        + "      var port={name:(info&&info.name)||'',sender:{id:EXT_ID,tab:getLiveTargetTab()},onMessage:portMsg,onDisconnect:portDisc,"
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
        + "      if(op&&window.HeavenExtNative)window.HeavenExtNative.createTab(EXT_ID,BASE+String(op).replace(/^\\/+/,''));"
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
        + "    query:function(q,cb){var list=[getLiveTargetTab()];if(typeof cb==='function')setTimeout(function(){cb(list);},0);return Promise.resolve(list);},"
        + "    getCurrent:function(cb){var t=getLiveTargetTab();if(typeof cb==='function')setTimeout(function(){cb(t);},0);return Promise.resolve(t);},"
        + "    get:function(id,cb){var t=getLiveTargetTab();if(typeof cb==='function')setTimeout(function(){cb(t);},0);return Promise.resolve(t);},"
        + "    create:function(props,cb){var t=getLiveTargetTab();if(props&&props.url&&window.HeavenExtNative)window.HeavenExtNative.createTab(EXT_ID,String(props.url));if(typeof cb==='function')setTimeout(function(){cb(t);},0);return Promise.resolve(t);},"
        + "    update:function(id,props,cb){var p=(typeof id==='object')?id:props;var t=getLiveTargetTab();if(p&&p.url&&window.HeavenExtNative)window.HeavenExtNative.updateTab(EXT_ID,String(p.url));var fn=typeof cb==='function'?cb:(typeof props==='function'?props:null);if(fn)setTimeout(function(){fn(t);},0);return Promise.resolve(t);},"
        + "    reload:function(id,props,cb){if(window.HeavenExtNative)window.HeavenExtNative.reloadTab();var fn=typeof cb==='function'?cb:(typeof props==='function'?props:(typeof id==='function'?id:null));if(fn)setTimeout(fn,0);return Promise.resolve();},"
        + "    sendMessage:function(tabId,msg,opts,cb){"
        + "      var fn=typeof cb==='function'?cb:(typeof opts==='function'?opts:null);"
        + "      return new Promise(function(resolve){"
        + "        function finish(val){if(fn)try{fn(val);}catch(e){}resolve(val);}"
        + "        if(window.HeavenExtNative&&window.HeavenExtNative.sendTabMessage){"
        + "          var rid='tr_'+(reqSeq++)+'_'+Date.now();"
        + "          pendingRuntimeReq[rid]=finish;"
        + "          var mStr='{}';try{mStr=JSON.stringify(msg===undefined?{}:msg);}catch(e){}"
        + "          window.HeavenExtNative.sendTabMessage(EXT_ID,rid,mStr);"
        + "          setTimeout(function(){if(pendingRuntimeReq[rid]){delete pendingRuntimeReq[rid];finish({});}},2200);"
        + "        }else{finish({});}"
        + "      });"
        + "    },"
        + "    executeScript:function(tabId,details,cb){"
        + "      var det=(typeof tabId==='object')?tabId:details;"
        + "      var fn=typeof cb==='function'?cb:(typeof details==='function'?details:null);"
        + "      if(det&&window.HeavenExtNative)window.HeavenExtNative.executeScript(EXT_ID,JSON.stringify({files:det.file?[det.file]:[],code:det.code||''}));"
        + "      if(fn)setTimeout(function(){fn([null]);},20);"
        + "      return Promise.resolve([null]);"
        + "    },"
        + "    insertCSS:function(tabId,details,cb){"
        + "      var det=(typeof tabId==='object')?tabId:details;"
        + "      if(det&&window.HeavenExtNative)window.HeavenExtNative.insertCss(EXT_ID,JSON.stringify({css:det.code||'',files:det.file?[det.file]:[]}));"
        + "      var fn=typeof cb==='function'?cb:(typeof details==='function'?details:null);"
        + "      if(fn)setTimeout(fn,10);"
        + "      return Promise.resolve();"
        + "    },"
        + "    onUpdated:mkEvt(),onActivated:mkEvt(),onRemoved:mkEvt(),onCreated:mkEvt()"
        + "  },"
        + "  windows:{WINDOW_ID_CURRENT:-2,getCurrent:function(o,cb){var t=getLiveTargetTab();var w={id:1,focused:true,type:'normal',state:'maximized',tabs:[t]};var fn=typeof o==='function'?o:cb;if(fn)setTimeout(function(){fn(w);},0);return Promise.resolve(w);},getAll:function(o,cb){var t=getLiveTargetTab();var ws=[{id:1,focused:true,tabs:[t]}];var fn=typeof o==='function'?o:cb;if(fn)setTimeout(function(){fn(ws);},0);return Promise.resolve(ws);},onFocusChanged:mkEvt()},"
        + "  scripting:{"
        + "    executeScript:function(inj,cb){"
        + "      var payload={files:(inj&&inj.files)||[],funcSource:(inj&&typeof inj.func==='function')?inj.func.toString():'',argsJson:JSON.stringify((inj&&inj.args)||[])};"
        + "      if(window.HeavenExtNative)window.HeavenExtNative.executeScript(EXT_ID,JSON.stringify(payload));"
        + "      var r=[{frameId:0,result:null}];if(typeof cb==='function')setTimeout(function(){cb(r);},20);return Promise.resolve(r);"
        + "    },"
        + "    insertCSS:function(inj,cb){if(inj&&window.HeavenExtNative)window.HeavenExtNative.insertCss(EXT_ID,JSON.stringify({css:inj.css||'',files:inj.files||[]}));if(typeof cb==='function')setTimeout(cb,10);return Promise.resolve();},"
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
    if ("<all_urls>".equals(p)
        || "*://*/*".equals(p)
        || "http://*/*".equals(p)
        || "https://*/*".equals(p)) {
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

    String name =
        resolveI18nPlaceholder(manifest.optString("name", "Chrome Extension"), localeMessages);
    String desc = resolveI18nPlaceholder(manifest.optString("description", ""), localeMessages);
    String version = manifest.optString("version", "1.0.0");
    int manifestVersion = manifest.optInt("manifest_version", 3);

    String popupPath = normalizeSingleRelPath(extractPopupPath(manifest));
    String popupUrl =
        !popupPath.isEmpty()
            ? ("https://" + EXT_VIRTUAL_HOST + "/" + extId + "/" + popupPath)
            : "";

    String optionsPath = normalizeSingleRelPath(extractOptionsPath(manifest));
    String optionsUrl =
        !optionsPath.isEmpty()
            ? ("https://" + EXT_VIRTUAL_HOST + "/" + extId + "/" + optionsPath)
            : "";

    String iconRel = normalizeSingleRelPath(extractBestIconPath(manifest));
    String iconBase64 = "";
    if (!iconRel.isEmpty()) {
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
            "exclude_matches_ignored", false);
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
    String extId = obj.optString("id", "");
    String popupUrl = obj.optString("popupUrl", "");
    String optionsUrl = obj.optString("optionsUrl", "");
    String launchUrl =
        !popupUrl.isEmpty()
            ? popupUrl
            : (!optionsUrl.isEmpty()
                ? optionsUrl
                : ("https://" + EXT_VIRTUAL_HOST + "/" + extId + EXT_HOME_PATH));

    m.put("id", extId);
    m.put("name", obj.optString("name", "Chrome Extension"));
    m.put("description", obj.optString("description", ""));
    m.put("version", obj.optString("version", "1.0"));
    m.put("manifestVersion", obj.optInt("manifestVersion", 3));
    m.put("enabled", obj.optBoolean("enabled", true));
    m.put("source", obj.optString("source", "webstore"));
    m.put("popupPath", obj.optString("popupPath", ""));
    m.put("popupUrl", popupUrl);
    m.put("optionsPath", obj.optString("optionsPath", ""));
    m.put("optionsUrl", optionsUrl);
    m.put("launchUrl", launchUrl);
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
