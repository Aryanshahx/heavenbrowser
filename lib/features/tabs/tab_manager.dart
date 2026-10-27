import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/omnibox_parser.dart';
import '../browser/engine/browser_engine.dart';
import '../settings/browser_settings.dart';
import '../shield/native_shield_bridge.dart';

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
    this.openerTabId,
    this.previewBytes,
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
  String? openerTabId;

  String get displayTitle {
    if (engine.isShowingDownloadsPage) {
      return 'Downloads';
    }
    if (engine.isShowingStartPage) {
      return isIncognito ? 'Incognito Home' : 'Home';
    }
    return engine.pageTitle;
  }

  String get displaySubtitle {
    if (engine.isShowingDownloadsPage) {
      return 'Heaven Downloads';
    }
    if (engine.isShowingStartPage) {
      return isIncognito ? 'Private stealth session' : 'Heaven Home & News';
    }
    return OmniboxParser.formatDisplayUrl(engine.currentUrl);
  }
}

class TabManagerController extends ChangeNotifier {
  TabManagerController({
    required this.settings,
    this.enablePlatformWebView = true,
  }) {
    _restoreOrInitializeSession();
  }

  static const String _keySavedTabs = 'hb.openTabs.v13';
  static const String _keySavedGroups = 'hb.tabGroups.v13';
  static const String _keySavedActiveTab = 'hb.activeTabId.v13';
  static const String _keyTabPreviewPrefix = 'hb.tabPreview.v15.';

  static String _previewStorageKey(String tabId) =>
      '$_keyTabPreviewPrefix$tabId';

  final BrowserSettingsController settings;
  final bool enablePlatformWebView;

  final List<BrowserTab> _tabs = <BrowserTab>[];
  final List<TabGroup> _groups = <TabGroup>[];
  final Map<String, String> _lastEngineSummaryByTab = <String, String>{};
  final ValueNotifier<int> viewportRevision = ValueNotifier<int>(0);
  late String _activeTabId;
  int _nextIdCounter = 1;
  int _nextGroupCounter = 1;
  bool _incognitoSessionUnlocked = false;
  int _lastPersistMs = 0;

  /// Direction hint for smooth viewport animations (+1 = forward/new, -1 = back/close, 0 = initial).
  int lastTransitionDirection = 0;
  int tabTransitionEpoch = 0;

  static const int _maxLiveBackgroundWebViews = 2;

  void _bumpViewport() {
    viewportRevision.value += 1;
  }

  static String _engineSummary(BrowserEngine e) =>
      '${e.currentUrl ?? ''}|${e.pageTitle}|${e.isShowingStartPage}|${e.isShowingDownloadsPage}';

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

