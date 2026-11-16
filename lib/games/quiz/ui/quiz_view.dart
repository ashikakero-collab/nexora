import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../core/game_contract.dart';
import '../core/question_bank.dart';
import '../core/question_model.dart';
import '../core/quiz_engine.dart';
import 'quiz_widgets.dart';

/// Full-screen NEXORA Quiz match (vs bot or same-device split screen).
class QuizView extends StatefulWidget {
  const QuizView({super.key, required this.launch});

  final GameLaunch launch;

  @override
  State<QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<QuizView> with TickerProviderStateMixin {
  late final QuizEngine _engine;
  late final AnimationController _clock;
  late final AnimationController _reveal;
  late final AnimationController _pulse;
  Timer? _botTimer;
  Timer? _advanceTimer;
  bool _botThinking = false;
  bool _finishSent = false;

  GameLaunch get _l => widget.launch;
  bool get _local => _l.mode == GameMode.local;

  // ------------------------------------------------------------- online
  // Engine player 0 is always THIS phone, 1 the opponent (the quiz is symmetric).
  NetInbox? _inbox;
  Timer? _graceTimer;
  bool get _online => _l.online;
  int get _other => _l.mySeat == 0 ? 1 : 0;
  int _ep(int seat) => seat == _l.mySeat ? 0 : 1;
  bool get _iPick => !_online || _l.mySeat == 0;

  Future<void> _onNet(NetMove m) async {
    if (!mounted) return;
    if (m.kind == 'replayDone') {
      switch (_engine.phase) {
        case QuizPhase.picking:
          setState(() {});
        case QuizPhase.question:
          _startRound();
        case QuizPhase.reveal:
          _onReveal();
        case QuizPhase.finished:
          setState(() {});
      }
      return;
    }
    final String a = '${m.data['a']}';
    if (a == 'cat') {
      if (_engine.phase != QuizPhase.picking) return;
      final int ci = (m.data['c'] as num?)?.toInt() ?? -1;
      _engine.start(ci < 0 || ci >= QuizCategory.values.length
          ? null
          : QuizCategory.values[ci]);
      if (!m.replay) {
        setState(() {});
        if (_engine.phase == QuizPhase.question) _startRound();
      }
      return;
    }
    if (a != 'ans') return;
    final int r = (m.data['r'] as num?)?.toInt() ?? 0;
    if (m.replay) {
      while (_engine.phase == QuizPhase.reveal && _engine.roundIndex < r) {
        _engine.next();
      }
    } else {
      while (true) {
        if (!mounted ||
            _engine.phase == QuizPhase.finished ||
            _engine.roundIndex > r) {
          return;
        }
        if (_engine.roundIndex == r) break;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
    if (_engine.roundIndex != r || _engine.phase != QuizPhase.question) return;
    final int p = _ep(m.seat);
    final int c = (m.data['c'] as num?)?.toInt() ?? -1;
    if (c < 0) {
      _engine.submitTimeout(p);
    } else {
      _engine.submit(
          p, c, (m.data['ms'] as num?)?.toInt() ?? QuizEngine.timeLimitMs);
    }
    if (!m.replay) _afterAnswer();
  }

  @override
  void initState() {
    super.initState();
    _engine = QuizEngine(
      bank: kQuestionBank,
      seed: _l.seed ?? DateTime.now().millisecondsSinceEpoch,
      vsBot: !_local,
      botLevel: switch (_l.difficulty) {
        BotDifficulty.easy => QuizBotLevel.easy,
        BotDifficulty.normal => QuizBotLevel.normal,
        BotDifficulty.hard => QuizBotLevel.hard,
      },
    );
    _clock = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: QuizEngine.timeLimitMs))
      ..addStatusListener((AnimationStatus s) {
        if (s == AnimationStatus.completed) _onTimeUp();
      });
    _reveal = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    if (_l.fancyEffects && !_l.reducedMotion) _pulse.repeat(reverse: true);
    final NetLink? net = _l.net;
    if (net != null) {
      final NetInbox inbox = NetInbox(_onNet);
      _inbox = inbox;
      net.listen(inbox.add,
          onReplayDone: () => inbox.add(const NetMove(
              seq: -1,
              seat: -1,
              kind: 'replayDone',
              data: <String, dynamic>{})));
    }
  }

  @override
  void dispose() {
    _inbox?.close();
    _graceTimer?.cancel();
    _botTimer?.cancel();
    _advanceTimer?.cancel();
    _clock.dispose();
    _reveal.dispose();
    _pulse.dispose();
    super.dispose();
  }

  int get _elapsedMs => (_clock.value * QuizEngine.timeLimitMs).round();

  void _haptic([bool heavy = false]) {
    if (!_l.soundOn) return;
    if (heavy) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  // ------------------------------------------------------------------ flow

  void _pickCategory(QuizCategory? c) {
    if (!_iPick || _engine.phase != QuizPhase.picking) return;
    if (_online) {
      _l.net!.send(<String, dynamic>{'a': 'cat', 'c': c?.index ?? -1});
    }
    _haptic();
    setState(() => _engine.start(c));
    if (_engine.phase == QuizPhase.question) {
      _startRound();
    }
  }

  void _startRound() {
    _botTimer?.cancel();
    _reveal.value = 0;
    _clock.forward(from: 0);
    if (_online) {
      _botThinking = !_engine.hasAnswered(1);
      _graceTimer?.cancel();
      final int round = _engine.roundIndex;
      // Opponent disconnected? The authority records their timeout so the match never stalls.
      _graceTimer = Timer(
          const Duration(milliseconds: QuizEngine.timeLimitMs + 9000), () {
        if (!mounted ||
            _engine.roundIndex != round ||
            _engine.phase != QuizPhase.question) {
          return;
        }
        if (_engine.hasAnswered(1) || !(_l.net?.isAuthority ?? false)) return;
        _l.net!.send(<String, dynamic>{
          'a': 'ans',
          'r': round,
          'c': -1,
          'ms': QuizEngine.timeLimitMs
        }, kind: 'timeout', asSeat: _other);
        _engine.submitTimeout(1);
        _afterAnswer();
      });
    } else if (!_local) {
      final QuizBotPlan plan = _engine.botPlan(_engine.currentQuestion);
      _botThinking = true;
      _botTimer = Timer(Duration(milliseconds: plan.delayMs), () {
        if (!mounted || _engine.phase != QuizPhase.question) return;
        _botThinking = false;
        _engine.submit(1, plan.choice, plan.delayMs);
        _afterAnswer();
      });
    }
    setState(() {});
  }

  void _answer(int player, int choice) {
    if (_engine.phase != QuizPhase.question || _engine.hasAnswered(player)) {
      return;
    }
    final int ms = _elapsedMs;
    final int round = _engine.roundIndex;
    if (_online && player != 0) return;
    if (_engine.submit(player, choice, ms)) {
      if (_online) {
        _l.net!.send(
            <String, dynamic>{'a': 'ans', 'r': round, 'c': choice, 'ms': ms});
      }
      _haptic();
      _afterAnswer();
    }
  }

  void _afterAnswer() {
    if (_online && _engine.hasAnswered(1)) _botThinking = false;
    if (_engine.phase == QuizPhase.reveal) {
      _onReveal();
    } else {
      setState(() {});
    }
  }

  void _onTimeUp() {
    if (_engine.phase != QuizPhase.question) return;
    if (_online) {
      // Only my own timeout is mine to record; the round closes when the opponent's answer arrives.
      if (_engine.submitTimeout(0)) {
        _l.net!.send(<String, dynamic>{
          'a': 'ans',
          'r': _engine.roundIndex,
          'c': -1,
          'ms': QuizEngine.timeLimitMs
        });
      }
      _afterAnswer();
      return;
    }
    _engine.timeUp();
    _onReveal();
  }

  void _onReveal() {
    _clock.stop();
    _graceTimer?.cancel();
    _botTimer?.cancel();
    _botThinking = false;
    _haptic(true);
    _reveal.forward(from: 0);
    setState(() {});
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 2300), () {
      if (!mounted) return;
      _engine.next();
      if (_engine.phase == QuizPhase.finished) {
        setState(() {});
      } else {
        _startRound();
      }
    });
  }

