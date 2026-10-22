import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/features/browser/engine/browser_engine.dart';
import 'package:heavenbrowser/features/downloads/downloads_controller.dart';
import 'package:heavenbrowser/features/search/heaven_search_service.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';
import 'package:heavenbrowser/features/shield/heaven_shield.dart';
import 'package:heavenbrowser/features/tabs/tab_manager.dart';
import 'package:heavenbrowser/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

HeavenSearchService _createMockSearchService() {
  final MockClient mockClient = MockClient((http.Request request) async {
    final String host = request.url.host;
    if (host == 'html.duckduckgo.com') {
      const String sampleHtml = '''
      <div class="result">
        <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ">Flutter Official Video</a>
        <a class="result__snippet">Build fast apps on every screen with <b>Flutter</b>.</a>
      </div>
      <div class="result">
        <a class="result__a" href="//duckduckgo.com/y.js?ad_domain=spam.example">Sponsored Ad</a>
        <a class="result__snippet">Should be skipped</a>
      </div>
      ''';
      return http.Response(sampleHtml, 200);
    }
    if (host == 'commons.wikimedia.org') {
      return http.Response(
        jsonEncode(<String, Object>{
          'query': <String, Object>{
            'pages': <String, Object>{
              '1': <String, Object>{
                'title': 'File:Flutter Logo.png',
                'imageinfo': <Map<String, Object>>[
                  <String, Object>{
                    'thumburl': 'https://example.com/thumb.png',
                    'url': 'https://example.com/full.png',
                    'descriptionurl':
                        'https://commons.wikimedia.org/wiki/File:Flutter',
                  },
                ],
              },
            },
          },
        }),
        200,
      );
    }
    if (host == 'news.google.com') {
      const String sampleRss = '''
      <rss><channel>
        <item>
          <title>Flutter 3.44 Released - TechDaily</title>
          <link>https://news.example.com/flutter</link>
          <pubDate>Thu, 22 Oct 2026 09:00:00 GMT</pubDate>
          <source url="https://news.example.com">TechDaily</source>
        </item>
      </channel></rss>
      ''';
      return http.Response(sampleRss, 200);
    }
    if (host == 'api.duckduckgo.com') {
      return http.Response(
        jsonEncode(<String, Object>{
          'Heading': 'Flutter (software)',
          'AbstractText':
              'Flutter is an open-source UI software development kit created by Google.',
          'AbstractURL': 'https://en.wikipedia.org/wiki/Flutter_(software)',
          'AbstractSource': 'Wikipedia',
        }),
        200,
      );
    }
    if (host == 'en.wikipedia.org') {
      return http.Response(
        jsonEncode(<String, Object>{
          'query': <String, Object>{
            'search': <Map<String, Object>>[
              <String, Object>{
                'title': 'Flutter (software)',
                'snippet': 'Open-source UI SDK',
              },
            ],
          },
        }),
        200,
      );
    }
    return http.Response('{}', 200);
  });

  return HeavenSearchService(client: mockClient);
}

