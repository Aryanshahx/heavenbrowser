import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/utils/omnibox_parser.dart';
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

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'colorValue': colorValue,
  };

  factory TabGroup.fromJson(Map<String, Object?> json) {
    return TabGroup(
      id: (json['id']?.toString() ?? 'grp_1').trim(),
      name: (json['name']?.toString() ?? 'Group').trim(),
      colorValue: (json['colorValue'] as num?)?.toInt() ?? palette.first,
    );
  }

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
    DateTime? lastActiveAt,
    this.groupId,
  }) : lastActiveAt = lastActiveAt ?? createdAt,
       repaintKey = GlobalKey();

  final String id;
  final bool isIncognito;
  final BrowserEngine engine;
  final DateTime createdAt;
  DateTime lastActiveAt;
  final GlobalKey repaintKey;
  Uint8List? previewBytes;
  String? groupId;

  String get displayTitle {
    if (engine.isShowingStartPage) {
      return isIncognito ? 'Incognito Home' : 'Home';
    }
    return engine.pageTitle;
  }

  String get displaySubtitle {
    if (engine.isShowingStartPage) {
      return isIncognito ? 'Private stealth session' : 'Heaven Home & News';
    }
    if (engine.isHibernated) {
      return '${engine.currentHost ?? OmniboxParser.formatDisplayUrl(engine.currentUrl)} • Sleeping';
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
    _restoreOrInitializeSession();
    if (enablePlatformWebView) {
      _hibernationTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(hibernateInactiveTabsNow()),
      );
    }
  }

  static const String _keySavedTabs = 'hb.openTabs.v13';
  static const String _keySavedGroups = 'hb.tabGroups.v13';
  static const String _keySavedActiveTab = 'hb.activeTabId.v13';

  final BrowserSettingsController settings;
  final ExtensionsController? extensions;
  final bool enablePlatformWebView;

  final List<BrowserTab> _tabs = <BrowserTab>[];
  final List<TabGroup> _groups = <TabGroup>[];
  late String _activeTabId;
  int _nextIdCounter = 1;
  int _nextGroupCounter = 1;
  Timer? _hibernationTimer;
  bool _incognitoSessionUnlocked = false;
  int _lastPersistMs = 0;

  List<BrowserTab> get allTabs => List<BrowserTab>.unmodifiable(_tabs);
  List<TabGroup> get groups => List<TabGroup>.unmodifiable(_groups);
  List<BrowserTab> get normalTabs =>
      _tabs.where((BrowserTab t) => !t.isIncognito).toList(growable: false);
  List<BrowserTab> get incognitoTabs =>
      _tabs.where((BrowserTab t) => t.isIncognito).toList(growable: false);

  bool get isIncognitoLocked =>
      settings.biometricLockIncognito && !_incognitoSessionUnlocked;

  void markIncognitoUnlocked(bool unlocked) {
    if (_incognitoSessionUnlocked != unlocked) {
      _incognitoSessionUnlocked = unlocked;
      notifyListeners();
    }
  }

  int get hibernatedTabCount =>
      _tabs.where((BrowserTab t) => t.engine.isHibernated).length;

  void _restoreOrInitializeSession() {
    if (settings.clearOnExit) {
      unawaited(settings.prefs.remove(_keySavedTabs));
      unawaited(settings.prefs.remove(_keySavedGroups));
      unawaited(settings.prefs.remove(_keySavedActiveTab));
      _spawnTab(incognito: false, switchTo: true);
      return;
    }

    final String? rawGroups = settings.prefs.getString(_keySavedGroups);
    if (rawGroups != null && rawGroups.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawGroups);
        if (decoded is List<Object?>) {
          for (final Object? item in decoded) {
            if (item is Map<String, Object?>) {
              final TabGroup g = TabGroup.fromJson(item);
              if (g.id.isNotEmpty) {
                _groups.add(g);
                final int? numSuffix = int.tryParse(
                  g.id.replaceFirst('grp_', ''),
                );
                if (numSuffix != null && numSuffix >= _nextGroupCounter) {
                  _nextGroupCounter = numSuffix + 1;
                }
              }
            }
          }
        }
      } on FormatException {
        _groups.clear();
      }
    }

    final String? rawTabs = settings.prefs.getString(_keySavedTabs);
    final String? savedActiveId = settings.prefs.getString(_keySavedActiveTab);
    if (rawTabs != null && rawTabs.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawTabs);
        if (decoded is List<Object?> && decoded.isNotEmpty) {
          final List<Map<String, Object?>> validEntries = decoded
              .whereType<Map<String, Object?>>()
              .toList();
          if (validEntries.isNotEmpty) {
            String targetActive = savedActiveId ?? '';
            final bool hasTarget = validEntries.any(
              (Map<String, Object?> m) => m['id']?.toString() == targetActive,
            );
            if (!hasTarget) {
              targetActive =
                  validEntries.last['id']?.toString() ?? 'tab_1';
            }

            for (final Map<String, Object?> entry in validEntries) {
              final String id =
                  (entry['id']?.toString() ?? 'tab_${_nextIdCounter++}').trim();
              final int? numSuffix = int.tryParse(
                id.replaceFirst('tab_', ''),
              );
              if (numSuffix != null && numSuffix >= _nextIdCounter) {
                _nextIdCounter = numSuffix + 1;
              }
              String? url = entry['url']?.toString().trim();
              if (url != null && OmniboxParser.isLegacyHeavenUrl(url)) {
                final String q = OmniboxParser.extractLegacyHeavenQuery(url);
                url = SearchEngine.google.buildSearchUri(q).toString();
              }
              final String? title = entry['title']?.toString().trim();
              final String? groupId = entry['groupId']?.toString().trim();
              final bool isActiveEntry = id == targetActive;
              final bool startAsSleeping =
                  !isActiveEntry && url != null && url.isNotEmpty;

              final BrowserEngine engine = BrowserEngine(
                settings: settings,
                extensions: extensions,
                onOpenNewTabFromExtension: (String extUrl) {
                  unawaited(openNewTab(incognito: false, initialInput: extUrl));
                },
                isIncognito: false,
                enablePlatformWebView: enablePlatformWebView,
                initialPersistedUrl: (url != null && url.isNotEmpty)
                    ? url
                    : null,
                initialPersistedTitle: title,
                startHibernated: startAsSleeping,
              );
              engine.addListener(_onTabEngineChanged);

              _tabs.add(
                BrowserTab(
                  id: id,
                  isIncognito: false,
                  engine: engine,
                  createdAt: DateTime.now(),
                  groupId: (groupId != null && groupId.isNotEmpty)
                      ? groupId
                      : null,
                ),
              );
            }
            _activeTabId = targetActive;
            return;
          }
        }
      } on FormatException {
        _tabs.clear();
      }
    }

    _spawnTab(incognito: false, switchTo: true);
    _persistSessionSnapshot(force: true);
  }

  void _persistSessionSnapshot({bool force = false}) {
    if (settings.clearOnExit) {
      return;
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (!force && (now - _lastPersistMs) < 250) {
      return;
    }
    _lastPersistMs = now;

    final List<BrowserTab> stdTabs = normalTabs;
    final List<Map<String, Object?>> serializedTabs = stdTabs
        .map(
          (BrowserTab t) => <String, Object?>{
            'id': t.id,
            'url': t.engine.currentUrl ?? '',
            'title': t.engine.pageTitle,
            'groupId': t.groupId ?? '',
          },
        )
        .toList(growable: false);

    final List<Map<String, Object?>> serializedGroups = _groups
        .map((TabGroup g) => g.toJson())
        .toList(growable: false);

    final String activeStdId = stdTabs.any((BrowserTab t) => t.id == _activeTabId)
        ? _activeTabId
        : (stdTabs.isNotEmpty ? stdTabs.last.id : '');

    unawaited(settings.prefs.setString(_keySavedTabs, jsonEncode(serializedTabs)));
    unawaited(
      settings.prefs.setString(_keySavedGroups, jsonEncode(serializedGroups)),
    );
    if (activeStdId.isNotEmpty) {
      unawaited(settings.prefs.setString(_keySavedActiveTab, activeStdId));
    }
  }

  /// Freezes background tabs that have been inactive longer than [threshold]
  /// (defaults to `settings.tabHibernationMinutes`), skipping active or media-playing tabs.
  Future<int> hibernateInactiveTabsNow({Duration? threshold}) async {
    if (!settings.tabHibernationEnabled && threshold == null) {
      return 0;
    }
    final Duration maxIdle =
        threshold ?? Duration(minutes: settings.tabHibernationMinutes);
    final DateTime now = DateTime.now();
    int frozenCount = 0;

    for (final BrowserTab tab in _tabs) {
      if (tab.id == _activeTabId) continue;
      if (tab.engine.isShowingStartPage ||
          tab.engine.isHibernated ||
          tab.engine.isMediaPlaying) {
        continue;
      }
      if (now.difference(tab.lastActiveAt) >= maxIdle) {
        await tab.engine.hibernate();
        frozenCount += 1;
      }
    }
    if (frozenCount > 0) {
      notifyListeners();
    }
    return frozenCount;
  }

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
    _persistSessionSnapshot(force: true);
    notifyListeners();
    return group;
  }

  void assignTabToGroup(String tabId, String? groupId) {
    for (final BrowserTab t in _tabs) {
      if (t.id == tabId) {
        t.groupId = groupId;
        _persistSessionSnapshot(force: true);
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
    _persistSessionSnapshot(force: true);
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
      final Uint8List? webShot = await tab.engine.captureNativeWebViewPreview();
      if (webShot != null && webShot.isNotEmpty) {
        tab.previewBytes = webShot;
        notifyListeners();
        return;
      }
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
      onOpenNewTabFromExtension: (String url) {
        unawaited(openNewTab(incognito: incognito, initialInput: url));
      },
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
    _persistSessionSnapshot();
    notifyListeners();
  }

  Future<BrowserTab> openNewTab({
    bool incognito = false,
    String? initialInput,
    bool switchTo = true,
  }) async {
    if (switchTo && _tabs.isNotEmpty) {
      activeTab.lastActiveAt = DateTime.now();
      unawaited(captureTabPreview(activeTab));
    }
    final BrowserTab tab = _spawnTab(incognito: incognito, switchTo: switchTo);
    _persistSessionSnapshot(force: true);
    notifyListeners();
    if (initialInput != null && initialInput.trim().isNotEmpty) {
      await tab.engine.loadUserEntry(initialInput.trim());
      _persistSessionSnapshot(force: true);
    }
    return tab;
  }

  void switchToTab(String tabId) {
    if (_activeTabId == tabId) {
      activeTab.lastActiveAt = DateTime.now();
      if (activeTab.engine.isHibernated) {
        unawaited(activeTab.engine.wakeFromHibernation());
      }
      return;
    }
    BrowserTab? target;
    for (final BrowserTab t in _tabs) {
      if (t.id == tabId) {
        target = t;
        break;
      }
    }
    if (target == null) {
      return;
    }
    activeTab.lastActiveAt = DateTime.now();
    unawaited(captureTabPreview(activeTab));
    _activeTabId = tabId;
    target.lastActiveAt = DateTime.now();
    if (target.engine.isHibernated) {
      unawaited(target.engine.wakeFromHibernation());
    }
    _persistSessionSnapshot(force: true);
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
      if (activeTab.engine.isHibernated) {
        unawaited(activeTab.engine.wakeFromHibernation());
      }
    }
    _persistSessionSnapshot(force: true);
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
      if (activeTab.engine.isHibernated) {
        unawaited(activeTab.engine.wakeFromHibernation());
      }
    }
    _persistSessionSnapshot(force: true);
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
    _groups.clear();
    await settings.clearHistory();
    await settings.prefs.remove(_keySavedTabs);
    await settings.prefs.remove(_keySavedGroups);
    await settings.prefs.remove(_keySavedActiveTab);
    _spawnTab(incognito: false, switchTo: true);
    _persistSessionSnapshot(force: true);
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
    _hibernationTimer?.cancel();
    for (final BrowserTab tab in _tabs) {
      tab.engine.removeListener(_onTabEngineChanged);
      tab.engine.dispose();
    }
    super.dispose();
  }
}
