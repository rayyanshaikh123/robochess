import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/board_remote.dart';
import '../../data/repositories/board_repository.dart';
import 'session_provider.dart';

final boardRepositoryProvider = Provider<BoardRepository>((ref) {
  return BoardRepository(BoardRemoteDataSource(ref.read(apiClientProvider)));
});
