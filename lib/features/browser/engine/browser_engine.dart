import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/omnibox_parser.dart';
import '../../devtools/devtools_models.dart';
import '../../extensions/extensions_controller.dart';
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

typedef SitePermissionPromptCallback =
    Future<bool> Function(String host, List<SitePermissionType> types);

class BrowserEngine extends ChangeNotifier {
  BrowserEngine({
    required this.settings,
    required this.isIncognito,
    this.extensions,
    this.onOpenNewTabFromExtension,
    this.enablePlatformWebView = true,
    String? initialPersistedUrl,
    String? initialPersistedTitle,
  }) {
    settings.addListener(_onSettingsChanged);
    extensions?.addListener(_onExtensionsChanged);

    final String cleanInitialUrl = (initialPersistedUrl ?? '').trim();
    if (cleanInitialUrl.isNotEmpty) {
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

    if (enablePlatformWebView) {
      _initializeController();
      if (_currentUrl != null && _currentUrl!.isNotEmpty) {
        final Uri? restoredUri = Uri.tryParse(_currentUrl!);
        if (restoredUri != null) {
          unawaited(_loadRestoredUri(restoredUri));
        }
      }
    }
  }

  final BrowserSettingsController settings;
  final ExtensionsController? extensions;
  final ValueChanged<String>? onOpenNewTabFromExtension;
  ValueChanged<String>? onWebStoreInstallMessage;
  SitePermissionPromptCallback? onSitePermissionPrompt;
  final bool isIncognito;
  final bool enablePlatformWebView;

  WebViewController? _controller;
  int? _androidWebViewId;
  String? _pageIconUrl;

  final List<String> _virtualHistory = <String>[''];
  int _virtualIndex = 0;

  String? _currentUrl;
  String _pageTitle = 'New Tab';
  double _progress = 0;
  double _pullProgress = 0;
  bool _isLoading = false;
  bool _isNavBarVisible = true;
  double _lastScrollY = 0;
  bool _webViewCanGoBack = false;
  bool _webViewCanGoForward = false;
  int _pageBlockedCount = 0;
  final Set<String> _pageBlockedDomains = <String>{};
  String? _errorMessage;
  String? _lastCompletedWebUrl;
  int _lastDownloadInterceptMs = 0;

  // Live Background Audio state
  bool _isMediaPlaying = false;
  String _playingMediaTitle = '';

  // Cached WebView configuration state (prevents redundant setInitialScale/UA resets & glitching!)
  bool? _appliedAllowJs;
  String? _appliedUserAgent;
  int? _appliedTextScale;
  bool? _appliedEffectiveDesktop;
  bool? _appliedForceDesktopStore;
  bool? _appliedAllow3pCookies;
  bool _mediaGestureConfigured = false;
  int _lastBlockedUiNotifyMs = 0;
  double _lastNotifiedProgress = 0.0;

  // Desktop Inspect / DevTools runtime state
  final List<DevToolsConsoleEntry> _consoleEntries = <DevToolsConsoleEntry>[];
  final List<DevToolsNetworkEntry> _networkEntries = <DevToolsNetworkEntry>[];
  DevToolsInspectedElement? _inspectedElement;
  bool _elementPickerActive = false;
  bool _pageDesignMode = false;

  WebViewController? get controller => _controller;
  int? get androidWebViewId => _androidWebViewId;
  String? get pageIconUrl => _pageIconUrl;
  String? get currentUrl => _currentUrl;
  bool get isNavBarVisible => _isNavBarVisible || isShowingStartPage;
  bool get isMediaPlaying => _isMediaPlaying;
  String get playingMediaTitle => _playingMediaTitle;

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
  bool get isShowingStartPage => _currentUrl == null || _currentUrl!.isEmpty;

  bool get canGoBack =>
      (!isShowingStartPage && _webViewCanGoBack) || _virtualIndex > 0;

  bool get canGoForward =>
      (!isShowingStartPage && _webViewCanGoForward) ||
      _virtualIndex < _virtualHistory.length - 1;

  int get pageBlockedCount => _pageBlockedCount;
  List<String> get pageBlockedDomains =>
      _pageBlockedDomains.toList(growable: false);
  String? get errorMessage => _errorMessage;

  bool get isSecure => _currentUrl != null && _currentUrl!.startsWith('https://');

  String? get currentHost {
    if (_currentUrl == null || _currentUrl!.isEmpty) {
      return null;
    }
    final Uri? parsed = Uri.tryParse(_currentUrl!);
    return (parsed != null && parsed.host.isNotEmpty) ? parsed.host : null;
  }

  static bool _isChromeWebStoreHostOrUrl(String? host, String? fullUrl) {
    final String h = (host ?? '').toLowerCase();
    return h == 'chromewebstore.google.com' ||
        (h == 'chrome.google.com' &&
            (fullUrl?.toLowerCase().contains('/webstore') ?? false)) ||
        ExtensionsController.isChromeWebStoreUrl(fullUrl);
  }

  Map<String, String> _headersForTarget({String? host, String? fullUrl}) {
    final bool desktop =
        settings.desktopMode || _isChromeWebStoreHostOrUrl(host, fullUrl);
    if (desktop) {
      return <String, String>{
        'Sec-CH-UA':
            '"Chromium";v="134", "Not:A-Brand";v="24", "Google Chrome";v="134"',
        'Sec-CH-UA-Mobile': '?0',
        'Sec-CH-UA-Platform': '"Windows"',
        'Accept-Language': settings.language.acceptLanguageHeader,
      };
    }
    return <String, String>{
      'Sec-CH-UA-Mobile': '?1',
      'Sec-CH-UA-Platform': '"Android"',
      'Accept-Language': settings.language.acceptLanguageHeader,
    };
  }

  void _resetCachedControllerFlags() {
    _appliedAllowJs = null;
    _appliedUserAgent = null;
    _appliedTextScale = null;
    _appliedEffectiveDesktop = null;
    _appliedForceDesktopStore = null;
    _appliedAllow3pCookies = null;
    _mediaGestureConfigured = false;
  }

  void setNavBarVisible(bool visible) {
    final bool next = isShowingStartPage ? true : visible;
    if (_isNavBarVisible != next) {
      _isNavBarVisible = next;
      notifyListeners();
    }
  }

  /// Updates top navigation bar visibility from scroll position & vertical delta:
  /// scrolling down hides the bar; scrolling up (or near top) reveals it.
  void handleWebScrollDelta(double scrollY, double deltaY) {
    if (isShowingStartPage) {
      setNavBarVisible(true);
      return;
    }
    if (scrollY <= 16 || deltaY <= -12) {
      setNavBarVisible(true);
    } else if (deltaY >= 16 && scrollY > 42) {
      setNavBarVisible(false);
    }
  }

  Future<void> _loadRestoredUri(Uri uri) async {
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
      unawaited(
        NativeShieldBridge.instance.approveExternalNavigation(
          webViewId: _androidWebViewId!,
          host: uri.host,
        ),
      );
    }
    await _applyControllerSettings(forHost: uri.host);
    await _controller?.loadRequest(
      uri,
      headers: _headersForTarget(host: uri.host, fullUrl: uri.toString()),
    );
  }

