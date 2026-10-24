import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/omnibox_parser.dart';

class DiscoverRegionConfig {
  const DiscoverRegionConfig({
    required this.countryCode,
    required this.countryName,
    required this.languageCode,
    required this.localDirectFeeds,
    required this.sportsHint,
    required this.entertainmentHint,
  });

  final String countryCode;
  final String countryName;
  final String languageCode;
  final List<({String source, String url})> localDirectFeeds;
  final String sportsHint;
  final String entertainmentHint;

  String get bingSetLang =>
      '${languageCode.toLowerCase()}-${countryCode.toLowerCase()}';

  @visibleForTesting
  static ui.Locale? debugLocaleOverride;

  static DiscoverRegionConfig detect() {
    final ui.Locale locale =
        debugLocaleOverride ?? ui.PlatformDispatcher.instance.locale;
    return fromLocaleAndOffset(locale, DateTime.now().timeZoneOffset);
  }

  static DiscoverRegionConfig fromLocaleAndOffset(
    ui.Locale locale,
    Duration tzOffset,
  ) {
    String cc = (locale.countryCode ?? '').trim().toUpperCase();
    final String rawLang = locale.languageCode.trim().toLowerCase();
    final String lang = rawLang.isEmpty ? 'en' : rawLang;

    if (cc.length != 2) {
      final int mins = tzOffset.inMinutes;
      if (mins == 330) {
        cc = 'IN';
      } else if (mins == 540) {
        cc = 'JP';
      } else if (mins == 480) {
        cc = 'SG';
      } else if (mins >= 600 && mins <= 660) {
        cc = 'AU';
      } else if (mins >= -480 && mins <= -240) {
        cc = 'US';
      } else if (mins == 60 || mins == 120) {
        cc = lang == 'fr'
            ? 'FR'
            : (lang == 'de' ? 'DE' : (lang == 'es' ? 'ES' : 'GB'));
      } else {
        cc = 'US';
      }
    }

    final String name = _countryNames[cc] ?? 'Local';
    return DiscoverRegionConfig(
      countryCode: cc,
      countryName: name,
      languageCode: lang,
      localDirectFeeds: _feedsForCountry(cc),
      sportsHint: _sportsQueryForCountry(cc, name),
      entertainmentHint: cc == 'IN'
          ? 'Bollywood Hollywood movies'
          : (cc == 'JP' || cc == 'KR'
                ? '$name anime cinema entertainment'
                : '$name movies television music'),
    );
  }

  static List<({String source, String url})> _feedsForCountry(String cc) {
    switch (cc) {
      case 'IN':
        return const <({String source, String url})>[
          (
            source: 'Times of India',
            url: 'https://timesofindia.indiatimes.com/rssfeedstopstories.cms',
          ),
          (
            source: 'NDTV',
            url: 'https://feeds.feedburner.com/ndtvnews-top-stories',
          ),
          (
            source: 'NDTV India',
            url: 'https://feeds.feedburner.com/ndtvnews-india-news',
          ),
        ];
      case 'US':
        return const <({String source, String url})>[
          (source: 'NPR News', url: 'https://feeds.npr.org/1001/rss.xml'),
          (
            source: 'NYT Top Stories',
            url: 'https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml',
          ),
          (
            source: 'BBC US & Canada',
            url: 'https://feeds.bbci.co.uk/news/world/us_and_canada/rss.xml',
          ),
        ];
      case 'GB':
        return const <({String source, String url})>[
          (source: 'BBC UK', url: 'https://feeds.bbci.co.uk/news/uk/rss.xml'),
          (
            source: 'The Guardian UK',
            url: 'https://www.theguardian.com/uk-news/rss',
          ),
        ];
      case 'CA':
        return const <({String source, String url})>[
          (
            source: 'CBC Top Stories',
            url: 'https://www.cbc.ca/webfeed/rss/rss-topstories',
          ),
          (
            source: 'BBC US & Canada',
            url: 'https://feeds.bbci.co.uk/news/world/us_and_canada/rss.xml',
          ),
        ];
      case 'AU':
        return const <({String source, String url})>[
          (
            source: 'ABC News AU',
            url: 'https://www.abc.net.au/news/feed/51120/rss.xml',
          ),
          (
            source: 'BBC Australia',
            url: 'https://feeds.bbci.co.uk/news/world/australia/rss.xml',
          ),
        ];
      default:
        return const <({String source, String url})>[
          (
            source: 'BBC World',
            url: 'https://feeds.bbci.co.uk/news/world/rss.xml',
          ),
          (
            source: 'The Guardian World',
            url: 'https://www.theguardian.com/world/rss',
          ),
        ];
    }
  }

