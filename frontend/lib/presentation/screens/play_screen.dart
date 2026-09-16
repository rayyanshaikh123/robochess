import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../widgets/animated_profile_avatar.dart';
import '../widgets/robo_app_bar.dart';
import '../providers/board_theme_provider.dart';
import '../providers/device_provider.dart';
import '../providers/board_provider.dart';
import '../providers/game_provider.dart';
import '../providers/local_board_provider.dart';
import '../providers/session_provider.dart';
import '../providers/user_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/config/app_config.dart';
import '../../domain/models/device_model.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/opening_context.dart';
import '../../domain/models/calibration_frame.dart';
import '../../domain/voice/voice_service.dart';
import '../../domain/voice/move_parser.dart';
import '../../data/repositories/pi_local_api.dart';
import 'manual_calibration_screen.dart';
import '../widgets/pi_live_camera_view.dart';
import '../theme/app_colors.dart';
import '../widgets/chess_piece_widget.dart';

enum _PlayTabMode { setup, playing }

enum _PlaySurface { board, app }

enum _OpponentType { bot, friend, online }

class _CapturedData {
  final List<String> whiteLost;
  final List<String> blackLost;
  final int whiteAdvantage;
  final int blackAdvantage;

  const _CapturedData({
    required this.whiteLost,
    required this.blackLost,
    required this.whiteAdvantage,
    required this.blackAdvantage,
  });
}

class PlayScreen extends ConsumerStatefulWidget {
  const PlayScreen({super.key});
  @override
  ConsumerState<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends ConsumerState<PlayScreen> {
  // ── Tab mode: Setup vs Playing ──
  _PlayTabMode _tabMode = _PlayTabMode.setup;

  // ── Setup configuration ──
  _PlaySurface _setupSurface = _PlaySurface.app;
  _OpponentType _setupOpponent = _OpponentType.bot;
  int _setupDifficulty = 5;
  String _setupSide = 'white'; // 'white', 'random', 'black'
  int _setupTimeControlMinutes = 10; // 10, 5, 3, 0 (unlimited)

  // ── Setup board wizard state ──
  bool _setupModelLoaded = false;
  bool _setupCalibrated = false;
  bool _setupValidated = false;
  bool _setupBusy = false;
  String? _setupError;
  String? _setupValidationNote;
  bool _setupShowCamera = false;

  // ── Chess Clocks & Flip ──
  Timer? _clockTimer;
  Timer? _botMoveTimer;
  Duration _whiteClock = const Duration(minutes: 10);
  Duration _blackClock = const Duration(minutes: 10);
  bool _clockRunning = false;
  bool _boardFlipped = false;

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
  String? _piConnectionError;
  String? _pendingLocalUci;
  int? _pendingLocalVersion;
  String? _wsGameId;
  String _gameMode = 'human_vs_ai';
  OpeningContext? _openingContext;

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
  Timer? _piSyncTimer;  // periodic Pi game-state sync when using board
  bool _piSyncInFlight = false;

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
        _tabMode = _PlayTabMode.playing;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    if (extra is OpeningContext) {
      _loadOpeningContext(extra);
      _tabMode = _PlayTabMode.playing;
    }
  }

  void _loadOpeningContext(OpeningContext ctx) {
    if (_openingContext?.name == ctx.name) return;
    setState(() {
      _openingContext = ctx;
      _tabMode = _PlayTabMode.playing;
    });
    _game.load_pgn(ctx.pgn);
    _moveHistory.clear();
    _selectedSquare = null;
    _legalDestinations = [];
    _lastMoveFrom = null;
    _lastMoveTo = null;
    _updateStatusMessage();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _botMoveTimer?.cancel();
    _autoDetectTimer?.cancel();
    _piSyncTimer?.cancel();
    _gameSub?.close();
    _statusSub?.cancel();
    _resultSub?.cancel();
    _gameWsSub?.cancel();
    ref.read(gameSocketProvider).close();
    _voiceService.dispose();
    super.dispose();
  }

  // ── Resolve human color from the chosen side ──
  String get _piBaseUrl =>
      ref.read(localBoardProvider).localApiBaseUrl ??
      AppConfig.piLocalApiBaseUrl;

  chess.Color _humanColor() {
    return _setupSide == 'black' ? chess.Color.BLACK : chess.Color.WHITE;
  }

  bool _isBotTurn() {
    return _gameMode == 'human_vs_ai' && _game.turn != _humanColor();
  }

  // ── Square name helpers (0-based row,col → algebraic) ──
  String _squareName(int row, int col) {
    final displayRow = _boardFlipped ? 7 - row : row;
    final displayCol = _boardFlipped ? 7 - col : col;
    final file = String.fromCharCode('a'.codeUnitAt(0) + displayCol);
    final rank = '${8 - displayRow}';
    return '$file$rank';
  }

