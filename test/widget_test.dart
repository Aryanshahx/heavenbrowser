import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heavenbrowser/core/theme/app_theme.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
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

    if (host == 'suggestqueries.google.com') {
      return http.Response(
        jsonEncode(<Object>[
          'flutter',
          <String>['flutter sdk', 'flutter webview', 'flutter dart 3'],
        ]),
        200,
      );
    }
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
      const String bingRss = '''
      <rss xmlns:News="http://www.bing.com:80/schema/news"><channel>
        <item>
          <title>SpaceX Starship&#039;s Orbital Launch Milestone</title>
          <link>http://www.bing.com/news/apiclick.aspx?ref=FexRss&amp;url=https%3a%2f%2fspacenews.example.com%2fstarship</link>
          <pubDate>Thu, 22 Oct 2026 11:30:00 GMT</pubDate>
          <News:Source>SpaceNews</News:Source>
          <News:Image>http://www.bing.com/th?id=OVFT.starshiphd99&amp;pid=News</News:Image>
        </item>
      </channel></rss>
      ''';
      return http.Response(bingRss, 200);
    }
    const String rss = '''
    <rss xmlns:media="http://search.yahoo.com/mrss/"><channel>
      <item>
        <title>Text Only Item Without Cover Photo Should Be Filtered Out</title>
        <link>https://textonly.example.com/no-photo</link>
        <pubDate>Thu, 22 Oct 2026 11:15:00 GMT</pubDate>
      </item>
      <item>
        <title>Linux Kernel Rust Drivers Expand on ARM64 - LWN</title>
        <link>https://lwn.example.com/rust-arm64</link>
        <pubDate>Thu, 22 Oct 2026 10:00:00 GMT</pubDate>
        <source url="https://lwn.example.com">LWN</source>
        <media:content url="https://ichef.bbci.co.uk/ace/standard/240/cpsprodpb/linux-arm64.jpg" medium="image" />
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

  group(
    'Step 7: Google-Powered Heaven Search, For You Cover Images & Foreign VPN',
    () {
      test('uses Electric Sapphire & Midnight Navy blue palette', () {
        expect(AppTheme.sapphireBlue, const Color(0xFF2563EB));
        expect(AppTheme.electricBlue, const Color(0xFF3B82F6));
        expect(AppTheme.deepNavyBg, const Color(0xFF040B16));
        expect(AppTheme.navySurface, const Color(0xFF0B162C));
        expect(AppTheme.darkTheme.colorScheme.primary, const Color(0xFF60A5FA));
      });

      test(
        'Heaven Search optimizes via Google Search Engine URLs, Google Autocomplete & Shield ad/redirect stripping',
        () async {
          final Uri googleUri = OmniboxParser.buildGoogleEngineUri(
            'raspberry pi 5 ubuntu',
          );
          expect(googleUri.host, 'www.google.com');
          expect(googleUri.path, '/search');
          expect(googleUri.queryParameters['q'], 'raspberry pi 5 ubuntu');
          expect(googleUri.queryParameters['safe'], 'off');
          expect(googleUri.queryParameters['pws'], '0');

          expect(
            OmniboxParser.extractGoogleSearchQuery(googleUri.toString()),
            'raspberry pi 5 ubuntu',
          );
          expect(
            OmniboxParser.formatDisplayUrl(googleUri.toString()),
            'Google • raspberry pi 5 ubuntu',
          );

          final Uri? unwrapped = OmniboxParser.unwrapGoogleRedirectUri(
            Uri.parse(
              'https://www.google.com/url?q=https%3A%2F%2Fflutter.dev%2Fdocs&sa=U',
            ),
          );
          expect(unwrapped?.toString(), 'https://flutter.dev/docs');

          final String shieldJs = HeavenShield.buildProtectionScript(
            shieldEnabled: true,
            sendDntAndGpc: true,
          );
          expect(shieldJs, contains('#tads'));
          expect(shieldJs, contains('#bottomads'));
          expect(shieldJs, isNot(contains('[data-google-query-id]')));
          expect(shieldJs, contains("href.startsWith('/url?')"));

          final List<http.Request> captured = <http.Request>[];
          final HeavenSearchService service = _createMockSearchService(
            capturedRequests: captured,
          );
          final List<String> suggestions = await service.fetchSuggestions(
            'flut',
          );
          expect(suggestions, contains('flutter sdk'));
          expect(
            captured.any(
              (http.Request r) => r.url.host == 'suggestqueries.google.com',
            ),
            isTrue,
          );

          final HeavenSearchResponse res = await service.search(
            'open web video',
          );
          expect(res.webResults.length, 2);
          expect(res.imageResults, isNotEmpty);
          expect(res.videoResults, isNotEmpty);
        },
      );

      test(
        'Discover For You guarantees real HTTPS cover images, unwraps Bing redirects & filters out text-only items',
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
          // Every returned card MUST have a valid HTTPS image (no website-name-only fallbacks!)
          for (final PersonalizedNewsItem card in feed) {
            expect(card.hasValidImage, isTrue);
            expect(card.imageUrl, startsWith('https://'));
            expect(card.title, isNot(contains('Text Only Item')));
          }
          expect(
            feed.first.title,
            "SpaceX Starship's Orbital Launch Milestone",
          );
          expect(feed.first.url, 'https://spacenews.example.com/starship');
          expect(feed.first.imageUrl, contains('w=800&h=450&c=7'));
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
    },
  );

  group('Heaven VPN (Built-In Foreign Country Servers + WARP + Custom Import)', () {
    const MethodChannel nativeChannel = MethodChannel(
      'com.hypertechlabs.heavenbrowser/native_shield',
    );

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, null);
    });

    test(
      'VpnController defaults to Foreign USA server, connects 1-tap Foreign Country OpenVPN, supports WARP & imports .ovpn/.conf',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
              switch (call.method) {
                case 'provisionForeignOpenVpnConfig':
                  final Map<Object?, Object?> args =
                      call.arguments as Map<Object?, Object?>;
                  final String cc =
                      args['countryCode']?.toString().toUpperCase() ?? 'US';
                  return <String, Object>{
                    'ok': true,
                    'configText':
                        'client\ndev tun\nremote 198.252.153.226 1194 tcp-client\n',
                    'serverIp': '198.252.153.226',
                    'countryCode': cc == 'AUTO_FOREIGN' ? 'NL' : cc,
                    'countryName': cc == 'JP' ? 'Japan' : 'United States',
                    'city': cc == 'JP' ? 'Tokyo' : 'Miami',
                    'source': 'RiseupVPN',
                    'endpoint': '198.252.153.226:1194',
                  };
                case 'fetchLiveForeignCountries':
                  return <String, Object>{
                    'ok': true,
                    'countries': <Map<String, Object>>[
                      <String, Object>{
                        'countryCode': 'SE',
                        'countryName': 'Sweden',
                        'serverCount': 2,
                      },
                    ],
                  };
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
                  return <String, Object>{
                    'ok': true,
                    'connected': true,
                    'profileName': 'Cloudflare WARP',
                  };
                case 'disconnectVpn':
                  return <String, Object>{'ok': true, 'connected': false};
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
                http.Response('ip=198.252.153.226\nloc=US\nwarp=off\n', 200),
          ),
        );

        // Built-in Foreign Country list includes USA (default), Netherlands, France, Canada, Japan, South Korea, etc.
        expect(vpn.selectedProfile.id, 'foreign_us');
        expect(vpn.selectedProfile.isBuiltInForeign, isTrue);
        expect(vpn.foreignProfiles.length, greaterThanOrEqualTo(9));

        // 1-Tap Connect to Built-in Foreign USA Server
        await vpn.connect();
        await Future<void>.delayed(Duration.zero);
        expect(vpn.isConnected, isTrue);
        expect(vpn.exitIp, '198.252.153.226');
        expect(vpn.exitCountry, 'US');

        // Refresh live foreign servers adds discovered countries (e.g. Sweden)
        await vpn.refreshLiveForeignServers();
        expect(
          vpn.foreignProfiles.any((VpnProfile p) => p.countryCode == 'SE'),
          isTrue,
        );

        // Custom OpenVPN .ovpn import works alongside WireGuard .conf import
        final String? ovpnErr = await vpn.addCustomProfile(
          name: 'Custom Frankfurt OpenVPN',
          countryLabel: '🇩🇪 Germany',
          configText:
              'client\ndev tun\nproto udp\nremote 89.163.212.10 1194\n<ca>\n-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n</ca>\n',
        );
        expect(ovpnErr, isNull);
        expect(vpn.selectedProfile.protocol, VpnProtocol.openvpn);

        final String? wgErr = await vpn.addCustomProfile(
          name: 'Proton Free Zurich',
          countryLabel: '🇨🇭 Switzerland',
          configText:
              '[Interface]\nPrivateKey = AAAA\nAddress = 10.2.0.2/32\n[Peer]\nPublicKey = BBBB\nEndpoint = 185.159.157.1:51820\nAllowedIPs = 0.0.0.0/0\n',
        );
        expect(wgErr, isNull);
        expect(vpn.customProfiles.length, 2);

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
  });

  testWidgets(
    'Step 7 UI: For You image cards, Search UX, Google query Edit & Built-in Foreign Country VPN on narrow 320px screen',
    (WidgetTester tester) async {
      const MethodChannel nativeChannel = MethodChannel(
        'com.hypertechlabs.heavenbrowser/native_shield',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
            switch (call.method) {
              case 'provisionForeignOpenVpnConfig':
                return <String, Object>{
                  'ok': true,
                  'configText':
                      'client\ndev tun\nremote 198.252.153.226 1194 tcp-client\n',
                  'serverIp': '198.252.153.226',
                  'countryCode': 'US',
                  'countryName': 'United States',
                  'city': 'Miami',
                  'source': 'RiseupVPN',
                  'endpoint': '198.252.153.226:1194',
                };
              case 'fetchLiveForeignCountries':
                return <Map<String, Object>>[];
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
                  'profileName': 'United States',
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
            'fileName': 'heaven_installer_v7.apk',
            'url': 'https://example.com/heaven_installer_v7.apk',
            'mimeType': 'application/vnd.android.package-archive',
            'state': 'running',
            'bytesDownloaded': 2097152,
            'totalBytes': 4194304,
            'speedBps': 524288,
            'localUri': '/storage/emulated/0/Download/heaven_installer_v7.apk',
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
          (_) async =>
              http.Response('ip=198.252.153.226\nloc=US\nwarp=off\n', 200),
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

      // 1. Discover Feed renders image-backed cards & filters out text-only items!
      expect(find.text('Discover'), findsOneWidget);
      expect(
        find.textContaining("SpaceX Starship's Orbital Launch Milestone"),
        findsOneWidget,
      );
      expect(find.textContaining('Text Only Item'), findsNothing);

      // 2. + New Tab button works with zero overflow on 320px!
      expect(find.byKey(const Key('bar_new_tab_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('bar_new_tab_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2'), findsOneWidget);

      // 3. Home Search submit & hidden Mic after searching
      await tester.enterText(
        find.byKey(const Key('home_search_textfield')),
        'flutter',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('home_search_icon_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Flutter Official Video'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);

      // 4. Open Heaven VPN Screen -> Shows Built-In Foreign Country Servers (United States, Netherlands, Japan...) & 1-Tap Connects!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VPN'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Heaven VPN'), findsOneWidget);
      expect(find.textContaining('United States'), findsWidgets);
      expect(find.byKey(const Key('vpn_power_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('vpn_power_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(vpn.isConnected, isTrue);
      expect(find.text('VPN Connected'), findsOneWidget);

      // Scroll down to verify Foreign Country Servers list renders with zero overflow on 320px!
      await tester.drag(find.byType(ListView).first, const Offset(0, -320));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Foreign Country Servers (Free)'), findsOneWidget);
      expect(find.text('Netherlands'), findsOneWidget);

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