  static String _sportsQueryForCountry(String cc, String countryName) {
    switch (cc) {
      case 'IN':
      case 'PK':
      case 'BD':
      case 'LK':
        return '$countryName Cricket IPL sports';
      case 'US':
        return 'NFL NBA MLB sports';
      case 'GB':
      case 'DE':
      case 'FR':
      case 'ES':
      case 'IT':
        return '$countryName Premier League Champions League F1 sports';
      case 'CA':
        return 'NHL NBA Canada sports';
      case 'AU':
      case 'NZ':
        return '$countryName Cricket AFL NRL sports';
      default:
        return '$countryName football sports';
    }
  }

  static const Map<String, String> _countryNames = <String, String>{
    'US': 'United States',
    'GB': 'United Kingdom',
    'IN': 'India',
    'CA': 'Canada',
    'AU': 'Australia',
    'DE': 'Germany',
    'FR': 'France',
    'ES': 'Spain',
    'IT': 'Italy',
    'NL': 'Netherlands',
    'SE': 'Sweden',
    'NO': 'Norway',
    'DK': 'Denmark',
    'FI': 'Finland',
    'CH': 'Switzerland',
    'AT': 'Austria',
    'BE': 'Belgium',
    'IE': 'Ireland',
    'PT': 'Portugal',
    'PL': 'Poland',
    'JP': 'Japan',
    'KR': 'South Korea',
    'SG': 'Singapore',
    'MY': 'Malaysia',
    'ID': 'Indonesia',
    'PH': 'Philippines',
    'TH': 'Thailand',
    'VN': 'Vietnam',
    'AE': 'UAE',
    'SA': 'Saudi Arabia',
    'IL': 'Israel',
    'TR': 'Turkey',
    'BR': 'Brazil',
    'MX': 'Mexico',
    'AR': 'Argentina',
    'CL': 'Chile',
    'CO': 'Colombia',
    'ZA': 'South Africa',
    'NG': 'Nigeria',
    'KE': 'Kenya',
    'EG': 'Egypt',
    'NZ': 'New Zealand',
    'PK': 'Pakistan',
    'BD': 'Bangladesh',
    'LK': 'Sri Lanka',
    'NP': 'Nepal',
  };
}

