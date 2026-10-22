import 'package:flutter/services.dart';

import 'heaven_shield.dart';

typedef NativeBlockedCallback = void Function(int webViewId, String domain);
typedef NativePullProgressCallback = void Function(double progress);
typedef NativePullRefreshCallback = void Function();
typedef NativeDownloadStartedCallback =
    void Function(Map<String, Object?> downloadInfo);
typedef NativeWebViewDownloadInterceptedCallback =
    void Function(bool wasEmptyPage);

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

  NativeDownloadStartedCallback? onDownloadStarted;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final Object? rawArgs = call.arguments;
    if (call.method == 'onResourceBlocked' &&
        rawArgs is Map<Object?, Object?>) {
      final Object? idVal = rawArgs['webViewId'];
      final int webViewId = idVal is num ? idVal.toInt() : -1;
      final String domain = (rawArgs['domain']?.toString() ?? 'tracker').trim();
      _blockedListeners[webViewId]?.call(webViewId, domain);
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
  }) async {
    try {
      await _channel.invokeMethod<bool>('updateConfig', <String, Object>{
        'shieldEnabled': shieldEnabled,
        'desktopMode': desktopMode,
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
  }) async {
    _blockedListeners[webViewId] = onBlocked;
    _pullProgressListeners[webViewId] = onPullProgress;
    _pullRefreshListeners[webViewId] = onPullRefresh;
    if (onDownloadIntercepted != null) {
      _downloadInterceptListeners[webViewId] = onDownloadIntercepted;
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
}
