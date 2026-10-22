import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/features/shield/heaven_shield.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OmniboxPosition {
  bottom('Bottom (Thumb-friendly)'),
  top('Top (Classic)');

  const OmniboxPosition(this.label);
  final String label;

  static OmniboxPosition fromName(String? name) {
    for (final OmniboxPosition pos in OmniboxPosition.values) {
      if (pos.name == name) {
        return pos;
      }
    }
    return OmniboxPosition.bottom;
  }
}

class QuickShortcut {
  const QuickShortcut({
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  Map<String, String> toJson() => <String, String>{
        'title': title,
        'url': url,
      };

  factory QuickShortcut.fromJson(Map<String, dynamic> json) {
    return QuickShortcut(
      title: (json['title'] as String? ?? '').trim(),
      url: (json['url'] as String? ?? '').trim(),
    );
  }
}

class BrowserSettingsController extends ChangeNotifier {
  BrowserSettingsController(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  static const String _keyThemeMode = 'hb_theme_mode';
  static const String _keySearchEngine = 'hb_search_engine';
  static const String _keyOmniboxPos = 'hb_omnibox_position';
  static const String _keyShieldEnabled = 'hb_shield_enabled';
  static const String _keyHttpsUpgrade = 'hb_https_upgrade';
  static const String _keyBlockThirdPartyCookies = 'hb_block_3p_cookies';
  static const String _keyJsEnabled = 'hb_js_enabled';
  static const String _keyDesktopMode = 'hb_desktop_mode';
  static const String _keyTextZoom = 'hb_text_zoom';
  static const String _keyTotalBlocked = 'hb_total_blocked';
  static const String _keyTrustedHosts = 'hb_trusted_hosts';
  static const String _keyShortcuts = 'hb_quick_shortcuts';

  static const List<QuickShortcut> defaultShortcuts = <QuickShortcut>[
    QuickShortcut(title: 'DuckDuckGo', url: 'https://duckduckgo.com'),
    QuickShortcut(title: 'Wikipedia', url: 'https://www.wikipedia.org'),
    QuickShortcut(title: 'GitHub', url: 'https://github.com'),
    QuickShortcut(title: 'Hacker News', url: 'https://news.ycombinator.com'),
    QuickShortcut(title: 'Proton', url: 'https://proton.me'),
    QuickShortcut(title: 'MDN Docs', url: 'https://developer.mozilla.org'),
  ];

  ThemeMode _themeMode = ThemeMode.system;
  SearchEngine _searchEngine = SearchEngine.duckDuckGo;
  OmniboxPosition _omniboxPosition = OmniboxPosition.bottom;
  bool _shieldEnabled = true;
  bool _httpsUpgrade = true;
  bool _blockThirdPartyCookies = true;
  bool _javascriptEnabled = true;
  bool _desktopMode = false;
  int _textZoom = 100;
  int _totalTrackersBlocked = 0;
  Set<String> _trustedHosts = <String>{};
  List<QuickShortcut> _shortcuts = List<QuickShortcut>.from(defaultShortcuts);

  ThemeMode get themeMode => _themeMode;
  SearchEngine get searchEngine => _searchEngine;
  OmniboxPosition get omniboxPosition => _omniboxPosition;
  bool get shieldEnabled => _shieldEnabled;
  bool get httpsUpgrade => _httpsUpgrade;
  bool get blockThirdPartyCookies => _blockThirdPartyCookies;
  bool get javascriptEnabled => _javascriptEnabled;
  bool get desktopMode => _desktopMode;
  int get textZoom => _textZoom;
  int get totalTrackersBlocked => _totalTrackersBlocked;
  Set<String> get trustedHosts => Set<String>.unmodifiable(_trustedHosts);
  List<QuickShortcut> get shortcuts => List<QuickShortcut>.unmodifiable(_shortcuts);

  void _load() {
    final String? themeStr = _prefs.getString(_keyThemeMode);
    if (themeStr == 'light') {
      _themeMode = ThemeMode.light;
    } else if (themeStr == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }

    _searchEngine = SearchEngine.fromName(_prefs.getString(_keySearchEngine));
    _omniboxPosition =
        OmniboxPosition.fromName(_prefs.getString(_keyOmniboxPos));
    _shieldEnabled = _prefs.getBool(_keyShieldEnabled) ?? true;
    _httpsUpgrade = _prefs.getBool(_keyHttpsUpgrade) ?? true;
    _blockThirdPartyCookies =
        _prefs.getBool(_keyBlockThirdPartyCookies) ?? true;
    _javascriptEnabled = _prefs.getBool(_keyJsEnabled) ?? true;
    _desktopMode = _prefs.getBool(_keyDesktopMode) ?? false;
    _textZoom = (_prefs.getInt(_keyTextZoom) ?? 100).clamp(75, 150);
    _totalTrackersBlocked = _prefs.getInt(_keyTotalBlocked) ?? 0;

    final List<String>? savedTrusted = _prefs.getStringList(_keyTrustedHosts);
    if (savedTrusted != null) {
      _trustedHosts = savedTrusted.map(HeavenShield.normalizeHost).toSet();
    }

    final String? rawShortcuts = _prefs.getString(_keyShortcuts);
    if (rawShortcuts != null && rawShortcuts.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(rawShortcuts) as List<dynamic>;
        _shortcuts = decoded
            .whereType<Map<String, dynamic>>()
            .map(QuickShortcut.fromJson)
            .where((QuickShortcut s) => s.title.isNotEmpty && s.url.isNotEmpty)
            .toList();
      } catch (_) {
        _shortcuts = List<QuickShortcut>.from(defaultShortcuts);
      }
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _prefs.setString(_keyThemeMode, mode.name);
  }

  Future<void> setSearchEngine(SearchEngine engine) async {
    _searchEngine = engine;
    notifyListeners();
    await _prefs.setString(_keySearchEngine, engine.name);
  }

  Future<void> setOmniboxPosition(OmniboxPosition position) async {
    _omniboxPosition = position;
    notifyListeners();
    await _prefs.setString(_keyOmniboxPos, position.name);
  }

  Future<void> setShieldEnabled(bool value) async {
    _shieldEnabled = value;
    notifyListeners();
    await _prefs.setBool(_keyShieldEnabled, value);
  }

  Future<void> setHttpsUpgrade(bool value) async {
    _httpsUpgrade = value;
    notifyListeners();
    await _prefs.setBool(_keyHttpsUpgrade, value);
  }

  Future<void> setBlockThirdPartyCookies(bool value) async {
    _blockThirdPartyCookies = value;
    notifyListeners();
    await _prefs.setBool(_keyBlockThirdPartyCookies, value);
  }

  Future<void> setJavascriptEnabled(bool value) async {
    _javascriptEnabled = value;
    notifyListeners();
    await _prefs.setBool(_keyJsEnabled, value);
  }

  Future<void> setDesktopMode(bool value) async {
    _desktopMode = value;
    notifyListeners();
    await _prefs.setBool(_keyDesktopMode, value);
  }

  Future<void> setTextZoom(int zoom) async {
    final int clamped = zoom.clamp(75, 150);
    _textZoom = clamped;
    notifyListeners();
    await _prefs.setInt(_keyTextZoom, clamped);
  }

  Future<void> recordBlockedTracker() async {
    _totalTrackersBlocked += 1;
    notifyListeners();
    await _prefs.setInt(_keyTotalBlocked, _totalTrackersBlocked);
  }

  Future<void> resetBlockedCounter() async {
    _totalTrackersBlocked = 0;
    notifyListeners();
    await _prefs.setInt(_keyTotalBlocked, 0);
  }

  bool isHostTrusted(String? host) {
    return HeavenShield.isHostTrusted(host, _trustedHosts);
  }

  Future<void> toggleHostTrust(String host) async {
    final String clean = HeavenShield.normalizeHost(host);
    if (clean.isEmpty) {
      return;
    }
    if (_trustedHosts.contains(clean)) {
      _trustedHosts.remove(clean);
    } else {
      _trustedHosts.add(clean);
    }
    notifyListeners();
    await _prefs.setStringList(_keyTrustedHosts, _trustedHosts.toList());
  }

  Future<void> addShortcut(QuickShortcut shortcut) async {
    _shortcuts = <QuickShortcut>[..._shortcuts, shortcut];
    notifyListeners();
    await _saveShortcuts();
  }

  Future<void> removeShortcutAt(int index) async {
    if (index < 0 || index >= _shortcuts.length) {
      return;
    }
    final List<QuickShortcut> updated = List<QuickShortcut>.from(_shortcuts)
      ..removeAt(index);
    _shortcuts = updated;
    notifyListeners();
    await _saveShortcuts();
  }

  Future<void> resetDefaultShortcuts() async {
    _shortcuts = List<QuickShortcut>.from(defaultShortcuts);
    notifyListeners();
    await _saveShortcuts();
  }

  Future<void> _saveShortcuts() async {
    final String encoded = jsonEncode(
      _shortcuts.map((QuickShortcut s) => s.toJson()).toList(),
    );
    await _prefs.setString(_keyShortcuts, encoded);
  }
}
