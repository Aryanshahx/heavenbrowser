import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/utils/omnibox_parser.dart';

enum HeavenSearchTab {
  all('All'),
  images('Images'),
  videos('Videos'),
  news('News'),
  wiki('Wiki');

  const HeavenSearchTab(this.label);
  final String label;
}

enum HeavenTimeFilter {
  any('Any time', ''),
  day('Past 24h', 'd'),
  week('Past week', 'w'),
  month('Past month', 'm'),
  year('Past year', 'y');

  const HeavenTimeFilter(this.label, this.ddgCode);
  final String label;
  final String ddgCode;
}

enum HeavenRegionFilter {
  india('India', 'in-en', 'IN', 'en-IN'),
  global('Global', 'wt-wt', 'US', 'en-US'),
  us('United States', 'us-en', 'US', 'en-US'),
  uk('United Kingdom', 'uk-en', 'GB', 'en-GB');

  const HeavenRegionFilter(
    this.label,
    this.ddgLocale,
    this.countryCode,
    this.langCode,
  );
  final String label;
  final String ddgLocale;
  final String countryCode;
  final String langCode;
}

enum HeavenSafeFilter {
  moderate('Safe: Moderate', '-1'),
  strict('Safe: Strict', '1'),
  off('Safe: Off', '-2');

  const HeavenSafeFilter(this.label, this.ddgCode);
  final String label;
  final String ddgCode;
}

class HeavenSearchFilters {
  const HeavenSearchFilters({
    this.time = HeavenTimeFilter.any,
    this.region = HeavenRegionFilter.india,
    this.safe = HeavenSafeFilter.moderate,
  });

  final HeavenTimeFilter time;
  final HeavenRegionFilter region;
  final HeavenSafeFilter safe;

  HeavenSearchFilters copyWith({
    HeavenTimeFilter? time,
    HeavenRegionFilter? region,
    HeavenSafeFilter? safe,
  }) {
    return HeavenSearchFilters(
      time: time ?? this.time,
      region: region ?? this.region,
      safe: safe ?? this.safe,
    );
  }

  bool get hasActiveCustomFilter =>
      time != HeavenTimeFilter.any || safe != HeavenSafeFilter.moderate;
}

class HeavenSearchResult {
  const HeavenSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    required this.sourceLabel,
    this.metaBadge,
    this.thumbnailUrl,
  });

  final String title;
  final String url;
  final String snippet;
  final String sourceLabel;
  final String? metaBadge;
  final String? thumbnailUrl;

  String get displayDomain => OmniboxParser.cleanDomain(url);
}

class HeavenImageResult {
  const HeavenImageResult({
    required this.title,
    required this.thumbUrl,
    required this.fullUrl,
    required this.pageUrl,
  });

