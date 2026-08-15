import 'dart:async';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../widgets/animated_profile_avatar.dart';
import '../providers/device_provider.dart';
import '../providers/board_provider.dart';
import '../providers/game_provider.dart';
import '../providers/session_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/config/app_config.dart';
import '../../domain/models/device_model.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/calibration_frame.dart';
import '../../domain/voice/voice_service.dart';
import '../../domain/voice/move_parser.dart';
import 'manual_calibration_screen.dart';

const kBackground = Color(0xFF151311);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHigh = Color(0xFF2C2A27);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kOnPrimary = Color(0xFF173800);
const kSecondary = Color(0xFFA2E7FF);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kOutlineVariant = Color(0xFF414939);
const kError = Color(0xFFFFB4AB);

const _pieceSymbols = {
  'p': '♙',
  'n': '♘',
  'b': '♗',
  'r': '♖',
  'q': '♕',
  'k': '♔',
};

class PlayScreen extends ConsumerStatefulWidget {
  const PlayScreen({super.key});
  @override
  ConsumerState<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends ConsumerState<PlayScreen> {
  // ── Game state ──
  final chess.Chess _game = chess.Chess();
  String? _selectedSquare; // e.g. "e2"
  List<String> _legalDestinations = [];
  String? _lastMoveFrom;
  String? _lastMoveTo;
  String _statusMessage = 'Your move';

  // ── Move history: [[moveNum, whiteSAN, blackSAN?]]
  final List<List<String?>> _moveHistory = [];

  // ── Voice state ──
  bool _voiceExpanded = false;
  bool _micActive = false;
  String _voiceStatus = 'Mic off';
  String? _lastParsedMove;
  List<MicInputDevice> _micDevices = const [];
  int? _selectedMicId;
  bool _micDevicesLoading = false;
  bool _micDropdownOpen = false;
  final VoiceService _voiceService = VoiceService();
  StreamSubscription<String>? _statusSub;
  StreamSubscription<String>? _resultSub;
  StreamSubscription<Map<String, dynamic>>? _gameWsSub;
  ProviderSubscription<AsyncValue<GameStateModel?>>? _gameSub;

  String? _linkedGameId;
  int _linkedGameVersion = 0;
  bool _syncing = false;
  String? _syncError;
  String? _pendingLocalUci;
  int? _pendingLocalVersion;
  String? _wsGameId;

  bool _gameUsesBoard = false;
  CalibrationFrame? _liveFrame;
  bool _livePreviewLoading = false;
  String? _livePreviewError;
  bool _snapshotDetecting = false;
  String? _snapshotNote;
  bool _inGameValidating = false;
  bool _inGameValidated = false;
  String? _inGameValidationNote;
  Timer? _autoDetectTimer;

  @override
  void initState() {
    super.initState();
    _gameSub = ref.listenManual<AsyncValue<GameStateModel?>>(
        gameControllerProvider, (previous, next) {
      final prevGameId = _linkedGameId;
      final prevVersion = _linkedGameVersion;
      final value = next.valueOrNull;
      if (value != null && mounted) {
        setState(() {
          _linkedGameId = value.gameId;
          _linkedGameVersion = value.gameVersion;
          _syncing = false;
          _syncError = null;
        });
        if (value.currentFen.isNotEmpty &&
            (value.gameId != prevGameId || value.gameVersion != prevVersion)) {
          _applyGameState(value);
        }
        if (value.gameId != prevGameId) {
          _connectGameSocket(value.gameId);
        }
      }
      if (next.hasError && mounted) {
        setState(() {
          _syncing = false;
          _syncError = 'Failed to sync with backend.';
        });
      }
    });
    final initialGame = ref.read(gameControllerProvider).valueOrNull;
    if (initialGame != null) {
      _linkedGameId = initialGame.gameId;
      _linkedGameVersion = initialGame.gameVersion;
      if (initialGame.currentFen.isNotEmpty) {
        _applyGameState(initialGame);
      }
      _connectGameSocket(initialGame.gameId);
    }
    _statusSub = _voiceService.statusStream.listen((status) {
      if (mounted) setState(() => _voiceStatus = status);
    });
    _resultSub = _voiceService.resultStream.listen(_handleVoiceResult);
    _loadMicDevices();
  }

  @override
  void dispose() {
    _autoDetectTimer?.cancel();
    _gameSub?.close();
    _statusSub?.cancel();
    _resultSub?.cancel();
    _gameWsSub?.cancel();
    ref.read(gameSocketProvider).close();
    _voiceService.dispose();
    super.dispose();
  }

  // ── Square name helpers (0-based row,col → algebraic) ──
  String _squareName(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + col);
    final rank = '${8 - row}';
    return '$file$rank';
  }

  // ── Tap on a board square ──
  void _onSquareTap(int row, int col) {
    if (_gameUsesBoard) return;
    final square = _squareName(row, col);
    final piece = _game.get(square);

    // If we have a selected square and this is a legal destination → make the move
    if (_selectedSquare != null && _legalDestinations.contains(square)) {
      _makeMove(_selectedSquare!, square);
      return;
    }

    // If tapping own piece → select it
    if (piece != null && piece.color == _game.turn) {
      final moves = _game.generate_moves();
      final destinations = moves
          .where((m) => m.fromAlgebraic == square)
          .map((m) => m.toAlgebraic)
          .toList();
      setState(() {
        _selectedSquare = square;
        _legalDestinations = destinations;
      });
      return;
    }

    // Otherwise deselect
    setState(() {
      _selectedSquare = null;
      _legalDestinations = [];
    });
  }

  // ── Make a move ──
  void _makeMove(String from, String to) {
    // Check for promotion
    final piece = _game.get(from);
    String? promotion;
    if (piece != null &&
        piece.type == chess.PieceType.PAWN &&
        (to[1] == '8' || to[1] == '1')) {
      promotion = 'q'; // Auto-promote to queen for now
    }

    final uci = '${from}${to}${promotion ?? ''}';
    final applied = _applyUciMove(uci);
    if (applied) {
      setState(() {});
      _submitRemoteMove(uci);
    }
  }

  Future<void> _submitRemoteMove(String uci) async {
    if (_linkedGameId == null) return;
    try {
      _pendingLocalUci = uci;
      _pendingLocalVersion = _linkedGameVersion + 1;
      await ref.read(gameControllerProvider.notifier).submitMove(
            gameId: _linkedGameId!,
            uci: uci,
            expectedVersion: _linkedGameVersion,
          );
    } catch (err) {
      if (!mounted) return;
      _pendingLocalUci = null;
      _pendingLocalVersion = null;
      setState(() => _syncError = 'Move sync failed. Resyncing...');
      _triggerResync();
    }
  }

  Future<void> _startGameFlow(DeviceModel? device) async {
    final result = await showModalBottomSheet<_PreGameResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBackground,
      builder: (_) => _PreGameSheet(device: device),
    );
    if (result == null) return;

