import 'package:flutter/services.dart';

import 'heaven_shield.dart';

typedef NativeBlockedCallback = void Function(int webViewId, String domain);

class NativeShieldBridge {
  NativeShieldBridge._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final NativeShieldBridge instance = NativeShieldBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.hypertechlabs.heavenbrowser/native_shield',
  );

  final Map<int, NativeBlockedCallback> _listeners =
      <int, NativeBlockedCallback>{};
  NativeBlockedCallback? fallbackListener;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onResourceBlocked') {
      final Object? rawArgs = call.arguments;
      if (rawArgs is Map<Object?, Object?>) {
        final Object? idVal = rawArgs['webViewId'];
        final int webViewId = idVal is num ? idVal.toInt() : -1;
        final String domain = (rawArgs['domain']?.toString() ?? 'tracker')
            .trim();
        final NativeBlockedCallback? cb = _listeners[webViewId];
        if (cb != null) {
          cb(webViewId, domain);
        } else {
          fallbackListener?.call(webViewId, domain);
        }
      }
    }
    return null;
  }

  Future<void> syncShieldConfig({
    required bool shieldEnabled,
    required Set<String> trustedHosts,
    required bool sendDntAndGpc,
  }) async {
    try {
      await _channel.invokeMethod<bool>('updateConfig', <String, Object>{
        'shieldEnabled': shieldEnabled,
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
      // Expected in unit/widget tests where Android Activity is not running.
    } on PlatformException {
      // Ignore transient platform channel errors.
    }
  }

  Future<void> attachWebView({
    required int webViewId,
    String? pageHost,
    required NativeBlockedCallback onBlocked,
  }) async {
    _listeners[webViewId] = onBlocked;
    try {
      await _channel.invokeMethod<bool>('attachToWebView', <String, Object?>{
        'webViewId': webViewId,
        'pageHost': pageHost,
      });
    } on MissingPluginException {
      // Expected in widget tests.
    } on PlatformException {
      // Ignore platform channel errors.
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
    _listeners.remove(webViewId);
  }

  Future<bool> openDefaultBrowserSettings() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'openDefaultBrowserSettings',
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