  final String title;
  final String thumbUrl;
  final String fullUrl;
  final String pageUrl;
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
    required this.imageResults,
    required this.videoResults,
    required this.newsResults,
    required this.wikiResults,
    this.instantMathResult,
    this.knowledgeCard,
  });

  final String query;
  final int elapsedMs;
  final List<HeavenSearchResult> webResults;
  final List<HeavenImageResult> imageResults;
  final List<HeavenSearchResult> videoResults;
  final List<HeavenSearchResult> newsResults;
  final List<HeavenSearchResult> wikiResults;
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

  Future<HeavenSearchResponse> search(
    String rawQuery, {
    HeavenSearchFilters filters = const HeavenSearchFilters(),
  }) async {
    final String query = rawQuery.trim();
    final Stopwatch stopwatch = Stopwatch()..start();
    final String? mathAnswer = HeavenMathEvaluator.tryEvaluate(query);

    final (
      List<HeavenSearchResult> web,
      List<HeavenImageResult> images,
      List<HeavenSearchResult> videos,
      List<HeavenSearchResult> news,
      List<HeavenSearchResult> wiki,
      HeavenKnowledgeCard? ddgCard,
    ) = await (
      _fetchOrganicWebResults(query, filters: filters),
      _fetchCommonsImages(query),
      _fetchVideoResults(query, filters: filters),
      _fetchGoogleNewsRss(query, filters: filters),
      _fetchWikipediaResults(query),
      _fetchKnowledgeCard(query),
    ).wait;

    HeavenKnowledgeCard? card = ddgCard;
    if (card == null && wiki.isNotEmpty) {
      card = await _fetchWikipediaSummaryCard(wiki.first.title);
    }

    final List<HeavenSearchResult> mergedWeb = web.isNotEmpty
        ? web
        : <HeavenSearchResult>[...wiki, ...news.take(6)];

    stopwatch.stop();
    return HeavenSearchResponse(
      query: query,
      elapsedMs: stopwatch.elapsedMilliseconds,
      webResults: mergedWeb,
      imageResults: images,
      videoResults: videos,
      newsResults: news,
      wikiResults: wiki,
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

  Future<List<HeavenSearchResult>> _fetchOrganicWebResults(
    String query, {
    required HeavenSearchFilters filters,
  }) async {
    try {
      final String dfPart = filters.time.ddgCode.isNotEmpty
          ? '&df=${filters.time.ddgCode}'
          : '';
      final Uri uri = Uri.parse(
        'https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(query)}'
        '&kl=${filters.region.ddgLocale}&kp=${filters.safe.ddgCode}$dfPart',
      );
      final http.Response res = await _client
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 7));
      if (res.statusCode != 200 || res.body.isEmpty) {
        return const <HeavenSearchResult>[];
      }
      return parseOrganicHtmlResults(res.body, maxItems: 20);
    } catch (_) {
      return const <HeavenSearchResult>[];
    }
  }

  Future<List<HeavenSearchResult>> _fetchVideoResults(
    String query, {
    required HeavenSearchFilters filters,
  }) async {
    try {
      final String videoQuery =
          '$query (site:youtube.com/watch OR site:vimeo.com OR site:dailymotion.com)';
      final String dfPart = filters.time.ddgCode.isNotEmpty
          ? '&df=${filters.time.ddgCode}'
          : '';
      final Uri uri = Uri.parse(
        'https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(videoQuery)}'
        '&kp=${filters.safe.ddgCode}$dfPart',
      );
      final http.Response res = await _client
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 7));
      if (res.statusCode != 200 || res.body.isEmpty) {
        return const <HeavenSearchResult>[];
      }
      final List<HeavenSearchResult> parsed = parseOrganicHtmlResults(
        res.body,
        maxItems: 14,
      );
      return parsed
          .map((HeavenSearchResult r) {
            final String? ytId = extractYouTubeVideoId(r.url);
            return HeavenSearchResult(
              title: r.title.replaceAll(' - YouTube', '').trim(),
              url: r.url,
              snippet: r.snippet,
              sourceLabel: r.sourceLabel,
              metaBadge: 'Video',
              thumbnailUrl: ytId != null
                  ? 'https://i.ytimg.com/vi/$ytId/hqdefault.jpg'
                  : null,
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const <HeavenSearchResult>[];
    }
  }

  static String? extractYouTubeVideoId(String url) {
    final Uri? parsed = Uri.tryParse(url);
    if (parsed == null) {
      return null;
    }
    final String host = parsed.host.toLowerCase();
    if (host.contains('youtube.com')) {
      final String? v = parsed.queryParameters['v'];
      if (v != null && v.length >= 8) {
        return v;
      }
    } else if (host == 'youtu.be' && parsed.pathSegments.isNotEmpty) {
      return parsed.pathSegments.first;
    }
    return null;
  }

  Future<List<HeavenImageResult>> _fetchCommonsImages(String query) async {
    try {
      final Uri uri = Uri.parse(
        'https://commons.wikimedia.org/w/api.php?action=query'
        '&generator=search&gsrsearch=${Uri.encodeQueryComponent(query)}'
        '&gsrnamespace=6&gsrlimit=18&prop=imageinfo'
        '&iiprop=url&iiurlwidth=500&format=json',
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
        return const <HeavenImageResult>[];
      }
      final Object? decoded = jsonDecode(res.body);
      if (decoded is! Map<String, Object?>) {
        return const <HeavenImageResult>[];
      }
      final Object? queryObj = decoded['query'];
      if (queryObj is! Map<String, Object?>) {
        return const <HeavenImageResult>[];
      }
      final Object? pagesObj = queryObj['pages'];
      if (pagesObj is! Map<String, Object?>) {
        return const <HeavenImageResult>[];
      }

      final List<HeavenImageResult> images = <HeavenImageResult>[];
      for (final Object? pageVal in pagesObj.values) {
        if (pageVal is Map<String, Object?>) {
          String rawTitle = (pageVal['title']?.toString() ?? '')
              .replaceFirst('File:', '')
              .replaceAll(RegExp(r'\.[a-zA-Z0-9]{3,4}$'), '')
              .replaceAll('_', ' ')
              .trim();
          final Object? infoList = pageVal['imageinfo'];
          if (infoList is List<Object?> && infoList.isNotEmpty) {
            final Object? first = infoList.first;
            if (first is Map<String, Object?>) {
              final String thumb = (first['thumburl']?.toString() ?? '').trim();
              final String full = (first['url']?.toString() ?? thumb).trim();
              final String descUrl =
                  (first['descriptionurl']?.toString() ?? full).trim();
              if (thumb.isNotEmpty &&
                  !thumb.toLowerCase().endsWith('.svg') &&
                  !thumb.toLowerCase().endsWith('.tif')) {
                images.add(
                  HeavenImageResult(
                    title: rawTitle.isEmpty ? query : rawTitle,
                    thumbUrl: thumb,
                    fullUrl: full,
                    pageUrl: descUrl,
                  ),
                );
              }
            }
          }
        }
      }
      return images;
    } catch (_) {
      return const <HeavenImageResult>[];
    }
  }

  Future<List<HeavenSearchResult>> _fetchGoogleNewsRss(
    String query, {
    required HeavenSearchFilters filters,
  }) async {
    try {
      final String timeToken = switch (filters.time) {
        HeavenTimeFilter.day => ' when:1d',
        HeavenTimeFilter.week => ' when:7d',
        HeavenTimeFilter.month => ' when:30d',
        HeavenTimeFilter.year => ' when:1y',
        HeavenTimeFilter.any => '',
      };
      final String qParam = Uri.encodeQueryComponent('$query$timeToken');
      final String hl = filters.region.langCode;
      final String gl = filters.region.countryCode;
      final String ceid = '$gl:${hl.split('-').first}';

      final Uri uri = Uri.parse(
        'https://news.google.com/rss/search?q=$qParam&hl=$hl&gl=$gl&ceid=$ceid',
      );
      final http.Response res = await _client
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200 || res.body.isEmpty) {
        return const <HeavenSearchResult>[];
      }
      return parseRssNewsItems(res.body);
    } catch (_) {
      return const <HeavenSearchResult>[];
    }
  }

  static List<HeavenSearchResult> parseRssNewsItems(String xml) {
    final List<HeavenSearchResult> items = <HeavenSearchResult>[];
    final RegExp itemRegex = RegExp(
      r'<item>([\s\S]*?)<\/item>',
      caseSensitive: false,
    );
    final RegExp titleRegex = RegExp(r'<title>([\s\S]*?)<\/title>');
    final RegExp linkRegex = RegExp(r'<link>([\s\S]*?)<\/link>');
    final RegExp pubDateRegex = RegExp(r'<pubDate>([\s\S]*?)<\/pubDate>');
    final RegExp sourceRegex = RegExp(
      r'<source(?:\s+url="([^"]*)")?[^>]*>([\s\S]*?)<\/source>',
    );

    for (final RegExpMatch match in itemRegex.allMatches(xml)) {
      final String block = match.group(1) ?? '';
      String title = stripHtmlTags(
        titleRegex.firstMatch(block)?.group(1) ?? '',
      ).trim();
      final String link = decodeHtmlEntities(
        linkRegex.firstMatch(block)?.group(1) ?? '',
      ).trim();
      final String pubDate = stripHtmlTags(
        pubDateRegex.firstMatch(block)?.group(1) ?? '',
      ).trim();
      final RegExpMatch? srcMatch = sourceRegex.firstMatch(block);
      final String sourceUrl = (srcMatch?.group(1) ?? '').trim();
      final String publisher = stripHtmlTags(
        srcMatch?.group(2) ?? 'News',
      ).trim();

      if (title.isEmpty || link.isEmpty) {
        continue;
      }
      // Clean trailing " - Publisher" from Google News title
      final String suffix = ' - $publisher';
      if (publisher.isNotEmpty && title.endsWith(suffix)) {
        title = title.substring(0, title.length - suffix.length).trim();
      }
      final String shortDate = pubDate.length > 16
          ? pubDate.substring(0, 16)
          : pubDate;

      items.add(
        HeavenSearchResult(
          title: title,
          url: link,
          snippet: shortDate.isNotEmpty
              ? '$publisher • Published $shortDate'
              : publisher,
          sourceLabel: sourceUrl.isNotEmpty
              ? OmniboxParser.cleanDomain(sourceUrl)
              : publisher,
          metaBadge: publisher,
        ),
      );
      if (items.length >= 18) {
        break;
      }
    }
    return items;
  }

  static List<HeavenSearchResult> parseOrganicHtmlResults(
    String html, {
    int maxItems = 18,
  }) {
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
      if (rawHref.contains('ad_domain=') || rawHref.contains('/y.js')) {
        continue;
      }

      final String cleanUrl = unwrapRedirectUrl(rawHref);
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        continue;
      }
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
      if (results.length >= maxItems) {
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
              imageUrl: image.isEmpty ? null : image,
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
        '&utf8=1&format=json&srlimit=12',
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

  static String stripHtmlTags(String html) {
    final String withoutTags = html
        .replaceAll('<![CDATA[', '')
        .replaceAll(']]>', '')
        .replaceAll(RegExp(r'<[^>]*>'), '');
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