  // ── Tap on a board square ──
  void _onSquareTap(int row, int col) {
    if (_gameUsesBoard) return;
    if (_isBotTurn()) return;
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

      if (_gameMode == 'human_vs_ai' && !_game.game_over && _isBotTurn()) {
        if (_linkedGameId != null) {
          _scheduleBotFallbackTimer();
        } else {
          _triggerLocalBotMove(delayMs: 600);
        }
      }
    }
  }

  void _triggerLocalBotMove({int delayMs = 600}) {
    _botMoveTimer?.cancel();
    _botMoveTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || _game.game_over) return;
      if (_game.turn == _humanColor()) return;
      final moves = _game.generate_moves();
      if (moves.isEmpty) return;
      chess.Move chosenMove = moves.first;
      for (final m in moves) {
        if (m.captured != null) {
          chosenMove = m;
          break;
        }
      }
      final promo = chosenMove.promotion != null
          ? chosenMove.promotion.toString().toLowerCase()
          : '';
      final uci = '${chosenMove.fromAlgebraic}${chosenMove.toAlgebraic}$promo';
      final ok = _applyUciMove(uci);
      if (ok) {
        setState(() {});
        // CRITICAL: Never call _submitRemoteMove — local-only bot response
      }
    });
  }

  void _scheduleBotFallbackTimer() {
    _botMoveTimer?.cancel();
    _botMoveTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _game.game_over) return;
      if (_game.turn == _humanColor()) return;
      // Backend hasn't responded with game.move — trigger local bot as fallback
      _triggerLocalBotMove(delayMs: 0);
    });
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
      builder: (_) => _PreGameSheet(
        device: device,
        localApi: PiLocalApi(baseUrl: _piBaseUrl),
      ),
    );
    if (result == null) return;

    setState(() {
      _syncing = true;
      _syncError = null;
      _piConnectionError = null;
      _gameMode = result.mode;
      _gameUsesBoard = result.useBoard;
      _inGameValidated = result.useBoard; // Board was validated in modal
      _inGameValidationNote = null;
      _selectedSquare = null;
      _legalDestinations = [];
      _snapshotNote = null;
    });
    _autoDetectTimer?.cancel();
    _piSyncTimer?.cancel();
    try {
      if (_setupSide == 'random') {
        _setupSide = Random().nextBool() ? 'white' : 'black';
      }
      await ref.read(gameControllerProvider.notifier).createGame(
            mode: result.mode,
            difficulty: result.difficulty,
            players:
                result.useBoard && device != null ? [device.deviceId] : null,
            playerSide: _setupSide,
          );
      if (result.useBoard) {
        try {
          await PiLocalApi(baseUrl: _piBaseUrl).startGame();
          if (mounted) {
            setState(() => _piConnectionError = null);
          }
          _fetchLiveFrame();
          _startAutoDetect();
        } catch (error) {
          if (mounted) {
            setState(() {
              _piConnectionError =
                  'Cannot reach the Pi at $_piBaseUrl. Check that the phone and Pi are on the same network and the agent is running.';
              _gameUsesBoard = false;
            });
          }
          _autoDetectTimer?.cancel();
          _piSyncTimer?.cancel();
        }
      } else {
        _clearSnapshot();
        _autoDetectTimer?.cancel();
        _piSyncTimer?.cancel();
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
    final piApi = PiLocalApi(baseUrl: _piBaseUrl);
    setState(() => _livePreviewLoading = true);
    try {
      final frame = CalibrationFrame(
        imageBase64: base64Encode(await piApi.cameraFrame(preview: true)),
        width: 800,
        height: 600,
      );
      if (!mounted) return;
      setState(() {
        _liveFrame = frame;
        _livePreviewError = null;
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
      if (!_gameUsesBoard ||
          _snapshotDetecting ||
          _syncing ||
          !_inGameValidated) return;
      _checkAutoDetectReady();
    });
    _startPiSync();
  }

  /// Periodically fetch the Pi's authoritative game state and sync the local
  /// Flutter board.  This catches engine moves executed on the Pi that were not
  /// reflected via auto-detect (e.g. when the Pi ran the engine turn but the
  /// Flutter client missed the result).
  void _startPiSync() {
    if (_piSyncTimer != null) return;
    _piSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_gameUsesBoard || _piBaseUrl.isEmpty || !mounted || _piSyncInFlight) return;
      _piSyncInFlight = true;
      try {
        final raw = await PiLocalApi(baseUrl: _piBaseUrl).gameState();
        final version = int.tryParse(raw['version']?.toString() ?? '');
        if (version != null && version >= _linkedGameVersion && mounted) {
          setState(() => _applyPiSnapshot(raw, version));
        }
      } catch (_) {
        // Silently ignore connectivity failures — the timer will retry.
      } finally {
        _piSyncInFlight = false;
      }
    });
  }

  void _applyPiSnapshot(Map<String, dynamic> snapshot, int version) {
    if (version < _linkedGameVersion) return;

    final moves = snapshot['moves'];
    var applied = moves is List && moves.length == version;
    if (applied) {
      final currentPly = _game.history.length;
      if (currentPly > moves.length) {
        applied = false;
      } else {
        for (var index = currentPly; index < moves.length; index++) {
          final uci = moves[index]?.toString() ?? '';
          if (uci.isEmpty || !_applyUciMove(uci)) {
            applied = false;
            break;
          }
        }
      }
    }

    if (!applied) {
      final fen = snapshot['fen']?.toString() ?? '';
      if (fen.isNotEmpty && fen != _game.fen) {
        _resetBoardFromFen(fen);
      }
    }

    _linkedGameVersion = version;
    final phase = snapshot['phase']?.toString();
    if (phase == 'executing_engine_move') {
      _snapshotNote = 'Engine moving the pieces...';
    } else if (phase == 'recovery') {
      _syncError = snapshot['last_error']?.toString() ?? 'Physical board needs recovery.';
    }
  }

  Future<void> _checkAutoDetectReady() async {
    if (_snapshotDetecting) return;
    try {
      final Map<String, dynamic> result;
      if (_gameUsesBoard && _piBaseUrl.isNotEmpty) {
        result = await PiLocalApi(baseUrl: _piBaseUrl).autoDetectReady();
      } else {
        result = await ref.read(boardRepositoryProvider).checkAutoDetect();
      }
      final data = result['data'] as Map<String, dynamic>? ?? result;
      final ready = data['ready'] == true;
      final reason = data['reason']?.toString() ?? '';

      // Immediately sync Pi state if returned (e.g. engine move completed or board updated)
      if (data['state'] is Map) {
        final state = Map<String, dynamic>.from(data['state'] as Map);
        final version = int.tryParse(state['version']?.toString() ?? '');
        if (version != null && version >= _linkedGameVersion && mounted) {
          setState(() => _applyPiSnapshot(state, version));
        }
      }

      if (ready) {
        // Auto-detect triggered successfully!
        final uci = data['uci']?.toString();
        final san = data['san']?.toString();
        if (uci != null && uci.isNotEmpty) {
          final applied = _applyUciMove(uci);
          setState(() {
            _snapshotNote = 'Auto-detected: ${san ?? uci} ($uci)';
          });

          // Check if engine move was provided by Pi or needs to be requested
          final engineData = data['engine_move'] as Map<String, dynamic>?;
          final aiUci = engineData?['uci']?.toString();
          if (aiUci != null && aiUci.isNotEmpty) {
            _applyUciMove(aiUci);
            if (mounted) {
              setState(() {
                _snapshotNote = 'Auto-detected: ${san ?? uci}. Engine: $aiUci';
              });
            }
          } else if (!_gameUsesBoard || _piBaseUrl.isEmpty) {
            try {
              final aiResult = await ref.read(boardRepositoryProvider).aiMove();
              final aiData = aiResult['data'] as Map<String, dynamic>? ?? {};
              final fetchedAiUci = aiData['uci']?.toString();
              if (fetchedAiUci != null && fetchedAiUci.isNotEmpty && mounted) {
                _applyUciMove(fetchedAiUci);
                setState(() {
                  _snapshotNote = 'Auto-detected: ${san ?? uci}. Engine: $fetchedAiUci';
                });
              }
            } catch (_) {
              if (mounted) {
                setState(() {
                  _snapshotNote =
                      'Auto-detected: ${san ?? uci} ($uci). Engine reply failed.';
                });
              }
            }
          }

          await _fetchLiveFrame();
        }
      } else if (reason.isNotEmpty && mounted) {
        setState(() {
          _snapshotNote = reason == 'hand_present'
              ? 'Hand detected. Move away to detect.'
              : reason;
        });
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
        final Map<String, dynamic> result;
        if (_gameUsesBoard && _piBaseUrl.isNotEmpty) {
          result = await PiLocalApi(baseUrl: _piBaseUrl).analyzeAndReply();
        } else {
          result =
              await ref.read(boardRepositoryProvider).analyzeAndReplySnapshot();
        }
        final data = result['data'] as Map<String, dynamic>? ?? result;
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
      final Map<String, dynamic> result;
      if (_gameUsesBoard && _piBaseUrl.isNotEmpty) {
        result = await PiLocalApi(baseUrl: _piBaseUrl).validateStart();
      } else {
        result = await ref.read(boardRepositoryProvider).validateStart();
      }
      final data = result['data'] as Map<String, dynamic>? ?? result;
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
      if (_gameUsesBoard && _piBaseUrl.isNotEmpty) {
        await PiLocalApi(baseUrl: _piBaseUrl).forceValidate();
      } else {
        await ref.read(boardRepositoryProvider).forceValidate();
      }
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

  Future<void> _manualPiCalibrate() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualCalibrationScreen(
          localApi: PiLocalApi(baseUrl: _piBaseUrl),
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _inGameValidated = false;
        _inGameValidationNote =
            'Pi calibration saved. Validate the board again.';
      });
    }
  }

  // ── Resign ──
  Future<void> _resignGame() async {
    final gameId = _linkedGameId;
    if (gameId == null || _game.game_over) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurfaceContLow,
        title: const Text('Resign?'),
        content: const Text('Are you sure you want to resign this game?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(gameControllerProvider.notifier).resignGame(gameId);
      if (!mounted) return;
      setState(() {
        _syncError = null;
        _statusMessage = 'You resigned.';
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _syncError = 'Resign failed. Please try again.');
    }
  }

  // ── Undo last move ──
  Future<void> _undoMove() async {
    _botMoveTimer?.cancel();
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

    if (!_clockRunning && _setupTimeControlMinutes > 0) {
      _startClock();
    }

    if (_game.game_over) {
      _clockTimer?.cancel();
      _clockRunning = false;
      String title = 'Game Finished';
      String subtitle = _statusMessage;
      if (_game.in_checkmate) {
        final winner = _game.turn == chess.Color.WHITE ? 'Black' : 'White';
        title = '$winner Won!';
        subtitle = 'Victory by checkmate';
      } else if (_game.in_stalemate) {
        title = 'Stalemate';
        subtitle = 'Draw by stalemate';
      } else if (_game.in_draw) {
        title = 'Draw';
        subtitle = 'Game ended in a draw';
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showGameOverDialog(title: title, subtitle: subtitle);
        }
      });
    }

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
      _botMoveTimer?.cancel();
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
    final cloudDevices = ref.watch(deviceListProvider).valueOrNull ?? [];
    final devices = List<DeviceModel>.from(cloudDevices);
    
    final localState = ref.watch(localBoardProvider);
    final localDevice = localState.selected;
    if (localDevice?.deviceId != null &&
        devices.every((d) => d.deviceId != localDevice!.deviceId)) {
      devices.insert(
          0,
          DeviceModel(
            deviceId: localDevice!.deviceId!,
            status: 'online',
            lastSeen: DateTime.now(),
          ));
    }

    final selectedId = ref.watch(selectedDeviceProvider);
    final activeDevice = _resolveActiveDevice(devices, selectedId);

    if (_tabMode == _PlayTabMode.setup) {
      return _buildSetupScreen(context, activeDevice);
    }
    return _buildChessComGameScreen(context, activeDevice);
  }

  // ── Clock & Timing Helpers ────────────────────────────────────────────────
  void _startClock() {
    _clockTimer?.cancel();
    if (_setupTimeControlMinutes == 0) return; // Unlimited / casual

    _clockRunning = true;
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _game.game_over) {
        timer.cancel();
        _clockRunning = false;
        return;
      }
      setState(() {
        if (_game.turn == chess.Color.WHITE) {
          if (_whiteClock.inSeconds > 0) {
            _whiteClock -= const Duration(seconds: 1);
          } else {
            timer.cancel();
            _clockRunning = false;
            _handleTimeOut(chess.Color.WHITE);
          }
        } else {
          if (_blackClock.inSeconds > 0) {
            _blackClock -= const Duration(seconds: 1);
          } else {
            timer.cancel();
            _clockRunning = false;
            _handleTimeOut(chess.Color.BLACK);
          }
        }
      });
    });
  }

  void _handleTimeOut(chess.Color timedOutColor) {
    final winner = timedOutColor == chess.Color.WHITE ? 'Black' : 'White';
    _statusMessage = '$winner won on time!';
    _showGameOverDialog(
      title: '$winner Won on Time!',
      subtitle:
          '${timedOutColor == chess.Color.WHITE ? "White" : "Black"} ran out of time.',
    );
  }

  String _formatClock(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // ── Board Setup Wizard Actions ────────────────────────────────────────────
  Future<void> _runSetupStep(Future<void> Function() action) async {
    setState(() {
      _setupBusy = true;
      _setupError = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() {
        _setupError = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _setupBusy = false);
    }
  }

  Future<void> _setupLoadModel() async {
    await _runSetupStep(() async {
      await PiLocalApi(baseUrl: _piBaseUrl).loadModel();
      setState(() => _setupModelLoaded = true);
    });
  }

  Future<void> _setupAutoCalibrate() async {
    await _runSetupStep(() async {
      await PiLocalApi(baseUrl: _piBaseUrl).autoCalibrate();
      setState(() {
        _setupCalibrated = true;
        _setupValidated = false;
      });
    });
  }

  Future<void> _setupManualCalibrate() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualCalibrationScreen(
          localApi: PiLocalApi(baseUrl: _piBaseUrl),
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _setupCalibrated = true;
        _setupValidated = false;
      });
    }
  }

  Future<void> _setupHomeGantry() async {
    if (_setupBusy) return;
    await _runSetupStep(() async {
      final data = await PiLocalApi(baseUrl: _piBaseUrl).homeGantry();
      
      final setupStages = (data['setup']?['stages'] as List?)?.cast<Map>() ?? [];
      final stageHomed = setupStages.any((s) => s['key'] == 'gantry_homed' && s['ok'] == true);
      final homed = data['status'] == 'gantry_homed' || 
                   data['homed'] == true ||
                   stageHomed ||
                   (data['status'] != 'error' && data['error'] == null);
                   
      final error = data['error']?.toString();

      if (!mounted) return;

      setState(() {
        _setupValidated = homed;
        if (homed) {
          _setupValidationNote = 'Gantry homed successfully ✓';
          _setupError = null;
        } else {
          _setupValidationNote = 'Gantry homing failed: ${error ?? 'Unknown error'}';
        }
      });
    });
  }

  Future<void> _setupValidateBoard() async {
    if (_setupBusy) return;
    await _runSetupStep(() async {
      final data = await PiLocalApi(baseUrl: _piBaseUrl).validateStart();
      final valid = data['valid'] == true;
      final summary = data['summary'] as Map?;
      final vision = data['vision'] as Map?;
      final detections = vision?['last_detections'] as List?;
      final error = data['error']?.toString();

      if (!mounted) return;

      setState(() {
        if (valid) {
          _setupValidationNote = 'Board position verified ✓\n'
              '${data['pieces_detected'] ?? 32} pieces detected.';
          if (detections != null) {
            final confs = detections
                .map((d) => (d['confidence'] as num).toDouble())
                .toList();
            if (confs.isNotEmpty) {
              final avgConf = (confs.reduce((a, b) => a + b) / confs.length);
              _setupValidationNote = '$_setupValidationNote\n'
                  'Avg Confidence: ${(avgConf * 100).toStringAsFixed(1)}%';
            }
          }
        } else {
          final missing = summary?['missing'] ?? 0;
          final extra = summary?['extra'] ?? 0;
          final wrong = summary?['wrong_color'] ?? 0;
          _setupValidationNote = error ??
              'Board position incorrect ❌\n'
                  'Missing: $missing | Extra: $extra | Wrong Color: $wrong';
        }
      });
    });
  }

  Future<void> _startMatchFromSetup(DeviceModel? device) async {
    final mode = _setupOpponent == _OpponentType.bot
        ? 'human_vs_ai'
        : (_setupOpponent == _OpponentType.friend
            ? 'human_vs_human'
            : 'online');
    final useBoard = _setupSurface == _PlaySurface.board;

    setState(() {
      _syncing = true;
      _syncError = null;
      _gameMode = mode;
      _gameUsesBoard = useBoard;
      _inGameValidated = useBoard;
      _inGameValidationNote = null;
      _selectedSquare = null;
      _legalDestinations = [];
      _snapshotNote = null;
      _moveHistory.clear();
      _game.reset();

      final clockDur = _setupTimeControlMinutes > 0
          ? Duration(minutes: _setupTimeControlMinutes)
          : Duration.zero;
      _whiteClock = clockDur;
      _blackClock = clockDur;

      if (_setupSide == 'black') {
        _boardFlipped = true;
      } else {
        _boardFlipped = false;
      }
    });

    _autoDetectTimer?.cancel();
    _piSyncTimer?.cancel();

    try {
      if (_setupSide == 'random') {
        _setupSide = Random().nextBool() ? 'white' : 'black';
      }
      await ref.read(gameControllerProvider.notifier).createGame(
            mode: mode,
            difficulty: _setupDifficulty,
            players: useBoard && device != null ? [device.deviceId] : null,
            playerSide: _setupSide,
          );

      if (useBoard) {
        try {
          await PiLocalApi(baseUrl: _piBaseUrl).startGame();
        } catch (e) {
          if (mounted) {
            setState(
                () => _syncError = 'Pi game session could not be started: $e');
          }
        }
        _fetchLiveFrame();
        _startAutoDetect();
      } else {
        _clearSnapshot();
        _autoDetectTimer?.cancel();
        _piSyncTimer?.cancel();
      }

      _startClock();

      if (mounted) {
        setState(() {
          _tabMode = _PlayTabMode.playing;
        });

        // If playing Black vs Bot, trigger Bot's opening move
        if (_setupSide == 'black' && _gameMode == 'human_vs_ai') {
          if (_linkedGameId != null) {
            _scheduleBotFallbackTimer();
          } else {
            _triggerLocalBotMove(delayMs: 600);
          }
        }
      }
    } catch (_) {
      if (mounted) {
        // Fallback to local offline play so matches never stall
        _startClock();
        setState(() {
          _tabMode = _PlayTabMode.playing;
          _gameUsesBoard = false;
          _syncError = 'Playing in local digital match.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  Future<void> _confirmExitToSetup() async {
    if (_game.history.isEmpty || _game.game_over) {
      setState(() => _tabMode = _PlayTabMode.setup);
      return;
    }
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceContLow,
        title: Text('Leave Match?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: const Text(
          'Your match progress is preserved. You can resume this match at any time from Match Setup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('STAY IN GAME'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: kOnPrimary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('MATCH SETUP'),
          ),
        ],
      ),
    );
    if (exit == true && mounted) {
      _botMoveTimer?.cancel();
      setState(() => _tabMode = _PlayTabMode.setup);
    }
  }

  void _showGameOverDialog({required String title, required String subtitle}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceContLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            const Icon(Icons.emoji_events_rounded,
                color: Colors.amber, size: 48),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kOnSurface,
              ),
            ),
          ],
        ),
        content: Text(
          subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 14, color: kOnSurfaceVariant),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _tabMode = _PlayTabMode.setup);
            },
            child: const Text('NEW MATCH'),
          ),
          if (_linkedGameId != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/analysis?game_id=$_linkedGameId');
              },
              child: const Text('ANALYZE'),
            ),
        ],
      ),
    );
  }

  // ── Captured Pieces Data ──────────────────────────────────────────────────
  _CapturedData _calculateCaptured(chess.Chess game) {
    final Map<String, int> whiteRemaining = {
      'p': 0,
      'n': 0,
      'b': 0,
      'r': 0,
      'q': 0
    };
    final Map<String, int> blackRemaining = {
      'p': 0,
      'n': 0,
      'b': 0,
      'r': 0,
      'q': 0
    };

    for (var file = 0; file < 8; file++) {
      final f = String.fromCharCode('a'.codeUnitAt(0) + file);
      for (var rank = 1; rank <= 8; rank++) {
        final p = game.get('$f$rank');
        if (p == null) continue;
        final typeStr = p.type.toString().toLowerCase();
        if (typeStr == 'k') continue;
        if (p.color == chess.Color.WHITE) {
          whiteRemaining[typeStr] = (whiteRemaining[typeStr] ?? 0) + 1;
        } else {
          blackRemaining[typeStr] = (blackRemaining[typeStr] ?? 0) + 1;
        }
      }
    }

    const starting = {'q': 1, 'r': 2, 'b': 2, 'n': 2, 'p': 8};
    const values = {'q': 9, 'r': 5, 'b': 3, 'n': 3, 'p': 1};

    final List<String> whiteLost = [];
    final List<String> blackLost = [];

    var whiteMaterial = 0;
    var blackMaterial = 0;

    for (final entry in starting.entries) {
      final type = entry.key;
      final startCount = entry.value;
      final wCount = whiteRemaining[type] ?? 0;
      final bCount = blackRemaining[type] ?? 0;
      whiteMaterial += wCount * (values[type] ?? 0);
      blackMaterial += bCount * (values[type] ?? 0);

      for (var i = 0; i < (startCount - wCount); i++) {
        whiteLost.add(type);
      }
      for (var i = 0; i < (startCount - bCount); i++) {
        blackLost.add(type);
      }
    }

    final diff = whiteMaterial - blackMaterial;
    return _CapturedData(
      whiteLost: whiteLost,
      blackLost: blackLost,
      whiteAdvantage: diff > 0 ? diff : 0,
      blackAdvantage: diff < 0 ? -diff : 0,
    );
  }

  String _pieceGlyph(String type, bool isWhite) {
    switch (type.toLowerCase()) {
      case 'p':
        return isWhite ? '♙' : '♟';
      case 'n':
        return isWhite ? '♘' : '♞';
      case 'b':
        return isWhite ? '♗' : '♝';
      case 'r':
        return isWhite ? '♖' : '♜';
      case 'q':
        return isWhite ? '♕' : '♛';
      default:
        return '';
    }
  }

  // ── VIEW 1: Game Initialization & Setup Screen ────────────────────────────
  Widget _buildSetupScreen(BuildContext context, DeviceModel? activeDevice) {
    final hasActiveGame = _game.history.isNotEmpty || _linkedGameId != null;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: RoboAppBar(
        sectionBadge: 'MATCH SETUP',
        actions: [
          IconButton(
            icon:
                const Icon(Icons.palette_outlined, color: kOnSurface, size: 20),
            tooltip: 'Chessboard Theme',
            onPressed: () => _showBoardThemeSheet(context),
          ),
          const AnimatedProfileAvatar(size: 34),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Resume Banner if match already in progress
            if (hasActiveGame) ...[
              Material(
                color: kPrimary.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                      color: kPrimary.withValues(alpha: 0.35), width: 1.5),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _tabMode = _PlayTabMode.playing),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: kPrimary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ACTIVE MATCH IN PROGRESS',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: kPrimary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_moveHistory.length} moves played • $_statusMessage',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: kOnSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            size: 16, color: kPrimary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],

            Text(
              'NEW CHESS MATCH',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: kOnSurface,
                letterSpacing: 1,
              ),
            ),
            Text(
              'Configure your opponent, clock, and board hardware',
              style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant),
            ),
            const SizedBox(height: 18),

            // Section 1: Game Mode
            _buildSectionHeader('GAME MODE', Icons.sports_esports_outlined),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildSelectCard(
                    title: 'vs Computer',
                    subtitle: 'Play AI Bot',
                    icon: Icons.smart_toy_outlined,
                    isSelected: _setupOpponent == _OpponentType.bot,
                    onTap: () =>
                        setState(() => _setupOpponent = _OpponentType.bot),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSelectCard(
                    title: 'Pass & Play',
                    subtitle: '2 Players',
                    icon: Icons.people_outline,
                    isSelected: _setupOpponent == _OpponentType.friend,
                    onTap: () =>
                        setState(() => _setupOpponent = _OpponentType.friend),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSelectCard(
                    title: 'Online',
                    subtitle: 'Multiplayer',
                    icon: Icons.public,
                    isSelected: _setupOpponent == _OpponentType.online,
                    onTap: () =>
                        setState(() => _setupOpponent = _OpponentType.online),
                  ),
                ),
              ],
            ),

            // If vs Computer: Bot Difficulty
            if (_setupOpponent == _OpponentType.bot) ...[
              const SizedBox(height: 18),
              _buildSectionHeader(
                  'BOT DIFFICULTY (ELO)', Icons.psychology_outlined),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildDifficultyChip(level: 1, label: 'Novice', elo: '800'),
                    const SizedBox(width: 8),
                    _buildDifficultyChip(
                        level: 3, label: 'Casual', elo: '1200'),
                    const SizedBox(width: 8),
                    _buildDifficultyChip(
                        level: 5, label: 'Intermediate', elo: '1500'),
                    const SizedBox(width: 8),
                    _buildDifficultyChip(
                        level: 8, label: 'Advanced', elo: '1800'),
                    const SizedBox(width: 8),
                    _buildDifficultyChip(
                        level: 10, label: 'Grandmaster', elo: '2200'),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),
            // Section 2: Side Selection
            _buildSectionHeader('PLAY AS', Icons.pie_chart_outline),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildSelectCard(
                    title: 'White',
                    subtitle: 'First Move',
                    icon: Icons.radio_button_checked,
                    iconColor: Colors.white,
                    isSelected: _setupSide == 'white',
                    onTap: () => setState(() => _setupSide = 'white'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSelectCard(
                    title: 'Random',
                    subtitle: '50 / 50',
                    icon: Icons.shuffle_rounded,
                    isSelected: _setupSide == 'random',
                    onTap: () => setState(() => _setupSide = 'random'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSelectCard(
                    title: 'Black',
                    subtitle: 'Second Move',
                    icon: Icons.radio_button_checked,
                    iconColor: Colors.black87,
                    isSelected: _setupSide == 'black',
                    onTap: () => setState(() => _setupSide = 'black'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),
            // Section 3: Time Control
            _buildSectionHeader('TIME CONTROL', Icons.timer_outlined),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildTimeControlChip(10, '10 min', 'Rapid'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTimeControlChip(5, '5 min', 'Blitz'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTimeControlChip(3, '3 min', 'Blitz'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTimeControlChip(0, '∞', 'Casual'),
                ),
              ],
            ),

            const SizedBox(height: 18),
            // Section 4: Playing Surface
            _buildSectionHeader(
                'PLAYING SURFACE', Icons.sports_kabaddi_outlined),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildSelectCard(
                    title: 'Phone Screen',
                    subtitle: 'Digital App Play',
                    icon: Icons.smartphone_rounded,
                    isSelected: _setupSurface == _PlaySurface.app,
                    onTap: () =>
                        setState(() => _setupSurface = _PlaySurface.app),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSelectCard(
                    title: 'RoboChess Board',
                    subtitle: 'Physical Robotic Board',
                    icon: Icons.grid_on_rounded,
                    isSelected: _setupSurface == _PlaySurface.board,
                    onTap: () =>
                        setState(() => _setupSurface = _PlaySurface.board),
                  ),
                ),
              ],
            ),

            // If Physical Board: Step-by-Step Setup Checklist
            if (_setupSurface == _PlaySurface.board) ...[
              const SizedBox(height: 20),
              _buildBoardSetupWizard(context, activeDevice),
            ],

            const SizedBox(height: 24),
            // Main Start Game CTA
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed:
                    _syncing ? null : () => _startMatchFromSetup(activeDevice),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: kOnPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                  shadowColor: kPrimary.withValues(alpha: 0.4),
                ),
                child: _syncing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _setupSurface == _PlaySurface.board
                                ? Icons.precision_manufacturing_rounded
                                : Icons.play_arrow_rounded,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _setupSurface == _PlaySurface.board
                                ? 'START MATCH ON BOARD'
                                : 'START CHESS MATCH',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Setup Helpers & Cards ─────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: kPrimary),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: kOnSurfaceVariant,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectCard({
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? kPrimary.withValues(alpha: 0.1) : kSurfaceContLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color:
              isSelected ? kPrimary : kOutlineVariant.withValues(alpha: 0.15),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color:
                      iconColor ?? (isSelected ? kPrimary : kOnSurfaceVariant),
                  size: 24),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? kPrimary : kOnSurface,
                ),
              ),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: kOnSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDifficultyChip(
      {required int level, required String label, required String elo}) {
    final isSelected = _setupDifficulty == level;
    return Material(
      color: isSelected ? kPrimary : kSurfaceContLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? kPrimary : kOutlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _setupDifficulty = level),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : kOnSurface,
                ),
              ),
              Text(
                'L$level • $elo',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white70 : kOnSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeControlChip(int minutes, String label, String sub) {
    final isSelected = _setupTimeControlMinutes == minutes;
    return Material(
      color: isSelected ? kPrimary : kSurfaceContLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? kPrimary : kOutlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _setupTimeControlMinutes = minutes),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : kOnSurface,
                ),
              ),
              Text(
                sub,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white70 : kOnSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBoardSetupWizard(
      BuildContext context, DeviceModel? activeDevice) {
    final isLinked = activeDevice != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimary.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.checklist_rounded,
                    color: kPrimary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PHYSICAL BOARD SETUP CHECKLIST',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: kOnSurface,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'Complete hardware readiness before launching match',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: kOnSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Step 1: Connect Board
          _buildWizardStepItem(
            stepNumber: '1',
            title: 'Link RoboChess Board',
            subtitle: isLinked
                ? 'Connected: ${activeDevice.deviceId}'
                : 'No board linked. Connect via Wi-Fi/Bluetooth.',
            isComplete: isLinked,
            busy: false,
            actionLabel: isLinked ? 'CHANGE' : 'LINK BOARD',
            onAction: () => context.push('/connect'),
          ),
          const SizedBox(height: 10),

          // Step 2: Vision Model
          _buildWizardStepItem(
            stepNumber: '2',
            title: 'Neural Vision Model',
            subtitle: _setupModelLoaded
                ? 'YOLO Piece Model Loaded ✓'
                : 'Loads neural network for piece detection',
            isComplete: _setupModelLoaded,
            busy: _setupBusy && !_setupModelLoaded,
            actionLabel: _setupModelLoaded ? 'READY' : 'LOAD MODEL',
            onAction: _setupModelLoaded ? null : _setupLoadModel,
          ),
          const SizedBox(height: 10),

          // Step 3: Grid Calibration
          _buildWizardStepItem(
            stepNumber: '3',
            title: 'Camera Grid Calibration',
            subtitle: _setupCalibrated
                ? '64-Square Coordinate Mapping Saved ✓'
                : 'Aligns camera perspective to physical squares',
            isComplete: _setupCalibrated,
            busy: _setupBusy && !_setupCalibrated,
            actionLabel: _setupCalibrated ? 'RE-CAL' : 'CALIBRATE',
            onAction: _setupAutoCalibrate,
            secondaryLabel: 'CROP (MANUAL)',
            onSecondaryAction: _setupManualCalibrate,
          ),
          const SizedBox(height: 10),

          // Step 4: Gantry Homing
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _setupValidated
                  ? kPrimary.withValues(alpha: 0.08)
                  : kSurfaceContHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _setupValidated
                    ? kPrimary.withValues(alpha: 0.4)
                    : kOutlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _setupValidated ? kPrimary : kSurfaceContHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: _setupValidated
                            ? const Icon(Icons.check,
                                size: 14, color: Colors.white)
                            : Text('4',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: kOnSurfaceVariant)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gantry Homing',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kOnSurface,
                            ),
                          ),
                          Text(
                            'Move the robotic gantry to its zero position.',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: kOnSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _setupShowCamera = !_setupShowCamera),
                      icon: Icon(
                          _setupShowCamera
                              ? Icons.videocam_off_outlined
                              : Icons.videocam_outlined,
                          size: 16),
                      label: Text(_setupShowCamera ? 'HIDE CAM' : 'PREVIEW CAM',
                          style: GoogleFonts.inter(
                              fontSize: 10, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _setupBusy ? null : _setupValidateBoard,
                        icon: _setupBusy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline,
                                size: 16),
                        label: Text('VALIDATE',
                            style: GoogleFonts.inter(
                                fontSize: 10, fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(
                          backgroundColor: kSecondary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _setupBusy ? null : _setupHomeGantry,
                        icon: _setupBusy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.home_rounded,
                                size: 16),
                        label: Text('HOME',
                            style: GoogleFonts.inter(
                                fontSize: 10, fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(
                          backgroundColor: kPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_setupShowCamera) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: PiLiveCameraView(
                        baseUrl: _piBaseUrl,
                      ),
                    ),
                  ),
                ],
                if (_setupValidationNote != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _setupValidated
                          ? kPrimary.withValues(alpha: 0.12)
                          : kError.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _setupValidated
                            ? kPrimary.withValues(alpha: 0.3)
                            : kError.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _setupValidationNote!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _setupValidated ? kPrimary : kError,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (_setupError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kError.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _setupError!,
                style: GoogleFonts.inter(
                    fontSize: 11, color: kError, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWizardStepItem({
    required String stepNumber,
    required String title,
    required String subtitle,
    required bool isComplete,
    required bool busy,
    required String actionLabel,
    required VoidCallback? onAction,
    String? secondaryLabel,
    VoidCallback? onSecondaryAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isComplete
            ? kPrimary.withValues(alpha: 0.08)
            : kSurfaceContHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isComplete
              ? kPrimary.withValues(alpha: 0.35)
              : kOutlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isComplete ? kPrimary : kSurfaceContHighest,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isComplete
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : Text(
                      stepNumber,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kOnSurfaceVariant,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kOnSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style:
                      GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (secondaryLabel != null &&
              onSecondaryAction != null &&
              !isComplete) ...[
            OutlinedButton(
              onPressed: busy ? null : onSecondaryAction,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
              ),
              child: Text(secondaryLabel,
                  style: GoogleFonts.inter(
                      fontSize: 9, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
          ],
          FilledButton(
            onPressed: busy ? null : onAction,
            style: FilledButton.styleFrom(
              backgroundColor:
                  isComplete ? kPrimary.withValues(alpha: 0.2) : kPrimary,
              foregroundColor: isComplete ? kPrimary : kOnPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: busy
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(actionLabel,
                    style: GoogleFonts.inter(
                        fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ── VIEW 2: Chess.com Style Active Game Arena ─────────────────────────────
  Widget _buildChessComGameScreen(
      BuildContext context, DeviceModel? activeDevice) {
    final captured = _calculateCaptured(_game);
    final isWhiteTurn = _game.turn == chess.Color.WHITE;
    final profileAsync = ref.watch(userProfileProvider);
    final userDisplayName = profileAsync.valueOrNull?.displayName ?? 'Player';

    // Top bar is ALWAYS the opponent/bot; bottom bar is ALWAYS the human user
    final topIsUser = false;
    final topIsWhite = _boardFlipped;
    final topIsTurn = topIsWhite ? isWhiteTurn : !isWhiteTurn;
    final topClock = topIsWhite ? _whiteClock : _blackClock;
    final topName = topIsUser
        ? userDisplayName
        : (_gameMode == 'human_vs_ai'
            ? 'RoboBot (Level $_setupDifficulty)'
            : 'Opponent');
    final topRating = topIsUser ? '1200' : '${700 + _setupDifficulty * 150}';
    final topCaptured = topIsWhite ? captured.blackLost : captured.whiteLost;
    final topAdvantage =
        topIsWhite ? captured.whiteAdvantage : captured.blackAdvantage;

    // Bottom player is White if not flipped, Black if flipped
    final bottomIsUser = true;
    final bottomIsWhite = !_boardFlipped;
    final bottomIsTurn = bottomIsWhite ? isWhiteTurn : !isWhiteTurn;
    final bottomClock = bottomIsWhite ? _whiteClock : _blackClock;
    final bottomName = bottomIsUser
        ? userDisplayName
        : (_gameMode == 'human_vs_ai'
            ? 'RoboBot (Level $_setupDifficulty)'
            : 'Opponent');
    final bottomRating =
        bottomIsUser ? '1200' : '${700 + _setupDifficulty * 150}';
    final bottomCaptured =
        bottomIsWhite ? captured.blackLost : captured.whiteLost;
    final bottomAdvantage =
        bottomIsWhite ? captured.whiteAdvantage : captured.blackAdvantage;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: RoboAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: kOnSurfaceVariant),
          tooltip: 'Match Setup',
          onPressed: _confirmExitToSetup,
        ),
        sectionBadge: _gameMode == 'human_vs_ai'
            ? 'VS BOT (LVL $_setupDifficulty)'
            : (_gameMode == 'human_vs_human' ? 'PASS & PLAY' : 'ONLINE MATCH'),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.palette_outlined, color: kOnSurface, size: 20),
            tooltip: 'Chessboard Theme',
            onPressed: () => _showBoardThemeSheet(context),
          ),
          IconButton(
            icon:
                const Icon(Icons.sync_alt_rounded, color: kOnSurface, size: 20),
            tooltip: 'Flip Board',
            onPressed: () => setState(() => _boardFlipped = !_boardFlipped),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: kOnSurface, size: 20),
            tooltip: 'Match Settings',
            onPressed: _confirmExitToSetup,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 80),
          child: Column(
            children: [
              if (_piConnectionError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: kError.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kError.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.wifi_off_rounded,
                              color: kError, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pi board unavailable',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                color: kError,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$_piConnectionError\nCheck the Pi agent and local network, then retry.',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: kOnSurfaceVariant),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _fetchLiveFrame,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retry connection'),
                          ),
                          TextButton(
                            onPressed: () => context.go('/connect'),
                            child: const Text('Open board setup'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Check or Sync Warning Banner
              if (_statusMessage.contains('Check') || _syncError != null)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: _syncError != null
                        ? kError.withValues(alpha: 0.12)
                        : kError.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _syncError ?? _statusMessage,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kError,
                    ),
                  ),
                ),

              // ── Opponent Player Bar (Chess.com layout) ──
              _buildChessComPlayerBar(
                context: context,
                name: topName,
                rating: topRating,
                isTurn: topIsTurn,
                clock: topClock,
                isBot: !topIsUser && _gameMode == 'human_vs_ai',
                capturedPieces: topCaptured,
                materialAdvantage: topAdvantage,
                isUser: topIsUser,
                isWhitePieceColor: !topIsWhite,
              ),

              const SizedBox(height: 8),

              // ── The Chessboard ──
              Stack(
                children: [
                  _buildChessBoard(context),
                  if (_gameUsesBoard)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: kPrimary, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                    color: Colors.greenAccent,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text('BOARD SYNCED',
                                style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 1)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // ── User Player Bar (Chess.com layout) ──
              _buildChessComPlayerBar(
                context: context,
                name: bottomName,
                rating: bottomRating,
                isTurn: bottomIsTurn,
                clock: bottomClock,
                isBot: !bottomIsUser && _gameMode == 'human_vs_ai',
                capturedPieces: bottomCaptured,
                materialAdvantage: bottomAdvantage,
                isUser: bottomIsUser,
                isWhitePieceColor: !bottomIsWhite,
              ),

              const SizedBox(height: 10),

              // ── SAN Move History Ribbon (Chess.com layout) ──
              _buildChessComMoveRibbon(),

              const SizedBox(height: 10),

              // ── Chess.com Action Toolbar ──
              _buildChessComToolbar(),

              // ── Live Camera or Board Validation if board used ──
              if (_gameUsesBoard && _linkedGameId != null) ...[
                const SizedBox(height: 12),
                _buildLiveBoardPreview(),
                const SizedBox(height: 10),
                _buildBoardValidationActions(),
              ],

              // ── Voice Command Panel ──
              const SizedBox(height: 10),
              _VoiceCommandButton(
                expanded: _voiceExpanded,
                micActive: _micActive,
                voiceStatus: _voiceStatus,
                lastParsedMove: _lastParsedMove,
                micDevices: _micDevices,
                selectedMicId: _selectedMicId,
                micDevicesLoading: _micDevicesLoading,
                micDropdownOpen: _micDropdownOpen,
                onToggle: () =>
                    setState(() => _voiceExpanded = !_voiceExpanded),
                onMicToggle: _onMicToggle,
                onRefreshMics: _loadMicDevices,
                onMicSelected: _selectMicDevice,
                onMicDropdownToggle: () =>
                    setState(() => _micDropdownOpen = !_micDropdownOpen),
              ),

              if (_openingContext != null) ...[
                const SizedBox(height: 12),
                _OpeningHintBanner(name: _openingContext!.name),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Chess.com In-Game Widgets ─────────────────────────────────────────────
  Widget _buildChessComPlayerBar({
    required BuildContext context,
    required String name,
    required String rating,
    required bool isTurn,
    required Duration clock,
    required bool isBot,
    required List<String> capturedPieces,
    required int materialAdvantage,
    required bool isUser,
    required bool isWhitePieceColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isTurn ? kPrimary.withValues(alpha: 0.07) : kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTurn
              ? kPrimary.withValues(alpha: 0.6)
              : kOutlineVariant.withValues(alpha: 0.15),
          width: isTurn ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          if (isUser)
            const AnimatedProfileAvatar(size: 38)
          else if (isBot)
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: kSecondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kSecondary.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: kSecondary, size: 20),
            )
          else
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kPrimary.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.person, color: kPrimary, size: 20),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kOnSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: kSurfaceContHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        rating,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: kOnSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (capturedPieces.isNotEmpty)
                      Text(
                        capturedPieces
                            .map((p) => _pieceGlyph(p, isWhitePieceColor))
                            .join(' '),
                        style: const TextStyle(fontSize: 13, height: 1.1),
                      )
                    else
                      Text(
                        isTurn ? 'TO MOVE' : 'WAITING',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isTurn ? kPrimary : kOnSurfaceVariant,
                          letterSpacing: 1.5,
                        ),
                      ),
                    if (materialAdvantage > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '+$materialAdvantage',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: kPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isTurn
                  ? kPrimary.withValues(alpha: 0.18)
                  : kSurfaceContHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    isTurn ? kPrimary : kOutlineVariant.withValues(alpha: 0.2),
                width: isTurn ? 1.5 : 1,
              ),
              boxShadow: isTurn
                  ? [
                      BoxShadow(
                        color: kPrimary.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              _setupTimeControlMinutes == 0 ? '∞' : _formatClock(clock),
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: isTurn ? kPrimary : kOnSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChessComMoveRibbon() {
    if (_moveHistory.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: kSurfaceContLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            'Make your first move to begin',
            style: GoogleFonts.inter(
                fontSize: 12,
                color: kOnSurfaceVariant,
                fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kOutlineVariant.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _moveHistory.length,
              itemBuilder: (ctx, idx) {
                final move = _moveHistory[idx];
                final isLast = idx == _moveHistory.length - 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Text(
                        '${move[0]}.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kOnSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isLast && move[2] == null
                              ? kPrimary.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          move[1] ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isLast && move[2] == null
                                ? kPrimary
                                : kOnSurface,
                          ),
                        ),
                      ),
                      if (move[2] != null) ...[
                        const SizedBox(width: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isLast
                                ? kPrimary.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            move[2]!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isLast ? kPrimary : kOnSurface,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const VerticalDivider(width: 12, indent: 6, endIndent: 6),
          IconButton(
            icon: const Icon(Icons.undo_rounded, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Undo move',
            onPressed: _undoMove,
          ),
        ],
      ),
    );
  }

  Widget _buildChessComToolbar() {
    final canOfferDraw = _gameMode == 'human_vs_human';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: kSurfaceContLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOutlineVariant.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildToolbarItem(
            icon: Icons.flag_outlined,
            label: 'Resign',
            color: kError,
            onTap:
                _game.game_over || _linkedGameId == null ? null : _resignGame,
          ),
          if (canOfferDraw)
            _buildToolbarItem(
              icon: Icons.handshake_outlined,
              label: 'Draw',
              color: kOnSurfaceVariant,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Draw offer sent')),
                );
              },
            ),
          _buildToolbarItem(
            icon: Icons.undo_rounded,
            label: 'Undo',
            color: kOnSurface,
            onTap: _undoMove,
          ),
          _buildToolbarItem(
            icon: _micActive ? Icons.mic : Icons.mic_none,
            label: 'Voice',
            color: _micActive ? kPrimary : kOnSurfaceVariant,
            onTap: () => setState(() => _voiceExpanded = !_voiceExpanded),
          ),
          if (_gameUsesBoard)
            _buildToolbarItem(
              icon: Icons.videocam_outlined,
              label: 'Board Cam',
              color: _liveFrame != null ? kSecondary : kOnSurfaceVariant,
              onTap: () {
                if (_liveFrame == null) {
                  _fetchLiveFrame();
                } else {
                  _clearSnapshot();
                }
              },
            ),
          _buildToolbarItem(
            icon: Icons.add_circle_outline_rounded,
            label: 'New Match',
            color: kPrimary,
            onTap: _confirmExitToSetup,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: onTap == null ? color.withValues(alpha: 0.3) : color,
                size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: onTap == null ? color.withValues(alpha: 0.3) : color,
              ),
            ),
          ],
        ),
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
          PiLiveCameraView(
            baseUrl: _piBaseUrl,
            onCalibrate: _manualPiCalibrate,
            onFlip: () {
              setState(() {
                _boardFlipped = !_boardFlipped;
              });
            },
          ),
          const SizedBox(height: 12),
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
                      style: GoogleFonts.outfit(
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
                      style: GoogleFonts.outfit(
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
    final isHumanTurn =
        _gameMode != 'human_vs_ai' || _game.turn == _humanColor();
    final inputEnabled = !_gameUsesBoard && !_game.game_over && isHumanTurn;
    final boardTheme = ref.watch(boardThemeProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final boardSize = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0.0, 560.0).toDouble()
            : 560.0;
        return Center(
          child: SizedBox.square(
            dimension: boardSize,
            child: Container(
              decoration: BoxDecoration(
                color: boardTheme.frameColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: kWoodBrassAccent.withOpacity(0.4),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4A2E1B).withOpacity(0.22),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
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
                    final isSelected =
                        inputEnabled && squareName == _selectedSquare;
                    final isLegalDest =
                        inputEnabled && _legalDestinations.contains(squareName);
                    final isLastMove = squareName == _lastMoveFrom ||
                        squareName == _lastMoveTo;

                    final displayRow = _boardFlipped ? 7 - row : row;
                    final displayCol = _boardFlipped ? 7 - col : col;

                    Color bgColor;
                    if (isSelected) {
                      bgColor = kPrimaryContainer.withOpacity(0.45);
                    } else if (isLastMove) {
                      bgColor = kPrimaryContainer.withOpacity(0.22);
                    } else {
                      bgColor = isLight
                          ? boardTheme.lightSquare
                          : boardTheme.darkSquare;
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
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: kPrimary.withOpacity(0.55),
                                ),
                              ),
                            // Legal capture ring
                            if (isLegalDest && piece != null)
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: kPrimary, width: 3),
                                ),
                              ),
                            // Piece
                            if (piece != null)
                              Padding(
                                padding: const EdgeInsets.all(3.0),
                                child: ChessPieceWidget.fromPiece(
                                  piece: piece,
                                ),
                              ),
                            // Rank/file labels
                            if (col == 0)
                              Positioned(
                                top: 2,
                                left: 3,
                                child: Text(
                                  '${8 - displayRow}',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: isLight
                                        ? boardTheme.darkSquare
                                            .withValues(alpha: 0.85)
                                        : boardTheme.lightSquare
                                            .withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                            if (row == 7)
                              Positioned(
                                bottom: 2,
                                right: 3,
                                child: Text(
                                  String.fromCharCode(
                                      'a'.codeUnitAt(0) + displayCol),
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: isLight
                                        ? boardTheme.darkSquare
                                            .withValues(alpha: 0.85)
                                        : boardTheme.lightSquare
                                            .withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBoardThemeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final activeTheme = ref.watch(boardThemeProvider);
            return SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Chessboard Theme',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: kOnSurface,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              size: 20, color: kOnSurfaceVariant),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ...kBoardThemes.map((theme) {
                      final isSelected = theme.id == activeTheme.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: isSelected
                              ? kPrimary.withValues(alpha: 0.08)
                              : kSurfaceContLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isSelected ? kPrimary : kOutlineVariant,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              ref
                                  .read(boardThemeProvider.notifier)
                                  .setTheme(theme);
                              Navigator.pop(ctx);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: theme.frameColor, width: 2),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              children: [
                                                Expanded(
                                                    child: Container(
                                                        color:
                                                            theme.lightSquare)),
                                                Expanded(
                                                    child: Container(
                                                        color:
                                                            theme.darkSquare)),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              children: [
                                                Expanded(
                                                    child: Container(
                                                        color:
                                                            theme.darkSquare)),
                                                Expanded(
                                                    child: Container(
                                                        color:
                                                            theme.lightSquare)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          theme.name,
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: kOnSurface,
                                          ),
                                        ),
                                        Text(
                                          theme.description,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: kOnSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle_rounded,
                                        color: kPrimary, size: 22),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
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
                  style: GoogleFonts.cinzel(
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
                  style: GoogleFonts.outfit(
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
  final PiLocalApi localApi;
  const _PreGameSheet({this.device, required this.localApi});

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
      if (!mounted) return;
      setState(() => _error =
          'Pi setup failed at ${widget.localApi.baseUrl}. Check the Pi agent and network connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadModel() async {
    await _runStep(() async {
      await widget.localApi.loadModel();
      setState(() => _modelLoaded = true);
    });
  }

  Future<void> _autoCalibrate() async {
    await _runStep(() async {
      await widget.localApi.autoCalibrate();
      setState(() {
        _calibrated = true;
        _validated = false;
      });
    });
  }

  Future<void> _manualCalibrate() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualCalibrationScreen(localApi: widget.localApi),
      ),
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
      final data = await widget.localApi.validateStart();
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
      await widget.localApi.forceValidate();
      setState(() {
        _validated = true;
        _validationNote = 'Force-validated: Using assumed initial position.';
      });
    });
  }

  Future<void> _debugCalibration() async {
    await _runStep(() async {
      final data = await widget.localApi.debugCalibration();
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
                style: GoogleFonts.outfit(
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
            if (_opponent == _OpponentType.friend) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kSurfaceContLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kOutlineVariant.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Two players, this device',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kOnSurface)),
                    const SizedBox(height: 4),
                    Text(
                        'Take turns on the same screen or board. To play someone '
                        'remotely instead, challenge them from your friends list.',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: kOnSurfaceVariant)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/friends'),
                        icon: const Icon(Icons.group, size: 16),
                        label: Text('PLAY WITH FRIENDS ONLINE',
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                              style: GoogleFonts.outfit(
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
                              style: GoogleFonts.outfit(
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
                    style: GoogleFonts.outfit(
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

class _PlayerRow extends ConsumerWidget {
  final chess.Chess game;
  const _PlayerRow({required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWhiteTurn = game.turn == chess.Color.WHITE;
    final profileAsync = ref.watch(userProfileProvider);
    final displayName =
        (profileAsync.valueOrNull?.displayName ?? 'Player').toUpperCase();

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
              child: const Icon(Icons.psychology, color: kSecondary, size: 20)),
          const SizedBox(width: 10),
          Flexible(
            child: Text('AI LEVEL 8',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kOnSurface)),
          ),
          const SizedBox(width: 8),
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
          const SizedBox(width: 8),
          const Spacer(),
          Flexible(
            child: Text(displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kOnSurface)),
          ),
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
              style: GoogleFonts.outfit(
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

class _OpeningHintBanner extends StatelessWidget {
  final String name;
  const _OpeningHintBanner({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kPrimary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimary.withOpacity(0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.school, color: kPrimary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('OPENING LESSON',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: kPrimary,
                      letterSpacing: 2)),
              const SizedBox(height: 3),
              Text(name,
                  style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _GameControls extends StatelessWidget {
  final VoidCallback? onUndo;
  final VoidCallback? onAnalyze;
  final VoidCallback? onResign;
  final String gameMode;
  const _GameControls({
    this.onUndo,
    this.onAnalyze,
    this.onResign,
    this.gameMode = 'human_vs_ai',
  });

  @override
  Widget build(BuildContext context) {
    final canOfferDraw = gameMode == 'human_vs_human';
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
      _ControlBtn(
          icon: Icons.flag, label: 'Resign', color: kError, onTap: onResign),
      const SizedBox(width: 12),
      _ControlBtn(
        icon: Icons.handshake,
        label: 'Draw',
        color: canOfferDraw ? kOnSurface : kOnSurfaceVariant.withOpacity(0.4),
        onTap: canOfferDraw ? () {} : null,
      ),
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
                    style: GoogleFonts.outfit(
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
