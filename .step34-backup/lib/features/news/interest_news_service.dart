import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/omnibox_parser.dart';

enum NewsCategoryTab {
  forYou(
    label: 'For You',
    query: 'world technology science entertainment',
    refreshQueries: <String>[
      'breaking world headlines today',
      'latest technology science discoveries',
      'global business innovation cinema',
      'trending world sports gaming news',
    ],
    directRssUrls: <({String source, String url})>[
      (source: 'BBC News', url: 'https://feeds.bbci.co.uk/news/world/rss.xml'),
      (
        source: 'The Guardian',
        url: 'https://www.theguardian.com/world/rss',
      ),
      (source: 'NPR News', url: 'https://feeds.npr.org/1001/rss.xml'),
      (source: 'The Verge', url: 'https://www.theverge.com/rss/index.xml'),
      (
        source: 'Ars Technica',
        url: 'https://feeds.arstechnica.com/arstechnica/index',
      ),
    ],
  ),
  tech(
    label: 'Technology',
    query: 'smartphones gadgets software technology',
    refreshQueries: <String>[
      'smartphones laptops hardware launches',
      'cybersecurity open source software',
      'semiconductors chips computing',
      'consumer electronics apps gadgets',
    ],
    directRssUrls: <({String source, String url})>[
      (source: 'The Verge', url: 'https://www.theverge.com/rss/index.xml'),
      (
        source: 'Ars Technica',
        url: 'https://feeds.arstechnica.com/arstechnica/index',
      ),
      (source: 'Wired', url: 'https://www.wired.com/feed/rss'),
      (source: 'Engadget', url: 'https://www.engadget.com/rss.xml'),
      (
        source: 'TechCrunch',
        url: 'https://techcrunch.com/feed/',
      ),
      (
        source: 'BBC Tech',
        url: 'https://feeds.bbci.co.uk/news/technology/rss.xml',
      ),
    ],
  ),
  entertainment(
    label: 'Movies & Showbiz',
    query: 'movies cinema streaming music entertainment',
    refreshQueries: <String>[
      'new movie releases box office cinema',
      'streaming series television trailers',
      'music albums concerts pop culture',
      'film festivals directors actors',
    ],
    directRssUrls: <({String source, String url})>[
      (
        source: 'BBC Entertainment',
        url: 'https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml',
      ),
      (source: 'Variety', url: 'https://variety.com/feed/'),
      (
        source: 'The Guardian Film',
        url: 'https://www.theguardian.com/film/rss',
      ),
      (source: 'IGN', url: 'https://feeds.feedburner.com/ign/all'),
    ],
  ),
  sports(
    label: 'Sports',
    query: 'football cricket F1 basketball sports',
    refreshQueries: <String>[
      'Champions League Premier League football',
      'international cricket test T20 matches',
      'Formula 1 motorsport tennis Grand Slam',
      'NBA Olympics athletics world sports',
    ],
    directRssUrls: <({String source, String url})>[
      (source: 'BBC Sport', url: 'https://feeds.bbci.co.uk/sport/rss.xml'),
      (
        source: 'The Guardian Sport',
        url: 'https://www.theguardian.com/uk/sport/rss',
      ),
      (
        source: 'ESPN',
        url: 'https://www.espn.com/espn/rss/news',
      ),
    ],
  ),
  gaming(
    label: 'Gaming',
    query: 'PlayStation PC Xbox Nintendo video games',
    refreshQueries: <String>[
      'PlayStation 5 Xbox PC game releases',
      'Nintendo Switch Steam indie games',
      'esports tournaments gaming hardware',
      'upcoming RPG action adventure games',
    ],
    directRssUrls: <({String source, String url})>[
      (source: 'IGN', url: 'https://feeds.feedburner.com/ign/all'),
      (source: 'Polygon', url: 'https://www.polygon.com/rss/index.xml'),
      (source: 'Eurogamer', url: 'https://www.eurogamer.net/feed'),
    ],
  ),
  business(
    label: 'Business',
    query: 'global markets startups economy finance',
    refreshQueries: <String>[
      'stock markets Wall Street global economy',
      'venture capital startups fintech',
      'bitcoin crypto digital assets',
      'energy trade central banks business',
    ],
    directRssUrls: <({String source, String url})>[
      (
        source: 'BBC Business',
        url: 'https://feeds.bbci.co.uk/news/business/rss.xml',
      ),
      (
        source: 'CNBC World',
        url: 'https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100727362',
      ),
      (
        source: 'CoinDesk',
        url: 'https://www.coindesk.com/arc/outboundfeeds/rss/',
      ),
    ],
  ),
  science(
    label: 'Science',
    query: 'NASA SpaceX astronomy physics science',
    refreshQueries: <String>[
      'NASA James Webb telescope astronomy',
      'SpaceX rocket launch space exploration',
      'quantum physics climate biology',
      'medical breakthroughs archaeology discoveries',
    ],
    directRssUrls: <({String source, String url})>[
      (source: 'Space.com', url: 'https://www.space.com/feeds/all'),
      (
        source: 'ScienceDaily',
        url: 'https://www.sciencedaily.com/rss/top/science.xml',
      ),
      (
        source: 'BBC Science',
        url: 'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml',
      ),
    ],
  );

