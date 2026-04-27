import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../domain/models/device_model.dart';
import '../../domain/models/user_stats.dart';
import '../providers/session_provider.dart';
import '../providers/device_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/animated_profile_avatar.dart';

// ── Colour tokens ────────────────────────────────────────────────────────────
const kBackground = Color(0xFF151311);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHigh = Color(0xFF2C2A27);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kPrimaryContainer = Color(0xFF68B631);
const kOnPrimary = Color(0xFF173800);
const kSecondary = Color(0xFFA2E7FF);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kOutlineVariant = Color(0xFF414939);
const kError = Color(0xFFFFB4AB);

class ProfileSettings extends ConsumerStatefulWidget {
  const ProfileSettings({super.key});

  @override
  ConsumerState<ProfileSettings> createState() => _ProfileSettingsState();
}

class _ProfileSettingsState extends ConsumerState<ProfileSettings> {
  bool _hapticEnabled = true;
  bool _darkModeEnabled = true;
  double _ledBrightness = 0.85;
  bool _signingOut = false;
  bool _unlinking = false;

  Future<void> _logout() async {
    setState(() => _signingOut = true);
    try {
      await ref.read(sessionProvider.notifier).logout();
      if (mounted) context.go('/login');
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final stats = ref.watch(userStatsProvider);
    final devices = ref.watch(deviceListProvider);
    final selectedDeviceId = ref.watch(selectedDeviceProvider);
    final displayName = profile.when(
      data: (value) => value.displayName,
      loading: () => 'Loading...',
      error: (_, __) => 'Grandmaster_X',
    );
    final email = profile.valueOrNull?.email;
    final profileError = profile.hasError ? 'Failed to load profile.' : null;
    final statsValue = stats.maybeWhen(
      data: (value) => value,
      orElse: () => const UserStats(
        rating: 0,
        globalRank: 0,
        gamesPlayed: 0,
        wins: 0,
        losses: 0,
        draws: 0,
        winRate: 0.0,
        accuracy: 0.0,
        puzzleAttempts: 0,
      ),
    );
    final gamesPlayed = statsValue.gamesPlayed;
    final winRate = statsValue.winRate;
    final accuracy = statsValue.accuracy;
    final statsError = stats.hasError ? 'Failed to load stats.' : null;
    final ratingText = stats.hasError ? '---' : _formatInt(statsValue.rating);
    final rankText = statsValue.globalRank > 0
        ? 'Global #${_formatInt(statsValue.globalRank)}'
        : 'Unranked';

    final deviceItems = devices.valueOrNull ?? const <DeviceModel>[];
    final deviceLoading = devices.isLoading;
    final deviceError = devices.hasError ? 'Failed to load devices.' : null;
    DeviceModel? device;
    if (deviceItems.isNotEmpty) {
      device = deviceItems.firstWhere(
        (item) => item.deviceId == selectedDeviceId,
        orElse: () => deviceItems.first,
      );
    }

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
          TextButton(
            onPressed: _signingOut ? null : _logout,
            child: Text(_signingOut ? 'SIGNING OUT...' : 'SIGN OUT',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: kPrimary,
                    letterSpacing: 1.5)),
          ),
          const AnimatedProfileAvatar(size: 36),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero: Player Identity ─────────────────────────────────────
            _PlayerHero(
              displayName: displayName,
              email: email,
              ratingText: ratingText,
              rankText: rankText,
            ),
            if (profileError != null) ...[
              const SizedBox(height: 10),
              Text(profileError,
                  style: GoogleFonts.inter(fontSize: 12, color: kError)),
            ],
            const SizedBox(height: 20),

            // ── Stats Bento Grid ──────────────────────────────────────────
            _StatsGrid(
              winRate: winRate,
              accuracy: accuracy,
              gamesPlayed: gamesPlayed,
            ),
            if (statsError != null) ...[
              const SizedBox(height: 10),
              Text(statsError,
                  style: GoogleFonts.inter(fontSize: 12, color: kError)),
            ],
            const SizedBox(height: 28),

            // ── Account ─────────────────────────────────────────────
            _SectionHeader(label: 'Account', accentColor: kPrimary),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _signingOut ? null : _logout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: kOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_signingOut ? 'SIGNING OUT...' : 'SIGN OUT',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2)),
              ),
            ),
            const SizedBox(height: 28),

            // ── System Settings ───────────────────────────────────────────
            _SectionHeader(label: 'System Settings', accentColor: kPrimary),
            const SizedBox(height: 14),
            _SettingToggle(
              icon: Icons.vibration,
              title: 'Haptic Feedback',
              subtitle: 'Tactile response for piece moves',
              value: _hapticEnabled,
              onChanged: (v) => setState(() => _hapticEnabled = v),
            ),
            const SizedBox(height: 10),
            _LedBrightnessSlider(
              value: _ledBrightness,
              onChanged: (v) => setState(() => _ledBrightness = v),
            ),
            const SizedBox(height: 10),
            _SettingToggle(
              icon: Icons.dark_mode,
              title: 'Dark Mode',
              subtitle: 'UI appearance preference',
              value: _darkModeEnabled,
              onChanged: (v) => setState(() => _darkModeEnabled = v),
            ),
            const SizedBox(height: 28),

            // ── Device Hardware ───────────────────────────────────────────
            _SectionHeader(label: 'Device Hardware', accentColor: kSecondary),
            const SizedBox(height: 14),
            _DeviceCard(
              device: device,
              loading: deviceLoading,
              errorText: deviceError,
              unlinking: _unlinking,
              onFirmwareUpdate: device == null ? null : () {},
              onDisconnect: device == null || _unlinking
                  ? null
                  : () async {
                      setState(() => _unlinking = true);
                      try {
                        await ref
                            .read(deviceListProvider.notifier)
                            .unlink(device!.deviceId);
                        if (selectedDeviceId == device!.deviceId) {
                          await ref
                              .read(selectedDeviceProvider.notifier)
                              .clear();
                        }
                      } finally {
                        if (mounted) setState(() => _unlinking = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Player Hero ───────────────────────────────────────────────────────────────
class _PlayerHero extends StatelessWidget {
  final String displayName;
  final String? email;
  final String ratingText;
  final String rankText;

  const _PlayerHero({
    required this.displayName,
    required this.email,
    required this.ratingText,
    required this.rankText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Avatar with gradient border
          Stack(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kPrimary, kPrimaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.all(2),
                child: Container(
                  decoration: BoxDecoration(
                    color: kSurfaceContHighest,
                    borderRadius: BorderRadius.circular(16),
                    image: const DecorationImage(
                      image: AssetImage('assets/images/profile_avatar.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kSecondary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('PRO',
                      style: GoogleFonts.inter(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF003642),
                          letterSpacing: 1)),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: kOnSurface)),
                if (email != null && email!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(email!,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: kOnSurfaceVariant)),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kSurfaceContHighest,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.military_tech,
                              color: kPrimary, size: 14),
                          const SizedBox(width: 4),
                          Text(ratingText,
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: kPrimary)),
                          const SizedBox(width: 4),
                          Text('ELO',
                              style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: kOnSurfaceVariant,
                                  letterSpacing: 1)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(rankText,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: kOnSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          // Edit button
          GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: kSurfaceContHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kPrimary.withOpacity(0.2)),
              ),
              child: Text('EDIT',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
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

// ── Stats Grid ────────────────────────────────────────────────────────────────
class _StatsGrid extends StatelessWidget {
  final double winRate;
  final double accuracy;
  final int gamesPlayed;

  const _StatsGrid(
      {required this.winRate,
      required this.accuracy,
      required this.gamesPlayed});

  @override
  Widget build(BuildContext context) {
    final gamesText = _formatInt(gamesPlayed);
    final clampedWinRate = winRate.clamp(0.0, 1.0) as double;
    final clampedAccuracy = accuracy.clamp(0.0, 1.0) as double;
    final winRateText = (clampedWinRate * 100).toStringAsFixed(1);
    final accuracyText = (clampedAccuracy * 100).toStringAsFixed(1);
    return Column(
      children: [
        // Games Played
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: kSurfaceContLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GAMES PLAYED',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: kOnSurfaceVariant,
                      letterSpacing: 2)),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(gamesText,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: kOnSurface)),
                  const SizedBox(width: 8),
                  const Icon(Icons.trending_up, color: kPrimary, size: 18),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Win Rate
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kSurfaceContLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WIN RATE',
                        style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: kOnSurfaceVariant,
                            letterSpacing: 2)),
                    const SizedBox(height: 12),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                              text: winRateText,
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  color: kOnSurface)),
                          TextSpan(
                              text: '%',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: kOnSurface)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: clampedWinRate,
                        backgroundColor: kSurfaceContHighest,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(kPrimary),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Accuracy
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kSurfaceContLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ACCURACY',
                        style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: kOnSurfaceVariant,
                            letterSpacing: 2)),
                    const SizedBox(height: 12),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                              text: accuracyText,
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  color: kSecondary)),
                          TextSpan(
                              text: '%',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: kSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Icon(Icons.my_location, color: kSecondary, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatInt(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final position = raw.length - i;
    if (i != 0 && position % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(raw[i]);
  }
  return buffer.toString();
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}

// ── Section Header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  final Color accentColor;
  const _SectionHeader({required this.label, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 16, height: 1, color: accentColor),
        const SizedBox(width: 8),
        Text(label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: kOnSurfaceVariant,
                letterSpacing: 3)),
      ],
    );
  }
}

