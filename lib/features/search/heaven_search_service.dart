import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/utils/omnibox_parser.dart';

enum HeavenSearchTab {
  web('All Web'),
  knowledge('Knowledge'),
  tech('Tech & Dev');

  const HeavenSearchTab(this.label);
  final String label;
}

class HeavenSearchResult {
  const HeavenSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    required this.sourceLabel,
    this.metaBadge,
  });

  final String title;
  final String url;
  final String snippet;
  final String sourceLabel;
  final String? metaBadge;

  String get displayDomain => OmniboxParser.cleanDomain(url);
}

class HeavenKnowledgeCard {
  const HeavenKnowledgeCard({
    required this.heading,
    required this.summary,
    required this.sourceUrl,
    required this.sourceName,
    this.imageUrl,
  });

  final String heading;
  final String summary;
  final String sourceUrl;
  final String sourceName;
  final String? imageUrl;
}

class HeavenSearchResponse {
  const HeavenSearchResponse({
    required this.query,
    required this.elapsedMs,
    required this.webResults,
    required this.knowledgeResults,
    required this.techResults,
    this.instantMathResult,
    this.knowledgeCard,
  });

  final String query;
  final int elapsedMs;
  final List<HeavenSearchResult> webResults;
  final List<HeavenSearchResult> knowledgeResults;
  final List<HeavenSearchResult> techResults;
  final String? instantMathResult;
  final HeavenKnowledgeCard? knowledgeCard;
}

class HeavenMathEvaluator {
  HeavenMathEvaluator(this._src);

  final String _src;
  int _pos = 0;

  static final RegExp _candidatePattern = RegExp(
    r'^[\d\s\+\-\*\/\%\^\(\)\.]+$',
  );
  static final RegExp _hasOperatorPattern = RegExp(r'[\+\-\*\/\%\^]');
  static final RegExp _hasDigitPattern = RegExp(r'\d');

  static String? tryEvaluate(String rawQuery) {
    final String trimmed = rawQuery.trim();
    if (trimmed.length < 3 ||
        !_candidatePattern.hasMatch(trimmed) ||
        !_hasOperatorPattern.hasMatch(trimmed) ||
        !_hasDigitPattern.hasMatch(trimmed)) {
      return null;
    }
    // Avoid treating simple dates like 2026-10-22 as math unless spaced or parenthesized
    if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$').hasMatch(trimmed)) {
      return null;
    }

    try {
      final HeavenMathEvaluator evaluator = HeavenMathEvaluator(trimmed);
      final double value = evaluator._parseExpression();
      evaluator._skipSpaces();
      if (evaluator._pos != trimmed.length || value.isNaN || value.isInfinite) {
        return null;
      }
      if ((value - value.roundToDouble()).abs() < 1e-9 && value.abs() < 1e15) {
        return value.round().toString();
      }
      return value
          .toStringAsFixed(6)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    } on FormatException {
      return null;
    }
  }

  void _skipSpaces() {
    while (_pos < _src.length && _src.codeUnitAt(_pos) == 32) {
      _pos++;
    }
  }

  double _parseExpression() {
    double x = _parseTerm();
    while (true) {
      _skipSpaces();
      if (_pos < _src.length && _src[_pos] == '+') {
        _pos++;
        x += _parseTerm();
      } else if (_pos < _src.length && _src[_pos] == '-') {
        _pos++;
        x -= _parseTerm();
      } else {
        return x;
      }
    }
  }

  double _parseTerm() {
    double x = _parsePower();
    while (true) {
      _skipSpaces();
      if (_pos < _src.length && _src[_pos] == '*') {
        _pos++;
        x *= _parsePower();
      } else if (_pos < _src.length && _src[_pos] == '/') {
        _pos++;
        final double denom = _parsePower();
        if (denom == 0) {
          throw const FormatException('Division by zero');
        }
        x /= denom;
      } else if (_pos < _src.length && _src[_pos] == '%') {
        _pos++;
        final double denom = _parsePower();
        if (denom == 0) {
          throw const FormatException('Modulo by zero');
        }
        x %= denom;
      } else {
        return x;
      }
    }
  }

  double _parsePower() {
    final double base = _parseFactor();
    _skipSpaces();
    if (_pos < _src.length && _src[_pos] == '^') {
      _pos++;
      final double exp = _parsePower();
      return math.pow(base, exp).toDouble();
    }
    return base;
  }

  double _parseFactor() {
    _skipSpaces();
    if (_pos < _src.length && _src[_pos] == '+') {
      _pos++;
      return _parseFactor();
    }
    if (_pos < _src.length && _src[_pos] == '-') {
      _pos++;
      return -_parseFactor();
    }
    if (_pos < _src.length && _src[_pos] == '(') {
      _pos++;
      final double inside = _parseExpression();
      _skipSpaces();
      if (_pos >= _src.length || _src[_pos] != ')') {
        throw const FormatException('Missing closing parenthesis');
      }
      _pos++;
      return inside;
    }

    final int start = _pos;
    while (_pos < _src.length &&
        ((_src.codeUnitAt(_pos) >= 48 && _src.codeUnitAt(_pos) <= 57) ||
            _src[_pos] == '.')) {
      _pos++;
    }
    if (start == _pos) {
      throw const FormatException('Expected number');
    }
    return double.parse(_src.substring(start, _pos));
  }
}

