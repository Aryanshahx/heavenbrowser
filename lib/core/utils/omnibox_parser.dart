enum SearchEngine {
  google(
    label: 'Google Search',
    shortLabel: 'Google',
    badge: 'G',
    homeUrl: 'https://www.google.com',
    queryPrefix: 'https://www.google.com/search?q=',
  ),
  duckDuckGo(
    label: 'DuckDuckGo',
    shortLabel: 'DDG',
    badge: 'D',
    homeUrl: 'https://duckduckgo.com',
    queryPrefix: 'https://duckduckgo.com/?kp=-2&q=',
  ),
  brave(
    label: 'Brave Search',
    shortLabel: 'Brave',
    badge: 'Br',
    homeUrl: 'https://search.brave.com',
    queryPrefix: 'https://search.brave.com/search?q=',
  ),
  bing(
    label: 'Bing Search',
    shortLabel: 'Bing',
    badge: 'Bi',
    homeUrl: 'https://www.bing.com',
    queryPrefix: 'https://www.bing.com/search?adlt=off&q=',
  ),
  startpage(
    label: 'Startpage',
    shortLabel: 'Startpage',
    badge: 'S',
    homeUrl: 'https://www.startpage.com',
    queryPrefix: 'https://www.startpage.com/sp/search?query=',
  );

  const SearchEngine({
    required this.label,
    required this.shortLabel,
    required this.badge,
    required this.homeUrl,
    required this.queryPrefix,
  });

  final String label;
  final String shortLabel;
  final String badge;
  final String homeUrl;
  final String queryPrefix;

  String buildSearchUrl(String rawQuery) {
    return '$queryPrefix${Uri.encodeQueryComponent(rawQuery.trim())}';
  }

  Uri buildSearchUri(String rawQuery) {
    final String q = rawQuery.trim();
    return Uri.parse(q.isEmpty ? homeUrl : buildSearchUrl(q));
  }

  static SearchEngine fromName(String? value) {
    for (final SearchEngine engine in SearchEngine.values) {
      if (engine.name == value) {
        return engine;
      }
    }
    return SearchEngine.google;
  }
}

class OmniboxParser {
  const OmniboxParser._();

  static final RegExp _domainLikePattern = RegExp(
    r'^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(:\d+)?(\/.*)?$',
  );

  static final RegExp _ipv4Pattern = RegExp(
    r'^(\d{1,3}\.){3}\d{1,3}(:\d+)?(\/.*)?$',
  );

  static final RegExp _localhostPattern = RegExp(
    r'^localhost(:\d+)?(\/.*)?$',
    caseSensitive: false,
  );

