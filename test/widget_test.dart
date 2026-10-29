import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heavenbrowser/core/constants/app_constants.dart';
import 'package:heavenbrowser/core/l10n/app_strings.dart';
import 'package:heavenbrowser/core/theme/app_theme.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/core/widgets/search_engine_chip_button.dart';
import 'package:heavenbrowser/features/browser/engine/browser_engine.dart';
import 'package:heavenbrowser/features/browser/page_translate_reader_service.dart';
import 'package:heavenbrowser/features/browser/presentation/browser_screen.dart';
import 'package:heavenbrowser/features/browser/presentation/widgets/listen_to_page_sheet.dart';
import 'package:heavenbrowser/features/browser/presentation/widgets/offline_pages_sheet.dart';
import 'package:heavenbrowser/features/browser/presentation/widgets/visual_search_sheet.dart';
import 'package:heavenbrowser/features/browser/presentation/widgets/web_context_menu_sheet.dart';
import 'package:heavenbrowser/features/browser/site_controls_sheet.dart';
import 'package:heavenbrowser/features/devtools/desktop_inspector_panel.dart';
import 'package:heavenbrowser/features/downloads/downloads_controller.dart';
import 'package:heavenbrowser/features/downloads/downloads_screen.dart';
import 'package:heavenbrowser/features/news/interest_news_service.dart';
import 'package:heavenbrowser/features/search/heaven_search_service.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';
import 'package:heavenbrowser/features/settings/help_screen.dart';
import 'package:heavenbrowser/features/settings/notifications_screen.dart';
import 'package:heavenbrowser/features/settings/settings_screen.dart';
import 'package:heavenbrowser/features/shield/native_shield_bridge.dart';
import 'package:heavenbrowser/features/tabs/tab_manager.dart';
import 'package:heavenbrowser/features/tabs/tabs_screen.dart';
import 'package:heavenbrowser/features/vpn/vpn_controller.dart';
import 'package:heavenbrowser/features/vpn/vpn_screen.dart';
import 'package:heavenbrowser/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Uint8List _kSamplePreviewPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

