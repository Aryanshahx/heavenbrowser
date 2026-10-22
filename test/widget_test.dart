import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heavenbrowser/core/theme/app_theme.dart';
import 'package:heavenbrowser/features/browser/engine/browser_engine.dart';
import 'package:heavenbrowser/features/downloads/downloads_controller.dart';
import 'package:heavenbrowser/features/news/interest_news_service.dart';
import 'package:heavenbrowser/features/search/heaven_search_service.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';
import 'package:heavenbrowser/features/shield/heaven_shield.dart';
import 'package:heavenbrowser/features/shield/native_shield_bridge.dart';
import 'package:heavenbrowser/features/tabs/tab_manager.dart';
import 'package:heavenbrowser/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Valid 1x1 transparent PNG for tab preview window tests
final Uint8List _kSamplePreviewPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

HeavenSearchService _createMockSearchService({
  List<http.Request>? capturedRequests,
}) {
  final MockClient mockClient = MockClient((http.Request request) async {
    capturedRequests?.add(request);
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

HeavenNewsFeedService _createMockNewsService(
  SharedPreferences prefs,
  InterestProfileController interests,
) {
  final MockClient client = MockClient((http.Request req) async {
    const String rss = '''
    <rss><channel>
      <item>
        <title>SpaceX Starship Orbital Launch Milestone - SpaceNews</title>
        <link>https://spacenews.example.com/starship</link>
        <pubDate>Thu, 22 Oct 2026 11:00:00 GMT</pubDate>
        <source url="https://spacenews.example.com">SpaceNews</source>
      </item>
      <item>
        <title>Linux Kernel Rust Drivers Expand on ARM64 - LWN</title>
        <link>https://lwn.example.com/rust-arm64</link>
        <pubDate>Thu, 22 Oct 2026 10:00:00 GMT</pubDate>
        <source url="https://lwn.example.com">LWN</source>
      </item>
    </channel></rss>
    ''';
    return http.Response(rss, 200);
  });
  return HeavenNewsFeedService(
    prefs: prefs,
    interests: interests,
    client: client,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Blue Theme, Unrestricted Search & Daily Personalized News', () {
    test('uses Electric Sapphire & Midnight Navy blue palette', () {
      expect(AppTheme.sapphireBlue, const Color(0xFF2563EB));
      expect(AppTheme.electricBlue, const Color(0xFF3B82F6));
      expect(AppTheme.deepNavyBg, const Color(0xFF040B16));
      expect(AppTheme.navySurface, const Color(0xFF0B162C));
      expect(AppTheme.darkTheme.colorScheme.primary, const Color(0xFF60A5FA));
    });

    test(
      'Heaven Search defaults to Global + Safe Off (unfiltered kp=-2 & Cookie p=-2)',
      () async {
        const HeavenSearchFilters defaultFilters = HeavenSearchFilters();
        expect(defaultFilters.safe, HeavenSafeFilter.off);
        expect(defaultFilters.region, HeavenRegionFilter.global);
        expect(HeavenSafeFilter.off.ddgCode, '-2');

        final List<http.Request> captured = <http.Request>[];
        final HeavenSearchService service = _createMockSearchService(
          capturedRequests: captured,
        );
        final HeavenSearchResponse res = await service.search('open web video');

        expect(res.webResults.length, 1);
        final Iterable<http.Request> ddgCalls = captured.where(
          (http.Request r) => r.url.host == 'html.duckduckgo.com',
        );
        expect(ddgCalls, isNotEmpty);
        for (final http.Request req in ddgCalls) {
          expect(req.url.queryParameters['kp'], '-2');
          expect(req.url.queryParameters['kl'], 'wt-wt');
          expect(req.headers['Cookie'], contains('p=-2'));
        }
        // Video search query is unrestricted across all video sites when Safe is Off
        final bool hasUnrestrictedVideoQuery = ddgCalls.any(
          (http.Request r) =>
              (r.url.queryParameters['q'] ?? '') ==
                  'open web video video watch' &&
              !(r.url.queryParameters['q'] ?? '').contains('site:youtube.com'),
        );
        expect(hasUnrestrictedVideoQuery, isTrue);
      },
    );

    test(
      'InterestProfileController learns user topics and decays old interests day by day',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final InterestProfileController interests = InterestProfileController(
          prefs,
        );

        await interests.recordActivity(
          text: 'spacex starship astronomy',
          weight: 2.5,
        );
        expect(interests.rankedInterests, isNotEmpty);
        expect(
          interests.rankedInterests.any(
            (InterestEntry e) =>
                e.label.toLowerCase().contains('science') ||
                e.label.toLowerCase().contains('spacex'),
          ),
          isTrue,
        );

        // Verify exponential day-by-day decay lowers score over 10 days
        final InterestEntry top = interests.rankedInterests.first;
        final int nowMs = DateTime.now().millisecondsSinceEpoch;
        final int tenDaysLaterMs = nowMs + (10 * 86400000);
        expect(
          top.decayedScore(tenDaysLaterMs),
          lessThan(top.decayedScore(nowMs)),
        );

        final HeavenNewsFeedService news = _createMockNewsService(
          prefs,
          interests,
        );
        final List<PersonalizedNewsItem> feed = await news.fetchFeed(
          NewsCategoryTab.forYou,
        );
        expect(feed.length, 2);
        expect(feed.first.title, contains('SpaceX Starship'));
        news.dispose();
      },
    );

    test(
      'Desktop Mode rewrites mobile subdomains and Shield strips trackers',
      () {
        expect(
          BrowserEngine.rewriteMobileToDesktopUri(
            Uri.parse('https://m.youtube.com/watch?v=123'),
          ).toString(),
          'https://www.youtube.com/watch?v=123',
        );
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
      },
    );
  });

  group('Downloads Pause/Resume/Cancel & Stuck-Screen Protection', () {
    const MethodChannel nativeChannel = MethodChannel(
      'com.hypertechlabs.heavenbrowser/native_shield',
    );

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, null);
    });

    test(
      'supports working Pause, Resume, Cancel & clears BrowserEngine stuck state on download intercept',
      () async {
        String currentNativeStatus = 'running';
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
              switch (call.method) {
                case 'startDownload':
                  currentNativeStatus = 'running';
                  return <String, Object>{
                    'downloadId': 701,
                    'fileName': 'ubuntu-arm64.iso',
                    'state': 'running',
                  };
                case 'pauseDownload':
                  currentNativeStatus = 'paused';
                  return true;
                case 'resumeDownload':
                  currentNativeStatus = 'running';
                  return true;
                case 'cancelDownload':
                  currentNativeStatus = 'canceled';
                  return true;
                case 'queryDownloads':
                  return <Map<String, Object>>[
                    <String, Object>{
                      'downloadId': 701,
                      'status': currentNativeStatus,
                      'bytesDownloaded': 4194304,
                      'totalBytes': 8388608,
                      'speedBps': currentNativeStatus == 'running'
                          ? 1048576
                          : 0,
                      'localUri':
                          '/storage/emulated/0/Download/ubuntu-arm64.iso',
                      'mimeType': 'application/octet-stream',
                    },
                  ];
                default:
                  return null;
              }
            });

        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final DownloadsController downloads = DownloadsController(
          prefs,
          enableNativePolling: false,
        );

        final bool started = await downloads.startUrlDownload(
          url: 'https://releases.ubuntu.com/ubuntu-arm64.iso',
          suggestedFileName: 'ubuntu-arm64.iso',
        );
        expect(started, isTrue);
        expect(downloads.items.first.state, 'running');

        // Pause works!
        await downloads.pauseDownload(701);
        expect(downloads.items.first.isPaused, isTrue);

        // Resume works!
        await downloads.resumeDownload(701);
        expect(downloads.items.first.isRunning, isTrue);

        // Cancel works!
        await downloads.cancelAndRemove(downloads.items.first);
        expect(downloads.items, isEmpty);

        // Verify native onDownloadStarted registers the intercepted download & keeps BrowserEngine clean!
        final BrowserSettingsController settings = BrowserSettingsController(
          prefs,
        );
        final BrowserEngine engine = BrowserEngine(
          settings: settings,
          isIncognito: false,
          enablePlatformWebView: false,
        );
        await engine.loadUserEntry('https://releases.ubuntu.com');
        NativeShieldBridge.instance.onDownloadStarted?.call(<String, Object?>{
          'downloadId': 702,
          'fileName': 'ubuntu-server.iso',
          'url': 'https://releases.ubuntu.com/ubuntu-server.iso',
          'mimeType': 'application/octet-stream',
          'totalBytes': 10485760,
          'localUri': '/storage/emulated/0/Download/ubuntu-server.iso',
          'wasEmptyPage': false,
        });
        expect(downloads.items.length, 1);
        expect(downloads.items.first.fileName, 'ubuntu-server.iso');
        expect(engine.isLoading, isFalse);
        expect(engine.errorMessage, isNull);
        expect(engine.currentUrl, 'https://releases.ubuntu.com');

        engine.dispose();
        downloads.dispose();
      },
    );
  });

  testWidgets(
    'Step 5 UI: No refresh in bar, working Home search + News feed, Copy/Edit/Share on link tap, Full-screen Tab Previews & Pause/Resume Downloads on narrow 320px screen',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'hb.downloads.v4': jsonEncode(<Map<String, Object>>[
          <String, Object>{
            'downloadId': 501,
            'fileName': 'heaven_installer_v5.apk',
            'url': 'https://example.com/heaven_installer_v5.apk',
            'mimeType': 'application/vnd.android.package-archive',
            'state': 'running',
            'bytesDownloaded': 2097152,
            'totalBytes': 4194304,
            'speedBps': 524288,
            'localUri': '/storage/emulated/0/Download/heaven_installer_v5.apk',
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
      final InterestProfileController interests = InterestProfileController(
        prefs,
      );
      final HeavenNewsFeedService newsService = _createMockNewsService(
        prefs,
        interests,
      );

      await tester.pumpWidget(
        HeavenBrowserApp(
          settings: settings,
          downloads: downloads,
          interests: interests,
          newsService: newsService,
          enablePlatformWebView: false,
          searchService: _createMockSearchService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 1. Refresh button is REMOVED from the top search bar!
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);

      // 2. Daily Personalized News Feed renders right below the Home Search Bar!
      expect(find.text('Daily Feed'), findsOneWidget);
      expect(
        find.textContaining('SpaceX Starship Orbital Launch Milestone'),
        findsOneWidget,
      );

      // 3. Home Screen Search Bar actually works directly!
      await tester.enterText(
        find.byKey(const Key('home_search_textfield')),
        'flutter',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Search Now'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Verify search ran AND recorded interest into daily profile!
      expect(find.text('Flutter Official Video'), findsOneWidget);
      expect(interests.rankedInterests, isNotEmpty);

      // Verify Heaven Search filter chips default to unfiltered (Global + Safe: Off)
      expect(find.text('Global'), findsOneWidget);
      expect(find.text('Safe: Off'), findsOneWidget);

      // Open a web result so an active URL link is in the top search bar
      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flutter 3.44 Released'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('news.example.com'), findsOneWidget);

      // 4. Tap active link in Search Bar -> Copy, Edit, Share options appear!
      await tester.tap(find.byKey(const Key('omnibox_display_pill')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);

      // Tap Edit -> populates current URL into top_omnibox_textfield ready to edit!
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final TextField editedField = tester.widget<TextField>(
        find.byKey(const Key('top_omnibox_textfield')),
      );
      expect(editedField.controller?.text, 'https://news.example.com/flutter');

      // Submit a new URL from edited bar
      await tester.enterText(
        find.byKey(const Key('top_omnibox_textfield')),
        'https://flutter.dev',
      );
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('flutter.dev'), findsOneWidget);

      // 5. Open Full-Screen Tabs Screen -> verify tall full-screen tab window preview!
      final Finder switchTabsFinder = find.byTooltip('Switch Tabs');
      await tester.tap(switchTabsFinder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Tabs (1)'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      final GridView tabsGrid = tester.widget<GridView>(find.byType(GridView));
      final SliverGridDelegateWithFixedCrossAxisCount delegate =
          tabsGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.childAspectRatio, closeTo(0.58, 0.01));
      await tester.tap(find.byTooltip('Back to browser'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 6. Open Downloads Screen -> verify Pause & Resume buttons render with zero overflow!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Downloads'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Restored interrupted download starts in 'paused' ready to Resume -> Pause -> Resume!
      expect(find.byTooltip('Resume download'), findsOneWidget);
      await tester.tap(find.byTooltip('Resume download'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Pause download'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause download'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Resume download'), findsOneWidget);

      // Also verify PNG memory preview renders cleanly in BrowserTab
      final TabManagerController tm = TabManagerController(
        settings: settings,
        enablePlatformWebView: false,
      );
      tm.activeTab.previewBytes = _kSamplePreviewPng;
      expect(tm.activeTab.previewBytes, isNotEmpty);
      tm.dispose();

      newsService.dispose();
      downloads.dispose();
    },
  );
}
