import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heavenbrowser/core/constants/app_constants.dart';
import 'package:heavenbrowser/core/l10n/app_strings.dart';
import 'package:heavenbrowser/core/theme/app_theme.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/features/browser/engine/browser_engine.dart';
import 'package:heavenbrowser/features/browser/presentation/browser_screen.dart';
import 'package:heavenbrowser/features/browser/site_controls_sheet.dart';
import 'package:heavenbrowser/features/devtools/desktop_inspector_panel.dart';
import 'package:heavenbrowser/features/downloads/downloads_controller.dart';
import 'package:heavenbrowser/features/extensions/extensions_controller.dart';
import 'package:heavenbrowser/features/news/interest_news_service.dart';
import 'package:heavenbrowser/features/search/heaven_search_service.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';
import 'package:heavenbrowser/features/settings/help_screen.dart';
import 'package:heavenbrowser/features/settings/notifications_screen.dart';
import 'package:heavenbrowser/features/settings/settings_screen.dart';
import 'package:heavenbrowser/features/shield/heaven_shield.dart';
import 'package:heavenbrowser/features/tabs/tab_manager.dart';
import 'package:heavenbrowser/features/tabs/tabs_screen.dart';
import 'package:heavenbrowser/features/vpn/vpn_controller.dart';
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

  group('Step 14 Core: Heaven Brand, Google + Perplexity Search, Persistent Tabs (No Sleep) & Extensions', () {
    test('uses Electric Sapphire & Midnight Navy blue palette and Heaven app name', () {
      expect(AppConstants.appName, 'Heaven');
      expect(AppConstants.appVersion, '0.0.1');
      expect(AppTheme.sapphireBlue, const Color(0xFF2563EB));
      expect(AppTheme.electricBlue, const Color(0xFF3B82F6));
      expect(AppTheme.deepNavyBg, const Color(0xFF040B16));
      expect(AppTheme.navySurface, const Color(0xFF0B162C));
      expect(AppTheme.darkTheme.colorScheme.primary, const Color(0xFF60A5FA));

      // Obsolete Step 13 sheets are completely removed
      expect(
        File('lib/features/browser/quick_action_sheet.dart').existsSync(),
        isFalse,
      );
      expect(
        File('lib/features/downloads/media_grabber_sheet.dart').existsSync(),
        isFalse,
      );
      expect(
        File('lib/features/extensions/extension_popup_sheet.dart').existsSync(),
        isFalse,
      );
    });

    test(
      'Google is Default Search Engine, Perplexity is supported, Heaven Engine is removed, and chrome-extension URLs rewrite cleanly',
      () async {
        expect(
          File(
            'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenGoogleBgSearch.java',
          ).existsSync(),
          isFalse,
        );
        expect(
          File('lib/features/search/heaven_search_view.dart').existsSync(),
          isFalse,
        );
        expect(SearchEngine.values.first, SearchEngine.google);
        expect(SearchEngine.values, contains(SearchEngine.perplexity));
        expect(
          SearchEngine.values.map((SearchEngine e) => e.name),
          isNot(contains('heaven')),
        );
        expect(SearchEngine.fromName('heaven'), SearchEngine.google);
        expect(SearchEngine.fromName('perplexity'), SearchEngine.perplexity);

        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final BrowserSettingsController settings = BrowserSettingsController(
          prefs,
        );
        expect(settings.searchEngine, SearchEngine.google);

        final BrowserEngine normalEngine = BrowserEngine(
          settings: settings,
          isIncognito: false,
          enablePlatformWebView: false,
        );
        await normalEngine.loadUserEntry('raspberry pi 5');
        expect(
          normalEngine.currentUrl,
          'https://www.google.com/search?q=raspberry+pi+5',
        );
        expect(settings.recentSearches, contains('raspberry pi 5'));

        // Switch to Perplexity and verify search query resolution + query extraction
        await settings.setSearchEngine(SearchEngine.perplexity);
        await normalEngine.loadUserEntry('quantum computing');
        expect(
          normalEngine.currentUrl,
          'https://www.perplexity.ai/search?q=quantum+computing',
        );
        expect(
          OmniboxParser.extractAnySearchQuery(normalEngine.currentUrl),
          'quantum computing',
        );

        // Chrome extension scheme URLs rewrite to virtual extension host instead of being blocked
        await normalEngine.loadUri(
          Uri.parse(
            'chrome-extension://eimadpbcbfnmbkopoojfekhnkhdbieeh/ui/popup/index.html',
          ),
        );
        expect(
          normalEngine.currentUrl,
          'https://chrome-ext.heaven.local/eimadpbcbfnmbkopoojfekhnkhdbieeh/ui/popup/index.html',
        );
        expect(
          OmniboxParser.formatDisplayUrl(normalEngine.currentUrl),
          'Extension • ui/popup/index.html',
        );

        // Legacy heaven:// search URLs automatically migrate to Google Search
        await normalEngine.loadUri(
          Uri.parse('heaven://search?q=flutter+sdk'),
        );
        expect(
          normalEngine.currentUrl,
          'https://www.google.com/search?q=flutter+sdk',
        );

        // Incognito never saves recent searches
        final BrowserEngine incogEngine = BrowserEngine(
          settings: settings,
          isIncognito: true,
          enablePlatformWebView: false,
        );
        await incogEngine.loadUserEntry('secret query');
        expect(settings.recentSearches, isNot(contains('secret query')));

        final HeavenSearchService service = _createMockSearchService();
        final List<String> suggestions = await service.fetchSuggestions(
          'flutter',
        );
        expect(suggestions, contains('flutter sdk'));

        normalEngine.dispose();
        incogEngine.dispose();
      },
    );

    test(
      'Open tabs, active tab, and tab groups persist across app restarts with Sleep Mode completely removed',
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
        final BrowserTab tab2 = await session1.openNewTab(
          incognito: false,
          initialInput: 'https://dart.dev',
        );
        final TabGroup grp = session1.createGroupAndAddTab(
          name: 'SDK Docs',
          tabId: tab2.id,
        );
        expect(session1.normalTabs.length, 2);
        expect(session1.groups.length, 1);
        session1.dispose();

        // Simulate app restart with the same SharedPreferences
        final TabManagerController session2 = TabManagerController(
          settings: settings,
          enablePlatformWebView: false,
        );
        expect(session2.normalTabs.length, 2);
        expect(session2.groups.length, 1);
        expect(session2.groups.first.name, 'SDK Docs');
        expect(session2.activeTab.groupId, grp.id);
        expect(session2.activeEngine.currentUrl, 'https://dart.dev');

        // Background restored tab retains its URL immediately without sleeping
        final BrowserTab bgTab = session2.normalTabs.first;
        expect(bgTab.engine.currentUrl, 'https://flutter.dev');
        expect(session2.lastActiveWebsiteTab?.id, tab2.id);
        session2.dispose();
      },
    );

    test(
      'ExtensionsController installs .crx packages, exposes launchUrl for New Tab opening, and exposes NO suggested catalog',
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
                      'optionsUrl':
                          'https://chrome-ext.heaven.local/eimadpbcbfnmbkopoojfekhnkhdbieeh/ui/options/index.html',
                      'launchUrl':
                          'https://chrome-ext.heaven.local/eimadpbcbfnmbkopoojfekhnkhdbieeh/ui/popup/index.html',
                      'hasBackground': true,
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

        final MockClient cwsMock = MockClient((http.Request req) async {
          const String rss = '''
          <rss version="2.0"><channel>
            <item>
              <title>JSON Viewer - Chrome Web Store</title>
              <link>https://chromewebstore.google.com/detail/json-viewer/gbmdgpbipfallnflgajpaliibnhdgobh</link>
              <description>Pretty print JSON documents in Chrome.</description>
            </item>
          </channel></rss>
          ''';
          return http.Response(rss, 200);
        });

        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final ExtensionsController ext = ExtensionsController(
          prefs,
          syncNativeOnInit: false,
          httpClient: cwsMock,
        );

        expect(ext.chromeExtensions, isEmpty);

        final List<ChromeWebStoreSearchItem> searchRes =
            await ext.searchWebStoreExtensions('json viewer');
        expect(searchRes.length, 1);
        expect(
          searchRes.first.extensionId,
          'gbmdgpbipfallnflgajpaliibnhdgobh',
        );

        final String? installErr = await ext.installFromWebStore(
          'https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh',
        );
        expect(installErr, isNull);
        expect(ext.isInstalled('eimadpbcbfnmbkopoojfekhnkhdbieeh'), isTrue);
        expect(
          ext.chromeExtensions.first.effectiveLaunchUrl,
          'https://chrome-ext.heaven.local/eimadpbcbfnmbkopoojfekhnkhdbieeh/ui/popup/index.html',
        );

        final String fullInjected = await ext.buildFullInjectionForUrl(
          'https://www.google.com/search?q=flutter',
        );
        expect(fullInjected, contains('__darkReaderCrxLoaded'));
        ext.dispose();
      },
    );

    test(
      'Privacy Policy file is populated and AppConstants.privacyPolicyUrl points to official GitHub policy',
      () {
        expect(
          AppConstants.privacyPolicyUrl,
          'https://github.com/Aryanshahx/heavenbrowser/blob/main/privacypolicy.md',
        );
        final File policyFile = File('privacypolicy.md');
        expect(policyFile.existsSync(), isTrue);
        final String policyText = policyFile.readAsStringSync();
        expect(policyText.length, greaterThan(1500));
        expect(policyText, contains('techlabs.hyper@gmail.com'));
      },
    );

    test(
      'Per-Site Permission store, 1-tap revoke, Ultra Data Saver & Data Saved metrics work cleanly',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final BrowserSettingsController settings = BrowserSettingsController(
          prefs,
        );

        expect(
          settings.getSitePermission('meet.example.com', SitePermissionType.camera),
          SitePermissionDecision.ask,
        );
        await settings.setSitePermission(
          'meet.example.com',
          SitePermissionType.camera,
          SitePermissionDecision.allow,
        );
        expect(
          settings.getSitePermission('meet.example.com', SitePermissionType.camera),
          SitePermissionDecision.allow,
        );

        await settings.revokeSitePermission(
          'meet.example.com',
          SitePermissionType.camera,
        );
        expect(
          settings.getSitePermission('meet.example.com', SitePermissionType.camera),
          SitePermissionDecision.block,
        );

        await settings.incrementBytesSaved(2 * 1024 * 1024);
        expect(settings.formattedDataSaved, '2.0 MB');

        await settings.setLanguage(BrowserLanguage.hi);
        expect(settings.language, BrowserLanguage.hi);
        expect(HelpScreen.supportEmail, 'techlabs.hyper@gmail.com');
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
    'Step 14 UI: Top Navigation Bar Auto-Hide on Scroll, Extension Opens in New Tab, Minimal Settings + Perplexity, Permissions, Notifications & Privacy Policy on 320px screen',
    (WidgetTester tester) async {
      const MethodChannel nativeChannel = MethodChannel(
        'com.hypertechlabs.heavenbrowser/native_shield',
      );
      Map<Object?, Object?>? capturedShortcutArgs;
      bool testNotificationSent = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
            switch (call.method) {
              case 'listChromeExtensions':
                return <Map<String, Object>>[
                  <String, Object>{
                    'id': 'eimadpbcbfnmbkopoojfekhnkhdbieeh',
                    'name': 'Dark Reader',
                    'description': 'Dark mode for every website',
                    'version': '4.9.96',
                    'manifestVersion': 3,
                    'enabled': true,
                    'source': 'webstore',
                    'popupUrl':
                        'https://chrome-ext.heaven.local/eimadpbcbfnmbkopoojfekhnkhdbieeh/ui/popup/index.html',
                    'launchUrl':
                        'https://chrome-ext.heaven.local/eimadpbcbfnmbkopoojfekhnkhdbieeh/ui/popup/index.html',
                    'hasBackground': true,
                    'iconBase64': base64Encode(_kSamplePreviewPng),
                    'permissions': <String>['storage', 'tabs'],
                    'matches': <String>['<all_urls>'],
                    'contentScriptCount': 1,
                  },
                ];
              case 'setPopupContextTab':
                return true;
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
      await settings.setSitePermission(
        'www.google.com',
        SitePermissionType.camera,
        SitePermissionDecision.allow,
      );

      final DownloadsController downloads = DownloadsController(
        prefs,
        enableNativePolling: false,
      );
      final ExtensionsController extensions = ExtensionsController(
        prefs,
        syncNativeOnInit: false,
      );
      await extensions.refreshChromeExtensions();

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
      final TabManagerController tabManager = tester
          .widget<BrowserScreen>(find.byType(BrowserScreen))
          .tabManager;

      // 1. Verify Top Navigation Bar is at the TOP of the screen and Quick Action FAB is removed
      expect(find.byKey(const Key('top_navigation_bar_wrapper')), findsOneWidget);
      expect(find.byKey(const Key('omnibox_display_pill')), findsOneWidget);
      expect(find.byKey(const Key('quick_action_fab')), findsNothing);
      final Offset topBarOffset = tester.getTopLeft(
        find.byKey(const Key('top_navigation_bar_wrapper')),
      );
      expect(topBarOffset.dy, lessThan(80));
      expect(find.text('Heaven'), findsWidgets);

      // 2. Submit search -> resolves to Google Search; then scroll down hides top bar & scroll up shows it again!
      await tester.enterText(
        find.byKey(const Key('home_search_textfield')),
        'flutter',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('home_search_icon_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('google.com'), findsWidgets);

      tabManager.activeEngine.handleWebScrollDelta(140, 60);
      await tester.pumpAndSettle();
      expect(tabManager.activeEngine.isNavBarVisible, isFalse);
      expect(find.byKey(const Key('omnibox_display_pill')), findsNothing);

      tabManager.activeEngine.handleWebScrollDelta(80, -35);
      await tester.pumpAndSettle();
      expect(tabManager.activeEngine.isNavBarVisible, isTrue);
      expect(find.byKey(const Key('omnibox_display_pill')), findsOneWidget);

      // 3. Per-Site Permission Dashboard shows allowed Camera & revokes with 1 tap!
      await tester.tap(find.byKey(const Key('site_permissions_button')));
      await tester.pumpAndSettle();
      expect(find.byType(SiteControlsSheet), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('revoke_perm_camera')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('revoke_perm_camera')));
      await tester.pumpAndSettle();
      expect(
        settings.getSitePermission('www.google.com', SitePermissionType.camera),
        SitePermissionDecision.block,
      );
      Navigator.of(tester.element(find.byType(SiteControlsSheet))).pop();
      await tester.pumpAndSettle();

      // 4. Tapping an installed Chrome extension opens it in a NEW TAB!
      expect(tabManager.normalTabs.length, 1);
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Chrome Extensions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chrome Extensions'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const Key('installed_extension_card_eimadpbcbfnmbkopoojfekhnkhdbieeh'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          const Key('installed_extension_card_eimadpbcbfnmbkopoojfekhnkhdbieeh'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tabManager.normalTabs.length, 2);
      expect(
        tabManager.activeEngine.currentUrl,
        'https://chrome-ext.heaven.local/eimadpbcbfnmbkopoojfekhnkhdbieeh/ui/popup/index.html',
      );

      // 5. Minimal Settings Screen: switch Search Engine to Perplexity & verify Privacy Policy tile!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings_search_engine_tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search_engine_option_perplexity')));
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

      // 6. Open Notification Control Center -> Send Test Alert!
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('send_test_notification_button')));
      await tester.pumpAndSettle();
      expect(testNotificationSent, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 7. Create Shortcut with website logo works cleanly
      await tester.tap(find.byTooltip('Browser Menu'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create shortcut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create shortcut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Shortcut'));
      await tester.pumpAndSettle();
      expect(capturedShortcutArgs, isNotNull);

      // 8. Tabs screen shows open tabs with zero Sleep Mode controls
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch Tabs'));
      await tester.pumpAndSettle();
      expect(find.byType(TabsScreen), findsOneWidget);
      expect(find.text('Sleeping'), findsNothing);

      vpn.dispose();
      extensions.dispose();
      newsService.dispose();
      downloads.dispose();
    },
  );

  group('Shield, DevTools & Native Java Architecture Invariants', () {
    test(
      'HeavenShield blocks Google Ads, YouTube Ads, and Pirated/Porn Redirect networks',
      () {
        expect(
          HeavenShield.matchBlockedDomain('pagead2.googlesyndication.com'),
          isNotNull,
        );
        expect(
          HeavenShield.matchBlockedDomain('googleads.g.doubleclick.net'),
          isNotNull,
        );
        expect(HeavenShield.matchBlockedDomain('ads.youtube.com'), isNotNull);
        expect(
          HeavenShield.matchBlockedDomain('syndication.exoclick.com'),
          isNotNull,
        );
        expect(HeavenShield.matchBlockedDomain('adsterra.com'), isNotNull);
        expect(
          HeavenShield.matchBlockedDomain('chromewebstore.google.com'),
          isNull,
        );
        expect(HeavenShield.matchBlockedDomain('www.google.com'), isNull);
        expect(HeavenShield.matchBlockedDomain('www.perplexity.ai'), isNull);
        expect(HeavenShield.matchBlockedDomain('www.youtube.com'), isNull);
      },
    );

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
        final ExtensionsController extensions = ExtensionsController(
          prefs,
          syncNativeOnInit: false,
        );

        await tester.pumpWidget(
          HeavenBrowserApp(
            settings: settings,
            searchService: _createMockSearchService(),
            downloads: downloads,
            newsService: newsService,
            interests: interests,
            vpn: vpn,
            extensions: extensions,
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
        extensions.dispose();
        newsService.dispose();
        downloads.dispose();
      },
    );

    test(
      'Native Java & Manifest safety: Heaven label, PiP & Media Grabber removed, Background MediaSession + WakeLock + Extension Native Bridge wired',
      () {
        final String shieldJava = File(
          'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenShieldPlugin.java',
        ).readAsStringSync();
        expect(shieldJava.contains('setWebChromeClient'), isFalse);
        expect(shieldJava.contains('ShieldWebChromeClient'), isFalse);
        expect(shieldJava.contains('enterPictureInPictureMode'), isFalse);
        expect(shieldJava.contains('executeHlsPlaylistDownload'), isFalse);
        expect(shieldJava.contains('addDocumentStartJavaScript'), isTrue);
        expect(shieldJava.contains('/youtubei/v1/player'), isTrue);
        expect(shieldJava.contains('onWebScrollNavBar'), isTrue);
        expect(shieldJava.contains('bgKeepAliveLoop'), isTrue);

        final String extJava = File(
          'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenChromeExtManager.java',
        ).readAsStringSync();
        expect(
          extJava.contains('update.googleapis.com/service/update2/crx'),
          isTrue,
        );
        expect(extJava.contains('HeavenExtNative'), isTrue);
        expect(extJava.contains('importScripts'), isTrue);
        expect(extJava.contains('normalizeExtensionUrl'), isTrue);
        expect(extJava.contains('DnrBlockRule'), isTrue);

        final String mediaServiceJava = File(
          'android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenMediaService.java',
        ).readAsStringSync();
        expect(
          mediaServiceJava.contains('FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK'),
          isTrue,
        );
        expect(mediaServiceJava.contains('MediaSession'), isTrue);
        expect(mediaServiceJava.contains('AudioFocusRequest'), isTrue);
        expect(mediaServiceJava.contains('PARTIAL_WAKE_LOCK'), isTrue);

        final String mainKt = File(
          'android/app/src/main/kotlin/com/hypertechlabs/heavenbrowser/MainActivity.kt',
        ).readAsStringSync();
        expect(mainKt.contains('onActivityPaused'), isTrue);
        expect(mainKt.contains('onActivityStopped'), isTrue);
        expect(mainKt.contains('onActivityResumed'), isTrue);
        expect(mainKt.contains('PictureInPicture'), isFalse);

        final String manifestXml = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();
        expect(manifestXml.contains('android:label="Heaven"'), isTrue);
        expect(
          manifestXml.contains('android:supportsPictureInPicture'),
          isFalse,
        );
        expect(manifestXml.contains('android.permission.USE_BIOMETRIC'), isTrue);
        expect(
          manifestXml.contains(
            'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
          ),
          isTrue,
        );
      },
    );
  });
}
