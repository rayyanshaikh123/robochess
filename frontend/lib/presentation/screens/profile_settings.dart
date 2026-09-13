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
import '../widgets/robo_app_bar.dart';
import '../providers/board_theme_provider.dart';
import '../theme/app_colors.dart';


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

  Future<void> _editProfile(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit profile'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Display name'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty || name == currentName) return;
    try {
      await ref.read(userRepositoryProvider).updateProfile(displayName: name);
      ref.invalidate(userProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update profile: $error')),
        );
      }
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
      appBar: RoboAppBar(
        sectionBadge: 'PROFILE',
        showBackButton: true,
        fallbackRoute: '/home',
        actions: [
          TextButton(
            onPressed: _signingOut ? null : _logout,
            child: Text(
              _signingOut ? 'SIGNING OUT...' : 'SIGN OUT',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kError,
                letterSpacing: 1,
              ),
            ),
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
              onEdit: () => _editProfile(displayName),
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
                    style: GoogleFonts.outfit(
                        fontSize: 13,
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
              onRefresh: device == null
                  ? null
                  : () => ref.read(deviceListProvider.notifier).load(),
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
            const SizedBox(height: 28),

            // ── App Experience ──────────────────────────────────────────
            _SectionHeader(label: 'App Experience', accentColor: kPrimary),
            const SizedBox(height: 14),

            // Chessboard Theme Selector
            const _BoardThemeSelectorCard(),
            const SizedBox(height: 14),
            Material(
              color: kSurfaceContLowest,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: kOutlineVariant),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.explore_rounded, color: kPrimary, size: 20),
                ),
                title: Text(
                  'Replay Onboarding Tour',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    color: kOnSurface,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  'Explore robotic board features and tactics tour',
                  style: GoogleFonts.inter(
                    color: kOnSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: kOnSurfaceVariant),
                onTap: () => context.push('/onboarding'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardThemeSelectorCard extends ConsumerWidget {
  const _BoardThemeSelectorCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(boardThemeProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceContLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kOutlineVariant),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.palette_rounded, color: kPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chessboard Theme',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      color: kOnSurface,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'Choose wooden, tournament green, or slate styles',
                    style: GoogleFonts.inter(
                      color: kOnSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 4 Theme Choice Chips / Cards
          Row(
            children: kBoardThemes.map((theme) {
              final isSelected = theme.id == activeTheme.id;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    ref.read(boardThemeProvider.notifier).setTheme(theme);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? kPrimary.withValues(alpha: 0.08) : kSurfaceContLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? kPrimary : kOutlineVariant,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        // 2x2 Mini Board Preview
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: theme.frameColor, width: 2),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(child: Container(color: theme.lightSquare)),
                                    Expanded(child: Container(color: theme.darkSquare)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(child: Container(color: theme.darkSquare)),
                                    Expanded(child: Container(color: theme.lightSquare)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            theme.name.replaceAll('Tournament ', ''),
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? kPrimary : kOnSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
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
  final VoidCallback onEdit;

  const _PlayerHero({
    required this.displayName,
    required this.email,
    required this.ratingText,
    required this.rankText,
    required this.onEdit,
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
          // Name-based logo avatar
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: kPrimary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: kOutlineVariant.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    AnimatedProfileAvatar.getInitials(displayName),
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.0,
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
                          color: kOnPrimary,
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
                    style: GoogleFonts.outfit(
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
                              style: GoogleFonts.outfit(
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
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: kSurfaceContHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kPrimary.withOpacity(0.2)),
              ),
              child: Text('EDIT',
                  style: GoogleFonts.outfit(
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
                      style: GoogleFonts.outfit(
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
                              style: GoogleFonts.outfit(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  color: kOnSurface)),
                          TextSpan(
                              text: '%',
                              style: GoogleFonts.outfit(
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
                              style: GoogleFonts.outfit(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  color: kSecondary)),
                          TextSpan(
                              text: '%',
                              style: GoogleFonts.outfit(
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
            style: GoogleFonts.outfit(
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
  final VoidCallback? onRefresh;
  final VoidCallback? onDisconnect;

  const _DeviceCard({
    required this.device,
    required this.loading,
    required this.errorText,
    required this.unlinking,
    required this.onRefresh,
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
                      style: GoogleFonts.outfit(
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
              onPressed: onRefresh,
              style: OutlinedButton.styleFrom(
                backgroundColor: kSurfaceContHighest,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.sync, color: kOnSurface, size: 16),
              label: Text('REFRESH STATUS',
                  style: GoogleFonts.outfit(
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
                  style: GoogleFonts.outfit(
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
