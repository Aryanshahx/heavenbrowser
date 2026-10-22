import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../browser/engine/browser_engine.dart';
import '../settings/browser_settings.dart';

class BrowserTab {
  BrowserTab({
    required this.id,
    required this.isIncognito,
    required this.engine,
    required this.createdAt,
  });

  final String id;
  final bool isIncognito;
  final BrowserEngine engine;
  final DateTime createdAt;

  String get displayTitle {
    if (engine.isShowingStartPage) {
      return isIncognito ? 'Incognito Tab' : 'Start Page';
    }
    if (engine.isShowingHeavenSearch) {
      final String q = engine.heavenSearchQuery;
      return q.isEmpty ? 'Heaven Search' : q;
    }
    return engine.pageTitle;
  }

  String get displaySubtitle {
    if (engine.isShowingStartPage) {
      return isIncognito ? 'Private stealth session' : 'Heaven Start Deck';
    }
    if (engine.isShowingHeavenSearch) {
      return 'Heaven Private Search';
    }
    return engine.currentHost ?? (engine.currentUrl ?? '');
  }
}

class TabManagerController extends ChangeNotifier {
  TabManagerController({
    required this.settings,
    this.enablePlatformWebView = true,
  }) {
    _spawnTab(incognito: false, switchTo: true);
  }

  final BrowserSettingsController settings;
  final bool enablePlatformWebView;

  final List<BrowserTab> _tabs = <BrowserTab>[];
  late String _activeTabId;
  int _nextIdCounter = 1;

  List<BrowserTab> get allTabs => List<BrowserTab>.unmodifiable(_tabs);
  List<BrowserTab> get normalTabs =>
      _tabs.where((BrowserTab t) => !t.isIncognito).toList(growable: false);
  List<BrowserTab> get incognitoTabs =>
      _tabs.where((BrowserTab t) => t.isIncognito).toList(growable: false);

  int get totalTabCount => _tabs.length;

  BrowserTab get activeTab {
    for (final BrowserTab tab in _tabs) {
      if (tab.id == _activeTabId) {
        return tab;
      }
    }
    return _tabs.first;
  }

  int get activeTabIndex {
    final int idx = _tabs.indexWhere((BrowserTab t) => t.id == _activeTabId);
    return idx >= 0 ? idx : 0;
  }

  BrowserEngine get activeEngine => activeTab.engine;
  bool get isActiveIncognito => activeTab.isIncognito;

  BrowserTab _spawnTab({required bool incognito, required bool switchTo}) {
    final String id = 'tab_${_nextIdCounter++}';
    final BrowserEngine engine = BrowserEngine(
      settings: settings,
      isIncognito: incognito,
      enablePlatformWebView: enablePlatformWebView,
    );
    engine.addListener(_onTabEngineChanged);

    final BrowserTab tab = BrowserTab(
      id: id,
      isIncognito: incognito,
      engine: engine,
      createdAt: DateTime.now(),
    );
    _tabs.add(tab);
    if (switchTo) {
      _activeTabId = id;
    }
    return tab;
  }

  void _onTabEngineChanged() {
    notifyListeners();
  }

  Future<BrowserTab> openNewTab({
    bool incognito = false,
    String? initialInput,
    bool switchTo = true,
  }) async {
    final BrowserTab tab = _spawnTab(incognito: incognito, switchTo: switchTo);
    notifyListeners();
    if (initialInput != null && initialInput.trim().isNotEmpty) {
      await tab.engine.loadUserEntry(initialInput.trim());
    }
    return tab;
  }

  void switchToTab(String tabId) {
    if (_activeTabId == tabId) {
      return;
    }
    final bool exists = _tabs.any((BrowserTab t) => t.id == tabId);
    if (!exists) {
      return;
    }
    _activeTabId = tabId;
    notifyListeners();
  }

  Future<void> closeTab(String tabId) async {
    final int idx = _tabs.indexWhere((BrowserTab t) => t.id == tabId);
    if (idx < 0) {
      return;
    }
    final BrowserTab removed = _tabs.removeAt(idx);
    removed.engine.removeListener(_onTabEngineChanged);

    if (removed.isIncognito) {
      // Wipe tab WebView data if this was the last Incognito tab
      final bool moreIncognito = _tabs.any((BrowserTab t) => t.isIncognito);
      if (!moreIncognito && enablePlatformWebView) {
        await _scrubIncognitoSession(removed.engine);
      }
    }
    removed.engine.dispose();

    if (_tabs.isEmpty) {
      _spawnTab(incognito: false, switchTo: true);
    } else if (_activeTabId == tabId) {
      // Prefer staying in same mode if another tab of same mode exists
      final List<BrowserTab> sameMode = _tabs
          .where((BrowserTab t) => t.isIncognito == removed.isIncognito)
          .toList();
      if (sameMode.isNotEmpty) {
        _activeTabId = sameMode.last.id;
      } else {
        final int nextIdx = (idx - 1).clamp(0, _tabs.length - 1);
        _activeTabId = _tabs[nextIdx].id;
      }
    }
    notifyListeners();
  }

  Future<void> closeAllTabsByMode({required bool incognito}) async {
    final List<BrowserTab> targets = _tabs
        .where((BrowserTab t) => t.isIncognito == incognito)
        .toList();
    if (targets.isEmpty) {
      return;
    }

    if (incognito && enablePlatformWebView) {
      await _scrubIncognitoSession(targets.first.engine);
    }

    for (final BrowserTab tab in targets) {
      tab.engine.removeListener(_onTabEngineChanged);
      tab.engine.dispose();
      _tabs.remove(tab);
    }

    if (_tabs.isEmpty) {
      _spawnTab(incognito: false, switchTo: true);
    } else if (!_tabs.any((BrowserTab t) => t.id == _activeTabId)) {
      _activeTabId = _tabs.last.id;
    }
    notifyListeners();
  }

  Future<void> burnAllSessionsAndData() async {
    if (enablePlatformWebView && _tabs.isNotEmpty) {
      await _tabs.first.engine.burnBrowsingData();
    }
    for (final BrowserTab tab in _tabs) {
      tab.engine.removeListener(_onTabEngineChanged);
      tab.engine.dispose();
    }
    _tabs.clear();
    await settings.clearHistory();
    _spawnTab(incognito: false, switchTo: true);
    notifyListeners();
  }

  Future<void> _scrubIncognitoSession(BrowserEngine sampleEngine) async {
    try {
      await sampleEngine.controller?.clearCache();
      await sampleEngine.controller?.clearLocalStorage();
      final WebViewCookieManager cookieManager = WebViewCookieManager();
      await cookieManager.clearCookies();
    } catch (_) {
      // Ignore cleanup errors in headless test environments.
    }
  }

  @override
  void dispose() {
    for (final BrowserTab tab in _tabs) {
      tab.engine.removeListener(_onTabEngineChanged);
      tab.engine.dispose();
    }
    super.dispose();
  }
}
