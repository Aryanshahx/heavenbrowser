import 'dart:convert';

class HeavenShield {
  const HeavenShield._();

  /// Comprehensive 260+ root domain list covering Google Ads, YouTube Ad servers,
  /// pirated streaming & adult/porn popunder/redirect networks, casino/cam spam,
  /// malvertising, and behavioral trackers.
  static const Set<String> blockedRootDomains = <String>{
    // Google Ads / DoubleClick / IMA Video Ads / FundingChoices
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'adservice.google.com',
    'adsense.com',
    'adsensecustomsearchads.com',
    'adtrafficquality.google',
    'ads.youtube.com',
    'fundingchoicesmessages.google.com',
    'admeld.com',
    '2mdn.net',
    'imasdk.googleapis.com',
    'ima3vpaid.appspot.com',
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
    'bidgear.com',

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

    // Pirated Streaming & Adult/Porn Popunders, Click-Hijacks & Redirect Traps
    'popads.net',
    'popcash.net',
    'propellerads.com',
    'propellerclick.com',
    'onclickads.net',
    'onclickalgo.com',
    'onclkds.com',
    'onclasrv.com',
    'adsterra.com',
    'adsterratech.com',
    'highperformanceformat.com',
    'profitabledisplaynetwork.com',
    'profitablecpmrate.com',
    'effectivegatecpm.com',
    'topcreativeformat.com',
    'agacelebir.com',
    'alwingulla.com',
    'exoclick.com',
    'exosrv.com',
    'syndication.exdynsrv.com',
    'exdynsrv.com',
    'realsrv.com',
    'tsyndicate.com',
    'tsyn-b.com',
    'magsrv.com',
    'pemsrv.com',
    'juicyads.com',
    'trafficjunky.net',
    'trafficjunky.com',
    'trafficstars.com',
    'twinrdsyn.com',
    'twinrdengine.com',
    'hilltopads.net',
    'hilltopads.com',
    'bet365.com',
    'go.stripchat.com',
    'jerkmate.com',
    'clickadu.com',
    'clickaine.com',
    'adcash.com',
    'ufpcdn.com',
    'acscdn.com',
    'bidvertiser.com',
    'ero-advertising.com',
    'plugrush.com',
    'admaven.com',
    'ad-maven.com',
    'dolohen.com',
    'richads.com',
    'richpush.co',
    'evadav.com',
    'galaksion.com',
    'mondiad.com',
    'monetag.com',
    'a-ads.com',
    'coinzilla.com',
    'xlivrdr.com',
    'prmtracking.com',
    'crakrevenue.com',
    'awempire.com',
    'irtyc.com',
    '1xbet.com',
    '1xstavka.ru',
    'betwinner.com',
    'mostbet.com',
    'melbet.com',
    'parimatch.com',
    '4rabet.com',

    // Mobile & In-Web Ad SDKs
    'adcolony.com',
    'applovin.com',
    'applvn.com',
    'unityads.unity3d.com',
    'vungle.com',
    'chartboost.com',
    'inmobi.com',
    'ironsrc.com',
    'supersonicads.com',
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
    'snap.licdn.com',
    'px.ads.linkedin.com',
    'ct.pinterest.com',
    'alb.reddit.com',
    'events.redditmedia.com',
    'mc.yandex.ru',
    'an.yandex.ru',
    'hm.baidu.com',
    'cpro.baidu.com',

    // Additional Video, Regional/Indian News, Push-Spam & Programmatic Ad Networks
    'clmbtech.com',
    'izooto.com',
    'vizury.com',
    'vdo.ai',
    'vidazoo.com',
    'anyclip.com',
    'jwpltx.com',
    'adrecover.com',
    'pushengage.com',
    'pushcrew.com',
    'webengage.com',
    'gravitec.net',
    'notix.io',
    'rollerads.com',
    'ungads.com',
    'yektanet.com',
    'trafmag.com',
    'adspyglass.com',
    'acint.net',
    'adriver.ru',
    'adhigh.net',
    'rtmark.net',
    'freestar.io',
    'pubfuture.com',
    'nitropay.com',
    'snigelweb.com',
    'ezoic.net',
    'ezodn.com',
    'mediavine.com',
    'adthrive.com',
    'cafemedia.com',
    'playwire.com',
    'venatusmedia.com',
    'adpushup.com',
    'setupad.com',
    'optad360.io',
    'onetag-sys.com',
    'smilewanted.com',
    'seedtag.com',
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
    final String lowerHost = uri.host.toLowerCase();
    final String lowerPage = (pageHost ?? '').toLowerCase().trim();
    if (lowerPage.isNotEmpty &&
        lowerHost != lowerPage &&
        !lowerHost.endsWith('.$lowerPage') &&
        !lowerPage.endsWith('.$lowerHost')) {
      const List<String> crossSiteRedirectTraps = <String>[
        'chaturbate.com',
        'stripchat.com',
        'livejasmin.com',
        'bongacams.com',
        'jerkmate.com',
        'cam4.com',
        'myfreecams.com',
        '1xbet',
        'betwinner',
        'mostbet',
        'melbet',
        'parimatch',
        '4rabet',
      ];
      for (final String trap in crossSiteRedirectTraps) {
        if (lowerHost.contains(trap)) {
          return true;
        }
      }
    }
    final String pathAndQuery = '${uri.path}?${uri.query}'.toLowerCase();
    if (pathAndQuery.contains('/adsbygoogle') ||
        pathAndQuery.contains('/pagead/') ||
        pathAndQuery.contains('/api/stats/ads') ||
        pathAndQuery.contains('/get_midroll_') ||
        pathAndQuery.contains('/gpt.js') ||
        pathAndQuery.contains('/afu.php') ||
        pathAndQuery.contains('/popunder') ||
        pathAndQuery.contains('google_vignette')) {
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

  /// Cosmetic DOM filter + strict popup/redirect/overlay firewall + YouTube zero-ad engine.
  static String buildProtectionScript({
    required bool shieldEnabled,
    required bool sendDntAndGpc,
  }) {
    final String encodedDomains = jsonEncode(blockedRootDomains.toList());

    return '''
(function() {
  if (window.__heavenShieldV10Active) return;
  window.__heavenShieldV10Active = true;

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

  function notifyShield(domain) {
    try {
      if (window.HeavenShieldChannel && window.HeavenShieldChannel.postMessage) {
        window.HeavenShieldChannel.postMessage(domain || 'ad-element');
      }
    } catch (_) {}
  }

  // 1. Unconditional popup/popunder lock (blocks rotating pirated/adult ad domains too!)
  const deadWindowProxy = new Proxy(
    { closed: false, close() {}, focus() {}, blur() {}, postMessage() {} },
    { get: (t, p) => (p in t ? t[p] : () => {}), set: () => true }
  );
  window.open = function(url) {
    notifyShield('popup-blocked');
    return deadWindowProxy;
  };

  // 2. Block synthetic detached <a href="https://ad-redirect..."> click() tricks
  const origAnchorClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function() {
    try {
      const href = this.href || '';
      if (!this.isConnected || (this.offsetWidth === 0 && this.offsetHeight === 0)) {
        if (href && !href.includes(location.hostname)) {
          notifyShield('redirect-blocked');
          return;
        }
      }
    } catch (_) {}
    return origAnchorClick.apply(this, arguments);
  };

  // 3. Approve ONLY real visible <a href> taps & strip invisible click-jacking overlays
  document.addEventListener('pointerdown', function(ev) {
    try {
      const a = ev.target && ev.target.closest ? ev.target.closest('a[href]') : null;
      if (!a) return;
      const r = a.getBoundingClientRect();
      const cs = window.getComputedStyle(a);
      const op = parseFloat(cs.opacity || '1');
      const isTransparentCover =
        (cs.position === 'fixed' || cs.position === 'absolute') &&
        r.width > window.innerWidth * 0.6 &&
        r.height > window.innerHeight * 0.4 &&
        !(a.textContent || '').trim();
      if (isTransparentCover || op < 0.12 || r.width < 10 || r.height < 10) {
        a.style.setProperty('pointer-events', 'none', 'important');
        a.removeAttribute('href');
        notifyShield('overlay-ad');
        return;
      }
      const parsed = new URL(a.href, location.href);
      if ((parsed.protocol === 'http:' || parsed.protocol === 'https:') &&
          parsed.hostname && parsed.hostname !== location.hostname) {
        notifyShield('ALLOW_NAV:' + parsed.hostname.toLowerCase());
      }
    } catch (_) {}
  }, true);

  // 4. Cosmetic CSS rules for Google Ads, YouTube Ads (Mobile + Desktop), & Pirated/Adult Slots
  const adCss = `
    ins.adsbygoogle,
    .adsbygoogle,
    #google_vignette,
    ins[data-vignette-loaded],
    [id^="div-gpt-ad"],
    [id^="google_ads_iframe"],
    iframe[src*="doubleclick.net"],
    iframe[src*="googlesyndication.com"],
    iframe[src*="googleadservices.com"],
    iframe[src*="adnxs.com"],
    iframe[src*="taboola.com"],
    iframe[src*="outbrain.com"],
    iframe[src*="exoclick"],
    iframe[src*="realsrv"],
    iframe[src*="tsyndicate"],
    iframe[src*="juicyads"],
    iframe[src*="trafficjunky"],
    iframe[src*="adsterra"],
    iframe[src*="propeller"],
    iframe[src*="magsrv"],
    iframe[src*="clmbtech"],
    iframe[src*="vdo.ai"],
    [data-ad-slot],
    [data-ad-client],
    #tads,
    #bottomads,
    #tvcap,
    [data-text-ad],
    [aria-label="Ads"],
    [aria-label="Advertisement"],
    [aria-label="Sponsored"],
    mobile-promo,
    .SwDSGe,
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
    #masthead-ad,
    ytd-ad-slot-renderer,
    ytd-promoted-sparkles-web-renderer,
    ytd-promoted-sparkles-text-search-renderer,
    ytd-promoted-video-renderer,
    ytd-compact-promoted-video-renderer,
    ytd-in-feed-ad-layout-renderer,
    ytd-banner-promo-renderer,
    ytd-statement-banner-renderer,
    ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"],
    ytm-promoted-sparkles-web-renderer,
    ytm-promoted-sparkles-text-search-renderer,
    ytm-promoted-video-renderer,
    ytm-companion-ad-renderer,
    ytm-companion-slot,
    ytm-statement-banner-renderer,
    ytm-in-feed-ad-layout-renderer,
    ytm-rich-item-renderer:has(ytm-ad-slot-renderer),
    ytm-ad-slot-renderer,
    ad-slot-renderer,
    .ytp-ad-overlay-container,
    .ytp-ad-message-container,
    .ytp-ad-image-overlay,
    .ytp-ad-player-overlay-layout,
    .ytp-featured-product,
    ytd-enforcement-message-view-model,
    ytm-enforcement-message-view-model {
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
    const root = document.head || document.documentElement;
    if (!root) return;
    const style = document.createElement('style');
    style.id = 'heaven-shield-css';
    style.textContent = adCss;
    root.appendChild(style);
  }
  ensureStyle();

  // 5. Remove invisible high-z-index click-jacking divs placed over video players
  function neutralizeClickjackOverlays() {
    try {
      const candidates = document.querySelectorAll('body > div, body > a');
      const vw = window.innerWidth || 360;
      const vh = window.innerHeight || 640;
      for (let i = 0; i < candidates.length && i < 40; i++) {
        const el = candidates[i];
        if (el.id && el.id.startsWith('heaven-')) continue;
        if (el.childElementCount > 3) continue;
        if (el.querySelector && el.querySelector('video, input, button, nav, main, header')) continue;
        const cs = window.getComputedStyle(el);
        if (cs.position !== 'fixed' && cs.position !== 'absolute') continue;
        const z = parseInt(cs.zIndex || '0', 10);
        if (z >= 9999) {
          const r = el.getBoundingClientRect();
          const coversScreen = r.width >= vw * 0.7 && r.height >= vh * 0.55;
          const isInvisible = parseFloat(cs.opacity || '1') < 0.15 ||
            ((cs.backgroundColor === 'rgba(0, 0, 0, 0)' || cs.backgroundColor === 'transparent') &&
             !(el.textContent || '').trim());
          if (coversScreen && isInvisible) {
            el.remove();
            notifyShield('clickjack-overlay');
          }
        }
      }
    } catch (_) {}
  }

  // 6. Sweep Google Vignette + YouTube pre-roll / mid-roll ads (debounced for 60fps smooth scrolling!)
  function sweepAds() {
    ensureStyle();
    neutralizeClickjackOverlays();
    try {
      if (location.hash === '#google_vignette') {
        history.replaceState(null, '', location.pathname + location.search);
      }
      if (document.documentElement && document.documentElement.classList.contains('google-vignette-active')) {
        document.documentElement.classList.remove('google-vignette-active');
        if (document.body) document.body.style.removeProperty('overflow');
      }
      const host = (location.hostname || '').toLowerCase();
      if (host.includes('google.')) {
        const anchors = document.querySelectorAll('a[ping], a[data-ping-url], a[href^="/url?"]');
        for (let i = 0; i < anchors.length; i++) {
          const a = anchors[i];
          if (a.hasAttribute('ping')) a.removeAttribute('ping');
          if (a.hasAttribute('data-ping-url')) a.removeAttribute('data-ping-url');
          if (a.hasAttribute('onmousedown')) a.removeAttribute('onmousedown');
          const href = a.getAttribute('href') || '';
          if (href.startsWith('/url?') || href.includes('google.com/url?')) {
            try {
              const u = new URL(href, location.origin);
              const target = u.searchParams.get('q') || u.searchParams.get('url');
              if (target && (target.startsWith('https://') || target.startsWith('http://'))) {
                a.setAttribute('href', target);
              }
            } catch (_) {}
          }
        }
      }
      if (host.includes('youtube.com')) {
        try {
          if (window.ytInitialPlayerResponse && typeof window.ytInitialPlayerResponse === 'object') {
            delete window.ytInitialPlayerResponse.adPlacements;
            delete window.ytInitialPlayerResponse.playerAds;
            delete window.ytInitialPlayerResponse.adSlots;
          }
        } catch (_) {}
        const skipSelectors = [
          '.ytp-skip-ad-button',
          '.ytp-ad-skip-button',
          '.ytp-ad-skip-button-modern',
          '.ytp-ad-skip-button-slot button',
          '.ytp-ad-overlay-close-button',
          '.videoAdUiSkipButton'
        ];
        for (const sel of skipSelectors) {
          const btn = document.querySelector(sel);
          if (btn) {
            btn.click();
            notifyShield('youtube-ad');
          }
        }
        const adPlayer = document.querySelector('.html5-video-player.ad-showing video, .html5-video-player.ad-interrupting video, #movie_player.ad-showing video');
        if (adPlayer) {
          if (!adPlayer.muted) {
            adPlayer.muted = true;
            adPlayer.__hbMutedAd = true;
          }
          adPlayer.playbackRate = 16;
          if (isFinite(adPlayer.duration) && adPlayer.duration > 0.15 && (adPlayer.duration - adPlayer.currentTime) > 0.15) {
            adPlayer.currentTime = adPlayer.duration;
            notifyShield('youtube-ad');
          }
        } else {
          const normalVid = document.querySelector('video');
          if (normalVid && normalVid.__hbMutedAd) {
            normalVid.muted = false;
            normalVid.__hbMutedAd = false;
            if (normalVid.playbackRate === 16) normalVid.playbackRate = 1;
          }
        }
      }
    } catch (_) {}
  }

  sweepAds();
  let sweepScheduled = false;
  const observer = new MutationObserver(() => {
    if (sweepScheduled) return;
    sweepScheduled = true;
    setTimeout(() => {
      sweepScheduled = false;
      sweepAds();
    }, 180);
  });
  if (document.documentElement) {
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }
})();
''';
  }
}