    setState(() {
      _syncing = true;
      _syncError = null;
      _gameUsesBoard = result.useBoard;
      _inGameValidated = result.useBoard; // Board was validated in modal
      _inGameValidationNote = null;
      _selectedSquare = null;
      _legalDestinations = [];
      _snapshotNote = null;
    });
    _autoDetectTimer?.cancel();
    try {
      await ref.read(gameControllerProvider.notifier).createGame(
            mode: result.mode,
            difficulty: result.difficulty,
            players:
                result.useBoard && device != null ? [device.deviceId] : null,
          );
      if (result.useBoard) {
        _fetchLiveFrame();
      } else {
        _clearSnapshot();
        _autoDetectTimer?.cancel();
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _syncError = 'Failed to start game.';
          _gameUsesBoard = false;
        });
        _clearSnapshot();
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  Future<void> _fetchLiveFrame() async {
    if (_livePreviewLoading) return;
    setState(() => _livePreviewLoading = true);
    try {
      final frame = await ref.read(boardRepositoryProvider).capturePreview();
      if (!mounted) return;
      setState(() {
        _liveFrame = frame;
        _livePreviewError = null;
        _livePreviewLoading = false;
      });
    } catch (_) {
      // Fallback: keep preview usable even if calibrated preview endpoint fails.
      try {
        final feed = await ref.read(boardRepositoryProvider).pollCameraFeed();
        if (!mounted) return;
        final imageBase64 = feed['image_base64']?.toString() ?? '';
        final width = int.tryParse(feed['width']?.toString() ?? '') ??
            _liveFrame?.width ??
            0;
        final height = int.tryParse(feed['height']?.toString() ?? '') ??
            _liveFrame?.height ??
            0;
        final status = feed['status']?.toString() ?? '';

        if (imageBase64.isNotEmpty) {
          setState(() {
            _liveFrame = CalibrationFrame(
              imageBase64: imageBase64,
              width: width,
              height: height,
            );
            _livePreviewError = null;
            _livePreviewLoading = false;
          });
          return;
        }

        setState(() {
          _livePreviewError = status == 'not_calibrated'
              ? 'Camera is live, but board is not calibrated yet.'
              : status == 'model_not_ready'
                  ? 'Camera is live, but model is not loaded yet.'
                  : 'Snapshot unavailable.';
          _livePreviewLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _livePreviewError = 'Snapshot unavailable.';
          _livePreviewLoading = false;
        });
      }
    }
  }

  void _clearSnapshot() {
    setState(() {
      _liveFrame = null;
      _livePreviewError = null;
      _livePreviewLoading = false;
      _snapshotNote = null;
    });
  }

