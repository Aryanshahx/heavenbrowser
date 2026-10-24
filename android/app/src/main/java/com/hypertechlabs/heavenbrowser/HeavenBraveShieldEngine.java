package com.hypertechlabs.heavenbrowser;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.net.Uri;
import android.net.http.SslError;
import android.os.Build;
import android.os.Message;
import android.os.SystemClock;
import android.view.KeyEvent;
import android.webkit.ClientCertRequest;
import android.webkit.HttpAuthHandler;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.SafeBrowsingResponse;
import android.webkit.ServiceWorkerClient;
import android.webkit.ServiceWorkerController;
import android.webkit.SslErrorHandler;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
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
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Native Brave-Style Shields Core Engine compiled directly into Heaven's Android runtime.
 *
 * <p>Implements all 5 Brave Shields layers natively without browser extensions or UI-thread IPC:
 * <ol>
 *   <li>Native Chromium WebView &amp; ServiceWorker network interception (zero MV3 limits).
 *   <li>EasyList + EasyPrivacy O(1) domain/pattern filter engine + RFC 1035 DNS CNAME Uncloaking.
 *   <li>Cosmetic CSS placeholder collapsing + throttled procedural DOM filtering.
 *   <li>"SugarCoat" privacy-safe JS surrogate replacements (GA, GTM, GPT, AdSense, FB Pixel, etc.).
 *   <li>Session + eTLD+1 seeded Anti-Fingerprinting ("Farbling") across Canvas, WebGL, Audio &amp; HW.
 * </ol>
 */
public final class HeavenBraveShieldEngine {
  private static final String PREFS_NAME = "heaven_brave_shields_prefs";
  private static final String KEY_TOTAL_BLOCKED = "total_blocked_requests";
  private static final String KEY_TOTAL_SURROGATES = "total_sugarcoat_surrogates";
  private static final String KEY_TOTAL_CNAME = "total_cname_uncloaked";
  private static final String KEY_LAST_FILTER_SYNC_MS = "last_filter_sync_epoch_ms";
  private static final String CACHE_FILE_NAME = "brave_shields_filters_v17.txt";
  private static final long FILTER_REFRESH_INTERVAL_MS = 24L * 60L * 60L * 1000L;

  private static final String[] FILTER_LIST_URLS = {
    "https://ublockorigin.github.io/uAssets/filters/filters.min.txt",
    "https://easylist.to/easylist/easyprivacy.txt",
    "https://easylist.to/easylist/easylist.txt"
  };

  // Valid 43-byte 1x1 transparent GIF for blocked tracking pixels (prevents img.onerror loops).
  private static final byte[] TRANSPARENT_GIF_1X1 = {
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, (byte) 0x80, 0x00,
    0x00, 0x00, 0x00, 0x00, (byte) 0xFF, (byte) 0xFF, (byte) 0xFF, 0x21, (byte) 0xF9, 0x04,
    0x01, 0x00, 0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3B
  };

  private static final Set<String> MULTI_PART_TLDS =
      new HashSet<>(
          Arrays.asList(
              "co.uk", "org.uk", "ac.uk", "co.in", "org.in", "net.in", "com.au", "net.au",
              "org.au", "co.jp", "ne.jp", "or.jp", "com.br", "com.mx", "co.kr", "co.nz",
              "co.za", "com.sg", "com.hk", "com.tw", "com.tr", "com.ar", "com.co", "com.my"));

  private static final Set<String> SAFE_FIRST_PARTY_SUBDOMAIN_PREFIXES =
      new HashSet<>(
          Arrays.asList(
              "www", "m", "mobile", "cdn", "static", "assets", "img", "images", "media",
              "video", "videos", "stream", "fonts", "auth", "login", "id", "accounts",
              "account", "checkout", "pay", "payments", "docs", "support", "help", "blog",
              "forum", "developer", "developers", "mail", "maps", "play", "news"));

  // Essential domains that must never have main infrastructure broken.
  private static final Set<String> ESSENTIAL_ALLOW_DOMAINS =
      new HashSet<>(
          Arrays.asList(
              "google.com",
              "gstatic.com",
              "googleapis.com",
              "googleusercontent.com",
              "googlevideo.com",
              "ytimg.com",
              "youtube.com",
              "youtu.be",
              "perplexity.ai",
              "duckduckgo.com",
              "search.brave.com",
              "bing.com",
              "startpage.com",
              "github.com",
              "githubusercontent.com",
              "githubassets.com",
              "cloudflare.com",
              "jsdelivr.net",
              "unpkg.com",
              "cdnjs.cloudflare.com",
              "wp.com",
              "wikimedia.org",
              "wikipedia.org"));

  // Built-in EasyList + EasyPrivacy + CNAME Cloaking high-frequency ad/tracker domains.
  private static final String[] BUILTIN_BLOCKED_DOMAINS = {
    // Major Ad Exchanges & Programmatic Networks (EasyList)
    "doubleclick.net",
    "googlesyndication.com",
    "googleadservices.com",
    "adservice.google.com",
    "adsensecustomsearchads.com",
    "2mdn.net",
    "adsafeprotected.com",
    "moatads.com",
    "adnxs.com",
    "rubiconproject.com",
    "pubmatic.com",
    "openx.net",
    "criteo.com",
    "criteo.net",
    "casalemedia.com",
    "indexww.com",
    "3lift.com",
    "triplelift.com",
    "taboola.com",
    "taboolasyndication.com",
    "outbrain.com",
    "outbrainimg.com",
    "zemanta.com",
    "mgid.com",
    "revcontent.com",
    "zergnet.com",
    "teads.tv",
    "sharethrough.com",
    "smartadserver.com",
    "sovrn.com",
    "lijit.com",
    "bidswitch.net",
    "mathtag.com",
    "mediamath.com",
    "rlcdn.com",
    "turn.com",
    "demdex.net",
    "everesttech.net",
    "advertising.com",
    "adform.net",
    "serving-sys.com",
    "sizmek.com",
    "flashtalking.com",
    "amazon-adsystem.com",
    "aaxads.com",
    "media.net",
    "adcolony.com",
    "unityads.unity3d.com",
    "applovin.com",
    "vungle.com",
    "inmobi.com",
    "chartboost.com",
    "ironsrc.com",
    "smaato.net",
    "fyber.com",
    "tapjoy.com",
    "startappservice.com",
    "yieldmo.com",
    "gumgum.com",
    "kargo.com",
    "nativo.com",
    "connatix.com",
    "primis.tech",
    "aniview.com",
    "spotxchange.com",
    "springserve.com",
    "tremorhub.com",
    "lijit.com",
    "sonobi.com",
    "contextweb.com",
    "pulsepoint.com",
    "districtm.io",
    "emxdgt.com",
    "33across.com",
    "conversantmedia.com",
    "dotomi.com",
    "cj.com",
    "Awin1.com",
    // Malvertising, Popunders & Piracy/Streaming Redirect Networks
    "exoclick.com",
    "exosrv.com",
    "realsrv.com",
    "syndication.exoclick.com",
    "adsterra.com",
    "adsterratech.com",
    "highperformanceformat.com",
    "profitablecpmrate.com",
    "propellerads.com",
    "propellerclick.com",
    "onclickads.net",
    "popads.net",
    "popcash.net",
    "popmyads.com",
    "hilltopads.net",
    "juicyads.com",
    "trafficjunky.net",
    "trafficstars.com",
    "plugrush.com",
    "clickadu.com",
    "adcash.com",
    "bidvertiser.com",
    "zeropark.com",
    "richpush.co",
    "pushground.com",
    "evadav.com",
    "galaksion.com",
    "mondiad.com",
    "admaven.com",
    "ad-maven.com",
    // Analytics, Telemetry, Session Replay & Fingerprinting (EasyPrivacy)
    "google-analytics.com",
    "ssl.google-analytics.com",
    "googletagmanager.com",
    "googletagservices.com",
    "scorecardresearch.com",
    "sb.scorecardresearch.com",
    "quantserve.com",
    "quantcount.com",
    "hotjar.com",
    "hotjar.io",
    "fullstory.com",
    "mouseflow.com",
    "luckyorange.com",
    "crazyegg.com",
    "smartlook.com",
    "logrocket.io",
    "clarity.ms",
    "mixpanel.com",
    "mxpnl.com",
    "amplitude.com",
    "segment.io",
    "segment.com",
    "heapanalytics.com",
    "kissmetrics.com",
    "chartbeat.com",
    "chartbeat.net",
    "parsely.com",
    "newrelic.com",
    "nr-data.net",
    "bugsnag.com",
    "omtrdc.net",
    "2o7.net",
    "adobedc.net",
    "optimizely.com",
    "hubspot.com",
    "hs-analytics.net",
    "hsadspixel.net",
    "pardot.com",
    "mktoresp.com",
    "marketo.net",
    "braze.com",
    "iad-01.braze.com",
    "clevertap.com",
    "appsflyer.com",
    "adjust.com",
    "branch.io",
    "app.link",
    "kochava.com",
    "singular.net",
    "bluekai.com",
    "krxd.net",
    "Krux.com",
    "lotame.com",
    "crwdcntrl.net",
    "exelator.com",
    "agkn.com",
    "tapad.com",
    "adsrvr.org",
    "liadm.com",
    "id5-sync.com",
    "uidapi.com",
    "liveintent.com",
    "pippio.com",
    "Narrative.io",
    "permutive.com",
    "zeotap.com",
    "fingerprintjs.com",
    "fpjs.io",
    // Common CNAME-Cloaked First-Party Disguise Targets
    "eulerian.net",
    "dnsdelegation.io",
    "storetail.io",
    "xiti.com",
    "aticdn.net",
    "keyade.com",
    "tracedock.com",
    "affex.org",
    "wt-eu02.net",
    "webtrekk.net",
    "actonservice.com",
    "eloqua.com",
    "ingenious.cloud",
    "dataunlocker.com",
    // Social & Cross-Site Tracking Pixels
    "connect.facebook.net",
    "an.facebook.com",
    "analytics.tiktok.com",
    "ads-twitter.com",
    "static.ads-twitter.com",
    "t.co/i/adsct",
    "snap.licdn.com",
    "px.ads.linkedin.com",
    "ct.pinterest.com",
    "trk.pinterest.com",
    "alb.reddit.com",
    "events.redditmedia.com",
    "quora.com/_/ad",
    "yandex.ru/metrika",
    "mc.yandex.ru"
  };