  const NewsCategoryTab({
    required this.label,
    required this.query,
    required this.refreshQueries,
    required this.directRssUrls,
  });

  final String label;
  final String query;
  final List<String> refreshQueries;
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
          label: 'Technology',
          query: 'smartphones gadgets software technology',
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
          label: 'Movies & Showbiz',
          query: 'movies cinema streaming music',
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
          query: 'football cricket F1 sports',
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
          query: 'global stock markets Bitcoin finance',
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
          query: 'SpaceX NASA astronomy science',
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

  static const String _cachePrefix = 'hb.newsFeedCache.global.v28.';

  final SharedPreferences prefs;
  final InterestProfileController interests;
  final http.Client _client;

  final Map<NewsCategoryTab, Set<String>> _seenUrlsByTab =
      <NewsCategoryTab, Set<String>>{};
  final Map<NewsCategoryTab, List<String>> _lastTopUrlsByTab =
      <NewsCategoryTab, List<String>>{};
  final Map<NewsCategoryTab, int> _refreshCycleByTab =
      <NewsCategoryTab, int>{};

  String _cacheKeyFor(NewsCategoryTab tab) => '$_cachePrefix${tab.name}';

  List<PersonalizedNewsItem> readCached(NewsCategoryTab tab) {
    final String? raw = prefs.getString(_cacheKeyFor(tab));
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

  Future<List<PersonalizedNewsItem>> fetchFeed(
    NewsCategoryTab tab, {
    bool forceRefresh = false,
  }) async {
    final int nextCycle = forceRefresh
        ? ((_refreshCycleByTab[tab] ?? 0) + 1)
        : (_refreshCycleByTab[tab] ?? 0);
    _refreshCycleByTab[tab] = nextCycle;

    final List<PersonalizedNewsItem> pool = (tab == NewsCategoryTab.forYou)
        ? await _fetchPersonalizedForYou(
            cycle: nextCycle,
            forceRefresh: forceRefresh,
          )
        : await _fetchCategoryFeed(
            tab,
            cycle: nextCycle,
            forceRefresh: forceRefresh,
          );

    if (pool.isEmpty) {
      final List<PersonalizedNewsItem> cached = readCached(tab);
      if (forceRefresh && cached.length > 1) {
        return _rotateStoriesForRefresh(tab, cached);
      }
      return cached;
    }

    final List<PersonalizedNewsItem> selected = forceRefresh
        ? _rotateStoriesForRefresh(tab, pool)
        : pool.take(24).toList(growable: false);

    _lastTopUrlsByTab[tab] = selected
        .take(math.max(1, math.min(6, selected.length ~/ 2)))
        .map((PersonalizedNewsItem e) => e.url)
        .toList(growable: false);

    unawaited(
      prefs.setString(
        _cacheKeyFor(tab),
        jsonEncode(
          selected
              .take(24)
              .map((PersonalizedNewsItem e) => e.toJson())
              .toList(),
        ),
      ),
    );
    return selected;
  }

  List<PersonalizedNewsItem> _rotateStoriesForRefresh(
    NewsCategoryTab tab,
    List<PersonalizedNewsItem> pool,
  ) {
    if (pool.length <= 1) {
      return pool;
    }
    final Set<String> seen = _seenUrlsByTab.putIfAbsent(
      tab,
      () => <String>{},
    );
    final List<String> previousTop = _lastTopUrlsByTab[tab] ?? const <String>[];
    if (previousTop.isNotEmpty) {
      seen.addAll(previousTop);
    } else {
      // First explicit refresh after initial load: rotate past the initial top slice
      final int initialSlice = math.max(1, math.min(6, pool.length ~/ 2));
      for (int i = 0; i < initialSlice; i++) {
        seen.add(pool[i].url);
      }
    }

    List<PersonalizedNewsItem> unseen = pool
        .where((PersonalizedNewsItem item) => !seen.contains(item.url))
        .toList(growable: false);
    List<PersonalizedNewsItem> previouslySeen = pool
        .where((PersonalizedNewsItem item) => seen.contains(item.url))
        .toList(growable: false);

    if (unseen.isEmpty) {
      // Whole candidate pool has been viewed — reset cycle while still rotating
      // away from the stories that were just at the top of the screen!
      seen.clear();
      final Set<String> justShown = previousTop.isNotEmpty
          ? previousTop.take(math.max(1, pool.length ~/ 2)).toSet()
          : <String>{pool.first.url};
      seen.addAll(justShown);
      unseen = pool
          .where((PersonalizedNewsItem item) => !seen.contains(item.url))
          .toList(growable: false);
      previouslySeen = pool
          .where((PersonalizedNewsItem item) => seen.contains(item.url))
          .toList(growable: false);
    }

    final List<PersonalizedNewsItem> combined = <PersonalizedNewsItem>[
      ...unseen,
      ...previouslySeen,
    ].take(24).toList(growable: false);

    _lastTopUrlsByTab[tab] = combined
        .take(math.max(1, math.min(6, combined.length ~/ 2)))
        .map((PersonalizedNewsItem e) => e.url)
        .toList(growable: false);
    return combined;
  }

  Future<List<PersonalizedNewsItem>> _fetchPersonalizedForYou({
    required int cycle,
    required bool forceRefresh,
  }) async {
    final List<InterestEntry> allRanked = interests.rankedInterests;
    final List<InterestEntry> selectedInterests;
    if (allRanked.length <= 3) {
      selectedInterests = allRanked;
    } else {
      final int start = (cycle * 2) % allRanked.length;
      selectedInterests = <InterestEntry>[
        for (int i = 0; i < 3; i++) allRanked[(start + i) % allRanked.length],
      ];
    }

    final List<String> rotatingAngles = NewsCategoryTab.forYou.refreshQueries;
    final String primaryAngle = rotatingAngles[cycle % rotatingAngles.length];
    final String secondaryAngle =
        rotatingAngles[(cycle + 1) % rotatingAngles.length];

    final List<Future<List<PersonalizedNewsItem>>> tasks =
        <Future<List<PersonalizedNewsItem>>>[
          for (final ({String source, String url}) feed
              in NewsCategoryTab.forYou.directRssUrls)
            _fetchDirectPublisherRss(
              feed.url,
              defaultSource: feed.source,
              forceRefresh: forceRefresh,
            ),
          for (final InterestEntry entry in selectedInterests)
            _fetchBingMediaNewsRss(
              _focusedNewsQuery(entry.query),
              topicBadge: entry.label,
              forceRefresh: forceRefresh,
            ),
          _fetchBingMediaNewsRss(
            primaryAngle,
            topicBadge: null,
            forceRefresh: forceRefresh,
          ),
          if (selectedInterests.isEmpty || forceRefresh)
            _fetchBingMediaNewsRss(
              secondaryAngle,
              topicBadge: null,
              forceRefresh: forceRefresh,
            ),
        ];

    return _mergeAndRankBatches(await Future.wait(tasks));
  }

  Future<List<PersonalizedNewsItem>> _fetchCategoryFeed(
    NewsCategoryTab tab, {
    required int cycle,
    required bool forceRefresh,
  }) async {
    final String badge = tab.label;
    final String dynamicQuery = tab.refreshQueries.isEmpty
        ? tab.query
        : tab.refreshQueries[cycle % tab.refreshQueries.length];

    final List<Future<List<PersonalizedNewsItem>>> tasks =
        <Future<List<PersonalizedNewsItem>>>[
          for (final ({String source, String url}) feed in tab.directRssUrls)
            _fetchDirectPublisherRss(
              feed.url,
              defaultSource: feed.source,
              topicBadge: badge,
              forceRefresh: forceRefresh,
            ),
          _fetchBingMediaNewsRss(
            tab.query,
            topicBadge: badge,
            forceRefresh: forceRefresh,
          ),
          if (dynamicQuery != tab.query)
            _fetchBingMediaNewsRss(
              dynamicQuery,
              topicBadge: badge,
              forceRefresh: forceRefresh,
            ),
        ];

    return _mergeAndRankBatches(await Future.wait(tasks));
  }

  static String _focusedNewsQuery(String raw) {
    final List<String> words = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((String w) => w.length >= 2)
        .take(3)
        .toList();
    return words.isEmpty ? 'world headlines news' : words.join(' ');
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

    final List<PersonalizedNewsItem> withImages = merged
        .where((PersonalizedNewsItem e) => e.hasValidImage)
        .toList(growable: false);
    if (withImages.isNotEmpty) {
      return withImages.take(72).toList(growable: false);
    }
    return merged.take(72).toList(growable: false);
  }

  Future<List<PersonalizedNewsItem>> _fetchDirectPublisherRss(
    String feedUrl, {
    required String defaultSource,
    String? topicBadge,
    bool forceRefresh = false,
  }) async {
    try {
      final http.Response response = await _client
          .get(
            Uri.parse(feedUrl),
            headers: <String, String>{
              'User-Agent': 'Mozilla/5.0 (compatible; HeavenBrowser/1.0)',
              'Accept':
                  'application/rss+xml, application/atom+xml, application/xml, text/xml',
              if (forceRefresh) 'Cache-Control': 'no-cache, max-age=0',
              if (forceRefresh) 'Pragma': 'no-cache',
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

  /// Fast global Bing News RSS with `<News:Image>` 800x450 HD cover photos (zero country filter)!
  Future<List<PersonalizedNewsItem>> _fetchBingMediaNewsRss(
    String query, {
    required String? topicBadge,
    bool forceRefresh = false,
  }) async {
    try {
      final Uri uri = Uri.parse(
        'https://www.bing.com/news/search?q=${Uri.encodeQueryComponent(query)}'
        '&format=rss&setlang=en',
      );
      final http.Response response = await _client
          .get(
            uri,
            headers: <String, String>{
              'User-Agent': 'Mozilla/5.0 (compatible; HeavenBrowser/1.0)',
              'Accept': 'application/rss+xml, application/xml, text/xml',
              if (forceRefresh) 'Cache-Control': 'no-cache, max-age=0',
              if (forceRefresh) 'Pragma': 'no-cache',
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
      if (out.length >= 24) break;
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
      if (items.length >= 30) {
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

    url = url.replaceFirst('/standard/240/', '/standard/800/');

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

    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (Match m) {
      final int? code = int.tryParse(m.group(1)!);
      return (code != null && code > 0 && code <= 0x10FFFF)
          ? String.fromCharCode(code)
          : m.group(0)!;
    });

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
