enum SearchEngine {
  duckDuckGo(
    label: 'DuckDuckGo',
    shortLabel: 'DDG',
    homeUrl: 'https://duckduckgo.com',
    queryPrefix: 'https://duckduckgo.com/?q=',
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
  ),
  google(
    label: 'Google',
    shortLabel: 'Google',
    homeUrl: 'https://www.google.com',
    queryPrefix: 'https://www.google.com/search?q=',
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

  String buildSearchUrl(String rawQuery) {
    return '$queryPrefix${Uri.encodeQueryComponent(rawQuery.trim())}';
  }

  static SearchEngine fromName(String? value) {
    for (final SearchEngine engine in SearchEngine.values) {
      if (engine.name == value) {
        return engine;
      }
    }
    return SearchEngine.duckDuckGo;
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
      return Uri.parse('about:blank');
    }

    // Explicit scheme provided (http:// or https://)
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

    // Contains spaces -> definitely a search query
    if (input.contains(' ')) {
      return Uri.parse(searchEngine.buildSearchUrl(input));
    }

    // Localhost or IPv4 address -> default to http:// so local dev servers work
    if (_localhostPattern.hasMatch(input) || _ipv4Pattern.hasMatch(input)) {
      return Uri.parse('http://$input');
    }

    // Bare domain like "github.com" or "wikipedia.org/wiki/Flutter"
    if (_domainLikePattern.hasMatch(input)) {
      final String scheme = httpsUpgrade ? 'https' : 'https';
      return Uri.parse('$scheme://$input');
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

  static String formatDisplayUrl(String? url) {
    if (url == null || url.isEmpty) {
      return '';
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
}