enum NewsCategoryTab {
  forYou(
    label: 'For You',
    query: 'technology science world',
    directRssUrls: <({String source, String url})>[
      (source: 'BBC News', url: 'https://feeds.bbci.co.uk/news/world/rss.xml'),
      (source: 'The Verge', url: 'https://www.theverge.com/rss/index.xml'),
      (
        source: 'Ars Technica',
        url: 'https://feeds.arstechnica.com/arstechnica/index',
      ),
    ],
  ),
  localCountry(
    label: 'Top Local',
    query: 'breaking news',
    directRssUrls: <({String source, String url})>[],
  ),
  tech(
    label: 'Tech & AI',
    query: 'AI smartphones technology',
    directRssUrls: <({String source, String url})>[
      (source: 'The Verge', url: 'https://www.theverge.com/rss/index.xml'),
      (
        source: 'Ars Technica',
        url: 'https://feeds.arstechnica.com/arstechnica/index',
      ),
      (source: 'Wired', url: 'https://www.wired.com/feed/rss'),
      (source: 'Engadget', url: 'https://www.engadget.com/rss.xml'),
      (
        source: 'BBC Tech',
        url: 'https://feeds.bbci.co.uk/news/technology/rss.xml',
      ),
    ],
  ),
  entertainment(
    label: 'Movies & Showbiz',
    query: 'Hollywood movies television',
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
    query: 'football cricket F1 sports',
    directRssUrls: <({String source, String url})>[
      (source: 'BBC Sport', url: 'https://feeds.bbci.co.uk/sport/rss.xml'),
    ],
  ),
  gaming(
    label: 'Gaming',
    query: 'PlayStation PC video games',
    directRssUrls: <({String source, String url})>[
      (source: 'IGN', url: 'https://feeds.feedburner.com/ign/all'),
    ],
  ),
  business(
    label: 'Business',
    query: 'stock market startups economy',
    directRssUrls: <({String source, String url})>[
      (
        source: 'BBC Business',
        url: 'https://feeds.bbci.co.uk/news/business/rss.xml',
      ),
      (
        source: 'CoinDesk',
        url: 'https://www.coindesk.com/arc/outboundfeeds/rss/',
      ),
    ],
  ),
  science(
    label: 'Science',
    query: 'NASA space astronomy science',
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

  String resolvedLabel([DiscoverRegionConfig? region]) {
    if (this == NewsCategoryTab.localCountry) {
      return (region ?? DiscoverRegionConfig.detect()).countryName;
    }
    return label;
  }

  String resolvedQuery(DiscoverRegionConfig region) {
    switch (this) {
      case NewsCategoryTab.forYou:
        return '${region.countryName} technology science world';
      case NewsCategoryTab.localCountry:
        return '${region.countryName} breaking news';
      case NewsCategoryTab.entertainment:
        return region.entertainmentHint;
      case NewsCategoryTab.sports:
        return region.sportsHint;
      case NewsCategoryTab.business:
        return '${region.countryName} stock market startups';
      case NewsCategoryTab.tech:
      case NewsCategoryTab.gaming:
      case NewsCategoryTab.science:
        return query;
    }
  }

  List<({String source, String url})> resolvedDirectFeeds(
    DiscoverRegionConfig region,
  ) {
    if (this == NewsCategoryTab.localCountry) {
      return region.localDirectFeeds;
    }
    if (this == NewsCategoryTab.forYou) {
      return <({String source, String url})>[
        ...region.localDirectFeeds.take(2),
        ...directRssUrls,
      ];
    }
    return directRssUrls;
  }
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

  bool get hasValidImage =>
      imageUrl != null && imageUrl!.trim().startsWith('http');

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
    final double elapsedDays = math.max(0.0, (nowMs - updatedAtMs) / 86400000);
    return score * math.pow(0.84, elapsedDays);
  }

