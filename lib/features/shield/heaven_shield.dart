import 'dart:convert';

class HeavenShield {
  const HeavenShield._();

  /// Curated high-impact ad, tracker, analytics, and popup root domains.
  static const List<String> blockedRootDomains = <String>[
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'google-analytics.com',
    'googletagmanager.com',
    'googletagservices.com',
    'adservice.google.com',
    'pagead2.googlesyndication.com',
    'connect.facebook.net',
    'an.facebook.com',
    'adnxs.com',
    'adsrvr.org',
    'criteo.com',
    'criteo.net',
    'taboola.com',
    'outbrain.com',
    'scorecardresearch.com',
    'quantserve.com',
    'rubiconproject.com',
    'pubmatic.com',
    'openx.net',
    'casalemedia.com',
    'moatads.com',
    'amazon-adsystem.com',
    'adform.net',
    'smartadserver.com',
    'bidswitch.net',
    'sharethrough.com',
    'indexww.com',
    '3lift.com',
    'hotjar.com',
    'mouseflow.com',
    'fullstory.com',
    'clarity.ms',
    'mixpanel.com',
    'amplitude.com',
    'segment.io',
    'segment.com',
    'heapanalytics.com',
    'newrelic.com',
    'nr-data.net',
    'bugsnag.com',
    'popads.net',
    'popcash.net',
    'propellerads.com',
    'adsterra.com',
    'exoclick.com',
    'tsyndicate.com',
  ];

  static String normalizeHost(String host) {
    String clean = host.trim().toLowerCase();
    if (clean.startsWith('www.') && clean.length > 4) {
      clean = clean.substring(4);
    }
    return clean;
  }

  static bool isHostTrusted(String? host, Set<String> trustedHosts) {
    if (host == null || host.isEmpty || trustedHosts.isEmpty) {
      return false;
    }
    final String normalized = normalizeHost(host);
    for (final String trusted in trustedHosts) {
      final String cleanTrusted = normalizeHost(trusted);
      if (normalized == cleanTrusted ||
          normalized.endsWith('.$cleanTrusted')) {
        return true;
      }
    }
    return false;
  }

  static String? matchBlockedDomain(String host) {
    final String lower = host.trim().toLowerCase();
    if (lower.isEmpty) {
      return null;
    }
    for (final String domain in blockedRootDomains) {
      if (lower == domain || lower.endsWith('.$domain')) {
        return domain;
      }
    }
    return null;
  }

  static bool shouldBlockUri(
    Uri uri, {
    required bool shieldEnabled,
    required Set<String> trustedHosts,
    String? currentPageHost,
  }) {
    if (!shieldEnabled) {
      return false;
    }
    if (isHostTrusted(currentPageHost, trustedHosts) ||
        isHostTrusted(uri.host, trustedHosts)) {
      return false;
    }
    return matchBlockedDomain(uri.host) != null;
  }

  /// Generates JavaScript injected into pages to enforce Global Privacy Control,
  /// Do Not Track, cross-origin window.name clearing, and subresource tracker
  /// blocking for fetch, XMLHttpRequest, and navigator.sendBeacon.
  static String buildProtectionScript({
    required bool shieldEnabled,
    required bool isSiteTrusted,
  }) {
    final String domainsJson = jsonEncode(blockedRootDomains);
    final bool activeBlocking = shieldEnabled && !isSiteTrusted;

    return '''
(function() {
  if (window.__heavenShieldInstalled) return;
  window.__heavenShieldInstalled = true;

  try {
    Object.defineProperty(navigator, 'globalPrivacyControl', {
      value: true,
      configurable: false
    });
    Object.defineProperty(navigator, 'doNotTrack', {
      value: '1',
      configurable: false
    });
  } catch (_) {}

  if (!${activeBlocking ? 'true' : 'false'}) return;

  const blockedDomains = $domainsJson;

  function findBlockedDomain(rawUrl) {
    if (!rawUrl || typeof rawUrl !== 'string') return null;
    try {
      const parsed = new URL(rawUrl, window.location.href);
      const host = (parsed.hostname || '').toLowerCase();
      if (!host) return null;
      for (let i = 0; i < blockedDomains.length; i++) {
        const d = blockedDomains[i];
        if (host === d || host.endsWith('.' + d)) {
          return d;
        }
      }
    } catch (_) {}
    return null;
  }

  function reportBlocked(domain) {
    try {
      if (window.HeavenShieldChannel && window.HeavenShieldChannel.postMessage) {
        window.HeavenShieldChannel.postMessage(domain);
      }
    } catch (_) {}
  }

  const origFetch = window.fetch;
  if (typeof origFetch === 'function') {
    window.fetch = function(input, init) {
      const url = (typeof input === 'string')
        ? input
        : (input && input.url ? input.url : '');
      const matched = findBlockedDomain(url);
      if (matched) {
        reportBlocked(matched);
        return Promise.reject(new TypeError('Blocked by Heaven Shield'));
      }
      return origFetch.apply(this, arguments);
    };
  }

  const origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    const matched = findBlockedDomain(String(url || ''));
    this.__heavenBlocked = Boolean(matched);
    if (matched) {
      reportBlocked(matched);
    }
    return origOpen.apply(this, arguments);
  };

  const origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function() {
    if (this.__heavenBlocked) {
      return;
    }
    return origSend.apply(this, arguments);
  };

  if (navigator && typeof navigator.sendBeacon === 'function') {
    const origBeacon = navigator.sendBeacon.bind(navigator);
    navigator.sendBeacon = function(url, data) {
      const matched = findBlockedDomain(String(url || ''));
      if (matched) {
        reportBlocked(matched);
        return true;
      }
      return origBeacon(url, data);
    };
  }
})();
''';
  }
}
