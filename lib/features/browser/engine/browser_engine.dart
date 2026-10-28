import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/omnibox_parser.dart';
import '../../devtools/devtools_models.dart';
import '../../settings/browser_settings.dart';
import '../../shield/native_shield_bridge.dart';
import '../page_translate_reader_service.dart';

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

typedef SitePermissionPromptCallback =
    Future<bool> Function(String host, List<SitePermissionType> types);

class BrowserEngine extends ChangeNotifier {
  BrowserEngine({
    required this.settings,
    required this.isIncognito,
    this.enablePlatformWebView = true,
    bool deferWebViewInit = false,
    String? initialPersistedUrl,
    String? initialPersistedTitle,
  }) {
    _lastAppliedSettingsRevision = settings.webViewConfigRevision;
    settings.addListener(_onSettingsChanged);

    final String cleanInitialUrl = (initialPersistedUrl ?? '').trim();
    if (cleanInitialUrl.isNotEmpty) {
      if (OmniboxParser.isDownloadsUrl(cleanInitialUrl)) {
        _currentUrl = AppConstants.downloadsTabUrl;
        _pageTitle = 'Downloads';
        _virtualHistory
          ..clear()
          ..add(AppConstants.downloadsTabUrl);
        _virtualIndex = 0;
      } else {
        _currentUrl = cleanInitialUrl;
        _lastCompletedWebUrl = cleanInitialUrl;
        _pageTitle = (initialPersistedTitle ?? '').trim().isNotEmpty
            ? initialPersistedTitle!.trim()
            : OmniboxParser.formatDisplayUrl(cleanInitialUrl);
        _virtualHistory
          ..clear()
          ..add(cleanInitialUrl);
        _virtualIndex = 0;
      }
    }

    // Lazy WebView allocation for weak/old phones: only create a Chromium
    // WebView immediately when actively restoring a visible web page!
    if (enablePlatformWebView && !deferWebViewInit && isShowingWebPage) {
      _initializeController();
      final Uri? restoredUri = Uri.tryParse(_currentUrl!);
      if (restoredUri != null) {
        unawaited(_loadRestoredUri(restoredUri));
      }
    }
  }

  static bool _didPrewarmSearch = false;

  final BrowserSettingsController settings;
  SitePermissionPromptCallback? onSitePermissionPrompt;
  NativeWebContextMenuCallback? onWebContextMenu;
  final bool isIncognito;
  final bool enablePlatformWebView;

  WebViewController? _controller;
  Widget? _cachedWebViewWidget;
  int? _androidWebViewId;
  String? _pageIconUrl;
  int _lastAppliedSettingsRevision = -1;

  final List<String> _virtualHistory = <String>[''];
  int _virtualIndex = 0;

  String? _currentUrl;
  String _pageTitle = 'New Tab';
  double _progress = 0;
  double _pullProgress = 0;
  bool _isLoading = false;
  bool _webViewCanGoBack = false;
  bool _webViewCanGoForward = false;
  String? _errorMessage;
  String? _lastCompletedWebUrl;
  int _lastDownloadInterceptMs = 0;
  int _lastPageFinishedMs = 0;
  int _userInitiatedLoadUntilMs = 0;
  int _lastCrossSiteNavMs = 0;
  int _isGoingBackUntilMs = 0;
  int _lastBackPressMs = 0;
  String? _lastBackOriginUrl;
  String? _lastSettledWebUrl;
  final List<String> _settledSiteBackStack = <String>[];
  Timer? _finishLoadingDebounceTimer;
  Timer? _settleHistoryTimer;

  // Live Background Audio state
  bool _isMediaPlaying = false;
  String _playingMediaTitle = '';

  // Live Instant Page Translate state
  bool _isPageTranslated = false;
  bool _isTranslatingPage = false;
  String? _translatedLangCode;

  // Cached WebView configuration state (prevents redundant setInitialScale/UA resets & glitching!)
  bool? _appliedAllowJs;
  String? _appliedUserAgent;
  int? _appliedTextScale;
  bool? _appliedEffectiveDesktop;
  bool? _appliedAllow3pCookies;
  bool _mediaGestureConfigured = false;
  double _lastNotifiedProgress = 0.0;

  // Desktop Inspect / DevTools runtime state
  final List<DevToolsConsoleEntry> _consoleEntries = <DevToolsConsoleEntry>[];
  final List<DevToolsNetworkEntry> _networkEntries = <DevToolsNetworkEntry>[];
  DevToolsInspectedElement? _inspectedElement;
  bool _elementPickerActive = false;
  bool _pageDesignMode = false;
  bool _devToolsEnabled = false;

  bool get hasLiveWebView => _controller != null;

  WebViewController? get controller => _controller;

  /// Returns a stable cached native Hybrid Composition [WebViewWidget] for the
  /// active [WebViewController] so Chromium renders directly into the Android
  /// Window RenderNode at 60/90/120Hz without Surface.lockHardwareCanvas()
  /// offscreen texture contention or widget recreation jitter.
  Widget? get cachedWebViewWidget {
    final WebViewController? ctrl = _controller;
    if (ctrl == null) {
      return null;
    }
    final Widget? existing = _cachedWebViewWidget;
    if (existing != null) {
      return existing;
    }
    final Widget created = ctrl.platform is AndroidWebViewController
        ? WebViewWidget.fromPlatformCreationParams(
            params: AndroidWebViewWidgetCreationParams(
              key: ValueKey<Object>(ctrl),
              controller: ctrl.platform,
              displayWithHybridComposition: true,
            ),
          )
        : WebViewWidget(key: ValueKey<Object>(ctrl), controller: ctrl);
    _cachedWebViewWidget = created;
    return created;
  }
  int? get androidWebViewId => _androidWebViewId;
  String? get pageIconUrl => _pageIconUrl;
  String? get currentUrl => _currentUrl;
  bool get isShowingStartPage => _currentUrl == null || _currentUrl!.isEmpty;
  bool get isShowingDownloadsPage => OmniboxParser.isDownloadsUrl(_currentUrl);
  bool get isShowingWebPage => !isShowingStartPage && !isShowingDownloadsPage;
  bool get isNavBarVisible => true;
  bool get isMediaPlaying => _isMediaPlaying;
  String get playingMediaTitle => _playingMediaTitle;
  bool get isPageTranslated => _isPageTranslated;
  bool get isTranslatingPage => _isTranslatingPage;
  String? get translatedLangCode => _translatedLangCode;

  List<DevToolsConsoleEntry> get consoleEntries =>
      List<DevToolsConsoleEntry>.unmodifiable(_consoleEntries);
  List<DevToolsNetworkEntry> get networkEntries =>
      List<DevToolsNetworkEntry>.unmodifiable(_networkEntries);
  DevToolsInspectedElement? get inspectedElement => _inspectedElement;
  bool get isElementPickerActive => _elementPickerActive;
  bool get isPageDesignMode => _pageDesignMode;
  int get consoleErrorCount =>
      _consoleEntries.where((DevToolsConsoleEntry e) => e.isError).length;
  String get pageTitle => _pageTitle;
  double get progress => _progress;
  double get pullProgress => _pullProgress;
  bool get isLoading => _isLoading;

  bool get canGoBack =>
      (isShowingWebPage &&
          (_webViewCanGoBack || _settledSiteBackStack.isNotEmpty)) ||
      _virtualIndex > 0;

  bool get canGoForward =>
      (isShowingWebPage && _webViewCanGoForward) ||
      _virtualIndex < _virtualHistory.length - 1;

  String? get errorMessage => _errorMessage;

  bool get isSecure =>
      isShowingDownloadsPage ||
      (_currentUrl != null && _currentUrl!.startsWith('https://'));

  String? get currentHost {
    if (_currentUrl == null ||
        _currentUrl!.isEmpty ||
        isShowingDownloadsPage) {
      return null;
    }
    final Uri? parsed = Uri.tryParse(_currentUrl!);
    return (parsed != null && parsed.host.isNotEmpty) ? parsed.host : null;
  }

  Map<String, String> _headersForTarget({String? host, String? fullUrl}) {
    final String acceptLang = settings.shieldPreventLangFp
        ? 'en-US,en;q=0.9'
        : settings.language.acceptLanguageHeader;
    final Map<String, String> out = settings.desktopMode
        ? <String, String>{
            'Sec-CH-UA':
                '"Chromium";v="134", "Not:A-Brand";v="24", "Google Chrome";v="134"',
            'Sec-CH-UA-Mobile': '?0',
            'Sec-CH-UA-Platform': '"Windows"',
            'Accept-Language': acceptLang,
          }
        : <String, String>{
            'Sec-CH-UA-Mobile': '?1',
            'Sec-CH-UA-Platform': '"Android"',
            'Accept-Language': acceptLang,
          };
    if (settings.sendDntAndGpc) {
      out['DNT'] = '1';
      out['Sec-GPC'] = '1';
    }
    return out;
  }

  void _resetCachedControllerFlags() {
    _appliedAllowJs = null;
    _appliedUserAgent = null;
    _appliedTextScale = null;
    _appliedEffectiveDesktop = null;
    _appliedAllow3pCookies = null;
    _mediaGestureConfigured = false;
  }

