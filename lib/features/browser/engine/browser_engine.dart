import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:heavenbrowser/core/constants/app_constants.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';
import 'package:heavenbrowser/features/shield/heaven_shield.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class FindMatchesState {
  const FindMatchesState({
    this.total = 0,
    this.current = 0,
  });

  final int total;
  final int current;
}

class BrowserPageState {
  const BrowserPageState({
    this.currentUrl,
    this.pageTitle,
    this.progress = 0,
    this.isLoading = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.errorDescription,
    this.blockedDomainsOnPage = const <String>[],
    this.findMatches = const FindMatchesState(),
  });

  final String? currentUrl;
  final String? pageTitle;
  final int progress;
  final bool isLoading;
  final bool canGoBack;
  final bool canGoForward;
  final String? errorDescription;
  final List<String> blockedDomainsOnPage;
  final FindMatchesState findMatches;

  bool get hasActivePage => currentUrl != null && currentUrl!.isNotEmpty;

  bool get isSecureHttps {
    if (currentUrl == null) {
      return false;
    }
    return Uri.tryParse(currentUrl!)?.scheme == 'https';
  }

  String? get host {
    if (currentUrl == null) {
      return null;
    }
    final String? h = Uri.tryParse(currentUrl!)?.host;
    return (h != null && h.isNotEmpty) ? h : null;
  }

  BrowserPageState copyWith({
    String? currentUrl,
    bool clearUrl = false,
    String? pageTitle,
    bool clearTitle = false,
    int? progress,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    String? errorDescription,
    bool clearError = false,
    List<String>? blockedDomainsOnPage,
    FindMatchesState? findMatches,
  }) {
    return BrowserPageState(
      currentUrl: clearUrl ? null : (currentUrl ?? this.currentUrl),
      pageTitle: clearTitle ? null : (pageTitle ?? this.pageTitle),
      progress: progress ?? this.progress,
      isLoading: isLoading ?? this.isLoading,
      canGoBack: canGoBack ?? this.canGoBack,
      canGoForward: canGoForward ?? this.canGoForward,
      errorDescription:
          clearError ? null : (errorDescription ?? this.errorDescription),
      blockedDomainsOnPage: blockedDomainsOnPage ?? this.blockedDomainsOnPage,
      findMatches: findMatches ?? this.findMatches,
    );
  }
}

abstract class BrowserEngine extends ChangeNotifier {
  BrowserPageState get state;

  Future<void> loadUri(Uri uri);
  Future<void> reload();
  Future<void> stopLoading();
  Future<void> goBack();
  Future<void> goForward();
  void showHome();
  Future<void> syncSettings(BrowserSettingsController settings);
  Future<void> findInPage(String query);
  Future<void> findNext({required bool forward});
  Future<void> clearFind();
  Future<void> clearSiteData();
  Future<void> wipeSessionAndData();
  Widget buildViewport(BuildContext context);
}

