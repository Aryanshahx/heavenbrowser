import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'vpn_controller.dart';

class HeavenVpnScreen extends StatelessWidget {
  const HeavenVpnScreen({super.key, required this.vpn});

  final VpnController vpn;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: vpn,
      builder: (BuildContext context, _) {
        final bool connected = vpn.isConnected;
        final Color activeColor = connected
            ? AppTheme.shieldEmerald
            : colors.primary;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Heaven VPN',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Refresh Live Foreign Servers',
                icon: vpn.isRefreshingServers
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.public_rounded),
                onPressed: vpn.isRefreshingServers
                    ? null
                    : vpn.refreshLiveForeignServers,
              ),
              IconButton(
                tooltip: 'Import Custom .conf / .ovpn',
                icon: const Icon(Icons.add_moderator_outlined),
                onPressed: () => _showAddProfileSheet(context),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: <Widget>[
                _buildPowerHeroCard(context, colors, isDark, activeColor),
                if (vpn.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.fireCrimson.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.fireCrimson.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppTheme.fireCrimson,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            vpn.errorMessage!,
                            style: const TextStyle(fontSize: 12.5, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _buildSplitTunnelCard(colors, isDark),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Foreign Country Servers (Free)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: vpn.isRefreshingServers
                          ? null
                          : vpn.refreshLiveForeignServers,
                      icon: const Icon(Icons.sync_rounded, size: 16),
                      label: const Text('More'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final VpnProfile profile in vpn.foreignProfiles) ...<Widget>[
                  _buildProfileTile(context, colors, isDark, profile),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Low-Ping Local Unblocker',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                _buildProfileTile(context, colors, isDark, vpn.builtInWarpProfile),
                if (vpn.customProfiles.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'Custom Imported Configs',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _showAddProfileSheet(context),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final VpnProfile profile in vpn.customProfiles) ...<Widget>[
                    _buildProfileTile(context, colors, isDark, profile),
                    const SizedBox(height: 8),
                  ],
                ] else ...<Widget>[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _showAddProfileSheet(context),
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Import Custom WireGuard / OpenVPN'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPowerHeroCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    Color activeColor,
  ) {
    final bool connected = vpn.isConnected;
    final VpnProfile activeProfile = vpn.selectedProfile;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.navySurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: activeColor.withValues(alpha: connected ? 0.65 : 0.35),
          width: connected ? 1.8 : 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: activeColor.withValues(alpha: connected ? 0.18 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          GestureDetector(
            key: const Key('vpn_power_button'),
            onTap: vpn.isBusy ? null : vpn.toggleConnection,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: connected
                      ? <Color>[AppTheme.shieldEmerald, const Color(0xFF059669)]
                      : <Color>[colors.primary, AppTheme.sapphireBlue],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.38),
                    blurRadius: 22,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: vpn.isBusy
                    ? const SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        connected
                            ? Icons.verified_user_rounded
                            : Icons.power_settings_new_rounded,
                        size: 46,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            vpn.isBusy
                ? (vpn.statusMessage ?? 'Connecting...')
                : (connected ? 'VPN Connected' : 'Tap to Connect Free VPN'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17.5,
              fontWeight: FontWeight.w800,
              color: connected ? AppTheme.shieldEmerald : colors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${activeProfile.flagEmoji} ${activeProfile.name} • ${activeProfile.countryLabel}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
          if (connected) ...<Widget>[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatColumn(
                    label: 'Download',
                    value: VpnController.formatBytes(vpn.rxBytes),
                    icon: Icons.south_rounded,
                    accent: AppTheme.shieldEmerald,
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    label: 'Upload',
                    value: VpnController.formatBytes(vpn.txBytes),
                    icon: Icons.north_rounded,
                    accent: colors.primary,
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    label: 'Exit IP',
                    value: vpn.exitIp != null
                        ? (vpn.exitCountry != null
                              ? '${vpn.exitCountry} • ${vpn.exitIp}'
                              : vpn.exitIp!)
                        : 'Encrypted',
                    icon: Icons.public_rounded,
                    accent: AppTheme.incognitoCyan,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSplitTunnelCard(ColorScheme colors, bool isDark) {
    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.38)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile.adaptive(
        title: const Text(
          'Browser-Only Split Tunnel',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          vpn.browserOnly
              ? 'Only Heaven Browser uses the foreign VPN. WhatsApp, UPI & phone apps stay on local Wi-Fi/5G.'
              : 'Entire device traffic is routed through Heaven VPN.',
          style: const TextStyle(fontSize: 12),
        ),
        value: vpn.browserOnly,
        onChanged: vpn.setBrowserOnly,
      ),
    );
  }

  Widget _buildProfileTile(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    VpnProfile profile,
  ) {
    final bool selected = vpn.selectedProfileId == profile.id;

    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: vpn.isBusy ? null : () => vpn.selectProfile(profile.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? colors.primary
                  : colors.outlineVariant.withValues(alpha: 0.38),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Text(profile.flagEmoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      profile.countryLabel,
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
              if (profile.isBuiltInWarp)
                IconButton(
                  tooltip: 'Rotate anonymous WireGuard key',
                  visualDensity: VisualDensity.compact,
                  onPressed: vpn.isBusy ? null : vpn.rotateFreeWarpIdentity,
                  icon: const Icon(Icons.key_rounded, size: 18),
                )
              else if (!profile.isBuiltIn)
                IconButton(
                  tooltip: 'Remove profile',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => vpn.removeCustomProfile(profile.id),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: AppTheme.fireCrimson,
                  ),
                ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddProfileSheet(BuildContext context) async {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController countryCtrl = TextEditingController();
    final TextEditingController confCtrl = TextEditingController();
    String? validationError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder:
              (BuildContext ctx, void Function(void Function()) setModalState) {
                final double bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
                return SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Expanded(
                              child: Text(
                                'Import Custom .conf / .ovpn',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final ClipboardData? clip =
                                    await Clipboard.getData('text/plain');
                                if (clip?.text != null &&
                                    clip!.text!.trim().isNotEmpty) {
                                  confCtrl.text = clip.text!.trim();
                                  setModalState(() => validationError = null);
                                }
                              },
                              icon: const Icon(
                                Icons.content_paste_rounded,
                                size: 16,
                              ),
                              label: const Text('Paste'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Profile Name (e.g. UK London VPN)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: countryCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Country (e.g. United Kingdom)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: confCtrl,
                          minLines: 5,
                          maxLines: 8,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          decoration: const InputDecoration(
                            labelText: 'WireGuard (.conf) or OpenVPN (.ovpn)',
                            hintText:
                                'Paste [Interface]...[Peer]... OR client\\ndev tun\\nremote ...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (validationError != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            validationError!,
                            style: const TextStyle(
                              color: AppTheme.fireCrimson,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () async {
                            final String? err = await vpn.addCustomProfile(
                              name: nameCtrl.text,
                              countryLabel: countryCtrl.text,
                              configText: confCtrl.text,
                            );
                            if (err != null) {
                              setModalState(() => validationError = err);
                              return;
                            }
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save Country Profile'),
                        ),
                      ],
                    ),
                  ),
                );
              },
        );
      },
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 16, color: accent),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
