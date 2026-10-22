package com.hypertechlabs.heavenbrowser;

import android.app.Activity;
import android.app.DownloadManager;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.net.Uri;
import android.net.http.SslError;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.os.SystemClock;
import android.provider.Settings;
import android.speech.RecognizerIntent;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.webkit.ClientCertRequest;
import android.webkit.CookieManager;
import android.webkit.HttpAuthHandler;
import android.webkit.ServiceWorkerClient;
import android.webkit.ServiceWorkerController;
import android.webkit.SslErrorHandler;
import android.webkit.URLUtil;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public class HeavenShieldPlugin
    implements FlutterPlugin,
        ActivityAware,
        MethodChannel.MethodCallHandler,
        PluginRegistry.ActivityResultListener {

  private static final String CHANNEL_NAME = "com.hypertechlabs.heavenbrowser/native_shield";
  private static final int VOICE_SEARCH_REQUEST_CODE = 49021;

  private static final byte[] TRANSPARENT_GIF = new byte[] {
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, (byte) 0x80, 0x00,
    0x00, (byte) 0xff, (byte) 0xff, (byte) 0xff, 0x00, 0x00, 0x00, 0x21, (byte) 0xf9,
    0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3b
  };

  private static final byte[] EMPTY_JS =
      "/* Blocked by Heaven Shield */".getBytes(StandardCharsets.UTF_8);

  private static final byte[] EMPTY_HTML =
      "<!doctype html><html><head><style>html,body{display:none!important;margin:0;padding:0;}</style></head><body></body></html>"
          .getBytes(StandardCharsets.UTF_8);

  private static final byte[] EMPTY_TEXT = new byte[0];

  private static final String DESKTOP_VIEWPORT_SCRIPT =
      "(function(){"
          + "try{"
          + "Object.defineProperty(navigator,'platform',{get:()=>'Linux x86_64',configurable:true});"
          + "Object.defineProperty(navigator,'maxTouchPoints',{get:()=>0,configurable:true});"
          + "if(navigator.userAgentData){"
          + "Object.defineProperty(navigator,'userAgentData',{get:()=>({brands:[{brand:'Chromium',version:'134'}],mobile:false,platform:'Linux'}),configurable:true});"
          + "}"
          + "var m=document.querySelector('meta[name=\"viewport\"]');"
          + "if(!m){m=document.createElement('meta');m.name='viewport';if(document.head)document.head.appendChild(m);}"
          + "if(m){m.setAttribute('content','width=1280, initial-scale=0.35, minimum-scale=0.1, maximum-scale=5.0, user-scalable=yes');}"
          + "}catch(_){}"
          + "})();";

  private static final String MOBILE_VIEWPORT_RESET_SCRIPT =
      "(function(){"
          + "try{"
          + "var m=document.querySelector('meta[name=\"viewport\"]');"
          + "if(m && m.getAttribute('content') && m.getAttribute('content').indexOf('width=1280')===0){"
          + "m.setAttribute('content','width=device-width, initial-scale=1.0, user-scalable=yes');"
          + "}"
          + "}catch(_){}"
          + "})();";

  private Activity activity;
  private ActivityPluginBinding activityBinding;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private FlutterPluginBinding pluginBinding;
  private MethodChannel channel;
  private MethodChannel.Result pendingVoiceResult;

  private volatile boolean shieldEnabled = true;
  private volatile boolean desktopMode = false;
  private volatile Set<String> blockedDomains = Collections.emptySet();
  private volatile Set<String> trustedHosts = Collections.emptySet();
  private volatile String cosmeticScript = "";
  private final Map<Long, String> currentPageHosts = new ConcurrentHashMap<>();
  private boolean serviceWorkerHooked = false;

  public HeavenShieldPlugin() {}

  public HeavenShieldPlugin(Activity activity) {
    this.activity = activity;
  }

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    this.pluginBinding = binding;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    setupServiceWorkerShield();
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.pluginBinding = null;
  }

  @Override
  public void onAttachedToActivity(ActivityPluginBinding binding) {
    this.activity = binding.getActivity();
    this.activityBinding = binding;
    binding.addActivityResultListener(this);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    if (this.activityBinding != null) {
      this.activityBinding.removeActivityResultListener(this);
      this.activityBinding = null;
    }
  }

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    if (this.activityBinding != null) {
      this.activityBinding.removeActivityResultListener(this);
      this.activityBinding = null;
    }
    this.activity = null;
  }

  @Override
  public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
    if (requestCode == VOICE_SEARCH_REQUEST_CODE) {
      MethodChannel.Result callback = this.pendingVoiceResult;
      this.pendingVoiceResult = null;
      if (callback != null) {
        if (resultCode == Activity.RESULT_OK && data != null) {
          ArrayList<String> matches =
              data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS);
          if (matches != null && !matches.isEmpty() && matches.get(0) != null) {
            callback.success(matches.get(0).trim());
            return true;
          }
        }
        callback.success(null);
      }
      return true;
    }
    return false;
  }

  private Context getAppContext() {
    if (activity != null) {
      return activity.getApplicationContext();
    }
    if (pluginBinding != null) {
      return pluginBinding.getApplicationContext();
    }
    return null;
  }

  private void setupServiceWorkerShield() {
    if (serviceWorkerHooked || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
      return;
    }
    try {
      ServiceWorkerController swController = ServiceWorkerController.getInstance();
      swController.setServiceWorkerClient(
          new ServiceWorkerClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebResourceRequest request) {
              String matched = evaluateRequestBlock(request, null);
              if (matched != null) {
                notifyBlocked(-1L, matched);
                return buildSurrogateResponse(request);
              }
              return null;
            }
          });
      serviceWorkerHooked = true;
    } catch (Throwable ignored) {
    }
  }

  @Override
  @SuppressWarnings("unchecked")
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    switch (call.method) {
      case "updateConfig": {
        Boolean enabled = call.argument("shieldEnabled");
        Boolean desktop = call.argument("desktopMode");
        List<String> domains = call.argument("blockedDomains");
        List<String> trusted = call.argument("trustedHosts");
        String script = call.argument("cosmeticScript");

        if (enabled != null) {
          this.shieldEnabled = enabled;
        }
        if (desktop != null) {
          this.desktopMode = desktop;
        }
        if (domains != null) {
          Set<String> next = new HashSet<>(domains.size() * 2);
          for (String d : domains) {
            if (d != null && !d.isEmpty()) {
              next.add(d.trim().toLowerCase(Locale.US));
            }
          }
          this.blockedDomains = next;
        }
        if (trusted != null) {
          Set<String> nextTrusted = new HashSet<>(trusted.size() * 2);
          for (String t : trusted) {
            if (t != null && !t.isEmpty()) {
              nextTrusted.add(normalizeHost(t));
            }
          }
          this.trustedHosts = nextTrusted;
        }
        if (script != null) {
          this.cosmeticScript = script;
        }
        result.success(true);
        break;
      }
      case "attachToWebView": {
        Number idNum = call.argument("webViewId");
        String pageHost = call.argument("pageHost");
        Boolean desktop = call.argument("desktopMode");
        if (idNum == null || pluginBinding == null) {
          result.success(false);
          return;
        }
        long webViewId = idNum.longValue();
        if (desktop != null) {
          this.desktopMode = desktop;
        }
        if (pageHost != null && !pageHost.isEmpty()) {
          currentPageHosts.put(webViewId, normalizeHost(pageHost));
        }
        boolean attached = attachShieldClient(webViewId);
        result.success(attached);
        break;
      }
      case "applyDesktopViewport": {
        Number idNum = call.argument("webViewId");
        Boolean desktop = call.argument("desktopMode");
        if (desktop != null) {
          this.desktopMode = desktop;
        }
        if (idNum != null && pluginBinding != null) {
          WebView webView =
              WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, idNum.longValue());
          if (webView != null) {
            configureWebViewViewport(webView, this.desktopMode);
          }
        }
        result.success(true);
        break;
      }
      case "updatePageHost": {
        Number idNum = call.argument("webViewId");
        String pageHost = call.argument("pageHost");
        if (idNum != null) {
          long webViewId = idNum.longValue();
          if (pageHost == null || pageHost.isEmpty()) {
            currentPageHosts.remove(webViewId);
          } else {
            currentPageHosts.put(webViewId, normalizeHost(pageHost));
          }
        }
        result.success(true);
        break;
      }
      case "startVoiceSearch": {
        if (activity == null) {
          result.success(null);
          return;
        }
        if (pendingVoiceResult != null) {
          pendingVoiceResult.success(null);
          pendingVoiceResult = null;
        }
        try {
          Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
          intent.putExtra(
              RecognizerIntent.EXTRA_LANGUAGE_MODEL,
              RecognizerIntent.LANGUAGE_MODEL_WEB_SEARCH);
          intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
          intent.putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak to search");
          pendingVoiceResult = result;
          activity.startActivityForResult(intent, VOICE_SEARCH_REQUEST_CODE);
        } catch (ActivityNotFoundException e) {
          pendingVoiceResult = null;
          result.success("__UNAVAILABLE__");
        } catch (Throwable t) {
          pendingVoiceResult = null;
          result.success(null);
        }
        break;
      }
      case "startDownload": {
        String url = call.argument("url");
        String fileName = call.argument("fileName");
        String mimeType = call.argument("mimeType");
        String userAgent = call.argument("userAgent");
        Map<String, Object> dlInfo =
            enqueueSystemDownload(url, userAgent, null, mimeType, fileName, -1L);
        result.success(dlInfo);
        break;
      }
      case "queryDownloads": {
        List<Number> rawIds = call.argument("downloadIds");
        result.success(queryDownloadStatuses(rawIds));
        break;
      }
      case "cancelDownload": {
        Number idNum = call.argument("downloadId");
        Context ctx = getAppContext();
        if (idNum != null && ctx != null) {
          DownloadManager dm =
              (DownloadManager) ctx.getSystemService(Context.DOWNLOAD_SERVICE);
          if (dm != null) {
            dm.remove(idNum.longValue());
          }
        }
        result.success(true);
        break;
      }
      case "openDownloadedFile": {
        Number idNum = call.argument("downloadId");
        result.success(openDownloadedItem(idNum != null ? idNum.longValue() : -1L));
        break;
      }
      case "openDefaultBrowserSettings": {
        try {
          if (activity != null) {
            Intent intent = new Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity.startActivity(intent);
            result.success(true);
          } else {
            result.success(false);
          }
        } catch (Throwable t) {
          result.success(false);
        }
        break;
      }
      default:
        result.notImplemented();
        break;
    }
  }

  private void configureWebViewViewport(WebView webView, boolean desktop) {
    WebSettings ws = webView.getSettings();
    ws.setSupportZoom(true);
    ws.setBuiltInZoomControls(true);
    ws.setDisplayZoomControls(false);
    ws.setUseWideViewPort(desktop);
    ws.setLoadWithOverviewMode(desktop);
    ws.setLayoutAlgorithm(
        desktop
            ? WebSettings.LayoutAlgorithm.NORMAL
            : WebSettings.LayoutAlgorithm.TEXT_AUTOSIZING);
    webView.setInitialScale(0);
  }

  private boolean attachShieldClient(long webViewId) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || pluginBinding == null) {
      return false;
    }
    WebView webView = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, webViewId);
    if (webView == null) {
      return false;
    }
    configureWebViewViewport(webView, this.desktopMode);
    webView.getSettings().setSupportMultipleWindows(false);
    webView.getSettings().setJavaScriptCanOpenWindowsAutomatically(false);

    // Attach native DownloadListener so tapping any downloadable file starts DownloadManager
    webView.setDownloadListener(
        (String url,
            String userAgent,
            String contentDisposition,
            String mimetype,
            long contentLength) -> {
          Map<String, Object> info =
              enqueueSystemDownload(
                  url, userAgent, contentDisposition, mimetype, null, contentLength);
          if (info != null) {
            mainHandler.post(
                () -> {
                  if (channel != null) {
                    channel.invokeMethod("onDownloadStarted", info);
                  }
                });
          }
        });

    // Attach non-blocking Pull-to-Refresh gesture tracker
    attachPullToRefreshListener(webViewId, webView);

    WebViewClient existing = webView.getWebViewClient();
    if (existing instanceof ShieldWebViewClient) {
      return true;
    }
    webView.setWebViewClient(new ShieldWebViewClient(webViewId, existing));
    return true;
  }

  private void attachPullToRefreshListener(long webViewId, WebView webView) {
    final float density = webView.getResources().getDisplayMetrics().density;
    final float slopPx = 22.0f * density;
    final float triggerDistancePx = 118.0f * density;

    webView.setOnTouchListener(
        new View.OnTouchListener() {
          private float startX = 0f;
          private float startY = 0f;
          private boolean trackingTopPull = false;
          private float lastProgress = 0f;
          private long lastEmitUptime = 0L;

          @Override
          public boolean onTouch(View v, MotionEvent event) {
            int action = event.getActionMasked();
            switch (action) {
              case MotionEvent.ACTION_DOWN: {
                if (!webView.canScrollVertically(-1)
                    && webView.getScrollY() <= 2
                    && event.getPointerCount() == 1) {
                  startX = event.getX();
                  startY = event.getY();
                  trackingTopPull = true;
                  lastProgress = 0f;
                } else {
                  trackingTopPull = false;
                }
                break;
              }
              case MotionEvent.ACTION_POINTER_DOWN: {
                if (trackingTopPull && lastProgress > 0f) {
                  emitPullProgress(webViewId, 0f);
                }
                trackingTopPull = false;
                lastProgress = 0f;
                break;
              }
              case MotionEvent.ACTION_MOVE: {
                if (!trackingTopPull) {
                  break;
                }
                if (webView.canScrollVertically(-1) || event.getPointerCount() > 1) {
                  trackingTopPull = false;
                  if (lastProgress > 0f) {
                    lastProgress = 0f;
                    emitPullProgress(webViewId, 0f);
                  }
                  break;
                }
                float dy = event.getY() - startY;
                float dx = Math.abs(event.getX() - startX);
                if (dy > slopPx && dy > dx * 1.4f) {
                  float raw = (dy - slopPx) / triggerDistancePx;
                  float clamped = Math.max(0f, Math.min(1f, raw));
                  long now = SystemClock.uptimeMillis();
                  if (Math.abs(clamped - lastProgress) >= 0.04f && (now - lastEmitUptime) >= 24L) {
                    lastProgress = clamped;
                    lastEmitUptime = now;
                    emitPullProgress(webViewId, clamped);
                  }
                } else if (dy < 0 && lastProgress > 0f) {
                  lastProgress = 0f;
                  emitPullProgress(webViewId, 0f);
                }
                break;
              }
              case MotionEvent.ACTION_UP: {
                if (trackingTopPull) {
                  boolean shouldRefresh = lastProgress >= 0.96f && !webView.canScrollVertically(-1);
                  trackingTopPull = false;
                  if (lastProgress > 0f) {
                    lastProgress = 0f;
                    emitPullProgress(webViewId, 0f);
                  }
                  if (shouldRefresh) {
                    emitPullRefresh(webViewId);
                  }
                }
                break;
              }
              case MotionEvent.ACTION_CANCEL: {
                if (trackingTopPull && lastProgress > 0f) {
                  lastProgress = 0f;
                  emitPullProgress(webViewId, 0f);
                }
                trackingTopPull = false;
                break;
              }
              default:
                break;
            }
            return false;
          }
        });
  }

  private void emitPullProgress(long webViewId, float progress) {
    mainHandler.post(
        () -> {
          if (channel != null) {
            Map<String, Object> payload = new HashMap<>();
            payload.put("webViewId", webViewId);
            payload.put("progress", (double) progress);
            channel.invokeMethod("onPullProgress", payload);
          }
        });
  }

  private void emitPullRefresh(long webViewId) {
    mainHandler.post(
        () -> {
          if (channel != null) {
            Map<String, Object> payload = new HashMap<>();
            payload.put("webViewId", webViewId);
            channel.invokeMethod("onPullRefresh", payload);
          }
        });
  }

  private Map<String, Object> enqueueSystemDownload(
      String url,
      String userAgent,
      String contentDisposition,
      String mimeType,
      String explicitFileName,
      long contentLength) {
    Context ctx = getAppContext();
    if (ctx == null || url == null || url.trim().isEmpty()) {
      return null;
    }
    String trimmedUrl = url.trim();
    if (!trimmedUrl.startsWith("http://") && !trimmedUrl.startsWith("https://")) {
      return null;
    }

    try {
      DownloadManager dm = (DownloadManager) ctx.getSystemService(Context.DOWNLOAD_SERVICE);
      if (dm == null) {
        return null;
      }
      Uri uri = Uri.parse(trimmedUrl);
      String resolvedName =
          (explicitFileName != null && !explicitFileName.trim().isEmpty())
              ? explicitFileName.trim()
              : URLUtil.guessFileName(trimmedUrl, contentDisposition, mimeType);
      resolvedName = resolvedName.replaceAll("[\\\\/:*?\"<>|]", "_");

      DownloadManager.Request req = new DownloadManager.Request(uri);
      req.setTitle(resolvedName);
      req.setDescription("Downloading via Heaven Browser");
      req.setNotificationVisibility(
          DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
      req.setAllowedOverMetered(true);
      req.setAllowedOverRoaming(true);

      if (mimeType != null && !mimeType.isEmpty()) {
        req.setMimeType(mimeType);
      }
      if (userAgent != null && !userAgent.isEmpty()) {
        req.addRequestHeader("User-Agent", userAgent);
      }
      try {
        String cookie = CookieManager.getInstance().getCookie(trimmedUrl);
        if (cookie != null && !cookie.isEmpty()) {
          req.addRequestHeader("Cookie", cookie);
        }
      } catch (Throwable ignored) {
      }

      try {
        req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, resolvedName);
      } catch (Throwable fallbackErr) {
        req.setDestinationInExternalFilesDir(ctx, Environment.DIRECTORY_DOWNLOADS, resolvedName);
      }

      long downloadId = dm.enqueue(req);
      Map<String, Object> result = new HashMap<>();
      result.put("downloadId", downloadId);
      result.put("url", trimmedUrl);
      result.put("fileName", resolvedName);
      result.put("mimeType", mimeType != null ? mimeType : "");
      result.put("totalBytes", contentLength > 0 ? contentLength : -1L);
      return result;
    } catch (Throwable t) {
      return null;
    }
  }

  private List<Map<String, Object>> queryDownloadStatuses(List<Number> rawIds) {
    Context ctx = getAppContext();
    if (ctx == null || rawIds == null || rawIds.isEmpty()) {
      return Collections.emptyList();
    }
    DownloadManager dm = (DownloadManager) ctx.getSystemService(Context.DOWNLOAD_SERVICE);
    if (dm == null) {
      return Collections.emptyList();
    }

    long[] ids = new long[rawIds.size()];
    for (int i = 0; i < rawIds.size(); i++) {
      ids[i] = rawIds.get(i).longValue();
    }

    List<Map<String, Object>> items = new ArrayList<>();
    DownloadManager.Query query = new DownloadManager.Query().setFilterById(ids);
    try (Cursor cursor = dm.query(query)) {
      if (cursor == null) {
        return items;
      }
      int idxId = cursor.getColumnIndex(DownloadManager.COLUMN_ID);
      int idxStatus = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS);
      int idxDownloaded =
          cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR);
      int idxTotal = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES);
      int idxLocalUri = cursor.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI);
      int idxMime = cursor.getColumnIndex(DownloadManager.COLUMN_MEDIA_TYPE);

      while (cursor.moveToNext()) {
        Map<String, Object> row = new HashMap<>();
        long id = idxId >= 0 ? cursor.getLong(idxId) : -1L;
        int status = idxStatus >= 0 ? cursor.getInt(idxStatus) : 0;
        long downloaded = idxDownloaded >= 0 ? cursor.getLong(idxDownloaded) : 0L;
        long total = idxTotal >= 0 ? cursor.getLong(idxTotal) : -1L;
        String localUri = idxLocalUri >= 0 ? cursor.getString(idxLocalUri) : null;
        String mime = idxMime >= 0 ? cursor.getString(idxMime) : null;

        String stateStr;
        if (status == DownloadManager.STATUS_SUCCESSFUL) {
          stateStr = "completed";
        } else if (status == DownloadManager.STATUS_FAILED) {
          stateStr = "failed";
        } else if (status == DownloadManager.STATUS_PAUSED) {
          stateStr = "paused";
        } else {
          stateStr = "running";
        }

        row.put("downloadId", id);
        row.put("state", stateStr);
        row.put("bytesDownloaded", downloaded);
        row.put("totalBytes", total);
        row.put("localUri", localUri != null ? localUri : "");
        row.put("mimeType", mime != null ? mime : "");
        items.add(row);
      }
    } catch (Throwable ignored) {
    }
    return items;
  }

  private boolean openDownloadedItem(long downloadId) {
    Context ctx = getAppContext();
    if (ctx == null || downloadId < 0) {
      return false;
    }
    try {
      DownloadManager dm = (DownloadManager) ctx.getSystemService(Context.DOWNLOAD_SERVICE);
      if (dm == null) {
        return false;
      }
      Uri contentUri = dm.getUriForDownloadedFile(downloadId);
      String mime = dm.getMimeTypeForDownloadedFile(downloadId);
      if (contentUri == null) {
        return false;
      }
      Intent openIntent = new Intent(Intent.ACTION_VIEW);
      openIntent.setDataAndType(
          contentUri, (mime != null && !mime.isEmpty()) ? mime : "*/*");
      openIntent.addFlags(
          Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION);
      ctx.startActivity(openIntent);
      return true;
    } catch (Throwable t) {
      return false;
    }
  }

  private static String normalizeHost(String host) {
    if (host == null) return "";
    String clean = host.trim().toLowerCase(Locale.US);
    if (clean.startsWith("www.") && clean.length() > 4) {
      clean = clean.substring(4);
    }
    return clean;
  }

  private static String extractRegistrableRoot(String host) {
    String clean = normalizeHost(host);
    String[] parts = clean.split("\\.");
    if (parts.length <= 2) {
      return clean;
    }
    return parts[parts.length - 2] + "." + parts[parts.length - 1];
  }

  private boolean isHostTrusted(String host) {
    if (host == null || host.isEmpty()) return false;
    Set<String> trusted = this.trustedHosts;
    if (trusted.isEmpty()) return false;
    String clean = normalizeHost(host);
    while (true) {
      if (trusted.contains(clean)) {
        return true;
      }
      int dot = clean.indexOf('.');
      if (dot < 0 || dot == clean.length() - 1) {
        break;
      }
      clean = clean.substring(dot + 1);
    }
    return false;
  }

  private String matchBlockedDomain(String host) {
    if (host == null || host.isEmpty()) return null;
    Set<String> blocked = this.blockedDomains;
    if (blocked.isEmpty()) return null;
    String clean = host.trim().toLowerCase(Locale.US);
    while (true) {
      if (blocked.contains(clean)) {
        return clean;
      }
      int dot = clean.indexOf('.');
      if (dot < 0 || dot == clean.length() - 1) {
        break;
      }
      clean = clean.substring(dot + 1);
    }
    return null;
  }

  private String evaluateRequestBlock(WebResourceRequest request, String pageHost) {
    if (!shieldEnabled || request == null) {
      return null;
    }
    Uri uri = request.getUrl();
    if (uri == null) {
      return null;
    }
    String scheme = uri.getScheme();
    if (scheme == null || (!scheme.equalsIgnoreCase("http") && !scheme.equalsIgnoreCase("https"))) {
      return null;
    }
    String reqHost = uri.getHost();
    if (reqHost == null || reqHost.isEmpty()) {
      return null;
    }
    if (isHostTrusted(pageHost) || isHostTrusted(reqHost)) {
      return null;
    }

    String matchedDomain = matchBlockedDomain(reqHost);
    if (matchedDomain != null) {
      return matchedDomain;
    }

    if (!request.isForMainFrame()) {
      String pathAndQuery =
          ((uri.getPath() != null ? uri.getPath() : "")
                  + (uri.getQuery() != null ? "?" + uri.getQuery() : ""))
              .toLowerCase(Locale.US);
      boolean thirdParty =
          pageHost != null
              && !pageHost.isEmpty()
              && !extractRegistrableRoot(reqHost).equals(extractRegistrableRoot(pageHost));

      if (pathAndQuery.contains("/adsbygoogle")
          || pathAndQuery.contains("/pagead/")
          || pathAndQuery.contains("/gpt.js")
          || pathAndQuery.contains("/pubads_impl")
          || pathAndQuery.contains("/prebid")
          || pathAndQuery.contains("/popunder")
          || (thirdParty
              && (pathAndQuery.contains("/adserver")
                  || pathAndQuery.contains("/adframe")
                  || pathAndQuery.contains("/ads/banner")
                  || pathAndQuery.contains("ad_type=video")))) {
        return normalizeHost(reqHost);
      }
    }
    return null;
  }

  private WebResourceResponse buildSurrogateResponse(WebResourceRequest request) {
    Map<String, String> headers = new HashMap<>();
    headers.put("Access-Control-Allow-Origin", "*");
    headers.put("Cache-Control", "no-store");

    String path =
        request.getUrl() != null && request.getUrl().getPath() != null
            ? request.getUrl().getPath().toLowerCase(Locale.US)
            : "";
    Map<String, String> reqHeaders = request.getRequestHeaders();
    String accept = reqHeaders != null && reqHeaders.get("Accept") != null
        ? reqHeaders.get("Accept").toLowerCase(Locale.US)
        : "";

    if (path.endsWith(".js") || accept.contains("script")) {
      return new WebResourceResponse(
          "application/javascript",
          "UTF-8",
          200,
          "OK",
          headers,
          new ByteArrayInputStream(EMPTY_JS));
    }
    if (path.endsWith(".png")
        || path.endsWith(".gif")
        || path.endsWith(".jpg")
        || path.endsWith(".jpeg")
        || path.endsWith(".webp")
        || accept.startsWith("image/")) {
      return new WebResourceResponse(
          "image/gif",
          null,
          200,
          "OK",
          headers,
          new ByteArrayInputStream(TRANSPARENT_GIF));
    }
    if (accept.contains("text/html") && !request.isForMainFrame()) {
      return new WebResourceResponse(
          "text/html",
          "UTF-8",
          200,
          "OK",
          headers,
          new ByteArrayInputStream(EMPTY_HTML));
    }
    return new WebResourceResponse(
        "text/plain",
        "UTF-8",
        204,
        "Blocked",
        headers,
        new ByteArrayInputStream(EMPTY_TEXT));
  }

  private void notifyBlocked(long webViewId, String domain) {
    mainHandler.post(
        () -> {
          if (channel != null) {
            Map<String, Object> payload = new HashMap<>();
            payload.put("webViewId", webViewId);
            payload.put("domain", domain);
            channel.invokeMethod("onResourceBlocked", payload);
          }
        });
  }

  private class ShieldWebViewClient extends WebViewClient {
    private final long webViewId;
    private final WebViewClient delegate;

    ShieldWebViewClient(long webViewId, WebViewClient delegate) {
      this.webViewId = webViewId;
      this.delegate = delegate;
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
      if (request != null && request.isForMainFrame() && request.getUrl() != null) {
        String h = request.getUrl().getHost();
        if (h != null && !h.isEmpty()) {
          currentPageHosts.put(webViewId, normalizeHost(h));
        }
      }
      String pageHost = currentPageHosts.get(webViewId);
      String matched = evaluateRequestBlock(request, pageHost);
      if (matched != null && !request.isForMainFrame()) {
        notifyBlocked(webViewId, matched);
        return buildSurrogateResponse(request);
      }
      return delegate != null ? delegate.shouldInterceptRequest(view, request) : null;
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
      if (request != null && !request.isForMainFrame()) {
        String pageHost = currentPageHosts.get(webViewId);
        String matched = evaluateRequestBlock(request, pageHost);
        if (matched != null) {
          notifyBlocked(webViewId, matched);
          return true;
        }
      }
      return delegate != null && delegate.shouldOverrideUrlLoading(view, request);
    }

    @Override
    public void onPageStarted(WebView view, String url, Bitmap favicon) {
      if (view != null) {
        configureWebViewViewport(view, desktopMode);
      }
      if (url != null) {
        Uri parsed = Uri.parse(url);
        if (parsed.getHost() != null) {
          currentPageHosts.put(webViewId, normalizeHost(parsed.getHost()));
        }
      }
      if (delegate != null) {
        delegate.onPageStarted(view, url, favicon);
      }
    }

    @Override
    public void onPageCommitVisible(WebView view, String url) {
      injectViewportAndShield(view, url);
      if (delegate != null) {
        delegate.onPageCommitVisible(view, url);
      }
    }

    @Override
    public void onPageFinished(WebView view, String url) {
      injectViewportAndShield(view, url);
      if (delegate != null) {
        delegate.onPageFinished(view, url);
      }
    }

    private void injectViewportAndShield(WebView view, String url) {
      if (view == null || url == null) {
        return;
      }
      configureWebViewViewport(view, desktopMode);
      view.evaluateJavascript(
          desktopMode ? DESKTOP_VIEWPORT_SCRIPT : MOBILE_VIEWPORT_RESET_SCRIPT, null);

      if (!shieldEnabled) {
        return;
      }
      String host = Uri.parse(url).getHost();
      if (isHostTrusted(host)) {
        return;
      }
      String script = cosmeticScript;
      if (script != null && !script.isEmpty()) {
        view.evaluateJavascript(script, null);
      }
    }

    @Override
    public void onReceivedHttpError(
        WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {
      if (delegate != null) {
        delegate.onReceivedHttpError(view, request, errorResponse);
      }
    }

    @Override
    public void onReceivedError(
        WebView view, WebResourceRequest request, WebResourceError error) {
      if (delegate != null) {
        delegate.onReceivedError(view, request, error);
      }
    }

    @Override
    public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
      if (delegate != null) {
        delegate.doUpdateVisitedHistory(view, url, isReload);
      }
    }

    @Override
    public void onReceivedHttpAuthRequest(
        WebView view, HttpAuthHandler handler, String host, String realm) {
      if (delegate != null) {
        delegate.onReceivedHttpAuthRequest(view, handler, host, realm);
      } else {
        super.onReceivedHttpAuthRequest(view, handler, host, realm);
      }
    }

    @Override
    public void onFormResubmission(WebView view, Message dontResend, Message resend) {
      if (delegate != null) {
        delegate.onFormResubmission(view, dontResend, resend);
      } else {
        super.onFormResubmission(view, dontResend, resend);
      }
    }

    @Override
    public void onLoadResource(WebView view, String url) {
      if (delegate != null) {
        delegate.onLoadResource(view, url);
      }
    }

    @Override
    public void onReceivedClientCertRequest(WebView view, ClientCertRequest request) {
      if (delegate != null) {
        delegate.onReceivedClientCertRequest(view, request);
      } else {
        super.onReceivedClientCertRequest(view, request);
      }
    }

    @Override
    public void onReceivedLoginRequest(
        WebView view, String realm, String account, String args) {
      if (delegate != null) {
        delegate.onReceivedLoginRequest(view, realm, account, args);
      }
    }

    @Override
    public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
      if (delegate != null) {
        delegate.onReceivedSslError(view, handler, error);
      } else {
        super.onReceivedSslError(view, handler, error);
      }
    }

    @Override
    public void onScaleChanged(WebView view, float oldScale, float newScale) {
      if (delegate != null) {
        delegate.onScaleChanged(view, oldScale, newScale);
      }
    }

    @Override
    public void onUnhandledKeyEvent(WebView view, KeyEvent event) {
      if (delegate != null) {
        delegate.onUnhandledKeyEvent(view, event);
      }
    }
  }
}
