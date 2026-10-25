package com.hypertechlabs.heavenbrowser;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.net.Uri;
import android.net.http.SslError;
import android.os.Build;
import android.os.Message;
import android.view.KeyEvent;
import android.webkit.ClientCertRequest;
import android.webkit.HttpAuthHandler;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.SafeBrowsingResponse;
import android.webkit.SslErrorHandler;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.io.ByteArrayInputStream;
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
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Native Heaven Shield Engine — zero-jank O(1) subresource ad/tracker filter and customizable
 * {@code DOCUMENT_START} privacy runtime.
 *
 * <p>Engineered for 120Hz scrolling smoothness: performs zero IPC/MethodChannel calls on
 * subresource interception, maintaining lock-free atomic counters queried passively by Flutter.
 */
public final class HeavenShieldEngine {
  private static final String PREFS_NAME = "heaven_shield_prefs_v19";
  private static final String KEY_TOTAL_BLOCKED = "total_blocked_count";

  private static final Set<String> STANDARD_AD_TRACKER_DOMAINS =
      Collections.unmodifiableSet(
          new HashSet<>(
              Arrays.asList(
                  "doubleclick.net",
                  "googlesyndication.com",
                  "googleadservices.com",
                  "adservice.google.com",
                  "pagead2.googlesyndication.com",
                  "2mdn.net",
                  "adnxs.com",
                  "rubiconproject.com",
                  "pubmatic.com",
                  "openx.net",
                  "casalemedia.com",
                  "criteo.com",
                  "criteo.net",
                  "taboola.com",
                  "outbrain.com",
                  "mgid.com",
                  "revcontent.com",
                  "zergnet.com",
                  "amazon-adsystem.com",
                  "moatads.com",
                  "adsafeprotected.com",
                  "doubleverify.com",
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
                  "bidvertiser.com",
                  "adform.net",
                  "smartadserver.com",
                  "teads.tv",
                  "sharethrough.com",
                  "indexexchange.com",
                  "3lift.com",
                  "sovrn.com",
                  "lijit.com",
                  "advertising.com",
                  "quantserve.com",
                  "scorecardresearch.com",
                  "zedo.com",
                  "serving-sys.com",
                  "flashtalking.com",
                  "mediavine.com",
                  "adthrive.com")));

  private static final Set<String> STRICT_EXTRA_TRACKER_DOMAINS =
      Collections.unmodifiableSet(
          new HashSet<>(
              Arrays.asList(
                  "google-analytics.com",
                  "googletagmanager.com",
                  "googletagservices.com",
                  "analytics.google.com",
                  "connect.facebook.net",
                  "pixel.facebook.com",
                  "analytics.tiktok.com",
                  "ads-twitter.com",
                  "analytics.twitter.com",
                  "bat.bing.com",
                  "clarity.ms",
                  "hotjar.com",
                  "hotjar.io",
                  "mouseflow.com",
                  "fullstory.com",
                  "logrocket.io",
                  "mixpanel.com",
                  "segment.io",
                  "segment.com",
                  "amplitude.com",
                  "heapanalytics.com",
                  "newrelic.com",
                  "nr-data.net",
                  "bugsnag.com",
                  "omtrdc.net",
                  "demdex.net",
                  "krxd.net",
                  "bluekai.com",
                  "bkrtx.com",
                  "rlcdn.com",
                  "tapad.com",
                  "appsflyer.com",
                  "adjust.com",
                  "branch.io",
                  "app.link",
                  "pardot.com",
                  "mktoresp.com",
                  "hs-analytics.net",
                  "hsadspixel.net",
                  "yandex.ru",
                  "mc.yandex.ru",
                  "statcounter.com",
                  "chartbeat.com",
                  "chartbeat.net",
                  "parsely.com",
                  "optimizely.com",
                  "crazyegg.com",
                  "luckyorange.com",
                  "cleverpush.com",
                  "onesignal.com")));

