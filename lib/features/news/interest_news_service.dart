import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/omnibox_parser.dart';

enum NewsCategoryTab {
  forYou(
    label: 'For You',
    query: 'India world technology science entertainment',
    directRssUrls: <({String source, String url})>[
      (
        source: 'NDTV',
        url: 'https://feeds.feedburner.com/ndtvnews-top-stories',
      ),
      (source: 'BBC News', url: 'https://feeds.bbci.co.uk/news/world/rss.xml'),
      (source: 'The Verge', url: 'https://www.theverge.com/rss/index.xml'),
    ],
  ),
  india(
    label: 'India',
    query: 'India latest news headlines',
    directRssUrls: <({String source, String url})>[
      (
        source: 'NDTV',
        url: 'https://feeds.feedburner.com/ndtvnews-top-stories',
      ),
      (
        source: 'NDTV India',
        url: 'https://feeds.feedburner.com/ndtvnews-india-news',
      ),
    ],
  ),
  tech(
    label: 'Tech & AI',
    query: 'Technology AI smartphones software',
    directRssUrls: <({String source, String url})>[
      (source: 'The Verge', url: 'https://www.theverge.com/rss/index.xml'),
      (
        source: 'BBC Tech',
        url: 'https://feeds.bbci.co.uk/news/technology/rss.xml',
      ),
    ],
  ),
  entertainment(
    label: 'Movies & Showbiz',
    query: 'Movies Bollywood Hollywood OTT',
    directRssUrls: <({String source, String url})>[
      (
        source: 'BBC Entertainment',
        url: 'https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml',
      ),
      (source: 'IGN', url: 'https://feeds.feedburner.com/ign/all'),
    ],
  ),
  sports(
    label: 'Sports',
    query: 'Cricket IPL Football sports',
    directRssUrls: <({String source, String url})>[
      (source: 'BBC Sport', url: 'https://feeds.bbci.co.uk/sport/rss.xml'),
      (
        source: 'NDTV Sports',
        url: 'https://feeds.feedburner.com/ndtvsports-latest',
      ),
    ],
  ),
  gaming(
    label: 'Gaming',
    query: 'Video games esports PC mobile gaming',
    directRssUrls: <({String source, String url})>[
      (source: 'IGN', url: 'https://feeds.feedburner.com/ign/all'),
    ],
  ),
  business(
    label: 'Business',
    query: 'Business markets startups crypto',
    directRssUrls: <({String source, String url})>[
      (
        source: 'BBC Business',
        url: 'https://feeds.bbci.co.uk/news/business/rss.xml',
      ),
      (
        source: 'NDTV Profit',
        url: 'https://feeds.feedburner.com/ndtvprofit-latest',
      ),
    ],
  ),
  science(
    label: 'Science',
    query: 'Space science discoveries ISRO NASA',
    directRssUrls: <({String source, String url})>[
      (source: 'Space.com', url: 'https://www.space.com/feeds/all'),
      (
        source: 'BBC Science',
        url: 'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml',
      ),
    ],
  );

  const NewsCategoryTab({
    required this.label,
    required this.query,
    required this.directRssUrls,
  });

  final String label;
  final String query;
  final List<({String source, String url})> directRssUrls;
}

class PersonalizedNewsItem {
  const PersonalizedNewsItem({
    required this.title,
    required this.url,
    required this.sourceName,
    required this.sourceUrl,
    required this.publishedAtMs,
    required this.timeLabel,
    this.imageUrl,
    this.matchedTopic,
    this.affinityScore = 0.0,
  });

