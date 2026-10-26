import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/omnibox_parser.dart';
import '../settings/browser_settings.dart';
import '../tabs/tab_manager.dart';
import 'native_shield_bridge.dart';

class HeavenShieldScreen extends StatefulWidget {
  const HeavenShieldScreen({
    super.key,
    required this.settings,
    this.tabManager,
    this.currentHost,
    this.activeWebViewId,
    this.onShieldChangedForActivePage,
  });

  final BrowserSettingsController settings;
  final TabManagerController? tabManager;
  final String? currentHost;
  final int? activeWebViewId;
  final VoidCallback? onShieldChangedForActivePage;

  @override
  State<HeavenShieldScreen> createState() => _HeavenShieldScreenState();
}

class _HeavenShieldScreenState extends State<HeavenShieldScreen> {
  HeavenShieldStats _stats = const HeavenShieldStats(
    pageBlocked: 0,
    totalBlocked: 0,
    shieldEnabled: true,
  );
  bool _activePageNeedsReload = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshStats());
  }

  @override
  void dispose() {
    if (_activePageNeedsReload && widget.onShieldChangedForActivePage != null) {
      final VoidCallback reloadCb = widget.onShieldChangedForActivePage!;
      WidgetsBinding.instance.addPostFrameCallback((_) => reloadCb());
    }
    super.dispose();
  }

  Future<void> _refreshStats() async {
    final HeavenShieldStats fetched = await NativeShieldBridge.instance
        .getHeavenShieldStats(webViewId: widget.activeWebViewId);
    if (mounted) {
      setState(() => _stats = fetched);
    }
  }

  void _notifyActivePage() {
    // Defer reloading the background WebView until leaving HeavenShieldScreen
    // so toggling settings never causes Hybrid Composition jank/jitter!
    _activePageNeedsReload = true;
  }

  Future<void> _toggleBiometricGuard(
    BuildContext messengerContext, {
    required bool nextValue,
    required Future<void> Function(bool) onApply,
    required String reason,
  }) async {
    final bool ok = await NativeShieldBridge.instance.authenticateBiometric(
      reason: reason,
    );
    if (!ok) {
      if (messengerContext.mounted) {
        ScaffoldMessenger.of(messengerContext)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Set up Fingerprint, Face Unlock, or Screen Lock in Android Settings first.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: Duration(milliseconds: 2200),
            ),
          );
      }
      return;
    }
    await onApply(nextValue);
  }

  Future<void> _showHelpDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Heaven Shield & privacy'),
          content: const Text(
            'Heaven Shield runs 100% locally on your device with zero cloud telemetry. '
            'Customize global defaults for ad & tracker blocking (including YouTube ads), '
            'AMP & bounce-URL unwrapping, cookie & script rules, WebRTC IP leak protection, '
            'social-media embeds, and biometric locks.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showModalSelector(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetCtx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ...children,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTrackersAdsSheet(BuildContext context) async {
    final HeavenTrackersAdsLevel current = widget.settings.trackersAdsLevel;
    await _showModalSelector(
      context,
      title: 'Block trackers & ads',
      children: <Widget>[
        Builder(
          builder: (BuildContext sheetCtx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _RadioSheetOption<HeavenTrackersAdsLevel>(
                optionKey: const Key('heaven_shield_mode_strict'),
                title: 'Aggressive',
                subtitle: 'Blocks trackers, ads, CNAME cloaking & analytics',
                value: HeavenTrackersAdsLevel.aggressive,
                groupValue: current,
                onSelect: (HeavenTrackersAdsLevel v) async {
                  Navigator.pop(sheetCtx);
                  await widget.settings.setTrackersAdsLevel(v);
                  _notifyActivePage();
                },
              ),
              _RadioSheetOption<HeavenTrackersAdsLevel>(
                optionKey: const Key('heaven_shield_mode_standard'),
                title: 'Standard',
                subtitle: 'Blocks ad networks & cross-site trackers (default)',
                value: HeavenTrackersAdsLevel.standard,
                groupValue: current,
                onSelect: (HeavenTrackersAdsLevel v) async {
                  Navigator.pop(sheetCtx);
                  await widget.settings.setTrackersAdsLevel(v);
                  _notifyActivePage();
                },
              ),
              _RadioSheetOption<HeavenTrackersAdsLevel>(
                optionKey: const Key('heaven_shield_mode_disabled'),
                title: 'Allow all trackers & ads',
                subtitle: 'Do not block ad networks or third-party trackers',
                value: HeavenTrackersAdsLevel.disabled,
                groupValue: current,
                onSelect: (HeavenTrackersAdsLevel v) async {
                  Navigator.pop(sheetCtx);
                  await widget.settings.setTrackersAdsLevel(v);
                  _notifyActivePage();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showHttpsUpgradeSheet(BuildContext context) async {
    final HeavenHttpsUpgradeMode current = widget.settings.httpsUpgradeMode;
    await _showModalSelector(
      context,
      title: 'Upgrade connections to HTTPS',
      children: <Widget>[
        Builder(
          builder: (BuildContext sheetCtx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final HeavenHttpsUpgradeMode m
                  in HeavenHttpsUpgradeMode.values)
                _RadioSheetOption<HeavenHttpsUpgradeMode>(
                  title: m.label,
                  subtitle: m.subtitle,
                  value: m,
                  groupValue: current,
                  onSelect: (HeavenHttpsUpgradeMode v) async {
                    Navigator.pop(sheetCtx);
                    await widget.settings.setHttpsUpgradeMode(v);
                    _notifyActivePage();
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showCookiePolicySheet(BuildContext context) async {
    final HeavenCookiePolicy current = widget.settings.cookiePolicy;
    await _showModalSelector(
      context,
      title: 'Block cookies',
      children: <Widget>[
        Builder(
          builder: (BuildContext sheetCtx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final HeavenCookiePolicy p in HeavenCookiePolicy.values)
                _RadioSheetOption<HeavenCookiePolicy>(
                  title: p.label,
                  value: p,
                  groupValue: current,
                  onSelect: (HeavenCookiePolicy v) async {
                    Navigator.pop(sheetCtx);
                    await widget.settings.setCookiePolicy(v);
                    _notifyActivePage();
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showDeleteBrowsingDataDialog(
    BuildContext context,
    BuildContext messengerContext,
  ) async {
    bool delHistory = true;
    bool delCookiesAndSiteData = true;
    bool delSearches = true;
    bool delOpenTabs = false;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext _, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Delete browsing data'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Browsing history'),
                      value: delHistory,
                      onChanged: (bool? v) =>
                          setDialogState(() => delHistory = v ?? false),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cookies, site data & cache'),
                      value: delCookiesAndSiteData,
                      onChanged: (bool? v) => setDialogState(
                        () => delCookiesAndSiteData = v ?? false,
                      ),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Recent search queries'),
                      value: delSearches,
                      onChanged: (bool? v) =>
                          setDialogState(() => delSearches = v ?? false),
                    ),
                    if (widget.tabManager != null)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('All open tabs'),
                        value: delOpenTabs,
                        onChanged: (bool? v) =>
                            setDialogState(() => delOpenTabs = v ?? false),
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const Key('confirm_delete_browsing_data_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.fireCrimson,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    if (delOpenTabs && widget.tabManager != null) {
                      await widget.tabManager!.burnAllSessionsAndData();
                    } else {
                      if (delHistory) {
                        await widget.settings.clearHistoryOnly();
                      }
                      if (delSearches) {
                        await widget.settings.clearRecentSearches();
                      }
                      if (delCookiesAndSiteData) {
                        await NativeShieldBridge.instance.clearSiteData(
                          domain: '',
                        );
                      }
                    }
                    if (messengerContext.mounted) {
                      ScaffoldMessenger.of(messengerContext)
                        ..clearSnackBars()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('Selected browsing data deleted'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(milliseconds: 1600),
                          ),
                        );
                    }
                  },
                  child: const Text('Delete data'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showSafeBrowsingSheet(BuildContext context) async {
    final HeavenSafeBrowsingMode current = widget.settings.safeBrowsingMode;
    await _showModalSelector(
      context,
      title: 'Safe Browsing',
      children: <Widget>[
        Builder(
          builder: (BuildContext sheetCtx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final HeavenSafeBrowsingMode m
                  in HeavenSafeBrowsingMode.values)
                _RadioSheetOption<HeavenSafeBrowsingMode>(
                  title: m.label,
                  subtitle: m.subtitle,
                  value: m,
                  groupValue: current,
                  onSelect: (HeavenSafeBrowsingMode v) async {
                    Navigator.pop(sheetCtx);
                    await widget.settings.setSafeBrowsingMode(v);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showWebrtcSheet(BuildContext context) async {
    final HeavenWebrtcPolicy current = widget.settings.webrtcPolicy;
    await _showModalSelector(
      context,
      title: 'WebRTC IP handling policy',
      children: <Widget>[
        Builder(
          builder: (BuildContext sheetCtx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final HeavenWebrtcPolicy p in HeavenWebrtcPolicy.values)
                _RadioSheetOption<HeavenWebrtcPolicy>(
                  title: p.label,
                  value: p,
                  groupValue: current,
                  onSelect: (HeavenWebrtcPolicy v) async {
                    Navigator.pop(sheetCtx);
                    await widget.settings.setWebrtcPolicy(v);
                    _notifyActivePage();
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showSecureDnsSheet(BuildContext context) async {
    final HeavenSecureDnsMode current = widget.settings.secureDnsMode;
    await _showModalSelector(
      context,
      title: 'Use secure DNS',
      children: <Widget>[
        Builder(
          builder: (BuildContext sheetCtx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final HeavenSecureDnsMode m in HeavenSecureDnsMode.values)
                _RadioSheetOption<HeavenSecureDnsMode>(
                  title: m.label,
                  subtitle: m.dohEndpoint.isEmpty ? null : m.dohEndpoint,
                  value: m,
                  groupValue: current,
                  onSelect: (HeavenSecureDnsMode v) async {
                    Navigator.pop(sheetCtx);
                    await widget.settings.setSecureDnsMode(v);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showJsOptimisationSheet(BuildContext context) async {
    final HeavenJsOptimisationMode current = widget.settings.jsOptimisationMode;
    await _showModalSelector(
      context,
      title: 'JavaScript optimisation and security',
      children: <Widget>[
        Builder(
          builder: (BuildContext sheetCtx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final HeavenJsOptimisationMode m
                  in HeavenJsOptimisationMode.values)
                _RadioSheetOption<HeavenJsOptimisationMode>(
                  title: m.label,
                  subtitle: m.subtitle,
                  value: m,
                  groupValue: current,
                  onSelect: (HeavenJsOptimisationMode v) async {
                    Navigator.pop(sheetCtx);
                    await widget.settings.setJsOptimisationMode(v);
                    _notifyActivePage();
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showWeb3DomainSheet(
    BuildContext context, {
    required String title,
    required String tldExample,
    required bool currentValue,
    required Future<void> Function(bool) onChanged,
  }) async {
    await _showModalSelector(
      context,
      title: title,
      children: <Widget>[
        Builder(
          builder: (BuildContext sheetCtx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _RadioSheetOption<bool>(
                title: 'Enabled',
                subtitle: 'Resolve $tldExample domains via HTTPS gateway',
                value: true,
                groupValue: currentValue,
                onSelect: (bool v) async {
                  Navigator.pop(sheetCtx);
                  await onChanged(v);
                },
              ),
              _RadioSheetOption<bool>(
                title: 'Disabled',
                subtitle: 'Treat $tldExample inputs as normal search queries',
                value: false,
                groupValue: currentValue,
                onSelect: (bool v) async {
                  Navigator.pop(sheetCtx);
                  await onChanged(v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showDoNotTrackSheet(BuildContext context) async {
    final bool current = widget.settings.sendDntAndGpc;
    await _showModalSelector(
      context,
      title: "Send a 'Do Not Track' request",
      children: <Widget>[
        Builder(
          builder: (BuildContext sheetCtx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _RadioSheetOption<bool>(
                title: 'On',
                subtitle: 'Send DNT: 1 and Global Privacy Control headers',
                value: true,
                groupValue: current,
                onSelect: (bool v) async {
                  Navigator.pop(sheetCtx);
                  await widget.settings.setSendDntAndGpc(v);
                  _notifyActivePage();
                },
              ),
              _RadioSheetOption<bool>(
                title: 'Off',
                subtitle: 'Do not send extra DNT request headers (default)',
                value: false,
                groupValue: current,
                onSelect: (bool v) async {
                  Navigator.pop(sheetCtx);
                  await widget.settings.setSendDntAndGpc(v);
                  _notifyActivePage();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAddExceptionDialog(BuildContext context) async {
    final TextEditingController hostCtrl = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext _, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Add Trusted Site'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Heaven Shield will stay paused on this domain and its subdomains.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('heaven_shield_exception_input'),
                    controller: hostCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      hintText: 'example.com',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const Key('heaven_shield_exception_save_button'),
                  onPressed: () async {
                    final bool ok = await widget.settings
                        .addShieldExceptionHost(hostCtrl.text);
                    if (!ok) {
                      setDialogState(
                        () => errorText =
                            'Enter a valid domain (e.g. example.com)',
                      );
                      return;
                    }
                    _notifyActivePage();
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('Allow Site'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final String cleanHost = OmniboxParser.cleanDomain(widget.currentHost);

    return ScaffoldMessenger(
      child: Builder(
        builder: (BuildContext innerContext) {
          return Scaffold(
            backgroundColor: isDark
                ? AppTheme.deepNavyBg
                : colors.surfaceContainerLowest,
            appBar: AppBar(
              centerTitle: false,
              title: const Text(
                'Heaven Shield & privacy',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              actions: <Widget>[
                IconButton(
                  tooltip: 'About Heaven Shield',
                  onPressed: () => _showHelpDialog(innerContext),
                  icon: const Icon(Icons.help_outline_rounded, size: 21),
                ),
              ],
            ),
            body: SafeArea(
              child: ListenableBuilder(
                listenable: widget.settings,
                builder: (BuildContext context, _) {
                  final BrowserSettingsController s = widget.settings;
                  final bool enabled = s.shieldEnabled;
                  final List<String> exceptions = s.shieldDisabledHosts;

                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 780),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                        children: <Widget>[
                      _buildMasterCard(innerContext, colors, isDark, enabled),
                      if (cleanHost.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        _ShieldRowTile.toggle(
                          tileKey: const Key(
                            'heaven_shield_current_site_switch',
                          ),
                          isDark: isDark,
                          colors: colors,
                          title: 'Protect $cleanHost',
                          subtitle: s.isShieldActiveForHost(cleanHost)
                              ? 'Heaven Shield active on this website'
                              : 'Paused on this site (allowlisted)',
                          value: s.isShieldActiveForHost(cleanHost),
                          onChanged: enabled
                              ? (bool v) async {
                                  await s.setShieldProtectionForHost(
                                    cleanHost,
                                    v,
                                  );
                                  _notifyActivePage();
                                }
                              : null,
                        ),
                      ],
                      const SizedBox(height: 18),
                      _SectionTitle('Heaven Shield global defaults', colors),
                      _InfoNoticeCard(
                        isDark: isDark,
                        colors: colors,
                        text:
                            "These are the default Shield settings for new sites. Changing these won't affect your existing per-site settings.",
                      ),
                      const SizedBox(height: 6),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_trackers_ads'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Block trackers & ads',
                        subtitle: s.trackersAdsLevel.subtitle,
                        onTap: () => _showTrackersAdsSheet(innerContext),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_de_amp'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Auto-redirect AMP pages',
                        subtitle:
                            "Always visit original (non-AMP) page URLs, instead of Google's Accelerated Mobile Page versions",
                        value: s.shieldAutoRedirectAmp,
                        onChanged: (bool v) async {
                          await s.setShieldAutoRedirectAmp(v);
                          _notifyActivePage();
                        },
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_debouncer'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Auto-redirect tracking URLs',
                        subtitle:
                            'Enable support for bypassing top-level redirect tracking URLs.',
                        value: s.shieldCleanUrls,
                        onChanged: (bool v) async {
                          await s.setShieldCleanUrls(v);
                          _notifyActivePage();
                        },
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_https_upgrade'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Upgrade connections to HTTPS',
                        subtitle: s.httpsUpgradeMode.subtitle,
                        onTap: () => _showHttpsUpgradeSheet(innerContext),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_block_scripts'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Block scripts',
                        subtitle: 'Blocks JavaScript (may break sites)',
                        value: !s.javascriptEnabled,
                        onChanged: (bool blockJs) async {
                          await s.setJavascriptEnabled(!blockJs);
                          _notifyActivePage();
                        },
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_cookie_policy'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Block cookies',
                        subtitle: s.cookiePolicy.label,
                        onTap: () => _showCookiePolicySheet(innerContext),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_fingerprinting'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Block fingerprinting',
                        subtitle: 'Prevents websites from fingerprinting me',
                        value: s.shieldAntiFingerprinting,
                        onChanged: (bool v) async {
                          await s.setShieldAntiFingerprinting(v);
                          _notifyActivePage();
                        },
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_lang_fingerprint'),
                        isDark: isDark,
                        colors: colors,
                        title:
                            'Prevent fingerprinting via language settings',
                        subtitle:
                            "Reduces how much websites can learn about you based on your browser's language settings.",
                        value: s.shieldPreventLangFp,
                        onChanged: (bool v) async {
                          await s.setShieldPreventLangFp(v);
                          _notifyActivePage();
                        },
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_content_filtering'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Content filtering',
                        subtitle:
                            'Enable custom filters that block regional and language-specific trackers and Annoyances',
                        onTap: () {
                          Navigator.of(innerContext).push(
                            MaterialPageRoute<void>(
                              builder: (_) => HeavenContentFilteringScreen(
                                settings: s,
                                onFiltersChanged: _notifyActivePage,
                              ),
                            ),
                          );
                        },
                      ),

                      // Section 2: Clear browsing data
                      const SizedBox(height: 18),
                      _SectionTitle('Clear browsing data', colors),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_clear_on_exit'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Clear data on exit',
                        subtitle: 'Clears all browsing data',
                        value: s.clearOnExit,
                        onChanged: s.setClearOnExit,
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_delete_browsing_data'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Delete browsing data',
                        subtitle: 'Delete history, cookies, site data, cache...',
                        onTap: () => _showDeleteBrowsingDataDialog(
                          innerContext,
                          innerContext,
                        ),
                      ),

                      // Section 3: Social Media Blocking
                      const SizedBox(height: 18),
                      _SectionTitle('Social Media Blocking', colors),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_social_facebook'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Allow Facebook logins and embedded posts',
                        value: s.allowFacebookEmbeds,
                        onChanged: (bool v) async {
                          await s.setAllowFacebookEmbeds(v);
                          _notifyActivePage();
                        },
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_social_twitter'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Allow X (Twitter) embedded tweets',
                        value: s.allowTwitterEmbeds,
                        onChanged: (bool v) async {
                          await s.setAllowTwitterEmbeds(v);
                          _notifyActivePage();
                        },
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_social_linkedin'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Allow LinkedIn embedded posts',
                        value: s.allowLinkedinEmbeds,
                        onChanged: (bool v) async {
                          await s.setAllowLinkedinEmbeds(v);
                          _notifyActivePage();
                        },
                      ),

                      // Section 4: Other privacy settings
                      const SizedBox(height: 18),
                      _SectionTitle('Other privacy settings', colors),
                      _ShieldRowTile.toggle(
                        tileKey: const Key(
                          'shield_switch_open_external_in_heaven',
                        ),
                        isDark: isDark,
                        colors: colors,
                        title: 'Open external links in Heaven',
                        subtitle:
                            'Opens links from other apps in a Heaven webview. Note: Heaven must be set as your default browser.',
                        value: s.openExternalLinksInHeaven,
                        onChanged: s.setOpenExternalLinksInHeaven,
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_safe_browsing'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Safe Browsing',
                        subtitle: s.safeBrowsingMode.subtitle,
                        onTap: () => _showSafeBrowsingSheet(innerContext),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key(
                          'shield_switch_allow_external_app_links',
                        ),
                        isDark: isDark,
                        colors: colors,
                        title:
                            'Allow app links to open in apps outside of Heaven',
                        value: s.allowExternalAppLinks,
                        onChanged: s.setAllowExternalAppLinks,
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_webrtc_policy'),
                        isDark: isDark,
                        colors: colors,
                        title: 'WebRTC IP handling policy',
                        subtitle: s.webrtcPolicy.label,
                        onTap: () => _showWebrtcSheet(innerContext),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_private_screenshots'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Allow screenshots in private tabs',
                        subtitle:
                            'If allowed, private tabs will also be visible when multiple apps are open.',
                        value: s.allowPrivateScreenshots,
                        onChanged: (bool v) async {
                          await s.setAllowPrivateScreenshots(v);
                          final bool inPrivate =
                              widget.tabManager?.isActiveIncognito ?? false;
                          unawaited(
                            NativeShieldBridge.instance
                                .updatePrivateWindowSecurity(
                                  blockScreenshots: inPrivate && !v,
                                ),
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_lock_private_tabs'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Lock Private tabs when you leave Heaven',
                        subtitle: 'Use screen lock to see open Private tabs',
                        value: s.biometricLockIncognito,
                        onChanged: (bool v) => _toggleBiometricGuard(
                          innerContext,
                          nextValue: v,
                          onApply: s.setBiometricLockIncognito,
                          reason: 'Verify biometrics to lock Private tabs',
                        ),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_lock_app'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Lock Heaven app with biometrics',
                        subtitle:
                            'Require fingerprint, face unlock, or PIN on app launch',
                        value: s.biometricLockApp,
                        onChanged: (bool v) => _toggleBiometricGuard(
                          innerContext,
                          nextValue: v,
                          onApply: s.setBiometricLockApp,
                          reason: 'Verify biometrics to configure Heaven Lock',
                        ),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key(
                          'shield_switch_payment_methods_check',
                        ),
                        isDark: isDark,
                        colors: colors,
                        title:
                            'Allow sites to check if you have payment methods saved',
                        value: s.allowPaymentMethodQuery,
                        onChanged: (bool v) async {
                          await s.setAllowPaymentMethodQuery(v);
                          _notifyActivePage();
                        },
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_unstoppable_domains'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Unstoppable Domains',
                        subtitle: s.resolveUnstoppableDomains
                            ? 'Enabled'
                            : 'Disabled',
                        onTap: () => _showWeb3DomainSheet(
                          innerContext,
                          title: 'Unstoppable Domains',
                          tldExample: '.crypto / .nft / .wallet',
                          currentValue: s.resolveUnstoppableDomains,
                          onChanged: s.setResolveUnstoppableDomains,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_ens_domains'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Ethereum Name Service',
                        subtitle: s.resolveEnsDomains ? 'Enabled' : 'Disabled',
                        onTap: () => _showWeb3DomainSheet(
                          innerContext,
                          title: 'Ethereum Name Service',
                          tldExample: '.eth',
                          currentValue: s.resolveEnsDomains,
                          onChanged: s.setResolveEnsDomains,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_sns_domains'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Solana Name Service',
                        subtitle: s.resolveSnsDomains ? 'Enabled' : 'Disabled',
                        onTap: () => _showWeb3DomainSheet(
                          innerContext,
                          title: 'Solana Name Service',
                          tldExample: '.sol',
                          currentValue: s.resolveSnsDomains,
                          onChanged: s.setResolveSnsDomains,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_secure_dns'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Use secure DNS',
                        subtitle: s.secureDnsMode.label,
                        onTap: () => _showSecureDnsSheet(innerContext),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_js_optimisation'),
                        isDark: isDark,
                        colors: colors,
                        title: 'JavaScript optimisation and security',
                        subtitle: s.jsOptimisationMode.subtitle,
                        onTap: () => _showJsOptimisationSheet(innerContext),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_block_app_notices'),
                        isDark: isDark,
                        colors: colors,
                        title: "Block 'Switch to App' notices",
                        value: s.blockSwitchToAppNotices,
                        onChanged: (bool v) async {
                          await s.setBlockSwitchToAppNotices(v);
                          _notifyActivePage();
                        },
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.action(
                        tileKey: const Key('shield_row_do_not_track'),
                        isDark: isDark,
                        colors: colors,
                        title: "Send a 'Do Not Track' request",
                        subtitle: s.sendDntAndGpc ? 'On' : 'Off',
                        onTap: () => _showDoNotTrackSheet(innerContext),
                      ),
                      const SizedBox(height: 4),
                      _ShieldRowTile.toggle(
                        tileKey: const Key('shield_switch_close_tabs_on_exit'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Close tabs on exit',
                        subtitle: "Don't persist tabs between browsing sessions",
                        value: s.closeTabsOnExit,
                        onChanged: s.setCloseTabsOnExit,
                      ),

                      // Section 5: Per-Site Exceptions & Restore Defaults
                      const SizedBox(height: 18),
                      _SectionTitle('Per-site Shield exceptions', colors),
                      _ShieldRowTile.action(
                        tileKey: const Key('heaven_shield_add_exception_button'),
                        isDark: isDark,
                        colors: colors,
                        title: 'Add Trusted Site Exception',
                        subtitle: 'Pause Heaven Shield on a specific domain',
                        onTap: () => _showAddExceptionDialog(innerContext),
                      ),
                      for (final String host in exceptions) ...<Widget>[
                        const SizedBox(height: 4),
                        Material(
                          color: isDark ? AppTheme.navySurface : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            title: Text(
                              host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: IconButton(
                              key: Key('heaven_shield_remove_exception_$host'),
                              tooltip: 'Remove exception',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () async {
                                await s.removeShieldExceptionHost(host);
                                _notifyActivePage();
                              },
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _ShieldRowTile.action(
                        tileKey: const Key(
                          'heaven_shield_restore_defaults_button',
                        ),
                        isDark: isDark,
                        colors: colors,
                        title: 'Restore Recommended Shield Defaults',
                        subtitle:
                            'Reset all Heaven Shield & privacy settings to safe defaults',
                        onTap: () async {
                          await s.resetHeavenShieldDefaults();
                          _notifyActivePage();
                          if (innerContext.mounted) {
                            ScaffoldMessenger.of(innerContext)
                              ..clearSnackBars()
                              ..showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Heaven Shield restored to recommended defaults',
                                  ),
                                  duration: Duration(milliseconds: 1600),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                          }
                        },
                      ),
                    ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMasterCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    bool enabled,
  ) {
    final Color accent = enabled
        ? AppTheme.shieldEmerald
        : colors.onSurfaceVariant;
    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent.withValues(alpha: enabled ? 0.55 : 0.25),
            width: enabled ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    enabled
                        ? Icons.verified_user_rounded
                        : Icons.shield_outlined,
                    color: accent,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        enabled
                            ? 'Heaven Shield Active'
                            : 'Heaven Shield Paused',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: enabled
                              ? AppTheme.shieldEmerald
                              : colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled
                            ? '${widget.settings.trackersAdsLevel.label} • Zero-telemetry local protection'
                            : 'Tap switch to enable ad & tracker protection',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  key: const Key('heaven_shield_master_switch'),
                  value: enabled,
                  onChanged: (bool v) async {
                    await widget.settings.setShieldEnabled(v);
                    _notifyActivePage();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.bolt_rounded,
                    size: 16,
                    color: AppTheme.shieldEmerald,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Blocked: ${_stats.totalBlocked} total${widget.activeWebViewId != null ? ' • ${_stats.pageBlocked} on page' : ''}',
                      key: const Key('heaven_shield_blocked_counter'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('heaven_shield_reset_stats_button'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                    ),
                    onPressed: () async {
                      await NativeShieldBridge.instance.resetHeavenShieldStats();
                      await _refreshStats();
                    },
                    child: const Text('Reset', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HeavenContentFilteringScreen extends StatefulWidget {
  const HeavenContentFilteringScreen({
    super.key,
    required this.settings,
    this.onFiltersChanged,
  });

  final BrowserSettingsController settings;
  final VoidCallback? onFiltersChanged;

  @override
  State<HeavenContentFilteringScreen> createState() =>
      _HeavenContentFilteringScreenState();
}

class _HeavenContentFilteringScreenState
    extends State<HeavenContentFilteringScreen> {
  late final TextEditingController _customRulesCtrl;

  @override
  void initState() {
    super.initState();
    _customRulesCtrl = TextEditingController(
      text: widget.settings.customFilterRules.join('\n'),
    );
  }

  @override
  void dispose() {
    _customRulesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.deepNavyBg
          : colors.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text(
          'Content filtering',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.settings,
          builder: (BuildContext context, _) {
            final BrowserSettingsController s = widget.settings;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: <Widget>[
                _SectionTitle('Filter lists', colors),
                _ShieldRowTile.toggle(
                  tileKey: const Key('filter_switch_cookie_notices'),
                  isDark: isDark,
                  colors: colors,
                  title: 'EasyList Cookie Notices',
                  subtitle: 'Hides GDPR & cookie consent popups automatically',
                  value: s.shieldBlockCookieBanners,
                  onChanged: (bool v) async {
                    await s.setShieldBlockCookieBanners(v);
                    widget.onFiltersChanged?.call();
                  },
                ),
                const SizedBox(height: 4),
                _ShieldRowTile.toggle(
                  tileKey: const Key('filter_switch_fanboy_annoyances'),
                  isDark: isDark,
                  colors: colors,
                  title: "Fanboy's Annoyances",
                  subtitle:
                      'Blocks floating newsletter modals & page-covering promos',
                  value: s.filterFanboyAnnoyances,
                  onChanged: (bool v) async {
                    await s.setFilterFanboyAnnoyances(v);
                    widget.onFiltersChanged?.call();
                  },
                ),
                const SizedBox(height: 4),
                _ShieldRowTile.toggle(
                  tileKey: const Key('filter_switch_mobile_notifs'),
                  isDark: isDark,
                  colors: colors,
                  title: "Fanboy's Mobile Notifications",
                  subtitle:
                      'Blocks web push-notification nag prompts (OneSignal, PushEngage)',
                  value: s.filterMobileNotifs,
                  onChanged: (bool v) async {
                    await s.setFilterMobileNotifs(v);
                    widget.onFiltersChanged?.call();
                  },
                ),
                const SizedBox(height: 4),
                _ShieldRowTile.toggle(
                  tileKey: const Key('filter_switch_anti_adblock'),
                  isDark: isDark,
                  colors: colors,
                  title: 'Anti-Adblock Defuser',
                  subtitle:
                      'Prevents sites from breaking when ad scripts are blocked',
                  value: s.filterAntiAdblock,
                  onChanged: (bool v) async {
                    await s.setFilterAntiAdblock(v);
                    widget.onFiltersChanged?.call();
                  },
                ),
                const SizedBox(height: 4),
                _ShieldRowTile.toggle(
                  tileKey: const Key('filter_switch_regional_india'),
                  isDark: isDark,
                  colors: colors,
                  title: 'Indian & South Asian Regional List',
                  subtitle: 'Blocks regional ad networks & push trackers',
                  value: s.filterRegionalIndia,
                  onChanged: (bool v) async {
                    await s.setFilterRegionalIndia(v);
                    widget.onFiltersChanged?.call();
                  },
                ),
                const SizedBox(height: 4),
                _ShieldRowTile.toggle(
                  tileKey: const Key('filter_switch_regional_global'),
                  isDark: isDark,
                  colors: colors,
                  title: 'Global Strict Regional Trackers',
                  subtitle:
                      'Blocks international analytics & telemetry endpoints',
                  value: s.filterRegionalGlobal,
                  onChanged: (bool v) async {
                    await s.setFilterRegionalGlobal(v);
                    widget.onFiltersChanged?.call();
                  },
                ),
                const SizedBox(height: 18),
                _SectionTitle('Custom filters', colors),
                Material(
                  color: isDark ? AppTheme.navySurface : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Enter one domain or CSS hide rule per line (e.g. ads.example.com or example.com##.promo-banner)',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          key: const Key('custom_filter_rules_textfield'),
                          controller: _customRulesCtrl,
                          maxLines: 5,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                          ),
                          decoration: const InputDecoration(
                            hintText:
                                '||ads.example.com^\n##.cookie-wall\nnews.site##.sticky-banner',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            key: const Key('save_custom_filter_rules_button'),
                            onPressed: () async {
                              await s.setCustomFilterRulesFromText(
                                _customRulesCtrl.text,
                              );
                              widget.onFiltersChanged?.call();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            child: const Text('Save custom filters'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class HeavenShieldQuickSheet extends StatefulWidget {
  const HeavenShieldQuickSheet({
    super.key,
    required this.settings,
    required this.currentHost,
    required this.activeWebViewId,
    required this.onReloadActivePage,
    required this.onOpenFullShieldSettings,
  });

  final BrowserSettingsController settings;
  final String? currentHost;
  final int? activeWebViewId;
  final VoidCallback onReloadActivePage;
  final VoidCallback onOpenFullShieldSettings;

  @override
  State<HeavenShieldQuickSheet> createState() => _HeavenShieldQuickSheetState();
}

class _HeavenShieldQuickSheetState extends State<HeavenShieldQuickSheet> {
  HeavenShieldStats _stats = const HeavenShieldStats(
    pageBlocked: 0,
    totalBlocked: 0,
    shieldEnabled: true,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loadStats());
  }

  Future<void> _loadStats() async {
    final HeavenShieldStats fetched = await NativeShieldBridge.instance
        .getHeavenShieldStats(webViewId: widget.activeWebViewId);
    if (mounted) {
      setState(() => _stats = fetched);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String host = OmniboxParser.cleanDomain(widget.currentHost);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: ListenableBuilder(
          listenable: widget.settings,
          builder: (BuildContext context, _) {
            final bool activeOnSite = widget.settings.isShieldActiveForHost(
              host,
            );
            final HeavenTrackersAdsLevel currentLevel =
                widget.settings.trackersAdsLevel;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Material(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    child: SwitchListTile.adaptive(
                      key: const Key('quick_shield_site_switch'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      secondary: Icon(
                        activeOnSite
                            ? Icons.verified_user_rounded
                            : Icons.shield_outlined,
                        color: activeOnSite
                            ? AppTheme.shieldEmerald
                            : colors.onSurfaceVariant,
                      ),
                      title: Text(
                        host.isEmpty ? 'Heaven Shield' : host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        activeOnSite
                            ? '${_stats.pageBlocked} trackers & ads blocked on page'
                            : 'Shields DOWN on this site',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: activeOnSite,
                      onChanged: (bool value) async {
                        if (host.isEmpty) {
                          await widget.settings.setShieldEnabled(value);
                        } else {
                          if (value && !widget.settings.shieldEnabled) {
                            await widget.settings.setShieldEnabled(true);
                          }
                          await widget.settings.setShieldProtectionForHost(
                            host,
                            value,
                          );
                        }
                        widget.onReloadActivePage();
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      'Block trackers & ads',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  Material(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (int i = 0;
                            i < HeavenTrackersAdsLevel.values.length;
                            i++) ...<Widget>[
                          if (i > 0)
                            Divider(
                              height: 1,
                              color: colors.outlineVariant.withValues(
                                alpha: 0.28,
                              ),
                            ),
                          Builder(
                            builder: (BuildContext _) {
                              final HeavenTrackersAdsLevel level =
                                  HeavenTrackersAdsLevel.values[i];
                              final bool selected = currentLevel == level;
                              return InkWell(
                                key: Key('quick_shield_mode_${level.name}'),
                                onTap: () async {
                                  if (currentLevel == level) return;
                                  await widget.settings.setTrackersAdsLevel(
                                    level,
                                  );
                                  if (host.isNotEmpty &&
                                      level !=
                                          HeavenTrackersAdsLevel.disabled &&
                                      !widget.settings.isShieldActiveForHost(
                                        host,
                                      )) {
                                    await widget.settings
                                        .setShieldProtectionForHost(host, true);
                                  }
                                  widget.onReloadActivePage();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  color: selected
                                      ? colors.primary.withValues(alpha: 0.11)
                                      : Colors.transparent,
                                  child: Row(
                                    children: <Widget>[
                                      Icon(
                                        selected
                                            ? Icons.radio_button_checked_rounded
                                            : Icons.radio_button_off_rounded,
                                        size: 19,
                                        color: selected
                                            ? colors.primary
                                            : colors.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          level.subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: selected
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            color: selected
                                                ? colors.primary
                                                : colors.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      key: const Key('quick_shield_customize_button'),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onOpenFullShieldSettings();
                      },
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Heaven Shield & privacy settings'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.colors);

  final String text;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: colors.primary,
        ),
      ),
    );
  }
}

class _InfoNoticeCard extends StatelessWidget {
  const _InfoNoticeCard({
    required this.isDark,
    required this.colors,
    required this.text,
  });

  final bool isDark;
  final ColorScheme colors;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.navySurface.withValues(alpha: 0.85)
            : colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.35,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ShieldRowTile extends StatelessWidget {
  const _ShieldRowTile._({
    required this.tileKey,
    required this.isDark,
    required this.colors,
    required this.title,
    this.subtitle,
    this.isToggle = false,
    this.value = false,
    this.onChanged,
    this.onTap,
  });

  factory _ShieldRowTile.toggle({
    Key? tileKey,
    required bool isDark,
    required ColorScheme colors,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return _ShieldRowTile._(
      tileKey: tileKey,
      isDark: isDark,
      colors: colors,
      title: title,
      subtitle: subtitle,
      isToggle: true,
      value: value,
      onChanged: onChanged,
    );
  }

  factory _ShieldRowTile.action({
    Key? tileKey,
    required bool isDark,
    required ColorScheme colors,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return _ShieldRowTile._(
      tileKey: tileKey,
      isDark: isDark,
      colors: colors,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  final Key? tileKey;
  final bool isDark;
  final ColorScheme colors;
  final String title;
  final String? subtitle;
  final bool isToggle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color cardBg = isDark ? AppTheme.navySurface : Colors.white;
    final ShapeBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    if (isToggle) {
      return Material(
        color: cardBg,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile.adaptive(
          key: tileKey,
          shape: shape,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 2,
          ),
          title: Text(
            title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
          ),
          subtitle: subtitle == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
          value: value,
          onChanged: onChanged,
        ),
      );
    }

    return Material(
      color: cardBg,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: tileKey,
        shape: shape,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
        onTap: onTap,
      ),
    );
  }
}

class _RadioSheetOption<T> extends StatelessWidget {
  const _RadioSheetOption({
    this.optionKey,
    required this.title,
    this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onSelect,
  });

  final Key? optionKey;
  final String title;
  final String? subtitle;
  final T value;
  final T groupValue;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final bool selected = value == groupValue;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        key: optionKey,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_off_rounded,
          color: selected ? colors.primary : colors.onSurfaceVariant,
          size: 21,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: const TextStyle(fontSize: 12)),
        onTap: () => onSelect(value),
      ),
    );
  }
}
