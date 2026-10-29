import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../shield/native_shield_bridge.dart';
import '../../engine/browser_engine.dart';

enum HeavenLensMode {
  translate('translate', 'Translate', Icons.translate_rounded),
  search('search', 'Search', Icons.image_search_rounded),
  text('text', 'Text', Icons.text_fields_rounded),
  shopping('shopping', 'Shopping', Icons.shopping_bag_outlined);

  const HeavenLensMode(this.code, this.label, this.icon);
  final String code;
  final String label;
  final IconData icon;
}

/// Instant, full-screen modern Google-Lens camera & visual search studio:
/// - Opens live 60fps Android Camera2 viewfinder immediately on tap
/// - Interactive 4-corner draggable Google Lens crop frame + tap-to-focus + zoom + torch + camera flip
/// - Prominent "Gallery" button to choose any image from device storage
/// - Multimodal "Add to your search" text input + Translate / Search / Text / Shopping modes
/// - Uploads natively to `https://lens.google.com/v3/upload` and loads live Google Lens results
class HeavenLensCameraScreen extends StatefulWidget {
  const HeavenLensCameraScreen({super.key, required this.engine});

  final BrowserEngine engine;

  static Future<void> open(BuildContext context, BrowserEngine engine) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 140),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (BuildContext ctx, Animation<double> anim, _) {
          return FadeTransition(
            opacity: anim,
            child: HeavenLensCameraScreen(engine: engine),
          );
        },
      ),
    );
  }

  @override
  State<HeavenLensCameraScreen> createState() => _HeavenLensCameraScreenState();
}

