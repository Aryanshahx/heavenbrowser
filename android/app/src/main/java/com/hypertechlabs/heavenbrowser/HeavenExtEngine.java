package com.hypertechlabs.heavenbrowser;

import android.graphics.Bitmap;
import android.net.Uri;
import android.net.http.SslError;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.view.KeyEvent;
import android.webkit.ClientCertRequest;
import android.webkit.HttpAuthHandler;
import android.webkit.JavascriptInterface;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.SafeBrowsingResponse;
import android.webkit.SslErrorHandler;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
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
import org.json.JSONObject;

/**
 * Native Chrome Desktop Extension Compatibility &amp; Execution Engine for Heaven Web Store.
 *
 * <p>Provides:
 * <ul>
 *   <li>Zero-jank single-bundle {@code DOCUMENT_START} compilation of enabled Top 10 extensions.
 *   <li>CSP-bypassing {@code HeavenExtBridge} background HTTPS fetch API (for SponsorBlock,
 *       Return YouTube Dislike, Quick Dictionary) restricted to audited public endpoints.
 *   <li>Lightweight {@code chrome.runtime} / {@code chrome.storage.local} desktop polyfill.
 *   <li>Optional O(1) native subresource ad/tracker filter active ONLY when {@code ublock_lite}
 *       is installed and enabled by the user.
 * </ul>
 */
public final class HeavenExtEngine {
  public static final String EXT_UBLOCK_LITE = "ublock_lite";
  public static final String EXT_DARK_READER = "dark_reader";
  public static final String EXT_SPONSORBLOCK = "sponsorblock";
  public static final String EXT_RETURN_YT_DISLIKE = "return_yt_dislike";
  public static final String EXT_VIDEO_SPEED = "video_speed";
  public static final String EXT_CLEAR_URLS = "clear_urls";
  public static final String EXT_CONSENT_O_MATIC = "consent_o_matic";
  public static final String EXT_GOOGLE_DICTIONARY = "google_dictionary";
  public static final String EXT_WRITE_CHECK = "write_check";
  public static final String EXT_ALLOW_COPY = "allow_copy";

  // Audited host allowlist for HeavenExtBridge cross-origin extension API requests.
  private static final Set<String> ALLOWED_API_HOSTS =
      new HashSet<>(
          Arrays.asList(
              "sponsor.ajay.app",
              "returnyoutubedislikeapi.com",
              "api.dictionaryapi.dev"));

  private static final Set<String> UBLOCK_LITE_AD_DOMAINS =
      new HashSet<>(
          Arrays.asList(
              "doubleclick.net",
              "googlesyndication.com",
              "googleadservices.com",
              "adservice.google.com",
              "2mdn.net",
              "adnxs.com",
              "rubiconproject.com",
              "pubmatic.com",
              "openx.net",
              "criteo.com",
              "criteo.net",
              "taboola.com",
              "outbrain.com",
              "mgid.com",
              "revcontent.com",
              "amazon-adsystem.com",
              "moatads.com",
              "adsafeprotected.com",
              "exoclick.com",
              "exosrv.com",
              "adsterra.com",
              "propellerads.com",
              "popads.net",
              "popcash.net",
              "onclickads.net",
              "hilltopads.net",
              "juicyads.com",
              "trafficjunky.net",
              "clickadu.com",
              "adcash.com",
              "scorecardresearch.com",
              "quantserve.com",
              "hotjar.com",
              "clarity.ms"));

  private static final byte[] EMPTY_JS = "/**/".getBytes(StandardCharsets.UTF_8);

  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final ExecutorService extHttpPool =
      Executors.newFixedThreadPool(
          2,
          r -> {
            Thread t = new Thread(r, "heaven-ext-http");
            t.setDaemon(true);
            t.setPriority(Thread.NORM_PRIORITY - 1);
            return t;
          });

  private final Set<String> enabledExtensionIds = ConcurrentHashMap.newKeySet();
  private final ConcurrentHashMap<String, String> extensionStorage = new ConcurrentHashMap<>();
  private volatile String cachedCompiledBundle = null;

  public void shutdown() {
    extHttpPool.shutdownNow();
  }