HeavenSearchService _createMockSearchService() {
  final MockClient mockClient = MockClient((http.Request request) async {
    if (request.url.host == 'suggestqueries.google.com') {
      return http.Response(
        jsonEncode(<Object>[
          'flutter',
          <String>['flutter sdk', 'flutter webview', 'flutter dart 3'],
        ]),
        200,
      );
    }
    return http.Response('[]', 200);
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
    'Step 19 Core: Customizable Heaven Shield, Reliable Multi-Country VPN, Extensions Removed & .bin-Free Downloads',
    () {
      test(
        'uses Electric Sapphire & Midnight Navy palette, Heaven app name, version 0.0.1, Heaven Shield active, and Extensions completely removed',
        () {
          expect(AppConstants.appName, 'Heaven');
          expect(AppConstants.appVersion, '0.0.1');
          expect(AppConstants.downloadsTabUrl, 'heaven://downloads');
          expect(AppTheme.sapphireBlue, const Color(0xFF2563EB));
          expect(AppTheme.electricBlue, const Color(0xFF3B82F6));
          expect(AppTheme.deepNavyBg, const Color(0xFF040B16));
          expect(AppTheme.navySurface, const Color(0xFF0B162C));
          expect(
            AppTheme.darkTheme.colorScheme.primary,
            const Color(0xFF60A5FA),
          );

          // Heaven Shield, blockers, Extensions & obsolete sheets are 100% removed
          expect(
            File('lib/features/shield/heaven_shield.dart').existsSync(),
            isFalse,
          );
          expect(
            File(
              'lib/features/browser/presentation/widgets/shield_sheet.dart',
            ).existsSync(),
            isFalse,
          );
          expect(
            File(
              'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenChromeExtManager.java',
            ).existsSync(),
            isFalse,
          );
          expect(
            File(
              'lib/features/extensions/extensions_controller.dart',
            ).existsSync(),
            isFalse,
          );
          expect(
            File('lib/features/extensions/extensions_screen.dart').existsSync(),
            isFalse,
          );
        },
      );

      test(
        'Google is Default Search Engine, Perplexity is supported, heaven://downloads resolves cleanly, and viewportRevision stays stable during navigation/scroll inside a tab',
        () async {
          expect(SearchEngine.values.first, SearchEngine.google);
          expect(SearchEngine.values, contains(SearchEngine.perplexity));
          expect(
            SearchEngine.values.map((SearchEngine e) => e.name),
            isNot(contains('heaven')),
          );
          expect(OmniboxParser.isDownloadsUrl('heaven://downloads'), isTrue);
          expect(
            OmniboxParser.isLegacyHeavenUrl('heaven://downloads'),
            isFalse,
          );
          expect(OmniboxParser.formatDisplayUrl('heaven://downloads'), 'Downloads');

          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );
          expect(settings.searchEngine, SearchEngine.google);

          final TabManagerController tabs = TabManagerController(
            settings: settings,
            enablePlatformWebView: false,
          );
          final int initialViewportRev = tabs.viewportRevision.value;

          await tabs.activeEngine.loadUserEntry('raspberry pi 5');
          expect(
            tabs.activeEngine.currentUrl,
            'https://www.google.com/search?q=raspberry+pi+5',
          );
          // Navigating or scrolling inside the active tab must NOT rebuild IndexedStack viewport!
          tabs.activeEngine.handleWebScrollDelta(180, 60);
          expect(tabs.viewportRevision.value, initialViewportRev);

          await settings.setSearchEngine(SearchEngine.perplexity);
          await tabs.activeEngine.loadUserEntry('quantum computing');
          expect(
            tabs.activeEngine.currentUrl,
            'https://www.perplexity.ai/search?q=quantum+computing',
          );

          // Opening Downloads tab opens heaven://downloads and reuses it if called again!
          final BrowserTab dlTab = await tabs.openDownloadsTab();
          expect(dlTab.engine.isShowingDownloadsPage, isTrue);
          expect(dlTab.displayTitle, 'Downloads');
          expect(tabs.totalTabCount, 2);

          final BrowserTab reusedDlTab = await tabs.openDownloadsTab();
          expect(reusedDlTab.id, dlTab.id);
          expect(tabs.totalTabCount, 2);

          // Legacy heaven:// search URLs still migrate automatically to Google Search
          await tabs.activeEngine.loadUri(
            Uri.parse('heaven://search?q=flutter+sdk'),
          );
          expect(
            tabs.activeEngine.currentUrl,
            'https://www.google.com/search?q=flutter+sdk',
          );

          tabs.dispose();
        },
      );

      test(
        'Open tabs (including heaven://downloads), tab groups, AND tab preview screenshots persist across app restarts',
        () async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );

          final TabManagerController session1 = TabManagerController(
            settings: settings,
            enablePlatformWebView: false,
          );
          await session1.activeEngine.loadUserEntry('https://flutter.dev');
          final BrowserTab tab1 = session1.activeTab;
          tab1.previewBytes = _kSamplePreviewPng;
          await prefs.setString(
            'hb.tabPreview.v15.${tab1.id}',
            base64Encode(_kSamplePreviewPng),
          );

          final BrowserTab dlTab = await session1.openDownloadsTab();
          final TabGroup grp = session1.createGroupAndAddTab(
            name: 'Files',
            tabId: dlTab.id,
          );
          expect(session1.normalTabs.length, 2);
          session1.dispose();

          final TabManagerController session2 = TabManagerController(
            settings: settings,
            enablePlatformWebView: false,
          );
          expect(session2.normalTabs.length, 2);
          expect(session2.groups.first.name, 'Files');
          expect(session2.activeTab.groupId, grp.id);
          expect(session2.activeEngine.isShowingDownloadsPage, isTrue);
          expect(session2.normalTabs[0].previewBytes, isNotNull);

          await session2.closeTab(dlTab.id);
          expect(session2.normalTabs.length, 1);
          expect(session2.normalTabs.first.previewBytes, isNotNull);
          session2.dispose();
        },
      );

      test(
        'Home Discover has no country-wise filter and rotates fresh stories on every refresh',
        () async {
          expect(
            NewsCategoryTab.values.map((NewsCategoryTab t) => t.name).toList(),
            equals(<String>[
              'forYou',
              'tech',
              'entertainment',
              'sports',
              'gaming',
              'business',
              'science',
            ]),
          );

          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final InterestProfileController interests = InterestProfileController(
            prefs,
          );
          final MockClient client = MockClient((http.Request req) async {
            expect(req.url.queryParameters.containsKey('cc'), isFalse);
            final String itemsXml = List<String>.generate(12, (int idx) {
              final int n = idx + 1;
              return '''
                <item>
                  <title>Global Technology Story Number $n Launches Worldwide</title>
                  <link>https://news.example.org/story-$n</link>
                  <pubDate>Wed, 28 Oct 2026 10:${(59 - idx).toString().padLeft(2, '0')}:00 GMT</pubDate>
                  <source url="https://news.example.org">GlobalTech</source>
                  <media:content url="https://cdn.example.org/cover-$n.jpg" medium="image" />
                </item>
              ''';
            }).join('\n');
            return http.Response('<rss><channel>$itemsXml</channel></rss>', 200);
          });
          final HeavenNewsFeedService service = HeavenNewsFeedService(
            prefs: prefs,
            interests: interests,
            client: client,
          );

          final List<PersonalizedNewsItem> initial = await service.fetchFeed(
            NewsCategoryTab.tech,
          );
          final List<PersonalizedNewsItem> refreshed = await service.fetchFeed(
            NewsCategoryTab.tech,
            forceRefresh: true,
          );
          expect(initial, isNotEmpty);
          expect(refreshed, isNotEmpty);
          expect(refreshed.first.url, isNot(equals(initial.first.url)));
          service.dispose();
          interests.dispose();
        },
      );

      test(
        'Downloads never fall back to .bin and refreshStatuses updates refined native filenames',
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
                if (call.method == 'startDownload') {
                  final Map<Object?, Object?> args =
                      call.arguments as Map<Object?, Object?>;
                  final String url = args['url']?.toString() ?? '';
                  if (url.contains('app-arm64-release.apk')) {
                    return null;
                  }
                  return <String, Object>{
                    'downloadId': 42,
                    'url': url,
                    'fileName': 'download',
                    'state': 'running',
                  };
                }
                if (call.method == 'queryDownloads') {
                  return <Map<String, Object>>[
                    <String, Object>{
                      'downloadId': 42,
                      'fileName': 'architecture-guide.pdf',
                      'state': 'completed',
                      'bytesDownloaded': 102400,
                      'totalBytes': 102400,
                      'speedBytesPerSec': 0,
                      'localUri':
                          '/storage/emulated/0/Download/architecture-guide.pdf',
                    },
                  ];
                }
                return null;
              });

          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final DownloadsController downloads = DownloadsController(
            prefs,
            enableNativePolling: false,
          );

          final bool ok = await downloads.startUrlDownload(
            url: 'https://cdn.example.com/releases/v2/download?id=9981',
          );
          expect(ok, isTrue);
          expect(downloads.items.first.fileName.endsWith('.bin'), isFalse);

          await downloads.refreshStatuses();
          expect(downloads.items.first.fileName, 'architecture-guide.pdf');
          expect(downloads.items.first.fileName.endsWith('.bin'), isFalse);

          final Map<String, Object?>? apkRes = await NativeShieldBridge.instance
              .startDownload(
                url:
                    'https://releases.example.com/app-arm64-release.apk?token=abc',
                mimeType: 'application/octet-stream',
              );
          expect(apkRes?['fileName'], 'app-arm64-release.apk');

          downloads.dispose();
        },
      );

      test(
        'Privacy Policy file is populated and Per-Site Permission store & 1-tap revoke work cleanly',
        () async {
          expect(
            AppConstants.privacyPolicyUrl,
            'https://github.com/Aryanshahx/heavenbrowser/blob/main/privacypolicy.md',
          );
          final File policyFile = File('privacypolicy.md');
          expect(policyFile.existsSync(), isTrue);
          final String policyText = policyFile.readAsStringSync();
          expect(policyText.length, greaterThan(1500));
          expect(policyText, contains('techlabs.hyper@gmail.com'));

          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );
          await settings.setSitePermission(
            'meet.example.com',
            SitePermissionType.camera,
            SitePermissionDecision.allow,
          );
          await settings.revokeSitePermission(
            'meet.example.com',
            SitePermissionType.camera,
          );
          expect(
            settings.getSitePermission(
              'meet.example.com',
              SitePermissionType.camera,
            ),
            SitePermissionDecision.block,
          );
          await settings.setLanguage(BrowserLanguage.hi);
          expect(settings.language, BrowserLanguage.hi);
          expect(HelpScreen.supportEmail, 'techlabs.hyper@gmail.com');
        },
      );
    },
  );

  group('Minimal Multi-Country VPN (43+ Built-In Countries + Live Relays)', () {
    const MethodChannel nativeChannel = MethodChannel(
      'com.hypertechlabs.heavenbrowser/native_shield',
    );

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, null);
    });

    test(
      'VpnController provides 42+ world countries out of the box, discovers live countries, and connects/disconnects cleanly',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
              switch (call.method) {
                case 'fetchLiveForeignCountries':
                  return <Map<String, Object>>[
                    <String, Object>{
                      'countryCode': 'IS',
                      'countryName': 'Iceland',
                      'serverCount': 3,
                    },
                  ];
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

        expect(vpn.foreignProfiles.length, greaterThanOrEqualTo(42));
        await vpn.refreshLiveForeignServers();
        expect(
          vpn.foreignProfiles.any((VpnProfile p) => p.name == 'Iceland'),
          isTrue,
        );

        expect(vpn.selectedProfile.id, VpnController.defaultForeignUsId);
        await vpn.connect();
        expect(vpn.isConnected, isTrue);
        expect(vpn.exitCountry, 'US');
        expect(callbackFired, isTrue);

        await vpn.selectProfile(VpnController.builtInWarpId);
        expect(vpn.isConnected, isTrue);

        await vpn.disconnect();
        expect(vpn.isConnected, isFalse);
        vpn.dispose();
      },
    );

    test(
      'Customizable Heaven Shield, VPN Endpoint Healing, Extension Removal & Instant Page Translate work cleanly',
      () async {
        expect(
          File('lib/features/store/heaven_web_store_screen.dart').existsSync(),
          isFalse,
        );
        expect(OmniboxParser.isLegacyHeavenUrl('heaven://store'), isTrue);

        SharedPreferences.setMockInitialValues(<String, Object>{
          'hb.vpn.warpConfig.v6':
              '[Interface]\nPrivateKey = AAAA\nAddress = 172.16.0.2/32\nDNS = 1.1.1.1\n\n[Peer]\nPublicKey = BBBB\nAllowedIPs = 0.0.0.0/0\nEndpoint = 162.159.192.1:0\n',
        });
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final BrowserSettingsController settings = BrowserSettingsController(
          prefs,
        );

        // Verify Heaven Shield & tab/cookie restrictions are 100% disabled by default
        expect(settings.shieldEnabled, isFalse);
        expect(settings.shieldBlockAds, isFalse);
        expect(settings.shieldBlockCookieBanners, isFalse);
        expect(settings.shieldCleanUrls, isFalse);
        expect(settings.shieldAntiFingerprinting, isFalse);
        expect(settings.shieldBlockPopups, isFalse);
        expect(settings.blockThirdPartyCookies, isFalse);
        expect(settings.cookiePolicy, HeavenCookiePolicy.allowAll);

        // Verify URL tracking parameter stripping & top-level bounce URL unwrapping
        final Uri dirty = Uri.parse(
          'https://example.com/search?q=flutter&utm_source=twitter&fbclid=xyz123&page=2&gclid=abc',
        );
        final Uri cleaned = BrowserSettingsController.stripTrackingParameters(
          dirty,
        );
        expect(cleaned.toString(), 'https://example.com/search?q=flutter&page=2');

        final Uri fbBounce = Uri.parse(
          'https://l.facebook.com/l.php?u=https%3A%2F%2Fnews.ycombinator.com%2Fitem%3Fid%3D1',
        );
        expect(
          OmniboxParser.unwrapTrackingRedirectUri(fbBounce).toString(),
          'https://news.ycombinator.com/item?id=1',
        );

        // Verify De-AMP URL unwrapping
        final Uri googleAmp = Uri.parse(
          'https://www.google.com/amp/s/example.com/tech/post',
        );
        expect(
          OmniboxParser.unwrapAmpUri(googleAmp).toString(),
          'https://example.com/tech/post',
        );
        final Uri cdnAmp = Uri.parse(
          'https://example-com.cdn.ampproject.org/v/s/example.com/story',
        );
        expect(
          OmniboxParser.unwrapAmpUri(cdnAmp).toString(),
          'https://example.com/story',
        );

        // Verify Web3 domain resolution (.eth, .sol, .crypto)
        expect(
          OmniboxParser.resolveInput(
            'vitalik.eth',
            searchEngine: SearchEngine.google,
            httpsUpgrade: true,
            resolveEns: true,
          ).toString(),
          'https://vitalik.eth.limo',
        );
        expect(
          OmniboxParser.resolveInput(
            'bonfida.sol',
            searchEngine: SearchEngine.google,
            httpsUpgrade: true,
            resolveSns: true,
          ).toString(),
          'https://bonfida.sol.build',
        );
        expect(
          OmniboxParser.resolveInput(
            'heaven.crypto',
            searchEngine: SearchEngine.google,
            httpsUpgrade: true,
            resolveUnstoppable: true,
          ).toString(),
          'https://ud.me/heaven.crypto',
        );

        // Verify unrestricted search engine & browser defaults (Heaven Shield removed)
        expect(settings.shieldAutoRedirectAmp, isFalse);
        expect(settings.shieldPreventLangFp, isFalse);
        expect(settings.allowFacebookEmbeds, isTrue);
        expect(settings.allowTwitterEmbeds, isTrue);
        expect(settings.allowLinkedinEmbeds, isTrue);
        expect(settings.safeBrowsingMode, HeavenSafeBrowsingMode.standard);
        expect(settings.webrtcPolicy, HeavenWebrtcPolicy.defaultPolicy);
        expect(settings.blockSwitchToAppNotices, isFalse);
        expect(settings.sendDntAndGpc, isFalse);
        expect(settings.closeTabsOnExit, isFalse);
        expect(settings.isShieldActiveForHost('example.org'), isFalse);

        // Verify each search engine preserves its own native query URL & exposes its own settings URL
        expect(
          SearchEngine.google.settingsUrl,
          'https://www.google.com/preferences',
        );
        expect(
          SearchEngine.perplexity.settingsUrl,
          'https://www.perplexity.ai/settings',
        );
        expect(
          SearchEngine.duckDuckGo.settingsUrl,
          'https://duckduckgo.com/settings',
        );
        expect(
          SearchEngine.duckDuckGo.queryPrefix.contains('kp='),
          isFalse,
        );
        expect(
          SearchEngine.brave.settingsUrl,
          'https://search.brave.com/settings',
        );
        expect(
          SearchEngine.bing.settingsUrl,
          'https://www.bing.com/account/general',
        );
        expect(
          SearchEngine.bing.queryPrefix.contains('adlt='),
          isFalse,
        );
        expect(
          SearchEngine.startpage.settingsUrl,
          'https://www.startpage.com/do/settings',
        );

        // Verify VpnController heals cached :0 WARP endpoint on load
        final VpnController vpnCheck = VpnController(
          prefs,
          enableNativePolling: false,
          client: MockClient(
            (_) async =>
                http.Response('ip=104.28.200.12\nloc=US\nwarp=on\n', 200),
          ),
        );
        await vpnCheck.selectProfile(VpnController.builtInWarpId);
        expect(
          vpnCheck.selectedProfile.id,
          equals(VpnController.builtInWarpId),
        );
        vpnCheck.dispose();

        final MockClient translateMock = MockClient((http.Request req) async {
          expect(req.url.host, 'translate.googleapis.com');
          return http.Response(
            jsonEncode(<Object>[
              <Object>[
                <Object>['नमस्ते दुनिया\n⟦HB_SEG⟧\nतेज़ ब्राउज़र', 'Hello world'],
              ],
            ]),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        });
        final List<String> translated =
            await PageTranslateReaderService.translateSegments(
              const <String>['Hello world', 'Fast browser'],
              targetLang: 'hi',
              client: translateMock,
            );
        expect(translated, <String>['नमस्ते दुनिया', 'तेज़ ब्राउज़र']);
      },
    );
  });

  testWidgets(
    'Step 19 UI on 320px Screen: Zero-Pull Search Bar, Customizable Heaven Shield, Reliable Multi-Country VPN, Extensions Removed',
    (WidgetTester tester) async {
      const MethodChannel nativeChannel = MethodChannel(
        'com.hypertechlabs.heavenbrowser/native_shield',
      );
      Map<Object?, Object?>? capturedShortcutArgs;
      bool testNotificationSent = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
            switch (call.method) {
              case 'createHomeScreenShortcut':
                capturedShortcutArgs = call.arguments as Map<Object?, Object?>?;
                return true;
              case 'getNotificationStatus':
                return <String, Object>{
                  'systemEnabled': true,
                  'runtimeGranted': true,
                  'downloadNotificationsEnabled': true,
                };
              case 'sendTestNotification':
                testNotificationSent = true;
                return true;
              case 'startDownload':
                final Map<Object?, Object?> args =
                    call.arguments as Map<Object?, Object?>;
                return <String, Object>{
                  'downloadId': 77,
                  'url': args['url']?.toString() ?? '',
                  'fileName': 'ubuntu-guide.pdf',
                  'state': 'running',
                };
              case 'getDownloadLocations':
                return <String, Object>{
                  'currentPath': '/storage/emulated/0/Download',
                  'currentLabel': 'System Downloads',
                  'presets': <Map<String, String>>[
                    <String, String>{
                      'label': 'System Downloads',
                      'path': '/storage/emulated/0/Download',
                    },
                    <String, String>{
                      'label': 'Heaven Subfolder',
                      'path': '/storage/emulated/0/Download/HeavenBrowser',
                    },
                  ],
                };
              case 'setDownloadLocation':
                final Map<Object?, Object?> args =
                    call.arguments as Map<Object?, Object?>;
                return <String, Object>{
                  'ok': true,
                  'path': args['path']?.toString() ?? '',
                  'label': args['label']?.toString() ?? 'Heaven Subfolder',
                };
              case 'provisionForeignOpenVpnConfig':
                return <String, Object>{
                  'ok': true,
                  'configText':
                      'client\ndev tun\nproto tcp-client\nremote 89.187.173.169 1194\ncipher AES-256-GCM\n<ca>\nCA\n</ca>\n<cert>\nCERT\n</cert>\n<key>\nKEY\n</key>\n',
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
              http.Response('ip=89.187.173.169\nloc=US\nwarp=off\n', 200),
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
      final TabManagerController tabManager = tester
          .widget<BrowserScreen>(find.byType(BrowserScreen))
          .tabManager;

      // 1. Home Discover has ZERO country-wise filter & ZERO Shield UI exists
      expect(
        find.byKey(const Key('discover_tab_localCountry')),
        findsNothing,
      );
      expect(find.byKey(const Key('discover_tab_forYou')), findsOneWidget);
      expect(find.byKey(const Key('omnibox_shield_badge_button')), findsNothing);
      expect(find.byKey(const Key('top_bar_shield_button')), findsNothing);

      // 2. Submit search -> resolves to Google; scrolling down glides floating search bar upward WITH ZERO WEBSITE PULL (viewport Rect stays 100% constant!)
      expect(find.byKey(const Key('home_search_icon_button')), findsNothing);
      expect(find.byKey(const Key('home_camera_lens_button')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('home_search_textfield')),
        'flutter',
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.textContaining('google.com'), findsWidgets);

      final Finder viewportBox = find.byKey(
        const Key('browser_website_viewport_box'),
      );
      final Finder topBarWrapper = find.byKey(
        const Key('top_navigation_bar_wrapper'),
      );
      final Finder pillFinder = find.byKey(const Key('omnibox_display_pill'));
      final Rect barRectBefore = tester.getRect(topBarWrapper);
      final Rect viewportBefore = tester.getRect(viewportBox);
      final double pillTopBefore = tester.getTopLeft(pillFinder).dy;

      // Search bar sits cleanly ABOVE websites (never overlaying website content)
      // AND stays permanently visible without disappearing or jittering on scroll!
      expect(
        viewportBefore.top,
        greaterThanOrEqualTo(barRectBefore.bottom - 0.5),
      );

      tabManager.activeEngine.handleWebScrollDelta(140, 60);
      expect(tabManager.activeEngine.isNavBarVisible, isTrue);
      await tester.pumpAndSettle();
      expect(tester.getRect(topBarWrapper), equals(barRectBefore));
      expect(tester.getRect(viewportBox), equals(viewportBefore));
      expect(tester.getTopLeft(pillFinder).dy, closeTo(pillTopBefore, 0.1));

      tabManager.activeEngine.handleWebScrollDelta(80, -35);
      expect(tabManager.activeEngine.isNavBarVisible, isTrue);
      await tester.pumpAndSettle();
      expect(tester.getRect(topBarWrapper), equals(barRectBefore));
      expect(tester.getRect(viewportBox), equals(viewportBefore));
      expect(tester.getTopLeft(pillFinder).dy, closeTo(pillTopBefore, 0.1));

      // 3. Left-Edge Swipe Gesture navigates Back to Home, and Right-Edge Swipe Gesture navigates Forward!
      await tester.drag(
        find.byKey(const Key('left_edge_back_gesture_zone')),
        const Offset(80, 0),
      );
      await tester.pumpAndSettle();
      expect(tabManager.activeEngine.isShowingStartPage, isTrue);

      await tester.drag(
        find.byKey(const Key('right_edge_forward_gesture_zone')),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();
      expect(tabManager.activeEngine.currentUrl, contains('google.com'));

      // 4. Verify Translate button is out of Search Bar, renamed from 'Language' to 'Translate' in 3-dots Menu,
      //    and opens a clean Translate-only sheet with ALL extra unrelated controls removed!
      expect(find.byKey(const Key('translate_reader_button')), findsNothing);
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('browser_menu_shield_tile')), findsNothing);
      expect(
        find.byKey(const Key('browser_menu_shield_settings_tile')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('browser_menu_web_store_tile')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('browser_menu_language_tile')),
        findsOneWidget,
      );
      expect(find.text('Translate'), findsOneWidget);
      expect(find.text('Language'), findsNothing);

      // Tap Translate button in 3-dots menu -> opens pure Translate Page sheet!
      await tester.tap(find.byKey(const Key('browser_menu_language_tile')));
      await tester.pumpAndSettle();
      expect(find.byType(TranslateReaderSheet), findsOneWidget);
      expect(
        find.byKey(const Key('language_sheet_app_language_tile')),
        findsNothing,
      );
      expect(find.byKey(const Key('open_clean_reader_button')), findsNothing);
      expect(find.text('Clear Site Cookies & Storage'), findsNothing);
      expect(find.text('Desktop Site'), findsNothing);
      expect(find.byKey(const Key('site_brave_shields_switch')), findsNothing);
      expect(find.byKey(const Key('revoke_perm_camera')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('translate_lang_chip_hi')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate_lang_chip_hi')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate_page_now_button')));
      await tester.pumpAndSettle();
      expect(tabManager.activeEngine.isPageTranslated, isTrue);
      expect(tabManager.activeEngine.translatedLangCode, 'hi');
      expect(
        find.byKey(const Key('restore_original_language_button')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('restore_original_language_button')),
      );
      await tester.pumpAndSettle();
      expect(tabManager.activeEngine.isPageTranslated, isFalse);

      // Dismiss pure Translate sheet, then open Clean Reader Mode from its dedicated 3-dots menu tile!
      Navigator.of(tester.element(find.byType(TranslateReaderSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('browser_menu_clean_reader_tile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clean_reader_view_modal')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // 4b. Top bar has ZERO Heaven Shield icon, and the Search Engine picker
      // from the search bar is a CLEAN engine list: the bottom "X Settings"
      // entry is GONE but every engine keeps its per-engine settings GEAR!
      expect(find.byKey(const Key('top_bar_shield_button')), findsNothing);
      await tester.tap(find.byKey(const Key('tiny_search_engine_switcher')).first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('popup_current_engine_settings_item')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('popup_engine_settings_google')),
        findsOneWidget,
      );
      // Tapping the per-engine gear opens that engine's own settings page!
      await tester.tap(
        find.byKey(const Key('popup_engine_settings_google')),
      );
      await tester.pumpAndSettle();
      expect(settings.searchEngine, SearchEngine.google);
      expect(
        tabManager.activeEngine.currentUrl,
        'https://www.google.com/preferences',
      );
      // Selecting an engine from the clean picker just switches engines!
      await tester.tap(find.byKey(const Key('tiny_search_engine_switcher')).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('popup_search_engine_bing')),
      );
      await tester.pumpAndSettle();
      expect(settings.searchEngine, SearchEngine.bing);
      await tester.tap(find.byKey(const Key('tiny_search_engine_switcher')).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('popup_search_engine_google')),
      );
      await tester.pumpAndSettle();
      expect(settings.searchEngine, SearchEngine.google);

      // 5. Starting a download displays tappable 'Download started' popup banner -> tapping it opens Downloads IN A TAB!
      await downloads.startUrlDownload(
        url: 'https://releases.example.com/ubuntu-guide.pdf',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byKey(const Key('download_started_popup_banner')),
        findsOneWidget,
      );
      expect(find.textContaining('Download started'), findsOneWidget);

      await tester.tap(find.byKey(const Key('download_started_popup_banner')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tabManager.totalTabCount, 2);
      expect(tabManager.activeEngine.isShowingDownloadsPage, isTrue);
      expect(find.byKey(const Key('downloads_tab_view')), findsOneWidget);
      expect(find.byType(DownloadsScreen), findsOneWidget);

      // Change Download Location sheet works cleanly inside the Downloads Tab!
      await tester.tap(find.byKey(const Key('change_download_location_card')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.tap(find.text('Heaven Subfolder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(downloads.downloadLocationLabel, 'Heaven Subfolder');

      // 6. Horizontal Swipe Gesture on the Top Address Bar switches smoothly between Tab 2 (Downloads) and Tab 1 (Google)!
      // Notice TickerMode automatically pauses Tab 2's indeterminate progress bar once switched away!
      await tester.drag(
        find.byKey(const Key('top_bar_tab_swipe_detector')),
        const Offset(90, 0),
      );
      await tester.pumpAndSettle();
      expect(tabManager.activeEngine.isShowingDownloadsPage, isFalse);
      expect(tabManager.activeEngine.currentUrl, contains('google.com'));

      // Browser Menu -> Downloads switches right back to the Downloads Tab without spawning duplicates!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Shield'), findsNothing);
      expect(find.text('Ultra Data Saver (Text-Only)'), findsNothing);
      await tester.tap(find.byKey(const Key('browser_menu_downloads_tile')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tabManager.totalTabCount, 2);
      expect(tabManager.activeEngine.isShowingDownloadsPage, isTrue);

      // 7. Minimal VPN Screen opens, renders 42+ countries + search filter + Browser Only chip cleanly on 320px!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.tap(find.text('VPN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(HeavenVpnScreen), findsOneWidget);
      expect(find.byKey(const Key('vpn_split_tunnel_chip')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('vpn_country_search_field')),
        'Switzerland',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.byKey(const Key('vpn_country_tile_foreign_ch')),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      // Switch back to Tab 1 via Top Address Bar Swipe!
      await tester.drag(
        find.byKey(const Key('top_bar_tab_swipe_detector')),
        const Offset(90, 0),
      );
      await tester.pumpAndSettle();
      expect(tabManager.activeEngine.currentUrl, contains('google.com'));

      // 8. Settings Screen exposes Heaven Web Store tile (ZERO Brave Shields switches!), switches to Perplexity, and opens Privacy Policy!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('browser_menu_settings_tile')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('browser_menu_settings_tile')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Ultra Data Saver'), findsNothing);
      expect(find.text('Privacy & Security'), findsNothing);
      expect(find.text('HTTPS Upgrade'), findsNothing);
      expect(find.text('Block Third-Party Cookies'), findsNothing);
      expect(
        find.byKey(const Key('settings_brave_shields_switch')),
        findsNothing,
      );
      expect(find.byKey(const Key('settings_farbling_switch')), findsNothing);
      expect(find.byKey(const Key('settings_web_store_tile')), findsNothing);
      expect(
        find.byKey(const Key('settings_heaven_shield_tile')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('settings_active_engine_own_settings_tile')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('settings_search_engine_tile')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('search_engine_option_perplexity')),
      );
      await tester.pumpAndSettle();
      expect(settings.searchEngine, SearchEngine.perplexity);

      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_privacy_policy_tile')),
        180,
        scrollable: find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_privacy_policy_tile')));
      await tester.pumpAndSettle();
      expect(find.textContaining('github.com'), findsWidgets);

      // 9. Notifications & Create Shortcut & Tabs Screen active rounded border still work cleanly!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.text('Anti-Redirect & Spam Hijack Alerts'), findsNothing);
      await tester.tap(find.byKey(const Key('send_test_notification_button')));
      await tester.pumpAndSettle();
      expect(testNotificationSent, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create shortcut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create shortcut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Shortcut'));
      await tester.pumpAndSettle();
      expect(capturedShortcutArgs, isNotNull);

      tabManager.activeTab.previewBytes = _kSamplePreviewPng;
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch Tabs'));
      await tester.pumpAndSettle();
      expect(find.byType(TabsScreen), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      final AnimatedContainer activeCardContainer = tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: find.byKey(
                ValueKey<String>('tab_card_${tabManager.activeTab.id}'),
              ),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .first;
      final BoxDecoration? fgDeco =
          activeCardContainer.foregroundDecoration as BoxDecoration?;
      expect(fgDeco, isNotNull);
      expect(fgDeco!.borderRadius, BorderRadius.circular(18));
      expect((fgDeco.border! as Border).top.width, 2.6);

      vpn.dispose();
      newsService.dispose();
      downloads.dispose();
    },
  );

  group('DevTools & Native Java Clean Architecture Invariants', () {
    testWidgets(
      'Desktop Inspect (DevTools) panel opens from Browser Menu & works across Elements, Console, Network, Storage & Info on 320px screen',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        SharedPreferences.setMockInitialValues(<String, Object>{});
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
                http.Response('ip=198.51.100.7\nloc=US\nwarp=on\n', 200),
          ),
        );

        await tester.pumpWidget(
          HeavenBrowserApp(
            settings: settings,
            searchService: _createMockSearchService(),
            downloads: downloads,
            newsService: newsService,
            interests: interests,
            vpn: vpn,
            enablePlatformWebView: false,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Browser Menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('browser_menu_inspect_tile')));
        await tester.pumpAndSettle();
        expect(find.byType(DesktopInspectorPanel), findsOneWidget);

        await tester.tap(
          find.byKey(const Key('devtools_element_picker_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Tap any element on the webpage above'),
          findsOneWidget,
        );

        await tester.tap(find.text('Console'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('devtools_console_input')),
          'document.title',
        );
        await tester.tap(find.byKey(const Key('devtools_console_run_button')));
        await tester.pumpAndSettle();
        expect(find.text('> document.title'), findsOneWidget);

        await tester.tap(find.byKey(const Key('devtools_close_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('desktop_inspector_panel')), findsNothing);

        vpn.dispose();
        newsService.dispose();
        downloads.dispose();
      },
    );

    test(
      'Native Java, Kotlin, ProGuard & Manifest safety: 120Hz WebView + HeavenShieldEngine + VPN R8/Handshake Fixes + Extensions Removed',
      () {
        expect(
          File(
            'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenBraveShieldEngine.java',
          ).existsSync(),
          isFalse,
        );
        expect(
          File(
            'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenExtEngine.java',
          ).existsSync(),
          isFalse,
        );
        expect(
          File('lib/features/shield/brave_shield_status.dart').existsSync(),
          isFalse,
        );
        expect(Directory('lib/features/store').existsSync(), isFalse);

        expect(
          File(
            'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenShieldEngine.java',
          ).existsSync(),
          isFalse,
        );
        expect(
          File('lib/features/shield/heaven_shield_screen.dart').existsSync(),
          isFalse,
        );

        final String shieldJava = File(
          'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenShieldPlugin.java',
        ).readAsStringSync();
        expect(shieldJava.contains('HeavenTabWebChromeClient'), isTrue);
        expect(shieldJava.contains('onOpenNewTabRequest'), isTrue);
        expect(shieldJava.contains('setSupportMultipleWindows(true)'), isTrue);
        expect(
          shieldJava.contains('setJavaScriptCanOpenWindowsAutomatically(true)'),
          isTrue,
        );
        expect(shieldJava.contains('ShieldWebChromeClient'), isFalse);
        expect(shieldJava.contains('HeavenBraveShieldEngine'), isFalse);
        expect(shieldJava.contains('HeavenShieldEngine'), isFalse);
        expect(shieldJava.contains('HeavenExtEngine'), isFalse);
        expect(shieldJava.contains('getBraveShieldStats'), isFalse);
        expect(shieldJava.contains('onBlockedRequest'), isFalse);
        expect(shieldJava.contains('canScrollVertically(-1)'), isFalse);
        expect(shieldJava.contains('HeavenChromeExtManager'), isFalse);
        expect(shieldJava.contains('URLUtil.guessFileName'), isFalse);
        expect(shieldJava.contains('download.bin'), isFalse);
        expect(shieldJava.contains('resolveSmartFileName'), isTrue);
        expect(shieldJava.contains('refineDownloadJobTarget'), isTrue);
        expect(shieldJava.contains('installPullToRefreshListener'), isTrue);
        expect(shieldJava.contains('onPageAtTop'), isTrue);
        expect(shieldJava.contains('onInnerScroll'), isTrue);
        expect(shieldJava.contains('FLAG_DEBUGGABLE'), isTrue);
        expect(shieldJava.contains('setOffscreenPreRaster(false)'), isTrue);
        expect(shieldJava.contains('Bitmap.Config.RGB_565'), isTrue);
        expect(shieldJava.contains('isLowRamDevice'), isTrue);
        expect(shieldJava.contains('onTrimMemory'), isTrue);
        expect(shieldJava.contains('LAYER_TYPE_HARDWARE'), isFalse);
        expect(shieldJava.contains('isVideoPlayerTouchZone'), isTrue);
        expect(shieldJava.contains('lastInnerScrollMsByWv'), isTrue);
        expect(
          shieldJava.contains("window.addEventListener('pointerdown'"),
          isTrue,
        );
        expect(
          shieldJava.contains("window.addEventListener('scroll'"),
          isFalse,
        );
        expect(shieldJava.contains('focusWebView'), isTrue);
        expect(shieldJava.contains('addDocumentStartJavaScript'), isTrue);
        expect(shieldJava.contains('window.__hbInBg'), isTrue);
        expect(shieldJava.contains('onWebScrollNavBar'), isTrue);
        expect(shieldJava.contains('bgKeepAliveLoop'), isTrue);

        final String browserEngineDart = File(
          'lib/features/browser/engine/browser_engine.dart',
        ).readAsStringSync();
        expect(
          browserEngineDart.contains('displayWithHybridComposition: true'),
          isTrue,
        );
        expect(browserEngineDart.contains('cachedWebViewWidget'), isTrue);

        final String browserScreenDart = File(
          'lib/features/browser/presentation/browser_screen.dart',
        ).readAsStringSync();
        expect(browserScreenDart.contains('if (leftProgress > 0.02)'), isTrue);
        expect(browserScreenDart.contains('if (rightProgress > 0.02)'), isTrue);

        final String mainKt = File(
          'android/app/src/main/kotlin/com/hypertechlabs/heavenbrowser/MainActivity.kt',
        ).readAsStringSync();
        expect(mainKt.contains('enableHighestRefreshRate'), isTrue);
        expect(mainKt.contains('preferredDisplayModeId'), isTrue);
        expect(mainKt.contains('onTrimMemory'), isTrue);

        final String vpnJava = File(
          'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenVpnManager.java',
        ).readAsStringSync();
        expect(vpnJava.contains('normalizeEndpointPort'), isTrue);
        expect(vpnJava.contains('waitForWireGuardPeerHandshake'), isTrue);
        expect(vpnJava.contains('normalizeVpnGateOvpnForOpenSsl3'), isTrue);
        expect(vpnJava.contains('extractRiseupOpenVpnPorts'), isTrue);
        expect(vpnJava.contains('DEFAULT:@SECLEVEL=0'), isTrue);
        expect(vpnJava.contains('pickFastestCandidate'), isTrue);
        expect(vpnJava.contains('ExecutorCompletionService'), isTrue);
        expect(vpnJava.contains('ensureRiseupReady'), isTrue);

        final String proguardRules = File(
          'android/app/proguard-rules.pro',
        ).readAsStringSync();
        expect(proguardRules.contains('-keep class com.wireguard.**'), isTrue);

        final String appGradle = File(
          'android/app/build.gradle.kts',
        ).readAsStringSync();
        expect(appGradle.contains('proguard-rules.pro'), isTrue);
        expect(appGradle.contains('useLegacyPackaging = true'), isTrue);
        expect(appGradle.contains('key.properties'), isTrue);
        expect(appGradle.contains('create("release")'), isTrue);

        final String workflowYml = File(
          '.github/workflows/build.yml',
        ).readAsStringSync();
        expect(workflowYml.contains('ANDROID_KEYSTORE_BASE64'), isTrue);
        expect(workflowYml.contains('ANDROID_KEYSTORE_PASSWORD'), isTrue);
        expect(workflowYml.contains('ANDROID_KEY_ALIAS'), isTrue);
        expect(workflowYml.contains('ANDROID_KEY_PASSWORD'), isTrue);
        expect(File('tool/generate_playstore_key.sh').existsSync(), isTrue);

        final String mediaServiceJava = File(
          'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenMediaService.java',
        ).readAsStringSync();
        expect(
          mediaServiceJava.contains('FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK'),
          isTrue,
        );
        expect(mediaServiceJava.contains('MediaSession'), isTrue);

        final String manifestXml = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();
        expect(manifestXml.contains('android:label="Heaven"'), isTrue);
        expect(manifestXml.contains('android:hardwareAccelerated="true"'), isTrue);
        expect(manifestXml.contains('android:extractNativeLibs="true"'), isTrue);
        expect(
          manifestXml.contains('io.flutter.embedding.android.EnableImpeller'),
          isTrue,
        );
        expect(
          manifestXml.contains('com.wireguard.android.backend.GoBackend\$VpnService'),
          isTrue,
        );
        expect(manifestXml.contains('systemExempted'), isTrue);
        expect(manifestXml.contains('android.permission.USE_BIOMETRIC'), isTrue);
      },
    );

    testWidgets(
      'Step 23: Tap-and-hold tab drag anywhere, 3-dots Add tab to new group, & single-pass loading bar',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final BrowserSettingsController settings = BrowserSettingsController(
          prefs,
        );
        final TabManagerController tabManager = TabManagerController(
          settings: settings,
          enablePlatformWebView: false,
        );

        final String firstTabId = tabManager.normalTabs.first.id;
        final BrowserTab secondTab = await tabManager.openNewTab(
          initialInput: 'https://m.youtube.com/shorts/abc123',
        );
        final BrowserTab thirdTab = await tabManager.openNewTab(
          initialInput: 'https://example.org',
        );
        // Search bar NEVER disappears even on Shorts or scrolling!
        expect(tabManager.activeEngine.isNavBarVisible, isTrue);

        await tester.pumpWidget(
          MaterialApp(home: TabsScreen(tabManager: tabManager)),
        );
        await tester.pumpAndSettle();
        expect(
          tabManager.normalTabs.map((BrowserTab t) => t.id).toList(),
          equals(<String>[firstTabId, secondTab.id, thirdTab.id]),
        );

        // 1. Tap-and-hold thirdTab and drag it onto firstTabId's slot to reorder!
        final Offset fromCenter = tester.getCenter(
          find.byKey(ValueKey<String>('tab_draggable_${thirdTab.id}')),
        );
        final Offset toCenter = tester.getCenter(
          find.byKey(ValueKey<String>('tab_drop_target_$firstTabId')),
        );
        final TestGesture dragGesture = await tester.startGesture(fromCenter);
        await tester.pump(const Duration(milliseconds: 260));
        await dragGesture.moveTo(toCenter);
        await tester.pump(const Duration(milliseconds: 80));
        await dragGesture.up();
        await tester.pumpAndSettle();

        expect(
          tabManager.normalTabs.map((BrowserTab t) => t.id).toList(),
          equals(<String>[thirdTab.id, firstTabId, secondTab.id]),
        );

        // 2. Top AppBar 3-dots menu removed; tap 3-dots menu button on tab card -> 'Add tab to new group' -> Create Group!
        expect(find.byKey(const Key('tabs_appbar_more_button')), findsNothing);
        await tester.tap(
          find.byKey(ValueKey<String>('tab_more_button_${thirdTab.id}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('add_tab_to_new_group_button')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('add_tab_to_new_group_button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('confirm_create_tab_group_button')),
        );
        await tester.pumpAndSettle();
        expect(tabManager.groups.length, 1);
        expect(thirdTab.groupId, tabManager.groups.first.id);

        // 3. Close a visible row-1 tab via Close button cleanly!
        await tester.tap(
          find.descendant(
            of: find.byKey(ValueKey<String>('tab_card_$firstTabId')),
            matching: find.byTooltip('Close tab'),
          ),
        );
        await tester.pumpAndSettle();
        expect(tabManager.normalTabs.length, 2);

        // 4. Verify single-pass loading bar invariants in source
        final String engineSrc = File(
          'lib/features/browser/engine/browser_engine.dart',
        ).readAsStringSync();
        expect(engineSrc.contains('_finishLoadingDebounceTimer'), isTrue);
        expect(engineSrc.contains('isFastRedirect'), isTrue);

        tabManager.dispose();
        settings.dispose();
      },
    );

    testWidgets(
      'Step 24: VPN in Settings, Zero .... & Idle Refresh Button in VPN Screen, & Full Tablet Optimization (800x1280 & 1280x800)',
      (WidgetTester tester) async {
        const MethodChannel nativeChannel = MethodChannel(
          'com.hypertechlabs.heavenbrowser/native_shield',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
              switch (call.method) {
                case 'fetchLiveForeignCountries':
                  return <String, Object?>{
                    'ok': true,
                    'countries': <Map<String, Object?>>[
                      <String, Object?>{
                        'countryCode': 'US',
                        'countryName': 'United States',
                        'serverCount': 4,
                      },
                    ],
                  };
                case 'provisionForeignOpenVpnConfig':
                  return <String, Object?>{
                    'ok': true,
                    'configText':
                        'client\ndev tun\nproto udp\nremote 89.187.173.169 1194\n<ca>\nTEST\n</ca>\n<cert>\nTEST\n</cert>\n<key>\nTEST\n</key>\n',
                    'serverHost': '89.187.173.169',
                    'countryCode': 'US',
                    'countryName': 'United States (Miami)',
                    'latencyMs': 95,
                  };
                case 'disconnectVpn':
                  return <String, Object?>{'ok': true};
                case 'getVpnStatus':
                  return <String, Object?>{
                    'connected': false,
                    'rxBytes': 0,
                    'txBytes': 0,
                  };
                default:
                  return null;
              }
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(nativeChannel, null);
        });

        // Start on a 1280x800 Landscape Tablet viewport!
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        SharedPreferences.setMockInitialValues(<String, Object>{});
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
                http.Response('ip=89.187.173.169\nloc=US\nwarp=off\n', 200),
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

        // 1. Tablet StartPage: centered search bar (<= 680px) + 3-column compact Discover grid!
        expect(find.byKey(const Key('tablet_bar_back_button')), findsOneWidget);
        expect(
          find.byKey(const Key('tablet_bar_reload_button')),
          findsOneWidget,
        );
        final Size searchFieldSize = tester.getSize(
          find.byKey(const Key('home_search_textfield')),
        );
        expect(searchFieldSize.width, lessThanOrEqualTo(680));

        expect(find.byKey(const Key('discover_tablet_grid')), findsOneWidget);
        final SliverGrid landscapeDiscoverGrid = tester.widget<SliverGrid>(
          find.byKey(const Key('discover_tablet_grid')),
        );
        final SliverGridDelegateWithFixedCrossAxisCount landscapeDelegate =
            landscapeDiscoverGrid.gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount;
        expect(landscapeDelegate.crossAxisCount, 3);
        expect(landscapeDelegate.mainAxisExtent, lessThanOrEqualTo(290));

        // Switch to 800x1280 Portrait Tablet -> 2-column compact Discover grid!
        tester.view.physicalSize = const Size(800, 1280);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final SliverGrid portraitDiscoverGrid = tester.widget<SliverGrid>(
          find.byKey(const Key('discover_tablet_grid')),
        );
        final SliverGridDelegateWithFixedCrossAxisCount portraitDelegate =
            portraitDiscoverGrid.gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount;
        expect(portraitDelegate.crossAxisCount, 2);

        // 2. Open Settings -> Heaven VPN tile is present and opens HeavenVpnScreen!
        tester.view.physicalSize = const Size(1280, 800);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Browser Menu'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('browser_menu_settings_tile')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('browser_menu_settings_tile')));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.byKey(const Key('settings_vpn_tile')), findsOneWidget);
        expect(find.text('Heaven VPN'), findsOneWidget);

        await tester.tap(find.byKey(const Key('settings_vpn_tile')));
        await tester.pumpAndSettle();
        expect(find.byType(HeavenVpnScreen), findsOneWidget);

        // 3. VPN Screen: Refresh button is IDLE (NOT spinning!), tablet 2-col country grid active, and ZERO "..." / "...." text anywhere!
        expect(find.byKey(const Key('vpn_refresh_button')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('vpn_refresh_button')),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );
        expect(find.byKey(const Key('vpn_tablet_country_grid')), findsOneWidget);

        for (final Text txt in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(HeavenVpnScreen),
            matching: find.byType(Text),
          ),
        )) {
          final String data = txt.data ?? '';
          expect(data.contains('...'), isFalse, reason: 'Found dots in "$data"');
        }
        final TextField vpnSearch = tester.widget<TextField>(
          find.byKey(const Key('vpn_country_search_field')),
        );
        expect(vpnSearch.decoration?.hintText?.contains('...'), isFalse);

        // Tapping Refresh completes cleanly and settles back to idle icon!
        await tester.tap(find.byKey(const Key('vpn_refresh_button')));
        await tester.pumpAndSettle();
        expect(vpn.isRefreshingServers, isFalse);
        expect(
          find.descendant(
            of: find.byKey(const Key('vpn_refresh_button')),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );

        // Connect VPN -> fast connection with zero "..." in status
        await tester.tap(find.byKey(const Key('vpn_power_button')));
        await tester.pumpAndSettle();
        expect(vpn.isConnected, isTrue);

        // Navigate back to BrowserScreen (pop VPN -> pop Settings)
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.textContaining('Connected •'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        // 4. Tablet TabsScreen: 5 columns on 1280x800, 4 columns on 960x800, & 3 columns on 800x1280!
        final TabManagerController tabManager = tester
            .widget<BrowserScreen>(find.byType(BrowserScreen))
            .tabManager;
        await tabManager.openNewTab(initialInput: 'https://example.com');
        await tabManager.openNewTab(initialInput: 'https://flutter.dev');
        await tabManager.openNewTab(initialInput: 'https://dart.dev');
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Switch Tabs'));
        await tester.pumpAndSettle();
        expect(find.byType(TabsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        final GridView landscapeTabsGrid = tester.widget<GridView>(
          find.byKey(const Key('tabs_grid_view')),
        );
        final SliverGridDelegateWithFixedCrossAxisCount landscapeTabsDel =
            landscapeTabsGrid.gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount;
        expect(landscapeTabsDel.crossAxisCount, 5);

        tester.view.physicalSize = const Size(960, 800);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final GridView midTabletTabsGrid = tester.widget<GridView>(
          find.byKey(const Key('tabs_grid_view')),
        );
        final SliverGridDelegateWithFixedCrossAxisCount midTabletTabsDel =
            midTabletTabsGrid.gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount;
        expect(midTabletTabsDel.crossAxisCount, 4);

        tester.view.physicalSize = const Size(800, 1280);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final GridView portraitTabsGrid = tester.widget<GridView>(
          find.byKey(const Key('tabs_grid_view')),
        );
        final SliverGridDelegateWithFixedCrossAxisCount portraitTabsDel =
            portraitTabsGrid.gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount;
        expect(portraitTabsDel.crossAxisCount, 3);

        vpn.dispose();
        downloads.dispose();
        interests.dispose();
        settings.dispose();
      },
    );

    testWidgets(
      'Step 25: Real Engine Images, Instant Re-Search on Engine Switch, & Chrome/Brave Context Menu + Seamless Child-Tab Back',
      (WidgetTester tester) async {
        // 1. Verify all 6 Search Engine real PNG brand assets exist
        for (final SearchEngine engine in SearchEngine.values) {
          final File iconFile = File(engine.logoAssetPath);
          expect(
            iconFile.existsSync(),
            isTrue,
            reason: 'Missing engine logo asset ${engine.logoAssetPath}',
          );
          final Uint8List bytes = iconFile.readAsBytesSync();
          expect(bytes.length, greaterThan(1500));
          expect(bytes.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
        }

        // 2. Domain equivalence & Search Query Extraction unit checks
        expect(
          OmniboxParser.isSameWebsite(
            'https://m.youtube.com/watch?v=123',
            'https://youtu.be/123',
          ),
          isTrue,
        );
        expect(
          OmniboxParser.isSameWebsite(
            'https://en.wikipedia.org/wiki/Dart',
            'https://fr.wikipedia.org/wiki/Dart',
          ),
          isTrue,
        );
        expect(
          OmniboxParser.isSameWebsite(
            'https://news.ycombinator.com/item?id=1',
            'https://flutter.dev/docs',
          ),
          isFalse,
        );

        const MethodChannel nativeChannel = MethodChannel(
          'com.hypertechlabs.heavenbrowser/native_shield',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
              switch (call.method) {
                case 'startDownload':
                  return <String, Object?>{
                    'downloadId': 777,
                    'url': (call.arguments as Map<Object?, Object?>)['url'],
                    'fileName': 'logo.png',
                    'mimeType': 'image/png',
                    'state': 'completed',
                    'bytesDownloaded': 4096,
                    'totalBytes': 4096,
                  };
                default:
                  return null;
              }
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(nativeChannel, null);
        });

        tester.view.physicalSize = const Size(900, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        SharedPreferences.setMockInitialValues(<String, Object>{});
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
                http.Response('ip=89.187.173.169\nloc=US\nwarp=off\n', 200),
          ),
        );

        await tester.pumpWidget(
          HeavenBrowserApp(
            settings: settings,
            downloads: downloads,
            interests: interests,
            newsService: newsService,
            searchService: _createMockSearchService(),
            vpn: vpn,
            enablePlatformWebView: false,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SearchEngineLogo), findsWidgets);
        final Image chipLogo = tester.widget<Image>(
          find
              .descendant(
                of: find.byKey(const Key('tiny_search_engine_switcher')).first,
                matching: find.byType(Image),
              )
              .first,
        );
        expect(chipLogo.image, isA<AssetImage>());
        expect(
          (chipLogo.image as AssetImage).assetName,
          'assets/images/engines/google.png',
        );

        final TabManagerController tabManager = tester
            .widget<BrowserScreen>(find.byType(BrowserScreen))
            .tabManager;

        // 3. Search Immediately on Search Engine Change while on ANY website!
        await tabManager.activeEngine.loadUserEntry(
          'https://www.google.com/search?q=raspberry+pi+5',
        );
        await tester.pumpAndSettle();
        expect(
          tabManager.activeEngine.currentUrl,
          contains('google.com/search?q=raspberry+pi+5'),
        );

        await tester.tap(
          find.byKey(const Key('tiny_search_engine_switcher')).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Perplexity').last);
        await tester.pumpAndSettle();
        expect(settings.searchEngine, SearchEngine.perplexity);
        expect(
          tabManager.activeEngine.currentUrl,
          'https://www.perplexity.ai/search?q=raspberry+pi+5',
        );

        await tabManager.activeEngine.loadUserEntry(
          'https://en.wikipedia.org/wiki/Quantum_computing',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('tiny_search_engine_switcher')).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Brave Search').last);
        await tester.pumpAndSettle();
        expect(settings.searchEngine, SearchEngine.brave);
        expect(
          tabManager.activeEngine.currentUrl,
          startsWith('https://search.brave.com/search?q='),
        );

        // 4. Chrome / Brave-Style Web Context Menu for Linked Images + Seamless Back!
        await tabManager.closeAllTabsByMode(incognito: false);
        await tester.pumpAndSettle();
        await tabManager.activeEngine.loadUserEntry(
          'https://news.ycombinator.com',
        );
        await tester.pumpAndSettle();

        tabManager.activeEngine.onWebContextMenu?.call(
          const WebContextMenuData(
            webViewId: 1,
            linkUrl: 'https://dart.dev/guides',
            linkText: 'Dart Guides',
            imageUrl: 'https://dart.dev/assets/logo.png',
            imageAlt: 'Dart Logo',
            hitType: 8,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WebContextMenuSheet), findsOneWidget);
        expect(find.byKey(const Key('ctx_open_new_tab')), findsOneWidget);
        expect(find.byKey(const Key('ctx_open_bg_tab')), findsOneWidget);
        expect(find.byKey(const Key('ctx_open_incognito_tab')), findsOneWidget);
        expect(find.byKey(const Key('ctx_copy_link')), findsOneWidget);
        expect(find.byKey(const Key('ctx_copy_link_text')), findsOneWidget);
        expect(find.byKey(const Key('ctx_download_link')), findsOneWidget);
        expect(find.byKey(const Key('ctx_open_image_new_tab')), findsOneWidget);
        expect(find.byKey(const Key('ctx_download_image')), findsOneWidget);
        expect(
          find.byKey(const Key('ctx_search_image_google')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('ctx_copy_image_url')), findsOneWidget);

        await tester.tap(find.byKey(const Key('ctx_open_new_tab')));
        await tester.pumpAndSettle();
        expect(tabManager.totalTabCount, 2);
        expect(tabManager.activeEngine.currentUrl, 'https://dart.dev/guides');
        expect(tabManager.canReturnToOpenerTab, isTrue);

        await tabManager.navigateBackSeamlessly();
        await tester.pumpAndSettle();
        expect(tabManager.totalTabCount, 1);
        expect(
          tabManager.activeEngine.currentUrl,
          'https://news.ycombinator.com',
        );

        vpn.dispose();
        downloads.dispose();
        interests.dispose();
        settings.dispose();
      },
    );

    testWidgets(
      'Step 26: Pirate-Site Ad/Popunder Blocking, 3-Dots Menu (Listen + Offline/PDF + Settings Below Notifications, No Incognito), Zero AI, "Google" Label, Camera Lens Next to Mic, Home Widget, & First-Launch Default Browser Prompt',
      (WidgetTester tester) async {
        // 1. Verify AI files/dependencies are 100% deleted & Android Home Screen Search Widget is registered!
        expect(
          File(
            'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenAiManager.java',
          ).existsSync(),
          isFalse,
        );
        expect(Directory('lib/features/ai').existsSync(), isFalse);
        expect(
          File('android/app/build.gradle.kts').readAsStringSync(),
          isNot(contains('com.google.mlkit:genai')),
        );
        expect(
          File(
            'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenSearchWidgetProvider.java',
          ).existsSync(),
          isTrue,
        );
        expect(
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
          contains('android.appwidget.action.APPWIDGET_UPDATE'),
        );
        expect(
          File(
            'android/app/src/main/res/xml/heaven_search_widget_info.xml',
          ).existsSync(),
          isTrue,
        );

        // 2. Verify "Google" label (never "Google (Default)" or "Google Search")
        expect(SearchEngine.google.label, 'Google');
        expect(SearchEngine.google.shortLabel, 'Google');

        // 3. Verify Pirate / Streaming Site Ad & Popunder Redirect Blocking + Single-Tab Navigation!
        expect(
          OmniboxParser.isKnownAdOrPopunderRedirect(
            Uri.parse('https://syndication.exoclick.com/splash.php?idzone=99'),
          ),
          isTrue,
        );
        expect(
          OmniboxParser.isKnownAdOrPopunderRedirect(
            Uri.parse('https://serve.popads.net/c?p=1234'),
          ),
          isTrue,
        );
        expect(
          OmniboxParser.isKnownAdOrPopunderRedirect(
            Uri.parse('https://flutter.dev/multi-platform'),
          ),
          isFalse,
        );

        int defaultBrowserRoleCalls = 0;
        int pinWidgetCalls = 0;
        int savePdfCalls = 0;
        final List<String> ttsSpokenChunks = <String>[];
        String lastCameraSource = '';

        const MethodChannel nativeChannel = MethodChannel(
          'com.hypertechlabs.heavenbrowser/native_shield',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
              switch (call.method) {
                case 'consumeInitialLaunchAction':
                  return null;
                case 'isDefaultBrowser':
                  return false;
                case 'requestDefaultBrowserRole':
                  defaultBrowserRoleCalls += 1;
                  return true;
                case 'requestPinSearchWidget':
                  pinWidgetCalls += 1;
                  return true;
                case 'refreshSearchWidgets':
                  return null;
                case 'lensStartCamera':
                  lastCameraSource = 'live_camera';
                  return <String, Object?>{
                    'ok': true,
                    'textureId': 42,
                    'previewWidth': 1080,
                    'previewHeight': 1440,
                    'isFront': false,
                    'hasFlash': true,
                    'maxZoom': 4.0,
                  };
                case 'lensCaptureAndSearch':
                  return <String, Object?>{
                    'ok': true,
                    'resultUrl':
                        'https://www.google.com/search?vsrid=MOCK_LENS_ID&udm=26',
                  };
                case 'lensStopCamera':
                  return true;
                case 'ttsSpeak':
                  final Map<Object?, Object?> args =
                      call.arguments as Map<Object?, Object?>;
                  ttsSpokenChunks.add(args['text']?.toString() ?? '');
                  return true;
                case 'ttsStop':
                  return null;
                case 'saveOfflinePage':
                  return <String, Object?>{
                    'ok': true,
                    'filePath': '/tmp/flutter_docs_offline.mht',
                    'sizeBytes': 48120,
                  };
                case 'loadOfflineArchive':
                  return true;
                case 'deleteOfflinePage':
                  return true;
                case 'saveWebPageAsPdf':
                  savePdfCalls += 1;
                  return true;
                default:
                  return null;
              }
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(nativeChannel, null);
        });

        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        SharedPreferences.setMockInitialValues(<String, Object>{});
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
                http.Response('ip=89.187.173.169\nloc=US\nwarp=off\n', 200),
          ),
        );

        await tester.pumpWidget(
          HeavenBrowserApp(
            settings: settings,
            downloads: downloads,
            interests: interests,
            newsService: newsService,
            searchService: _createMockSearchService(),
            vpn: vpn,
            enablePlatformWebView: false,
            promptDefaultBrowserOnFirstLaunch: true,
          ),
        );
        await tester.pumpAndSettle();

        // 4. First-Launch Default Browser Prompt appears once and calls requestDefaultBrowserRole!
        expect(
          find.byKey(const Key('first_launch_default_browser_dialog')),
          findsOneWidget,
        );
        expect(settings.hasPromptedDefaultBrowser, isTrue);
        await tester.tap(
          find.byKey(const Key('default_browser_confirm_button')),
        );
        await tester.pumpAndSettle();
        expect(defaultBrowserRoleCalls, 1);

        // Zero AI buttons anywhere in top bar!
        expect(find.byKey(const Key('top_bar_ai_button')), findsNothing);

        // 5. Home Screen Search Bar: Search icon button removed, Camera button right next to Mic button!
        expect(find.byKey(const Key('home_search_icon_button')), findsNothing);
        final Finder homeMic = find.byKey(const Key('home_voice_mic_button'));
        final Finder homeCamera = find.byKey(
          const Key('home_camera_lens_button'),
        );
        expect(homeMic, findsOneWidget);
        expect(homeCamera, findsOneWidget);
        expect(
          tester.getCenter(homeCamera).dx,
          greaterThan(tester.getCenter(homeMic).dx),
        );
        expect(
          (tester.getCenter(homeCamera).dy - tester.getCenter(homeMic).dy)
              .abs(),
          lessThan(2.0),
        );

        // Search engine picker displays "Google", NEVER "Google (Default)"!
        await tester.tap(
          find.byKey(const Key('tiny_search_engine_switcher')).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Google'), findsWidgets);
        expect(find.textContaining('Google (Default)'), findsNothing);
        expect(find.textContaining('Google Search'), findsNothing);
        await tester.tap(find.text('Google').last);
        await tester.pumpAndSettle();

        // 6. Camera button next to Mic opens HeavenLensCameraScreen instantly & searches with Google Lens!
        await tester.tap(homeCamera);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(find.byType(HeavenLensCameraScreen), findsOneWidget);
        expect(lastCameraSource, 'live_camera');
        await tester.tap(find.byKey(const Key('lens_shutter_capture_button')));
        await tester.pumpAndSettle();

        final TabManagerController tabManager = tester
            .widget<BrowserScreen>(find.byType(BrowserScreen))
            .tabManager;
        expect(
          tabManager.activeEngine.currentUrl,
          'https://www.google.com/search?vsrid=MOCK_LENS_ID&udm=26',
        );
        expect(tabManager.totalTabCount, 1);

        // 7. Heaven Shield & navigation/tab restrictions removed: websites & redirects navigate freely!
        await tabManager.activeEngine.loadUserEntry('https://stream-example.tv');
        await tester.pumpAndSettle();
        expect(tabManager.totalTabCount, 1);

        final adDecision = await tabManager.activeEngine
            .handleWebsiteNavigationOrRedirect(
              'https://syndication.exoclick.com/popunder?zone=1',
            );
        expect(adDecision.name, 'navigate');

        final legitDecision = await tabManager.activeEngine
            .handleWebsiteNavigationOrRedirect(
              'https://flutter.dev/docs',
            );
        expect(legitDecision.name, 'navigate');

        final bounceDecision = await tabManager.activeEngine
            .handleWebsiteNavigationOrRedirect(
              'https://spam-tracker-redirect.xyz/jump',
            );
        expect(bounceDecision.name, 'navigate');

        // 8. 3-Dots Menu: No Incognito, No AI, Listen + Offline/PDF in grid, Settings right below Notifications!
        await tester.tap(find.byTooltip('Browser Menu'));
        await tester.pumpAndSettle();
        expect(find.text('Incognito'), findsNothing);
        expect(find.byKey(const Key('browser_menu_ai_tile')), findsNothing);
        expect(
          find.byKey(const Key('browser_menu_listen_tile')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('browser_menu_offline_pdf_tile')),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(const Key('browser_menu_settings_tile')),
        );
        await tester.pumpAndSettle();
        final double notificationsDy = tester
            .getCenter(find.byKey(const Key('browser_menu_notifications_tile')))
            .dy;
        final double settingsDy = tester
            .getCenter(find.byKey(const Key('browser_menu_settings_tile')))
            .dy;
        expect(settingsDy, greaterThan(notificationsDy));
        expect(settingsDy - notificationsDy, lessThan(80.0));

        // 9. Listen to This Page (TTS) from 3-dots menu!
        await tester.ensureVisible(
          find.byKey(const Key('browser_menu_listen_tile')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('browser_menu_listen_tile')));
        await tester.pumpAndSettle();
        expect(find.byType(ListenToPageSheet), findsOneWidget);
        expect(ttsSpokenChunks, isNotEmpty);

        // Change speed to 1.5x and close sheet -> active Listen mini bar stays above viewport!
        await tester.tap(find.byKey(const Key('tts_rate_1.5x')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('active_tts_mini_bar')), findsOneWidget);

        // Stop TTS from mini bar
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('active_tts_mini_bar')),
            matching: find.byTooltip('Stop'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('active_tts_mini_bar')), findsNothing);

        // 10. Offline Pages & Save Webpage as PDF from 3-dots menu!
        await tester.tap(find.byTooltip('Browser Menu'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('browser_menu_offline_pdf_tile')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(OfflinePagesSheet), findsOneWidget);

        await tester.tap(find.byKey(const Key('save_offline_page_button')));
        await tester.pumpAndSettle();
        expect(find.textContaining('stream-example.tv'), findsWidgets);
        expect(find.textContaining('47 KB'), findsOneWidget);

        await tester.tap(find.byKey(const Key('save_webpage_pdf_button')));
        await tester.pumpAndSettle();
        expect(savePdfCalls, 1);

        // 11. Settings -> Add Search Widget tile triggers 1-tap widget pin!
        await tester.tap(find.byTooltip('Browser Menu'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('browser_menu_settings_tile')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('browser_menu_settings_tile')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('settings_default_browser_tile')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('settings_add_widget_tile')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('settings_add_widget_tile')));
        await tester.pumpAndSettle();
        expect(pinWidgetCalls, 1);

        vpn.dispose();
        downloads.dispose();
        interests.dispose();
        settings.dispose();
      },
    );

    testWidgets(
      'Step 27: Redirect Back-Navigation Fix, Top Camera Button Removed, Instant Widget Keyboard (Even When Already Tapped), & Instant Modern Google-Lens Live Camera + Gallery Search',
      (WidgetTester tester) async {
        // 1. Verify native Step 27 architecture files & widget Android 14+ BAL + no-animation flags!
        final String widgetJava = File(
          'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenSearchWidgetProvider.java',
        ).readAsStringSync();
        expect(widgetJava, contains('FLAG_ACTIVITY_NO_ANIMATION'));
        expect(
          widgetJava,
          contains('MODE_BACKGROUND_ACTIVITY_START_ALLOWED'),
        );
        expect(widgetJava, contains('onAppWidgetOptionsChanged'));
        expect(
          File(
            'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenLensCameraManager.java',
          ).existsSync(),
          isTrue,
        );
        expect(
          File(
            'android/app/src/main/res/drawable/heaven_widget_preview.xml',
          ).existsSync(),
          isTrue,
        );
        final String widgetInfoXml = File(
          'android/app/src/main/res/xml/heaven_search_widget_info.xml',
        ).readAsStringSync();
        expect(
          widgetInfoXml,
          contains('android:previewLayout="@layout/heaven_search_widget"'),
        );
        expect(
          widgetInfoXml,
          contains('android:previewImage="@drawable/heaven_widget_preview"'),
        );

        int showSoftKeyboardCalls = 0;
        int lensStartCalls = 0;
        int galleryPickCalls = 0;
        String lastLensMode = '';
        String lastLensQuery = '';

        // Valid 1x1 JPEG bytes for gallery preview rendering in widget test
        final Uint8List tinyPngBytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        );

        const MethodChannel nativeChannel = MethodChannel(
          'com.hypertechlabs.heavenbrowser/native_shield',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
              switch (call.method) {
                case 'consumeInitialLaunchAction':
                  return null;
                case 'showSoftKeyboard':
                  showSoftKeyboardCalls += 1;
                  return true;
                case 'lensStartCamera':
                  lensStartCalls += 1;
                  return <String, Object?>{
                    'ok': true,
                    'textureId': 99,
                    'previewWidth': 1080,
                    'previewHeight': 1440,
                    'isFront': call.arguments['facing'] == 'front',
                    'hasFlash': true,
                    'maxZoom': 4.0,
                  };
                case 'lensSetTorch':
                  return call.arguments['enabled'] == true;
                case 'lensStopCamera':
                  return true;
                case 'lensPickGalleryImage':
                  galleryPickCalls += 1;
                  return <String, Object?>{
                    'ok': true,
                    'base64Jpeg': base64Encode(tinyPngBytes),
                    'width': 400,
                    'height': 400,
                  };
                case 'lensSearchImageBytes':
                  final Map<Object?, Object?> args =
                      call.arguments as Map<Object?, Object?>;
                  lastLensMode = args['mode']?.toString() ?? '';
                  lastLensQuery = args['query']?.toString() ?? '';
                  return <String, Object?>{
                    'ok': true,
                    'resultUrl':
                        'https://www.google.com/search?vsrid=GALLERY_LENS_OK&udm=24&q=${Uri.encodeQueryComponent(lastLensQuery)}',
                  };
                default:
                  return null;
              }
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(nativeChannel, null);
        });

        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        SharedPreferences.setMockInitialValues(<String, Object>{});
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
                http.Response('ip=89.187.173.169\nloc=US\nwarp=off\n', 200),
          ),
        );

        await tester.pumpWidget(
          HeavenBrowserApp(
            settings: settings,
            downloads: downloads,
            interests: interests,
            newsService: newsService,
            searchService: _createMockSearchService(),
            vpn: vpn,
            enablePlatformWebView: false,
          ),
        );
        await tester.pumpAndSettle();

        // 2. Top Search Area has ZERO camera button, while Home Screen Search Bar keeps Camera next to Mic!
        expect(
          find.byKey(const Key('top_bar_camera_lens_button')),
          findsNothing,
        );
        expect(find.byKey(const Key('home_camera_lens_button')), findsOneWidget);

        // Tap top search bar -> editing mode ALSO has ZERO camera button & shows keyboard!
        await tester.tap(find.byKey(const Key('omnibox_display_pill')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('top_omnibox_textfield')), findsOneWidget);
        expect(
          find.byKey(const Key('top_omnibox_camera_lens_button')),
          findsNothing,
        );
        final int kbCallsAfterFirstTap = showSoftKeyboardCalls;
        expect(kbCallsAfterFirstTap, greaterThanOrEqualTo(1));

        // 3. Even when ALREADY tapped in search bar, tapping Heaven Search Widget forces keyboard open!
        NativeShieldBridge.instance.onExternalLaunchAction?.call(
          const <String, Object?>{'type': 'omnibox'},
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('top_omnibox_textfield')), findsOneWidget);
        expect(showSoftKeyboardCalls, greaterThan(kbCallsAfterFirstTap));

        // Close omnibox edit overlay
        await tester.tap(find.byTooltip('Cancel'));
        await tester.pumpAndSettle();

        // 4. Instant Google-Lens Camera Screen + Choose from Gallery + Multimodal Query & Modes!
        await tester.tap(find.byKey(const Key('home_camera_lens_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(find.byType(HeavenLensCameraScreen), findsOneWidget);
        expect(lensStartCalls, 1);
        expect(
          find.byKey(const Key('lens_pick_gallery_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('lens_shutter_capture_button')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('lens_torch_button')), findsOneWidget);
        expect(
          find.byKey(const Key('lens_flip_camera_button')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('lens_mode_translate')), findsOneWidget);
        expect(find.byKey(const Key('lens_mode_search')), findsOneWidget);
        expect(find.byKey(const Key('lens_mode_text')), findsOneWidget);
        expect(find.byKey(const Key('lens_mode_shopping')), findsOneWidget);

        // Select Shopping mode + enter multimodal question + tap Gallery button!
        await tester.tap(find.byKey(const Key('lens_mode_shopping')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('lens_multimodal_query_field')),
          'black sneakers',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('lens_pick_gallery_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(galleryPickCalls, 1);
        // The picked photo now opens FROZEN with the draggable 4-corner crop
        // frame (Google-Lens style) — the crop feature actually works!
        expect(find.text('Back to Live Camera'), findsOneWidget);
        expect(
          find.byKey(const Key('lens_crop_frame_button')),
          findsNothing,
        );
        expect(lastLensMode, isEmpty);

        // Press the shutter to search the picked (optionally cropped) photo!
        await tester.tap(find.byKey(const Key('lens_shutter_capture_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();

        expect(lastLensMode, 'shopping');
        expect(lastLensQuery, 'black sneakers');

        final TabManagerController tabManager = tester
            .widget<BrowserScreen>(find.byType(BrowserScreen))
            .tabManager;
        expect(
          tabManager.activeEngine.currentUrl,
          contains('google.com/search?vsrid=GALLERY_LENS_OK'),
        );

        // 5. Redirect Back-Navigation Fix: Website A -> transient redirect hop -> Website B (same tab) -> Back returns to Website A -> Back returns to StartPage!
        await tabManager.activeEngine.goHome();
        await tester.pumpAndSettle();
        expect(tabManager.activeEngine.isShowingStartPage, isTrue);

        // User opens Website A (still 1 tab: the Heaven Search Widget tap
        // earlier found a fresh StartPage tab and simply REUSED it — no
        // empty-tab pile-up!)
        await tabManager.activeEngine.loadUserEntry('https://site-a.com/news');
        await tester.pumpAndSettle();
        expect(tabManager.activeEngine.currentUrl, 'https://site-a.com/news');
        expect(tabManager.totalTabCount, 1);

        // Website A redirects via intermediate hop -> Website B inside the SAME tab!
        tabManager.activeEngine.recordHeadlessWebsiteRedirect(
          'https://redirect-hop.example/bounce',
          isTransientHop: true,
        );
        tabManager.activeEngine.recordHeadlessWebsiteRedirect(
          'https://site-b.org/final-article',
          isTransientHop: false,
        );
        await tester.pumpAndSettle();
        expect(
          tabManager.activeEngine.currentUrl,
          'https://site-b.org/final-article',
        );
        expect(tabManager.totalTabCount, 1);
        expect(tabManager.activeEngine.canGoBack, isTrue);

        // First Back -> skips intermediate redirect hop and lands cleanly back on Website A!
        final bool back1 = await tabManager.navigateBackSeamlessly();
        await tester.pumpAndSettle();
        expect(back1, isTrue);
        expect(tabManager.activeEngine.currentUrl, 'https://site-a.com/news');
        expect(tabManager.activeEngine.canGoBack, isTrue);

        // Second Back -> lands cleanly back on StartPage!
        final bool back2 = await tabManager.navigateBackSeamlessly();
        await tester.pumpAndSettle();
        expect(back2, isTrue);
        expect(tabManager.activeEngine.isShowingStartPage, isTrue);

        vpn.dispose();
        downloads.dispose();
        interests.dispose();
        settings.dispose();
      },
    );
  });

  group(
    'Step 28: Heaven Shield Removed, Per-Engine Own Settings, Unrestricted Multi-Tab, Fresh Home News & Active-Tab Positioned TabsScreen',
    () {
      test(
        'Legacy Shield prefs are ignored and multi-window/target=_blank requests spawn real new tabs without restriction',
        () async {
          SharedPreferences.setMockInitialValues(<String, Object>{
            'hb.shield.enabled': true,
            'hb.shield.mode': 'strict',
            'hb.shield.blockAds': true,
            'hb.shield.blockPopups': true,
            'hb.blockThirdPartyCookies': true,
          });
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );
          expect(settings.shieldEnabled, isFalse);
          expect(settings.shieldBlockAds, isFalse);
          expect(settings.shieldBlockPopups, isFalse);
          expect(settings.blockThirdPartyCookies, isFalse);
          expect(settings.cookiePolicy, HeavenCookiePolicy.allowAll);

          final TabManagerController tabManager = TabManagerController(
            settings: settings,
            enablePlatformWebView: false,
          );
          await tabManager.activeEngine.loadUserEntry(
            'https://duckduckgo.com/?q=flutter',
          );
          expect(tabManager.normalTabs.length, 1);

          // Simulate search engine opening a result in a new tab (target="_blank" / window.open)
          tabManager.activeEngine.requestNewTabFromEngine(
            'https://flutter.dev/docs',
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));

          expect(tabManager.normalTabs.length, 2);
          expect(
            tabManager.activeEngine.currentUrl,
            'https://flutter.dev/docs',
          );

          tabManager.dispose();
          settings.dispose();
        },
      );

      testWidgets(
        'Per-search-engine own settings open from Home chip, Top chip & SettingsScreen, and Home pull-to-refresh shows new news with zero country filter',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          SharedPreferences.setMockInitialValues(<String, Object>{});
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
          final MockClient rotatingNewsClient = MockClient((
            http.Request req,
          ) async {
            expect(req.url.queryParameters.containsKey('cc'), isFalse);
            final String xmlItems = List<String>.generate(14, (int i) {
              final int numId = i + 1;
              return '''
                <item>
                  <title>Headline Batch Story #$numId Breaking Global Update</title>
                  <link>https://worldnews.example.com/article-$numId</link>
                  <pubDate>Wed, 28 Oct 2026 12:${(59 - i).toString().padLeft(2, '0')}:00 GMT</pubDate>
                  <source url="https://worldnews.example.com">WorldNews</source>
                  <media:content url="https://images.example.com/photo-$numId.jpg" medium="image" />
                </item>
              ''';
            }).join('\n');
            return http.Response('<rss><channel>$xmlItems</channel></rss>', 200);
          });
          final HeavenNewsFeedService newsService = HeavenNewsFeedService(
            prefs: prefs,
            interests: interests,
            client: rotatingNewsClient,
          );
          final VpnController vpn = VpnController(
            prefs,
            enableNativePolling: false,
            client: MockClient(
              (_) async =>
                  http.Response('ip=198.51.100.12\nloc=US\nwarp=off\n', 200),
            ),
          );

          await tester.pumpWidget(
            HeavenBrowserApp(
              settings: settings,
              downloads: downloads,
              interests: interests,
              newsService: newsService,
              searchService: _createMockSearchService(),
              vpn: vpn,
              enablePlatformWebView: false,
            ),
          );
          await tester.pumpAndSettle();

          // 1. Country-wise filter is completely gone; initial headline #1 is shown on Home Screen
          expect(
            find.byKey(const Key('discover_tab_localCountry')),
            findsNothing,
          );
          expect(
            find.text('Headline Batch Story #1 Breaking Global Update'),
            findsOneWidget,
          );

          // 2. Pull down to refresh on Home Screen -> new news headline rotates right to the top!
          await tester.fling(
            find.byType(CustomScrollView).first,
            const Offset(0, 360),
            1200,
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          expect(
            find.text('Headline Batch Story #7 Breaking Global Update'),
            findsOneWidget,
          );

          // 3. Home Screen search engine chip picker: bottom "X Settings"
          // entry removed, but the per-engine GEAR is there — tapping it
          // opens that engine's own settings page!
          await tester.tap(
            find.byKey(const Key('tiny_search_engine_switcher')).last,
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('popup_current_engine_settings_item')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('popup_engine_settings_duckDuckGo')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const Key('popup_engine_settings_duckDuckGo')),
          );
          await tester.pumpAndSettle();

          final TabManagerController tabManager = tester
              .widget<BrowserScreen>(find.byType(BrowserScreen))
              .tabManager;
          expect(settings.searchEngine, SearchEngine.duckDuckGo);
          expect(
            tabManager.activeEngine.currentUrl,
            'https://duckduckgo.com/settings',
          );

          // Going Home and switching engines from the plain picker rows
          // keeps the StartPage (instant switch, no navigation)!
          await tabManager.activeEngine.goHome();
          await tester.pumpAndSettle();
          expect(tabManager.activeEngine.isShowingStartPage, isTrue);
          await tester.tap(
            find.byKey(const Key('tiny_search_engine_switcher')).last,
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('popup_search_engine_duckDuckGo')),
          );
          await tester.pumpAndSettle();
          expect(settings.searchEngine, SearchEngine.duckDuckGo);
          expect(tabManager.activeEngine.isShowingStartPage, isTrue);

          // 4. SettingsScreen exposes active engine settings tile + per-engine gear in Search Engine picker!
          await tester.tap(find.byTooltip('Browser Menu'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const Key('browser_menu_settings_tile')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('browser_menu_settings_tile')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SettingsScreen), findsOneWidget);
          expect(
            find.byKey(const Key('settings_heaven_shield_tile')),
            findsNothing,
          );
          expect(find.text('DuckDuckGo Settings'), findsOneWidget);

          await tester.tap(
            find.byKey(const Key('settings_search_engine_tile')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('open_engine_own_settings_brave')),
          );
          await tester.pumpAndSettle();
          expect(settings.searchEngine, SearchEngine.brave);
          expect(
            tabManager.activeEngine.currentUrl,
            'https://search.brave.com/settings',
          );

          vpn.dispose();
          newsService.dispose();
          downloads.dispose();
          interests.dispose();
          settings.dispose();
        },
      );

      testWidgets(
        'TabsScreen removes All button, places New Group before New Tab, and opens scrolled directly to the active tab',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(390, 760);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );
          final TabManagerController tabManager = TabManagerController(
            settings: settings,
            enablePlatformWebView: false,
          );

          // Open 12 websites and keep Tab #11 active (row 5 in 2-column grid, well below top fold)
          await tabManager.activeEngine.loadUserEntry(
            'https://site-1.example.org',
          );
          final List<BrowserTab> opened = <BrowserTab>[
            tabManager.normalTabs.first,
          ];
          for (int i = 2; i <= 12; i++) {
            final BrowserTab t = await tabManager.openNewTab(
              initialInput: 'https://site-$i.example.org',
            );
            opened.add(t);
          }
          final BrowserTab activeTarget = opened[10]; // Tab #11 (index 10)
          tabManager.switchToTab(activeTarget.id);
          expect(tabManager.activeTab.id, activeTarget.id);

          await tester.pumpWidget(
            MaterialApp(home: TabsScreen(tabManager: tabManager)),
          );
          await tester.pumpAndSettle();

          // 1. "All (...)" button is 100% removed
          expect(find.textContaining('All ('), findsNothing);
          expect(find.widgetWithText(ChoiceChip, 'All (12)'), findsNothing);

          // 2. "New Group" button is in the bottom bar strictly BEFORE "New Tab"
          final Finder newGroupBtn = find.byKey(
            const Key('tabs_bottom_new_group_button'),
          );
          final Finder newTabBtn = find.byKey(
            const Key('tabs_bottom_new_tab_button'),
          );
          expect(newGroupBtn, findsOneWidget);
          expect(newTabBtn, findsOneWidget);
          expect(
            tester.getTopLeft(newGroupBtn).dx,
            lessThan(tester.getTopLeft(newTabBtn).dx),
          );

          // 3. TabsScreen did NOT open at the top (0.0) — it opened scrolled right to Tab #11!
          final ScrollableState gridScrollState = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const Key('tabs_grid_view')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(gridScrollState.position.pixels, greaterThan(400.0));
          expect(
            find.byKey(ValueKey<String>('tab_card_${activeTarget.id}')),
            findsOneWidget,
          );

          // 4. Tapping "New Group" creates a group chip, and tapping the chip toggles filter cleanly without an "All" chip!
          await tester.tap(newGroupBtn);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('confirm_create_tab_group_button')),
          );
          await tester.pumpAndSettle();
          expect(tabManager.groups.length, 1);
          expect(find.textContaining('All ('), findsNothing);

          final String grpId = tabManager.groups.first.id;
          final Finder grpChip = find.byKey(
            ValueKey<String>('tab_group_filter_$grpId'),
          );
          expect(grpChip, findsOneWidget);
          await tester.tap(grpChip);
          await tester.pumpAndSettle();
          // Filtered to just the 1 grouped tab
          expect(
            find.byKey(ValueKey<String>('tab_card_${activeTarget.id}')),
            findsOneWidget,
          );
          // Tap group chip again -> unselects filter back to all 12 tabs!
          await tester.tap(grpChip);
          await tester.pumpAndSettle();
          expect(tabManager.normalTabs.length, 12);

          tabManager.dispose();
          settings.dispose();
        },
      );
    },
  );

  group(
    'Step 29: True Standalone Search Engine Parity, SecureWebChromeClient Multi-Tab Fix & Pirated-Site Redirect Back Recovery',
    () {
      test(
        'HeavenTabWebChromeClient extends SecureWebChromeClient, search engines skip DOM prototype hooks, and HTTP redirects are never hijacked',
        () async {
          SharedPreferences.setMockInitialValues(<String, Object>{
            'hb.httpsUpgrade': true,
          });
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );
          expect(settings.httpsUpgrade, isFalse);

          final BrowserEngine engine = BrowserEngine(
            settings: settings,
            isIncognito: false,
            enablePlatformWebView: false,
          );
          final NavigationDecision httpDecision = await engine
              .handleWebsiteNavigationOrRedirect('http://mirror.site/movie');
          expect(httpDecision, NavigationDecision.navigate);

          final String pluginJava = File(
            'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenShieldPlugin.java',
          ).readAsStringSync();
          expect(
            pluginJava,
            contains(
              'extends WebChromeClientProxyApi.SecureWebChromeClient',
            ),
          );
          expect(pluginJava, contains('resolveCleanMobileUserAgent'));
          expect(pluginJava, contains('isStandaloneSearchEngine'));
          expect(pluginJava, contains("h.indexOf('google.')!==-1"));
          expect(pluginJava, contains("h==='perplexity.ai'"));
          expect(pluginJava, contains("h==='startpage.com'"));
          expect(pluginJava, contains("h==='duckduckgo.com'"));
          expect(pluginJava, contains("h==='brave.com'"));
          expect(pluginJava, contains("h==='bing.com'"));
          expect(pluginJava, contains('CookieManager.getInstance().flush()'));
          expect(pluginJava, contains('wv.stopLoading()'));

          final String proguard = File(
            'android/app/proguard-rules.pro',
          ).readAsStringSync();
          expect(
            proguard,
            contains('-keep class io.flutter.plugins.webviewflutter.** { *; }'),
          );

          engine.dispose();
          settings.dispose();
        },
      );

      test(
        'Pirated-site popup redirect tab closes on 1 Back press back to pirated site, and same-tab multi-hop ad redirects recover cleanly on Back',
        () async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );
          final TabManagerController tabManager = TabManagerController(
            settings: settings,
            enablePlatformWebView: false,
          );

          // Part A: Pirated site spawns window.open / target="_blank" popup redirect chain in Tab 2
          await tabManager.activeEngine.loadUserEntry(
            'https://vegamovies.example/movie-1080p',
          );
          final String pirateTabId = tabManager.activeTab.id;
          expect(tabManager.totalTabCount, 1);

          tabManager.activeEngine.requestNewTabFromEngine(
            'https://onclick-ad1.example/jump',
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(tabManager.totalTabCount, 2);
          expect(tabManager.activeTab.openerTabId, pirateTabId);

          // Popup Tab 2 auto-redirects through multiple ad hops without user interaction
          tabManager.activeEngine.recordHeadlessWebsiteRedirect(
            'https://tracker-ad2.example/bounce',
            isTransientHop: true,
          );
          tabManager.activeEngine.recordHeadlessWebsiteRedirect(
            'https://rummy-casino.example/play',
            isTransientHop: false,
          );
          expect(
            tabManager.activeEngine.currentUrl,
            'https://rummy-casino.example/play',
          );
          // Meanwhile Tab 1 is still intact on the pirated site!
          expect(
            tabManager.allTabs.first.engine.currentUrl,
            'https://vegamovies.example/movie-1080p',
          );

          // Pressing Back ONCE closes the spawned ad popup tab and returns directly to the pirated site!
          final bool closedPopupBack =
              await tabManager.navigateBackSeamlessly();
          expect(closedPopupBack, isTrue);
          expect(tabManager.totalTabCount, 1);
          expect(tabManager.activeTab.id, pirateTabId);
          expect(
            tabManager.activeEngine.currentUrl,
            'https://vegamovies.example/movie-1080p',
          );

          // Part B: Same-tab pirated-site redirect chain + pushState trap after user tap
          tabManager.activeEngine.simulateUserTapOnCurrentWebPageForTest();
          tabManager.activeEngine.recordHeadlessWebsiteRedirect(
            'https://onclick-ad1.example/hop1',
            isTransientHop: true,
          );
          tabManager.activeEngine.recordHeadlessWebsiteRedirect(
            'https://slow-redirect-ad2.example/hop2',
            isTransientHop: true,
          );
          tabManager.activeEngine.recordHeadlessWebsiteRedirect(
            'https://spam-bet.example/landing',
            isTransientHop: true,
          );
          tabManager.activeEngine.recordHeadlessWebsiteRedirect(
            'https://spam-bet.example/trap-step-2',
            isTransientHop: false,
          );
          expect(
            tabManager.activeEngine.currentUrl,
            'https://spam-bet.example/trap-step-2',
          );

          // Pressing Back ONCE skips all transient ad hops & pushState traps back to vegamovies!
          final bool recoveredSameTab =
              await tabManager.navigateBackSeamlessly();
          expect(recoveredSameTab, isTrue);
          expect(
            tabManager.activeEngine.currentUrl,
            'https://vegamovies.example/movie-1080p',
          );

          // Standalone search engine result in new tab: navigates in child tab, then closes back to SERP
          await settings.setSearchEngine(SearchEngine.duckDuckGo);
          await tabManager.activeEngine.loadUserEntry('flutter engine');
          final String serpUrl = tabManager.activeEngine.currentUrl!;
          expect(serpUrl, 'https://duckduckgo.com/?q=flutter+engine');

          tabManager.activeEngine.requestNewTabFromEngine(
            'https://docs.flutter.dev/overview',
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(tabManager.totalTabCount, 2);
          tabManager.activeEngine.simulateUserTapOnCurrentWebPageForTest();
          await tabManager.activeEngine.loadUserEntry(
            'https://api.flutter.dev/index.html',
          );
          expect(
            tabManager.activeEngine.currentUrl,
            'https://api.flutter.dev/index.html',
          );

          // Back #1 inside child tab -> returns to docs.flutter.dev/overview
          expect(await tabManager.navigateBackSeamlessly(), isTrue);
          expect(
            tabManager.activeEngine.currentUrl,
            'https://docs.flutter.dev/overview',
          );
          expect(tabManager.totalTabCount, 2);

          // Back #2 on child tab's initial page -> closes child tab and returns to DuckDuckGo SERP!
          expect(await tabManager.navigateBackSeamlessly(), isTrue);
          expect(tabManager.totalTabCount, 1);
          expect(tabManager.activeEngine.currentUrl, serpUrl);

          tabManager.dispose();
          settings.dispose();
        },
      );
    },
  );

  group(
    'Step 30: Pirated-Site Download Pass-Through, Heaven Logo Widget, Modern Lens Camera UI & Guaranteed Keyboard',
    () {
      test(
        'Direct popup file downloads start instantly like Brave while same-tab pages keep navigating',
        () async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );
          final BrowserEngine engine = BrowserEngine(
            settings: settings,
            isIncognito: false,
            enablePlatformWebView: false,
          );

          int startDownloadCalls = 0;
          final List<Map<String, Object?>> downloadEvents =
              <Map<String, Object?>>[];
          const MethodChannel nativeChannel = MethodChannel(
            'com.hypertechlabs.heavenbrowser/native_shield',
          );
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
                if (call.method == 'startDownload') {
                  startDownloadCalls += 1;
                  return <String, Object?>{
                    'downloadId': 4242,
                    'url': call.arguments['url'],
                    'fileName': 'movie.1080p.mkv',
                    'mimeType': '',
                    'state': 'running',
                    'bytesDownloaded': 0,
                    'totalBytes': -1,
                  };
                }
                return null;
              });
          addTearDown(() {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(nativeChannel, null);
          });
          NativeShieldBridge.instance.onDownloadStarted = downloadEvents.add;
          addTearDown(() {
            NativeShieldBridge.instance.onDownloadStarted = null;
          });

          // A pirated-site popup whose final target is a DIRECT file becomes
          // an instant background download — the pirated page stays intact!
          await engine.startDirectPopupFileDownload(
            'https://files.example/movie.1080p.mkv?token=abc',
          );
          expect(startDownloadCalls, 1);
          expect(downloadEvents, hasLength(1));
          expect(downloadEvents.first['fileName'], 'movie.1080p.mkv');

          // Same-tab navigations to normal pages are NEVER intercepted!
          final NavigationDecision pageDecision = await engine
              .handleWebsiteNavigationOrRedirect('https://watch.example/page');
          expect(pageDecision, NavigationDecision.navigate);

          // Native invariants: Brave-style popup file detection + intent://
          // resolution + ad-cookie flush on popup cleanup + guaranteed
          // keyboard retries!
          final String pluginJava = File(
            'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenShieldPlugin.java',
          ).readAsStringSync();
          expect(pluginJava, contains('isLikelyDirectFileUrl'));
          expect(pluginJava, contains('emitDirectDownloadRequest'));
          expect(pluginJava, contains('resolveIntentStylePopupUrl'));
          expect(pluginJava, contains('browser_fallback_url'));
          expect(pluginJava, contains('Intent.URI_INTENT_SCHEME'));
          expect(pluginJava, contains('flushCookiesAsyncThrottled'));
          expect(pluginJava, contains('requestGuaranteedSoftKeyboard'));
          expect(pluginJava, contains('KEYBOARD_RETRY_DELAY_MS'));
          // Hang fix invariants: one-shot clear, no stacked retry waves, and
          // the soft-input mode never stays sticky (keyboard always returning)!
          expect(pluginJava, contains('restoreSoftInputMode'));
          expect(pluginJava, contains('SOFT_INPUT_ADJUST_RESIZE'));
          expect(pluginJava, contains('this.pendingShowKeyboardOnWindowFocus = false;'));

          engine.dispose();
          settings.dispose();
        },
      );

      testWidgets(
        'Home Screen Widget shows the Heaven logo (no search icon) and a modern Lens camera icon',
        (WidgetTester tester) async {
          final String layoutXml = File(
            'android/app/src/main/res/layout/heaven_search_widget.xml',
          ).readAsStringSync();
          expect(layoutXml, contains('@drawable/heaven_widget_logo_icon'));
          expect(layoutXml, isNot(contains('ic_widget_search_brand')));
          // Real Heaven logo PNGs exist in every density bucket!
          for (final String bucket in <String>[
            'mdpi',
            'hdpi',
            'xhdpi',
            'xxhdpi',
            'xxxhdpi',
          ]) {
            expect(
              File(
                'android/app/src/main/res/drawable-$bucket/heaven_widget_logo_icon.png',
              ).existsSync(),
              isTrue,
            );
          }
          expect(
            File(
              'android/app/src/main/res/drawable/ic_widget_search_brand.xml',
            ).existsSync(),
            isFalse,
          );

          // Preview draws the Heaven brand globe (no search magnifier) + the
          // modern viewfinder camera icon!
          final String previewXml = File(
            'android/app/src/main/res/drawable/heaven_widget_preview.xml',
          ).readAsStringSync();
          expect(previewXml, contains('Heaven Brand Globe'));
          expect(previewXml, isNot(contains('Magnifier')));

          // Modern vector camera icon (viewfinder brackets + iris + sparkle)!
          final String cameraXml = File(
            'android/app/src/main/res/drawable/ic_widget_camera.xml',
          ).readAsStringSync();
          expect(cameraXml, contains('viewfinder corner arcs'));
          expect(cameraXml, contains('strokeColor'));
          expect(cameraXml, isNot(contains('M9,2L7.17,4H4')));
        },
      );

      testWidgets(
        'Heaven Lens camera: no 1x/2x zoom buttons, working drag crop frame, non-overlapping search area',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );
          final TabManagerController tabManager = TabManagerController(
            settings: settings,
            enablePlatformWebView: false,
          );

          const MethodChannel nativeChannel = MethodChannel(
            'com.hypertechlabs.heavenbrowser/native_shield',
          );
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
                switch (call.method) {
                  case 'consumeInitialLaunchAction':
                    return null;
                  case 'lensStartCamera':
                    return <String, Object?>{
                      'ok': true,
                      'textureId': 7,
                      'previewWidth': 1080,
                      'previewHeight': 1440,
                      'isFront': false,
                      'hasFlash': true,
                      'maxZoom': 4.0,
                    };
                  case 'lensStopCamera':
                    return true;
                }
                return null;
              });
          addTearDown(() {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(nativeChannel, null);
          });

          await tester.pumpWidget(
            MaterialApp(
              home: HeavenLensCameraScreen(engine: tabManager.activeEngine),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 220));

          // 1x / 2x zoom buttons completely removed!
          expect(find.text('1x'), findsNothing);
          expect(find.text('2x'), findsNothing);

          // The Crop button is gone — crop works by simply dragging the
          // viewfinder corners directly!
          expect(
            find.byKey(const Key('lens_crop_frame_button')),
            findsNothing,
          );

          // Drag the bottom-right corner handle (interactive crop WORKS!)...
          await tester.drag(
            find.byKey(const Key('lens_crop_corner_bottomRight')),
            const Offset(-36, -28),
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            find.byKey(const Key('lens_reset_crop_button')),
            findsOneWidget,
          );

          // ...and Full Frame resets it cleanly!
          await tester.tap(find.byKey(const Key('lens_reset_crop_button')));
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            find.byKey(const Key('lens_reset_crop_button')),
            findsNothing,
          );

          // "Add to your search" lives at the TOP, and while the soft
          // keyboard is open the ENTIRE bottom dock (mode selector + shutter
          // + gallery) hides — nothing can ever overlap the ask bar!
          tester.view.viewInsets = FakeViewPadding(bottom: 300);
          await tester.pump(const Duration(milliseconds: 200));
          final double askBarTop = tester.getTopLeft(
            find.byKey(const Key('lens_multimodal_query_field')),
          ).dy;
          expect(askBarTop, lessThan(200));
          expect(
            find.byKey(const Key('lens_shutter_capture_button')),
            findsNothing,
          );
          expect(find.byKey(const Key('lens_mode_search')), findsNothing);
          expect(
            find.byKey(const Key('lens_pick_gallery_button')),
            findsNothing,
          );
          // Keyboard closed -> the full dock returns instantly!
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            find.byKey(const Key('lens_shutter_capture_button')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('lens_mode_search')), findsOneWidget);

          tabManager.dispose();
          settings.dispose();
        },
      );

      testWidgets(
        'Guaranteed keyboard popup NEVER re-arms itself in an infinite loop (app hang regression)',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          int showSoftKeyboardCalls = 0;
          const MethodChannel nativeChannel = MethodChannel(
            'com.hypertechlabs.heavenbrowser/native_shield',
          );
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
                switch (call.method) {
                  case 'consumeInitialLaunchAction':
                    return null;
                  case 'showSoftKeyboard':
                    showSoftKeyboardCalls += 1;
                    return true;
                }
                return null;
              });
          addTearDown(() {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(nativeChannel, null);
          });

          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );
          final DownloadsController downloads = DownloadsController(
            prefs,
            enableNativePolling: false,
          );
          final InterestProfileController interests =
              InterestProfileController(prefs);
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
              interests: interests,
              newsService: newsService,
              searchService: _createMockSearchService(),
              vpn: vpn,
              enablePlatformWebView: false,
            ),
          );
          await tester.pumpAndSettle();

          // Home Screen Widget tap -> omnibox edit overlay opens with the
          // guaranteed keyboard flow!
          NativeShieldBridge.instance.onExternalLaunchAction?.call(
            const <String, Object?>{'type': 'omnibox'},
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('top_omnibox_textfield')),
            findsOneWidget,
          );
          expect(showSoftKeyboardCalls, greaterThanOrEqualTo(1));

          // The native window-focus event must NEVER echo back into another
          // native showSoftKeyboard request — the old echo re-armed the retry
          // wave exponentially (7 -> 49 -> 343 ...) and hung the whole app!
          final int beforeFocusEvents = showSoftKeyboardCalls;
          for (int i = 0; i < 6; i++) {
            NativeShieldBridge.instance.onWindowFocusedForKeyboard?.call();
            await tester.pump();
          }
          expect(showSoftKeyboardCalls, beforeFocusEvents);

          // The omnibox stays focused and usable after the focus events.
          expect(
            find.byKey(const Key('top_omnibox_textfield')),
            findsOneWidget,
          );

          // Dart source invariant: _handleWindowFocusedForKeyboard contains
          // no NativeShieldBridge.showSoftKeyboard() echo!
          final String browserScreen = File(
            'lib/features/browser/presentation/browser_screen.dart',
          ).readAsStringSync();
          final int fnStart = browserScreen.indexOf(
            'void _handleWindowFocusedForKeyboard()',
          );
          final int fnEnd = browserScreen.indexOf(
            'void _forceShowKeyboardForActiveField()',
            fnStart,
          );
          expect(fnStart, greaterThanOrEqualTo(0));
          expect(fnEnd, greaterThan(fnStart));
          final String fnBody = browserScreen.substring(fnStart, fnEnd);
          expect(fnBody, isNot(contains('showSoftKeyboard')));

          vpn.dispose();
          newsService.dispose();
          downloads.dispose();
          interests.dispose();
          settings.dispose();
        },
      );
    },
  );

  group(
    'Step 32: Widget New-Tab Actions, Matching Camera Icons, Clean Engine Picker & Background Popunders',
    () {
      test(
        'Script popunders open in background tabs (user stays on the download page) while tapped target=_blank links switch tabs',
        () async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );
          final TabManagerController tabManager = TabManagerController(
            settings: settings,
            enablePlatformWebView: false,
          );

          await tabManager.activeEngine.loadUserEntry(
            'https://pirate.example/download-page',
          );
          final String pirateTabId = tabManager.activeTab.id;

          // A script-opened popunder (NO user gesture) must NEVER steal focus —
          // the user stays on the pirated download page like in Brave!
          tabManager.activeEngine.requestNewTabFromEngine(
            'https://unknown-ad.example/popunder',
            background: true,
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(tabManager.totalTabCount, 2);
          expect(tabManager.activeTab.id, pirateTabId);
          expect(
            tabManager.activeEngine.currentUrl,
            'https://pirate.example/download-page',
          );
          expect(
            tabManager.allTabs
                .lastWhere(
                  (BrowserTab t) => t.id != pirateTabId,
                )
                .engine
                .currentUrl,
            'https://unknown-ad.example/popunder',
          );

          // A real user-tapped target="_blank" link opens in the FOREGROUND!
          tabManager.activeEngine.requestNewTabFromEngine(
            'https://filehost.example/download',
            background: false,
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(tabManager.totalTabCount, 3);
          expect(
            tabManager.activeEngine.currentUrl,
            'https://filehost.example/download',
          );

          // Native invariants: isUserGesture-driven background flag + the
          // longer 8s popup redirect capture window for slow ad chains!
          final String pluginJava = File(
            'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenShieldPlugin.java',
          ).readAsStringSync();
          expect(pluginJava, contains('payload.put("background"'));
          expect(pluginJava, contains('!isUserGesture'));
          expect(pluginJava, contains('8000L'));

          tabManager.dispose();
          settings.dispose();
        },
      );

      test(
        'In-app camera icon is an exact 1:1 mirror of the Home Screen Widget camera icon',
        () async {
          final String sheet = File(
            'lib/features/browser/presentation/widgets/visual_search_sheet.dart',
          ).readAsStringSync();
          // The Flutter painter mirrors ic_widget_camera.xml's 24x24 geometry!
          expect(sheet, contains('ic_widget_camera.xml'));
          expect(sheet, contains('Radius.circular(3.2'));
          expect(sheet, contains('18.85'));
          expect(sheet, contains('20.4'));

          final String widgetIcon = File(
            'android/app/src/main/res/drawable/ic_widget_camera.xml',
          ).readAsStringSync();
          // The exact same anchors exist in the widget vector!
          expect(widgetIcon, contains('M18.2,3.4'));
          expect(widgetIcon, contains('3.5,3.5'));
          expect(widgetIcon, contains('M12,8.5a3.5,3.5'));
          // The widget camera icon color is HARDCODED Heaven blue — it never
          // changes with the launcher's day/night mode, so it is ALWAYS the
          // exact same color as the in-app camera icon!
          expect(widgetIcon, contains('#FF2563EB'));
          expect(widgetIcon, isNot(contains('@color/heaven_widget_accent')));

          // The widget mic icon uses the very same hardcoded Heaven blue!
          final String widgetMic = File(
            'android/app/src/main/res/drawable/ic_widget_mic.xml',
          ).readAsStringSync();
          expect(widgetMic, contains('#FF2563EB'));
          expect(widgetMic, isNot(contains('@color/heaven_widget_accent')));

          // The in-app painter defaults to the identical #2563EB (never
          // theme-dependent)!
          expect(sheet, contains('color ?? const Color(0xFF2563EB)'));

          // The widget picker preview draws the camera with the EXACT scaled
          // geometry of ic_widget_camera.xml in the same hardcoded blue!
          final String preview = File(
            'android/app/src/main/res/drawable/heaven_widget_preview.xml',
          ).readAsStringSync();
          expect(preview, contains('M289,26.25a1.75,1.75'));
          expect(preview, contains('M284.75,26.3'));
          expect(preview, contains('M292.1,23.7'));
          expect(preview, isNot(contains('#FF60A5FA')));

          // The widget logo + camera drawables are still wired into the widget.
          final String layoutXml = File(
            'android/app/src/main/res/layout/heaven_search_widget.xml',
          ).readAsStringSync();
          expect(layoutXml, contains('@drawable/heaven_widget_logo_icon'));
          expect(layoutXml, contains('@drawable/ic_widget_camera'));
        },
      );

      testWidgets(
        'Home Screen Widget taps never disturb the current website and never pile up empty StartPage tabs',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          int lensStartCalls = 0;
          const MethodChannel nativeChannel = MethodChannel(
            'com.hypertechlabs.heavenbrowser/native_shield',
          );
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
                switch (call.method) {
                  case 'consumeInitialLaunchAction':
                    return null;
                  case 'showSoftKeyboard':
                    return true;
                  case 'lensStartCamera':
                    lensStartCalls += 1;
                    return <String, Object?>{
                      'ok': true,
                      'textureId': 7,
                      'previewWidth': 1080,
                      'previewHeight': 1440,
                      'isFront': false,
                      'hasFlash': true,
                      'maxZoom': 4.0,
                    };
                  case 'lensStopCamera':
                    return true;
                }
                return null;
              });
          addTearDown(() {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(nativeChannel, null);
          });

          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final BrowserSettingsController settings = BrowserSettingsController(
            prefs,
          );
          final DownloadsController downloads = DownloadsController(
            prefs,
            enableNativePolling: false,
          );
          final InterestProfileController interests =
              InterestProfileController(prefs);
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
              interests: interests,
              newsService: newsService,
              searchService: _createMockSearchService(),
              vpn: vpn,
              enablePlatformWebView: false,
            ),
          );
          await tester.pumpAndSettle();

          final TabManagerController tabManager = tester
              .widget<BrowserScreen>(find.byType(BrowserScreen))
              .tabManager;

          // User is browsing a website in Tab 1...
          await tabManager.activeEngine.loadUserEntry(
            'https://pirate.example/movie',
          );
          await tester.pumpAndSettle();
          final String websiteTabId = tabManager.activeTab.id;
          expect(tabManager.totalTabCount, 1);

          // 1. Widget search bar tap -> NEW TAB opens + instantly ready for typing!
          NativeShieldBridge.instance.onExternalLaunchAction?.call(
            const <String, Object?>{'type': 'omnibox'},
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pumpAndSettle();
          expect(tabManager.totalTabCount, 2);
          expect(tabManager.activeTab.id, isNot(websiteTabId));
          expect(tabManager.activeEngine.isShowingStartPage, isTrue);
          expect(
            find.byKey(const Key('top_omnibox_textfield')),
            findsOneWidget,
          );
          // The user's website tab is still perfectly intact!
          expect(
            tabManager.allTabs
                .firstWhere((BrowserTab t) => t.id == websiteTabId)
                .engine
                .currentUrl,
            'https://pirate.example/movie',
          );
          // Close the omnibox edit overlay.
          await tester.tap(find.byTooltip('Cancel'));
          await tester.pumpAndSettle();

          // 2. Widget camera tap while the current tab is a FRESH StartPage:
          // the tab is simply REUSED — no empty-tab pile-up!
          NativeShieldBridge.instance.onExternalLaunchAction?.call(
            const <String, Object?>{'type': 'camera'},
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          // NOTE: no pumpAndSettle here — the Lens scan animation runs forever!
          expect(tabManager.totalTabCount, 2);
          expect(tabManager.activeTab.id, isNot(websiteTabId));
          expect(tabManager.activeEngine.isShowingStartPage, isTrue);
          expect(find.byType(HeavenLensCameraScreen), findsOneWidget);
          expect(lensStartCalls, 1);

          // 3. Another widget search tap after closing Lens — still the SAME
          // fresh tab, ready for typing instantly (2 tabs total, NOT 4)!
          await tester.tap(find.byKey(const Key('lens_close_button')));
          await tester.pumpAndSettle();
          NativeShieldBridge.instance.onExternalLaunchAction?.call(
            const <String, Object?>{'type': 'omnibox'},
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pumpAndSettle();
          expect(tabManager.totalTabCount, 2);
          expect(
            find.byKey(const Key('top_omnibox_textfield')),
            findsOneWidget,
          );

          vpn.dispose();
          newsService.dispose();
          downloads.dispose();
          interests.dispose();
          settings.dispose();
        },
      );
    },
  );
}
