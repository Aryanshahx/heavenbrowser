import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:heavenbrowser/core/theme/app_theme.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/features/browser/engine/browser_engine.dart';
import 'package:heavenbrowser/features/browser/presentation/widgets/omnibox_bar.dart';
import 'package:heavenbrowser/features/browser/presentation/widgets/site_privacy_sheet.dart';
import 'package:heavenbrowser/features/browser/presentation/widgets/start_page_view.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';
import 'package:heavenbrowser/features/settings/presentation/settings_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.settings,
    required this.engine,
    this.initialExternalUrl,
  });

  final BrowserSettingsController settings;
  final BrowserEngine engine;
  final String? initialExternalUrl;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with WidgetsBindingObserver {
  final GlobalKey<OmniboxBarState> _omniboxKey = GlobalKey<OmniboxBarState>();
  final TextEditingController _omniboxController = TextEditingController();
  final FocusNode _omniboxFocusNode = FocusNode();
  final TextEditingController _findController = TextEditingController();

  bool _findBarVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_onSettingsChanged);

    final String? launchUrlStr = widget.initialExternalUrl;
    if (launchUrlStr != null && launchUrlStr.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _submitOmnibox(launchUrlStr);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_onSettingsChanged);
    _omniboxController.dispose();
    _omniboxFocusNode.dispose();
    _findController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    widget.engine.syncSettings(widget.settings);
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final Uri uri = routeInformation.uri;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      await widget.engine.loadUri(uri);
      return true;
    }
    return false;
  }

  Future<void> _submitOmnibox(String rawInput) async {
    final Uri resolved = OmniboxParser.resolveInput(
      rawInput,
      searchEngine: widget.settings.searchEngine,
      httpsUpgrade: widget.settings.httpsUpgrade,
    );
    if (_findBarVisible) {
      setState(() => _findBarVisible = false);
      await widget.engine.clearFind();
    }
    await widget.engine.loadUri(resolved);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext ctx) => SettingsScreen(
          settings: widget.settings,
          onClearAllBrowsingData: widget.engine.clearSiteData,
        ),
      ),
    );
  }

  void _openSitePrivacySheet() {
    final BrowserPageState page = widget.engine.state;
    if (!page.hasActivePage) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return SitePrivacySheet(
          pageState: page,
          settings: widget.settings,
          onToggleSiteTrust: () async {
            final String? host = page.host;
            if (host != null) {
              await widget.settings.toggleHostTrust(host);
              await widget.engine.reload();
            }
          },
          onClearSiteData: () async {
            await widget.engine.clearSiteData();
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Site cookies & storage cleared'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmFireWipe() async {
    final bool? confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        final TextTheme textTheme = Theme.of(sheetContext).textTheme;
        final ColorScheme colors = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 44,
                  color: AppTheme.fireCrimson,
                ),
                const SizedBox(height: 10),
                Text(
                  'Burn Session & Site Data?',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This immediately wipes all cookies, cached files, local storage, and closes your current session.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.fireCrimson,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        icon: const Icon(Icons.local_fire_department_rounded),
                        label: const Text('Burn Now'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      setState(() => _findBarVisible = false);
      await widget.engine.wipeSessionAndData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session burned — cookies, cache & storage wiped'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openBrowserMenu() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            widget.settings,
            widget.engine,
          ]),
          builder: (BuildContext context, _) {
            final BrowserPageState page = widget.engine.state;
            final ColorScheme colors = Theme.of(context).colorScheme;
            final String? url = page.currentUrl;

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: <Widget>[
                        _MenuQuickAction(
                          icon: Icons.refresh_rounded,
                          label: 'Reload',
                          onTap: page.hasActivePage
                              ? () {
                                  Navigator.of(sheetContext).pop();
                                  widget.engine.reload();
                                }
                              : null,
                        ),
                        _MenuQuickAction(
                          icon: Icons.share_outlined,
                          label: 'Share',
                          onTap: (url != null && url.isNotEmpty)
                              ? () async {
                                  Navigator.of(sheetContext).pop();
                                  await SharePlus.instance.share(
                                    ShareParams(
                                      text: url,
                                      title: page.pageTitle,
                                    ),
                                  );
                                }
                              : null,
                        ),
                        _MenuQuickAction(
                          icon: Icons.search_rounded,
                          label: 'Find',
                          onTap: page.hasActivePage
                              ? () {
                                  Navigator.of(sheetContext).pop();
                                  setState(() {
                                    _findBarVisible = true;
                                    _findController.clear();
                                  });
                                }
                              : null,
                        ),
                        _MenuQuickAction(
                          icon: Icons.copy_rounded,
                          label: 'Copy URL',
                          onTap: (url != null && url.isNotEmpty)
                              ? () async {
                                  Navigator.of(sheetContext).pop();
                                  await Clipboard.setData(
                                    ClipboardData(text: url),
                                  );
                                  if (!mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text('Link copied to clipboard'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.desktop_windows_outlined),
                      title: const Text('Desktop Site'),
                      value: widget.settings.desktopMode,
                      onChanged: (bool val) async {
                        await widget.settings.setDesktopMode(val);
                        if (page.hasActivePage) {
                          await widget.engine.reload();
                        }
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.shield_outlined),
                      title: const Text('Heaven Shield'),
                      subtitle: Text(
                        '${widget.settings.totalTrackersBlocked} trackers blocked total',
                      ),
                      value: widget.settings.shieldEnabled,
                      onChanged: (bool val) async {
                        await widget.settings.setShieldEnabled(val);
                        if (page.hasActivePage) {
                          await widget.engine.reload();
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.text_fields_rounded),
                      title: const Text('Text Zoom'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            onPressed: widget.settings.textZoom > 75
                                ? () => widget.settings.setTextZoom(
                                      widget.settings.textZoom - 10,
                                    )
                                : null,
                            icon: const Icon(Icons.remove_rounded),
                          ),
                          Text(
                            '${widget.settings.textZoom}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                          IconButton(
                            onPressed: widget.settings.textZoom < 150
                                ? () => widget.settings.setTextZoom(
                                      widget.settings.textZoom + 10,
                                    )
                                : null,
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                    ),
                    if (url != null && url.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.open_in_new_rounded),
                        title: const Text('Open in External App'),
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          final Uri? parsed = Uri.tryParse(url);
                          if (parsed != null) {
                            await launchUrl(
                              parsed,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                      ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Settings'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _openSettings();
                      },
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.settings,
        widget.engine,
      ]),
      builder: (BuildContext context, _) {
        final BrowserPageState page = widget.engine.state;
        final bool isOmniboxEditing =
            _omniboxKey.currentState?.isEditing ?? _omniboxFocusNode.hasFocus;
        final bool canInterceptBack = isOmniboxEditing ||
            _findBarVisible ||
            page.canGoBack ||
            page.hasActivePage;

        final Widget omnibox = OmniboxBar(
          key: _omniboxKey,
          pageState: page,
          controller: _omniboxController,
          focusNode: _omniboxFocusNode,
          searchEngineLabel: widget.settings.searchEngine.label,
          onSubmitted: _submitOmnibox,
          onBack: widget.engine.goBack,
          onForward: widget.engine.goForward,
          onReloadOrStop: () {
            if (page.isLoading) {
              widget.engine.stopLoading();
            } else {
              widget.engine.reload();
            }
          },
          onHome: () {
            setState(() => _findBarVisible = false);
            widget.engine.showHome();
          },
          onTapSecurityBadge: _openSitePrivacySheet,
          onFireWipe: _confirmFireWipe,
          onOpenMenu: _openBrowserMenu,
        );

        final Widget progressIndicator = page.isLoading
            ? LinearProgressIndicator(
                value: page.progress > 0 && page.progress < 100
                    ? page.progress / 100.0
                    : null,
                minHeight: 2.5,
              )
            : const SizedBox(height: 2.5);

        return PopScope(
          canPop: !canInterceptBack,
          onPopInvokedWithResult: (bool didPop, Object? result) async {
            if (didPop) {
              return;
            }
            if (_omniboxKey.currentState?.isEditing == true ||
                _omniboxFocusNode.hasFocus) {
              _omniboxKey.currentState?.cancelEditing();
              return;
            }
            if (_findBarVisible) {
              setState(() => _findBarVisible = false);
              await widget.engine.clearFind();
              return;
            }
            if (page.canGoBack) {
              await widget.engine.goBack();
              return;
            }
            if (page.hasActivePage) {
              widget.engine.showHome();
            }
          },
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: <Widget>[
                  if (widget.settings.omniboxPosition ==
                      OmniboxPosition.top) ...<Widget>[
                    omnibox,
                    progressIndicator,
                  ],
                  if (_findBarVisible && page.hasActivePage)
                    _FindInPageBar(
                      controller: _findController,
                      matches: page.findMatches,
                      onChanged: widget.engine.findInPage,
                      onPrevious: () =>
                          widget.engine.findNext(forward: false),
                      onNext: () => widget.engine.findNext(forward: true),
                      onClose: () {
                        setState(() => _findBarVisible = false);
                        widget.engine.clearFind();
                      },
                    ),
                  Expanded(
                    child: !page.hasActivePage
                        ? StartPageView(
                            settings: widget.settings,
                            onFocusOmnibox: () =>
                                _omniboxKey.currentState?.activateEditing(),
                            onOpenUrl: _submitOmnibox,
                            onOpenSettings: _openSettings,
                          )
                        : Stack(
                            children: <Widget>[
                              Positioned.fill(
                                child: widget.engine.buildViewport(context),
                              ),
                              if (page.errorDescription != null)
                                Positioned.fill(
                                  child: _ErrorRecoveryOverlay(
                                    url: page.currentUrl ?? '',
                                    message: page.errorDescription!,
                                    onRetry: widget.engine.reload,
                                    onGoHome: widget.engine.showHome,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  if (widget.settings.omniboxPosition ==
                      OmniboxPosition.bottom) ...<Widget>[
                    progressIndicator,
                    omnibox,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MenuQuickAction extends StatelessWidget {
  const _MenuQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 20,
                color: enabled ? colors.onSurface : colors.outline,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: enabled ? colors.onSurface : colors.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FindInPageBar extends StatelessWidget {
  const _FindInPageBar({
    required this.controller,
    required this.matches,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final FindMatchesState matches;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Find in page...',
              ),
              onChanged: onChanged,
            ),
          ),
          Text(
            '${matches.current}/${matches.total}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: matches.total > 0 ? onPrevious : null,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: matches.total > 0 ? onNext : null,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _ErrorRecoveryOverlay extends StatelessWidget {
  const _ErrorRecoveryOverlay({
    required this.url,
    required this.message,
    required this.onRetry,
    required this.onGoHome,
  });

  final String url;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool blockedByShield = message.startsWith('Blocked by Heaven Shield');

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          elevation: 0,
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  blockedByShield
                      ? Icons.gpp_good_rounded
                      : Icons.wifi_off_rounded,
                  size: 48,
                  color: blockedByShield
                      ? AppTheme.shieldEmerald
                      : AppTheme.warningAmber,
                ),
                const SizedBox(height: 14),
                Text(
                  blockedByShield
                      ? 'Protected by Heaven Shield'
                      : 'Unable to Load Page',
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.outline,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onGoHome,
                        child: const Text('Start Page'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