  void _startAutoDetect() {
    if (_autoDetectTimer != null) return;
    _autoDetectTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_gameUsesBoard || _snapshotDetecting || _syncing || !_inGameValidated) return;
      _checkAutoDetectReady();
    });
  }

  Future<void> _checkAutoDetectReady() async {
    if (_snapshotDetecting) return;
    try {
      final result = await ref.read(boardRepositoryProvider).checkAutoDetect();
      final data = result['data'] as Map<String, dynamic>? ?? {};
      final ready = data['ready'] == true;
      final reason = data['reason']?.toString() ?? '';
      
      if (ready) {
        // Auto-detect triggered successfully!
        final uci = data['uci']?.toString();
        final san = data['san']?.toString();
        if (uci != null && uci.isNotEmpty) {
          setState(() {
            _snapshotNote = 'Auto-detected: $san ($uci)';
          });

          try {
            final aiResult = await ref.read(boardRepositoryProvider).aiMove();
            final aiData = aiResult['data'] as Map<String, dynamic>? ?? {};
            final aiUci = aiData['uci']?.toString();
            if (aiUci != null && aiUci.isNotEmpty && mounted) {
              setState(() {
                _snapshotNote = 'Auto-detected: $san ($uci). Engine: $aiUci';
              });
            }
          } catch (_) {
            if (mounted) {
              setState(() {
                _snapshotNote = 'Auto-detected: $san ($uci). Engine reply failed.';
              });
            }
          }

          await _fetchLiveFrame();
        }
      }
    } catch (err) {
      // Silently fail on auto-detect check errors
    }
  }

  Future<void> _detectSnapshotMove() async {
    if (_snapshotDetecting) return;
    setState(() {
      _snapshotDetecting = true;
      _snapshotNote = 'Waiting for clear board...';
    });
    try {
      const maxAttempts = 8;
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        final result =
            await ref.read(boardRepositoryProvider).analyzeAndReplySnapshot();
        final data = result['data'] as Map<String, dynamic>? ?? {};
        final humanData = data['human_move'] as Map<String, dynamic>? ?? data;
        final engineData = data['engine_move'] as Map<String, dynamic>?;
        final status = humanData['analysis_status']?.toString() ?? 'unknown';
        final message = humanData['analysis_message']?.toString();
        final reason = humanData['reason']?.toString();
        final retry = humanData['retry'] == true;
        final uci = humanData['uci']?.toString();
        final versionRaw = humanData['game_version'];
        final version = int.tryParse(versionRaw?.toString() ?? '');
        final fallback = humanData['fallback'] == true;

        if (status == 'waiting') {
          if (mounted) {
            setState(() {
              _snapshotNote = message ??
                  (reason == 'hand_present'
                      ? 'Hand detected. Move away to detect.'
                      : 'Hold steady and try again.');
            });
          }
          if (retry && attempt < maxAttempts - 1) {
            await Future.delayed(const Duration(milliseconds: 400));
            continue;
          }
          break;
        }

        if (status == 'red') {
          if (mounted) {
            setState(() {
              _snapshotNote = message ?? 'No legal move matched. Try again.';
            });
          }
          if (retry && attempt < maxAttempts - 1) {
            await Future.delayed(const Duration(milliseconds: 400));
            continue;
          }
          break;
        }

        if (mounted) {
          setState(() {
            if (uci == null || uci.isEmpty) {
              _snapshotNote = message ?? 'Snapshot captured.';
            } else {
              _snapshotNote = message ??
                  (fallback ? 'Move: $uci (stabilized)' : 'Move: $uci');
              if (_gameUsesBoard) {
                final applied = _applyUciMove(uci);
                if (applied && version != null) {
                  _pendingLocalUci = uci;
                  _pendingLocalVersion = version;
                  _linkedGameVersion = version;
                }
              }
            }
          });
        }

        if (_gameUsesBoard && engineData != null) {
          final aiUci = engineData['uci']?.toString();
          if (aiUci != null && aiUci.isNotEmpty && mounted) {
            setState(() {
              final aiApplied = _applyUciMove(aiUci);
              if (aiApplied) {
                final aiVersionRaw = engineData['game_version'];
                final aiVersion = int.tryParse(aiVersionRaw?.toString() ?? '');
                if (aiVersion != null) {
                  _pendingLocalUci = aiUci;
                  _pendingLocalVersion = aiVersion;
                  _linkedGameVersion = aiVersion;
                }
                _snapshotNote =
                    '${_snapshotNote ?? 'Move detected.'} Engine: $aiUci';
              }
            });
          }
        }
        break;
      }
    } catch (err) {
      if (mounted) {
        setState(() => _snapshotNote = 'Snapshot detection failed.');
      }
    } finally {
      if (mounted) {
        setState(() => _snapshotDetecting = false);
      }
      await _fetchLiveFrame();
    }
  }

  Future<void> _validateBoardInGame() async {
    if (_inGameValidating) return;
    setState(() {
      _inGameValidating = true;
      _inGameValidationNote = null;
    });
    try {
      final result = await ref.read(boardRepositoryProvider).validateStart();
      final data = result['data'] as Map<String, dynamic>? ?? {};
      final valid = data['valid'] == true;
      final detected = data['pieces_detected'] as int? ?? 0;
      final summary = data['summary'] as Map<String, dynamic>? ?? {};
      final missing = summary['missing'] as int? ?? 0;
      final extra = summary['extra'] as int? ?? 0;
      final wrongColor = summary['wrong_color'] as int? ?? 0;
      final parts = <String>[];
      if (missing > 0) parts.add('$missing missing');
      if (extra > 0) parts.add('$extra extra');
      if (wrongColor > 0) parts.add('$wrongColor wrong color');
      final note = valid
          ? 'Position valid. ($detected/32 pieces detected)'
          : 'Detected $detected/32 pieces. Issues: ${parts.join(', ')}.';
      setState(() {
        _inGameValidated = valid;
        _inGameValidationNote = note;
        _inGameValidating = false;
      });
      // Manual validation no longer auto-starts detection.
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _inGameValidationNote = 'Validation failed. Check backend.';
        _inGameValidating = false;
      });
    }
  }

  Future<void> _forceValidateInGame() async {
    if (_inGameValidating) return;
    setState(() {
      _inGameValidating = true;
      _inGameValidationNote = null;
    });
    try {
      await ref.read(boardRepositoryProvider).forceValidate();
      if (!mounted) return;
      setState(() {
        _inGameValidated = true;
        _inGameValidationNote =
            'Force validated. Using assumed initial position.';
        _inGameValidating = false;
      });
      // Manual force-validate does not auto-start detection.
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _inGameValidationNote = 'Force validate failed. Check backend.';
        _inGameValidating = false;
      });
    }
  }

  // ── Undo last move ──
  Future<void> _undoMove() async {
    if (_game.history.isEmpty && _linkedGameId == null) return;

    // Optimistically undo local state, then let server dictate final state
    _game.undo();

    if (_linkedGameId != null) {
      try {
        await ref.read(gameControllerProvider.notifier).undoMove();
      } catch (e) {
        if (!mounted) return;
        setState(() => _syncError = 'Failed to undo move.');
      }
    } else {
      if (_moveHistory.isNotEmpty) {
        final last = _moveHistory.last;
        if (last[2] != null) {
          _moveHistory.last[2] = null;
        } else {
          _moveHistory.removeLast();
        }
      }
      setState(() {
        _selectedSquare = null;
        _legalDestinations = [];
        _lastMoveFrom = null;
        _lastMoveTo = null;
        _updateStatusMessage();
      });
    }
  }

  void _updateStatusMessage() {
    if (_game.in_checkmate) {
      _statusMessage = 'Checkmate!';
    } else if (_game.in_stalemate) {
      _statusMessage = 'Stalemate — Draw!';
    } else if (_game.in_draw) {
      _statusMessage = 'Draw!';
    } else if (_game.in_check) {
      _statusMessage = 'Check!';
    } else {
      _statusMessage =
          _game.turn == chess.Color.WHITE ? 'White to move' : 'Black to move';
    }
  }

  bool _applyUciMove(String uci) {
    if (uci.length < 4) return false;
    final from = uci.substring(0, 2);
    final to = uci.substring(2, 4);
    final promotion = uci.length > 4 ? uci.substring(4, 5) : null;

    final moveResult = _game.move({
      'from': from,
      'to': to,
      if (promotion != null) 'promotion': promotion,
    });

    if (moveResult != true) {
      return false;
    }

    final undoInfo = _game.undo();
    final san = undoInfo?['san'] as String? ?? '$from$to';
    _game.move({
      'from': from,
      'to': to,
      if (promotion != null) 'promotion': promotion,
    });

    _recordMoveHistory(san);

    _selectedSquare = null;
    _legalDestinations = [];
    _lastMoveFrom = from;
    _lastMoveTo = to;
    _updateStatusMessage();
    return true;
  }

  void _recordMoveHistory(String san) {
    final moveNumber = (_game.move_number).toString();
    if (_game.turn == chess.Color.BLACK) {
      _moveHistory.add([moveNumber, san, null]);
    } else {
      if (_moveHistory.isNotEmpty) {
        _moveHistory.last[2] = san;
      } else {
        _moveHistory.add([moveNumber, null, san]);
      }
    }
  }

  void _resetBoardFromFen(String fen) {
    final loaded = _game.load(fen);
    if (!loaded) {
      _syncError = 'Failed to load game state.';
      return;
    }
    _moveHistory.clear();
    _selectedSquare = null;
    _legalDestinations = [];
    _lastMoveFrom = null;
    _lastMoveTo = null;
    _updateStatusMessage();
  }

  void _applyGameState(GameStateModel state) {
    if (state.currentFen.isEmpty) return;
    setState(() {
      _resetBoardFromFen(state.currentFen);
      _linkedGameVersion = state.gameVersion;
      _pendingLocalUci = null;
      _pendingLocalVersion = null;
      _syncError = null;
    });
  }

  void _connectGameSocket(String gameId) {
    if (_wsGameId == gameId) return;
    _wsGameId = gameId;
    _gameWsSub?.cancel();
    final socket = ref.read(gameSocketProvider);
    socket.connect(gameId: gameId, lastKnownVersion: _linkedGameVersion);
    _gameWsSub = socket.stream.listen(_handleGameSocketMessage, onError: (_) {
      if (!mounted) return;
      setState(() => _syncError = 'Connection lost. Reconnecting...');
      _triggerResync();
    });
  }

  void _handleGameSocketMessage(Map<String, dynamic> message) {
    final type = message['type'];
    final data = message['data'];
    if (type == 'game.move' && data is Map<String, dynamic>) {
      final uci = data['uci']?.toString();
      final version = int.tryParse(data['game_version']?.toString() ?? '');
      final fen = data['fen']?.toString();
      if (uci == null || uci.isEmpty) return;

      if (_pendingLocalUci == uci &&
          version != null &&
          _pendingLocalVersion == version) {
        setState(() {
          _linkedGameVersion = version;
          _pendingLocalUci = null;
          _pendingLocalVersion = null;
        });
        return;
      }

      final applied = _applyUciMove(uci);
      setState(() {
        if (!applied && fen != null && fen.isNotEmpty) {
          _resetBoardFromFen(fen);
        } else if (!applied) {
          _syncError = 'Out of sync. Resyncing...';
          _triggerResync();
        }
        if (version != null) {
          _linkedGameVersion = version;
        }
        _snapshotNote = 'Engine move: $uci';
      });
      return;
    }

    if (type == 'game.delta' && data is Map<String, dynamic>) {
      final moves = data['moves'];
      final toVersion = int.tryParse(data['to_version']?.toString() ?? '');
      if (moves is List) {
        var appliedAll = true;
        for (final entry in moves) {
          if (entry is! Map<String, dynamic>) continue;
          final uci = entry['uci']?.toString();
          final fen = entry['fen_after']?.toString();
          final moveNumber =
              int.tryParse(entry['move_number']?.toString() ?? '');
          if (uci == null || uci.isEmpty) continue;
          if (_pendingLocalUci == uci &&
              moveNumber != null &&
              _pendingLocalVersion == moveNumber) {
            _pendingLocalUci = null;
            _pendingLocalVersion = null;
            continue;
          }
          final applied = _applyUciMove(uci);
          if (!applied) {
            appliedAll = false;
            if (fen != null && fen.isNotEmpty) {
              _resetBoardFromFen(fen);
            }
          }
        }
        setState(() {
          if (!appliedAll) {
            _syncError = 'Delta sync had conflicts.';
          } else {
            _syncError = null;
          }
          if (toVersion != null) {
            _linkedGameVersion = toVersion;
          }
          if (moves.isNotEmpty) {
            final last = moves.last;
            if (last is Map<String, dynamic>) {
              final uci = last['uci']?.toString();
              if (uci != null && uci.isNotEmpty) {
                _snapshotNote = 'Engine move: $uci';
              }
            }
          }
        });
      }
      return;
    }

    if (type == 'game.state' && data is Map<String, dynamic>) {
      final state = GameStateModel.fromJson(data);
      _applyGameState(state);
      return;
    }

    if (type == 'game.up_to_date' && data is Map<String, dynamic>) {
      final version = int.tryParse(data['game_version']?.toString() ?? '');
      if (version != null && mounted) {
        setState(() => _linkedGameVersion = version);
      }
      return;
    }

    if (type == 'error') {
      final messageText = message['message']?.toString() ?? 'Websocket error.';
      if (mounted) {
        setState(() => _syncError = messageText);
      }
    }
  }

  void _triggerResync() {
    final gameId = _linkedGameId;
    if (gameId == null) return;
    ref.read(gameSocketProvider).resync(
          gameId: gameId,
          lastKnownVersion: _linkedGameVersion,
        );
    ref.read(gameControllerProvider.notifier).refresh(gameId);
  }

  // ── Handle voice result ──
  void _handleVoiceResult(String text) {
    final result = parseMove(text, _game);
    if (!mounted) return;

    if (result.isSuccess) {
      if (result.isCommand) {
        setState(() => _lastParsedMove = '⚡ ${result.uci}');
        if (result.uci == 'UNDO') _undoMove();
        return;
      }
      // Try to make the move on the board
      final uci = result.uci!;
      if (uci.length >= 4) {
        final from = uci.substring(0, 2);
        final to = uci.substring(2, 4);
        _makeMove(from, to);
        setState(() =>
            _lastParsedMove = '♟ ${from.toUpperCase()} → ${to.toUpperCase()}');
      }
    } else {
      setState(() => _lastParsedMove = '⚠ ${result.error}');
    }
  }

  void _onMicToggle(bool value) async {
    setState(() => _micActive = value);
    if (value) {
      await _voiceService.startListening();
    } else {
      await _voiceService.stopListening();
      setState(() => _lastParsedMove = null);
    }
  }

  Future<void> _loadMicDevices() async {
    if (_micDevicesLoading) return;
    setState(() => _micDevicesLoading = true);

    final devices = await _voiceService.getAvailableMicrophones();
    if (!mounted) return;

    MicInputDevice? selected;
    for (final device in devices) {
      if (device.isSelected) {
        selected = device;
        break;
      }
    }
    selected ??= devices.isNotEmpty ? devices.first : null;

    setState(() {
      _micDevices = devices;
      _selectedMicId = selected?.id;
      _micDevicesLoading = false;
    });
  }

  Future<void> _selectMicDevice(MicInputDevice device) async {
    setState(() {
      _selectedMicId = device.id;
      _micDropdownOpen = false;
      _voiceStatus = 'Switching to ${device.name}...';
    });
    await _voiceService.selectMicrophone(device);
    await _loadMicDevices();
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceListProvider).valueOrNull ?? [];
    final selectedId = ref.watch(selectedDeviceProvider);
    final activeDevice = _resolveActiveDevice(devices, selectedId);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Row(children: [
          const Icon(Icons.settings_remote, color: kPrimary),
          const SizedBox(width: 10),
          Text('ROBOCHESS',
              style: GoogleFonts.spaceGrotesk(
                  color: kPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 2)),
        ]),
        actions: [
          const AnimatedProfileAvatar(size: 34),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        child: Column(children: [
          _BoardSyncCard(
            device: activeDevice,
            linkedGameId: _linkedGameId,
            syncing: _syncing,
            error: _syncError,
            onStart: () => _startGameFlow(activeDevice),
            onLink: () => context.go('/connect'),
          ),
          const SizedBox(height: 16),
          _PlayerRow(game: _game),
          const SizedBox(height: 16),

          // ── Status message ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: kSurfaceContHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_statusMessage,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        _statusMessage.contains('Check') ? kError : kPrimary)),
          ),

          if (_gameUsesBoard && _linkedGameId != null) ...[
            const SizedBox(height: 12),
            _buildLiveBoardPreview(),
          ],

          // ── Board ──
          _buildChessBoard(context),

          const SizedBox(height: 20),
          _MoveHistoryCard(history: _moveHistory),
          const SizedBox(height: 12),
          _AIInsightCard(game: _game),
          const SizedBox(height: 16),
          _GameControls(
            onUndo: _undoMove,
            onAnalyze: _linkedGameId != null
                ? () => context.go('/analysis?game_id=$_linkedGameId')
                : null,
          ),
          const SizedBox(height: 12),
          _VoiceCommandButton(
            expanded: _voiceExpanded,
            micActive: _micActive,
            voiceStatus: _voiceStatus,
            lastParsedMove: _lastParsedMove,
            micDevices: _micDevices,
            selectedMicId: _selectedMicId,
            micDevicesLoading: _micDevicesLoading,
            micDropdownOpen: _micDropdownOpen,
            onToggle: () => setState(() => _voiceExpanded = !_voiceExpanded),
            onMicToggle: _onMicToggle,
            onRefreshMics: _loadMicDevices,
            onMicSelected: _selectMicDevice,
            onMicDropdownToggle: () =>
                setState(() => _micDropdownOpen = !_micDropdownOpen),
          ),
        ]),
      ),
    );
  }

  Widget _buildLiveBoardPreview() {
    final frame = _liveFrame;
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceContHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOutlineVariant.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('BOARD SNAPSHOT',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: kOnSurfaceVariant,
                      letterSpacing: 2)),
              const Spacer(),
              TextButton.icon(
                onPressed: (_snapshotDetecting || _livePreviewLoading)
                    ? null
                    : _detectSnapshotMove,
                icon: const Icon(Icons.camera_alt, size: 14),
                label: Text(
                    _snapshotDetecting ? 'DETECTING...' : 'DETECT WHEN CLEAR',
                    style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                style: TextButton.styleFrom(
                  foregroundColor: kPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: frame != null && frame.height != 0
                ? frame.width / frame.height
                : 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: frame == null
                            ? Container(
                                color: kSurfaceContLow,
                                child: Center(
                                  child: Text(
                                    _livePreviewLoading
                                        ? 'Capturing snapshot...'
                                        : 'No snapshot yet',
                                    style: GoogleFonts.inter(
                                        fontSize: 11, color: kOnSurfaceVariant),
                                  ),
                                ),
                              )
                            : Image.memory(
                                frame.bytes,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                      ),
                      if (_livePreviewLoading)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black26,
                            child: const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: kPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (_livePreviewError != null) ...[
            const SizedBox(height: 8),
            Text(_livePreviewError!,
                style: GoogleFonts.inter(fontSize: 11, color: kError)),
          ],
          if (_snapshotNote != null) ...[
            const SizedBox(height: 6),
            Text(_snapshotNote!,
                style:
                    GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _buildBoardValidationActions() {
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOutlineVariant.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('BOARD VALIDATION',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: kOnSurfaceVariant,
                      letterSpacing: 2)),
              const Spacer(),
              if (_inGameValidated)
                const Icon(Icons.check_circle, color: kPrimary, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _inGameValidating ? null : _validateBoardInGame,
                  icon: const Icon(Icons.verified, size: 14),
                  label: Text('VALIDATE',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kOnSurface,
                    side: BorderSide(color: kOnSurfaceVariant.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _inGameValidating ? null : _forceValidateInGame,
                  icon: const Icon(Icons.flash_on, size: 14),
                  label: Text('FORCE VALIDATE',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kSecondary,
                    side: BorderSide(color: kSecondary.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          if (_inGameValidationNote != null) ...[
            const SizedBox(height: 8),
            Text(_inGameValidationNote!,
                style:
                    GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  // ── Interactive board builder ──
  Widget _buildChessBoard(BuildContext context) {
    final inputEnabled = !_gameUsesBoard;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: kSurfaceContHighest,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: kPrimary.withOpacity(0.05),
                blurRadius: 40,
                spreadRadius: 10)
          ],
        ),
        padding: const EdgeInsets.all(6),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8),
          itemCount: 64,
          itemBuilder: (_, idx) {
            final row = idx ~/ 8;
            final col = idx % 8;
            final squareName = _squareName(row, col);
            final isLight = (row + col) % 2 == 0;
            final piece = _game.get(squareName);

            // Highlighting
            final isSelected = inputEnabled && squareName == _selectedSquare;
            final isLegalDest =
                inputEnabled && _legalDestinations.contains(squareName);
            final isLastMove =
                squareName == _lastMoveFrom || squareName == _lastMoveTo;

            Color bgColor;
            if (isSelected) {
              bgColor = kPrimary.withOpacity(0.35);
            } else if (isLastMove) {
              bgColor = kPrimary.withOpacity(0.15);
            } else {
              bgColor = isLight ? kSurfaceContHigh : kSurfaceContLow;
            }

            return GestureDetector(
              onTap: inputEnabled ? () => _onSquareTap(row, col) : null,
              child: Container(
                decoration: BoxDecoration(color: bgColor),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Legal move dot
                    if (isLegalDest && piece == null)
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kPrimary.withOpacity(0.4),
                        ),
                      ),
                    // Legal capture ring
                    if (isLegalDest && piece != null)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: kPrimary.withOpacity(0.6), width: 3),
                        ),
                      ),
                    // Piece
                    if (piece != null)
                      Text(
                        _pieceSymbols[piece.type.toString().toLowerCase()] ??
                            '',
                        style: TextStyle(
                          fontSize: 24,
                          color: piece.color == chess.Color.WHITE
                              ? kPrimary
                              : kSecondary,
                          shadows: [
                            Shadow(
                              color: (piece.color == chess.Color.WHITE
                                      ? kPrimary
                                      : kSecondary)
                                  .withOpacity(0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    // Rank/file labels
                    if (col == 0)
                      Positioned(
                        top: 1,
                        left: 2,
                        child: Text('${8 - row}',
                            style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w700,
                                color: isLight
                                    ? kSurfaceContLow
                                    : kSurfaceContHigh)),
                      ),
                    if (row == 7)
                      Positioned(
                        bottom: 1,
                        right: 2,
                        child: Text(
                            String.fromCharCode('a'.codeUnitAt(0) + col),
                            style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w700,
                                color: isLight
                                    ? kSurfaceContLow
                                    : kSurfaceContHigh)),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
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

class _BoardSyncCard extends StatelessWidget {
  final DeviceModel? device;
  final String? linkedGameId;
  final bool syncing;
  final String? error;
  final VoidCallback? onStart;
  final VoidCallback onLink;

  const _BoardSyncCard({
    required this.device,
    required this.linkedGameId,
    required this.syncing,
    required this.error,
    required this.onStart,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.router, color: kSecondary, size: 18),
              const SizedBox(width: 8),
              Text('ACTIVE BOARD',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface)),
              const Spacer(),
              if (device == null)
                TextButton(
                  onPressed: onLink,
                  child: Text('LINK BOARD',
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: kPrimary,
                          letterSpacing: 1)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(device?.deviceId ?? 'No board selected',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kOnSurfaceVariant)),
          if (linkedGameId != null) ...[
            const SizedBox(height: 6),
            Text('SYNCED GAME: $linkedGameId',
                style:
                    GoogleFonts.inter(fontSize: 10, color: kOnSurfaceVariant)),
          ],
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(error!, style: GoogleFonts.inter(fontSize: 11, color: kError)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: syncing ? null : onStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: kOnPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(syncing ? 'SYNCING...' : 'NEW GAME',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2)),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PlaySurface { board, app }

enum _OpponentType { bot, friend }

class _PreGameResult {
  final String mode;
  final int difficulty;
  final bool useBoard;

  const _PreGameResult({
    required this.mode,
    required this.difficulty,
    required this.useBoard,
  });
}

class _PreGameSheet extends ConsumerStatefulWidget {
  final DeviceModel? device;
  const _PreGameSheet({this.device});

  @override
  ConsumerState<_PreGameSheet> createState() => _PreGameSheetState();
}

class _PreGameSheetState extends ConsumerState<_PreGameSheet> {
  _PlaySurface _surface = _PlaySurface.board;
  _OpponentType _opponent = _OpponentType.bot;
  int _difficulty = 5;
  bool _modelLoaded = false;
  bool _calibrated = false;
  bool _validated = false;
  bool _busy = false;
  String? _error;
  String? _validationNote;

  @override
  void initState() {
    super.initState();
    if (widget.device == null) {
      _surface = _PlaySurface.app;
    }
  }

  Future<void> _runStep(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (err) {
      setState(() => _error = err.message);
    } catch (err) {
      setState(() => _error = 'Step failed. Check backend connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadModel() async {
    await _runStep(() async {
      await ref.read(boardRepositoryProvider).loadModel(
            modelPath: AppConfig.boardModelRef,
          );
      setState(() => _modelLoaded = true);
    });
  }

  Future<void> _autoCalibrate() async {
    await _runStep(() async {
      await ref.read(boardRepositoryProvider).autoCalibrate();
      setState(() {
        _calibrated = true;
        _validated = false;
      });
    });
  }

  Future<void> _manualCalibrate() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ManualCalibrationScreen()),
    );
    if (ok == true) {
      setState(() {
        _calibrated = true;
        _validated = false;
      });
    }
  }

  Future<void> _validateBoard() async {
    if (_busy) return; // Prevent multiple simultaneous validations
    await _runStep(() async {
      final result = await ref.read(boardRepositoryProvider).validateStart();
      final data = result['data'] as Map<String, dynamic>? ?? {};
      final valid = data['valid'] == true;
      final detected = data['pieces_detected'] as int? ?? 0;
      final summary = data['summary'] as Map<String, dynamic>? ?? {};
      final missing = summary['missing'] as int? ?? 0;
      final extra = summary['extra'] as int? ?? 0;
      final wrongColor = summary['wrong_color'] as int? ?? 0;
      
      if (!mounted) return;
      
      setState(() {
        _validated = valid;
        if (valid) {
          _validationNote = 'Position valid ✓  ($detected/32 pieces detected)';
        } else {
          final parts = <String>[];
          if (missing > 0) parts.add('$missing missing');
          if (extra > 0) parts.add('$extra extra');
          if (wrongColor > 0) parts.add('$wrongColor wrong color');
          _validationNote =
              'Detected $detected/32 pieces. Issues: ${parts.join(', ')}.\n'
              'Tip: ${wrongColor > 0 ? "Re-calibrate — board orientation may be flipped." : "Ensure all pieces are placed and lighting is good."}';
        }
      });
    });
  }

  Future<void> _forceValidate() async {
    await _runStep(() async {
      await ref.read(boardRepositoryProvider).forceValidate();
      setState(() {
        _validated = true;
        _validationNote = 'Force-validated: Using assumed initial position.';
      });
    });
  }

  Future<void> _debugCalibration() async {
    await _runStep(() async {
      final result = await ref.read(boardRepositoryProvider).debugCalibration();
      final data = result['data'] as Map<String, dynamic>? ?? {};
      final total = data['raw_detections_total'];
      final tip = data['tip'];
      setState(() {
        _validationNote = 'Diagnostic: $total raw detections.\n$tip';
      });
    });
  }

  String _resolveMode() {
    if (_opponent == _OpponentType.friend) return 'human_vs_human';
    return _surface == _PlaySurface.board ? 'phone_vs_board' : 'human_vs_ai';
  }

  Future<void> _startGame() async {
    final useBoard = _surface == _PlaySurface.board;
    if (useBoard && !_validated) {
      await _validateBoard();
      if (!_validated) return;
    }
    final mode = _resolveMode();
    Navigator.of(context).pop(
      _PreGameResult(mode: mode, difficulty: _difficulty, useBoard: useBoard),
    );
  }

  @override
  Widget build(BuildContext context) {
    final useBoard = _surface == _PlaySurface.board;
    final ready = !useBoard || (_modelLoaded && _calibrated);
    final needsValidation = useBoard && !_validated;
    final startLabel = !ready
        ? 'COMPLETE SETUP'
        : needsValidation
            ? 'RUN VALIDATION & START'
            : 'START GAME';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prepare Game',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: kOnSurface)),
            const SizedBox(height: 12),
            _OptionRow(
              title: 'Opponent',
              options: const ['Bot', 'Friend'],
              selectedIndex: _opponent == _OpponentType.bot ? 0 : 1,
              onSelect: (index) => setState(() {
                _opponent =
                    index == 0 ? _OpponentType.bot : _OpponentType.friend;
              }),
            ),
            if (_opponent == _OpponentType.bot) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Engine Level',
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: kOnSurface)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: kSurfaceContHighest,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('Level $_difficulty',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: kPrimary,
                            letterSpacing: 1)),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: kPrimary,
                  inactiveTrackColor: kSurfaceContHighest,
                  thumbColor: kPrimary,
                  overlayColor: kPrimary.withOpacity(0.2),
                  trackHeight: 4,
                  valueIndicatorTextStyle:
                      GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
                child: Slider(
                  value: _difficulty.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: _difficulty.toString(),
                  onChanged: (val) => setState(() => _difficulty = val.toInt()),
                ),
              ),
            ],
            const SizedBox(height: 10),
            _OptionRow(
              title: 'Play on',
              options: const ['Board', 'App'],
              selectedIndex: _surface == _PlaySurface.board ? 0 : 1,
              disabledIndices: widget.device == null ? [0] : [],
              onSelect: (index) => setState(() {
                _surface = index == 0 ? _PlaySurface.board : _PlaySurface.app;
              }),
            ),
            if (useBoard) ...[
              const SizedBox(height: 14),
              Text('Board Setup',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kOnSurfaceVariant,
                      letterSpacing: 2)),
              const SizedBox(height: 8),
              _StepTile(
                title: 'Load Detection Model',
                done: _modelLoaded,
                busy: _busy,
                onTap: _modelLoaded ? null : _loadModel,
              ),
              _StepTile(
                title: 'Auto Calibration',
                done: _calibrated,
                busy: _busy,
                onTap: _modelLoaded ? _autoCalibrate : null,
              ),
              _StepTile(
                title: 'Manual Calibration (Optional)',
                done: _calibrated,
                busy: _busy,
                onTap: _modelLoaded ? _manualCalibrate : null,
              ),
              _StepTile(
                title: 'Validate Start Position',
                done: _validated,
                busy: _busy,
                onTap: _calibrated ? _validateBoard : null,
              ),
              if (_validationNote != null) ...[
                const SizedBox(height: 6),
                Text(_validationNote!,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: kOnSurfaceVariant)),
                if (!_validated && _calibrated) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _debugCalibration,
                          icon: const Icon(Icons.bug_report, size: 14),
                          label: Text('DIAGNOSTICS',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kOnSurface,
                            side: BorderSide(
                                color: kOnSurfaceVariant.withOpacity(0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _forceValidate,
                          icon: const Icon(Icons.flash_on, size: 14),
                          label: Text('FORCE PROCEED',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kSecondary,
                            side:
                                BorderSide(color: kSecondary.withOpacity(0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: GoogleFonts.inter(fontSize: 12, color: kError)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy || !ready ? null : _startGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: kOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(startLabel,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String title;
  final List<String> options;
  final int selectedIndex;
  final List<int> disabledIndices;
  final ValueChanged<int> onSelect;

  const _OptionRow({
    required this.title,
    required this.options,
    required this.selectedIndex,
    this.disabledIndices = const [],
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kOnSurfaceVariant)),
        ),
        ...options.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          final selected = index == selectedIndex;
          final disabled = disabledIndices.contains(index);
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: OutlinedButton(
              onPressed: disabled ? null : () => onSelect(index),
              style: OutlinedButton.styleFrom(
                backgroundColor:
                    selected ? kPrimary.withOpacity(0.2) : kSurfaceContHighest,
                side: BorderSide(
                    color:
                        selected ? kPrimary : kOutlineVariant.withOpacity(0.2)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(label.toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: selected ? kPrimary : kOnSurfaceVariant,
                      letterSpacing: 1)),
            ),
          );
        }),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  final String title;
  final bool done;
  final bool busy;
  final VoidCallback? onTap;

  const _StepTile({
    required this.title,
    required this.done,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? kPrimary : kOnSurfaceVariant, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kOnSurface)),
          ),
          TextButton(
            onPressed: busy ? null : onTap,
            child: Text(done ? 'DONE' : 'RUN',
                style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: done ? kPrimary : kSecondary,
                    letterSpacing: 1)),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final chess.Chess game;
  const _PlayerRow({required this.game});

  @override
  Widget build(BuildContext context) {
    final isWhiteTurn = game.turn == chess.Color.WHITE;

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: kSurfaceContLow,
            borderRadius: BorderRadius.circular(14),
            border:
                const Border(left: BorderSide(color: kSecondary, width: 4))),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: kSecondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.smart_toy, color: kSecondary, size: 20)),
          const SizedBox(width: 10),
          Text('AI LEVEL 8',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kOnSurface)),
          const Spacer(),
          Text(isWhiteTurn ? 'WAITING' : 'TO MOVE',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isWhiteTurn ? kOnSurfaceVariant : kSecondary,
                  letterSpacing: 2)),
        ]),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: kSurfaceContLow,
            borderRadius: BorderRadius.circular(14),
            border: const Border(right: BorderSide(color: kPrimary, width: 4))),
        child: Row(children: [
          Text(isWhiteTurn ? 'TO MOVE' : 'WAITING',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isWhiteTurn ? kPrimary : kOnSurfaceVariant,
                  letterSpacing: 2)),
          const Spacer(),
          Text('PLAYER_ONE',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kOnSurface)),
          const SizedBox(width: 10),
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.person, color: kPrimary, size: 20)),
        ]),
      ),
    ]);
  }
}

