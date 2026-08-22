import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../widgets/animated_profile_avatar.dart';
import '../providers/device_provider.dart';
import '../providers/local_board_provider.dart';
import '../../domain/models/device_model.dart';
import 'dart:math' as math;

// ── Colour tokens ────────────────────────────────────────────────────────────
const kBackground = Color(0xFF151311);
const kSurfaceContLowest = Color(0xFF0F0E0C);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kPrimaryContainer = Color(0xFF68B631);
const kOnPrimary = Color(0xFF173800);
const kSecondary = Color(0xFFA2E7FF);
const kOnSecondary = Color(0xFF003642);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kOutlineVariant = Color(0xFF414939);

class CrossConnect extends ConsumerWidget {
  const CrossConnect({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            const Icon(Icons.settings_remote, color: kPrimary),
            const SizedBox(width: 10),
            Text('ROBOCHESS',
                style: GoogleFonts.spaceGrotesk(
                    color: kPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 2)),
          ],
        ),
        actions: [
          const AnimatedProfileAvatar(size: 34),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          children: [
            // ── Connection Status Banner ──────────────────────────────────
            _StatusBanner(),
            const SizedBox(height: 24),

            // ── Linked Boards ─────────────────────────────────────────────
            _LinkedBoards(),
            const SizedBox(height: 24),

            // ── Game Launch ───────────────────────────────────────────────
            _RadarSection(),
            const SizedBox(height: 28),

            // ── Active Friends + Nearby Boards ────────────────────────────
            _ActiveFriends(),
            const SizedBox(height: 24),
            _NearbyBoards(),
          ],
        ),
      ),
    );
  }
}

// ── Status Banner ─────────────────────────────────────────────────────────────
class _StatusBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider).valueOrNull ?? [];
    final selectedId = ref.watch(selectedDeviceProvider);
    final active = _resolveActiveDevice(devices, selectedId);
    final lastSeenText =
        active?.lastSeen != null ? _formatRelative(active!.lastSeen!) : '--';
    final connectionLabel = active?.status == 'connected'
        ? 'Connected'
        : active == null
            ? 'No board linked'
            : 'Offline';

    return Column(
      children: [
        // Device card
        Container(
          padding: const EdgeInsets.all(16),
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
              Expanded(child: _ActiveDeviceStatus()),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Latency card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kSurfaceContLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.network_check, color: kPrimary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LAST SEEN',
                        style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: kOnSurfaceVariant,
                            letterSpacing: 2)),
                    Text(lastSeenText,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kOnSurface)),
                  ],
                ),
              ),
              Text(connectionLabel,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: kOnSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveDeviceStatus extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider).valueOrNull ?? [];
    final selectedId = ref.watch(selectedDeviceProvider);
    final active = _resolveActiveDevice(devices, selectedId);
    final statusText =
        active == null ? 'NO BOARD LINKED' : (active.status.toUpperCase());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DEVICE',
            style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: kOnSurfaceVariant,
                letterSpacing: 2)),
        const SizedBox(height: 4),
        Text(active?.deviceId ?? 'Connect a board',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 16, fontWeight: FontWeight.w700, color: kOnSurface)),
        const SizedBox(height: 6),
        Row(
          children: [
            _PulsingDot(
                color: active?.status == 'connected' ? kPrimary : kSecondary),
            const SizedBox(width: 6),
            Text(statusText,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color:
                        active?.status == 'connected' ? kPrimary : kSecondary)),
          ],
        ),
      ],
    );
  }
}

DeviceModel? _resolveActiveDevice(
    List<DeviceModel> devices, String? selectedId) {
  if (devices.isEmpty) return null;
  if (selectedId == null) return devices.first;
  for (final device in devices) {
    if (device.deviceId == selectedId) return device;
  }
  return devices.first;
}

