import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';

enum NewsCategoryTab {
  forYou(label: 'For You', query: ''),
  india(label: 'India', query: 'India latest news'),
  tech(label: 'Tech & AI', query: 'Technology AI smartphones software'),
  entertainment(
    label: 'Movies & Showbiz',
    query: 'Movies Bollywood Hollywood OTT',
  ),
  sports(label: 'Sports', query: 'Cricket IPL Football sports'),
  gaming(label: 'Gaming', query: 'Video games esports PC mobile gaming'),
  business(label: 'Business', query: 'Business markets startups crypto'),
  science(label: 'Science', query: 'Space science discoveries ISRO NASA');

  const NewsCategoryTab({required this.label, required this.query});

  final String label;
  final String query;
}

class PersonalizedNewsItem {
  const PersonalizedNewsItem({
    required this.title,
    required this.url,
    required this.sourceName,
    required this.sourceUrl,
    required this.publishedAtMs,
    required this.timeLabel,
    this.matchedTopic,
    this.affinityScore = 0.0,
  });

  final String title;
  final String url;
  final String sourceName;
  final String sourceUrl;
  final int publishedAtMs;
  final String timeLabel;
  final String? matchedTopic;
  final double affinityScore;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'url': url,
    'sourceName': sourceName,
    'sourceUrl': sourceUrl,
    'publishedAtMs': publishedAtMs,
    'timeLabel': timeLabel,
    'matchedTopic': matchedTopic,
    'affinityScore': affinityScore,
  };

  factory PersonalizedNewsItem.fromJson(Map<String, Object?> map) {
    return PersonalizedNewsItem(
      title: (map['title']?.toString() ?? '').trim(),
      url: (map['url']?.toString() ?? '').trim(),
      sourceName: (map['sourceName']?.toString() ?? 'News').trim(),
      sourceUrl: (map['sourceUrl']?.toString() ?? '').trim(),
      publishedAtMs: (map['publishedAtMs'] is num)
          ? (map['publishedAtMs']! as num).toInt()
          : 0,
      timeLabel: (map['timeLabel']?.toString() ?? '').trim(),
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

    // Also track the strongest specific keyword so daily niche topics personalize the feed!
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

  static const String _cachePrefix = 'hb.newsFeedCache.v5.';

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
      fetched = await _fetchRssByQuery(tab.query, topicBadge: tab.label);
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
          _fetchTopHeadlinesRss(),
          for (final InterestEntry entry in topInterests)
            _fetchRssByQuery(entry.query, topicBadge: entry.label),
          if (topInterests.isEmpty)
            _fetchRssByQuery(
              'Technology science entertainment sports India',
              topicBadge: 'Trending',
            ),
        ];

    final List<List<PersonalizedNewsItem>> batches = await Future.wait(tasks);
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
            : 18.0;
        final double recencyBoost = math.max(0.0, 12.0 - (hoursOld * 0.45));
        final double topicBonus = item.matchedTopic != null ? 4.0 : 0.0;

        merged.add(
          PersonalizedNewsItem(
            title: item.title,
            url: item.url,
            sourceName: item.sourceName,
            sourceUrl: item.sourceUrl,
            publishedAtMs: item.publishedAtMs,
            timeLabel: item.timeLabel,
            matchedTopic: item.matchedTopic,
            affinityScore: affinity + recencyBoost + topicBonus,
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
    final RegExp itemExp = RegExp(r'<item>([\s\S]*?)</item>');
    final RegExp titleExp = RegExp(r'<title>([\s\S]*?)</title>');
    final RegExp linkExp = RegExp(r'<link>([\s\S]*?)</link>');
    final RegExp pubDateExp = RegExp(r'<pubDate>([\s\S]*?)</pubDate>');
    final RegExp sourceExp = RegExp(
      r'<source(?:\s+url="([^"]*)")?>([\s\S]*?)</source>',
    );

    final List<PersonalizedNewsItem> items = <PersonalizedNewsItem>[];
    for (final RegExpMatch match in itemExp.allMatches(xml)) {
      final String block = match.group(1) ?? '';
      String title = _unescapeXml(titleExp.firstMatch(block)?.group(1) ?? '');
      final String link = _unescapeXml(
        linkExp.firstMatch(block)?.group(1) ?? '',
      ).trim();
      final String rawPub = _unescapeXml(
        pubDateExp.firstMatch(block)?.group(1) ?? '',
      ).trim();
      final RegExpMatch? srcMatch = sourceExp.firstMatch(block);
      final String srcUrl = _unescapeXml(srcMatch?.group(1) ?? '').trim();
      final String srcName = _unescapeXml(srcMatch?.group(2) ?? 'News').trim();

      if (srcName.isNotEmpty && title.endsWith(' - $srcName')) {
        title = title.substring(0, title.length - srcName.length - 3).trim();
      }
      if (title.isEmpty || !link.startsWith('http')) {
        continue;
      }

      final int pubMs = _parseRfc822DateMs(rawPub);
      items.add(
        PersonalizedNewsItem(
          title: title,
          url: link,
          sourceName: srcName.isEmpty ? 'News' : srcName,
          sourceUrl: srcUrl.isNotEmpty ? srcUrl : link,
          publishedAtMs: pubMs,
          timeLabel: _formatRelativeAge(pubMs, rawPub),
          matchedTopic: topicBadge,
        ),
      );
      if (items.length >= 16) {
        break;
      }
    }
    return items;
  }

  static int _parseRfc822DateMs(String raw) {
    if (raw.isEmpty) {
      return 0;
    }
    // Example: "Thu, 22 Oct 2026 14:25:00 GMT"
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
