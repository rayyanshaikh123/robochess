import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/repositories/pi_local_api.dart';

/// Continuous Wi-Fi camera view from the Pi's MJPEG endpoint.
class PiLiveCameraView extends StatefulWidget {
  final String baseUrl;
  final VoidCallback? onCalibrate;

  const PiLiveCameraView({super.key, required this.baseUrl, this.onCalibrate});

  @override
  State<PiLiveCameraView> createState() => _PiLiveCameraViewState();
}

class _PiLiveCameraViewState extends State<PiLiveCameraView> {
  late PiLocalApi _api;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _fallbackTimer;
  Uint8List? _frame;
  String? _error;
  bool _polling = false;

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

  @override
  void dispose() {
    _subscription?.cancel();
    _fallbackTimer?.cancel();
    _api.client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          leading: Icon(Icons.videocam,
              color: _frame == null ? Colors.orange : Colors.green),
          title: const Text('Live board camera'),
          subtitle: Text(_frame == null
              ? (_error ?? 'Connecting to Pi…')
              : 'Live over Wi-Fi'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(onPressed: _connect, icon: const Icon(Icons.refresh)),
            if (widget.onCalibrate != null)
              IconButton(
                  onPressed: widget.onCalibrate,
                  icon: const Icon(Icons.crop_free)),
          ]),
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