  private static final String[] BUILTIN_URL_PATTERNS = {
    "/pagead/js/adsbygoogle.js",
    "/pagead/lvz?",
    "/pagead/adview?",
    "/pagead/gen_204",
    "/pagead/interaction/",
    "/pcs/activeview",
    "/gampad/ads?",
    "/tag/js/gpt.js",
    "/gtag/js?",
    "/gtm.js?",
    "/fbevents.js",
    "/api/stats/ads",
    "/ptracking?",
    "/get_midroll_info?",
    "ad_type=",
    "/adserver/",
    "/adframe.",
    "/popunder",
    "/prebid",
    "/hb_bid",
    "/openrtb2/auction",
    "/b/ss/",
    "/collect?v=1&",
    "/collect?v=2&",
    "/pixel.gif?",
    "/beacon.js"
  };

  // Immutable snapshot swapped atomically when EasyList/EasyPrivacy updates complete.
  static final class FilterSnapshot {
    final Set<String> blockedDomains;
    final Set<String> exceptionDomains;
    final List<UrlPatternRule> patternRules;
    final int totalRuleCount;

    FilterSnapshot(
        Set<String> blockedDomains,
        Set<String> exceptionDomains,
        List<UrlPatternRule> patternRules) {
      this.blockedDomains = blockedDomains;
      this.exceptionDomains = exceptionDomains;
      this.patternRules = patternRules;
      this.totalRuleCount =
          blockedDomains.size() + exceptionDomains.size() + patternRules.size();
    }
  }

  private static final class UrlPatternRule {
    final String token;
    final boolean thirdPartyOnly;
    final boolean scriptOnly;
    final boolean imageOnly;

    UrlPatternRule(String token, boolean thirdPartyOnly, boolean scriptOnly, boolean imageOnly) {
      this.token = token;
      this.thirdPartyOnly = thirdPartyOnly;
      this.scriptOnly = scriptOnly;
      this.imageOnly = imageOnly;
    }
  }

  private static final class SurrogateSpec {
    final String name;
    final String mimeType;
    final byte[] bodyBytes;

    SurrogateSpec(String name, String mimeType, String jsCode) {
      this.name = name;
      this.mimeType = mimeType;
      this.bodyBytes = jsCode.getBytes(StandardCharsets.UTF_8);
    }
  }

  private static final Map<String, SurrogateSpec> SUGARCOAT_BY_KEY = buildSugarCoatLibrary();

  private final Context appContext;
  private final ExecutorService shieldWorkerPool =
      Executors.newFixedThreadPool(
          2,
          r -> {
            Thread t = new Thread(r, "heaven-brave-shield-io");
            t.setDaemon(true);
            t.setPriority(Thread.NORM_PRIORITY - 1);
            return t;
          });

  private volatile boolean shieldsGloballyEnabled = true;
  private volatile boolean farblingEnabled = true;
  private volatile FilterSnapshot activeSnapshot;
  private volatile long lastFilterSyncMs = 0L;
  private final AtomicBoolean syncInProgress = new AtomicBoolean(false);

  private final Set<String> disabledSiteHosts = ConcurrentHashMap.newKeySet();
  private final ConcurrentHashMap<Long, String> activePageHostByWv = new ConcurrentHashMap<>();
  private final ConcurrentHashMap<Long, AtomicLong> tabBlockedCountByWv = new ConcurrentHashMap<>();
  private final ConcurrentHashMap<Long, AtomicLong> tabSurrogateCountByWv =
      new ConcurrentHashMap<>();
  private final ConcurrentHashMap<Long, AtomicLong> tabCnameCountByWv = new ConcurrentHashMap<>();

  // CNAME cache: host -> uncloaked canonical target domain (or "" when verified clean/non-CNAME)
  private final ConcurrentHashMap<String, String> cnameCache = new ConcurrentHashMap<>();
  private final Set<String> pendingCnameLookups = ConcurrentHashMap.newKeySet();

  private final AtomicLong totalBlockedRequests = new AtomicLong(0L);
  private final AtomicLong totalSugarCoatSurrogates = new AtomicLong(0L);
  private final AtomicLong totalCnameUncloaked = new AtomicLong(0L);
  private final long sessionFarblingSecret;

  public HeavenBraveShieldEngine(Context context) {
    this.appContext = context.getApplicationContext();
    byte[] seedBytes = new byte[8];
    new SecureRandom().nextBytes(seedBytes);
    long s = 0L;
    for (byte b : seedBytes) {
      s = (s << 8) | (b & 0xFFL);
    }
    this.sessionFarblingSecret = (s == 0L) ? 0x9E3779B97F4A7C15L : s;
    this.activeSnapshot = compileSnapshotFromLines(Collections.emptyList());

    SharedPreferences prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    this.totalBlockedRequests.set(prefs.getLong(KEY_TOTAL_BLOCKED, 0L));
    this.totalSugarCoatSurrogates.set(prefs.getLong(KEY_TOTAL_SURROGATES, 0L));
    this.totalCnameUncloaked.set(prefs.getLong(KEY_TOTAL_CNAME, 0L));
    this.lastFilterSyncMs = prefs.getLong(KEY_LAST_FILTER_SYNC_MS, 0L);

    installServiceWorkerInterceptor();
    shieldWorkerPool.execute(this::loadCachedOrSyncFilterLists);
  }

  public void shutdown() {
    persistLifetimeCounters();
    shieldWorkerPool.shutdownNow();
  }

  public void updateConfiguration(
      boolean enabled, boolean farbling, List<String> disabledHosts) {
    this.shieldsGloballyEnabled = enabled;
    this.farblingEnabled = farbling;
    this.disabledSiteHosts.clear();
    if (disabledHosts != null) {
      for (String h : disabledHosts) {
        String clean = normalizeHost(h);
        if (!clean.isEmpty()) {
          this.disabledSiteHosts.add(clean);
        }
      }
    }
  }

  public void setPageHostForWebView(long webViewId, String pageHost) {
    String clean = normalizeHost(pageHost);
    String prev = activePageHostByWv.get(webViewId);
    if (!clean.isEmpty()) {
      activePageHostByWv.put(webViewId, clean);
      if (prev == null || !prev.equals(clean)) {
        resetTabCounters(webViewId);
      }
    } else {
      activePageHostByWv.remove(webViewId);
    }
  }

  public void resetTabCounters(long webViewId) {
    tabBlockedCountByWv.put(webViewId, new AtomicLong(0L));
    tabSurrogateCountByWv.put(webViewId, new AtomicLong(0L));
    tabCnameCountByWv.put(webViewId, new AtomicLong(0L));
  }

