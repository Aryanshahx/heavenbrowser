import 'dart:convert';

class HeavenShield {
  const HeavenShield._();

  /// Comprehensive 170+ root domain list covering ad networks, video ad SDKs,
  /// popunders, malvertising, behavioral trackers, and telemetry beacons.
  static const Set<String> blockedRootDomains = <String>{
    // Google Ads / DoubleClick / IMA Video Ads
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'adservice.google.com',
    'adsense.com',
    'admeld.com',
    '2mdn.net',
    'imasdk.googleapis.com',
    'pagead2.googlesyndication.com',
    'tpc.googlesyndication.com',
    'google-analytics.com',
    'googletagmanager.com',
    'googletagservices.com',

    // Major Programmatic & Display Ad Exchanges
    'adnxs.com',
    'adsrvr.org',
    'criteo.com',
    'criteo.net',
    'pubmatic.com',
    'rubiconproject.com',
    'openx.net',
    'casalemedia.com',
    'indexww.com',
    'amazon-adsystem.com',
    'media.net',
    'yieldmo.com',
    'sharethrough.com',
    '33across.com',
    'triplelift.com',
    '3lift.com',
    'lijit.com',
    'sovrn.com',
    'gumgum.com',
    'teads.tv',
    'kargo.com',
    'smartadserver.com',
    'undertone.com',
    'conversantmedia.com',
    'exponential.com',
    'tribalfusion.com',
    'zedo.com',
    'adform.net',
    'serving-sys.com',
    'flashtalking.com',
    'celtra.com',
    'bidswitch.net',
    'contextweb.com',
    'sonobi.com',
    'spotxchange.com',
    'spotx.tv',
    'fwmrm.net',
    'innovid.com',
    'springserve.com',
    'connatix.com',
    'primis.tech',
    'aniview.com',

    // Native Content Chumboxes & Sponsored Widgets
    'taboola.com',
    'trc.taboola.com',
    'outbrain.com',
    'outbrainimg.com',
    'zemanta.com',
    'mgid.com',
    'revcontent.com',
    'content.ad',
    'adblade.com',
    'zergnet.com',
    'nativo.com',
    'dianomi.com',

    // Aggressive Popunders, Redirects & Malvertising Networks
    'popads.net',
    'popcash.net',
    'propellerads.com',
    'onclickads.net',
    'adsterra.com',
    'adsterratech.com',
    'highperformanceformat.com',
    'profitabledisplaynetwork.com',
    'exoclick.com',
    'exosrv.com',
    'syndication.exdynsrv.com',
    'exdynsrv.com',
    'juicyads.com',
    'trafficjunky.net',
    'trafficstars.com',
    'hilltopads.net',
    'clickadu.com',
    'adcash.com',
    'bidvertiser.com',
    'ero-advertising.com',
    'plugrush.com',
    'admaven.com',
    'richads.com',
    'evadav.com',
    'galaksion.com',
    'monetag.com',
    'a-ads.com',
    'coinzilla.com',

    // Mobile & In-Web Ad SDKs
    'adcolony.com',
    'applovin.com',
    'applvn.com',
    'unityads.unity3d.com',
    'vungle.com',
    'chartboost.com',
    'inmobi.com',
    'ironsrc.com',
    'SupersonicAds.com',
    'startappservice.com',
    'tapjoy.com',
    'smaato.net',
    'fyber.com',
    'mobfox.com',
    'admob.com',

    // Ad Verification, Viewability & Attribution Trackers
    'moatads.com',
    'adsafeprotected.com',
    'doubleverify.com',
    'scorecardresearch.com',
    'sb.scorecardresearch.com',
    'quantserve.com',
    'quantcount.com',
    'imrworldwide.com',
    'krxd.net',
    'bluekai.com',
    'demdex.net',
    'omtrdc.net',
    'everesttech.net',
    'agkn.com',
    'rlcdn.com',
    'tapad.com',
    'lotame.com',
    'crwdcntrl.net',
    'exelator.com',
    'eyeota.net',
    'mathtag.com',
    'turn.com',
    'mookie1.com',
    'dotomi.com',
    'liadm.com',
    'id5-sync.com',

    // Session Replay, Heatmaps & Behavioral Trackers
    'hotjar.com',
    'hotjar.io',
    'clarity.ms',
    'mouseflow.com',
    'fullstory.com',
    'luckyorange.com',
    'crazyegg.com',
    'inspectlet.com',
    'logrocket.io',
    'smartlook.com',
    'mixpanel.com',
    'amplitude.com',
    'heapanalytics.com',
    'segment.io',
    'segment.com',
    'kissmetrics.com',
    'clevertap.com',
    'braze.com',
    'onesignal.com',
    'appsflyer.com',
    'adjust.com',
    'branch.io',
    'app.link',
    'kochava.com',
    'singular.net',

    // Social Ad Pixels & Cross-Site Trackers
    'connect.facebook.net',
    'an.facebook.com',
    'analytics.tiktok.com',
    'ads-twitter.com',
    'static.ads-twitter.com',
    't.co/i/adsct',
    'sc-static.net/scevent.min.js',
    'snap.licdn.com',
    'px.ads.linkedin.com',
    'ct.pinterest.com',
    'alb.reddit.com',
    'events.redditmedia.com',
    'mc.yandex.ru',
    'an.yandex.ru',
    'hm.baidu.com',
    'cpro.baidu.com',
  };