  Map<String, Object?> toJson() => <String, Object?>{
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

  static const Map<String, ({String label, String query, List<String> keywords})>
  _curatedBuckets =
      <String, ({String label, String query, List<String> keywords})>{
        'tech': (
          label: 'Tech & AI',
          query: 'AI smartphones technology',
          keywords: <String>[
            'android',
            'apple',
            'iphone',
            'google',
            'openai',
            'chatgpt',
            'gemini',
            'flutter',
            'linux',
            'coding',
            'github',
            'laptop',
            'gpu',
            'nvidia',
            'tech',
            'software',
          ],
        ),
        'entertainment': (
          label: 'Movies & OTT',
          query: 'Bollywood Hollywood movies',
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
          label: 'Sports',
          query: 'Cricket football F1 sports',
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
          query: 'PlayStation GTA video games',
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
          query: 'Sensex Nifty Bitcoin markets',
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
          query: 'ISRO SpaceX NASA astronomy',
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
            if (parsed.key.isNotEmpty && parsed.query.isNotEmpty) {
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
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<InterestEntry> active =
        _entries.values
            .where((InterestEntry e) => e.decayedScore(now) >= 0.25)
            .toList()
          ..sort(
            (InterestEntry a, InterestEntry b) =>
                b.decayedScore(now).compareTo(a.decayedScore(now)),
          );
    final String encoded = jsonEncode(
      active.take(30).map((InterestEntry e) => e.toJson()).toList(),
    );
    await _prefs.setString(_storageKey, encoded);
  }

  Future<void> recordActivity({
    required String text,
    double weight = 1.5,
  }) async {
    String normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return;
    }
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      final Uri? uri = Uri.tryParse(normalized);
      if (uri != null) {
        final String hostPart = uri.host
            .replaceFirst(RegExp(r'^www\.'), '')
            .split('.')
            .first;
        final String pathPart = uri.pathSegments.join(' ');
        final String qPart = uri.queryParameters['q'] ?? '';
        normalized = '$hostPart $pathPart $qPart'.toLowerCase();
      }
    }

    final List<String> tokens = normalized
        .split(RegExp(r'[^a-z0-9]+'))
        .where((String w) => w.length >= 3 && !_stopWords.contains(w))
        .toList();
    if (tokens.isEmpty) {
      return;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;

    _curatedBuckets.forEach((
      String bucketKey,
      ({String label, String query, List<String> keywords}) info,
    ) {
      if (tokens.any((String t) => info.keywords.contains(t))) {
        _bumpEntry(
          key: 'cat:$bucketKey',
          label: info.label,
          query: info.query,
          delta: weight * 1.4,
          nowMs: now,
        );
      }
    });

    final List<String> meaningful = tokens
        .where((String t) => t.length >= 4 && !RegExp(r'^\d+$').hasMatch(t))
        .take(2)
        .toList();
    for (final String token in meaningful) {
      final String pretty = token[0].toUpperCase() + token.substring(1);
      _bumpEntry(
        key: 'kw:$token',
        label: pretty,
        query: pretty,
        delta: weight,
        nowMs: now,
      );
    }

    unawaited(_persist());
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

  static const String _cachePrefix = 'hb.newsFeedCache.v8.';

  final SharedPreferences prefs;
  final InterestProfileController interests;
  final http.Client _client;

  String _cacheKeyFor(NewsCategoryTab tab, DiscoverRegionConfig region) =>
      '$_cachePrefix${region.countryCode}.${tab.name}';

  List<PersonalizedNewsItem> readCached(NewsCategoryTab tab) {
    final DiscoverRegionConfig region = DiscoverRegionConfig.detect();
    final String? raw = prefs.getString(_cacheKeyFor(tab, region));
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
    final DiscoverRegionConfig region = DiscoverRegionConfig.detect();
    List<PersonalizedNewsItem> fetched;
    if (tab == NewsCategoryTab.forYou) {
      fetched = await _fetchPersonalizedForYou(region);
    } else {
      fetched = await _fetchCategoryFeed(tab, region);
    }

    if (fetched.isNotEmpty) {
      unawaited(
        prefs.setString(
          _cacheKeyFor(tab, region),
          jsonEncode(
            fetched
                .take(24)
                .map((PersonalizedNewsItem e) => e.toJson())
                .toList(),
          ),
        ),
      );
      return fetched;
    }
    return readCached(tab);
  }

  Future<List<PersonalizedNewsItem>> _fetchPersonalizedForYou(
    DiscoverRegionConfig region,
  ) async {
    final List<InterestEntry> topInterests = interests.rankedInterests
        .take(3)
        .toList(growable: false);

    final List<Future<List<PersonalizedNewsItem>>> tasks =
        <Future<List<PersonalizedNewsItem>>>[
          for (final ({String source, String url}) feed
              in NewsCategoryTab.forYou.resolvedDirectFeeds(region))
            _fetchDirectPublisherRss(feed.url, defaultSource: feed.source),
          for (final InterestEntry entry in topInterests)
            _fetchBingMediaNewsRss(
              _focusedNewsQuery(entry.query, region),
              topicBadge: entry.label,
              region: region,
            ),
          if (topInterests.isEmpty) ...<Future<List<PersonalizedNewsItem>>>[
            _fetchBingMediaNewsRss(
              '${region.countryName} top news technology',
              topicBadge: null,
              region: region,
            ),
            _fetchBingMediaNewsRss(
              'World science entertainment',
              topicBadge: null,
              region: region,
            ),
          ],
        ];

    return _mergeAndRankBatches(await Future.wait(tasks));
  }

  Future<List<PersonalizedNewsItem>> _fetchCategoryFeed(
    NewsCategoryTab tab,
    DiscoverRegionConfig region,
  ) async {
    final String badge = tab.resolvedLabel(region);
    final List<Future<List<PersonalizedNewsItem>>> tasks =
        <Future<List<PersonalizedNewsItem>>>[
          for (final ({String source, String url}) feed
              in tab.resolvedDirectFeeds(region))
            _fetchDirectPublisherRss(
              feed.url,
              defaultSource: feed.source,
              topicBadge: badge,
            ),
          _fetchBingMediaNewsRss(
            tab.resolvedQuery(region),
            topicBadge: badge,
            region: region,
          ),
        ];

    return _mergeAndRankBatches(await Future.wait(tasks));
  }

  static String _focusedNewsQuery(String raw, DiscoverRegionConfig region) {
    final List<String> words = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((String w) => w.length >= 2)
        .take(3)
        .toList();
    return words.isEmpty ? '${region.countryName} news' : words.join(' ');
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
        final double topicBonus = item.matchedTopic != null ? 5.0 : 0.0;
        final double imageBonus = item.hasValidImage ? 40.0 : 0.0;

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

    // Ensure Google Discover cards always display real cover photos whenever image items exist!
    final List<PersonalizedNewsItem> withImages = merged
        .where((PersonalizedNewsItem e) => e.hasValidImage)
        .toList(growable: false);
    if (withImages.isNotEmpty) {
      return withImages.take(24).toList(growable: false);
    }
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
              'User-Agent': 'Mozilla/5.0 (compatible; HeavenBrowser/1.0)',
              'Accept':
                  'application/rss+xml, application/atom+xml, application/xml, text/xml',
            },
          )
          .timeout(const Duration(seconds: 6));
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

  /// Fast Bing News RSS with `<News:Image>` 800x450 HD cover photos (~250ms)!
  Future<List<PersonalizedNewsItem>> _fetchBingMediaNewsRss(
    String query, {
    required String? topicBadge,
    required DiscoverRegionConfig region,
  }) async {
    try {
      final Uri uri = Uri.parse(
        'https://www.bing.com/news/search?q=${Uri.encodeQueryComponent(query)}'
        '&format=rss&setlang=${Uri.encodeQueryComponent(region.bingSetLang)}'
        '&cc=${Uri.encodeQueryComponent(region.countryCode)}',
      );
      final http.Response response = await _client
          .get(
            uri,
            headers: const <String, String>{
              'User-Agent': 'Mozilla/5.0 (compatible; HeavenBrowser/1.0)',
              'Accept': 'application/rss+xml, application/xml, text/xml',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200 || response.body.isEmpty) {
        return const <PersonalizedNewsItem>[];
      }
      return parseRichFeedXml(
        response.body,
        defaultSource: 'News',
        topicBadge: topicBadge,
      );
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
      r'src="((?:https?:\/\/www\.bing\.com)?\/th\?id=[^"]+)"',
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
        imageUrl = _normalizeCoverImageUrl(_unescapeXml(im.group(1) ?? ''));
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

  /// Parses RSS `<item>`, Atom `<entry>`, and Bing `<News:Image>` XML feeds with HD cover photos!
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
    final RegExp bingSourceExp = RegExp(
      r'<News:Source>([\s\S]*?)</News:Source>',
      caseSensitive: false,
    );
    final RegExp bingImgExp = RegExp(
      r'<News:Image>([\s\S]*?)</News:Image>',
      caseSensitive: false,
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
      r'<img[^>]*\bsrc="(https?:\/\/[^"\s>]+)"',
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

      // Unwrap Bing News RSS apiclick redirect URLs straight to the publisher article!
      link = _unwrapBingNewsRedirect(link);

      final String rawPub = _unescapeXml(
        pubDateExp.firstMatch(block)?.group(1) ?? '',
      ).trim();

      final RegExpMatch? srcMatch = sourceExp.firstMatch(block);
      final String srcUrl = _unescapeXml(srcMatch?.group(1) ?? '').trim();
      final String bingSrc = _stripHtml(
        bingSourceExp.firstMatch(block)?.group(1) ?? '',
      );
      String srcName = _stripHtml(
        srcMatch?.group(2) ?? (bingSrc.isNotEmpty ? bingSrc : defaultSource),
      ).trim();
      if (srcName.endsWith(' on MSN')) {
        srcName = srcName.substring(0, srcName.length - 7).trim();
      }

      if (srcName.isNotEmpty && title.endsWith(' - $srcName')) {
        title = title.substring(0, title.length - srcName.length - 3).trim();
      }
      if (title.isEmpty || !link.startsWith('http')) {
        continue;
      }

      final String rawImgCandidate = _unescapeXml(
        bingImgExp.firstMatch(block)?.group(1) ??
            mediaUrlExp.firstMatch(block)?.group(1) ??
            storyImgExp.firstMatch(block)?.group(1) ??
            inlineImgExp.firstMatch(_unescapeXml(block))?.group(1) ??
            '',
      ).trim();

      final String? img = _normalizeCoverImageUrl(rawImgCandidate);

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
      if (items.length >= 18) {
        break;
      }
    }
    return items;
  }

  static String _unwrapBingNewsRedirect(String rawLink) {
    if (!rawLink.contains('bing.com/news/apiclick')) {
      return rawLink;
    }
    final Uri? parsed = Uri.tryParse(rawLink);
    final String? realUrl = parsed?.queryParameters['url'];
    if (realUrl != null && realUrl.startsWith('http')) {
      return realUrl.trim();
    }
    return rawLink;
  }

  static String? _normalizeCoverImageUrl(String raw) {
    if (raw.isEmpty) return null;
    String url = raw.trim();
    if (url.startsWith('//')) {
      url = 'https:$url';
    } else if (url.startsWith('/th?')) {
      url = 'https://www.bing.com$url';
    } else if (url.startsWith('http://www.bing.com/')) {
      url = 'https://${url.substring(7)}';
    } else if (url.startsWith('http://')) {
      url = 'https://${url.substring(7)}';
    }

    if (!url.startsWith('https://')) {
      return null;
    }
    final String lower = url.toLowerCase();
    if (lower.endsWith('.svg') ||
        lower.contains('1x1') ||
        lower.contains('pixel') ||
        lower.contains('feedburner.com/~ff')) {
      return null;
    }

    // Upgrade BBC 240px thumbnails to 800px HD
    url = url.replaceFirst('/standard/240/', '/standard/800/');

    // Upgrade Bing News <News:Image> thumbnails to crisp 800x450 16:9 HD JPEG!
    if (url.contains('bing.com/th?')) {
      if (RegExp(r'[?&]w=\d+').hasMatch(url)) {
        url = url
            .replaceAll(RegExp(r'w=\d+'), 'w=800')
            .replaceAll(RegExp(r'h=\d+'), 'h=450');
      } else {
        url = '$url&w=800&h=450&c=7';
      }
    }
    return url;
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
    if (input.isEmpty) return '';
    String out = input
        .replaceAll('<![CDATA[', '')
        .replaceAll(']]>', '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');

    // Decode decimal entities like &#038; -> & and &#8217; -> '
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (Match m) {
      final int? code = int.tryParse(m.group(1)!);
      return (code != null && code > 0 && code <= 0x10FFFF)
          ? String.fromCharCode(code)
          : m.group(0)!;
    });

    // Decode hex entities like &#x26; -> &
    out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (Match m) {
      final int? code = int.tryParse(m.group(1)!, radix: 16);
      return (code != null && code > 0 && code <= 0x10FFFF)
          ? String.fromCharCode(code)
          : m.group(0)!;
    });

    return out.trim();
  }

  void dispose() {
    _client.close();
  }
}
