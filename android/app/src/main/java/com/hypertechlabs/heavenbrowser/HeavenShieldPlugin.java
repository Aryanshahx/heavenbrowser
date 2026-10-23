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
import android.net.http.SslError;
import android.os.Build;
import android.os.CancellationSignal;
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
import android.webkit.JavascriptInterface;
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
  private static final String NOTIF_CHANNEL_ALERTS = "heaven_alerts_v13";
  private static final int VOICE_SEARCH_REQUEST_CODE = 49021;
  private static final int NOTIF_PERM_REQUEST_CODE = 49022;
  private static final int FOLDER_PICKER_REQUEST_CODE = 49025;
  private static final int EXT_FILE_PICKER_REQUEST_CODE = 49026;
  private static final int SITE_HARDWARE_PERM_REQUEST_CODE = 49027;
  private static final int LEGACY_CREDENTIAL_REQUEST_CODE = 49028;

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

  private static final String CHROME_WEB_STORE_DESKTOP_SCRIPT =
      "(function(){"
          + "try{"
          + "var dUa='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';"
          + "Object.defineProperty(navigator,'userAgent',{get:()=>dUa,configurable:true});"
          + "Object.defineProperty(navigator,'appVersion',{get:()=>dUa.slice(8),configurable:true});"
          + "Object.defineProperty(navigator,'platform',{get:()=>'Win32',configurable:true});"
          + "Object.defineProperty(navigator,'vendor',{get:()=>'Google Inc.',configurable:true});"
          + "Object.defineProperty(navigator,'maxTouchPoints',{get:()=>0,configurable:true});"
          + "Object.defineProperty(navigator,'userAgentData',{get:()=>({"
          + "brands:[{brand:'Chromium',version:'134'},{brand:'Google Chrome',version:'134'},{brand:'Not:A-Brand',version:'24'}],"
          + "mobile:false,platform:'Windows',"
          + "getHighEntropyValues:function(){return Promise.resolve({architecture:'x86',bitness:'64',mobile:false,model:'',platform:'Windows',platformVersion:'15.0.0',uaFullVersion:'134.0.6998.89'});}"
          + "}),configurable:true});"
          + "var m=document.querySelector('meta[name=\"viewport\"]');"
          + "if(!m&&document.head){m=document.createElement('meta');m.name='viewport';document.head.appendChild(m);}"
          + "if(m){m.setAttribute('content','width=1160, initial-scale=0.36, minimum-scale=0.2, maximum-scale=4.0, user-scalable=yes');}"
          + "function cleanStoreUi(){"
          + "  var nodes=document.querySelectorAll('div, section, aside, p, span');"
          + "  for(var i=0;i<nodes.length;i++){"
          + "    var el=nodes[i];"
          + "    if(el.children&&el.children.length>4)continue;"
          + "    var t=(el.textContent||'').trim();"
          + "    if(t.indexOf('only available on desktop')!==-1||t.indexOf('open this page on your desktop browser')!==-1){"
          + "      var box=el.closest('[role=\"alert\"], [role=\"banner\"], aside')||el;"
          + "      box.style.setProperty('display','none','important');"
          + "    }"
          + "  }"
          + "  var btns=document.querySelectorAll('button');"
          + "  for(var b=0;b<btns.length;b++){"
          + "    var btn=btns[b];"
          + "    var bt=(btn.textContent||'').trim();"
          + "    if((bt==='Add to Chrome'||bt==='Install')&&!btn.__heavenHooked){"
          + "      btn.__heavenHooked=true;"
          + "      btn.removeAttribute('disabled');"
          + "      btn.setAttribute('aria-disabled','false');"
          + "      btn.addEventListener('click',function(ev){"
          + "        ev.preventDefault();ev.stopPropagation();"
          + "        var mId=(location.href||'').match(/([a-p]{32})/);"
          + "        if(mId){"
          + "          this.textContent='Installing in Heaven...';"
          + "          if(window.HeavenExtNative&&window.HeavenExtNative.installWebStore){"
          + "            window.HeavenExtNative.installWebStore(location.href);"
          + "          }else if(window.HeavenChromeExtChannel){"
          + "            window.HeavenChromeExtChannel.postMessage(JSON.stringify({extId:mId[1],op:'install_cws',data:{url:location.href}}));"
          + "          }"
          + "        }"
          + "      },true);"
          + "    }"
          + "  }"
          + "}"
          + "cleanStoreUi();"
          + "if(!window.__heavenCwsObs&&document.documentElement){"
          + "  window.__heavenCwsObs=new MutationObserver(cleanStoreUi);"
          + "  window.__heavenCwsObs.observe(document.documentElement,{childList:true,subtree:true});"
          + "}"
          + "}catch(_){}"
          + "})();";

  private static final String EARLY_YOUTUBE_AND_REDIRECT_GUARD_SCRIPT =
      "(function(){"
          + "try{"
          + "if(window.__heavenShieldDocStartV12)return;"
          + "window.__heavenShieldDocStartV12=true;"
          + "function notify(tag){try{if(window.HeavenShieldChannel&&window.HeavenShieldChannel.postMessage)window.HeavenShieldChannel.postMessage(tag);}catch(e){}}"
          + "var trustedList=window.__heavenTrustedHosts||[];"
          + "var hn=(location.hostname||'').toLowerCase().replace(/^www\\./,'');"
          + "if(hn==='chrome-ext.heaven.local'||location.protocol==='chrome-extension:')return;"
          + "for(var ti=0;ti<trustedList.length;ti++){"
          + "  var th=trustedList[ti];"
          + "  if(th&&(hn===th||hn.slice(-(th.length+1))==='.'+th))return;"
          + "}"
          + "var deadWin=new Proxy({closed:false,close:function(){},focus:function(){},blur:function(){},postMessage:function(){},location:{href:'about:blank'}},{get:function(t,p){return p in t?t[p]:function(){};},set:function(){return true;}});"
          + "try{Object.defineProperty(window,'open',{configurable:true,writable:false,value:function(){notify('popup-blocked');return deadWin;}});}catch(e){window.open=function(){notify('popup-blocked');return deadWin;};}"
          + "var origClick=HTMLAnchorElement.prototype.click;"
          + "HTMLAnchorElement.prototype.click=function(){"
          + "  try{"
          + "    var href=this.href||'';"
          + "    if(!this.isConnected||(this.offsetWidth===0&&this.offsetHeight===0)){"
          + "      if(href&&href.indexOf(location.hostname)===-1){notify('redirect-blocked');return;}"
          + "    }"
          + "  }catch(e){}"
          + "  return origClick.apply(this,arguments);"
          + "};"
          + "document.addEventListener('pointerdown',function(ev){"
          + "  try{"
          + "    var a=ev.target&&ev.target.closest?ev.target.closest('a[href]'):null;"
          + "    if(!a)return;"
          + "    var r=a.getBoundingClientRect();"
          + "    var cs=window.getComputedStyle(a);"
          + "    var op=parseFloat(cs.opacity||'1');"
          + "    var fullOverlay=(cs.position==='fixed'||cs.position==='absolute')&&r.width>window.innerWidth*0.65&&r.height>window.innerHeight*0.45&&!(a.textContent||'').trim();"
          + "    if(fullOverlay||op<0.12||r.width<10||r.height<10){"
          + "      a.style.setProperty('pointer-events','none','important');"
          + "      a.removeAttribute('href');"
          + "      notify('overlay-ad');"
          + "      return;"
          + "    }"
          + "    var u=new URL(a.href,location.href);"
          + "    if((u.protocol==='http:'||u.protocol==='https:')&&u.hostname&&u.hostname!==location.hostname){"
          + "      notify('ALLOW_NAV:'+u.hostname.toLowerCase());"
          + "    }"
          + "  }catch(e){}"
          + "},true);"
          + "var isYt=hn==='youtube.com'||hn.slice(-12)==='.youtube.com'||hn==='youtube-nocookie.com'||hn.slice(-21)==='.youtube-nocookie.com';"
          + "if(isYt){"
          + "  var AD_FEED_KEYS=['adSlotRenderer','promotedSparklesWebRenderer','promotedSparklesTextSearchRenderer','promotedVideoRenderer','compactPromotedVideoRenderer','inFeedAdLayoutRenderer','statementBannerRenderer','mastheadAdRenderer','brandInteractionRenderer','searchPyvRenderer'];"
          + "  function hasFeedAd(item){"
          + "    if(!item||typeof item!=='object')return false;"
          + "    for(var k=0;k<AD_FEED_KEYS.length;k++){if(AD_FEED_KEYS[k] in item)return true;}"
          + "    if(item.richItemRenderer&&item.richItemRenderer.content){"
          + "      var c=item.richItemRenderer.content;"
          + "      for(var m=0;m<AD_FEED_KEYS.length;m++){if(AD_FEED_KEYS[m] in c)return true;}"
          + "    }"
          + "    return false;"
          + "  }"
          + "  function pruneYtAds(obj,depth){"
          + "    if(!obj||typeof obj!=='object'||depth>9)return obj;"
          + "    try{"
          + "      if(Array.isArray(obj)){"
          + "        for(var i=obj.length-1;i>=0;i--){"
          + "          if(hasFeedAd(obj[i])){obj.splice(i,1);}"
          + "          else if(obj[i]&&typeof obj[i]==='object'){pruneYtAds(obj[i],depth+1);}"
          + "        }"
          + "        return obj;"
          + "      }"
          + "      if('adPlacements' in obj)delete obj.adPlacements;"
          + "      if('playerAds' in obj)delete obj.playerAds;"
          + "      if('adSlots' in obj)delete obj.adSlots;"
          + "      if('adBreakHeartbeatParams' in obj)delete obj.adBreakHeartbeatParams;"
          + "      if('enforcementMessageViewModel' in obj)delete obj.enforcementMessageViewModel;"
          + "      if(obj.auxiliaryUi&&obj.auxiliaryUi.messageRenderers&&obj.auxiliaryUi.messageRenderers.bkaEnforcementMessageViewModel){"
          + "        delete obj.auxiliaryUi.messageRenderers.bkaEnforcementMessageViewModel;"
          + "      }"
          + "      var subKeys=['playerResponse','response','contents','items','results','twoColumnBrowseResultsRenderer','twoColumnSearchResultsRenderer','twoColumnWatchNextResults','singleColumnBrowseResultsRenderer','singleColumnSearchResultsRenderer','singleColumnWatchNextResults','sectionListRenderer','itemSectionRenderer','richGridRenderer','tabs','tabRenderer','content','onResponseReceivedEndpoints','onResponseReceivedActions','appendContinuationItemsAction','continuationItems','entries'];"
          + "      for(var s=0;s<subKeys.length;s++){"
          + "        var sk=subKeys[s];"
          + "        if(obj[sk]&&typeof obj[sk]==='object'){pruneYtAds(obj[sk],depth+1);}"
          + "      }"
          + "    }catch(e){}"
          + "    return obj;"
          + "  }"
          + "  function shouldPruneText(t){"
          + "    return t&&(t.indexOf('\"adPlacements\"')!==-1||t.indexOf('\"playerAds\"')!==-1||t.indexOf('\"adSlots\"')!==-1||t.indexOf('\"adSlotRenderer\"')!==-1||t.indexOf('\"promotedSparkles')!==-1||t.indexOf('\"promotedVideoRenderer\"')!==-1||t.indexOf('EnforcementMessageViewModel')!==-1);"
          + "  }"
          + "  var ytInitPlayer=window.ytInitialPlayerResponse?pruneYtAds(window.ytInitialPlayerResponse,0):undefined;"
          + "  try{"
          + "    Object.defineProperty(window,'ytInitialPlayerResponse',{configurable:true,get:function(){return ytInitPlayer;},set:function(v){ytInitPlayer=pruneYtAds(v,0);}});"
          + "  }catch(e){}"
          + "  var ytInitData=window.ytInitialData?pruneYtAds(window.ytInitialData,0):undefined;"
          + "  try{"
          + "    Object.defineProperty(window,'ytInitialData',{configurable:true,get:function(){return ytInitData;},set:function(v){ytInitData=pruneYtAds(v,0);}});"
          + "  }catch(e){}"
          + "  var origParse=JSON.parse;"
          + "  JSON.parse=function(text,reviver){"
          + "    var parsed=origParse.apply(this,arguments);"
          + "    if(parsed&&typeof parsed==='object'&&typeof text==='string'&&shouldPruneText(text)){"
          + "      return pruneYtAds(parsed,0);"
          + "    }"
          + "    return parsed;"
          + "  };"
          + "  if(window.fetch){"
          + "    var origFetch=window.fetch;"
          + "    window.fetch=function(input,init){"
          + "      var reqUrl='';"
          + "      try{reqUrl=typeof input==='string'?input:(input&&input.url?input.url:'');}catch(e){}"
          + "      if(reqUrl.indexOf('/pagead/')!==-1||reqUrl.indexOf('/api/stats/ads')!==-1||reqUrl.indexOf('/ptracking')!==-1||reqUrl.indexOf('doubleclick.net')!==-1||reqUrl.indexOf('googlesyndication.com')!==-1){"
          + "        notify('youtube-ad');"
          + "        return Promise.resolve(new Response('',{status:204}));"
          + "      }"
          + "      var isYtApi=reqUrl.indexOf('/youtubei/v1/player')!==-1||reqUrl.indexOf('/youtubei/v1/next')!==-1||reqUrl.indexOf('/youtubei/v1/browse')!==-1||reqUrl.indexOf('/youtubei/v1/search')!==-1||reqUrl.indexOf('/youtubei/v1/reel/')!==-1;"
          + "      if(!isYtApi){return origFetch.apply(this,arguments);}"
          + "      return origFetch.apply(this,arguments).then(function(resp){"
          + "        if(!resp||!resp.ok)return resp;"
          + "        return resp.clone().text().then(function(rawTxt){"
          + "          if(!shouldPruneText(rawTxt))return resp;"
          + "          try{"
          + "            var data=origParse(rawTxt);"
          + "            pruneYtAds(data,0);"
          + "            notify('youtube-ad');"
          + "            return new Response(JSON.stringify(data),{status:resp.status,statusText:resp.statusText,headers:resp.headers});"
          + "          }catch(e){return resp;}"
          + "        }).catch(function(){return resp;});"
          + "      });"
          + "    };"
          + "  }"
          + "  var origXhrOpen=XMLHttpRequest.prototype.open;"
          + "  var origXhrSend=XMLHttpRequest.prototype.send;"
          + "  XMLHttpRequest.prototype.open=function(method,url){"
          + "    this.__hbUrl=typeof url==='string'?url:String(url||'');"
          + "    return origXhrOpen.apply(this,arguments);"
          + "  };"
          + "  XMLHttpRequest.prototype.send=function(){"
          + "    var u=this.__hbUrl||'';"
          + "    if(u.indexOf('/pagead/')!==-1||u.indexOf('/api/stats/ads')!==-1||u.indexOf('doubleclick.net')!==-1){"
          + "      notify('youtube-ad');"
          + "      return;"
          + "    }"
          + "    if(u.indexOf('/youtubei/v1/')!==-1){"
          + "      var xhr=this;"
          + "      xhr.addEventListener('readystatechange',function(){"
          + "        if(xhr.readyState===4&&(xhr.responseType===''||xhr.responseType==='text')){"
          + "          try{"
          + "            var rt=xhr.responseText;"
          + "            if(shouldPruneText(rt)){"
          + "              var cleaned=JSON.stringify(pruneYtAds(origParse(rt),0));"
          + "              Object.defineProperty(xhr,'responseText',{configurable:true,get:function(){return cleaned;}});"
          + "              Object.defineProperty(xhr,'response',{configurable:true,get:function(){return cleaned;}});"
          + "              notify('youtube-ad');"
          + "            }"
          + "          }catch(e){}"
          + "        }"
          + "      });"
          + "    }"
          + "    return origXhrSend.apply(this,arguments);"
          + "  };"
          + "  function injectYtStyle(){"
          + "    if(document.getElementById('heaven-yt-docstart-css'))return;"
          + "    var root=document.head||document.documentElement;"
          + "    if(!root)return;"
          + "    var st=document.createElement('style');"
          + "    st.id='heaven-yt-docstart-css';"
          + "    st.textContent='#masthead-ad,ytd-ad-slot-renderer,ytd-promoted-sparkles-web-renderer,ytd-promoted-sparkles-text-search-renderer,ytd-promoted-video-renderer,ytd-compact-promoted-video-renderer,ytd-in-feed-ad-layout-renderer,ytd-banner-promo-renderer,ytd-statement-banner-renderer,ytd-engagement-panel-section-list-renderer[target-id=\"engagement-panel-ads\"],ytm-ad-slot-renderer,ytm-promoted-sparkles-web-renderer,ytm-promoted-sparkles-text-search-renderer,ytm-promoted-video-renderer,ytm-companion-ad-renderer,ytm-companion-slot,ytm-statement-banner-renderer,ytm-in-feed-ad-layout-renderer,ad-slot-renderer,.ytp-ad-overlay-container,.ytp-ad-message-container,.ytp-ad-image-overlay,.ytp-ad-player-overlay-layout,.ytp-featured-product,ytd-enforcement-message-view-model,ytm-enforcement-message-view-model{display:none!important;height:0!important;max-height:0!important;visibility:hidden!important;pointer-events:none!important;}';"
          + "    root.appendChild(st);"
          + "  }"
          + "  injectYtStyle();"
          + "  setInterval(function(){"
          + "    try{"
          + "      injectYtStyle();"
          + "      var mp=document.getElementById('movie_player');"
          + "      var adPlayer=document.querySelector('.html5-video-player.ad-showing, .html5-video-player.ad-interrupting, #movie_player.ad-showing');"
          + "      var skip=document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-slot button, .ytp-ad-overlay-close-button, .videoAdUiSkipButton');"
          + "      if(skip){skip.click();}"
          + "      if(adPlayer){"
          + "        if(mp&&typeof mp.skipAd==='function'){try{mp.skipAd();}catch(e){}}"
          + "        var vid=adPlayer.querySelector('video');"
          + "        if(vid){"
          + "          if(!vid.muted){vid.muted=true;vid.__hbMutedAd=true;}"
          + "          vid.playbackRate=16;"
          + "          if(isFinite(vid.duration)&&vid.duration>0.15&&(vid.duration-vid.currentTime)>0.15){"
          + "            vid.currentTime=vid.duration;"
          + "            notify('youtube-ad');"
          + "          }"
          + "        }"
          + "      }else{"
          + "        var normalVid=document.querySelector('video');"
          + "        if(normalVid&&normalVid.__hbMutedAd){normalVid.muted=false;normalVid.__hbMutedAd=false;if(normalVid.playbackRate===16)normalVid.playbackRate=1;}"
          + "      }"
          + "      var dialog=document.querySelector('tp-yt-paper-dialog:has(ytd-enforcement-message-view-model)');"
          + "      if(dialog){dialog.remove();var v=document.querySelector('video');if(v&&v.paused)v.play();}"
          + "    }catch(e){}"
          + "  },200);"
          + "}"
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
          + "if(window.__heavenMediaHookV14)return;"
          + "window.__heavenMediaHookV14=true;"
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
          + "    Object.defineProperty(Document.prototype,'hidden',{configurable:true,get:function(){return false;}});"
          + "    Object.defineProperty(Document.prototype,'webkitHidden',{configurable:true,get:function(){return false;}});"
          + "    Object.defineProperty(Document.prototype,'visibilityState',{configurable:true,get:function(){return 'visible';}});"
          + "    Object.defineProperty(Document.prototype,'webkitVisibilityState',{configurable:true,get:function(){return 'visible';}});"
          + "    Object.defineProperty(document,'hidden',{configurable:true,get:function(){return false;}});"
          + "    Object.defineProperty(document,'visibilityState',{configurable:true,get:function(){return 'visible';}});"
          + "    var blockVis=function(ev){if(ev){ev.stopImmediatePropagation();ev.stopPropagation();}};"
          + "    window.addEventListener('visibilitychange',blockVis,true);"
          + "    window.addEventListener('webkitvisibilitychange',blockVis,true);"
          + "    document.addEventListener('visibilitychange',blockVis,true);"
          + "    document.addEventListener('webkitvisibilitychange',blockVis,true);"
          + "    document.addEventListener('freeze',blockVis,true);"
          + "    window.addEventListener('pagehide',blockVis,true);"
          + "    var origDocAdd=Document.prototype.addEventListener;"
          + "    Document.prototype.addEventListener=function(type,fn,opts){"
          + "      if(type==='visibilitychange'||type==='webkitvisibilitychange'||type==='freeze')return;"
          + "      return origDocAdd.apply(this,arguments);"
          + "    };"
          + "    var origWinAdd=Window.prototype.addEventListener;"
          + "    Window.prototype.addEventListener=function(type,fn,opts){"
          + "      if(type==='visibilitychange'||type==='webkitvisibilitychange'||type==='freeze')return;"
          + "      return origWinAdd.apply(this,arguments);"
          + "    };"
          + "    var origPause=HTMLMediaElement.prototype.pause;"
          + "    HTMLMediaElement.prototype.pause=function(){"
          + "      if(window.__hbInBg&&this.__hbShouldPlayInBg&&!window.__hbMediaCmdPause&&!this.ended){"
          + "        return;"
          + "      }"
          + "      return origPause.apply(this,arguments);"
          + "    };"
          + "    setInterval(function(){try{window._lact=Date.now();}catch(e){}},5000);"
          + "  }catch(e){}"
          + "}"
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
          + "var lastScTop=0;var lastScTarget=null;"
          + "window.addEventListener('scroll',function(ev){"
          + "  try{"
          + "    if(!window.HeavenMediaBridge||!window.HeavenMediaBridge.onScroll)return;"
          + "    var tgt=ev&&ev.target;"
          + "    var st=0;"
          + "    if(!tgt||tgt===document||tgt===document.documentElement||tgt===document.body){"
          + "      st=window.pageYOffset||document.documentElement.scrollTop||0;"
          + "      tgt=document;"
          + "    }else if(typeof tgt.scrollTop==='number'&&tgt.scrollHeight>tgt.clientHeight+80){"
          + "      st=tgt.scrollTop;"
          + "    }else{return;}"
          + "    if(lastScTarget!==tgt){lastScTarget=tgt;lastScTop=st;return;}"
          + "    var dy=st-lastScTop;"
          + "    if(Math.abs(dy)<14&&st>12)return;"
          + "    lastScTop=st;"
          + "    window.HeavenMediaBridge.onScroll(Math.round(st),Math.round(dy));"
          + "  }catch(e){}"
          + "},{passive:true,capture:true});"
          + "}catch(_){}"
          + "})();";

  private static final String ULTRA_DATA_SAVER_STYLE_SCRIPT =
      "(function(){"
          + "try{"
          + "var st=document.getElementById('heaven-ultra-datasaver-css');"
          + "if(window.__heavenUltraDataSaver){"
          + "  if(!st){st=document.createElement('style');st.id='heaven-ultra-datasaver-css';"
          + "  st.textContent='img,picture,video,canvas,svg[width][height]:not([width=\"16\"]):not([width=\"20\"]):not([width=\"24\"]),iframe[src*=\"ads\"],iframe[src*=\"youtube\"]{display:none!important;max-height:0!important;} *{background-image:none!important;animation:none!important;transition:none!important;}';"
          + "  (document.head||document.documentElement).appendChild(st);}"
          + "}else if(st){st.remove();}"
          + "}catch(e){}"
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
  private MethodChannel.Result pendingExtFileResult;
  private MethodChannel.Result pendingNotifPermResult;
  private MethodChannel.Result pendingSiteHardwarePermResult;
  private MethodChannel.Result pendingBiometricResult;
  private HeavenVpnManager vpnManager;
  private HeavenChromeExtManager chromeExtManager;
  private volatile long activeFocusedWebViewId = -1L;
  private volatile String activePopupTabUrl = "https://www.google.com";
  private volatile String activePopupTabTitle = "Google";

  private final ExecutorService downloadPool = Executors.newCachedThreadPool();
  private final Map<Long, DownloadJob> downloadJobs = new ConcurrentHashMap<>();
  private final AtomicLong idGenerator = new AtomicLong(System.currentTimeMillis());
  private BroadcastReceiver controlReceiver;
  private BroadcastReceiver mediaCmdReceiver;
  private boolean notifChannelsReady = false;
  private volatile String customDownloadPath = "";
  private volatile boolean downloadNotificationsEnabled = true;

  private volatile boolean shieldEnabled = true;
  private volatile boolean desktopMode = false;
  private volatile boolean ultraDataSaverMode = false;
  private volatile boolean backgroundMediaEnabled = true;
  private volatile boolean antiRedirectEnabled = true;
  private volatile boolean webNotificationsEnabled = false;
  private volatile boolean backgroundPlayNotifEnabled = true;

  private volatile boolean appInBackground = false;
  private volatile boolean userPausedFromNotification = false;
  private volatile boolean activeAudioOrVideoPlaying = false;
  private volatile long activeMediaWebViewId = -1L;
  private volatile String activeMediaTitle = "Heaven";
  private volatile String activeMediaHost = "Heaven";
  private final Map<Long, Boolean> lastNavBarVisibleByWv = new ConcurrentHashMap<>();
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
  private volatile Set<String> blockedDomains = Collections.emptySet();
  private volatile Set<String> trustedHosts = Collections.emptySet();
  private volatile String cosmeticScript = "";
  private final Map<Long, String> currentPageHosts = new ConcurrentHashMap<>();
  private final Map<String, Long> approvedExternalNavUntilMs = new ConcurrentHashMap<>();
  private final Map<Long, Long> userInitiatedNavUntilMs = new ConcurrentHashMap<>();
  private final Map<Long, Boolean> lastDesktopApplied = new ConcurrentHashMap<>();
  private final Map<Long, ScriptHandler> docStartHandlers = new ConcurrentHashMap<>();
  private boolean serviceWorkerHooked = false;

  private static final Set<String> BUILTIN_CRITICAL_AD_ROOTS;

  static {
    Set<String> s = new HashSet<>(32);
    String[] critical = {
      "doubleclick.net",
      "googlesyndication.com",
      "googleadservices.com",
      "adservice.google.com",
      "ads.youtube.com",
      "2mdn.net",
      "imasdk.googleapis.com",
      "fundingchoicesmessages.google.com",
      "exoclick.com",
      "exosrv.com",
      "realsrv.com",
      "adsterra.com",
      "propellerads.com",
      "popads.net",
      "popcash.net",
      "juicyads.com",
      "trafficjunky.net",
      "tsyndicate.com",
      "clickadu.com",
      "hilltopads.net",
      "monetag.com",
      "onclkds.com",
      "highperformanceformat.com",
      "profitablecpmrate.com"
    };
    Collections.addAll(s, critical);
    BUILTIN_CRITICAL_AD_ROOTS = Collections.unmodifiableSet(s);
  }

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
    this.chromeExtManager = new HeavenChromeExtManager(appCtx);
    this.chromeExtManager.setOnExtensionsChangedListener(this::refreshAllDocumentStartHandlers);
    this.chromeExtManager.setActiveTabBridge(
        new HeavenChromeExtManager.ActiveTabExtensionBridge() {
          @Override
          public void evalInActiveTab(final String jsCode) {
            mainHandler.post(
                () -> {
                  if (pluginBinding == null || activeFocusedWebViewId < 0) {
                    return;
                  }
                  WebView wv =
                      WebViewFlutterAndroidExternalApi.getWebView(
                          pluginBinding, activeFocusedWebViewId);
                  if (wv != null && jsCode != null && !jsCode.isEmpty()) {
                    wv.evaluateJavascript(jsCode, null);
                  }
                });
          }

          @Override
          public void evalInAllWebViews(final String jsCode) {
            mainHandler.post(
                () -> {
                  if (pluginBinding == null || jsCode == null || jsCode.isEmpty()) {
                    return;
                  }
                  for (Long id : new ArrayList<>(docStartHandlers.keySet())) {
                    if (id == null) continue;
                    try {
                      WebView wv = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, id);
                      if (wv != null) {
                        wv.evaluateJavascript(jsCode, null);
                      }
                    } catch (Throwable ignored) {
                    }
                  }
                });
          }

          @Override
          public void evalInWebView(final long webViewId, final String jsCode) {
            mainHandler.post(
                () -> {
                  if (pluginBinding == null || webViewId < 0 || jsCode == null || jsCode.isEmpty()) {
                    return;
                  }
                  try {
                    WebView wv =
                        WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, webViewId);
                    if (wv != null) {
                      wv.evaluateJavascript(jsCode, null);
                    }
                  } catch (Throwable ignored) {
                  }
                });
          }

          @Override
          public void openNewTab(final String url) {
            mainHandler.post(
                () -> {
                  MethodChannel ch = channel;
                  if (ch != null && url != null && !url.isEmpty()) {
                    ch.invokeMethod("onExtensionOpenNewTab", Collections.singletonMap("url", url));
                  }
                });
          }

          @Override
          public void navigateTargetTab(final String url) {
            mainHandler.post(
                () -> {
                  if (url == null || url.isEmpty()) return;
                  if (pluginBinding != null && activeFocusedWebViewId >= 0) {
                    WebView wv =
                        WebViewFlutterAndroidExternalApi.getWebView(
                            pluginBinding, activeFocusedWebViewId);
                    if (wv != null) {
                      wv.loadUrl(url);
                      return;
                    }
                  }
                  MethodChannel ch = channel;
                  if (ch != null) {
                    ch.invokeMethod("onExtensionOpenNewTab", Collections.singletonMap("url", url));
                  }
                });
          }

          @Override
          public void onWebStoreInstalledFromPage(final Map<String, Object> res) {
            mainHandler.post(
                () -> {
                  String doneJs =
                      "(function(){var bs=document.querySelectorAll('button');for(var i=0;i<bs.length;i++){if(bs[i].textContent&&bs[i].textContent.indexOf('Installing in Heaven')!==-1){bs[i].textContent='Added to Heaven';}}})();";
                  for (Long id : new ArrayList<>(docStartHandlers.keySet())) {
                    if (id == null || pluginBinding == null) continue;
                    WebView wv = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, id);
                    if (wv != null) wv.evaluateJavascript(doneJs, null);
                  }
                  MethodChannel ch = channel;
                  if (ch != null && res != null) {
                    ch.invokeMethod("onWebStoreExtensionInstalled", res);
                  }
                });
          }

          @Override
          public String getActiveTabUrl() {
            return activePopupTabUrl;
          }

          @Override
          public String getActiveTabTitle() {
            return activePopupTabTitle;
          }
        });
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    setupServiceWorkerShield();
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
    if (this.chromeExtManager != null) {
      this.chromeExtManager.shutdown();
      this.chromeExtManager = null;
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
    if (requestCode == EXT_FILE_PICKER_REQUEST_CODE) {
      MethodChannel.Result extCb = this.pendingExtFileResult;
      this.pendingExtFileResult = null;
      if (extCb == null) {
        return true;
      }
      if (resultCode == Activity.RESULT_OK && data != null && data.getData() != null) {
        final Uri docUri = data.getData();
        final Context ctx = resolveContext();
        if (ctx != null && chromeExtManager != null) {
          downloadPool.execute(
              () -> {
                try (InputStream is = ctx.getContentResolver().openInputStream(docUri);
                    ByteArrayOutputStream bos = new ByteArrayOutputStream()) {
                  if (is == null) {
                    mainHandler.post(() -> extCb.success(null));
                    return;
                  }
                  byte[] buf = new byte[16384];
                  int n;
                  while ((n = is.read(buf)) > 0) {
                    bos.write(buf, 0, n);
                  }
                  String seg = docUri.getLastPathSegment();
                  chromeExtManager.installFromLocalBytes(
                      seg != null ? seg : "extension.crx", bos.toByteArray(), extCb);
                } catch (Throwable t) {
                  Map<String, Object> err = new HashMap<>();
                  err.put("ok", false);
                  err.put("error", "Could not read selected extension file");
                  mainHandler.post(() -> extCb.success(err));
                }
              });
          return true;
        }
      }
      extCb.success(null);
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
              if (request != null && chromeExtManager != null) {
                WebResourceResponse extRes =
                    chromeExtManager.interceptExtensionRequest(
                        request.getUrl(), activePopupTabUrl, activePopupTabTitle);
                if (extRes != null) {
                  return extRes;
                }
              }
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
          String normInit = initHost != null ? normalizeHost(initHost) : "";
          if (!HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(normInit)) {
            this.activeFocusedWebViewId = wvId;
          }
          if (!normInit.isEmpty()) {
            currentPageHosts.put(wvId, normInit);
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
        String pageHost = call.argument("pageHost");
        if (pageHost == null) {
          pageHost = call.argument("host");
        }
        if (wvIdObj instanceof Number) {
          long id = ((Number) wvIdObj).longValue();
          if (pageHost == null || pageHost.trim().isEmpty()) {
            currentPageHosts.remove(id);
          } else {
            String normHost = normalizeHost(pageHost);
            if (!HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(normHost)) {
              this.activeFocusedWebViewId = id;
            }
            currentPageHosts.put(id, normHost);
            userInitiatedNavUntilMs.put(id, System.currentTimeMillis() + 4500L);
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

      case "sendChromeExtensionRuntimeMessage":
        if (chromeExtManager != null) {
          String extId = call.argument("id");
          String msgJson = call.argument("messageJson");
          String senderUrl = call.argument("senderUrl");
          chromeExtManager.dispatchRuntimeMessageToBackground(
              extId != null ? extId : "", msgJson, senderUrl, result);
        } else {
          result.success("{}");
        }
        break;

      case "triggerChromeExtensionAction":
        if (chromeExtManager != null) {
          String extId = call.argument("id");
          String tabUrl = call.argument("url");
          String tabTitle = call.argument("title");
          chromeExtManager.dispatchExtensionActionClicked(
              extId != null ? extId : "",
              tabUrl != null ? tabUrl : activePopupTabUrl,
              tabTitle != null ? tabTitle : activePopupTabTitle);
          result.success(true);
        } else {
          result.success(false);
        }
        break;

      case "listChromeExtensions":
        if (chromeExtManager != null) {
          result.success(chromeExtManager.listInstalledExtensions());
        } else {
          result.success(Collections.emptyList());
        }
        break;

      case "installWebStoreExtension":
        if (chromeExtManager != null) {
          String urlOrId = call.argument("urlOrId");
          chromeExtManager.installFromWebStore(urlOrId != null ? urlOrId : "", result);
        } else {
          result.success(Collections.singletonMap("ok", false));
        }
        break;

      case "pickChromeExtensionFile":
        handlePickChromeExtensionFile(result);
        break;

      case "toggleChromeExtension":
        if (chromeExtManager != null) {
          String extId = call.argument("id");
          Boolean en = call.argument("enabled");
          result.success(
              chromeExtManager.setExtensionEnabled(
                  extId != null ? extId : "", en == null || en));
        } else {
          result.success(false);
        }
        break;

      case "uninstallChromeExtension":
        if (chromeExtManager != null) {
          String extId = call.argument("id");
          result.success(chromeExtManager.uninstallExtension(extId != null ? extId : ""));
        } else {
          result.success(false);
        }
        break;

      case "approveExternalNavigation":
        Object navWvObj = call.argument("webViewId");
        String navHost = call.argument("host");
        if (navWvObj instanceof Number && navHost != null && !navHost.isEmpty()) {
          long navWvId = ((Number) navWvObj).longValue();
          String key = navWvId + "|" + normalizeHost(navHost);
          approvedExternalNavUntilMs.put(key, System.currentTimeMillis() + 5000L);
          userInitiatedNavUntilMs.put(navWvId, System.currentTimeMillis() + 4500L);
        }
        result.success(true);
        break;

      case "prepareChromeWebStoreView":
        Object cwsWvObj = call.argument("webViewId");
        if (cwsWvObj instanceof Number && pluginBinding != null) {
          WebView cwsWv =
              WebViewFlutterAndroidExternalApi.getWebView(
                  pluginBinding, ((Number) cwsWvObj).longValue());
          if (cwsWv != null) {
            cwsWv.getSettings().setUserAgentString(DESKTOP_CHROME_WIN_UA);
            cwsWv.getSettings().setUseWideViewPort(true);
            cwsWv.getSettings().setLoadWithOverviewMode(true);
            result.success(true);
            return;
          }
        }
        result.success(false);
        break;

      case "getChromeExtensionScriptsForUrl":
        if (chromeExtManager != null) {
          String pageUrl = call.argument("url");
          String u = pageUrl != null ? pageUrl : "";
          downloadPool.execute(
              () -> {
                String bundle = chromeExtManager.buildContentScriptsBundleForUrl(u);
                mainHandler.post(() -> result.success(bundle));
              });
        } else {
          result.success("");
        }
        break;

      case "updateChromeExtensionStorage":
        if (chromeExtManager != null) {
          String extId = call.argument("id");
          String patchJson = call.argument("patchJson");
          chromeExtManager.updateExtensionStorage(extId, patchJson);
        }
        result.success(true);
        break;

      case "setPopupContextTab":
        String pUrl = call.argument("url");
        String pTitle = call.argument("title");
        Object pWvId = call.argument("webViewId");
        if (pWvId instanceof Number) {
          activeFocusedWebViewId = ((Number) pWvId).longValue();
        }
        if (pUrl != null && !pUrl.isEmpty()) {
          activePopupTabUrl = pUrl;
        }
        if (pTitle != null && !pTitle.isEmpty()) {
          activePopupTabTitle = pTitle;
        }
        result.success(true);
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
    Boolean ultraSaverArg = call.argument("ultraDataSaverMode");
    if (ultraSaverArg != null) {
      this.ultraDataSaverMode = ultraSaverArg;
      applyUltraDataSaverToAttachedWebViews(ultraSaverArg);
    }
    Boolean bgMediaArg = call.argument("backgroundMediaEnabled");
    if (bgMediaArg != null) {
      this.backgroundMediaEnabled = bgMediaArg;
      if (!bgMediaArg) {
        mainHandler.removeCallbacks(bgKeepAliveLoop);
        stopBackgroundMediaService();
      }
    }
    Boolean antiRedirectArg = call.argument("antiRedirectProtection");
    if (antiRedirectArg != null) {
      this.antiRedirectEnabled = antiRedirectArg;
    }
    Boolean webNotifArg = call.argument("webNotificationsEnabled");
    if (webNotifArg != null) {
      this.webNotificationsEnabled = webNotifArg;
    }
    Boolean bgPlayNotifArg = call.argument("backgroundPlayNotificationEnabled");
    if (bgPlayNotifArg != null) {
      this.backgroundPlayNotifEnabled = bgPlayNotifArg;
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
    refreshAllDocumentStartHandlers();
  }

  private void applyUltraDataSaverToAttachedWebViews(boolean enabled) {
    if (pluginBinding == null) {
      return;
    }
    for (Long id : new ArrayList<>(docStartHandlers.keySet())) {
      if (id == null) continue;
      try {
        WebView wv = WebViewFlutterAndroidExternalApi.getWebView(pluginBinding, id);
        if (wv != null) {
          wv.getSettings().setBlockNetworkImage(enabled);
          wv.evaluateJavascript(
              "window.__heavenUltraDataSaver=" + enabled + ";" + ULTRA_DATA_SAVER_STYLE_SCRIPT,
              null);
        }
      } catch (Throwable ignored) {
      }
    }
  }

  private String buildDocumentStartBundle() {
    String extDocStart =
        this.chromeExtManager != null ? this.chromeExtManager.getDocumentStartExtensionsJs() : "";
    String flagsJs =
        "window.__heavenBgMediaEnabled="
            + this.backgroundMediaEnabled
            + ";window.__heavenWebNotifsBlocked="
            + (!this.webNotificationsEnabled)
            + ";window.__heavenUltraDataSaver="
            + this.ultraDataSaverMode
            + ";window.__hbInBg="
            + this.appInBackground
            + ";";
    if (!this.shieldEnabled) {
      return "(function(){window.__heavenShieldDisabled=true;"
          + flagsJs
          + "})();"
          + BG_AUDIO_AND_SCROLL_SCRIPT
          + (this.ultraDataSaverMode ? ULTRA_DATA_SAVER_STYLE_SCRIPT : "")
          + extDocStart;
    }
    StringBuilder trustedJs = new StringBuilder(flagsJs).append("window.__heavenTrustedHosts=[");
    boolean first = true;
    for (String h : this.trustedHosts) {
      if (h == null || h.isEmpty()) continue;
      if (!first) trustedJs.append(',');
      first = false;
      trustedJs
          .append('\'')
          .append(h.replace("\\", "\\\\").replace("'", "\\'"))
          .append('\'');
    }
    trustedJs.append("];");
    String cos = this.cosmeticScript != null ? this.cosmeticScript : "";
    return trustedJs.toString()
        + BG_AUDIO_AND_SCROLL_SCRIPT
        + EARLY_YOUTUBE_AND_REDIRECT_GUARD_SCRIPT
        + (this.ultraDataSaverMode ? ULTRA_DATA_SAVER_STYLE_SCRIPT : "")
        + cos
        + extDocStart;
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
      settings.setJavaScriptCanOpenWindowsAutomatically(false);
      settings.setSupportMultipleWindows(true);
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
      } else {
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

  private final class WebViewMediaJsBridge {
    private final long webViewId;

    WebViewMediaJsBridge(long webViewId) {
      this.webViewId = webViewId;
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

    @JavascriptInterface
    public void onScroll(int scrollTop, int deltaY) {
      if (scrollTop <= 16 || deltaY <= -14) {
        emitNavBarVisibility(webViewId, true);
      } else if (deltaY >= 18 && scrollTop > 42) {
        emitNavBarVisibility(webViewId, false);
      }
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

      webView.getSettings().setMediaPlaybackRequiresUserGesture(false);
      webView.getSettings().setBlockNetworkImage(this.ultraDataSaverMode);
      try {
        webView.addJavascriptInterface(
            new WebViewMediaJsBridge(webViewId), "HeavenMediaBridge");
      } catch (Throwable ignored) {
      }
      if (this.chromeExtManager != null) {
        try {
          webView.addJavascriptInterface(
              this.chromeExtManager.createWebViewJsBridge(webViewId), "HeavenExtNative");
        } catch (Throwable ignored) {
        }
      }

      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        webView.setOnScrollChangeListener(
            (v, scrollX, scrollY, oldScrollX, oldScrollY) -> {
              int dy = scrollY - oldScrollY;
              if (scrollY <= 16 || dy <= -12) {
                emitNavBarVisibility(webViewId, true);
              } else if (dy >= 16 && scrollY > 42) {
                emitNavBarVisibility(webViewId, false);
              }
            });
      }

      applyDesktopSettingsToWebView(webView, webViewId, this.desktopMode, true);
      installOrRefreshDocumentStartShield(webView, webViewId);
      installPullToRefreshListener(webView, webViewId);
      installDownloadListener(webView, webViewId);

      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        WebViewClient existing = webView.getWebViewClient();
        if (!(existing instanceof ShieldWebViewClient)) {
          webView.setWebViewClient(new ShieldWebViewClient(webViewId, existing));
        }
        return true;
      }
    } catch (Throwable ignored) {
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

  private void handlePickChromeExtensionFile(MethodChannel.Result result) {
    if (this.activity == null) {
      result.success(null);
      return;
    }
    this.pendingExtFileResult = result;
    Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    intent.addCategory(Intent.CATEGORY_OPENABLE);
    intent.setType("*/*");
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    try {
      this.activity.startActivityForResult(intent, EXT_FILE_PICKER_REQUEST_CODE);
    } catch (ActivityNotFoundException e) {
      this.pendingExtFileResult = null;
      result.success(null);
    }
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

  private boolean shouldBlockInUltraDataSaver(
      String reqHost, String activePageHost, String lowerPath, WebResourceRequest request) {
    if (!this.ultraDataSaverMode || request.isForMainFrame()) {
      return false;
    }
    if (HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(reqHost)
        || "chromewebstore.google.com".equals(reqHost)) {
      return false;
    }
    String accept = "";
    Map<String, String> headers = request.getRequestHeaders();
    if (headers != null) {
      for (Map.Entry<String, String> e : headers.entrySet()) {
        if ("accept".equalsIgnoreCase(e.getKey()) && e.getValue() != null) {
          accept = e.getValue().toLowerCase(Locale.US);
          break;
        }
      }
    }
    if (lowerPath.endsWith(".jpg")
        || lowerPath.endsWith(".jpeg")
        || lowerPath.endsWith(".png")
        || lowerPath.endsWith(".webp")
        || lowerPath.endsWith(".gif")
        || lowerPath.endsWith(".avif")
        || lowerPath.endsWith(".woff2")
        || lowerPath.endsWith(".woff")
        || lowerPath.endsWith(".ttf")
        || accept.startsWith("image/")
        || accept.contains("font/")) {
      return true;
    }
    // Block heavy third-party scripts in Ultra Data Saver mode while keeping first-party HTML/JS
    if ((lowerPath.endsWith(".js") || accept.contains("javascript"))
        && activePageHost != null
        && !activePageHost.isEmpty()
        && !isSameRootDomain(reqHost, activePageHost)
        && !reqHost.endsWith("gstatic.com")) {
      return true;
    }
    return false;
  }

  private WebResourceResponse interceptIfAdOrTracker(long webViewId, WebResourceRequest request) {
    if (request == null) {
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
    String fullPath = url.getEncodedPath() != null ? url.getEncodedPath().toLowerCase(Locale.US) : "";
    String fullQuery = url.getEncodedQuery() != null ? url.getEncodedQuery().toLowerCase(Locale.US) : "";

    // 1. Ultra Data Saver (Text-Only Mode) network image/font/3P-script blocker
    if (shouldBlockInUltraDataSaver(host, activePageHost, fullPath, request)) {
      notifyBytesSavedOnMainThread(36800L);
      return buildEmptyResponseForPath(fullPath, request);
    }

    // 2. MV3 Chrome Extension declarativeNetRequest block rules
    if (chromeExtManager != null
        && !request.isForMainFrame()
        && chromeExtManager.shouldBlockByExtensionDnr(url, activePageHost)) {
      notifyBlockedOnMainThread(webViewId, host, 18400L);
      return buildEmptyResponseForPath(fullPath, request);
    }

    if (!shieldEnabled) {
      return null;
    }

    if (HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(host)
        || HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(activePageHost)) {
      return null;
    }
    if (activePageHost != null && isTrustedHost(activePageHost)) {
      return null;
    }
    if (request.isForMainFrame() && isTrustedHost(host)) {
      return null;
    }
    if (matchesBlockedDomain(host)
        || matchesAdPathSignature(host, fullPath, fullQuery, activePageHost)) {
      long estSaved = fullPath.contains("video") || fullPath.contains("vast") ? 48000L : 18400L;
      notifyBlockedOnMainThread(webViewId, host, estSaved);
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
    if (host == null || host.isEmpty()) {
      return false;
    }
    Set<String> snapshot = this.blockedDomains;
    if (snapshot.contains(host) || BUILTIN_CRITICAL_AD_ROOTS.contains(host)) {
      return true;
    }
    int dot = host.indexOf('.');
    while (dot != -1 && dot + 1 < host.length()) {
      String parent = host.substring(dot + 1);
      if (snapshot.contains(parent) || BUILTIN_CRITICAL_AD_ROOTS.contains(parent)) {
        return true;
      }
      dot = host.indexOf('.', dot + 1);
    }
    return false;
  }

  private boolean matchesAdPathSignature(
      String reqHost, String lowerPath, String lowerQuery, String pageHost) {
    // 1. First-party YouTube ad endpoints & ad telemetry (never block normal googlevideo streams!)
    if (reqHost.endsWith("youtube.com") || reqHost.endsWith("youtube-nocookie.com")) {
      if (lowerPath.contains("/pagead/")
          || lowerPath.contains("/api/stats/ads")
          || lowerPath.contains("/ptracking")
          || lowerPath.contains("/get_midroll_")
          || (lowerPath.contains("/api/stats/qoe") && lowerQuery.contains("adformat="))) {
        return true;
      }
    }
    if (reqHost.endsWith("googlevideo.com")
        && lowerPath.contains("/videoplayback")
        && (lowerQuery.contains("&oad=") || lowerQuery.startsWith("oad="))) {
      return true;
    }
    // 2. Google Search & Web AdSense / IMA paths
    if (lowerPath.contains("/pagead/")
        || lowerPath.contains("/ads/ga-audiences")
        || lowerPath.endsWith("/adsbygoogle.js")
        || lowerPath.endsWith("/gpt.js")) {
      return true;
    }
    boolean thirdParty =
        pageHost != null
            && !pageHost.isEmpty()
            && !isSameRootDomain(reqHost, pageHost);
    if (!thirdParty) {
      return false;
    }
    return lowerPath.contains("/adserver")
        || lowerPath.contains("/prebid")
        || lowerPath.contains("/popunder")
        || lowerPath.contains("/pop.js")
        || lowerPath.contains("/popads")
        || lowerPath.contains("/afu.php")
        || lowerPath.contains("/vast.xml")
        || lowerPath.endsWith("/analytics.js")
        || (lowerQuery.contains("zoneid=") && lowerQuery.contains("cb="));
  }

  private static boolean isChromeWebStoreUri(Uri u) {
    if (u == null) return false;
    String h = normalizeHost(u.getHost());
    String p = u.getEncodedPath() != null ? u.getEncodedPath().toLowerCase(Locale.US) : "";
    return "chromewebstore.google.com".equals(h)
        || ("chrome.google.com".equals(h) && p.startsWith("/webstore"));
  }

  private static String extractRegistrableRoot(String rawHost) {
    String h = normalizeHost(rawHost);
    if (h.isEmpty()) return "";
    String[] parts = h.split("\\.");
    if (parts.length <= 2) {
      return h;
    }
    String secondLast = parts[parts.length - 2];
    if (secondLast.length() <= 3
        && ("co".equals(secondLast)
            || "com".equals(secondLast)
            || "org".equals(secondLast)
            || "net".equals(secondLast)
            || "gov".equals(secondLast)
            || "ac".equals(secondLast))) {
      if (parts.length >= 3) {
        return parts[parts.length - 3]
            + "."
            + parts[parts.length - 2]
            + "."
            + parts[parts.length - 1];
      }
    }
    return parts[parts.length - 2] + "." + parts[parts.length - 1];
  }

  private static boolean isSameRootDomain(String hostA, String hostB) {
    if (hostA == null || hostB == null || hostA.isEmpty() || hostB.isEmpty()) {
      return false;
    }
    if (hostA.equals(hostB)) return true;
    String rA = extractRegistrableRoot(hostA);
    String rB = extractRegistrableRoot(hostB);
    return !rA.isEmpty() && rA.equals(rB);
  }

  private static boolean isSearchOrAuthPortal(String host) {
    if (host == null || host.isEmpty()) return false;
    return host.contains("google.")
        || host.endsWith("bing.com")
        || host.endsWith("duckduckgo.com")
        || host.endsWith("brave.com")
        || host.endsWith("yahoo.com")
        || host.endsWith("wikipedia.org")
        || host.endsWith("github.com")
        || host.endsWith("microsoftonline.com")
        || host.endsWith("live.com")
        || host.endsWith("apple.com")
        || host.equals(HeavenChromeExtManager.EXT_VIRTUAL_HOST);
  }

  private static boolean isSuspiciousRedirectTarget(Uri uri, String currentPageHost) {
    if (uri == null) return false;
    String destHost = normalizeHost(uri.getHost());
    String full = uri.toString().toLowerCase(Locale.US);
    if (full.contains("google_vignette")) {
      return true;
    }
    String[] trapRoots = {
      "1xbet", "betwinner", "mostbet", "melbet", "parimatch", "4rabet",
      "chaturbate.com", "stripchat.com", "livejasmin.com", "bongacams.com",
      "jerkmate.com", "cam4.com", "myfreecams.com", "realsrv.com",
      "exoclick.com", "tsyndicate.com", "adsterra", "propeller", "popads",
      "popcash", "hilltopads", "clickadu", "juicyads", "trafficjunky",
      "highperformanceformat.com", "profitablecpmrate.com", "effectivegatecpm.com",
      "onclkds.com", "onclickalgo.com", "dolohen.com", "monetag.com"
    };
    for (String trap : trapRoots) {
      if (destHost.contains(trap) && !isSameRootDomain(destHost, currentPageHost)) {
        return true;
      }
    }
    String q = uri.getEncodedQuery() != null ? uri.getEncodedQuery().toLowerCase(Locale.US) : "";
    return !isSameRootDomain(destHost, currentPageHost)
        && ((q.contains("zoneid=") && (q.contains("var=") || q.contains("ymid=")))
            || full.contains("/afu.php?")
            || full.contains("/popunder"));
  }

  private boolean isApprovedExternalNav(long webViewId, String destHost) {
    long now = System.currentTimeMillis();
    String exactKey = webViewId + "|" + destHost;
    Long exp = approvedExternalNavUntilMs.get(exactKey);
    if (exp != null && exp >= now) {
      return true;
    }
    String root = extractRegistrableRoot(destHost);
    for (Map.Entry<String, Long> e : approvedExternalNavUntilMs.entrySet()) {
      if (e.getValue() < now) {
        approvedExternalNavUntilMs.remove(e.getKey());
        continue;
      }
      if (e.getKey().startsWith(webViewId + "|")) {
        String approvedHost = e.getKey().substring((webViewId + "|").length());
        if (extractRegistrableRoot(approvedHost).equals(root)) {
          return true;
        }
      }
    }
    return false;
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
    notifyBlockedOnMainThread(webViewId, domain, 14200L);
  }

  private void notifyBlockedOnMainThread(
      final long webViewId, final String domain, final long bytesSaved) {
    mainHandler.post(
        () -> {
          MethodChannel ch = this.channel;
          if (ch != null) {
            Map<String, Object> payload = new HashMap<>(6);
            payload.put("webViewId", webViewId);
            payload.put("domain", domain);
            payload.put("bytesSaved", bytesSaved);
            ch.invokeMethod("onResourceBlocked", payload);
          }
        });
  }

  private void notifyBytesSavedOnMainThread(final long bytesSaved) {
    mainHandler.post(
        () -> {
          MethodChannel ch = this.channel;
          if (ch != null) {
            ch.invokeMethod("onBytesSaved", Collections.singletonMap("bytesSaved", bytesSaved));
          }
        });
  }

  private void notifyRedirectBlockedOnMainThread(final long webViewId, final String target) {
    notifyBlockedOnMainThread(webViewId, target, 24000L);
    mainHandler.post(
        () -> {
          MethodChannel ch = this.channel;
          if (ch != null) {
            Map<String, Object> payload = new HashMap<>(4);
            payload.put("webViewId", webViewId);
            payload.put("target", target);
            ch.invokeMethod("onRedirectBlocked", payload);
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
      if (request != null && chromeExtManager != null) {
        WebResourceResponse extRes =
            chromeExtManager.interceptExtensionRequest(
                request.getUrl(), activePopupTabUrl, activePopupTabTitle);
        if (extRes != null) {
          return extRes;
        }
      }
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
      if (request != null && request.getUrl() != null) {
        Uri rawUri = request.getUrl();
        String rawScheme =
            rawUri.getScheme() != null ? rawUri.getScheme().toLowerCase(Locale.US) : "";

        // 0. Never block Chrome/Firefox Extension URLs — rewrite chrome-extension:// to virtual HTTPS host!
        if ("chrome-extension".equals(rawScheme) || "moz-extension".equals(rawScheme)) {
          String mapped = HeavenChromeExtManager.normalizeExtensionUrl(rawUri.toString(), "");
          if (mapped != null && !mapped.isEmpty()) {
            currentPageHosts.put(webViewId, HeavenChromeExtManager.EXT_VIRTUAL_HOST);
            view.loadUrl(mapped);
          }
          return true;
        }
      }

      if (request != null && request.isForMainFrame() && request.getUrl() != null) {
        Uri destUri = request.getUrl();
        String scheme = destUri.getScheme() != null ? destUri.getScheme().toLowerCase(Locale.US) : "";
        String destHost = normalizeHost(destUri.getHost());
        String prevHost = currentPageHosts.get(webViewId);
        boolean pageTrusted = prevHost != null && isTrustedHost(prevHost);
        boolean fromOrToExtension =
            HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(destHost)
                || HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(prevHost);

        // 1. Always allow Chrome Extension pages and any redirect initiated from an Extension!
        if (fromOrToExtension) {
          if (!destHost.isEmpty()) {
            currentPageHosts.put(webViewId, destHost);
          }
          if (HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(destHost)) {
            view.getSettings().setJavaScriptCanOpenWindowsAutomatically(true);
          }
          return delegate != null
              ? delegate.shouldOverrideUrlLoading(view, request)
              : super.shouldOverrideUrlLoading(view, request);
        }

        // 2. Force Desktop Windows Chrome 134 mode automatically for Chrome Web Store!
        if (isChromeWebStoreUri(destUri)) {
          String curUa = view.getSettings().getUserAgentString();
          currentPageHosts.put(webViewId, destHost);
          if (curUa == null || curUa.contains("Mobile") || curUa.contains("Android")) {
            view.getSettings().setUserAgentString(DESKTOP_CHROME_WIN_UA);
            view.getSettings().setUseWideViewPort(true);
            view.getSettings().setLoadWithOverviewMode(true);
            Map<String, String> chHeaders = new HashMap<>(6);
            chHeaders.put(
                "Sec-CH-UA",
                "\"Chromium\";v=\"134\", \"Not:A-Brand\";v=\"24\", \"Google Chrome\";v=\"134\"");
            chHeaders.put("Sec-CH-UA-Mobile", "?0");
            chHeaders.put("Sec-CH-UA-Platform", "\"Windows\"");
            view.loadUrl(destUri.toString(), chHeaders);
            return true;
          }
          return delegate != null
              ? delegate.shouldOverrideUrlLoading(view, request)
              : super.shouldOverrideUrlLoading(view, request);
        }

        // Restore normal UA when navigating away from Chrome Web Store if desktopMode is false
        if (!desktopMode && "chromewebstore.google.com".equals(prevHost) && !isChromeWebStoreUri(destUri)) {
          applyDesktopSettingsToWebView(view, webViewId, false, true);
        }

        // 3. Targeted Ad / Malware / Adult-Trap / Play-Store Hijack Firewall (never blocks normal or extension redirects!)
        if ((shieldEnabled || antiRedirectEnabled) && !pageTrusted) {
          if (!"http".equals(scheme)
              && !"https".equals(scheme)
              && !"about".equals(scheme)
              && !"blob".equals(scheme)
              && !"data".equals(scheme)) {
            if (!"mailto".equals(scheme) && !"tel".equals(scheme)) {
              notifyRedirectBlockedOnMainThread(webViewId, scheme + "://");
              return true;
            }
          }
          Long userNavUntil = userInitiatedNavUntilMs.get(webViewId);
          boolean inUserNavGrace =
              userNavUntil != null && System.currentTimeMillis() <= userNavUntil;
          if (!inUserNavGrace
              && ("play.google.com".equals(destHost) || "apps.apple.com".equals(destHost))
              && prevHost != null
              && !prevHost.contains("google.")
              && !isApprovedExternalNav(webViewId, destHost)) {
            notifyRedirectBlockedOnMainThread(webViewId, destHost);
            return true;
          }
          if (matchesBlockedDomain(destHost)
              || (!isApprovedExternalNav(webViewId, destHost)
                  && isSuspiciousRedirectTarget(destUri, prevHost))) {
            notifyRedirectBlockedOnMainThread(
                webViewId, destHost.isEmpty() ? "ad-redirect" : destHost);
            return true;
          }
        }

        if (!destHost.isEmpty()) {
          currentPageHosts.put(webViewId, destHost);
        }
      }
      return delegate != null
          ? delegate.shouldOverrideUrlLoading(view, request)
              : super.shouldOverrideUrlLoading(view, request);
    }

    @Override
    @SuppressWarnings("deprecation")
    public boolean shouldOverrideUrlLoading(WebView view, String url) {
      if (url != null) {
        String lower = url.toLowerCase(Locale.US);
        if (lower.startsWith("chrome-extension://") || lower.startsWith("moz-extension://")) {
          String mapped = HeavenChromeExtManager.normalizeExtensionUrl(url, "");
          view.loadUrl(mapped);
          return true;
        }
        if (shieldEnabled) {
          Uri u = Uri.parse(url);
          String destHost = normalizeHost(u.getHost());
          String prevHost = currentPageHosts.get(webViewId);
          if (!HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(destHost)
              && !HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(prevHost)
              && (matchesBlockedDomain(destHost) || isSuspiciousRedirectTarget(u, prevHost))) {
            notifyBlockedOnMainThread(webViewId, destHost);
            return true;
          }
        }
      }
      return delegate != null
          ? delegate.shouldOverrideUrlLoading(view, url)
          : super.shouldOverrideUrlLoading(view, url);
    }

    @Override
    public void onPageStarted(WebView view, String url, Bitmap favicon) {
      emitNavBarVisibility(webViewId, true);
      boolean isCws = false;
      boolean isExtPage = false;
      if (url != null) {
        Uri parsed = Uri.parse(url);
        isCws = isChromeWebStoreUri(parsed);
        String host = normalizeHost(parsed.getHost());
        isExtPage = HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(host);
        if (!host.isEmpty()) {
          currentPageHosts.put(webViewId, host);
        }
      }
      view.getSettings().setJavaScriptCanOpenWindowsAutomatically(isExtPage);
      if (isCws) {
        view.getSettings().setUserAgentString(DESKTOP_CHROME_WIN_UA);
        view.getSettings().setUseWideViewPort(true);
        view.getSettings().setLoadWithOverviewMode(true);
      } else if (desktopMode && !isExtPage) {
        applyDesktopSettingsToWebView(view, webViewId, true, false);
      }
      if (delegate != null) {
        delegate.onPageStarted(view, url, favicon);
      } else {
        super.onPageStarted(view, url, favicon);
      }
      injectScripts(view, url, "document_start");
    }

    @Override
    public void onPageCommitVisible(WebView view, String url) {
      if (delegate != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        delegate.onPageCommitVisible(view, url);
      } else {
        super.onPageCommitVisible(view, url);
      }
      injectScripts(view, url, "document_idle");
    }

    @Override
    public void onPageFinished(WebView view, String url) {
      if (delegate != null) {
        delegate.onPageFinished(view, url);
      } else {
        super.onPageFinished(view, url);
      }
      if (url != null && (url.startsWith("http://") || url.startsWith("https://"))) {
        Uri parsedFin = Uri.parse(url);
        String finHost = normalizeHost(parsedFin.getHost());
        if (!finHost.isEmpty() && !HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(finHost)) {
          activeFocusedWebViewId = webViewId;
          activePopupTabUrl = url;
          String wvTitle = view != null ? view.getTitle() : null;
          activePopupTabTitle =
              (wvTitle != null && !wvTitle.trim().isEmpty()) ? wvTitle.trim() : finHost;
        }
      }
      injectScripts(view, url, "all");
    }

    private void injectScripts(final WebView view, final String url, final String extStage) {
      Uri parsed = url != null ? Uri.parse(url) : null;
      boolean isCws = isChromeWebStoreUri(parsed);
      boolean isExtPage =
          parsed != null
              && HeavenChromeExtManager.EXT_VIRTUAL_HOST.equals(normalizeHost(parsed.getHost()));
      if (isCws) {
        view.evaluateJavascript(CHROME_WEB_STORE_DESKTOP_SCRIPT, null);
      } else if (desktopMode && !isExtPage) {
        view.evaluateJavascript(DESKTOP_VIEWPORT_SCRIPT, null);
      }
      view.evaluateJavascript(
          "window.__heavenBgMediaEnabled="
              + backgroundMediaEnabled
              + ";window.__heavenWebNotifsBlocked="
              + (!webNotificationsEnabled)
              + ";window.__heavenUltraDataSaver="
              + ultraDataSaverMode
              + ";window.__hbInBg="
              + appInBackground
              + ";"
              + BG_AUDIO_AND_SCROLL_SCRIPT
              + ULTRA_DATA_SAVER_STYLE_SCRIPT,
          null);

      // Inject enabled Chrome Extensions (.crx / MV2 & MV3) on EVERY search engine & website!
      if (chromeExtManager != null && url != null && url.startsWith("http") && !isCws && !isExtPage) {
        downloadPool.execute(
            () -> {
              final String extBundle =
                  chromeExtManager.buildContentScriptsBundleForUrl(url, extStage, false);
              if (!extBundle.isEmpty()) {
                mainHandler.post(() -> view.evaluateJavascript(extBundle, null));
              }
            });
      }

      if (!shieldEnabled) {
        return;
      }
      String pageHost = currentPageHosts.get(webViewId);
      if (pageHost != null && isTrustedHost(pageHost)) {
        return;
      }
      view.evaluateJavascript(EARLY_YOUTUBE_AND_REDIRECT_GUARD_SCRIPT, null);
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