  static const Set<String> trackingQueryParameters = <String>{
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_term',
    'utm_content',
    'utm_id',
    'fbclid',
    'gclid',
    'dclid',
    'msclkid',
    'twclid',
    'ttclid',
    'yclid',
    'mc_cid',
    'mc_eid',
    '_hsenc',
    '_hsmi',
    'igshid',
    'si',
  };

  /// O(number of labels) domain suffix check against [blockedRootDomains].
  static String? matchBlockedDomain(String host) {
    String current = host.trim().toLowerCase();
    if (current.isEmpty) {
      return null;
    }
    while (true) {
      if (blockedRootDomains.contains(current)) {
        return current;
      }
      final int dot = current.indexOf('.');
      if (dot < 0 || dot == current.length - 1) {
        break;
      }
      current = current.substring(dot + 1);
    }
    return null;
  }

  static bool shouldBlockUri(Uri uri, {String? pageHost}) {
    if (uri.host.isEmpty) {
      return false;
    }
    if (matchBlockedDomain(uri.host) != null) {
      return true;
    }
    final String pathAndQuery = '${uri.path}?${uri.query}'.toLowerCase();
    if (pathAndQuery.contains('/adsbygoogle') ||
        pathAndQuery.contains('/pagead/') ||
        pathAndQuery.contains('/gpt.js') ||
        pathAndQuery.contains('/popunder')) {
      return true;
    }
    return false;
  }

  /// Strips tracking parameters while preserving functional query arguments.
  static ({Uri uri, int removedCount}) stripTrackingParameters(Uri uri) {
    if (!uri.hasQuery || uri.queryParametersAll.isEmpty) {
      return (uri: uri, removedCount: 0);
    }

    int removed = 0;
    final Map<String, List<String>> cleanParams = <String, List<String>>{};

    uri.queryParametersAll.forEach((String key, List<String> values) {
      final String lower = key.toLowerCase();
      if (trackingQueryParameters.contains(lower) || lower.startsWith('utm_')) {
        removed += values.length;
      } else {
        cleanParams[key] = values;
      }
    });

    if (removed == 0) {
      return (uri: uri, removedCount: 0);
    }

    final String newQuery = cleanParams.entries
        .expand(
          (MapEntry<String, List<String>> entry) => entry.value.map(
            (String v) =>
                '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(v)}',
          ),
        )
        .join('&');

    return (
      uri: uri.replace(query: newQuery.isEmpty ? null : newQuery),
      removedCount: removed,
    );
  }