class _MoveHistoryCard extends StatelessWidget {
  final List<List<String?>> history;
  const _MoveHistoryCard({required this.history});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: kSurfaceContLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kOutlineVariant.withOpacity(0.1))),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('MOVE HISTORY',
              style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: kOnSurfaceVariant,
                  letterSpacing: 2)),
          const Spacer(),
          Text('${history.length} moves',
              style: GoogleFonts.inter(fontSize: 10, color: kOnSurfaceVariant)),
        ]),
        const SizedBox(height: 12),
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text('No moves yet — make your first move!',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: kOnSurfaceVariant,
                      fontStyle: FontStyle.italic)),
            ),
          ),
        ...history.asMap().entries.map((e) {
          final isActive = e.key == history.length - 1;
          final m = e.value;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
                color:
                    isActive ? kPrimary.withOpacity(0.05) : Colors.transparent,
                borderRadius: isActive ? BorderRadius.circular(8) : null),
            child: Row(children: [
              SizedBox(
                  width: 28,
                  child: Text('${m[0]}.',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: kOnSurfaceVariant))),
              Expanded(
                  child: Text(m[1] ?? '',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isActive ? kPrimary : kOnSurface))),
              Expanded(
                  child: Text(m[2] ?? (isActive ? '...' : ''),
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: kOnSurface,
                          fontStyle: isActive && m[2] == null
                              ? FontStyle.italic
                              : FontStyle.normal))),
            ]),
          );
        }),
      ]),
    );
  }
}

