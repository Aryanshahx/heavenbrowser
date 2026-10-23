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
import 'features/extensions/extensions_controller.dart';
import 'features/news/interest_news_service.dart';
import 'features/search/heaven_search_service.dart';
import 'features/settings/browser_settings.dart';
import 'features/tabs/tab_manager.dart';
import 'features/vpn/vpn_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final BrowserSettingsController settings = BrowserSettingsController(prefs);
  final DownloadsController downloads = DownloadsController(prefs);
  final ExtensionsController extensions = ExtensionsController(prefs);
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
      extensions: extensions,
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
    this.extensions,
    this.interests,
    this.newsService,
    this.vpn,
    this.enablePlatformWebView = true,
    this.searchService,
  });

  final BrowserSettingsController settings;
  final DownloadsController? downloads;
  final ExtensionsController? extensions;
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
  ExtensionsController? _ownedExtensions;
  InterestProfileController? _ownedInterests;
  HeavenNewsFeedService? _ownedNewsService;
  VpnController? _ownedVpn;

  DownloadsController get _effectiveDownloads =>
      widget.downloads ?? _ownedDownloads!;
  ExtensionsController get _effectiveExtensions =>
      widget.extensions ?? _ownedExtensions!;
  InterestProfileController get _effectiveInterests =>
      widget.interests ?? _ownedInterests!;
  HeavenNewsFeedService get _effectiveNews =>
      widget.newsService ?? _ownedNewsService!;
  VpnController get _effectiveVpn => widget.vpn ?? _ownedVpn!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.extensions == null) {
      _ownedExtensions = ExtensionsController(widget.settings.prefs);
    }
    _tabManager = TabManagerController(
      settings: widget.settings,
      extensions: _effectiveExtensions,
      enablePlatformWebView: widget.enablePlatformWebView,
    );
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
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final String incoming = routeInformation.uri.toString();
    if (incoming.startsWith('http://') || incoming.startsWith('https://')) {
      await _tabManager.openNewTab(incognito: false, initialInput: incoming);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabManager.dispose();
    _ownedDownloads?.dispose();
    _ownedExtensions?.dispose();
    _ownedInterests?.dispose();
    _ownedNewsService?.dispose();
    _ownedVpn?.dispose();
    super.dispose();
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
            MaterialPageRoute<void>(
              builder: (_) => BrowserScreen(
                settings: widget.settings,
                tabManager: _tabManager,
                searchService: _searchService,
                downloads: _effectiveDownloads,
                extensions: _effectiveExtensions,
                newsService: _effectiveNews,
                interests: _effectiveInterests,
                vpn: _effectiveVpn,
              ),
            ),
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
              builder: (_) => BrowserScreen(
                settings: widget.settings,
                tabManager: _tabManager,
                searchService: _searchService,
                downloads: _effectiveDownloads,
                extensions: _effectiveExtensions,
                newsService: _effectiveNews,
                interests: _effectiveInterests,
                vpn: _effectiveVpn,
              ),
            );
          },
        );
      },
    );
  }
}
