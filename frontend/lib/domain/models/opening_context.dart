/// Context passed from the Learn platform (openings / lesson tracks) to the
/// Play screen so it can load a guided opening position.
class OpeningContext {
  final String name;
  final String pgn;

  const OpeningContext({required this.name, required this.pgn});
}
