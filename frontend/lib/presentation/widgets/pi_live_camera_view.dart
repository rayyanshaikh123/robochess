import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/repositories/pi_local_api.dart';

/// Continuous Wi-Fi camera view from the Pi's MJPEG endpoint.
class PiLiveCameraView extends StatefulWidget {
  final String baseUrl;
  final VoidCallback? onCalibrate;
  final VoidCallback? onFlip;

  const PiLiveCameraView({
    super.key,
    required this.baseUrl,
    this.onCalibrate,
    this.onFlip,
  });

  @override
  State<PiLiveCameraView> createState() => _PiLiveCameraViewState();
}

class _PiLiveCameraViewState extends State<PiLiveCameraView> {
  late PiLocalApi _api;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _fallbackTimer;
  Timer? _pollingBackupTimer;
  Uint8List? _frame;
  String? _error;
  bool _polling = false;
  bool _flipping = false;

  @override
  void initState() {
    super.initState();
    _api = PiLocalApi(baseUrl: widget.baseUrl);
    _connect();
  }

  @override
  void didUpdateWidget(covariant PiLiveCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl) {
      _api.client.close();
      _api = PiLocalApi(baseUrl: widget.baseUrl);
      _frame = null;
      _connect();
    }
  }

  void _connect() {
    _subscription?.cancel();
    _fallbackTimer?.cancel();
    _error = null;
    _subscription = _api.cameraStream().listen(
      (frame) {
        if (mounted) {
          setState(() {
            _frame = frame;
            _error = null;
          });
        }
      },
      onError: (Object error) {
        _startFrameFallback(error);
      },
      onDone: () => _startFrameFallback('Pi stream closed'),
    );
    // Also start polling as backup to ensure we always get frames
    _startPollingBackup();
  }

  void _startPollingBackup() {
    _pollingBackupTimer?.cancel();
    _pollingBackupTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted) return;
      try {
        final frame = await _api.cameraFrame(preview: true);
        if (mounted && _frame == null) {
          // Only use polled frame if we don't have a stream frame
          setState(() {
            _frame = frame;
            _error = 'Live over Wi-Fi (polling fallback)';
          });
        }
      } catch (_) {
        // Ignore polling errors
      }
    });
  }

  void _startFrameFallback(Object error) {
    if (!mounted) return;
    _fallbackTimer?.cancel();
    setState(() {
      _error = _frame == null
          ? 'Stream unavailable; trying camera frames… ($error)'
          : 'Live over Wi-Fi (compatibility mode)';
    });
    _pollFrame();
    _fallbackTimer =
        Timer.periodic(const Duration(milliseconds: 350), (_) => _pollFrame());
  }

  Future<void> _pollFrame() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final frame = await _api.cameraFrame(preview: true);
      if (mounted) {
        setState(() {
          _frame = frame;
          _error = 'Live over Wi-Fi (frame fallback)';
        });
      }
    } catch (error) {
      if (mounted && _frame == null) {
        setState(() => _error = 'Pi camera unavailable: $error');
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _flipCamera() async {
    if (_flipping) return;
    setState(() => _flipping = true);
    try {
      await _api.flipCalibration();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Board camera flipped 180°'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      widget.onFlip?.call();
      _connect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to flip: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _flipping = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _fallbackTimer?.cancel();
    _pollingBackupTimer?.cancel();
    _api.client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.videocam,
                  color: _frame == null ? Colors.orange : Colors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Live board camera',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      _frame == null
                          ? (_error ?? 'Connecting to Pi…')
                          : 'Live over Wi-Fi',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Flip orientation (180°)',
                onPressed: _flipping ? null : _flipCamera,
                icon: _flipping
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.screen_rotation_rounded),
              ),
              IconButton(
                tooltip: 'Refresh stream',
                onPressed: _connect,
                icon: const Icon(Icons.refresh),
              ),
              if (widget.onCalibrate != null)
                IconButton(
                    tooltip: 'Calibrate corners',
                    onPressed: widget.onCalibrate,
                    icon: const Icon(Icons.crop_free)),
            ],
          ),
        ),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: _frame == null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error ?? 'Waiting for camera frames…',
                      textAlign: TextAlign.center),
                ))
              : Image.memory(_frame!,
                  fit: BoxFit.contain, gaplessPlayback: true),
        ),
      ]),
    );
  }
}
