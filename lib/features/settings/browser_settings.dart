import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/omnibox_parser.dart';
import '../shield/native_shield_bridge.dart';

enum HeavenShieldMode {
  standard(
    'Standard',
    'Blocks ad networks & trackers while keeping logins and video players smooth',
  ),
  strict(
    'Strict',
    'Aggressive ad, analytics, CNAME tracker & hardware-entropy blocking',
  );

  const HeavenShieldMode(this.label, this.description);
  final String label;
  final String description;

  static HeavenShieldMode fromName(String? raw) {
    for (final HeavenShieldMode m in HeavenShieldMode.values) {
      if (m.name == raw) return m;
    }
    return HeavenShieldMode.standard;
  }
}

enum SitePermissionType {
  location('Location', 'Access your GPS or coarse location'),
  camera('Camera', 'Capture video or photos on this site'),
  microphone('Microphone', 'Record audio or voice calls'),
  notifications('Notifications', 'Show website push alerts'),
  popups('Pop-ups & Redirects', 'Open new windows or external redirects'),
  javascript('JavaScript', 'Run interactive scripts on this site'),
  protectedMedia('Protected Media', 'Play DRM-encrypted video streams');

  const SitePermissionType(this.label, this.description);
  final String label;
  final String description;
}

enum SitePermissionDecision {
  ask('Ask'),
  allow('Allowed'),
  block('Blocked');

  const SitePermissionDecision(this.label);
  final String label;