class _LinkedBoards extends ConsumerWidget {
  Widget _localBoardCard(BuildContext context, String deviceId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurfaceContHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_connected, color: kPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Local RoboChess board'),
                const SizedBox(height: 3),
                const Text('Saved local board • offline mode'),
                const SizedBox(height: 3),
                Text(deviceId),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.go('/local'),
            child: const Text('OPEN'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesState = ref.watch(deviceListProvider);
    final selectedId = ref.watch(selectedDeviceProvider);
    final localState = ref.watch(localBoardProvider);
    final localDeviceId = ref.watch(localLinkedDeviceIdProvider).valueOrNull ??
        localState.selected?.deviceId;

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
          Row(
            children: [
              const Icon(Icons.router, color: kSecondary, size: 18),
              const SizedBox(width: 8),
              Text('LINKED BOARDS',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.go('/connect/link'),
                icon: const Icon(Icons.add, size: 16, color: kPrimary),
                label: Text('LINK',
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kPrimary,
                        letterSpacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          devicesState.when(
          data: (items) {
              if (items.isEmpty && localDeviceId == null) {
                return Text('No boards linked yet.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: kOnSurfaceVariant));
              }
              if (selectedId == null && items.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ref
                      .read(selectedDeviceProvider.notifier)
                      .select(items.first.deviceId);
                });
              }
              return Column(
                children: [
                  if (localDeviceId != null)
                    _localBoardCard(context, localDeviceId),
                  ...items.map((device) {
                    final isSelected = device.deviceId == selectedId;
                    return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kSurfaceContHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? kPrimary
                            : kOutlineVariant.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.memory,
                            color: device.status == 'connected'
                                ? kPrimary
                                : kSecondary,
                            size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(device.deviceId,
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: kOnSurface)),
                              const SizedBox(height: 4),
                              Text(device.status.toUpperCase(),
                                  style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: device.status == 'connected'
                                          ? kPrimary
                                          : kOnSurfaceVariant)),
                              const SizedBox(height: 4),
                              Text(
                                  device.lastSeen == null
                                      ? 'Last seen: --'
                                      : 'Last seen: ${device.lastSeen!.toLocal().toString()}',
                                  style: GoogleFonts.inter(
                                      fontSize: 9, color: kOnSurfaceVariant)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              context.go('/connect/board/${device.deviceId}'),
                          child: Text('DETAILS',
                              style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: kSecondary)),
                        ),
                        TextButton(
                          onPressed: () => ref
                              .read(selectedDeviceProvider.notifier)
                              .select(device.deviceId),
                          child: Text(isSelected ? 'ACTIVE' : 'SELECT',
                              style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? kPrimary : kSecondary)),
                        ),
                        IconButton(
                          onPressed: () async {
                            await ref
                                .read(deviceListProvider.notifier)
                                .unlink(device.deviceId);
                            if (selectedId == device.deviceId) {
                              await ref
                                  .read(selectedDeviceProvider.notifier)
                                  .clear();
                            }
                          },
                          icon: const Icon(Icons.link_off,
                              color: kOnSurfaceVariant, size: 18),
                        ),
                      ],
                    ),
                    );
                  }).toList(),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(
              backgroundColor: kSurfaceContHighest,
              valueColor: AlwaysStoppedAnimation<Color>(kPrimary),
              minHeight: 6,
            ),
            error: (err, _) => localDeviceId != null
                ? _localBoardCard(context, localDeviceId)
                : Text('Failed to load boards.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: kOnSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

// ── Radar Section ─────────────────────────────────────────────────────────────
class _RadarSection extends StatefulWidget {
  @override
  State<_RadarSection> createState() => _RadarSectionState();
}

class _RadarSectionState extends State<_RadarSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: kSurfaceContLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kOutlineVariant.withOpacity(0.1)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Radar rings
          ...[1.0, 0.67, 0.33].map((scale) => Container(
                width: 260 * scale,
                height: 260 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: kPrimary.withOpacity(0.08 + (1 - scale) * 0.1),
                      width: 1),
                ),
              )),
          // Spinning sweep
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Transform.rotate(
              angle: _ctrl.value * 2 * math.pi,
              child: CustomPaint(
                size: const Size(260, 260),
                painter: _RadarSweepPainter(),
              ),
            ),
          ),
          // Content
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('GAME LAUNCH',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kPrimary,
                      letterSpacing: 4)),
              const SizedBox(height: 8),
              Text('Ready to Play?',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface)),
              const SizedBox(height: 24),
              // Start a playable game. Online matchmaking is not available
              // in the current backend, so this opens the working game flow
              // instead of silently doing nothing.
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kPrimary, kPrimaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: kPrimary.withOpacity(0.3),
                        blurRadius: 24,
                        spreadRadius: 2)
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.go('/play'),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.explore,
                              color: kOnPrimary, size: 22),
                          const SizedBox(width: 10),
                          Text('Start a Game',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: kOnPrimary)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Capabilities row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StatChip(
                      icon: Icons.smart_toy, label: 'AI AVAILABLE', color: kSecondary),
                  const SizedBox(width: 20),
                  _StatChip(
                      icon: Icons.timer,
                      label: 'INSTANT START',
                      color: kSecondary),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RadarSweepPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          kPrimary.withOpacity(0.05),
          kPrimary.withOpacity(0.25),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_RadarSweepPainter _) => false;
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(label.toUpperCase(),
            style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: kOnSurfaceVariant,
                letterSpacing: 1)),
      ],
    );
  }
}

