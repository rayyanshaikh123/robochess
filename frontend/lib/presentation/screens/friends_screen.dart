import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/errors/api_exception.dart';
import '../../domain/models/challenge_model.dart';
import '../../domain/models/friend_model.dart';
import '../providers/social_provider.dart';

// ── Colour tokens ──────────────────────────────────────
const kBackground = Color(0xFF151311);
const kSurfaceContLowest = Color(0xFF0F0E0C);
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

enum _Tab { friends, incoming, sent, search }

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  _Tab _tab = _Tab.friends;
  final _searchController = TextEditingController();
  Timer? _debounce;
  StreamSubscription<String>? _gameStarted;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    // A challenge accepted by either side creates the game; jump straight in.
    _gameStarted = ref
        .read(challengesProvider.notifier)
        .gameStarted
        .listen(_openGame);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gameStarted?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _openGame(String gameId) {
    if (!mounted || gameId.isEmpty) return;
    context.go('/play/game/$gameId');
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? kSurfaceContHigh : null,
      ),
    );
  }

  /// Run a mutation, surfacing the server's own message when it refuses.
  Future<void> _run(String id, Future<void> Function() action,
      {String? success}) async {
    setState(() => _busyId = id);
    try {
      await action();
      if (success != null) _toast(success);
    } on ApiException catch (err) {
      _toast(err.message, isError: true);
    } catch (_) {
      _toast('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(userSearchProvider.notifier).search(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final friendsState = ref.watch(friendsProvider);
    final challengesState = ref.watch(challengesProvider);

    final incomingCount =
        friendsState.valueOrNull?.incoming.length ?? 0;
    final challengeCount =
        challengesState.valueOrNull?.incoming.length ?? 0;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        title: Text('PLAY WITH FRIENDS',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kPrimary,
                letterSpacing: 2)),
        actions: [
          IconButton(
            tooltip: 'Your games',
            onPressed: () => context.go('/play/games'),
            icon: const Icon(Icons.sports_esports, color: kOnSurfaceVariant),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kPrimary,
        backgroundColor: kSurfaceContLow,
        onRefresh: () async {
          await ref.read(friendsProvider.notifier).load();
          await ref.read(challengesProvider.notifier).load();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            if (challengeCount > 0) ...[
              _IncomingChallenges(
                challenges: challengesState.valueOrNull!.incoming,
                busyId: _busyId,
                onAccept: (challenge) => _run(
                  challenge.challengeId,
                  () async {
                    final gameId = await ref
                        .read(challengesProvider.notifier)
                        .accept(challenge.challengeId);
                    _openGame(gameId);
                  },
                ),
                onReject: (challenge) => _run(
                  challenge.challengeId,
                  () => ref
                      .read(challengesProvider.notifier)
                      .reject(challenge.challengeId),
                  success: 'Challenge declined',
                ),
              ),
              const SizedBox(height: 24),
            ],
            _TabBar(
              current: _tab,
              incomingCount: incomingCount,
              onChanged: (tab) {
                setState(() => _tab = tab);
                if (tab != _Tab.search) {
                  _searchController.clear();
                  ref.read(userSearchProvider.notifier).clear();
                }
              },
            ),
            const SizedBox(height: 20),
            if (_tab == _Tab.search) _buildSearch() else _buildList(friendsState),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() {
    final results = ref.watch(userSearchProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: GoogleFonts.inter(fontSize: 14, color: kOnSurface),
          decoration: InputDecoration(
            hintText: 'Search by name, or exact email',
            hintStyle:
                GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant),
            prefixIcon: const Icon(Icons.search, color: kOnSurfaceVariant),
            filled: true,
            fillColor: kSurfaceContLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        results.when(
          data: (items) {
            if (_searchController.text.trim().length < 2) {
              return const _Hint(
                  'Type at least 2 characters to find players.');
            }
            if (items.isEmpty) {
              return const _Hint('No players matched that search.');
            }
            return Column(
              children: items
                  .map((user) => _SearchRow(
                        user: user,
                        busy: _busyId == user.userId,
                        onAdd: () => _run(
                          user.userId,
                          () => ref
                              .read(friendsProvider.notifier)
                              .sendRequest(user.userId),
                          success: 'Friend request sent',
                        ),
                        onChallenge: () => _challenge(user.userId,
                            user.displayName),
                      ))
                  .toList(),
            );
          },
          loading: () => const LinearProgressIndicator(
            backgroundColor: kSurfaceContHighest,
            valueColor: AlwaysStoppedAnimation<Color>(kPrimary),
            minHeight: 6,
          ),
          error: (_, __) => const _Hint('Search failed. Please try again.'),
        ),
      ],
    );
  }

  Widget _buildList(AsyncValue<FriendsState> state) {
    return state.when(
      data: (data) {
        final rows = switch (_tab) {
          _Tab.friends => data.friends,
          _Tab.incoming => data.incoming,
          _Tab.sent => data.outgoing,
          _Tab.search => const <FriendModel>[],
        };
        if (rows.isEmpty) {
          return _Hint(switch (_tab) {
            _Tab.friends =>
              'No friends yet. Use Search to find players and send a request.',
            _Tab.incoming => 'No incoming friend requests.',
            _Tab.sent => 'No pending sent requests.',
            _Tab.search => '',
          });
        }
        return Column(
          children: rows
              .map((row) => _FriendRow(
                    friend: row,
                    tab: _tab,
                    busy: _busyId == row.friendshipId,
                    onAccept: () => _run(
                      row.friendshipId,
                      () => ref
                          .read(friendsProvider.notifier)
                          .acceptRequest(row.friendshipId),
                      success: 'You are now friends',
                    ),
                    onReject: () => _run(
                      row.friendshipId,
                      () => ref
                          .read(friendsProvider.notifier)
                          .rejectRequest(row.friendshipId),
                      success: 'Request declined',
                    ),
                    onCancel: () => _run(
                      row.friendshipId,
                      () => ref
                          .read(friendsProvider.notifier)
                          .cancelRequest(row.friendshipId),
                      success: 'Request cancelled',
                    ),
                    onRemove: () => _confirmRemove(row),
                    onChallenge: () =>
                        _challenge(row.user.userId, row.user.displayName),
                  ))
              .toList(),
        );
      },
      loading: () => const LinearProgressIndicator(
        backgroundColor: kSurfaceContHighest,
        valueColor: AlwaysStoppedAnimation<Color>(kPrimary),
        minHeight: 6,
      ),
      error: (_, __) =>
          const _Hint('Could not load your friends. Pull to retry.'),
    );
  }

  Future<void> _confirmRemove(FriendModel friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurfaceContLow,
        title: const Text('Remove friend?'),
        content: Text(
            '${friend.user.displayName} will be removed from your friends list.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      friend.friendshipId,
      () => ref.read(friendsProvider.notifier).removeFriend(friend.user.userId),
      success: 'Friend removed',
    );
  }

  Future<void> _challenge(String userId, String displayName) async {
    final options = await ref.read(timeControlsProvider.future).catchError(
          (_) => <TimeControlOption>[],
        );
    if (!mounted) return;

    final result = await showModalBottomSheet<_ChallengeChoice>(
      context: context,
      backgroundColor: kBackground,
      isScrollControlled: true,
      builder: (_) => _ChallengeSheet(
        displayName: displayName,
        timeControls: options,
      ),
    );
    if (result == null || !mounted) return;

    await _run(
      userId,
      () => ref.read(challengesProvider.notifier).create(
            opponentId: userId,
            timeControl: result.timeControl,
            color: result.color,
            surface: result.surface,
          ),
      success: 'Challenge sent to $displayName',
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────────

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text,
            style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant)),
      );
}

class _TabBar extends StatelessWidget {
  final _Tab current;
  final int incomingCount;
  final ValueChanged<_Tab> onChanged;

  const _TabBar({
    required this.current,
    required this.incomingCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget tab(_Tab value, String label, {int badge = 0}) {
      final selected = value == current;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? kPrimary.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected
                      ? kPrimary
                      : kOutlineVariant.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: selected ? kPrimary : kOnSurfaceVariant)),
                if (badge > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: kPrimary,
                        borderRadius: BorderRadius.circular(99)),
                    child: Text('$badge',
                        style: GoogleFonts.inter(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: kOnPrimary)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(_Tab.friends, 'FRIENDS'),
        const SizedBox(width: 8),
        tab(_Tab.incoming, 'INBOX', badge: incomingCount),
        const SizedBox(width: 8),
        tab(_Tab.sent, 'SENT'),
        const SizedBox(width: 8),
        tab(_Tab.search, 'SEARCH'),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: kSurfaceContHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person, color: kOnSurfaceVariant),
            ),
          ],
        ),
      );
}