BrowserEngine createDefaultBrowserEngine({
  required BrowserSettingsController settings,
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  if (WebViewPlatform.instance != null) {
    return WebViewBrowserEngine(
      settings: settings,
      navigatorKey: navigatorKey,
    );
  }
  return InMemoryBrowserEngine(settings: settings);
}

class WebViewBrowserEngine extends BrowserEngine {
  WebViewBrowserEngine({
    required this.settings,
    required this.navigatorKey,
  }) {
    _initController();
  }

  BrowserSettingsController settings;
  final GlobalKey<NavigatorState> navigatorKey;
  late final WebViewController _controller;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  final Set<String> _upgradedHttpsHosts = <String>{};

  BrowserPageState _state = const BrowserPageState();

  @override
  BrowserPageState get state => _state;

  void _updateState(BrowserPageState next) {
    _state = next;
    notifyListeners();
  }

  void _recordBlocked(String domain) {
    final List<String> updated = <String>[
      ..._state.blockedDomainsOnPage,
      domain,
    ];
    _updateState(_state.copyWith(blockedDomainsOnPage: updated));
    settings.recordBlockedTracker();
  }

  void _initController() {
    _controller = WebViewController();
    _controller.setBackgroundColor(const Color(0x00000000));

    _controller.addJavaScriptChannel(
      'HeavenShieldChannel',
      onMessageReceived: (JavaScriptMessage message) {
        final String domain = message.message.trim();
        if (domain.isNotEmpty) {
          _recordBlocked(domain);
        }
      },
    );

    _controller.addJavaScriptChannel(
      'HeavenFindChannel',
      onMessageReceived: (JavaScriptMessage message) {
        try {
          final Map<String, dynamic> data =
              jsonDecode(message.message) as Map<String, dynamic>;
          final int total = (data['total'] as num?)?.toInt() ?? 0;
          final int current = (data['current'] as num?)?.toInt() ?? 0;
          _updateState(
            _state.copyWith(
              findMatches: FindMatchesState(total: total, current: current),
            ),
          );
        } catch (_) {}
      },
    );

    _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (NavigationRequest request) async {
          final Uri? uri = Uri.tryParse(request.url);
          if (uri == null) {
            return NavigationDecision.prevent;
          }

          final String scheme = uri.scheme.toLowerCase();
          if (scheme == 'mailto' || scheme == 'tel' || scheme == 'sms') {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }

          if (scheme != 'http' && scheme != 'https' && scheme != 'about') {
            return NavigationDecision.prevent;
          }

          final String pageHost =
              request.isMainFrame ? uri.host : (_state.host ?? uri.host);

          if (HeavenShield.shouldBlockUri(
            uri,
            shieldEnabled: settings.shieldEnabled,
            trustedHosts: settings.trustedHosts,
            currentPageHost: pageHost,
          )) {
            final String matched =
                HeavenShield.matchBlockedDomain(uri.host) ?? uri.host;
            _recordBlocked(matched);
            return NavigationDecision.prevent;
          }

          if (request.isMainFrame &&
              scheme == 'http' &&
              settings.httpsUpgrade &&
              !OmniboxParser.isLocalOrPrivateHost(uri.host) &&
              !_upgradedHttpsHosts.contains(uri.host)) {
            _upgradedHttpsHosts.add(uri.host);
            final Uri upgraded = uri.replace(scheme: 'https');
            await _controller.loadRequest(upgraded);
            return NavigationDecision.prevent;
          }

          return NavigationDecision.navigate;
        },
        onPageStarted: (String url) async {
          if (url == 'about:blank') {
            return;
          }
          _updateState(
            _state.copyWith(
              currentUrl: url,
              isLoading: true,
              progress: 10,
              clearError: true,
              blockedDomainsOnPage: <String>[],
              findMatches: const FindMatchesState(),
            ),
          );
          await _injectShield(url);
          await _refreshNavAvailability();
        },
        onProgress: (int progress) {
          _updateState(
            _state.copyWith(
              progress: progress,
              isLoading: progress < 100,
            ),
          );
        },
        onPageFinished: (String url) async {
          if (url == 'about:blank') {
            return;
          }
          await _injectShield(url);
          final String? title = await _controller.getTitle();
          final bool back = await _controller.canGoBack();
          final bool forward = await _controller.canGoForward();
          _updateState(
            _state.copyWith(
              currentUrl: url,
              pageTitle: (title != null && title.trim().isNotEmpty)
                  ? title.trim()
                  : OmniboxParser.formatDisplayUrl(url),
              progress: 100,
              isLoading: false,
              canGoBack: back,
              canGoForward: forward,
            ),
          );
        },
        onUrlChange: (UrlChange change) async {
          final String? url = change.url;
          if (url == null || url.isEmpty || url == 'about:blank') {
            return;
          }
          await _refreshNavAvailability(overrideUrl: url);
        },
        onWebResourceError: (WebResourceError error) {
          if (error.isForMainFrame != true) {
            return;
          }
          if (error.description.contains('ERR_ABORTED') ||
              error.errorCode == -999) {
            return;
          }
          _updateState(
            _state.copyWith(
              isLoading: false,
              progress: 0,
              errorDescription: error.description,
            ),
          );
        },
      ),
    );

    _configureDialogs();
    _configureAndroidHardening();
    syncSettings(settings);
  }

  void _configureDialogs() {
    _controller.setOnJavaScriptAlertDialog(
      (JavaScriptAlertDialogRequest request) async {
        final BuildContext? ctx = navigatorKey.currentContext;
        if (ctx == null) {
          return;
        }
        await showDialog<void>(
          context: ctx,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Page Alert'),
            content: Text(request.message),
            actions: <Widget>[
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );

    _controller.setOnJavaScriptConfirmDialog(
      (JavaScriptConfirmDialogRequest request) async {
        final BuildContext? ctx = navigatorKey.currentContext;
        if (ctx == null) {
          return false;
        }
        final bool? confirmed = await showDialog<bool>(
          context: ctx,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Confirm Action'),
            content: Text(request.message),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
        return confirmed ?? false;
      },
    );
  }

  Future<void> _configureAndroidHardening() async {
    if (_controller.platform case final AndroidWebViewController platform) {
      await platform.setAllowFileAccess(false);
      await platform.setAllowContentAccess(false);
      await platform.setGeolocationEnabled(false);
      await platform.setMediaPlaybackRequiresUserGesture(true);
      await platform.enableZoom(true);
      await platform.setUseWideViewPort(true);
    }
  }

  Future<void> _injectShield(String url) async {
    if (!settings.javascriptEnabled) {
      return;
    }
    final String? host = Uri.tryParse(url)?.host;
    final String script = HeavenShield.buildProtectionScript(
      shieldEnabled: settings.shieldEnabled,
      isSiteTrusted: settings.isHostTrusted(host),
    );
    try {
      await _controller.runJavaScript(script);
    } catch (_) {}
  }

  Future<void> _refreshNavAvailability({String? overrideUrl}) async {
    final bool back = await _controller.canGoBack();
    final bool forward = await _controller.canGoForward();
    _updateState(
      _state.copyWith(
        currentUrl: overrideUrl,
        canGoBack: back,
        canGoForward: forward,
      ),
    );
  }

  @override
  Future<void> syncSettings(BrowserSettingsController nextSettings) async {
    settings = nextSettings;
    await _controller.setJavaScriptMode(
      nextSettings.javascriptEnabled
          ? JavaScriptMode.unrestricted
          : JavaScriptMode.disabled,
    );
    await _controller.setUserAgent(
      nextSettings.desktopMode
          ? AppConstants.desktopUserAgent
          : AppConstants.mobileUserAgent,
    );

    if (_controller.platform case final AndroidWebViewController platform) {
      await platform.setTextZoom(nextSettings.textZoom);
      if (_cookieManager.platform
          case final AndroidWebViewCookieManager cookiePlatform) {
        await cookiePlatform.setAcceptThirdPartyCookies(
          platform,
          !nextSettings.blockThirdPartyCookies,
        );
      }
    }
  }

  @override
  Future<void> loadUri(Uri uri) async {
    if (HeavenShield.shouldBlockUri(
      uri,
      shieldEnabled: settings.shieldEnabled,
      trustedHosts: settings.trustedHosts,
      currentPageHost: uri.host,
    )) {
      final String matched =
          HeavenShield.matchBlockedDomain(uri.host) ?? uri.host;
      _recordBlocked(matched);
      _updateState(
        _state.copyWith(
          currentUrl: uri.toString(),
          isLoading: false,
          progress: 0,
          errorDescription:
              'Blocked by Heaven Shield: $matched is a known tracker/ad domain.',
        ),
      );
      return;
    }

    _updateState(
      _state.copyWith(
        currentUrl: uri.toString(),
        isLoading: true,
        progress: 8,
        clearError: true,
        blockedDomainsOnPage: <String>[],
        findMatches: const FindMatchesState(),
      ),
    );
    await _controller.loadRequest(uri);
  }

  @override
  Future<void> reload() async {
    if (!_state.hasActivePage) {
      return;
    }
    _updateState(_state.copyWith(clearError: true, isLoading: true));
    await _controller.reload();
  }

  @override
  Future<void> stopLoading() async {
    if (settings.javascriptEnabled) {
      try {
        await _controller.runJavaScript('window.stop();');
      } catch (_) {}
    }
    _updateState(_state.copyWith(isLoading: false, progress: 100));
  }

  @override
  Future<void> goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      await _refreshNavAvailability();
    }
  }

  @override
  Future<void> goForward() async {
    if (await _controller.canGoForward()) {
      await _controller.goForward();
      await _refreshNavAvailability();
    }
  }

  @override
  void showHome() {
    _updateState(
      const BrowserPageState(),
    );
  }

  @override
  Future<void> findInPage(String query) async {
    if (!_state.hasActivePage || !settings.javascriptEnabled) {
      return;
    }
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      await clearFind();
      return;
    }
    final String safeQuery = jsonEncode(trimmed);
    final String js = '''
(function() {
  function clearMarks() {
    const oldMarks = document.querySelectorAll('mark[data-heaven-find]');
    oldMarks.forEach(function(m) {
      const parent = m.parentNode;
      if (parent) {
        parent.replaceChild(document.createTextNode(m.textContent || ''), m);
        parent.normalize();
      }
    });
    window.__heavenFindMarks = [];
    window.__heavenFindIdx = -1;
  }

  clearMarks();
  const needle = ($safeQuery).toLowerCase();
  if (!needle || !document.body) {
    HeavenFindChannel.postMessage(JSON.stringify({total: 0, current: 0}));
    return;
  }

  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
    acceptNode: function(node) {
      if (!node.parentElement) return NodeFilter.FILTER_REJECT;
      const tag = node.parentElement.tagName;
      if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT' || tag === 'TEXTAREA') {
        return NodeFilter.FILTER_REJECT;
      }
      return node.nodeValue && node.nodeValue.toLowerCase().indexOf(needle) !== -1
        ? NodeFilter.FILTER_ACCEPT
        : NodeFilter.FILTER_SKIP;
    }
  });

  const textNodes = [];
  while (walker.nextNode()) {
    textNodes.push(walker.currentNode);
  }

  const marks = [];
  textNodes.forEach(function(textNode) {
    const text = textNode.nodeValue || '';
    const lower = text.toLowerCase();
    let start = 0;
    let idx = lower.indexOf(needle, start);
    if (idx === -1) return;

    const frag = document.createDocumentFragment();
    while (idx !== -1) {
      if (idx > start) {
        frag.appendChild(document.createTextNode(text.slice(start, idx)));
      }
      const mark = document.createElement('mark');
      mark.setAttribute('data-heaven-find', '1');
      mark.style.backgroundColor = '#FDE047';
      mark.style.color = '#0F172A';
      mark.style.padding = '0 1px';
      mark.style.borderRadius = '2px';
      mark.textContent = text.slice(idx, idx + needle.length);
      frag.appendChild(mark);
      marks.push(mark);
      start = idx + needle.length;
      idx = lower.indexOf(needle, start);
    }
    if (start < text.length) {
      frag.appendChild(document.createTextNode(text.slice(start)));
    }
    if (textNode.parentNode) {
      textNode.parentNode.replaceChild(frag, textNode);
    }
  });

  window.__heavenFindMarks = marks;
  if (marks.length > 0) {
    window.__heavenFindIdx = 0;
    marks[0].style.backgroundColor = '#FB923C';
    marks[0].scrollIntoView({behavior: 'smooth', block: 'center'});
    HeavenFindChannel.postMessage(JSON.stringify({total: marks.length, current: 1}));
  } else {
    window.__heavenFindIdx = -1;
    HeavenFindChannel.postMessage(JSON.stringify({total: 0, current: 0}));
  }
})();
''';
    await _controller.runJavaScript(js);
  }

  @override
  Future<void> findNext({required bool forward}) async {
    if (!_state.hasActivePage || !settings.javascriptEnabled) {
      return;
    }
    final String step = forward ? '1' : '-1';
    final String js = '''
(function() {
  const marks = window.__heavenFindMarks || [];
  if (!marks.length) return;
  const prev = window.__heavenFindIdx || 0;
  if (marks[prev]) {
    marks[prev].style.backgroundColor = '#FDE047';
  }
  const next = (prev + ($step) + marks.length) % marks.length;
  window.__heavenFindIdx = next;
  marks[next].style.backgroundColor = '#FB923C';
  marks[next].scrollIntoView({behavior: 'smooth', block: 'center'});
  HeavenFindChannel.postMessage(JSON.stringify({total: marks.length, current: next + 1}));
})();
''';
    await _controller.runJavaScript(js);
  }

  @override
  Future<void> clearFind() async {
    _updateState(_state.copyWith(findMatches: const FindMatchesState()));
    if (!_state.hasActivePage || !settings.javascriptEnabled) {
      return;
    }
    const String js = '''
(function() {
  const oldMarks = document.querySelectorAll('mark[data-heaven-find]');
  oldMarks.forEach(function(m) {
    const parent = m.parentNode;
    if (parent) {
      parent.replaceChild(document.createTextNode(m.textContent || ''), m);
      parent.normalize();
    }
  });
  window.__heavenFindMarks = [];
  window.__heavenFindIdx = -1;
})();
''';
    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  @override
  Future<void> clearSiteData() async {
    await _cookieManager.clearCookies();
    await _controller.clearCache();
    await _controller.clearLocalStorage();
  }

  @override
  Future<void> wipeSessionAndData() async {
    await clearSiteData();
    _upgradedHttpsHosts.clear();
    try {
      await _controller.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    _updateState(const BrowserPageState());
  }

  @override
  Widget buildViewport(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

/// Deterministic in-memory browser engine used during headless widget tests
/// and desktop environments without Android WebView platform channels.
class InMemoryBrowserEngine extends BrowserEngine {
  InMemoryBrowserEngine({required this.settings});

  BrowserSettingsController settings;
  final List<String> _history = <String>[];
  int _historyIndex = -1;
  int wipeCount = 0;

  BrowserPageState _state = const BrowserPageState();

  @override
  BrowserPageState get state => _state;

  @override
  Future<void> syncSettings(BrowserSettingsController nextSettings) async {
    settings = nextSettings;
    notifyListeners();
  }

  @override
  Future<void> loadUri(Uri uri) async {
    if (HeavenShield.shouldBlockUri(
      uri,
      shieldEnabled: settings.shieldEnabled,
      trustedHosts: settings.trustedHosts,
      currentPageHost: uri.host,
    )) {
      final String matched =
          HeavenShield.matchBlockedDomain(uri.host) ?? uri.host;
      await settings.recordBlockedTracker();
      _state = _state.copyWith(
        currentUrl: uri.toString(),
        pageTitle: 'Blocked by Heaven Shield',
        isLoading: false,
        progress: 100,
        errorDescription:
            'Blocked by Heaven Shield: $matched is a known tracker/ad domain.',
        blockedDomainsOnPage: <String>[matched],
      );
      notifyListeners();
      return;
    }

    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(uri.toString());
    _historyIndex = _history.length - 1;

    _state = BrowserPageState(
      currentUrl: uri.toString(),
      pageTitle: OmniboxParser.formatDisplayUrl(uri.toString()),
      progress: 100,
      isLoading: false,
      canGoBack: _historyIndex > 0,
      canGoForward: false,
    );
    notifyListeners();
  }

  @override
  Future<void> reload() async {
    if (!_state.hasActivePage) {
      return;
    }
    _state = _state.copyWith(clearError: true, progress: 100, isLoading: false);
    notifyListeners();
  }

  @override
  Future<void> stopLoading() async {
    _state = _state.copyWith(isLoading: false, progress: 100);
    notifyListeners();
  }

  @override
  Future<void> goBack() async {
    if (_historyIndex > 0) {
      _historyIndex -= 1;
      final String url = _history[_historyIndex];
      _state = BrowserPageState(
        currentUrl: url,
        pageTitle: OmniboxParser.formatDisplayUrl(url),
        progress: 100,
        isLoading: false,
        canGoBack: _historyIndex > 0,
        canGoForward: _historyIndex < _history.length - 1,
      );
      notifyListeners();
    }
  }

  @override
  Future<void> goForward() async {
    if (_historyIndex < _history.length - 1) {
      _historyIndex += 1;
      final String url = _history[_historyIndex];
      _state = BrowserPageState(
        currentUrl: url,
        pageTitle: OmniboxParser.formatDisplayUrl(url),
        progress: 100,
        isLoading: false,
        canGoBack: _historyIndex > 0,
        canGoForward: _historyIndex < _history.length - 1,
      );
      notifyListeners();
    }
  }

  @override
  void showHome() {
    _state = const BrowserPageState();
    notifyListeners();
  }

  @override
  Future<void> findInPage(String query) async {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty || !_state.hasActivePage) {
      _state = _state.copyWith(findMatches: const FindMatchesState());
    } else {
      final String haystack =
          '${_state.currentUrl ?? ''} ${_state.pageTitle ?? ''}'.toLowerCase();
      final int matches = q.allMatches(haystack).length;
      _state = _state.copyWith(
        findMatches: FindMatchesState(
          total: matches,
          current: matches > 0 ? 1 : 0,
        ),
      );
    }
    notifyListeners();
  }

  @override
  Future<void> findNext({required bool forward}) async {
    final FindMatchesState m = _state.findMatches;
    if (m.total <= 0) {
      return;
    }
    final int next = forward
        ? (m.current % m.total) + 1
        : ((m.current - 2 + m.total) % m.total) + 1;
    _state = _state.copyWith(
      findMatches: FindMatchesState(total: m.total, current: next),
    );
    notifyListeners();
  }

  @override
  Future<void> clearFind() async {
    _state = _state.copyWith(findMatches: const FindMatchesState());
    notifyListeners();
  }

  @override
  Future<void> clearSiteData() async {
    wipeCount += 1;
  }

  @override
  Future<void> wipeSessionAndData() async {
    wipeCount += 1;
    _history.clear();
    _historyIndex = -1;
    _state = const BrowserPageState();
    notifyListeners();
  }

  @override
  Widget buildViewport(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.public, size: 48, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              _state.pageTitle ?? '',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            SelectableText(
              _state.currentUrl ?? '',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