  public void setEnabledExtensions(List<String> ids) {
    Set<String> next = new HashSet<>();
    if (ids != null) {
      for (String id : ids) {
        if (id != null && !id.trim().isEmpty()) {
          next.add(id.trim());
        }
      }
    }
    if (!next.equals(enabledExtensionIds)) {
      enabledExtensionIds.clear();
      enabledExtensionIds.addAll(next);
      cachedCompiledBundle = null;
    }
  }

  public boolean isUblockLiteActive() {
    return enabledExtensionIds.contains(EXT_UBLOCK_LITE);
  }

  public void attachBridgeAndClient(final WebView webView, final long webViewId) {
    if (webView == null) {
      return;
    }
    try {
      webView.addJavascriptInterface(new WebViewExtJsBridge(webView), "HeavenExtBridge");
    } catch (Throwable ignored) {
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      try {
        WebViewClient existing = webView.getWebViewClient();
        if (existing != null && !(existing instanceof ExtAwareWebViewClient)) {
          webView.setWebViewClient(new ExtAwareWebViewClient(existing, webViewId));
        }
      } catch (Throwable ignored) {
      }
    }
  }

  private WebResourceResponse interceptIfUblockEnabled(WebResourceRequest request) {
    if (!enabledExtensionIds.contains(EXT_UBLOCK_LITE)
        || request == null
        || request.isForMainFrame()) {
      return null;
    }
    Uri uri = request.getUrl();
    if (uri == null) {
      return null;
    }
    String host = uri.getHost();
    if (host == null || host.isEmpty()) {
      return null;
    }
    String cur = host.toLowerCase(Locale.US);
    while (true) {
      if (UBLOCK_LITE_AD_DOMAINS.contains(cur)) {
        Map<String, String> headers = new HashMap<>(4);
        headers.put("Access-Control-Allow-Origin", "*");
        headers.put("Cache-Control", "no-store");
        return new WebResourceResponse(
            "application/javascript",
            "utf-8",
            200,
            "OK",
            headers,
            new ByteArrayInputStream(EMPTY_JS));
      }
      int dot = cur.indexOf('.');
      if (dot < 0 || dot + 1 >= cur.length()) {
        break;
      }
      cur = cur.substring(dot + 1);
    }
    return null;
  }