class _RowShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const _RowShell({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSurfaceContLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kOutlineVariant.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const _Avatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: kOnSurface)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: kOnSurfaceVariant)),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      );
}

Widget _actionButton(String label, VoidCallback? onTap, {Color? color}) {
  return TextButton(
    onPressed: onTap,
    child: Text(label,
        style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: onTap == null ? kOnSurfaceVariant : (color ?? kPrimary))),
  );
}

class _FriendRow extends StatelessWidget {
  final FriendModel friend;
  final _Tab tab;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCancel;
  final VoidCallback onRemove;
  final VoidCallback onChallenge;

  const _FriendRow({
    required this.friend,
    required this.tab,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    required this.onCancel,
    required this.onRemove,
    required this.onChallenge,
  });

  @override
  Widget build(BuildContext context) {
    final rating = friend.user.rating;
    final subtitle = switch (tab) {
      _Tab.friends => rating == null ? 'Friend' : 'Rating $rating',
      _Tab.incoming => 'Wants to be friends',
      _Tab.sent => 'Request pending',
      _Tab.search => '',
    };

    final actions = <Widget>[];
    if (busy) {
      actions.add(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
      ));
    } else {
      switch (tab) {
        case _Tab.friends:
          actions.add(_actionButton('PLAY', onChallenge));
          actions.add(IconButton(
            tooltip: 'Remove friend',
            onPressed: onRemove,
            icon: const Icon(Icons.person_remove_outlined,
                size: 18, color: kOnSurfaceVariant),
          ));
          break;
        case _Tab.incoming:
          actions.add(_actionButton('ACCEPT', onAccept));
          actions.add(_actionButton('DECLINE', onReject, color: kError));
          break;
        case _Tab.sent:
          actions.add(_actionButton('CANCEL', onCancel, color: kError));
          break;
        case _Tab.search:
          break;
      }
    }

