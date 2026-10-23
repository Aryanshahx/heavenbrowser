import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/theme/app_theme.dart';
import '../browser/engine/browser_engine.dart';
import '../shield/native_shield_bridge.dart';
import 'extensions_controller.dart';

/// Renders a real Desktop Chrome Extension's `action.default_popup` (`popup.html`)
/// over `https://chrome-ext.heaven.local/<extId>/...` with live `chrome.storage`,
/// `chrome.tabs`, and `chrome.scripting` bridged to the active browser tab.
class ExtensionPopupSheet extends StatefulWidget {
  const ExtensionPopupSheet({
    super.key,
    required this.extension,
    this.activeEngine,
    this.onOpenNewTab,
  });

  final InstalledChromeExtension extension;
  final BrowserEngine? activeEngine;
  final ValueChanged<String>? onOpenNewTab;

  static Future<void> show(
    BuildContext context, {
    required InstalledChromeExtension extension,
    BrowserEngine? activeEngine,
    ValueChanged<String>? onOpenNewTab,
  }) async {
    await NativeShieldBridge.instance.setPopupContextTab(
      url: activeEngine?.currentUrl ?? 'https://www.google.com',
      title: activeEngine?.pageTitle ?? 'Heaven Tab',
    );
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExtensionPopupSheet(
        extension: extension,
        activeEngine: activeEngine,
        onOpenNewTab: onOpenNewTab,
      ),
    );
  }

  @override
  State<ExtensionPopupSheet> createState() => _ExtensionPopupSheetState();
}

class _ExtensionPopupSheetState extends State<ExtensionPopupSheet> {
  WebViewController? _popupController;
  int? _androidWebViewId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initPopupWebView();
  }

  void _initPopupWebView() {
    final WebViewController ctrl = WebViewController();
    _popupController = ctrl;
    unawaited(ctrl.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(
      ctrl.addJavaScriptChannel(
        'HeavenChromeExtChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          _handleChromeExtBridgeMessage(msg.message);
        },
      ),
    );
    unawaited(
      ctrl.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _loading = false);
            }
          },
        ),
      ),
    );

    if (ctrl.platform case final AndroidWebViewController androidCtrl) {
      _androidWebViewId = androidCtrl.webViewIdentifier;
      unawaited(
        NativeShieldBridge.instance.attachWebView(
          webViewId: androidCtrl.webViewIdentifier,
          desktopMode: false,
          pageHost: 'chrome-ext.heaven.local',
          onBlocked: (_, _) {},
          onPullProgress: (_) {},
          onPullRefresh: () {},
          onDownloadIntercepted: (_) {},
        ),
      );
    }

    unawaited(ctrl.loadRequest(Uri.parse(widget.extension.popupUrl)));
  }

  void _handleChromeExtBridgeMessage(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<Object?, Object?>) return;
      final String extId = decoded['extId']?.toString() ?? widget.extension.id;
      final String op = decoded['op']?.toString() ?? '';
      final Object? data = decoded['data'];

      if (op == 'storage_set' && data != null) {
        unawaited(
          NativeShieldBridge.instance.updateChromeExtensionStorage(
            extId,
            jsonEncode(data),
          ),
        );
      } else if (op == 'open_tab' && data is Map<Object?, Object?>) {
        final String url = data['url']?.toString() ?? '';
        if (url.isNotEmpty) {
          if (mounted) Navigator.pop(context);
          widget.onOpenNewTab?.call(url);
        }
      } else if (op == 'exec_js' && data is Map<Object?, Object?>) {
        final String code = data['code']?.toString() ?? '';
        if (code.isNotEmpty) {
          unawaited(widget.activeEngine?.controller?.runJavaScript(code));
        }
      } else if (op == 'insert_css' && data is Map<Object?, Object?>) {
        final String css = data['css']?.toString() ?? '';
        if (css.isNotEmpty) {
          final String encoded = jsonEncode(css);
          unawaited(
            widget.activeEngine?.controller?.runJavaScript(
              '(function(){var s=document.createElement("style");s.textContent=$encoded;(document.head||document.documentElement).appendChild(s);})();',
            ),
          );
        }
      }
    } catch (_) {
      // Ignore malformed bridge payloads.
    }
  }

  @override
  void dispose() {
    if (_androidWebViewId != null) {
      NativeShieldBridge.instance.detachWebView(_androidWebViewId!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
              child: Row(
                children: <Widget>[
                  if (widget.extension.iconBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        widget.extension.iconBytes!,
                        width: 28,
                        height: 28,
                      ),
                    )
                  else
                    Icon(Icons.extension_rounded, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.extension.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Chrome Extension Popup • v${widget.extension.version}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            const Divider(height: 1),
            Expanded(
              child: Container(
                color: isDark ? AppTheme.deepNavyBg : Colors.white,
                child: _popupController != null
                    ? WebViewWidget(controller: _popupController!)
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
