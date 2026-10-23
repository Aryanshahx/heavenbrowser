import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heavenbrowser/core/l10n/app_strings.dart';
import 'package:heavenbrowser/core/theme/app_theme.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/features/browser/engine/browser_engine.dart';
import 'package:heavenbrowser/features/downloads/downloads_controller.dart';
import 'package:heavenbrowser/features/extensions/extensions_controller.dart';
import 'package:heavenbrowser/features/news/interest_news_service.dart';
import 'package:heavenbrowser/features/search/heaven_search_service.dart';
import 'package:heavenbrowser/features/search/heaven_search_view.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';
import 'package:heavenbrowser/features/settings/help_screen.dart';
import 'package:heavenbrowser/features/tabs/tab_manager.dart';
import 'package:heavenbrowser/features/vpn/vpn_controller.dart';
import 'package:heavenbrowser/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    if (host == 'www.bing.com' &&
        path == '/search' &&
        request.url.queryParameters['format'] == 'rss') {
      const String bingWebRss = '''
      <rss version="2.0"><channel>
        <item>
          <title>Flutter Official Docs</title>
          <link>https://docs.flutter.dev/get-started</link>
          <description>Install Flutter SDK on Ubuntu Linux and build fast native apps.</description>
        </item>
      </channel></rss>
      ''';
      return http.Response(bingWebRss, 200);
    }
    if (host == 'www.bing.com' && path == '/search') {
      final String bingWebHtml = '''
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
      <div class="news-card newsitem cardcommon" data-title="Flutter 3.47 Released" data-url="https://news.example.com/flutter" data-author="TechDaily">
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
          <title>Flutter 3.47 Released - TechDaily</title>
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

  group('Step 8: Google-Inspired Native Heaven Search, Extensions, Gestures & Settings', () {
    test('uses Electric Sapphire & Midnight Navy blue palette', () {
      expect(AppTheme.sapphireBlue, const Color(0xFF2563EB));
      expect(AppTheme.electricBlue, const Color(0xFF3B82F6));
      expect(AppTheme.deepNavyBg, const Color(0xFF040B16));
      expect(AppTheme.navySurface, const Color(0xFF0B162C));
      expect(AppTheme.darkTheme.colorScheme.primary, const Color(0xFF60A5FA));
    });

    test(
      'Heaven Search stays native (does NOT open google.com), parses Bing RSS fast, formats Google-inspired breadcrumbs & records recent searches outside Incognito',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final BrowserSettingsController settings = BrowserSettingsController(
          prefs,
        );
        final BrowserEngine normalEngine = BrowserEngine(
          settings: settings,
          isIncognito: false,
          enablePlatformWebView: false,
        );
        await normalEngine.loadUserEntry('raspberry pi 5');
        expect(normalEngine.isShowingHeavenSearch, isTrue);
        expect(normalEngine.heavenSearchQuery, 'raspberry pi 5');
        expect(settings.recentSearches, contains('raspberry pi 5'));

        // Incognito never saves recent searches!
        final BrowserEngine incogEngine = BrowserEngine(
          settings: settings,
          isIncognito: true,
          enablePlatformWebView: false,
        );
        await incogEngine.loadUserEntry('secret query');
        expect(settings.recentSearches, isNot(contains('secret query')));

        await settings.removeRecentSearch('raspberry pi 5');
        expect(settings.recentSearches, isEmpty);

        // Google-inspired breadcrumb formatting
        expect(
          OmniboxParser.formatGoogleBreadcrumb(
            'https://docs.flutter.dev/get-started/install',
          ),
          'https://docs.flutter.dev › get-started › install',
        );

        final HeavenSearchService service = _createMockSearchService();
        final HeavenSearchResponse fastRes = await service.searchFastWeb(
          'flutter',
        );
        expect(fastRes.webResults.length, 3);
        expect(fastRes.webResults.first.title, 'Flutter Official Docs');
        expect(fastRes.relatedSearches, contains('flutter sdk'));

        normalEngine.dispose();
        incogEngine.dispose();
      },
    );

    test(
      'ExtensionsController installs Desktop Chrome Web Store (.crx) extensions, parses 32-char IDs & merges CRX content_scripts',
      () async {
        const MethodChannel nativeChannel = MethodChannel(
          'com.hypertechlabs.heavenbrowser/native_shield',
        );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(nativeChannel, null);
        });

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
              switch (call.method) {
                case 'listChromeExtensions':
                  return const <Map<String, Object>>[];
                case 'installWebStoreExtension':
                  return <String, Object>{
                    'ok': true,
                    'extension': <String, Object>{
                      'id': 'eimadpbcbfnmbkopoojfekhnkhdbieeh',
                      'name': 'Dark Reader',
                      'description': 'Dark mode for every website',
                      'version': '4.9.96',
                      'manifestVersion': 3,
                      'enabled': true,
                      'source': 'webstore',
                      'popupUrl':
                          'https://chrome-ext.heaven.local/eimadpbcbfnmbkopoojfekhnkhdbieeh/ui/popup/index.html',
                      'iconBase64': base64Encode(_kSamplePreviewPng),
                      'permissions': <String>['storage', 'tabs'],
                      'matches': <String>['<all_urls>'],
                      'contentScriptCount': 1,
                    },
                  };
                case 'getChromeExtensionScriptsForUrl':
                  return 'window.__darkReaderCrxLoaded = true;';
                case 'toggleChromeExtension':
                case 'uninstallChromeExtension':
                  return true;
                default:
                  return null;
              }
            });

        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final ExtensionsController ext = ExtensionsController(
          prefs,
          syncNativeOnInit: false,
        );

        expect(
          ExtensionsController.extractChromeWebStoreId(
            'https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh?hl=en',
          ),
          'eimadpbcbfnmbkopoojfekhnkhdbieeh',
        );
        expect(
          ExtensionsController.featuredWebStoreCatalog.length,
          greaterThanOrEqualTo(6),
        );

        final String? installErr = await ext.installFromWebStore(
          'https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh',
        );
        expect(installErr, isNull);
        expect(ext.isInstalled('eimadpbcbfnmbkopoojfekhnkhdbieeh'), isTrue);
        expect(ext.chromeExtensions.first.name, 'Dark Reader');
        expect(ext.chromeExtensions.first.hasPopup, isTrue);
        expect(ext.chromeExtensions.first.iconBytes, isNotNull);

        final String? scriptErr = await ext.addCustomExtension(
          name: 'Custom Dark Boost',
          description: 'Adds custom border',
          matchPattern: 'example.com',
          jsCode: 'window.__heavenExtRan = true;',
          cssCode: 'body { outline: 1px solid blue; }',
        );
        expect(scriptErr, isNull);

        final String fullInjected = await ext.buildFullInjectionForUrl(
          'https://sub.example.com/article',
        );
        expect(fullInjected, contains('__darkReaderCrxLoaded'));
        expect(fullInjected, contains('__heavenExtRan'));
        expect(fullInjected, contains('outline: 1px solid blue'));
        ext.dispose();
      },
    );

    test(
      'HeavenSearchService copies live Background Google Search results directly into Heaven Search UI',
      () async {
        const MethodChannel nativeChannel = MethodChannel(
          'com.hypertechlabs.heavenbrowser/native_shield',
        );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(nativeChannel, null);
        });

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
              if (call.method == 'searchGoogleInBackground') {
                return <String, Object>{
                  'ok': true,
                  'webResults': <Map<String, Object>>[
                    <String, Object>{
                      'title': 'Google Live Result: Flutter SDK',
                      'url': 'https://flutter.dev',
                      'snippet': 'Copied from background Google Search DOM.',
                      'sourceLabel': 'flutter.dev',
                    },
                  ],
                  'knowledgeCard': <String, Object>{
                    'heading': 'Flutter Framework',
                    'summary': 'UI toolkit by Google.',
                    'sourceUrl': 'https://flutter.dev',
                    'sourceName': 'Google',
                  },
                  'relatedSearches': <String>[
                    'flutter desktop extensions',
                    'flutter android arm64',
                  ],
                };
              }
              return null;
            });

        final HeavenSearchService service = _createMockSearchService();
        final HeavenSearchResponse res = await service.searchFastWeb('flutter');
        expect(res.webResults.first.title, 'Google Live Result: Flutter SDK');
        expect(res.knowledgeCard?.heading, 'Flutter Framework');
        expect(res.relatedSearches, contains('flutter desktop extensions'));
      },
    );

    test(
      'Tab Groups, Adjacent Tab Gesture Switching, Languages & Per-Site Controls work cleanly',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final BrowserSettingsController settings = BrowserSettingsController(
          prefs,
        );
        final TabManagerController tm = TabManagerController(
          settings: settings,
          enablePlatformWebView: false,
        );

        final BrowserTab second = await tm.openNewTab(incognito: false);
        expect(tm.activeTab.id, second.id);
        expect(tm.switchAdjacentTab(-1), isTrue);
        expect(tm.activeTab.id, isNot(second.id));

        final TabGroup group = tm.createGroupAndAddTab(
          name: 'Dev Docs',
          tabId: second.id,
        );
        expect(tm.groups.length, 1);
        expect(second.groupId, group.id);
        tm.deleteGroup(group.id);
        expect(second.groupId, isNull);

        await settings.setLanguage(BrowserLanguage.hi);
        expect(settings.language, BrowserLanguage.hi);
        expect(settings.language.acceptLanguageHeader, contains('hi-IN'));

        await settings.toggleSiteJavaScript('paywall.example.com');
        expect(
          settings.isJavaScriptAllowedForHost('paywall.example.com'),
          isFalse,
        );

        expect(HelpScreen.supportEmail, 'techlabs.hyper@gmail.com');
        tm.dispose();
      },
    );
  });

  group('Restored Step 7 Foreign Country VPN & Download Location Control', () {
    const MethodChannel nativeChannel = MethodChannel(
      'com.hypertechlabs.heavenbrowser/native_shield',
    );

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, null);
    });

    test(
      'VpnController defaults to United States Foreign OpenVPN, connects Foreign & WARP profiles & reloads failed tabs',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
              switch (call.method) {
                case 'provisionForeignOpenVpnConfig':
                  return <String, Object>{
                    'ok': true,
                    'configText':
                        'client\ndev tun\nremote 89.187.173.169 443 tcp-client\ncipher AES-256-GCM\n<ca>\nCA\n</ca>\n<cert>\nCERT\n</cert>\n<key>\nKEY\n</key>\n',
                    'serverHost': '89.187.173.169',
                    'countryCode': 'US',
                    'countryName': 'United States',
                    'latencyMs': 38,
                  };
                case 'provisionFreeWarpConfig':
                  return <String, Object>{
                    'ok': true,
                    'configText':
                        '[Interface]\nPrivateKey = AAAA\nAddress = 172.16.0.2/32\nDNS = 1.1.1.1\n\n[Peer]\nPublicKey = BBBB\nAllowedIPs = 0.0.0.0/0\nEndpoint = 162.159.193.1:2408\n',
                    'clientIpv4': '172.16.0.2',
                    'endpoint': '162.159.193.1:2408',
                  };
                case 'connectVpn':
                  return <String, Object>{
                    'ok': true,
                    'connected': true,
                    'profileName': 'Fastest Nearby Edge (WARP)',
                  };
                case 'validateWireGuardConfig':
                  return <String, Object>{
                    'valid': true,
                    'endpoint': '185.159.157.1:51820',
                    'addresses': '10.2.0.2/32',
                  };
                case 'disconnectVpn':
                  return <String, Object>{'ok': true, 'connected': false};
                default:
                  return null;
              }
            });

        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        bool callbackFired = false;
        final VpnController vpn = VpnController(
          prefs,
          enableNativePolling: false,
          client: MockClient(
            (_) async =>
                http.Response('ip=89.187.173.169\nloc=US\nwarp=off\n', 200),
          ),
        )..onTunnelConnected = () => callbackFired = true;

        expect(vpn.selectedProfile.id, VpnController.defaultForeignUsId);
        expect(vpn.foreignProfiles.length, greaterThanOrEqualTo(9));

        await vpn.connect();
        expect(vpn.isConnected, isTrue);
        expect(vpn.exitCountry, 'US');
        expect(callbackFired, isTrue);

        await vpn.selectProfile(VpnController.builtInWarpId);
        expect(vpn.isConnected, isTrue);

        final String? wgErr = await vpn.addCustomProfile(
          name: 'Proton Free NL',
          countryLabel: 'Netherlands',
          configText:
              '[Interface]\nPrivateKey = AAAA\nAddress = 10.2.0.2/32\n[Peer]\nPublicKey = BBBB\nEndpoint = 185.159.157.1:51820\nAllowedIPs = 0.0.0.0/0\n',
        );
        expect(wgErr, isNull);
        expect(vpn.customProfiles.length, 1);

        await vpn.disconnect();
        expect(vpn.isConnected, isFalse);
        vpn.dispose();
      },
    );

    test('DownloadsController changes download location cleanly', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
            if (call.method == 'setDownloadLocation') {
              final Map<Object?, Object?> args =
                  call.arguments as Map<Object?, Object?>;
              final String p = args['path']?.toString() ?? '';
              return <String, Object>{
                'ok': true,
                'path': p,
                'label': 'Heaven Subfolder',
              };
            }
            return null;
          });

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final DownloadsController downloads = DownloadsController(
        prefs,
        enableNativePolling: false,
      );
      final String? err = await downloads.setDownloadLocation(
        '/storage/emulated/0/Download/HeavenBrowser',
        label: 'Heaven Subfolder',
      );
      expect(err, isNull);
      expect(
        downloads.downloadLocationPath,
        '/storage/emulated/0/Download/HeavenBrowser',
      );
      expect(downloads.downloadLocationLabel, 'Heaven Subfolder');
      downloads.dispose();
    });
  });

  testWidgets(
    'Step 9 UI: Background Google -> Heaven Search UI, Desktop Chrome Extensions (.crx), Website Logo Shortcut & Classic Foreign VPN on 320px screen',
    (WidgetTester tester) async {
      const MethodChannel nativeChannel = MethodChannel(
        'com.hypertechlabs.heavenbrowser/native_shield',
      );
      Map<Object?, Object?>? capturedShortcutArgs;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
            switch (call.method) {
              case 'searchGoogleInBackground':
                return <String, Object>{
                  'ok': true,
                  'webResults': <Map<String, Object>>[
                    <String, Object>{
                      'title': 'Flutter Official Docs',
                      'url': 'https://docs.flutter.dev',
                      'snippet': 'Build apps for any screen.',
                      'sourceLabel': 'docs.flutter.dev',
                    },
                  ],
                  'relatedSearches': <String>['flutter sdk', 'dart pub'],
                };
              case 'listChromeExtensions':
                return const <Map<String, Object>>[];
              case 'createHomeScreenShortcut':
                capturedShortcutArgs = call.arguments as Map<Object?, Object?>?;
                return true;
              case 'provisionForeignOpenVpnConfig':
                return <String, Object>{
                  'ok': true,
                  'configText':
                      'client\ndev tun\nremote 89.187.173.169 443 tcp-client\ncipher AES-256-GCM\n<ca>\nCA\n</ca>\n<cert>\nCERT\n</cert>\n<key>\nKEY\n</key>\n',
                  'serverHost': '89.187.173.169',
                  'countryCode': 'US',
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

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final BrowserSettingsController settings = BrowserSettingsController(
        prefs,
      );
      await settings.recordRecentSearch('ubuntu raspberry pi');

      final DownloadsController downloads = DownloadsController(
        prefs,
        enableNativePolling: false,
      );
      final ExtensionsController extensions = ExtensionsController(
        prefs,
        syncNativeOnInit: false,
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
              http.Response('ip=89.187.173.169\nloc=US\nwarp=off\n', 200),
        ),
      );

      await tester.pumpWidget(
        HeavenBrowserApp(
          settings: settings,
          downloads: downloads,
          extensions: extensions,
          interests: interests,
          newsService: newsService,
          vpn: vpn,
          enablePlatformWebView: false,
          searchService: _createMockSearchService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 1. Tiny Search Engine Switcher button is present right on the Search Bar!
      expect(
        find.byKey(const Key('tiny_search_engine_switcher')),
        findsWidgets,
      );

      // 2. Tapping Home Search Bar displays Recent Searches!
      await tester.tap(find.byKey(const Key('home_search_textfield')));
      await tester.pumpAndSettle();
      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text('ubuntu raspberry pi'), findsOneWidget);

      // 3. Submit query -> Background Google Search copied into Heaven Search UI!
      await tester.enterText(
        find.byKey(const Key('home_search_textfield')),
        'flutter',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('home_search_icon_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Flutter Official Docs'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('People also search for'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(HeavenSearchView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('People also search for'), findsOneWidget);

      // 4. Open Browser Menu -> Verify Chrome Extensions & Create shortcut!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Add tab to new group'), findsOneWidget);
      expect(find.text('Chrome Extensions'), findsOneWidget);
      expect(find.text('Site controls'), findsOneWidget);
      expect(find.text('Create shortcut'), findsOneWidget);

      // Open Desktop Chrome Extensions screen -> Verify Web Store + .crx UI!
      await tester.tap(find.text('Chrome Extensions'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Desktop Chrome Extensions'), findsOneWidget);
      expect(
        find.byKey(const Key('open_chrome_web_store_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import_crx_file_button')), findsOneWidget);
      expect(find.text('Dark Reader'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Open Create Shortcut -> Verify Website Logo & shortcut creation!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create shortcut'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Create Shortcut'), findsOneWidget);
      await tester.tap(find.text('Add Shortcut'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(capturedShortcutArgs, isNotNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Open Restored Foreign Country VPN screen -> Verify Foreign Countries & 1-tap Connect!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VPN'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Foreign Country Servers'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vpn_power_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(vpn.isConnected, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Open Downloads screen -> Verify Change Download Location card!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Downloads'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('change_download_location_card')),
        findsOneWidget,
      );

      final TabManagerController tm = TabManagerController(
        settings: settings,
        enablePlatformWebView: false,
      );
      tm.activeTab.previewBytes = _kSamplePreviewPng;
      expect(tm.activeTab.previewBytes, isNotEmpty);
      tm.dispose();

      vpn.dispose();
      extensions.dispose();
      newsService.dispose();
      downloads.dispose();
    },
  );
}
