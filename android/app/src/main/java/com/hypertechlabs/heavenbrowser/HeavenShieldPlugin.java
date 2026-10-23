package com.hypertechlabs.heavenbrowser;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.drawable.Icon;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.net.http.SslError;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.os.SystemClock;
import android.provider.DocumentsContract;
import android.provider.Settings;
import android.speech.RecognizerIntent;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.webkit.ClientCertRequest;
import android.webkit.CookieManager;
import android.webkit.HttpAuthHandler;
import android.webkit.MimeTypeMap;
import android.webkit.ServiceWorkerClient;
import android.webkit.ServiceWorkerController;
import android.webkit.SslErrorHandler;
import android.webkit.URLUtil;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebStorage;
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
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
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
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicLong;

public class HeavenShieldPlugin
    implements FlutterPlugin,
        ActivityAware,
        MethodChannel.MethodCallHandler,
        PluginRegistry.ActivityResultListener,
        PluginRegistry.RequestPermissionsResultListener {

  private static final String CHANNEL_NAME = "com.hypertechlabs.heavenbrowser/native_shield";
  private static final String NATIVE_PREFS_NAME = "heaven_native_prefs";
  private static final String PREF_DOWNLOAD_PATH = "custom_download_path";
  private static final String PREF_DL_NOTIFS_ENABLED = "download_notifs_enabled";
  private static final String ACTION_DOWNLOAD_CONTROL =
      "com.hypertechlabs.heavenbrowser.DOWNLOAD_CONTROL";
  private static final String NOTIF_CHANNEL_PROGRESS = "heaven_dl_progress_v5";
  private static final String NOTIF_CHANNEL_COMPLETE = "heaven_dl_complete_v5";
  private static final int VOICE_SEARCH_REQUEST_CODE = 49021;
  private static final int NOTIF_PERM_REQUEST_CODE = 49022;
  private static final int FOLDER_PICKER_REQUEST_CODE = 49025;

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

  private static final class DownloadJob {
    final long id;
    final String url;
    final String fileName;
    volatile String mimeType;
    final String userAgent;
    final String cookies;
    final String referer;
    final File targetFile;
    final File partFile;

    volatile String state = "running"; // running, paused, completed, failed, canceled
    final AtomicLong bytesDownloaded = new AtomicLong(0L);
    volatile long totalBytes = -1L;
    volatile long speedBytesPerSec = 0L;
    volatile boolean supportsRange = true;
    volatile String etag = "";
    volatile boolean pauseRequested = false;
    volatile boolean cancelRequested = false;
    volatile HttpURLConnection activeConn;
    volatile InputStream activeStream;

    DownloadJob(
        long id,
        String url,
        String fileName,
        String mimeType,
        String userAgent,
        String cookies,
        String referer,
        File targetFile,
        File partFile) {
      this.id = id;
      this.url = url;
      this.fileName = fileName;
      this.mimeType = mimeType != null ? mimeType : "";
      this.userAgent = userAgent != null ? userAgent : "";
      this.cookies = cookies != null ? cookies : "";
      this.referer = referer != null ? referer : "";
      this.targetFile = targetFile;
      this.partFile = partFile;
    }

    int notifId() {
      return 70000 + (int) (Math.abs(id) % 20000L);
    }

    Map<String, Object> toMap() {
      Map<String, Object> m = new HashMap<>();
      m.put("downloadId", id);
      m.put("url", url);
      m.put("fileName", fileName);
      m.put("mimeType", mimeType);
      m.put("state", state);
      m.put("bytesDownloaded", bytesDownloaded.get());
      m.put("totalBytes", totalBytes);
      m.put("speedBytesPerSec", speedBytesPerSec);
      m.put("supportsRange", supportsRange);
      File f = "completed".equals(state) ? targetFile : partFile;
      m.put("localUri", f.getAbsolutePath());
      return m;
    }
  }

  private Activity activity;
  private ActivityPluginBinding activityBinding;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private FlutterPluginBinding pluginBinding;
  private MethodChannel channel;
  private MethodChannel.Result pendingVoiceResult;
  private MethodChannel.Result pendingFolderResult;
  private MethodChannel.Result pendingNotifPermResult;
  private HeavenVpnManager vpnManager;

  private final ExecutorService downloadPool = Executors.newCachedThreadPool();
  private final Map<Long, DownloadJob> downloadJobs = new ConcurrentHashMap<>();
  private final AtomicLong idGenerator = new AtomicLong(System.currentTimeMillis());
  private BroadcastReceiver controlReceiver;
  private boolean notifChannelsReady = false;
  private volatile String customDownloadPath = "";
  private volatile boolean downloadNotificationsEnabled = true;

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

  private Context resolveContext() {
    if (this.activity != null) {
      return this.activity;
    }
    if (this.pluginBinding != null) {
      return this.pluginBinding.getApplicationContext();
    }
    return null;
  }

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    this.pluginBinding = binding;
    Context appCtx = binding.getApplicationContext();
    SharedPreferences sp = appCtx.getSharedPreferences(NATIVE_PREFS_NAME, Context.MODE_PRIVATE);
    this.customDownloadPath = sp.getString(PREF_DOWNLOAD_PATH, "");
    this.downloadNotificationsEnabled = sp.getBoolean(PREF_DL_NOTIFS_ENABLED, true);
    this.vpnManager = new HeavenVpnManager(appCtx);
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    setupServiceWorkerShield();
    registerDownloadControlReceiver(appCtx);
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    unregisterDownloadControlReceiver(binding.getApplicationContext());
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
    binding.addRequestPermissionsResultListener(this);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    if (this.activityBinding != null) {
      this.activityBinding.removeActivityResultListener(this);
      this.activityBinding.removeRequestPermissionsResultListener(this);
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
      this.activityBinding.removeRequestPermissionsResultListener(this);
      this.activityBinding = null;
    }
    this.activity = null;
  }

  private void registerDownloadControlReceiver(Context appContext) {
    if (appContext == null || controlReceiver != null) {
      return;
    }
    controlReceiver =
        new BroadcastReceiver() {
          @Override
          public void onReceive(Context context, Intent intent) {
            if (intent == null || !ACTION_DOWNLOAD_CONTROL.equals(intent.getAction())) {
              return;
            }
            long id = intent.getLongExtra("downloadId", -1L);
            String cmd = intent.getStringExtra("cmd");
            if (id <= 0 || cmd == null) {
              return;
            }
            if ("pause".equals(cmd)) {
              pauseDownloadInternal(id);
            } else if ("resume".equals(cmd)) {
              resumeDownloadInternal(id);
            } else if ("cancel".equals(cmd)) {
              cancelDownloadInternal(id);
            }
          }
        };
    IntentFilter filter = new IntentFilter(ACTION_DOWNLOAD_CONTROL);
    if (Build.VERSION.SDK_INT >= 33) {
      appContext.registerReceiver(controlReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
    } else {
      appContext.registerReceiver(controlReceiver, filter);
    }
  }

  private void unregisterDownloadControlReceiver(Context appContext) {
    if (appContext != null && controlReceiver != null) {
      try {
        appContext.unregisterReceiver(controlReceiver);
      } catch (IllegalArgumentException ignored) {
        // Already unregistered.
      }
      controlReceiver = null;
    }
  }

  private void ensureNotificationSetup() {
    Context ctx = resolveContext();
    if (ctx == null) {
      return;
    }
    if (Build.VERSION.SDK_INT >= 33 && this.activity != null) {
      if (this.activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
          != PackageManager.PERMISSION_GRANTED) {
        this.activity.requestPermissions(
            new String[] {Manifest.permission.POST_NOTIFICATIONS}, NOTIF_PERM_REQUEST_CODE);
      }
    }
    if (notifChannelsReady || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return;
    }
    NotificationManager nm =
        (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
    if (nm == null) {
      return;
    }
    NotificationChannel progressChannel =
        new NotificationChannel(
            NOTIF_CHANNEL_PROGRESS,
            "Active Downloads",
            NotificationManager.IMPORTANCE_LOW);
    progressChannel.setDescription("Live progress for files downloading in Heaven Browser");
    progressChannel.setShowBadge(false);
    nm.createNotificationChannel(progressChannel);

    NotificationChannel completeChannel =
        new NotificationChannel(
            NOTIF_CHANNEL_COMPLETE,
            "Completed Downloads",
            NotificationManager.IMPORTANCE_DEFAULT);
    completeChannel.setDescription("Alerts when a download finishes");
    nm.createNotificationChannel(completeChannel);
    notifChannelsReady = true;
  }

  @Override
  public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
    if (vpnManager != null && vpnManager.onActivityResult(requestCode, resultCode)) {
      return true;
    }
    if (requestCode == VOICE_SEARCH_REQUEST_CODE) {
      MethodChannel.Result callback = this.pendingVoiceResult;
      this.pendingVoiceResult = null;
      if (callback == null) {
        return true;
      }
      if (resultCode == Activity.RESULT_OK && data != null) {
        ArrayList<String> matches =
            data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS);
        if (matches != null && !matches.isEmpty() && matches.get(0) != null) {
          callback.success(matches.get(0).trim());
          return true;
        }
      }
      callback.success(null);
      return true;
    }
    if (requestCode == FOLDER_PICKER_REQUEST_CODE) {
      MethodChannel.Result folderCb = this.pendingFolderResult;
      this.pendingFolderResult = null;
      if (folderCb == null) {
        return true;
      }
      if (resultCode == Activity.RESULT_OK && data != null && data.getData() != null) {
        Uri treeUri = data.getData();
        Context ctx = resolveContext();
        if (ctx != null) {
          try {
            int takeFlags =
                data.getFlags()
                    & (Intent.FLAG_GRANT_READ_URI_PERMISSION
                        | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            ctx.getContentResolver().takePersistableUriPermission(treeUri, takeFlags);
          } catch (Throwable ignored) {
          }
          String resolvedPath = resolveTreeUriToFilePath(ctx, treeUri);
          if (resolvedPath != null && !resolvedPath.isEmpty()) {
            saveCustomDownloadPath(ctx, resolvedPath);
            Map<String, Object> out = new HashMap<>();
            out.put("ok", true);
            out.put("path", resolvedPath);
            out.put("label", friendlyFolderLabel(resolvedPath));
            folderCb.success(out);
            return true;
          }
        }
      }
      folderCb.success(null);
      return true;
    }
    return false;
  }

  @Override
  public boolean onRequestPermissionsResult(
      int requestCode, String[] permissions, int[] grantResults) {
    if (requestCode == NOTIF_PERM_REQUEST_CODE) {
      MethodChannel.Result cb = this.pendingNotifPermResult;
      this.pendingNotifPermResult = null;
      if (cb != null) {
        boolean granted =
            grantResults != null
                && grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        cb.success(granted);
      }
      return true;
    }
    return false;
  }

  private void setupServiceWorkerShield() {
    if (serviceWorkerHooked) {
      return;
    }
    try {
      ServiceWorkerController swController = ServiceWorkerController.getInstance();
      swController.setServiceWorkerClient(
          new ServiceWorkerClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebResourceRequest request) {
              return interceptIfAdOrTracker(-1L, request);
            }
          });
      serviceWorkerHooked = true;
    } catch (Throwable ignored) {
      // Older WebView builds may lack ServiceWorkerController support.
    }
  }

  @Override
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    switch (call.method) {
      case "openDefaultBrowserSettings":
        result.success(openDefaultBrowserSettings());
        break;

      case "startVoiceSearch":
        startVoiceSearch(result);
        break;

      case "updateConfig":
      case "updateShieldConfig":
        handleUpdateConfig(call);
        result.success(true);
        break;

      case "attachToWebView":
        Object idObj = call.argument("webViewId");
        String initHost = call.argument("pageHost");
        Boolean initDesktop = call.argument("desktopMode");
        if (initDesktop != null) {
          this.desktopMode = initDesktop;
        }
        if (idObj instanceof Number) {
          long wvId = ((Number) idObj).longValue();
          if (initHost != null && !initHost.trim().isEmpty()) {
            currentPageHosts.put(wvId, normalizeHost(initHost));
          }
          boolean attached = attachShieldToWebView(wvId);
          result.success(attached);
        } else {
          result.success(false);
        }
        break;

      case "applyDesktopViewport":
        Object dvId = call.argument("webViewId");
        Boolean enabledArg = call.argument("desktopMode");
        boolean wantDesktop = enabledArg != null && enabledArg;
        this.desktopMode = wantDesktop;
        if (dvId instanceof Number && pluginBinding != null) {
          WebView wv =
              WebViewFlutterAndroidExternalApi.getWebView(
                  pluginBinding, ((Number) dvId).longValue());
          if (wv != null) {
            applyDesktopSettingsToWebView(wv, wantDesktop);
            result.success(true);
            return;
          }
        }
        result.success(false);
        break;

      case "captureWebViewPreview":
        Object capId = call.argument("webViewId");
        if (capId instanceof Number && pluginBinding != null) {
          captureWebViewPreview(((Number) capId).longValue(), result);
        } else {
          result.success(null);
        }
        break;

      case "updatePageHost":
      case "setWebViewPageHost":
        Object wvIdObj = call.argument("webViewId");
        String pageHost = call.argument("pageHost");
        if (pageHost == null) {
          pageHost = call.argument("host");
        }
        if (wvIdObj instanceof Number) {
          long id = ((Number) wvIdObj).longValue();
          if (pageHost == null || pageHost.trim().isEmpty()) {
            currentPageHosts.remove(id);
          } else {
            currentPageHosts.put(id, normalizeHost(pageHost));
          }
        }
        result.success(true);
        break;

      case "startDownload":
        handleStartDownload(call, result);
        break;

      case "restoreDownload":
        handleRestoreDownload(call, result);
        break;

      case "pauseDownload":
        Object pauseId = call.argument("downloadId");
        if (pauseId instanceof Number) {
          result.success(pauseDownloadInternal(((Number) pauseId).longValue()));
        } else {
          result.success(false);
        }
        break;

      case "resumeDownload":
        Object resumeId = call.argument("downloadId");
        if (resumeId instanceof Number) {
          result.success(resumeDownloadInternal(((Number) resumeId).longValue()));
        } else {
          result.success(false);
        }
        break;

      case "queryDownloads":
        handleQueryDownloads(call, result);
        break;

      case "cancelDownload":
        Object cancelId = call.argument("downloadId");
        if (cancelId instanceof Number) {
          result.success(cancelDownloadInternal(((Number) cancelId).longValue()));
        } else {
          result.success(false);
        }
        break;

      case "openDownloadedFile":
        handleOpenDownloadedFile(call, result);
        break;

      case "getDownloadLocations":
        handleGetDownloadLocations(result);
        break;

      case "setDownloadLocation":
        handleSetDownloadLocation(call, result);
        break;

      case "pickDownloadFolder":
        handlePickDownloadFolder(result);
        break;

      case "createHomeScreenShortcut":
        handleCreateHomeScreenShortcut(call, result);
        break;

      case "getNotificationStatus":
        handleGetNotificationStatus(result);
        break;

      case "requestNotificationPermission":
        handleRequestNotificationPermission(result);
        break;

      case "openNotificationSettings":
        result.success(openAppNotificationSettings());
        break;

      case "setDownloadNotificationsEnabled":
        Boolean dlNotifArg = call.argument("enabled");
        setDownloadNotificationsEnabledInternal(dlNotifArg == null || dlNotifArg);
        result.success(true);
        break;

      case "clearSiteData":
        String targetDomain = call.argument("domain");
        handleClearSiteData(targetDomain, result);
        break;

      case "provisionFreeWarpConfig":
        if (vpnManager != null) {
          String routeMode = call.argument("routeMode");
          vpnManager.provisionFreeWarpConfig(
              routeMode != null ? routeMode : "stealth_4500", result);
        } else {
          result.success(Collections.singletonMap("ok", false));
        }
        break;

      case "validateWireGuardConfig":
        if (vpnManager != null) {
          String rawCfg = call.argument("configText");
          vpnManager.validateWireGuardConfig(rawCfg != null ? rawCfg : "", result);
        } else {
          result.success(Collections.singletonMap("valid", false));
        }
        break;

      case "connectVpn":
        if (vpnManager != null) {
          String cfgText = call.argument("configText");
          String profName = call.argument("profileName");
          String routeMode = call.argument("routeMode");
          Boolean bOnly = call.argument("browserOnly");
          Boolean builtInWarp = call.argument("isBuiltInWarp");
          vpnManager.connectVpn(
              this.activity,
              cfgText != null ? cfgText : "",
              profName != null ? profName : "Heaven Stealth VPN",
              routeMode != null ? routeMode : "stealth_4500",
              bOnly != null && bOnly,
              builtInWarp == null || builtInWarp,
              result);
        } else {
          result.success(Collections.singletonMap("ok", false));
        }
        break;

      case "disconnectVpn":
        if (vpnManager != null) {
          vpnManager.disconnectVpn(result);
        } else {
          result.success(Collections.singletonMap("ok", true));
        }
        break;

      case "getVpnStatus":
        if (vpnManager != null) {
          vpnManager.getVpnStatus(result);
        } else {
          result.success(Collections.singletonMap("connected", false));
        }
        break;

      default:
        result.notImplemented();
        break;
    }
  }

  private void captureWebViewPreview(long webViewId, MethodChannel.Result result) {
    WebView webView = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, webViewId);
    if (webView == null || webView.getWidth() <= 0 || webView.getHeight() <= 0) {
      result.success(null);
      return;
    }
    try {
      int srcW = webView.getWidth();
      int srcH = webView.getHeight();
      int targetW = 360;
      float scale = (float) targetW / (float) srcW;
      int targetH = Math.max(240, Math.min(760, Math.round(srcH * scale)));

      Bitmap bitmap = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      canvas.scale(scale, scale);
      canvas.translate(-webView.getScrollX(), -webView.getScrollY());
      webView.draw(canvas);

      downloadPool.execute(
          () -> {
            try {
              ByteArrayOutputStream out = new ByteArrayOutputStream(28 * 1024);
              bitmap.compress(Bitmap.CompressFormat.JPEG, 82, out);
              bitmap.recycle();
              byte[] bytes = out.toByteArray();
              mainHandler.post(() -> result.success(bytes));
            } catch (Throwable t) {
              bitmap.recycle();
              mainHandler.post(() -> result.success(null));
            }
          });
    } catch (Throwable t) {
      result.success(null);
    }
  }

  private void startVoiceSearch(MethodChannel.Result result) {
    if (this.activity == null) {
      result.error("NO_ACTIVITY", "Voice search requires foreground activity", null);
      return;
    }
    if (this.pendingVoiceResult != null) {
      this.pendingVoiceResult.success(null);
      this.pendingVoiceResult = null;
    }
    try {
      Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
      intent.putExtra(
          RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_WEB_SEARCH);
      intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag());
      intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
      intent.putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak to search Heaven...");
      this.pendingVoiceResult = result;
      this.activity.startActivityForResult(intent, VOICE_SEARCH_REQUEST_CODE);
    } catch (ActivityNotFoundException e) {
      this.pendingVoiceResult = null;
      result.error("NO_VOICE_ENGINE", "Speech recognition is not available on this device", null);
    }
  }

  private void handleUpdateConfig(MethodCall call) {
    Boolean enabledArg = call.argument("shieldEnabled");
    if (enabledArg != null) {
      this.shieldEnabled = enabledArg;
    }
    Boolean desktopArg = call.argument("desktopMode");
    if (desktopArg != null) {
      this.desktopMode = desktopArg;
    }
    List<String> domainsArg = call.argument("blockedDomains");
    if (domainsArg != null) {
      Set<String> next = new HashSet<>(domainsArg.size() * 2);
      for (String d : domainsArg) {
        if (d != null && !d.isEmpty()) {
          next.add(normalizeHost(d));
        }
      }
      this.blockedDomains = next;
    }
    List<String> trustedArg = call.argument("trustedHosts");
    if (trustedArg != null) {
      Set<String> nextTrusted = new HashSet<>(trustedArg.size() * 2);
      for (String h : trustedArg) {
        if (h != null && !h.isEmpty()) {
          nextTrusted.add(normalizeHost(h));
        }
      }
      this.trustedHosts = nextTrusted;
    }
    String scriptArg = call.argument("cosmeticScript");
    if (scriptArg != null) {
      this.cosmeticScript = scriptArg;
    }
  }

  private void applyDesktopSettingsToWebView(WebView webView, boolean enableDesktop) {
    WebSettings settings = webView.getSettings();
    settings.setUseWideViewPort(enableDesktop);
    settings.setLoadWithOverviewMode(enableDesktop);
    settings.setSupportZoom(true);
    settings.setBuiltInZoomControls(true);
    settings.setDisplayZoomControls(false);
    if (enableDesktop) {
      webView.setInitialScale(0);
      webView.evaluateJavascript(DESKTOP_VIEWPORT_SCRIPT, null);
    } else {
      webView.setInitialScale(0);
      webView.evaluateJavascript(MOBILE_VIEWPORT_RESET_SCRIPT, null);
    }
  }

  private boolean attachShieldToWebView(final long webViewId) {
    if (pluginBinding == null) {
      return false;
    }
    WebView webView = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, webViewId);
    if (webView == null) {
      return false;
    }

    applyDesktopSettingsToWebView(webView, this.desktopMode);
    installPullToRefreshListener(webView, webViewId);
    installDownloadListener(webView, webViewId);

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      WebViewClient existing = webView.getWebViewClient();
      if (!(existing instanceof ShieldWebViewClient)) {
        webView.setWebViewClient(new ShieldWebViewClient(webViewId, existing));
      }
      return true;
    }
    return false;
  }

  private void installPullToRefreshListener(final WebView webView, final long webViewId) {
    final float density = webView.getResources().getDisplayMetrics().density;
    final float triggerPx = 118.0f * density;
    final float touchSlopPx = 12.0f * density;

    webView.setOnTouchListener(
        new View.OnTouchListener() {
          private float startY = -1f;
          private float startX = -1f;
          private boolean trackingTopPull = false;
          private boolean draggingRefresh = false;

          @Override
          public boolean onTouch(View v, MotionEvent event) {
            int action = event.getActionMasked();
            if (event.getPointerCount() > 1) {
              if (draggingRefresh) {
                emitPullProgress(webViewId, 0.0);
              }
              trackingTopPull = false;
              draggingRefresh = false;
              return false;
            }

            switch (action) {
              case MotionEvent.ACTION_DOWN:
                if (webView.getScrollY() <= 2 && !webView.canScrollVertically(-1)) {
                  startY = event.getRawY();
                  startX = event.getRawX();
                  trackingTopPull = true;
                  draggingRefresh = false;
                } else {
                  trackingTopPull = false;
                  draggingRefresh = false;
                }
                break;

              case MotionEvent.ACTION_MOVE:
                if (!trackingTopPull) {
                  break;
                }
                if (webView.getScrollY() > 2 || webView.canScrollVertically(-1)) {
                  if (draggingRefresh) {
                    emitPullProgress(webViewId, 0.0);
                  }
                  trackingTopPull = false;
                  draggingRefresh = false;
                  break;
                }
                float dy = event.getRawY() - startY;
                float dx = Math.abs(event.getRawX() - startX);
                if (!draggingRefresh) {
                  if (dy > touchSlopPx && dy > dx * 1.35f) {
                    draggingRefresh = true;
                    MotionEvent cancel =
                        MotionEvent.obtain(
                            SystemClock.uptimeMillis(),
                            SystemClock.uptimeMillis(),
                            MotionEvent.ACTION_CANCEL,
                            event.getX(),
                            event.getY(),
                            0);
                    webView.onTouchEvent(cancel);
                    cancel.recycle();
                  } else if (dy < -touchSlopPx || dx > touchSlopPx * 2.0f) {
                    trackingTopPull = false;
                  }
                }
                if (draggingRefresh) {
                  double progress = Math.min(1.0, Math.max(0.0, (dy - touchSlopPx) / triggerPx));
                  emitPullProgress(webViewId, progress);
                  return true;
                }
                break;

              case MotionEvent.ACTION_UP:
              case MotionEvent.ACTION_CANCEL:
                if (draggingRefresh) {
                  float finalDy = event.getRawY() - startY;
                  boolean triggered =
                      action == MotionEvent.ACTION_UP && (finalDy - touchSlopPx) >= triggerPx;
                  emitPullProgress(webViewId, 0.0);
                  trackingTopPull = false;
                  draggingRefresh = false;
                  if (triggered) {
                    emitPullRefresh(webViewId);
                  }
                  return true;
                }
                trackingTopPull = false;
                draggingRefresh = false;
                break;

              default:
                break;
            }
            return false;
          }
        });
  }

  private void emitPullProgress(final long webViewId, final double progress) {
    mainHandler.post(
        () -> {
          MethodChannel ch = this.channel;
          if (ch != null) {
            Map<String, Object> payload = new HashMap<>(4);
            payload.put("webViewId", webViewId);
            payload.put("progress", progress);
            ch.invokeMethod("onPullProgress", payload);
          }
        });
  }

  private void emitPullRefresh(final long webViewId) {
    mainHandler.post(
        () -> {
          MethodChannel ch = this.channel;
          if (ch != null) {
            Map<String, Object> payload = new HashMap<>(2);
            payload.put("webViewId", webViewId);
            ch.invokeMethod("onPullRefresh", payload);
          }
        });
  }

  private void installDownloadListener(final WebView webView, final long webViewId) {
    webView.setDownloadListener(
        (url, userAgent, contentDisposition, mimeType, contentLength) -> {
          if (url == null || url.isEmpty()) {
            return;
          }
          mainHandler.post(
              () -> {
                String currentUrl = webView.getUrl();
                boolean wasEmptyPage =
                    currentUrl == null
                        || currentUrl.trim().isEmpty()
                        || "about:blank".equalsIgnoreCase(currentUrl.trim());
                // Prevent WebView from staying stuck on an aborted binary stream navigation!
                webView.stopLoading();

                String guessedName = URLUtil.guessFileName(url, contentDisposition, mimeType);
                DownloadJob job =
                    createAndStartJob(
                        url,
                        guessedName,
                        mimeType,
                        userAgent,
                        currentUrl,
                        contentLength,
                        null,
                        true);
                if (job != null && this.channel != null) {
                  Map<String, Object> info = job.toMap();
                  info.put("webViewId", webViewId);
                  info.put("wasEmptyPage", wasEmptyPage);
                  this.channel.invokeMethod("onDownloadStarted", info);
                }
              });
        });
  }

  private File resolveDownloadsDir(Context ctx) {
    String custom = this.customDownloadPath;
    if (custom != null && !custom.trim().isEmpty()) {
      File customDir = new File(custom.trim());
      if ((customDir.exists() || customDir.mkdirs()) && customDir.canWrite()) {
        return customDir;
      }
    }
    File pub = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
    if (pub != null && (pub.exists() || pub.mkdirs()) && pub.canWrite()) {
      return pub;
    }
    File fallback = ctx.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
    if (fallback != null && !fallback.exists()) {
      //noinspection ResultOfMethodCallIgnored
      fallback.mkdirs();
    }
    return fallback != null ? fallback : ctx.getFilesDir();
  }

  private void saveCustomDownloadPath(Context ctx, String path) {
    String clean = path == null ? "" : path.trim();
    this.customDownloadPath = clean;
    if (ctx != null) {
      ctx.getSharedPreferences(NATIVE_PREFS_NAME, Context.MODE_PRIVATE)
          .edit()
          .putString(PREF_DOWNLOAD_PATH, clean)
          .apply();
    }
  }

  private String friendlyFolderLabel(String rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty()) {
      return "Downloads";
    }
    String p = rawPath.trim();
    File ext = Environment.getExternalStorageDirectory();
    if (ext != null) {
      String root = ext.getAbsolutePath();
      if (p.equals(root)) {
        return "Internal Storage";
      }
      if (p.startsWith(root + File.separator)) {
        return p.substring(root.length() + 1);
      }
    }
    if (p.contains("/Android/data/")) {
      return "App Private Downloads";
    }
    File f = new File(p);
    return f.getName().isEmpty() ? p : f.getName();
  }

  private void handleGetDownloadLocations(MethodChannel.Result result) {
    Context ctx = resolveContext();
    if (ctx == null) {
      result.success(Collections.emptyMap());
      return;
    }
    File activeDir = resolveDownloadsDir(ctx);
    List<Map<String, String>> presets = new ArrayList<>();

    File pubDl = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
    if (pubDl != null) {
      presets.add(makeLocationItem("Downloads (Default)", pubDl.getAbsolutePath()));
      presets.add(
          makeLocationItem(
              "Downloads / HeavenBrowser", new File(pubDl, "HeavenBrowser").getAbsolutePath()));
    }
    File pubDocs = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS);
    if (pubDocs != null) {
      presets.add(
          makeLocationItem(
              "Documents / HeavenBrowser", new File(pubDocs, "HeavenBrowser").getAbsolutePath()));
    }
    File pubPics = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES);
    if (pubPics != null) {
      presets.add(
          makeLocationItem(
              "Pictures / HeavenBrowser", new File(pubPics, "HeavenBrowser").getAbsolutePath()));
    }
    File pubMovies = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES);
    if (pubMovies != null) {
      presets.add(
          makeLocationItem(
              "Movies / HeavenBrowser", new File(pubMovies, "HeavenBrowser").getAbsolutePath()));
    }
    File appPrivate = ctx.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
    if (appPrivate != null) {
      presets.add(makeLocationItem("App Private Storage", appPrivate.getAbsolutePath()));
    }

    Map<String, Object> out = new HashMap<>();
    out.put("currentPath", activeDir.getAbsolutePath());
    out.put("currentLabel", friendlyFolderLabel(activeDir.getAbsolutePath()));
    out.put("presets", presets);
    result.success(out);
  }

  private static Map<String, String> makeLocationItem(String label, String path) {
    Map<String, String> m = new HashMap<>(4);
    m.put("label", label);
    m.put("path", path);
    return m;
  }

  private void handleSetDownloadLocation(MethodCall call, MethodChannel.Result result) {
    Context ctx = resolveContext();
    String path = call.argument("path");
    if (ctx == null || path == null || path.trim().isEmpty()) {
      result.success(Collections.singletonMap("ok", false));
      return;
    }
    File dir = new File(path.trim());
    if (!dir.exists()) {
      //noinspection ResultOfMethodCallIgnored
      dir.mkdirs();
    }
    if (!dir.exists() || !dir.canWrite()) {
      Map<String, Object> err = new HashMap<>();
      err.put("ok", false);
      err.put("error", "Cannot write to selected folder on this Android version. Use Choose Custom Folder.");
      result.success(err);
      return;
    }
    saveCustomDownloadPath(ctx, dir.getAbsolutePath());
    Map<String, Object> out = new HashMap<>();
    out.put("ok", true);
    out.put("path", dir.getAbsolutePath());
    out.put("label", friendlyFolderLabel(dir.getAbsolutePath()));
    result.success(out);
  }

  private void handlePickDownloadFolder(MethodChannel.Result result) {
    if (this.activity == null) {
      result.success(null);
      return;
    }
    try {
      Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
      intent.addFlags(
          Intent.FLAG_GRANT_READ_URI_PERMISSION
              | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
              | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
      this.pendingFolderResult = result;
      this.activity.startActivityForResult(intent, FOLDER_PICKER_REQUEST_CODE);
    } catch (ActivityNotFoundException e) {
      this.pendingFolderResult = null;
      result.success(null);
    }
  }

  private String resolveTreeUriToFilePath(Context ctx, Uri treeUri) {
    try {
      String docId = DocumentsContract.getTreeDocumentId(treeUri);
      if (docId != null) {
        if (docId.startsWith("raw:")) {
          return docId.substring(4);
        }
        String[] split = docId.split(":", 2);
        if (split.length >= 1 && "primary".equalsIgnoreCase(split[0])) {
          File root = Environment.getExternalStorageDirectory();
          String rel = split.length == 2 ? split[1] : "";
          File resolved = rel.isEmpty() ? root : new File(root, rel);
          if (resolved.exists() || resolved.mkdirs()) {
            return resolved.getAbsolutePath();
          }
        }
      }
    } catch (Throwable ignored) {
    }
    File fallback = ctx.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
    return fallback != null ? fallback.getAbsolutePath() : null;
  }

  @SuppressWarnings("deprecation")
  private void handleCreateHomeScreenShortcut(MethodCall call, MethodChannel.Result result) {
    Context ctx = resolveContext();
    String title = call.argument("title");
    String url = call.argument("url");
    if (ctx == null || url == null || url.trim().isEmpty()) {
      result.success(false);
      return;
    }
    String cleanUrl = url.trim();
    String cleanTitle =
        (title != null && !title.trim().isEmpty()) ? title.trim() : cleanUrl;
    if (cleanTitle.length() > 28) {
      cleanTitle = cleanTitle.substring(0, 28).trim();
    }

    Intent launchIntent = new Intent(Intent.ACTION_VIEW, Uri.parse(cleanUrl));
    launchIntent.setClassName(
        ctx.getPackageName(), "com.hypertechlabs.heavenbrowser.MainActivity");
    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);

    Bitmap iconBmp = buildShortcutIconBitmap(cleanTitle);

    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        ShortcutManager sm = ctx.getSystemService(ShortcutManager.class);
        if (sm != null && sm.isRequestPinShortcutSupported()) {
          String shortcutId = "hb_site_" + Math.abs(cleanUrl.hashCode());
          ShortcutInfo info =
              new ShortcutInfo.Builder(ctx, shortcutId)
                  .setShortLabel(cleanTitle)
                  .setLongLabel(cleanTitle)
                  .setIcon(Icon.createWithBitmap(iconBmp))
                  .setIntent(launchIntent)
                  .build();
          boolean requested = sm.requestPinShortcut(info, null);
          result.success(requested);
          return;
        }
      }
      Intent legacy = new Intent("com.android.launcher.action.INSTALL_SHORTCUT");
      legacy.putExtra(Intent.EXTRA_SHORTCUT_INTENT, launchIntent);
      legacy.putExtra(Intent.EXTRA_SHORTCUT_NAME, cleanTitle);
      legacy.putExtra(Intent.EXTRA_SHORTCUT_ICON, iconBmp);
      ctx.sendBroadcast(legacy);
      result.success(true);
    } catch (Throwable t) {
      result.success(false);
    }
  }

  private static Bitmap buildShortcutIconBitmap(String label) {
    int size = 192;
    Bitmap bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
    Canvas canvas = new Canvas(bmp);

    Paint bg = new Paint(Paint.ANTI_ALIAS_FLAG);
    bg.setColor(Color.parseColor("#2563EB"));
    RectF rect = new RectF(12f, 12f, size - 12f, size - 12f);
    canvas.drawRoundRect(rect, 44f, 44f, bg);

    String initial = "H";
    if (label != null) {
      for (int i = 0; i < label.length(); i++) {
        char ch = label.charAt(i);
        if (Character.isLetterOrDigit(ch)) {
          initial = String.valueOf(Character.toUpperCase(ch));
          break;
        }
      }
    }

    Paint txt = new Paint(Paint.ANTI_ALIAS_FLAG);
    txt.setColor(Color.WHITE);
    txt.setTextAlign(Paint.Align.CENTER);
    txt.setFakeBoldText(true);
    txt.setTextSize(92f);
    Paint.FontMetrics fm = txt.getFontMetrics();
    float centerY = (size / 2f) - ((fm.ascent + fm.descent) / 2f);
    canvas.drawText(initial, size / 2f, centerY, txt);
    return bmp;
  }

  private void handleGetNotificationStatus(MethodChannel.Result result) {
    Context ctx = resolveContext();
    boolean systemEnabled = true;
    boolean runtimeGranted = true;
    if (ctx != null) {
      NotificationManager nm =
          (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
      if (nm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        systemEnabled = nm.areNotificationsEnabled();
      }
      if (Build.VERSION.SDK_INT >= 33) {
        runtimeGranted =
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED;
      }
    }
    Map<String, Object> out = new HashMap<>();
    out.put("systemEnabled", systemEnabled && runtimeGranted);
    out.put("runtimeGranted", runtimeGranted);
    out.put("downloadNotificationsEnabled", this.downloadNotificationsEnabled);
    result.success(out);
  }

  private void handleRequestNotificationPermission(MethodChannel.Result result) {
    if (Build.VERSION.SDK_INT < 33) {
      result.success(true);
      return;
    }
    if (this.activity == null) {
      result.success(false);
      return;
    }
    if (this.activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
        == PackageManager.PERMISSION_GRANTED) {
      result.success(true);
      return;
    }
    this.pendingNotifPermResult = result;
    this.activity.requestPermissions(
        new String[] {Manifest.permission.POST_NOTIFICATIONS}, NOTIF_PERM_REQUEST_CODE);
  }

  private boolean openAppNotificationSettings() {
    Context ctx = resolveContext();
    if (ctx == null) {
      return false;
    }
    try {
      Intent intent;
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS);
        intent.putExtra(Settings.EXTRA_APP_PACKAGE, ctx.getPackageName());
      } else {
        intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        intent.setData(Uri.parse("package:" + ctx.getPackageName()));
      }
      if (this.activity != null) {
        this.activity.startActivity(intent);
      } else {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        ctx.startActivity(intent);
      }
      return true;
    } catch (Throwable ignored) {
      return false;
    }
  }

  private void setDownloadNotificationsEnabledInternal(boolean enabled) {
    this.downloadNotificationsEnabled = enabled;
    Context ctx = resolveContext();
    if (ctx != null) {
      ctx.getSharedPreferences(NATIVE_PREFS_NAME, Context.MODE_PRIVATE)
          .edit()
          .putBoolean(PREF_DL_NOTIFS_ENABLED, enabled)
          .apply();
      if (!enabled) {
        NotificationManager nm =
            (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) {
          for (DownloadJob job : downloadJobs.values()) {
            nm.cancel(job.notifId());
          }
        }
      }
    }
  }

  private void handleClearSiteData(String domain, MethodChannel.Result result) {
    try {
      CookieManager cm = CookieManager.getInstance();
      if (domain != null && !domain.trim().isEmpty()) {
        String clean = normalizeHost(domain);
        String existing = cm.getCookie("https://" + clean);
        if (existing != null) {
          String[] pairs = existing.split(";");
          for (String pair : pairs) {
            int eq = pair.indexOf('=');
            String name = (eq > 0 ? pair.substring(0, eq) : pair).trim();
            if (!name.isEmpty()) {
              cm.setCookie(
                  "https://" + clean, name + "=; Max-Age=0; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT");
              cm.setCookie(
                  "https://." + clean, name + "=; Max-Age=0; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT");
            }
          }
        }
        cm.flush();
        WebStorage.getInstance().deleteOrigin("https://" + clean);
        WebStorage.getInstance().deleteOrigin("https://www." + clean);
      } else {
        cm.removeAllCookies(null);
        cm.flush();
        WebStorage.getInstance().deleteAllData();
      }
      result.success(true);
    } catch (Throwable t) {
      result.success(false);
    }
  }

  private File uniqueTargetFile(File dir, String rawName) {
    String safe =
        rawName == null || rawName.trim().isEmpty()
            ? "download.bin"
            : rawName.replaceAll("[\\\\/:*?\"<>|]", "_").trim();
    File candidate = new File(dir, safe);
    if (!candidate.exists() && !new File(dir, safe + ".part").exists()) {
      return candidate;
    }
    int dot = safe.lastIndexOf('.');
    String base = dot > 0 ? safe.substring(0, dot) : safe;
    String ext = dot > 0 ? safe.substring(dot) : "";
    for (int i = 1; i <= 999; i++) {
      String numbered = base + " (" + i + ")" + ext;
      File c = new File(dir, numbered);
      if (!c.exists() && !new File(dir, numbered + ".part").exists()) {
        return c;
      }
    }
    return new File(dir, System.currentTimeMillis() + "_" + safe);
  }

  private void handleStartDownload(MethodCall call, MethodChannel.Result result) {
    String url = call.argument("url");
    String fileName = call.argument("fileName");
    String mimeType = call.argument("mimeType");
    String userAgent = call.argument("userAgent");
    if (url == null || url.trim().isEmpty()) {
      result.error("INVALID_URL", "Download URL is empty", null);
      return;
    }
    String cleanUrl = url.trim();
    String resolvedName =
        (fileName != null && !fileName.trim().isEmpty())
            ? fileName.trim()
            : URLUtil.guessFileName(cleanUrl, null, mimeType);
    DownloadJob job =
        createAndStartJob(cleanUrl, resolvedName, mimeType, userAgent, null, -1L, null, true);
    if (job == null) {
      result.error("DOWNLOAD_ERROR", "Unable to initialize download", null);
      return;
    }
    result.success(job.toMap());
  }

  private void handleRestoreDownload(MethodCall call, MethodChannel.Result result) {
    Object idObj = call.argument("downloadId");
    String url = call.argument("url");
    String fileName = call.argument("fileName");
    String mimeType = call.argument("mimeType");
    String localPath = call.argument("localUri");
    String savedState = call.argument("state");
    Object totalObj = call.argument("totalBytes");
    if (!(idObj instanceof Number) || url == null || url.isEmpty()) {
      result.success(false);
      return;
    }
    long id = ((Number) idObj).longValue();
    if (downloadJobs.containsKey(id)) {
      result.success(true);
      return;
    }
    Context ctx = resolveContext();
    if (ctx == null) {
      result.success(false);
      return;
    }
    File dir = resolveDownloadsDir(ctx);
    String safeName = (fileName != null && !fileName.isEmpty()) ? fileName : "download.bin";
    File targetFile;
    File partFile;
    if (localPath != null && !localPath.isEmpty()) {
      if (localPath.endsWith(".part")) {
        partFile = new File(localPath);
        targetFile = new File(localPath.substring(0, localPath.length() - 5));
      } else {
        targetFile = new File(localPath);
        partFile = new File(localPath + ".part");
      }
    } else {
      targetFile = new File(dir, safeName);
      partFile = new File(dir, safeName + ".part");
    }

    String cookies = "";
    try {
      String c = CookieManager.getInstance().getCookie(url);
      if (c != null) cookies = c;
    } catch (Throwable ignored) {
    }

    DownloadJob job =
        new DownloadJob(id, url, safeName, mimeType, "", cookies, "", targetFile, partFile);
    if (totalObj instanceof Number) {
      job.totalBytes = ((Number) totalObj).longValue();
    }
    if (targetFile.exists() && "completed".equals(savedState)) {
      job.state = "completed";
      job.bytesDownloaded.set(targetFile.length());
      if (job.totalBytes <= 0) job.totalBytes = targetFile.length();
    } else {
      job.state = "paused".equals(savedState) ? "paused" : "failed";
      if (partFile.exists()) {
        job.bytesDownloaded.set(partFile.length());
      }
    }
    downloadJobs.put(id, job);
    result.success(true);
  }

  private DownloadJob createAndStartJob(
      String url,
      String fileName,
      String mimeType,
      String userAgent,
      String referer,
      long initialTotal,
      Long explicitId,
      boolean startImmediately) {
    Context ctx = resolveContext();
    if (ctx == null) {
      return null;
    }
    ensureNotificationSetup();

    File dir = resolveDownloadsDir(ctx);
    File target = uniqueTargetFile(dir, fileName);
    File part = new File(target.getParentFile(), target.getName() + ".part");
    long id = explicitId != null ? explicitId : idGenerator.incrementAndGet();

    String cookies = "";
    try {
      String rawCookie = CookieManager.getInstance().getCookie(url);
      if (rawCookie != null) {
        cookies = rawCookie;
      }
    } catch (Throwable ignored) {
    }

    DownloadJob job =
        new DownloadJob(
            id, url, target.getName(), mimeType, userAgent, cookies, referer, target, part);
    if (initialTotal > 0) {
      job.totalBytes = initialTotal;
    }
    downloadJobs.put(id, job);
    if (startImmediately) {
      postDownloadNotification(job);
      downloadPool.execute(() -> executeDownloadLoop(job));
    }
    return job;
  }

  private boolean pauseDownloadInternal(long id) {
    DownloadJob job = downloadJobs.get(id);
    if (job == null) {
      return false;
    }
    if (!"running".equals(job.state)) {
      return "paused".equals(job.state);
    }
    job.pauseRequested = true;
    job.state = "paused";
    job.speedBytesPerSec = 0L;
    closeActiveStreamAsync(job);
    postDownloadNotification(job);
    return true;
  }

  private boolean resumeDownloadInternal(long id) {
    DownloadJob job = downloadJobs.get(id);
    if (job == null || "completed".equals(job.state)) {
      return false;
    }
    if ("running".equals(job.state)) {
      return true;
    }
    ensureNotificationSetup();
    if (job.partFile.exists()) {
      job.bytesDownloaded.set(job.partFile.length());
    } else {
      job.bytesDownloaded.set(0L);
    }
    job.pauseRequested = false;
    job.cancelRequested = false;
    job.state = "running";
    postDownloadNotification(job);
    downloadPool.execute(() -> executeDownloadLoop(job));
    return true;
  }

  private boolean cancelDownloadInternal(long id) {
    DownloadJob job = downloadJobs.remove(id);
    if (job == null) {
      return false;
    }
    job.cancelRequested = true;
    job.pauseRequested = false;
    job.state = "canceled";
    closeActiveStreamAsync(job);
    downloadPool.execute(
        () -> {
          if (job.partFile.exists()) {
            //noinspection ResultOfMethodCallIgnored
            job.partFile.delete();
          }
        });
    cancelNotification(job.notifId());
    return true;
  }

  private void closeActiveStreamAsync(final DownloadJob job) {
    downloadPool.execute(
        () -> {
          InputStream in = job.activeStream;
          HttpURLConnection conn = job.activeConn;
          job.activeStream = null;
          job.activeConn = null;
          if (in != null) {
            try {
              in.close();
            } catch (IOException ignored) {
            }
          }
          if (conn != null) {
            try {
              conn.disconnect();
            } catch (Throwable ignored) {
            }
          }
        });
  }

  private HttpURLConnection openFollowingRedirects(DownloadJob job, long resumeOffset)
      throws IOException {
    String currentUrl = job.url;
    for (int hop = 0; hop < 8; hop++) {
      HttpURLConnection conn = (HttpURLConnection) URI.create(currentUrl).toURL().openConnection();
      conn.setInstanceFollowRedirects(false);
      conn.setConnectTimeout(15000);
      conn.setReadTimeout(25000);
      conn.setRequestProperty(
          "User-Agent",
          !job.userAgent.isEmpty()
              ? job.userAgent
              : "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/134.0.0.0 Mobile Safari/537.36");
      conn.setRequestProperty("Accept", "*/*");
      conn.setRequestProperty("Accept-Encoding", "identity");
      if (!job.cookies.isEmpty()) {
        conn.setRequestProperty("Cookie", job.cookies);
      }
      if (!job.referer.isEmpty()) {
        conn.setRequestProperty("Referer", job.referer);
      }
      if (resumeOffset > 0) {
        conn.setRequestProperty("Range", "bytes=" + resumeOffset + "-");
        if (!job.etag.isEmpty()) {
          conn.setRequestProperty("If-Range", job.etag);
        }
      }
      int status = conn.getResponseCode();
      if (status == HttpURLConnection.HTTP_MOVED_PERM
          || status == HttpURLConnection.HTTP_MOVED_TEMP
          || status == HttpURLConnection.HTTP_SEE_OTHER
          || status == 307
          || status == 308) {
        String loc = conn.getHeaderField("Location");
        conn.disconnect();
        if (loc == null || loc.isEmpty()) {
          throw new IOException("Empty redirect Location");
        }
        currentUrl = URI.create(currentUrl).resolve(loc).toString();
        continue;
      }
      return conn;
    }
    throw new IOException("Too many redirects");
  }

  private void executeDownloadLoop(final DownloadJob job) {
    HttpURLConnection conn = null;
    InputStream in = null;
    FileOutputStream out = null;
    try {
      File parent = job.partFile.getParentFile();
      if (parent != null && !parent.exists()) {
        //noinspection ResultOfMethodCallIgnored
        parent.mkdirs();
      }
      long resumeFrom = job.partFile.exists() ? job.partFile.length() : 0L;
      job.bytesDownloaded.set(resumeFrom);

      conn = openFollowingRedirects(job, resumeFrom);
      job.activeConn = conn;
      if (job.cancelRequested || job.pauseRequested) {
        return;
      }

      int code = conn.getResponseCode();
      String acceptRanges = conn.getHeaderField("Accept-Ranges");
      if (acceptRanges != null && "none".equalsIgnoreCase(acceptRanges.trim())) {
        job.supportsRange = false;
      }
      String etagHeader = conn.getHeaderField("ETag");
      if (etagHeader != null && !etagHeader.isEmpty()) {
        job.etag = etagHeader;
      }
      String serverMime = conn.getContentType();
      if (serverMime != null && !serverMime.isEmpty()) {
        int semi = serverMime.indexOf(';');
        job.mimeType = (semi > 0 ? serverMime.substring(0, semi) : serverMime).trim();
      }

      boolean append;
      if (code == HttpURLConnection.HTTP_PARTIAL && resumeFrom > 0) {
        append = true;
        job.supportsRange = true;
        long partLen = conn.getContentLengthLong();
        String contentRange = conn.getHeaderField("Content-Range");
        long parsedTotal = parseTotalFromContentRange(contentRange);
        if (parsedTotal > 0) {
          job.totalBytes = parsedTotal;
        } else if (partLen > 0) {
          job.totalBytes = resumeFrom + partLen;
        }
      } else if (code >= 200 && code < 300) {
        append = false;
        resumeFrom = 0L;
        job.bytesDownloaded.set(0L);
        long fullLen = conn.getContentLengthLong();
        if (fullLen > 0) {
          job.totalBytes = fullLen;
        }
      } else if (code == 416 && resumeFrom > 0 && job.totalBytes > 0 && resumeFrom >= job.totalBytes) {
        completeDownloadFile(job);
        return;
      } else {
        throw new IOException("HTTP " + code);
      }

      in = conn.getInputStream();
      job.activeStream = in;
      out = new FileOutputStream(job.partFile, append);

      byte[] buf = new byte[32 * 1024];
      long lastTickTime = SystemClock.elapsedRealtime();
      long lastTickBytes = job.bytesDownloaded.get();
      long lastNotifTime = 0L;

      int n;
      while ((n = in.read(buf)) != -1) {
        if (job.cancelRequested || job.pauseRequested) {
          break;
        }
        out.write(buf, 0, n);
        long nowBytes = job.bytesDownloaded.addAndGet(n);

        long nowMs = SystemClock.elapsedRealtime();
        long elapsed = nowMs - lastTickTime;
        if (elapsed >= 500L) {
          job.speedBytesPerSec = ((nowBytes - lastTickBytes) * 1000L) / Math.max(1L, elapsed);
          lastTickTime = nowMs;
          lastTickBytes = nowBytes;
        }
        if (nowMs - lastNotifTime >= 900L) {
          lastNotifTime = nowMs;
          postDownloadNotification(job);
        }
      }
      out.flush();

      if (job.cancelRequested) {
        cancelNotification(job.notifId());
        return;
      }
      if (job.pauseRequested) {
        job.state = "paused";
        job.speedBytesPerSec = 0L;
        postDownloadNotification(job);
        return;
      }

      completeDownloadFile(job);
    } catch (Throwable err) {
      if (job.cancelRequested) {
        cancelNotification(job.notifId());
      } else if (job.pauseRequested) {
        job.state = "paused";
        job.speedBytesPerSec = 0L;
        postDownloadNotification(job);
      } else {
        job.state = "failed";
        job.speedBytesPerSec = 0L;
        postDownloadNotification(job);
      }
    } finally {
      job.activeStream = null;
      job.activeConn = null;
      if (out != null) {
        try {
          out.close();
        } catch (IOException ignored) {
        }
      }
      if (in != null) {
        try {
          in.close();
        } catch (IOException ignored) {
        }
      }
      if (conn != null) {
        try {
          conn.disconnect();
        } catch (Throwable ignored) {
        }
      }
    }
  }

  private long parseTotalFromContentRange(String header) {
    if (header == null) {
      return -1L;
    }
    int slash = header.lastIndexOf('/');
    if (slash > 0 && slash + 1 < header.length()) {
      String tail = header.substring(slash + 1).trim();
      if (!"*".equals(tail)) {
        try {
          return Long.parseLong(tail);
        } catch (NumberFormatException ignored) {
        }
      }
    }
    return -1L;
  }

  private void completeDownloadFile(DownloadJob job) throws IOException {
    if (job.targetFile.exists()) {
      //noinspection ResultOfMethodCallIgnored
      job.targetFile.delete();
    }
    if (job.partFile.exists() && !job.partFile.renameTo(job.targetFile)) {
      throw new IOException("Unable to finalize downloaded file");
    }
    long finalLen = job.targetFile.length();
    job.bytesDownloaded.set(finalLen);
    job.totalBytes = finalLen;
    job.speedBytesPerSec = 0L;
    job.state = "completed";

    Context ctx = resolveContext();
    if (ctx != null) {
      String resolvedMime = resolveMimeForFile(job.targetFile, job.mimeType);
      job.mimeType = resolvedMime;
      try {
        MediaScannerConnection.scanFile(
            ctx,
            new String[] {job.targetFile.getAbsolutePath()},
            new String[] {resolvedMime},
            null);
      } catch (Throwable ignored) {
      }
    }
    postDownloadNotification(job);
  }

  private String resolveMimeForFile(File file, String fallbackMime) {
    String name = file.getName();
    int dot = name.lastIndexOf('.');
    if (dot >= 0 && dot + 1 < name.length()) {
      String ext = name.substring(dot + 1).toLowerCase(Locale.US);
      String fromExt = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
      if (fromExt != null && !fromExt.isEmpty()) {
        return fromExt;
      }
    }
    if (fallbackMime != null && !fallbackMime.isEmpty() && !"*/*".equals(fallbackMime)) {
      return fallbackMime;
    }
    return "application/octet-stream";
  }

  private static String formatBytesShort(long bytes) {
    if (bytes <= 0) return "0 B";
    if (bytes < 1024) return bytes + " B";
    double kb = bytes / 1024.0;
    if (kb < 1024.0) return String.format(Locale.US, "%.1f KB", kb);
    double mb = kb / 1024.0;
    if (mb < 1024.0) return String.format(Locale.US, "%.1f MB", mb);
    return String.format(Locale.US, "%.2f GB", mb / 1024.0);
  }

  private PendingIntent buildControlPendingIntent(Context ctx, long id, String cmd, int reqOffset) {
    Intent intent = new Intent(ACTION_DOWNLOAD_CONTROL);
    intent.setPackage(ctx.getPackageName());
    intent.putExtra("downloadId", id);
    intent.putExtra("cmd", cmd);
    int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
    return PendingIntent.getBroadcast(
        ctx, (int) ((Math.abs(id) % 10000L) * 10L) + reqOffset, intent, flags);
  }

  @SuppressWarnings("deprecation")
  private void postDownloadNotification(DownloadJob job) {
    if (!this.downloadNotificationsEnabled) {
      return;
    }
    Context ctx = resolveContext();
    if (ctx == null) {
      return;
    }
    NotificationManager nm =
        (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
    if (nm == null) {
      return;
    }
    ensureNotificationSetup();

    boolean done = "completed".equals(job.state);
    boolean paused = "paused".equals(job.state);
    boolean failed = "failed".equals(job.state);

    Notification.Builder builder;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      builder =
          new Notification.Builder(ctx, done ? NOTIF_CHANNEL_COMPLETE : NOTIF_CHANNEL_PROGRESS);
    } else {
      builder = new Notification.Builder(ctx);
    }

    builder.setContentTitle(job.fileName);
    builder.setOnlyAlertOnce(!done);
    builder.setAutoCancel(done || failed);

    long dl = job.bytesDownloaded.get();
    long tot = job.totalBytes;
    int pct = (tot > 0) ? (int) Math.min(100L, (dl * 100L) / tot) : 0;

    if (done) {
      builder.setSmallIcon(android.R.drawable.stat_sys_download_done);
      builder.setContentText("Download complete \u2022 " + formatBytesShort(tot) + " \u2022 Tap to open");
      builder.setOngoing(false);
      try {
        Uri uri = HeavenFileProvider.getUriForFile(job.targetFile);
        Intent viewIntent = new Intent(Intent.ACTION_VIEW);
        viewIntent.setDataAndType(uri, resolveMimeForFile(job.targetFile, job.mimeType));
        viewIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION);
        PendingIntent pi =
            PendingIntent.getActivity(
                ctx,
                job.notifId(),
                viewIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        builder.setContentIntent(pi);
      } catch (Throwable ignored) {
      }
    } else if (paused) {
      builder.setSmallIcon(android.R.drawable.ic_media_pause);
      String sub =
          tot > 0
              ? "Paused \u2022 " + pct + "% (" + formatBytesShort(dl) + " / " + formatBytesShort(tot) + ")"
              : "Paused \u2022 " + formatBytesShort(dl);
      builder.setContentText(sub);
      builder.setProgress(100, pct, false);
      builder.setOngoing(false);
      builder.addAction(
          new Notification.Action.Builder(
                  null, "Resume", buildControlPendingIntent(ctx, job.id, "resume", 1))
              .build());
      builder.addAction(
          new Notification.Action.Builder(
                  null, "Cancel", buildControlPendingIntent(ctx, job.id, "cancel", 2))
              .build());
    } else if (failed) {
      builder.setSmallIcon(android.R.drawable.stat_notify_error);
      builder.setContentText("Download interrupted \u2022 Tap Resume to retry");
      builder.setOngoing(false);
      builder.addAction(
          new Notification.Action.Builder(
                  null, "Resume", buildControlPendingIntent(ctx, job.id, "resume", 1))
              .build());
    } else {
      builder.setSmallIcon(android.R.drawable.stat_sys_download);
      String speedTxt =
          job.speedBytesPerSec > 0 ? " \u2022 " + formatBytesShort(job.speedBytesPerSec) + "/s" : "";
      String sub =
          tot > 0
              ? pct + "% \u2022 " + formatBytesShort(dl) + " / " + formatBytesShort(tot) + speedTxt
              : formatBytesShort(dl) + speedTxt;
      builder.setContentText(sub);
      builder.setProgress(100, pct, tot <= 0);
      builder.setOngoing(true);
      builder.addAction(
          new Notification.Action.Builder(
                  null, "Pause", buildControlPendingIntent(ctx, job.id, "pause", 3))
              .build());
      builder.addAction(
          new Notification.Action.Builder(
                  null, "Cancel", buildControlPendingIntent(ctx, job.id, "cancel", 2))
              .build());
    }

    try {
      nm.notify(job.notifId(), builder.build());
    } catch (SecurityException ignored) {
      // User declined notification permission on Android 13+.
    }
  }

  private void cancelNotification(int notifId) {
    Context ctx = resolveContext();
    if (ctx == null) return;
    NotificationManager nm =
        (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
    if (nm != null) {
      nm.cancel(notifId);
    }
  }

  private void handleQueryDownloads(MethodCall call, MethodChannel.Result result) {
    List<Number> rawIds = call.argument("downloadIds");
    if (rawIds == null || rawIds.isEmpty()) {
      result.success(Collections.emptyList());
      return;
    }
    List<Map<String, Object>> out = new ArrayList<>(rawIds.size());
    for (Number n : rawIds) {
      if (n == null) continue;
      DownloadJob job = downloadJobs.get(n.longValue());
      if (job != null) {
        out.add(job.toMap());
      }
    }
    result.success(out);
  }

  private void handleOpenDownloadedFile(MethodCall call, MethodChannel.Result result) {
    Context ctx = resolveContext();
    if (ctx == null) {
      result.success(false);
      return;
    }
    Object idObj = call.argument("downloadId");
    String localUriArg = call.argument("localUri");
    String mimeArg = call.argument("mimeType");

    File fileToOpen = null;
    if (idObj instanceof Number) {
      DownloadJob job = downloadJobs.get(((Number) idObj).longValue());
      if (job != null && job.targetFile.exists()) {
        fileToOpen = job.targetFile;
        if (mimeArg == null || mimeArg.isEmpty()) {
          mimeArg = job.mimeType;
        }
      }
    }
    if (fileToOpen == null && localUriArg != null && !localUriArg.isEmpty()) {
      String cleanPath =
          localUriArg.startsWith("file://") ? Uri.parse(localUriArg).getPath() : localUriArg;
      if (cleanPath != null) {
        File candidate = new File(cleanPath);
        if (candidate.exists()) {
          fileToOpen = candidate;
        }
      }
    }
    if (fileToOpen == null || !fileToOpen.exists()) {
      result.success(false);
      return;
    }

    try {
      Uri contentUri = HeavenFileProvider.getUriForFile(fileToOpen);
      String resolvedMime = resolveMimeForFile(fileToOpen, mimeArg);
      Intent viewIntent = new Intent(Intent.ACTION_VIEW);
      viewIntent.setDataAndType(contentUri, resolvedMime);
      viewIntent.addFlags(
          Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION);
      ctx.startActivity(viewIntent);
      result.success(true);
    } catch (Throwable e) {
      result.success(false);
    }
  }

  private boolean openDefaultBrowserSettings() {
    if (this.activity == null) {
      return false;
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        Intent intent = new Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS);
        this.activity.startActivity(intent);
        return true;
      }
    } catch (Exception ignored) {
    }
    try {
      Intent fallback = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
      fallback.setData(Uri.parse("package:" + this.activity.getPackageName()));
      this.activity.startActivity(fallback);
      return true;
    } catch (Exception ignored) {
      return false;
    }
  }

  private WebResourceResponse interceptIfAdOrTracker(long webViewId, WebResourceRequest request) {
    if (!shieldEnabled || request == null) {
      return null;
    }
    Uri url = request.getUrl();
    if (url == null) {
      return null;
    }
    String scheme = url.getScheme();
    if (scheme == null || (!"http".equalsIgnoreCase(scheme) && !"https".equalsIgnoreCase(scheme))) {
      return null;
    }
    String host = normalizeHost(url.getHost());
    if (host.isEmpty()) {
      return null;
    }
    String activePageHost = webViewId >= 0 ? currentPageHosts.get(webViewId) : null;
    if (activePageHost != null && isTrustedHost(activePageHost)) {
      return null;
    }
    if (request.isForMainFrame() && isTrustedHost(host)) {
      return null;
    }
    String fullPath = url.getEncodedPath() != null ? url.getEncodedPath().toLowerCase() : "";
    if (matchesBlockedDomain(host) || matchesAdPathSignature(host, fullPath, activePageHost)) {
      notifyBlockedOnMainThread(webViewId, host);
      return buildEmptyResponseForPath(fullPath, request);
    }
    return null;
  }

  private boolean isTrustedHost(String host) {
    for (String trusted : trustedHosts) {
      if (host.equals(trusted) || host.endsWith("." + trusted)) {
        return true;
      }
    }
    return false;
  }

  private boolean matchesBlockedDomain(String host) {
    Set<String> snapshot = this.blockedDomains;
    if (snapshot.contains(host)) {
      return true;
    }
    int dot = host.indexOf('.');
    while (dot != -1 && dot + 1 < host.length()) {
      String parent = host.substring(dot + 1);
      if (snapshot.contains(parent)) {
        return true;
      }
      dot = host.indexOf('.', dot + 1);
    }
    return false;
  }

  private boolean matchesAdPathSignature(String reqHost, String lowerPath, String pageHost) {
    boolean thirdParty =
        pageHost != null
            && !pageHost.isEmpty()
            && !reqHost.equals(pageHost)
            && !reqHost.endsWith("." + pageHost);
    if (!thirdParty) {
      return false;
    }
    return lowerPath.contains("/pagead/")
        || lowerPath.contains("/ads/ga-audiences")
        || lowerPath.contains("/adserver/")
        || lowerPath.contains("/prebid")
        || lowerPath.contains("/popunder")
        || lowerPath.endsWith("/adsbygoogle.js")
        || lowerPath.endsWith("/gpt.js")
        || lowerPath.endsWith("/analytics.js");
  }

  private WebResourceResponse buildEmptyResponseForPath(
      String lowerPath, WebResourceRequest request) {
    Map<String, String> headers = new HashMap<>(4);
    headers.put("Access-Control-Allow-Origin", "*");
    headers.put("Cache-Control", "no-store");

    String accept = "";
    Map<String, String> reqHeaders = request.getRequestHeaders();
    if (reqHeaders != null) {
      for (Map.Entry<String, String> e : reqHeaders.entrySet()) {
        if ("accept".equalsIgnoreCase(e.getKey()) && e.getValue() != null) {
          accept = e.getValue().toLowerCase();
          break;
        }
      }
    }
    if (lowerPath.endsWith(".js") || accept.contains("javascript")) {
      return new WebResourceResponse(
          "application/javascript", "UTF-8", 200, "OK", headers, new ByteArrayInputStream(EMPTY_JS));
    }
    if (lowerPath.endsWith(".gif")
        || lowerPath.endsWith(".png")
        || lowerPath.endsWith(".jpg")
        || lowerPath.endsWith(".jpeg")
        || lowerPath.endsWith(".webp")
        || accept.contains("image/")) {
      return new WebResourceResponse(
          "image/gif", null, 200, "OK", headers, new ByteArrayInputStream(TRANSPARENT_GIF));
    }
    if (request.isForMainFrame() || accept.contains("text/html")) {
      return new WebResourceResponse(
          "text/html", "UTF-8", 200, "OK", headers, new ByteArrayInputStream(EMPTY_HTML));
    }
    return new WebResourceResponse(
        "text/plain", "UTF-8", 200, "OK", headers, new ByteArrayInputStream(EMPTY_TEXT));
  }

  private void notifyBlockedOnMainThread(final long webViewId, final String domain) {
    mainHandler.post(
        () -> {
          MethodChannel ch = this.channel;
          if (ch != null) {
            Map<String, Object> payload = new HashMap<>(4);
            payload.put("webViewId", webViewId);
            payload.put("domain", domain);
            ch.invokeMethod("onResourceBlocked", payload);
          }
        });
  }

  private static String normalizeHost(String raw) {
    if (raw == null) {
      return "";
    }
    String clean = raw.trim().toLowerCase();
    if (clean.startsWith("www.")) {
      clean = clean.substring(4);
    }
    return clean;
  }

  private final class ShieldWebViewClient extends WebViewClient {
    private final long webViewId;
    private final WebViewClient delegate;

    ShieldWebViewClient(long webViewId, WebViewClient delegate) {
      this.webViewId = webViewId;
      this.delegate = delegate;
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
      WebResourceResponse blocked = interceptIfAdOrTracker(webViewId, request);
      if (blocked != null) {
        return blocked;
      }
      return delegate != null
          ? delegate.shouldInterceptRequest(view, request)
          : super.shouldInterceptRequest(view, request);
    }

    @Override
    @SuppressWarnings("deprecation")
    public WebResourceResponse shouldInterceptRequest(WebView view, String url) {
      return delegate != null
          ? delegate.shouldInterceptRequest(view, url)
          : super.shouldInterceptRequest(view, url);
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
      if (request != null && request.isForMainFrame() && request.getUrl() != null) {
        String host = normalizeHost(request.getUrl().getHost());
        if (!host.isEmpty()) {
          currentPageHosts.put(webViewId, host);
        }
      }
      return delegate != null
          ? delegate.shouldOverrideUrlLoading(view, request)
          : super.shouldOverrideUrlLoading(view, request);
    }

    @Override
    @SuppressWarnings("deprecation")
    public boolean shouldOverrideUrlLoading(WebView view, String url) {
      return delegate != null
          ? delegate.shouldOverrideUrlLoading(view, url)
          : super.shouldOverrideUrlLoading(view, url);
    }

    @Override
    public void onPageStarted(WebView view, String url, Bitmap favicon) {
      if (url != null) {
        Uri parsed = Uri.parse(url);
        String host = normalizeHost(parsed.getHost());
        if (!host.isEmpty()) {
          currentPageHosts.put(webViewId, host);
        }
      }
      if (desktopMode) {
        applyDesktopSettingsToWebView(view, true);
      }
      if (delegate != null) {
        delegate.onPageStarted(view, url, favicon);
      } else {
        super.onPageStarted(view, url, favicon);
      }
      injectScripts(view);
    }

    @Override
    public void onPageCommitVisible(WebView view, String url) {
      if (delegate != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        delegate.onPageCommitVisible(view, url);
      } else {
        super.onPageCommitVisible(view, url);
      }
      injectScripts(view);
    }

    @Override
    public void onPageFinished(WebView view, String url) {
      if (delegate != null) {
        delegate.onPageFinished(view, url);
      } else {
        super.onPageFinished(view, url);
      }
      injectScripts(view);
    }

    private void injectScripts(WebView view) {
      if (desktopMode) {
        view.evaluateJavascript(DESKTOP_VIEWPORT_SCRIPT, null);
      }
      if (!shieldEnabled) {
        return;
      }
      String pageHost = currentPageHosts.get(webViewId);
      if (pageHost != null && isTrustedHost(pageHost)) {
        return;
      }
      String script = cosmeticScript;
      if (script != null && !script.isEmpty()) {
        view.evaluateJavascript(script, null);
      }
    }

    @Override
    public void onLoadResource(WebView view, String url) {
      if (delegate != null) delegate.onLoadResource(view, url);
      else super.onLoadResource(view, url);
    }

    @Override
    public void onReceivedError(
        WebView view, WebResourceRequest request, WebResourceError error) {
      if (delegate != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        delegate.onReceivedError(view, request, error);
      } else {
        super.onReceivedError(view, request, error);
      }
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onReceivedError(
        WebView view, int errorCode, String description, String failingUrl) {
      if (delegate != null) {
        delegate.onReceivedError(view, errorCode, description, failingUrl);
      } else {
        super.onReceivedError(view, errorCode, description, failingUrl);
      }
    }

    @Override
    public void onReceivedHttpError(
        WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {
      if (delegate != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        delegate.onReceivedHttpError(view, request, errorResponse);
      } else {
        super.onReceivedHttpError(view, request, errorResponse);
      }
    }

    @Override
    public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
      if (delegate != null) delegate.onReceivedSslError(view, handler, error);
      else super.onReceivedSslError(view, handler, error);
    }

    @Override
    public void onReceivedClientCertRequest(WebView view, ClientCertRequest request) {
      if (delegate != null) delegate.onReceivedClientCertRequest(view, request);
      else super.onReceivedClientCertRequest(view, request);
    }

    @Override
    public void onReceivedHttpAuthRequest(
        WebView view, HttpAuthHandler handler, String host, String realm) {
      if (delegate != null) delegate.onReceivedHttpAuthRequest(view, handler, host, realm);
      else super.onReceivedHttpAuthRequest(view, handler, host, realm);
    }

    @Override
    public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
      if (delegate != null) delegate.doUpdateVisitedHistory(view, url, isReload);
      else super.doUpdateVisitedHistory(view, url, isReload);
    }

    @Override
    public void onFormResubmission(WebView view, Message dontResend, Message resend) {
      if (delegate != null) delegate.onFormResubmission(view, dontResend, resend);
      else super.onFormResubmission(view, dontResend, resend);
    }

    @Override
    public boolean shouldOverrideKeyEvent(WebView view, KeyEvent event) {
      return delegate != null
          ? delegate.shouldOverrideKeyEvent(view, event)
          : super.shouldOverrideKeyEvent(view, event);
    }

    @Override
    public void onUnhandledKeyEvent(WebView view, KeyEvent event) {
      if (delegate != null) delegate.onUnhandledKeyEvent(view, event);
      else super.onUnhandledKeyEvent(view, event);
    }

    @Override
    public void onScaleChanged(WebView view, float oldScale, float newScale) {
      if (delegate != null) delegate.onScaleChanged(view, oldScale, newScale);
      else super.onScaleChanged(view, oldScale, newScale);
    }
  }
}