class HeavenSearchService {
  HeavenSearchService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const Map<String, String> _browserHeaders = <String, String>{
    'User-Agent': AppConstants.desktopUserAgent,
    'Accept-Language': 'en-US,en;q=0.9',
  };

  Future<HeavenSearchResponse> search(String rawQuery) async {
    final String query = rawQuery.trim();
    final Stopwatch stopwatch = Stopwatch()..start();
    final String? mathAnswer = HeavenMathEvaluator.tryEvaluate(query);

    final (
      List<HeavenSearchResult> web,
      HeavenKnowledgeCard? ddgCard,
      List<HeavenSearchResult> wiki,
      List<HeavenSearchResult> tech,
    ) = await (
      _fetchOrganicWebResults(query),
      _fetchKnowledgeCard(query),
      _fetchWikipediaResults(query),
      _fetchTechResults(query),
    ).wait;

    HeavenKnowledgeCard? card = ddgCard;
    if (card == null && wiki.isNotEmpty) {
      card = await _fetchWikipediaSummaryCard(wiki.first.title);
    }

    // Fallback synthesis: if organic HTML endpoint returned empty on any network,
    // blend verified Wikipedia + Tech results so Heaven Search always delivers real links.
    final List<HeavenSearchResult> mergedWeb = web.isNotEmpty
        ? web
        : <HeavenSearchResult>[...wiki, ...tech];

    stopwatch.stop();
    return HeavenSearchResponse(
      query: query,
      elapsedMs: stopwatch.elapsedMilliseconds,
      webResults: mergedWeb,
      knowledgeResults: wiki,
      techResults: tech,
      instantMathResult: mathAnswer,
      knowledgeCard: card,
    );
  }

