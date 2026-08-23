import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/models/opening_context.dart';

const _background = Color(0xFF151311);
const _surface = Color(0xFF1D1B19);
const _surfaceHigh = Color(0xFF373431);
const _primary = Color(0xFF8ADB52);
const _onSurface = Color(0xFFE7E2DD);
const _muted = Color(0xFFC0CAB4);

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
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        title: Text('GRANDMASTER ACADEMY',
            style: GoogleFonts.spaceGrotesk(
                color: _primary, fontWeight: FontWeight.w700, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _primary),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(title,
              style: GoogleFonts.spaceGrotesk(
                  color: _onSurface,
                  fontSize: 32,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(description,
              style: GoogleFonts.inter(
                  color: _muted, height: 1.5, fontSize: 13)),
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
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: accent.withOpacity(0.14),
            child: Text('$number',
                style: GoogleFonts.spaceGrotesk(
                    color: accent, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(lesson.title,
                style: GoogleFonts.spaceGrotesk(
                    color: _onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        Text(lesson.summary,
            style: GoogleFonts.inter(color: _muted, height: 1.45)),
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
              backgroundColor: _surfaceHigh,
              foregroundColor: accent,
            ),
          ),
        ),
      ]),
    );
  }
}
