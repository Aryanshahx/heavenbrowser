package com.hypertechlabs.heavenbrowser;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.KeyguardManager;
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
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.drawable.Icon;
import android.hardware.biometrics.BiometricManager;
import android.hardware.biometrics.BiometricPrompt;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.CancellationSignal;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.DocumentsContract;
import android.provider.Settings;
import android.speech.RecognizerIntent;
import android.view.MotionEvent;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.MimeTypeMap;
import android.webkit.WebSettings;
import android.webkit.WebStorage;
import android.webkit.WebView;
import androidx.webkit.ScriptHandler;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
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
  private static final String NOTIF_CHANNEL_ALERTS = "heaven_alerts_v13";
  private static final int VOICE_SEARCH_REQUEST_CODE = 49021;
  private static final int NOTIF_PERM_REQUEST_CODE = 49022;
  private static final int FOLDER_PICKER_REQUEST_CODE = 49025;
  private static final int SITE_HARDWARE_PERM_REQUEST_CODE = 49027;
  private static final int LEGACY_CREDENTIAL_REQUEST_CODE = 49028;

  private static final String DESKTOP_CHROME_WIN_UA =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
          + "(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";

  private static final String MOBILE_CHROME_ANDROID_UA =
      "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 "
          + "(KHTML, like Gecko) Chrome/134.0.0.0 Mobile Safari/537.36";

  private static final String DESKTOP_VIEWPORT_SCRIPT =
      "(function(){"
          + "try{"
          + "Object.defineProperty(navigator,'platform',{get:()=>'Win32',configurable:true});"
          + "Object.defineProperty(navigator,'vendor',{get:()=>'Google Inc.',configurable:true});"
          + "Object.defineProperty(navigator,'maxTouchPoints',{get:()=>0,configurable:true});"
          + "Object.defineProperty(navigator,'userAgentData',{get:()=>({"
          + "brands:[{brand:'Chromium',version:'134'},{brand:'Google Chrome',version:'134'},{brand:'Not:A-Brand',version:'24'}],"
          + "mobile:false,platform:'Windows',"
          + "getHighEntropyValues:function(){return Promise.resolve({architecture:'x86',bitness:'64',mobile:false,model:'',platform:'Windows',platformVersion:'15.0.0',uaFullVersion:'134.0.6998.89'});}"
          + "}),configurable:true});"
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

  private static final String BG_AUDIO_AND_SCROLL_SCRIPT =
      "(function(){"
          + "try{"
          + "if(window.__heavenMediaHookV16)return;"
          + "window.__heavenMediaHookV16=true;"
          + "window.__hbInBg=window.__hbInBg||false;"
          + "if(window.__heavenWebNotifsBlocked&&window.Notification){"
          + "  try{"
          + "    Object.defineProperty(Notification,'permission',{configurable:true,get:function(){return 'denied';}});"
          + "    Notification.requestPermission=function(cb){if(typeof cb==='function')cb('denied');return Promise.resolve('denied');};"
          + "  }catch(e){}"
          + "}"
          + "var isGoogleSerp=(location.hostname||'').indexOf('www.google.')===0&&location.pathname==='/search';"
          + "if(window.__heavenBgMediaEnabled&&!isGoogleSerp){"
          + "  try{"
          + "    var origHiddenDesc=Object.getOwnPropertyDescriptor(Document.prototype,'hidden');"
          + "    var origVisDesc=Object.getOwnPropertyDescriptor(Document.prototype,'visibilityState');"
          + "    Object.defineProperty(Document.prototype,'hidden',{configurable:true,get:function(){return window.__hbInBg?false:(origHiddenDesc&&origHiddenDesc.get?origHiddenDesc.get.call(this):false);}});"
          + "    Object.defineProperty(Document.prototype,'webkitHidden',{configurable:true,get:function(){return window.__hbInBg?false:(origHiddenDesc&&origHiddenDesc.get?origHiddenDesc.get.call(this):false);}});"
          + "    Object.defineProperty(Document.prototype,'visibilityState',{configurable:true,get:function(){return window.__hbInBg?'visible':(origVisDesc&&origVisDesc.get?origVisDesc.get.call(this):'visible');}});"
          + "    Object.defineProperty(Document.prototype,'webkitVisibilityState',{configurable:true,get:function(){return window.__hbInBg?'visible':(origVisDesc&&origVisDesc.get?origVisDesc.get.call(this):'visible');}});"
          + "    var guardBgVis=function(ev){if(window.__hbInBg&&ev){ev.stopImmediatePropagation();ev.stopPropagation();}};"
          + "    window.addEventListener('visibilitychange',guardBgVis,true);"
          + "    window.addEventListener('webkitvisibilitychange',guardBgVis,true);"
          + "    document.addEventListener('visibilitychange',guardBgVis,true);"
          + "    document.addEventListener('webkitvisibilitychange',guardBgVis,true);"
          + "    document.addEventListener('freeze',guardBgVis,true);"
          + "    window.addEventListener('pagehide',guardBgVis,true);"
          + "    var origPause=HTMLMediaElement.prototype.pause;"
          + "    HTMLMediaElement.prototype.pause=function(){"
          + "      if(window.__hbInBg&&this.__hbShouldPlayInBg&&!window.__hbMediaCmdPause&&!this.ended){"
          + "        return;"
          + "      }"
          + "      return origPause.apply(this,arguments);"
          + "    };"
          + "    setInterval(function(){if(window.__hbInBg){try{window._lact=Date.now();}catch(e){}}},5000);"
          + "  }catch(e){}"
          + "}"
          + "var lastAtTop=true;var lastInnerSy=0;var lastInnerEmitMs=0;"
          + "window.addEventListener('scroll',function(ev){"
          + "  try{"
          + "    var t=ev&&ev.target;"
          + "    var winSy=window.pageYOffset||document.documentElement.scrollTop||0;"
          + "    var isInner=(t&&t!==document&&t!==window&&typeof t.scrollTop==='number');"
          + "    var sy=winSy;"
          + "    if(isInner&&t.scrollTop>sy){sy=t.scrollTop;}"
          + "    var nowTop=(sy<=6);"
          + "    if(nowTop!==lastAtTop){"
          + "      lastAtTop=nowTop;"
          + "      if(window.HeavenMediaBridge&&window.HeavenMediaBridge.onPageAtTop){window.HeavenMediaBridge.onPageAtTop(nowTop);}"
          + "    }"
          + "    if(isInner&&winSy<=4&&window.HeavenMediaBridge&&window.HeavenMediaBridge.onInnerScroll){"
          + "      var dy=t.scrollTop-lastInnerSy;"
          + "      lastInnerSy=t.scrollTop;"
          + "      var nowMs=Date.now();"
          + "      if(Math.abs(dy)>=6&&(nowMs-lastInnerEmitMs)>=55){"
          + "        lastInnerEmitMs=nowMs;"
          + "        window.HeavenMediaBridge.onInnerScroll(Math.round(t.scrollTop),Math.round(dy));"
          + "      }"
          + "    }"
          + "  }catch(e){}"
          + "},{passive:true,capture:true});"
          + "function reportMedia(el,playing,ended){"
          + "  try{"
          + "    if(!window.HeavenMediaBridge)return;"
          + "    window.HeavenMediaBridge.onPlaybackState(!!playing,!!ended,document.title||location.hostname||'Heaven',location.hostname||'Heaven');"
          + "  }catch(e){}"
          + "}"
          + "document.addEventListener('play',function(ev){var t=ev&&ev.target;if(t&&(t.tagName==='VIDEO'||t.tagName==='AUDIO')){t.__hbShouldPlayInBg=true;window.__hbMediaCmdPause=false;reportMedia(t,true,false);}},true);"
          + "document.addEventListener('playing',function(ev){var t=ev&&ev.target;if(t&&(t.tagName==='VIDEO'||t.tagName==='AUDIO')){t.__hbShouldPlayInBg=true;window.__hbMediaCmdPause=false;reportMedia(t,true,false);}},true);"
          + "document.addEventListener('ended',function(ev){var t=ev&&ev.target;if(t&&(t.tagName==='VIDEO'||t.tagName==='AUDIO')){t.__hbShouldPlayInBg=false;reportMedia(t,false,true);}},true);"
          + "document.addEventListener('pause',function(ev){"
          + "  var t=ev&&ev.target;"
          + "  if(!t||(t.tagName!=='VIDEO'&&t.tagName!=='AUDIO'))return;"
          + "  if(window.__hbInBg&&t.__hbShouldPlayInBg&&!window.__hbMediaCmdPause&&!t.ended){"
          + "    setTimeout(function(){try{t.play().catch(function(){});}catch(e){}},30);"
          + "    return;"
          + "  }"
          + "  t.__hbShouldPlayInBg=false;"
          + "  reportMedia(t,false,!!t.ended);"
          + "},true);"
          + "}catch(_){}"
          + "})();";

  private static final class DownloadJob {
    final long id;
    final String url;
    volatile String resolvedUrl;
    volatile String fileName;
    volatile String mimeType;
    final String userAgent;
    final String cookies;
    final String referer;
    volatile File targetFile;
    volatile File partFile;

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
      this.resolvedUrl = url;
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
  private MethodChannel.Result pendingSiteHardwarePermResult;
  private MethodChannel.Result pendingBiometricResult;
  private HeavenVpnManager vpnManager;
  private HeavenBraveShieldEngine braveShieldEngine;
  private volatile long activeFocusedWebViewId = -1L;

  private final ExecutorService downloadPool = Executors.newCachedThreadPool();
  private final Map<Long, DownloadJob> downloadJobs = new ConcurrentHashMap<>();
  private final AtomicLong idGenerator = new AtomicLong(System.currentTimeMillis());
  private BroadcastReceiver controlReceiver;
  private BroadcastReceiver mediaCmdReceiver;
  private boolean notifChannelsReady = false;
  private volatile String customDownloadPath = "";
  private volatile boolean downloadNotificationsEnabled = true;

  private volatile boolean desktopMode = false;
  private volatile boolean backgroundMediaEnabled = true;
  private volatile boolean webNotificationsEnabled = false;
  private volatile boolean backgroundPlayNotifEnabled = true;

  private volatile boolean appInBackground = false;
  private volatile boolean userPausedFromNotification = false;
  private volatile boolean activeAudioOrVideoPlaying = false;
  private volatile long activeMediaWebViewId = -1L;
  private volatile String activeMediaTitle = "Heaven";
  private volatile String activeMediaHost = "Heaven";
  private final Map<Long, Boolean> lastNavBarVisibleByWv = new ConcurrentHashMap<>();
  private final Map<Long, Long> lastNavToggleMsByWv = new ConcurrentHashMap<>();
  private final Map<Long, Integer> accumulatedScrollDyByWv = new ConcurrentHashMap<>();
  private final Map<Long, Long> pageLoadingUntilMsByWv = new ConcurrentHashMap<>();
  private final Map<Long, Boolean> pageAtTopByWv = new ConcurrentHashMap<>();
  private final Runnable bgKeepAliveLoop =
      new Runnable() {
        @Override
        public void run() {
          if (!appInBackground || !backgroundMediaEnabled || !activeAudioOrVideoPlaying) {
            return;
          }
          keepActiveMediaWebViewAwake();
          mainHandler.postDelayed(this, 1100L);
        }
      };
  private final Map<Long, Boolean> lastDesktopApplied = new ConcurrentHashMap<>();
  private final Map<Long, ScriptHandler> docStartHandlers = new ConcurrentHashMap<>();

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
    this.braveShieldEngine = new HeavenBraveShieldEngine(appCtx);
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    registerDownloadControlReceiver(appCtx);
    registerMediaCommandReceiver(appCtx);
    try {
      WebView.setWebContentsDebuggingEnabled(true);
    } catch (Throwable ignored) {
    }
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    unregisterDownloadControlReceiver(binding.getApplicationContext());
    unregisterMediaCommandReceiver(binding.getApplicationContext());
    stopBackgroundMediaService();
    if (this.braveShieldEngine != null) {
      this.braveShieldEngine.shutdown();
      this.braveShieldEngine = null;
    }
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

  public void onActivityPaused() {
    this.appInBackground = true;
    broadcastBgFlagToWebViews(true);
    if (!this.backgroundMediaEnabled || !this.activeAudioOrVideoPlaying) {
      return;
    }
    startOrUpdateBackgroundMediaService();
    mainHandler.removeCallbacks(bgKeepAliveLoop);
    keepActiveMediaWebViewAwake();
    mainHandler.postDelayed(this::keepActiveMediaWebViewAwake, 120L);
    mainHandler.postDelayed(this::keepActiveMediaWebViewAwake, 420L);
    mainHandler.postDelayed(bgKeepAliveLoop, 1000L);
  }

  public void onActivityStopped() {
    this.appInBackground = true;
    broadcastBgFlagToWebViews(true);
    if (!this.backgroundMediaEnabled || !this.activeAudioOrVideoPlaying) {
      return;
    }
    startOrUpdateBackgroundMediaService();
    mainHandler.removeCallbacks(bgKeepAliveLoop);
    keepActiveMediaWebViewAwake();
    mainHandler.postDelayed(this::keepActiveMediaWebViewAwake, 80L);
    mainHandler.postDelayed(this::keepActiveMediaWebViewAwake, 320L);
    mainHandler.postDelayed(bgKeepAliveLoop, 900L);
  }

  public void onActivityResumed() {
    this.appInBackground = false;
    mainHandler.removeCallbacks(bgKeepAliveLoop);
    broadcastBgFlagToWebViews(false);
    if (!this.activeAudioOrVideoPlaying) {
      stopBackgroundMediaService();
    }
  }

  private void broadcastBgFlagToWebViews(final boolean inBg) {
    if (pluginBinding == null) {
      return;
    }
    final String js = "window.__hbInBg=" + inBg + ";";
    for (Long id : new ArrayList<>(docStartHandlers.keySet())) {
      if (id == null) continue;
      try {
        WebView wv = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, id);
        if (wv != null) {
          wv.evaluateJavascript(js, null);
        }
      } catch (Throwable ignored) {
      }
    }
  }

  private void keepActiveMediaWebViewAwake() {
    if (!this.backgroundMediaEnabled
        || !this.activeAudioOrVideoPlaying
        || this.userPausedFromNotification
        || pluginBinding == null) {
      return;
    }
    long targetId = activeMediaWebViewId >= 0 ? activeMediaWebViewId : activeFocusedWebViewId;
    if (targetId < 0) {
      return;
    }
    try {
      WebView wv = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, targetId);
      if (wv != null) {
        wv.dispatchWindowVisibilityChanged(View.VISIBLE);
        wv.onResume();
        wv.resumeTimers();
        wv.evaluateJavascript(
            "(function(){try{"
                + "window.__hbInBg=true;window._lact=Date.now();"
                + "var list=document.querySelectorAll('video,audio');"
                + "for(var i=0;i<list.length;i++){"
                + "  var m=list[i];"
                + "  if((m.__hbShouldPlayInBg||i===0)&&m.paused&&!m.ended&&!window.__hbMediaCmdPause){"
                + "    m.play().catch(function(){});"
                + "  }"
                + "}"
                + "}catch(e){}})();",
            null);
      }
    } catch (Throwable ignored) {
    }
  }

  private void startOrUpdateBackgroundMediaService() {
    if (!this.backgroundMediaEnabled) {
      return;
    }
    Context ctx = resolveContext();
    if (ctx == null) {
      return;
    }
    try {
      Intent svc = new Intent(ctx, HeavenMediaService.class);
      svc.setAction(HeavenMediaService.ACTION_START_OR_UPDATE);
      svc.putExtra(HeavenMediaService.EXTRA_TITLE, activeMediaTitle);
      svc.putExtra(HeavenMediaService.EXTRA_HOST, activeMediaHost);
      svc.putExtra(HeavenMediaService.EXTRA_PLAYING, activeAudioOrVideoPlaying);
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        ctx.startForegroundService(svc);
      } else {
        ctx.startService(svc);
      }
    } catch (Throwable ignored) {
    }
  }

  private void stopBackgroundMediaService() {
    Context ctx = resolveContext();
    if (ctx == null) {
      return;
    }
    try {
      ctx.stopService(new Intent(ctx, HeavenMediaService.class));
    } catch (Throwable ignored) {
    }
  }

  private void registerMediaCommandReceiver(Context appContext) {
    if (appContext == null || mediaCmdReceiver != null) {
      return;
    }
    mediaCmdReceiver =
        new BroadcastReceiver() {
          @Override
          public void onReceive(Context context, Intent intent) {
            if (intent == null
                || !HeavenMediaService.ACTION_BROADCAST_MEDIA_CMD.equals(intent.getAction())) {
              return;
            }
            String cmd = intent.getStringExtra("cmd");
            long targetId =
                activeMediaWebViewId >= 0 ? activeMediaWebViewId : activeFocusedWebViewId;
            if (pluginBinding == null || targetId < 0 || cmd == null) {
              return;
            }
            WebView wv = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, targetId);
            if (wv == null) {
              return;
            }
            if ("toggle".equals(cmd)) {
              cmd = activeAudioOrVideoPlaying ? "pause" : "play";
            }
            if ("pause".equals(cmd) || "stop".equals(cmd)) {
              userPausedFromNotification = true;
              activeAudioOrVideoPlaying = false;
              mainHandler.removeCallbacks(bgKeepAliveLoop);
              wv.evaluateJavascript(
                  "(function(){window.__hbMediaCmdPause=true;var l=document.querySelectorAll('video,audio');for(var i=0;i<l.length;i++){try{l[i].__hbShouldPlayInBg=false;l[i].pause();}catch(e){}}})();",
                  null);
              if ("stop".equals(cmd)) {
                stopBackgroundMediaService();
              } else {
                startOrUpdateBackgroundMediaService();
              }
            } else if ("play".equals(cmd)) {
              userPausedFromNotification = false;
              activeAudioOrVideoPlaying = true;
              wv.dispatchWindowVisibilityChanged(View.VISIBLE);
              wv.onResume();
              wv.resumeTimers();
              wv.evaluateJavascript(
                  "(function(){window.__hbMediaCmdPause=false;var m=document.querySelector('video,audio');if(m){m.__hbShouldPlayInBg=true;try{m.play().catch(function(){});}catch(e){}}})();",
                  null);
              startOrUpdateBackgroundMediaService();
              if (appInBackground && backgroundMediaEnabled) {
                mainHandler.removeCallbacks(bgKeepAliveLoop);
                mainHandler.postDelayed(bgKeepAliveLoop, 1000L);
              }
            }
          }
        };
    IntentFilter filter = new IntentFilter(HeavenMediaService.ACTION_BROADCAST_MEDIA_CMD);
    if (Build.VERSION.SDK_INT >= 33) {
      appContext.registerReceiver(mediaCmdReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
    } else {
      appContext.registerReceiver(mediaCmdReceiver, filter);
    }
  }

  private void unregisterMediaCommandReceiver(Context appContext) {
    if (appContext != null && mediaCmdReceiver != null) {
      try {
        appContext.unregisterReceiver(mediaCmdReceiver);
      } catch (IllegalArgumentException ignored) {
      }
      mediaCmdReceiver = null;
    }
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
    progressChannel.setDescription("Live progress for files downloading in Heaven");
    progressChannel.setShowBadge(false);
    nm.createNotificationChannel(progressChannel);

    NotificationChannel completeChannel =
        new NotificationChannel(
            NOTIF_CHANNEL_COMPLETE,
            "Completed Downloads",
            NotificationManager.IMPORTANCE_DEFAULT);
    completeChannel.setDescription("Alerts when a download finishes");
    nm.createNotificationChannel(completeChannel);

    NotificationChannel alertsChannel =
        new NotificationChannel(
            NOTIF_CHANNEL_ALERTS,
            "Security & Media Alerts",
            NotificationManager.IMPORTANCE_DEFAULT);
    alertsChannel.setDescription("Security anti-redirect alerts and Heaven notifications");
    nm.createNotificationChannel(alertsChannel);
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
    if (requestCode == LEGACY_CREDENTIAL_REQUEST_CODE) {
      MethodChannel.Result bioCb = this.pendingBiometricResult;
      this.pendingBiometricResult = null;
      if (bioCb != null) {
        bioCb.success(resultCode == Activity.RESULT_OK);
      }
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
    if (requestCode == SITE_HARDWARE_PERM_REQUEST_CODE) {
      MethodChannel.Result cb = this.pendingSiteHardwarePermResult;
      this.pendingSiteHardwarePermResult = null;
      if (cb != null) {
        boolean allGranted = grantResults != null && grantResults.length > 0;
        if (allGranted) {
          for (int g : grantResults) {
            if (g != PackageManager.PERMISSION_GRANTED) {
              allGranted = false;
              break;
            }
          }
        }
        cb.success(allGranted);
      }
      return true;
    }
    return false;
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
        handleUpdateConfig(call);
        result.success(true);
        break;

      case "attachToWebView":
        Object idObj = call.argument("webViewId");
        Boolean initDesktop = call.argument("desktopMode");
        String initHost = call.argument("pageHost");
        if (initDesktop != null) {
          this.desktopMode = initDesktop;
        }
        if (idObj instanceof Number) {
          long wvId = ((Number) idObj).longValue();
          this.activeFocusedWebViewId = wvId;
          pageAtTopByWv.put(wvId, Boolean.TRUE);
          if (braveShieldEngine != null && initHost != null) {
            braveShieldEngine.setPageHostForWebView(wvId, initHost);
          }
          boolean attached = attachShieldToWebView(wvId);
          result.success(attached);
        } else {
          result.success(false);
        }
        break;

      case "focusWebView":
        Object focusObj = call.argument("webViewId");
        if (focusObj instanceof Number && pluginBinding != null) {
          long fWvId = ((Number) focusObj).longValue();
          this.activeFocusedWebViewId = fWvId;
          try {
            WebView wv = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, fWvId);
            if (wv != null) {
              wv.onResume();
              wv.resumeTimers();
            }
          } catch (Throwable ignored) {
          }
          result.success(true);
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
          long targetWvId = ((Number) dvId).longValue();
          WebView wv = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, targetWvId);
          if (wv != null) {
            applyDesktopSettingsToWebView(wv, targetWvId, wantDesktop, false);
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
        String updatedHost = call.argument("pageHost");
        if (wvIdObj instanceof Number) {
          long id = ((Number) wvIdObj).longValue();
          this.activeFocusedWebViewId = id;
          if (braveShieldEngine != null) {
            braveShieldEngine.setPageHostForWebView(id, updatedHost);
          }
          pageLoadingUntilMsByWv.put(id, SystemClock.elapsedRealtime() + 650L);
          pageAtTopByWv.put(id, Boolean.TRUE);
          accumulatedScrollDyByWv.put(id, 0);
          emitNavBarVisibility(id, true);
        }
        result.success(true);
        break;

      case "getBraveShieldStats":
        Object statsWvObj = call.argument("webViewId");
        long statsWvId = (statsWvObj instanceof Number) ? ((Number) statsWvObj).longValue() : -1L;
        if (braveShieldEngine != null) {
          result.success(braveShieldEngine.getStatsSnapshot(statsWvId));
        } else {
          result.success(Collections.singletonMap("enabled", false));
        }
        break;

      case "refreshBraveFilterLists":
        if (braveShieldEngine != null) {
          braveShieldEngine.forceRefreshFilterLists(
              () -> mainHandler.post(() -> result.success(braveShieldEngine.getStatsSnapshot(-1L))));
        } else {
          result.success(Collections.singletonMap("enabled", false));
        }
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

      case "sendTestNotification":
        result.success(handleSendTestNotification());
        break;

      case "isBiometricAvailable":
        result.success(checkBiometricAvailable());
        break;

      case "authenticateBiometric":
        String bioReason = call.argument("reason");
        handleAuthenticateBiometric(bioReason, result);
        break;

      case "requestSiteHardwarePermissions":
        List<String> permNames = call.argument("permissions");
        handleRequestSiteHardwarePermissions(permNames, result);
        break;

      case "provisionFreeWarpConfig":
        if (vpnManager != null) {
          vpnManager.provisionFreeWarpConfig(result);
        } else {
          result.success(Collections.singletonMap("ok", false));
        }
        break;

      case "provisionForeignOpenVpnConfig":
        if (vpnManager != null) {
          String countryCode = call.argument("countryCode");
          List<String> excludeHosts = call.argument("excludeHosts");
          vpnManager.provisionForeignOpenVpnConfig(
              countryCode != null ? countryCode : "AUTO_FOREIGN", excludeHosts, result);
        } else {
          result.success(Collections.singletonMap("ok", false));
        }
        break;

      case "fetchLiveForeignCountries":
        if (vpnManager != null) {
          vpnManager.fetchLiveForeignCountries(result);
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
          Boolean bOnly = call.argument("browserOnly");
          vpnManager.connectVpn(
              this.activity,
              cfgText != null ? cfgText : "",
              profName != null ? profName : "Heaven Free VPN",
              bOnly == null || bOnly,
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
    int targetW = 270;
      float scale = (float) targetW / (float) srcW;
      int targetH = Math.max(180, Math.min(540, Math.round(srcH * scale)));

      Bitmap bitmap = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      canvas.drawColor(Color.WHITE);
      canvas.scale(scale, scale);
      canvas.translate(-webView.getScrollX(), -webView.getScrollY());
      webView.draw(canvas);

      downloadPool.execute(
          () -> {
            try {
              if (isUniformBlankBitmap(bitmap)) {
                bitmap.recycle();
                mainHandler.post(() -> result.success(null));
                return;
              }
              ByteArrayOutputStream out = new ByteArrayOutputStream(20 * 1024);
              bitmap.compress(Bitmap.CompressFormat.JPEG, 76, out);
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

  private static boolean isUniformBlankBitmap(Bitmap bmp) {
    if (bmp == null || bmp.getWidth() < 8 || bmp.getHeight() < 8) {
      return true;
    }
    int w = bmp.getWidth();
    int h = bmp.getHeight();
    int first = bmp.getPixel(w / 2, h / 2) & 0x00FFFFFF;
    int[] xs = {w / 8, w / 4, w / 2, (w * 3) / 4, (w * 7) / 8};
    int[] ys = {h / 8, h / 4, h / 2, (h * 3) / 4, (h * 7) / 8};
    for (int y : ys) {
      for (int x : xs) {
        int px = bmp.getPixel(x, y) & 0x00FFFFFF;
        if (px != first) {
          return false;
        }
      }
    }
    return true;
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
    Boolean desktopArg = call.argument("desktopMode");
    if (desktopArg != null) {
      this.desktopMode = desktopArg;
    }
    Boolean bgMediaArg = call.argument("backgroundMediaEnabled");
    if (bgMediaArg != null) {
      this.backgroundMediaEnabled = bgMediaArg;
      if (!bgMediaArg) {
        mainHandler.removeCallbacks(bgKeepAliveLoop);
        stopBackgroundMediaService();
      }
    }
    Boolean webNotifArg = call.argument("webNotificationsEnabled");
    if (webNotifArg != null) {
      this.webNotificationsEnabled = webNotifArg;
    }
    Boolean bgPlayNotifArg = call.argument("backgroundPlayNotificationEnabled");
    if (bgPlayNotifArg != null) {
      this.backgroundPlayNotifEnabled = bgPlayNotifArg;
    }
    if (this.braveShieldEngine != null) {
      Boolean shieldsArg = call.argument("braveShieldsEnabled");
      Boolean farblingArg = call.argument("farblingEnabled");
      List<String> disabledHostsArg = call.argument("disabledShieldHosts");
      this.braveShieldEngine.updateConfiguration(
          shieldsArg == null || shieldsArg,
          farblingArg == null || farblingArg,
          disabledHostsArg);
    }
    refreshAllDocumentStartHandlers();
  }

  private String buildDocumentStartBundle() {
    String braveScript =
        (this.braveShieldEngine != null)
            ? this.braveShieldEngine.buildDocumentStartProtectionScript()
            : "";
    return braveScript
        + "window.__heavenBgMediaEnabled="
        + this.backgroundMediaEnabled
        + ";window.__heavenWebNotifsBlocked="
        + (!this.webNotificationsEnabled)
        + ";window.__hbInBg="
        + this.appInBackground
        + ";"
        + BG_AUDIO_AND_SCROLL_SCRIPT;
  }

  private void installOrRefreshDocumentStartShield(WebView webView, long webViewId) {
    if (webView == null) {
      return;
    }
    try {
      ScriptHandler old = docStartHandlers.remove(webViewId);
      if (old != null) {
        try {
          old.remove();
        } catch (Throwable ignored) {
        }
      }
      if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
        ScriptHandler next =
            WebViewCompat.addDocumentStartJavaScript(
                webView, buildDocumentStartBundle(), Collections.singleton("*"));
        docStartHandlers.put(webViewId, next);
      }
    } catch (Throwable ignored) {
    }
  }

  private void refreshAllDocumentStartHandlers() {
    if (pluginBinding == null || docStartHandlers.isEmpty()) {
      return;
    }
    for (Long id : new ArrayList<>(docStartHandlers.keySet())) {
      if (id == null) continue;
      try {
        WebView wv = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, id);
        if (wv != null) {
          installOrRefreshDocumentStartShield(wv, id);
        } else {
          docStartHandlers.remove(id);
        }
      } catch (Throwable ignored) {
      }
    }
  }

  private void applyDesktopSettingsToWebView(
      WebView webView, long webViewId, boolean enableDesktop, boolean forceApply) {
    try {
      Boolean prev = webViewId >= 0 ? lastDesktopApplied.get(webViewId) : null;
      boolean modeUnchanged = prev != null && prev == enableDesktop;
      WebSettings settings = webView.getSettings();
      settings.setUseWideViewPort(enableDesktop);
      settings.setLoadWithOverviewMode(enableDesktop);
      settings.setSupportZoom(true);
      settings.setBuiltInZoomControls(true);
      settings.setDisplayZoomControls(false);
      // Allow website download buttons / popups to navigate directly in the active WebView
      // and trigger DownloadListener cleanly without popup traps!
      settings.setJavaScriptCanOpenWindowsAutomatically(true);
      settings.setSupportMultipleWindows(false);
      if (!forceApply && modeUnchanged) {
        return;
      }
      if (webViewId >= 0) {
        lastDesktopApplied.put(webViewId, enableDesktop);
      }
      if (enableDesktop) {
        settings.setUserAgentString(DESKTOP_CHROME_WIN_UA);
        webView.setInitialScale(0);
        webView.evaluateJavascript(DESKTOP_VIEWPORT_SCRIPT, null);
      } else if (prev != null && prev) {
        // Only reset UA/scale when actually transitioning back from Desktop -> Mobile!
        settings.setUserAgentString(MOBILE_CHROME_ANDROID_UA);
        webView.setInitialScale(0);
        webView.evaluateJavascript(MOBILE_VIEWPORT_RESET_SCRIPT, null);
      }
    } catch (Throwable ignored) {
    }
  }

  private void emitNavBarVisibility(final long webViewId, final boolean visible) {
    Boolean prev = lastNavBarVisibleByWv.get(webViewId);
    if (prev != null && prev == visible) {
      return;
    }
    lastNavBarVisibleByWv.put(webViewId, visible);
    lastNavToggleMsByWv.put(webViewId, SystemClock.elapsedRealtime());
    accumulatedScrollDyByWv.put(webViewId, 0);
    mainHandler.post(
        () -> {
          MethodChannel ch = channel;
          if (ch != null) {
            Map<String, Object> ev = new HashMap<>(4);
            ev.put("webViewId", webViewId);
            ev.put("visible", visible);
            ch.invokeMethod("onWebScrollNavBar", ev);
          }
        });
  }

  private void processScrollDeltaForNavBar(final long webViewId, int scrollY, int dy) {
    if (scrollY <= 18) {
      accumulatedScrollDyByWv.put(webViewId, 0);
      emitNavBarVisibility(webViewId, true);
      return;
    }
    long nowMs = SystemClock.elapsedRealtime();
    Long loadingLockUntil = pageLoadingUntilMsByWv.get(webViewId);
    if (loadingLockUntil != null && nowMs < loadingLockUntil) {
      return;
    }
    Long lastToggle = lastNavToggleMsByWv.get(webViewId);
    if (lastToggle != null && (nowMs - lastToggle) < 340L) {
      accumulatedScrollDyByWv.put(webViewId, 0);
      return;
    }
    if (Math.abs(dy) > 480) {
      return;
    }
    Integer prevAcc = accumulatedScrollDyByWv.get(webViewId);
    int acc = prevAcc != null ? prevAcc : 0;
    if ((acc > 0 && dy < 0) || (acc < 0 && dy > 0)) {
      acc = dy;
    } else {
      acc += dy;
    }
    accumulatedScrollDyByWv.put(webViewId, acc);
    if (acc <= -28) {
      emitNavBarVisibility(webViewId, true);
    } else if (acc >= 48 && scrollY > 76) {
      emitNavBarVisibility(webViewId, false);
    }
  }

  private final class WebViewMediaJsBridge {
    private final long webViewId;

    WebViewMediaJsBridge(long webViewId) {
      this.webViewId = webViewId;
    }

    @JavascriptInterface
    public void onPageAtTop(boolean atTop) {
      pageAtTopByWv.put(webViewId, atTop);
    }

    @JavascriptInterface
    public void onInnerScroll(int scrollTop, int dy) {
      pageAtTopByWv.put(webViewId, scrollTop <= 6);
      processScrollDeltaForNavBar(webViewId, scrollTop, dy);
    }

    @JavascriptInterface
    public void onPlaybackState(boolean playing, boolean ended, String title, String host) {
      if (!playing && appInBackground && !ended && !userPausedFromNotification) {
        return;
      }
      activeMediaWebViewId = webViewId;
      activeAudioOrVideoPlaying = playing;
      if (playing) {
        userPausedFromNotification = false;
      }
      if (title != null && !title.trim().isEmpty()) {
        activeMediaTitle = title.trim();
      }
      if (host != null && !host.trim().isEmpty()) {
        activeMediaHost = host.trim();
      }
      mainHandler.post(
          () -> {
            if (playing && backgroundMediaEnabled && backgroundPlayNotifEnabled) {
              startOrUpdateBackgroundMediaService();
              if (appInBackground) {
                mainHandler.removeCallbacks(bgKeepAliveLoop);
                mainHandler.postDelayed(bgKeepAliveLoop, 1000L);
              }
            } else if (!playing && !appInBackground) {
              stopBackgroundMediaService();
            } else if (!playing && ended) {
              mainHandler.removeCallbacks(bgKeepAliveLoop);
              stopBackgroundMediaService();
            }
            MethodChannel ch = channel;
            if (ch != null) {
              Map<String, Object> ev = new HashMap<>(6);
              ev.put("webViewId", webViewId);
              ev.put("playing", playing);
              ev.put("title", activeMediaTitle);
              ch.invokeMethod("onMediaPlaybackChanged", ev);
            }
          });
    }
  }

  @SuppressLint("JavascriptInterface")
  private boolean attachShieldToWebView(final long webViewId) {
    if (pluginBinding == null) {
      return false;
    }
    try {
      WebView webView = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, webViewId);
      if (webView == null) {
        return false;
      }

      WebSettings ws = webView.getSettings();
      ws.setMediaPlaybackRequiresUserGesture(false);
      ws.setDomStorageEnabled(true);
      ws.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
      ws.setBlockNetworkImage(false);
      webView.onResume();
      webView.resumeTimers();
      try {
        webView.addJavascriptInterface(
            new WebViewMediaJsBridge(webViewId), "HeavenMediaBridge");
      } catch (Throwable ignored) {
      }

      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        webView.setOnScrollChangeListener(
            (v, scrollX, scrollY, oldScrollX, oldScrollY) -> {
              pageAtTopByWv.put(webViewId, scrollY <= 6);
              processScrollDeltaForNavBar(webViewId, scrollY, scrollY - oldScrollY);
            });
      }

      if (this.braveShieldEngine != null) {
        this.braveShieldEngine.attachToWebView(webView, webViewId);
      }
      applyDesktopSettingsToWebView(webView, webViewId, this.desktopMode, false);
      installOrRefreshDocumentStartShield(webView, webViewId);
      installPullToRefreshListener(webView, webViewId);
      installDownloadListener(webView, webViewId);
      return true;
    } catch (Throwable ignored) {
    }
    return false;
  }

  private void installPullToRefreshListener(final WebView webView, final long webViewId) {
    final float density = webView.getResources().getDisplayMetrics().density;
    final float triggerPx = 88.0f * density;
    final float touchSlopPx = 14.0f * density;

    webView.setOnTouchListener(
        new View.OnTouchListener() {
          private float startY = -1f;
          private float startX = -1f;
          private boolean trackingTopPull = false;
          private boolean draggingRefresh = false;
          private double lastEmittedProgress = 0.0;
          private long lastEmitMs = 0L;

          private boolean isWebPageAtTop() {
            if (webView.getScrollY() > 8) {
              return false;
            }
            Boolean jsTop = pageAtTopByWv.get(webViewId);
            return jsTop == null || jsTop;
          }

          @Override
          public boolean onTouch(View v, MotionEvent event) {
            int action = event.getActionMasked();
            if (event.getPointerCount() > 1) {
              if (draggingRefresh) {
                emitPullProgress(webViewId, 0.0);
              }
              trackingTopPull = false;
              draggingRefresh = false;
              lastEmittedProgress = 0.0;
              return false;
            }

            switch (action) {
              case MotionEvent.ACTION_DOWN:
                if (isWebPageAtTop()) {
                  startY = event.getRawY();
                  startX = event.getRawX();
                  trackingTopPull = true;
                  draggingRefresh = false;
                  lastEmittedProgress = 0.0;
                } else {
                  trackingTopPull = false;
                  draggingRefresh = false;
                }
                break;

              case MotionEvent.ACTION_MOVE:
                if (!trackingTopPull) {
                  break;
                }
                if (!draggingRefresh && !isWebPageAtTop()) {
                  trackingTopPull = false;
                  break;
                }
                float dy = event.getRawY() - startY;
                float dx = Math.abs(event.getRawX() - startX);
                if (!draggingRefresh) {
                  if (dy > touchSlopPx && dy > dx * 1.3f) {
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
                  } else if (dy < -touchSlopPx || dx > touchSlopPx * 1.8f) {
                    trackingTopPull = false;
                  }
                }
                if (draggingRefresh) {
                  double progress = Math.min(1.0, Math.max(0.0, (dy - touchSlopPx) / triggerPx));
                  long now = SystemClock.elapsedRealtime();
                  if ((now - lastEmitMs) >= 20L
                      && Math.abs(progress - lastEmittedProgress) >= 0.025) {
                    lastEmitMs = now;
                    lastEmittedProgress = progress;
                    emitPullProgress(webViewId, progress);
                  }
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
                  lastEmittedProgress = 0.0;
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

                String guessedName = resolveSmartFileName(url, contentDisposition, mimeType);
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
  private void handleCreateHomeScreenShortcut(
      final MethodCall call, final MethodChannel.Result result) {
    final Context ctx = resolveContext();
    final String title = call.argument("title");
    final String url = call.argument("url");
    final String explicitIconUrl = call.argument("iconUrl");
    final Object webViewIdObj = call.argument("webViewId");
    if (ctx == null || url == null || url.trim().isEmpty()) {
      result.success(false);
      return;
    }
    final String cleanUrl = url.trim();
    String computedTitle =
        (title != null && !title.trim().isEmpty()) ? title.trim() : cleanUrl;
    if (computedTitle.length() > 28) {
      computedTitle = computedTitle.substring(0, 28).trim();
    }
    final String cleanTitle = computedTitle;

    Bitmap liveFaviconCopy = null;
    if (webViewIdObj instanceof Number && pluginBinding != null) {
      try {
        WebView wv =
            WebViewFlutterAndroidExternalApi.getWebView(
                pluginBinding, ((Number) webViewIdObj).longValue());
        if (wv != null && wv.getFavicon() != null && !wv.getFavicon().isRecycled()) {
          liveFaviconCopy =
              wv.getFavicon().copy(Bitmap.Config.ARGB_8888, false);
        }
      } catch (Throwable ignored) {
      }
    }
    final Bitmap fallbackWebViewBmp = liveFaviconCopy;

    downloadPool.execute(
        () -> {
          Bitmap fetchedLogo =
              downloadBestWebsiteLogoBitmap(cleanUrl, explicitIconUrl, fallbackWebViewBmp);
          final Bitmap iconBmp =
              fetchedLogo != null
                  ? composeWebsiteLogoLauncherBitmap(fetchedLogo)
                  : buildShortcutIconBitmap(cleanTitle);

          mainHandler.post(
              () -> {
                Intent launchIntent = new Intent(Intent.ACTION_VIEW, Uri.parse(cleanUrl));
                launchIntent.setClassName(
                    ctx.getPackageName(), "com.hypertechlabs.heavenbrowser.MainActivity");
                launchIntent.addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);

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
                  Intent legacy =
                      new Intent("com.android.launcher.action.INSTALL_SHORTCUT");
                  legacy.putExtra(Intent.EXTRA_SHORTCUT_INTENT, launchIntent);
                  legacy.putExtra(Intent.EXTRA_SHORTCUT_NAME, cleanTitle);
                  legacy.putExtra(Intent.EXTRA_SHORTCUT_ICON, iconBmp);
                  ctx.sendBroadcast(legacy);
                  result.success(true);
                } catch (Throwable t) {
                  result.success(false);
                }
              });
        });
  }

  private static Bitmap downloadBestWebsiteLogoBitmap(
      String pageUrl, String explicitIconUrl, Bitmap webViewFavicon) {
    List<String> candidates = new ArrayList<>(6);
    if (explicitIconUrl != null
        && (explicitIconUrl.startsWith("https://") || explicitIconUrl.startsWith("http://"))) {
      candidates.add(explicitIconUrl.trim());
    }
    try {
      Uri u = Uri.parse(pageUrl);
      String host = u.getHost();
      String scheme = u.getScheme() != null ? u.getScheme() : "https";
      if (host != null && !host.isEmpty()) {
        candidates.add(scheme + "://" + host + "/apple-touch-icon.png");
        candidates.add(
            "https://www.google.com/s2/favicons?sz=256&domain_url=" + Uri.encode(pageUrl));
        candidates.add("https://icons.duckduckgo.com/ip3/" + host + ".ico");
        candidates.add(scheme + "://" + host + "/favicon.ico");
      }
    } catch (Throwable ignored) {
    }

    Bitmap bestSmall = webViewFavicon;
    for (String iconEndpoint : candidates) {
      Bitmap decoded = fetchRemoteBitmap(iconEndpoint);
      if (decoded != null) {
        if (decoded.getWidth() >= 64 && decoded.getHeight() >= 64) {
          return decoded;
        }
        if (bestSmall == null
            || (decoded.getWidth() * decoded.getHeight())
                > (bestSmall.getWidth() * bestSmall.getHeight())) {
          bestSmall = decoded;
        }
      }
    }
    return bestSmall;
  }

  private static Bitmap fetchRemoteBitmap(String urlStr) {
    HttpURLConnection conn = null;
    try {
      conn = (HttpURLConnection) URI.create(urlStr).toURL().openConnection();
      conn.setInstanceFollowRedirects(true);
      conn.setConnectTimeout(4500);
      conn.setReadTimeout(5500);
      conn.setRequestProperty(
          "User-Agent",
          "Mozilla/5.0 (Linux; Android 15; Mobile) AppleWebKit/537.36 Chrome/134.0.0.0");
      int code = conn.getResponseCode();
      if (code < 200 || code >= 300) {
        return null;
      }
      try (InputStream is = conn.getInputStream();
          ByteArrayOutputStream bos = new ByteArrayOutputStream()) {
        byte[] buf = new byte[8192];
        int n;
        int total = 0;
        while ((n = is.read(buf)) > 0) {
          total += n;
          if (total > 3 * 1024 * 1024) {
            return null;
          }
          bos.write(buf, 0, n);
        }
        byte[] bytes = bos.toByteArray();
        Bitmap bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
        if (bmp != null && bmp.getWidth() >= 16 && bmp.getHeight() >= 16) {
          return bmp;
        }
      }
    } catch (Throwable ignored) {
      return null;
    } finally {
      if (conn != null) {
        conn.disconnect();
      }
    }
    return null;
  }

  private static Bitmap composeWebsiteLogoLauncherBitmap(Bitmap srcLogo) {
    int size = 192;
    Bitmap out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
    Canvas canvas = new Canvas(out);

    RectF outerRect = new RectF(8f, 8f, size - 8f, size - 8f);
    Path clipPath = new Path();
    clipPath.addRoundRect(outerRect, 42f, 42f, Path.Direction.CW);

    Paint bgPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    bgPaint.setColor(Color.WHITE);
    canvas.drawRoundRect(outerRect, 42f, 42f, bgPaint);

    Paint bmpPaint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
    canvas.save();
    canvas.clipPath(clipPath);
    if (srcLogo.getWidth() >= 96 && srcLogo.getHeight() >= 96) {
      canvas.drawBitmap(srcLogo, null, outerRect, bmpPaint);
    } else {
      float pad = 28f;
      RectF inset = new RectF(pad, pad, size - pad, size - pad);
      canvas.drawBitmap(srcLogo, null, inset, bmpPaint);
    }
    canvas.restore();
    return out;
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

  @SuppressWarnings("deprecation")
  private boolean handleSendTestNotification() {
    Context ctx = resolveContext();
    if (ctx == null) {
      return false;
    }
    ensureNotificationSetup();
    NotificationManager nm =
        (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
    if (nm == null) {
      return false;
    }
    try {
      Intent openIntent = new Intent(Intent.ACTION_MAIN);
      openIntent.setClassName(
          ctx.getPackageName(), "com.hypertechlabs.heavenbrowser.MainActivity");
      openIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
      PendingIntent pi =
          PendingIntent.getActivity(
              ctx,
              9913,
              openIntent,
              PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
      Notification.Builder b =
          Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
              ? new Notification.Builder(ctx, NOTIF_CHANNEL_ALERTS)
              : new Notification.Builder(ctx);
      b.setSmallIcon(android.R.drawable.ic_popup_reminder)
          .setContentTitle("Heaven Notifications Active")
          .setContentText("Download progress, background audio & shield alerts are ready.")
          .setAutoCancel(true)
          .setContentIntent(pi);
      nm.notify(89130, b.build());
      return true;
    } catch (Throwable ignored) {
      return false;
    }
  }

  @SuppressWarnings("deprecation")
  private boolean checkBiometricAvailable() {
    Context ctx = resolveContext();
    if (ctx == null) {
      return false;
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        BiometricManager bm = ctx.getSystemService(BiometricManager.class);
        if (bm != null) {
          int can =
              bm.canAuthenticate(
                  BiometricManager.Authenticators.BIOMETRIC_STRONG
                      | BiometricManager.Authenticators.BIOMETRIC_WEAK
                      | BiometricManager.Authenticators.DEVICE_CREDENTIAL);
          return can == BiometricManager.BIOMETRIC_SUCCESS;
        }
      } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        BiometricManager bm = ctx.getSystemService(BiometricManager.class);
        if (bm != null && bm.canAuthenticate() == BiometricManager.BIOMETRIC_SUCCESS) {
          return true;
        }
      }
      KeyguardManager km = (KeyguardManager) ctx.getSystemService(Context.KEYGUARD_SERVICE);
      return km != null && km.isKeyguardSecure();
    } catch (Throwable ignored) {
      return false;
    }
  }

  @SuppressWarnings("deprecation")
  private void handleAuthenticateBiometric(String reason, final MethodChannel.Result result) {
    final Activity act = this.activity;
    if (act == null) {
      result.success(false);
      return;
    }
    final String subtitle =
        (reason != null && !reason.trim().isEmpty())
            ? reason.trim()
            : "Verify identity to unlock private session";

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      try {
        BiometricPrompt.Builder builder =
            new BiometricPrompt.Builder(act)
                .setTitle("Heaven Security")
                .setSubtitle(subtitle);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
          builder.setAllowedAuthenticators(
              BiometricManager.Authenticators.BIOMETRIC_STRONG
                  | BiometricManager.Authenticators.BIOMETRIC_WEAK
                  | BiometricManager.Authenticators.DEVICE_CREDENTIAL);
        } else if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
          builder.setDeviceCredentialAllowed(true);
        } else {
          builder.setNegativeButton(
              "Cancel", act.getMainExecutor(), (dialog, which) -> result.success(false));
        }

        final AtomicLong settled = new AtomicLong(0L);
        BiometricPrompt prompt = builder.build();
        CancellationSignal cancelSig = new CancellationSignal();
        prompt.authenticate(
            cancelSig,
            act.getMainExecutor(),
            new BiometricPrompt.AuthenticationCallback() {
              @Override
              public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult res) {
                if (settled.compareAndSet(0L, 1L)) {
                  mainHandler.post(() -> result.success(true));
                }
              }

              @Override
              public void onAuthenticationError(int errorCode, CharSequence errString) {
                if (settled.compareAndSet(0L, 1L)) {
                  mainHandler.post(() -> result.success(false));
                }
              }
            });
        return;
      } catch (Throwable ignored) {
      }
    }

    try {
      KeyguardManager km = (KeyguardManager) act.getSystemService(Context.KEYGUARD_SERVICE);
      if (km != null && km.isKeyguardSecure()) {
        Intent credIntent =
            km.createConfirmDeviceCredentialIntent("Heaven Security", subtitle);
        if (credIntent != null) {
          this.pendingBiometricResult = result;
          act.startActivityForResult(credIntent, LEGACY_CREDENTIAL_REQUEST_CODE);
          return;
        }
      }
    } catch (Throwable ignored) {
    }
    result.success(false);
  }

  private void handleRequestSiteHardwarePermissions(
      List<String> requested, MethodChannel.Result result) {
    if (requested == null || requested.isEmpty()) {
      result.success(true);
      return;
    }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      result.success(true);
      return;
    }
    if (this.activity == null) {
      result.success(false);
      return;
    }
    List<String> missing = new ArrayList<>();
    for (String perm : requested) {
      if (perm != null
          && !perm.isEmpty()
          && this.activity.checkSelfPermission(perm) != PackageManager.PERMISSION_GRANTED) {
        missing.add(perm);
      }
    }
    if (missing.isEmpty()) {
      result.success(true);
      return;
    }
    this.pendingSiteHardwarePermResult = result;
    this.activity.requestPermissions(
        missing.toArray(new String[0]), SITE_HARDWARE_PERM_REQUEST_CODE);
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
    String safe = sanitizeDownloadFileName(rawName);
    if (safe.isEmpty()) {
      safe = "download";
    }
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

  private static String sanitizeDownloadFileName(String raw) {
    if (raw == null) return "";
    String s = raw.trim();
    int slash = Math.max(s.lastIndexOf('/'), s.lastIndexOf('\\'));
    if (slash >= 0 && slash + 1 < s.length()) {
      s = s.substring(slash + 1);
    }
    s = s.replaceAll("[\\\\/:*?\"<>|\\p{Cntrl}]", "_").trim();
    while (s.startsWith(".")) {
      s = s.substring(1).trim();
    }
    if (s.length() > 180) {
      int dot = s.lastIndexOf('.');
      if (dot > 0 && s.length() - dot <= 12) {
        String ext = s.substring(dot);
        s = s.substring(0, 180 - ext.length()) + ext;
      } else {
        s = s.substring(0, 180);
      }
    }
    return s;
  }

  private static String extractValidExtension(String name) {
    if (name == null) return "";
    int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot + 1 >= name.length()) {
      return "";
    }
    String ext = name.substring(dot + 1).trim().toLowerCase(Locale.US);
    if (ext.isEmpty() || ext.length() > 10 || !ext.matches("[a-z0-9]+")) {
      return "";
    }
    if ("bin".equals(ext)
        || "download".equals(ext)
        || "tmp".equals(ext)
        || "part".equals(ext)
        || "php".equals(ext)
        || "ashx".equals(ext)
        || "aspx".equals(ext)
        || "jsp".equals(ext)
        || "cgi".equals(ext)) {
      return "";
    }
    return ext;
  }

  private static String stripTrailingBinOrGenericExt(String name) {
    if (name == null || name.isEmpty()) return "download";
    int dot = name.lastIndexOf('.');
    if (dot > 0 && dot + 1 < name.length()) {
      String ext = name.substring(dot + 1).toLowerCase(Locale.US);
      if ("bin".equals(ext)
          || "download".equals(ext)
          || "php".equals(ext)
          || "ashx".equals(ext)
          || "aspx".equals(ext)
          || "jsp".equals(ext)) {
        return name.substring(0, dot);
      }
    }
    return name;
  }

  private static String decodePercentSafe(String raw) {
    if (raw == null || raw.isEmpty()) return "";
    try {
      return URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8");
    } catch (Throwable ignored) {
      return raw;
    }
  }

  private static String extractDispositionFileName(String contentDisposition) {
    if (contentDisposition == null || contentDisposition.trim().isEmpty()) {
      return "";
    }
    String cd = contentDisposition.trim();
    // 1. RFC 5987 filename*=UTF-8''encoded_name.ext
    String lower = cd.toLowerCase(Locale.US);
    int starIdx = lower.indexOf("filename*=");
    if (starIdx >= 0) {
      String rest = cd.substring(starIdx + 10).trim();
      int semi = rest.indexOf(';');
      if (semi >= 0) {
        rest = rest.substring(0, semi).trim();
      }
      if ((rest.startsWith("\"") && rest.endsWith("\""))
          || (rest.startsWith("'") && rest.endsWith("'"))) {
        rest = rest.substring(1, rest.length() - 1);
      }
      int dblQuote = rest.indexOf("''");
      if (dblQuote >= 0 && dblQuote + 2 < rest.length()) {
        rest = rest.substring(dblQuote + 2);
      }
      String decoded = sanitizeDownloadFileName(decodePercentSafe(rest));
      if (!decoded.isEmpty()) {
        return decoded;
      }
    }
    // 2. Standard filename="name.ext" or filename=name.ext
    int fnIdx = lower.indexOf("filename=");
    if (fnIdx >= 0) {
      String rest = cd.substring(fnIdx + 9).trim();
      if (rest.startsWith("\"")) {
        int endQ = rest.indexOf('"', 1);
        rest = endQ > 1 ? rest.substring(1, endQ) : rest.substring(1);
      } else if (rest.startsWith("'")) {
        int endQ = rest.indexOf('\'', 1);
        rest = endQ > 1 ? rest.substring(1, endQ) : rest.substring(1);
      } else {
        int semi = rest.indexOf(';');
        if (semi >= 0) {
          rest = rest.substring(0, semi).trim();
        }
      }
      String decoded = sanitizeDownloadFileName(decodePercentSafe(rest));
      if (!decoded.isEmpty()) {
        return decoded;
      }
    }
    return "";
  }

  private static String extractUrlFileName(String rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty()) {
      return "";
    }
    try {
      Uri u = Uri.parse(rawUrl.trim());
      String rcd = u.getQueryParameter("response-content-disposition");
      if (rcd != null && !rcd.isEmpty()) {
        String fromRcd = extractDispositionFileName(rcd);
        if (!fromRcd.isEmpty()) return fromRcd;
      }
      String[] hintParams = {"filename", "file", "name", "download", "attachment", "title"};
      for (String p : hintParams) {
        String val = u.getQueryParameter(p);
        if (val != null && !val.trim().isEmpty() && val.contains(".")) {
          String clean = sanitizeDownloadFileName(decodePercentSafe(val));
          if (!extractValidExtension(clean).isEmpty()) {
            return clean;
          }
        }
      }
      String seg = u.getLastPathSegment();
      if (seg != null && !seg.trim().isEmpty()) {
        String cleanSeg = sanitizeDownloadFileName(decodePercentSafe(seg));
        if (!cleanSeg.isEmpty()) {
          return cleanSeg;
        }
      }
    } catch (Throwable ignored) {
    }
    return "";
  }

  private static String extensionFromMimeOrMagic(
      String rawMime, String urlHint, byte[] magic, int magicLen) {
    // 1. Magic byte signatures (100% ground-truth file content when server sends octet-stream!)
    if (magic != null && magicLen >= 4) {
      int b0 = magic[0] & 0xFF;
      int b1 = magic[1] & 0xFF;
      int b2 = magic[2] & 0xFF;
      int b3 = magic[3] & 0xFF;
      if (b0 == 0x25 && b1 == 0x50 && b2 == 0x44 && b3 == 0x46) {
        return "pdf";
      }
      if (b0 == 0x50 && b1 == 0x4B && b2 == 0x03 && b3 == 0x04) {
        String asciiHead =
            new String(magic, 0, Math.min(magicLen, 16384), StandardCharsets.ISO_8859_1);
        String lowerUrl = urlHint != null ? urlHint.toLowerCase(Locale.US) : "";
        String lowerMime = rawMime != null ? rawMime.toLowerCase(Locale.US) : "";
        if (asciiHead.contains("AndroidManifest.xml")
            || asciiHead.contains("classes.dex")
            || lowerMime.contains("android.package-archive")
            || lowerUrl.contains(".apk")) {
          return "apk";
        }
        if (asciiHead.contains("word/document.xml")) return "docx";
        if (asciiHead.contains("xl/workbook.xml")) return "xlsx";
        if (asciiHead.contains("ppt/presentation.xml")) return "pptx";
        if (asciiHead.contains("META-INF/MANIFEST.MF") && lowerUrl.contains(".jar")) return "jar";
        if (asciiHead.contains("mimetypeapplication/epub+zip")) return "epub";
        return "zip";
      }
      if (b0 == 0x89 && b1 == 0x50 && b2 == 0x4E && b3 == 0x47) return "png";
      if (b0 == 0xFF && b1 == 0xD8 && b2 == 0xFF) return "jpg";
      if (b0 == 0x47 && b1 == 0x49 && b2 == 0x46 && b3 == 0x38) return "gif";
      if (magicLen >= 12
          && b0 == 0x52
          && b1 == 0x49
          && b2 == 0x46
          && b3 == 0x46
          && magic[8] == 'W'
          && magic[9] == 'E'
          && magic[10] == 'B'
          && magic[11] == 'P') {
        return "webp";
      }
      if (magicLen >= 12
          && b0 == 0x52
          && b1 == 0x49
          && b2 == 0x46
          && b3 == 0x46
          && magic[8] == 'W'
          && magic[9] == 'A'
          && magic[10] == 'V'
          && magic[11] == 'E') {
        return "wav";
      }
      if (magicLen >= 12
          && magic[4] == 'f'
          && magic[5] == 't'
          && magic[6] == 'y'
          && magic[7] == 'p') {
        String brand = new String(magic, 8, 4, StandardCharsets.US_ASCII).toLowerCase(Locale.US);
        if (brand.startsWith("m4a")) return "m4a";
        if (brand.startsWith("qt")) return "mov";
        if (brand.startsWith("avif") || brand.startsWith("avis")) return "avif";
        return "mp4";
      }
      if ((b0 == 'I' && b1 == 'D' && b2 == '3')
          || (b0 == 0xFF && (b1 & 0xE0) == 0xE0 && (b1 & 0x18) != 0x08)) {
        return "mp3";
      }
      if (b0 == 'f' && b1 == 'L' && b2 == 'a' && b3 == 'C') return "flac";
      if (b0 == 'O' && b1 == 'g' && b2 == 'g' && b3 == 'S') return "ogg";
      if (b0 == 0x1A && b1 == 0x45 && b2 == 0xDF && b3 == 0xA3) {
        String head = new String(magic, 0, Math.min(magicLen, 128), StandardCharsets.ISO_8859_1);
        return head.toLowerCase(Locale.US).contains("webm") ? "webm" : "mkv";
      }
      if (b0 == 'R' && b1 == 'a' && b2 == 'r' && b3 == '!') return "rar";
      if (magicLen >= 6 && b0 == 0x37 && b1 == 0x7A && b2 == 0xBC && b3 == 0xAF) return "7z";
      if (b0 == 0x1F && b1 == 0x8B) return "gz";
    }

    // 2. Clean MIME type mapping (NEVER maps application/octet-stream to .bin!)
    if (rawMime != null && !rawMime.trim().isEmpty()) {
      String m = rawMime.trim().toLowerCase(Locale.US);
      int semi = m.indexOf(';');
      if (semi > 0) m = m.substring(0, semi).trim();
      if (!"application/octet-stream".equals(m)
          && !"binary/octet-stream".equals(m)
          && !"application/force-download".equals(m)
          && !"application/x-download".equals(m)
          && !"application/download".equals(m)
          && !"*/*".equals(m)) {
        switch (m) {
          case "application/vnd.android.package-archive":
            return "apk";
          case "application/pdf":
            return "pdf";
          case "application/zip":
          case "application/x-zip-compressed":
            return "zip";
          case "application/vnd.rar":
          case "application/x-rar-compressed":
            return "rar";
          case "application/x-7z-compressed":
            return "7z";
          case "application/gzip":
          case "application/x-gzip":
            return "gz";
          case "application/x-tar":
            return "tar";
          case "application/json":
            return "json";
          case "application/epub+zip":
            return "epub";
          case "text/plain":
            return "txt";
          case "text/csv":
            return "csv";
          case "text/html":
            return "html";
          case "video/mp4":
            return "mp4";
          case "video/webm":
            return "webm";
          case "video/x-matroska":
            return "mkv";
          case "audio/mpeg":
          case "audio/mp3":
            return "mp3";
          case "audio/mp4":
          case "audio/x-m4a":
            return "m4a";
          case "audio/wav":
          case "audio/x-wav":
            return "wav";
          case "audio/ogg":
            return "ogg";
          case "image/jpeg":
          case "image/jpg":
            return "jpg";
          case "image/png":
            return "png";
          case "image/webp":
            return "webp";
          case "image/gif":
            return "gif";
          case "image/svg+xml":
            return "svg";
          default:
            String sysExt = MimeTypeMap.getSingleton().getExtensionFromMimeType(m);
            if (sysExt != null
                && !sysExt.isEmpty()
                && !"bin".equalsIgnoreCase(sysExt)) {
              return sysExt.toLowerCase(Locale.US);
            }
            break;
        }
      }
    }
    return "";
  }

  private static String resolveSmartFileName(
      String url, String contentDisposition, String mimeType) {
    String dispName = extractDispositionFileName(contentDisposition);
    String urlName = extractUrlFileName(url);
    String chosen = !dispName.isEmpty() ? dispName : urlName;

    String existingExt = extractValidExtension(chosen);
    if (!existingExt.isEmpty()) {
      return chosen;
    }
    String urlExt = extractValidExtension(urlName);
    String base = stripTrailingBinOrGenericExt(chosen.isEmpty() ? "download" : chosen);
    if (base.isEmpty()) {
      base = "download";
    }
    if (!urlExt.isEmpty()) {
      return base + "." + urlExt;
    }
    String mimeExt = extensionFromMimeOrMagic(mimeType, url, null, 0);
    if (!mimeExt.isEmpty()) {
      return base + "." + mimeExt;
    }
    return base;
  }

  private void refineDownloadJobTarget(
      DownloadJob job,
      String responseDisposition,
      String responseMime,
      byte[] firstChunk,
      int firstChunkLen) {
    try {
      String dispName = extractDispositionFileName(responseDisposition);
      String finalUrlName = extractUrlFileName(job.resolvedUrl);
      String currentExt = extractValidExtension(job.fileName);

      String bestCandidate = !dispName.isEmpty() ? dispName : job.fileName;
      if ((bestCandidate == null
              || bestCandidate.isEmpty()
              || "download".equalsIgnoreCase(stripTrailingBinOrGenericExt(bestCandidate)))
          && !finalUrlName.isEmpty()) {
        bestCandidate = finalUrlName;
      }

      String candExt = extractValidExtension(bestCandidate);
      String detectedExt =
          extensionFromMimeOrMagic(
              responseMime, job.resolvedUrl, firstChunk, firstChunkLen);

      String finalName;
      if (!candExt.isEmpty()) {
        // Keep true extension unless server gave .zip header on a verified Android .apk!
        if ("zip".equals(candExt) && "apk".equals(detectedExt)) {
          finalName = bestCandidate.substring(0, bestCandidate.lastIndexOf('.')) + ".apk";
        } else {
          finalName = bestCandidate;
        }
      } else {
        String cleanBase =
            stripTrailingBinOrGenericExt(
                bestCandidate != null && !bestCandidate.isEmpty() ? bestCandidate : "download");
        if (cleanBase.isEmpty()) cleanBase = "download";
        String extToUse = !detectedExt.isEmpty() ? detectedExt : extractValidExtension(finalUrlName);
        if (extToUse.isEmpty() && !currentExt.isEmpty()) {
          extToUse = currentExt;
        }
        finalName = extToUse.isEmpty() ? cleanBase : (cleanBase + "." + extToUse);
      }

      if (!detectedExt.isEmpty()
          && (job.mimeType == null
              || job.mimeType.isEmpty()
              || "application/octet-stream".equalsIgnoreCase(job.mimeType)
              || "binary/octet-stream".equalsIgnoreCase(job.mimeType))) {
        String mappedMime =
            "apk".equals(detectedExt)
                ? "application/vnd.android.package-archive"
                : MimeTypeMap.getSingleton().getMimeTypeFromExtension(detectedExt);
        if (mappedMime != null && !mappedMime.isEmpty()) {
          job.mimeType = mappedMime;
        }
      }

      if (finalName != null
          && !finalName.isEmpty()
          && !finalName.equals(job.fileName)) {
        File dir = job.targetFile.getParentFile();
        if (dir != null) {
          File oldPart = job.partFile;
          File nextTarget = uniqueTargetFile(dir, finalName);
          File nextPart = new File(dir, nextTarget.getName() + ".part");
          if (oldPart != null && oldPart.exists() && !oldPart.equals(nextPart)) {
            //noinspection ResultOfMethodCallIgnored
            oldPart.renameTo(nextPart);
          }
          job.targetFile = nextTarget;
          job.partFile = nextPart;
          job.fileName = nextTarget.getName();
        }
      }
    } catch (Throwable ignored) {
    }
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
    String candidateName = (fileName != null) ? fileName.trim() : "";
    String resolvedName =
        (!candidateName.isEmpty() && !candidateName.toLowerCase(Locale.US).endsWith(".bin"))
            ? sanitizeDownloadFileName(candidateName)
            : resolveSmartFileName(cleanUrl, null, mimeType);
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
    String safeName =
        (fileName != null && !fileName.isEmpty())
            ? fileName
            : resolveSmartFileName(url, null, mimeType);
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
        job.resolvedUrl = currentUrl;
        continue;
      }
      job.resolvedUrl = currentUrl;
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
      String serverDisp = conn.getHeaderField("Content-Disposition");
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

      byte[] buf = new byte[32 * 1024];
      int firstRead = -1;
      if (!append) {
        firstRead = in.read(buf);
        refineDownloadJobTarget(
            job, serverDisp, job.mimeType, firstRead > 0 ? buf : null, Math.max(0, firstRead));
      }

      out = new FileOutputStream(job.partFile, append);
      long lastTickTime = SystemClock.elapsedRealtime();
      long lastTickBytes = job.bytesDownloaded.get();
      long lastNotifTime = 0L;

      if (firstRead > 0 && !job.cancelRequested && !job.pauseRequested) {
        out.write(buf, 0, firstRead);
        job.bytesDownloaded.addAndGet(firstRead);
        postDownloadNotification(job);
        lastNotifTime = SystemClock.elapsedRealtime();
      }

      int n;
      while (!job.cancelRequested && !job.pauseRequested && (n = in.read(buf)) != -1) {
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
      if ("apk".equals(ext)) {
        return "application/vnd.android.package-archive";
      }
      if ("mkv".equals(ext)) {
        return "video/x-matroska";
      }
      if ("7z".equals(ext)) {
        return "application/x-7z-compressed";
      }
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

  private static String normalizeHost(String raw) {
    if (raw == null || raw.isEmpty()) {
      return "";
    }
    String lower = raw.toLowerCase(Locale.US).trim();
    if (lower.startsWith("www.")) {
      lower = lower.substring(4);
    }
    int colon = lower.indexOf(':');
    if (colon > 0) {
      lower = lower.substring(0, colon);
    }
    return lower;
  }
}