  /**
   * Builds and caches a single zero-jank {@code DOCUMENT_START} bundle containing:
   * 1) Top safe-area inset for the floating zero-pull search bar, and
   * 2) Only the currently enabled Heaven Web Store extensions.
   */
  public String getCompiledDocumentStartBundle() {
    String existing = cachedCompiledBundle;
    if (existing != null) {
      return existing;
    }
    StringBuilder sb = new StringBuilder(12288);
    sb.append("(function(){try{");
    sb.append("if(window.__hbExtRuntimeV18)return;window.__hbExtRuntimeV18=true;");

    // 1. Static top breathing space for the floating zero-pull top bar (never mutates on scroll!)
    sb.append(
        "function applyTopSafeSpace(){"
            + "  if(window!==window.top)return;"
            + "  if(document.getElementById('__hb_top_safe_css'))return;"
            + "  var st=document.createElement('style');st.id='__hb_top_safe_css';"
            + "  st.textContent='html:not(:fullscreen){padding-top:52px!important;scroll-padding-top:56px!important;box-sizing:border-box;}';"
            + "  (document.head||document.documentElement).appendChild(st);"
            + "}"
            + "if(document.head||document.documentElement){applyTopSafeSpace();}"
            + "else{document.addEventListener('DOMContentLoaded',applyTopSafeSpace,{once:true});}");

    if (enabledExtensionIds.isEmpty()) {
      sb.append("}catch(_){}})();");
      String minimal = sb.toString();
      cachedCompiledBundle = minimal;
      return minimal;
    }

    // 2. Chrome Desktop Extension API Compatibility Shim (chrome.runtime + chrome.storage.local + CSP-safe fetch)
    sb.append(
        "window.__hbScrollActive=false;var __hbScrollEndT=0;"
            + "window.addEventListener('scroll',function(){"
            + "  window.__hbScrollActive=true;"
            + "  clearTimeout(__hbScrollEndT);"
            + "  __hbScrollEndT=setTimeout(function(){window.__hbScrollActive=false;},240);"
            + "},{passive:true});"
            + "window.__hbRunIdle=function(fn){"
            + "  if(window.requestIdleCallback){window.requestIdleCallback(function(){if(!window.__hbScrollActive)fn();},{timeout:600});}"
            + "  else{setTimeout(function(){if(!window.__hbScrollActive)fn();},180);}"
            + "};"
            + "var __hbCbs={},__hbSeq=1;"
            + "window.__hbResolveFetch=function(id,ok,body){"
            + "  var cb=__hbCbs[id];if(!cb)return;delete __hbCbs[id];"
            + "  if(ok)cb.res(body);else cb.rej(new Error(body||'err'));"
            + "};"
            + "window.__hbExtFetchJson=function(url){"
            + "  return new Promise(function(res,rej){"
            + "    if(window.HeavenExtBridge&&window.HeavenExtBridge.fetchJson){"
            + "      var id='r'+(++__hbSeq);"
            + "      __hbCbs[id]={res:function(txt){try{res(JSON.parse(txt));}catch(e){rej(e);}},rej:rej};"
            + "      window.HeavenExtBridge.fetchJson(id,url);"
            + "    }else{fetch(url).then(function(r){return r.json();}).then(res).catch(rej);}"
            + "  });"
            + "};"
            + "window.chrome=window.chrome||{};"
            + "window.chrome.runtime=window.chrome.runtime||{id:'heaven-desktop-compat',getManifest:function(){return{manifest_version:3,name:'Heaven Desktop Extension Runtime',version:'1.0'};}};"
            + "window.chrome.storage=window.chrome.storage||{local:{"
            + "  get:function(k,cb){var v=window.HeavenExtBridge?window.HeavenExtBridge.storageGet(String(k)):null;var o={};o[k]=v;if(cb)cb(o);return Promise.resolve(o);},"
            + "  set:function(o,cb){if(window.HeavenExtBridge&&o){Object.keys(o).forEach(function(k){window.HeavenExtBridge.storageSet(k,String(o[k]));});}if(cb)cb();return Promise.resolve();}"
            + "}};");

    // Extension 1: uBlock Origin Lite (Cosmetic cleanup pairing with native O(1) network filter)
    if (enabledExtensionIds.contains(EXT_UBLOCK_LITE)) {
      sb.append(
          "(function(){try{"
              + "function injectUbo(){"
              + "  if(document.getElementById('__hb_ext_ubo'))return;"
              + "  var s=document.createElement('style');s.id='__hb_ext_ubo';"
              + "  s.textContent='ins.adsbygoogle,[id^=\"div-gpt-ad\"],[id^=\"google_ads_iframe\"],.OUTBRAIN,[id^=\"taboola-\"],[data-ad-slot],ytd-ad-slot-renderer,ytm-promoted-sparkles-web-renderer,.ytp-ad-overlay-container{display:none!important;height:0!important;min-height:0!important;margin:0!important;}';"
              + "  (document.head||document.documentElement).appendChild(s);"
              + "}"
              + "if(document.head)injectUbo();else document.addEventListener('DOMContentLoaded',injectUbo,{once:true});"
              + "}catch(_){}})();");
    }

    // Extension 2: Dark Reader (Luminance-aware GPU dark mode — skips already-dark sites & preserves media!)
    if (enabledExtensionIds.contains(EXT_DARK_READER)) {
      sb.append(
          "(function(){try{"
              + "function applyDarkReader(){"
              + "  if(document.getElementById('__hb_ext_darkreader'))return;"
              + "  var bg=getComputedStyle(document.body||document.documentElement).backgroundColor||'';"
              + "  var m=bg.match(/\\d+/g);"
              + "  if(m&&m.length>=3){"
              + "    var a=m.length>=4?parseFloat(m[3]):1;"
              + "    var lum=(0.299*(+m[0])+0.587*(+m[1])+0.114*(+m[2]));"
              + "    if(a>0.2&&lum<85)return;"
              + "  }"
              + "  var cs=document.querySelector('meta[name=\"color-scheme\"]');"
              + "  if(cs&&(cs.content||'').toLowerCase()==='dark')return;"
              + "  var s=document.createElement('style');s.id='__hb_ext_darkreader';"
              + "  s.textContent='html{filter:invert(0.91) hue-rotate(180deg)!important;background:#fff!important;}img,video,picture,canvas,iframe,[style*=\"background-image\"]{filter:invert(1) hue-rotate(180deg)!important;}';"
              + "  (document.head||document.documentElement).appendChild(s);"
              + "}"
              + "document.addEventListener('DOMContentLoaded',function(){window.__hbRunIdle(applyDarkReader);},{once:true});"
              + "}catch(_){}})();");
    }

    // Extension 3: SponsorBlock for YouTube (Live sponsor.ajay.app segments + auto-skip toast)
    if (enabledExtensionIds.contains(EXT_SPONSORBLOCK)) {
      sb.append(
          "(function(){try{"
              + "if((location.hostname||'').indexOf('youtube.com')<0)return;"
              + "var curVid='',segs=[];"
              + "function toastSkip(cat){"
              + "  var d=document.createElement('div');"
              + "  d.textContent='SponsorBlock skipped '+(cat||'sponsor');"
              + "  d.style.cssText='position:fixed;bottom:72px;right:14px;z-index:2147483647;background:#0B162C;color:#60A5FA;border:1px solid #2563EB;padding:6px 12px;border-radius:999px;font:600 12px system-ui;box-shadow:0 4px 14px rgba(0,0,0,.4);';"
              + "  document.body.appendChild(d);setTimeout(function(){d.remove();},2200);"
              + "}"
              + "function checkVideoId(){"
              + "  var u=new URLSearchParams(location.search);var v=u.get('v')||'';"
              + "  if(!v||v===curVid)return;curVid=v;segs=[];"
              + "  window.__hbExtFetchJson('https://sponsor.ajay.app/api/skipSegments?videoID='+encodeURIComponent(v)+'&categories=%5B%22sponsor%22,%22selfpromo%22%5D')"
              + "    .then(function(arr){if(Array.isArray(arr))segs=arr;}).catch(function(){});"
              + "}"
              + "setInterval(function(){"
              + "  if(window.__hbScrollActive)return;"
              + "  checkVideoId();"
              + "  if(!segs.length)return;"
              + "  var vid=document.querySelector('video');if(!vid||vid.paused)return;"
              + "  var t=vid.currentTime;"
              + "  for(var i=0;i<segs.length;i++){"
              + "    var seg=segs[i].segment;"
              + "    if(seg&&t>=seg[0]&&t<seg[1]-0.4){vid.currentTime=seg[1];toastSkip(segs[i].category);break;}"
              + "  }"
              + "},1100);"
              + "}catch(_){}})();");
    }

    // Extension 4: Return YouTube Dislike (Live returnyoutubedislikeapi.com integration)
    if (enabledExtensionIds.contains(EXT_RETURN_YT_DISLIKE)) {
      sb.append(
          "(function(){try{"
              + "if((location.hostname||'').indexOf('youtube.com')<0)return;"
              + "var lastId='',dislikeText='';"
              + "function fmtCount(n){if(n>=1e6)return(n/1e6).toFixed(1)+'M';if(n>=1e3)return(n/1e3).toFixed(1)+'K';return String(n);}"
              + "function renderDislike(){"
              + "  if(!dislikeText)return;"
              + "  var btns=document.querySelectorAll('dislike-button-view-model button,ytm-dislike-button-renderer button,button[aria-label*=\"dislike\" i]');"
              + "  for(var i=0;i<btns.length;i++){"
              + "    var b=btns[i];"
              + "    if(!b.querySelector('.__hb_ryd')){var sp=document.createElement('span');sp.className='__hb_ryd';sp.style.cssText='margin-left:5px;font-weight:600;font-size:12px;';sp.textContent=dislikeText;b.appendChild(sp);}"
              + "    else{b.querySelector('.__hb_ryd').textContent=dislikeText;}"
              + "  }"
              + "}"
              + "setInterval(function(){"
              + "  if(window.__hbScrollActive)return;"
              + "  var v=(new URLSearchParams(location.search)).get('v')||'';"
              + "  if(!v)return;"
              + "  if(v!==lastId){lastId=v;dislikeText='';"
              + "    window.__hbExtFetchJson('https://returnyoutubedislikeapi.com/votes?videoId='+encodeURIComponent(v))"
              + "      .then(function(d){if(d&&typeof d.dislikes==='number'){dislikeText=fmtCount(d.dislikes);renderDislike();}}).catch(function(){});"
              + "  }else{renderDislike();}"
              + "},1800);"
              + "}catch(_){}})();");
    }

    // Extension 5: Video Speed Controller (Floating 0.25x - 4.0x HTML5 video controller pill)
    if (enabledExtensionIds.contains(EXT_VIDEO_SPEED)) {
      sb.append(
          "(function(){try{"
              + "function attachVsc(){"
              + "  var vids=document.querySelectorAll('video');"
              + "  for(var i=0;i<vids.length;i++){"
              + "    var v=vids[i];if(v.__hbVsc||v.clientWidth<140)continue;"
              + "    var p=v.parentElement;if(!p)continue;v.__hbVsc=true;"
              + "    if(getComputedStyle(p).position==='static')p.style.position='relative';"
              + "    var bar=document.createElement('div');"
              + "    bar.style.cssText='position:absolute;top:8px;left:8px;z-index:2147483640;display:flex;gap:5px;align-items:center;background:rgba(4,11,22,0.72);color:#fff;padding:3px 8px;border-radius:999px;font:700 11px system-ui;backdrop-filter:blur(4px);pointer-events:auto;';"
              + "    function mkBtn(t,fn){var b=document.createElement('span');b.textContent=t;b.style.cssText='padding:2px 5px;cursor:pointer;user-select:none;';b.addEventListener('click',function(e){e.stopPropagation();e.preventDefault();fn();},true);return b;}"
              + "    var lbl=document.createElement('span');lbl.textContent=(v.playbackRate||1).toFixed(2)+'x';"
              + "    (function(video,label){"
              + "      bar.appendChild(mkBtn('−',function(){video.playbackRate=Math.max(0.25,Math.round((video.playbackRate-0.25)*100)/100);label.textContent=video.playbackRate.toFixed(2)+'x';}));"
              + "      bar.appendChild(label);"
              + "      bar.appendChild(mkBtn('+',function(){video.playbackRate=Math.min(4.0,Math.round((video.playbackRate+0.25)*100)/100);label.textContent=video.playbackRate.toFixed(2)+'x';}));"
              + "      bar.appendChild(mkBtn('»10s',function(){video.currentTime=Math.min(video.duration||999999,video.currentTime+10);}));"
              + "    })(v,lbl);"
              + "    p.appendChild(bar);"
              + "  }"
              + "}"
              + "setInterval(function(){if(!window.__hbScrollActive)attachVsc();},2000);"
              + "}catch(_){}})();");
    }

    // Extension 6: ClearURLs (Strips tracking params across all search engines & links)
    if (enabledExtensionIds.contains(EXT_CLEAR_URLS)) {
      sb.append(
          "(function(){try{"
              + "var bad=/^(utm_[a-z0-9_]+|fbclid|gclid|dclid|msclkid|mc_eid|igshid|yclid|_hsenc|_hsmi|mkt_tok|rb_clickid|oly_enc_id|vero_id)$/i;"
              + "function cleanHref(raw){"
              + "  try{var u=new URL(raw,location.href);var ch=false;"
              + "  Array.from(u.searchParams.keys()).forEach(function(k){if(bad.test(k)){u.searchParams.delete(k);ch=true;}});"
              + "  return ch?u.toString():null;}catch(_){return null;}"
              + "}"
              + "var cleanedSelf=cleanHref(location.href);"
              + "if(cleanedSelf&&history.replaceState)history.replaceState(null,'',cleanedSelf);"
              + "document.addEventListener('click',function(ev){"
              + "  var a=ev.target&&ev.target.closest?ev.target.closest('a[href]'):null;"
              + "  if(!a)return;var c=cleanHref(a.href);if(c)a.href=c;"
              + "},{passive:true,capture:true});"
              + "}catch(_){}})();");
    }

    // Extension 7: I Don't Care About Cookies (Dismisses/hides GDPR & cookie banners cleanly)
    if (enabledExtensionIds.contains(EXT_CONSENT_O_MATIC)) {
      sb.append(
          "(function(){try{"
              + "function hideCookieWalls(){"
              + "  if(document.getElementById('__hb_ext_cookie'))return;"
              + "  var s=document.createElement('style');s.id='__hb_ext_cookie';"
              + "  s.textContent='#onetrust-consent-sdk,#CybotCookiebotDialog,.qc-cmp2-container,#didomi-host,.cc-window,.osano-cm-window,[id*=\"cookie-banner\" i],[class*=\"cookie-consent\" i]{display:none!important;opacity:0!important;pointer-events:none!important;}';"
              + "  (document.head||document.documentElement).appendChild(s);"
              + "  if(document.body&&getComputedStyle(document.body).overflow==='hidden')document.body.style.overflow='auto';"
              + "}"
              + "document.addEventListener('DOMContentLoaded',function(){window.__hbRunIdle(hideCookieWalls);},{once:true});"
              + "}catch(_){}})();");
    }

    // Extension 8: Quick Dictionary Lookup (Double-tap word on any search engine / article)
    if (enabledExtensionIds.contains(EXT_GOOGLE_DICTIONARY)) {
      sb.append(
          "(function(){try{"
              + "var card=null;"
              + "function showDef(word,phon,meaning){"
              + "  if(card)card.remove();"
              + "  card=document.createElement('div');"
              + "  card.style.cssText='position:fixed;left:14px;right:14px;bottom:18px;z-index:2147483647;background:#0B162C;color:#F8FAFC;border:1.5px solid #3B82F6;border-radius:16px;padding:12px 14px;font:400 13px/1.4 system-ui;box-shadow:0 10px 28px rgba(0,0,0,.55);';"
              + "  var h=document.createElement('div');h.style.cssText='font-weight:800;font-size:14px;color:#60A5FA;margin-bottom:4px;';"
              + "  h.textContent=word+(phon?'  '+phon:'');"
              + "  var p=document.createElement('div');p.textContent=meaning;"
              + "  card.appendChild(h);card.appendChild(p);"
              + "  card.addEventListener('click',function(){card.remove();card=null;});"
              + "  document.body.appendChild(card);"
              + "  setTimeout(function(){if(card){card.remove();card=null;}},6500);"
              + "}"
              + "document.addEventListener('dblclick',function(){"
              + "  var sel=(window.getSelection&&window.getSelection().toString()||'').trim();"
              + "  if(!/^[A-Za-z]{3,24}$/.test(sel))return;"
              + "  window.__hbExtFetchJson('https://api.dictionaryapi.dev/api/v2/entries/en/'+encodeURIComponent(sel.toLowerCase()))"
              + "    .then(function(arr){"
              + "      if(!Array.isArray(arr)||!arr[0]||!arr[0].meanings||!arr[0].meanings[0])return;"
              + "      var def=arr[0].meanings[0].definitions&&arr[0].meanings[0].definitions[0]?arr[0].meanings[0].definitions[0].definition:'';"
              + "      if(def)showDef(arr[0].word||sel,arr[0].phonetic||'',def);"
              + "    }).catch(function(){});"
              + "},{passive:true});"
              + "}catch(_){}})();");
    }

    // Extension 9: Grammarly Lite Writing Assistant (Word count + 1-tap typo polish on textareas)
    if (enabledExtensionIds.contains(EXT_WRITE_CHECK)) {
      sb.append(
          "(function(){try{"
              + "var badge=null,activeEl=null;"
              + "var fixes={' teh ':' the ',' recieve ':' receive ',' definately ':' definitely ',' seperate ':' separate ',' occured ':' occurred '};"
              + "function ensureBadge(){"
              + "  if(badge)return badge;"
              + "  badge=document.createElement('div');"
              + "  badge.style.cssText='position:fixed;bottom:14px;right:14px;z-index:2147483645;background:#2563EB;color:#fff;padding:5px 10px;border-radius:999px;font:700 11.5px system-ui;box-shadow:0 4px 12px rgba(0,0,0,.35);display:none;cursor:pointer;';"
              + "  badge.addEventListener('click',function(){"
              + "    if(!activeEl)return;"
              + "    var v=activeEl.value!==undefined?activeEl.value:activeEl.innerText||'';"
              + "    var nv=' '+v+' ';Object.keys(fixes).forEach(function(k){nv=nv.split(k).join(fixes[k]);});"
              + "    nv=nv.trim().replace(/  +/g,' ');"
              + "    if(activeEl.value!==undefined)activeEl.value=nv;else activeEl.innerText=nv;"
              + "    badge.textContent='Polished ✓';"
              + "  });"
              + "  document.body.appendChild(badge);return badge;"
              + "}"
              + "document.addEventListener('input',function(ev){"
              + "  var t=ev.target;if(!t||(t.tagName!=='TEXTAREA'&&!t.isContentEditable))return;"
              + "  activeEl=t;var txt=(t.value!==undefined?t.value:t.innerText||'').trim();"
              + "  var b=ensureBadge();"
              + "  if(txt.length<12){b.style.display='none';return;}"
              + "  var words=txt.split(/\\s+/).length;"
              + "  b.style.display='block';b.textContent=words+' words • Polish';"
              + "},{passive:true});"
              + "document.addEventListener('focusout',function(){if(badge)setTimeout(function(){badge.style.display='none';},1200);},{passive:true});"
              + "}catch(_){}})();");
    }

    // Extension 10: SuperCopy — Allow Copy, Select & Context Menu everywhere
    if (enabledExtensionIds.contains(EXT_ALLOW_COPY)) {
      sb.append(
          "(function(){try{"
              + "function unlockCopy(){"
              + "  if(!document.getElementById('__hb_ext_copy')){"
              + "    var s=document.createElement('style');s.id='__hb_ext_copy';"
              + "    s.textContent='*,*::before,*::after{-webkit-user-select:text!important;user-select:text!important;}';"
              + "    (document.head||document.documentElement).appendChild(s);"
              + "  }"
              + "}"
              + "if(document.head)unlockCopy();else document.addEventListener('DOMContentLoaded',unlockCopy,{once:true});"
              + "['copy','cut','selectstart'].forEach(function(evName){"
              + "  window.addEventListener(evName,function(e){e.stopImmediatePropagation();},{capture:true,passive:true});"
              + "});"
              + "}catch(_){}})();");
    }

    sb.append("}catch(_){}})();");
    String built = sb.toString();
    cachedCompiledBundle = built;
    return built;
  }