  void _initializeController() {
    _resetCachedControllerFlags();
    final WebViewController webController = WebViewController();
    _controller = webController;

    unawaited(_applyControllerSettings());
    unawaited(_prewarmGoogleSearchConnection());

    unawaited(
      webController.addJavaScriptChannel(
        'HeavenShieldChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          final String payload = msg.message.trim();
          if (payload.startsWith('ALLOW_NAV:')) {
            final String allowedHost = payload.substring('ALLOW_NAV:'.length);
            if (_androidWebViewId != null && allowedHost.isNotEmpty) {
              unawaited(
                NativeShieldBridge.instance.approveExternalNavigation(
                  webViewId: _androidWebViewId!,
                  host: allowedHost,
                ),
              );
            }
            return;
          }
          _recordBlockedResource(payload);
        },
      ),
    );

    unawaited(
      webController.addJavaScriptChannel(
        'HeavenChromeExtChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          _handleChromeExtChannelMessage(msg.message);
        },
      ),
    );

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
      webController
          .setOnScrollPositionChange((ScrollPositionChange pos) {
            final double dy = pos.y - _lastScrollY;
            _lastScrollY = pos.y;
            handleWebScrollDelta(pos.y, dy);
          })
          .catchError((Object _) {}),
    );

    unawaited(
      webController.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigationRequest,
          onPageStarted: (String url) {
            if (url == 'about:blank' && isShowingStartPage) {
              return;
            }
            final String? nextHost = Uri.tryParse(url)?.host;
            _currentUrl = url;
            _isNavBarVisible = true;
            _lastScrollY = 0;
            _pageIconUrl = null;
            _elementPickerActive = false;
            _pageDesignMode = false;
            _networkEntries.clear();
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
                  pageHost: nextHost,
                ),
              );
            }
            notifyListeners();
          },
          onProgress: (int value) {
            if (isShowingStartPage) {
              return;
            }
            final double nextProgress = (value.clamp(0, 100)) / 100.0;
            final bool nextLoading = value < 100;
            final bool loadingChanged = _isLoading != nextLoading;
            final bool significantStep =
                (nextProgress - _lastNotifiedProgress).abs() >= 0.04 ||
                value >= 100;
            _progress = nextProgress;
            _isLoading = nextLoading;
            if (loadingChanged || significantStep) {
              _lastNotifiedProgress = nextProgress;
              notifyListeners();
            }
          },
          onPageFinished: (String url) async {
            if (url == 'about:blank' && isShowingStartPage) {
              _isLoading = false;
              _progress = 0;
              notifyListeners();
              return;
            }
            _currentUrl = url;
            _lastCompletedWebUrl = url;
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
              final bool changed = _currentUrl != nextUrl;
              _currentUrl = nextUrl;
              _syncVirtualEntryWithWebUrl(nextUrl);
              unawaited(_refreshNavigationState());
              if (changed) {
                unawaited(reinjectActiveExtensions());
              }
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
          onBlocked: (int _, String domain, int bytesSaved) {
            _recordBlockedResource(domain, bytesSaved: bytesSaved);
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
          onDownloadIntercepted: (bool wasEmptyPage) {
            _lastDownloadInterceptMs = DateTime.now().millisecondsSinceEpoch;
            _isLoading = false;
            _progress = 0;
            _errorMessage = null;
            if (wasEmptyPage && _lastCompletedWebUrl == null) {
              _currentUrl = null;
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
    if (_androidWebViewId == null || isShowingStartPage) {
      return null;
    }
    return NativeShieldBridge.instance.captureWebViewPreview(
      _androidWebViewId!,
    );
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

  void _recordBlockedResource(String domainOrTag, {int bytesSaved = 14200}) {
    _pageBlockedCount += 1;
    if (domainOrTag.isNotEmpty) {
      _pageBlockedDomains.add(domainOrTag);
      if (_networkEntries.length < 250) {
        _networkEntries.insert(
          0,
          DevToolsNetworkEntry(
            url: 'https://$domainOrTag',
            method: 'BLOCKED',
            type: 'shield',
            status: 0,
            durationMs: 0,
            blocked: true,
          ),
        );
      }
    }
    unawaited(settings.incrementBlockedCount(1, bytesSaved));
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBlockedUiNotifyMs >= 240 || _pageBlockedCount <= 2) {
      _lastBlockedUiNotifyMs = now;
      notifyListeners();
    }
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

    // Rewrite Chrome/Firefox extension scheme URLs to virtual extension host — NEVER block them!
    final String lowerScheme = uri.scheme.toLowerCase();
    if (lowerScheme == 'chrome-extension' || lowerScheme == 'moz-extension') {
      final String extPath = uri.path.isEmpty ? '/' : uri.path;
      final Uri mapped = Uri(
        scheme: 'https',
        host: 'chrome-ext.heaven.local',
        path: '/${uri.host}$extPath',
        query: uri.hasQuery ? uri.query : null,
        fragment: uri.hasFragment ? uri.fragment : null,
      );
      await _controller?.loadRequest(mapped);
      return NavigationDecision.prevent;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      final bool blocksRedirect =
          (settings.antiRedirectProtection || settings.shieldEnabled) &&
          !settings.isHostTrusted(currentHost);
      if (blocksRedirect && uri.scheme != 'mailto' && uri.scheme != 'tel') {
        _recordBlockedResource('${uri.scheme}-redirect');
        unawaited(settings.incrementRedirectBlockedCount());
        return NavigationDecision.prevent;
      }
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return NavigationDecision.prevent;
    }

    final String destLowerHost = uri.host.toLowerCase();
    final String prevLowerHost = (currentHost ?? '').toLowerCase();

    // Always allow Chrome Extension virtual pages and any redirect initiated from an extension!
    if (destLowerHost == 'chrome-ext.heaven.local' ||
        prevLowerHost == 'chrome-ext.heaven.local') {
      return NavigationDecision.navigate;
    }

    // Automatic Anti-Redirect protection against unsolicited Play Store hijacks
    if (request.isMainFrame &&
        settings.antiRedirectProtection &&
        !settings.isHostTrusted(currentHost) &&
        destLowerHost == 'play.google.com' &&
        prevLowerHost.isNotEmpty &&
        !prevLowerHost.endsWith('google.com')) {
      _recordBlockedResource('play.google.com-hijack');
      unawaited(settings.incrementRedirectBlockedCount());
      return NavigationDecision.prevent;
    }

    // Bypass Google's /url?q=... redirect wrapper directly to the destination
    if (request.isMainFrame) {
      final Uri? unwrappedGoogle = OmniboxParser.unwrapGoogleRedirectUri(uri);
      if (unwrappedGoogle != null && unwrappedGoogle != uri) {
        await _applyControllerSettings(forHost: unwrappedGoogle.host);
        await _controller?.loadRequest(
          unwrappedGoogle,
          headers: _headersForTarget(
            host: unwrappedGoogle.host,
            fullUrl: unwrappedGoogle.toString(),
          ),
        );
        return NavigationDecision.prevent;
      }
    }

    // If Desktop Mode is enabled and a site redirects to m.example.com, rewrite to desktop host
    if (request.isMainFrame && settings.desktopMode) {
      final Uri desktopUri = rewriteMobileToDesktopUri(uri);
      if (desktopUri != uri) {
        await _controller?.loadRequest(
          desktopUri,
          headers: _headersForTarget(
            host: desktopUri.host,
            fullUrl: desktopUri.toString(),
          ),
        );
        return NavigationDecision.prevent;
      }
    }

    final bool shieldActiveForSite =
        settings.shieldEnabled && !settings.isHostTrusted(currentHost);

    if (shieldActiveForSite &&
        HeavenShield.shouldBlockUri(uri, pageHost: currentHost)) {
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
          headers: _headersForTarget(
            host: stripped.uri.host,
            fullUrl: stripped.uri.toString(),
          ),
        );
        notifyListeners();
        return NavigationDecision.prevent;
      }
    }

    if (request.isMainFrame &&
        settings.httpsUpgrade &&
        uri.scheme == 'http' &&
        !OmniboxParser.isLocalOrPrivateHost(uri.host)) {
      final Uri httpsUri = uri.replace(scheme: 'https');
      await _controller?.loadRequest(
        httpsUri,
        headers: _headersForTarget(
          host: httpsUri.host,
          fullUrl: httpsUri.toString(),
        ),
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

  void _onExtensionsChanged() {
    final String? url = _currentUrl;
    if (url != null && !isShowingStartPage) {
      unawaited(reinjectActiveExtensions());
    }
  }

  Future<void> _prewarmGoogleSearchConnection() async {
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
    final bool forceDesktopStore = _isChromeWebStoreHostOrUrl(
      host,
      _currentUrl,
    );
    final bool effectiveDesktop = settings.desktopMode || forceDesktopStore;

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
      if (force ||
          _appliedEffectiveDesktop != effectiveDesktop ||
          _appliedForceDesktopStore != forceDesktopStore) {
        _appliedEffectiveDesktop = effectiveDesktop;
        _appliedForceDesktopStore = forceDesktopStore;
        if (forceDesktopStore) {
          await NativeShieldBridge.instance.prepareChromeWebStoreView(
            androidCtrl.webViewIdentifier,
          );
        } else {
          await NativeShieldBridge.instance.applyDesktopViewport(
            webViewId: androidCtrl.webViewIdentifier,
            desktopMode: effectiveDesktop,
          );
        }
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
    await settings.setDesktopMode(enabled);
    await _applyControllerSettings(force: true);

    final String? activeUrl = _currentUrl;
    if (activeUrl != null && !isShowingStartPage && _controller != null) {
      Uri? parsed = Uri.tryParse(activeUrl);
      if (parsed != null) {
        if (enabled) {
          parsed = rewriteMobileToDesktopUri(parsed);
        }
        _currentUrl = parsed.toString();
        _isLoading = true;
        _errorMessage = null;
        notifyListeners();
        await _controller!.loadRequest(
          parsed,
          headers: _headersForTarget(
            host: parsed.host,
            fullUrl: parsed.toString(),
          ),
        );
      }
    }
  }

  void _handleChromeExtChannelMessage(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<Object?, Object?>) return;
      final String extId = decoded['extId']?.toString() ?? '';
      final String op = decoded['op']?.toString() ?? '';
      final Object? data = decoded['data'];
      if (op == 'storage_set' && extId.isNotEmpty && data != null) {
        unawaited(
          NativeShieldBridge.instance.updateChromeExtensionStorage(
            extId,
            jsonEncode(data),
          ),
        );
      } else if (op == 'open_tab' && data is Map<Object?, Object?>) {
        final String target = data['url']?.toString() ?? '';
        if (target.isNotEmpty) {
          onOpenNewTabFromExtension?.call(target);
        }
      } else if (op == 'reload_tab') {
        unawaited(reloadFullPage());
      } else if (op == 'install_cws' && extensions != null) {
        final String cwsUrl = (data is Map<Object?, Object?>)
            ? (data['url']?.toString() ?? extId)
            : extId;
        unawaited(() async {
          final String? err = await extensions!.installFromWebStore(cwsUrl);
          if (err == null) {
            await _controller?.runJavaScript(
              '(function(){var bs=document.querySelectorAll("button");for(var i=0;i<bs.length;i++){if(bs[i].textContent&&bs[i].textContent.indexOf("Installing in Heaven")!==-1){bs[i].textContent="Added to Heaven";}}})();',
            );
          }
          onWebStoreInstallMessage?.call(
            err ?? 'Chrome Extension (.crx) installed in Heaven!',
          );
        }());
      }
    } catch (_) {
      // Ignore malformed messages.
    }
  }

  Future<void> reinjectActiveExtensions() async {
    final WebViewController? webController = _controller;
    final String? url = _currentUrl;
    if (webController == null ||
        extensions == null ||
        url == null ||
        isShowingStartPage) {
      return;
    }
    final Uri? parsed = Uri.tryParse(url);
    if (!settings.isJavaScriptAllowedForHost(parsed?.host)) {
      return;
    }
    final String crxAndScripts = await extensions!.buildFullInjectionForUrl(
      url,
    );
    if (crxAndScripts.isNotEmpty) {
      try {
        await webController.runJavaScript(crxAndScripts);
      } catch (_) {}
    }
  }

  Future<void> _injectProtectionAndZoom(String url) async {
    final WebViewController? webController = _controller;
    final Uri? parsed = Uri.tryParse(url);
    final String lowerHost = (parsed?.host ?? '').toLowerCase();
    // Never overwrite window.open or run ad-blocker scripts inside Chrome Extension tabs!
    if (lowerHost == 'chrome-ext.heaven.local') {
      return;
    }
    if (webController == null ||
        !settings.isJavaScriptAllowedForHost(parsed?.host)) {
      return;
    }

    final bool trusted = settings.isHostTrusted(parsed?.host);
    final bool blockPopups = settings.arePopupsBlockedForHost(parsed?.host);
    final StringBuffer combined = StringBuffer(
      HeavenShield.buildProtectionScript(
        shieldEnabled: settings.shieldEnabled && !trusted,
        sendDntAndGpc: settings.sendDntAndGpc,
      ),
    );
    if (blockPopups) {
      combined.write(
        '\n;(function(){try{window.open=function(){return null;};}catch(_){}})();',
      );
    }
    if (settings.ultraDataSaverMode) {
      combined.write(
        '\n;(function(){try{if(!document.getElementById("__hb_uds")){var s=document.createElement("style");s.id="__hb_uds";s.textContent="img,picture,video,canvas,svg.hero,[style*=\\"background-image\\"]{display:none!important;}";(document.head||document.documentElement).appendChild(s);}}catch(_){}})();',
      );
    }

    try {
      await webController.runJavaScript(combined.toString());
      await webController.runJavaScript(_buildDevToolsAgentScript());
    } catch (_) {
      // Ignore JS errors on non-HTML responses.
    }

    await reinjectActiveExtensions();

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
    final String trimmed = rawInput.trim();
    if (!isIncognito &&
        trimmed.isNotEmpty &&
        !OmniboxParser.looksLikeDirectDestination(trimmed)) {
      unawaited(settings.recordRecentSearch(trimmed));
    }
    final Uri target = OmniboxParser.resolveInput(
      trimmed,
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
    _isNavBarVisible = true;
    _lastScrollY = 0;

    // Rewrite chrome-extension:// or moz-extension:// to https://chrome-ext.heaven.local/...
    Uri migratedUri = uri;
    final String lowerScheme = migratedUri.scheme.toLowerCase();
    if (lowerScheme == 'chrome-extension' || lowerScheme == 'moz-extension') {
      final String extPath = migratedUri.path.isEmpty ? '/' : migratedUri.path;
      migratedUri = Uri(
        scheme: 'https',
        host: 'chrome-ext.heaven.local',
        path: '/${migratedUri.host}$extPath',
        query: migratedUri.hasQuery ? migratedUri.query : null,
        fragment: migratedUri.hasFragment ? migratedUri.fragment : null,
      );
    } else if (OmniboxParser.isLegacyHeavenUrl(migratedUri.toString())) {
      final String q = OmniboxParser.extractLegacyHeavenQuery(
        migratedUri.toString(),
      );
      migratedUri = SearchEngine.google.buildSearchUri(q);
    }

    final bool isExtTarget =
        migratedUri.host.toLowerCase() == 'chrome-ext.heaven.local';
    Uri finalUri = isExtTarget
        ? migratedUri
        : (OmniboxParser.unwrapGoogleRedirectUri(migratedUri) ?? migratedUri);
    if (!isExtTarget && settings.desktopMode) {
      finalUri = rewriteMobileToDesktopUri(finalUri);
    }
    final bool shieldActive =
        !isExtTarget &&
        settings.shieldEnabled &&
        !settings.isHostTrusted(finalUri.host);
    if (shieldActive) {
      final ({Uri uri, int removedCount}) stripped =
          HeavenShield.stripTrackingParameters(finalUri);
      finalUri = stripped.uri;
      if (stripped.removedCount > 0) {
        _pageBlockedCount += stripped.removedCount;
        await settings.incrementBlockedCount(stripped.removedCount);
      }
    }
    if (settings.httpsUpgrade &&
        finalUri.scheme == 'http' &&
        !OmniboxParser.isLocalOrPrivateHost(finalUri.host)) {
      finalUri = finalUri.replace(scheme: 'https');
    }

    final String targetUrl = finalUri.toString();
    _pushVirtualLocation(targetUrl);

    _currentUrl = targetUrl;
    _pageTitle = OmniboxParser.formatDisplayUrl(_currentUrl);
    _isLoading = true;
    _progress = 0.08;
    _lastNotifiedProgress = 0.08;
    notifyListeners();

    if (_androidWebViewId != null) {
      unawaited(
        NativeShieldBridge.instance.updatePageHost(
          webViewId: _androidWebViewId!,
          pageHost: finalUri.host,
        ),
      );
      unawaited(
        NativeShieldBridge.instance.approveExternalNavigation(
          webViewId: _androidWebViewId!,
          host: finalUri.host,
        ),
      );
    }

    await _applyControllerSettings(forHost: finalUri.host);
    await _controller?.loadRequest(
      finalUri,
      headers: _headersForTarget(
        host: finalUri.host,
        fullUrl: finalUri.toString(),
      ),
    );
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
    _isNavBarVisible = true;
    _lastScrollY = 0;
    _progress = 0;
    _pullProgress = 0;
    _errorMessage = null;
    _pageBlockedCount = 0;
    _pageBlockedDomains.clear();
    _isMediaPlaying = false;
    _webViewCanGoBack = false;
    _webViewCanGoForward = false;
    await _controller?.loadRequest(Uri.parse('about:blank'));
    notifyListeners();
  }

  Future<void> goBack() async {
    _isNavBarVisible = true;
    if (!isShowingStartPage &&
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
    _isNavBarVisible = true;
    if (!isShowingStartPage &&
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
    _errorMessage = null;
    _isNavBarVisible = true;
    if (isShowingStartPage) {
      notifyListeners();
      return;
    }
    await _controller?.reload();
  }

  Future<void> reloadOrStop() async {
    _isNavBarVisible = true;
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

  // ---------------------------------------------------------------------------
  // Desktop Browser Inspect / DevTools Engine
  // ---------------------------------------------------------------------------

  void _appendConsoleEntry(DevToolsConsoleEntry entry) {
    if (_consoleEntries.length >= 250) {
      _consoleEntries.removeAt(0);
    }
    _consoleEntries.add(entry);
    notifyListeners();
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
      window.__heavenDevToolsV10.send({
        kind: 'net',
        entry: { url: this.__hbUrl || '', method: this.__hbMethod || 'GET', type: 'xhr', status: this.status || 0, dur: Math.round(performance.now() - t0), size: (this.responseText ? this.responseText.length : 0) }
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
    final List<DevToolsNetworkEntry> combined = <DevToolsNetworkEntry>[
      ..._networkEntries.where((DevToolsNetworkEntry e) => e.blocked),
      ..._networkEntries.where((DevToolsNetworkEntry e) => !e.blocked),
    ];
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
    settings.removeListener(_onSettingsChanged);
    extensions?.removeListener(_onExtensionsChanged);
    if (_androidWebViewId != null) {
      NativeShieldBridge.instance.detachWebView(_androidWebViewId!);
    }
    super.dispose();
  }
}
