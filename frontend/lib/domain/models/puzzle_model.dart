class PuzzleModel {
  final String puzzleId;
  final String fen;
  final int? rating;
  final List<String> tags;
  final int length;

  PuzzleModel({
    required this.puzzleId,
    required this.fen,
    required this.length,
    this.rating,
    this.tags = const [],
  });

  factory PuzzleModel.fromJson(Map<String, dynamic> json) {
    return PuzzleModel(
      puzzleId: json['puzzle_id']?.toString() ?? '',
      fen: json['fen']?.toString() ?? '',
      length: json['length'] is int
          ? json['length'] as int
          : int.tryParse(json['length']?.toString() ?? '0') ?? 0,
      rating: json['rating'] is int
          ? json['rating'] as int
          : int.tryParse(json['rating']?.toString() ?? ''),
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}
