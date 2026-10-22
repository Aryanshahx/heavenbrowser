import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heavenbrowser/app.dart';
import 'package:heavenbrowser/core/constants/app_constants.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/features/browser/engine/browser_engine.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';
import 'package:heavenbrowser/features/shield/heaven_shield.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<BrowserSettingsController> _createTestSettings() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return BrowserSettingsController(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OmniboxParser', () {
    test('upgrades http URLs to https when httpsUpgrade is enabled', () {
      final Uri resolved = OmniboxParser.resolveInput(
        'http://example.com/path',
        searchEngine: SearchEngine.duckDuckGo,
        httpsUpgrade: true,
      );
      expect(resolved.toString(), 'https://example.com/path');
    });

    test('preserves http on localhost and private LAN addresses', () {
      final Uri local = OmniboxParser.resolveInput(
        'localhost:8080/api',
        searchEngine: SearchEngine.duckDuckGo,
        httpsUpgrade: true,
      );
      expect(local.toString(), 'http://localhost:8080/api');
    });

    test('resolves bare domains and encodes search phrases accurately', () {
      final Uri domain = OmniboxParser.resolveInput(
        'github.com/flutter/flutter',
        searchEngine: SearchEngine.duckDuckGo,
        httpsUpgrade: true,
      );
      expect(domain.toString(), 'https://github.com/flutter/flutter');

      final Uri query = OmniboxParser.resolveInput(
        'raspberry pi 5 browser',
        searchEngine: SearchEngine.brave,
        httpsUpgrade: true,
      );
      expect(
        query.toString(),
        'https://search.brave.com/search?q=raspberry+pi+5+browser',
      );
    });
  });

  group('HeavenShield', () {
    test('blocks known tracker domains and subdomains unless trusted', () {
      final Uri tracker = Uri.parse('https://stats.g.doubleclick.net/r/collect');
      expect(
        HeavenShield.shouldBlockUri(
          tracker,
          shieldEnabled: true,
          trustedHosts: const <String>{},
        ),
        isTrue,
      );

      expect(
        HeavenShield.shouldBlockUri(
          tracker,
          shieldEnabled: true,
          trustedHosts: const <String>{'example.com'},
          currentPageHost: 'news.example.com',
        ),
        isFalse,
      );
    });
  });

  group('HeavenBrowserApp UI & Functionalities', () {
    testWidgets('renders Start Page, switches search engine, and navigates', (
      WidgetTester tester,
    ) async {
      final BrowserSettingsController settings = await _createTestSettings();
      final InMemoryBrowserEngine engine =
          InMemoryBrowserEngine(settings: settings);

      await tester.pumpWidget(
        HeavenBrowserApp(settings: settings, engine: engine),
      );

      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text('Heaven Shield Active'), findsOneWidget);

      // Switch search engine chip to Brave Search
      await tester.tap(find.text('Brave Search'));
      await tester.pumpAndSettle();
      expect(settings.searchEngine, SearchEngine.brave);

      // Focus omnibox and search
      await tester.tap(find.text('Search or enter address'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('omnibox_input')),
        'flutter linux',
      );
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      expect(
        engine.state.currentUrl,
        'https://search.brave.com/search?q=flutter+linux',
      );
    });

    testWidgets('blocks tracker URL via Heaven Shield and increments counter', (
      WidgetTester tester,
    ) async {
      final BrowserSettingsController settings = await _createTestSettings();
      final InMemoryBrowserEngine engine =
          InMemoryBrowserEngine(settings: settings);

      await tester.pumpWidget(
        HeavenBrowserApp(settings: settings, engine: engine),
      );
      expect(settings.totalTrackersBlocked, 0);

      await tester.tap(find.text('Search or enter address'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('omnibox_input')),
        'doubleclick.net',
      );
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      expect(settings.totalTrackersBlocked, 1);
      expect(find.text('Protected by Heaven Shield'), findsOneWidget);
    });

    testWidgets('supports Back/Forward navigation and Fire session wipe', (
      WidgetTester tester,
    ) async {
      final BrowserSettingsController settings = await _createTestSettings();
      final InMemoryBrowserEngine engine =
          InMemoryBrowserEngine(settings: settings);

      await tester.pumpWidget(
        HeavenBrowserApp(settings: settings, engine: engine),
      );

      await engine.loadUri(Uri.parse('https://wikipedia.org'));
      await tester.pumpAndSettle();
      await engine.loadUri(Uri.parse('https://github.com'));
      await tester.pumpAndSettle();

      expect(engine.state.currentUrl, 'https://github.com');

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(engine.state.currentUrl, 'https://wikipedia.org');

      await tester.tap(find.byTooltip('Forward'));
      await tester.pumpAndSettle();
      expect(engine.state.currentUrl, 'https://github.com');

      // Trigger Burn Session button
      await tester.tap(find.byTooltip('Burn Session & Clear Data'));
      await tester.pumpAndSettle();
      expect(find.text('Burn Session & Site Data?'), findsOneWidget);

      await tester.tap(find.text('Burn Now'));
      await tester.pumpAndSettle();

      expect(engine.state.hasActivePage, isFalse);
      expect(engine.wipeCount, 1);
      expect(find.text('Heaven Shield Active'), findsOneWidget);
    });

    testWidgets('persists theme mode and omnibox position in SettingsScreen', (
      WidgetTester tester,
    ) async {
      final BrowserSettingsController settings = await _createTestSettings();
      final InMemoryBrowserEngine engine =
          InMemoryBrowserEngine(settings: settings);

      await tester.pumpWidget(
        HeavenBrowserApp(settings: settings, engine: engine),
      );

      await tester.tap(find.byTooltip('Browser Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(settings.themeMode, ThemeMode.dark);

      await tester.tap(find.text('Top'));
      await tester.pumpAndSettle();
      expect(settings.omniboxPosition, OmniboxPosition.top);
    });

    testWidgets('adds custom Quick Launch site and supports Find in Page', (
      WidgetTester tester,
    ) async {
      final BrowserSettingsController settings = await _createTestSettings();
      final InMemoryBrowserEngine engine =
          InMemoryBrowserEngine(settings: settings);

      await tester.pumpWidget(
        HeavenBrowserApp(settings: settings, engine: engine),
      );

      final Finder addSiteBtn = find.text('Add Site');
      await tester.scrollUntilVisible(
        addSiteBtn,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(addSiteBtn);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Dart Dev',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Website URL'),
        'dart.dev',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(
        settings.shortcuts.any((QuickShortcut s) => s.title == 'Dart Dev'),
        isTrue,
      );

      await engine.loadUri(Uri.parse('https://dart.dev'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Find in page...'),
        'dart',
      );
      await tester.pumpAndSettle();
      expect(engine.state.findMatches.total, greaterThan(0));
    });
  });
}
