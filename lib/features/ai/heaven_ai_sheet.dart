import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../browser/engine/browser_engine.dart';
import '../shield/native_shield_bridge.dart';

/// Pure on-device zero-size extractive text intelligence fallback for phones
/// without Android AICore hardware (or when user chooses Instant Lite Mode
/// instead of downloading the Gemini Nano model).
class HeavenLocalSmartAi {
  const HeavenLocalSmartAi._();

  static const Set<String> _stopWords = <String>{
    'the', 'and', 'for', 'that', 'this', 'with', 'from', 'your', 'have',
    'are', 'was', 'were', 'been', 'will', 'would', 'could', 'should', 'into',
    'about', 'than', 'then', 'them', 'they', 'their', 'there', 'what', 'when',
    'where', 'which', 'while', 'who', 'whom', 'whose', 'also', 'more', 'most',
    'some', 'such', 'only', 'over', 'under', 'after', 'before', 'between',
    'through', 'during', 'each', 'other', 'very', 'just', 'like', 'make',
  };

  static List<String> _splitSentences(List<String> paragraphs) {
    final List<String> out = <String>[];
    final RegExp splitter = RegExp(r'(?<=[.!?])\s+');
    for (final String p in paragraphs) {
      for (final String raw in p.split(splitter)) {
        final String clean = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (clean.length >= 32 && clean.length <= 360) {
          out.add(clean);
        }
      }
    }
    if (out.isEmpty) {
      for (final String p in paragraphs) {
        final String clean = p.trim();
        if (clean.isNotEmpty) {
          out.add(clean);
        }
      }
    }
    return out;
  }

  static List<String> _tokenize(String text) {
    return RegExp(r'[a-z0-9]{3,}')
        .allMatches(text.toLowerCase())
        .map((RegExpMatch m) => m.group(0)!)
        .where((String w) => !_stopWords.contains(w))
        .toList(growable: false);
  }

  static String summarizeArticle({
    required String title,
    required List<String> paragraphs,
    int bulletCount = 3,
  }) {
    final List<String> sentences = _splitSentences(paragraphs);
    if (sentences.isEmpty) {
      return '• $title';
    }
    if (sentences.length <= bulletCount) {
      return sentences.map((String s) => '• $s').join('\n\n');
    }

    final Map<String, int> freq = <String, int>{};
    for (final String w in _tokenize('$title ${sentences.join(' ')}')) {
      freq[w] = (freq[w] ?? 0) + 1;
    }
    final Set<String> titleTerms = _tokenize(title).toSet();

    final List<({int index, double score, String text})> scored =
        <({int index, double score, String text})>[];
    for (int i = 0; i < sentences.length; i++) {
      final String s = sentences[i];
      final List<String> words = _tokenize(s);
      if (words.isEmpty) continue;
      double sum = 0;
      for (final String w in words.toSet()) {
        sum += (freq[w] ?? 1).toDouble();
        if (titleTerms.contains(w)) {
          sum += 2.5;
        }
      }
      // Normalize by sqrt(length) and slight lead-paragraph boost
      final double positionBoost = i == 0 ? 1.22 : (i < 4 ? 1.10 : 1.0);
      final double score = (sum / math.sqrt(words.length + 2)) * positionBoost;
      scored.add((index: i, score: score, text: s));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final List<({int index, double score, String text})> picked = scored
        .take(bulletCount)
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return picked.map((e) => '• ${e.text}').join('\n\n');
  }

  static String answerFromContext({
    required String prompt,
    String? pageTitle,
    List<String> paragraphs = const <String>[],
  }) {
    final String cleanPrompt = prompt.trim();
    final String lower = cleanPrompt.toLowerCase();

    if (paragraphs.isNotEmpty) {
      if (lower.contains('summar') ||
          lower.contains('key point') ||
          lower.contains('tl;dr') ||
          lower.contains('takeaway')) {
        return summarizeArticle(
          title: pageTitle ?? 'Page Summary',
          paragraphs: paragraphs,
          bulletCount: 4,
        );
      }

      final Set<String> queryTerms = _tokenize(cleanPrompt).toSet();
      final List<String> sentences = _splitSentences(paragraphs);
      if (queryTerms.isNotEmpty && sentences.isNotEmpty) {
        final List<({int index, double score, String text})> matches =
            <({int index, double score, String text})>[];
        for (int i = 0; i < sentences.length; i++) {
          final List<String> words = _tokenize(sentences[i]);
          int hits = 0;
          for (final String w in words.toSet()) {
            if (queryTerms.contains(w)) {
              hits++;
            }
          }
          if (hits > 0) {
            matches.add((
              index: i,
              score: hits / math.sqrt(words.length + 3),
              text: sentences[i],
            ));
          }
        }
        if (matches.isNotEmpty) {
          matches.sort((a, b) => b.score.compareTo(a.score));
          final List<String> top = (matches.take(3).toList()
                ..sort((a, b) => a.index.compareTo(b.index)))
              .map((e) => '• ${e.text}')
              .toList();
          return 'Based on "${pageTitle ?? 'this page'}":\n\n${top.join('\n\n')}';
        }
      }

      return 'Key highlights from "${pageTitle ?? 'this page'}":\n\n'
          '${summarizeArticle(title: pageTitle ?? '', paragraphs: paragraphs, bulletCount: 3)}';
    }

    return 'Open any article or webpage and tap Summarize Page or ask a question about its content. '
        'On Android devices with AICore (Gemini Nano), download the free on-device model above for full generative chat.';
  }
}

class HeavenAiSheet extends StatefulWidget {
  const HeavenAiSheet({
    super.key,
    required this.engine,
  });

