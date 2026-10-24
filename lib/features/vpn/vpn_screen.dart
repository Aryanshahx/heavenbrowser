import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'vpn_controller.dart';

class HeavenVpnScreen extends StatefulWidget {
  const HeavenVpnScreen({super.key, required this.vpn});

  final VpnController vpn;

  @override
  State<HeavenVpnScreen> createState() => _HeavenVpnScreenState();
}

class _HeavenVpnScreenState extends State<HeavenVpnScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.vpn.enableNativePolling) {
      unawaited(widget.vpn.refreshLiveForeignServers());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: widget.vpn,
      builder: (BuildContext context, _) {
        final VpnController vpn = widget.vpn;
        final bool connected = vpn.isConnected;
        final Color activeColor = connected
            ? AppTheme.shieldEmerald
            : colors.primary;

        final List<VpnProfile> all = vpn.allProfiles;
        final String q = _searchQuery.trim().toLowerCase();
        final List<VpnProfile> filtered = q.isEmpty
            ? all
            : all
                  .where(
                    (VpnProfile p) =>
                        p.name.toLowerCase().contains(q) ||
                        p.countryCode.toLowerCase().contains(q) ||
                        p.countryLabel.toLowerCase().contains(q),
                  )
                  .toList(growable: false);

        return Scaffold(
          appBar: AppBar(
            centerTitle: false,
            title: const Text(
              'VPN',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Refresh Live Countries',
                icon: vpn.isRefreshingServers
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 20),
                onPressed: vpn.isRefreshingServers
                    ? null
                    : vpn.refreshLiveForeignServers,
              ),
              IconButton(
                tooltip: 'Import Custom .conf / .ovpn',
                icon: const Icon(Icons.add_rounded, size: 22),
                onPressed: () => _showAddProfileSheet(context),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: _buildMinimalConnectionCard(
                    context,
                    colors,
                    isDark,
                    activeColor,
                  ),
                ),
                if (vpn.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.fireCrimson.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppTheme.fireCrimson,
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              vpn.errorMessage!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.navySurface
                          : colors.surfaceContainerHighest.withValues(
                              alpha: 0.55,
                            ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.32),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const Key('vpn_country_search_field'),
                            controller: _searchController,
                            onChanged: (String val) {
                              setState(() => _searchQuery = val);
                            },
                            style: const TextStyle(fontSize: 13.5),
                            decoration: InputDecoration(
                              hintText: 'Search ${all.length} countries...',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: Icon(
                              Icons.close_rounded,
                              size: 17,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (BuildContext context, int index) {
                      return _buildMinimalCountryTile(
                        context,
                        colors,
                        isDark,
                        filtered[index],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMinimalConnectionCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    Color activeColor,
  ) {
    final VpnController vpn = widget.vpn;
    final bool connected = vpn.isConnected;
    final VpnProfile active = vpn.selectedProfile;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.navySurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: activeColor.withValues(alpha: connected ? 0.65 : 0.32),
          width: connected ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              GestureDetector(
                key: const Key('vpn_power_button'),
                onTap: vpn.isBusy ? null : vpn.toggleConnection,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeColor,
                  ),
                  child: Center(
                    child: vpn.isBusy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            connected
                                ? Icons.power_settings_new_rounded
                                : Icons.power_settings_new_rounded,
                            size: 26,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      vpn.isBusy
                          ? (vpn.statusMessage ?? 'Connecting...')
                          : (connected ? 'Connected' : 'Disconnected'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: connected
                            ? AppTheme.shieldEmerald
                            : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${active.flagEmoji} ${active.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (connected) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        '↓ ${VpnController.formatBytes(vpn.rxBytes)} • ↑ ${VpnController.formatBytes(vpn.txBytes)}${vpn.exitIp != null ? ' • ${vpn.exitIp}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              InkWell(
                key: const Key('vpn_split_tunnel_chip'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => vpn.setBrowserOnly(!vpn.browserOnly),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    vpn.browserOnly ? 'Browser Only' : 'Full Device',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalCountryTile(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    VpnProfile profile,
  ) {
    final VpnController vpn = widget.vpn;
    final bool selected = vpn.selectedProfileId == profile.id;

    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        key: Key('vpn_country_tile_${profile.id}'),
        borderRadius: BorderRadius.circular(13),
        onTap: vpn.isBusy ? null : () => vpn.selectProfile(profile.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? colors.primary
                  : colors.outlineVariant.withValues(alpha: 0.28),
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: <Widget>[
              Text(profile.flagEmoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Text(
                profile.countryCode.isNotEmpty &&
                        profile.countryCode != 'AUTO_FOREIGN'
                    ? profile.countryCode
                    : (profile.isBuiltInWarp ? 'WARP' : 'AUTO'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (!profile.isBuiltIn) ...<Widget>[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: () => vpn.removeCustomProfile(profile.id),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppTheme.fireCrimson,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 18,
                color: selected
                    ? colors.primary
                    : colors.onSurfaceVariant.withValues(alpha: 0.45),
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
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder:
              (BuildContext ctx, void Function(void Function()) setModalState) {
                final double bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
                return SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottomInset),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Expanded(
                              child: Text(
                                'Import WireGuard / OpenVPN',
                                style: TextStyle(
                                  fontSize: 15.5,
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
                            labelText: 'Country / Name',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: confCtrl,
                          minLines: 4,
                          maxLines: 7,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          decoration: const InputDecoration(
                            labelText: '.conf or .ovpn configuration',
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
                        FilledButton(
                          onPressed: () async {
                            final String? err = await widget.vpn
                                .addCustomProfile(
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
                          child: const Text('Save Country'),
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
