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
import java.util.ArrayList;
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
 * Native Heaven Shield Engine — zero-jank O(1) subresource ad/tracker/social/malware filter and
 * customizable {@code DOCUMENT_START} privacy runtime.
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
                  "cleverpush.com")));

  private static final Set<String> FACEBOOK_EMBED_DOMAINS =
      Collections.unmodifiableSet(
          new HashSet<>(
              Arrays.asList(
                  "connect.facebook.net",
                  "graph.facebook.com",
                  "an.facebook.com",
                  "pixel.facebook.com")));

  private static final Set<String> TWITTER_EMBED_DOMAINS =
      Collections.unmodifiableSet(
          new HashSet<>(
              Arrays.asList(
                  "platform.twitter.com",
                  "syndication.twitter.com",
                  "publish.twitter.com",
                  "platform.x.com",
                  "syndication.x.com")));

  private static final Set<String> LINKEDIN_EMBED_DOMAINS =
      Collections.unmodifiableSet(
          new HashSet<>(
              Arrays.asList(
                  "platform.linkedin.com", "snap.licdn.com", "px.ads.linkedin.com")));

  private static final Set<String> REGIONAL_INDIA_DOMAINS =
      Collections.unmodifiableSet(
          new HashSet<>(
              Arrays.asList(
                  "colombiaonline.com",
                  "clmbtech.com",
                  "izooto.com",
                  "vcommission.com",
                  "vizury.com",
                  "moengage.com",
                  "clevertap-prod.com",
                  "wzrkt.com",
                  "webengage.com")));

  private static final Set<String> MOBILE_NOTIF_ANNOYANCE_DOMAINS =
      Collections.unmodifiableSet(
          new HashSet<>(
              Arrays.asList(
                  "onesignal.com",
                  "pushengage.com",
                  "pushwoosh.com",
                  "gravitec.net",
                  "sendpulse.com",
                  "subscribers.com",
                  "webpushr.com",
                  "pushnami.com")));

  private static final Set<String> ENHANCED_THREAT_DOMAINS =
      Collections.unmodifiableSet(
          new HashSet<>(
              Arrays.asList(
                  "coinhive.com",
                  "crypto-loot.com",
                  "jsecoin.com",
                  "webminepool.com",
                  "authedmine.com",
                  "minero.cc")));

  private static final byte[] EMPTY_JS = "/*hb*/".getBytes(StandardCharsets.UTF_8);
  private static final byte[] EMPTY_CSS = "/*hb*/".getBytes(StandardCharsets.UTF_8);
  private static final byte[] EMPTY_TEXT = new byte[0];
  private static final byte[] TRANSPARENT_GIF =
      new byte[] {
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, (byte) 0x80, 0x00, 0x00, 0x00,
        0x00, 0x00, (byte) 0xFF, (byte) 0xFF, (byte) 0xFF, 0x21, (byte) 0xF9, 0x04, 0x01, 0x00,
        0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02,
        0x44, 0x01, 0x00, 0x3B
      };

  public static final class HostCssRule {
    public final String host; // empty string = global rule
    public final String selector;

    HostCssRule(String host, String selector) {
      this.host = host;
      this.selector = selector;
    }
  }

  private final SharedPreferences prefs;
  private final AtomicLong totalBlockedCount = new AtomicLong(0L);
  private final AtomicLong unpersistedDelta = new AtomicLong(0L);
  private final ConcurrentHashMap<Long, AtomicInteger> pageBlockedByWv = new ConcurrentHashMap<>();
  private final ConcurrentHashMap<Long, String> activeHostByWv = new ConcurrentHashMap<>();
  private final Set<Long> wrappedWebViewIds = ConcurrentHashMap.newKeySet();

  private volatile boolean shieldEnabled = true;
  private volatile boolean strictMode = false;
  private volatile boolean blockAdsAndTrackers = true;
  private volatile boolean blockCookieBanners = true;
  private volatile boolean cleanTrackingUrls = true;
  private volatile boolean antiFingerprinting = true;
  private volatile boolean blockPopups = true;

  // Step 20: Extended Heaven Shield & Privacy protections
  private volatile boolean autoRedirectAmp = true;
  private volatile boolean preventLanguageFingerprinting = true;
  private volatile boolean allowFacebookEmbeds = true;
  private volatile boolean allowTwitterEmbeds = true;
  private volatile boolean allowLinkedinEmbeds = false;
  private volatile String safeBrowsingMode = "standard"; // enhanced | standard | off
  private volatile String webrtcPolicy = "default"; // default | public_only | public_and_private | disable_non_proxied_udp
  private volatile boolean allowPaymentMethodQuery = true;
  private volatile boolean strictJsSecurity = false;
  private volatile boolean blockSwitchToAppNotices = true;
  private volatile boolean sendDoNotTrack = false;
  private volatile boolean filterFanboyAnnoyances = true;
  private volatile boolean filterMobileNotifications = true;
  private volatile boolean filterAntiAdblockKiller = true;
  private volatile boolean filterRegionalIndia = false;
  private volatile boolean filterRegionalGlobal = false;

  private volatile Set<String> disabledHosts = Collections.emptySet();
  private volatile Set<String> customBlockedDomains = Collections.emptySet();
  private volatile List<HostCssRule> customCssRules = Collections.emptyList();
  private volatile String cachedDocumentStartBundle = null;

  public HeavenShieldEngine(Context context) {
    this.prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    this.totalBlockedCount.set(Math.max(0L, this.prefs.getLong(KEY_TOTAL_BLOCKED, 0L)));
  }

  public void updateConfiguration(
      Boolean enabled,
      Boolean strict,
      Boolean blockAds,
      Boolean cookieBanners,
      Boolean cleanUrls,
      Boolean antiFp,
      Boolean popups,
      List<String> allowlistedHosts) {
    if (enabled != null) {
      this.shieldEnabled = enabled;
    }
    if (strict != null) {
      this.strictMode = strict;
    }
    if (blockAds != null) {
      this.blockAdsAndTrackers = blockAds;
    }
    if (cookieBanners != null) {
      this.blockCookieBanners = cookieBanners;
    }
    if (cleanUrls != null) {
      this.cleanTrackingUrls = cleanUrls;
    }
    if (antiFp != null) {
      this.antiFingerprinting = antiFp;
    }
    if (popups != null) {
      this.blockPopups = popups;
    }
    if (allowlistedHosts != null) {
      Set<String> next = new HashSet<>();
      for (String raw : allowlistedHosts) {
        String h = normalizeHost(raw);
        if (!h.isEmpty()) {
          next.add(h);
        }
      }
      this.disabledHosts = Collections.unmodifiableSet(next);
    }
    this.cachedDocumentStartBundle = null;
  }

  public void updateExtendedPrivacyConfiguration(
      Boolean autoAmp,
      Boolean langFp,
      Boolean fbEmbeds,
      Boolean twEmbeds,
      Boolean liEmbeds,
      String safeBrowsing,
      String webrtc,
      Boolean paymentQuery,
      Boolean strictJs,
      Boolean switchToApp,
      Boolean dnt,
      Boolean fanboyAnnoyances,
      Boolean mobileNotifs,
      Boolean antiAdblock,
      Boolean regionalIndia,
      Boolean regionalGlobal,
      List<String> rawCustomRules) {
    if (autoAmp != null) this.autoRedirectAmp = autoAmp;
    if (langFp != null) this.preventLanguageFingerprinting = langFp;
    if (fbEmbeds != null) this.allowFacebookEmbeds = fbEmbeds;
    if (twEmbeds != null) this.allowTwitterEmbeds = twEmbeds;
    if (liEmbeds != null) this.allowLinkedinEmbeds = liEmbeds;
    if (safeBrowsing != null && !safeBrowsing.trim().isEmpty()) {
      this.safeBrowsingMode = safeBrowsing.trim().toLowerCase(Locale.US);
    }
    if (webrtc != null && !webrtc.trim().isEmpty()) {
      this.webrtcPolicy = webrtc.trim().toLowerCase(Locale.US);
    }
    if (paymentQuery != null) this.allowPaymentMethodQuery = paymentQuery;
    if (strictJs != null) this.strictJsSecurity = strictJs;
    if (switchToApp != null) this.blockSwitchToAppNotices = switchToApp;
    if (dnt != null) this.sendDoNotTrack = dnt;
    if (fanboyAnnoyances != null) this.filterFanboyAnnoyances = fanboyAnnoyances;
    if (mobileNotifs != null) this.filterMobileNotifications = mobileNotifs;
    if (antiAdblock != null) this.filterAntiAdblockKiller = antiAdblock;
    if (regionalIndia != null) this.filterRegionalIndia = regionalIndia;
    if (regionalGlobal != null) this.filterRegionalGlobal = regionalGlobal;

    if (rawCustomRules != null) {
      Set<String> doms = new HashSet<>();
      List<HostCssRule> css = new ArrayList<>();
      for (String rawLine : rawCustomRules) {
        if (rawLine == null) continue;
        String line = rawLine.trim();
        if (line.isEmpty() || line.startsWith("!") || line.startsWith("[")) {
          continue;
        }
        int cssIdx = line.indexOf("##");
        if (cssIdx >= 0) {
          String hostPart = normalizeHost(line.substring(0, cssIdx));
          String selPart = line.substring(cssIdx + 2).trim();
          if (!selPart.isEmpty() && selPart.length() <= 240 && !selPart.contains("{")) {
            css.add(new HostCssRule(hostPart, selPart));
          }
          continue;
        }
        String ruleDom = line;
        if (ruleDom.startsWith("||")) {
          ruleDom = ruleDom.substring(2);
        }
        int caret = ruleDom.indexOf('^');
        if (caret >= 0) {
          ruleDom = ruleDom.substring(0, caret);
        }
        String normDom = normalizeHost(ruleDom);
        if (!normDom.isEmpty() && normDom.contains(".")) {
          doms.add(normDom);
        }
      }
      this.customBlockedDomains = Collections.unmodifiableSet(doms);
      this.customCssRules = Collections.unmodifiableList(css);
    }
    this.cachedDocumentStartBundle = null;
  }

  public void updateWebViewHost(long webViewId, String rawHostOrUrl) {
    String clean = normalizeHost(rawHostOrUrl);
    if (!clean.isEmpty()) {
      String prev = activeHostByWv.put(webViewId, clean);
      if (!clean.equals(prev)) {
        pageBlockedByWv.put(webViewId, new AtomicInteger(0));
      }
    }
  }

  public void resetPageBlocked(long webViewId) {
    pageBlockedByWv.put(webViewId, new AtomicInteger(0));
  }

  public Map<String, Object> getStats(long webViewId) {
    Map<String, Object> out = new HashMap<>(4);
    AtomicInteger pageCounter = webViewId >= 0 ? pageBlockedByWv.get(webViewId) : null;
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
    } else if (s.startsWith("m.") && s.length() > 2) {
      s = s.substring(2);
    }
    return s;
  }

  public void attachClient(WebView webView, long webViewId, String initialHost) {
    if (initialHost != null && !initialHost.trim().isEmpty()) {
      updateWebViewHost(webViewId, initialHost);
    }
    attachClientWrapperIfNeeded(webView, webViewId);
  }

  public void attachClientWrapperIfNeeded(WebView webView, long webViewId) {
    if (webView == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return;
    }
    if (!wrappedWebViewIds.add(webViewId)) {
      return;
    }
    try {
      WebViewClient existing = webView.getWebViewClient();
      if (existing != null && !(existing instanceof ShieldWebViewClient)) {
        webView.setWebViewClient(new ShieldWebViewClient(existing, webViewId));
      }
    } catch (Throwable ignored) {
      wrappedWebViewIds.remove(webViewId);
    }
  }

  boolean shouldBlockDomain(String reqHost, String pageHost) {
    String cur = normalizeHost(reqHost);
    if (cur.isEmpty()) {
      return false;
    }
    String normPage = normalizeHost(pageHost);

    // Enhanced Safe Browsing cryptominer/threat block applies regardless of 1P/3P
    if (!"off".equals(this.safeBrowsingMode)) {
      String threatCheck = cur;
      while (true) {
        if (ENHANCED_THREAT_DOMAINS.contains(threatCheck)) {
          return true;
        }
        int dot = threatCheck.indexOf('.');
        if (dot < 0 || dot + 1 >= threatCheck.length()) break;
        threatCheck = threatCheck.substring(dot + 1);
      }
    }

    // Never block same-domain first-party subresources
    if (!normPage.isEmpty() && (cur.equals(normPage) || cur.endsWith("." + normPage))) {
      return false;
    }

    // Social Media Blocking (only on third-party pages!)
    if (!this.allowFacebookEmbeds
        && !normPage.endsWith("facebook.com")
        && !normPage.endsWith("fb.com")
        && !normPage.endsWith("instagram.com")
        && matchesDomainSet(cur, FACEBOOK_EMBED_DOMAINS)) {
      return true;
    }
    if (!this.allowTwitterEmbeds
        && !normPage.endsWith("twitter.com")
        && !normPage.endsWith("x.com")
        && matchesDomainSet(cur, TWITTER_EMBED_DOMAINS)) {
      return true;
    }
    if (!this.allowLinkedinEmbeds
        && !normPage.endsWith("linkedin.com")
        && matchesDomainSet(cur, LINKEDIN_EMBED_DOMAINS)) {
      return true;
    }

    // Custom filter list domains & Content Filtering lists
    if (!this.customBlockedDomains.isEmpty() && matchesDomainSet(cur, this.customBlockedDomains)) {
      return true;
    }
    if (this.filterMobileNotifications && matchesDomainSet(cur, MOBILE_NOTIF_ANNOYANCE_DOMAINS)) {
      return true;
    }
    if (this.filterRegionalIndia && matchesDomainSet(cur, REGIONAL_INDIA_DOMAINS)) {
      return true;
    }

    if (!this.blockAdsAndTrackers) {
      return false;
    }

    final boolean checkStrict = this.strictMode || this.filterRegionalGlobal;
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

  private static boolean matchesDomainSet(String host, Set<String> set) {
    String cur = host;
    while (true) {
      if (set.contains(cur)) {
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
    if (!this.shieldEnabled || request == null || request.isForMainFrame()) {
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
    String path = uri.getPath();

    // Third-party Facebook / Twitter embed iframe paths
    boolean blocked = shouldBlockDomain(reqHost, pageHost);
    if (!blocked && reqHost != null && path != null) {
      String lowerHost = reqHost.toLowerCase(Locale.US);
      String lowerPath = path.toLowerCase(Locale.US);
      if (!this.allowFacebookEmbeds
          && (lowerHost.endsWith("facebook.com"))
          && (lowerPath.startsWith("/plugins/") || lowerPath.contains("/plugins/post.php"))) {
        blocked = true;
      } else if (this.blockAdsAndTrackers && this.strictMode) {
        if (lowerPath.contains("/pagead/")
            || lowerPath.contains("/adserver/")
            || lowerPath.endsWith("/ads.js")
            || lowerPath.endsWith("/prebid.js")) {
          blocked = true;
        }
      }
    }

    if (!blocked) {
      return null;
    }

    AtomicInteger pageCount = pageBlockedByWv.computeIfAbsent(webViewId, k -> new AtomicInteger(0));
    pageCount.incrementAndGet();
    long nextTotal = totalBlockedCount.incrementAndGet();
    if (unpersistedDelta.incrementAndGet() >= 15L) {
      unpersistedDelta.set(0L);
      prefs.edit().putLong(KEY_TOTAL_BLOCKED, nextTotal).apply();
    }

    String safePath = path != null ? path.toLowerCase(Locale.US) : "";
    Map<String, String> reqHeaders = request.getRequestHeaders();
    String accept = "";
    if (reqHeaders != null) {
      String rawAccept = reqHeaders.get("Accept");
      if (rawAccept == null) {
        rawAccept = reqHeaders.get("accept");
      }
      if (rawAccept != null) {
        accept = rawAccept.toLowerCase(Locale.US);
      }
    }

    Map<String, String> respHeaders = new HashMap<>(4);
    respHeaders.put("Access-Control-Allow-Origin", "*");
    respHeaders.put("Cache-Control", "no-store");

    if (safePath.endsWith(".png")
        || safePath.endsWith(".gif")
        || safePath.endsWith(".jpg")
        || safePath.endsWith(".jpeg")
        || safePath.endsWith(".webp")
        || accept.startsWith("image/")) {
      return new WebResourceResponse(
          "image/gif",
          null,
          200,
          "OK",
          respHeaders,
          new ByteArrayInputStream(TRANSPARENT_GIF));
    }
    if (safePath.endsWith(".css") || accept.startsWith("text/css")) {
      return new WebResourceResponse(
          "text/css", "utf-8", 200, "OK", respHeaders, new ByteArrayInputStream(EMPTY_CSS));
    }
    if (safePath.endsWith(".js")
        || accept.contains("javascript")
        || accept.contains("ecmascript")) {
      return new WebResourceResponse(
          "application/javascript",
          "utf-8",
          200,
          "OK",
          respHeaders,
          new ByteArrayInputStream(EMPTY_JS));
    }
    return new WebResourceResponse(
        "text/plain", "utf-8", 200, "OK", respHeaders, new ByteArrayInputStream(EMPTY_TEXT));
  }

  /**
   * Builds and caches a single zero-jank {@code DOCUMENT_START} bundle containing:
   * 1) Top safe-area inset for the floating zero-pull search bar, and
   * 2) All customizable Heaven Shield & Privacy protections (respecting per-site allowlist).
   */
  public String getCompiledDocumentStartBundle() {
    String existing = cachedDocumentStartBundle;
    if (existing != null) {
      return existing;
    }

    StringBuilder sb = new StringBuilder(16384);
    sb.append("(function(){try{");
    sb.append("if(window.__hbShieldRuntimeV20)return;window.__hbShieldRuntimeV20=true;");

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

    // 2. Interactive Element Blocker helper (invoked on-demand from Heaven Shield Quick Sheet)
    sb.append(
        "window.__hbStartElementPicker=function(){"
            + "if(window.__hbPickerActive)return;"
            + "window.__hbPickerActive=true;"
            + "window.__hbPickedSelector='';"
            + "var badge=document.createElement('div');"
            + "badge.id='__hb_picker_hud';"
            + "badge.style.cssText='position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#0B162C;color:#fff;padding:10px 16px;border-radius:999px;font:600 13px system-ui,sans-serif;z-index:2147483647;box-shadow:0 6px 24px rgba(0,0,0,.45);border:1.5px solid #10B981;';"
            + "badge.textContent='Tap any annoying element to block it (or tap here to cancel)';"
            + "(document.body||document.documentElement).appendChild(badge);"
            + "var cleanup=function(){window.__hbPickerActive=false;if(badge.parentNode)badge.parentNode.removeChild(badge);document.removeEventListener('click',onTap,true);};"
            + "var buildSel=function(el){"
            + "if(!el||el===document.body||el===document.documentElement)return '';"
            + "if(el.id&&/^[a-zA-Z][\\w-]*$/.test(el.id))return '#'+el.id;"
            + "var tag=el.tagName.toLowerCase();"
            + "var cls=(typeof el.className==='string')?el.className.trim().split(/\\s+/).filter(function(c){return /^[a-zA-Z][\\w-]{2,40}$/.test(c);}).slice(0,2):[];"
            + "if(cls.length)return tag+'.'+cls.join('.');"
            + "return tag;"
            + "};"
            + "var onTap=function(ev){"
            + "ev.preventDefault();ev.stopPropagation();"
            + "if(ev.target===badge){window.__hbPickedSelector='__CANCEL__';cleanup();return;}"
            + "var sel=buildSel(ev.target);"
            + "if(sel){try{ev.target.style.setProperty('display','none','important');}catch(_){}}"
            + "window.__hbPickedSelector=sel||'__CANCEL__';"
            + "cleanup();"
            + "};"
            + "document.addEventListener('click',onTap,true);"
            + "};");

    // Global WebRTC IP Handling Policy (applies even if site ad-shield is paused)
    if ("disable_non_proxied_udp".equals(this.webrtcPolicy)
        || "public_only".equals(this.webrtcPolicy)) {
      final boolean forceRelay = "disable_non_proxied_udp".equals(this.webrtcPolicy);
      sb.append(
          "(function(){"
              + "var OrigPC=window.RTCPeerConnection||window.webkitRTCPeerConnection;"
              + "if(!OrigPC)return;"
              + "var WrappedPC=function(cfg,constraints){"
              + "var c=cfg?Object.assign({},cfg):{};"
              + (forceRelay ? "c.iceTransportPolicy='relay';" : "")
              + "var pc=new OrigPC(c,constraints);"
              + (!forceRelay
                  ? "var origAdd=pc.addIceCandidate;"
                      + "if(origAdd){pc.addIceCandidate=function(cand){"
                      + "if(cand&&cand.candidate&&/(192\\.168\\.|10\\.|172\\.(1[6-9]|2\\d|3[01])\\.|\\.local)/i.test(cand.candidate)){return Promise.resolve();}"
                      + "return origAdd.apply(this,arguments);};}"
                  : "")
              + "return pc;"
              + "};"
              + "WrappedPC.prototype=OrigPC.prototype;"
              + "try{window.RTCPeerConnection=WrappedPC;window.webkitRTCPeerConnection=WrappedPC;}catch(_){}"
              + "})();");
    }

    // Payment method query protection
    if (!this.allowPaymentMethodQuery) {
      sb.append(
          "if(window.PaymentRequest&&PaymentRequest.prototype){"
              + "PaymentRequest.prototype.canMakePayment=function(){return Promise.resolve(false);};"
              + "PaymentRequest.prototype.hasEnrolledInstrument=function(){return Promise.resolve(false);};"
              + "}");
    }

    // Do Not Track & Global Privacy Control DOM flags
    if (this.sendDoNotTrack) {
      sb.append(
          "try{Object.defineProperty(navigator,'doNotTrack',{get:function(){return '1';},configurable:true});"
              + "Object.defineProperty(navigator,'globalPrivacyControl',{get:function(){return true;},configurable:true});}catch(_){}");
    }

    // Strict JavaScript security (disable WebAssembly & SharedArrayBuffer JIT attack surfaces on HTTP/untrusted)
    if (this.strictJsSecurity) {
      sb.append(
          "try{if(location.protocol==='http:'||window.top===window){"
              + "Object.defineProperty(window,'SharedArrayBuffer',{get:function(){return undefined;},configurable:true});"
              + "Object.defineProperty(window,'WebAssembly',{get:function(){return undefined;},configurable:true});"
              + "}}catch(_){}");
    }

    // Block 'Switch to App' notices
    if (this.blockSwitchToAppNotices) {
      sb.append(
          "function hideSwitchAppPrompts(){"
              + "if(document.getElementById('__hb_no_app_nag'))return;"
              + "var s=document.createElement('style');s.id='__hb_no_app_nag';"
              + "s.textContent='.smartbanner,#smartbanner,[id*=\"branch-banner\"],.branch-journeys-top,[class*=\"SmartBanner\"],[data-testid=\"xpromo-app-selector\"],shreddit-experience-tree,[class*=\"OpenInAppBanner\"]{display:none!important;}';"
              + "(document.head||document.documentElement).appendChild(s);"
              + "var metas=document.querySelectorAll('meta[name=\"apple-itunes-app\"],meta[name=\"google-play-app\"]');"
              + "for(var i=0;i<metas.length;i++){if(metas[i].parentNode)metas[i].parentNode.removeChild(metas[i]);}"
              + "}"
              + "if(document.head||document.documentElement){hideSwitchAppPrompts();}"
              + "else{document.addEventListener('DOMContentLoaded',hideSwitchAppPrompts,{once:true});}");
    }

    if (!this.shieldEnabled) {
      sb.append("}catch(_){}})();");
      String built = sb.toString();
      this.cachedDocumentStartBundle = built;
      return built;
    }

    // Per-site allowlist check inside JS
    sb.append("var host=(location.hostname||'').toLowerCase().replace(/^(www\\.|m\\.)/,'');");
    if (!this.disabledHosts.isEmpty()) {
      sb.append("var allow=[");
      boolean first = true;
      for (String h : this.disabledHosts) {
        if (!first) sb.append(',');
        first = false;
        sb.append('\'').append(escapeJsSingleQuote(h)).append('\'');
      }
      sb.append("];");
      sb.append(
          "for(var i=0;i<allow.length;i++){"
              + "var ah=allow[i];"
              + "if(host===ah||host.endsWith('.'+ah))return;"
              + "}");
    }

    // Auto-redirect AMP pages (<html amp> canonical link redirect)
    if (this.autoRedirectAmp) {
      sb.append(
          "document.addEventListener('DOMContentLoaded',function(){try{"
              + "var root=document.documentElement;"
              + "if(!root)return;"
              + "var isAmp=root.hasAttribute('amp')||root.hasAttribute('\\u26a1')||/\\/amp(\\/|$)/i.test(location.pathname);"
              + "if(!isAmp)return;"
              + "var canon=document.querySelector('link[rel=\"canonical\"][href]');"
              + "if(canon&&canon.href&&canon.href!==location.href&&!/(\\/amp(\\/|$)|cdn\\.ampproject\\.org)/i.test(canon.href)){"
              + "location.replace(canon.href);"
              + "}"
              + "}catch(_){}},{once:true});");
    }

    // Anti-Adblock Killer defuser
    if (this.filterAntiAdblockKiller && this.blockAdsAndTrackers) {
      sb.append(
          "try{window.canRunAds=true;window.isAdBlockActive=false;window.google_ad_status=1;}catch(_){}");
    }

    // Cosmetic Ad, Cookie Banner, Fanboy Annoyances & Custom CSS Element Hiding
    if (this.blockAdsAndTrackers || this.blockCookieBanners || !this.customCssRules.isEmpty()) {
      StringBuilder css = new StringBuilder(2048);
      if (this.blockAdsAndTrackers) {
        css.append(
            "ins.adsbygoogle,[id^='div-gpt-ad'],[data-ad-slot],[data-google-query-id],"
                + "iframe[src*='doubleclick.net'],iframe[src*='googlesyndication.com'],"
                + ".taboola-widget,.OUTBRAIN,[id*='taboola-']{display:none!important;}");
      }
      if (this.blockCookieBanners) {
        css.append(
            "#onetrust-consent-sdk,#onetrust-banner-sdk,.onetrust-pc-dark-filter,"
                + "#CybotCookiebotDialog,#CybotCookiebotDialogBodyUnderlay,"
                + ".qc-cmp2-container,#sp_message_container,.fc-consent-root,"
                + "#didomi-host,.cc-window,.cc-banner,[id*='cookie-banner'],"
                + "[class*='cookie-consent-banner']{display:none!important;}"
                + "html,body{overflow:auto!important;}");
      }
      if (this.filterFanboyAnnoyances) {
        css.append(
            ".newsletter-popup,.subscribe-modal,[class*='newsletter-overlay'],"
                + "[id*='onesignal-slidedown']{display:none!important;}");
      }
      for (HostCssRule r : this.customCssRules) {
        if (r.host.isEmpty()) {
          css.append(r.selector).append("{display:none!important;}");
        }
      }
      if (css.length() > 0) {
        sb.append(
            "function applyShieldCss(){"
                + "if(document.getElementById('__hb_shield_css'))return;"
                + "var s=document.createElement('style');s.id='__hb_shield_css';"
                + "s.textContent='")
            .append(escapeJsSingleQuote(css.toString()))
            .append(
                "';(document.head||document.documentElement).appendChild(s);"
                    + "}"
                    + "if(document.head||document.documentElement){applyShieldCss();}"
                    + "else{document.addEventListener('DOMContentLoaded',applyShieldCss,{once:true});}");
      }
      // Host-specific custom CSS rules (including per-site blocked elements)
      boolean hasHostSpecific = false;
      for (HostCssRule r : this.customCssRules) {
        if (!r.host.isEmpty()) {
          hasHostSpecific = true;
          break;
        }
      }
      if (hasHostSpecific) {
        sb.append("(function(){var hCss='';");
        for (HostCssRule r : this.customCssRules) {
          if (!r.host.isEmpty()) {
            sb.append("if(host==='")
                .append(escapeJsSingleQuote(r.host))
                .append("'||host.endsWith('.")
                .append(escapeJsSingleQuote(r.host))
                .append("')){hCss+='")
                .append(escapeJsSingleQuote(r.selector))
                .append("{display:none!important;}';}");
          }
        }
        sb.append(
            "if(hCss){var injectHost=function(){var hs=document.createElement('style');hs.textContent=hCss;(document.head||document.documentElement).appendChild(hs);};"
                + "if(document.head||document.documentElement)injectHost();else document.addEventListener('DOMContentLoaded',injectHost,{once:true});}"
                + "})();");
      }
    }

    // URL Tracking Parameter Cleaner inside History API (SPA navigations)
    if (this.cleanTrackingUrls) {
      sb.append(
          "(function(){"
              + "var rx=/^(utm_[a-z0-9_]+|fbclid|gclid|dclid|msclkid|twclid|mc_cid|mc_eid|igshid|_hsenc|_hsmi|yclid|vero_id|mkt_tok|si)$/i;"
              + "function cleanHref(u){try{"
              + "var p=new URL(u,location.href);var ch=false;"
              + "Array.from(p.searchParams.keys()).forEach(function(k){if(rx.test(k)){p.searchParams.delete(k);ch=true;}});"
              + "return ch?p.toString():u;}catch(_){return u;}}"
              + "var cleaned=cleanHref(location.href);"
              + "if(cleaned!==location.href&&history.replaceState){history.replaceState(history.state,'',cleaned);}"
              + "})();");
    }

    // Anti-Fingerprinting Guard
    if (this.antiFingerprinting) {
      sb.append(
          "(function(){"
              + "try{Object.defineProperty(navigator,'deviceMemory',{get:function(){return 8;},configurable:true});}catch(_){}"
              + "try{Object.defineProperty(navigator,'hardwareConcurrency',{get:function(){return 8;},configurable:true});}catch(_){}"
              + "if(navigator.getBattery){navigator.getBattery=function(){return Promise.reject(new Error('Blocked by Heaven Shield'));};}"
              + "var origToDataURL=HTMLCanvasElement.prototype.toDataURL;"
              + "HTMLCanvasElement.prototype.toDataURL=function(){"
              + "try{var ctx=this.getContext('2d');"
              + "if(ctx&&this.width>0&&this.height>0&&this.width<=512&&this.height<=512){"
              + "var img=ctx.getImageData(0,0,1,1);img.data[0]=img.data[0]^1;ctx.putImageData(img,0,0);"
              + "}}catch(_){}"
              + "return origToDataURL.apply(this,arguments);"
              + "};"
              + "})();");
    }

    // Prevent Fingerprinting via Language Settings
    if (this.preventLanguageFingerprinting) {
      sb.append(
          "(function(){try{"
              + "var baseLang=(navigator.language||'en-US').split('-')[0];"
              + "var norm=baseLang==='en'?'en-US':baseLang;"
              + "Object.defineProperty(navigator,'language',{get:function(){return norm;},configurable:true});"
              + "Object.defineProperty(navigator,'languages',{get:function(){return Object.freeze([norm]);},configurable:true});"
              + "}catch(_){}})();");
    }

    // Unrequested Popup & Tab-Under Guard
    if (this.blockPopups) {
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
      } else if (c == '\n' || c == '\r') {
        out.append(' ');
      } else {
        out.append(c);
      }
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