  void _restoreOrInitializeSession() {
    if (settings.clearOnExit || settings.closeTabsOnExit) {
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
              final String? openerTabId = entry['openerTabId']
                  ?.toString()
                  .trim();

              Uint8List? restoredPreview;
              final String? rawPrevB64 = settings.prefs.getString(
                _previewStorageKey(id),
              );
              if (rawPrevB64 != null && rawPrevB64.isNotEmpty) {
                try {
                  final Uint8List decodedBytes = base64Decode(rawPrevB64);
                  if (decodedBytes.isNotEmpty) {
                    restoredPreview = decodedBytes;
                  }
                } on FormatException {
                  // Ignore malformed cached preview.
                }
              }

              final BrowserEngine engine = BrowserEngine(
                settings: settings,
                isIncognito: false,
                enablePlatformWebView: enablePlatformWebView,
                deferWebViewInit: id != targetActive,
                initialPersistedUrl: (url != null && url.isNotEmpty)
                    ? url
                    : null,
                initialPersistedTitle: title,
              );
              engine.addListener(_onTabEngineChanged);

              final BrowserTab restoredTab = BrowserTab(
                id: id,
                isIncognito: false,
                engine: engine,
                createdAt: DateTime.now(),
                groupId: (groupId != null && groupId.isNotEmpty)
                    ? groupId
                    : null,
                openerTabId: (openerTabId != null && openerTabId.isNotEmpty)
                    ? openerTabId
                    : null,
                previewBytes: restoredPreview,
              );
              _lastEngineSummaryByTab[id] = _engineSummary(engine);
              _tabs.add(restoredTab);
            }
            _activeTabId = targetActive;
            _bumpViewport();
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
    if (settings.clearOnExit || settings.closeTabsOnExit) {
      unawaited(settings.prefs.remove(_keySavedTabs));
      unawaited(settings.prefs.remove(_keySavedActiveTab));
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
            'openerTabId': t.openerTabId ?? '',
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

  /// Moves [fromTabId] to the grid slot of [toTabId] and persists the new order.
  bool moveTab(String fromTabId, String toTabId) {
    if (fromTabId == toTabId) {
      return false;
    }
    final int fromIndex = _tabs.indexWhere(
      (BrowserTab t) => t.id == fromTabId,
    );
    final int toIndex = _tabs.indexWhere((BrowserTab t) => t.id == toTabId);
    if (fromIndex < 0 || toIndex < 0 || fromIndex == toIndex) {
      return false;
    }
    if (_tabs[fromIndex].isIncognito != _tabs[toIndex].isIncognito) {
      return false;
    }
    final BrowserTab moving = _tabs.removeAt(fromIndex);
    _tabs.insert(toIndex, moving);
    _bumpViewport();
    _persistSessionSnapshot(force: true);
    notifyListeners();
    return true;
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
      if (t.engine.errorMessage != null && t.engine.isShowingWebPage) {
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

  void _persistTabPreviewBytes(BrowserTab tab, Uint8List bytes) {
    if (tab.isIncognito || settings.clearOnExit || bytes.isEmpty) {
      return;
    }
    unawaited(
      settings.prefs.setString(_previewStorageKey(tab.id), base64Encode(bytes)),
    );
  }

  void _removePersistedTabPreview(String tabId) {
    unawaited(settings.prefs.remove(_previewStorageKey(tabId)));
  }

  Future<void> captureTabPreview(BrowserTab tab) async {
    if (!enablePlatformWebView) {
      return;
    }
    if (!tab.engine.isShowingWebPage) {
      if (tab.previewBytes != null) {
        tab.previewBytes = null;
        _removePersistedTabPreview(tab.id);
        notifyListeners();
      }
      return;
    }
    try {
      final Uint8List? webShot = await tab.engine.captureNativeWebViewPreview();
      if (webShot != null && webShot.isNotEmpty) {
        tab.previewBytes = webShot;
        _persistTabPreviewBytes(tab, webShot);
        notifyListeners();
        return;
      }
      final BuildContext? ctx = tab.repaintKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final RenderObject? ro = ctx.findRenderObject();
      if (ro is RenderRepaintBoundary && !ro.debugNeedsPaint) {
        final ui.Image img = await ro.toImage(pixelRatio: 1.15);
        final ByteData? byteData = await img.toByteData(
          format: ui.ImageByteFormat.png,
        );
        img.dispose();
        if (byteData != null) {
          final Uint8List pngBytes = byteData.buffer.asUint8List();
          if (pngBytes.isNotEmpty) {
            tab.previewBytes = pngBytes;
            _persistTabPreviewBytes(tab, pngBytes);
            notifyListeners();
          }
        }
      }
    } catch (_) {
      // Non-fatal fallback if surface isn't ready yet; existing previewBytes stay intact!
    }
  }

  BrowserTab _spawnTab({
    required bool incognito,
    required bool switchTo,
    String? openerTabId,
    String? groupId,
  }) {
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
      openerTabId: openerTabId,
      groupId: groupId,
    );
    _lastEngineSummaryByTab[id] = _engineSummary(engine);
    if (openerTabId != null) {
      final int parentIdx = _tabs.indexWhere(
        (BrowserTab t) => t.id == openerTabId,
      );
      if (parentIdx >= 0 && parentIdx < _tabs.length - 1) {
        _tabs.insert(parentIdx + 1, tab);
      } else {
        _tabs.add(tab);
      }
    } else {
      _tabs.add(tab);
    }
    if (switchTo) {
      _activeTabId = id;
      _syncPrivateScreenshotSecurity();
    }
    _bumpViewport();
    return tab;
  }

  void _onTabEngineChanged() {
    bool summaryChanged = false;
    for (final BrowserTab t in _tabs) {
      final String next = _engineSummary(t.engine);
      if (_lastEngineSummaryByTab[t.id] != next) {
        _lastEngineSummaryByTab[t.id] = next;
        summaryChanged = true;
      }
    }
    if (!summaryChanged) {
      return;
    }
    _persistSessionSnapshot();
    notifyListeners();
  }

  Future<BrowserTab> openDownloadsTab({bool? incognito}) async {
    final bool targetIncognito = incognito ?? isActiveIncognito;
    for (final BrowserTab t in _tabs) {
      if (t.isIncognito == targetIncognito && t.engine.isShowingDownloadsPage) {
        switchToTab(t.id);
        return t;
      }
    }
    return openNewTab(
      incognito: targetIncognito,
      initialInput: AppConstants.downloadsTabUrl,
      switchTo: true,
    );
  }

  void _hibernateExcessBackgroundTabs() {
    if (!enablePlatformWebView) return;
    final List<BrowserTab> candidates = _tabs
        .where(
          (BrowserTab t) =>
              t.id != _activeTabId &&
              t.engine.hasLiveWebView &&
              !t.engine.isMediaPlaying,
        )
        .toList();
    if (candidates.length <= _maxLiveBackgroundWebViews) {
      return;
    }
    candidates.sort(
      (BrowserTab a, BrowserTab b) => a.lastActiveAt.compareTo(b.lastActiveAt),
    );
    final int toHibernate = candidates.length - _maxLiveBackgroundWebViews;
    for (int i = 0; i < toHibernate; i++) {
      candidates[i].engine.hibernateWebView();
    }
  }

  Future<BrowserTab> openNewTab({
    bool incognito = false,
    String? initialInput,
    bool switchTo = true,
    String? openerTabId,
    String? groupId,
  }) async {
    if (switchTo && _tabs.isNotEmpty) {
      activeTab.lastActiveAt = DateTime.now();
      unawaited(captureTabPreview(activeTab));
      lastTransitionDirection = 1;
      tabTransitionEpoch += 1;
    }
    final BrowserTab tab = _spawnTab(
      incognito: incognito,
      switchTo: switchTo,
      openerTabId: openerTabId,
      groupId: groupId,
    );
    _hibernateExcessBackgroundTabs();
    _persistSessionSnapshot(force: true);
    notifyListeners();
    if (initialInput != null && initialInput.trim().isEmpty == false) {
      await tab.engine.loadUserEntry(
        initialInput.trim(),
        replaceInitialBlankHistory: openerTabId != null,
      );
      _persistSessionSnapshot(force: true);
    }
    return tab;
  }

  /// True when the active tab was opened via cross-website redirect / link from
  /// another open tab and can seamlessly return to that opener tab on Back.
  bool get canReturnToOpenerTab {
    if (_tabs.isEmpty) return false;
    final BrowserTab current = activeTab;
    final String? parentId = current.openerTabId;
    if (parentId == null || parentId.isEmpty) return false;
    return _tabs.any(
      (BrowserTab t) => t.id == parentId && t.isIncognito == current.isIncognito,
    );
  }

  /// Navigates back inside the active tab if possible; otherwise closes the
  /// spawned child tab and seamlessly switches back to its opener tab.
  Future<bool> navigateBackSeamlessly() async {
    if (activeEngine.canGoBack) {
      await activeEngine.goBack();
      return true;
    }
    if (canReturnToOpenerTab) {
      await closeTab(activeTab.id);
      return true;
    }
    return false;
  }

  void switchToTab(String tabId) {
    if (_activeTabId == tabId) {
      activeTab.lastActiveAt = DateTime.now();
      unawaited(activeTab.engine.focusNativeWebView());
      return;
    }
    final int oldIndex = activeTabIndex;
    BrowserTab? target;
    int newIndex = 0;
    for (int i = 0; i < _tabs.length; i++) {
      if (_tabs[i].id == tabId) {
        target = _tabs[i];
        newIndex = i;
        break;
      }
    }
    if (target == null) {
      return;
    }
    activeTab.lastActiveAt = DateTime.now();
    unawaited(captureTabPreview(activeTab));
    lastTransitionDirection = newIndex >= oldIndex ? 1 : -1;
    tabTransitionEpoch += 1;
    _activeTabId = tabId;
    target.lastActiveAt = DateTime.now();
    unawaited(target.engine.focusNativeWebView());
    _hibernateExcessBackgroundTabs();
    _syncPrivateScreenshotSecurity();
    _bumpViewport();
    _persistSessionSnapshot(force: true);
    notifyListeners();
  }

  void _syncPrivateScreenshotSecurity() {
    if (!enablePlatformWebView) return;
    unawaited(
      NativeShieldBridge.instance.updatePrivateWindowSecurity(
        blockScreenshots:
            isActiveIncognito && !settings.allowPrivateScreenshots,
      ),
    );
  }

  Future<void> closeTab(String tabId) async {
    final int idx = _tabs.indexWhere((BrowserTab t) => t.id == tabId);
    if (idx < 0) {
      return;
    }
    final BrowserTab removed = _tabs.removeAt(idx);
    final String closedHost = OmniboxParser.cleanDomain(
      removed.engine.currentUrl,
    );
    _lastEngineSummaryByTab.remove(removed.id);
    removed.engine.removeListener(_onTabEngineChanged);
    _removePersistedTabPreview(removed.id);

    if (!removed.isIncognito &&
        closedHost.isNotEmpty &&
        settings.autoShredMode == HeavenAutoShredMode.siteTabClosed) {
      final bool stillOpenElsewhere = _tabs.any(
        (BrowserTab t) =>
            OmniboxParser.cleanDomain(t.engine.currentUrl) == closedHost,
      );
      if (!stillOpenElsewhere && enablePlatformWebView) {
        unawaited(NativeShieldBridge.instance.clearSiteData(domain: closedHost));
      }
    }

    if (removed.isIncognito) {
      final bool moreIncognito = _tabs.any((BrowserTab t) => t.isIncognito);
      if (!moreIncognito && enablePlatformWebView) {
        await _scrubIncognitoSession(removed.engine);
      }
    }
    removed.engine.dispose();

    if (_tabs.isEmpty) {
      lastTransitionDirection = -1;
      tabTransitionEpoch += 1;
      _spawnTab(incognito: false, switchTo: true);
    } else if (_activeTabId == tabId) {
      lastTransitionDirection = -1;
      tabTransitionEpoch += 1;
      final String? parentId = removed.openerTabId;
      final BrowserTab? opener = (parentId != null && parentId.isNotEmpty)
          ? _tabs
                .where(
                  (BrowserTab t) =>
                      t.id == parentId && t.isIncognito == removed.isIncognito,
                )
                .firstOrNull
          : null;
      if (opener != null) {
        _activeTabId = opener.id;
        opener.lastActiveAt = DateTime.now();
      } else {
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
      unawaited(activeTab.engine.focusNativeWebView());
    }
    _syncPrivateScreenshotSecurity();
    _bumpViewport();
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
      _lastEngineSummaryByTab.remove(tab.id);
      tab.engine.removeListener(_onTabEngineChanged);
      _removePersistedTabPreview(tab.id);
      tab.engine.dispose();
      _tabs.remove(tab);
    }

    if (_tabs.isEmpty) {
      _spawnTab(incognito: false, switchTo: true);
    } else if (!_tabs.any((BrowserTab t) => t.id == _activeTabId)) {
      _activeTabId = _tabs.last.id;
    }
    _bumpViewport();
    _persistSessionSnapshot(force: true);
    notifyListeners();
  }

  Future<void> burnAllSessionsAndData() async {
    if (enablePlatformWebView && _tabs.isNotEmpty) {
      await _tabs.first.engine.burnBrowsingData();
    }
    for (final BrowserTab tab in _tabs) {
      _lastEngineSummaryByTab.remove(tab.id);
      tab.engine.removeListener(_onTabEngineChanged);
      _removePersistedTabPreview(tab.id);
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
    for (final BrowserTab tab in _tabs) {
      tab.engine.removeListener(_onTabEngineChanged);
      tab.engine.dispose();
    }
    viewportRevision.dispose();
    super.dispose();
  }
}
