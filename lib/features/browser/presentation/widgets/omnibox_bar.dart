import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:heavenbrowser/core/theme/app_theme.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/features/browser/engine/browser_engine.dart';

class OmniboxBar extends StatefulWidget {
  const OmniboxBar({
    super.key,
    required this.pageState,
    required this.controller,
    required this.focusNode,
    required this.searchEngineLabel,
    required this.onSubmitted,
    required this.onBack,
    required this.onForward,
    required this.onReloadOrStop,
    required this.onHome,
    required this.onTapSecurityBadge,
    required this.onFireWipe,
    required this.onOpenMenu,
  });

  final BrowserPageState pageState;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String searchEngineLabel;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReloadOrStop;
  final VoidCallback onHome;
  final VoidCallback onTapSecurityBadge;
  final VoidCallback onFireWipe;
  final VoidCallback onOpenMenu;

  @override
  State<OmniboxBar> createState() => OmniboxBarState();
}

class OmniboxBarState extends State<OmniboxBar> {
  bool _isEditing = false;
  String? _clipboardPreview;

  bool get isEditing => _isEditing;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChange);
    widget.controller.addListener(_handleTextChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    widget.controller.removeListener(_handleTextChange);
    super.dispose();
  }

  void _handleTextChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> activateEditing() async {
    final String initialText = widget.pageState.currentUrl ?? '';
    widget.controller.value = TextEditingValue(
      text: initialText,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: initialText.length,
      ),
    );
    setState(() {
      _isEditing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.focusNode.requestFocus();
      }
    });
    try {
      final ClipboardData? clip =
          await Clipboard.getData(Clipboard.kTextPlain);
      final String? text = clip?.text?.trim();
      if (mounted && _isEditing) {
        setState(() {
          _clipboardPreview = (text != null && text.isNotEmpty) ? text : null;
        });
      }
    } catch (_) {}
  }

  void cancelEditing() {
    widget.focusNode.unfocus();
    if (mounted) {
      setState(() {
        _isEditing = false;
        _clipboardPreview = null;
      });
    }
  }

  void _handleFocusChange() {
    if (!widget.focusNode.hasFocus && _isEditing && mounted) {
      setState(() {
        _isEditing = false;
        _clipboardPreview = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final BrowserPageState page = widget.pageState;
    final int blockedCount = page.blockedDomainsOnPage.length;

    return Material(
      color: isDark ? const Color(0xFF101625) : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.outlineVariant.withAlpha(120)),
            bottom: BorderSide(color: colors.outlineVariant.withAlpha(120)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_isEditing && _clipboardPreview != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: const Icon(Icons.content_paste_go_rounded, size: 16),
                    label: Text(
                      'Paste & Go: $_clipboardPreview',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () {
                      final String target = _clipboardPreview!;
                      cancelEditing();
                      widget.onSubmitted(target);
                    },
                  ),
                ),
              ),
            Row(
              children: <Widget>[
                if (!_isEditing) ...<Widget>[
                  _CompactNavButton(
                    tooltip: 'Back',
                    icon: Icons.arrow_back_ios_new_rounded,
                    onPressed: page.canGoBack ? widget.onBack : null,
                  ),
                  _CompactNavButton(
                    tooltip: 'Forward',
                    icon: Icons.arrow_forward_ios_rounded,
                    onPressed: page.canGoForward ? widget.onForward : null,
                  ),
                ],
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1B2438)
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: _isEditing
                            ? colors.primary
                            : colors.outlineVariant,
                        width: _isEditing ? 1.5 : 1,
                      ),
                    ),
                    child: _isEditing
                        ? Row(
                            children: <Widget>[
                              const SizedBox(width: 12),
                              Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  key: const ValueKey<String>('omnibox_input'),
                                  controller: widget.controller,
                                  focusNode: widget.focusNode,
                                  autofocus: true,
                                  keyboardType: TextInputType.url,
                                  textInputAction: TextInputAction.go,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  style: textTheme.bodyMedium,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText:
                                        'Search ${widget.searchEngineLabel} or type URL',
                                  ),
                                  onSubmitted: (String value) {
                                    cancelEditing();
                                    if (value.trim().isNotEmpty) {
                                      widget.onSubmitted(value);
                                    }
                                  },
                                ),
                              ),
                              if (widget.controller.text.isNotEmpty)
                                IconButton(
                                  tooltip: 'Clear input',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  onPressed: widget.controller.clear,
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                ),
                            ],
                          )
                        : Row(
                            children: <Widget>[
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: page.hasActivePage
                                    ? widget.onTapSecurityBadge
                                    : activateEditing,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Icon(
                                    !page.hasActivePage
                                        ? Icons.shield_outlined
                                        : (page.isSecureHttps
                                            ? Icons.lock_rounded
                                            : Icons.warning_amber_rounded),
                                    size: 17,
                                    color: !page.hasActivePage
                                        ? colors.primary
                                        : (page.isSecureHttps
                                            ? AppTheme.shieldEmerald
                                            : AppTheme.warningAmber),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: activateEditing,
                                  child: Text(
                                    page.hasActivePage
                                        ? OmniboxParser.formatDisplayUrl(
                                            page.currentUrl,
                                          )
                                        : 'Search or enter address',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: page.hasActivePage
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: page.hasActivePage
                                          ? colors.onSurface
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                              if (page.hasActivePage && blockedCount > 0)
                                GestureDetector(
                                  onTap: widget.onTapSecurityBadge,
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.shieldEmerald.withAlpha(35),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$blockedCount',
                                      style: textTheme.labelSmall?.copyWith(
                                        color: AppTheme.shieldEmerald,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              if (page.hasActivePage)
                                IconButton(
                                  tooltip: page.isLoading ? 'Stop' : 'Reload',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 34,
                                  ),
                                  onPressed: widget.onReloadOrStop,
                                  icon: Icon(
                                    page.isLoading
                                        ? Icons.close_rounded
                                        : Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                if (_isEditing)
                  TextButton(
                    onPressed: cancelEditing,
                    child: const Text('Cancel'),
                  )
                else ...<Widget>[
                  _CompactNavButton(
                    tooltip: 'Start Page',
                    icon: Icons.home_outlined,
                    onPressed: page.hasActivePage ? widget.onHome : null,
                  ),
                  _CompactNavButton(
                    tooltip: 'Burn Session & Clear Data',
                    icon: Icons.local_fire_department_rounded,
                    color: AppTheme.fireCrimson,
                    onPressed: widget.onFireWipe,
                  ),
                  _CompactNavButton(
                    tooltip: 'Browser Menu',
                    icon: Icons.more_vert_rounded,
                    onPressed: widget.onOpenMenu,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactNavButton extends StatelessWidget {
  const _CompactNavButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: onPressed != null ? color : null),
    );
  }
}