  private static final byte[] EMPTY_JS = "/**/".getBytes(StandardCharsets.UTF_8);
  private static final byte[] EMPTY_CSS = "".getBytes(StandardCharsets.UTF_8);
  private static final byte[] EMPTY_TEXT = "".getBytes(StandardCharsets.UTF_8);
  // 1x1 transparent GIF (43 bytes)
  private static final byte[] TRANSPARENT_GIF =
      new byte[] {
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, (byte) 0x80, 0x00, 0x00,
        0x00, 0x00, 0x00, (byte) 0xff, (byte) 0xff, (byte) 0xff, 0x21, (byte) 0xf9, 0x04, 0x01,
        0x00, 0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0x02, 0x02, 0x44, 0x01, 0x00, 0x3b
      };

  private final SharedPreferences prefs;
  private final AtomicLong totalBlockedCount = new AtomicLong(0L);
  private final ConcurrentHashMap<Long, AtomicInteger> pageBlockedByWv = new ConcurrentHashMap<>();
  private final ConcurrentHashMap<Long, String> activeHostByWv = new ConcurrentHashMap<>();
  private final Set<String> disabledHosts = ConcurrentHashMap.newKeySet();

  private volatile boolean shieldEnabled = true;
  private volatile boolean strictMode = false;
  private volatile boolean blockAdsAndTrackers = true;
  private volatile boolean blockCookieBanners = true;
  private volatile boolean cleanTrackingUrls = true;
  private volatile boolean antiFingerprinting = true;
  private volatile boolean blockPopupsAndRedirects = true;
  private volatile String cachedDocumentStartBundle = null;

  public HeavenShieldEngine(Context appContext) {
    this.prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    this.totalBlockedCount.set(Math.max(0L, this.prefs.getLong(KEY_TOTAL_BLOCKED, 0L)));
  }

  public void updateConfiguration(
      Boolean shieldEnabledArg,
      Boolean strictModeArg,
      Boolean blockAdsArg,
      Boolean blockCookieBannersArg,
      Boolean cleanUrlsArg,
      Boolean antiFingerprintArg,
      Boolean blockPopupsArg,
      List<String> disabledHostsArg) {
    boolean changed = false;
    if (shieldEnabledArg != null && this.shieldEnabled != shieldEnabledArg) {
      this.shieldEnabled = shieldEnabledArg;
      changed = true;
    }
    if (strictModeArg != null && this.strictMode != strictModeArg) {
      this.strictMode = strictModeArg;
      changed = true;
    }
    if (blockAdsArg != null && this.blockAdsAndTrackers != blockAdsArg) {
      this.blockAdsAndTrackers = blockAdsArg;
      changed = true;
    }
    if (blockCookieBannersArg != null && this.blockCookieBanners != blockCookieBannersArg) {
      this.blockCookieBanners = blockCookieBannersArg;
      changed = true;
    }
    if (cleanUrlsArg != null && this.cleanTrackingUrls != cleanUrlsArg) {
      this.cleanTrackingUrls = cleanUrlsArg;
      changed = true;
    }
    if (antiFingerprintArg != null && this.antiFingerprinting != antiFingerprintArg) {
      this.antiFingerprinting = antiFingerprintArg;
      changed = true;
    }
    if (blockPopupsArg != null && this.blockPopupsAndRedirects != blockPopupsArg) {
      this.blockPopupsAndRedirects = blockPopupsArg;
      changed = true;
    }
    if (disabledHostsArg != null) {
      Set<String> normalized = new HashSet<>();
      for (String raw : disabledHostsArg) {
        String h = normalizeHost(raw);
        if (!h.isEmpty()) {
          normalized.add(h);
        }
      }
      if (!normalized.equals(this.disabledHosts)) {
        this.disabledHosts.clear();
        this.disabledHosts.addAll(normalized);
        changed = true;
      }
    }
    if (changed) {
      this.cachedDocumentStartBundle = null;
    }
  }

