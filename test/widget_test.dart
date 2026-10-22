import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
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
        <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fflutter.dev%2Fdocs">Flutter Documentation</a>
        <a class="result__snippet">Build fast apps on every screen with <b>Flutter</b>.</a>
      </div>
      <div class="result">
        <a class="result__a" href="//duckduckgo.com/y.js?ad_domain=spam.example">Sponsored Ad</a>
        <a class="result__snippet">Should be skipped</a>
      </div>
      ''';
      return http.Response(sampleHtml, 200);
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
    if (host == 'hn.algolia.com') {
      return http.Response(
        jsonEncode(<String, Object>{
          'hits': <Map<String, Object>>[
            <String, Object>{
              'title': 'Flutter 3 Released',
              'url': 'https://flutter.dev',
              'points': 512,
              'num_comments': 180,
              'author': 'aryan',
              'objectID': '101',
            },
          ],
        }),
        200,
      );
    }
    if (host == 'duckduckgo.com' && request.url.path == '/ac/') {
      return http.Response(
        jsonEncode(<Object>[
          'flut',
          <String>['flutter', 'flutter tutorial'],
        ]),
        200,
      );
    }
    return http.Response('{}', 200);
  });

  return HeavenSearchService(client: mockClient);
}

void main() {
  group('OmniboxParser & Default Heaven Search', () {
    test(
      'defaults to Heaven Search and resolves queries to heaven://search',
      () {
        expect(SearchEngine.fromName(null), SearchEngine.heaven);
        final Uri uri = OmniboxParser.resolveInput(
          'raspberry pi 5 ubuntu',
          searchEngine: SearchEngine.heaven,
          httpsUpgrade: true,
        );
        expect(OmniboxParser.isHeavenSearchUrl(uri.toString()), isTrue);
        expect(
          OmniboxParser.extractHeavenQuery(uri.toString()),
          'raspberry pi 5 ubuntu',
        );
      },
    );

    test('supports switching to external search engines cleanly', () {
      final Uri uri = OmniboxParser.resolveInput(
        'privacy news',
        searchEngine: SearchEngine.brave,
        httpsUpgrade: true,
      );
      expect(uri.host, 'search.brave.com');
      expect(uri.queryParameters['q'], 'privacy news');
    });

    test('upgrades http URLs to https while keeping private LAN IPs http', () {
      final Uri publicSite = OmniboxParser.resolveInput(
        'http://example.com/blog',
        searchEngine: SearchEngine.heaven,
        httpsUpgrade: true,
      );
      expect(publicSite.toString(), 'https://example.com/blog');

      final Uri localRouter = OmniboxParser.resolveInput(
        '192.168.1.1:8080',
        searchEngine: SearchEngine.heaven,
        httpsUpgrade: true,
      );
      expect(localRouter.toString(), 'http://192.168.1.1:8080');
    });
  });

  group('Heaven Search Engine & Instant Calculator', () {
    test('evaluates arithmetic expressions accurately and ignores dates', () {
      expect(HeavenMathEvaluator.tryEvaluate('(1250 * 18) / 100'), '225');
      expect(HeavenMathEvaluator.tryEvaluate('2 ^ 10'), '1024');
      expect(HeavenMathEvaluator.tryEvaluate('2026-10-22'), isNull);
      expect(HeavenMathEvaluator.tryEvaluate('flutter sdk'), isNull);
    });

    test(
      'unwraps direct URLs, skips sponsored ads, and fetches knowledge',
      () async {
        final HeavenSearchService service = _createMockSearchService();
        final HeavenSearchResponse res = await service.search('flutter');

        expect(res.webResults.length, 1);
        expect(res.webResults.first.url, 'https://flutter.dev/docs');
        expect(res.webResults.first.title, 'Flutter Documentation');
        expect(res.knowledgeCard?.heading, 'Flutter (software)');
        expect(res.knowledgeResults.first.sourceLabel, 'en.wikipedia.org');
        expect(res.techResults.first.metaBadge, '512 pts');
      },
    );
  });

  group('Heaven Shield Ad & Tracker Firewall', () {
    test(
      'blocks ad networks, popunders & ad paths while allowing real sites',
      () {
        expect(
          HeavenShield.shouldBlockUri(
            Uri.parse(
              'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js',
            ),
          ),
          isTrue,
        );
        expect(
          HeavenShield.shouldBlockUri(
            Uri.parse('https://trc.taboola.com/libtrc/loader.js'),
          ),
          isTrue,
        );
        expect(
          HeavenShield.shouldBlockUri(
            Uri.parse('https://c1.popads.net/pop.js'),
          ),
          isTrue,
        );
        expect(
          HeavenShield.shouldBlockUri(Uri.parse('https://flutter.dev/docs')),
          isFalse,
        );
      },
    );

    test('strips tracking query parameters while keeping real query params', () {
      final ({Uri uri, int removedCount})
      cleaned = HeavenShield.stripTrackingParameters(
        Uri.parse(
          'https://news.example.com/post?id=99&utm_source=x&fbclid=abc&gclid=xyz',
        ),
      );
      expect(cleaned.removedCount, 3);
      expect(cleaned.uri.toString(), 'https://news.example.com/post?id=99');
    });
  });

  group('Smart Usage Quick Launch & Multi-Tab Incognito Isolation', () {
    test(
      'auto-ranks Quick Launch by visit frequency and isolates Incognito',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final BrowserSettingsController settings = BrowserSettingsController(
          prefs,
        );

        expect(settings.searchEngine, SearchEngine.heaven);

        // Simulate visiting proton.me 3 times and archlinux.org 1 time
        await settings.recordPageVisit(
          url: 'https://proton.me/mail',
          title: 'Proton Mail',
        );
        await settings.recordPageVisit(
          url: 'https://proton.me/drive',
          title: 'Proton Drive',
        );
        await settings.recordPageVisit(
          url: 'https://proton.me/calendar',
          title: 'Proton Calendar',
        );
        await settings.recordPageVisit(
          url: 'https://archlinux.org',
          title: 'Arch Linux',
        );

        final List<SiteUsageEntry> ranked = settings.quickLaunchSites;
        expect(ranked[0].domain, 'proton.me');
        expect(ranked[0].visitCount, 3);
        expect(ranked[1].domain, 'archlinux.org');
        expect(ranked[1].visitCount, 1);

        // Verify Multi-Tab + Incognito zero-history guarantee
        final TabManagerController tabManager = TabManagerController(
          settings: settings,
          enablePlatformWebView: false,
        );
        final int historyBefore = settings.history.length;

        final BrowserTab stealthTab = await tabManager.openNewTab(
          incognito: true,
          initialInput: 'https://secret.example.org',
        );
        expect(stealthTab.isIncognito, isTrue);
        expect(tabManager.totalTabCount, 2);
        expect(settings.history.length, historyBefore);
        expect(
          settings.quickLaunchSites.any(
            (SiteUsageEntry e) => e.domain == 'secret.example.org',
          ),
          isFalse,
        );

        tabManager.dispose();
      },
    );
  });

  testWidgets('Browser renders Heaven Search natively and opens Incognito tab', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final BrowserSettingsController settings = BrowserSettingsController(prefs);

    await tester.pumpWidget(
      HeavenBrowserApp(
        settings: settings,
        enablePlatformWebView: false,
        searchService: _createMockSearchService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Heaven Browser'), findsOneWidget);
    expect(find.text('Smart Quick Launch'), findsOneWidget);
    expect(find.text('+ Incognito'), findsOneWidget);

    // Tap search box and execute a Heaven Search query natively
    await tester.tap(find.text('Search with Heaven Search or enter URL'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'flutter');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    // Verify native Heaven Search results rendered inside the browser tab!
    expect(find.text('Heaven Search'), findsOneWidget);
    expect(find.text('Flutter Documentation'), findsOneWidget);

    // Open Tab Switcher via the tab count badge ('1') and create an Incognito tab
    await tester.tap(find.byTooltip('Switch Tabs (Hold for New Tab)'));
    await tester.pumpAndSettle();
    expect(find.text('Tabs (1)'), findsOneWidget);

    await tester.tap(find.text('Incognito'));
    await tester.pumpAndSettle();

    expect(find.text('Heaven Stealth'), findsOneWidget);
  });
}