  private final class WebViewExtJsBridge {
    private final WebView webView;

    WebViewExtJsBridge(WebView webView) {
      this.webView = webView;
    }

    @JavascriptInterface
    public String storageGet(String key) {
      return key != null ? extensionStorage.get(key) : null;
    }

    @JavascriptInterface
    public void storageSet(String key, String value) {
      if (key != null && value != null && extensionStorage.size() < 512) {
        extensionStorage.put(key, value);
      }
    }

    @JavascriptInterface
    public void fetchJson(final String reqId, final String rawUrl) {
      if (reqId == null || rawUrl == null) {
        return;
      }
      extHttpPool.execute(
          () -> {
            HttpURLConnection conn = null;
            try {
              URI uri = URI.create(rawUrl);
              String host = uri.getHost() != null ? uri.getHost().toLowerCase(Locale.US) : "";
              if (!"https".equalsIgnoreCase(uri.getScheme()) || !ALLOWED_API_HOSTS.contains(host)) {
                deliverFetchResult(reqId, false, "disallowed_host");
                return;
              }
              conn = (HttpURLConnection) uri.toURL().openConnection();
              conn.setConnectTimeout(4500);
              conn.setReadTimeout(5500);
              conn.setRequestProperty("Accept", "application/json");
              conn.setRequestProperty("User-Agent", "HeavenBrowser/0.0.1 DesktopExtCompat");
              int code = conn.getResponseCode();
              if (code < 200 || code >= 300) {
                deliverFetchResult(reqId, false, "http_" + code);
                return;
              }
              StringBuilder sb = new StringBuilder(2048);
              try (InputStream is = conn.getInputStream();
                  BufferedReader br =
                      new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
                char[] buf = new char[4096];
                int n;
                int total = 0;
                while ((n = br.read(buf)) > 0) {
                  total += n;
                  if (total > 262144) break;
                  sb.append(buf, 0, n);
                }
              }
              deliverFetchResult(reqId, true, sb.toString());
            } catch (Throwable t) {
              deliverFetchResult(reqId, false, "network_error");
            } finally {
              if (conn != null) {
                conn.disconnect();
              }
            }
          });
    }