class _PositionInsight {
  final String headline;
  final String detail;
  final String candidateMove;
  final String evaluation;
  final int legalMoves;
  final Color accentColor;

  const _PositionInsight({
    required this.headline,
    required this.detail,
    required this.candidateMove,
    required this.evaluation,
    required this.legalMoves,
    required this.accentColor,
  });
}

class _CandidateMove {
  final String san;
  final int score;

  const _CandidateMove({required this.san, required this.score});
}

class _AIInsightCard extends StatelessWidget {
  final chess.Chess game;

  const _AIInsightCard({required this.game});

  static const _pieceValues = {
    'p': 100,
    'n': 320,
    'b': 330,
    'r': 500,
    'q': 900,
    'k': 0,
  };

  @override
  Widget build(BuildContext context) {
    final insight = _buildInsight(game);

    return Container(
      decoration: BoxDecoration(
          color: kSurfaceContHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kOutlineVariant.withOpacity(0.1))),
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.bolt, color: insight.accentColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('LIVE AI INSIGHT',
                style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: insight.accentColor,
                    letterSpacing: 2)),
            const Spacer(),
            Text(insight.evaluation,
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: kOnSurface,
                    letterSpacing: 1)),
          ]),
          const SizedBox(height: 6),
          Text(insight.headline,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kOnSurface)),
          const SizedBox(height: 5),
          Text(insight.detail,
              style: GoogleFonts.inter(
                  fontSize: 13, color: kOnSurfaceVariant, height: 1.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InsightChip(
                label: 'Candidate',
                value: insight.candidateMove,
                color: insight.accentColor,
              ),
              _InsightChip(
                label: 'Legal Moves',
                value: '${insight.legalMoves}',
                color: kSecondary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Heuristic only, updates from the current legal board state.',
              style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: kOnSurfaceVariant,
                  letterSpacing: 1)),
        ])),
      ]),
    );
  }

  _PositionInsight _buildInsight(chess.Chess source) {
    final legalMoves = source.generate_moves();
    final sideToMove = source.turn == chess.Color.WHITE ? 'White' : 'Black';
    final material = _materialScore(source);
    final evaluation = _formatEvaluation(material);

    if (source.in_checkmate) {
      final winner = source.turn == chess.Color.WHITE ? 'Black' : 'White';
      return _PositionInsight(
        headline: 'Checkmate. $winner wins.',
        detail: 'The side to move has no legal escape from check.',
        candidateMove: 'None',
        evaluation: evaluation,
        legalMoves: legalMoves.length,
        accentColor: kError,
      );
    }

    if (source.in_stalemate || source.in_draw) {
      return _PositionInsight(
        headline: 'Drawn position detected.',
        detail: source.in_stalemate
            ? 'The side to move is not in check but has no legal move.'
            : 'The current position satisfies the chess package draw rules.',
        candidateMove: 'None',
        evaluation: evaluation,
        legalMoves: legalMoves.length,
        accentColor: kOnSurfaceVariant,
      );
    }

    final candidate = _bestCandidate(source, legalMoves);
    final status =
        source.in_check ? '$sideToMove is in check' : '$sideToMove to move';
    final materialText = material == 0
        ? 'Material is balanced'
        : material > 0
            ? 'White is ahead by ${_formatPawnUnits(material)}'
            : 'Black is ahead by ${_formatPawnUnits(-material)}';
    final detail = source.in_check
        ? 'Priority is king safety. The suggested candidate is the highest-scoring legal escape from this one-ply evaluator.'
        : '$materialText, with ${legalMoves.length} legal replies available. Candidate move is selected by material, checks, and immediate mate threats.';

    return _PositionInsight(
      headline: status,
      detail: detail,
      candidateMove: candidate?.san ?? 'None',
      evaluation: evaluation,
      legalMoves: legalMoves.length,
      accentColor: source.in_check ? kError : kSecondary,
    );
  }

  _CandidateMove? _bestCandidate(chess.Chess source, List<dynamic> legalMoves) {
    if (legalMoves.isEmpty) return null;

    final side = source.turn;
    _CandidateMove? best;

    for (final move in legalMoves) {
      final candidateGame = source.copy();
      final san = candidateGame.move_to_san(move);
      candidateGame.move({
        'from': move.fromAlgebraic,
        'to': move.toAlgebraic,
        if (move.promotion != null) 'promotion': move.promotion.toString(),
      });

      final sideMultiplier = side == chess.Color.WHITE ? 1 : -1;
      var score = _materialScore(candidateGame) * sideMultiplier;
      if (candidateGame.in_checkmate) score += 100000;
      if (candidateGame.in_check) score += 35;

      final candidate = _CandidateMove(san: san, score: score);
      if (best == null || candidate.score > best.score) {
        best = candidate;
      }
    }

    return best;
  }

  int _materialScore(chess.Chess source) {
    var score = 0;
    for (var fileIndex = 0; fileIndex < 8; fileIndex++) {
      final file = String.fromCharCode('a'.codeUnitAt(0) + fileIndex);
      for (var rank = 1; rank <= 8; rank++) {
        final piece = source.get('$file$rank');
        if (piece == null) continue;

        final value = _pieceValues[piece.type.toString()] ?? 0;
        score += piece.color == chess.Color.WHITE ? value : -value;
      }
    }
    return score;
  }

  String _formatEvaluation(int centipawns) {
    if (centipawns == 0) return 'EVAL 0.0';
    final pawns = (centipawns.abs() / 100).toStringAsFixed(1);
    return centipawns > 0 ? 'EVAL +$pawns' : 'EVAL -$pawns';
  }

  String _formatPawnUnits(int centipawns) {
    final pawns = centipawns / 100;
    final label = pawns == 1 ? 'pawn' : 'pawns';
    return '${pawns.toStringAsFixed(1)} $label';
  }
}