void main() {
  group('Defaults, Desktop Rewrite & Clean Home State', () {
    test(
      'defaults to Top Dock Bar, Heaven Search, and zero starter sites',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final BrowserSettingsController settings = BrowserSettingsController(
          prefs,
        );

        expect(settings.bottomOmnibox, isFalse);
        expect(settings.searchEngine, SearchEngine.heaven);
        expect(settings.quickLaunchSites, isEmpty);

        // Once user visits real sites, they populate automatically by usage
        await settings.recordPageVisit(
          url: 'https://proton.me/mail',
          title: 'Proton Mail',
        );
        await settings.recordPageVisit(
          url: 'https://proton.me/drive',
          title: 'Proton Drive',
        );
        expect(settings.quickLaunchSites.length, 1);
        expect(settings.quickLaunchSites.first.domain, 'proton.me');
        expect(settings.quickLaunchSites.first.visitCount, 2);
      },
    );

    test('Desktop Mode rewrites mobile subdomains to desktop hosts', () {
      expect(
        BrowserEngine.rewriteMobileToDesktopUri(
          Uri.parse('https://m.youtube.com/watch?v=123'),
        ).toString(),
        'https://www.youtube.com/watch?v=123',
      );
      expect(
        BrowserEngine.rewriteMobileToDesktopUri(
          Uri.parse('https://en.m.wikipedia.org/wiki/India'),
        ).toString(),
        'https://en.wikipedia.org/wiki/India',
      );
    });
  });

  group('Heaven Search Multi-Verticals, Filters & Shield', () {
    test(
      'returns Web, Images, Videos (with YT thumb), News RSS & Wiki',
      () async {
        final HeavenSearchService service = _createMockSearchService();
        final HeavenSearchResponse res = await service.search(
          'flutter',
          filters: const HeavenSearchFilters(
            time: HeavenTimeFilter.week,
            region: HeavenRegionFilter.india,
            safe: HeavenSafeFilter.strict,
          ),
        );

        expect(res.webResults.length, 1);
        expect(res.imageResults.length, 1);
        expect(res.videoResults.first.thumbnailUrl, contains('dQw4w9WgXcQ'));
        expect(res.newsResults.first.metaBadge, 'TechDaily');
        expect(res.wikiResults.first.sourceLabel, 'en.wikipedia.org');
      },
    );

    test('blocks ad domains and strips tracking parameters', () {
      expect(
        HeavenShield.shouldBlockUri(
          Uri.parse(
            'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js',
          ),
        ),
        isTrue,
      );
      final ({Uri uri, int removedCount}) cleaned =
          HeavenShield.stripTrackingParameters(
            Uri.parse('https://example.com/p?id=7&utm_source=ads&fbclid=1'),
          );
      expect(cleaned.removedCount, 2);
      expect(cleaned.uri.toString(), 'https://example.com/p?id=7');
    });
  });

  group('Downloads Controller & Multi-Tab Isolation', () {
    test('enqueues downloads and isolates Incognito tabs', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final DownloadsController downloads = DownloadsController(
        prefs,
        enableNativePolling: false,
      );

      final bool started = await downloads.startUrlDownload(
        url: 'https://example.com/manual.pdf',
        suggestedFileName: 'manual.pdf',
      );
      expect(started, isTrue);
      expect(downloads.items.length, 1);
      expect(downloads.items.first.fileName, 'manual.pdf');

      final BrowserSettingsController settings = BrowserSettingsController(
        prefs,
      );
      final TabManagerController tabManager = TabManagerController(
        settings: settings,
        enablePlatformWebView: false,
      );
      await tabManager.openNewTab(
        incognito: true,
        initialInput: 'https://private.example.org',
      );
      expect(settings.history, isEmpty);
      expect(settings.quickLaunchSites, isEmpty);

      tabManager.dispose();
      downloads.dispose();
    });
  });

  testWidgets(
    'Narrow 320px screen renders Top Bar, Home/Forward/Mic, Search, Tabs, Library & Downloads cleanly with zero overflow',
    (WidgetTester tester) async {
      // Simulate narrow 320x640 phone screen to verify zero layout cut-off
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'hb.downloads.v4': jsonEncode(<Map<String, Object>>[
          <String, Object>{
            'downloadId': 401,
            'fileName': 'heaven_browser_release_notes_2026.pdf',
            'url': 'https://example.com/heaven_browser_release_notes_2026.pdf',
            'mimeType': 'application/pdf',
            'state': 'completed',
            'bytesDownloaded': 524288,
            'totalBytes': 524288,
            'localUri': 'file:///storage/emulated/0/Download/heaven.pdf',
            'createdAtMs': 1792660000000,
          },
        ]),
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final BrowserSettingsController settings = BrowserSettingsController(
        prefs,
      );
      final DownloadsController downloads = DownloadsController(
        prefs,
        enableNativePolling: false,
      );

      await tester.pumpWidget(
        HeavenBrowserApp(
          settings: settings,
          downloads: downloads,
          enablePlatformWebView: false,
          searchService: _createMockSearchService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Clean Home Screen: no Bookmarks/History/+ Incognito/Smart Quick Launch clutter
      expect(find.text('Heaven'), findsWidgets);
      expect(find.text('Smart Quick Launch'), findsNothing);
      expect(find.text('+ Incognito'), findsNothing);

      // Verify Home, Forward, and Voice Search Mic buttons in Top Dock Bar
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.byTooltip('Forward'), findsWidgets);
      expect(find.byTooltip('Voice Search'), findsWidgets);

      // Run a Heaven Search query and switch tabs (Images / News)
      await tester.tap(find.text('Search or type web address'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, 'flutter');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Flutter Official Video'), findsOneWidget);
      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Flutter 3.44 Released'), findsOneWidget);

      // Open result URL -> Back via menu -> Forward via Top Dock Forward button!
      await tester.tap(find.text('Flutter 3.44 Released'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('news.example.com'), findsOneWidget);

      // Bookmark & Download current URL via real Browser Menu buttons!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Bookmark Page'));
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('All'), findsOneWidget);

      await tester.tap(find.byTooltip('Forward').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('news.example.com'), findsOneWidget);

      // Tap Home button in Top Bar -> returns straight to clean Home Screen
      await tester.tap(find.byTooltip('Home'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Search or type web address'), findsOneWidget);

      // Open Full-Screen Tabs Screen -> verify zero overflow & open Incognito tab
      await tester.tap(find.byTooltip('Switch Tabs'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Tabs (1)'), findsOneWidget);
      await tester.tap(find.text('Incognito (0)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('New Incognito'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Heaven Incognito'), findsOneWidget);

      // Open Menu -> Open Bookmarks/History Library Screen -> verify zero overflow
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Library'), findsOneWidget);
      expect(settings.bookmarks.length, 1);
      await tester.tap(find.textContaining('History'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Open Menu -> Open Downloads Screen -> verify populated download card has zero overflow
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('Downloads'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(downloads.items.length, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Open Menu -> Open Settings Screen -> verify zero overflow
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Set as Default Browser'), findsOneWidget);

      downloads.dispose();
    },
  );
}
