import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heavenbrowser/core/constants/app_constants.dart';
import 'package:heavenbrowser/core/l10n/app_strings.dart';
import 'package:heavenbrowser/core/theme/app_theme.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/features/browser/page_translate_reader_service.dart';
import 'package:heavenbrowser/features/browser/presentation/browser_screen.dart';
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
import 'package:heavenbrowser/features/shield/heaven_shield_screen.dart';
import 'package:heavenbrowser/features/shield/native_shield_bridge.dart';
import 'package:heavenbrowser/features/tabs/tab_manager.dart';
import 'package:heavenbrowser/features/tabs/tabs_screen.dart';
import 'package:heavenbrowser/features/vpn/vpn_controller.dart';
import 'package:heavenbrowser/features/vpn/vpn_screen.dart';
import 'package:heavenbrowser/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
        'Home Discover dynamically adapts country tab & localized RSS queries to user locale (US, UK, Germany, Japan, India)',
        () async {
          addTearDown(() {
            DiscoverRegionConfig.debugLocaleOverride = null;
          });

          DiscoverRegionConfig.debugLocaleOverride = const Locale('en', 'US');
          expect(DiscoverRegionConfig.detect().countryCode, 'US');
          expect(
            NewsCategoryTab.localCountry.resolvedLabel(),
            'United States',
          );

          DiscoverRegionConfig.debugLocaleOverride = const Locale('en', 'GB');
          expect(DiscoverRegionConfig.detect().countryCode, 'GB');
          expect(
            NewsCategoryTab.localCountry.resolvedLabel(),
            'United Kingdom',
          );

          DiscoverRegionConfig.debugLocaleOverride = const Locale('de', 'DE');
          expect(DiscoverRegionConfig.detect().countryCode, 'DE');
          expect(NewsCategoryTab.localCountry.resolvedLabel(), 'Germany');

          DiscoverRegionConfig.debugLocaleOverride = const Locale('ja', 'JP');
          expect(DiscoverRegionConfig.detect().countryCode, 'JP');
          expect(NewsCategoryTab.localCountry.resolvedLabel(), 'Japan');

          DiscoverRegionConfig.debugLocaleOverride = const Locale('en', 'IN');
          expect(DiscoverRegionConfig.detect().countryCode, 'IN');
          expect(NewsCategoryTab.localCountry.resolvedLabel(), 'India');
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

        // Verify Heaven Shield default customizable state
        expect(settings.shieldEnabled, isTrue);
        expect(settings.shieldMode, HeavenShieldMode.standard);
        expect(settings.shieldBlockAds, isTrue);
        expect(settings.shieldBlockCookieBanners, isTrue);
        expect(settings.shieldCleanUrls, isTrue);
        expect(settings.shieldAntiFingerprinting, isTrue);
        expect(settings.shieldBlockPopups, isTrue);

        // Verify URL tracking parameter stripping preserves genuine query params
        final Uri dirty = Uri.parse(
          'https://example.com/search?q=flutter&utm_source=twitter&fbclid=xyz123&page=2&gclid=abc',
        );
        final Uri cleaned = BrowserSettingsController.stripTrackingParameters(
          dirty,
        );
        expect(cleaned.toString(), 'https://example.com/search?q=flutter&page=2');

        // Verify per-site exceptions & subdomain matching
        expect(settings.isShieldActiveForHost('example.org'), isTrue);
        await settings.addShieldDisabledHost('https://www.example.org/news');
        expect(settings.shieldDisabledHosts, contains('example.org'));
        expect(settings.isShieldActiveForHost('example.org'), isFalse);
        expect(settings.isShieldActiveForHost('sub.example.org'), isFalse);
        await settings.removeShieldDisabledHost('example.org');
        expect(settings.isShieldActiveForHost('example.org'), isTrue);

        // Verify Strict mode + Restore Defaults
        await settings.setShieldMode(HeavenShieldMode.strict);
        await settings.setShieldBlockAds(false);
        expect(settings.shieldMode, HeavenShieldMode.strict);
        expect(settings.shieldBlockAds, isFalse);
        await settings.resetHeavenShieldDefaults();
        expect(settings.shieldMode, HeavenShieldMode.standard);
        expect(settings.shieldBlockAds, isTrue);

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
      int shieldTotalBlocked = 14;

      DiscoverRegionConfig.debugLocaleOverride = const Locale('en', 'GB');
      addTearDown(() {
        DiscoverRegionConfig.debugLocaleOverride = null;
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
            switch (call.method) {
              case 'createHomeScreenShortcut':
                capturedShortcutArgs = call.arguments as Map<Object?, Object?>?;
                return true;
              case 'getHeavenShieldStats':
                return <String, Object>{
                  'pageBlocked': 4,
                  'totalBlocked': shieldTotalBlocked,
                  'enabled': true,
                };
              case 'resetHeavenShieldStats':
                shieldTotalBlocked = 0;
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

      // 1. Dynamic Country in Home Discover shows 'United Kingdom' (en_GB) & ZERO Shield UI exists
      expect(
        find.byKey(const Key('discover_tab_localCountry')),
        findsOneWidget,
      );
      expect(find.text('United Kingdom'), findsOneWidget);
      expect(find.byKey(const Key('omnibox_shield_badge_button')), findsNothing);

      // 2. Submit search -> resolves to Google Search; scrolling down glides floating search bar upward WITH ZERO WEBSITE PULL (viewport Rect stays 100% constant!)
      await tester.enterText(
        find.byKey(const Key('home_search_textfield')),
        'flutter',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('home_search_icon_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('google.com'), findsWidgets);

      final Finder viewportStack = find.byType(IndexedStack);
      final Finder pillFinder = find.byKey(const Key('omnibox_display_pill'));
      final Rect viewportBefore = tester.getRect(viewportStack);
      final double pillTopBefore = tester.getTopLeft(pillFinder).dy;

      // Trigger downward scroll -> bar glides upward via SlideTransition while viewport Rect NEVER shifts or resizes!
      tabManager.activeEngine.handleWebScrollDelta(140, 60);
      expect(tabManager.activeEngine.isNavBarVisible, isFalse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.getRect(viewportStack), equals(viewportBefore));
      final double pillTopMidHide = tester.getTopLeft(pillFinder).dy;
      expect(pillTopMidHide, lessThan(pillTopBefore - 4.0));
      await tester.pumpAndSettle();
      expect(tester.getRect(viewportStack), equals(viewportBefore));
      expect(tester.getTopLeft(pillFinder).dy, lessThan(-20.0));

      // Trigger upward scroll -> bar glides smoothly back down while viewport Rect remains 100% stationary!
      tabManager.activeEngine.handleWebScrollDelta(80, -35);
      expect(tabManager.activeEngine.isNavBarVisible, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(viewportStack), equals(viewportBefore));
      await tester.pumpAndSettle();
      expect(tester.getRect(viewportStack), equals(viewportBefore));
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

      // 4. Address-bar Translate & Reader button opens Instant Page Translate + Clean Reader Sheet (NO Permission Grid / NO Brave Shields!)
      await tester.tap(find.byKey(const Key('translate_reader_button')));
      await tester.pumpAndSettle();
      expect(find.byType(TranslateReaderSheet), findsOneWidget);
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

      // Open Clean Reader Mode directly from TranslateReaderSheet!
      await tester.tap(find.byKey(const Key('open_clean_reader_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clean_reader_view_modal')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // 4b. Tap top-bar Heaven Shield icon -> Quick Sheet -> open full Heaven Shield settings & customize!
      expect(find.byKey(const Key('top_bar_shield_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('top_bar_shield_button')));
      await tester.pumpAndSettle();
      expect(find.byType(HeavenShieldQuickSheet), findsOneWidget);
      expect(find.byKey(const Key('quick_shield_site_switch')), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick_shield_customize_button')));
      await tester.pumpAndSettle();

      expect(find.byType(HeavenShieldScreen), findsOneWidget);
      expect(
        find.byKey(const Key('heaven_shield_blocked_counter')),
        findsOneWidget,
      );
      expect(find.textContaining('Blocked: 14'), findsOneWidget);

      // Switch to Strict mode & toggle Popup Guard off, then add a site exception
      await tester.tap(find.byKey(const Key('heaven_shield_mode_strict')));
      await tester.pumpAndSettle();
      expect(settings.shieldMode, HeavenShieldMode.strict);

      await tester.scrollUntilVisible(
        find.byKey(const Key('heaven_shield_add_exception_button')),
        140,
        scrollable: find
            .descendant(
              of: find.byType(HeavenShieldScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('heaven_shield_add_exception_button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('heaven_shield_exception_input')),
        'example.org',
      );
      await tester.tap(
        find.byKey(const Key('heaven_shield_exception_save_button')),
      );
      await tester.pumpAndSettle();
      expect(settings.isShieldActiveForHost('example.org'), isFalse);

      // Restore recommended defaults resets Strict -> Standard and clears exceptions
      await tester.scrollUntilVisible(
        find.byKey(const Key('heaven_shield_restore_defaults_button')),
        140,
        scrollable: find
            .descendant(
              of: find.byType(HeavenShieldScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('heaven_shield_restore_defaults_button')),
      );
      await tester.pumpAndSettle();
      expect(settings.shieldMode, HeavenShieldMode.standard);
      expect(settings.isShieldActiveForHost('example.org'), isTrue);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // Verify 3-dots Browser Menu has Heaven Shield (and NO Web Store!)
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('browser_menu_translate_reader_tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('browser_menu_shield_tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('browser_menu_web_store_tile')),
        findsNothing,
      );
      Navigator.of(tester.element(find.byType(BrowserScreen))).pop();
      await tester.pumpAndSettle();

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
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Ultra Data Saver'), findsNothing);
      expect(
        find.byKey(const Key('settings_brave_shields_switch')),
        findsNothing,
      );
      expect(find.byKey(const Key('settings_farbling_switch')), findsNothing);
      expect(find.byKey(const Key('settings_web_store_tile')), findsNothing);
      expect(
        find.byKey(const Key('settings_heaven_shield_tile')),
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

        final String shieldJava = File(
          'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenShieldPlugin.java',
        ).readAsStringSync();
        expect(shieldJava.contains('setWebChromeClient'), isFalse);
        expect(shieldJava.contains('ShieldWebChromeClient'), isFalse);
        expect(shieldJava.contains('HeavenBraveShieldEngine'), isFalse);
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
        expect(shieldJava.contains('HeavenShieldEngine'), isTrue);
        expect(shieldJava.contains('getHeavenShieldStats'), isTrue);
        expect(shieldJava.contains('resetHeavenShieldStats'), isTrue);
        expect(shieldJava.contains('FLAG_DEBUGGABLE'), isTrue);
        expect(shieldJava.contains('setOffscreenPreRaster(true)'), isTrue);
        expect(shieldJava.contains('LAYER_TYPE_HARDWARE'), isTrue);
        expect(shieldJava.contains('focusWebView'), isTrue);
        expect(shieldJava.contains('addDocumentStartJavaScript'), isTrue);
        expect(shieldJava.contains('window.__hbInBg'), isTrue);
        expect(shieldJava.contains('onWebScrollNavBar'), isTrue);
        expect(shieldJava.contains('bgKeepAliveLoop'), isTrue);

        final String shieldEngineJava = File(
          'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenShieldEngine.java',
        ).readAsStringSync();
        expect(shieldEngineJava.contains('interceptSubresource'), isTrue);
        expect(shieldEngineJava.contains('shouldBlockDomain'), isTrue);
        expect(
          shieldEngineJava.contains('getCompiledDocumentStartBundle'),
          isTrue,
        );
        expect(shieldEngineJava.contains('__hb_top_safe_css'), isTrue);
        expect(
          shieldEngineJava.contains('io.flutter.plugin.common.MethodChannel'),
          isFalse,
        );

        final String mainKt = File(
          'android/app/src/main/kotlin/com/hypertechlabs/heavenbrowser/MainActivity.kt',
        ).readAsStringSync();
        expect(mainKt.contains('enableHighestRefreshRate'), isTrue);
        expect(mainKt.contains('preferredDisplayModeId'), isTrue);

        final String vpnJava = File(
          'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenVpnManager.java',
        ).readAsStringSync();
        expect(vpnJava.contains('normalizeEndpointPort'), isTrue);
        expect(vpnJava.contains('waitForWireGuardPeerHandshake'), isTrue);
        expect(vpnJava.contains('normalizeVpnGateOvpnForOpenSsl3'), isTrue);
        expect(vpnJava.contains('extractRiseupOpenVpnPorts'), isTrue);
        expect(vpnJava.contains('DEFAULT:@SECLEVEL=0'), isTrue);

        final String proguardRules = File(
          'android/app/proguard-rules.pro',
        ).readAsStringSync();
        expect(proguardRules.contains('-keep class com.wireguard.**'), isTrue);

        final String appGradle = File(
          'android/app/build.gradle.kts',
        ).readAsStringSync();
        expect(appGradle.contains('proguard-rules.pro'), isTrue);
        expect(appGradle.contains('useLegacyPackaging = true'), isTrue);

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
          manifestXml.contains('com.wireguard.android.backend.GoBackend\$VpnService'),
          isTrue,
        );
        expect(manifestXml.contains('systemExempted'), isTrue);
        expect(manifestXml.contains('android.permission.USE_BIOMETRIC'), isTrue);
      },
    );
  });
}