// ── Setting Toggle Row ────────────────────────────────────────────────────────
class _SettingToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kSurfaceContHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kOnSurfaceVariant, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kOnSurface)),
                Text(subtitle,
                    style: GoogleFonts.inter(
                        fontSize: 10, color: kOnSurfaceVariant)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: kPrimary,
            activeTrackColor: kPrimary.withOpacity(0.3),
            inactiveThumbColor: kOnSurfaceVariant,
            inactiveTrackColor: kSurfaceContHighest,
          ),
        ],
      ),
    );
  }
}

// ── LED Brightness Slider ─────────────────────────────────────────────────────
class _LedBrightnessSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _LedBrightnessSlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kSurfaceContHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.light_mode,
                    color: kOnSurfaceVariant, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text('Board LED Brightness',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kOnSurface)),
              ),
              Text('${(value * 100).round()}%',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kPrimary,
                      fontFeatures: [const FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: kPrimary,
              inactiveTrackColor: kSurfaceContHighest,
              thumbColor: kPrimary,
              overlayColor: kPrimary.withOpacity(0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Device Card ───────────────────────────────────────────────────────────────
class _DeviceCard extends StatelessWidget {
  final DeviceModel? device;
  final bool loading;
  final String? errorText;
  final bool unlinking;
  final VoidCallback? onFirmwareUpdate;
  final VoidCallback? onDisconnect;

  const _DeviceCard({
    required this.device,
    required this.loading,
    required this.errorText,
    required this.unlinking,
    required this.onFirmwareUpdate,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final status = device?.status ?? 'unknown';
    final statusColor = status == 'connected' ? kPrimary : kOnSurfaceVariant;
    final connectionValue = device == null
        ? 0.0
        : status == 'connected'
            ? 1.0
            : 0.2;
    final connectionText = device == null
        ? '--'
        : status == 'connected'
            ? '100%'
            : '20%';
    final lastSeenText = device?.lastSeen != null
        ? 'Last seen ${_formatDateTime(device!.lastSeen!)}'
        : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSecondary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loading ? 'Loading device...' : 'RoboBoard v2',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: kOnSurface)),
                  const SizedBox(height: 4),
                  Text(
                      device == null
                          ? 'Connect a board to see details'
                          : 'ID: ${device!.deviceId}',
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          color: kOnSurfaceVariant,
                          fontFeatures: [const FontFeature.tabularFigures()])),
                ],
              ),
              Column(
                children: [
                  const Icon(Icons.precision_manufacturing,
                      color: kSecondary, size: 26),
                  const SizedBox(height: 4),
                  Text(status.toUpperCase(),
                      style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                          letterSpacing: 1)),
                ],
              ),
            ],
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(errorText!,
                style: GoogleFonts.inter(fontSize: 10, color: kError)),
          ],
          if (lastSeenText != null) ...[
            const SizedBox(height: 8),
            Text(lastSeenText,
                style:
                    GoogleFonts.inter(fontSize: 10, color: kOnSurfaceVariant)),
          ],
          const SizedBox(height: 24),
          // Connection
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.link, color: kPrimary, size: 16),
                  const SizedBox(width: 6),
                  Text('Connection',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: kOnSurface)),
                ],
              ),
              Text(connectionText,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: kSurfaceContHighest,
                borderRadius: BorderRadius.circular(99),
              ),
              child: FractionallySizedBox(
                widthFactor: connectionValue,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    gradient:
                        const LinearGradient(colors: [kPrimary, kSecondary]),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Buttons
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onFirmwareUpdate,
              style: OutlinedButton.styleFrom(
                backgroundColor: kSurfaceContHighest,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.sync, color: kOnSurface, size: 16),
              label: Text('FIRMWARE UPDATE',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface,
                      letterSpacing: 1)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onDisconnect,
              style: OutlinedButton.styleFrom(
                foregroundColor: kError,
                side: BorderSide(color: kError.withOpacity(0.2)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(unlinking ? 'DISCONNECTING...' : 'DISCONNECT DEVICE',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kError,
                      letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}
