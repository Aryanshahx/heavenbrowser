import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../shield/native_shield_bridge.dart';
import '../../engine/browser_engine.dart';

/// Manages sequential on-device Text-To-Speech playback for "Listen to This Page".
class PageTtsController extends ChangeNotifier {
  PageTtsController() {
    NativeShieldBridge.instance.onTtsEvent = _handleNativeTtsEvent;
  }

  List<String> _segments = const <String>[];
  String _pageTitle = '';
  int _currentIndex = 0;
  double _speechRate = 1.0;
  bool _isPlaying = false;
  bool _isPaused = false;
  int _utteranceSeq = 0;
  String _activeUtteranceId = '';

  List<String> get segments => _segments;
  String get pageTitle => _pageTitle;
  int get currentIndex => _currentIndex;
  double get speechRate => _speechRate;
  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  bool get hasSession => _segments.isNotEmpty && (_isPlaying || _isPaused);

  Future<bool> startFromEngine(BrowserEngine engine) async {
    final List<String> extracted = await engine.extractListenParagraphs();
    if (extracted.isEmpty) {
      return false;
    }
    _segments = extracted;
    _pageTitle = engine.pageTitle;
    _currentIndex = 0;
    _isPaused = false;
    await _speakCurrentSegment();
    return true;
  }

  Future<void> _speakCurrentSegment() async {
    if (_segments.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _segments.length) {
      await stop();
      return;
    }
    _utteranceSeq += 1;
    final String uttId = 'hb_tts_$_utteranceSeq';
    _activeUtteranceId = uttId;
    _isPlaying = true;
    _isPaused = false;
    notifyListeners();

    await NativeShieldBridge.instance.ttsSpeak(
      text: _segments[_currentIndex],
      rate: _speechRate,
      utteranceId: uttId,
    );
  }

  void _handleNativeTtsEvent(String event, String utteranceId) {
    if (utteranceId.isNotEmpty && utteranceId != _activeUtteranceId) {
      return;
    }
    if (event == 'done') {
      if (_isPlaying && _currentIndex + 1 < _segments.length) {
        _currentIndex += 1;
        unawaited(_speakCurrentSegment());
      } else {
        _isPlaying = false;
        _isPaused = false;
        notifyListeners();
      }
    } else if (event == 'error') {
      _isPlaying = false;
      _isPaused = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_segments.isEmpty) return;
    if (_isPlaying) {
      _activeUtteranceId = '';
      _isPlaying = false;
      _isPaused = true;
      await NativeShieldBridge.instance.ttsStop();
      notifyListeners();
    } else {
      await _speakCurrentSegment();
    }
  }

  Future<void> jumpToIndex(int index) async {
    if (index < 0 || index >= _segments.length) return;
    _currentIndex = index;
    await _speakCurrentSegment();
  }

  Future<void> nextSegment() async {
    if (_currentIndex + 1 < _segments.length) {
      _currentIndex += 1;
      await _speakCurrentSegment();
    }
  }

  Future<void> previousSegment() async {
    if (_currentIndex > 0) {
      _currentIndex -= 1;
      await _speakCurrentSegment();
    }
  }

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate.clamp(0.75, 2.0);
    notifyListeners();
    if (_isPlaying) {
      await _speakCurrentSegment();
    }
  }

  Future<void> stop() async {
    _activeUtteranceId = '';
    _isPlaying = false;
    _isPaused = false;
    _segments = const <String>[];
    _currentIndex = 0;
    await NativeShieldBridge.instance.ttsStop();
    notifyListeners();
  }

  @override
  void dispose() {
    if (NativeShieldBridge.instance.onTtsEvent == _handleNativeTtsEvent) {
      NativeShieldBridge.instance.onTtsEvent = null;
    }
    unawaited(NativeShieldBridge.instance.ttsStop());
    super.dispose();
  }
}