  void setNavBarVisible(bool visible, {bool respectCooldown = false}) {
    // Search bar remains permanently visible above websites (no auto-hide).
  }

  void handleWebScrollDelta(double scrollY, double deltaY) {
    // Search bar remains permanently visible above websites (zero scroll rebuild churn).
  }

  Future<void> focusNativeWebView() async {
    if (enablePlatformWebView && isShowingWebPage && _controller == null) {
      _initializeController();
      final Uri? restoredUri = Uri.tryParse(_currentUrl!);
      if (restoredUri != null) {
        await _loadRestoredUri(restoredUri);
      }
      if (_androidWebViewId != null) {
        await NativeShieldBridge.instance.focusWebView(_androidWebViewId!);
      }
      return;
    }
    if (_androidWebViewId != null && isShowingWebPage) {
      await NativeShieldBridge.instance.focusWebView(_androidWebViewId!);
    }
  }

  /// Releases native Chromium WebView memory on idle background tabs so weak/old
  /// phones can keep dozens of tabs open without RAM pressure.
  void hibernateWebView() {
    if (_controller == null || _isMediaPlaying) {
      return;
    }
    _finishLoadingDebounceTimer?.cancel();
    _finishLoadingDebounceTimer = null;
    if (_androidWebViewId != null) {
      NativeShieldBridge.instance.detachWebView(_androidWebViewId!);
    }
    _controller = null;
    _cachedWebViewWidget = null;
    _androidWebViewId = null;
    _isLoading = false;
    _progress = 0;
    _pullProgress = 0;
    _webViewCanGoBack = false;
    _webViewCanGoForward = false;
    _resetCachedControllerFlags();
  }

  Future<void> _loadRestoredUri(Uri uri) async {
    _markUserInitiatedLoad();
    _isLoading = _controller != null;
    _progress = 0.1;
    notifyListeners();
    if (_androidWebViewId != null) {
      unawaited(
        NativeShieldBridge.instance.updatePageHost(
          webViewId: _androidWebViewId!,
          pageHost: uri.host,
        ),
      );
    }
    await _applyControllerSettings(forHost: uri.host);
    await _controller?.loadRequest(uri, headers: _headersForTarget());
  }

  void _markUserInitiatedLoad() {
    _userInitiatedLoadUntilMs = DateTime.now().millisecondsSinceEpoch + 1600;
  }

  static bool _isOAuthOrSsoFlow(Uri uri) {
    final String h = uri.host.toLowerCase();
    final String p = uri.path.toLowerCase();
    if (p.contains('/oauth') ||
        p.contains('/authorize') ||
        p.contains('/auth/') ||
        p.contains('/saml') ||
        p.contains('/openid')) {
      return true;
    }
    return (h == 'accounts.google.com' ||
            h == 'appleid.apple.com' ||
            h == 'login.microsoftonline.com' ||
            h == 'auth0.com' ||
            h.endsWith('.auth0.com')) &&
        (p.contains('signin') || p.contains('login') || p.contains('auth'));
  }

  void _initializeController() {
    _resetCachedControllerFlags();
    _cachedWebViewWidget = null;
    final WebViewController webController = WebViewController();
    _controller = webController;

    unawaited(_applyControllerSettings());
    unawaited(_prewarmGoogleSearchConnection());

    unawaited(
      webController.addJavaScriptChannel(
        'HeavenDevToolsChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          _handleDevToolsChannelMessage(msg.message);
        },
      ),
    );

    unawaited(
      webController
          .setOnConsoleMessage((JavaScriptConsoleMessage msg) {
            if (msg.message.startsWith('__hb_')) return;
            _appendConsoleEntry(
              DevToolsConsoleEntry(
                timestamp: DateTime.now(),
                level: msg.level.name.toLowerCase(),
                message: msg.message,
              ),
            );
          })
          .catchError((Object _) {}),
    );

    unawaited(
      webController.platform
          .setOnPlatformPermissionRequest(_handleWebPermissionRequest)
          .catchError((Object _) {}),
    );