// ── Active Friends ────────────────────────────────────────────────────────────
class _ActiveFriends extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider).valueOrNull ?? [];
    final connected =
        devices.where((device) => device.status == 'connected').toList();
    final onlineCount = connected.length;

    return Column(
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.group, color: kPrimary, size: 22),
                const SizedBox(width: 8),
                Text('Active Boards',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: kOnSurface)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text('${onlineCount} ONLINE',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: kPrimary,
                      letterSpacing: 1)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (connected.isEmpty)
          Text('No active boards right now.',
              style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant))
        else
          ...connected.map((device) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ActiveBoardCard(device: device),
              )),
      ],
    );
  }
}

class _ActiveBoardCard extends StatelessWidget {
  final DeviceModel device;
  const _ActiveBoardCard({required this.device});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurfaceContLow.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kSurfaceContHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person,
                    color: kOnSurfaceVariant, size: 28),
              ),
              Positioned(
                bottom: -1,
                right: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: kPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: kSurfaceContLow, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.deviceId,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kOnSurface)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.wifi, color: kOnSurfaceVariant, size: 13),
                    const SizedBox(width: 4),
                    Text('Connected',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: kOnSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context.go('/connect/board/${device.deviceId}'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: kSurfaceContHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('DETAILS',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: kPrimary,
                      letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Nearby Boards ─────────────────────────────────────────────────────────────
class _NearbyBoards extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider).valueOrNull ?? [];
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.sensors, color: kSecondary, size: 22),
                const SizedBox(width: 8),
                Text('Nearby Boards',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: kOnSurface)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kSecondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(devices.isEmpty ? 'BLE IDLE' : 'BLE ACTIVE',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: kSecondary,
                      letterSpacing: 1)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (devices.isEmpty)
          Text('No nearby boards detected yet.',
              style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant))
        else
          ...devices.map((device) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BoardCard(device: device),
              )),
      ],
    );
  }
}

class _BoardCard extends StatelessWidget {
  final DeviceModel device;
  const _BoardCard({required this.device});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurfaceContLow.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOutlineVariant.withOpacity(0.0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kSurfaceContHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.grid_view, color: kSecondary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.deviceId,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kOnSurface)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.signal_cellular_alt,
                        color: device.status == 'connected'
                            ? kSecondary
                            : kOnSurfaceVariant,
                        size: 13),
                    const SizedBox(width: 4),
                    Text(
                        'STRENGTH: ${device.status == 'connected' ? 'HIGH' : 'LOW'}',
                        style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: kOnSurfaceVariant,
                            letterSpacing: 1)),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context.go('/connect/board/${device.deviceId}'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: kSecondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('DETAILS',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: kSecondary,
                      letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatRelative(DateTime value) {
  final delta = DateTime.now().difference(value.toLocal());
  if (delta.inMinutes < 1) return '${delta.inSeconds}s ago';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

// ── Pulsing Dot ───────────────────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(_anim.value),
          boxShadow: [
            BoxShadow(
                color: widget.color.withOpacity(_anim.value * 0.6),
                blurRadius: 6)
          ],
        ),
      ),
    );
  }
}
