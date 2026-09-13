import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/models/opening_context.dart';
import '../theme/app_colors.dart';


class LessonTrackScreen extends StatelessWidget {
  final String title;
  final String description;
  final Color accent;
  final List<LessonItem> lessons;

  const LessonTrackScreen({
    super.key,
    required this.title,
    required this.description,
    required this.accent,
    required this.lessons,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        surfaceTintColor: Colors.transparent,
        title: Text('GRANDMASTER ACADEMY',
            style: GoogleFonts.cinzel(
                color: kPrimary, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 1.5)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/learn');
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(title,
              style: GoogleFonts.cinzel(
                  color: kOnSurface,
                  fontSize: 28,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(description,
              style: GoogleFonts.inter(
                  color: kOnSurfaceVariant, height: 1.5, fontSize: 13)),
          const SizedBox(height: 24),
          ...lessons.asMap().entries.map((entry) {
            final index = entry.key;
            final lesson = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _LessonCard(
                number: index + 1,
                lesson: lesson,
                accent: accent,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class LessonItem {
  final String title;
  final String summary;
  final String objective;

  const LessonItem({
    required this.title,
    required this.summary,
    required this.objective,
  });
}

class _LessonCard extends StatelessWidget {
  final int number;
  final LessonItem lesson;
  final Color accent;

  const _LessonCard({
    required this.number,
    required this.lesson,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: accent.withOpacity(0.14),
            child: Text('$number',
                style: GoogleFonts.outfit(
                    color: accent, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(lesson.title,
                style: GoogleFonts.outfit(
                    color: kOnSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        Text(lesson.summary,
            style: GoogleFonts.inter(color: kOnSurfaceVariant, height: 1.45)),
        const SizedBox(height: 8),
        Text('OBJECTIVE  ${lesson.objective}',
            style: GoogleFonts.inter(
                color: accent, fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => context.go(
              '/play',
              extra: OpeningContext(
                name: lesson.title,
                pgn: lesson.objective,
              ),
            ),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('PRACTICE'),
            style: FilledButton.styleFrom(
              backgroundColor: kSurfaceContHighest,
              foregroundColor: accent,
            ),
          ),
        ),
      ]),
    );
  }
}
