import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/omnibox_parser.dart';
import '../../settings/browser_settings.dart';
import '../../shield/heaven_shield.dart';
import '../../shield/native_shield_bridge.dart';

class ReadableArticle {
  const ReadableArticle({
    required this.title,
    required this.siteName,
    required this.paragraphs,
  });

  final String title;
  final String siteName;
  final List<String> paragraphs;
}

class BrowserEngine extends ChangeNotifier {
  BrowserEngine({
    required this.settings,
    required this.isIncognito,
    this.enablePlatformWebView = true,
  }) {
    settings.addListener(_onSettingsChanged);
    if (enablePlatformWebView) {
      _initializeController();
    }
  }

  final BrowserSettingsController settings;
  final bool isIncognito;
  final bool enablePlatformWebView;

  WebViewController? _controller;
  int? _androidWebViewId;

  final List<String> _virtualHistory = <String>[''];
  int _virtualIndex = 0;

  String? _currentUrl;
  String _pageTitle = 'New Tab';
  double _progress = 0;
  double _pullProgress = 0;
  bool _isLoading = false;
  bool _webViewCanGoBack = false;
  bool _webViewCanGoForward = false;
  int _pageBlockedCount = 0;
  final Set<String> _pageBlockedDomains = <String>{};
  String? _errorMessage;

  WebViewController? get controller => _controller;
  String? get currentUrl => _currentUrl;
  String get pageTitle => _pageTitle;
  double get progress => _progress;
  double get pullProgress => _pullProgress;
  bool get isLoading => _isLoading;
  bool get isShowingStartPage => _currentUrl == null || _currentUrl!.isEmpty;
  bool get isShowingHeavenSearch =>
      OmniboxParser.isHeavenSearchUrl(_currentUrl);
  String get heavenSearchQuery => OmniboxParser.extractHeavenQuery(_currentUrl);

  bool get canGoBack =>
      (!isShowingStartPage && !isShowingHeavenSearch && _webViewCanGoBack) ||
      _virtualIndex > 0;

  bool get canGoForward =>
      (!isShowingStartPage && !isShowingHeavenSearch && _webViewCanGoForward) ||
      _virtualIndex < _virtualHistory.length - 1;

  int get pageBlockedCount => _pageBlockedCount;
  List<String> get pageBlockedDomains =>
      _pageBlockedDomains.toList(growable: false);
  String? get errorMessage => _errorMessage;

  bool get isSecure =>
      isShowingHeavenSearch ||
      (_currentUrl != null && _currentUrl!.startsWith('https://'));

  String? get currentHost {
    if (_currentUrl == null || isShowingHeavenSearch) {
      return null;
    }
    final Uri? parsed = Uri.tryParse(_currentUrl!);
    return (parsed != null && parsed.host.isNotEmpty) ? parsed.host : null;
  }

  Map<String, String> get _clientHintHeaders => settings.desktopMode
      ? const <String, String>{
          'Sec-CH-UA-Mobile': '?0',
          'Sec-CH-UA-Platform': '"Linux"',
        }
      : const <String, String>{
          'Sec-CH-UA-Mobile': '?1',
          'Sec-CH-UA-Platform': '"Android"',
        };

  void _initializeController() {
    final WebViewController webController = WebViewController();
    _controller = webController;

    unawaited(_applyControllerSettings());

    unawaited(
      webController.addJavaScriptChannel(
        'HeavenShieldChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          _recordBlockedResource(msg.message.trim());
        },
      ),
    );

