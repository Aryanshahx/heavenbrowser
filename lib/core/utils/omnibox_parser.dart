enum SearchEngine {
  heaven(
    label: 'Heaven Search (Google Engine)',
    shortLabel: 'Heaven',
    homeUrl: 'heaven://search',
    queryPrefix: 'heaven://search?q=',
  ),
  google(
    label: 'Google Search',
    shortLabel: 'Google',
    homeUrl: 'https://www.google.com',
    queryPrefix: 'https://www.google.com/search?safe=off&q=',
  ),
  heavenLite(
    label: 'Heaven Lite (Multi-Source)',
    shortLabel: 'Heaven Lite',
    homeUrl: 'heaven://lite',
    queryPrefix: 'heaven://lite?q=',
  ),
  duckDuckGo(
    label: 'DuckDuckGo',
    shortLabel: 'DDG',
    homeUrl: 'https://duckduckgo.com',
    queryPrefix: 'https://duckduckgo.com/?kp=-2&q=',
  ),
  brave(
    label: 'Brave Search',
    shortLabel: 'Brave',
    homeUrl: 'https://search.brave.com',
    queryPrefix: 'https://search.brave.com/search?q=',
  ),
  startpage(
    label: 'Startpage',
    shortLabel: 'Startpage',
    homeUrl: 'https://www.startpage.com',
    queryPrefix: 'https://www.startpage.com/sp/search?query=',
  );

  const SearchEngine({
    required this.label,
    required this.shortLabel,
    required this.homeUrl,
    required this.queryPrefix,
  });

  final String label;
  final String shortLabel;
  final String homeUrl;
  final String queryPrefix;

  bool get isNativeHeaven =>
      this == SearchEngine.heaven || this == SearchEngine.heavenLite;

  String buildSearchUrl(String rawQuery) {
    return '$queryPrefix${Uri.encodeQueryComponent(rawQuery.trim())}';
  }

  static SearchEngine fromName(String? value) {
    for (final SearchEngine engine in SearchEngine.values) {
      if (engine.name == value) {
        return engine;
      }
    }
    return SearchEngine.heaven;
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

  static bool isHeavenSearchUrl(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    final Uri? uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'heaven' &&
        (uri.host == 'search' || uri.host == 'lite');
  }

  static bool isHeavenLiteUrl(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    final Uri? uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'heaven' && uri.host == 'lite';
  }

  static String extractHeavenQuery(String? url) {
    if (url == null || url.isEmpty) {
      return '';
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'heaven') {
      return '';
    }
    return (uri.queryParameters['q'] ?? '').trim();
  }

  /// Extracts the search query if [url] is a Google Search results URL.
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

  /// Builds a clean, fast, unrestricted Google Search Engine URI.
  static Uri buildGoogleEngineUri(String query) {
    return Uri.https('www.google.com', '/search', <String, String>{
      'q': query.trim(),
      'safe': 'off',
      'pws': '0',
    });
  }

  /// Unwraps `https://www.google.com/url?q=https://...` tracking redirects to direct URLs.
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

  static Uri resolveInput(
    String rawInput, {
    required SearchEngine searchEngine,
    required bool httpsUpgrade,
  }) {
    final String input = rawInput.trim();
    if (input.isEmpty) {
      return Uri.parse(searchEngine.homeUrl);
    }

    if (input == 'about:blank' || input.startsWith('heaven://')) {
      return Uri.parse(input);
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
    if (isHeavenSearchUrl(url)) {
      final String q = extractHeavenQuery(url);
      return q.isEmpty ? 'Heaven Search' : 'Heaven Search • $q';
    }
    final String googleQ = extractGoogleSearchQuery(url);
    if (googleQ.isNotEmpty) {
      return 'Google • $googleQ';
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return url;
    }
    String host = uri.host;
    if (host.startsWith('www.') && host.length > 4) {
      host = host.substring(4);
    }
    return host;
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
