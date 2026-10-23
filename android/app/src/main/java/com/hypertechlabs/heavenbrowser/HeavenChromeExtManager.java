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
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
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
 * unpacked MV2/MV3 bundles) inside Android WebView with a chrome.* WebExtension API polyfill and
 * https://chrome-ext.heaven.local/<extId>/... virtual origin serving.
 */
public final class HeavenChromeExtManager {

  public static final String EXT_VIRTUAL_HOST = "chrome-ext.heaven.local";
  private static final String REGISTRY_FILE = "registry.json";
  private static final String STORAGE_FILE = "__heaven_storage.json";
  private static final String POLYFILL_PATH = "/__heaven_chrome_polyfill.js";
  private static final Pattern EXT_ID_PATTERN = Pattern.compile("([a-p]{32})");

  private final Context appContext;
  private final File rootDir;
  private final ExecutorService ioPool = Executors.newCachedThreadPool();
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final Object lock = new Object();

  private JSONArray registryArray = new JSONArray();

  public HeavenChromeExtManager(Context context) {
    this.appContext = context.getApplicationContext();
    this.rootDir = new File(this.appContext.getFilesDir(), "chrome_extensions");
    if (!this.rootDir.exists()) {
      //noinspection ResultOfMethodCallIgnored
      this.rootDir.mkdirs();
    }
    loadRegistry();
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
        || clean.contains("clients2.google.com/service/update2/crx")) {
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
    synchronized (lock) {
      for (int i = 0; i < registryArray.length(); i++) {
        JSONObject item = registryArray.optJSONObject(i);
        if (item != null && extId.equals(item.optString("id"))) {
          try {
            item.put("enabled", enabled);
            saveRegistryLocked();
            return true;
          } catch (Throwable ignored) {
            return false;
          }
        }
      }
    }
    return false;
  }

  public boolean uninstallExtension(String extId) {
    synchronized (lock) {
      JSONArray updated = new JSONArray();
      boolean removed = false;
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
      return removed;
    }
  }

