import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/browser/presentation/browser_screen.dart';
import 'features/downloads/downloads_controller.dart';
import 'features/news/interest_news_service.dart';
import 'features/search/heaven_search_service.dart';
import 'features/settings/browser_settings.dart';
import 'features/shield/native_shield_bridge.dart';
import 'features/tabs/tab_manager.dart';
import 'features/vpn/vpn_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final BrowserSettingsController settings = BrowserSettingsController(prefs);
  final DownloadsController downloads = DownloadsController(prefs);
  final InterestProfileController interests = InterestProfileController(prefs);
  final HeavenNewsFeedService newsService = HeavenNewsFeedService(
    prefs: prefs,
    interests: interests,
  );
  final VpnController vpn = VpnController(prefs);

  runApp(
    HeavenBrowserApp(
      settings: settings,
      downloads: downloads,
      interests: interests,
      newsService: newsService,
      vpn: vpn,
    ),
  );
}

class HeavenBrowserApp extends StatefulWidget {
  const HeavenBrowserApp({
    super.key,
    required this.settings,
    this.downloads,
    this.interests,
    this.newsService,
    this.vpn,
    this.enablePlatformWebView = true,
    this.searchService,
  });

  final BrowserSettingsController settings;
  final DownloadsController? downloads;
  final InterestProfileController? interests;
  final HeavenNewsFeedService? newsService;
  final VpnController? vpn;
  final bool enablePlatformWebView;
  final HeavenSearchService? searchService;

  @override
  State<HeavenBrowserApp> createState() => _HeavenBrowserAppState();
}