  void _finish() {
    if (_finishSent) return;
    _finishSent = true;
    final int w = _engine.winner();
    final List<int> seatScores = _online
        ? <int>[
            _l.mySeat == 0 ? _engine.scores[0] : _engine.scores[1],
            _l.mySeat == 0 ? _engine.scores[1] : _engine.scores[0]
          ]
        : <int>[_engine.scores[0], _engine.scores[1]];
    final List<int> winners =
        w < 0 ? <int>[] : <int>[_online ? (w == 0 ? _l.mySeat : _other) : w];
    final GameOutcome outcome = w == 0
        ? GameOutcome.win
        : w == 1
            ? GameOutcome.loss
            : GameOutcome.draw;
    final int s0 = _engine.scores[0];
    final int s1 = _engine.scores[1];
    final int c0 = _engine.correctCounts[0];
    final int c1 = _engine.correctCounts[1];
    final int n = _engine.totalRounds;
    final String p2Fa = _local ? 'بازیکن ۲' : (_online ? _p2Name : 'ربات');
    final String p2En = _local ? 'Player 2' : (_online ? _p2Name : 'Bot');
    _l.onFinish(GameResult(
      outcome: outcome,
      score: s0,
      opponentScore: s1,
      winnerSeats: winners,
      scores: seatScores,
      summaryFa:
          '$c0 از $n پاسخ درست ($s0 امتیاز) در برابر $p2Fa با $c1 پاسخ درست ($s1 امتیاز).',
      summaryEn:
          '$c0/$n correct ($s0 pts) vs $p2En with $c1/$n correct ($s1 pts).',
    ));
  }