  Future<List<String>> fetchSuggestions(String rawPrefix) async {
    final String q = rawPrefix.trim();
    if (q.length < 2) {
      return const <String>[];
    }
    try {
      final Uri uri = Uri.parse(
        'https://duckduckgo.com/ac/?q=${Uri.encodeQueryComponent(q)}&type=list',
      );
      final http.Response res = await _client
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) {
        return const <String>[];
      }
      final Object? decoded = jsonDecode(res.body);
      if (decoded is List<Object?> &&
          decoded.length >= 2 &&
          decoded[1] is List<Object?>) {
        final List<Object?> rawItems = decoded[1] as List<Object?>;
        return rawItems
            .map((Object? e) => e?.toString().trim() ?? '')
            .where((String s) => s.isNotEmpty)
            .take(6)
            .toList(growable: false);
      }
    } catch (_) {
      // Fail silently on offline/autocomplete timeout.
    }
    return const <String>[];
  }

  Future<List<HeavenSearchResult>> _fetchOrganicWebResults(String query) async {
    try {
      final Uri uri = Uri.parse(
        'https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(query)}',
      );
      final http.Response res = await _client
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 7));
      if (res.statusCode != 200 || res.body.isEmpty) {
        return const <HeavenSearchResult>[];
      }
      return parseOrganicHtmlResults(res.body);
    } catch (_) {
      return const <HeavenSearchResult>[];
    }
  }

  static List<HeavenSearchResult> parseOrganicHtmlResults(String html) {
    final List<HeavenSearchResult> results = <HeavenSearchResult>[];
    final Set<String> seenUrls = <String>{};

    final RegExp linkPattern = RegExp(
      r'<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>',
      caseSensitive: false,
    );
    final RegExp snippetPattern = RegExp(
      r'class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)<\/(?:a|div)>',
      caseSensitive: false,
    );

    final List<RegExpMatch> linkMatches = linkPattern.allMatches(html).toList();
    for (int i = 0; i < linkMatches.length; i++) {
      final RegExpMatch match = linkMatches[i];
      final String rawHref = decodeHtmlEntities(match.group(1) ?? '');
      // Skip sponsored redirect links
      if (rawHref.contains('ad_domain=') || rawHref.contains('/y.js')) {
        continue;
      }

      final String cleanUrl = unwrapRedirectUrl(rawHref);
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        continue;
      }
      // Strip sponsored ad links even when wrapped inside uddg=
      if (cleanUrl.contains('ad_domain=') ||
          cleanUrl.contains('/y.js') ||
          cleanUrl.contains('bing.com/aclick')) {
        continue;
      }
      if (!seenUrls.add(cleanUrl)) {
        continue;
      }

      final String title = stripHtmlTags(match.group(2) ?? '').trim();
      if (title.isEmpty) {
        continue;
      }

      final int blockStart = match.end;
      final int blockEnd = (i + 1 < linkMatches.length)
          ? linkMatches[i + 1].start
          : html.length;
      final String blockSlice = html.substring(blockStart, blockEnd);
      final RegExpMatch? snippetMatch = snippetPattern.firstMatch(blockSlice);
      final String snippet = snippetMatch != null
          ? stripHtmlTags(snippetMatch.group(1) ?? '').trim()
          : '';

      results.add(
        HeavenSearchResult(
          title: title,
          url: cleanUrl,
          snippet: snippet.isEmpty
              ? OmniboxParser.cleanDomain(cleanUrl)
              : snippet,
          sourceLabel: OmniboxParser.cleanDomain(cleanUrl),
        ),
      );
      if (results.length >= 16) {
        break;
      }
    }
    return results;
  }

  static String unwrapRedirectUrl(String rawHref) {
    String href = rawHref.trim();
    if (href.startsWith('//')) {
      href = 'https:$href';
    }
    final Uri? parsed = Uri.tryParse(href);
    if (parsed != null) {
      final String? uddg = parsed.queryParameters['uddg'];
      if (uddg != null && uddg.isNotEmpty) {
        return uddg;
      }
    }
    return href;
  }

  Future<HeavenKnowledgeCard?> _fetchKnowledgeCard(String query) async {
    try {
      final Uri uri = Uri.parse(
        'https://api.duckduckgo.com/?q=${Uri.encodeQueryComponent(query)}'
        '&format=json&no_html=1&skip_disambig=1',
      );
      final http.Response res = await _client
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final Object? data = jsonDecode(res.body);
        if (data is Map<String, Object?>) {
          final String abstractText = (data['AbstractText']?.toString() ?? '')
              .trim();
          final String heading = (data['Heading']?.toString() ?? '').trim();
          final String abstractUrl = (data['AbstractURL']?.toString() ?? '')
              .trim();
          final String source =
              (data['AbstractSource']?.toString() ?? 'Knowledge Graph').trim();
          String? image = (data['Image']?.toString() ?? '').trim();
          if (image.isNotEmpty && image.startsWith('/')) {
            image = 'https://duckduckgo.com$image';
          }
          if (abstractText.isNotEmpty &&
              heading.isNotEmpty &&
              abstractUrl.isNotEmpty) {
            return HeavenKnowledgeCard(
              heading: heading,
              summary: abstractText,
              sourceUrl: abstractUrl,
              sourceName: source,
              imageUrl: (image.isEmpty) ? null : image,
            );
          }
        }
      }
    } catch (_) {
      // Ignore instant-answer errors.
    }
    return null;
  }

  Future<HeavenKnowledgeCard?> _fetchWikipediaSummaryCard(String title) async {
    try {
      final String slug = Uri.encodeComponent(title.replaceAll(' ', '_'));
      final Uri uri = Uri.parse(
        'https://en.wikipedia.org/api/rest_v1/page/summary/$slug',
      );
      final http.Response res = await _client
          .get(
            uri,
            headers: const <String, String>{
              'User-Agent':
                  'HeavenBrowser/0.0.1 (https://github.com/Aryanshahx/heavenbrowser)',
            },
          )
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final Object? data = jsonDecode(res.body);
        if (data is Map<String, Object?>) {
          final String extract = (data['extract']?.toString() ?? '').trim();
          final String pageTitle = (data['title']?.toString() ?? title).trim();
          String sourceUrl = 'https://en.wikipedia.org/wiki/$slug';
          final Object? contentUrls = data['content_urls'];
          if (contentUrls is Map<String, Object?>) {
            final Object? desktop = contentUrls['desktop'];
            if (desktop is Map<String, Object?> && desktop['page'] != null) {
              sourceUrl = desktop['page']!.toString();
            }
          }
          String? thumbUrl;
          final Object? thumb = data['thumbnail'];
          if (thumb is Map<String, Object?> && thumb['source'] != null) {
            thumbUrl = thumb['source']!.toString();
          }
          if (extract.length >= 40) {
            return HeavenKnowledgeCard(
              heading: pageTitle,
              summary: extract,
              sourceUrl: sourceUrl,
              sourceName: 'Wikipedia',
              imageUrl: thumbUrl,
            );
          }
        }
      }
    } catch (_) {
      // Ignore Wikipedia summary fallback errors.
    }
    return null;
  }

  Future<List<HeavenSearchResult>> _fetchWikipediaResults(String query) async {
    try {
      final Uri uri = Uri.parse(
        'https://en.wikipedia.org/w/api.php?action=query&list=search'
        '&srsearch=${Uri.encodeQueryComponent(query)}'
        '&utf8=1&format=json&srlimit=10',
      );
      final http.Response res = await _client
          .get(
            uri,
            headers: const <String, String>{
              'User-Agent':
                  'HeavenBrowser/0.0.1 (https://github.com/Aryanshahx/heavenbrowser)',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        return const <HeavenSearchResult>[];
      }
      final Object? decoded = jsonDecode(res.body);
      if (decoded is! Map<String, Object?>) {
        return const <HeavenSearchResult>[];
      }
      final Object? queryObj = decoded['query'];
      if (queryObj is! Map<String, Object?>) {
        return const <HeavenSearchResult>[];
      }
      final Object? searchItems = queryObj['search'];
      if (searchItems is! List<Object?>) {
        return const <HeavenSearchResult>[];
      }

      final List<HeavenSearchResult> items = <HeavenSearchResult>[];
      for (final Object? entry in searchItems) {
        if (entry is Map<String, Object?>) {
          final String title = (entry['title']?.toString() ?? '').trim();
          final String snippet = stripHtmlTags(
            entry['snippet']?.toString() ?? '',
          ).trim();
          if (title.isEmpty) continue;
          final String wikiSlug = Uri.encodeComponent(
            title.replaceAll(' ', '_'),
          );
          items.add(
            HeavenSearchResult(
              title: title,
              url: 'https://en.wikipedia.org/wiki/$wikiSlug',
              snippet: snippet.isEmpty ? 'Wikipedia Encyclopedia' : snippet,
              sourceLabel: 'en.wikipedia.org',
              metaBadge: 'Wikipedia',
            ),
          );
        }
      }
      return items;
    } catch (_) {
      return const <HeavenSearchResult>[];
    }
  }

  Future<List<HeavenSearchResult>> _fetchTechResults(String query) async {
    try {
      final Uri uri = Uri.parse(
        'https://hn.algolia.com/api/v1/search?query=${Uri.encodeQueryComponent(query)}'
        '&tags=story&hitsPerPage=12',
      );
      final http.Response res = await _client
          .get(uri)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        return const <HeavenSearchResult>[];
      }
      final Object? decoded = jsonDecode(res.body);
      if (decoded is! Map<String, Object?>) {
        return const <HeavenSearchResult>[];
      }
      final Object? hits = decoded['hits'];
      if (hits is! List<Object?>) {
        return const <HeavenSearchResult>[];
      }

      final List<HeavenSearchResult> items = <HeavenSearchResult>[];
      for (final Object? raw in hits) {
        if (raw is Map<String, Object?>) {
          final String title = (raw['title']?.toString() ?? '').trim();
          final String objectId = (raw['objectID']?.toString() ?? '').trim();
          String url = (raw['url']?.toString() ?? '').trim();
          if (url.isEmpty && objectId.isNotEmpty) {
            url = 'https://news.ycombinator.com/item?id=$objectId';
          }
          if (title.isEmpty || url.isEmpty) continue;
          final int points = (raw['points'] is num)
              ? (raw['points']! as num).toInt()
              : 0;
          final int comments = (raw['num_comments'] is num)
              ? (raw['num_comments']! as num).toInt()
              : 0;
          final String author = (raw['author']?.toString() ?? 'dev').trim();

          items.add(
            HeavenSearchResult(
              title: title,
              url: url,
              snippet:
                  'Shared by @$author • $points points • $comments comments on Hacker News',
              sourceLabel: OmniboxParser.cleanDomain(url),
              metaBadge: '$points pts',
            ),
          );
        }
      }
      return items;
    } catch (_) {
      return const <HeavenSearchResult>[];
    }
  }

  static String stripHtmlTags(String html) {
    final String withoutTags = html.replaceAll(RegExp(r'<[^>]*>'), '');
    return decodeHtmlEntities(withoutTags).replaceAll(RegExp(r'\s+'), ' ');
  }

  static String decodeHtmlEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (Match m) {
          final int? code = int.tryParse(m.group(1) ?? '');
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        });
  }
}
