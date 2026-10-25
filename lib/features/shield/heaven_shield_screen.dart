import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/omnibox_parser.dart';
import '../settings/browser_settings.dart';
import 'native_shield_bridge.dart';

class HeavenShieldScreen extends StatefulWidget {
  const HeavenShieldScreen({
    super.key,
    required this.settings,
    this.currentHost,
    this.activeWebViewId,
    this.onShieldChangedForActivePage,
  });

  final BrowserSettingsController settings;
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

  @override
  void initState() {
    super.initState();
    unawaited(_refreshStats());
  }

  Future<void> _refreshStats() async {
    final HeavenShieldStats fetched = await NativeShieldBridge.instance
        .getHeavenShieldStats(webViewId: widget.activeWebViewId);
    if (mounted) {
      setState(() => _stats = fetched);
    }
  }

  Future<void> _showAddExceptionDialog(BuildContext context) async {
    final TextEditingController hostCtrl = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext ctx,
                void Function(void Function()) setDialogState,
              ) {
                return AlertDialog(
                  title: const Text(
                    'Add Site Exception',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(
                        'Heaven Shield will pause ad & tracker blocking on this domain.',
                        style: TextStyle(fontSize: 12.5),
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
                            () => errorText = 'Enter a valid domain (e.g. example.com)',
                          );
                          return;
                        }
                        widget.onShieldChangedForActivePage?.call();
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
            appBar: AppBar(
              centerTitle: false,
              title: const Text(
                'Heaven Shield',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
              ),
            ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.settings,
          builder: (BuildContext context, _) {
            final BrowserSettingsController s = widget.settings;
            final bool enabled = s.shieldEnabled;
            final List<String> exceptions = s.shieldDisabledHosts;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
              children: <Widget>[
                _buildMasterCard(context, colors, isDark, enabled),
                if (cleanHost.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _buildCurrentSiteCard(colors, isDark, cleanHost),
                ],
                const SizedBox(height: 18),
                _SectionHeader('Protection Mode', colors),
                _ShieldCardGroup(
                  isDark: isDark,
                  colors: colors,
                  children: <Widget>[
                    _buildModeOption(
                      key: const Key('heaven_shield_mode_standard'),
                      colors: colors,
                      mode: HeavenShieldMode.standard,
                      selected: s.shieldMode == HeavenShieldMode.standard,
                      enabled: enabled,
                    ),
                    _divider(colors),
                    _buildModeOption(
                      key: const Key('heaven_shield_mode_strict'),
                      colors: colors,
                      mode: HeavenShieldMode.strict,
                      selected: s.shieldMode == HeavenShieldMode.strict,
                      enabled: enabled,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionHeader('Customize Protections', colors),
                _ShieldCardGroup(
                  isDark: isDark,
                  colors: colors,
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      key: const Key('heaven_shield_ads_switch'),
                      dense: true,
                      secondary: Icon(
                        Icons.block_rounded,
                        size: 20,
                        color: enabled && s.shieldBlockAds
                            ? AppTheme.shieldEmerald
                            : colors.onSurfaceVariant,
                      ),
                      title: const Text('Ad & Tracker Blocker'),
                      subtitle: const Text(
                        'Blocks ad networks, malvertising & collapses empty ad slots',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: s.shieldBlockAds,
                      onChanged: enabled
                          ? (bool v) async {
                              await s.setShieldBlockAds(v);
                              widget.onShieldChangedForActivePage?.call();
                            }
                          : null,
                    ),
                    _divider(colors),
                    SwitchListTile.adaptive(
                      key: const Key('heaven_shield_cookie_banners_switch'),
                      dense: true,
                      secondary: Icon(
                        Icons.cookie_outlined,
                        size: 20,
                        color: enabled && s.shieldBlockCookieBanners
                            ? AppTheme.shieldEmerald
                            : colors.onSurfaceVariant,
                      ),
                      title: const Text('Hide Cookie & Consent Banners'),
                      subtitle: const Text(
                        'Suppresses intrusive GDPR & cookie notice overlays',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: s.shieldBlockCookieBanners,
                      onChanged: enabled
                          ? (bool v) async {
                              await s.setShieldBlockCookieBanners(v);
                              widget.onShieldChangedForActivePage?.call();
                            }
                          : null,
                    ),
                    _divider(colors),
                    SwitchListTile.adaptive(
                      key: const Key('heaven_shield_clean_urls_switch'),
                      dense: true,
                      secondary: Icon(
                        Icons.link_off_rounded,
                        size: 20,
                        color: enabled && s.shieldCleanUrls
                            ? AppTheme.shieldEmerald
                            : colors.onSurfaceVariant,
                      ),
                      title: const Text('Clean Tracking URLs'),
                      subtitle: const Text(
                        'Strips utm_*, fbclid, gclid & msclkid tracking parameters',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: s.shieldCleanUrls,
                      onChanged: enabled
                          ? (bool v) async {
                              await s.setShieldCleanUrls(v);
                              widget.onShieldChangedForActivePage?.call();
                            }
                          : null,
                    ),
                    _divider(colors),
                    SwitchListTile.adaptive(
                      key: const Key('heaven_shield_fingerprint_switch'),
                      dense: true,
                      secondary: Icon(
                        Icons.fingerprint_rounded,
                        size: 20,
                        color: enabled && s.shieldAntiFingerprinting
                            ? AppTheme.shieldEmerald
                            : colors.onSurfaceVariant,
                      ),
                      title: const Text('Anti-Fingerprinting Guard'),
                      subtitle: const Text(
                        'Sends GPC/DNT & masks battery, network & hardware entropy',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: s.shieldAntiFingerprinting,
                      onChanged: enabled
                          ? (bool v) async {
                              await s.setShieldAntiFingerprinting(v);
                              widget.onShieldChangedForActivePage?.call();
                            }
                          : null,
                    ),
                    _divider(colors),
                    SwitchListTile.adaptive(
                      key: const Key('heaven_shield_popups_switch'),
                      dense: true,
                      secondary: Icon(
                        Icons.open_in_new_off_rounded,
                        size: 20,
                        color: enabled && s.shieldBlockPopups
                            ? AppTheme.shieldEmerald
                            : colors.onSurfaceVariant,
                      ),
                      title: const Text('Popup & Redirect Guard'),
                      subtitle: const Text(
                        'Blocks unrequested background popups & ad redirects',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: s.shieldBlockPopups,
                      onChanged: enabled
                          ? (bool v) async {
                              await s.setShieldBlockPopups(v);
                              widget.onShieldChangedForActivePage?.call();
                            }
                          : null,
                    ),
                    _divider(colors),
                    SwitchListTile.adaptive(
                      key: const Key('heaven_shield_https_switch'),
                      dense: true,
                      secondary: Icon(
                        Icons.https_outlined,
                        size: 20,
                        color: s.httpsUpgrade
                            ? AppTheme.shieldEmerald
                            : colors.onSurfaceVariant,
                      ),
                      title: const Text('HTTPS-First Upgrade'),
                      subtitle: const Text(
                        'Upgrades http:// links to encrypted https:// automatically',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: s.httpsUpgrade,
                      onChanged: s.setHttpsUpgrade,
                    ),
                    _divider(colors),
                    SwitchListTile.adaptive(
                      key: const Key('heaven_shield_3p_cookies_switch'),
                      dense: true,
                      secondary: Icon(
                        Icons.privacy_tip_outlined,
                        size: 20,
                        color: s.blockThirdPartyCookies
                            ? AppTheme.shieldEmerald
                            : colors.onSurfaceVariant,
                      ),
                      title: const Text('Block Third-Party Cookies'),
                      subtitle: const Text(
                        'Prevents cross-site tracking cookies across websites',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: s.blockThirdPartyCookies,
                      onChanged: s.setBlockThirdPartyCookies,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionHeader('Site Exceptions (Trusted Sites)', colors),
                _ShieldCardGroup(
                  isDark: isDark,
                  colors: colors,
                  children: <Widget>[
                    ListTile(
                      key: const Key('heaven_shield_add_exception_button'),
                      dense: true,
                      leading: Icon(
                        Icons.add_moderator_outlined,
                        size: 20,
                        color: colors.primary,
                      ),
                      title: const Text('Add Trusted Site Exception'),
                      subtitle: const Text(
                        'Pause Heaven Shield on a specific domain',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      trailing: Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: colors.primary,
                      ),
                      onTap: () => _showAddExceptionDialog(context),
                    ),
                    for (final String host in exceptions) ...<Widget>[
                      _divider(colors),
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.language_rounded,
                          size: 19,
                          color: colors.onSurfaceVariant,
                        ),
                        title: Text(
                          host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Shield paused on this site',
                          style: TextStyle(fontSize: 11),
                        ),
                        trailing: IconButton(
                          key: Key('heaven_shield_remove_exception_$host'),
                          tooltip: 'Remove Exception',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: AppTheme.fireCrimson,
                          ),
                          onPressed: () async {
                            await s.removeShieldExceptionHost(host);
                            widget.onShieldChangedForActivePage?.call();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                _ShieldCardGroup(
                  isDark: isDark,
                  colors: colors,
                  children: <Widget>[
                    ListTile(
                      key: const Key('heaven_shield_restore_defaults_button'),
                      dense: true,
                      leading: Icon(
                        Icons.restart_alt_rounded,
                        size: 20,
                        color: colors.primary,
                      ),
                      title: const Text('Restore Recommended Shield Defaults'),
                      onTap: () async {
                        await s.resetHeavenShieldDefaults();
                        widget.onShieldChangedForActivePage?.call();
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
              ],
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
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: accent.withValues(alpha: enabled ? 0.6 : 0.28),
            width: enabled ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    enabled
                        ? Icons.verified_user_rounded
                        : Icons.shield_outlined,
                    color: accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        enabled ? 'Heaven Shield Active' : 'Heaven Shield Paused',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: enabled
                              ? AppTheme.shieldEmerald
                              : colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled
                            ? '${widget.settings.activeShieldProtectionCount} privacy layers • ${widget.settings.shieldMode.label} mode'
                            : 'Tap switch to enable ad & tracker protection',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
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
                    widget.onShieldChangedForActivePage?.call();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.bolt_rounded,
                    size: 17,
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
                    child: const Text('Reset', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentSiteCard(
    ColorScheme colors,
    bool isDark,
    String cleanHost,
  ) {
    final bool siteProtected = widget.settings.isShieldActiveForHost(cleanHost);
    return _ShieldCardGroup(
      isDark: isDark,
      colors: colors,
      children: <Widget>[
        SwitchListTile.adaptive(
          key: const Key('heaven_shield_current_site_switch'),
          dense: true,
          secondary: Icon(
            siteProtected
                ? Icons.gpp_good_rounded
                : Icons.gpp_maybe_outlined,
            size: 20,
            color: siteProtected
                ? AppTheme.shieldEmerald
                : AppTheme.warningAmber,
          ),
          title: Text(
            cleanHost,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            siteProtected
                ? 'Protected on this site'
                : 'Allowlisted (Shield paused on this site)',
            style: const TextStyle(fontSize: 11.5),
          ),
          value: siteProtected,
          onChanged: widget.settings.shieldEnabled
              ? (bool protect) async {
                  await widget.settings.setShieldProtectionForHost(
                    cleanHost,
                    protect,
                  );
                  widget.onShieldChangedForActivePage?.call();
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildModeOption({
    required Key key,
    required ColorScheme colors,
    required HeavenShieldMode mode,
    required bool selected,
    required bool enabled,
  }) {
    return ListTile(
      key: key,
      dense: true,
      enabled: enabled,
      leading: Icon(
        mode == HeavenShieldMode.strict
            ? Icons.security_rounded
            : Icons.tune_rounded,
        size: 20,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
      title: Text(
        mode.label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      subtitle: Text(mode.description, style: const TextStyle(fontSize: 11.5)),
      trailing: Icon(
        selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off,
        size: 19,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
      onTap: enabled
          ? () async {
              await widget.settings.setShieldMode(mode);
              widget.onShieldChangedForActivePage?.call();
            }
          : null,
    );
  }

  Widget _divider(ColorScheme colors) => Divider(
    height: 1,
    indent: 16,
    endIndent: 16,
    color: colors.outlineVariant.withValues(alpha: 0.25),
  );
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
    final HeavenShieldStats s = await NativeShieldBridge.instance
        .getHeavenShieldStats(webViewId: widget.activeWebViewId);
    if (mounted) {
      setState(() => _stats = s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String cleanHost = OmniboxParser.cleanDomain(widget.currentHost);

    return SafeArea(
      child: ListenableBuilder(
        listenable: widget.settings,
        builder: (BuildContext context, _) {
          final BrowserSettingsController s = widget.settings;
          final bool activeOnSite = cleanHost.isEmpty
              ? s.shieldEnabled
              : s.isShieldActiveForHost(cleanHost);

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: (activeOnSite
                                ? AppTheme.shieldEmerald
                                : colors.onSurfaceVariant)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        activeOnSite
                            ? Icons.verified_user_rounded
                            : Icons.shield_outlined,
                        color: activeOnSite
                            ? AppTheme.shieldEmerald
                            : colors.onSurfaceVariant,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            cleanHost.isEmpty ? 'Heaven Shield' : cleanHost,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            activeOnSite
                                ? '${_stats.pageBlocked} blocked on page • ${_stats.totalBlocked} total'
                                : 'Protection paused for this site',
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
                      key: const Key('quick_shield_site_switch'),
                      value: activeOnSite,
                      onChanged: (bool nextVal) async {
                        if (cleanHost.isEmpty) {
                          await s.setShieldEnabled(nextVal);
                        } else {
                          if (!s.shieldEnabled && nextVal) {
                            await s.setShieldEnabled(true);
                          }
                          await s.setShieldProtectionForHost(
                            cleanHost,
                            nextVal,
                          );
                        }
                        widget.onReloadActivePage();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<HeavenShieldMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const <ButtonSegment<HeavenShieldMode>>[
                    ButtonSegment<HeavenShieldMode>(
                      value: HeavenShieldMode.standard,
                      label: Text('Standard'),
                      icon: Icon(Icons.tune_rounded, size: 16),
                    ),
                    ButtonSegment<HeavenShieldMode>(
                      value: HeavenShieldMode.strict,
                      label: Text('Strict'),
                      icon: Icon(Icons.security_rounded, size: 16),
                    ),
                  ],
                  selected: <HeavenShieldMode>{s.shieldMode},
                  onSelectionChanged: s.shieldEnabled
                      ? (Set<HeavenShieldMode> sel) async {
                          await s.setShieldMode(sel.first);
                          widget.onReloadActivePage();
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  key: const Key('quick_shield_customize_button'),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onOpenFullShieldSettings();
                  },
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Customize Heaven Shield'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.colors);

  final String title;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: colors.primary,
        ),
      ),
    );
  }
}

class _ShieldCardGroup extends StatelessWidget {
  const _ShieldCardGroup({
    required this.isDark,
    required this.colors,
    required this.children,
  });

  final bool isDark;
  final ColorScheme colors;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
