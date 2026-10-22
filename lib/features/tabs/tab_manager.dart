import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../browser/engine/browser_engine.dart';
import '../settings/browser_settings.dart';

class BrowserTab {
  BrowserTab({
    required this.id,
    required this.isIncognito,
    required this.engine,
    required this.createdAt,
  }) : repaintKey = GlobalKey();

  final String id;
  final bool isIncognito;
  final BrowserEngine engine;
  final DateTime createdAt;
  final GlobalKey repaintKey;
  Uint8List? previewBytes;

  String get displayTitle {
    if (engine.isShowingStartPage) {
      return isIncognito ? 'Incognito Home' : 'Home';
    }
    if (engine.isShowingHeavenSearch) {
      final String q = engine.heavenSearchQuery;
      return q.isEmpty ? 'Heaven Search' : q;
    }
    return engine.pageTitle;
  }

  String get displaySubtitle {
    if (engine.isShowingStartPage) {
      return isIncognito ? 'Private stealth session' : 'Heaven Home & News';
    }
    if (engine.isShowingHeavenSearch) {
      return 'Heaven Search';
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

  Future<void> captureTabPreview(BrowserTab tab) async {
    if (!enablePlatformWebView) {
      return;
    }
    try {
      // 1. If showing a native WebView website, capture live Android WebView pixels
      final Uint8List? webShot = await tab.engine.captureNativeWebViewPreview();
      if (webShot != null && webShot.isNotEmpty) {
        tab.previewBytes = webShot;
        notifyListeners();
        return;
      }
      // 2. Otherwise capture the Flutter RepaintBoundary (Home / Search screen)
      final BuildContext? ctx = tab.repaintKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final RenderObject? ro = ctx.findRenderObject();
      if (ro is RenderRepaintBoundary && !ro.debugNeedsPaint) {
        final ui.Image img = await ro.toImage(pixelRatio: 1.25);
        final ByteData? byteData = await img.toByteData(
          format: ui.ImageByteFormat.png,
        );
        img.dispose();
        if (byteData != null) {
          tab.previewBytes = byteData.buffer.asUint8List();
          notifyListeners();
        }
      }
    } catch (_) {
      // Non-fatal fallback if surface isn't ready yet.
    }
  }

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
    if (switchTo && _tabs.isNotEmpty) {
      unawaited(captureTabPreview(activeTab));
    }
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
    unawaited(captureTabPreview(activeTab));
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
      final bool moreIncognito = _tabs.any((BrowserTab t) => t.isIncognito);
      if (!moreIncognito && enablePlatformWebView) {
        await _scrubIncognitoSession(removed.engine);
      }
    }
    removed.engine.dispose();

    if (_tabs.isEmpty) {
      _spawnTab(incognito: false, switchTo: true);
    } else if (_activeTabId == tabId) {
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