    unawaited(
      webController.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigationRequest,
          onPageStarted: (String url) {
            if (url == 'about:blank' && !isShowingWebPage) {
              return;
            }
            _finishLoadingDebounceTimer?.cancel();
            _finishLoadingDebounceTimer = null;
            _settleHistoryTimer?.cancel();
            _settleHistoryTimer = null;
            final int nowMs = DateTime.now().millisecondsSinceEpoch;
            final bool isFastRedirect =
                _isLoading || (nowMs - _lastPageFinishedMs) < 420;
            final String? nextHost = Uri.tryParse(url)?.host;
            _onWebUrlTransition(url);
            _currentUrl = url;
            _pageIconUrl = null;
            _elementPickerActive = false;
            _pageDesignMode = false;
            _networkEntries.clear();
            _isLoading = true;
            if (isFastRedirect) {
              // Keep progress moving forward monotonically across search/HTTP redirects
              // so the blue loading bar NEVER resets back to 0 and restarts a second time!
              if (_progress < 0.18) {
                _progress = 0.18;
              } else if (_progress > 0.82) {
                _progress = 0.82;
              }
            } else {
              _progress = 0.12;
            }
            _lastNotifiedProgress = _progress;
            _pullProgress = 0;
            _errorMessage = null;
            _syncVirtualEntryWithWebUrl(url);
            if (_androidWebViewId != null) {
              unawaited(
                NativeShieldBridge.instance.updatePageHost(
                  webViewId: _androidWebViewId!,
                  pageHost: nextHost,
                ),
              );
            }
            notifyListeners();
          },
          onProgress: (int value) {
            if (!isShowingWebPage || !_isLoading) {
              return;
            }
            // Do NOT flip _isLoading=false on onProgress(100): Chromium emits 100%
            // on intermediate search redirects before onPageStarted of the target page!
            final double capped = (value.clamp(12, 94)) / 100.0;
            if (capped <= _progress) {
              return;
            }
            _progress = capped;
            if ((_progress - _lastNotifiedProgress).abs() >= 0.08) {
              _lastNotifiedProgress = _progress;
              notifyListeners();
            }
          },
          onPageFinished: (String url) async {
            if (url == 'about:blank' && !isShowingWebPage) {
              _finishLoadingDebounceTimer?.cancel();
              _isLoading = false;
              _progress = 0;
              notifyListeners();
              return;
            }
            _currentUrl = url;
            _lastCompletedWebUrl = url;
            _lastPageFinishedMs = DateTime.now().millisecondsSinceEpoch;
            _progress = 1.0;
            _lastNotifiedProgress = 1.0;
            _pullProgress = 0;
            _syncVirtualEntryWithWebUrl(url);
            if (_androidWebViewId != null) {
              unawaited(
                NativeShieldBridge.instance.recordWebUrlCommit(
                  webViewId: _androidWebViewId,
                  url: url,
                ),
              );
            }
            _scheduleSettledWebUrlCommit(url);
            notifyListeners();

            // Settle guard: if an immediate client/HTTP redirect starts within 180ms
            // (e.g. Google Search sei= handshake), onPageStarted cancels this timer
            // so the user sees ONE seamless single-pass blue loading bar!
            _finishLoadingDebounceTimer?.cancel();
            _finishLoadingDebounceTimer = Timer(
              const Duration(milliseconds: 180),
              () {
                _finishLoadingDebounceTimer = null;
                _userInitiatedLoadUntilMs = 0;
                if (_isLoading) {
                  _isLoading = false;
                  _progress = 0;
                  notifyListeners();
                }
              },
            );

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
                nextUrl != 'about:blank' &&
                !isShowingDownloadsPage) {
              _onWebUrlTransition(nextUrl);
              _currentUrl = nextUrl;
              _syncVirtualEntryWithWebUrl(nextUrl);
              if (_androidWebViewId != null) {
                unawaited(
                  NativeShieldBridge.instance.recordWebUrlCommit(
                    webViewId: _androidWebViewId,
                    url: nextUrl,
                  ),
                );
              }
              unawaited(_refreshNavigationState());
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame ?? true) {
              final String desc = error.description.toUpperCase();
              final bool recentlyInterceptedDownload =
                  (DateTime.now().millisecondsSinceEpoch -
                      _lastDownloadInterceptMs) <
                  3500;
              if (recentlyInterceptedDownload) {
                _finishLoadingDebounceTimer?.cancel();
                _isLoading = false;
                _progress = 0;
                _errorMessage = null;
                if (_lastCompletedWebUrl != null) {
                  _currentUrl = _lastCompletedWebUrl;
                  _syncVirtualEntryWithWebUrl(_lastCompletedWebUrl!);
                }
                notifyListeners();
                return;
              }
              if (desc.contains('ERR_ABORTED') ||
                  desc.contains('INTERRUPTED') ||
                  error.errorCode == -999) {
                return;
              }
              _finishLoadingDebounceTimer?.cancel();
              _isLoading = false;
              _progress = 0;
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
        androidCtrl
            .setGeolocationPermissionsPromptCallbacks(
              onShowPrompt: _handleGeolocationPrompt,
              onHidePrompt: () {},
            )
            .catchError((Object _) {}),
      );
      unawaited(
        NativeShieldBridge.instance.attachWebView(
          webViewId: androidCtrl.webViewIdentifier,
          desktopMode: settings.desktopMode,
          pageHost: currentHost,
          onPullProgress: (double value) {
            if ((_pullProgress - value).abs() >= 0.025 || value == 0.0) {
              _pullProgress = value;
              notifyListeners();
            }
          },
          onPullRefresh: () {
            _pullProgress = 0;
            unawaited(reloadFullPage());
          },
          onDownloadIntercepted: (bool wasEmptyPage) {
            _lastDownloadInterceptMs = DateTime.now().millisecondsSinceEpoch;
            _isLoading = false;
            _progress = 0;
            _errorMessage = null;
            if (wasEmptyPage && _lastCompletedWebUrl == null) {
              openDownloadsPage();
              return;
            } else if (_lastCompletedWebUrl != null) {
              _currentUrl = _lastCompletedWebUrl;
              _syncVirtualEntryWithWebUrl(_lastCompletedWebUrl!);
            }
            notifyListeners();
          },
          onConsoleMessage:
              (String level, String message, String sourceId, int line) {
                if (message.startsWith('__hb_')) return;
                _appendConsoleEntry(
                  DevToolsConsoleEntry(
                    timestamp: DateTime.now(),
                    level: level,
                    message: message,
                    source: sourceId,
                    line: line,
                  ),
                );
              },
          onMediaPlaybackChanged: (bool playing, String title) {
            if (_isMediaPlaying != playing || _playingMediaTitle != title) {
              _isMediaPlaying = playing;
              _playingMediaTitle = title;
              notifyListeners();
            }
          },
          onScrollNavBarChanged: (bool visible) {
            setNavBarVisible(visible);
          },
          onContextMenu: (WebContextMenuData data) {
            onWebContextMenu?.call(data);
          },
        ),
      );
    }
  }

  Future<void> _handleWebPermissionRequest(
    PlatformWebViewPermissionRequest request,
  ) async {
    final String host = OmniboxParser.cleanDomain(currentHost);
    if (host.isEmpty) {
      await request.deny();
      return;
    }
    final List<SitePermissionType> neededTypes = <SitePermissionType>[];
    final List<String> androidPerms = <String>[];

    for (final WebViewPermissionResourceType t in request.types) {
      if (t == WebViewPermissionResourceType.camera) {
        neededTypes.add(SitePermissionType.camera);
        androidPerms.add('android.permission.CAMERA');
      } else if (t == WebViewPermissionResourceType.microphone) {
        neededTypes.add(SitePermissionType.microphone);
        androidPerms.add('android.permission.RECORD_AUDIO');
      } else if (t == AndroidWebViewPermissionResourceType.protectedMediaId) {
        neededTypes.add(SitePermissionType.protectedMedia);
      }
    }

    if (neededTypes.isEmpty) {
      await request.deny();
      return;
    }

    for (final SitePermissionType t in neededTypes) {
      if (settings.getSitePermission(host, t) == SitePermissionDecision.block) {
        await request.deny();
        return;
      }
    }

    final List<SitePermissionType> undecided = neededTypes
        .where(
          (SitePermissionType t) =>
              settings.getSitePermission(host, t) == SitePermissionDecision.ask,
        )
        .toList();

    bool approved = true;
    if (undecided.isNotEmpty) {
      if (onSitePermissionPrompt != null) {
        approved = await onSitePermissionPrompt!(host, undecided);
      } else {
        approved = false;
      }
      for (final SitePermissionType t in undecided) {
        await settings.setSitePermission(
          host,
          t,
          approved ? SitePermissionDecision.allow : SitePermissionDecision.block,
        );
      }
    }

    if (!approved) {
      await request.deny();
      return;
    }

    if (androidPerms.isNotEmpty) {
      final bool hwGranted = await NativeShieldBridge.instance
          .requestSiteHardwarePermissions(androidPerms);
      if (!hwGranted) {
        await request.deny();
        return;
      }
    }

    await request.grant();
  }

  Future<GeolocationPermissionsResponse> _handleGeolocationPrompt(
    GeolocationPermissionsRequestParams params,
  ) async {
    final String host = OmniboxParser.cleanDomain(
      params.origin.isNotEmpty ? params.origin : currentHost,
    );
    if (host.isEmpty) {
      return const GeolocationPermissionsResponse(allow: false, retain: false);
    }

    final SitePermissionDecision current = settings.getSitePermission(
      host,
      SitePermissionType.location,
    );
    if (current == SitePermissionDecision.block) {
      return const GeolocationPermissionsResponse(allow: false, retain: false);
    }

    bool allow = current == SitePermissionDecision.allow;
    if (current == SitePermissionDecision.ask) {
      allow = onSitePermissionPrompt != null
          ? await onSitePermissionPrompt!(host, <SitePermissionType>[
              SitePermissionType.location,
            ])
          : false;
      await settings.setSitePermission(
        host,
        SitePermissionType.location,
        allow ? SitePermissionDecision.allow : SitePermissionDecision.block,
      );
    }

    if (!allow) {
      return const GeolocationPermissionsResponse(allow: false, retain: false);
    }

    final bool hwGranted = await NativeShieldBridge.instance
        .requestSiteHardwarePermissions(<String>[
          'android.permission.ACCESS_FINE_LOCATION',
          'android.permission.ACCESS_COARSE_LOCATION',
        ]);
    return GeolocationPermissionsResponse(allow: hwGranted, retain: false);
  }

  Future<Uint8List?> captureNativeWebViewPreview() async {
    if (_androidWebViewId == null || !isShowingWebPage) {
      return null;
    }
    return NativeShieldBridge.instance.captureWebViewPreview(
      _androidWebViewId!,
    );
  }

  void _onWebUrlTransition(String nextUrl) {
    if (!nextUrl.startsWith('http://') && !nextUrl.startsWith('https://')) {
      return;
    }
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs <= _isGoingBackUntilMs) {
      return;
    }
    final String? prevSettled = _lastSettledWebUrl;
    if (prevSettled != null &&
        prevSettled.isNotEmpty &&
        !OmniboxParser.isSameWebsite(prevSettled, nextUrl)) {
      if (_settledSiteBackStack.isEmpty ||
          !OmniboxParser.isSameWebsite(_settledSiteBackStack.last, prevSettled)) {
        if (_settledSiteBackStack.length >= 40) {
          _settledSiteBackStack.removeAt(0);
        }
        _settledSiteBackStack.add(prevSettled);
      }
      _lastSettledWebUrl = null;
    }
  }

  void _scheduleSettledWebUrlCommit(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return;
    }
    _settleHistoryTimer?.cancel();
    _settleHistoryTimer = Timer(const Duration(milliseconds: 450), () {
      _settleHistoryTimer = null;
      if (_currentUrl == url) {
        _lastSettledWebUrl = url;
      }
    });
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

  Future<NavigationDecision> _handleNavigationRequest(
    NavigationRequest request,
  ) async {
    final Uri? uri = Uri.tryParse(request.url);
    if (uri == null) {
      return NavigationDecision.prevent;
    }

    if (OmniboxParser.isDownloadsUrl(request.url)) {
      openDownloadsPage();
      return NavigationDecision.prevent;
    }

    if (uri.scheme == 'about' || uri.scheme == 'data' || uri.scheme == 'blob') {
      return NavigationDecision.navigate;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      if (settings.allowExternalAppLinks && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return NavigationDecision.prevent;
    }

    // Bypass top-level redirect tracking wrappers & AMP pages directly to canonical destination
    if (request.isMainFrame) {
      Uri resolvedUri =
          (settings.shieldCleanUrls
              ? OmniboxParser.unwrapTrackingRedirectUri(uri)
              : OmniboxParser.unwrapGoogleRedirectUri(uri)) ??
          uri;
      if (settings.isShieldActiveForHost(resolvedUri.host) &&
          settings.shieldAutoRedirectAmp) {
        resolvedUri = OmniboxParser.unwrapAmpUri(resolvedUri) ?? resolvedUri;
      }
      if (settings.desktopMode) {
        resolvedUri = rewriteMobileToDesktopUri(resolvedUri);
      }
      if (settings.httpsUpgrade &&
          resolvedUri.scheme == 'http' &&
          !OmniboxParser.isLocalOrPrivateHost(resolvedUri.host)) {
        resolvedUri = resolvedUri.replace(scheme: 'https');
      }
      if (settings.isShieldActiveForHost(resolvedUri.host) &&
          settings.shieldCleanUrls) {
        resolvedUri = BrowserSettingsController.stripTrackingParameters(
          resolvedUri,
        );
      }

      // Block pirate/streaming ad-redirect hijacks & rapid cross-site popunder bounce chains!
      if (settings.isShieldActiveForHost(currentHost)) {
        if (OmniboxParser.isKnownAdOrPopunderRedirect(
          resolvedUri,
          currentUrl: _currentUrl,
        )) {
          return NavigationDecision.prevent;
        }
        final int nowMs = DateTime.now().millisecondsSinceEpoch;
        final bool isUserDirectLoad =
            nowMs <= _userInitiatedLoadUntilMs || nowMs <= _isGoingBackUntilMs;
        final String? establishedUrl = _lastCompletedWebUrl;
        if (!isUserDirectLoad &&
            establishedUrl != null &&
            establishedUrl.isNotEmpty &&
            !_isOAuthOrSsoFlow(resolvedUri) &&
            !OmniboxParser.isSameWebsite(
              establishedUrl,
              resolvedUri.toString(),
            )) {
          if ((nowMs - _lastCrossSiteNavMs) < 650) {
            return NavigationDecision.prevent;
          }
          _lastCrossSiteNavMs = nowMs;
        }
      }

      _onWebUrlTransition(resolvedUri.toString());

      if (resolvedUri != uri) {
        await _applyControllerSettings(forHost: resolvedUri.host);
        await _controller?.loadRequest(
          resolvedUri,
          headers: _headersForTarget(),
        );
        return NavigationDecision.prevent;
      }
    }

    return NavigationDecision.navigate;
  }

  /// Evaluates a main-frame website redirect or link navigation (also usable in
  /// unit/widget tests without a platform WebView).
  Future<NavigationDecision> handleWebsiteNavigationOrRedirect(
    String targetUrl,
  ) {
    return _handleNavigationRequest(
      NavigationRequest(url: targetUrl, isMainFrame: true),
    );
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
    if (_lastAppliedSettingsRevision == settings.webViewConfigRevision) {
      return;
    }
    _lastAppliedSettingsRevision = settings.webViewConfigRevision;
    unawaited(_applyControllerSettings());
  }

  Future<void> _prewarmGoogleSearchConnection() async {
    if (_didPrewarmSearch) return;
    _didPrewarmSearch = true;
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final HttpClientRequest req = await client.getUrl(
        Uri.parse('https://www.google.com/generate_204'),
      );
      final HttpClientResponse res = await req.close().timeout(
        const Duration(seconds: 3),
      );
      await res.drain<void>();
    } catch (_) {
      // Best-effort DNS + TLS pre-warm.
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _applyControllerSettings({
    String? forHost,
    bool force = false,
  }) async {
    final WebViewController? webController = _controller;
    if (webController == null) {
      return;
    }

    final String? host = forHost ?? currentHost;
    final bool effectiveDesktop = settings.desktopMode;

    final bool allowJs = settings.isJavaScriptAllowedForHost(host);
    if (force || _appliedAllowJs != allowJs) {
      _appliedAllowJs = allowJs;
      await webController.setJavaScriptMode(
        allowJs ? JavaScriptMode.unrestricted : JavaScriptMode.disabled,
      );
    }

    final String desiredUa = effectiveDesktop
        ? AppConstants.desktopUserAgent
        : AppConstants.mobileUserAgent;
    if (force || _appliedUserAgent != desiredUa) {
      _appliedUserAgent = desiredUa;
      await webController.setUserAgent(desiredUa);
    }

    if (webController.platform
        case final AndroidWebViewController androidCtrl) {
      if (force || !_mediaGestureConfigured) {
        _mediaGestureConfigured = true;
        await androidCtrl.setMediaPlaybackRequiresUserGesture(false);
        await androidCtrl.enableZoom(true);
      }
      final int desiredScale = settings.textScalePercent;
      if (force || _appliedTextScale != desiredScale) {
        _appliedTextScale = desiredScale;
        await androidCtrl.setTextZoom(desiredScale);
      }
      if (force || _appliedEffectiveDesktop != effectiveDesktop) {
        _appliedEffectiveDesktop = effectiveDesktop;
        await NativeShieldBridge.instance.applyDesktopViewport(
          webViewId: androidCtrl.webViewIdentifier,
          desktopMode: effectiveDesktop,
        );
      }

      final bool allow3p = !isIncognito && !settings.blockThirdPartyCookies;
      if (force || _appliedAllow3pCookies != allow3p) {
        _appliedAllow3pCookies = allow3p;
        final WebViewCookieManager cookieManager = WebViewCookieManager();
        if (cookieManager.platform
            case final AndroidWebViewCookieManager androidCookies) {
          await androidCookies.setAcceptThirdPartyCookies(androidCtrl, allow3p);
        }
      }
    }
  }

  Future<void> setDesktopModeAndReload(bool enabled) async {
    _markUserInitiatedLoad();
    await settings.setDesktopMode(enabled);
    await _applyControllerSettings(force: true);

    final String? activeUrl = _currentUrl;
    if (activeUrl != null && isShowingWebPage && _controller != null) {
      Uri? parsed = Uri.tryParse(activeUrl);
      if (parsed != null) {
        if (enabled) {
          parsed = rewriteMobileToDesktopUri(parsed);
        }
        _currentUrl = parsed.toString();
        _isLoading = true;
        _errorMessage = null;
        notifyListeners();
        await _controller!.loadRequest(parsed, headers: _headersForTarget());
      }
    }
  }

  Future<void> _injectProtectionAndZoom(String url) async {
    final WebViewController? webController = _controller;
    final Uri? parsed = Uri.tryParse(url);
    if (webController == null ||
        !settings.isJavaScriptAllowedForHost(parsed?.host)) {
      return;
    }

    final StringBuffer combined = StringBuffer();
    if (settings.sendDntAndGpc) {
      combined.write(
        "(function(){try{Object.defineProperty(navigator,'globalPrivacyControl',{value:true,configurable:true});Object.defineProperty(navigator,'doNotTrack',{value:'1',configurable:true});}catch(_){}})();",
      );
    }

    try {
      if (combined.isNotEmpty) {
        await webController.runJavaScript(combined.toString());
      }
      if (_devToolsEnabled) {
        await webController.runJavaScript(_buildDevToolsAgentScript());
      }
    } catch (_) {
      // Ignore JS errors on non-HTML responses.
    }

    try {
      final Object rawIcon = await webController.runJavaScriptReturningResult(
        '(function(){'
        'var el=document.querySelector(\'link[rel*="apple-touch-icon"][href]\')'
        '||document.querySelector(\'link[rel="shortcut icon"][href]\')'
        '||document.querySelector(\'link[rel*="icon"][href]\');'
        'return el?el.href:"";'
        '})()',
      );
      String candidate = rawIcon.toString().trim();
      if (candidate.startsWith('"') &&
          candidate.endsWith('"') &&
          candidate.length >= 2) {
        candidate = candidate.substring(1, candidate.length - 1);
      }
      if (candidate.startsWith('http://') || candidate.startsWith('https://')) {
        _pageIconUrl = candidate;
      }
    } catch (_) {}
  }

  Future<void> _refreshNavigationState() async {
    final WebViewController? webController = _controller;
    if (webController == null || !isShowingWebPage) {
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

  void openDownloadsPage() {
    _finishLoadingDebounceTimer?.cancel();
    _finishLoadingDebounceTimer = null;
    _pushVirtualLocation(AppConstants.downloadsTabUrl);
    _currentUrl = AppConstants.downloadsTabUrl;
    _pageTitle = 'Downloads';
    _isLoading = false;
    _isPageTranslated = false;
    _translatedLangCode = null;
    _progress = 0;
    _pullProgress = 0;
    _errorMessage = null;
    _webViewCanGoBack = false;
    _webViewCanGoForward = false;
    notifyListeners();
  }

  Future<void> loadUserEntry(
    String rawInput, {
    bool replaceInitialBlankHistory = false,
  }) async {
    final String trimmed = rawInput.trim();
    if (OmniboxParser.isDownloadsUrl(trimmed)) {
      openDownloadsPage();
      return;
    }
    if (!isIncognito &&
        trimmed.isNotEmpty &&
        !OmniboxParser.looksLikeDirectDestination(trimmed)) {
      unawaited(settings.recordRecentSearch(trimmed));
    }
    final Uri target = OmniboxParser.resolveInput(
      trimmed,
      searchEngine: settings.searchEngine,
      httpsUpgrade: settings.httpsUpgrade,
      resolveEns: settings.resolveEnsDomains,
      resolveSns: settings.resolveSnsDomains,
      resolveUnstoppable: settings.resolveUnstoppableDomains,
    );
    await loadUri(
      target,
      replaceInitialBlankHistory: replaceInitialBlankHistory,
    );
  }

  Future<void> loadUri(
    Uri uri, {
    bool replaceInitialBlankHistory = false,
  }) async {
    if (OmniboxParser.isDownloadsUrl(uri.toString())) {
      openDownloadsPage();
      return;
    }
    _markUserInitiatedLoad();
    _finishLoadingDebounceTimer?.cancel();
    _finishLoadingDebounceTimer = null;
    _errorMessage = null;
    _pullProgress = 0;
    _isPageTranslated = false;
    _translatedLangCode = null;

    Uri migratedUri = uri;
    if (OmniboxParser.isLegacyHeavenUrl(migratedUri.toString())) {
      final String q = OmniboxParser.extractLegacyHeavenQuery(
        migratedUri.toString(),
      );
      migratedUri = SearchEngine.google.buildSearchUri(q);
    }

    Uri finalUri =
        (settings.shieldCleanUrls
            ? OmniboxParser.unwrapTrackingRedirectUri(migratedUri)
            : OmniboxParser.unwrapGoogleRedirectUri(migratedUri)) ??
        migratedUri;
    if (settings.isShieldActiveForHost(finalUri.host) &&
        settings.shieldAutoRedirectAmp) {
      finalUri = OmniboxParser.unwrapAmpUri(finalUri) ?? finalUri;
    }
    if (settings.desktopMode) {
      finalUri = rewriteMobileToDesktopUri(finalUri);
    }
    if (settings.httpsUpgrade &&
        finalUri.scheme == 'http' &&
        !OmniboxParser.isLocalOrPrivateHost(finalUri.host)) {
      finalUri = finalUri.replace(scheme: 'https');
    }
    if (settings.isShieldActiveForHost(finalUri.host) &&
        settings.shieldCleanUrls) {
      finalUri = BrowserSettingsController.stripTrackingParameters(finalUri);
    }

    final String targetUrl = finalUri.toString();
    if (replaceInitialBlankHistory &&
        _virtualHistory.length == 1 &&
        _virtualHistory.first.isEmpty) {
      _virtualHistory[0] = targetUrl;
      _virtualIndex = 0;
    } else {
      _pushVirtualLocation(targetUrl);
    }

    if (enablePlatformWebView && _controller == null) {
      _initializeController();
    }

    _currentUrl = targetUrl;
    _pageTitle = OmniboxParser.formatDisplayUrl(_currentUrl);
    _isLoading = true;
    _progress = 0.12;
    _lastNotifiedProgress = 0.12;
    notifyListeners();

    if (_androidWebViewId != null) {
      unawaited(
        NativeShieldBridge.instance.updatePageHost(
          webViewId: _androidWebViewId!,
          pageHost: finalUri.host,
        ),
      );
    }

    await _applyControllerSettings(forHost: finalUri.host);
    await _controller?.loadRequest(finalUri, headers: _headersForTarget());
    if (_controller == null) {
      _onWebUrlTransition(targetUrl);
      _lastCompletedWebUrl = targetUrl;
      _lastSettledWebUrl = targetUrl;
      _userInitiatedLoadUntilMs = 0;
      _isLoading = false;
      _progress = 0;
      if (!isIncognito &&
          (_currentUrl!.startsWith('http://') ||
              _currentUrl!.startsWith('https://'))) {
        await settings.recordPageVisit(url: _currentUrl!, title: _pageTitle);
      }
      notifyListeners();
    }
  }

  Future<void> goHome() async {
    _finishLoadingDebounceTimer?.cancel();
    _finishLoadingDebounceTimer = null;
    _settleHistoryTimer?.cancel();
    _settleHistoryTimer = null;
    _settledSiteBackStack.clear();
    _lastSettledWebUrl = null;
    _pushVirtualLocation('');
    _currentUrl = null;
    _pageTitle = isIncognito ? 'Incognito Tab' : 'New Tab';
    _isLoading = false;
    _progress = 0;
    _pullProgress = 0;
    _errorMessage = null;
    _isMediaPlaying = false;
    _webViewCanGoBack = false;
    _webViewCanGoForward = false;
    await _controller?.loadRequest(Uri.parse('about:blank'));
    notifyListeners();
  }

  Future<void> goBack() async {
    _markUserInitiatedLoad();
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    _isGoingBackUntilMs = nowMs + 2800;

    final String? originBeforeBack = _currentUrl;
    final bool bouncedBackToSameSite =
        originBeforeBack != null &&
        _lastBackOriginUrl != null &&
        (nowMs - _lastBackPressMs) < 5000 &&
        OmniboxParser.isSameWebsite(originBeforeBack, _lastBackOriginUrl!);
    _lastBackPressMs = nowMs;
    _lastBackOriginUrl = originBeforeBack;

    if (isShowingWebPage && _controller != null) {
      final Map<String, Object?> smart = await NativeShieldBridge.instance
          .smartGoBack(
            webViewId: _androidWebViewId,
            skipPredecessor: bouncedBackToSameSite,
          );
      if (smart['navigated'] == true) {
        final String targetUrl = (smart['targetUrl']?.toString() ?? '').trim();
        if (targetUrl.isNotEmpty) {
          _lastSettledWebUrl = targetUrl;
          while (_settledSiteBackStack.isNotEmpty &&
              OmniboxParser.isSameWebsite(
                _settledSiteBackStack.last,
                targetUrl,
              )) {
            _settledSiteBackStack.removeLast();
          }
        }
        await _refreshNavigationState();
        return;
      }

      // Only call raw WebView.goBack() if smartGoBack did NOT exhaust a redirect
      // trap chain at index 0 (otherwise raw goBack() would re-enter the redirect loop!)
      if (smart['exhaustedRedirectChain'] != true &&
          !bouncedBackToSameSite &&
          await _controller!.canGoBack()) {
        await _controller!.goBack();
        await _refreshNavigationState();
        return;
      }
    }

    // Fallback when a website redirected via location.replace() or exhausted a
    // redirect chain at index 0: step back to previous settled website or StartPage!
    if (isShowingWebPage && _settledSiteBackStack.isNotEmpty) {
      String previousSiteUrl = _settledSiteBackStack.removeLast();
      if (bouncedBackToSameSite &&
          OmniboxParser.isSameWebsite(previousSiteUrl, originBeforeBack) &&
          _settledSiteBackStack.isNotEmpty) {
        previousSiteUrl = _settledSiteBackStack.removeLast();
      }
      if (!bouncedBackToSameSite ||
          !OmniboxParser.isSameWebsite(previousSiteUrl, originBeforeBack)) {
        _lastSettledWebUrl = previousSiteUrl;
        _syncVirtualEntryWithWebUrl(previousSiteUrl);
        await _restoreVirtualLocation(previousSiteUrl);
        return;
      }
    }

    if (_virtualIndex > 0) {
      _virtualIndex -= 1;
      final String target = _virtualHistory[_virtualIndex];
      _lastSettledWebUrl =
          (target.startsWith('http://') || target.startsWith('https://'))
          ? target
          : null;
      await _restoreVirtualLocation(target);
      return;
    }

    // If tab started directly on a web URL (initialInput) whose redirect chain
    // was exhausted, return cleanly to StartPage instead of getting stuck!
    if (isShowingWebPage) {
      await goHome();
    }
  }

  Future<void> goForward() async {
    _markUserInitiatedLoad();
    if (isShowingWebPage &&
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
    _markUserInitiatedLoad();
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
    if (OmniboxParser.isDownloadsUrl(target)) {
      _currentUrl = AppConstants.downloadsTabUrl;
      _pageTitle = 'Downloads';
      _isLoading = false;
      _isPageTranslated = false;
      _translatedLangCode = null;
      _progress = 0;
      _webViewCanGoBack = false;
      _webViewCanGoForward = false;
      notifyListeners();
      return;
    }

    if (enablePlatformWebView && _controller == null) {
      _initializeController();
    }
    _currentUrl = target;
    _pageTitle = OmniboxParser.formatDisplayUrl(target);
    _isLoading = _controller != null;
    notifyListeners();
    final Uri parsedTarget = Uri.parse(target);
    await _applyControllerSettings(forHost: parsedTarget.host);
    await _controller?.loadRequest(
      parsedTarget,
      headers: _headersForTarget(host: parsedTarget.host, fullUrl: target),
    );
  }

  Future<void> reloadFullPage() async {
    _markUserInitiatedLoad();
    _finishLoadingDebounceTimer?.cancel();
    _finishLoadingDebounceTimer = null;
    _errorMessage = null;
    if (!isShowingWebPage) {
      notifyListeners();
      return;
    }
    if (enablePlatformWebView && _controller == null && _currentUrl != null) {
      _initializeController();
      notifyListeners();
      final Uri? target = Uri.tryParse(_currentUrl!);
      if (target != null) {
        await _applyControllerSettings(forHost: target.host);
        await _controller?.loadRequest(
          target,
          headers: _headersForTarget(host: target.host, fullUrl: _currentUrl),
        );
      }
      return;
    }
    await _controller?.reload();
  }

  Future<void> setDevToolsEnabled(bool enabled) async {
    _devToolsEnabled = enabled;
    if (enabled && _controller != null && isShowingWebPage) {
      try {
        await _controller!.runJavaScript(_buildDevToolsAgentScript());
      } catch (_) {}
    }
  }

  Future<void> reloadOrStop() async {
    if (!isShowingWebPage || _controller == null) {
      return;
    }
    if (_isLoading) {
      _finishLoadingDebounceTimer?.cancel();
      _finishLoadingDebounceTimer = null;
      await _controller!.runJavaScript('window.stop();');
      _isLoading = false;
      _progress = 0;
      notifyListeners();
    } else {
      _errorMessage = null;
      await _controller!.reload();
    }
  }

  Future<int> findInPage(String term) async {
    if (_controller == null ||
        !isShowingWebPage ||
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

  Future<bool> translateCurrentPage(
    String targetLangCode, {
    http.Client? client,
  }) async {
    if (!isShowingWebPage) {
      return false;
    }
    _isTranslatingPage = true;
    notifyListeners();
    try {
      await settings.setTranslateTargetLang(targetLangCode);
      if (_controller == null) {
        _isPageTranslated = true;
        _translatedLangCode = targetLangCode;
        return true;
      }

      final Object rawNodes = await _controller!.runJavaScriptReturningResult(r'''
(function(){
  try {
    const skip = new Set(['SCRIPT','STYLE','NOSCRIPT','CODE','PRE','TEXTAREA','INPUT','SVG','MATH']);
    const nodes = [];
    const texts = [];
    const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = walker.nextNode()) && nodes.length < 150) {
      const p = n.parentElement;
      if (!p || skip.has(p.tagName) || p.isContentEditable) continue;
      const orig = (typeof n.__hbOrigText === 'string') ? n.__hbOrigText : (n.nodeValue || '');
      const clean = orig.replace(/\s+/g, ' ').trim();
      if (clean.length < 3 || /^[0-9.,:%+$-]+$/.test(clean)) continue;
      n.__hbOrigText = orig;
      nodes.push(n);
      texts.push(clean);
    }
    window.__hbTxNodes = nodes;
    return JSON.stringify(texts);
  } catch (_) {
    return '[]';
  }
})()
''');

      String jsonStr = rawNodes.toString();
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        jsonStr = jsonDecode(jsonStr) as String;
      }
      final Object? parsed = jsonDecode(jsonStr);
      if (parsed is! List || parsed.isEmpty) {
        return false;
      }
      final List<String> originals = parsed
          .map((Object? e) => e?.toString() ?? '')
          .toList(growable: false);
      final List<String> translated =
          await PageTranslateReaderService.translateSegments(
            originals,
            targetLang: targetLangCode,
            client: client,
          );
      final String encodedTranslated = jsonEncode(translated);
      final String encodedLang = jsonEncode(targetLangCode);
      await _controller!.runJavaScript('''
(function(){
  try {
    const arr = $encodedTranslated;
    const nodes = window.__hbTxNodes || [];
    for (let i = 0; i < nodes.length && i < arr.length; i++) {
      if (arr[i]) nodes[i].nodeValue = ' ' + arr[i] + ' ';
    }
    document.documentElement.setAttribute('data-hb-translated', $encodedLang);
  } catch (_) {}
})();
''');
      _isPageTranslated = true;
      _translatedLangCode = targetLangCode;
      return true;
    } catch (_) {
      return false;
    } finally {
      _isTranslatingPage = false;
      notifyListeners();
    }
  }

  Future<void> restoreOriginalPageLanguage() async {
    if (_controller != null && isShowingWebPage) {
      try {
        await _controller!.runJavaScript('''
(function(){
  try {
    const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = walker.nextNode())) {
      if (typeof n.__hbOrigText === 'string') {
        n.nodeValue = n.__hbOrigText;
      }
    }
    document.documentElement.removeAttribute('data-hb-translated');
  } catch (_) {}
})();
''');
      } catch (_) {}
    }
    _isPageTranslated = false;
    _translatedLangCode = null;
    notifyListeners();
  }

  Future<ReadableArticle?> extractReadableArticle() async {
    if (!isShowingWebPage) {
      return null;
    }
    if (_controller == null) {
      return ReadableArticle(
        title: _pageTitle,
        siteName: OmniboxParser.cleanDomain(_currentUrl),
        paragraphs: <String>[
          'Clean Reader View formats $_pageTitle for distraction-free reading in Heaven.',
        ],
      );
    }
    if (!settings.javascriptEnabled) {
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

  /// Extracts clean spoken-word paragraphs from any webpage (articles, docs,
  /// forums, or general pages) for "Listen to This Page".
  Future<List<String>> extractListenParagraphs() async {
    final ReadableArticle? article = await extractReadableArticle();
    if (article != null && article.paragraphs.isNotEmpty) {
      return <String>[
        if (article.title.trim().isNotEmpty) article.title.trim(),
        ...article.paragraphs,
      ];
    }
    if (!isShowingWebPage || _controller == null) {
      return const <String>[];
    }
    try {
      final Object raw = await _controller!.runJavaScriptReturningResult('''
(function(){
  try {
    const out = [];
    const seen = new Set();
    const nodes = document.querySelectorAll('h1,h2,h3,p,li,blockquote');
    for (let i = 0; i < nodes.length && out.length < 90; i++) {
      const t = String(nodes[i].innerText || '').replace(/\\s+/g, ' ').trim();
      if (t.length >= 24 && !seen.has(t)) {
        seen.add(t);
        out.push(t);
      }
    }
    if (out.length === 0 && document.body) {
      const lines = String(document.body.innerText || '').split(/\\n+/);
      for (const ln of lines) {
        const clean = ln.replace(/\\s+/g, ' ').trim();
        if (clean.length >= 24 && out.length < 90) out.push(clean);
      }
    }
    return JSON.stringify(out);
  } catch (_) {
    return '[]';
  }
})()
''');
      String jsonStr = raw.toString();
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        jsonStr = jsonDecode(jsonStr).toString();
      }
      final Object? parsed = jsonDecode(jsonStr);
      if (parsed is List<Object?>) {
        return parsed
            .map((Object? e) => e?.toString().trim() ?? '')
            .where((String s) => s.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}
    return const <String>[];
  }

  ///Simulates a same-tab website redirect chain in headless tests (where there
  /// is no platform WebView) so Back navigation over transient hops can be verified.
  void recordHeadlessWebsiteRedirect(
    String targetUrl, {
    required bool isTransientHop,
  }) {
    _onWebUrlTransition(targetUrl);
    _currentUrl = targetUrl;
    _lastCompletedWebUrl = targetUrl;
    _syncVirtualEntryWithWebUrl(targetUrl);
    if (!isTransientHop) {
      _lastSettledWebUrl = targetUrl;
    }
    notifyListeners();
  }

  /// Navigates the active tab to a resolved Google Lens visual search URL
  /// returned by the native multipart uploader.
  Future<void> openGoogleLensResultUrl(String resultUrl) async {
    final String clean = resultUrl.trim();
    if (clean.isEmpty) return;
    await loadUserEntry(clean);
  }

  /// Uploads a JPEG image via native Google Lens multipart POST and opens the
  /// resulting Google Lens visual search results inside the active tab.
  Future<bool> loadGoogleLensImageBase64(
    String base64Jpeg, {
    double cropLeft = 0.0,
    double cropTop = 0.0,
    double cropRight = 1.0,
    double cropBottom = 1.0,
    String mode = 'search',
    String query = '',
  }) async {
    final String cleanB64 = base64Jpeg.trim();
    if (cleanB64.isEmpty) return false;
    final Map<String, Object?> res = await NativeShieldBridge.instance
        .lensSearchImageBytes(
          base64Jpeg: cleanB64,
          cropLeft: cropLeft,
          cropTop: cropTop,
          cropRight: cropRight,
          cropBottom: cropBottom,
          mode: mode,
          query: query,
          language: settings.language.code,
        );
    final String resultUrl = (res['resultUrl']?.toString() ?? '').trim();
    if (res['ok'] == true && resultUrl.isNotEmpty) {
      await openGoogleLensResultUrl(resultUrl);
      return true;
    }
    return false;
  }

  /// Opens a saved `.mht` offline webpage archive inside the active tab even
  /// with zero network connectivity.
  Future<bool> loadSavedOfflineArchive({
    required String filePath,
    required String title,
    required String originalUrl,
  }) async {
    _markUserInitiatedLoad();
    _errorMessage = null;
    if (enablePlatformWebView && _controller == null) {
      _initializeController();
    }
    final String displayTarget = originalUrl.trim().isNotEmpty
        ? originalUrl.trim()
        : 'https://offline.heaven.local';
    _pushVirtualLocation(displayTarget);
    _currentUrl = displayTarget;
    _pageTitle = title.trim().isNotEmpty ? title.trim() : 'Offline Page';
    _isLoading = false;
    _progress = 0;
    _lastCompletedWebUrl = displayTarget;
    notifyListeners();

    if (_controller == null) {
      return true;
    }
    return NativeShieldBridge.instance.loadOfflineArchive(
      webViewId: _androidWebViewId,
      filePath: filePath,
    );
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

  // ---------------------------------------------------------------------------
  // Desktop Browser Inspect / DevTools Engine
  // ---------------------------------------------------------------------------

  void _appendConsoleEntry(DevToolsConsoleEntry entry) {
    if (_consoleEntries.length >= 80) {
      _consoleEntries.removeAt(0);
    }
    _consoleEntries.add(entry);
    // Only notify UI when DevTools is open — prevents console spam from
    // rebuilding BrowserScreen dozens of times during webpage/YouTube loads!
    if (_devToolsEnabled) {
      notifyListeners();
    }
  }

  void clearConsoleLogs() {
    _consoleEntries.clear();
    notifyListeners();
  }

  void clearNetworkLogs() {
    _networkEntries.clear();
    notifyListeners();
  }

  void _handleDevToolsChannelMessage(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<Object?, Object?>) return;
      final String kind = decoded['kind']?.toString() ?? '';
      if (kind == 'picked_element' &&
          decoded['element'] is Map<Object?, Object?>) {
        _inspectedElement = DevToolsInspectedElement.fromMap(
          decoded['element']! as Map<Object?, Object?>,
        );
        _elementPickerActive = false;
        notifyListeners();
      } else if (kind == 'net' && decoded['entry'] is Map<Object?, Object?>) {
        final Map<Object?, Object?> e =
            decoded['entry']! as Map<Object?, Object?>;
        if (_networkEntries.length < 250) {
          _networkEntries.insert(
            0,
            DevToolsNetworkEntry(
              url: e['url']?.toString() ?? '',
              method: e['method']?.toString() ?? 'GET',
              type: e['type']?.toString() ?? 'xhr',
              status: (e['status'] as num?)?.toInt() ?? 200,
              durationMs: (e['dur'] as num?)?.toInt() ?? 0,
              transferBytes: (e['size'] as num?)?.toInt() ?? 0,
            ),
          );
          notifyListeners();
        }
      } else if (kind == 'error') {
        _appendConsoleEntry(
          DevToolsConsoleEntry(
            timestamp: DateTime.now(),
            level: 'error',
            message: decoded['message']?.toString() ?? 'Uncaught Error',
            source: decoded['source']?.toString() ?? '',
            line: (decoded['line'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    } catch (_) {
      // Ignore malformed DevTools event payloads.
    }
  }

  static String _buildDevToolsAgentScript() {
    return r'''
(function() {
  if (window.__heavenDevToolsV10) return;
  window.__heavenDevToolsV10 = {
    nextId: 1,
    nodeMap: new Map(),
    pickerOn: false,
    send(payload) {
      try {
        if (window.HeavenDevToolsChannel) {
          window.HeavenDevToolsChannel.postMessage(JSON.stringify(payload));
        }
      } catch (_) {}
    },
    ensureId(el) {
      if (!el || el.nodeType !== 1) return 0;
      let id = el.__hbNodeId;
      if (!id) {
        id = this.nextId++;
        el.__hbNodeId = id;
        this.nodeMap.set(id, el);
      }
      return id;
    },
    cssPath(el) {
      if (!el || el.nodeType !== 1) return '';
      if (el.id) return el.tagName.toLowerCase() + '#' + el.id;
      const cls = (typeof el.className === 'string' ? el.className.trim().split(/\s+/).slice(0, 2).join('.') : '');
      return el.tagName.toLowerCase() + (cls ? '.' + cls : '');
    },
    highlight(el) {
      let box = document.getElementById('__hb_devtools_hl');
      if (!el || !el.getBoundingClientRect) {
        if (box) box.style.display = 'none';
        return;
      }
      if (!box) {
        box = document.createElement('div');
        box.id = '__hb_devtools_hl';
        box.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483646;border:2px solid #2563EB;background:rgba(37,99,235,0.18);box-sizing:border-box;transition:all 80ms ease;';
        const badge = document.createElement('div');
        badge.id = '__hb_devtools_hl_lbl';
        badge.style.cssText = 'position:absolute;left:0;top:-22px;background:#0F172A;color:#F8FAFC;font:700 10px monospace;padding:2px 6px;border-radius:4px;white-space:nowrap;';
        box.appendChild(badge);
        document.documentElement.appendChild(box);
      }
      const r = el.getBoundingClientRect();
      box.style.display = 'block';
      box.style.left = r.left + 'px';
      box.style.top = r.top + 'px';
      box.style.width = Math.max(2, r.width) + 'px';
      box.style.height = Math.max(2, r.height) + 'px';
      const lbl = document.getElementById('__hb_devtools_hl_lbl');
      if (lbl) {
        lbl.textContent = this.cssPath(el) + ' (' + Math.round(r.width) + 'x' + Math.round(r.height) + ')';
        lbl.style.top = r.top < 24 ? '2px' : '-22px';
      }
    },
    serializeElement(el) {
      if (!el || el.nodeType !== 1) return null;
      const id = this.ensureId(el);
      const r = el.getBoundingClientRect();
      const attrs = {};
      if (el.attributes) {
        for (let i = 0; i < el.attributes.length; i++) {
          const a = el.attributes[i];
          attrs[a.name] = String(a.value || '').slice(0, 300);
        }
      }
      const cs = window.getComputedStyle(el);
      const keys = ['display', 'position', 'width', 'height', 'margin', 'padding', 'color', 'background-color', 'font-size', 'font-weight', 'z-index', 'opacity'];
      const comp = {};
      for (const k of keys) comp[k] = cs.getPropertyValue(k) || '';
      const rawHtml = el.outerHTML || '';
      return {
        nodeId: id,
        tag: el.tagName.toLowerCase(),
        selector: this.cssPath(el),
        outerHtml: rawHtml.length > 2400 ? rawHtml.slice(0, 2400) + '...' : rawHtml,
        inlineStyle: el.getAttribute('style') || '',
        dimensions: Math.round(r.width) + ' x ' + Math.round(r.height) + ' px',
        attributes: attrs,
        computedStyles: comp
      };
    }
  };

  if (window.fetch) {
    const origFetch = window.fetch;
    window.fetch = function(input, init) {
      const t0 = performance.now();
      const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      const method = (init && init.method) ? String(init.method).toUpperCase() : 'GET';
      return origFetch.apply(this, arguments).then(function(res) {
        window.__heavenDevToolsV10.send({
          kind: 'net',
          entry: { url: String(url), method: method, type: 'fetch', status: res.status || 200, dur: Math.round(performance.now() - t0), size: 0 }
        });
        return res;
      }).catch(function(err) {
        window.__heavenDevToolsV10.send({
          kind: 'net',
          entry: { url: String(url), method: method, type: 'fetch', status: 0, dur: Math.round(performance.now() - t0), size: 0 }
        });
        throw err;
      });
    };
  }
  const origOpen = XMLHttpRequest.prototype.open;
  const origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(m, u) {
    this.__hbMethod = String(m || 'GET').toUpperCase();
    this.__hbUrl = String(u || '');
    return origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function() {
    const t0 = performance.now();
    this.addEventListener('loadend', () => {
      let sz = 0;
      try {
        if (this.responseType === '' || this.responseType === 'text') {
          sz = this.responseText ? this.responseText.length : 0;
        }
      } catch (_) {}
      window.__heavenDevToolsV10.send({
        kind: 'net',
        entry: { url: this.__hbUrl || '', method: this.__hbMethod || 'GET', type: 'xhr', status: this.status || 0, dur: Math.round(performance.now() - t0), size: sz }
      });
    });
    return origSend.apply(this, arguments);
  };

  document.addEventListener('click', function(ev) {
    const dt = window.__heavenDevToolsV10;
    if (!dt || !dt.pickerOn) return;
    const t = ev.target;
    if (!t || (t.id && t.id.indexOf('__hb_devtools') === 0)) return;
    ev.preventDefault();
    ev.stopPropagation();
    dt.pickerOn = false;
    dt.highlight(t);
    dt.send({ kind: 'picked_element', element: dt.serializeElement(t) });
  }, true);

  window.addEventListener('error', function(ev) {
    if (!ev || !ev.message) return;
    window.__heavenDevToolsV10.send({
      kind: 'error',
      message: String(ev.message),
      source: String(ev.filename || ''),
      line: Number(ev.lineno || 0)
    });
  });
})();
''';
  }

  Future<Map<String, Object?>?> _evalJsonMap(String jsExpression) async {
    final WebViewController? ctrl = _controller;
    if (ctrl == null) return null;
    try {
      await ctrl.runJavaScript(_buildDevToolsAgentScript());
      final Object raw = await ctrl.runJavaScriptReturningResult(jsExpression);
      String text = raw.toString();
      if (text.startsWith('"') && text.endsWith('"')) {
        text = jsonDecode(text).toString();
      }
      final Object? parsed = jsonDecode(text);
      if (parsed is Map<Object?, Object?>) {
        return <String, Object?>{
          for (final MapEntry<Object?, Object?> e in parsed.entries)
            if (e.key != null) e.key.toString(): e.value,
        };
      }
    } catch (_) {
      // Non-fatal in headless tests or about:blank.
    }
    return null;
  }

  Future<void> setElementPickerActive(bool active) async {
    _elementPickerActive = active;
    notifyListeners();
    final WebViewController? ctrl = _controller;
    if (ctrl == null) return;
    try {
      await ctrl.runJavaScript(_buildDevToolsAgentScript());
      await ctrl.runJavaScript(
        'if(window.__heavenDevToolsV10){window.__heavenDevToolsV10.pickerOn=${active ? "true" : "false"};}',
      );
    } catch (_) {}
  }

  Future<void> clearInspectorHighlight({bool notify = true}) async {
    _elementPickerActive = false;
    if (notify) {
      notifyListeners();
    }
    try {
      await _controller?.runJavaScript(
        'if(window.__heavenDevToolsV10){window.__heavenDevToolsV10.pickerOn=false;window.__heavenDevToolsV10.highlight(null);}',
      );
    } catch (_) {}
  }

  Future<List<DevToolsDomNode>> fetchDomTreeNodes() async {
    final Map<String, Object?>? res = await _evalJsonMap('''
(function(){
  const dt = window.__heavenDevToolsV10;
  const out = [];
  function walk(el, depth) {
    if (!el || el.nodeType !== 1 || out.length >= 160 || depth > 7) return;
    if (el.id && el.id.indexOf('__hb_devtools') === 0) return;
    const id = dt.ensureId(el);
    let directText = '';
    for (let i = 0; i < el.childNodes.length; i++) {
      if (el.childNodes[i].nodeType === 3) {
        directText += el.childNodes[i].nodeValue || '';
      }
    }
    directText = directText.replace(/\\s+/g, ' ').trim().slice(0, 60);
    out.push({
      nodeId: id,
      tag: el.tagName.toLowerCase(),
      id: el.id || '',
      cls: typeof el.className === 'string' ? el.className.trim().slice(0, 50) : '',
      txt: directText,
      depth: depth,
      children: el.children ? el.children.length : 0
    });
    if (el.children) {
      for (let c = 0; c < el.children.length && out.length < 160; c++) {
        walk(el.children[c], depth + 1);
      }
    }
  }
  walk(document.documentElement, 0);
  return JSON.stringify({ nodes: out });
})()
''');
    if (res == null || res['nodes'] is! List<Object?>) {
      return const <DevToolsDomNode>[];
    }
    return (res['nodes']! as List<Object?>)
        .whereType<Map<Object?, Object?>>()
        .map(DevToolsDomNode.fromMap)
        .toList(growable: false);
  }

  Future<DevToolsInspectedElement?> inspectDomNode(int nodeId) async {
    final Map<String, Object?>? res = await _evalJsonMap('''
(function(){
  const dt = window.__heavenDevToolsV10;
  const el = dt.nodeMap.get($nodeId);
  if (!el) return JSON.stringify({});
  el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  dt.highlight(el);
  return JSON.stringify({ element: dt.serializeElement(el) });
})()
''');
    if (res != null && res['element'] is Map<Object?, Object?>) {
      _inspectedElement = DevToolsInspectedElement.fromMap(
        res['element']! as Map<Object?, Object?>,
      );
      notifyListeners();
      return _inspectedElement;
    }
    return null;
  }

  Future<void> mutateDomNode({
    required int nodeId,
    required String action,
    String value = '',
  }) async {
    final WebViewController? ctrl = _controller;
    if (ctrl == null) return;
    final String encodedVal = jsonEncode(value);
    try {
      await ctrl.runJavaScript('''
(function(){
  const dt = window.__heavenDevToolsV10;
  const el = dt && dt.nodeMap ? dt.nodeMap.get($nodeId) : null;
  if (!el) return;
  if ('$action' === 'style') el.setAttribute('style', $encodedVal);
  else if ('$action' === 'html') el.outerHTML = $encodedVal;
  else if ('$action' === 'hide') el.style.setProperty('display', 'none', 'important');
  else if ('$action' === 'remove') { dt.highlight(null); el.remove(); }
})()
''');
      if (action == 'remove') {
        _inspectedElement = null;
        notifyListeners();
      } else if (action != 'html') {
        await inspectDomNode(nodeId);
      }
    } catch (_) {}
  }

  Future<String> evaluateDevToolsJs(String code) async {
    final String clean = code.trim();
    if (clean.isEmpty) return '';
    _appendConsoleEntry(
      DevToolsConsoleEntry(
        timestamp: DateTime.now(),
        level: 'input',
        message: '> $clean',
      ),
    );
    final WebViewController? ctrl = _controller;
    if (ctrl == null) {
      const String fallback = 'undefined (no active web document)';
      _appendConsoleEntry(
        DevToolsConsoleEntry(
          timestamp: DateTime.now(),
          level: 'result',
          message: '< $fallback',
        ),
      );
      return fallback;
    }

    final String encodedExpr = jsonEncode(clean);
    try {
      final Object raw = await ctrl.runJavaScriptReturningResult('''
(function(){
  try {
    const val = (0, eval)($encodedExpr);
    if (val === undefined) return 'undefined';
    if (val === null) return 'null';
    if (typeof val === 'object') {
      try { return JSON.stringify(val, null, 2); } catch (_) { return String(val); }
    }
    return String(val);
  } catch (err) {
    return 'Uncaught ' + String(err);
  }
})()
''');
      String formatted = raw.toString();
      if (formatted.startsWith('"') && formatted.endsWith('"')) {
        try {
          formatted = jsonDecode(formatted).toString();
        } catch (_) {}
      }
      final bool isErr = formatted.startsWith('Uncaught ');
      _appendConsoleEntry(
        DevToolsConsoleEntry(
          timestamp: DateTime.now(),
          level: isErr ? 'error' : 'result',
          message: isErr ? formatted : '< $formatted',
        ),
      );
      return formatted;
    } catch (e) {
      final String errStr = e.toString();
      _appendConsoleEntry(
        DevToolsConsoleEntry(
          timestamp: DateTime.now(),
          level: 'error',
          message: errStr,
        ),
      );
      return errStr;
    }
  }

  Future<List<DevToolsNetworkEntry>> refreshNetworkResourceTimings() async {
    final Map<String, Object?>? res = await _evalJsonMap('''
(function(){
  const entries = (performance.getEntriesByType ? performance.getEntriesByType('resource') : []).slice(-90).reverse();
  const list = entries.map(e => ({
    url: e.name || '',
    type: e.initiatorType || 'other',
    dur: Math.round(e.duration || 0),
    size: e.transferSize || e.encodedBodySize || 0,
    status: e.responseStatus || 200
  }));
  return JSON.stringify({ list: list });
})()
''');
    final List<DevToolsNetworkEntry> combined = List<DevToolsNetworkEntry>.of(
      _networkEntries,
    );
    final Set<String> seenUrls = <String>{
      for (final DevToolsNetworkEntry e in combined) e.url,
    };
    if (res != null && res['list'] is List<Object?>) {
      for (final Object? item in res['list']! as List<Object?>) {
        if (item is Map<Object?, Object?>) {
          final String u = item['url']?.toString() ?? '';
          if (u.isEmpty || !seenUrls.add(u)) continue;
          combined.add(
            DevToolsNetworkEntry(
              url: u,
              method: 'GET',
              type: item['type']?.toString() ?? 'other',
              status: (item['status'] as num?)?.toInt() ?? 200,
              durationMs: (item['dur'] as num?)?.toInt() ?? 0,
              transferBytes: (item['size'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }
    }
    return combined;
  }

  Future<Map<String, Object?>> fetchStorageAndMetrics() async {
    final Map<String, Object?>? res = await _evalJsonMap('''
(function(){
  const ls = {};
  try {
    for (let i = 0; i < localStorage.length && i < 60; i++) {
      const k = localStorage.key(i);
      if (k !== null) ls[k] = String(localStorage.getItem(k) || '').slice(0, 300);
    }
  } catch (_) {}
  const ss = {};
  try {
    for (let i = 0; i < sessionStorage.length && i < 60; i++) {
      const k = sessionStorage.key(i);
      if (k !== null) ss[k] = String(sessionStorage.getItem(k) || '').slice(0, 300);
    }
  } catch (_) {}
  const navEntry = (performance.getEntriesByType && performance.getEntriesByType('navigation')[0]) || null;
  const loadMs = navEntry ? Math.round(navEntry.loadEventEnd || navEntry.duration || 0) : 0;
  return JSON.stringify({
    localStorage: ls,
    sessionStorage: ss,
    cookies: document.cookie || '',
    userAgent: navigator.userAgent || '',
    platform: navigator.platform || '',
    viewport: window.innerWidth + ' x ' + window.innerHeight + ' (@' + (window.devicePixelRatio || 1).toFixed(2) + 'x)',
    domNodes: document.getElementsByTagName('*').length,
    loadMs: loadMs,
    designMode: document.designMode === 'on'
  });
})()
''');
    return res ??
        <String, Object?>{
          'localStorage': const <String, Object?>{},
          'sessionStorage': const <String, Object?>{},
          'cookies': '',
          'userAgent': settings.desktopMode
              ? AppConstants.desktopUserAgent
              : AppConstants.mobileUserAgent,
          'platform': settings.desktopMode ? 'Win32' : 'Android',
          'viewport': 'Headless / Start Page',
          'domNodes': 0,
          'loadMs': 0,
          'designMode': _pageDesignMode,
        };
  }

  Future<void> updateWebStorageItem({
    required bool session,
    required String key,
    String? value,
  }) async {
    final WebViewController? ctrl = _controller;
    if (ctrl == null) return;
    final String target = session ? 'sessionStorage' : 'localStorage';
    final String kJson = jsonEncode(key);
    try {
      if (value == null) {
        await ctrl.runJavaScript('try{$target.removeItem($kJson);}catch(_){}');
      } else {
        final String vJson = jsonEncode(value);
        await ctrl.runJavaScript(
          'try{$target.setItem($kJson,$vJson);}catch(_){}',
        );
      }
    } catch (_) {}
  }

  Future<void> setPageDesignMode(bool enabled) async {
    _pageDesignMode = enabled;
    notifyListeners();
    try {
      await _controller?.runJavaScript(
        'document.designMode=${enabled ? '"on"' : '"off"'};',
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _finishLoadingDebounceTimer?.cancel();
    _finishLoadingDebounceTimer = null;
    _settleHistoryTimer?.cancel();
    _settleHistoryTimer = null;
    settings.removeListener(_onSettingsChanged);
    if (_androidWebViewId != null) {
      NativeShieldBridge.instance.detachWebView(_androidWebViewId!);
    }
    _cachedWebViewWidget = null;
    super.dispose();
  }
}