    private void deliverFetchResult(final String reqId, final boolean ok, final String payload) {
      final String quotedId = JSONObject.quote(reqId);
      final String quotedBody = JSONObject.quote(payload != null ? payload : "");
      mainHandler.post(
          () -> {
            try {
              webView.evaluateJavascript(
                  "window.__hbResolveFetch&&window.__hbResolveFetch("
                      + quotedId
                      + ","
                      + ok
                      + ","
                      + quotedBody
                      + ");",
                  null);
            } catch (Throwable ignored) {
            }
          });
    }
  }

  private final class ExtAwareWebViewClient extends WebViewClient {
    private final WebViewClient delegate;
    @SuppressWarnings("unused")
    private final long webViewId;

    ExtAwareWebViewClient(WebViewClient delegate, long webViewId) {
      this.delegate = delegate;
      this.webViewId = webViewId;
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
      WebResourceResponse blocked = interceptIfUblockEnabled(request);
      if (blocked != null) {
        return blocked;
      }
      return delegate.shouldInterceptRequest(view, request);
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
      return delegate.shouldOverrideUrlLoading(view, request);
    }

    @Override
    @SuppressWarnings("deprecation")
    public boolean shouldOverrideUrlLoading(WebView view, String url) {
      return delegate.shouldOverrideUrlLoading(view, url);
    }

