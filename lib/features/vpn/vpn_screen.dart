import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'vpn_controller.dart';

typedef HeavenVpnScreen = VpnScreen;

class VpnScreen extends StatelessWidget {
  const VpnScreen({super.key, required this.vpn});

  final VpnController vpn;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: vpn,
      builder: (BuildContext context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Heaven VPN',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Refresh Encrypted Key',
                onPressed: vpn.isBusy ? null : vpn.refreshWarpKeyAndReconnect,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'Import Custom Country .conf',
                onPressed: () => _showAddProfileSheet(context),
                icon: const Icon(Icons.add_moderator_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: <Widget>[
                _buildPowerHeroCard(context, colors, isDark),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.shieldEmerald.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.shieldEmerald.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    children: <Widget>[
                      Icon(
                        Icons.notifications_off_rounded,
                        size: 18,
                        color: AppTheme.shieldEmerald,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Silent Stealth Mode: Runs without any persistent VPN notification card.',
                          style: TextStyle(fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
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
                _buildTunnelScopeCard(colors, isDark),
                const SizedBox(height: 18),
                const Text(
                  'Anti-ISP Block Stealth Routes (Free)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final VpnProfile route in vpn.builtInRoutes) ...<Widget>[
                  _buildProfileTile(context, colors, isDark, route),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Custom Country WireGuard (.conf)',
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
                      label: const Text('Import'),
                    ),
                  ],
                ),
                if (vpn.customProfiles.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.navySurface : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      'Import any free ProtonVPN / Windscribe / Mullvad WireGuard (.conf) file to pick specific countries (USA, Netherlands, Japan) with zero persistent notifications.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                        height: 1.38,
                      ),
                    ),
                  )
                else
                  for (final VpnProfile custom
                      in vpn.customProfiles) ...<Widget>[
                    _buildProfileTile(context, colors, isDark, custom),
                    const SizedBox(height: 8),
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
  ) {
    final bool connected = vpn.isConnected;
    final VpnProfile activeProfile = vpn.selectedProfile;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.navySurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: connected
              ? AppTheme.shieldEmerald.withValues(alpha: 0.65)
              : colors.outlineVariant.withValues(alpha: 0.4),
          width: connected ? 1.6 : 1.0,
        ),
      ),
      child: Column(
        children: <Widget>[
          GestureDetector(
            key: const Key('vpn_power_button'),
            onTap: vpn.isBusy ? null : vpn.toggleConnection,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: connected
                      ? <Color>[
                          AppTheme.shieldEmerald,
                          const Color(0xFF059669),
                        ]
                      : <Color>[colors.primary, AppTheme.sapphireBlue],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: (connected ? AppTheme.shieldEmerald : colors.primary)
                        .withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: 2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: vpn.isBusy
                  ? const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.power_settings_new_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            vpn.isBusy
                ? (vpn.statusMessage ?? 'Connecting...')
                : (connected ? 'VPN Connected' : 'Tap to Unblock Websites'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17.5,
              fontWeight: FontWeight.w800,
              color: connected ? AppTheme.shieldEmerald : colors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${activeProfile.flagEmoji} ${activeProfile.name}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
          if (connected) ...<Widget>[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatColumn(
                    label: 'Download',
                    value: VpnController.formatBytes(vpn.rxBytes),
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    label: 'Upload',
                    value: VpnController.formatBytes(vpn.txBytes),
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    label: 'Exit IP',
                    value: vpn.exitIp != null
                        ? '${vpn.exitCountry ?? ''} ${vpn.exitIp}'.trim()
                        : 'Encrypted',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTunnelScopeCard(ColorScheme colors, bool isDark) {
    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: SwitchListTile(
        title: const Text(
          'Full Encrypted DNS & IPv6 Protection',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        subtitle: Text(
          !vpn.browserOnly
              ? 'Recommended: Prevents ISP DNS poisoning & IPv6 leaks on banned websites'
              : 'Browser-Only Split Tunnel active',
          style: const TextStyle(fontSize: 11.5),
        ),
        value: !vpn.browserOnly,
        onChanged: (bool fullProtection) =>
            vpn.setBrowserOnly(!fullProtection),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? colors.primary
              : colors.outlineVariant.withValues(alpha: 0.35),
          width: selected ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => vpn.selectProfile(profile.id),
        leading: Text(profile.flagEmoji, style: const TextStyle(fontSize: 22)),
        title: Text(
          profile.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        subtitle: Text(
          profile.countryLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!profile.isBuiltInWarp)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                onPressed: () => vpn.removeCustomProfile(profile.id),
              ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? colors.primary : colors.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddProfileSheet(BuildContext context) async {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController countryCtrl = TextEditingController();
    final TextEditingController cfgCtrl = TextEditingController();
    String? errText;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Import Country WireGuard (.conf)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Server Name',
                        hintText: 'e.g. USA Free WireGuard',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: countryCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Country Label',
                        hintText: 'e.g. United States',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: cfgCtrl,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'WireGuard [Interface] & [Peer] Config',
                        hintText: '[Interface]\nPrivateKey = ...\n[Peer]\n...',
                      ),
                    ),
                    if (errText != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        errText!,
                        style: const TextStyle(
                          color: AppTheme.fireCrimson,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () async {
                        final String? err = await vpn.addCustomProfile(
                          name: nameCtrl.text,
                          countryLabel: countryCtrl.text,
                          configText: cfgCtrl.text,
                        );
                        if (err != null) {
                          setModalState(() => errText = err);
                          return;
                        }
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Save Server'),
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
  const _StatColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
