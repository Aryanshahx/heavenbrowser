import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/browser/presentation/browser_screen.dart';
import 'features/downloads/downloads_controller.dart';
import 'features/search/heaven_search_service.dart';
import 'features/settings/browser_settings.dart';
import 'features/tabs/tab_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final BrowserSettingsController settings = BrowserSettingsController(prefs);
  final DownloadsController downloads = DownloadsController(prefs);

  runApp(HeavenBrowserApp(settings: settings, downloads: downloads));
}

class HeavenBrowserApp extends StatefulWidget {
  const HeavenBrowserApp({
    super.key,
    required this.settings,
    this.downloads,
    this.enablePlatformWebView = true,
    this.searchService,
  });

  final BrowserSettingsController settings;
  final DownloadsController? downloads;
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

  DownloadsController get _effectiveDownloads =>
      widget.downloads ?? _ownedDownloads!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabManager = TabManagerController(
      settings: widget.settings,
      enablePlatformWebView: widget.enablePlatformWebView,
    );
    _searchService = widget.searchService ?? HeavenSearchService();

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.downloads == null && _ownedDownloads == null) {
      return FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder:
            (BuildContext context, AsyncSnapshot<SharedPreferences> snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }
              _ownedDownloads ??= DownloadsController(
                snapshot.data!,
                enableNativePolling: widget.enablePlatformWebView,
              );
              return _buildMaterialApp();
            },
      );
    }
    return _buildMaterialApp();
  }

  Widget _buildMaterialApp() {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (BuildContext context, _) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
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
              ),
            );
          },
        );
      },
    );
  }
}