class _HeavenLensCameraScreenState extends State<HeavenLensCameraScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocusNode = FocusNode();

  late final AnimationController _scanAnimController;

  int? _textureId;
  double _previewWidth = 1080;
  double _previewHeight = 1440;
  bool _startingCamera = true;
  bool _isFrontCamera = false;
  bool _hasFlash = false;
  bool _torchEnabled = false;
  double _zoom = 1.0;
  double _baseScaleZoom = 1.0;
  double _maxZoom = 4.0;
  String? _cameraError;

  // Interactive normalized Google Lens crop box [0..1]
  Rect _cropRect = const Rect.fromLTRB(0.10, 0.16, 0.90, 0.80);
  bool _hasCustomCrop = false;

  // Tap-to-focus indicator
  Offset? _focusTapOffset;
  Timer? _focusIndicatorTimer;

  // Picked/captured freeze-frame image state
  Uint8List? _frozenImageBytes;
  bool _editingGalleryCrop = false;
  bool _searchingLens = false;

  HeavenLensMode _selectedMode = HeavenLensMode.search;

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    unawaited(_startLiveCamera(front: false));
  }

  @override
  void dispose() {
    _focusIndicatorTimer?.cancel();
    _scanAnimController.dispose();
    _queryController.dispose();
    _queryFocusNode.dispose();
    unawaited(NativeShieldBridge.instance.lensStopCamera(release: true));
    super.dispose();
  }

  Future<void> _startLiveCamera({required bool front}) async {
    if (!mounted) return;
    setState(() {
      _startingCamera = true;
      _cameraError = null;
    });
    final Map<String, Object?> res = await NativeShieldBridge.instance
        .lensStartCamera(facing: front ? 'front' : 'back');
    if (!mounted) return;
    if (res['ok'] == true && res['textureId'] is num) {
      setState(() {
        _textureId = (res['textureId'] as num).toInt();
        _previewWidth =
            ((res['previewWidth'] as num?)?.toDouble() ?? 1080).clamp(160, 4096);
        _previewHeight =
            ((res['previewHeight'] as num?)?.toDouble() ?? 1440).clamp(
              160,
              4096,
            );
        _isFrontCamera = res['isFront'] == true;
        _hasFlash = res['hasFlash'] == true;
        _torchEnabled = false;
        _zoom = 1.0;
        _maxZoom = ((res['maxZoom'] as num?)?.toDouble() ?? 4.0).clamp(
          1.0,
          8.0,
        );
        _startingCamera = false;
        _cameraError = null;
      });
    } else {
      setState(() {
        _startingCamera = false;
        _cameraError =
            (res['error']?.toString() ?? '').trim().isNotEmpty
            ? res['error']!.toString()
            : 'Live camera preview unavailable';
      });
    }
  }

  Future<void> _toggleTorch() async {
    if (!_hasFlash || _searchingLens) return;
    final bool next = !_torchEnabled;
    final bool applied = await NativeShieldBridge.instance.lensSetTorch(
      enabled: next,
    );
    if (mounted) {
      setState(() => _torchEnabled = applied);
    }
  }

  Future<void> _flipCamera() async {
    if (_startingCamera || _searchingLens) return;
    HapticFeedback.selectionClick();
    await _startLiveCamera(front: !_isFrontCamera);
  }

  void _resetCrop() {
    setState(() {
      _cropRect = const Rect.fromLTRB(0.10, 0.16, 0.90, 0.80);
      _hasCustomCrop = false;
    });
  }

  Future<void> _captureAndSearchLiveFrame() async {
    if (_searchingLens) return;
    _queryFocusNode.unfocus();
    HapticFeedback.mediumImpact();

    // If user is currently editing a picked Gallery photo, search that photo!
    if (_frozenImageBytes != null && _editingGalleryCrop) {
      await _uploadGalleryBytesToLens(base64Encode(_frozenImageBytes!));
      return;
    }

    setState(() => _searchingLens = true);
    final Rect sendCrop = _hasCustomCrop
        ? _cropRect
        : const Rect.fromLTRB(0.0, 0.0, 1.0, 1.0);

    final Map<String, Object?> res = await NativeShieldBridge.instance
        .lensCaptureAndSearch(
          cropLeft: sendCrop.left,
          cropTop: sendCrop.top,
          cropRight: sendCrop.right,
          cropBottom: sendCrop.bottom,
          mode: _selectedMode.code,
          query: _queryController.text.trim(),
          language: widget.engine.settings.language.code,
        );
    if (!mounted) return;

    final String previewB64 = (res['previewBase64']?.toString() ?? '').trim();
    if (previewB64.isNotEmpty) {
      try {
        _frozenImageBytes = base64Decode(previewB64);
      } catch (_) {}
    }

    final String resultUrl = (res['resultUrl']?.toString() ?? '').trim();
    if (res['ok'] == true && resultUrl.isNotEmpty) {
      await NativeShieldBridge.instance.lensStopCamera(release: true);
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.engine.openGoogleLensResultUrl(resultUrl);
      return;
    }

    setState(() => _searchingLens = false);
    final String err = (res['error']?.toString() ?? '').trim();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          err.isNotEmpty
              ? err
              : 'Could not reach Google Lens. Check your connection and try again.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    if (_searchingLens) return;
    _queryFocusNode.unfocus();
    HapticFeedback.selectionClick();

    final Map<String, Object?> picked = await NativeShieldBridge.instance
        .lensPickGalleryImage();
    if (!mounted) return;
    if (picked['cancelled'] == true) {
      return;
    }
    final String b64 = (picked['base64Jpeg']?.toString() ?? '').trim();
    if (picked['ok'] != true || b64.isEmpty) {
      final String err = (picked['error']?.toString() ?? '').trim();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            err.isNotEmpty ? err : 'Unable to load selected gallery image',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Uint8List? decoded;
    try {
      decoded = base64Decode(b64);
    } catch (_) {}

    if (decoded != null) {
      // Google-Lens style: the picked photo opens frozen with the draggable
      // 4-corner crop frame. Adjust the frame (optional) and press the shutter
      // to search exactly the selected region!
      setState(() {
        _frozenImageBytes = decoded;
        _editingGalleryCrop = true;
        _cropRect = const Rect.fromLTRB(0.08, 0.12, 0.92, 0.88);
        _hasCustomCrop = true;
      });
      return;
    }
    await _uploadGalleryBytesToLens(b64);
  }

  Future<void> _uploadGalleryBytesToLens(String base64Jpeg) async {
    setState(() => _searchingLens = true);
    final Rect sendCrop = (_editingGalleryCrop && _hasCustomCrop)
        ? _cropRect
        : const Rect.fromLTRB(0.0, 0.0, 1.0, 1.0);

    final Map<String, Object?> res = await NativeShieldBridge.instance
        .lensSearchImageBytes(
          base64Jpeg: base64Jpeg,
          cropLeft: sendCrop.left,
          cropTop: sendCrop.top,
          cropRight: sendCrop.right,
          cropBottom: sendCrop.bottom,
          mode: _selectedMode.code,
          query: _queryController.text.trim(),
          language: widget.engine.settings.language.code,
        );
    if (!mounted) return;

    final String resultUrl = (res['resultUrl']?.toString() ?? '').trim();
    if (res['ok'] == true && resultUrl.isNotEmpty) {
      await NativeShieldBridge.instance.lensStopCamera(release: true);
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.engine.openGoogleLensResultUrl(resultUrl);
      return;
    }

    setState(() {
      _searchingLens = false;
      _editingGalleryCrop = _frozenImageBytes != null;
    });
    final String err = (res['error']?.toString() ?? '').trim();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          err.isNotEmpty
              ? err
              : 'Google Lens upload failed. Check internet connection.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleViewfinderTap(TapUpDetails details, Size boxSize) {
    if (_frozenImageBytes != null || _textureId == null) return;
    _queryFocusNode.unfocus();
    final Offset local = details.localPosition;
    final double nx = (local.dx / math.max(1, boxSize.width)).clamp(0.05, 0.95);
    final double ny = (local.dy / math.max(1, boxSize.height)).clamp(
      0.05,
      0.95,
    );
    unawaited(NativeShieldBridge.instance.lensFocusPoint(nx, ny));
    _focusIndicatorTimer?.cancel();
    setState(() => _focusTapOffset = local);
    _focusIndicatorTimer = Timer(const Duration(milliseconds: 950), () {
      if (mounted) {
        setState(() => _focusTapOffset = null);
      }
    });
  }

  void _updateCornerDrag(
    _LensCorner corner,
    Offset delta,
    Size viewportSize,
  ) {
    final double dx = delta.dx / math.max(1, viewportSize.width);
    final double dy = delta.dy / math.max(1, viewportSize.height);
    const double minSpan = 0.16;

    double l = _cropRect.left;
    double t = _cropRect.top;
    double r = _cropRect.right;
    double b = _cropRect.bottom;

    switch (corner) {
      case _LensCorner.topLeft:
        l = (l + dx).clamp(0.04, r - minSpan);
        t = (t + dy).clamp(0.08, b - minSpan);
      case _LensCorner.topRight:
        r = (r + dx).clamp(l + minSpan, 0.96);
        t = (t + dy).clamp(0.08, b - minSpan);
      case _LensCorner.bottomLeft:
        l = (l + dx).clamp(0.04, r - minSpan);
        b = (b + dy).clamp(t + minSpan, 0.90);
      case _LensCorner.bottomRight:
        r = (r + dx).clamp(l + minSpan, 0.96);
        b = (b + dy).clamp(t + minSpan, 0.90);
    }

    setState(() {
      _cropRect = Rect.fromLTRB(l, t, r, b);
      _hasCustomCrop = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keyboard open => the bottom dock is hidden entirely (ask bar at top).
    final bool keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 12;
    return Scaffold(
      key: const Key('heaven_lens_camera_screen'),
      backgroundColor: const Color(0xFF060B14),
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 1. Live 60fps Camera2 Viewfinder OR Frozen Gallery/Captured Photo
          _buildCameraOrImageLayer(),

          // 2. Subtle top & bottom gradient scrims for crisp readability
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.62),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.82),
                  ],
                  stops: const <double>[0.0, 0.18, 0.62, 1.0],
                ),
              ),
            ),
          ),

          // 3. Interactive Google-Lens 4-Corner Frame + Laser Shimmer + Tap-to-Focus
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Size boxSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              // The 4 corner drag handles live in their OWN layer strictly
              // ABOVE the tap/pinch layer so dragging a corner ALWAYS wins
              // the gesture arena (pinch-zoom can never swallow a crop drag)!
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: (TapUpDetails d) =>
                        _handleViewfinderTap(d, boxSize),
                    onScaleStart: (_) => _baseScaleZoom = _zoom,
                    onScaleUpdate: (ScaleUpdateDetails d) {
                      if (_frozenImageBytes != null || d.pointerCount < 2) {
                        return;
                      }
                      final double next = (_baseScaleZoom * d.scale).clamp(
                        1.0,
                        _maxZoom,
                      );
                      if ((next - _zoom).abs() >= 0.04) {
                        setState(() => _zoom = next);
                        unawaited(
                          NativeShieldBridge.instance.lensSetZoom(next),
                        );
                      }
                    },
                    child: AnimatedBuilder(
                      animation: _scanAnimController,
                      builder: (BuildContext context, _) {
                        return CustomPaint(
                          painter: _GoogleLensFramePainter(
                            cropRect: _cropRect,
                            scanProgress: _scanAnimController.value,
                            isSearching: _searchingLens,
                            dimOutside:
                                _hasCustomCrop || _editingGalleryCrop,
                          ),
                        );
                      },
                    ),
                  ),
                  ..._buildCornerDragHandles(boxSize),
                  if (_focusTapOffset != null)
                    Positioned(
                      left: _focusTapOffset!.dx - 26,
                      top: _focusTapOffset!.dy - 26,
                      child: IgnorePointer(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.heavenAccent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          // 4. Top Floating Glass Controls + Bottom Google-Lens Studio Controls
          SafeArea(
            child: Column(
              children: <Widget>[
                _buildTopBar(context),
                if (_hasCustomCrop || _editingGalleryCrop)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 8,
                      children: <Widget>[
                        if (_hasCustomCrop)
                          ActionChip(
                            key: const Key('lens_reset_crop_button'),
                            avatar: const Icon(
                              Icons.crop_free_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Full Frame',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.55,
                            ),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.24),
                            ),
                            onPressed: _resetCrop,
                          ),
                        if (_editingGalleryCrop)
                          ActionChip(
                            avatar: const Icon(
                              Icons.videocam_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Back to Live Camera',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.55,
                            ),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.24),
                            ),
                            onPressed: () {
                              setState(() {
                                _frozenImageBytes = null;
                                _editingGalleryCrop = false;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (_searchingLens)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xEB0F172A),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppTheme.electricBlue.withValues(alpha: 0.55),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Searching with Google Lens...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // While the soft keyboard is open the whole bottom dock
                // (mode selector + shutter + gallery) HIDES completely —
                // the "Add to your search" bar at the top can NEVER overlap
                // anything, and the dock returns as soon as typing ends!
                if (!keyboardOpen) ...<Widget>[
                  _buildModeSelectorRow(),
                  const SizedBox(height: 14),
                  _buildBottomShutterAndGalleryDock(),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraOrImageLayer() {
    if (_frozenImageBytes != null) {
      return Image.memory(
        _frozenImageBytes!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }
    if (_textureId != null) {
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _previewWidth,
              height: _previewHeight,
              child: Texture(textureId: _textureId!),
            ),
          ),
        ),
      );
    }
    if (_startingCamera) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.electricBlue),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.electricBlue.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: ModernHeavenCameraIcon(size: 32, color: Colors.white),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _cameraError ?? 'Point camera or choose an image from Gallery',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can grant camera access or tap Gallery below to search any photo with Google Lens.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('lens_retry_camera_button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              onPressed: () => _startLiveCamera(front: _isFrontCamera),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Enable Live Camera'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCornerDragHandles(Size viewport) {
    const double hitSize = 44;
    final double leftPx = _cropRect.left * viewport.width;
    final double topPx = _cropRect.top * viewport.height;
    final double rightPx = _cropRect.right * viewport.width;
    final double bottomPx = _cropRect.bottom * viewport.height;

    Widget buildHandle(_LensCorner corner, double cx, double cy) {
      return Positioned(
        left: cx - hitSize / 2,
        top: cy - hitSize / 2,
        width: hitSize,
        height: hitSize,
        child: GestureDetector(
          key: Key('lens_crop_corner_${corner.name}'),
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (DragUpdateDetails d) =>
              _updateCornerDrag(corner, d.delta, viewport),
          child: const SizedBox.expand(),
        ),
      );
    }

    return <Widget>[
      buildHandle(_LensCorner.topLeft, leftPx, topPx),
      buildHandle(_LensCorner.topRight, rightPx, topPx),
      buildHandle(_LensCorner.bottomLeft, leftPx, bottomPx),
      buildHandle(_LensCorner.bottomRight, rightPx, bottomPx),
    ];
  }

  /// Google-Lens style top bar: [Close X] [Add to your search field] [Search
  /// icon] [Flashlight] [Flip camera] — one clean row, no "Heaven Lens"
  /// title, and the ask area can NEVER be overlapped by anything!
  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Row(
        children: <Widget>[
          _GlassCircleIconButton(
            buttonKey: const Key('lens_close_button'),
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(child: _buildMultimodalAskBar()),
          if (_hasFlash && _frozenImageBytes == null) ...<Widget>[
            const SizedBox(width: 8),
            _GlassCircleIconButton(
              buttonKey: const Key('lens_torch_button'),
              icon: _torchEnabled
                  ? Icons.flash_on_rounded
                  : Icons.flash_off_rounded,
              active: _torchEnabled,
              tooltip: 'Flash',
              onTap: _toggleTorch,
            ),
          ],
          const SizedBox(width: 8),
          _GlassCircleIconButton(
            buttonKey: const Key('lens_flip_camera_button'),
            icon: Icons.cameraswitch_rounded,
            tooltip: 'Flip Camera',
            onTap: _flipCamera,
          ),
        ],
      ),
    );
  }

  /// Runs the visual search with the typed query (live frame, or the frozen
  /// gallery/captured photo when one is on screen).
  void _submitQuerySearch() {
    if (_queryController.text.trim().isEmpty) {
      _queryFocusNode.requestFocus();
      return;
    }
    _captureAndSearchLiveFrame();
  }

  Widget _buildMultimodalAskBar() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xCC0F172A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: <Widget>[
          GestureDetector(
            key: const Key('lens_multimodal_search_button'),
            behavior: HitTestBehavior.opaque,
            onTap: _submitQuerySearch,
            child: const Icon(
              Icons.manage_search_rounded,
              size: 20,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('lens_multimodal_query_field'),
              controller: _queryController,
              focusNode: _queryFocusNode,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
              textInputAction: TextInputAction.search,
              onSubmitted: (String _) => _submitQuerySearch(),
              decoration: const InputDecoration(
                hintText: 'Add to your search...',
                hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _queryController,
            builder: (BuildContext context, TextEditingValue v, _) {
              if (v.text.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                onTap: _queryController.clear,
                child: const Icon(
                  Icons.cancel_rounded,
                  size: 17,
                  color: Colors.white60,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelectorRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: HeavenLensMode.values.map((HeavenLensMode mode) {
            final bool active = _selectedMode == mode;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                key: Key('lens_mode_${mode.code}'),
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedMode = mode);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? AppTheme.electricBlue
                        : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: active
                          ? AppTheme.heavenAccent
                          : Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(mode.icon, size: 15, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        mode.label,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBottomShutterAndGalleryDock() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            // Left: Prominent "Gallery" button (Choose image from gallery)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(26),
                  child: InkWell(
                    key: const Key('lens_pick_gallery_button'),
                    borderRadius: BorderRadius.circular(26),
                    onTap: _searchingLens ? null : _pickFromGallery,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.photo_library_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              'Gallery',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Center: Google-Lens Shutter Search Button
            GestureDetector(
              key: const Key('lens_shutter_capture_button'),
              onTap: _searchingLens ? null : _captureAndSearchLiveFrame,
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3.2),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppTheme.electricBlue.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.brandGradient,
                  ),
                  child: Icon(
                    _editingGalleryCrop
                        ? Icons.check_rounded
                        : Icons.search_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),

            // Right: kept clear — the crop frame is adjusted by simply
            // dragging the 4 viewfinder corners (no extra button needed)!
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

enum _LensCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Modern Heaven Lens camera icon: sleek viewfinder brackets + optical iris +
/// sparkle accent — in the spirit of Google Lens, but Heaven's own design.
class ModernHeavenCameraIcon extends StatelessWidget {
  const ModernHeavenCameraIcon({super.key, required this.size, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ModernHeavenCameraIconPainter(
          color ?? const Color(0xFF2563EB),
        ),
      ),
    );
  }
}

class _ModernHeavenCameraIconPainter extends CustomPainter {
  const _ModernHeavenCameraIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Exact 1:1 mirror of the Home Screen Widget's ic_widget_camera.xml
    // vector (24x24 viewport) so the in-app camera icon always matches the
    // widget camera icon perfectly!
    final double s = size.width / 24.0;
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.05 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Top-left bracket with rounded corner
    final Path tl = Path()
      ..moveTo(3.5 * s, 8.6 * s)
      ..lineTo(3.5 * s, 6.7 * s)
      ..arcToPoint(
        Offset(6.7 * s, 3.5 * s),
        radius: Radius.circular(3.2 * s),
      )
      ..lineTo(8.6 * s, 3.5 * s);
    // Bottom-left bracket with rounded corner
    final Path bl = Path()
      ..moveTo(3.5 * s, 15.4 * s)
      ..lineTo(3.5 * s, 17.3 * s)
      ..arcToPoint(
        Offset(6.7 * s, 20.5 * s),
        radius: Radius.circular(3.2 * s),
      )
      ..lineTo(8.6 * s, 20.5 * s);
    // Bottom-right bracket with rounded corner
    final Path br = Path()
      ..moveTo(15.4 * s, 20.5 * s)
      ..lineTo(17.3 * s, 20.5 * s)
      ..arcToPoint(
        Offset(20.5 * s, 17.3 * s),
        radius: Radius.circular(3.2 * s),
      )
      ..lineTo(20.5 * s, 15.4 * s);
    canvas.drawPath(tl, stroke);
    canvas.drawPath(bl, stroke);
    canvas.drawPath(br, stroke);

    // Central optical iris ring
    canvas.drawCircle(
      Offset(12 * s, 12 * s),
      3.5 * s,
      stroke..strokeWidth = 2.0 * s,
    );

    // Top-right 4-point sparkle accent
    final Path sparkle = Path()
      ..moveTo(18.2 * s, 3.4 * s)
      ..lineTo(18.85 * s, 4.95 * s)
      ..lineTo(20.4 * s, 5.6 * s)
      ..lineTo(18.85 * s, 6.25 * s)
      ..lineTo(18.2 * s, 7.8 * s)
      ..lineTo(17.55 * s, 6.25 * s)
      ..lineTo(16.0 * s, 5.6 * s)
      ..lineTo(17.55 * s, 4.95 * s)
      ..close();
    canvas.drawPath(sparkle, fill);
  }

  @override
  bool shouldRepaint(covariant _ModernHeavenCameraIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _GlassCircleIconButton extends StatelessWidget {
  const _GlassCircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.buttonKey,
    this.active = false,
  });

  final Key? buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? AppTheme.electricBlue.withValues(alpha: 0.72)
          : Colors.black.withValues(alpha: 0.46),
      shape: const CircleBorder(),
      child: InkWell(
        key: buttonKey,
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 21),
          ),
        ),
      ),
    );
  }
}

class _GoogleLensFramePainter extends CustomPainter {
  const _GoogleLensFramePainter({
    required this.cropRect,
    required this.scanProgress,
    required this.isSearching,
    required this.dimOutside,
  });

  final Rect cropRect;
  final double scanProgress;
  final bool isSearching;
  final bool dimOutside;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect frame = Rect.fromLTRB(
      cropRect.left * size.width,
      cropRect.top * size.height,
      cropRect.right * size.width,
      cropRect.bottom * size.height,
    );
    const double radius = 26.0;
    final RRect frameRRect = RRect.fromRectAndRadius(
      frame,
      const Radius.circular(radius),
    );

    if (dimOutside || isSearching) {
      final Path mask = Path()
        ..addRect(Offset.zero & size)
        ..addRRect(frameRRect)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(
        mask,
        Paint()..color = Colors.black.withValues(alpha: 0.48),
      );
    }

    // Subtle scan line shimmer inside the Google Lens frame
    final double scanY =
        frame.top + 22 + (frame.height - 44).clamp(0.0, 2000.0) * scanProgress;
    final Rect glowBand = Rect.fromLTWH(
      frame.left + 12,
      scanY - 12,
      math.max(0, frame.width - 24),
      24,
    );
    final Paint scanPaint = Paint()
      ..shader = LinearGradient(
        colors: <Color>[
          Colors.transparent,
          (isSearching ? AppTheme.heavenAccent : Colors.white).withValues(
            alpha: isSearching ? 0.55 : 0.22,
          ),
          Colors.transparent,
        ],
      ).createShader(glowBand);
    canvas.drawRect(glowBand, scanPaint);

    // 4 Rounded Google-Lens Corner Brackets
    final Paint bracketPaint = Paint()
      ..color = isSearching ? AppTheme.heavenAccent : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final double arm = math.min(
      34.0,
      math.min(frame.width, frame.height) * 0.22,
    );
    final double r = math.min(radius, arm * 0.72);

    // Top-Left
    final Path tl = Path()
      ..moveTo(frame.left, frame.top + arm)
      ..lineTo(frame.left, frame.top + r)
      ..arcToPoint(
        Offset(frame.left + r, frame.top),
        radius: Radius.circular(r),
      )
      ..lineTo(frame.left + arm, frame.top);

    // Top-Right
    final Path tr = Path()
      ..moveTo(frame.right - arm, frame.top)
      ..lineTo(frame.right - r, frame.top)
      ..arcToPoint(
        Offset(frame.right, frame.top + r),
        radius: Radius.circular(r),
      )
      ..lineTo(frame.right, frame.top + arm);

    // Bottom-Right
    final Path br = Path()
      ..moveTo(frame.right, frame.bottom - arm)
      ..lineTo(frame.right, frame.bottom - r)
      ..arcToPoint(
        Offset(frame.right - r, frame.bottom),
        radius: Radius.circular(r),
      )
      ..lineTo(frame.right - arm, frame.bottom);

    // Bottom-Left
    final Path bl = Path()
      ..moveTo(frame.left + arm, frame.bottom)
      ..lineTo(frame.left + r, frame.bottom)
      ..arcToPoint(
        Offset(frame.left, frame.bottom - r),
        radius: Radius.circular(r),
      )
      ..lineTo(frame.left, frame.bottom - arm);

    canvas.drawPath(tl, bracketPaint);
    canvas.drawPath(tr, bracketPaint);
    canvas.drawPath(br, bracketPaint);
    canvas.drawPath(bl, bracketPaint);
  }

  @override
  bool shouldRepaint(covariant _GoogleLensFramePainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.scanProgress != scanProgress ||
        oldDelegate.isSearching != isSearching ||
        oldDelegate.dimOutside != dimOutside;
  }
}
