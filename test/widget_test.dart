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
import 'package:heavenbrowser/features/vpn/vpn_controller.dart';
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
  final String encodedYoutube = base64Url
      .encode(utf8.encode('https://www.youtube.com/watch?v=dQw4w9WgXcQ'))
      .replaceAll('=', '');

  final MockClient mockClient = MockClient((http.Request request) async {
    capturedRequests?.add(request);
    final String host = request.url.host;
    final String path = request.url.path;

    if (host == 'www.bing.com' && path == '/search') {
      final String bingWebHtml =
          '''
      <ol id="b_results">
        <li class="b_algo">
          <h2><a href="https://www.bing.com/ck/a?!&&p=abc&u=a1$encodedYoutube&ntb=1">Flutter Official Video</a></h2>
          <div class="b_caption"><p>Build fast apps on every screen with <strong>Flutter</strong>.</p></div>
        </li>
      </ol>
      ''';
      return http.Response(bingWebHtml, 200);
    }
    if (host == 'www.bing.com' && path == '/images/async') {
      const String bingImagesHtml = '''
      <a class="iusc" m="{&quot;murl&quot;:&quot;https://example.com/full.png&quot;,&quot;turl&quot;:&quot;https://example.com/thumb.png&quot;,&quot;purl&quot;:&quot;https://flutter.dev/showcase&quot;,&quot;t&quot;:&quot;Flutter Showcase UI&quot;}"></a>
      ''';
      return http.Response(bingImagesHtml, 200);
    }
    if (host == 'www.bing.com' && path == '/videos/search') {
      const String bingVideosHtml = '''
      <div class="mc_vtvc" vrhm="{&quot;vt&quot;:&quot;Flutter 60fps Demo&quot;,&quot;murl&quot;:&quot;https://www.youtube.com/watch?v=dQw4w9WgXcQ&quot;,&quot;du&quot;:&quot;04:12&quot;,&quot;thid&quot;:&quot;OVP.flutter123&quot;}"></div>
      ''';
      return http.Response(bingVideosHtml, 200);
    }
    if (host == 'www.bing.com' && path == '/news/infinitescrollajax') {
      const String bingNewsHtml = '''
      <div class="news-card newsitem cardcommon" data-title="Flutter 3.44 Released" data-url="https://news.example.com/flutter" data-author="TechDaily">
        <img src="/th?id=ONUT.flutternews123&amp;pid=News&amp;w=234&amp;h=132" />
        <div class="snippet">Google ships faster Impeller rendering on Android.</div>
        <span aria-label="2 hours ago">2h</span>
      </div>
      ''';
      return http.Response(bingNewsHtml, 200);
    }
    if (host == 'html.duckduckgo.com') {
      const String sampleHtml = '''
      <div class="result">
        <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fdart.dev%2Foverview">Dart Language Overview</a>
        <a class="result__snippet">Client-optimized language for fast apps on any platform.</a>
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
    if (req.url.host == 'www.bing.com') {
      const String bingCards = '''
      <div class="news-card newsitem cardcommon" data-title="SpaceX Starship Orbital Launch Milestone" data-url="https://spacenews.example.com/starship" data-author="SpaceNews">
        <img src="/th?id=ONUT.starshiphd99&amp;w=234&amp;h=132" />
        <span aria-label="1 hour ago">1h</span>
      </div>
      ''';
      return http.Response(bingCards, 200);
    }
    const String rss = '''
    <rss xmlns:media="http://search.yahoo.com/mrss/"><channel>
      <item>
        <title>SpaceX Starship Orbital Launch Milestone - SpaceNews</title>
        <link>https://spacenews.example.com/starship</link>
        <pubDate>Thu, 22 Oct 2026 11:00:00 GMT</pubDate>
        <source url="https://spacenews.example.com">SpaceNews</source>
        <media:thumbnail url="https://ichef.bbci.co.uk/ace/standard/240/cpsprodpb/starship.jpg" />
      </item>
      <item>
        <title>Linux Kernel Rust Drivers Expand on ARM64 - LWN</title>
        <link>https://lwn.example.com/rust-arm64</link>
        <pubDate>Thu, 22 Oct 2026 10:00:00 GMT</pubDate>
        <source url="https://lwn.example.com">LWN</source>
        <media:content url="https://cdn.example.com/linux-arm64-cover.jpg" medium="image" />
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

  group('Blue Theme, Google-Grade Unrestricted Search & Discover Image News', () {
    test('uses Electric Sapphire & Midnight Navy blue palette', () {
      expect(AppTheme.sapphireBlue, const Color(0xFF2563EB));
      expect(AppTheme.electricBlue, const Color(0xFF3B82F6));
      expect(AppTheme.deepNavyBg, const Color(0xFF040B16));
      expect(AppTheme.navySurface, const Color(0xFF0B162C));
      expect(AppTheme.darkTheme.colorScheme.primary, const Color(0xFF60A5FA));
    });

    test(
      'Heaven Search combines Bing adlt=off + DDG kp=-2 unfiltered Web, Images, Videos & News',
      () async {
        const HeavenSearchFilters defaultFilters = HeavenSearchFilters();
        expect(defaultFilters.safe, HeavenSafeFilter.off);
        expect(defaultFilters.region, HeavenRegionFilter.global);
        expect(HeavenSafeFilter.off.ddgCode, '-2');
        expect(HeavenSafeFilter.off.bingParam, 'off');
        expect(HeavenSafeFilter.off.bingCookie, 'OFF');

        final List<http.Request> captured = <http.Request>[];
        final HeavenSearchService service = _createMockSearchService(
          capturedRequests: captured,
        );
        final HeavenSearchResponse res = await service.search('open web video');

        // Merged Bing + DDG unrestricted web results without duplicates
        expect(res.webResults.length, 2);
        expect(
          res.webResults.first.url,
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        );
        expect(res.imageResults, isNotEmpty);
        expect(res.imageResults.first.fullUrl, 'https://example.com/full.png');
        expect(res.videoResults, isNotEmpty);
        expect(res.videoResults.first.metaBadge, '04:12');
        expect(res.newsResults, isNotEmpty);
        expect(res.newsResults.first.thumbnailUrl, contains('w=640&h=360'));

        // Verify Bing requests send ADLT=OFF cookie & adlt=off param
        final Iterable<http.Request> bingWebCalls = captured.where(
          (http.Request r) =>
              r.url.host == 'www.bing.com' && r.url.path == '/search',
        );
        expect(bingWebCalls, isNotEmpty);
        for (final http.Request req in bingWebCalls) {
          expect(req.url.queryParameters['adlt'], 'off');
          expect(req.headers['Cookie'], contains('ADLT=OFF'));
        }

        // Verify DDG requests send kp=-2 & Cookie p=-2
        final Iterable<http.Request> ddgCalls = captured.where(
          (http.Request r) => r.url.host == 'html.duckduckgo.com',
        );
        expect(ddgCalls, isNotEmpty);
        for (final http.Request req in ddgCalls) {
          expect(req.url.queryParameters['kp'], '-2');
          expect(req.headers['Cookie'], contains('p=-2'));
        }
      },
    );

    test(
      'Discover Feed parses HD publisher & Bing cover images and ranks user interests',
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

        final HeavenNewsFeedService news = _createMockNewsService(
          prefs,
          interests,
        );
        final List<PersonalizedNewsItem> feed = await news.fetchFeed(
          NewsCategoryTab.forYou,
        );
        expect(feed, isNotEmpty);
        expect(feed.first.title, contains('SpaceX Starship'));
        // Verify HD cover image extraction & BBC /240/ -> /800/ or Bing 640x360 upgrade!
        expect(feed.first.imageUrl, isNotNull);
        expect(
          feed.first.imageUrl!.contains('/800/') ||
              feed.first.imageUrl!.contains('w=640&h=360'),
          isTrue,
        );
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

  group(
    'Heaven VPN (Option 3: 1-Tap Free WARP + Custom Country WireGuard) & Downloads',
    () {
      const MethodChannel nativeChannel = MethodChannel(
        'com.hypertechlabs.heavenbrowser/native_shield',
      );

      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, null);
      });

      test(
        'VpnController provisions free Cloudflare WARP tunnel, connects, tracks RX/TX & imports custom country .conf',
        () async {
          bool nativeConnected = false;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
                switch (call.method) {
                  case 'provisionFreeWarpConfig':
                    return <String, Object>{
                      'ok': true,
                      'configText':
                          '[Interface]\nPrivateKey = AAAA\nAddress = 172.16.0.2/32\nDNS = 1.1.1.1\n\n[Peer]\nPublicKey = BBBB\nAllowedIPs = 0.0.0.0/0\nEndpoint = 162.159.192.1:2408\n',
                      'clientIpv4': '172.16.0.2',
                      'endpoint': '162.159.192.1:2408',
                    };
                  case 'validateWireGuardConfig':
                    return <String, Object>{
                      'valid': true,
                      'endpoint': '185.159.157.1:51820',
                      'addresses': '10.2.0.2/32',
                    };
                  case 'connectVpn':
                    nativeConnected = true;
                    return <String, Object>{
                      'ok': true,
                      'connected': true,
                      'profileName':
                          (call.arguments
                              as Map<Object?, Object?>)['profileName'] ??
                          'VPN',
                    };
                  case 'disconnectVpn':
                    nativeConnected = false;
                    return <String, Object>{'ok': true, 'connected': false};
                  case 'getVpnStatus':
                    return <String, Object>{
                      'connected': nativeConnected,
                      'rxBytes': 2097152,
                      'txBytes': 524288,
                      'profileName': 'Cloudflare WARP (Instant Free)',
                    };
                  default:
                    return null;
                }
              });

          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final VpnController vpn = VpnController(
            prefs,
            enableNativePolling: false,
            client: MockClient(
              (_) async =>
                  http.Response('ip=104.28.210.44\nloc=SG\nwarp=on\n', 200),
            ),
          );

          // 1-Tap Free Cloudflare WARP Connect
          await vpn.connect();
          await Future<void>.delayed(Duration.zero);
          expect(vpn.isConnected, isTrue);
          expect(vpn.exitIp, '104.28.210.44');
          expect(vpn.exitCountry, 'SG');

          // Custom Country WireGuard .conf import (e.g., Switzerland)
          final String? err = await vpn.addCustomProfile(
            name: 'Proton Free Zurich',
            countryLabel: '🇨🇭 Switzerland',
            configText:
                '[Interface]\nPrivateKey = AAAA\nAddress = 10.2.0.2/32\n[Peer]\nPublicKey = BBBB\nEndpoint = 185.159.157.1:51820\nAllowedIPs = 0.0.0.0/0\n',
          );
          expect(err, isNull);
          expect(vpn.customProfiles.length, 1);
          expect(vpn.selectedProfile.countryLabel, '🇨🇭 Switzerland');

          // Disconnect
          await vpn.disconnect();
          expect(vpn.isConnected, isFalse);
          vpn.dispose();
        },
      );

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
          await downloads.pauseDownload(701);
          expect(downloads.items.first.isPaused, isTrue);
          await downloads.resumeDownload(701);
          expect(downloads.items.first.isRunning, isTrue);
          await downloads.cancelAndRemove(downloads.items.first);
          expect(downloads.items, isEmpty);

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
          expect(engine.isLoading, isFalse);
          expect(engine.errorMessage, isNull);

          engine.dispose();
          downloads.dispose();
        },
      );
    },
  );

  testWidgets(
    'Step 6 UI: Discover image feed without Reset button, Search icon submit without Enter circle, Mic hidden after search, + New Tab in bar, Tap-anywhere dismisses Copy/Edit/Share, Wide Edit Bar & Heaven VPN on narrow 320px screen',
    (WidgetTester tester) async {
      const MethodChannel nativeChannel = MethodChannel(
        'com.hypertechlabs.heavenbrowser/native_shield',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
            switch (call.method) {
              case 'provisionFreeWarpConfig':
                return <String, Object>{
                  'ok': true,
                  'configText':
                      '[Interface]\nPrivateKey = AAAA\nAddress = 172.16.0.2/32\nDNS = 1.1.1.1\n\n[Peer]\nPublicKey = BBBB\nAllowedIPs = 0.0.0.0/0\nEndpoint = 162.159.192.1:2408\n',
                  'clientIpv4': '172.16.0.2',
                  'endpoint': '162.159.192.1:2408',
                };
              case 'connectVpn':
                return <String, Object>{
                  'ok': true,
                  'connected': true,
                  'profileName': 'Heaven Instant Free VPN',
                };
              case 'disconnectVpn':
                return <String, Object>{'ok': true, 'connected': false};
              default:
                return null;
            }
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, null);
      });

      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'hb.downloads.v4': jsonEncode(<Map<String, Object>>[
          <String, Object>{
            'downloadId': 501,
            'fileName': 'heaven_installer_v6.apk',
            'url': 'https://example.com/heaven_installer_v6.apk',
            'mimeType': 'application/vnd.android.package-archive',
            'state': 'running',
            'bytesDownloaded': 2097152,
            'totalBytes': 4194304,
            'speedBps': 524288,
            'localUri': '/storage/emulated/0/Download/heaven_installer_v6.apk',
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
      final VpnController vpn = VpnController(
        prefs,
        enableNativePolling: false,
        client: MockClient(
          (_) async => http.Response('ip=104.28.14.9\nloc=SG\nwarp=on\n', 200),
        ),
      );

      await tester.pumpWidget(
        HeavenBrowserApp(
          settings: settings,
          downloads: downloads,
          interests: interests,
          newsService: newsService,
          vpn: vpn,
          enablePlatformWebView: false,
          searchService: _createMockSearchService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 1. Reset Interests button is REMOVED & Google Discover Feed renders!
      expect(find.text('Reset Interests'), findsNothing);
      expect(find.byTooltip('Reset Interest Profile'), findsNothing);
      expect(find.text('Discover'), findsOneWidget);
      expect(
        find.textContaining('SpaceX Starship Orbital Launch Milestone'),
        findsOneWidget,
      );

      // 2. Circle Enter button is REMOVED from Home Screen Search Bar!
      expect(find.byTooltip('Search Now'), findsNothing);
      expect(find.byKey(const Key('home_search_icon_button')), findsOneWidget);

      // 3. + New Tab button is right in the search bar area and works with zero overflow!
      expect(find.byKey(const Key('bar_new_tab_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('bar_new_tab_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2'), findsOneWidget);

      // 4. Typing in Home Search Bar hides Home Mic, and clicking Search icon submits!
      await tester.enterText(
        find.byKey(const Key('home_search_textfield')),
        'flutter',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('home_search_icon_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 5. After searching, Mic button is NOT shown anywhere on screen!
      expect(find.text('Flutter Official Video'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);

      // Open a web result so an active URL link is in the top search bar
      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flutter 3.44 Released'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('news.example.com'), findsOneWidget);
      // Mic button is STILL hidden on active websites!
      expect(find.byIcon(Icons.mic_rounded), findsNothing);

      // 6. Tap active link -> Copy, Edit, Share appear; tap anywhere outside -> disappears!
      await tester.tap(find.byKey(const Key('omnibox_display_pill')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);

      // Tap anywhere outside (e.g. middle of page) -> Copy, Edit, Share disappear!
      await tester.tapAt(const Offset(160, 420));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Share'), findsNothing);

      // 7. Tap active link again -> Tap Edit -> Copy/Edit/Share hides & Search Bar expands WIDE!
      await tester.tap(find.byKey(const Key('omnibox_display_pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Copy'), findsNothing);

      final Size wideSize = tester.getSize(
        find.byKey(const Key('wide_editing_omnibox_container')),
      );
      // On a 320px screen with 8px horizontal padding on each side, width is 304px!
      expect(wideSize.width, greaterThanOrEqualTo(300));
      final TextField editedField = tester.widget<TextField>(
        find.byKey(const Key('top_omnibox_textfield')),
      );
      expect(editedField.controller?.text, 'https://news.example.com/flutter');

      // Submit a new URL via keyboard Enter
      await tester.enterText(
        find.byKey(const Key('top_omnibox_textfield')),
        'https://flutter.dev',
      );
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('flutter.dev'), findsOneWidget);

      // 8. Open Heaven VPN Screen from Browser Menu -> 1-Tap Connect works cleanly on 320px!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      expect(find.text('VPN'), findsOneWidget);
      await tester.tap(find.text('VPN'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Heaven VPN'), findsOneWidget);
      expect(find.byKey(const Key('vpn_power_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('vpn_power_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(vpn.isConnected, isTrue);
      expect(find.text('VPN Connected'), findsOneWidget);

      final TabManagerController tm = TabManagerController(
        settings: settings,
        enablePlatformWebView: false,
      );
      tm.activeTab.previewBytes = _kSamplePreviewPng;
      expect(tm.activeTab.previewBytes, isNotEmpty);
      tm.dispose();

      vpn.dispose();
      newsService.dispose();
      downloads.dispose();
    },
  );
}