    @Override
    public void onPageStarted(WebView view, String url, Bitmap favicon) {
      delegate.onPageStarted(view, url, favicon);
    }

    @Override
    public void onPageFinished(WebView view, String url) {
      delegate.onPageFinished(view, url);
    }

    @Override
    public void onPageCommitVisible(WebView view, String url) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        delegate.onPageCommitVisible(view, url);
      }
    }

    @Override
    public void onLoadResource(WebView view, String url) {
      delegate.onLoadResource(view, url);
    }

    @Override
    public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
      delegate.doUpdateVisitedHistory(view, url, isReload);
    }

    @Override
    public void onReceivedError(
        WebView view, WebResourceRequest request, WebResourceError error) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        delegate.onReceivedError(view, request, error);
      }
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onReceivedError(
        WebView view, int errorCode, String description, String failingUrl) {
      delegate.onReceivedError(view, errorCode, description, failingUrl);
    }

    @Override
    public void onReceivedHttpError(
        WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        delegate.onReceivedHttpError(view, request, errorResponse);
      }
    }

    @Override
    public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
      delegate.onReceivedSslError(view, handler, error);
    }

    @Override
    public void onReceivedClientCertRequest(WebView view, ClientCertRequest request) {
      delegate.onReceivedClientCertRequest(view, request);
    }

    @Override
    public void onReceivedHttpAuthRequest(
        WebView view, HttpAuthHandler handler, String host, String realm) {
      delegate.onReceivedHttpAuthRequest(view, handler, host, realm);
    }

    @Override
    public void onReceivedLoginRequest(
        WebView view, String realm, String account, String args) {
      delegate.onReceivedLoginRequest(view, realm, account, args);
    }

    @Override
    public void onFormResubmission(WebView view, Message dontResend, Message resend) {
      delegate.onFormResubmission(view, dontResend, resend);
    }

    @Override
    public boolean shouldOverrideKeyEvent(WebView view, KeyEvent event) {
      return delegate.shouldOverrideKeyEvent(view, event);
    }

    @Override
    public void onUnhandledKeyEvent(WebView view, KeyEvent event) {
      delegate.onUnhandledKeyEvent(view, event);
    }

    @Override
    public void onScaleChanged(WebView view, float oldScale, float newScale) {
      delegate.onScaleChanged(view, oldScale, newScale);
    }

    @Override
    public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        return delegate.onRenderProcessGone(view, detail);
      }
      return false;
    }

    @Override
    public void onSafeBrowsingHit(
        WebView view,
        WebResourceRequest request,
        int threatType,
        SafeBrowsingResponse callback) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
        delegate.onSafeBrowsingHit(view, request, threatType, callback);
      }
    }
  }
}
