import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, this.onOpenUrlInBrowser});

  static const String supportEmail = 'techlabs.hyper@gmail.com';
  final ValueChanged<String>? onOpenUrlInBrowser;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String _topic = 'Bug Report';
  final TextEditingController _messageController = TextEditingController();

  static const List<String> _topics = <String>[
    'Bug Report',
    'VPN / Banned Website Issue',
    'Chrome Extensions (.crx)',
    'Background Media & PiP',
    'General Question',
  ];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _openPrivacyPolicy() async {
    if (widget.onOpenUrlInBrowser != null) {
      Navigator.pop(context);
      widget.onOpenUrlInBrowser!(AppConstants.privacyPolicyUrl);
      return;
    }
    final Uri uri = Uri.parse(AppConstants.privacyPolicyUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      await Clipboard.setData(
        const ClipboardData(text: AppConstants.privacyPolicyUrl),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Privacy Policy link copied to clipboard!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _sendSupportEmail() async {
    final String bodyText = _messageController.text.trim();
    final String subject =
        '[Heaven Browser v${AppConstants.appVersion}] $_topic';
    final String fullBody =
        '${bodyText.isEmpty ? 'Hi HyperTech Labs team,\n\nI need help with:' : bodyText}\n\n---\nApp: ${AppConstants.appName} ${AppConstants.appVersion}\nPackage: com.hypertechlabs.heavenbrowser';

    final Uri mailUri = Uri(
      scheme: 'mailto',
      path: HelpScreen.supportEmail,
      queryParameters: <String, String>{'subject': subject, 'body': fullBody},
    );

    bool launched = false;
    try {
      launched = await launchUrl(mailUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }

    if (!launched && mounted) {
      await Clipboard.setData(
        const ClipboardData(text: HelpScreen.supportEmail),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No email app found — copied techlabs.hyper@gmail.com to clipboard!',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.navySurface : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.support_agent_rounded,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Contact HyperTech Labs',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SelectableText(
                              HelpScreen.supportEmail,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy email address',
                        onPressed: () {
                          Clipboard.setData(
                            const ClipboardData(text: HelpScreen.supportEmail),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied techlabs.hyper@gmail.com'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 19),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final String item in _topics)
                        ChoiceChip(
                          label: Text(
                            item,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: _topic == item,
                          onSelected: (_) => setState(() => _topic = item),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    minLines: 4,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText:
                          'Describe what happened or what feature you want...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('send_help_email_button'),
                    onPressed: _sendSupportEmail,
                    icon: const Icon(Icons.email_rounded),
                    label: const Text('Email techlabs.hyper@gmail.com'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Material(
              color: isDark ? AppTheme.navySurface : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: ListTile(
                key: const Key('help_privacy_policy_tile'),
                leading: Icon(Icons.privacy_tip_rounded, color: colors.primary),
                title: const Text(
                  'Privacy Policy',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Read our full zero-tracking privacy policy on GitHub',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: _openPrivacyPolicy,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Quick Answers',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _buildFaqTile(
              colors,
              isDark,
              title: 'How do Background Video & Auto-PiP work?',
              answer:
                  'Play any video on YouTube, Twitch, or the web. Press Home to pop into native Android Picture-in-Picture automatically, or lock your screen to keep audio playing in the background.',
            ),
            _buildFaqTile(
              colors,
              isDark,
              title: 'How do One-Handed Gestures & Quick Actions work?',
              answer:
                  'Swipe left or right on the bottom address bar to switch tabs instantly, swipe up on the address bar to open the full Tab Grid, or tap the corner Quick Action button for 1-tap controls.',
            ),
            _buildFaqTile(
              colors,
              isDark,
              title: 'How do I install & use Desktop Chrome Extensions?',
              answer:
                  'Open Menu -> Extensions, tap Chrome Web Store (Desktop View) or paste an extension link. Installed MV2/MV3 extensions run on Google, DuckDuckGo, and every website.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqTile(
    ColorScheme colors,
    bool isDark, {
    required String title,
    required String answer,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.navySurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: ExpansionTile(
        shape: const Border(),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: <Widget>[
          Text(
            answer,
            style: TextStyle(
              fontSize: 12.5,
              color: colors.onSurfaceVariant,
              height: 1.42,
            ),
          ),
        ],
      ),
    );
  }
}