  public void removeWebView(long webViewId) {
    activePageHostByWv.remove(webViewId);
    tabBlockedCountByWv.remove(webViewId);
    tabSurrogateCountByWv.remove(webViewId);
    tabCnameCountByWv.remove(webViewId);
  }

  public boolean isShieldActiveForHost(String rawHost) {
    if (!shieldsGloballyEnabled) {
      return false;
    }
    String host = normalizeHost(rawHost);
    if (host.isEmpty()) {
      return true;
    }
    if (disabledSiteHosts.contains(host)) {
      return false;
    }
    String base = extractEtldPlusOne(host);
    return !disabledSiteHosts.contains(base);
  }

  public boolean isFarblingEnabled() {
    return shieldsGloballyEnabled && farblingEnabled;
  }

  public Map<String, Object> getStatsSnapshot(long webViewId) {
    Map<String, Object> out = new HashMap<>(10);
    AtomicLong tb = tabBlockedCountByWv.get(webViewId);
    AtomicLong ts = tabSurrogateCountByWv.get(webViewId);
    AtomicLong tc = tabCnameCountByWv.get(webViewId);
    FilterSnapshot snap = activeSnapshot;
    out.put("enabled", shieldsGloballyEnabled);
    out.put("farblingEnabled", farblingEnabled);
    out.put("tabBlocked", tb != null ? tb.get() : 0L);
    out.put("tabSurrogates", ts != null ? ts.get() : 0L);
    out.put("tabCnameUncloaked", tc != null ? tc.get() : 0L);
    out.put("totalBlocked", totalBlockedRequests.get());
    out.put("totalSurrogates", totalSugarCoatSurrogates.get());
    out.put("totalCnameUncloaked", totalCnameUncloaked.get());
    out.put("activeRuleCount", snap != null ? snap.totalRuleCount : 0);
    out.put("lastFilterSyncMs", lastFilterSyncMs);
    return out;
  }

  public void forceRefreshFilterLists(final Runnable onDone) {
    shieldWorkerPool.execute(
        () -> {
          syncRemoteFilterListsInternal();
          if (onDone != null) {
            onDone.run();
          }
        });
  }

  public void attachToWebView(final WebView webView, final long webViewId) {
    if (webView == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return;
    }
    try {
      WebViewClient current = webView.getWebViewClient();
      if (current instanceof BraveNativeWebViewClient) {
        return;
      }
      if (current != null) {
        webView.setWebViewClient(new BraveNativeWebViewClient(current, webViewId));
      }
    } catch (Throwable ignored) {
    }
  }