class _HeavenBrowserAppState extends State<HeavenBrowserApp>
    with WidgetsBindingObserver {
  late final TabManagerController _tabManager;
  late final HeavenSearchService _searchService;
  DownloadsController? _ownedDownloads;
  InterestProfileController? _ownedInterests;
  HeavenNewsFeedService? _ownedNewsService;
  VpnController? _ownedVpn;
  bool _appUnlocked = false;
  bool _verifyingAppLock = false;

  DownloadsController get _effectiveDownloads =>
      widget.downloads ?? _ownedDownloads!;
  InterestProfileController get _effectiveInterests =>
      widget.interests ?? _ownedInterests!;
  HeavenNewsFeedService get _effectiveNews =>
      widget.newsService ?? _ownedNewsService!;
  VpnController get _effectiveVpn => widget.vpn ?? _ownedVpn!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appUnlocked = !widget.settings.biometricLockApp;

    _tabManager = TabManagerController(
      settings: widget.settings,
      enablePlatformWebView: widget.enablePlatformWebView,
    );
    widget.settings.addListener(_onPrivacyWindowSettingsChanged);
    _searchService = widget.searchService ?? HeavenSearchService();

    if (widget.downloads == null) {
      _ownedDownloads = DownloadsController(
        widget.settings.prefs,
        enableNativePolling: widget.enablePlatformWebView,
      );
    }
    if (widget.interests == null) {
      _ownedInterests = InterestProfileController(widget.settings.prefs);
    }
    if (widget.newsService == null) {
      _ownedNewsService = HeavenNewsFeedService(
        prefs: widget.settings.prefs,
        interests: _effectiveInterests,
        client: widget.enablePlatformWebView
            ? null
            : MockClient((_) async => http.Response('<rss></rss>', 200)),
      );
    }
    if (widget.vpn == null) {
      _ownedVpn = VpnController(
        widget.settings.prefs,
        enableNativePolling: widget.enablePlatformWebView,
        client: widget.enablePlatformWebView
            ? null
            : MockClient(
                (_) async =>
                    http.Response('ip=104.28.14.9\nloc=SG\nwarp=on\n', 200),
              ),
      );
    }
    _effectiveVpn.onTunnelConnected = () {
      unawaited(_tabManager.reloadFailedTabs());
    };

    final String initialRoute = PlatformDispatcher.instance.defaultRouteName;
    if (initialRoute.startsWith('http://') ||
        initialRoute.startsWith('https://')) {
      unawaited(_tabManager.activeEngine.loadUserEntry(initialRoute));
    }

    // Request Android POST_NOTIFICATIONS permission on app startup, apply exit-shred if enabled, and sync FLAG_SECURE
    if (widget.enablePlatformWebView) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (widget.settings.clearOnExit) {
          await widget.settings.clearHistoryOnly();
          await NativeShieldBridge.instance.clearSiteData(domain: '');
        } else if (widget.settings.autoShredMode ==
            HeavenAutoShredMode.appExit) {
          await NativeShieldBridge.instance.clearSiteData(domain: '');
        }
        await NativeShieldBridge.instance.updatePrivateWindowSecurity(
          blockScreenshots:
              _tabManager.activeTab.isIncognito &&
              !widget.settings.allowPrivateScreenshots,
        );
        await NativeShieldBridge.instance.requestNotificationPermission();
        if (mounted && widget.settings.biometricLockApp && !_appUnlocked) {
          await _unlockEntireApp();
        }
      });
    }
  }

  void _onPrivacyWindowSettingsChanged() {
    if (!widget.enablePlatformWebView) return;
    unawaited(
      NativeShieldBridge.instance.updatePrivateWindowSecurity(
        blockScreenshots:
            _tabManager.activeTab.isIncognito &&
            !widget.settings.allowPrivateScreenshots,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (widget.enablePlatformWebView) {
        unawaited(_tabManager.captureTabPreview(_tabManager.activeTab));
      }
    }
    if (state == AppLifecycleState.paused) {
      if (widget.settings.biometricLockIncognito) {
        _tabManager.markIncognitoUnlocked(false);
      }
      if (widget.settings.biometricLockApp && _appUnlocked) {
        setState(() => _appUnlocked = false);
      }
    } else if (state == AppLifecycleState.detached) {
      if (widget.settings.clearOnExit) {
        unawaited(widget.settings.clearHistoryOnly());
        if (widget.enablePlatformWebView) {
          unawaited(NativeShieldBridge.instance.clearSiteData(domain: ''));
        }
      } else if (widget.settings.autoShredMode == HeavenAutoShredMode.appExit &&
          widget.enablePlatformWebView) {
        unawaited(NativeShieldBridge.instance.clearSiteData(domain: ''));
      }
    } else if (state == AppLifecycleState.resumed) {
      if (widget.enablePlatformWebView &&
          widget.settings.biometricLockApp &&
          !_appUnlocked) {
        unawaited(_unlockEntireApp());
      }
    }
  }

  Future<void> _unlockEntireApp() async {
    if (_verifyingAppLock) return;
    setState(() => _verifyingAppLock = true);
    final bool ok = await NativeShieldBridge.instance.authenticateBiometric(
      reason: 'Unlock Heaven',
    );
    if (!mounted) return;
    setState(() {
      _verifyingAppLock = false;
      if (ok) {
        _appUnlocked = true;
      }
    });
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final String incoming = routeInformation.uri.toString();
    if (incoming.startsWith('http://') || incoming.startsWith('https://')) {
      if (!widget.settings.openExternalLinksInHeaven) {
        return false;
      }
      await _tabManager.openNewTab(incognito: false, initialInput: incoming);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onPrivacyWindowSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _tabManager.dispose();
    _ownedDownloads?.dispose();
    _ownedInterests?.dispose();
    _ownedNewsService?.dispose();
    _ownedVpn?.dispose();
    super.dispose();
  }

  Widget _buildHomeOrLockGate() {
    if (widget.settings.biometricLockApp && !_appUnlocked) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: AppTheme.electricBlue.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      size: 42,
                      color: AppTheme.electricBlue,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Heaven Locked',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Verify your fingerprint, face, or device PIN to continue browsing privately.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    key: const Key('unlock_app_biometric_button'),
                    onPressed: _verifyingAppLock ? null : _unlockEntireApp,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: Text(
                      _verifyingAppLock ? 'Verifying...' : 'Unlock Browser',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return BrowserScreen(
      settings: widget.settings,
      tabManager: _tabManager,
      searchService: _searchService,
      downloads: _effectiveDownloads,
      newsService: _effectiveNews,
      interests: _effectiveInterests,
      vpn: _effectiveVpn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (BuildContext context, _) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          locale: Locale(widget.settings.language.code),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: widget.settings.themeMode,
          onGenerateInitialRoutes: (String _) => <Route<dynamic>>[
            MaterialPageRoute<void>(builder: (_) => _buildHomeOrLockGate()),
          ],
          onGenerateRoute: (RouteSettings routeSettings) {
            final String? name = routeSettings.name;
            if (name != null &&
                (name.startsWith('http://') || name.startsWith('https://'))) {
              unawaited(
                _tabManager.openNewTab(incognito: false, initialInput: name),
              );
            }
            return MaterialPageRoute<void>(
              builder: (_) => _buildHomeOrLockGate(),
            );
          },
        );
      },
    );
  }
}
