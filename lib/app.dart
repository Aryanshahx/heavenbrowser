import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:heavenbrowser/core/constants/app_constants.dart';
import 'package:heavenbrowser/core/theme/app_theme.dart';
import 'package:heavenbrowser/features/browser/engine/browser_engine.dart';
import 'package:heavenbrowser/features/browser/presentation/browser_screen.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';

class HeavenBrowserApp extends StatefulWidget {
  const HeavenBrowserApp({
    super.key,
    required this.settings,
    this.engine,
  });

  final BrowserSettingsController settings;
  final BrowserEngine? engine;

  @override
  State<HeavenBrowserApp> createState() => _HeavenBrowserAppState();
}

class _HeavenBrowserAppState extends State<HeavenBrowserApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final BrowserEngine _engine;
  late final bool _ownsEngine;
  String? _initialExternalUrl;

  @override
  void initState() {
    super.initState();
    _ownsEngine = widget.engine == null;
    _engine = widget.engine ??
        createDefaultBrowserEngine(
          settings: widget.settings,
          navigatorKey: _navigatorKey,
        );

    final String defaultRoute = PlatformDispatcher.instance.defaultRouteName;
    if (defaultRoute.startsWith('http://') ||
        defaultRoute.startsWith('https://')) {
      _initialExternalUrl = defaultRoute;
    }
  }

  @override
  void dispose() {
    if (_ownsEngine) {
      _engine.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (BuildContext context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: widget.settings.themeMode,
          home: BrowserScreen(
            settings: widget.settings,
            engine: _engine,
            initialExternalUrl: _initialExternalUrl,
          ),
        );
      },
    );
  }
}