    return _RowShell(
      title: friend.user.displayName,
      subtitle: subtitle,
      actions: actions,
    );
  }
}

class _SearchRow extends StatelessWidget {
  final UserSearchResult user;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onChallenge;

  const _SearchRow({
    required this.user,
    required this.busy,
    required this.onAdd,
    required this.onChallenge,
  });

  @override
  Widget build(BuildContext context) {
    late final String subtitle;
    late final Widget action;

    if (busy) {
      subtitle = 'Working...';
      action = const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
      );
    } else if (user.isFriend) {
      subtitle = 'Already friends';
      action = _actionButton('PLAY', onChallenge);
    } else if (user.isPending) {
      subtitle = user.requestedByMe ? 'Request sent' : 'Wants to be friends';
      action = _actionButton('PENDING', null);
    } else {
      subtitle = user.rating == null ? 'Player' : 'Rating ${user.rating}';
      action = _actionButton('ADD', onAdd);
    }

    return _RowShell(
        title: user.displayName, subtitle: subtitle, actions: [action]);
  }
}

class _IncomingChallenges extends StatelessWidget {
  final List<ChallengeModel> challenges;
  final String? busyId;
  final void Function(ChallengeModel) onAccept;
  final void Function(ChallengeModel) onReject;

  const _IncomingChallenges({
    required this.challenges,
    required this.busyId,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.sports_esports, color: kSecondary, size: 18),
            const SizedBox(width: 8),
            Text('GAME CHALLENGES',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: kOnSurface)),
          ],
        ),
        const SizedBox(height: 12),
        ...challenges.map((challenge) {
          final busy = busyId == challenge.challengeId;
          final expired = challenge.hasExpired;
          return _RowShell(
            title: challenge.opponent.displayName,
            subtitle: expired
                ? 'Challenge expired'
                : '${challenge.timeControlLabel ?? 'Unlimited'} · tap Accept to play',
            actions: busy
                ? const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kPrimary)),
                    )
                  ]
                : [
                    if (!expired)
                      _actionButton('ACCEPT', () => onAccept(challenge)),
                    _actionButton('DECLINE', () => onReject(challenge),
                        color: kError),
                  ],
          );
        }),
      ],
    );
  }
}

