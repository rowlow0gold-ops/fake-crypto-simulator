import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/firestore_service.dart';
import '../store/app_state.dart';
import '../theme/theme.dart';

/// Main game tab — shows create/join when not in a game, or the live room when active.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    if (!s.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(
            title: const Text('Play', style: TextStyle(fontWeight: FontWeight.w700))),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Sign in with Google in Settings to play with friends.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.dim, fontSize: 15),
            ),
          ),
        ),
      );
    }

    if (s.inGame) {
      return const _ActiveGameView();
    }

    return Scaffold(
      appBar: AppBar(
          title: const Text('Play', style: TextStyle(fontWeight: FontWeight.w700))),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Icon(Icons.sports_esports_outlined,
                size: 64, color: AppColors.dim),
            const SizedBox(height: 16),
            const Text('Challenge your friends',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Create a room or join with a code. Trade with a game wallet and see who ends up on top.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.dim),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => _showCreateDialog(context),
                child: const Text('Create room',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => _showJoinDialog(context),
                child: const Text('Join with code',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.text)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showJoinDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Join room'),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          style: const TextStyle(fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: '------',
            hintStyle: TextStyle(color: AppColors.dim),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.dim))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent, foregroundColor: AppColors.bg),
            onPressed: () async {
              final code = ctrl.text.trim();
              if (code.length != 6) return;
              Navigator.pop(ctx);
              final ok = await context.read<AppState>().joinRoom(code);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Room not found or already ended')),
                );
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (_) => const _CreateRoomSheet(),
    );
  }
}

// ---------- Create room bottom sheet ----------

class _CreateRoomSheet extends StatefulWidget {
  const _CreateRoomSheet();
  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  String _mode = 'specials'; // 'original' or 'specials'
  String _classMode = 'choose'; // 'random', 'choose', 'vote'
  ClassTier _class = ClassTier.middle;
  int _timeMins = 60;
  String _visibility = 'full';
  bool _creating = false;

  static const _timeLimits = [
    (label: '1h', mins: 60),
    (label: '3h', mins: 180),
    (label: '6h', mins: 360),
    (label: '12h', mins: 720),
    (label: '1d', mins: 1440),
    (label: '3d', mins: 4320),
    (label: '7d', mins: 10080),
    (label: '14d', mins: 20160),
    (label: '1m', mins: 43200),
    (label: '3m', mins: 129600),
    (label: '6m', mins: 259200),
    (label: '1y', mins: 525600),
  ];

