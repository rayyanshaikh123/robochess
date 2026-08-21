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
  Uint8List? _frame;
  String? _error;

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
        if (mounted) setState(() => _error = 'Live camera unavailable: $error');
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
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