// ── Challenge sheet ───────────────────────────────────────────────────────────

class _ChallengeChoice {
  final String? timeControl;
  final String color;
  final String surface;
  const _ChallengeChoice(this.timeControl, this.color, this.surface);
}

class _ChallengeSheet extends StatefulWidget {
  final String displayName;
  final List<TimeControlOption> timeControls;

  const _ChallengeSheet({
    required this.displayName,
    required this.timeControls,
  });

  @override
  State<_ChallengeSheet> createState() => _ChallengeSheetState();
}

class _ChallengeSheetState extends State<_ChallengeSheet> {
  String _timeControl = 'unlimited';
  String _color = 'random';
  String _surface = 'app';

  @override
  Widget build(BuildContext context) {
    final options = widget.timeControls.isEmpty
        ? const [TimeControlOption(key: 'unlimited', label: 'Unlimited')]
        : widget.timeControls;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Challenge ${widget.displayName}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kOnSurface)),
          const SizedBox(height: 4),
          Text('They will get a notification and can accept or decline.',
              style:
                  GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant)),
          const SizedBox(height: 20),
          _label('TIME CONTROL'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options
                .map((option) => _chip(option.label, _timeControl == option.key,
                    () => setState(() => _timeControl = option.key)))
                .toList(),
          ),
          const SizedBox(height: 20),
          _label('YOUR COLOUR'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _chip('Random', _color == 'random',
                  () => setState(() => _color = 'random')),
              _chip('White', _color == 'white',
                  () => setState(() => _color = 'white')),
              _chip('Black', _color == 'black',
                  () => setState(() => _color = 'black')),
            ],
          ),
          const SizedBox(height: 20),
          _label('PLAY ON'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _chip('This app', _surface == 'app',
                  () => setState(() => _surface = 'app')),
              _chip('My board', _surface == 'board',
                  () => setState(() => _surface = 'board')),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: kPrimary, foregroundColor: kOnPrimary),
              onPressed: () => Navigator.of(context).pop(
                _ChallengeChoice(
                  _timeControl == 'unlimited' ? null : _timeControl,
                  _color,
                  _surface,
                ),
              ),
              icon: const Icon(Icons.send, size: 18),
              label: Text('SEND CHALLENGE',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: kOnSurfaceVariant));

  Widget _chip(String label, bool selected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? kPrimary.withOpacity(0.15) : kSurfaceContLowest,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
                color:
                    selected ? kPrimary : kOutlineVariant.withOpacity(0.3)),
          ),
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? kPrimary : kOnSurfaceVariant)),
        ),
      );
}