  final BrowserEngine engine;

  @override
  State<HeavenAiSheet> createState() => _HeavenAiSheetState();
}

class _HeavenAiSheetState extends State<HeavenAiSheet> {
  final TextEditingController _promptController = TextEditingController();

  String _modelStatus = 'checking'; // checking | available | downloadable | downloading | unavailable
  String _modelName = 'Gemini Nano';
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  bool _includePageContext = true;
  bool _isGenerating = false;
  bool _preferLiteFallback = false;
  String? _responseText;
  String _responseEngineLabel = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    NativeShieldBridge.instance.onAiDownloadProgress = _onNativeDownloadProgress;
    unawaited(_refreshAiStatus());
  }

  @override
  void dispose() {
    if (NativeShieldBridge.instance.onAiDownloadProgress ==
        _onNativeDownloadProgress) {
      NativeShieldBridge.instance.onAiDownloadProgress = null;
    }
    _promptController.dispose();
    super.dispose();
  }

  void _onNativeDownloadProgress(
    String state,
    int bytesDownloaded,
    int totalBytes,
    String? error,
  ) {
    if (!mounted) return;
    setState(() {
      _downloadedBytes = bytesDownloaded;
      _totalBytes = totalBytes;
      if (state == 'completed') {
        _modelStatus = 'available';
      } else if (state == 'failed') {
        _modelStatus = 'downloadable';
        _errorText = error ?? 'Model download could not complete.';
      } else {
        _modelStatus = 'downloading';
      }
    });
  }

  Future<void> _refreshAiStatus() async {
    final Map<String, Object?> res = await NativeShieldBridge.instance
        .checkOnDeviceAiStatus();
    if (!mounted) return;
    setState(() {
      _modelStatus = (res['status']?.toString() ?? 'unavailable').trim();
      final String name = (res['modelName']?.toString() ?? '').trim();
      if (name.isNotEmpty) {
        _modelName = name;
      }
    });
  }