class _InsightChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InsightChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(fontSize: 10, color: kOnSurfaceVariant),
          children: [
            TextSpan(
              text: '${label.toUpperCase()}: ',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameControls extends StatelessWidget {
  final VoidCallback? onUndo;
  final VoidCallback? onAnalyze;
  const _GameControls({this.onUndo, this.onAnalyze});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _ControlBtn(
          icon: Icons.undo, label: 'Undo', color: kOnSurface, onTap: onUndo),
      const SizedBox(width: 12),
      _ControlBtn(
          icon: Icons.analytics,
          label: 'Analyze',
          color: kSecondary,
          onTap: onAnalyze),
      const SizedBox(width: 12),
      _ControlBtn(icon: Icons.flag, label: 'Resign', color: kError),
      const SizedBox(width: 12),
      _ControlBtn(icon: Icons.handshake, label: 'Draw', color: kOnSurface),
    ]);
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ControlBtn(
      {required this.icon,
      required this.label,
      required this.color,
      this.onTap});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: kSurfaceContHighest.withOpacity(0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kOutlineVariant.withOpacity(0.1))),
          child: Column(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(label.toUpperCase(),
                style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 2)),
          ]),
        ),
      ),
    );
  }
}

class _MicInputPicker extends StatelessWidget {
  final List<MicInputDevice> devices;
  final int? selectedMicId;
  final bool loading;
  final bool dropdownOpen;
  final VoidCallback onRefresh;
  final VoidCallback onToggleDropdown;
  final ValueChanged<MicInputDevice> onSelected;

