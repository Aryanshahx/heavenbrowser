import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/omnibox_parser.dart';
import '../shield/native_shield_bridge.dart';

class SiteUsageEntry {
  const SiteUsageEntry({
    required this.domain,
    required this.url,
    required this.title,
    required this.visitCount,
    required this.lastVisitedMs,
    this.isPinned = false,
  });

  final String domain;
  final String url;
  final String title;
  final int visitCount;
  final int lastVisitedMs;
  final bool isPinned;

  SiteUsageEntry copyWith({
    String? url,
    String? title,
    int? visitCount,
    int? lastVisitedMs,
    bool? isPinned,
  }) {
    return SiteUsageEntry(
      domain: domain,
      url: url ?? this.url,
      title: title ?? this.title,
      visitCount: visitCount ?? this.visitCount,
      lastVisitedMs: lastVisitedMs ?? this.lastVisitedMs,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'domain': domain,
    'url': url,
    'title': title,
    'visitCount': visitCount,
    'lastVisitedMs': lastVisitedMs,
    'isPinned': isPinned,
  };

  factory SiteUsageEntry.fromJson(Map<String, Object?> json) {
    final String rawUrl = (json['url']?.toString() ?? '').trim();
    final String domain = (json['domain']?.toString() ?? '').trim().isNotEmpty
        ? json['domain']!.toString().trim()
        : OmniboxParser.cleanDomain(rawUrl);
    return SiteUsageEntry(
      domain: domain,
      url: rawUrl.isEmpty ? 'https://$domain' : rawUrl,
      title: (json['title']?.toString() ?? '').trim().isNotEmpty
          ? json['title']!.toString().trim()
          : OmniboxParser.friendlySiteTitleFromDomain(domain),
      visitCount: (json['visitCount'] is num)
          ? (json['visitCount']! as num).toInt()
          : 0,
      lastVisitedMs: (json['lastVisitedMs'] is num)
          ? (json['lastVisitedMs']! as num).toInt()
          : 0,
      isPinned: json['isPinned'] == true,
    );
  }
}

class BookmarkItem {
  const BookmarkItem({
    required this.title,
    required this.url,
    required this.createdAtMs,
  });

  final String title;
  final String url;
  final int createdAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'url': url,
    'createdAtMs': createdAtMs,
  };

  factory BookmarkItem.fromJson(Map<String, Object?> json) {
    return BookmarkItem(
      title: (json['title']?.toString() ?? 'Bookmark').trim(),
      url: (json['url']?.toString() ?? '').trim(),
      createdAtMs: (json['createdAtMs'] is num)
          ? (json['createdAtMs']! as num).toInt()
          : 0,
    );
  }
}

class HistoryItem {
  const HistoryItem({
    required this.title,
    required this.url,
    required this.visitedAtMs,
  });

  final String title;
  final String url;
  final int visitedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'url': url,
    'visitedAtMs': visitedAtMs,
  };

  factory HistoryItem.fromJson(Map<String, Object?> json) {
    return HistoryItem(
      title: (json['title']?.toString() ?? 'Page').trim(),
      url: (json['url']?.toString() ?? '').trim(),
      visitedAtMs: (json['visitedAtMs'] is num)
          ? (json['visitedAtMs']! as num).toInt()
          : 0,
    );
  }
}

