import 'package:chess/chess.dart'; 
void main() { 
  var c = Chess(); 
  print(c.load_pgn('1. e4 c5')); 
  print(c.fen); 
}