  /// Cosmetic DOM filter + popup blocker + YouTube video-ad auto-skipper.
  static String buildProtectionScript({
    required bool shieldEnabled,
    required bool sendDntAndGpc,
  }) {
    final String encodedDomains = jsonEncode(blockedRootDomains.toList());

    return '''
(function() {
  if (window.__heavenShieldV3Active) return;
  window.__heavenShieldV3Active = true;

  if ($sendDntAndGpc) {
    try {
      Object.defineProperty(navigator, 'globalPrivacyControl', {
        get: () => true,
        configurable: true
      });
      Object.defineProperty(navigator, 'doNotTrack', {
        get: () => '1',
        configurable: true
      });
    } catch (_) {}
  }

  if (!$shieldEnabled) return;

  const blockedDomains = new Set($encodedDomains);

  function matchBlocked(rawUrl) {
    try {
      const parsed = new URL(rawUrl, window.location.href);
      let h = (parsed.hostname || '').toLowerCase();
      while (h) {
        if (blockedDomains.has(h)) return h;
        const dot = h.indexOf('.');
        if (dot < 0) break;
        h = h.slice(dot + 1);
      }
    } catch (_) {}
    return null;
  }

  function notifyShield(domain) {
    try {
      if (window.HeavenShieldChannel && window.HeavenShieldChannel.postMessage) {
        window.HeavenShieldChannel.postMessage(domain || 'ad-element');
      }
    } catch (_) {}
  }

  // Block popup hijacks (window.open to ad networks or blank popunders)
  const origOpen = window.open;
  window.open = function(url, target, features) {
    const matched = url ? matchBlocked(String(url)) : 'popup';
    if (matched || !url || String(url) === 'about:blank') {
      notifyShield(matched || 'popup');
      return null;
    }
    return origOpen ? origOpen.call(this, url, target, features) : null;
  };

  // Cosmetic CSS rules (collapses ad slots cleanly so zero blank boxes remain)
  const adCss = `
    ins.adsbygoogle,
    .adsbygoogle,
    [id^="div-gpt-ad"],
    [id^="google_ads_iframe"],
    iframe[src*="doubleclick.net"],
    iframe[src*="googlesyndication.com"],
    iframe[src*="adnxs.com"],
    iframe[src*="taboola.com"],
    iframe[src*="outbrain.com"],
    iframe[src*="exoclick.com"],
    iframe[src*="adsterra"],
    [data-ad-slot],
    [data-ad-client],
    [data-google-query-id],
    [aria-label="Advertisement"],
    [aria-label="Sponsored"],
    .ad-banner,
    .ad-container,
    .ad-slot,
    .ad-wrapper,
    .dfp-ad,
    .sponsored-banner,
    .taboola-widget,
    .OUTBRAIN,
    div[id*="taboola-"],
    div[id*="outbrain_widget"],
    ytd-ad-slot-renderer,
    ytd-promoted-sparkles-web-renderer,
    ytd-in-feed-ad-layout-renderer,
    ytd-banner-promo-renderer,
    ytm-promoted-sparkles-web-renderer,
    ytm-companion-ad-renderer,
    .ytp-ad-overlay-container,
    .ytp-ad-message-container {
      display: none !important;
      height: 0 !important;
      min-height: 0 !important;
      max-height: 0 !important;
      visibility: hidden !important;
      opacity: 0 !important;
      pointer-events: none !important;
      overflow: hidden !important;
    }
  `;

  function ensureStyle() {
    if (document.getElementById('heaven-shield-css')) return;
    const style = document.createElement('style');
    style.id = 'heaven-shield-css';
    style.textContent = adCss;
    (document.head || document.documentElement).appendChild(style);
  }
  ensureStyle();

  // Auto-skip video pre-rolls on YouTube mobile/desktop web
  function sweepAds() {
    ensureStyle();
    try {
      const skipSelectors = [
        '.ytp-ad-skip-button',
        '.ytp-ad-skip-button-modern',
        '.ytp-skip-ad-button',
        '.videoAdUiSkipButton'
      ];
      for (const sel of skipSelectors) {
        const btn = document.querySelector(sel);
        if (btn) {
          btn.click();
          notifyShield('video-ad');
        }
      }
      const adPlayer = document.querySelector('.ad-showing video');
      if (adPlayer && isFinite(adPlayer.duration) && adPlayer.duration > 0) {
        adPlayer.muted = true;
        adPlayer.currentTime = adPlayer.duration;
        notifyShield('video-ad');
      }
    } catch (_) {}
  }

  sweepAds();
  const observer = new MutationObserver(() => sweepAds());
  observer.observe(document.documentElement, { childList: true, subtree: true });
})();
''';
  }
}
