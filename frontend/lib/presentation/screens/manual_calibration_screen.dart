import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/board_provider.dart';
import '../../domain/models/calibration_frame.dart';
import '../../data/repositories/pi_local_api.dart';

const kBackground = Color(0xFF151311);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kSecondary = Color(0xFFA2E7FF);
const kOnPrimary = Color(0xFF173800);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kError = Color(0xFFFFB4AB);

Rect _imageDisplayRect(Size displaySize, int imgW, int imgH) {
  final scaleX = displaySize.width / imgW;
  final scaleY = displaySize.height / imgH;
  final scale = math.min(scaleX, scaleY); // contain: full image visible

  final w = imgW * scale;
  final h = imgH * scale;
  final left = (displaySize.width - w) / 2;
  final top = (displaySize.height - h) / 2;
  return Rect.fromLTWH(left, top, w, h);
}

/// Converts a tap position (in display/widget space) to the actual image pixel
/// coordinate, accounting for the cover scaling.
Offset _displayToImage(
    Offset displayPos, Size displaySize, int imgW, int imgH) {
  final rect = _imageDisplayRect(displaySize, imgW, imgH);
  final imageX = ((displayPos.dx - rect.left) / rect.width * imgW)
      .clamp(0.0, imgW.toDouble());
  final imageY = ((displayPos.dy - rect.top) / rect.height * imgH)
      .clamp(0.0, imgH.toDouble());
  return Offset(imageX, imageY);
}

/// Converts an image-space coordinate back to display/widget space for
/// rendering the draggable corner dots.
Offset _imageToDisplay(Offset imagePos, Size displaySize, int imgW, int imgH) {
  final rect = _imageDisplayRect(displaySize, imgW, imgH);
  return Offset(
    rect.left + imagePos.dx * rect.width / imgW,
    rect.top + imagePos.dy * rect.height / imgH,
  );
}

class ManualCalibrationScreen extends ConsumerStatefulWidget {
  final PiLocalApi? localApi;

  const ManualCalibrationScreen({super.key, this.localApi});

  @override
  ConsumerState<ManualCalibrationScreen> createState() =>
      _ManualCalibrationScreenState();
}