  const _MicInputPicker({
    required this.devices,
    required this.selectedMicId,
    required this.loading,
    required this.dropdownOpen,
    required this.onRefresh,
    required this.onToggleDropdown,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selectedDevice = _selectedDevice;
    final selectorLabel = loading
        ? 'Scanning microphones...'
        : selectedDevice?.name ??
            (devices.isEmpty
                ? 'System default microphone'
                : devices.first.name);
    final selectorSubLabel = selectedDevice?.type ??
        (devices.isEmpty
            ? 'No selectable inputs found'
            : '${devices.length} inputs available');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: kSurfaceContLow.withOpacity(0.7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kOutlineVariant.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_voice, color: kSecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Microphone source',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kOnSurface)),
                ),
                GestureDetector(
                  onTap: loading ? null : onRefresh,
                  child: Icon(
                    Icons.refresh,
                    color: loading ? kOnSurfaceVariant : kSecondary,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: loading || devices.isEmpty ? null : onToggleDropdown,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: kSurfaceContHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: dropdownOpen
                        ? kSecondary.withOpacity(0.35)
                        : kOutlineVariant.withOpacity(0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      devices.isEmpty
                          ? Icons.mic_none
                          : Icons.radio_button_checked,
                      color: devices.isEmpty ? kOnSurfaceVariant : kSecondary,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(selectorLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: kOnSurface)),
                          const SizedBox(height: 2),
                          Text(selectorSubLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  fontSize: 10, color: kOnSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (loading)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kSecondary,
                        ),
                      )
                    else
                      Icon(
                        dropdownOpen ? Icons.expand_less : Icons.expand_more,
                        color: devices.isEmpty ? kOnSurfaceVariant : kSecondary,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
            if (dropdownOpen && !loading && devices.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: kSurfaceContHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kOutlineVariant.withOpacity(0.25)),
                ),
                child: Column(
                  children: devices
                      .take(5)
                      .map((device) => _MicDeviceTile(
                            device: device,
                            selected: device.id == selectedMicId,
                            onTap: () => onSelected(device),
                          ))
                      .toList(),
                ),
              ),
            if (dropdownOpen && devices.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Showing first 5 microphones. Tap refresh after connecting a new device.',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: kOnSurfaceVariant, height: 1.4),
                ),
              ),
            if (!loading && devices.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No selectable microphones found. Using Android system default.',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: kOnSurfaceVariant, height: 1.4),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Same idea as the Python picker: choose an input, then the listener restarts on that route where Android permits it.',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: kOnSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  MicInputDevice? get _selectedDevice {
    for (final device in devices) {
      if (device.id == selectedMicId || device.isSelected) return device;
    }
    return null;
  }
}

class _MicDeviceTile extends StatelessWidget {
  final MicInputDevice device;
  final bool selected;
  final VoidCallback onTap;

  const _MicDeviceTile({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? kSecondary.withOpacity(0.1) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: kOutlineVariant.withOpacity(0.12)),
            left: selected
                ? const BorderSide(color: kSecondary, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.mic,
              color: selected ? kSecondary : kOnSurfaceVariant,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? kSecondary : kOnSurface)),
                  const SizedBox(height: 2),
                  Text(device.type,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 10, color: kOnSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceCommandButton extends StatelessWidget {
  final bool expanded;
  final bool micActive;
  final String voiceStatus;
  final String? lastParsedMove;
  final List<MicInputDevice> micDevices;
  final int? selectedMicId;
  final bool micDevicesLoading;
  final bool micDropdownOpen;
  final VoidCallback onToggle;
  final ValueChanged<bool> onMicToggle;
  final VoidCallback onRefreshMics;
  final VoidCallback onMicDropdownToggle;
  final ValueChanged<MicInputDevice> onMicSelected;
  const _VoiceCommandButton({
    required this.expanded,
    required this.micActive,
    required this.voiceStatus,
    required this.lastParsedMove,
    required this.micDevices,
    required this.selectedMicId,
    required this.micDevicesLoading,
    required this.micDropdownOpen,
    required this.onToggle,
    required this.onMicToggle,
    required this.onRefreshMics,
    required this.onMicDropdownToggle,
    required this.onMicSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
              color: kSurfaceContLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: expanded
                      ? kPrimary.withOpacity(0.5)
                      : kOutlineVariant.withOpacity(0.2))),
          child: Row(children: [
            Icon(micActive ? Icons.mic : Icons.mic_off,
                color: micActive ? kPrimary : kOnSurfaceVariant, size: 26),
            const SizedBox(width: 12),
            Text('VOICE PLAY',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: expanded ? kPrimary : kOnSurfaceVariant,
                    letterSpacing: 3)),
            const Spacer(),
            Icon(expanded ? Icons.expand_more : Icons.expand_less,
                color: kOnSurfaceVariant, size: 22),
          ]),
        ),
      ),
      if (expanded)
        Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
              color: kSurfaceContHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kOutlineVariant.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)
              ]),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Mic on/off toggle ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: micActive
                      ? kPrimary.withOpacity(0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: micActive
                        ? kPrimary.withOpacity(0.2)
                        : kOutlineVariant.withOpacity(0.15),
                  ),
                ),
                child: Row(children: [
                  Icon(micActive ? Icons.mic : Icons.mic_off,
                      color: micActive ? kPrimary : kOnSurfaceVariant,
                      size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Microphone',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: micActive ? kPrimary : kOnSurface)),
                        Text(
                            micActive
                                ? 'Listening for voice commands'
                                : 'Tap to enable',
                            style: GoogleFonts.inter(
                                fontSize: 10, color: kOnSurfaceVariant)),
                      ],
                    ),
                  ),
                  Switch(
                    value: micActive,
                    onChanged: onMicToggle,
                    activeColor: kPrimary,
                    activeTrackColor: kPrimary.withOpacity(0.3),
                    inactiveThumbColor: kOnSurfaceVariant,
                    inactiveTrackColor: kSurfaceContLow,
                  ),
                ]),
              ),
            ),

            _MicInputPicker(
              devices: micDevices,
              selectedMicId: selectedMicId,
              loading: micDevicesLoading,
              dropdownOpen: micDropdownOpen,
              onRefresh: onRefreshMics,
              onToggleDropdown: onMicDropdownToggle,
              onSelected: onMicSelected,
            ),

            // ── Voice status ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: micActive ? kPrimary : kOnSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    voiceStatus,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: micActive ? kOnSurface : kOnSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),

            // ── Parsed move result ──
            if (lastParsedMove != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: lastParsedMove!.startsWith('⚠')
                        ? kError.withOpacity(0.08)
                        : kPrimary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: lastParsedMove!.startsWith('⚠')
                          ? kError.withOpacity(0.2)
                          : kPrimary.withOpacity(0.2),
                    ),
                  ),
                  child: Text(
                    lastParsedMove!,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color:
                          lastParsedMove!.startsWith('⚠') ? kError : kPrimary,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 4),
            const Divider(color: kOutlineVariant, height: 1, thickness: 0.2),

            // ── Help text ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('VOICE COMMANDS',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: kOnSurfaceVariant,
                      letterSpacing: 2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Text(
                'Say a move like "D2 to D4" · "Castle kingside" · "Undo"',
                style: GoogleFonts.inter(
                    fontSize: 11, color: kOnSurfaceVariant, height: 1.5),
              ),
            ),

            // ── Status bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Row(children: [
                Expanded(
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                            value: micActive ? null : 0.0,
                            backgroundColor: kSurfaceContLow,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                micActive ? kPrimary : kOnSurfaceVariant),
                            minHeight: 4))),
                const SizedBox(width: 12),
                Text(micActive ? 'LISTENING' : 'MIC OFF',
                    style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: micActive ? kPrimary : kOnSurfaceVariant,
                        letterSpacing: 2)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}