  final String title;
  final String url;
  final String sourceName;
  final String sourceUrl;
  final int publishedAtMs;
  final String timeLabel;
  final String? imageUrl;
  final String? matchedTopic;
  final double affinityScore;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'url': url,
    'sourceName': sourceName,
    'sourceUrl': sourceUrl,
    'publishedAtMs': publishedAtMs,
    'timeLabel': timeLabel,
    'imageUrl': imageUrl,
    'matchedTopic': matchedTopic,
    'affinityScore': affinityScore,
  };

  factory PersonalizedNewsItem.fromJson(Map<String, Object?> map) {
    final String? rawImg = map['imageUrl']?.toString().trim();
    return PersonalizedNewsItem(
      title: (map['title']?.toString() ?? '').trim(),
      url: (map['url']?.toString() ?? '').trim(),
      sourceName: (map['sourceName']?.toString() ?? 'News').trim(),
      sourceUrl: (map['sourceUrl']?.toString() ?? '').trim(),
      publishedAtMs: (map['publishedAtMs'] is num)
          ? (map['publishedAtMs']! as num).toInt()
          : 0,
      timeLabel: (map['timeLabel']?.toString() ?? '').trim(),
      imageUrl: (rawImg != null && rawImg.isNotEmpty) ? rawImg : null,
      matchedTopic: map['matchedTopic']?.toString(),
      affinityScore: (map['affinityScore'] is num)
          ? (map['affinityScore']! as num).toDouble()
          : 0.0,
    );
  }
}

class InterestEntry {
  const InterestEntry({
    required this.key,
    required this.label,
    required this.query,
    required this.score,
    required this.updatedAtMs,
  });

  final String key;
  final String label;
  final String query;
  final double score;
  final int updatedAtMs;

  double decayedScore(int nowMs) {
    final double days = math.max(0.0, (nowMs - updatedAtMs) / 86400000.0);
    return score * math.pow(0.88, days);
  }

  Map<String, Object> toJson() => <String, Object>{
    'key': key,
    'label': label,
    'query': query,
    'score': score,
    'updatedAtMs': updatedAtMs,
  };

  factory InterestEntry.fromJson(Map<String, Object?> map) {
    return InterestEntry(
      key: (map['key']?.toString() ?? '').trim(),
      label: (map['label']?.toString() ?? '').trim(),
      query: (map['query']?.toString() ?? '').trim(),
      score: (map['score'] is num) ? (map['score']! as num).toDouble() : 1.0,
      updatedAtMs: (map['updatedAtMs'] is num)
          ? (map['updatedAtMs']! as num).toInt()
          : 0,
    );
  }
}

class InterestProfileController extends ChangeNotifier {
  InterestProfileController(this._prefs) {
    _load();
  }

  static const String _storageKey = 'hb.interestProfile.v5';

  static const Map<
    String,
    ({String label, String query, List<String> keywords})
  >
  _curatedBuckets =
      <String, ({String label, String query, List<String> keywords})>{
        'tech': (
          label: 'Tech & AI',
          query: 'AI Android smartphones technology coding',
          keywords: <String>[
            'android',
            'iphone',
            'apple',
            'google',
            'openai',
            'chatgpt',
            'gemini',
            'claude',
            'linux',
            'ubuntu',
            'flutter',
            'python',
            'github',
            'laptop',
            'gpu',
            'nvidia',
            'tech',
            'software',
            'cyber',
            'vpn',
          ],
        ),
        'entertainment': (
          label: 'Movies & OTT',
          query: 'Movies web series Bollywood Hollywood anime',
          keywords: <String>[
            'movie',
            'movies',
            'film',
            'cinema',
            'bollywood',
            'hollywood',
            'netflix',
            'prime',
            'hotstar',
            'trailer',
            'actor',
            'anime',
            'manga',
            'series',
            'music',
            'song',
          ],
        ),
        'sports': (
          label: 'Sports & Cricket',
          query: 'Cricket IPL India football Champions League',
          keywords: <String>[
            'cricket',
            'ipl',
            'bcci',
            'kohli',
            'rohit',
            'dhoni',
            'match',
            'score',
            'football',
            'fifa',
            'premier',
            'tennis',
            'f1',
            'formula',
          ],
        ),
        'gaming': (
          label: 'Gaming',
          query: 'Gaming GTA PlayStation PC mobile games esports',
          keywords: <String>[
            'game',
            'gaming',
            'gta',
            'minecraft',
            'valorant',
            'bgmi',
            'pubg',
            'playstation',
            'ps5',
            'xbox',
            'steam',
            'esports',
            'roblox',
          ],
        ),
        'finance': (
          label: 'Markets & Crypto',
          query: 'Stock market Sensex Nifty Bitcoin startups',
          keywords: <String>[
            'stock',
            'nifty',
            'sensex',
            'market',
            'bitcoin',
            'crypto',
            'ethereum',
            'bank',
            'finance',
            'startup',
            'economy',
            'gold',
          ],
        ),
        'science': (
          label: 'Science & Space',
          query: 'Space ISRO NASA astronomy physics science',
          keywords: <String>[
            'space',
            'isro',
            'nasa',
            'spacex',
            'rocket',
            'moon',
            'mars',
            'science',
            'quantum',
            'physics',
            'astronomy',
          ],
        ),
      };