  // ------------------------------------------------------------------ helpers

  String _catName(QuizCategory? c) => c == null
      ? _l.tx('ترکیبی', 'Mixed')
      : _l.tx(quizCategoryNameFa(c), quizCategoryNameEn(c));

  String _qText(QuizQuestion q) => _l.isFa ? q.fa : q.en;
  List<String> _opts(QuizQuestion q) => _l.isFa ? q.optionsFa : q.optionsEn;

  String get _p1Name =>
      _l.playerName.isEmpty ? _l.tx('بازیکن ۱', 'Player 1') : _l.playerName;
  String get _p2Name => _online
      ? (_l.netName(_other) ?? 'Pilot')
      : (_local
          ? _l.tx('بازیکن ۲', 'Player 2')
          : _l.tx('ربات نکسورا', 'NX Bot'));

  String _roundLabel() => _l.tx(
      'سؤال ${_engine.roundIndex + 1} از ${_engine.totalRounds}',
      'Q ${_engine.roundIndex + 1}/${_engine.totalRounds}');

  QuizOptionState _optionState(int player, int index) {
    final QuizQuestion q = _engine.currentQuestion;
    final QuizAnswer? mine = _engine.currentAnswers[player];
    if (_engine.phase == QuizPhase.reveal) {
      if (index == q.correct) return QuizOptionState.correct;
      if (mine != null && mine.choice == index) return QuizOptionState.wrong;
      return QuizOptionState.dimmed;
    }
    if (mine != null) {
      return mine.choice == index
          ? QuizOptionState.picked
          : QuizOptionState.dimmed;
    }
    return QuizOptionState.idle;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_engine.phase) {
      case QuizPhase.picking:
        body = _buildPicker();
      case QuizPhase.question:
      case QuizPhase.reveal:
        body = _local ? _buildLocal() : _buildVsBot();
      case QuizPhase.finished:
        body = _buildSummary();
    }
    return NxBackground(
      palette: WorldPalette.oracle,
      stars: _l.fancyEffects,
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: _l.reducedMotion ? Duration.zero : NxMotion.slow,
          child: KeyedSubtree(
              key: ValueKey<QuizPhase>(_engine.phase == QuizPhase.reveal
                  ? QuizPhase.question
                  : _engine.phase),
              child: body),
        ),
      ),
    );
  }

  Widget _buildPicker() {
    final NxThemeColors visual = NxThemeColors.of(context);
    final List<QuizCategory?> cats = <QuizCategory?>[
      null,
      ...QuizCategory.values
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.md, NxSpace.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 48),
          AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? child) => Text(
              _l.tx('کوییز نکسورا', 'NEXORA Quiz'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: NxColors.iceWhite,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                shadows: <Shadow>[
                  Shadow(
                      color: visual.accent
                          .withValues(alpha: 0.4 + 0.4 * _pulse.value),
                      blurRadius: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _local
                ? _l.tx('دو نفره روی یک گوشی · دسته را انتخاب کنید',
                    'Two players, one device · pick a category')
                : !_iPick
                    ? _l.tx('در برابر $_p2Name · میزبان دسته را انتخاب می‌کند…',
                        'Versus $_p2Name · the host is picking a category…')
                    : _l.tx('در برابر $_p2Name · دسته را انتخاب کن',
                        'Versus $_p2Name · pick a category'),
            textAlign: TextAlign.center,
            style: TextStyle(color: visual.muted, fontSize: 13),
          ),
          const SizedBox(height: NxSpace.md),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.only(bottom: NxSpace.lg),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              itemCount: cats.length,
              itemBuilder: (BuildContext context, int i) {
                final QuizCategory? c = cats[i];
                final int count = _engine.countFor(c);
                return QuizCategoryTile(
                  category: c,
                  label: _catName(c),
                  countLabel: _l.tx('$count سؤال', '$count questions'),
                  enabled: count > 0 && _iPick,
                  onTap: () => _pickCategory(c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _timer({double size = 74}) => AnimatedBuilder(
        animation: _clock,
        builder: (BuildContext context, Widget? child) {
          final int left = ((QuizEngine.timeLimitMs - _elapsedMs) / 1000)
              .ceil()
              .clamp(0, 15);
          return QuizTimerRing(
              fraction: 1 - _clock.value, seconds: left, size: size);
        },
      );

  Widget _answers(int player, {required bool compact, bool grid = false}) {
    final QuizQuestion q = _engine.currentQuestion;
    final List<String> opts = _opts(q);
    final bool canTap =
        _engine.phase == QuizPhase.question && !_engine.hasAnswered(player);
    final QuizAnswer? bot = !_local ? _engine.currentAnswers[1] : null;
    final List<Widget> buttons = <Widget>[];
    for (int i = 0; i < 4; i++) {
      final bool showBot = player == 0 &&
          bot != null &&
          bot.choice == i &&
          _engine.phase == QuizPhase.reveal;
      buttons.add(AnimatedBuilder(
        animation: _reveal,
        builder: (BuildContext context, Widget? child) => QuizAnswerButton(
          index: i,
          text: i < opts.length ? opts[i] : '',
          state: _optionState(player, i),
          reveal: _l.reducedMotion ? 1.0 : _reveal.value,
          compact: compact,
          markerIcon: showBot ? Icons.smart_toy_rounded : null,
          onTap: canTap ? () => _answer(player, i) : null,
        ),
      ));
    }
    if (grid) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: buttons[0]),
            const SizedBox(width: 8),
            Expanded(child: buttons[1])
          ]),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Expanded(child: buttons[2]),
            const SizedBox(width: 8),
            Expanded(child: buttons[3])
          ]),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final Widget b in buttons)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: b),
      ],
    );
  }

  Widget _pointsFor(int player) {
    if (_engine.phase != QuizPhase.reveal) return const SizedBox(height: 28);
    final QuizAnswer? a = _engine.currentAnswers[player];
    return SizedBox(
      height: 28,
      child: AnimatedBuilder(
        animation: _reveal,
        builder: (BuildContext context, Widget? child) => QuizPointsBadge(
            points: a?.points ?? 0,
            progress: _l.reducedMotion ? 0.0 : _reveal.value),
      ),
    );
  }

  Widget _buildVsBot() {
    final QuizQuestion q = _engine.currentQuestion;
    final QuizAnswer? botAns = _engine.currentAnswers[1];
    String botStatus;
    Color botStatusColor = NxColors.textDim;
    if (_engine.phase == QuizPhase.reveal) {
      if (botAns == null || botAns.choice == null) {
        botStatus = _l.tx('بی‌پاسخ', 'No answer');
      } else if (botAns.correct) {
        botStatus = _l.tx('درست!', 'Correct!');
        botStatusColor = NxColors.success;
      } else {
        botStatus = _l.tx('اشتباه', 'Wrong');
        botStatusColor = NxColors.danger;
      }
    } else if (botAns != null) {
      botStatus = _l.tx('پاسخ داد ✓', 'Answered ✓');
      botStatusColor = NxColors.gold;
    } else {
      final int dots = 1 + (_elapsedMs ~/ 400) % 3;
      final String d = '.' * dots;
      botStatus = '${_l.tx('در حال فکر', 'Thinking')}$d';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 56),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: QuizScoreChip(
                    name: _p1Name,
                    score: _engine.scores[0],
                    color: NxColors.turquoise,
                    icon: Icons.person_rounded,
                    active: _engine.phase == QuizPhase.question &&
                        !_engine.hasAnswered(0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _clock,
                    builder: (BuildContext context, Widget? child) =>
                        QuizScoreChip(
                      name: _p2Name,
                      score: _engine.scores[1],
                      color: NxColors.pink,
                      icon: Icons.smart_toy_rounded,
                      status: botStatus,
                      statusColor: botStatusColor,
                      active: _botThinking,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(child: _timer()),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  QuizQuestionCard(
                    category: q.category,
                    categoryLabel: _catName(q.category),
                    roundLabel: _roundLabel(),
                    text: _qText(q),
                  ),
                  const SizedBox(height: 6),
                  Center(child: _pointsFor(0)),
                  const SizedBox(height: 6),
                  _answers(0, compact: false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerPane(int player, {required bool flipped}) {
    final QuizQuestion q = _engine.currentQuestion;
    final Color color = player == 0 ? NxColors.turquoise : NxColors.pink;
    final QuizAnswer? mine = _engine.currentAnswers[player];
    String? status;
    if (_engine.phase == QuizPhase.question) {
      status = mine != null
          ? _l.tx('قفل شد، منتظر حریف…', 'Locked in, waiting…')
          : null;
    }
    return Padding(
      // Flipped pane: its bottom is the screen top, keep the host exit corner free.
      padding: EdgeInsets.fromLTRB(12, 6, 12, flipped ? 56 : 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: QuizScoreChip(
                  name: player == 0 ? _p1Name : _p2Name,
                  score: _engine.scores[player],
                  color: color,
                  icon: Icons.person_rounded,
                  status: status,
                  active: _engine.phase == QuizPhase.question && mine == null,
                ),
              ),
              const SizedBox(width: 8),
              _pointsFor(player),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  QuizQuestionCard(
                    category: q.category,
                    categoryLabel: _catName(q.category),
                    roundLabel: _roundLabel(),
                    text: _qText(q),
                    compact: true,
                  ),
                  const SizedBox(height: 8),
                  _answers(player, compact: true, grid: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocal() {
    return Column(
      children: <Widget>[
        Expanded(
            child: RotatedBox(
                quarterTurns: 2, child: _playerPane(1, flipped: true))),
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: NxSpace.md),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: <Color>[
              NxColors.pink.withValues(alpha: 0.18),
              Colors.transparent,
              NxColors.turquoise.withValues(alpha: 0.18),
            ]),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text('${_engine.scores[0]}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: NxColors.turquoise,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
              ),
              _timer(size: 56),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 2,
                  child: Text('${_engine.scores[1]}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: NxColors.pink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _playerPane(0, flipped: false)),
      ],
    );
  }

  Widget _buildSummary() {
    final int w = _engine.winner();
    final String title;
    final Color tc;
    if (w == -1) {
      title = _l.tx('مساوی!', 'Draw!');
      tc = NxColors.gold;
    } else if (_local) {
      title = _l.tx('${w == 0 ? _p1Name : _p2Name} برنده شد!',
          '${w == 0 ? _p1Name : _p2Name} wins!');
      tc = w == 0 ? NxColors.turquoise : NxColors.pink;
    } else {
      title = w == 0
          ? _l.tx('پیروز شدی!', 'You win!')
          : _l.tx('ربات برنده شد', 'The bot wins');
      tc = w == 0 ? NxColors.success : NxColors.danger;
    }
    final List<Widget> rows = <Widget>[];
    for (int r = 0; r < _engine.history.length; r++) {
      final QuizAnswer? a = _engine.history[r][0];
      final QuizAnswer? b = _engine.history[r][1];
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            SizedBox(
                width: 28,
                child: Text('${r + 1}',
                    style: const TextStyle(
                        color: NxColors.textDim, fontWeight: FontWeight.w700))),
            Expanded(
              child: Text(_qText(_engine.questions[r]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: NxColors.iceWhite, fontSize: 12)),
            ),
            _mark(a, NxColors.turquoise),
            const SizedBox(width: 6),
            _mark(b, NxColors.pink),
          ],
        ),
      ));
    }
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(NxSpace.md, 56, NxSpace.md, NxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? child) => Transform.scale(
              scale: 1 + 0.05 * math.sin(_pulse.value * math.pi),
              child: Icon(
                  w == -1
                      ? Icons.handshake_rounded
                      : Icons.emoji_events_rounded,
                  size: 72,
                  color: tc,
                  shadows: <Shadow>[
                    Shadow(
                        color: tc.withValues(alpha: 0.4 + 0.4 * _pulse.value),
                        blurRadius: 24)
                  ]),
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: tc, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(_catName(_engine.category),
              textAlign: TextAlign.center,
              style: const TextStyle(color: NxColors.textDim, fontSize: 13)),
          const SizedBox(height: NxSpace.md),
          Row(
            children: <Widget>[
              Expanded(
                child: QuizScoreChip(
                  name: _p1Name,
                  score: _engine.scores[0],
                  color: NxColors.turquoise,
                  icon: Icons.person_rounded,
                  status: _l.tx('${_engine.correctCounts[0]} درست',
                      '${_engine.correctCounts[0]} correct'),
                  active: w == 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: QuizScoreChip(
                  name: _p2Name,
                  score: _engine.scores[1],
                  color: NxColors.pink,
                  icon: _local ? Icons.person_rounded : Icons.smart_toy_rounded,
                  status: _l.tx('${_engine.correctCounts[1]} درست',
                      '${_engine.correctCounts[1]} correct'),
                  active: w == 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: NxSpace.md),
          Expanded(
            child: GlassPanel(
              blur: false,
              padding: const EdgeInsets.all(12),
              child: ListView(children: rows),
            ),
          ),
          const SizedBox(height: NxSpace.md),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: NxColors.turquoise,
                foregroundColor: NxColors.navyDeep,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(NxRadius.md)),
              ),
              onPressed: _finishSent ? null : () => setState(_finish),
              icon: const Icon(Icons.check_rounded),
              label: Text(_l.tx('ثبت نتیجه', 'Finish'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mark(QuizAnswer? a, Color c) {
    final int pts = a == null ? 0 : a.points;
    final bool ok = a != null && a.correct;
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color:
            (ok ? NxColors.success : NxColors.danger).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(ok ? '+$pts' : '✕',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: ok ? NxColors.success : NxColors.danger,
              fontSize: 11,
              fontWeight: FontWeight.w800)),
    );
  }
}