class ListenToPageSheet extends StatefulWidget {
  const ListenToPageSheet({
    super.key,
    required this.engine,
    required this.tts,
  });

  final BrowserEngine engine;
  final PageTtsController tts;

  @override
  State<ListenToPageSheet> createState() => _ListenToPageSheetState();
}

class _ListenToPageSheetState extends State<ListenToPageSheet> {
  bool _loading = false;
  String? _emptyMessage;

  static const List<double> _rates = <double>[0.8, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    if (!widget.tts.hasSession ||
        widget.tts.pageTitle != widget.engine.pageTitle) {
      unawaited(_initializePlayback());
    }
  }

  Future<void> _initializePlayback() async {
    if (!widget.engine.isShowingWebPage) {
      setState(() {
        _emptyMessage =
            'Open any article or webpage first to listen to it aloud.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _emptyMessage = null;
    });
    final bool ok = await widget.tts.startFromEngine(widget.engine);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!ok) {
        _emptyMessage = 'No readable text found on this page.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: widget.tts,
      builder: (BuildContext context, _) {
        final List<String> segments = widget.tts.segments;
        final int idx = widget.tts.currentIndex;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: Padding(
              key: const Key('listen_to_page_sheet'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.headphones_rounded,
                          color: colors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Listen to This Page',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              widget.engine.isShowingWebPage
                                  ? widget.engine.pageTitle
                                  : 'Read webpages aloud offline',
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
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_emptyMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.navySurface
                            : colors.surfaceContainerHighest.withValues(
                                alpha: 0.5,
                              ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _emptyMessage!,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  else if (segments.isNotEmpty) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.navySurface
                            : colors.surfaceContainerHighest.withValues(
                                alpha: 0.55,
                              ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                'Paragraph ${idx + 1} of ${segments.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: colors.primary,
                                ),
                              ),
                              Text(
                                widget.tts.isPlaying ? 'Playing' : 'Paused',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: widget.tts.isPlaying
                                      ? AppTheme.shieldEmerald
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: segments.isEmpty
                                ? 0
                                : ((idx + 1) / segments.length).clamp(0.0, 1.0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              IconButton(
                                key: const Key('tts_prev_button'),
                                tooltip: 'Previous Paragraph',
                                onPressed: idx > 0
                                    ? widget.tts.previousSegment
                                    : null,
                                icon: const Icon(
                                  Icons.skip_previous_rounded,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                key: const Key('tts_play_pause_button'),
                                onPressed: widget.tts.togglePlayPause,
                                icon: Icon(
                                  widget.tts.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                label: Text(
                                  widget.tts.isPlaying ? 'Pause' : 'Play',
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                key: const Key('tts_next_button'),
                                tooltip: 'Next Paragraph',
                                onPressed: idx + 1 < segments.length
                                    ? widget.tts.nextSegment
                                    : null,
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                key: const Key('tts_stop_button'),
                                tooltip: 'Stop Reading',
                                onPressed: () async {
                                  await widget.tts.stop();
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                                icon: const Icon(
                                  Icons.stop_circle_outlined,
                                  color: AppTheme.fireCrimson,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: <Widget>[
                              for (final double r in _rates)
                                ChoiceChip(
                                  key: Key('tts_rate_${r}x'),
                                  label: Text(
                                    r == r.roundToDouble()
                                        ? '${r.toInt()}x'
                                        : '${r}x',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  selected:
                                      (widget.tts.speechRate - r).abs() < 0.02,
                                  onSelected: (_) =>
                                      widget.tts.setSpeechRate(r),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: segments.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (BuildContext context, int i) {
                          final bool current = i == idx;
                          return Material(
                            color: current
                                ? colors.primary.withValues(
                                    alpha: isDark ? 0.18 : 0.10,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => widget.tts.jumpToIndex(i),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Text(
                                  segments[i],
                                  maxLines: current ? 6 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    fontWeight: current
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: current
                                        ? colors.onSurface
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
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