  static const Set<String> _stopWords = <String>{
    'the',
    'and',
    'for',
    'with',
    'from',
    'that',
    'this',
    'what',
    'when',
    'where',
    'how',
    'who',
    'why',
    'are',
    'was',
    'were',
    'have',
    'has',
    'will',
    'http',
    'https',
    'www',
    'com',
    'org',
    'net',
    'html',
    'watch',
    'free',
    'download',
    'online',
    'home',
    'page',
    'news',
    'search',
    'site',
    'web',
    'official',
    'best',
    'top',
    'new',
    '2025',
    '2026',
  };

  final SharedPreferences _prefs;
  final Map<String, InterestEntry> _entries = <String, InterestEntry>{};

  List<InterestEntry> get rankedInterests {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<InterestEntry> list = _entries.values.toList();
    list.sort(
      (InterestEntry a, InterestEntry b) =>
          b.decayedScore(now).compareTo(a.decayedScore(now)),
    );
    return list
        .where((InterestEntry e) => e.decayedScore(now) >= 0.45)
        .take(12)
        .toList(growable: false);
  }

  void _load() {
    final String? raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List<Object?>) {
        for (final Object? item in decoded) {
          if (item is Map<String, Object?>) {
            final InterestEntry parsed = InterestEntry.fromJson(item);
            if (parsed.key.isNotEmpty) {
              _entries[parsed.key] = parsed;
            }
          }
        }
      }
    } on FormatException {
      _entries.clear();
    }
  }

  Future<void> _persist() async {
    final List<InterestEntry> top = rankedInterests;
    await _prefs.setString(
      _storageKey,
      jsonEncode(top.map((InterestEntry e) => e.toJson()).toList()),
    );
  }

  Future<void> recordActivity({
    required String text,
    double weight = 1.5,
  }) async {
    final String lower = text.toLowerCase();
    final List<String> tokens = lower
        .split(RegExp(r'[^a-z0-9]+'))
        .where((String w) => w.length >= 3 && !_stopWords.contains(w))
        .toList(growable: false);
    if (tokens.isEmpty) {
      return;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    bool matchedBucket = false;

    for (final MapEntry<
          String,
          ({String label, String query, List<String> keywords})
        >
        bucket
        in _curatedBuckets.entries) {
      final int hits = tokens
          .where((String t) => bucket.value.keywords.contains(t))
          .length;
      if (hits > 0) {
        matchedBucket = true;
        _bumpEntry(
          key: 'cat:${bucket.key}',
          label: bucket.value.label,
          query: bucket.value.query,
          delta: weight * math.min(2.5, hits.toDouble()),
          nowMs: now,
        );
      }
    }

    final String primaryTerm = tokens.firstWhere(
      (String t) => t.length >= 4 && int.tryParse(t) == null,
      orElse: () => '',
    );
    if (primaryTerm.isNotEmpty) {
      final String titleCase =
          primaryTerm[0].toUpperCase() + primaryTerm.substring(1);
      _bumpEntry(
        key: 'kw:$primaryTerm',
        label: titleCase,
        query: primaryTerm,
        delta: matchedBucket ? weight * 0.75 : weight * 1.15,
        nowMs: now,
      );
    }

    await _persist();
    notifyListeners();
  }

  void _bumpEntry({
    required String key,
    required String label,
    required String query,
    required double delta,
    required int nowMs,
  }) {
    final InterestEntry? existing = _entries[key];
    final double base = existing != null ? existing.decayedScore(nowMs) : 0.0;
    final double nextScore = math.min(40.0, base + delta);
    _entries[key] = InterestEntry(
      key: key,
      label: label,
      query: query,
      score: nextScore,
      updatedAtMs: nowMs,
    );
  }

  double computeHeadlineAffinity(String title, String source) {
    final List<InterestEntry> active = rankedInterests;
    if (active.isEmpty) {
      return 0.0;
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    final String lower = '$title $source'.toLowerCase();
    double total = 0.0;
    for (final InterestEntry entry in active) {
      final double w = entry.decayedScore(now);
      if (entry.key.startsWith('kw:')) {
        final String kw = entry.key.substring(3);
        if (lower.contains(kw)) {
          total += w * 1.8;
        }
      } else if (entry.key.startsWith('cat:')) {
        final String catKey = entry.key.substring(4);
        final ({String label, String query, List<String> keywords})? bucket =
            _curatedBuckets[catKey];
        if (bucket != null &&
            bucket.keywords.any((String k) => lower.contains(k))) {
          total += w * 1.1;
        }
      }
    }
    return total;
  }

  Future<void> clearInterests() async {
    _entries.clear();
    await _prefs.remove(_storageKey);
    notifyListeners();
  }
}

class HeavenNewsFeedService {
  HeavenNewsFeedService({
    required this.prefs,
    required this.interests,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const String _cachePrefix = 'hb.newsFeedCache.v6.';

  final SharedPreferences prefs;
  final InterestProfileController interests;
  final http.Client _client;

  List<PersonalizedNewsItem> readCached(NewsCategoryTab tab) {
    final String? raw = prefs.getString('$_cachePrefix${tab.name}');
    if (raw == null || raw.isEmpty) {
      return const <PersonalizedNewsItem>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List<Object?>) {
        return decoded
            .whereType<Map<String, Object?>>()
            .map(PersonalizedNewsItem.fromJson)
            .where((PersonalizedNewsItem e) => e.url.isNotEmpty)
            .toList(growable: false);
      }
    } on FormatException {
      return const <PersonalizedNewsItem>[];
    }
    return const <PersonalizedNewsItem>[];
  }

  Future<List<PersonalizedNewsItem>> fetchFeed(NewsCategoryTab tab) async {
    List<PersonalizedNewsItem> fetched;
    if (tab == NewsCategoryTab.forYou) {
      fetched = await _fetchPersonalizedForYou();
    } else {
      fetched = await _fetchCategoryFeed(tab);
    }

    if (fetched.isNotEmpty) {
      await prefs.setString(
        '$_cachePrefix${tab.name}',
        jsonEncode(
          fetched.take(24).map((PersonalizedNewsItem e) => e.toJson()).toList(),
        ),
      );
      return fetched;
    }
    return readCached(tab);
  }

  Future<List<PersonalizedNewsItem>> _fetchPersonalizedForYou() async {
    final List<InterestEntry> topInterests = interests.rankedInterests
        .take(3)
        .toList(growable: false);

    final List<Future<List<PersonalizedNewsItem>>> tasks =
        <Future<List<PersonalizedNewsItem>>>[
          for (final ({String source, String url}) feed
              in NewsCategoryTab.forYou.directRssUrls)
            _fetchDirectPublisherRss(feed.url, defaultSource: feed.source),
          for (final InterestEntry entry in topInterests)
            _fetchBingRichNewsByQuery(entry.query, topicBadge: entry.label),
          if (topInterests.isEmpty)
            _fetchBingRichNewsByQuery(
              'India technology science entertainment sports',
              topicBadge: 'Discover',
            ),
          _fetchTopHeadlinesRss(),
        ];

    return _mergeAndRankBatches(await Future.wait(tasks));
  }

  Future<List<PersonalizedNewsItem>> _fetchCategoryFeed(
    NewsCategoryTab tab,
  ) async {
    final List<Future<List<PersonalizedNewsItem>>> tasks =
        <Future<List<PersonalizedNewsItem>>>[
          for (final ({String source, String url}) feed in tab.directRssUrls)
            _fetchDirectPublisherRss(
              feed.url,
              defaultSource: feed.source,
              topicBadge: tab.label,
            ),
          _fetchBingRichNewsByQuery(tab.query, topicBadge: tab.label),
          _fetchRssByQuery(tab.query, topicBadge: tab.label),
        ];

    return _mergeAndRankBatches(await Future.wait(tasks));
  }

  List<PersonalizedNewsItem> _mergeAndRankBatches(
    List<List<PersonalizedNewsItem>> batches,
  ) {
    final Set<String> seenTitles = <String>{};
    final List<PersonalizedNewsItem> merged = <PersonalizedNewsItem>[];
    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    for (final List<PersonalizedNewsItem> batch in batches) {
      for (final PersonalizedNewsItem item in batch) {
        final String normKey = item.title
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '')
            .trim();
        if (normKey.length < 8 || !seenTitles.add(normKey)) {
          continue;
        }
        final double affinity = interests.computeHeadlineAffinity(
          item.title,
          item.sourceName,
        );
        final double hoursOld = item.publishedAtMs > 0
            ? math.max(0.0, (nowMs - item.publishedAtMs) / 3600000.0)
            : 12.0;
        final double recencyBoost = math.max(0.0, 12.0 - (hoursOld * 0.45));
        final double topicBonus = item.matchedTopic != null ? 4.0 : 0.0;
        final double imageBonus =
            (item.imageUrl != null && item.imageUrl!.isNotEmpty) ? 16.0 : 0.0;

        merged.add(
          PersonalizedNewsItem(
            title: item.title,
            url: item.url,
            sourceName: item.sourceName,
            sourceUrl: item.sourceUrl,
            publishedAtMs: item.publishedAtMs,
            timeLabel: item.timeLabel,
            imageUrl: item.imageUrl,
            matchedTopic: item.matchedTopic,
            affinityScore: affinity + recencyBoost + topicBonus + imageBonus,
          ),
        );
      }
    }

    merged.sort(
      (PersonalizedNewsItem a, PersonalizedNewsItem b) =>
          b.affinityScore.compareTo(a.affinityScore),
    );
    return merged.take(24).toList(growable: false);
  }

  Future<List<PersonalizedNewsItem>> _fetchDirectPublisherRss(
    String feedUrl, {
    required String defaultSource,
    String? topicBadge,
  }) async {
    try {
      final http.Response response = await _client
          .get(
            Uri.parse(feedUrl),
            headers: const <String, String>{
              'User-Agent': AppConstants.mobileUserAgent,
              'Accept':
                  'application/rss+xml, application/atom+xml, application/xml, text/xml',
            },
          )
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200 || response.body.isEmpty) {
        return const <PersonalizedNewsItem>[];
      }
      return parseRichFeedXml(
        response.body,
        defaultSource: defaultSource,
        topicBadge: topicBadge,
      );
    } catch (_) {
      return const <PersonalizedNewsItem>[];
    }
  }

  Future<List<PersonalizedNewsItem>> _fetchBingRichNewsByQuery(
    String query, {
    required String? topicBadge,
  }) async {
    try {
      final Uri uri = Uri.parse(
        'https://www.bing.com/news/infinitescrollajax?InfiniteScroll=1'
        '&q=${Uri.encodeQueryComponent(query)}&IG=1&IID=news.1&sfx=1',
      );
      final http.Response response = await _client
          .get(
            uri,
            headers: const <String, String>{
              'User-Agent': AppConstants.desktopUserAgent,
              'Accept-Language': 'en-US,en;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200 || response.body.isEmpty) {
        return const <PersonalizedNewsItem>[];
      }
      return parseBingDiscoverHtml(response.body, topicBadge: topicBadge);
    } catch (_) {
      return const <PersonalizedNewsItem>[];
    }
  }

  static List<PersonalizedNewsItem> parseBingDiscoverHtml(
    String html, {
    String? topicBadge,
  }) {
    final List<PersonalizedNewsItem> out = <PersonalizedNewsItem>[];
    final List<String> cards = html.split('<div class="news-card');
    final RegExp urlReg = RegExp(r'data-url="([^"]+)"');
    final RegExp titleReg = RegExp(r'data-title="([^"]+)"');
    final RegExp authorReg = RegExp(r'data-author="([^"]+)"');
    final RegExp imgReg = RegExp(
      r'src="((?:https:\/\/www\.bing\.com)?\/th\?id=(?:ONUT|OVFT)\.[^"]+)"',
      caseSensitive: false,
    );
    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    for (int i = 1; i < cards.length; i++) {
      final String block = cards[i];
      final String url = _unescapeXml(
        urlReg.firstMatch(block)?.group(1) ?? '',
      ).trim();
      final String title = _stripHtml(
        titleReg.firstMatch(block)?.group(1) ?? '',
      ).trim();
      final String author = _stripHtml(
        authorReg.firstMatch(block)?.group(1) ?? 'News',
      ).trim();

      if (!url.startsWith('http') || title.isEmpty) continue;

      String? imageUrl;
      final RegExpMatch? im = imgReg.firstMatch(block);
      if (im != null) {
        String rawImg = _unescapeXml(im.group(1) ?? '');
        if (rawImg.startsWith('/')) {
          rawImg = 'https://www.bing.com$rawImg';
        }
        imageUrl = rawImg
            .replaceAll(RegExp(r'w=\d+'), 'w=640')
            .replaceAll(RegExp(r'h=\d+'), 'h=360');
      }

      out.add(
        PersonalizedNewsItem(
          title: title,
          url: url,
          sourceName: author.isEmpty ? OmniboxParser.cleanDomain(url) : author,
          sourceUrl: 'https://${OmniboxParser.cleanDomain(url)}',
          publishedAtMs: nowMs - (i * 900000),
          timeLabel: 'Today',
          imageUrl: imageUrl,
          matchedTopic: topicBadge,
        ),
      );
      if (out.length >= 14) break;
    }
    return out;
  }

  /// Parses both RSS `<item>` and Atom `<entry>` XML feeds along with real cover photos!
  static List<PersonalizedNewsItem> parseRichFeedXml(
    String xml, {
    String defaultSource = 'News',
    String? topicBadge,
  }) {
    final RegExp blockExp = RegExp(
      r'<(?:item|entry)(?:\s[^>]*)?>([\s\S]*?)</(?:item|entry)>',
      caseSensitive: false,
    );
    final RegExp titleExp = RegExp(r'<title(?:\s[^>]*)?>([\s\S]*?)</title>');
    final RegExp linkTagExp = RegExp(r'<link>([\s\S]*?)</link>');
    final RegExp linkHrefExp = RegExp(r'<link[^>]*href="([^"]+)"');
    final RegExp pubDateExp = RegExp(
      r'<(?:pubDate|published|updated)>([\s\S]*?)</(?:pubDate|published|updated)>',
    );
    final RegExp sourceExp = RegExp(
      r'<source(?:\s+url="([^"]*)")?>([\s\S]*?)</source>',
    );
    final RegExp mediaUrlExp = RegExp(
      r'<(?:media:content|media:thumbnail|enclosure)[^>]*\burl="([^"]+)"',
      caseSensitive: false,
    );
    final RegExp storyImgExp = RegExp(
      r'<StoryImage>([\s\S]*?)</StoryImage>',
      caseSensitive: false,
    );
    final RegExp inlineImgExp = RegExp(
      r'<img[^>]*\bsrc="(https?:\/\/[^"]+)"',
      caseSensitive: false,
    );

    final List<PersonalizedNewsItem> items = <PersonalizedNewsItem>[];
    for (final RegExpMatch match in blockExp.allMatches(xml)) {
      final String block = match.group(1) ?? '';
      String title = _stripHtml(titleExp.firstMatch(block)?.group(1) ?? '');
      String link = _unescapeXml(
        linkTagExp.firstMatch(block)?.group(1) ??
            linkHrefExp.firstMatch(block)?.group(1) ??
            '',
      ).trim();
      final String rawPub = _unescapeXml(
        pubDateExp.firstMatch(block)?.group(1) ?? '',
      ).trim();

      final RegExpMatch? srcMatch = sourceExp.firstMatch(block);
      final String srcUrl = _unescapeXml(srcMatch?.group(1) ?? '').trim();
      final String srcName = _stripHtml(
        srcMatch?.group(2) ?? defaultSource,
      ).trim();

      if (srcName.isNotEmpty && title.endsWith(' - $srcName')) {
        title = title.substring(0, title.length - srcName.length - 3).trim();
      }
      if (title.isEmpty || !link.startsWith('http')) {
        continue;
      }

      String? img = _unescapeXml(
        mediaUrlExp.firstMatch(block)?.group(1) ??
            storyImgExp.firstMatch(block)?.group(1) ??
            inlineImgExp.firstMatch(_unescapeXml(block))?.group(1) ??
            '',
      ).trim();

      if (img.isNotEmpty) {
        // Upgrade BBC 240px thumbnails to crisp 800px HD
        img = img.replaceFirst('/standard/240/', '/standard/800/');
        if (!img.startsWith('http') || img.endsWith('.svg')) {
          img = null;
        }
      } else {
        img = null;
      }

      final int pubMs = _parseDateMs(rawPub);
      items.add(
        PersonalizedNewsItem(
          title: title,
          url: link,
          sourceName: srcName.isEmpty ? defaultSource : srcName,
          sourceUrl: srcUrl.isNotEmpty
              ? srcUrl
              : 'https://${OmniboxParser.cleanDomain(link)}',
          publishedAtMs: pubMs,
          timeLabel: _formatRelativeAge(pubMs, rawPub),
          imageUrl: img,
          matchedTopic: topicBadge,
        ),
      );
      if (items.length >= 16) {
        break;
      }
    }
    return items;
  }

  Future<List<PersonalizedNewsItem>> _fetchTopHeadlinesRss() async {
    final Uri uri = Uri.parse(
      'https://news.google.com/rss?hl=en-IN&gl=IN&ceid=IN:en',
    );
    return _fetchAndParseRss(uri, topicBadge: null);
  }

  Future<List<PersonalizedNewsItem>> _fetchRssByQuery(
    String query, {
    required String? topicBadge,
  }) async {
    final Uri uri = Uri.https(
      'news.google.com',
      '/rss/search',
      <String, String>{'q': query, 'hl': 'en-IN', 'gl': 'IN', 'ceid': 'IN:en'},
    );
    return _fetchAndParseRss(uri, topicBadge: topicBadge);
  }

  Future<List<PersonalizedNewsItem>> _fetchAndParseRss(
    Uri uri, {
    required String? topicBadge,
  }) async {
    try {
      final http.Response response = await _client
          .get(
            uri,
            headers: const <String, String>{
              'User-Agent': AppConstants.mobileUserAgent,
              'Accept': 'application/rss+xml, application/xml, text/xml',
            },
          )
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) {
        return const <PersonalizedNewsItem>[];
      }
      return parseGoogleNewsRss(response.body, topicBadge: topicBadge);
    } on Exception {
      return const <PersonalizedNewsItem>[];
    }
  }

  static List<PersonalizedNewsItem> parseGoogleNewsRss(
    String xml, {
    String? topicBadge,
  }) {
    return parseRichFeedXml(xml, defaultSource: 'News', topicBadge: topicBadge);
  }

  static int _parseDateMs(String raw) {
    if (raw.isEmpty) {
      return 0;
    }
    final DateTime? iso = DateTime.tryParse(raw);
    if (iso != null) {
      return iso.millisecondsSinceEpoch;
    }
    final RegExp rfc = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
    );
    final RegExpMatch? m = rfc.firstMatch(raw);
    if (m == null) {
      return 0;
    }
    const Map<String, int> months = <String, int>{
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final int? day = int.tryParse(m.group(1)!);
    final int? month = months[m.group(2)!.toLowerCase()];
    final int? year = int.tryParse(m.group(3)!);
    final int? hour = int.tryParse(m.group(4)!);
    final int? minute = int.tryParse(m.group(5)!);
    final int? sec = int.tryParse(m.group(6)!);
    if (day == null ||
        month == null ||
        year == null ||
        hour == null ||
        minute == null ||
        sec == null) {
      return 0;
    }
    return DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      sec,
    ).millisecondsSinceEpoch;
  }

  static String _formatRelativeAge(int pubMs, String rawFallback) {
    if (pubMs <= 0) {
      return rawFallback.length > 16 ? rawFallback.substring(0, 16) : '';
    }
    final int diffMin = math.max(
      1,
      ((DateTime.now().millisecondsSinceEpoch - pubMs) / 60000).round(),
    );
    if (diffMin < 60) {
      return '${diffMin}m ago';
    }
    final int diffHours = (diffMin / 60).round();
    if (diffHours < 24) {
      return '${diffHours}h ago';
    }
    final int diffDays = (diffHours / 24).round();
    return '${diffDays}d ago';
  }

  static String _stripHtml(String input) {
    return _unescapeXml(input)
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _unescapeXml(String input) {
    return input
        .replaceAll('<![CDATA[', '')
        .replaceAll(']]>', '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  void dispose() {
    _client.close();
  }
}
