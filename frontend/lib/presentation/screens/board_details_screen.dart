import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/device_provider.dart';
import '../../domain/models/device_model.dart';

const kBackground = Color(0xFF151311);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kSecondary = Color(0xFFA2E7FF);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kOutlineVariant = Color(0xFF414939);

class BoardDetailsScreen extends ConsumerStatefulWidget {
  final String deviceId;
  const BoardDetailsScreen({super.key, required this.deviceId});

  @override
  ConsumerState<BoardDetailsScreen> createState() => _BoardDetailsScreenState();
}

class _BoardDetailsScreenState extends ConsumerState<BoardDetailsScreen> {
  final List<int> _latencyHistory = [];
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _pingTimer;
  DateTime? _pendingPingAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSocket());
  }

  Future<void> _initSocket() async {
    final socket = ref.read(deviceSocketProvider);
    await socket.connect();
    socket.subscribe([widget.deviceId]);
    _sub = socket.stream.listen(_handleEvent);
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _sendPing());
    _sendPing();
  }

  void _sendPing() {
    _pendingPingAt = DateTime.now();
    ref.read(deviceSocketProvider).ping();
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (event['type'] == 'pong') {
      if (_pendingPingAt == null) return;
      final latency = DateTime.now().difference(_pendingPingAt!).inMilliseconds;
      setState(() {
        _latencyHistory.add(latency);
        if (_latencyHistory.length > 20) {
          _latencyHistory.removeAt(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceListProvider).valueOrNull ?? [];
    final device = _resolveDevice(devices, widget.deviceId);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Board Details',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 16, fontWeight: FontWeight.w700, color: kOnSurface)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DeviceHeader(device: device),
            const SizedBox(height: 16),
            _StatusPanel(device: device),
            const SizedBox(height: 16),
            _LatencyPanel(history: _latencyHistory),
          ],
        ),
      ),
    );
  }

  DeviceModel? _resolveDevice(List<DeviceModel> devices, String deviceId) {
    for (final device in devices) {
      if (device.deviceId == deviceId) return device;
    }
    return null;
  }
}

class _DeviceHeader extends StatelessWidget {
  final DeviceModel? device;

  const _DeviceHeader({required this.device});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kSecondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.router, color: kSecondary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BOARD ID',
                    style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: kOnSurfaceVariant,
                        letterSpacing: 2)),
                const SizedBox(height: 6),
                Text(device?.deviceId ?? 'Unknown',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kOnSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final DeviceModel? device;

  const _StatusPanel({required this.device});

  @override
  Widget build(BuildContext context) {
    final status = device?.status ?? 'unknown';
    final lastSeen = device?.lastSeen;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STATUS',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: kOnSurfaceVariant,
                  letterSpacing: 2)),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status == 'connected' ? kPrimary : kSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Text(status.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface)),
            ],
          ),
          const SizedBox(height: 12),
          Text('LAST SEEN',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: kOnSurfaceVariant,
                  letterSpacing: 2)),
          const SizedBox(height: 6),
          Text(
              lastSeen != null ? lastSeen.toLocal().toString() : 'No heartbeat',
              style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant)),
        ],
      ),
    );
  }
}

class _LatencyPanel extends StatelessWidget {
  final List<int> history;

  const _LatencyPanel({required this.history});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kOutlineVariant.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.network_check, color: kPrimary, size: 20),
              const SizedBox(width: 8),
              Text('LATENCY HISTORY',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface)),
            ],
          ),
          const SizedBox(height: 12),
          if (history.isEmpty)
            Text('Waiting for samples...',
                style:
                    GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant))
          else
            SizedBox(
              height: 80,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children:
                    history.map((value) => _LatencyBar(value: value)).toList(),
              ),
            ),
          const SizedBox(height: 12),
          if (history.isNotEmpty)
            Text('Last: ${history.last} ms',
                style:
                    GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
        ],
      ),
    );
  }
}

class _LatencyBar extends StatelessWidget {
  final int value;

  const _LatencyBar({required this.value});

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(20, 400);
    final height = (clamped / 400) * 70;
    return Container(
      width: 6,
      margin: const EdgeInsets.only(right: 4),
      height: height.toDouble(),
      decoration: BoxDecoration(
        color: kPrimary.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