  static const _visOptions = [
    (label: 'Total only', value: 'total'),
    (label: 'Full holdings', value: 'full'),
    (label: 'Hidden (reveal at end)', value: 'hidden'),
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: ListView(
          controller: scrollCtrl,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.dim,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Create room',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            // Mode
            _sectionLabel('Game mode'),
            _chipRow([
              _chip('Use real portfolio', _mode == 'original',
                  () => setState(() => _mode = 'original')),
              _chip('Fresh wallet', _mode == 'specials',
                  () => setState(() => _mode = 'specials')),
            ]),

            // Class (only for specials)
            if (_mode == 'specials') ...[
              const SizedBox(height: 16),
              _sectionLabel('Class selection'),
              _chipRow([
                _chip('Choose', _classMode == 'choose',
                    () => setState(() => _classMode = 'choose')),
                _chip('Random', _classMode == 'random',
                    () => setState(() => _classMode = 'random')),
              ]),
              if (_classMode == 'choose') ...[
                const SizedBox(height: 12),
                _sectionLabel('Your class'),
                Wrap(
                  spacing: 8,
                  children: ClassTier.values.map((t) {
                    final active = _class == t;
                    return ChoiceChip(
                      label: Text(
                          '${kClassLabels[t]} (\$${NumberFormat.compact().format(kStartingBalance[t])})'),
                      selected: active,
                      onSelected: (_) => setState(() => _class = t),
                      selectedColor: AppColors.accent,
                      backgroundColor: AppColors.cardAlt,
                      labelStyle: TextStyle(
                        color: active ? AppColors.bg : AppColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],

            // Time limit
            const SizedBox(height: 16),
            _sectionLabel('Time limit'),
            Wrap(
              spacing: 8,
              children: _timeLimits.map((t) {
                final active = _timeMins == t.mins;
                return ChoiceChip(
                  label: Text(t.label),
                  selected: active,
                  onSelected: (_) => setState(() => _timeMins = t.mins),
                  selectedColor: AppColors.accent,
                  backgroundColor: AppColors.cardAlt,
                  labelStyle: TextStyle(
                    color: active ? AppColors.bg : AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),

            // Visibility
            const SizedBox(height: 16),
            _sectionLabel('What others see'),
            Wrap(
              spacing: 8,
              children: _visOptions.map((v) {
                final active = _visibility == v.value;
                return ChoiceChip(
                  label: Text(v.label),
                  selected: active,
                  onSelected: (_) => setState(() => _visibility = v.value),
                  selectedColor: AppColors.accent,
                  backgroundColor: AppColors.cardAlt,
                  labelStyle: TextStyle(
                    color: active ? AppColors.bg : AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: AppColors.bg,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _creating ? null : _create,
                child: _creating
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg))
                    : const Text('Create & share code',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    final s = context.read<AppState>();
    final code = await s.createRoom(
      mode: _mode,
      specialsCash: kStartingBalance[_class] ?? 10000,
      classMode: _classMode,
      timeLimitMinutes: _timeMins,
      visibility: _visibility,
      creatorClass: _class,
    );
    if (!mounted) return;
    Navigator.pop(context);
    // Show the code in a dialog
    _showCodeDialog(context, code);
  }

  void _showCodeDialog(BuildContext context, String code) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Room created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this code with your friends:',
                style: TextStyle(color: AppColors.dim)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Code copied!')),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 8,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Tap to copy', style: TextStyle(color: AppColors.dim, fontSize: 12)),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent, foregroundColor: AppColors.bg),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.dim, fontWeight: FontWeight.w600, fontSize: 13)),
      );

  Widget _chipRow(List<Widget> chips) =>
      Row(children: chips.map((c) => Expanded(child: c)).toList());

  Widget _chip(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: active ? AppColors.accent : AppColors.cardAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                  color: active ? AppColors.bg : AppColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                )),
          ),
        ),
      );
}

// ---------- Active game view ----------

class _ActiveGameView extends StatefulWidget {
  const _ActiveGameView();
  @override
  State<_ActiveGameView> createState() => _ActiveGameViewState();
}

class _ActiveGameViewState extends State<_ActiveGameView> {
  Timer? _timer;
  final _chatCtrl = TextEditingController();
  final _chatScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Refresh every 5s so time-left + leaderboard values stay current.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
      // Also push our updated portfolio value to Firestore
      final s = context.read<AppState>();
      if (s.inGame) s.syncGameWallet();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chatCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final data = s.activeRoomData;
    if (data == null) return const SizedBox.shrink();

    final code = data['code'] as String? ?? s.activeRoomCode ?? '';
    final status = data['status'] as String? ?? 'active';
    final visibility = data['visibility'] as String? ?? 'full';
    final mode = data['mode'] as String? ?? 'specials';
    final leaderboard = s.roomLeaderboard();
    final usd = NumberFormat.currency(locale: 'en_US', symbol: '\$');

    // Time remaining
    String timeLeft = '';
    if (data['endsAt'] != null && status == 'active') {
      final end = (data['endsAt'] as dynamic);
      DateTime endTime;
      try {
        endTime = end.toDate();
      } catch (_) {
        endTime = DateTime.now().add(const Duration(hours: 999));
      }
      final diff = endTime.difference(DateTime.now());
      if (diff.isNegative) {
        timeLeft = 'Ended';
      } else if (diff.inDays > 0) {
        timeLeft = '${diff.inDays}d ${diff.inHours % 24}h left';
      } else if (diff.inHours > 0) {
        timeLeft = '${diff.inHours}h ${diff.inMinutes % 60}m left';
      } else if (diff.inMinutes > 0) {
        timeLeft = '${diff.inMinutes}m ${diff.inSeconds % 60}s left';
      } else {
        timeLeft = '${diff.inSeconds}s left';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Game ', style: TextStyle(fontWeight: FontWeight.w700)),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied!')),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(code,
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        fontSize: 14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _confirmLeave(context, s),
            child: const Text('Leave', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom + 60),
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _badge(status == 'lobby'
                    ? 'Lobby'
                    : status == 'ended'
                        ? 'Ended'
                        : 'Live',
                    status == 'active' ? AppColors.green : AppColors.dim),
                Text(mode == 'original' ? 'Real portfolio' : 'Fresh wallet',
                    style: const TextStyle(color: AppColors.dim, fontSize: 12)),
                if (timeLeft.isNotEmpty)
                  Text(timeLeft,
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Lobby
          if (status == 'lobby') _lobbySection(context, s, data),

          // Leaderboard
          const Text('Leaderboard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...List.generate(leaderboard.length, (i) {
            final m = leaderboard[i];
            final isMe = m['uid'] == s.uid;
            final name = m['displayName'] as String? ?? 'Player';
            final val = (m['portfolioValue'] as num?)?.toDouble() ?? 0;
            final cls = m['class'] as String? ?? 'middle';

            // Medal for top 3
            String? medal;
            Color? medalColor;
            if (i == 0) { medal = '1st'; medalColor = const Color(0xFFFFD700); }
            else if (i == 1) { medal = '2nd'; medalColor = const Color(0xFFC0C0C0); }
            else if (i == 2) { medal = '3rd'; medalColor = const Color(0xFFCD7F32); }

            // Extract holdings for visibility
            List<MapEntry<String, dynamic>> holdings = [];
            if (visibility == 'full' || status == 'ended') {
              try {
                final wallet = m['gameWallet'] as Map<String, dynamic>?;
                if (wallet != null && wallet['holdings'] != null) {
                  holdings = (wallet['holdings'] as Map<String, dynamic>).entries.toList();
                }
              } catch (_) {}
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isMe
                    ? AppColors.accent.withOpacity(0.1)
                    : i < 3
                        ? medalColor!.withOpacity(0.06)
                        : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isMe
                        ? AppColors.accent
                        : i < 3
                            ? medalColor!.withOpacity(0.4)
                            : AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Rank badge for top 3, plain number for rest
                      if (medal != null)
                        Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: medalColor!.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            medal,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              color: medalColor,
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${i + 1}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.dim,
                            ),
                          ),
                        ),
                      if (m['photoUrl'] != null)
                        CircleAvatar(
                          backgroundImage: NetworkImage(m['photoUrl']),
                          radius: 16,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$name${isMe ? ' (you)' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(kClassLabels[tierFromString(cls)] ?? cls,
                                style: const TextStyle(
                                    color: AppColors.dim, fontSize: 11)),
                          ],
                        ),
                      ),
                      if (visibility != 'hidden' || status == 'ended')
                        Text(usd.format(val),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: i < 3 ? 16 : 14,
                            )),
                      if (visibility == 'hidden' && status != 'ended')
                        const Text('???',
                            style: TextStyle(
                                color: AppColors.dim, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  // Holdings row
                  if (holdings.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: holdings.map((e) {
                        final h = e.value as Map<String, dynamic>;
                        final coinId = h['coinId'] as String? ?? e.key;
                        final amt = (h['amount'] as num?)?.toDouble() ?? 0;
                        final costBasis = (h['costBasisUsd'] as num?)?.toDouble() ?? 0;
                        final avg = amt > 0 ? costBasis / amt : 0.0;
                        final meta = s.metaOf(coinId);
                        final price = s.priceOf(coinId);
                        final valH = amt * price;
                        if (valH < 0.01) return const SizedBox.shrink();
                        final plPct = avg > 0 ? (price - avg) / avg * 100 : 0.0;
                        final rowUp = plPct >= 0;
                        final avgFmt = avg > 10
                            ? usd.format(avg)
                            : '\$${avg.toStringAsFixed(4)}';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.cardAlt,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${meta.symbol} ${usd.format(valH)}',
                                style: const TextStyle(fontSize: 11, color: AppColors.text),
                              ),
                              Text(
                                'avg $avgFmt  ${rowUp ? '+' : ''}${plPct.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: rowUp ? AppColors.green : AppColors.red,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // Invite button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Invite — share code'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Room code $code copied!')),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Chat
          const Text('Chat',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _chatSection(s, code),
        ],
      ),
    );
  }

  Widget _chatSection(AppState s, String code) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: FirestoreService.chatStream(code),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: Text('No messages yet',
                          style: TextStyle(color: AppColors.dim)));
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                      child: Text('No messages yet',
                          style: TextStyle(color: AppColors.dim)));
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_chatScroll.hasClients) {
                    _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
                  }
                });
                return ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.all(10),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final isMe = d['uid'] == s.uid;
                    final name = d['displayName'] as String? ?? '';
                    final text = d['text'] as String? ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe && d['photoUrl'] != null)
                            CircleAvatar(
                              backgroundImage: NetworkImage(d['photoUrl']),
                              radius: 12,
                            ),
                          if (!isMe && d['photoUrl'] != null) const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Text(name,
                                      style: const TextStyle(
                                          color: AppColors.dim, fontSize: 10)),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? AppColors.accent.withOpacity(0.2)
                                        : AppColors.cardAlt,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(text,
                                      style: const TextStyle(fontSize: 13)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatCtrl,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: AppColors.dim, fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: AppColors.accent, size: 20),
                  onPressed: () {
                    final text = _chatCtrl.text.trim();
                    if (text.isEmpty) return;
                    FirestoreService.sendMessage(
                      code: code,
                      uid: s.uid!,
                      displayName: s.displayName,
                      photoUrl: s.photoUrl,
                      text: text,
                    );
                    _chatCtrl.clear();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lobbySection(BuildContext context, AppState s, Map<String, dynamic> data) {
    final isCreator = data['createdBy'] == s.uid;
    final members = data['members'] as Map<String, dynamic>? ?? {};
    return Column(
      children: [
        Text('${members.length} player${members.length == 1 ? '' : 's'} in the room. Share the code to invite more.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.dim)),
        const SizedBox(height: 16),
        if (isCreator)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: AppColors.bg,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => s.startGameFromLobby(),
              child: const Text('Start game',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          )
        else
          const Text('Waiting for the host to start...',
              style: TextStyle(color: AppColors.dim, fontStyle: FontStyle.italic)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );

  void _confirmLeave(BuildContext context, AppState s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Leave room?'),
        content: const Text(
            'You can rejoin later with the same code if the room is still active.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Stay', style: TextStyle(color: AppColors.dim))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.red, foregroundColor: AppColors.bg),
            onPressed: () {
              Navigator.pop(ctx);
              s.leaveRoom();
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }
}