  Future<bool> _askUserToDownloadModelIfNeeded() async {
    if (_modelStatus != 'downloadable' || _preferLiteFallback) {
      return _modelStatus == 'available';
    }
    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogCtx) {
        return AlertDialog(
          key: const Key('ai_confirm_download_dialog'),
          icon: const Icon(
            Icons.auto_awesome_rounded,
            color: AppTheme.electricBlue,
            size: 30,
          ),
          title: const Text('Download On-Device AI Model?'),
          content: const Text(
            'To keep Heaven small and fast, the 100% free Gemini Nano model is not bundled in the app. '
            'Would you like to download it to your device via Android AICore now, or use Instant Lite Mode with zero download?',
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('ai_confirm_use_lite'),
              onPressed: () => Navigator.pop(dialogCtx, 'lite'),
              child: const Text('Use Instant Lite'),
            ),
            FilledButton(
              key: const Key('ai_confirm_download_yes'),
              onPressed: () => Navigator.pop(dialogCtx, 'download'),
              child: const Text('Download Model'),
            ),
          ],
        );
      },
    );

    if (!mounted) return false;
    if (choice == 'download') {
      await _startModelDownload();
      return _modelStatus == 'available';
    }
    if (choice == 'lite') {
      setState(() => _preferLiteFallback = true);
    }
    return false;
  }

  Future<void> _startModelDownload() async {
    setState(() {
      _modelStatus = 'downloading';
      _errorText = null;
    });
    final Map<String, Object?> res = await NativeShieldBridge.instance
        .downloadOnDeviceAiModel();
    if (!mounted) return;
    final bool ok = res['ok'] == true || res['status'] == 'available';
    setState(() {
      _modelStatus = ok ? 'available' : 'downloadable';
      if (!ok && res['error'] != null) {
        _errorText = res['error'].toString();
      }
    });
  }

  Future<void> _runPageQuickAction(String mode) async {
    if (_isGenerating) return;
    await _askUserToDownloadModelIfNeeded();
    if (!mounted) return;

    setState(() {
      _isGenerating = true;
      _errorText = null;
    });

    final ReadableArticle? article = await widget.engine
        .extractReadableArticle();
    final List<String> paragraphs = article?.paragraphs ?? const <String>[];
    final String title = article?.title.isNotEmpty == true
        ? article!.title
        : widget.engine.pageTitle;
    final String joined = paragraphs.join('\n\n');

    if (_modelStatus == 'available' && !_preferLiteFallback) {
      Map<String, Object?> nativeRes;
      if (mode == 'summarize' && joined.isNotEmpty) {
        nativeRes = await NativeShieldBridge.instance.summarizeWithOnDeviceAi(
          joined,
        );
      } else {
        final String instruction = switch (mode) {
          'keypoints' =>
            'List the 4 most important key points from this webpage concisely:',
          'explain' =>
            'Explain the main topic of this webpage in simple, easy-to-understand English:',
          _ => 'Summarize this webpage clearly in 3 concise bullet points:',
        };
        final String fullPrompt = joined.isNotEmpty
            ? '$instruction\n\nTitle: $title\n\n$joined'
            : '$instruction\n\nWebpage: $title (${widget.engine.currentUrl ?? ''})';
        nativeRes = await NativeShieldBridge.instance.promptOnDeviceAi(
          fullPrompt,
        );
      }

      if (!mounted) return;
      if (nativeRes['ok'] == true &&
          (nativeRes['text']?.toString().trim().isNotEmpty ?? false)) {
        setState(() {
          _isGenerating = false;
          _responseText = nativeRes['text']!.toString().trim();
          _responseEngineLabel = '$_modelName (On-Device)';
        });
        return;
      }
    }

    // Zero-size local fallback so every Android phone gets an instant answer
    final String localOut = switch (mode) {
      'keypoints' => HeavenLocalSmartAi.summarizeArticle(
        title: title,
        paragraphs: paragraphs,
        bulletCount: 4,
      ),
      'explain' =>
        'Simple overview of "$title":\n\n'
            '${HeavenLocalSmartAi.summarizeArticle(title: title, paragraphs: paragraphs, bulletCount: 2)}',
      _ => HeavenLocalSmartAi.summarizeArticle(
        title: title,
        paragraphs: paragraphs,
        bulletCount: 3,
      ),
    };

    if (!mounted) return;
    setState(() {
      _isGenerating = false;
      _responseText = localOut;
      _responseEngineLabel = 'Heaven Instant On-Device Lite';
    });
  }

  Future<void> _submitCustomPrompt() async {
    final String raw = _promptController.text.trim();
    if (raw.isEmpty || _isGenerating) return;
    FocusScope.of(context).unfocus();

    await _askUserToDownloadModelIfNeeded();
    if (!mounted) return;

    setState(() {
      _isGenerating = true;
      _errorText = null;
    });

    ReadableArticle? article;
    if (_includePageContext && widget.engine.isShowingWebPage) {
      article = await widget.engine.extractReadableArticle();
    }
    final List<String> paragraphs = article?.paragraphs ?? const <String>[];
    final String title = article?.title.isNotEmpty == true
        ? article!.title
        : widget.engine.pageTitle;

    if (_modelStatus == 'available' && !_preferLiteFallback) {
      final String fullPrompt =
          (_includePageContext && paragraphs.isNotEmpty)
          ? 'Use the webpage context below to answer the user concisely.\n\n'
                'Page Title: $title\n'
                'Page Content:\n${paragraphs.join('\n')}\n\n'
                'User Question: $raw'
          : raw;
      final Map<String, Object?> nativeRes = await NativeShieldBridge.instance
          .promptOnDeviceAi(fullPrompt);
      if (!mounted) return;
      if (nativeRes['ok'] == true &&
          (nativeRes['text']?.toString().trim().isNotEmpty ?? false)) {
        setState(() {
          _isGenerating = false;
          _responseText = nativeRes['text']!.toString().trim();
          _responseEngineLabel = '$_modelName (On-Device)';
        });
        return;
      }
    }

    final String localReply = HeavenLocalSmartAi.answerFromContext(
      prompt: raw,
      pageTitle: widget.engine.isShowingWebPage ? title : null,
      paragraphs: paragraphs,
    );
    if (!mounted) return;
    setState(() {
      _isGenerating = false;
      _responseText = localReply;
      _responseEngineLabel = 'Heaven Instant On-Device Lite';
    });
  }

  static String _formatMb(int bytes) {
    if (bytes <= 0) return '0 MB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final bool hasWebPage = widget.engine.isShowingWebPage;
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final (String badgeText, Color badgeColor) = switch (_modelStatus) {
      'available' when !_preferLiteFallback => (
        '$_modelName • On-Device Ready',
        AppTheme.shieldEmerald,
      ),
      'downloadable' => (
        'Model Downloadable On-Demand',
        AppTheme.electricBlue,
      ),
      'downloading' => ('Downloading AI Model', AppTheme.electricBlue),
      _ => ('Instant On-Device Lite • 0 MB', colors.primary),
    };

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: SingleChildScrollView(
            key: const Key('heaven_ai_sheet'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[Color(0xFF2563EB), Color(0xFF06B6D4)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Heaven On-Device AI',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            badgeText,
                            key: const Key('ai_status_badge'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: badgeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_modelStatus == 'downloadable')
                  Container(
                    key: const Key('ai_download_prompt_card'),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(
                        alpha: isDark ? 0.14 : 0.08,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Download Free On-Device Gemini Nano Model?',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Heaven keeps its APK tiny by downloading the on-device AI model via Google Play Services only when you want it. 100% free & private.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            FilledButton.icon(
                              key: const Key('ai_download_model_button'),
                              onPressed: _startModelDownload,
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 17,
                              ),
                              label: const Text('Download Model'),
                            ),
                            if (!_preferLiteFallback)
                              OutlinedButton(
                                onPressed: () {
                                  setState(() => _preferLiteFallback = true);
                                },
                                child: const Text('Use Instant Lite'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                if (_modelStatus == 'downloading')
                  Container(
                    key: const Key('ai_downloading_card'),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.navySurface
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _totalBytes > 0
                              ? 'Downloading on-device AI model (${_formatMb(_downloadedBytes)} / ${_formatMb(_totalBytes)})'
                              : 'Downloading on-device AI model via Android AICore',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _totalBytes > 0
                              ? (_downloadedBytes / _totalBytes).clamp(0.0, 1.0)
                              : null,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                  ),

                if (_errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _errorText!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                if (hasWebPage) ...<Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      ActionChip(
                        key: const Key('ai_summarize_page_button'),
                        avatar: const Icon(Icons.summarize_outlined, size: 16),
                        label: const Text('Summarize Page'),
                        onPressed: _isGenerating
                            ? null
                            : () => _runPageQuickAction('summarize'),
                      ),
                      ActionChip(
                        key: const Key('ai_keypoints_button'),
                        avatar: const Icon(
                          Icons.format_list_bulleted_rounded,
                          size: 16,
                        ),
                        label: const Text('Key Points'),
                        onPressed: _isGenerating
                            ? null
                            : () => _runPageQuickAction('keypoints'),
                      ),
                      ActionChip(
                        key: const Key('ai_explain_button'),
                        avatar: const Icon(Icons.lightbulb_outline, size: 16),
                        label: const Text('Explain Simply'),
                        onPressed: _isGenerating
                            ? null
                            : () => _runPageQuickAction('explain'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                if (_isGenerating)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),

                if (_responseText != null && !_isGenerating)
                  Container(
                    key: const Key('ai_response_card'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.navySurface
                          : colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                _responseEngineLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                            InkWell(
                              key: const Key('ai_copy_response_button'),
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: _responseText!),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('AI response copied'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.copy_rounded,
                                      size: 14,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Copy',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _responseText!,
                          style: const TextStyle(fontSize: 13.5, height: 1.45),
                        ),
                      ],
                    ),
                  ),

                if (hasWebPage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilterChip(
                      selected: _includePageContext,
                      onSelected: (bool v) {
                        setState(() => _includePageContext = v);
                      },
                      label: const Text(
                        'Include current webpage context',
                        style: TextStyle(fontSize: 12),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.navySurface
                        : colors.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          key: const Key('ai_prompt_textfield'),
                          controller: _promptController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submitCustomPrompt(),
                          minLines: 1,
                          maxLines: 3,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: hasWebPage
                                ? 'Ask anything about this page'
                                : 'Ask Heaven On-Device AI',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('ai_send_prompt_button'),
                        tooltip: 'Ask AI',
                        onPressed: _isGenerating ? null : _submitCustomPrompt,
                        icon: Icon(
                          Icons.send_rounded,
                          size: 20,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