    unawaited(
      webController.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigationRequest,
          onPageStarted: (String url) {
            if (url == 'about:blank' &&
                (isShowingStartPage || isShowingHeavenSearch)) {
              return;
            }
            _currentUrl = url;
            _isLoading = true;
            _progress = 0.1;
            _pullProgress = 0;
            _errorMessage = null;
            _pageBlockedCount = 0;
            _pageBlockedDomains.clear();
            _syncVirtualEntryWithWebUrl(url);
            if (_androidWebViewId != null) {
              unawaited(
                NativeShieldBridge.instance.updatePageHost(
                  webViewId: _androidWebViewId!,
                  pageHost: Uri.tryParse(url)?.host,
                ),
              );
            }
            notifyListeners();
          },
          onProgress: (int value) {
            _progress = (value.clamp(0, 100)) / 100.0;
            _isLoading = value < 100;
            notifyListeners();
          },
          onPageFinished: (String url) async {
            if (url == 'about:blank' &&
                (isShowingStartPage || isShowingHeavenSearch)) {
              _isLoading = false;
              _progress = 0;
              notifyListeners();
              return;
            }
            _currentUrl = url;
            _isLoading = false;
            _progress = 1.0;
            _pullProgress = 0;
            _syncVirtualEntryWithWebUrl(url);
            await _injectProtectionAndZoom(url);
            await _refreshNavigationState();

            if (!isIncognito &&
                (url.startsWith('http://') || url.startsWith('https://'))) {
              await settings.recordPageVisit(url: url, title: _pageTitle);
            }
            notifyListeners();
          },
          onUrlChange: (UrlChange change) {
            final String? nextUrl = change.url;
            if (nextUrl != null &&
                nextUrl.isNotEmpty &&
                nextUrl != 'about:blank') {
              _currentUrl = nextUrl;
              _syncVirtualEntryWithWebUrl(nextUrl);
              unawaited(_refreshNavigationState());
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame ?? true) {
              _isLoading = false;
              _errorMessage = error.description;
              notifyListeners();
            }
          },
        ),
      ),
    );

    if (webController.platform
        case final AndroidWebViewController androidCtrl) {
      _androidWebViewId = androidCtrl.webViewIdentifier;
      unawaited(
        NativeShieldBridge.instance.attachWebView(
          webViewId: androidCtrl.webViewIdentifier,
          desktopMode: settings.desktopMode,
          pageHost: currentHost,
          onBlocked: (int _, String domain) {
            _recordBlockedResource(domain);
          },
          onPullProgress: (double value) {
            if ((_pullProgress - value).abs() >= 0.02 || value == 0.0) {
              _pullProgress = value;
              notifyListeners();
            }
          },
          onPullRefresh: () {
            _pullProgress = 0;
            unawaited(reloadFullPage());
          },
        ),
      );
    }
  }

  void _syncVirtualEntryWithWebUrl(String url) {
    if (_virtualHistory.isEmpty) {
      _virtualHistory.add(url);
      _virtualIndex = 0;
      return;
    }
    final String current = _virtualHistory[_virtualIndex];
    if (current.startsWith('http://') || current.startsWith('https://')) {
      _virtualHistory[_virtualIndex] = url;
    }
  }

  void _pushVirtualLocation(String target) {
    if (_virtualHistory[_virtualIndex] == target) {
      return;
    }
    if (_virtualIndex < _virtualHistory.length - 1) {
      _virtualHistory.removeRange(_virtualIndex + 1, _virtualHistory.length);
    }
    _virtualHistory.add(target);
    _virtualIndex = _virtualHistory.length - 1;
  }

  void _recordBlockedResource(String domainOrTag) {
    _pageBlockedCount += 1;
    if (domainOrTag.isNotEmpty) {
      _pageBlockedDomains.add(domainOrTag);
    }
    unawaited(settings.incrementBlockedCount(1));
    notifyListeners();
  }

  Future<NavigationDecision> _handleNavigationRequest(
    NavigationRequest request,
  ) async {
    final Uri? uri = Uri.tryParse(request.url);
    if (uri == null) {
      return NavigationDecision.prevent;
    }

    if (uri.scheme == 'about' || uri.scheme == 'data' || uri.scheme == 'blob') {
      return NavigationDecision.navigate;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return NavigationDecision.prevent;
    }

    // If Desktop Mode is enabled and a site redirects to m.example.com, rewrite to desktop host
    if (request.isMainFrame && settings.desktopMode) {
      final Uri desktopUri = rewriteMobileToDesktopUri(uri);
      if (desktopUri != uri) {
        await _controller?.loadRequest(desktopUri, headers: _clientHintHeaders);
        return NavigationDecision.prevent;
      }
    }

    final bool shieldActiveForSite =
        settings.shieldEnabled && !settings.isHostTrusted(currentHost);

    if (shieldActiveForSite && HeavenShield.shouldBlockUri(uri)) {
      _recordBlockedResource(
        HeavenShield.matchBlockedDomain(uri.host) ?? uri.host,
      );
      return NavigationDecision.prevent;
    }

    if (request.isMainFrame && shieldActiveForSite) {
      final ({Uri uri, int removedCount}) stripped =
          HeavenShield.stripTrackingParameters(uri);
      if (stripped.removedCount > 0 && stripped.uri != uri) {
        _pageBlockedCount += stripped.removedCount;
        await settings.incrementBlockedCount(stripped.removedCount);
        await _controller?.loadRequest(
          stripped.uri,
          headers: _clientHintHeaders,
        );
        notifyListeners();
        return NavigationDecision.prevent;
      }
    }

    if (request.isMainFrame &&
        settings.httpsUpgrade &&
        uri.scheme == 'http' &&
        !OmniboxParser.isLocalOrPrivateHost(uri.host)) {
      await _controller?.loadRequest(
        uri.replace(scheme: 'https'),
        headers: _clientHintHeaders,
      );
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  static Uri rewriteMobileToDesktopUri(Uri uri) {
    final String lowerHost = uri.host.toLowerCase();
    if (lowerHost.startsWith('m.') && lowerHost.length > 4) {
      final String rest = uri.host.substring(2);
      final String targetHost =
          (rest == 'youtube.com' || rest == 'facebook.com')
          ? 'www.$rest'
          : rest;
      return uri.replace(host: targetHost);
    }
    if (lowerHost.contains('.m.')) {
      return uri.replace(host: uri.host.replaceFirst('.m.', '.'));
    }
    if (lowerHost.startsWith('mobile.') && lowerHost.length > 9) {
      return uri.replace(host: uri.host.substring(7));
    }
    return uri;
  }

  void _onSettingsChanged() {
    unawaited(_applyControllerSettings());
  }

  Future<void> _applyControllerSettings() async {
    final WebViewController? webController = _controller;
    if (webController == null) {
      return;
    }

    await webController.setJavaScriptMode(
      settings.javascriptEnabled
          ? JavaScriptMode.unrestricted
          : JavaScriptMode.disabled,
    );

    await webController.setUserAgent(
      settings.desktopMode
          ? AppConstants.desktopUserAgent
          : AppConstants.mobileUserAgent,
    );

    if (webController.platform
        case final AndroidWebViewController androidCtrl) {
      await androidCtrl.setMediaPlaybackRequiresUserGesture(false);
      await androidCtrl.setTextZoom(settings.textScalePercent);
      await androidCtrl.enableZoom(true);
      await NativeShieldBridge.instance.applyDesktopViewport(
        webViewId: androidCtrl.webViewIdentifier,
        desktopMode: settings.desktopMode,
      );

      final WebViewCookieManager cookieManager = WebViewCookieManager();
      if (cookieManager.platform
          case final AndroidWebViewCookieManager androidCookies) {
        final bool allow3p = !isIncognito && !settings.blockThirdPartyCookies;
        await androidCookies.setAcceptThirdPartyCookies(androidCtrl, allow3p);
      }
    }
  }

  /// Properly switches Desktop Mode sequentially (awaiting User-Agent + Native WideViewport)
  /// before reloading with Desktop Client-Hints and m. -> desktop host rewrite.
  Future<void> setDesktopModeAndReload(bool enabled) async {
    await settings.setDesktopMode(enabled);
    await _applyControllerSettings();

    final String? activeUrl = _currentUrl;
    if (activeUrl != null &&
        !isShowingStartPage &&
        !isShowingHeavenSearch &&
        _controller != null) {
      Uri? parsed = Uri.tryParse(activeUrl);
      if (parsed != null) {
        if (enabled) {
          parsed = rewriteMobileToDesktopUri(parsed);
        }
        _currentUrl = parsed.toString();
        _isLoading = true;
        _errorMessage = null;
        notifyListeners();
        await _controller!.loadRequest(parsed, headers: _clientHintHeaders);
      }
    }
  }

  Future<void> _injectProtectionAndZoom(String url) async {
    final WebViewController? webController = _controller;
    if (webController == null || !settings.javascriptEnabled) {
      return;
    }

    final Uri? parsed = Uri.tryParse(url);
    final bool trusted = settings.isHostTrusted(parsed?.host);
    final String script = HeavenShield.buildProtectionScript(
      shieldEnabled: settings.shieldEnabled && !trusted,
      sendDntAndGpc: settings.sendDntAndGpc,
    );

    try {
      await webController.runJavaScript(script);
    } catch (_) {
      // Ignore JS errors on non-HTML responses.
    }
  }

  Future<void> _refreshNavigationState() async {
    final WebViewController? webController = _controller;
    if (webController == null) {
      return;
    }
    _webViewCanGoBack = await webController.canGoBack();
    _webViewCanGoForward = await webController.canGoForward();
    final String? title = await webController.getTitle();
    if (title != null && title.trim().isNotEmpty && title != 'about:blank') {
      _pageTitle = title.trim();
    } else if (_currentUrl != null) {
      _pageTitle = OmniboxParser.formatDisplayUrl(_currentUrl);
    }
    notifyListeners();
  }

  Future<void> loadUserEntry(String rawInput) async {
    final Uri target = OmniboxParser.resolveInput(
      rawInput,
      searchEngine: settings.searchEngine,
      httpsUpgrade: settings.httpsUpgrade,
    );
    await loadUri(target);
  }

  Future<void> loadUri(Uri uri) async {
    _errorMessage = null;
    _pageBlockedCount = 0;
    _pageBlockedDomains.clear();
    _pullProgress = 0;

    final String targetUrl = uri.toString();
    _pushVirtualLocation(targetUrl);

    if (OmniboxParser.isHeavenSearchUrl(targetUrl)) {
      _currentUrl = targetUrl;
      final String q = OmniboxParser.extractHeavenQuery(targetUrl);
      _pageTitle = q.isEmpty ? 'Heaven Search' : '$q — Heaven Search';
      _isLoading = false;
      _progress = 0;
      _webViewCanGoBack = false;
      _webViewCanGoForward = false;
      notifyListeners();
      return;
    }

    Uri finalUri = settings.desktopMode ? rewriteMobileToDesktopUri(uri) : uri;
    final bool shieldActive =
        settings.shieldEnabled && !settings.isHostTrusted(finalUri.host);
    if (shieldActive) {
      final ({Uri uri, int removedCount}) stripped =
          HeavenShield.stripTrackingParameters(finalUri);
      finalUri = stripped.uri;
      if (stripped.removedCount > 0) {
        _pageBlockedCount += stripped.removedCount;
        await settings.incrementBlockedCount(stripped.removedCount);
      }
    }

    _currentUrl = finalUri.toString();
    _pageTitle = OmniboxParser.formatDisplayUrl(_currentUrl);
    _isLoading = true;
    _progress = 0.1;
    notifyListeners();

    if (_androidWebViewId != null) {
      unawaited(
        NativeShieldBridge.instance.updatePageHost(
          webViewId: _androidWebViewId!,
          pageHost: finalUri.host,
        ),
      );
    }

    await _applyControllerSettings();
    await _controller?.loadRequest(finalUri, headers: _clientHintHeaders);
    if (_controller == null) {
      _isLoading = false;
      if (!isIncognito &&
          (_currentUrl!.startsWith('http://') ||
              _currentUrl!.startsWith('https://'))) {
        await settings.recordPageVisit(url: _currentUrl!, title: _pageTitle);
      }
      notifyListeners();
    }
  }

  Future<void> goHome() async {
    _pushVirtualLocation('');
    _currentUrl = null;
    _pageTitle = isIncognito ? 'Incognito Tab' : 'New Tab';
    _isLoading = false;
    _progress = 0;
    _pullProgress = 0;
    _errorMessage = null;
    _pageBlockedCount = 0;
    _pageBlockedDomains.clear();
    _webViewCanGoBack = false;
    _webViewCanGoForward = false;
    await _controller?.loadRequest(Uri.parse('about:blank'));
    notifyListeners();
  }

  Future<void> goBack() async {
    if (!isShowingStartPage &&
        !isShowingHeavenSearch &&
        _controller != null &&
        await _controller!.canGoBack()) {
      await _controller!.goBack();
      await _refreshNavigationState();
      return;
    }

    if (_virtualIndex > 0) {
      _virtualIndex -= 1;
      await _restoreVirtualLocation(_virtualHistory[_virtualIndex]);
    }
  }

  Future<void> goForward() async {
    if (!isShowingStartPage &&
        !isShowingHeavenSearch &&
        _controller != null &&
        await _controller!.canGoForward()) {
      await _controller!.goForward();
      await _refreshNavigationState();
      return;
    }

    if (_virtualIndex < _virtualHistory.length - 1) {
      _virtualIndex += 1;
      await _restoreVirtualLocation(_virtualHistory[_virtualIndex]);
    }
  }

  Future<void> _restoreVirtualLocation(String target) async {
    _errorMessage = null;
    _pullProgress = 0;
    if (target.isEmpty) {
      _currentUrl = null;
      _pageTitle = isIncognito ? 'Incognito Tab' : 'New Tab';
      _isLoading = false;
      _progress = 0;
      _webViewCanGoBack = false;
      _webViewCanGoForward = false;
      notifyListeners();
      return;
    }

    if (OmniboxParser.isHeavenSearchUrl(target)) {
      _currentUrl = target;
      final String q = OmniboxParser.extractHeavenQuery(target);
      _pageTitle = q.isEmpty ? 'Heaven Search' : '$q — Heaven Search';
      _isLoading = false;
      _progress = 0;
      _webViewCanGoBack = false;
      _webViewCanGoForward = false;
      notifyListeners();
      return;
    }

    _currentUrl = target;
    _pageTitle = OmniboxParser.formatDisplayUrl(target);
    _isLoading = _controller != null;
    notifyListeners();
    await _controller?.loadRequest(
      Uri.parse(target),
      headers: _clientHintHeaders,
    );
  }

  Future<void> reloadFullPage() async {
    _errorMessage = null;
    if (isShowingStartPage) {
      notifyListeners();
      return;
    }
    if (isShowingHeavenSearch) {
      notifyListeners();
      return;
    }
    await _controller?.reload();
  }

  Future<void> reloadOrStop() async {
    if (isShowingHeavenSearch) {
      notifyListeners();
      return;
    }
    if (_controller == null) {
      return;
    }
    if (_isLoading) {
      await _controller!.runJavaScript('window.stop();');
      _isLoading = false;
      notifyListeners();
    } else {
      _errorMessage = null;
      await _controller!.reload();
    }
  }

  Future<int> findInPage(String term) async {
    if (_controller == null ||
        term.trim().isEmpty ||
        !settings.javascriptEnabled) {
      return 0;
    }
    final String escaped = jsonEncode(term.trim());
    try {
      final Object result = await _controller!.runJavaScriptReturningResult('''
(function() {
  const q = $escaped.toLowerCase();
  if (!q) return 0;
  window.find($escaped, false, false, true, false, true, false);
  const bodyText = (document.body && document.body.innerText) ? document.body.innerText.toLowerCase() : '';
  return bodyText.split(q).length - 1;
})();
''');
      return int.tryParse(result.toString().replaceAll('"', '')) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<ReadableArticle?> extractReadableArticle() async {
    if (_controller == null ||
        isShowingStartPage ||
        isShowingHeavenSearch ||
        !settings.javascriptEnabled) {
      return null;
    }
    try {
      final Object raw = await _controller!.runJavaScriptReturningResult('''
(function() {
  const root = document.querySelector('article, [role="main"], main') || document.body;
  if (!root) return '';
  const blocks = Array.from(root.querySelectorAll('h1, h2, h3, p, li'))
    .map(el => (el.innerText || '').replace(/\\s+/g, ' ').trim())
    .filter(txt => txt.length >= 38);
  const deduped = [];
  const seen = new Set();
  for (const b of blocks) {
    if (!seen.has(b)) {
      seen.add(b);
      deduped.push(b);
    }
    if (deduped.length >= 80) break;
  }
  return JSON.stringify({
    title: document.title || '',
    site: window.location.hostname || '',
    paragraphs: deduped
  });
})();
''');

      String jsonStr = raw.toString();
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        jsonStr = jsonDecode(jsonStr) as String;
      }
      if (jsonStr.isEmpty) {
        return null;
      }
      final Object? parsed = jsonDecode(jsonStr);
      if (parsed is Map<String, Object?>) {
        final List<String> paragraphs = (parsed['paragraphs'] is List<Object?>)
            ? (parsed['paragraphs']! as List<Object?>)
                  .map((Object? e) => e?.toString().trim() ?? '')
                  .where((String s) => s.isNotEmpty)
                  .toList()
            : <String>[];
        if (paragraphs.isEmpty) {
          return null;
        }
        return ReadableArticle(
          title: (parsed['title']?.toString() ?? _pageTitle).trim(),
          siteName: OmniboxParser.cleanDomain(
            parsed['site']?.toString() ?? currentHost,
          ),
          paragraphs: paragraphs,
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> burnBrowsingData() async {
    if (_controller != null) {
      await _controller!.clearCache();
      await _controller!.clearLocalStorage();
      final WebViewCookieManager cookieManager = WebViewCookieManager();
      await cookieManager.clearCookies();
    }
    _virtualHistory
      ..clear()
      ..add('');
    _virtualIndex = 0;
    await goHome();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    if (_androidWebViewId != null) {
      NativeShieldBridge.instance.detachWebView(_androidWebViewId!);
    }
    super.dispose();
  }
}
