class PuzzleAttemptResult {
  final bool correct;
  final String nextFen;
  final bool completed;
  final String? expectedUci;
  final int nextIndex;

  PuzzleAttemptResult({
    required this.correct,
    required this.nextFen,
    required this.completed,
    required this.nextIndex,
    this.expectedUci,
  });

  factory PuzzleAttemptResult.fromJson(Map<String, dynamic> json) {
    return PuzzleAttemptResult(
      correct: json['correct'] == true,
      nextFen: json['next_fen']?.toString() ?? '',
      completed: json['completed'] == true,
      nextIndex: json['next_index'] is int
          ? json['next_index'] as int
          : int.tryParse(json['next_index']?.toString() ?? '0') ?? 0,
      expectedUci: json['expected_uci']?.toString(),
    );
  }
}
