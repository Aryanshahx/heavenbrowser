import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../browser/engine/browser_engine.dart';
import '../extensions/extensions_controller.dart';
import '../settings/browser_settings.dart';

class TabGroup {
  TabGroup({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  final String id;
  String name;
  int colorValue;

  Color get color => Color(colorValue);

  static const List<int> palette = <int>[
    0xFF2563EB, // Sapphire
    0xFF10B981, // Emerald
    0xFF8B5CF6, // Purple
    0xFFF59E0B, // Amber
    0xFFEC4899, // Rose
    0xFF06B6D4, // Cyan
  ];
}

class BrowserTab {
  BrowserTab({
    required this.id,
    required this.isIncognito,
    required this.engine,
    required this.createdAt,
    this.groupId,
  }) : repaintKey = GlobalKey();

  final String id;
  final bool isIncognito;
  final BrowserEngine engine;
  final DateTime createdAt;
  final GlobalKey repaintKey;
  Uint8List? previewBytes;
  String? groupId;

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
    this.extensions,
    this.enablePlatformWebView = true,
  }) {
    _spawnTab(incognito: false, switchTo: true);
  }

  final BrowserSettingsController settings;
  final ExtensionsController? extensions;
  final bool enablePlatformWebView;

  final List<BrowserTab> _tabs = <BrowserTab>[];
  final List<TabGroup> _groups = <TabGroup>[];
  late String _activeTabId;
  int _nextIdCounter = 1;
  int _nextGroupCounter = 1;

  List<BrowserTab> get allTabs => List<BrowserTab>.unmodifiable(_tabs);
  List<TabGroup> get groups => List<TabGroup>.unmodifiable(_groups);
  List<BrowserTab> get normalTabs =>
      _tabs.where((BrowserTab t) => !t.isIncognito).toList(growable: false);
  List<BrowserTab> get incognitoTabs =>
      _tabs.where((BrowserTab t) => t.isIncognito).toList(growable: false);

  TabGroup? groupById(String? groupId) {
    if (groupId == null) return null;
    for (final TabGroup g in _groups) {
      if (g.id == groupId) return g;
    }
    return null;
  }

  TabGroup createGroupAndAddTab({
    required String name,
    required String tabId,
    int? colorValue,
  }) {
    final String cleanName = name.trim().isEmpty ? 'Group' : name.trim();
    final int chosenColor =
        colorValue ??
        TabGroup.palette[(_nextGroupCounter - 1) % TabGroup.palette.length];
    final TabGroup group = TabGroup(
      id: 'grp_${_nextGroupCounter++}',
      name: cleanName,
      colorValue: chosenColor,
    );
    _groups.add(group);
    for (final BrowserTab t in _tabs) {
      if (t.id == tabId) {
        t.groupId = group.id;
        break;
      }
    }
    notifyListeners();
    return group;
  }

  void assignTabToGroup(String tabId, String? groupId) {
    for (final BrowserTab t in _tabs) {
      if (t.id == tabId) {
        t.groupId = groupId;
        notifyListeners();
        return;
      }
    }
  }

  void deleteGroup(String groupId) {
    _groups.removeWhere((TabGroup g) => g.id == groupId);
    for (final BrowserTab t in _tabs) {
      if (t.groupId == groupId) {
        t.groupId = null;
      }
    }
    notifyListeners();
  }

  bool switchAdjacentTab(int delta) {
    final BrowserTab current = activeTab;
    final List<BrowserTab> pool = current.isIncognito
        ? incognitoTabs
        : normalTabs;
    if (pool.length <= 1) return false;
    final int idx = pool.indexWhere((BrowserTab t) => t.id == current.id);
    if (idx < 0) return false;
    final int nextIdx = (idx + delta) % pool.length;
    final int wrapped = nextIdx < 0 ? pool.length - 1 : nextIdx;
    switchToTab(pool[wrapped].id);
    return true;
  }

  Future<void> reloadFailedTabs() async {
    for (final BrowserTab t in _tabs) {
      if (t.engine.errorMessage != null && !t.engine.isShowingStartPage) {
        await t.engine.reloadFullPage();
      }
    }
  }

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
      extensions: extensions,
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