  public void updateWebViewHost(long webViewId, String rawHost) {
    String clean = normalizeHost(rawHost);
    String prev = activeHostByWv.put(webViewId, clean);
    if (prev == null || !prev.equals(clean)) {
      pageBlockedByWv.put(webViewId, new AtomicInteger(0));
    }
  }

  public void attachClient(final WebView webView, final long webViewId, final String initialHost) {
    if (webView == null) {
      return;
    }
    if (initialHost != null && !initialHost.isEmpty()) {
      updateWebViewHost(webViewId, initialHost);
    } else {
      pageBlockedByWv.putIfAbsent(webViewId, new AtomicInteger(0));
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      try {
        WebViewClient existing = webView.getWebViewClient();
        if (existing != null && !(existing instanceof ShieldWebViewClient)) {
          webView.setWebViewClient(new ShieldWebViewClient(existing, webViewId));
        }
      } catch (Throwable ignored) {
      }
    }
  }

  public Map<String, Object> getStats(long webViewId) {
    Map<String, Object> out = new HashMap<>(4);
    AtomicInteger pageCounter = pageBlockedByWv.get(webViewId);
    out.put("pageBlocked", pageCounter != null ? pageCounter.get() : 0);
    out.put("totalBlocked", totalBlockedCount.get());
    out.put("shieldEnabled", shieldEnabled);
    return out;
  }

  public void resetStats() {
    totalBlockedCount.set(0L);
    for (AtomicInteger c : pageBlockedByWv.values()) {
      c.set(0);
    }
    prefs.edit().putLong(KEY_TOTAL_BLOCKED, 0L).apply();
  }

  public boolean isHostAllowlisted(String rawHost) {
    String cur = normalizeHost(rawHost);
    if (cur.isEmpty() || disabledHosts.isEmpty()) {
      return false;
    }
    while (true) {
      if (disabledHosts.contains(cur)) {
        return true;
      }
      int dot = cur.indexOf('.');
      if (dot < 0 || dot + 1 >= cur.length()) {
        break;
      }
      cur = cur.substring(dot + 1);
    }
    return false;
  }

  private static String normalizeHost(String raw) {
    if (raw == null) {
      return "";
    }
    String s = raw.trim().toLowerCase(Locale.US);
    if (s.startsWith("https://")) {
      s = s.substring(8);
    } else if (s.startsWith("http://")) {
      s = s.substring(7);
    }
    int slash = s.indexOf('/');
    if (slash >= 0) {
      s = s.substring(0, slash);
    }
    int colon = s.indexOf(':');
    if (colon >= 0) {
      s = s.substring(0, colon);
    }
    if (s.startsWith("www.") && s.length() > 4) {
      s = s.substring(4);
    }
    return s;
  }

  private boolean shouldBlockDomain(String requestHost, String pageHost) {
    if (requestHost == null || requestHost.isEmpty()) {
      return false;
    }
    String cur = requestHost.toLowerCase(Locale.US);
    // Never block same-site first-party resources so site logins/assets stay 100% intact.
    if (pageHost != null && !pageHost.isEmpty()) {
      if (cur.equals(pageHost) || cur.endsWith("." + pageHost)) {
        return false;
      }
    }
    final boolean checkStrict = this.strictMode;
    while (true) {
      if (STANDARD_AD_TRACKER_DOMAINS.contains(cur)
          || (checkStrict && STRICT_EXTRA_TRACKER_DOMAINS.contains(cur))) {
        return true;
      }
      int dot = cur.indexOf('.');
      if (dot < 0 || dot + 1 >= cur.length()) {
        break;
      }
      cur = cur.substring(dot + 1);
    }
    return false;
  }