  public void updateExtensionStorage(String extId, String patchJson) {
    if (extId == null || extId.isEmpty() || patchJson == null) {
      return;
    }
    synchronized (lock) {
      File extDir = new File(rootDir, sanitizeId(extId));
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
        if ("clear".equals(op)) {
          current = new JSONObject();
        } else if ("remove".equals(op)) {
          JSONArray keys = patch.optJSONArray("keys");
          if (keys != null) {
            for (int i = 0; i < keys.length(); i++) {
              current.remove(keys.optString(i));
            }
          }
        } else {
          JSONObject items = patch.optJSONObject("items");
          if (items != null) {
            Iterator<String> it = items.keys();
            while (it.hasNext()) {
              String k = it.next();
              current.put(k, items.opt(k));
            }
          }
        }
        try (FileOutputStream fos = new FileOutputStream(storeFile, false)) {
          fos.write(current.toString().getBytes(StandardCharsets.UTF_8));
        }
      } catch (Throwable ignored) {
      }
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
   * so extension popups, icons, ES modules, CSS, and web_accessible_resources run with a genuine
   * HTTPS origin inside WebView.
   */
  public WebResourceResponse interceptExtensionRequest(Uri uri, String activeTabUrl, String activeTabTitle) {
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
      String js = buildChromeApiPolyfillJs(extId, extDir, activeTabUrl, activeTabTitle);
      return buildTextResponse("application/javascript", 200, js);
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
          patched =
              html.substring(0, headIdx + 6) + polyfillTag + html.substring(headIdx + 6);
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

  /**
   * Builds the combined JS + CSS bundle for all enabled Desktop Chrome Extensions whose manifest
   * content_scripts match the given page URL.
   */
  public String buildContentScriptsBundleForUrl(String pageUrl) {
    if (pageUrl == null
        || (!pageUrl.startsWith("http://") && !pageUrl.startsWith("https://"))
        || pageUrl.contains(EXT_VIRTUAL_HOST)) {
      return "";
    }

    StringBuilder bundle = new StringBuilder();
    synchronized (lock) {
      for (int i = 0; i < registryArray.length(); i++) {
        JSONObject extMeta = registryArray.optJSONObject(i);
        if (extMeta == null || !extMeta.optBoolean("enabled", true)) {
          continue;
        }
        String extId = extMeta.optString("id", "");
        File extDir = new File(rootDir, sanitizeId(extId));
        if (!extDir.isDirectory()) {
          continue;
        }
        JSONArray csList = extMeta.optJSONArray("contentScripts");
        if (csList == null || csList.length() == 0) {
          continue;
        }

        boolean polyfillEmittedForExt = false;
        for (int c = 0; c < csList.length(); c++) {
          JSONObject cs = csList.optJSONObject(c);
          if (cs == null || !doesContentScriptMatch(cs, pageUrl)) {
            continue;
          }

          if (!polyfillEmittedForExt) {
            polyfillEmittedForExt = true;
            bundle
                .append("\n;(function(){\n")
                .append(buildChromeApiPolyfillJs(extId, extDir, pageUrl, ""))
                .append("\n");
          }

          JSONArray cssFiles = cs.optJSONArray("css");
          if (cssFiles != null) {
            for (int k = 0; k < cssFiles.length(); k++) {
              String cssRel = cssFiles.optString(k, "");
              String cssContent = safeReadAssetUtf8(extDir, cssRel);
              if (!cssContent.isEmpty()) {
                String styleId = "hb-crx-css-" + extId + "-" + c + "-" + k;
                bundle
                    .append("if(!document.getElementById('")
                    .append(styleId)
                    .append("')){var st=document.createElement('style');st.id='")
                    .append(styleId)
                    .append("';st.textContent=")
                    .append(JSONObject.quote(cssContent))
                    .append(";(document.head||document.documentElement).appendChild(st);}\n");
              }
            }
          }

          JSONArray jsFiles = cs.optJSONArray("js");
          if (jsFiles != null) {
            for (int k = 0; k < jsFiles.length(); k++) {
              String jsRel = jsFiles.optString(k, "");
              String jsContent = safeReadAssetUtf8(extDir, jsRel);
              if (!jsContent.isEmpty()) {
                String guardKey = "__hb_crx_ran_" + extId + "_" + c + "_" + k;
                bundle
                    .append("if(!window['")
                    .append(guardKey)
                    .append("']){window['")
                    .append(guardKey)
                    .append("']=true;try{\n")
                    .append(jsContent)
                    .append("\n}catch(e){}}\n");
              }
            }
          }
        }
        if (polyfillEmittedForExt) {
          bundle.append("})();\n");
        }
      }
    }
    return bundle.toString();
  }

  private String buildChromeApiPolyfillJs(
      String extId, File extDir, String activeTabUrl, String activeTabTitle) {
    String manifestJson = "{}";
    String messagesJson = "{}";
    String storageJson = "{}";
    synchronized (lock) {
      File mf = new File(extDir, "manifest.json");
      if (mf.isFile()) {
        try {
          manifestJson = readUtf8File(mf);
        } catch (Throwable ignored) {
        }
      }
      messagesJson = loadLocaleMessagesRawJson(extDir);
      storageJson = readExtensionStorageLocked(extDir).toString();
    }

    String baseOrigin = "https://" + EXT_VIRTUAL_HOST + "/" + extId + "/";
    String safeTabUrl = activeTabUrl != null ? activeTabUrl : "https://www.google.com";
    String safeTabTitle = activeTabTitle != null ? activeTabTitle : "Heaven Tab";

    return "var __hbExtId="
        + JSONObject.quote(extId)
        + ";var __hbBase="
        + JSONObject.quote(baseOrigin)
        + ";var __hbManifest="
        + manifestJson
        + ";var __hbMsgs="
        + messagesJson
        + ";var __hbStore="
        + storageJson
        + ";(function(){"
        + "function makeEvent(){var ls=[];return{addListener:function(fn){if(typeof fn==='function')ls.push(fn);},"
        + "removeListener:function(fn){var i=ls.indexOf(fn);if(i>=0)ls.splice(i,1);},"
        + "hasListener:function(fn){return ls.indexOf(fn)>=0;},"
        + "_emit:function(){var a=arguments;for(var i=0;i<ls.length;i++){try{ls[i].apply(null,a);}catch(e){}}}}}"
        + "var onChangedEv=makeEvent();var onMsgEv=makeEvent();"
        + "function persist(op,payload){try{if(window.HeavenChromeExtChannel){"
        + "window.HeavenChromeExtChannel.postMessage(JSON.stringify({extId:__hbExtId,op:op,data:payload}));"
        + "}}catch(e){}}"
        + "function makeStorageArea(){"
        + "  return{"
        + "    get:function(keys,cb){"
        + "      var res={};"
        + "      if(keys===null||keys===undefined){for(var k in __hbStore)res[k]=__hbStore[k];}"
        + "      else if(typeof keys==='string'){if(keys in __hbStore)res[keys]=__hbStore[keys];}"
        + "      else if(Array.isArray(keys)){for(var i=0;i<keys.length;i++){var key=keys[i];if(key in __hbStore)res[key]=__hbStore[key];}}"
        + "      else if(typeof keys==='object'){for(var dk in keys){res[dk]=(dk in __hbStore)?__hbStore[dk]:keys[dk];}}"
        + "      if(typeof cb==='function')setTimeout(function(){cb(res);},0);"
        + "      return Promise.resolve(res);"
        + "    },"
        + "    set:function(items,cb){"
        + "      var changes={};"
        + "      if(items&&typeof items==='object'){"
        + "        for(var k in items){changes[k]={oldValue:__hbStore[k],newValue:items[k]};__hbStore[k]=items[k];}"
        + "        persist('storage_set',{op:'set',items:items});"
        + "        onChangedEv._emit(changes,'local');"
        + "      }"
        + "      if(typeof cb==='function')setTimeout(cb,0);"
        + "      return Promise.resolve();"
        + "    },"
        + "    remove:function(keys,cb){"
        + "      var arr=Array.isArray(keys)?keys:[keys];"
        + "      for(var i=0;i<arr.length;i++)delete __hbStore[arr[i]];"
        + "      persist('storage_set',{op:'remove',keys:arr});"
        + "      if(typeof cb==='function')setTimeout(cb,0);"
        + "      return Promise.resolve();"
        + "    },"
        + "    clear:function(cb){"
        + "      __hbStore={};persist('storage_set',{op:'clear'});"
        + "      if(typeof cb==='function')setTimeout(cb,0);"
        + "      return Promise.resolve();"
        + "    },"
        + "    onChanged:onChangedEv"
        + "  };"
        + "}"
        + "var area=makeStorageArea();"
        + "var chromeObj={"
        + "  runtime:{"
        + "    id:__hbExtId,"
        + "    lastError:undefined,"
        + "    getManifest:function(){return __hbManifest;},"
        + "    getURL:function(p){var clean=String(p||'').replace(/^\\/+/, '');return __hbBase+clean;},"
        + "    sendMessage:function(msg,cb){"
        + "      persist('runtime_msg',msg);"
        + "      onMsgEv._emit(msg,{id:__hbExtId},function(r){if(typeof cb==='function')cb(r);});"
        + "      if(typeof cb==='function')setTimeout(function(){cb({});},0);"
        + "      return Promise.resolve({});"
        + "    },"
        + "    onMessage:onMsgEv,"
        + "    onInstalled:makeEvent(),"
        + "    onStartup:makeEvent(),"
        + "    connect:function(){return{postMessage:function(){},disconnect:function(){},onMessage:makeEvent(),onDisconnect:makeEvent()};}"
        + "  },"
        + "  storage:{local:area,sync:area,session:area,onChanged:onChangedEv},"
        + "  i18n:{"
        + "    getUILanguage:function(){return navigator.language||'en';},"
        + "    getMessage:function(name,subs){"
        + "      var entry=__hbMsgs[name]||__hbMsgs[String(name||'').toLowerCase()];"
        + "      if(!entry||!entry.message)return '';"
        + "      var msg=String(entry.message);"
        + "      if(subs){var arr=Array.isArray(subs)?subs:[subs];for(var i=0;i<arr.length;i++){msg=msg.replace('$'+(i+1),String(arr[i]));}}"
        + "      return msg;"
        + "    }"
        + "  },"
        + "  tabs:{"
        + "    query:function(q,cb){"
        + "      var t=[{id:1,active:true,currentWindow:true,url:"
        + JSONObject.quote(safeTabUrl)
        + ",title:"
        + JSONObject.quote(safeTabTitle)
        + "}];"
        + "      if(typeof cb==='function')setTimeout(function(){cb(t);},0);"
        + "      return Promise.resolve(t);"
        + "    },"
        + "    create:function(props,cb){"
        + "      if(props&&props.url)persist('open_tab',{url:props.url});"
        + "      if(typeof cb==='function')setTimeout(function(){cb({id:2});},0);"
        + "      return Promise.resolve({id:2});"
        + "    },"
        + "    sendMessage:function(tabId,msg,cb){"
        + "      persist('tab_msg',{msg:msg});"
        + "      if(typeof cb==='function')setTimeout(function(){cb({});},0);"
        + "      return Promise.resolve({});"
        + "    },"
        + "    onUpdated:makeEvent(),onActivated:makeEvent()"
        + "  },"
        + "  scripting:{"
        + "    executeScript:function(inj){"
        + "      if(inj&&inj.func)persist('exec_js',{code:'('+inj.func.toString()+')()'});"
        + "      return Promise.resolve([{result:true}]);"
        + "    },"
        + "    insertCSS:function(inj){"
        + "      if(inj&&inj.css)persist('insert_css',{css:inj.css});"
        + "      return Promise.resolve();"
        + "    }"
        + "  },"
        + "  action:{setBadgeText:function(){},setBadgeBackgroundColor:function(){},setIcon:function(){}},"
        + "  browserAction:{setBadgeText:function(){},setBadgeBackgroundColor:function(){},setIcon:function(){}},"
        + "  permissions:{contains:function(_,cb){if(cb)cb(true);return Promise.resolve(true);},request:function(_,cb){if(cb)cb(true);return Promise.resolve(true);}}"
        + "};"
        + "if(!window.chrome||!window.chrome.storage){window.chrome=Object.assign(window.chrome||{},chromeObj);}"
        + "if(!window.browser){window.browser=window.chrome;}"
        + "})();";
  }

  private Map<String, Object> unpackAndRegisterPackage(
      String extId, byte[] rawBytes, String source) throws Exception {
    int zipOffset = locateZipOffset(rawBytes);
    if (zipOffset < 0 || zipOffset >= rawBytes.length) {
      throw new IOException("Package is neither a valid Chrome .crx nor a .zip archive");
    }

    String cleanId = sanitizeId(extId);
    File extDir = new File(rootDir, cleanId);
    if (extDir.exists()) {
      deleteRecursively(extDir);
    }
    if (!extDir.mkdirs() && !extDir.isDirectory()) {
      throw new IOException("Could not create extension directory");
    }

    String canonicalRoot = extDir.getCanonicalPath() + File.separator;
    int extractedFiles = 0;

    try (ZipInputStream zis =
        new ZipInputStream(
            new ByteArrayInputStream(rawBytes, zipOffset, rawBytes.length - zipOffset))) {
      ZipEntry entry;
      byte[] buf = new byte[16384];
      while ((entry = zis.getNextEntry()) != null) {
        String name = entry.getName();
        if (name == null || name.isEmpty()) {
          continue;
        }
        File outFile = new File(extDir, name);
        String canonicalOut = outFile.getCanonicalPath();
        if (!canonicalOut.startsWith(canonicalRoot)) {
          continue; // Prevent Zip-Slip traversal
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
          extractedFiles++;
        }
        zis.closeEntry();
      }
    }

    File manifestFile = new File(extDir, "manifest.json");
    // Handle ZIPs wrapped in a single top-level folder
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

    if (!manifestFile.isFile() || extractedFiles == 0) {
      deleteRecursively(extDir);
      throw new IOException("Archive does not contain a Chrome Extension manifest.json");
    }

    JSONObject manifest = new JSONObject(readUtf8File(manifestFile));
    JSONObject localeMessages = new JSONObject(loadLocaleMessagesRawJson(extDir));

    String rawName = manifest.optString("name", "Chrome Extension");
    String rawDesc = manifest.optString("description", "Desktop Chrome Extension");
    String resolvedName = resolveI18nPlaceholder(rawName, localeMessages);
    String resolvedDesc = resolveI18nPlaceholder(rawDesc, localeMessages);
    String version = manifest.optString("version", "1.0");
    int manifestVersion = manifest.optInt("manifest_version", 3);

    String popupRel = extractPopupPath(manifest);
    String iconBase64 = extractBestIconBase64(extDir, manifest);
    JSONArray normalizedContentScripts = extractContentScripts(manifest);
    JSONArray permissions = extractPermissionsList(manifest);

    JSONObject record = new JSONObject();
    record.put("id", cleanId);
    record.put("name", resolvedName);
    record.put("description", resolvedDesc);
    record.put("version", version);
    record.put("manifestVersion", manifestVersion);
    record.put("enabled", true);
    record.put("source", source);
    record.put("popupPath", popupRel);
    record.put(
        "popupUrl",
        popupRel.isEmpty()
            ? ""
            : ("https://" + EXT_VIRTUAL_HOST + "/" + cleanId + "/" + popupRel));
    record.put("iconBase64", iconBase64);
    record.put("contentScripts", normalizedContentScripts);
    record.put("permissions", permissions);
    record.put("installedAtMs", System.currentTimeMillis());

    synchronized (lock) {
      JSONArray updated = new JSONArray();
      updated.put(record);
      for (int i = 0; i < registryArray.length(); i++) {
        JSONObject existing = registryArray.optJSONObject(i);
        if (existing != null && !cleanId.equals(existing.optString("id"))) {
          updated.put(existing);
        }
      }
      registryArray = updated;
      saveRegistryLocked();
    }

    Map<String, Object> response = new HashMap<>();
    response.put("ok", true);
    response.put("extension", extensionJsonToSummaryMap(record));
    return response;
  }

  public static int locateZipOffset(byte[] data) {
    if (data == null || data.length < 16) {
      return -1;
    }
    // Raw ZIP magic: PK\x03\x04
    if (data[0] == 'P' && data[1] == 'K' && data[2] == 3 && data[3] == 4) {
      return 0;
    }
    // Chrome CRX magic: Cr24
    if (data[0] == 'C' && data[1] == 'r' && data[2] == '2' && data[3] == '4') {
      ByteBuffer bb = ByteBuffer.wrap(data, 4, 12).order(ByteOrder.LITTLE_ENDIAN);
      int version = bb.getInt();
      if (version == 3) {
        int headerLen = bb.getInt();
        int offset = 12 + headerLen;
        if (offset > 0 && offset + 4 <= data.length && data[offset] == 'P' && data[offset + 1] == 'K') {
          return offset;
        }
      } else if (version == 2) {
        int pubKeyLen = bb.getInt();
        int sigLen = bb.getInt();
        int offset = 16 + pubKeyLen + sigLen;
        if (offset > 0 && offset + 4 <= data.length && data[offset] == 'P' && data[offset + 1] == 'K') {
          return offset;
        }
      }
    }
    // Fallback scan within first 64 KB for PK\x03\x04
    int limit = Math.min(data.length - 4, 65536);
    for (int i = 0; i < limit; i++) {
      if (data[i] == 'P' && data[i + 1] == 'K' && data[i + 2] == 3 && data[i + 3] == 4) {
        return i;
      }
    }
    return -1;
  }

  private static boolean doesContentScriptMatch(JSONObject cs, String pageUrl) {
    JSONArray excludes = cs.optJSONArray("excludeMatches");
    if (excludes != null) {
      for (int i = 0; i < excludes.length(); i++) {
        if (matchesChromePattern(excludes.optString(i, ""), pageUrl)) {
          return false;
        }
      }
    }
    JSONArray matches = cs.optJSONArray("matches");
    if (matches == null || matches.length() == 0) {
      return false;
    }
    for (int i = 0; i < matches.length(); i++) {
      if (matchesChromePattern(matches.optString(i, ""), pageUrl)) {
        return true;
      }
    }
    return false;
  }

  public static boolean matchesChromePattern(String pattern, String url) {
    if (pattern == null || pattern.isEmpty() || url == null || url.isEmpty()) {
      return false;
    }
    String p = pattern.trim();
    if ("<all_urls>".equals(p) || "*://*/*".equals(p) || "*".equals(p)) {
      return url.startsWith("http://") || url.startsWith("https://");
    }
    try {
      Uri u = Uri.parse(url);
      String uScheme = u.getScheme() != null ? u.getScheme().toLowerCase(Locale.US) : "";
      String uHost = u.getHost() != null ? u.getHost().toLowerCase(Locale.US) : "";
      String uPath = u.getEncodedPath() != null && !u.getEncodedPath().isEmpty() ? u.getEncodedPath() : "/";
      if (u.getEncodedQuery() != null && !u.getEncodedQuery().isEmpty()) {
        uPath = uPath + "?" + u.getEncodedQuery();
      }

      int schemeSep = p.indexOf("://");
      if (schemeSep < 0) {
        // Domain suffix shorthand
        String cleanDom = p.toLowerCase(Locale.US);
        return uHost.equals(cleanDom) || uHost.endsWith("." + cleanDom);
      }

      String pScheme = p.substring(0, schemeSep).toLowerCase(Locale.US);
      if (!"*".equals(pScheme) && !pScheme.equals(uScheme)) {
        return false;
      }

      String rest = p.substring(schemeSep + 3);
      int slashIdx = rest.indexOf('/');
      String pHost = (slashIdx >= 0 ? rest.substring(0, slashIdx) : rest).toLowerCase(Locale.US);
      String pPath = slashIdx >= 0 ? rest.substring(slashIdx) : "/*";

      if (!"*".equals(pHost)) {
        if (pHost.startsWith("*.")) {
          String baseDom = pHost.substring(2);
          if (!uHost.equals(baseDom) && !uHost.endsWith("." + baseDom)) {
            return false;
          }
        } else if (!uHost.equals(pHost)) {
          return false;
        }
      }

      if ("/*".equals(pPath) || "*".equals(pPath)) {
        return true;
      }
      String regex = wildcardToRegex(pPath);
      return Pattern.compile(regex).matcher(uPath).matches();
    } catch (Throwable ignored) {
      return false;
    }
  }

  private static String wildcardToRegex(String glob) {
    StringBuilder sb = new StringBuilder("^");
    for (int i = 0; i < glob.length(); i++) {
      char ch = glob.charAt(i);
      if (ch == '*') {
        sb.append(".*");
      } else if ("\\.[]{}()+-?^$|".indexOf(ch) >= 0) {
        sb.append('\\').append(ch);
      } else {
        sb.append(ch);
      }
    }
    sb.append('$');
    return sb.toString();
  }

  private static String extractPopupPath(JSONObject manifest) {
    JSONObject action = manifest.optJSONObject("action");
    if (action == null) {
      action = manifest.optJSONObject("browser_action");
    }
    if (action != null) {
      String popup = action.optString("default_popup", "").trim();
      while (popup.startsWith("/") || popup.startsWith("./")) {
        popup = popup.startsWith("./") ? popup.substring(2) : popup.substring(1);
      }
      return popup;
    }
    return "";
  }

  private static String extractBestIconBase64(File extDir, JSONObject manifest) {
    JSONObject icons = manifest.optJSONObject("icons");
    String[] preferredSizes = new String[] {"128", "96", "64", "48", "32", "256", "16"};
    String chosenRel = "";
    if (icons != null) {
      for (String sz : preferredSizes) {
        String candidate = icons.optString(sz, "").trim();
        if (!candidate.isEmpty()) {
          chosenRel = candidate;
          break;
        }
      }
      if (chosenRel.isEmpty()) {
        Iterator<String> it = icons.keys();
        if (it.hasNext()) {
          chosenRel = icons.optString(it.next(), "").trim();
        }
      }
    }
    if (chosenRel.isEmpty()) {
      return "";
    }
    while (chosenRel.startsWith("/") || chosenRel.startsWith("./")) {
      chosenRel = chosenRel.startsWith("./") ? chosenRel.substring(2) : chosenRel.substring(1);
    }
    try {
      File iconFile = new File(extDir, chosenRel);
      String canonicalRoot = extDir.getCanonicalPath() + File.separator;
      if (iconFile.isFile()
          && iconFile.length() <= 512 * 1024
          && iconFile.getCanonicalPath().startsWith(canonicalRoot)) {
        byte[] bytes = readFileBytes(iconFile);
        return Base64.encodeToString(bytes, Base64.NO_WRAP);
      }
    } catch (Throwable ignored) {
    }
    return "";
  }

  private static JSONArray extractContentScripts(JSONObject manifest) {
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
      String p = arr.optString(i, "").trim();
      while (p.startsWith("/") || p.startsWith("./")) {
        p = p.startsWith("./") ? p.substring(2) : p.substring(1);
      }
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

  /**
   * 4-stage resilient Chrome Extension CRX downloader:
   * 1) Dual-stack IPv6-first Happy Eyeballs TLS socket on update.googleapis.com (bypasses
   *    /192.0.0.2 464XLAT CLAT blackholes on IPv6-only mobile carriers like Jio/Airtel 5G).
   * 2) Dual-stack IPv6-first Happy Eyeballs TLS socket on clients2.google.com.
   * 3) Underlying physical non-VPN Wi-Fi/Cellular Network binding (bypasses dead VPN tunnels).
   * 4) Offscreen Chromium WebView HTTP/3 QUIC + same-origin CDN blob fetcher fallback.
   */
  private byte[] downloadExtensionCrxMultiStage(String extId) throws Exception {
    String[] endpoints = buildCrxUpdateEndpoints(extId);
    Throwable lastError = null;

    // Stages 1 & 2: Default route with IPv6-first Happy Eyeballs + DoH DNS recovery
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

    // Stage 3: Bind directly to active physical Wi-Fi / Cellular network (bypasses broken VPN/CLAT)
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

    // Stage 4: Chromium WebView QUIC / HTTP3 same-origin clients2.googleusercontent.com fallback
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
                  String escapedUrl =
                      blobUrl.replace("\\", "\\\\").replace("'", "\\'");
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