  static bool isLegacyHeavenUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.trim().toLowerCase().startsWith('heaven://');
  }

  static String extractLegacyHeavenQuery(String? url) {
    if (url == null || url.isEmpty) return '';
    final Uri? parsed = Uri.tryParse(url.trim());
    return (parsed?.queryParameters['q'] ?? '').trim();
  }

  static bool looksLikeDirectDestination(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.contains(' ')) {
      return false;
    }
    return trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        _domainLikePattern.hasMatch(trimmed) ||
        _ipv4Pattern.hasMatch(trimmed) ||
        _localhostPattern.hasMatch(trimmed);
  }

  static String extractGoogleSearchQuery(String? url) {
    if (url == null || url.isEmpty) {
      return '';
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return '';
    }
    final String host = uri.host.toLowerCase();
    final bool isGoogleHost =
        host == 'www.google.com' ||
        host == 'google.com' ||
        host == 'www.google.co.in' ||
        host == 'google.co.in';
    if (!isGoogleHost || uri.path != '/search') {
      return '';
    }
    return (uri.queryParameters['q'] ?? '').trim();
  }

  static String extractAnySearchQuery(String? url) {
    if (url == null || url.isEmpty) {
      return '';
    }
    final String googleQ = extractGoogleSearchQuery(url);
    if (googleQ.isNotEmpty) {
      return googleQ;
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return '';
    }
    final String host = uri.host.toLowerCase();
    if (host.endsWith('duckduckgo.com') ||
        host.endsWith('search.brave.com') ||
        (host.endsWith('bing.com') && uri.path == '/search')) {
      return (uri.queryParameters['q'] ?? '').trim();
    }
    if (host.endsWith('startpage.com')) {
      return (uri.queryParameters['query'] ?? uri.queryParameters['q'] ?? '')
          .trim();
    }
    return '';
  }

  static Uri? unwrapGoogleRedirectUri(Uri uri) {
    final String host = uri.host.toLowerCase();
    if ((host == 'www.google.com' ||
            host == 'google.com' ||
            host == 'www.google.co.in') &&
        uri.path == '/url') {
      final String? target =
          uri.queryParameters['q'] ?? uri.queryParameters['url'];
      if (target != null &&
          (target.startsWith('https://') || target.startsWith('http://'))) {
        return Uri.tryParse(target);
      }
    }
    return null;
  }

  static bool looksLikeSearchQuery(
    String rawInput, {
    required SearchEngine searchEngine,
  }) {
    final String input = rawInput.trim();
    if (input.isEmpty) return false;
    if (input == 'about:blank' ||
        input.startsWith('http://') ||
        input.startsWith('https://')) {
      return false;
    }
    if (input.contains(' ')) return true;
    if (_localhostPattern.hasMatch(input) ||
        _ipv4Pattern.hasMatch(input) ||
        _domainLikePattern.hasMatch(input)) {
      return false;
    }
    return true;
  }

  static Uri resolveInput(
    String rawInput, {
    required SearchEngine searchEngine,
    required bool httpsUpgrade,
  }) {
    final String input = rawInput.trim();
    if (input.isEmpty) {
      return Uri.parse(searchEngine.homeUrl);
    }

    if (input == 'about:blank') {
      return Uri.parse(input);
    }

    // Legacy heaven://search URLs migrate automatically to active search engine (Google default)
    if (input.startsWith('heaven://')) {
      final Uri? legacy = Uri.tryParse(input);
      final String q = (legacy?.queryParameters['q'] ?? '').trim();
      return Uri.parse(
        q.isEmpty ? searchEngine.homeUrl : searchEngine.buildSearchUrl(q),
      );
    }

    if (input.startsWith('http://') || input.startsWith('https://')) {
      final Uri? parsed = Uri.tryParse(input);
      if (parsed != null && parsed.host.isNotEmpty) {
        if (httpsUpgrade &&
            parsed.scheme == 'http' &&
            !isLocalOrPrivateHost(parsed.host)) {
          return parsed.replace(scheme: 'https');
        }
        return parsed;
      }
    }

    if (input.contains(' ')) {
      return Uri.parse(searchEngine.buildSearchUrl(input));
    }

    if (_localhostPattern.hasMatch(input) || _ipv4Pattern.hasMatch(input)) {
      return Uri.parse('http://$input');
    }

    if (_domainLikePattern.hasMatch(input)) {
      return Uri.parse('https://$input');
    }

    return Uri.parse(searchEngine.buildSearchUrl(input));
  }

  static bool isLocalOrPrivateHost(String host) {
    final String lower = host.toLowerCase();
    if (lower == 'localhost' || lower == '127.0.0.1' || lower == '::1') {
      return true;
    }
    if (lower.startsWith('192.168.') || lower.startsWith('10.')) {
      return true;
    }
    if (lower.startsWith('172.')) {
      final List<String> parts = lower.split('.');
      if (parts.length >= 2) {
        final int? second = int.tryParse(parts[1]);
        if (second != null && second >= 16 && second <= 31) {
          return true;
        }
      }
    }
    return false;
  }

  static String cleanDomain(String? urlOrHost) {
    if (urlOrHost == null || urlOrHost.isEmpty) {
      return '';
    }
    final Uri? parsed = Uri.tryParse(urlOrHost);
    String host = (parsed != null && parsed.host.isNotEmpty)
        ? parsed.host
        : urlOrHost;
    host = host.trim().toLowerCase();
    if (host.startsWith('www.') && host.length > 4) {
      host = host.substring(4);
    } else if (host.startsWith('m.') && host.length > 2) {
      host = host.substring(2);
    }
    return host;
  }

  static String formatDisplayUrl(String? url) {
    if (url == null || url.isEmpty) {
      return '';
    }
    final String googleQ = extractGoogleSearchQuery(url);
    if (googleQ.isNotEmpty) {
      return 'Google • $googleQ';
    }
    final String anyQ = extractAnySearchQuery(url);
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return url;
    }
    String host = uri.host;
    if (host.startsWith('www.') && host.length > 4) {
      host = host.substring(4);
    }
    if (anyQ.isNotEmpty) {
      return '${friendlySiteTitleFromDomain(host)} • $anyQ';
    }
    return host;
  }

  static String formatGoogleBreadcrumb(String rawUrl) {
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.host.isEmpty) {
      return rawUrl;
    }
    final String base = '${uri.scheme}://${uri.host}';
    final List<String> segments = uri.pathSegments
        .where((String s) => s.trim().isNotEmpty)
        .take(3)
        .map((String s) {
          final String clean = Uri.decodeComponent(s);
          return clean.length > 20 ? '${clean.substring(0, 20)}…' : clean;
        })
        .toList();
    if (segments.isEmpty) {
      return base;
    }
    return '$base › ${segments.join(' › ')}';
  }

  static String friendlySiteTitleFromDomain(String domain) {
    final String clean = cleanDomain(domain);
    if (clean.isEmpty) {
      return 'Website';
    }
    final String firstPart = clean.split('.').first;
    if (firstPart.isEmpty) {
      return clean;
    }
    return firstPart[0].toUpperCase() + firstPart.substring(1);
  }
}