  private WebResourceResponse interceptSubresource(long webViewId, WebResourceRequest request) {
    if (!this.shieldEnabled
        || !this.blockAdsAndTrackers
        || request == null
        || request.isForMainFrame()) {
      return null;
    }
    String pageHost = activeHostByWv.get(webViewId);
    if (pageHost != null && isHostAllowlisted(pageHost)) {
      return null;
    }
    Uri uri = request.getUrl();
    if (uri == null) {
      return null;
    }
    String reqHost = uri.getHost();
    if (!shouldBlockDomain(reqHost, pageHost)) {
      String path = uri.getPath();
      if (!this.strictMode || path == null) {
        return null;
      }
      String lowerPath = path.toLowerCase(Locale.US);
      if (!lowerPath.contains("/pagead/")
          && !lowerPath.contains("/adserver/")
          && !lowerPath.endsWith("/ads.js")
          && !lowerPath.endsWith("/prebid.js")) {
        return null;
      }
    }

    AtomicInteger pageCount = pageBlockedByWv.computeIfAbsent(webViewId, k -> new AtomicInteger(0));
    pageCount.incrementAndGet();
    long nextTotal = totalBlockedCount.incrementAndGet();
    if ((nextTotal & 7L) == 0L) {
      prefs.edit().putLong(KEY_TOTAL_BLOCKED, nextTotal).apply();
    }

    String path = uri.getPath() != null ? uri.getPath().toLowerCase(Locale.US) : "";
    String accept = "";
    Map<String, String> reqHeaders = request.getRequestHeaders();
    if (reqHeaders != null) {
      String a = reqHeaders.get("Accept");
      if (a == null) {
        a = reqHeaders.get("accept");
      }
      if (a != null) {
        accept = a.toLowerCase(Locale.US);
      }
    }

    Map<String, String> respHeaders = new HashMap<>(4);
    respHeaders.put("Access-Control-Allow-Origin", "*");
    respHeaders.put("Cache-Control", "no-store");

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
          respHeaders,
          new ByteArrayInputStream(TRANSPARENT_GIF));
    }
    if (path.endsWith(".css") || accept.startsWith("text/css")) {
      return new WebResourceResponse(
          "text/css",
          "utf-8",
          200,
          "OK",
          respHeaders,
          new ByteArrayInputStream(EMPTY_CSS));
    }
    if (path.endsWith(".js") || accept.contains("javascript") || accept.contains("ecmascript")) {
      return new WebResourceResponse(
          "application/javascript",
          "utf-8",
          200,
          "OK",
          respHeaders,
          new ByteArrayInputStream(EMPTY_JS));
    }
    return new WebResourceResponse(
        "text/plain",
        "utf-8",
        200,
        "OK",
        respHeaders,
        new ByteArrayInputStream(EMPTY_TEXT));
  }

  /**
   * Builds and caches a single zero-jank {@code DOCUMENT_START} bundle containing:
   * 1) Top safe-area inset for the floating zero-pull search bar, and
   * 2) Customizable Heaven Shield protections (respecting per-site allowlist).
   */
  public String getCompiledDocumentStartBundle() {
    String existing = cachedDocumentStartBundle;
    if (existing != null) {
      return existing;
    }

    StringBuilder sb = new StringBuilder(10240);
    sb.append("(function(){try{");
    sb.append("if(window.__hbShieldRuntimeV19)return;window.__hbShieldRuntimeV19=true;");

    // 1. Static top breathing space for the floating zero-pull top bar (never mutates on scroll!)
    sb.append(
        "function applyTopSafeSpace(){"
            + "if(window!==window.top)return;"
            + "if(document.getElementById('__hb_top_safe_css'))return;"
            + "var st=document.createElement('style');st.id='__hb_top_safe_css';"
            + "st.textContent='html:not(:fullscreen){padding-top:52px!important;scroll-padding-top:56px!important;box-sizing:border-box;}';"
            + "(document.head||document.documentElement).appendChild(st);"
            + "}"
            + "if(document.head||document.documentElement){applyTopSafeSpace();}"
            + "else{document.addEventListener('DOMContentLoaded',applyTopSafeSpace,{once:true});}");

    if (!this.shieldEnabled) {
      sb.append("}catch(_){}})();");
      String built = sb.toString();
      this.cachedDocumentStartBundle = built;
      return built;
    }

    // Serialize per-site allowlist for fast O(1) client-side check as well.
    sb.append("var allowSet={");
    boolean first = true;
    for (String h : this.disabledHosts) {
      if (!first) {
        sb.append(',');
      }
      first = false;
      sb.append('\'').append(escapeJsSingleQuote(h)).append("':1");
    }
    sb.append("};");
    sb.append(
        "var curHost=(location.hostname||'').toLowerCase().replace(/^www\\./,'');"
            + "function isSiteAllowed(h){"
            + "while(h){if(allowSet[h])return true;var d=h.indexOf('.');if(d<0)break;h=h.slice(d+1);}"
            + "return false;"
            + "}"
            + "if(isSiteAllowed(curHost))return;");

    // 2. Cosmetic Ad-Slot Collapsing CSS (when Ad & Tracker Blocking is enabled)
    if (this.blockAdsAndTrackers) {
      sb.append(
          "function injectAdCosmetics(){"
              + "if(document.getElementById('__hb_shield_ads_css'))return;"
              + "var s=document.createElement('style');s.id='__hb_shield_ads_css';"
              + "s.textContent='"
              + "ins.adsbygoogle,[id^=\"div-gpt-ad\"],[data-google-query-id],"
              + "iframe[src*=\"doubleclick.net\"],iframe[src*=\"googlesyndication.com\"],"
              + ".taboola-widget,.OUTBRAIN,[id^=\"taboola-\"],.ad-slot-banner"
              + "{display:none!important;height:0!important;min-height:0!important;pointer-events:none!important;}';"
              + "(document.head||document.documentElement).appendChild(s);"
              + "}"
              + "if(document.head||document.documentElement){injectAdCosmetics();}"
              + "else{document.addEventListener('DOMContentLoaded',injectAdCosmetics,{once:true});}");
    }

    // 3. Cookie & Annoyance Banner Blocker
    if (this.blockCookieBanners) {
      sb.append(
          "function injectCookieShield(){"
              + "if(document.getElementById('__hb_shield_cookie_css'))return;"
              + "var s=document.createElement('style');s.id='__hb_shield_cookie_css';"
              + "s.textContent='"
              + "#onetrust-consent-sdk,#CybotCookiebotDialog,#qc-cmp2-container,"
              + ".cc-window,.cc-banner,#cookie-law-info-bar,.fc-consent-root,"
              + "#sp_message_container,[id*=\"cookie-consent\"][role=\"dialog\"]"
              + "{display:none!important;visibility:hidden!important;pointer-events:none!important;}';"
              + "(document.head||document.documentElement).appendChild(s);"
              + "}"
              + "if(document.head||document.documentElement){injectCookieShield();}"
              + "else{document.addEventListener('DOMContentLoaded',injectCookieShield,{once:true});}");
    }

    // 4. Tracking URL Parameter Cleaner (utm_*, fbclid, gclid, msclkid, igshid, mc_eid, yclid)
    if (this.cleanTrackingUrls) {
      sb.append(
          "(function(){"
              + "var dropRx=/^(utm_[a-z0-9_]+|fbclid|gclid|dclid|msclkid|yclid|mc_eid|igshid|_hsenc|_hsmi|vero_id|mkt_tok)$/i;"
              + "function cleanHref(raw){"
              + "try{var u=new URL(raw,location.href);if(u.protocol!=='http:'&&u.protocol!=='https:')return null;"
              + "var dirty=false;var keys=[];u.searchParams.forEach(function(_,k){if(dropRx.test(k))keys.push(k);});"
              + "for(var i=0;i<keys.length;i++){u.searchParams.delete(keys[i]);dirty=true;}"
              + "return dirty?u.toString():null;}catch(_){return null;}"
              + "}"
              + "var cleanedSelf=cleanHref(location.href);"
              + "if(cleanedSelf&&window.history&&history.replaceState){try{history.replaceState(history.state,'',cleanedSelf);}catch(_){}}"
              + "document.addEventListener('click',function(ev){"
              + "var a=ev.target&&ev.target.closest?ev.target.closest('a[href]'):null;"
              + "if(!a)return;var c=cleanHref(a.href);if(c)a.href=c;"
              + "},{capture:true,passive:true});"
              + "})();");
    }

    // 5. Anti-Fingerprinting Protection
    if (this.antiFingerprinting) {
      sb.append(
          "(function(){"
              + "try{Object.defineProperty(navigator,'globalPrivacyControl',{get:function(){return true;},configurable:true});}catch(_){}"
              + "try{Object.defineProperty(navigator,'doNotTrack',{get:function(){return '1';},configurable:true});}catch(_){}"
              + "if(navigator.getBattery){try{navigator.getBattery=undefined;}catch(_){}}"
              + "try{if(navigator.connection){Object.defineProperty(navigator,'connection',{get:function(){return undefined;},configurable:true});}}catch(_){}");
      if (this.strictMode) {
        sb.append(
            "try{Object.defineProperty(navigator,'hardwareConcurrency',{get:function(){return 4;},configurable:true});}catch(_){}"
                + "try{Object.defineProperty(navigator,'deviceMemory',{get:function(){return 8;},configurable:true});}catch(_){}");
      }
      sb.append("})();");
    }

    // 6. Popup & Unrequested Redirect Guard
    if (this.blockPopupsAndRedirects) {
      sb.append(
          "(function(){"
              + "var lastTap=0;"
              + "var markTap=function(){lastTap=Date.now();};"
              + "window.addEventListener('pointerdown',markTap,{capture:true,passive:true});"
              + "window.addEventListener('touchend',markTap,{capture:true,passive:true});"
              + "window.addEventListener('keydown',markTap,{capture:true,passive:true});"
              + "var origOpen=window.open;"
              + "window.open=function(u){"
              + "if(Date.now()-lastTap>1800)return null;"
              + "return origOpen?origOpen.apply(window,arguments):null;"
              + "};"
              + "})();");
    }

    sb.append("}catch(_){}})();");
    String built = sb.toString();
    this.cachedDocumentStartBundle = built;
    return built;
  }

  private static String escapeJsSingleQuote(String raw) {
    StringBuilder out = new StringBuilder(raw.length() + 4);
    for (int i = 0; i < raw.length(); i++) {
      char c = raw.charAt(i);
      if (c == '\\' || c == '\'') {
        out.append('\\');
      }
      out.append(c);
    }
    return out.toString();
  }

  private final class ShieldWebViewClient extends WebViewClient {
    private final WebViewClient delegate;
    private final long webViewId;

    ShieldWebViewClient(WebViewClient delegate, long webViewId) {
      this.delegate = delegate;
      this.webViewId = webViewId;
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
      WebResourceResponse blocked = interceptSubresource(webViewId, request);
      if (blocked != null) {
        return blocked;
      }
      return delegate.shouldInterceptRequest(view, request);
    }

    @Override
    @SuppressWarnings("deprecation")
    public WebResourceResponse shouldInterceptRequest(WebView view, String url) {
      return delegate.shouldInterceptRequest(view, url);
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
      if (url != null) {
        updateWebViewHost(webViewId, url);
      }
      delegate.onPageStarted(view, url, favicon);
    }

    @Override
    public void onPageFinished(WebView view, String url) {
      delegate.onPageFinished(view, url);
    }

    @Override
    public void onLoadResource(WebView view, String url) {
      delegate.onLoadResource(view, url);
    }

    @Override
    public void onPageCommitVisible(WebView view, String url) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        delegate.onPageCommitVisible(view, url);
      }
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
    public void onFormResubmission(WebView view, Message dontResend, Message resend) {
      delegate.onFormResubmission(view, dontResend, resend);
    }

    @Override
    public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
      delegate.doUpdateVisitedHistory(view, url, isReload);
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
    public void onReceivedLoginRequest(
        WebView view, String realm, String account, String args) {
      delegate.onReceivedLoginRequest(view, realm, account, args);
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