class _ManualCalibrationScreenState
    extends ConsumerState<ManualCalibrationScreen> {
  CalibrationFrame? _frame;
  bool _loading = true;
  String? _error;

  /// Points stored in **image pixel** coordinates (not display coords).
  final List<Offset> _imagePoints = [];

  static const _labels = ['TL', 'TR', 'BR', 'BL'];

  @override
  void dispose() {
    widget.localApi?.client.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadFrame();
  }

  Future<void> _loadFrame() async {
    setState(() {
      _loading = true;
      _error = null;
      _imagePoints.clear();
    });
    try {
      final frame = widget.localApi == null
          ? await ref.read(boardRepositoryProvider).captureFrame()
          : CalibrationFrame(
              imageBase64: base64Encode(await widget.localApi!.cameraFrame()),
              width: 800,
              height: 600,
            );
      if (mounted) {
        setState(() {
          _frame = frame;
          _loading = false;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = 'Failed to capture frame: $err';
          _loading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final frame = _frame;
    if (frame == null || _imagePoints.length != 4) return;

    final corners = _imagePoints
        .map((p) => [
              p.dx.clamp(0.0, frame.width.toDouble()).toDouble(),
              p.dy.clamp(0.0, frame.height.toDouble()).toDouble(),
            ])
        .toList();

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.localApi == null) {
        await ref.read(boardRepositoryProvider).manualCalibrate(corners);
      } else {
        await widget.localApi!.saveCalibration(corners: corners);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = 'Manual calibration failed: $err';
          _loading = false;
        });
      }
    }
  }

  Future<void> _autoCalibratePi() async {
    if (widget.localApi == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.localApi!.autoCalibrate();
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = 'Automatic calibration failed: $err';
          _loading = false;
        });
      }
    }
  }

  void _addPoint(Offset localPos, Size displaySize) {
    final frame = _frame;
    if (frame == null || _imagePoints.length >= 4) return;
    final imgPt =
        _displayToImage(localPos, displaySize, frame.width, frame.height);
    setState(() => _imagePoints.add(imgPt));
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    final pointCount = _imagePoints.length;
    final nextLabel = pointCount < 4 ? _labels[pointCount] : null;

    return Scaffold(
      backgroundColor: kBackground,
      // ── Overlay AppBar + controls on top of the full-screen preview ──
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
            widget.localApi == null
                ? 'Manual Calibration'
                : 'Pi Board Calibration',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 16, fontWeight: FontWeight.w700, color: kOnSurface)),
        actions: [
          TextButton(
            onPressed: _loading ? null : _loadFrame,
            child: Text('REFRESH',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: kPrimary,
                    letterSpacing: 1)),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Full-screen camera preview ──────────────────────────────
          Positioned.fill(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : frame == null
                    ? Center(
                        child: Text('No frame available',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: kOnSurfaceVariant)),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final displaySize = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) =>
                                _addPoint(details.localPosition, displaySize),
                            child: Stack(
                              children: [
                                // Full-screen image (cover)
                                Positioned.fill(
                                  child: Image.memory(
                                    frame.bytes,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),

                                // Grid overlay
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _GridOverlayPainter(
                                      imgW: frame.width,
                                      imgH: frame.height,
                                      displaySize: displaySize,
                                    ),
                                  ),
                                ),

                                // Corner dots
                                ..._imagePoints.asMap().entries.map((e) {
                                  final index = e.key;
                                  final imgPt = e.value;
                                  final dp = _imageToDisplay(imgPt, displaySize,
                                      frame.width, frame.height);
                                  return Positioned(
                                    left: dp.dx - 14,
                                    top: dp.dy - 14,
                                    child: _CornerDot(
                                      label: _labels[index],
                                      color: index == 0
                                          ? const Color(0xFF8ADB52)
                                          : index == 1
                                              ? const Color(0xFFA2E7FF)
                                              : index == 2
                                                  ? const Color(0xFFFFD080)
                                                  : const Color(0xFFFF8AB4),
                                    ),
                                  );
                                }),

                                // Board outline once all 4 points are set
                                if (_imagePoints.length == 4)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _BoardOutlinePainter(
                                        imagePoints: _imagePoints,
                                        displaySize: displaySize,
                                        imgW: frame.width,
                                        imgH: frame.height,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // ── Bottom overlay: instruction chip + buttons ──────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    kBackground.withOpacity(0.92),
                    Colors.transparent,
                  ],
                  stops: const [0.6, 1.0],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Instruction row
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: kSurfaceContLow.withOpacity(0.88),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.touch_app_rounded,
                            color: kPrimary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            nextLabel != null
                                ? 'Tap corner ${pointCount + 1}/4 — $nextLabel  (${4 - pointCount} remaining)'
                                : 'All 4 corners selected. Tap SAVE CALIBRATION.',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: kOnSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    Text(_error!,
                        style: GoogleFonts.inter(fontSize: 11, color: kError)),
                  ],
                  const SizedBox(height: 10),

                  if (widget.localApi != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _autoCalibratePi,
                        icon: const Icon(Icons.auto_fix_high, size: 16),
                        label: const Text('AUTO-DETECT BOARD CORNERS'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => setState(() => _imagePoints.clear()),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text('RESET',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _loading || _imagePoints.length != 4
                              ? null
                              : _submit,
                          icon: const Icon(Icons.check_circle_outline_rounded,
                              size: 16),
                          label: Text('SAVE',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: kOnPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Corner Dot Widget ─────────────────────────────────────────────────────

class _CornerDot extends StatelessWidget {
  final String label;
  final Color color;
  const _CornerDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withOpacity(0.90),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: Colors.black87)),
      ),
    );
  }
}

// ─── Grid Overlay Painter ─────────────────────────────────────────────────

class _GridOverlayPainter extends CustomPainter {
  final int imgW, imgH;
  final Size displaySize;

  const _GridOverlayPainter(
      {required this.imgW, required this.imgH, required this.displaySize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 0.6;

    final rect = _imageDisplayRect(displaySize, imgW, imgH);
    final ox = rect.left;
    final oy = rect.top;
    final w = rect.width;
    final h = rect.height;

    // 8×8 grid
    for (int i = 1; i < 8; i++) {
      final x = ox + w * i / 8;
      canvas.drawLine(Offset(x, oy), Offset(x, oy + h), paint);
      final y = oy + h * i / 8;
      canvas.drawLine(Offset(ox, y), Offset(ox + w, y), paint);
    }

    // Image border
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(ox, oy, w, h), borderPaint);
  }

  @override
  bool shouldRepaint(_GridOverlayPainter old) =>
      old.imgW != imgW || old.imgH != imgH || old.displaySize != displaySize;
}

// ─── Board Outline Painter ────────────────────────────────────────────────

class _BoardOutlinePainter extends CustomPainter {
  final List<Offset> imagePoints;
  final Size displaySize;
  final int imgW, imgH;

  const _BoardOutlinePainter({
    required this.imagePoints,
    required this.displaySize,
    required this.imgW,
    required this.imgH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imagePoints.length != 4) return;

    final pts = imagePoints
        .map((p) => _imageToDisplay(p, displaySize, imgW, imgH))
        .toList();

    final path = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF8ADB52).withOpacity(0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF8ADB52).withOpacity(0.85)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_BoardOutlinePainter old) =>
      old.imagePoints != imagePoints || old.displaySize != displaySize;
}
