import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../widgets/animated_profile_avatar.dart';
import '../widgets/robo_app_bar.dart';
import '../providers/device_provider.dart';
import '../providers/local_board_provider.dart';
import '../../domain/models/device_model.dart';
import '../../domain/models/robochess_device.dart';
import '../theme/app_colors.dart';

class CrossConnect extends ConsumerWidget {
  const CrossConnect({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: const RoboAppBar(
        sectionBadge: 'CONNECT',
        actions: [
          AnimatedProfileAvatar(size: 34),
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
            const _ArenaLaunchSection(),
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
                        style: GoogleFonts.outfit(
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
            style: GoogleFonts.outfit(
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesState = ref.watch(deviceListProvider);
    final localState = ref.watch(localBoardProvider);
    final selectedId = ref.watch(selectedDeviceProvider);

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
                  style: GoogleFonts.cinzel(
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
              final localDevice = localState.selected;
              final hasLocalDevice = localDevice?.deviceId != null &&
                  items.every((item) => item.deviceId != localDevice!.deviceId);
              if (items.isEmpty && !hasLocalDevice) {
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
                  if (hasLocalDevice)
                    _LocalLinkedBoardCard(
                      deviceId: localDevice!.deviceId!,
                      isConnected: localState.connection == LocalConnectionState.connected ||
                          localState.connection == LocalConnectionState.ready,
                      onPlay: () => context.go('/play'),
                      onConnect: () => context.push('/connect/link'),
                      onForget: () async {
                        await ref.read(localBoardProvider.notifier).forgetDevice();
                      },
                    ),
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
            error: (err, _) => Text('Failed to load boards.',
                style:
                    GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

// ── Tournament Arena Launch Section ─────────────────────────────────────────────
class _LocalLinkedBoardCard extends StatelessWidget {
  final String deviceId;
  final bool isConnected;
  final VoidCallback onPlay;
  final VoidCallback onConnect;
  final VoidCallback? onForget;

  const _LocalLinkedBoardCard({
    required this.deviceId,
    required this.isConnected,
    required this.onPlay,
    required this.onConnect,
    this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurfaceContHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected ? kPrimary : kOutlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
            color: isConnected ? kPrimary : kOnSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deviceId,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: kOnSurface)),
                const SizedBox(height: 4),
                Text(
                  isConnected ? 'CONNECTED LOCALLY' : 'SAVED BOARD (OFFLINE)',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isConnected ? kPrimary : kOnSurfaceVariant,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: isConnected ? onPlay : onConnect,
            child: Text(
              isConnected ? 'PLAY' : 'CONNECT',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isConnected ? kPrimary : kSecondary,
                letterSpacing: 1,
              ),
            ),
          ),
          if (!isConnected && onForget != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: kOnSurfaceVariant),
              tooltip: 'Forget saved board',
              onPressed: onForget,
            ),
        ],
      ),
    );
  }
}

class _ArenaLaunchSection extends StatelessWidget {
  const _ArenaLaunchSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kOutlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.shield_outlined, color: kPrimary, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            'TOURNAMENT ARENA',
            style: GoogleFonts.cinzel(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kPrimary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ready to Play?',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: kOnSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Challenge the Stockfish engine, play on the wooden board, or match with friends.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: kOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => context.go('/play'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: kOnPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            icon: const Icon(Icons.play_arrow, size: 20),
            label: Text(
              'START MATCH',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _StatChip(
                icon: Icons.psychology_outlined,
                label: 'STOCKFISH READY',
                color: kSecondary,
              ),
              SizedBox(width: 16),
              _StatChip(
                icon: Icons.wifi_tethering,
                label: 'BOARD SYNC',
                color: kSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
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
                    style: GoogleFonts.outfit(
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
                    style: GoogleFonts.outfit(
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