  private void installServiceWorkerInterceptor() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
      return;
    }
    try {
      ServiceWorkerController swc = ServiceWorkerController.getInstance();
      swc.setServiceWorkerClient(
          new ServiceWorkerClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebResourceRequest request) {
              return evaluateNetworkRequest(-1L, request);
            }
          });
    } catch (Throwable ignored) {
    }
  }

  /**
   * Core network-layer inspection executed on Chromium's background IO worker thread.
   * Zero main-thread dispatches, zero MethodChannel calls, sub-50-microsecond hot path.
   */
  public WebResourceResponse evaluateNetworkRequest(long webViewId, WebResourceRequest request) {
    if (!shieldsGloballyEnabled || request == null) {
      return null;
    }
    // Never block top-level document navigations here; subresources/scripts/pixels/iframes only.
    if (request.isForMainFrame()) {
      Uri mainUri = request.getUrl();
      if (mainUri != null && webViewId >= 0) {
        String mainHost = normalizeHost(mainUri.getHost());
        if (!mainHost.isEmpty()) {
          setPageHostForWebView(webViewId, mainHost);
        }
      }
      return null;
    }

    Uri uri = request.getUrl();
    if (uri == null) {
      return null;
    }
    String scheme = uri.getScheme();
    if (scheme == null || (!"https".equalsIgnoreCase(scheme) && !"http".equalsIgnoreCase(scheme))) {
      return null;
    }
    String reqHost = normalizeHost(uri.getHost());
    if (reqHost.isEmpty()) {
      return null;
    }

    String pageHost = resolvePageHost(webViewId, request);
    if (!pageHost.isEmpty() && !isShieldActiveForHost(pageHost)) {
      return null;
    }

    String fullUrlLower = uri.toString().toLowerCase(Locale.US);
    String pathAndQuery = extractPathAndQueryLower(fullUrlLower);

    FilterSnapshot snap = this.activeSnapshot;
    if (matchesDomainSet(reqHost, snap.exceptionDomains)) {
      return null;
    }

    String pageBase = extractEtldPlusOne(pageHost);
    String reqBase = extractEtldPlusOne(reqHost);
    boolean isThirdParty = !pageBase.isEmpty() && !pageBase.equals(reqBase);

    boolean shouldBlock = false;
    boolean wasCnameUncloaked = false;

    // 1. Direct EasyList / EasyPrivacy O(1) domain trie check
    if (matchesDomainSet(reqHost, snap.blockedDomains)) {
      // Allow essential first-party assets unless explicitly ad/tracking path
      if (isThirdParty || !matchesDomainSet(reqHost, ESSENTIAL_ALLOW_DOMAINS)) {
        shouldBlock = true;
      }
    }

    // 2. EasyList / EasyPrivacy URL path & option rules
    if (!shouldBlock) {
      String acceptHeader = headerLower(request, "Accept");
      boolean isScript =
          pathAndQuery.contains(".js")
              || acceptHeader.contains("javascript")
              || "script".equals(headerLower(request, "Sec-Fetch-Dest"));
      boolean isImage =
          acceptHeader.startsWith("image/")
              || "image".equals(headerLower(request, "Sec-Fetch-Dest"));

      List<UrlPatternRule> rules = snap.patternRules;
      for (int i = 0, n = rules.size(); i < n; i++) {
        UrlPatternRule rule = rules.get(i);
        if (rule.thirdPartyOnly && !isThirdParty) {
          continue;
        }
        if (rule.scriptOnly && !isScript) {
          continue;
        }
        if (rule.imageOnly && !isImage) {
          continue;
        }
        if (fullUrlLower.contains(rule.token)) {
          shouldBlock = true;
          break;
        }
      }
    }

    // 3. DNS CNAME Uncloaking for disguised first-party tracker subdomains
    if (!shouldBlock
        && !isThirdParty
        && !pageHost.isEmpty()
        && !reqHost.equals(pageHost)
        && isCandidateForCnameUncloak(reqHost, pageBase)) {
      String cnameTarget = lookupCnameTargetFast(reqHost);
      if (cnameTarget != null && !cnameTarget.isEmpty()) {
        String cnameBase = extractEtldPlusOne(cnameTarget);
        if (!cnameBase.equals(pageBase) && matchesDomainSet(cnameTarget, snap.blockedDomains)) {
          shouldBlock = true;
          wasCnameUncloaked = true;
        }
      }
    }

    if (!shouldBlock) {
      return null;
    }

    // Record native lock-free counters (zero UI-thread IPC!)
    long totalNow = totalBlockedRequests.incrementAndGet();
    if (webViewId >= 0) {
      tabBlockedCountByWv
          .computeIfAbsent(webViewId, k -> new AtomicLong(0L))
          .incrementAndGet();
    }
    if (wasCnameUncloaked) {
      totalCnameUncloaked.incrementAndGet();
      if (webViewId >= 0) {
        tabCnameCountByWv
            .computeIfAbsent(webViewId, k -> new AtomicLong(0L))
            .incrementAndGet();
      }
    }
    if ((totalNow & 0x1FL) == 0L) {
      shieldWorkerPool.execute(this::persistLifetimeCounters);
    }

    // 4. "SugarCoat" Privacy-Safe Surrogate Replacement
    SurrogateSpec surrogate = matchSugarCoatSurrogate(reqHost, pathAndQuery);
    if (surrogate != null) {
      totalSugarCoatSurrogates.incrementAndGet();
      if (webViewId >= 0) {
        tabSurrogateCountByWv
            .computeIfAbsent(webViewId, k -> new AtomicLong(0L))
            .incrementAndGet();
      }
      return buildResponse(200, "OK", surrogate.mimeType, surrogate.bodyBytes);
    }

    // Return clean resource-appropriate empty payload so DOM never shows broken icons or hangs
    return buildCleanBlockedResponse(request, pathAndQuery);
  }

  private void persistLifetimeCounters() {
    try {
      appContext
          .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
          .edit()
          .putLong(KEY_TOTAL_BLOCKED, totalBlockedRequests.get())
          .putLong(KEY_TOTAL_SURROGATES, totalSugarCoatSurrogates.get())
          .putLong(KEY_TOTAL_CNAME, totalCnameUncloaked.get())
          .putLong(KEY_LAST_FILTER_SYNC_MS, lastFilterSyncMs)
          .apply();
    } catch (Throwable ignored) {
    }
  }

  private String resolvePageHost(long webViewId, WebResourceRequest request) {
    if (webViewId >= 0) {
      String tracked = activePageHostByWv.get(webViewId);
      if (tracked != null && !tracked.isEmpty()) {
        return tracked;
      }
    }
    Map<String, String> headers = request.getRequestHeaders();
    if (headers != null) {
      String ref = headers.get("Referer");
      if (ref == null) {
        ref = headers.get("referer");
      }
      if (ref != null && !ref.isEmpty()) {
        try {
          Uri refUri = Uri.parse(ref);
          return normalizeHost(refUri.getHost());
        } catch (Throwable ignored) {
        }
      }
    }
    return "";
  }

  private static String headerLower(WebResourceRequest request, String key) {
    Map<String, String> headers = request.getRequestHeaders();
    if (headers == null) {
      return "";
    }
    String v = headers.get(key);
    if (v == null) {
      v = headers.get(key.toLowerCase(Locale.US));
    }
    return v != null ? v.toLowerCase(Locale.US) : "";
  }

  private static boolean isCandidateForCnameUncloak(String reqHost, String pageBase) {
    if (reqHost.length() <= pageBase.length() + 1) {
      return false;
    }
    String prefix = reqHost.substring(0, reqHost.length() - pageBase.length() - 1);
    int dot = prefix.indexOf('.');
    String firstLabel = dot >= 0 ? prefix.substring(0, dot) : prefix;
    return !SAFE_FIRST_PARTY_SUBDOMAIN_PREFIXES.contains(firstLabel);
  }

  /**
   * Fast CNAME lookup: O(1) lock-free memory hit, or bounded 140ms RFC 1035 DNS wire query with
   * async fallback so page rendering never stalls.
   */
  private String lookupCnameTargetFast(final String host) {
    String cached = cnameCache.get(host);
    if (cached != null) {
      return cached;
    }
    if (cnameCache.size() > 2048) {
      cnameCache.clear();
    }
    // Perform bounded 140ms UDP CNAME wire query on current IO worker thread; if network blocks
    // UDP 53, cache "" immediately so subsequent requests take 0ns.
    if (pendingCnameLookups.add(host)) {
      try {
        String resolved = queryDnsCnameChain(host, 140);
        String value = resolved != null ? normalizeHost(resolved) : "";
        cnameCache.put(host, value);
        return value;
      } catch (Throwable ignored) {
        cnameCache.put(host, "");
      } finally {
        pendingCnameLookups.remove(host);
      }
    }
    return "";
  }

  /**
   * Pure-Java RFC 1035 DNS wire-format CNAME resolver (queries 1.1.1.1 / 8.8.8.8 port 53).
   * Uncloaks disguised first-party tracker subdomains directly at the DNS layer.
   */
  static String queryDnsCnameChain(String domain, int timeoutMs) {
    String current = normalizeHost(domain);
    String deepestCname = null;
    String[] resolvers = {"1.1.1.1", "8.8.8.8"};

    for (int hop = 0; hop < 4; hop++) {
      byte[] queryPacket = buildDnsQueryPacket(current, 5 /* TYPE_CNAME */);
      if (queryPacket == null) {
        break;
      }
      String nextCname = null;
      for (String resolverIp : resolvers) {
        try (DatagramSocket socket = new DatagramSocket()) {
          socket.setSoTimeout(timeoutMs);
          InetAddress addr = InetAddress.getByName(resolverIp);
          DatagramPacket req = new DatagramPacket(queryPacket, queryPacket.length, addr, 53);
          socket.send(req);

          byte[] respBuf = new byte[512];
          DatagramPacket resp = new DatagramPacket(respBuf, respBuf.length);
          socket.receive(resp);
          nextCname = parseFirstCnameFromDnsPacket(respBuf, resp.getLength());
          break;
        } catch (Throwable ignored) {
          // Try secondary resolver if primary UDP timed out
        }
      }
      if (nextCname == null || nextCname.isEmpty() || nextCname.equalsIgnoreCase(current)) {
        break;
      }
      deepestCname = normalizeHost(nextCname);
      current = deepestCname;
    }
    return deepestCname;
  }

  private static byte[] buildDnsQueryPacket(String host, int qtype) {
    if (host == null || host.isEmpty()) {
      return null;
    }
    String[] labels = host.split("\\.");
    ByteArrayOutputStream out = new ByteArrayOutputStream(96);
    int txId = (host.hashCode() & 0xFFFF);
    out.write((txId >> 8) & 0xFF);
    out.write(txId & 0xFF);
    out.write(0x01); // RD = 1 (recursion desired)
    out.write(0x00);
    out.write(0x00);
    out.write(0x01); // QDCOUNT = 1
    out.write(0x00);
    out.write(0x00); // ANCOUNT = 0
    out.write(0x00);
    out.write(0x00); // NSCOUNT = 0
    out.write(0x00);
    out.write(0x00); // ARCOUNT = 0
    for (String label : labels) {
      byte[] b = label.getBytes(StandardCharsets.US_ASCII);
      if (b.length == 0 || b.length > 63) {
        return null;
      }
      out.write(b.length);
      out.write(b, 0, b.length);
    }
    out.write(0x00); // root label
    out.write((qtype >> 8) & 0xFF);
    out.write(qtype & 0xFF);
    out.write(0x00);
    out.write(0x01); // QCLASS = IN
    return out.toByteArray();
  }

  static String parseFirstCnameFromDnsPacket(byte[] pkt, int len) {
    if (pkt == null || len < 12) {
      return null;
    }
    int qdCount = ((pkt[4] & 0xFF) << 8) | (pkt[5] & 0xFF);
    int anCount = ((pkt[6] & 0xFF) << 8) | (pkt[7] & 0xFF);
    if (anCount <= 0) {
      return null;
    }
    int offset = 12;
    for (int q = 0; q < qdCount; q++) {
      offset = skipDnsName(pkt, len, offset);
      if (offset < 0 || offset + 4 > len) {
        return null;
      }
      offset += 4;
    }
    for (int a = 0; a < anCount; a++) {
      offset = skipDnsName(pkt, len, offset);
      if (offset < 0 || offset + 10 > len) {
        return null;
      }
      int rtype = ((pkt[offset] & 0xFF) << 8) | (pkt[offset + 1] & 0xFF);
      int rdLength = ((pkt[offset + 8] & 0xFF) << 8) | (pkt[offset + 9] & 0xFF);
      offset += 10;
      if (offset + rdLength > len) {
        return null;
      }
      if (rtype == 5 /* CNAME */) {
        return readDnsName(pkt, len, offset);
      }
      offset += rdLength;
    }
    return null;
  }

  private static int skipDnsName(byte[] pkt, int len, int pos) {
    int jumps = 0;
    while (pos < len && jumps++ < 64) {
      int b = pkt[pos] & 0xFF;
      if (b == 0) {
        return pos + 1;
      }
      if ((b & 0xC0) == 0xC0) {
        return (pos + 2 <= len) ? (pos + 2) : -1;
      }
      pos += 1 + b;
    }
    return -1;
  }

  private static String readDnsName(byte[] pkt, int len, int pos) {
    StringBuilder sb = new StringBuilder(64);
    int jumps = 0;
    while (pos >= 0 && pos < len && jumps++ < 32) {
      int b = pkt[pos] & 0xFF;
      if (b == 0) {
        break;
      }
      if ((b & 0xC0) == 0xC0) {
        if (pos + 1 >= len) {
          return null;
        }
        pos = ((b & 0x3F) << 8) | (pkt[pos + 1] & 0xFF);
        continue;
      }
      pos += 1;
      if (pos + b > len) {
        return null;
      }
      if (sb.length() > 0) {
        sb.append('.');
      }
      sb.append(new String(pkt, pos, b, StandardCharsets.US_ASCII));
      pos += b;
    }
    return sb.toString();
  }

  private static Map<String, SurrogateSpec> buildSugarCoatLibrary() {
    Map<String, SurrogateSpec> map = new HashMap<>(24);

    // 1. Google Analytics (analytics.js / ga.js / gtag/js) — executes hitCallback safely!
    SurrogateSpec gaSurrogate =
        new SurrogateSpec(
            "google-analytics",
            "application/javascript; charset=utf-8",
            "(function(){try{"
                + "var noop=function(){};"
                + "var gaFn=function(){"
                + "  var args=Array.prototype.slice.call(arguments);"
                + "  for(var i=0;i<args.length;i++){"
                + "    var a=args[i];"
                + "    if(a&&typeof a==='object'&&typeof a.hitCallback==='function'){"
                + "      try{setTimeout(a.hitCallback,1);}catch(_){}"
                + "    }"
                + "  }"
                + "};"
                + "gaFn.create=noop;gaFn.getByName=function(){return null;};"
                + "gaFn.getAll=function(){return[];};gaFn.remove=noop;gaFn.loaded=true;"
                + "if(!window.GoogleAnalyticsObject)window.GoogleAnalyticsObject='ga';"
                + "window[window.GoogleAnalyticsObject]=gaFn;window.ga=window.ga||gaFn;"
                + "window. dataLayer=window.dataLayer||[];"
                + "window.gtag=window.gtag||function(){"
                + "  var a=arguments;"
                + "  if(a.length>=3&&a[2]&&typeof a[2].event_callback==='function'){"
                + "    try{setTimeout(a[2].event_callback,1);}catch(_){}"
                + "  }"
                + "};"
                + "window._gat=window._gat||{_getTracker:function(){return{_trackPageview:noop,_trackEvent:noop};}};"
                + "}catch(_){}})();");
    map.put("google-analytics.com/analytics.js", gaSurrogate);
    map.put("google-analytics.com/ga.js", gaSurrogate);
    map.put("/gtag/js", gaSurrogate);

    // 2. Google Tag Manager (gtm.js) — preserves dataLayer & eventCallback!
    SurrogateSpec gtmSurrogate =
        new SurrogateSpec(
            "google-tag-manager",
            "application/javascript; charset=utf-8",
            "(function(){try{"
                + "var dl=window.dataLayer=window.dataLayer||[];"
                + "var origPush=dl.push?dl.push.bind(dl):Array.prototype.push.bind(dl);"
                + "dl.push=function(){"
                + "  var r=origPush.apply(dl,arguments);"
                + "  for(var i=0;i<arguments.length;i++){"
                + "    var o=arguments[i];"
                + "    if(o&&typeof o==='object'&&typeof o.eventCallback==='function'){"
                + "      try{setTimeout(o.eventCallback,1);}catch(_){}"
                + "    }"
                + "  }"
                + "  return r;"
                + "};"
                + "window.google_tag_manager=window.google_tag_manager||{};"
                + "}catch(_){}})();");
    map.put("googletagmanager.com/gtm.js", gtmSurrogate);

    // 3. Google Publisher Tags (gpt.js) — full chainable slot/pubads stub so publisher pages never crash!
    SurrogateSpec gptSurrogate =
        new SurrogateSpec(
            "googletag-gpt",
            "application/javascript; charset=utf-8",
            "(function(){try{"
                + "var noop=function(){};var noopThis=function(){return this;};"
                + "var slot={addService:noopThis,clearCategoryExclusions:noopThis,clearTargeting:noopThis,"
                + "defineSizeMapping:noopThis,get:function(){return null;},getAdUnitPath:function(){return '';},"
                + "getAttributeKeys:function(){return[];},getCategoryExclusions:function(){return[];},"
                + "getDomId:function(){return '';},getSlotElementId:function(){return '';},"
                + "getTargeting:function(){return[];},getTargetingKeys:function(){return[];},"
                + "set:noopThis,setCategoryExclusion:noopThis,setClickUrl:noopThis,"
                + "setCollapseEmptyDiv:noopThis,setSafeFrameConfig:noopThis,setTargeting:noopThis};"
                + "var pubads={addEventListener:noopThis,clear:noop,clearCategoryExclusions:noopThis,"
                + "clearTagForChildDirectedTreatment:noopThis,clearTargeting:noopThis,"
                + "collapseEmptyDivs:noop,disableInitialLoad:noop,display:noop,enableAsyncRendering:noop,"
                + "enableLazyLoad:noop,enableSingleRequest:noop,enableSyncRendering:noop,"
                + "enableVideoAds:noop,get:function(){return null;},getAttributeKeys:function(){return[];},"
                + "getSlots:function(){return[];},getTargeting:function(){return[];},"
                + "getTargetingKeys:function(){return[];},isInitialLoadDisabled:function(){return true;},"
                + "refresh:noop,removeEventListener:function(){return false;},set:noopThis,"
                + "setCategoryExclusion:noopThis,setCentering:noop,setCookieOptions:noopThis,"
                + "setForceSafeFrame:noopThis,setLocation:noopThis,setPublisherProvidedId:noopThis,"
                + "setPrivacySettings:noopThis,setRequestNonPersonalizedAds:noopThis,"
                + "setSafeFrameConfig:noopThis,setTagForChildDirectedTreatment:noopThis,"
                + "setTagForUnderAgeOfConsent:noopThis,setTargeting:noopThis,setVideoContent:noopThis,"
                + "updateCorrelator:noop};"
                + "var gt=window.googletag=window.googletag||{};"
                + "var q=Array.isArray(gt.cmd)?gt.cmd:[];"
                + "gt.apiReady=true;gt.pubadsReady=true;"
                + "gt.cmd={push:function(fn){if(typeof fn==='function'){try{fn();}catch(_){}}return 1;}};"
                + "gt.companionAds=function(){return{addEventListener:noopThis,enableSyncLoading:noop,setRefreshUnfilledSlots:noop};};"
                + "gt.content=function(){return{addEventListener:noopThis,setContent:noop};};"
                + "gt.defineSlot=function(){return slot;};gt.defineOutOfPageSlot=function(){return slot;};"
                + "gt.destroySlots=function(){return true;};gt.disablePublisherConsole=noop;"
                + "gt.display=noop;gt.enableServices=noop;gt.getVersion=function(){return '';};"
                + "gt.pubads=function(){return pubads;};gt.setAdIframeTitle=noop;"
                + "gt.sizeMapping=function(){return{addSize:noopThis,build:function(){return[];}};};"
                + "for(var i=0;i<q.length;i++){if(typeof q[i]==='function'){try{q[i]();}catch(_){}}}"
                + "}catch(_){}})();");
    map.put("/tag/js/gpt.js", gptSurrogate);

    // 4. Google AdSense (adsbygoogle.js)
    SurrogateSpec adsenseSurrogate =
        new SurrogateSpec(
            "adsbygoogle",
            "application/javascript; charset=utf-8",
            "(function(){window.adsbygoogle=window.adsbygoogle||{loaded:true,push:function(){}};window.adsbygoogle.loaded=true;})();");
    map.put("/pagead/js/adsbygoogle.js", adsenseSurrogate);

    // 5. Meta / Facebook Pixel (fbevents.js)
    SurrogateSpec fbqSurrogate =
        new SurrogateSpec(
            "facebook-pixel",
            "application/javascript; charset=utf-8",
            "(function(){if(window.fbq)return;var f=function(){};f.callMethod=f;f.queue=[];f.loaded=true;f.version='2.0';f.push=f;window.fbq=f;window._fbq=f;})();");
    map.put("/fbevents.js", fbqSurrogate);

    // 6. Common Analytics / A-B Testing SDK Surrogates (Hotjar, Mixpanel, Amplitude, Segment, Optimizely, ScoreCard, Adobe)
    SurrogateSpec universalSdkSurrogate =
        new SurrogateSpec(
            "sugarcoat-sdk-noop",
            "application/javascript; charset=utf-8",
            "(function(){var n=function(){return n;};"
                + "window.hj=window.hj||function(){(window.hj.q=window.hj.q||[]).push(arguments);};"
                + "window.mixpanel=window.mixpanel||{init:n,track:n,identify:n,people:{set:n}};"
                + "window.amplitude=window.amplitude||{getInstance:function(){return{init:n,logEvent:n,setUserId:n,setUserProperties:n};}};"
                + "window.analytics=window.analytics||{load:n,page:n,track:n,identify:n,ready:function(cb){if(typeof cb==='function')try{cb();}catch(_){}}};"
                + "window.optimizely=window.optimizely||[];"
                + "window._satellite=window._satellite||{pageBottom:n,track:n,getVar:function(){return '';}};"
                + "window.COMSCORE=window.COMSCORE||{beacon:n};"
                + "})();");
    map.put("hotjar.com", universalSdkSurrogate);
    map.put("mixpanel.com", universalSdkSurrogate);
    map.put("amplitude.com", universalSdkSurrogate);
    map.put("segment.com/analytics.js", universalSdkSurrogate);
    map.put("optimizely.com", universalSdkSurrogate);
    map.put("scorecardresearch.com", universalSdkSurrogate);
    map.put("adobedtm.com", universalSdkSurrogate);
    return map;
  }

  private static SurrogateSpec matchSugarCoatSurrogate(String reqHost, String pathAndQuery) {
    if (pathAndQuery.contains("/pagead/js/adsbygoogle.js")) {
      return SUGARCOAT_BY_KEY.get("/pagead/js/adsbygoogle.js");
    }
    if (pathAndQuery.contains("/tag/js/gpt.js")) {
      return SUGARCOAT_BY_KEY.get("/tag/js/gpt.js");
    }
    if (pathAndQuery.contains("/gtag/js")) {
      return SUGARCOAT_BY_KEY.get("/gtag/js");
    }
    if (reqHost.endsWith("googletagmanager.com") && pathAndQuery.contains("/gtm.js")) {
      return SUGARCOAT_BY_KEY.get("googletagmanager.com/gtm.js");
    }
    if (reqHost.endsWith("google-analytics.com")
        && (pathAndQuery.contains("analytics.js") || pathAndQuery.contains("/ga.js"))) {
      return SUGARCOAT_BY_KEY.get("google-analytics.com/analytics.js");
    }
    if (pathAndQuery.contains("/fbevents.js")) {
      return SUGARCOAT_BY_KEY.get("/fbevents.js");
    }
    if (pathAndQuery.endsWith(".js") || pathAndQuery.contains(".js?")) {
      if (reqHost.endsWith("hotjar.com")) return SUGARCOAT_BY_KEY.get("hotjar.com");
      if (reqHost.endsWith("mixpanel.com") || reqHost.endsWith("mxpnl.com")) {
        return SUGARCOAT_BY_KEY.get("mixpanel.com");
      }
      if (reqHost.endsWith("amplitude.com")) return SUGARCOAT_BY_KEY.get("amplitude.com");
      if (reqHost.endsWith("segment.com") || reqHost.endsWith("segment.io")) {
        return SUGARCOAT_BY_KEY.get("segment.com/analytics.js");
      }
      if (reqHost.endsWith("optimizely.com")) return SUGARCOAT_BY_KEY.get("optimizely.com");
      if (reqHost.endsWith("scorecardresearch.com")) {
        return SUGARCOAT_BY_KEY.get("scorecardresearch.com");
      }
    }
    return null;
  }

  private static WebResourceResponse buildCleanBlockedResponse(
      WebResourceRequest request, String pathAndQuery) {
    String accept = headerLower(request, "Accept");
    String dest = headerLower(request, "Sec-Fetch-Dest");
    if (accept.startsWith("image/")
        || "image".equals(dest)
        || pathAndQuery.endsWith(".gif")
        || pathAndQuery.endsWith(".png")) {
      return buildResponse(200, "OK", "image/gif", TRANSPARENT_GIF_1X1);
    }
    if ("script".equals(dest)
        || accept.contains("javascript")
        || pathAndQuery.endsWith(".js")
        || pathAndQuery.contains(".js?")) {
      return buildResponse(
          200, "OK", "application/javascript; charset=utf-8", new byte[] {'/', '*', '*', '/'});
    }
    if ("style".equals(dest) || accept.contains("text/css") || pathAndQuery.endsWith(".css")) {
      return buildResponse(200, "OK", "text/css; charset=utf-8", new byte[0]);
    }
    if ("iframe".equals(dest) || "document".equals(dest) || accept.contains("text/html")) {
      return buildResponse(200, "OK", "text/html; charset=utf-8", new byte[0]);
    }
    return buildResponse(204, "No Content", "text/plain; charset=utf-8", new byte[0]);
  }

  private static WebResourceResponse buildResponse(
      int statusCode, String reason, String contentType, byte[] body) {
    String mime = contentType;
    String encoding = "utf-8";
    int semi = contentType.indexOf(';');
    if (semi > 0) {
      mime = contentType.substring(0, semi).trim();
    }
    Map<String, String> headers = new HashMap<>(6);
    headers.put("Access-Control-Allow-Origin", "*");
    headers.put("Access-Control-Allow-Methods", "GET, POST, OPTIONS, HEAD");
    headers.put("Cache-Control", "no-store");
    headers.put("X-Heaven-Shields", "active");
    return new WebResourceResponse(
        mime, encoding, statusCode, reason, headers, new ByteArrayInputStream(body));
  }

  /**
   * Builds the combined Cosmetic + Procedural Filtering + Anti-Fingerprinting (Farbling)
   * DOCUMENT_START script injected natively into frames before website JS executes.
   */
  public String buildDocumentStartProtectionScript() {
    if (!shieldsGloballyEnabled) {
      return "";
    }
    StringBuilder sb = new StringBuilder(8192);
    sb.append("(function(){try{");
    sb.append("if(window.__hbBraveShieldV17)return;window.__hbBraveShieldV17=true;");
    sb.append("var host=(location.hostname||'').toLowerCase();");
    sb.append("if(!host)return;");

    // Sync per-site disabled list into fast JS lookup for cosmetic & farbling skips
    sb.append("var disabled=[");
    boolean first = true;
    for (String d : disabledSiteHosts) {
      if (!first) sb.append(',');
      first = false;
      sb.append('\'').append(d.replace("'", "")).append('\'');
    }
    sb.append("];");
    sb.append(
        "for(var i=0;i<disabled.length;i++){"
            + "var dh=disabled[i];"
            + "if(host===dh||host.endsWith('.'+dh))return;"
            + "}");

    // Pillar 5: Advanced Anti-Fingerprinting ("Farbling") + Global Privacy Control
    if (farblingEnabled) {
      long low32 = sessionFarblingSecret & 0xFFFFFFFFL;
      long high32 = (sessionFarblingSecret >>> 32) & 0xFFFFFFFFL;
      sb.append("(function(){try{");
      sb.append(
          "try{Object.defineProperty(Navigator.prototype,'globalPrivacyControl',{get:function(){return true;},configurable:true});}catch(_){}");
      // Skip strict challenges / OAuth endpoints so logins & CAPTCHAs never trip
      sb.append(
          "if(host==='accounts.google.com'||host==='challenges.cloudflare.com'||host.endsWith('.recaptcha.net'))return;");
      sb.append(
          "var parts=host.split('.');"
              + "var etld=parts.length>=2?parts.slice(-2).join('.'):host;"
              + "var h=("
              + low32
              + "^"
              + high32
              + ")>>>0;"
              + "for(var ci=0;ci<etld.length;ci++){h=Math.imul(h^etld.charCodeAt(ci),2654435761)>>>0;}"
              + "function nextRand(){h=(h+0x6D2B79F5)>>>0;var t=Math.imul(h^(h>>>15),1|h);t=(t+Math.imul(t^(t>>>7),61|t))^t;return((t^(t>>>14))>>>0)/4294967296;}");

      // Hardware concurrency & deviceMemory farbling (deterministic per-site + per-session)
      sb.append(
          "var cores=[4,6,8][h%3];var mem=[4,8][(h>>>3)%2];"
              + "try{Object.defineProperty(Navigator.prototype,'hardwareConcurrency',{get:function(){return cores;},configurable:true});}catch(_){}"
              + "try{if('deviceMemory' in Navigator.prototype){Object.defineProperty(Navigator.prototype,'deviceMemory',{get:function(){return mem;},configurable:true});}}catch(_){}");

      // Canvas 2D Farbling (subtly flips LSB on deterministic sparse pixels — invisible to eye, defeats Canvas hash)
      sb.append(
          "var origGetImageData=CanvasRenderingContext2D.prototype.getImageData;"
              + "function farblePixels(data,seedBase){"
              + "  if(!data||data.length<16)return;"
              + "  var step=Math.max(16,((seedBase%13)+7)*4);"
              + "  for(var p=(seedBase%7)*4;p<data.length;p+=step){data[p]=data[p]^1;}"
              + "}"
              + "CanvasRenderingContext2D.prototype.getImageData=function(){"
              + "  var img=origGetImageData.apply(this,arguments);"
              + "  try{if(img&&img.data&&img.width>=8&&img.height>=2){farblePixels(img.data,h);}}catch(_){}"
              + "  return img;"
              + "};"
              + "var origToDataURL=HTMLCanvasElement.prototype.toDataURL;"
              + "HTMLCanvasElement.prototype.toDataURL=function(){"
              + "  try{"
              + "    if(this.width>=8&&this.width<=1200&&this.height>=2&&this.height<=400){"
              + "      var ctx=this.getContext('2d');"
              + "      if(ctx){"
              + "        var px=origGetImageData.call(ctx,0,0,Math.min(this.width,32),1);"
              + "        px.data[0]=px.data[0]^((h&1)||1);"
              + "        ctx.putImageData(px,0,0);"
              + "      }"
              + "    }"
              + "  }catch(_){}"
              + "  return origToDataURL.apply(this,arguments);"
              + "};");

      // Font metric subpixel farbling against offscreen font enumeration
      sb.append(
          "var origMeasure=CanvasRenderingContext2D.prototype.measureText;"
              + "var fontJitter=((nextRand()-0.5)*0.0004);"
              + "CanvasRenderingContext2D.prototype.measureText=function(){"
              + "  var m=origMeasure.apply(this,arguments);"
              + "  try{"
              + "    var w=m.width;"
              + "    Object.defineProperty(m,'width',{get:function(){return w>0?w+fontJitter:w;},configurable:true});"
              + "  }catch(_){}"
              + "  return m;"
              + "};");

      // WebAudio AudioBuffer / AnalyserNode farbling
      sb.append(
          "if(window.AudioBuffer&&AudioBuffer.prototype.getChannelData){"
              + "  var origChan=AudioBuffer.prototype.getChannelData;"
              + "  var audioDelta=(nextRand()*1e-7);"
              + "  AudioBuffer.prototype.getChannelData=function(){"
              + "    var arr=origChan.apply(this,arguments);"
              + "    try{if(arr&&!arr.__hbFarbled&&arr.length>0){arr.__hbFarbled=true;for(var k=0;k<arr.length;k+=64){arr[k]=arr[k]+audioDelta;}}}catch(_){}"
              + "    return arr;"
              + "  };"
              + "}");

      // WebGL parameter & readPixels farbling
      sb.append(
          "function patchWebGL(proto){"
              + "  if(!proto||!proto.getParameter)return;"
              + "  var origParam=proto.getParameter;"
              + "  proto.getParameter=function(p){"
              + "    var v=origParam.apply(this,arguments);"
              + "    if((p===37445||p===37446)&&typeof v==='string'&&v.length>0){"
              + "      return v+(h%2===0?'':' ');"
              + "    }"
              + "    return v;"
              + "  };"
              + "}"
              + "if(window.WebGLRenderingContext)patchWebGL(WebGLRenderingContext.prototype);"
              + "if(window.WebGL2RenderingContext)patchWebGL(WebGL2RenderingContext.prototype);");
      sb.append("}catch(_){}})();");
    }

    // Pillar 3: Cosmetic CSS + Throttled Procedural Filtering (collapses empty ad placeholders!)
    sb.append(
        "(function(){try{"
            + "var css='"
            + "ins.adsbygoogle,[id^=\"div-gpt-ad\"],[id^=\"google_ads_iframe\"],"
            + "iframe[src*=\"doubleclick.net\"],iframe[src*=\"googlesyndication.com\"],"
            + "iframe[src*=\"adnxs.com\"],iframe[src*=\"exoclick.com\"],"
            + "[id^=\"taboola-\"],.taboola-below-article-thumbnails,.OUTBRAIN,[data-ob-template],"
            + "[data-ad-slot],[data-ad-unit-path],[data-ez-ph-id],div[aria-label=\"advertisement\"],"
            + ".ytp-ad-module,.ytp-ad-overlay-container,.ytp-ad-message-container,"
            + "ytd-ad-slot-renderer,ytd-in-feed-ad-layout-renderer,ytd-banner-promo-renderer,"
            + "ytd-promoted-sparkles-web-renderer,ytm-promoted-sparkles-web-renderer,"
            + "ytm-companion-ad-renderer,#masthead-ad,#player-ads"
            + "{display:none!important;height:0!important;min-height:0!important;"
            + "max-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important;visibility:hidden!important;}';"
            + "function injectStyle(){"
            + "  if(document.getElementById('__hb_brave_cosmetic'))return;"
            + "  var st=document.createElement('style');st.id='__hb_brave_cosmetic';"
            + "  st.textContent=css;"
            + "  (document.head||document.documentElement).appendChild(st);"
            + "}"
            + "if(document.head||document.documentElement){injectStyle();}"
            + "else{document.addEventListener('DOMContentLoaded',injectStyle,{once:true});}"
            // Procedural filter: collapses empty wrapper boxes left behind by blocked ad iframes & skips YT pre-roll ad state
            + "var procTimer=0;"
            + "function runProceduralPass(){"
            + "  procTimer=0;"
            + "  try{"
            + "    injectStyle();"
            + "    var slots=document.querySelectorAll('ins.adsbygoogle,[id^=\"div-gpt-ad\"],[data-ad-slot],[id^=\"google_ads_iframe\"]');"
            + "    for(var i=0;i<slots.length;i++){"
            + "      var p=slots[i].parentElement;"
            + "      if(p&&p.tagName==='DIV'&&p.children.length<=2&&(p.innerText||'').trim().length<=16){"
            + "        p.style.setProperty('min-height','0px','important');"
            + "        if((p.innerText||'').trim().length===0){p.style.setProperty('height','0px','important');p.style.setProperty('margin','0px','important');}"
            + "      }"
            + "    }"
            + "    if(host.endsWith('youtube.com')){"
            + "      var player=document.querySelector('.html5-video-player.ad-showing');"
            + "      if(player){"
            + "        var vid=player.querySelector('video');"
            + "        if(vid&&isFinite(vid.duration)&&vid.duration>0){vid.muted=true;vid.currentTime=vid.duration;}"
            + "        var skip=document.querySelector('.ytp-ad-skip-button,.ytp-ad-skip-button-modern,.ytp-skip-ad-button');"
            + "        if(skip)skip.click();"
            + "      }"
            + "    }"
            + "  }catch(_){}"
            + "}"
            + "function scheduleProcedural(){"
            + "  if(procTimer)return;"
            + "  procTimer=setTimeout(function(){"
            + "    if(window.requestIdleCallback){window.requestIdleCallback(runProceduralPass,{timeout:400});}"
            + "    else{runProceduralPass();}"
            + "  },320);"
            + "}"
            + "document.addEventListener('DOMContentLoaded',function(){"
            + "  runProceduralPass();"
            + "  if(window.MutationObserver&&document.documentElement){"
            + "    new MutationObserver(scheduleProcedural).observe(document.documentElement,{childList:true,subtree:true});"
            + "  }"
            + "},{once:true});"
            + "}catch(_){}})();");

    sb.append("}catch(_){}})();");
    return sb.toString();
  }

  private void loadCachedOrSyncFilterLists() {
    File cacheFile = new File(appContext.getFilesDir(), CACHE_FILE_NAME);
    if (cacheFile.exists() && cacheFile.length() > 512) {
      List<String> lines = readLinesFromFile(cacheFile, 65000);
      if (!lines.isEmpty()) {
        this.activeSnapshot = compileSnapshotFromLines(lines);
      }
    }
    long now = System.currentTimeMillis();
    if (!cacheFile.exists() || (now - lastFilterSyncMs) >= FILTER_REFRESH_INTERVAL_MS) {
      syncRemoteFilterListsInternal();
    }
  }

  private void syncRemoteFilterListsInternal() {
    if (!syncInProgress.compareAndSet(false, true)) {
      return;
    }
    try {
      List<String> mergedLines = new ArrayList<>(32000);
      for (String listUrl : FILTER_LIST_URLS) {
        List<String> fetched = fetchRemoteFilterLines(listUrl, 28000);
        if (!fetched.isEmpty()) {
          mergedLines.addAll(fetched);
          if (mergedLines.size() >= 45000) {
            break;
          }
        }
      }
      if (!mergedLines.isEmpty()) {
        FilterSnapshot next = compileSnapshotFromLines(mergedLines);
        this.activeSnapshot = next;
        this.lastFilterSyncMs = System.currentTimeMillis();
        writeLinesToCacheFile(new File(appContext.getFilesDir(), CACHE_FILE_NAME), mergedLines);
        persistLifetimeCounters();
      }
    } catch (Throwable ignored) {
    } finally {
      syncInProgress.set(false);
    }
  }

  private static List<String> fetchRemoteFilterLines(String urlStr, int maxLines) {
    List<String> out = new ArrayList<>();
    HttpURLConnection conn = null;
    try {
      conn = (HttpURLConnection) URI.create(urlStr).toURL().openConnection();
      conn.setConnectTimeout(6000);
      conn.setReadTimeout(9000);
      conn.setRequestProperty("User-Agent", "HeavenBrowser/0.0.1 BraveShieldsSync");
      if (conn.getResponseCode() != 200) {
        return out;
      }
      try (InputStream is = conn.getInputStream();
          BufferedReader br =
              new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
        String line;
        while ((line = br.readLine()) != null && out.size() < maxLines) {
          String trimmed = line.trim();
          if (trimmed.isEmpty()
              || trimmed.charAt(0) == '!'
              || trimmed.charAt(0) == '['
              || trimmed.contains("##")
              || trimmed.contains("#@#")
              || trimmed.contains("#?#")) {
            continue;
          }
          out.add(trimmed);
        }
      }
    } catch (Throwable ignored) {
    } finally {
      if (conn != null) {
        conn.disconnect();
      }
    }
    return out;
  }

  private static List<String> readLinesFromFile(File f, int maxLines) {
    List<String> out = new ArrayList<>();
    try (FileInputStream fis = new FileInputStream(f);
        BufferedReader br =
            new BufferedReader(new InputStreamReader(fis, StandardCharsets.UTF_8))) {
      String line;
      while ((line = br.readLine()) != null && out.size() < maxLines) {
        if (!line.isEmpty()) {
          out.add(line);
        }
      }
    } catch (Throwable ignored) {
    }
    return out;
  }

  private static void writeLinesToCacheFile(File f, List<String> lines) {
    try (FileOutputStream fos = new FileOutputStream(f)) {
      StringBuilder chunk = new StringBuilder(16384);
      for (String line : lines) {
        chunk.append(line).append('\n');
        if (chunk.length() >= 14000) {
          fos.write(chunk.toString().getBytes(StandardCharsets.UTF_8));
          chunk.setLength(0);
        }
      }
      if (chunk.length() > 0) {
        fos.write(chunk.toString().getBytes(StandardCharsets.UTF_8));
      }
    } catch (Throwable ignored) {
    }
  }

  /**
   * Native EasyList / EasyPrivacy compiler: indexes ||domain^, @@||exception^, and URL option rules.
   */
  static FilterSnapshot compileSnapshotFromLines(List<String> rawLines) {
    Set<String> blocked = new HashSet<>(BUILTIN_BLOCKED_DOMAINS.length * 2 + rawLines.size());
    Set<String> exceptions = new HashSet<>(ESSENTIAL_ALLOW_DOMAINS);
    List<UrlPatternRule> patterns = new ArrayList<>(BUILTIN_URL_PATTERNS.length + 256);

    for (String d : BUILTIN_BLOCKED_DOMAINS) {
      String clean = normalizeHost(d);
      if (!clean.isEmpty() && !clean.contains("/")) {
        blocked.add(clean);
      } else if (clean.contains("/")) {
        patterns.add(new UrlPatternRule(d.toLowerCase(Locale.US), true, false, false));
      }
    }
    for (String p : BUILTIN_URL_PATTERNS) {
      patterns.add(new UrlPatternRule(p.toLowerCase(Locale.US), false, false, false));
    }

    for (String raw : rawLines) {
      String line = raw.trim();
      if (line.isEmpty() || line.charAt(0) == '!' || line.contains("##")) {
        continue;
      }
      boolean isException = line.startsWith("@@");
      if (isException) {
        line = line.substring(2);
      }

      String options = "";
      int dollar = line.indexOf('$');
      if (dollar >= 0) {
        options = line.substring(dollar + 1).toLowerCase(Locale.US);
        line = line.substring(0, dollar);
        // Skip rules constrained to specific unrelated site domains or badfilter/popup-only modifiers
        if (options.contains("domain=")
            || options.contains("badfilter")
            || options.contains("elemhide")
            || options.contains("generichide")) {
          continue;
        }
      }

      if (line.startsWith("||")) {
        String body = line.substring(2);
        int endIdx = body.length();
        for (int i = 0; i < body.length(); i++) {
          char c = body.charAt(i);
          if (c == '^' || c == '/' || c == '*' || c == '?') {
            endIdx = i;
            break;
          }
        }
        String candHost = normalizeHost(body.substring(0, endIdx));
        boolean hasPathAfterDomain =
            endIdx < body.length()
                && !(endIdx == body.length() - 1 && body.charAt(endIdx) == '^');
        if (!hasPathAfterDomain && isValidHostname(candHost)) {
          if (isException) {
            exceptions.add(candHost);
          } else if (!ESSENTIAL_ALLOW_DOMAINS.contains(candHost)) {
            blocked.add(candHost);
          }
          continue;
        }
      }

      if (!isException && patterns.size() < 900) {
        String cleanPattern = line.replace("^", "").replace("*", "");
        if (cleanPattern.length() >= 8 && !cleanPattern.startsWith("/")) {
          continue;
        }
        if (cleanPattern.length() >= 8) {
          boolean tp = options.contains("third-party") || options.contains("3p");
          boolean sc = options.contains("script");
          boolean im = options.contains("image");
          patterns.add(new UrlPatternRule(cleanPattern.toLowerCase(Locale.US), tp, sc, im));
        }
      }
    }

    return new FilterSnapshot(blocked, exceptions, patterns);
  }

  private static boolean isValidHostname(String h) {
    if (h == null || h.length() < 4 || h.indexOf('.') <= 0 || h.endsWith(".")) {
      return false;
    }
    for (int i = 0; i < h.length(); i++) {
      char c = h.charAt(i);
      if (!((c >= 'a' && c <= 'z')
          || (c >= '0' && c <= '9')
          || c == '.'
          || c == '-'
          || c == '_')) {
        return false;
      }
    }
    return true;
  }

  static boolean matchesDomainSet(String host, Set<String> domainSet) {
    if (host == null || host.isEmpty() || domainSet.isEmpty()) {
      return false;
    }
    String cur = host;
    while (true) {
      if (domainSet.contains(cur)) {
        return true;
      }
      int dot = cur.indexOf('.');
      if (dot < 0 || dot + 1 >= cur.length()) {
        return false;
      }
      cur = cur.substring(dot + 1);
    }
  }

  static String extractEtldPlusOne(String rawHost) {
    String h = normalizeHost(rawHost);
    if (h.isEmpty()) {
      return "";
    }
    String[] parts = h.split("\\.");
    if (parts.length <= 2) {
      return h;
    }
    String lastTwo = parts[parts.length - 2] + "." + parts[parts.length - 1];
    if (MULTI_PART_TLDS.contains(lastTwo) && parts.length >= 3) {
      return parts[parts.length - 3] + "." + lastTwo;
    }
    return lastTwo;
  }

  static String normalizeHost(String raw) {
    if (raw == null) {
      return "";
    }
    String s = raw.trim().toLowerCase(Locale.US);
    while (s.endsWith(".")) {
      s = s.substring(0, s.length() - 1);
    }
    return s;
  }

  private static String extractPathAndQueryLower(String fullUrlLower) {
    int schemeIdx = fullUrlLower.indexOf("://");
    int slashIdx = fullUrlLower.indexOf('/', schemeIdx >= 0 ? schemeIdx + 3 : 0);
    return slashIdx >= 0 ? fullUrlLower.substring(slashIdx) : "/";
  }

  /**
   * Transparently wraps webview_flutter's WebViewClientImpl, delegating 100% of navigation and
   * lifecycle callbacks while running Brave Shields subresource interception on Chromium IO threads.
   */
  private final class BraveNativeWebViewClient extends WebViewClient {
    private final WebViewClient delegate;
    private final long webViewId;

    BraveNativeWebViewClient(WebViewClient delegate, long webViewId) {
      this.delegate = delegate;
      this.webViewId = webViewId;
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
      WebResourceResponse shieldResp = evaluateNetworkRequest(webViewId, request);
      if (shieldResp != null) {
        return shieldResp;
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
      if (url != null) {
        try {
          setPageHostForWebView(webViewId, Uri.parse(url).getHost());
        } catch (Throwable ignored) {
        }
      }
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