  static SitePermissionDecision fromName(String? raw) {
    for (final SitePermissionDecision d in SitePermissionDecision.values) {
      if (d.name == raw) return d;
    }
    return SitePermissionDecision.ask;
  }
}

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

  static const String _keySearchEngine = 'hb.searchEngine.v13';
  static const String _legacyKeySearchEngine = 'hb.searchEngine.v3';
  static const String _keyThemeMode = 'hb.themeMode.v3';
  static const String _keyHttpsUpgrade = 'hb.httpsUpgrade';
  static const String _keyBlockThirdPartyCookies = 'hb.blockThirdPartyCookies';
  static const String _keySendDntGpc = 'hb.sendDntGpc';
  static const String _keyClearOnExit = 'hb.clearOnExit';
  static const String _keyJavascriptEnabled = 'hb.javascriptEnabled';
  static const String _keyDesktopMode = 'hb.desktopMode';
  static const String _keyTextScalePercent = 'hb.textScalePercent';
  static const String _keyJsDisabledHosts = 'hb.jsDisabledHosts.v8';
  static const String _keyPopupAllowedHosts = 'hb.popupAllowedHosts.v8';
  static const String _keySitePermissions = 'hb.sitePermissions.v13';
  static const String _keyRecentSearches = 'hb.recentSearches.v8';
  static const String _keyLanguage = 'hb.language.v8';
  static const String _keyBgMedia = 'hb.bgMedia.v13';
  static const String _keyBiometricIncognito = 'hb.biometricIncognito.v13';
  static const String _keyBiometricApp = 'hb.biometricApp.v13';
  static const String _keyDownloadNotifs = 'hb.downloadNotifs.v8';
  static const String _keyBgPlayNotifs = 'hb.bgPlayNotifs.v13';
  static const String _keyWebNotifs = 'hb.webNotifs.v8';
  static const String _keyShieldEnabled = 'hb.shield.enabled.v19';
  static const String _keyShieldMode = 'hb.shield.mode.v19';
  static const String _keyShieldBlockAds = 'hb.shield.blockAds.v19';
  static const String _keyShieldCookieBanners = 'hb.shield.cookieBanners.v19';
  static const String _keyShieldCleanUrls = 'hb.shield.cleanUrls.v19';
  static const String _keyShieldAntiFp = 'hb.shield.antiFp.v19';
  static const String _keyShieldBlockPopups = 'hb.shield.blockPopups.v19';
  static const String _keyShieldDisabledHosts = 'hb.shield.disabledHosts.v19';
  static const String _keyTranslateTargetLang = 'hb.translateLang.v18';
  static const String _keyReaderFontSize = 'hb.readerFontSize.v18';
  static const String _keyReaderTheme = 'hb.readerTheme.v18';
  static const String _keySiteUsage = 'hb.siteUsage.v3';
  static const String _keyHiddenDomains = 'hb.hiddenQuickDomains.v3';
  static const String _keyBookmarks = 'hb.bookmarks.v3';
  static const String _keyHistory = 'hb.history.v3';

  // Google is the default search engine; top navigation bar is always used.
  SearchEngine _searchEngine = SearchEngine.google;
  ThemeMode _themeMode = ThemeMode.dark;
  BrowserLanguage _language = BrowserLanguage.en;
  bool _httpsUpgrade = true;
  bool _blockThirdPartyCookies = true;
  bool _sendDntAndGpc = true;
  bool _clearOnExit = false;
  bool _javascriptEnabled = true;
  bool _desktopMode = false;
  bool _backgroundMediaEnabled = true;
  bool _biometricLockIncognito = false;
  bool _biometricLockApp = false;
  bool _downloadNotificationsEnabled = true;
  bool _backgroundPlayNotificationEnabled = true;
  bool _webNotificationsEnabled = false;
  bool _shieldEnabled = true;
  HeavenShieldMode _shieldMode = HeavenShieldMode.standard;
  bool _shieldBlockAds = true;
  bool _shieldBlockCookieBanners = true;
  bool _shieldCleanUrls = true;
  bool _shieldAntiFingerprinting = true;
  bool _shieldBlockPopups = true;
  int _textScalePercent = 100;
  String _translateTargetLang = 'en';
  double _readerFontSize = 18.0;
  String _readerTheme = 'midnight';

  final Set<String> _jsDisabledHosts = <String>{};
  final Set<String> _popupAllowedHosts = <String>{};
  final Set<String> _shieldDisabledHosts = <String>{};
  final Map<String, Map<SitePermissionType, SitePermissionDecision>>
  _sitePermissions =
      <String, Map<SitePermissionType, SitePermissionDecision>>{};
  List<String> _recentSearches = <String>[];
  final Map<String, SiteUsageEntry> _siteUsageByDomain =
      <String, SiteUsageEntry>{};
  final Set<String> _hiddenQuickDomains = <String>{};
  List<BookmarkItem> _bookmarks = <BookmarkItem>[];
  List<HistoryItem> _history = <HistoryItem>[];

  int _webViewConfigRevision = 0;
  int get webViewConfigRevision => _webViewConfigRevision;
  SharedPreferences get prefs => _prefs;
  SearchEngine get searchEngine => _searchEngine;
  ThemeMode get themeMode => _themeMode;
  BrowserLanguage get language => _language;
  bool get httpsUpgrade => _httpsUpgrade;
  bool get blockThirdPartyCookies => _blockThirdPartyCookies;
  bool get sendDntAndGpc => _sendDntAndGpc;
  bool get clearOnExit => _clearOnExit;
  bool get javascriptEnabled => _javascriptEnabled;
  bool get desktopMode => _desktopMode;
  bool get backgroundMediaEnabled => _backgroundMediaEnabled;
  bool get biometricLockIncognito => _biometricLockIncognito;
  bool get biometricLockApp => _biometricLockApp;
  bool get downloadNotificationsEnabled => _downloadNotificationsEnabled;
  bool get backgroundPlayNotificationEnabled =>
      _backgroundPlayNotificationEnabled;
  bool get webNotificationsEnabled => _webNotificationsEnabled;
  bool get shieldEnabled => _shieldEnabled;
  HeavenShieldMode get shieldMode => _shieldMode;
  bool get shieldBlockAds => _shieldBlockAds;
  bool get shieldBlockCookieBanners => _shieldBlockCookieBanners;
  bool get shieldCleanUrls => _shieldCleanUrls;
  bool get shieldAntiFingerprinting => _shieldAntiFingerprinting;
  bool get shieldBlockPopups => _shieldBlockPopups;
  List<String> get shieldDisabledHosts {
    final List<String> list = _shieldDisabledHosts.toList()..sort();
    return List<String>.unmodifiable(list);
  }

  int get activeShieldProtectionCount {
    if (!_shieldEnabled) return 0;
    int count = 0;
    if (_shieldBlockAds) count++;
    if (_shieldBlockCookieBanners) count++;
    if (_shieldCleanUrls) count++;
    if (_shieldAntiFingerprinting) count++;
    if (_shieldBlockPopups) count++;
    if (_httpsUpgrade) count++;
    if (_blockThirdPartyCookies) count++;
    return count;
  }
  String get translateTargetLang => _translateTargetLang;
  double get readerFontSize => _readerFontSize;
  String get readerTheme => _readerTheme;
  int get textScalePercent => _textScalePercent;
  List<String> get recentSearches => List<String>.unmodifiable(_recentSearches);
  List<BookmarkItem> get bookmarks =>
      List<BookmarkItem>.unmodifiable(_bookmarks);
  List<HistoryItem> get history => List<HistoryItem>.unmodifiable(_history);

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
    final String? savedEngine =
        _prefs.getString(_keySearchEngine) ??
        _prefs.getString(_legacyKeySearchEngine);
    _searchEngine = SearchEngine.fromName(savedEngine);
    _themeMode = switch (_prefs.getString(_keyThemeMode)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
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
    _language = BrowserLanguage.fromCode(_prefs.getString(_keyLanguage));
    _backgroundMediaEnabled = _prefs.getBool(_keyBgMedia) ?? true;
    _biometricLockIncognito =
        _prefs.getBool(_keyBiometricIncognito) ?? false;
    _biometricLockApp = _prefs.getBool(_keyBiometricApp) ?? false;
    _downloadNotificationsEnabled =
        _prefs.getBool(_keyDownloadNotifs) ?? true;
    _backgroundPlayNotificationEnabled =
        _prefs.getBool(_keyBgPlayNotifs) ?? true;
    _webNotificationsEnabled = _prefs.getBool(_keyWebNotifs) ?? false;
    _shieldEnabled = _prefs.getBool(_keyShieldEnabled) ?? true;
    _shieldMode = HeavenShieldMode.fromName(_prefs.getString(_keyShieldMode));
    _shieldBlockAds = _prefs.getBool(_keyShieldBlockAds) ?? true;
    _shieldBlockCookieBanners =
        _prefs.getBool(_keyShieldCookieBanners) ?? true;
    _shieldCleanUrls = _prefs.getBool(_keyShieldCleanUrls) ?? true;
    _shieldAntiFingerprinting = _prefs.getBool(_keyShieldAntiFp) ?? true;
    _shieldBlockPopups = _prefs.getBool(_keyShieldBlockPopups) ?? true;
    _translateTargetLang =
        _prefs.getString(_keyTranslateTargetLang) ?? 'en';
    _readerFontSize =
        (_prefs.getDouble(_keyReaderFontSize) ?? 18.0).clamp(14.0, 26.0);
    _readerTheme = _prefs.getString(_keyReaderTheme) ?? 'midnight';

    final List<String>? savedShieldAllow = _prefs.getStringList(
      _keyShieldDisabledHosts,
    );
    if (savedShieldAllow != null) {
      _shieldDisabledHosts
        ..clear()
        ..addAll(
          savedShieldAllow
              .map(OmniboxParser.cleanDomain)
              .where((String h) => h.isNotEmpty),
        );
    }

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

    final String? rawPerms = _prefs.getString(_keySitePermissions);
    if (rawPerms != null && rawPerms.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawPerms);
        if (decoded is Map<String, Object?>) {
          for (final MapEntry<String, Object?> hostEntry in decoded.entries) {
            final Object? permMap = hostEntry.value;
            if (permMap is Map<String, Object?>) {
              final Map<SitePermissionType, SitePermissionDecision> parsed =
                  <SitePermissionType, SitePermissionDecision>{};
              for (final SitePermissionType t in SitePermissionType.values) {
                final String? v = permMap[t.name]?.toString();
                if (v != null) {
                  parsed[t] = SitePermissionDecision.fromName(v);
                }
              }
              if (parsed.isNotEmpty) {
                _sitePermissions[hostEntry.key] = parsed;
              }
            }
          }
        }
      } on FormatException {
        _sitePermissions.clear();
      }
    }

    final List<String>? savedRecent = _prefs.getStringList(_keyRecentSearches);
    if (savedRecent != null) {
      _recentSearches = savedRecent
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .take(15)
          .toList();
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

    _pushNativeBrowserConfig();
  }

  void _pushNativeBrowserConfig() {
    NativeShieldBridge.instance.syncBrowserConfig(
      desktopMode: _desktopMode,
      backgroundMediaEnabled: _backgroundMediaEnabled,
      webNotificationsEnabled: _webNotificationsEnabled,
      backgroundPlayNotificationEnabled: _backgroundPlayNotificationEnabled,
      shieldEnabled: _shieldEnabled,
      shieldStrictMode: _shieldMode == HeavenShieldMode.strict,
      shieldBlockAds: _shieldBlockAds,
      shieldBlockCookieBanners: _shieldBlockCookieBanners,
      shieldCleanUrls: _shieldCleanUrls,
      shieldAntiFingerprinting: _shieldAntiFingerprinting,
      shieldBlockPopups: _shieldBlockPopups,
      shieldDisabledHosts: _shieldDisabledHosts.toList(growable: false),
    );
  }

  static final RegExp _trackingParamRegex = RegExp(
    r'^(utm_[a-z0-9_]+|fbclid|gclid|dclid|msclkid|yclid|mc_eid|igshid|_hsenc|_hsmi|vero_id|mkt_tok)$',
    caseSensitive: false,
  );

  static Uri stripTrackingParameters(Uri uri) {
    if (!uri.hasQuery || uri.queryParametersAll.isEmpty) {
      return uri;
    }
    bool modified = false;
    final Map<String, List<String>> kept = <String, List<String>>{};
    uri.queryParametersAll.forEach((String key, List<String> values) {
      if (_trackingParamRegex.hasMatch(key)) {
        modified = true;
      } else {
        kept[key] = values;
      }
    });
    if (!modified) {
      return uri;
    }
    if (kept.isEmpty) {
      return uri.replace(queryParameters: const <String, dynamic>{}).removeFragment().replace(
        fragment: uri.hasFragment ? uri.fragment : null,
      );
    }
    return uri.replace(queryParameters: kept);
  }

  bool isHostShieldAllowlisted(String? rawHost) {
    String cur = OmniboxParser.cleanDomain(rawHost);
    if (cur.isEmpty || _shieldDisabledHosts.isEmpty) {
      return false;
    }
    while (true) {
      if (_shieldDisabledHosts.contains(cur)) {
        return true;
      }
      final int dot = cur.indexOf('.');
      if (dot < 0 || dot + 1 >= cur.length) {
        break;
      }
      cur = cur.substring(dot + 1);
    }
    return false;
  }

  bool isShieldActiveForHost(String? rawHost) {
    return _shieldEnabled && !isHostShieldAllowlisted(rawHost);
  }

  Future<void> setShieldEnabled(bool enabled) async {
    if (_shieldEnabled == enabled) return;
    _shieldEnabled = enabled;
    await _prefs.setBool(_keyShieldEnabled, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldMode(HeavenShieldMode mode) async {
    if (_shieldMode == mode) return;
    _shieldMode = mode;
    await _prefs.setString(_keyShieldMode, mode.name);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldBlockAds(bool enabled) async {
    if (_shieldBlockAds == enabled) return;
    _shieldBlockAds = enabled;
    await _prefs.setBool(_keyShieldBlockAds, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldBlockCookieBanners(bool enabled) async {
    if (_shieldBlockCookieBanners == enabled) return;
    _shieldBlockCookieBanners = enabled;
    await _prefs.setBool(_keyShieldCookieBanners, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldCleanUrls(bool enabled) async {
    if (_shieldCleanUrls == enabled) return;
    _shieldCleanUrls = enabled;
    await _prefs.setBool(_keyShieldCleanUrls, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldAntiFingerprinting(bool enabled) async {
    if (_shieldAntiFingerprinting == enabled) return;
    _shieldAntiFingerprinting = enabled;
    await _prefs.setBool(_keyShieldAntiFp, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldBlockPopups(bool enabled) async {
    if (_shieldBlockPopups == enabled) return;
    _shieldBlockPopups = enabled;
    await _prefs.setBool(_keyShieldBlockPopups, enabled);
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<bool> addShieldExceptionHost(String rawHost) async {
    final String clean = OmniboxParser.cleanDomain(rawHost);
    if (clean.isEmpty || !clean.contains('.')) {
      return false;
    }
    if (!_shieldDisabledHosts.add(clean)) {
      return true;
    }
    await _prefs.setStringList(
      _keyShieldDisabledHosts,
      _shieldDisabledHosts.toList(growable: false),
    );
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
    return true;
  }

  Future<void> removeShieldExceptionHost(String rawHost) async {
    final String clean = OmniboxParser.cleanDomain(rawHost);
    if (!_shieldDisabledHosts.remove(clean)) {
      return;
    }
    await _prefs.setStringList(
      _keyShieldDisabledHosts,
      _shieldDisabledHosts.toList(growable: false),
    );
    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setShieldProtectionForHost(String rawHost, bool protectSite) async {
    if (protectSite) {
      // Remove exact host or any parent domain matching rawHost
      String cur = OmniboxParser.cleanDomain(rawHost);
      bool changed = false;
      while (cur.isNotEmpty) {
        if (_shieldDisabledHosts.remove(cur)) {
          changed = true;
        }
        final int dot = cur.indexOf('.');
        if (dot < 0 || dot + 1 >= cur.length) {
          break;
        }
        cur = cur.substring(dot + 1);
      }
      if (!changed) return;
      await _prefs.setStringList(
        _keyShieldDisabledHosts,
        _shieldDisabledHosts.toList(growable: false),
      );
      _webViewConfigRevision += 1;
      _pushNativeBrowserConfig();
      notifyListeners();
    } else {
      await addShieldExceptionHost(rawHost);
    }
  }

  Future<void> resetHeavenShieldDefaults() async {
    _shieldEnabled = true;
    _shieldMode = HeavenShieldMode.standard;
    _shieldBlockAds = true;
    _shieldBlockCookieBanners = true;
    _shieldCleanUrls = true;
    _shieldAntiFingerprinting = true;
    _shieldBlockPopups = true;
    _httpsUpgrade = true;
    _blockThirdPartyCookies = true;
    _sendDntAndGpc = true;
    _shieldDisabledHosts.clear();

    await _prefs.setBool(_keyShieldEnabled, true);
    await _prefs.setString(_keyShieldMode, HeavenShieldMode.standard.name);
    await _prefs.setBool(_keyShieldBlockAds, true);
    await _prefs.setBool(_keyShieldCookieBanners, true);
    await _prefs.setBool(_keyShieldCleanUrls, true);
    await _prefs.setBool(_keyShieldAntiFp, true);
    await _prefs.setBool(_keyShieldBlockPopups, true);
    await _prefs.setBool(_keyHttpsUpgrade, true);
    await _prefs.setBool(_keyBlockThirdPartyCookies, true);
    await _prefs.setBool(_keySendDntGpc, true);
    await _prefs.setStringList(_keyShieldDisabledHosts, const <String>[]);

    _webViewConfigRevision += 1;
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> addShieldDisabledHost(String rawHost) =>
      addShieldExceptionHost(rawHost);

  Future<void> removeShieldDisabledHost(String rawHost) =>
      removeShieldExceptionHost(rawHost);

  Future<void> setTranslateTargetLang(String langCode) async {
    final String clean = langCode.trim();
    if (clean.isEmpty || _translateTargetLang == clean) return;
    _translateTargetLang = clean;
    await _prefs.setString(_keyTranslateTargetLang, clean);
    notifyListeners();
  }

  Future<void> setReaderFontSize(double size) async {
    final double clamped = size.clamp(14.0, 26.0);
    if ((_readerFontSize - clamped).abs() < 0.05) return;
    _readerFontSize = clamped;
    await _prefs.setDouble(_keyReaderFontSize, clamped);
    notifyListeners();
  }

  Future<void> setReaderTheme(String theme) async {
    if (_readerTheme == theme) return;
    _readerTheme = theme;
    await _prefs.setString(_keyReaderTheme, theme);
    notifyListeners();
  }

  SitePermissionDecision getSitePermission(
    String? host,
    SitePermissionType type,
  ) {
    final String clean = OmniboxParser.cleanDomain(host);
    if (clean.isEmpty) {
      return switch (type) {
        SitePermissionType.javascript =>
          _javascriptEnabled
              ? SitePermissionDecision.allow
              : SitePermissionDecision.block,
        SitePermissionType.popups => SitePermissionDecision.block,
        SitePermissionType.protectedMedia => SitePermissionDecision.allow,
        SitePermissionType.notifications =>
          _webNotificationsEnabled
              ? SitePermissionDecision.ask
              : SitePermissionDecision.block,
        _ => SitePermissionDecision.ask,
      };
    }
    if (type == SitePermissionType.javascript) {
      return isJavaScriptAllowedForHost(clean)
          ? SitePermissionDecision.allow
          : SitePermissionDecision.block;
    }
    if (type == SitePermissionType.popups) {
      return arePopupsBlockedForHost(clean)
          ? SitePermissionDecision.block
          : SitePermissionDecision.allow;
    }
    final SitePermissionDecision? explicit = _sitePermissions[clean]?[type];
    if (explicit != null) {
      return explicit;
    }
    if (type == SitePermissionType.protectedMedia) {
      return SitePermissionDecision.allow;
    }
    if (type == SitePermissionType.notifications && !_webNotificationsEnabled) {
      return SitePermissionDecision.block;
    }
    return SitePermissionDecision.ask;
  }

  Future<void> setSitePermission(
    String host,
    SitePermissionType type,
    SitePermissionDecision decision,
  ) async {
    final String clean = OmniboxParser.cleanDomain(host);
    if (clean.isEmpty) return;
    if (type == SitePermissionType.javascript) {
      if (decision == SitePermissionDecision.block) {
        _jsDisabledHosts.add(clean);
      } else {
        _jsDisabledHosts.remove(clean);
      }
      await _prefs.setStringList(
        _keyJsDisabledHosts,
        _jsDisabledHosts.toList(),
      );
      _webViewConfigRevision += 1;
      notifyListeners();
      return;
    }
    if (type == SitePermissionType.popups) {
      if (decision == SitePermissionDecision.allow) {
        _popupAllowedHosts.add(clean);
      } else {
        _popupAllowedHosts.remove(clean);
      }
      await _prefs.setStringList(
        _keyPopupAllowedHosts,
        _popupAllowedHosts.toList(),
      );
      notifyListeners();
      return;
    }
    final Map<SitePermissionType, SitePermissionDecision> map =
        _sitePermissions.putIfAbsent(
          clean,
          () => <SitePermissionType, SitePermissionDecision>{},
        );
    if (decision == SitePermissionDecision.ask) {
      map.remove(type);
      if (map.isEmpty) {
        _sitePermissions.remove(clean);
      }
    } else {
      map[type] = decision;
    }
    await _persistSitePermissions();
    notifyListeners();
  }

  Future<void> revokeSitePermission(
    String host,
    SitePermissionType type,
  ) async {
    await setSitePermission(host, type, SitePermissionDecision.block);
  }

  Future<void> revokeAllPermissionsForSite(String host) async {
    final String clean = OmniboxParser.cleanDomain(host);
    if (clean.isEmpty) return;
    _sitePermissions[clean] = <SitePermissionType, SitePermissionDecision>{
      SitePermissionType.location: SitePermissionDecision.block,
      SitePermissionType.camera: SitePermissionDecision.block,
      SitePermissionType.microphone: SitePermissionDecision.block,
      SitePermissionType.notifications: SitePermissionDecision.block,
      SitePermissionType.protectedMedia: SitePermissionDecision.block,
    };
    _popupAllowedHosts.remove(clean);
    await _prefs.setStringList(
      _keyPopupAllowedHosts,
      _popupAllowedHosts.toList(),
    );
    await _persistSitePermissions();
    notifyListeners();
  }

  Future<void> _persistSitePermissions() async {
    final Map<String, Map<String, String>> out =
        <String, Map<String, String>>{};
    for (final MapEntry<String, Map<SitePermissionType, SitePermissionDecision>>
        e
        in _sitePermissions.entries) {
      out[e.key] = <String, String>{
        for (final MapEntry<SitePermissionType, SitePermissionDecision> p
            in e.value.entries)
          p.key.name: p.value.name,
      };
    }
    await _prefs.setString(_keySitePermissions, jsonEncode(out));
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
    if (url.isEmpty) {
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

  Future<void> setBackgroundMediaEnabled(bool value) async {
    _backgroundMediaEnabled = value;
    await _prefs.setBool(_keyBgMedia, value);
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setBiometricLockIncognito(bool value) async {
    _biometricLockIncognito = value;
    await _prefs.setBool(_keyBiometricIncognito, value);
    notifyListeners();
  }

  Future<void> setBiometricLockApp(bool value) async {
    _biometricLockApp = value;
    await _prefs.setBool(_keyBiometricApp, value);
    notifyListeners();
  }

  Future<void> setHttpsUpgrade(bool value) async {
    _httpsUpgrade = value;
    await _prefs.setBool(_keyHttpsUpgrade, value);
    notifyListeners();
  }

  Future<void> setBlockThirdPartyCookies(bool value) async {
    _blockThirdPartyCookies = value;
    _webViewConfigRevision += 1;
    await _prefs.setBool(_keyBlockThirdPartyCookies, value);
    notifyListeners();
  }

  Future<void> setSendDntAndGpc(bool value) async {
    _sendDntAndGpc = value;
    await _prefs.setBool(_keySendDntGpc, value);
    notifyListeners();
  }

  Future<void> setClearOnExit(bool value) async {
    _clearOnExit = value;
    await _prefs.setBool(_keyClearOnExit, value);
    notifyListeners();
  }

  Future<void> setJavascriptEnabled(bool value) async {
    _javascriptEnabled = value;
    _webViewConfigRevision += 1;
    await _prefs.setBool(_keyJavascriptEnabled, value);
    notifyListeners();
  }

  Future<void> setDesktopMode(bool value) async {
    _desktopMode = value;
    _webViewConfigRevision += 1;
    await _prefs.setBool(_keyDesktopMode, value);
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setTextScalePercent(int value) async {
    _textScalePercent = value.clamp(75, 175);
    _webViewConfigRevision += 1;
    await _prefs.setInt(_keyTextScalePercent, _textScalePercent);
    notifyListeners();
  }

  Future<void> setLanguage(BrowserLanguage lang) async {
    if (_language == lang) return;
    _language = lang;
    await _prefs.setString(_keyLanguage, lang.name);
    notifyListeners();
  }

  Future<void> setDownloadNotificationsEnabled(bool value) async {
    _downloadNotificationsEnabled = value;
    await _prefs.setBool(_keyDownloadNotifs, value);
    unawaited(NativeShieldBridge.instance.setDownloadNotificationsEnabled(value));
    notifyListeners();
  }

  Future<void> setBackgroundPlayNotificationEnabled(bool value) async {
    _backgroundPlayNotificationEnabled = value;
    await _prefs.setBool(_keyBgPlayNotifs, value);
    _pushNativeBrowserConfig();
    notifyListeners();
  }

  Future<void> setWebNotificationsEnabled(bool value) async {
    _webNotificationsEnabled = value;
    await _prefs.setBool(_keyWebNotifs, value);
    _pushNativeBrowserConfig();
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
        clean.startsWith('https://')) {
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
    _webViewConfigRevision += 1;
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