class BrowserSettingsController extends ChangeNotifier {
  BrowserSettingsController(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  static const String _keySearchEngine = 'hb.searchEngine.v3';
  static const String _keyThemeMode = 'hb.themeMode.v3';
  static const String _keyBottomBar = 'hb.bottomOmnibox.v4';
  static const String _keyShieldEnabled = 'hb.shieldEnabled';
  static const String _keyHttpsUpgrade = 'hb.httpsUpgrade';
  static const String _keyBlockThirdPartyCookies = 'hb.blockThirdPartyCookies';
  static const String _keySendDntGpc = 'hb.sendDntGpc';
  static const String _keyClearOnExit = 'hb.clearOnExit';
  static const String _keyJavascriptEnabled = 'hb.javascriptEnabled';
  static const String _keyDesktopMode = 'hb.desktopMode';
  static const String _keyTextScalePercent = 'hb.textScalePercent';
  static const String _keyTotalBlocked = 'hb.totalBlocked';
  static const String _keyTrustedHosts = 'hb.trustedHosts';
  static const String _keyJsDisabledHosts = 'hb.jsDisabledHosts.v8';
  static const String _keyPopupAllowedHosts = 'hb.popupAllowedHosts.v8';
  static const String _keyRecentSearches = 'hb.recentSearches.v8';
  static const String _keyLanguage = 'hb.language.v8';
  static const String _keyGesturesEnabled = 'hb.gesturesEnabled.v8';
  static const String _keyEdgeSwipe = 'hb.edgeSwipe.v8';
  static const String _keyBarSwipeTabs = 'hb.barSwipeTabs.v8';
  static const String _keyDownloadNotifs = 'hb.downloadNotifs.v8';
  static const String _keyWebNotifs = 'hb.webNotifs.v8';
  static const String _keySiteUsage = 'hb.siteUsage.v3';
  static const String _keyHiddenDomains = 'hb.hiddenQuickDomains.v3';
  static const String _keyBookmarks = 'hb.bookmarks.v3';
  static const String _keyHistory = 'hb.history.v3';

  // Heaven Search is ALWAYS the default search engine, and TOP dock is ALWAYS default.
  SearchEngine _searchEngine = SearchEngine.heaven;
  ThemeMode _themeMode = ThemeMode.dark;
  BrowserLanguage _language = BrowserLanguage.en;
  bool _bottomOmnibox = false;
  bool _shieldEnabled = true;
  bool _httpsUpgrade = true;
  bool _blockThirdPartyCookies = true;
  bool _sendDntAndGpc = true;
  bool _clearOnExit = false;
  bool _javascriptEnabled = true;
  bool _desktopMode = false;
  bool _gesturesEnabled = true;
  bool _edgeSwipeNavigation = true;
  bool _barSwipeSwitchTabs = true;
  bool _downloadNotificationsEnabled = true;
  bool _webNotificationsEnabled = false;
  int _textScalePercent = 100;
  int _totalTrackersBlocked = 0;

  final Set<String> _trustedHosts = <String>{};
  final Set<String> _jsDisabledHosts = <String>{};
  final Set<String> _popupAllowedHosts = <String>{};
  List<String> _recentSearches = <String>[];
  final Map<String, SiteUsageEntry> _siteUsageByDomain =
      <String, SiteUsageEntry>{};
  final Set<String> _hiddenQuickDomains = <String>{};
  List<BookmarkItem> _bookmarks = <BookmarkItem>[];
  List<HistoryItem> _history = <HistoryItem>[];

  SharedPreferences get prefs => _prefs;
  SearchEngine get searchEngine => _searchEngine;
  ThemeMode get themeMode => _themeMode;
  BrowserLanguage get language => _language;
  bool get bottomOmnibox => _bottomOmnibox;
  bool get shieldEnabled => _shieldEnabled;
  bool get httpsUpgrade => _httpsUpgrade;
  bool get blockThirdPartyCookies => _blockThirdPartyCookies;
  bool get sendDntAndGpc => _sendDntAndGpc;
  bool get clearOnExit => _clearOnExit;
  bool get javascriptEnabled => _javascriptEnabled;
  bool get desktopMode => _desktopMode;
  bool get gesturesEnabled => _gesturesEnabled;
  bool get edgeSwipeNavigation => _edgeSwipeNavigation;
  bool get barSwipeSwitchTabs => _barSwipeSwitchTabs;
  bool get downloadNotificationsEnabled => _downloadNotificationsEnabled;
  bool get webNotificationsEnabled => _webNotificationsEnabled;
  int get textScalePercent => _textScalePercent;
  int get totalTrackersBlocked => _totalTrackersBlocked;
  Set<String> get trustedHosts => Set<String>.unmodifiable(_trustedHosts);
  List<String> get recentSearches => List<String>.unmodifiable(_recentSearches);
  List<BookmarkItem> get bookmarks =>
      List<BookmarkItem>.unmodifiable(_bookmarks);
  List<HistoryItem> get history => List<HistoryItem>.unmodifiable(_history);

  /// Returns ONLY websites actually visited or pinned by the user (zero starter clutter),
  /// automatically ranked by pin status and visit frequency.
  List<SiteUsageEntry> get quickLaunchSites {
    final List<SiteUsageEntry> pinned = <SiteUsageEntry>[];
    final List<SiteUsageEntry> frequent = <SiteUsageEntry>[];

    for (final SiteUsageEntry entry in _siteUsageByDomain.values) {
      if (_hiddenQuickDomains.contains(entry.domain)) {
        continue;
      }
      if (entry.isPinned) {
        pinned.add(entry);
      } else if (entry.visitCount > 0) {
        frequent.add(entry);
      }
    }

    pinned.sort((SiteUsageEntry a, SiteUsageEntry b) {
      final int byCount = b.visitCount.compareTo(a.visitCount);
      return byCount != 0
          ? byCount
          : b.lastVisitedMs.compareTo(a.lastVisitedMs);
    });

    frequent.sort((SiteUsageEntry a, SiteUsageEntry b) {
      final int byCount = b.visitCount.compareTo(a.visitCount);
      return byCount != 0
          ? byCount
          : b.lastVisitedMs.compareTo(a.lastVisitedMs);
    });

    return <SiteUsageEntry>[...pinned, ...frequent].take(8).toList();
  }

  void _load() {
    _searchEngine = SearchEngine.fromName(_prefs.getString(_keySearchEngine));
    _themeMode = switch (_prefs.getString(_keyThemeMode)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    // Default false = Top Dock Bar
    _bottomOmnibox = _prefs.getBool(_keyBottomBar) ?? false;
    _shieldEnabled = _prefs.getBool(_keyShieldEnabled) ?? true;
    _httpsUpgrade = _prefs.getBool(_keyHttpsUpgrade) ?? true;
    _blockThirdPartyCookies =
        _prefs.getBool(_keyBlockThirdPartyCookies) ?? true;
    _sendDntAndGpc = _prefs.getBool(_keySendDntGpc) ?? true;
    _clearOnExit = _prefs.getBool(_keyClearOnExit) ?? false;
    _javascriptEnabled = _prefs.getBool(_keyJavascriptEnabled) ?? true;
    _desktopMode = _prefs.getBool(_keyDesktopMode) ?? false;
    _textScalePercent = (_prefs.getInt(_keyTextScalePercent) ?? 100).clamp(
      75,
      175,
    );
    _totalTrackersBlocked = _prefs.getInt(_keyTotalBlocked) ?? 0;
    _language = BrowserLanguage.fromCode(_prefs.getString(_keyLanguage));
    _gesturesEnabled = _prefs.getBool(_keyGesturesEnabled) ?? true;
    _edgeSwipeNavigation = _prefs.getBool(_keyEdgeSwipe) ?? true;
    _barSwipeSwitchTabs = _prefs.getBool(_keyBarSwipeTabs) ?? true;
    _downloadNotificationsEnabled =
        _prefs.getBool(_keyDownloadNotifs) ?? true;
    _webNotificationsEnabled = _prefs.getBool(_keyWebNotifs) ?? false;

    final List<String>? savedJsDisabled = _prefs.getStringList(
      _keyJsDisabledHosts,
    );
    if (savedJsDisabled != null) {
      _jsDisabledHosts
        ..clear()
        ..addAll(savedJsDisabled);
    }

    final List<String>? savedPopupAllowed = _prefs.getStringList(
      _keyPopupAllowedHosts,
    );
    if (savedPopupAllowed != null) {
      _popupAllowedHosts
        ..clear()
        ..addAll(savedPopupAllowed);
    }

    final List<String>? savedRecent = _prefs.getStringList(_keyRecentSearches);
    if (savedRecent != null) {
      _recentSearches = savedRecent
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .take(15)
          .toList();
    }

    final List<String>? savedTrusted = _prefs.getStringList(_keyTrustedHosts);
    if (savedTrusted != null) {
      _trustedHosts
        ..clear()
        ..addAll(savedTrusted);
    }

    final List<String>? hidden = _prefs.getStringList(_keyHiddenDomains);
    if (hidden != null) {
      _hiddenQuickDomains
        ..clear()
        ..addAll(hidden);
    }

    final String? rawUsage = _prefs.getString(_keySiteUsage);
    if (rawUsage != null && rawUsage.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawUsage);
        if (decoded is List<Object?>) {
          for (final Object? item in decoded) {
            if (item is Map<String, Object?>) {
              final SiteUsageEntry entry = SiteUsageEntry.fromJson(item);
              if (entry.domain.isNotEmpty) {
                _siteUsageByDomain[entry.domain] = entry;
              }
            }
          }
        }
      } on FormatException {
        _siteUsageByDomain.clear();
      }
    }

    final String? rawBookmarks = _prefs.getString(_keyBookmarks);
    if (rawBookmarks != null && rawBookmarks.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawBookmarks);
        if (decoded is List<Object?>) {
          _bookmarks = decoded
              .whereType<Map<String, Object?>>()
              .map(BookmarkItem.fromJson)
              .where((BookmarkItem b) => b.url.isNotEmpty)
              .toList();
        }
      } on FormatException {
        _bookmarks = <BookmarkItem>[];
      }
    }

    final String? rawHistory = _prefs.getString(_keyHistory);
    if (rawHistory != null && rawHistory.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawHistory);
        if (decoded is List<Object?>) {
          _history = decoded
              .whereType<Map<String, Object?>>()
              .map(HistoryItem.fromJson)
              .where((HistoryItem h) => h.url.isNotEmpty)
              .toList();
        }
      } on FormatException {
        _history = <HistoryItem>[];
      }
    }

    _pushNativeShieldConfig();
  }

  void _pushNativeShieldConfig() {
    NativeShieldBridge.instance.syncShieldConfig(
      shieldEnabled: _shieldEnabled,
      desktopMode: _desktopMode,
      trustedHosts: _trustedHosts,
      sendDntAndGpc: _sendDntAndGpc,
    );
  }

  bool isHostTrusted(String? host) {
    if (host == null || host.isEmpty) {
      return false;
    }
    return _trustedHosts.contains(OmniboxParser.cleanDomain(host));
  }

  Future<void> toggleHostTrust(String host) async {
    final String normalized = OmniboxParser.cleanDomain(host);
    if (normalized.isEmpty) {
      return;
    }
    if (!_trustedHosts.remove(normalized)) {
      _trustedHosts.add(normalized);
    }
    await _prefs.setStringList(_keyTrustedHosts, _trustedHosts.toList());
    _pushNativeShieldConfig();
    notifyListeners();
  }

  Future<void> recordPageVisit({
    required String url,
    required String title,
  }) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final String cleanDomain = OmniboxParser.cleanDomain(uri.host);
    final String cleanTitle = title.trim().isNotEmpty
        ? title.trim()
        : OmniboxParser.friendlySiteTitleFromDomain(cleanDomain);

    if (cleanDomain.isNotEmpty && !_hiddenQuickDomains.contains(cleanDomain)) {
      final SiteUsageEntry? existing = _siteUsageByDomain[cleanDomain];
      final String canonicalOrigin = '${uri.scheme}://${uri.host}';
      final String shortLabel = existing != null && existing.isPinned
          ? existing.title
          : OmniboxParser.friendlySiteTitleFromDomain(cleanDomain);

      _siteUsageByDomain[cleanDomain] = SiteUsageEntry(
        domain: cleanDomain,
        url: existing != null && existing.isPinned
            ? existing.url
            : canonicalOrigin,
        title: shortLabel,
        visitCount: (existing?.visitCount ?? 0) + 1,
        lastVisitedMs: now,
        isPinned: existing?.isPinned ?? false,
      );
      await _persistSiteUsage();
    }

    if (_history.isEmpty || _history.first.url != url) {
      _history = <HistoryItem>[
        HistoryItem(title: cleanTitle, url: url, visitedAtMs: now),
        ..._history.where((HistoryItem h) => h.url != url).take(249),
      ];
      await _persistHistory();
    }

    notifyListeners();
  }

  Future<void> pinOrAddQuickLaunchSite({
    required String title,
    required String rawUrl,
  }) async {
    final Uri resolved = OmniboxParser.resolveInput(
      rawUrl,
      searchEngine: _searchEngine,
      httpsUpgrade: _httpsUpgrade,
    );
    final String domain = OmniboxParser.cleanDomain(resolved.toString());
    if (domain.isEmpty) {
      return;
    }
    _hiddenQuickDomains.remove(domain);
    await _prefs.setStringList(_keyHiddenDomains, _hiddenQuickDomains.toList());

    final SiteUsageEntry? existing = _siteUsageByDomain[domain];
    _siteUsageByDomain[domain] = SiteUsageEntry(
      domain: domain,
      url: resolved.toString(),
      title: title.trim().isEmpty
          ? OmniboxParser.friendlySiteTitleFromDomain(domain)
          : title.trim(),
      visitCount: (existing?.visitCount ?? 0) + 1,
      lastVisitedMs: DateTime.now().millisecondsSinceEpoch,
      isPinned: true,
    );
    await _persistSiteUsage();
    notifyListeners();
  }

  Future<void> togglePinQuickSite(String domain) async {
    final String clean = OmniboxParser.cleanDomain(domain);
    final SiteUsageEntry? existing = _siteUsageByDomain[clean];
    if (existing != null) {
      _siteUsageByDomain[clean] = existing.copyWith(
        isPinned: !existing.isPinned,
      );
      await _persistSiteUsage();
      notifyListeners();
    }
  }

  Future<void> removeQuickLaunchSite(String domain) async {
    final String clean = OmniboxParser.cleanDomain(domain);
    _siteUsageByDomain.remove(clean);
    _hiddenQuickDomains.add(clean);
    await _prefs.setStringList(_keyHiddenDomains, _hiddenQuickDomains.toList());
    await _persistSiteUsage();
    notifyListeners();
  }

  Future<void> restoreDefaultQuickLaunch() async {
    _hiddenQuickDomains.clear();
    await _prefs.remove(_keyHiddenDomains);
    notifyListeners();
  }

  bool isBookmarked(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    return _bookmarks.any((BookmarkItem b) => b.url == url);
  }

  Future<bool> toggleBookmark({
    required String url,
    required String title,
  }) async {
    if (url.isEmpty || OmniboxParser.isHeavenSearchUrl(url)) {
      return false;
    }
    final int idx = _bookmarks.indexWhere((BookmarkItem b) => b.url == url);
    bool added;
    if (idx >= 0) {
      _bookmarks = List<BookmarkItem>.of(_bookmarks)..removeAt(idx);
      added = false;
    } else {
      final String cleanTitle = title.trim().isNotEmpty
          ? title.trim()
          : OmniboxParser.formatDisplayUrl(url);
      _bookmarks = <BookmarkItem>[
        BookmarkItem(
          title: cleanTitle,
          url: url,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        ..._bookmarks,
      ];
      added = true;
    }
    await _persistBookmarks();
    notifyListeners();
    return added;
  }

  Future<void> removeBookmark(String url) async {
    _bookmarks = _bookmarks.where((BookmarkItem b) => b.url != url).toList();
    await _persistBookmarks();
    notifyListeners();
  }

  Future<void> deleteHistoryItem(HistoryItem target) async {
    _history = _history
        .where(
          (HistoryItem h) =>
              !(h.url == target.url && h.visitedAtMs == target.visitedAtMs),
        )
        .toList();
    await _persistHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history = <HistoryItem>[];
    await _prefs.remove(_keyHistory);
    notifyListeners();
  }

  Future<void> clearUsageAndHistory() async {
    _history = <HistoryItem>[];
    _siteUsageByDomain.removeWhere((_, SiteUsageEntry v) => !v.isPinned);
    await _prefs.remove(_keyHistory);
    await _persistSiteUsage();
    notifyListeners();
  }

  Future<void> _persistSiteUsage() async {
    final String encoded = jsonEncode(
      _siteUsageByDomain.values.map((SiteUsageEntry e) => e.toJson()).toList(),
    );
    await _prefs.setString(_keySiteUsage, encoded);
  }

  Future<void> _persistBookmarks() async {
    final String encoded = jsonEncode(
      _bookmarks.map((BookmarkItem b) => b.toJson()).toList(),
    );
    await _prefs.setString(_keyBookmarks, encoded);
  }

  Future<void> _persistHistory() async {
    final String encoded = jsonEncode(
      _history.map((HistoryItem h) => h.toJson()).toList(),
    );
    await _prefs.setString(_keyHistory, encoded);
  }

  int _lastBlockedNotifyMs = 0;

  Future<void> incrementBlockedCount([int delta = 1]) async {
    if (delta <= 0) {
      return;
    }
    _totalTrackersBlocked += delta;
    await _prefs.setInt(_keyTotalBlocked, _totalTrackersBlocked);
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBlockedNotifyMs >= 350) {
      _lastBlockedNotifyMs = now;
      notifyListeners();
    }
  }

  Future<void> setSearchEngine(SearchEngine engine) async {
    _searchEngine = engine;
    await _prefs.setString(_keySearchEngine, engine.name);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final String raw = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
    await _prefs.setString(_keyThemeMode, raw);
    notifyListeners();
  }

  Future<void> setBottomOmnibox(bool value) async {
    _bottomOmnibox = value;
    await _prefs.setBool(_keyBottomBar, value);
    notifyListeners();
  }

  Future<void> setShieldEnabled(bool value) async {
    _shieldEnabled = value;
    await _prefs.setBool(_keyShieldEnabled, value);
    _pushNativeShieldConfig();
    notifyListeners();
  }

  Future<void> setHttpsUpgrade(bool value) async {
    _httpsUpgrade = value;
    await _prefs.setBool(_keyHttpsUpgrade, value);
    notifyListeners();
  }

  Future<void> setBlockThirdPartyCookies(bool value) async {
    _blockThirdPartyCookies = value;
    await _prefs.setBool(_keyBlockThirdPartyCookies, value);
    notifyListeners();
  }

  Future<void> setSendDntAndGpc(bool value) async {
    _sendDntAndGpc = value;
    await _prefs.setBool(_keySendDntGpc, value);
    _pushNativeShieldConfig();
    notifyListeners();
  }

  Future<void> setClearOnExit(bool value) async {
    _clearOnExit = value;
    await _prefs.setBool(_keyClearOnExit, value);
    notifyListeners();
  }

  Future<void> setJavascriptEnabled(bool value) async {
    _javascriptEnabled = value;
    await _prefs.setBool(_keyJavascriptEnabled, value);
    notifyListeners();
  }

  Future<void> setDesktopMode(bool value) async {
    _desktopMode = value;
    await _prefs.setBool(_keyDesktopMode, value);
    _pushNativeShieldConfig();
    notifyListeners();
  }

  Future<void> setTextScalePercent(int value) async {
    _textScalePercent = value.clamp(75, 175);
    await _prefs.setInt(_keyTextScalePercent, _textScalePercent);
    notifyListeners();
  }

  Future<void> setLanguage(BrowserLanguage lang) async {
    if (_language == lang) return;
    _language = lang;
    await _prefs.setString(_keyLanguage, lang.name);
    notifyListeners();
  }

  Future<void> setGesturesEnabled(bool value) async {
    _gesturesEnabled = value;
    await _prefs.setBool(_keyGesturesEnabled, value);
    notifyListeners();
  }

  Future<void> setEdgeSwipeNavigation(bool value) async {
    _edgeSwipeNavigation = value;
    await _prefs.setBool(_keyEdgeSwipe, value);
    notifyListeners();
  }

  Future<void> setBarSwipeSwitchTabs(bool value) async {
    _barSwipeSwitchTabs = value;
    await _prefs.setBool(_keyBarSwipeTabs, value);
    notifyListeners();
  }

  Future<void> setDownloadNotificationsEnabled(bool value) async {
    _downloadNotificationsEnabled = value;
    await _prefs.setBool(_keyDownloadNotifs, value);
    unawaited(NativeShieldBridge.instance.setDownloadNotificationsEnabled(value));
    notifyListeners();
  }

  Future<void> setWebNotificationsEnabled(bool value) async {
    _webNotificationsEnabled = value;
    await _prefs.setBool(_keyWebNotifs, value);
    notifyListeners();
  }

  List<String> matchingRecentSearches(String prefix, {int limit = 8}) {
    final String q = prefix.trim().toLowerCase();
    if (q.isEmpty) {
      return List<String>.unmodifiable(_recentSearches.take(limit));
    }
    return _recentSearches
        .where((String s) => s.toLowerCase().contains(q))
        .take(limit)
        .toList(growable: false);
  }

  Future<void> recordRecentSearch(String rawQuery) async {
    final String clean = rawQuery.trim();
    if (clean.isEmpty ||
        clean.startsWith('http://') ||
        clean.startsWith('https://') ||
        clean.startsWith('heaven://')) {
      return;
    }
    _recentSearches = <String>[
      clean,
      ..._recentSearches.where(
        (String s) => s.toLowerCase() != clean.toLowerCase(),
      ),
    ].take(15).toList();
    await _prefs.setStringList(_keyRecentSearches, _recentSearches);
    notifyListeners();
  }

  Future<void> removeRecentSearch(String query) async {
    _recentSearches = _recentSearches
        .where((String s) => s != query)
        .toList();
    await _prefs.setStringList(_keyRecentSearches, _recentSearches);
    notifyListeners();
  }

  Future<void> clearRecentSearches() async {
    _recentSearches = <String>[];
    await _prefs.remove(_keyRecentSearches);
    notifyListeners();
  }

  bool isJavaScriptAllowedForHost(String? host) {
    if (!_javascriptEnabled) return false;
    if (host == null || host.isEmpty) return true;
    return !_jsDisabledHosts.contains(OmniboxParser.cleanDomain(host));
  }

  Future<void> toggleSiteJavaScript(String host) async {
    final String clean = OmniboxParser.cleanDomain(host);
    if (clean.isEmpty) return;
    if (!_jsDisabledHosts.remove(clean)) {
      _jsDisabledHosts.add(clean);
    }
    await _prefs.setStringList(_keyJsDisabledHosts, _jsDisabledHosts.toList());
    notifyListeners();
  }

  bool arePopupsBlockedForHost(String? host) {
    if (host == null || host.isEmpty) return true;
    return !_popupAllowedHosts.contains(OmniboxParser.cleanDomain(host));
  }

  Future<void> toggleSitePopups(String host) async {
    final String clean = OmniboxParser.cleanDomain(host);
    if (clean.isEmpty) return;
    if (!_popupAllowedHosts.remove(clean)) {
      _popupAllowedHosts.add(clean);
    }
    await _prefs.setStringList(
      _keyPopupAllowedHosts,
      _popupAllowedHosts.toList(),
    );
    notifyListeners();
  }
}
