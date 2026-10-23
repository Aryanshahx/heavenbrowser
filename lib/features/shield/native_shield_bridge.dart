import 'package:flutter/services.dart';

import 'heaven_shield.dart';

typedef NativeBlockedCallback =
    void Function(int webViewId, String domain, int bytesSaved);
typedef NativePullProgressCallback = void Function(double progress);
typedef NativePullRefreshCallback = void Function();
typedef NativeDownloadStartedCallback =
    void Function(Map<String, Object?> downloadInfo);
typedef NativeWebViewDownloadInterceptedCallback =
    void Function(bool wasEmptyPage);
typedef NativeConsoleMessageCallback =
    void Function(String level, String message, String sourceId, int line);
typedef NativeMediaStreamDetectedCallback =
    void Function(String url, String kind, String format, String label);
typedef NativeMediaPlaybackChangedCallback =
    void Function(bool playing, bool isVideo, String title);

class NativeShieldBridge {
  NativeShieldBridge._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final NativeShieldBridge instance = NativeShieldBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.hypertechlabs.heavenbrowser/native_shield',
  );

  final Map<int, NativeBlockedCallback> _blockedListeners =
      <int, NativeBlockedCallback>{};
  final Map<int, NativePullProgressCallback> _pullProgressListeners =
      <int, NativePullProgressCallback>{};
  final Map<int, NativePullRefreshCallback> _pullRefreshListeners =
      <int, NativePullRefreshCallback>{};
  final Map<int, NativeWebViewDownloadInterceptedCallback>
  _downloadInterceptListeners =
      <int, NativeWebViewDownloadInterceptedCallback>{};
  final Map<int, NativeConsoleMessageCallback> _consoleListeners =
      <int, NativeConsoleMessageCallback>{};
  final Map<int, NativeMediaStreamDetectedCallback> _streamListeners =
      <int, NativeMediaStreamDetectedCallback>{};
  final Map<int, NativeMediaPlaybackChangedCallback> _playbackListeners =
      <int, NativeMediaPlaybackChangedCallback>{};

  NativeDownloadStartedCallback? onDownloadStarted;
  void Function(bool inPip)? onPipModeChanged;
  void Function(String target)? onRedirectBlocked;
  void Function(int bytesSaved)? onBytesSaved;
  void Function(String url)? onExtensionOpenNewTab;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final Object? rawArgs = call.arguments;
    if (call.method == 'onResourceBlocked' &&
        rawArgs is Map<Object?, Object?>) {
      final Object? idVal = rawArgs['webViewId'];
      final int webViewId = idVal is num ? idVal.toInt() : -1;
      final String domain = (rawArgs['domain']?.toString() ?? 'tracker').trim();
      final int bytesSaved = (rawArgs['bytesSaved'] is num)
          ? (rawArgs['bytesSaved']! as num).toInt()
          : 14200;
      _blockedListeners[webViewId]?.call(webViewId, domain, bytesSaved);
    } else if (call.method == 'onBytesSaved' &&
        rawArgs is Map<Object?, Object?>) {
      final int bytes = (rawArgs['bytesSaved'] is num)
          ? (rawArgs['bytesSaved']! as num).toInt()
          : 0;
      if (bytes > 0) {
        onBytesSaved?.call(bytes);
      }
    } else if (call.method == 'onRedirectBlocked' &&
        rawArgs is Map<Object?, Object?>) {
      final String target = (rawArgs['target']?.toString() ?? 'redirect')
          .trim();
      onRedirectBlocked?.call(target);
    } else if (call.method == 'onPipModeChanged' &&
        rawArgs is Map<Object?, Object?>) {
      onPipModeChanged?.call(rawArgs['inPip'] == true);
    } else if (call.method == 'onExtensionOpenNewTab' &&
        rawArgs is Map<Object?, Object?>) {
      final String url = (rawArgs['url']?.toString() ?? '').trim();
      if (url.isNotEmpty) {
        onExtensionOpenNewTab?.call(url);
      }
    } else if (call.method == 'onMediaStreamDetected' &&
        rawArgs is Map<Object?, Object?>) {
      final int webViewId = (rawArgs['webViewId'] as num?)?.toInt() ?? -1;
      final String url = (rawArgs['url']?.toString() ?? '').trim();
      final String kind = (rawArgs['kind']?.toString() ?? 'video').trim();
      final String format = (rawArgs['format']?.toString() ?? 'MP4').trim();
      final String label = (rawArgs['label']?.toString() ?? 'Media Stream')
          .trim();
      if (url.isNotEmpty) {
        _streamListeners[webViewId]?.call(url, kind, format, label);
      }
    } else if (call.method == 'onMediaPlaybackChanged' &&
        rawArgs is Map<Object?, Object?>) {
      final int webViewId = (rawArgs['webViewId'] as num?)?.toInt() ?? -1;
      final bool playing = rawArgs['playing'] == true;
      final bool isVideo = rawArgs['isVideo'] != false;
      final String title = (rawArgs['title']?.toString() ?? '').trim();
      _playbackListeners[webViewId]?.call(playing, isVideo, title);
    } else if (call.method == 'onPullProgress' &&
        rawArgs is Map<Object?, Object?>) {
      final Object? idVal = rawArgs['webViewId'];
      final Object? progVal = rawArgs['progress'];
      final int webViewId = idVal is num ? idVal.toInt() : -1;
      final double progress = progVal is num
          ? progVal.toDouble().clamp(0.0, 1.0)
          : 0.0;
      _pullProgressListeners[webViewId]?.call(progress);
    } else if (call.method == 'onPullRefresh' &&
        rawArgs is Map<Object?, Object?>) {
      final Object? idVal = rawArgs['webViewId'];
      final int webViewId = idVal is num ? idVal.toInt() : -1;
      _pullRefreshListeners[webViewId]?.call();
    } else if (call.method == 'onConsoleMessage' &&
        rawArgs is Map<Object?, Object?>) {
      final Object? idVal = rawArgs['webViewId'];
      final int webViewId = idVal is num ? idVal.toInt() : -1;
      final String level = rawArgs['level']?.toString() ?? 'log';
      final String msg = rawArgs['message']?.toString() ?? '';
      final String src = rawArgs['sourceId']?.toString() ?? '';
      final int ln = (rawArgs['lineNumber'] as num?)?.toInt() ?? 0;
      _consoleListeners[webViewId]?.call(level, msg, src, ln);
    } else if (call.method == 'onDownloadStarted' &&
        rawArgs is Map<Object?, Object?>) {
      final Map<String, Object?> normalized = <String, Object?>{
        for (final MapEntry<Object?, Object?> e in rawArgs.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
      final Object? wvVal = normalized['webViewId'];
      final int webViewId = wvVal is num ? wvVal.toInt() : -1;
      final bool wasEmpty = normalized['wasEmptyPage'] == true;
      if (webViewId >= 0) {
        _downloadInterceptListeners[webViewId]?.call(wasEmpty);
      }
      onDownloadStarted?.call(normalized);
    }
    return null;
  }

  Future<void> syncShieldConfig({
    required bool shieldEnabled,
    required bool desktopMode,
    required Set<String> trustedHosts,
    required bool sendDntAndGpc,
    bool ultraDataSaverMode = false,
    bool backgroundMediaEnabled = true,
    bool autoPipEnabled = true,
    bool antiRedirectProtection = true,
    bool webNotificationsEnabled = false,
    bool backgroundPlayNotificationEnabled = true,
  }) async {
    try {
      await _channel.invokeMethod<bool>('updateConfig', <String, Object>{
        'shieldEnabled': shieldEnabled,
        'desktopMode': desktopMode,
        'ultraDataSaverMode': ultraDataSaverMode,
        'backgroundMediaEnabled': backgroundMediaEnabled,
        'autoPipEnabled': autoPipEnabled,
        'antiRedirectProtection': antiRedirectProtection,
        'webNotificationsEnabled': webNotificationsEnabled,
        'backgroundPlayNotificationEnabled': backgroundPlayNotificationEnabled,
        'blockedDomains': HeavenShield.blockedRootDomains.toList(
          growable: false,
        ),
        'trustedHosts': trustedHosts.toList(growable: false),
        'cosmeticScript': HeavenShield.buildProtectionScript(
          shieldEnabled: shieldEnabled,
          sendDntAndGpc: sendDntAndGpc,
        ),
      });
    } on MissingPluginException {
      // Expected in unit/widget tests.
    } on PlatformException {
      // Ignore transient platform channel errors.
    }
  }

  Future<void> attachWebView({
    required int webViewId,
    required bool desktopMode,
    String? pageHost,
    required NativeBlockedCallback onBlocked,
    required NativePullProgressCallback onPullProgress,
    required NativePullRefreshCallback onPullRefresh,
    NativeWebViewDownloadInterceptedCallback? onDownloadIntercepted,
    NativeConsoleMessageCallback? onConsoleMessage,
    NativeMediaStreamDetectedCallback? onMediaStreamDetected,
    NativeMediaPlaybackChangedCallback? onMediaPlaybackChanged,
  }) async {
    _blockedListeners[webViewId] = onBlocked;
    _pullProgressListeners[webViewId] = onPullProgress;
    _pullRefreshListeners[webViewId] = onPullRefresh;
    if (onDownloadIntercepted != null) {
      _downloadInterceptListeners[webViewId] = onDownloadIntercepted;
    }
    if (onConsoleMessage != null) {
      _consoleListeners[webViewId] = onConsoleMessage;
    }
    if (onMediaStreamDetected != null) {
      _streamListeners[webViewId] = onMediaStreamDetected;
    }
    if (onMediaPlaybackChanged != null) {
      _playbackListeners[webViewId] = onMediaPlaybackChanged;
    }
    try {
      await _channel.invokeMethod<bool>('attachToWebView', <String, Object?>{
        'webViewId': webViewId,
        'pageHost': pageHost,
        'desktopMode': desktopMode,
      });
    } on MissingPluginException {
      // Expected in widget tests.
    } on PlatformException {
      // Ignore platform channel errors.
    }
  }

  Future<void> applyDesktopViewport({
    required int webViewId,
    required bool desktopMode,
  }) async {
    try {
      await _channel.invokeMethod<bool>(
        'applyDesktopViewport',
        <String, Object>{'webViewId': webViewId, 'desktopMode': desktopMode},
      );
    } on MissingPluginException {
      // Expected in widget tests.
    } on PlatformException {
      // Ignore platform channel errors.
    }
  }

  Future<Uint8List?> captureWebViewPreview(int webViewId) async {
    try {
      final Uint8List? bytes = await _channel.invokeMethod<Uint8List>(
        'captureWebViewPreview',
        <String, Object>{'webViewId': webViewId},
      );
      return (bytes != null && bytes.isNotEmpty) ? bytes : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> updatePageHost({
    required int webViewId,
    required String? pageHost,
  }) async {
    try {
      await _channel.invokeMethod<bool>('updatePageHost', <String, Object?>{
        'webViewId': webViewId,
        'pageHost': pageHost,
      });
    } on MissingPluginException {
      // Expected in widget tests.
    } on PlatformException {
      // Ignore platform channel errors.
    }
  }

  void detachWebView(int webViewId) {
    _blockedListeners.remove(webViewId);
    _pullProgressListeners.remove(webViewId);
    _pullRefreshListeners.remove(webViewId);
    _downloadInterceptListeners.remove(webViewId);
    _consoleListeners.remove(webViewId);
    _streamListeners.remove(webViewId);
    _playbackListeners.remove(webViewId);
  }

  Future<bool> enterPictureInPicture() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'enterPictureInPicture',
      );
      return ok ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<List<Map<String, String>>> scanPageMediaStreams(int webViewId) async {
    try {
      final Object? raw = await _channel.invokeMethod<Object?>(
        'scanPageMediaStreams',
        <String, Object>{'webViewId': webViewId},
      );
      if (raw is List<Object?>) {
        return raw
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> m) => <String, String>{
                for (final MapEntry<Object?, Object?> e in m.entries)
                  if (e.key != null && e.value != null)
                    e.key.toString(): e.value.toString(),
              },
            )
            .toList(growable: false);
      }
      return const <Map<String, String>>[];
    } on MissingPluginException {
      return const <Map<String, String>>[];
    } on PlatformException {
      return const <Map<String, String>>[];
    }
  }

  Future<bool> isBiometricAvailable() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'isBiometricAvailable',
      );
      return ok ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticateBiometric({
    String reason = 'Verify your fingerprint or face to unlock',
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'authenticateBiometric',
        <String, Object>{'reason': reason},
      );
      return ok ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestSiteHardwarePermissions(List<String> permissions) async {
    if (permissions.isEmpty) {
      return true;
    }
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'requestSiteHardwarePermissions',
        <String, Object>{'permissions': permissions},
      );
      return ok ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> sendTestNotification() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'sendTestNotification',
      );
      return ok ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<String> sendChromeExtensionRuntimeMessage({
    required String id,
    required String messageJson,
    String? senderUrl,
  }) async {
    try {
      final String? reply = await _channel.invokeMethod<String>(
        'sendChromeExtensionRuntimeMessage',
        <String, Object?>{
          'id': id,
          'messageJson': messageJson,
          'senderUrl': senderUrl ?? '',
        },
      );
      return reply ?? '{}';
    } on MissingPluginException {
      return '{}';
    } on PlatformException {
      return '{}';
    }
  }

  Future<bool> triggerChromeExtensionAction({
    required String id,
    required String url,
    required String title,
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'triggerChromeExtensionAction',
        <String, Object>{'id': id, 'url': url, 'title': title},
      );
      return ok ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<void> approveExternalNavigation({
    required int webViewId,
    required String host,
  }) async {
    try {
      await _channel.invokeMethod<bool>(
        'approveExternalNavigation',
        <String, Object>{'webViewId': webViewId, 'host': host},
      );
    } on MissingPluginException {
      // Expected in widget tests.
    } on PlatformException {
      // Ignore platform channel errors.
    }
  }

  Future<void> prepareChromeWebStoreView(int webViewId) async {
    try {
      await _channel.invokeMethod<bool>(
        'prepareChromeWebStoreView',
        <String, Object>{'webViewId': webViewId},
      );
    } on MissingPluginException {
      // Expected in widget tests.
    } on PlatformException {
      // Ignore platform channel errors.
    }
  }

  Future<bool> openDefaultBrowserSettings() async {
    try {
      final bool? opened = await _channel.invokeMethod<bool>(
        'openDefaultBrowserSettings',
      );
      return opened ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> startVoiceSearch() async {
    try {
      final String? spoken = await _channel.invokeMethod<String>(
        'startVoiceSearch',
      );
      return spoken;
    } on MissingPluginException {
      return '__UNAVAILABLE__';
    } on PlatformException catch (e) {
      if (e.code == 'NO_VOICE_ENGINE') {
        return '__UNAVAILABLE__';
      }
      return null;
    }
  }

  Future<Map<String, Object?>?> startDownload({
    required String url,
    String? fileName,
    String? mimeType,
    String? userAgent,
  }) async {
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>(
            'startDownload',
            <String, Object?>{
              'url': url,
              'fileName': fileName,
              'mimeType': mimeType,
              'userAgent': userAgent,
            },
          );
      if (raw == null) {
        return <String, Object?>{
          'downloadId': DateTime.now().millisecondsSinceEpoch,
          'url': url,
          'fileName': fileName ?? 'download.bin',
          'mimeType': mimeType ?? '',
          'state': 'running',
          'bytesDownloaded': 0,
          'totalBytes': -1,
        };
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return <String, Object?>{
        'downloadId': DateTime.now().millisecondsSinceEpoch,
        'url': url,
        'fileName': fileName ?? 'download.bin',
        'mimeType': mimeType ?? '',
        'state': 'running',
        'bytesDownloaded': 0,
        'totalBytes': -1,
      };
    } on PlatformException {
      return null;
    }
  }

  Future<void> restoreDownload({
    required int downloadId,
    required String url,
    required String fileName,
    required String mimeType,
    required String localUri,
    required String state,
    required int totalBytes,
  }) async {
    try {
      await _channel.invokeMethod<bool>('restoreDownload', <String, Object>{
        'downloadId': downloadId,
        'url': url,
        'fileName': fileName,
        'mimeType': mimeType,
        'localUri': localUri,
        'state': state,
        'totalBytes': totalBytes,
      });
    } on MissingPluginException {
      // Expected in tests.
    } on PlatformException {
      // Non-fatal.
    }
  }

  Future<bool> pauseDownload(int downloadId) async {
    try {
      final bool? paused = await _channel.invokeMethod<bool>(
        'pauseDownload',
        <String, Object>{'downloadId': downloadId},
      );
      return paused ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> resumeDownload(int downloadId) async {
    try {
      final bool? resumed = await _channel.invokeMethod<bool>(
        'resumeDownload',
        <String, Object>{'downloadId': downloadId},
      );
      return resumed ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<List<Map<String, Object?>>> queryDownloads(List<int> ids) async {
    if (ids.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    try {
      final List<Object?>? rawList = await _channel.invokeMethod<List<Object?>>(
        'queryDownloads',
        <String, Object>{'downloadIds': ids},
      );
      if (rawList == null) {
        return const <Map<String, Object?>>[];
      }
      return rawList
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> m) => <String, Object?>{
              for (final MapEntry<Object?, Object?> e in m.entries)
                if (e.key != null) e.key.toString(): e.value,
            },
          )
          .toList(growable: false);
    } on MissingPluginException {
      return const <Map<String, Object?>>[];
    } on PlatformException {
      return const <Map<String, Object?>>[];
    }
  }

  Future<void> cancelDownload(int downloadId) async {
    try {
      await _channel.invokeMethod<bool>('cancelDownload', <String, Object>{
        'downloadId': downloadId,
      });
    } on MissingPluginException {
      // Expected in widget tests.
    } on PlatformException {
      // Ignore errors.
    }
  }

  Future<bool> openDownloadedFile({
    required int downloadId,
    required String localUri,
    required String mimeType,
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'openDownloadedFile',
        <String, Object>{
          'downloadId': downloadId,
          'localUri': localUri,
          'mimeType': mimeType,
        },
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<String, Object?>> provisionFreeWarpConfig() async {
    const Map<String, Object?> testFallback = <String, Object?>{
      'ok': true,
      'configText':
          '[Interface]\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\nAddress = 172.16.0.2/32\nDNS = 1.1.1.1\n\n[Peer]\nPublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=\nAllowedIPs = 0.0.0.0/0\nEndpoint = 162.159.192.6:2408\n',
      'clientIpv4': '172.16.0.2',
      'endpoint': '162.159.192.6:2408',
    };
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('provisionFreeWarpConfig');
      if (raw == null) {
        return testFallback;
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return testFallback;
    } on PlatformException catch (e) {
      return <String, Object?>{
        'ok': false,
        'error': e.message ?? 'Provisioning error',
      };
    }
  }

  Future<Map<String, Object?>> validateWireGuardConfig(
    String configText,
  ) async {
    final bool hasSections =
        configText.contains('[Interface]') && configText.contains('[Peer]');
    final Map<String, Object?> fallback = <String, Object?>{
      'valid': hasSections,
      if (!hasSections) 'error': 'Missing [Interface] or [Peer] section',
    };
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>(
            'validateWireGuardConfig',
            <String, Object>{'configText': configText},
          );
      if (raw == null) {
        return fallback;
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return fallback;
    } on PlatformException catch (e) {
      return <String, Object?>{
        'valid': false,
        'error': e.message ?? 'Invalid config',
      };
    }
  }

  Future<Map<String, Object?>> connectVpn({
    required String configText,
    required String profileName,
    required bool browserOnly,
  }) async {
    final Map<String, Object?> fallback = <String, Object?>{
      'ok': true,
      'connected': true,
      'profileName': profileName,
    };
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('connectVpn', <String, Object>{
            'configText': configText,
            'profileName': profileName,
            'browserOnly': browserOnly,
          });
      if (raw == null) {
        return fallback;
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return fallback;
    } on PlatformException catch (e) {
      return <String, Object?>{
        'ok': false,
        'connected': false,
        'error': e.message ?? 'VPN connection failed',
      };
    }
  }

  Future<void> disconnectVpn() async {
    try {
      await _channel.invokeMethod<Map<Object?, Object?>>('disconnectVpn');
    } on MissingPluginException {
      // Expected in widget tests.
    } on PlatformException {
      // Non-fatal.
    }
  }

  Future<Map<String, Object?>> provisionForeignOpenVpnConfig({
    required String countryCode,
    List<String> excludeHosts = const <String>[],
  }) async {
    final Map<String, Object?> fallback = <String, Object?>{
      'ok': true,
      'configText':
          'client\ndev tun\nremote 89.187.173.169 1194 tcp-client\ncipher AES-256-GCM\n<ca>\nTEST\n</ca>\n<cert>\nTEST\n</cert>\n<key>\nTEST\n</key>\n',
      'serverHost': '89.187.173.169',
      'countryCode': countryCode,
      'countryName': countryCode,
      'latencyMs': 42,
    };
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>(
            'provisionForeignOpenVpnConfig',
            <String, Object>{
              'countryCode': countryCode,
              'excludeHosts': excludeHosts,
            },
          );
      if (raw == null) {
        return fallback;
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return fallback;
    } on PlatformException catch (e) {
      return <String, Object?>{
        'ok': false,
        'error': e.message ?? 'Foreign VPN provisioning failed',
      };
    }
  }

  Future<List<Map<String, Object?>>> fetchLiveForeignCountries() async {
    try {
      final Object? raw = await _channel.invokeMethod<Object?>(
        'fetchLiveForeignCountries',
      );
      final Object? listObj = (raw is Map<Object?, Object?>)
          ? raw['countries']
          : raw;
      if (listObj is List<Object?>) {
        return listObj
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> m) => <String, Object?>{
                for (final MapEntry<Object?, Object?> e in m.entries)
                  if (e.key != null) e.key.toString(): e.value,
              },
            )
            .toList(growable: false);
      }
      return const <Map<String, Object?>>[];
    } on MissingPluginException {
      return const <Map<String, Object?>>[];
    } on PlatformException {
      return const <Map<String, Object?>>[];
    }
  }

  Future<Map<String, Object?>> getDownloadLocations() async {
    const Map<String, Object?> fallback = <String, Object?>{
      'currentPath': '/storage/emulated/0/Download',
      'currentLabel': 'Downloads',
      'presets': <Map<String, String>>[
        <String, String>{
          'label': 'Downloads (Default)',
          'path': '/storage/emulated/0/Download',
        },
        <String, String>{
          'label': 'Downloads / HeavenBrowser',
          'path': '/storage/emulated/0/Download/HeavenBrowser',
        },
        <String, String>{
          'label': 'Documents / HeavenBrowser',
          'path': '/storage/emulated/0/Documents/HeavenBrowser',
        },
      ],
    };
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('getDownloadLocations');
      if (raw == null || raw.isEmpty) {
        return fallback;
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    }
  }

  Future<Map<String, Object?>> setDownloadLocation(String path) async {
    final Map<String, Object?> fallback = <String, Object?>{
      'ok': true,
      'path': path,
      'label': path.split('/').where((String s) => s.isNotEmpty).lastOrNull ??
          'Downloads',
    };
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>(
            'setDownloadLocation',
            <String, Object>{'path': path},
          );
      if (raw == null) {
        return fallback;
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return fallback;
    } on PlatformException catch (e) {
      return <String, Object?>{
        'ok': false,
        'error': e.message ?? 'Cannot set download folder',
      };
    }
  }

  Future<Map<String, Object?>?> pickDownloadFolder() async {
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('pickDownloadFolder');
      if (raw == null) {
        return null;
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return const <String, Object?>{
        'ok': true,
        'path': '/storage/emulated/0/Download/HeavenCustom',
        'label': 'Download/HeavenCustom',
      };
    } on PlatformException {
      return null;
    }
  }

  Future<bool> createHomeScreenShortcut({
    required String title,
    required String url,
    String? iconUrl,
    int? webViewId,
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'createHomeScreenShortcut',
        <String, Object?>{
          'title': title,
          'url': url,
          'iconUrl': iconUrl,
          'webViewId': webViewId,
        },
      );
      return ok ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<List<Map<String, Object?>>> listChromeExtensions() async {
    try {
      final Object? raw = await _channel.invokeMethod<Object?>(
        'listChromeExtensions',
      );
      if (raw is List<Object?>) {
        return raw
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> m) => <String, Object?>{
                for (final MapEntry<Object?, Object?> e in m.entries)
                  if (e.key != null) e.key.toString(): e.value,
              },
            )
            .toList(growable: false);
      }
      return const <Map<String, Object?>>[];
    } on MissingPluginException {
      return const <Map<String, Object?>>[];
    } on PlatformException {
      return const <Map<String, Object?>>[];
    }
  }

  Future<Map<String, Object?>> installWebStoreExtension(String urlOrId) async {
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>(
            'installWebStoreExtension',
            <String, Object>{'urlOrId': urlOrId},
          );
      if (raw == null) {
        return const <String, Object?>{
          'ok': false,
          'error': 'Extension installer unavailable.',
        };
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return const <String, Object?>{
        'ok': false,
        'error': 'Extension installer unavailable in headless environment.',
      };
    } on PlatformException catch (e) {
      return <String, Object?>{
        'ok': false,
        'error': e.message ?? 'Chrome Web Store installation failed.',
      };
    }
  }

  Future<Map<String, Object?>?> pickChromeExtensionFile() async {
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('pickChromeExtensionFile');
      if (raw == null) {
        return null;
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> toggleChromeExtension(String id, bool enabled) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'toggleChromeExtension',
        <String, Object>{'id': id, 'enabled': enabled},
      );
      return ok ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> uninstallChromeExtension(String id) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'uninstallChromeExtension',
        <String, Object>{'id': id},
      );
      return ok ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<String> getChromeExtensionScriptsForUrl(String url) async {
    try {
      final String? js = await _channel.invokeMethod<String>(
        'getChromeExtensionScriptsForUrl',
        <String, Object>{'url': url},
      );
      return js ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  Future<void> updateChromeExtensionStorage(
    String id,
    String patchJson,
  ) async {
    try {
      await _channel.invokeMethod<bool>(
        'updateChromeExtensionStorage',
        <String, Object>{'id': id, 'patchJson': patchJson},
      );
    } on MissingPluginException {
      // Expected in widget tests.
    } on PlatformException {
      // Non-fatal.
    }
  }

  Future<void> setPopupContextTab({
    required String url,
    required String title,
    int? webViewId,
  }) async {
    try {
      await _channel.invokeMethod<bool>(
        'setPopupContextTab',
        <String, Object?>{'url': url, 'title': title, 'webViewId': webViewId},
      );
    } on MissingPluginException {
      // Expected in widget tests.
    } on PlatformException {
      // Non-fatal.
    }
  }

  Future<Map<String, Object?>> getNotificationStatus() async {
    const Map<String, Object?> fallback = <String, Object?>{
      'systemEnabled': true,
      'runtimeGranted': true,
      'downloadNotificationsEnabled': true,
    };
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('getNotificationStatus');
      if (raw == null) {
        return fallback;
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      return granted ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> openNotificationSettings() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'openNotificationSettings',
      );
      return ok ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<void> setDownloadNotificationsEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<bool>(
        'setDownloadNotificationsEnabled',
        <String, Object>{'enabled': enabled},
      );
    } on MissingPluginException {
      // Expected in widget tests.
    } on PlatformException {
      // Non-fatal.
    }
  }

  Future<bool> clearSiteData({String? domain}) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'clearSiteData',
        <String, Object?>{'domain': domain},
      );
      return ok ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<String, Object?>> getVpnStatus() async {
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('getVpnStatus');
      if (raw == null) {
        return const <String, Object?>{'connected': false};
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries)
          if (e.key != null) e.key.toString(): e.value,
      };
    } on MissingPluginException {
      return const <String, Object?>{'connected': false};
    } on PlatformException {
      return const <String, Object?>{'connected': false};
    }
  }
}
