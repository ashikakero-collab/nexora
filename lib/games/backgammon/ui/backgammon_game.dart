import 'dart:ui' as ui;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/core/game_contract.dart';

import '../core/backgammon_bot.dart';
import '../core/backgammon_rules.dart';
import 'bg_geometry.dart';
import 'bg_skins.dart';
import '../../../core/ui2/nx2_board_art.dart';
import 'bg_widgets.dart';

enum _Phase { opening, awaitRoll, rolling, playing, bot, gameOver }

class BackgammonGame extends StatefulWidget {
  const BackgammonGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<BackgammonGame> createState() => _BackgammonGameState();
}

class _BackgammonGameState extends State<BackgammonGame>
    with TickerProviderStateMixin {
  int _skin = bgSkinIndex();
  void _nextSkin() {
    setState(() => _skin = (_skin + 1) % kBgSkins.length);
    bgSetSkin(_skin);
  }

  late BgState _s;
  late BgDice _dice;
  late BgBot _bot;
  late AnimationController _rollCtl;
  late AnimationController _flyCtl;
  late AnimationController _pulseCtl;
  late AnimationController _flashCtl;

  _Phase _phase = _Phase.opening;
  int _turn = 0;
  List<int> _shownDice = <int>[];
  List<bool> _usedDice = <bool>[];
  BgTurnTracker? _tracker;
  int? _selected;
  List<BgMove> _legal = <BgMove>[];
  bool _busy = false;
  bool _finished = false;
  bool _openingRoll = false;

  Offset? _flyFrom;
  Offset? _flyTo;
  int _flyPlayer = 0;
  int? _liftPlayer;
  int? _liftPlace;
  Offset? _flashAt;

  String _statusFa = '';
  String _statusEn = '';
  String? _bannerFa;
  String? _bannerEn;

  // ------------------------------------------------------------- online
  NetInbox? _inbox;
  bool _replayedAny = false;
  BgTurnTracker? _replayTracker;

  GameLaunch get _l => widget.launch;
  bool _isRemote(int p) => _l.isRemoteSeat(p);
  bool _human(int p) => !_isBot(p) && !_isRemote(p);
  int get _me => _l.mySeat;
  bool get _fancy => _l.fancyEffects && !_l.reducedMotion;

  @override
  void initState() {
    super.initState();
    final int seed = _l.seed ?? DateTime.now().microsecondsSinceEpoch;
    _s = BgState.initial();
    _dice = BgDice(seed);
    _bot = BgBot(level: _l.difficulty.index, seed: seed + 7);
    _rollCtl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _l.reducedMotion ? 260 : 820));
    _flyCtl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _l.reducedMotion ? 160 : 380));
    _pulseCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    if (_l.reducedMotion) {
      _pulseCtl.value = 0.7;
    } else {
      _pulseCtl.repeat(reverse: true);
    }
    _flashCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 520));
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
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _opening());
    }
  }

  String _stateHash() => hashOf(
      '${_s.points.join(',')}|${_s.bar.join(',')}|${_s.off.join(',')}|$_turn');

  List<List<int>> _encode(List<BgMove> ms) => <List<int>>[
        for (final BgMove m in ms) <int>[m.from, m.to, m.die]
      ];

  List<BgMove> _decode(dynamic raw) {
    final List<BgMove> out = <BgMove>[];
    if (raw is! List) return out;
    for (final dynamic e in raw) {
      if (e is List && e.length >= 3) {
        out.add(BgMove((e[0] as num).toInt(), (e[1] as num).toInt(),
            (e[2] as num).toInt()));
      }
    }
    return out;
  }

  /// Same dice as the animated opening, instantly (used when rebuilding from the log).
  void _fastOpening() {
    int a = 0;
    int b = 0;
    do {
      a = _dice.roll();
      b = _dice.roll();
    } while (a == b);
    _turn = a > b ? 0 : 1;
    _replayStart(<int>[a, b]);
  }

  void _replayStart(List<int> dice) {
    final BgTurnTracker t = BgTurnTracker(_s, _turn, dice);
    _s.turn = _turn;
    _replayTracker = t;
    if (t.total == 0) {
      _turn = 1 - _turn;
      _replayTracker = null;
    }
  }

  Future<void> _onNet(NetMove m) async {
    if (!mounted) return;
    if (m.kind == 'replayDone') {
      if (!_replayedAny) {
        await _opening();
        return;
      }
      if (_s.winner != null) {
        _gameOver();
        return;
      }
      final BgTurnTracker? t = _replayTracker;
      _replayTracker = null;
      if (t != null) {
        _startTurnWithDice(List<int>.from(t.rolled));
      } else {
        _turn = 1 - _turn;
        _endTurn();
      }
      return;
    }
    if (m.kind != 'move') return;
    final String a = '${m.data['a']}';
    if (m.replay) {
      if (!_replayedAny) {
        _replayedAny = true;
        _fastOpening();
      }
      if (m.seat != _turn || _s.winner != null) return;
      if (a == 'roll') {
        _replayStart(<int>[_dice.roll(), _dice.roll()]);
      } else if (a == 'turn') {
        final BgTurnTracker? t = _replayTracker;
        if (t == null) return;
        for (final BgMove mv in _decode(m.data['m'])) {
          t.play(mv);
        }
        _s = t.state.copy();
        _replayTracker = null;
        if (_s.winner == null) _turn = 1 - _turn;
      }
      return;
    }
    if (m.seat != _turn || _finished) return;
    while (_busy || _phase == _Phase.rolling || _phase == _Phase.opening) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
    }
    _l.net?.verify(m.seq, m.data['h'] as String?, _stateHash());
    if (a == 'roll') {
      setState(() => _phase = _Phase.rolling);
      if (!await _run(_rollCtl)) return;
      _startTurnWithDice(<int>[_dice.roll(), _dice.roll()]);
    } else if (a == 'turn') {
      await _netPlay(_decode(m.data['m']));
    }
  }

  /// Animate the remote player's whole turn, checker by checker.
  Future<void> _netPlay(List<BgMove> plan) async {
    final BgTurnTracker? t = _tracker;
    if (t == null) return;
    for (final BgMove mv in plan) {
      if (!mounted || _finished) return;
      final BgState before = _s.copy();
      final BgMove? played = t.play(mv);
      if (played == null) break;
      await _animateMove(played, t.player, before, t.state.copy());
      if (!mounted) return;
      setState(() => _usedDice = List<bool>.from(t.used));
      if (_s.winner != null) {
        _gameOver();
        return;
      }
      await _wait(200);
    }
    if (!mounted) return;
    await _wait(200);
    if (!mounted) return;
    _endTurn();
  }

  void _sendTurn(BgTurnTracker t) {
    if (!_l.online) return;
    _l.net!.send(<String, dynamic>{'a': 'turn', 'm': _encode(t.played)});
  }

  @override
  void dispose() {
    _inbox?.close();
    _rollCtl.dispose();
    _flyCtl.dispose();
    _pulseCtl.dispose();
    _flashCtl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- helpers
  bool _isBot(int p) => _l.vsBot && p == 1;

  String _name(int p, {bool fa = true}) {
    final String? online = _l.netName(p);
    if (online != null) return online;
    if (p == 0) return _l.playerName;
    if (_l.vsBot) return fa ? 'ربات NX' : 'NX Bot';
    return fa ? 'بازیکن ۲' : 'Player 2';
  }

  String _nameL(int p) => _l.isFa ? _name(p, fa: true) : _name(p, fa: false);

  void _status(String fa, String en) {
    _statusFa = fa;
    _statusEn = en;
  }

  Future<void> _wait(int ms) => Future<void>.delayed(
      Duration(milliseconds: _l.reducedMotion ? (ms * 0.6).round() : ms));

  Future<bool> _run(AnimationController c) async {
    if (!mounted) return false;
    await c.forward(from: 0);
    return mounted;
  }

  void _haptic({bool heavy = false}) {
    if (!_l.soundOn) return;
    if (heavy) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  // ------------------------------------------------------------------ flow
  Future<void> _opening() async {
    if (!mounted) return;
    int a = 0;
    int b = 0;
    _openingRoll = true;
    do {
      setState(() {
        _phase = _Phase.rolling;
        _shownDice = <int>[1, 1];
        _usedDice = <bool>[false, false];
        _status('تاس آغاز: بیشترین عدد شروع می‌کند',
            'Opening roll: highest die starts');
      });
      if (!await _run(_rollCtl)) return;
      a = _dice.roll();
      b = _dice.roll();
      setState(() {
        _phase = _Phase.opening;
        _shownDice = <int>[a, b];
        if (a == b) {
          _status('مساوی ($a و $b) — دوباره!', 'Tie ($a & $b) — roll again!');
        } else {
          _status('${_name(0)}: $a  •  ${_name(1)}: $b',
              '${_name(0, fa: false)}: $a  •  ${_name(1, fa: false)}: $b');
        }
      });
      await _wait(1100);
      if (!mounted) return;
    } while (a == b);
    _openingRoll = false;
    _turn = a > b ? 0 : 1;
    _startTurnWithDice(<int>[a, b]);
  }

  Future<void> _rollHuman() async {
    if (_phase != _Phase.awaitRoll || !_human(_turn)) return;
    if (_l.online) {
      _l.net!.send(<String, dynamic>{'a': 'roll', 'h': _stateHash()});
    }
    setState(() => _phase = _Phase.rolling);
    _haptic();
    if (!await _run(_rollCtl)) return;
    _haptic(heavy: true);
    _startTurnWithDice(<int>[_dice.roll(), _dice.roll()]);
  }

  void _startTurnWithDice(List<int> dice) {
    if (!mounted) return;
    final BgTurnTracker t = BgTurnTracker(_s, _turn, dice);
    _s.turn = _turn;
    setState(() {
      _tracker = t;
      _shownDice = List<int>.from(t.pool);
      _usedDice = List<bool>.from(t.used);
      _selected = null;
      _legal = <BgMove>[];
    });
    if (_isBot(_turn)) {
      _botPlay(t);
      return;
    }
    if (_isRemote(_turn)) {
      _l.net?.turnSeat = _turn;
      setState(() {
        _phase = _Phase.bot;
        _status(
            t.total == 0
                ? '${_name(_turn)} حرکتی ندارد'
                : '${_name(_turn)} در حال بازی…',
            t.total == 0
                ? '${_name(_turn, fa: false)} cannot move'
                : '${_name(_turn, fa: false)} is playing…');
      });
      if (t.total == 0) _passAfterDelay();
      return;
    }
    if (t.total == 0) {
      setState(() {
        _phase = _Phase.playing;
        _status('حرکت مجازی وجود ندارد', 'No legal moves');
      });
      _passAfterDelay();
      return;
    }
    _refreshHumanMoves();
  }

  Future<void> _passAfterDelay() async {
    await _wait(1400);
    if (!mounted || _finished) return;
    _endTurn();
  }

  void _refreshHumanMoves() {
    final BgTurnTracker? t = _tracker;
    if (t == null) return;
    final List<BgMove> legal = t.legalMoves();
    setState(() {
      _phase = _Phase.playing;
      _legal = legal;
      _selected = null;
      if (t.complete) {
        _status('حرکت‌ها تمام شد — تأیید کن', 'All dice played — confirm');
      } else if (t.state.bar[t.player] > 0) {
        _selected = kBgBar;
        _status(
            'اول مهره‌ی روی بار را وارد کن', 'Enter your checker from the bar');
      } else {
        _status('مهره‌ای را انتخاب کن', 'Select a checker');
      }
    });
  }

  Future<void> _onBoardTap(Offset p) async {
    final BgTurnTracker? t = _tracker;
    if (_phase == _Phase.awaitRoll && _human(_turn)) {
      if ((p - BgGeom.diceCenter).distance < 140) _rollHuman();
      return;
    }
    if (_phase != _Phase.playing || t == null || _busy || _isBot(_turn)) return;
    final int? target = BgGeom.hitTest(p, t.player);
    if (target == null) {
      setState(() => _selected = null);
      return;
    }
    if (_selected != null) {
      final List<BgMove> cands = _legal
          .where((BgMove m) => m.from == _selected && m.to == target)
          .toList()
        ..sort((BgMove a, BgMove b) => a.die.compareTo(b.die));
      if (cands.isNotEmpty) {
        await _humanMove(cands.first);
        return;
      }
    }
    if (target != kBgOff && _legal.any((BgMove m) => m.from == target)) {
      _haptic();
      setState(() => _selected = _selected == target ? null : target);
      return;
    }
    setState(() => _selected = null);
  }

  Future<void> _humanMove(BgMove m) async {
    final BgTurnTracker? t = _tracker;
    if (t == null) return;
    _busy = true;
    final BgState before = _s.copy();
    final BgMove? played = t.play(m);
    if (played == null) {
      _busy = false;
      return;
    }
    setState(() {
      _selected = null;
      _legal = <BgMove>[];
    });
    await _animateMove(played, t.player, before, t.state.copy());
    if (!mounted) return;
    _busy = false;
    setState(() => _usedDice = List<bool>.from(t.used));
    if (_s.winner != null) {
      _sendTurn(t);
      _gameOver();
      return;
    }
    _refreshHumanMoves();
  }

  void _undo() {
    final BgTurnTracker? t = _tracker;
    if (t == null || !t.canUndo || _busy) return;
    t.undo();
    _haptic();
    setState(() {
      _s = t.state.copy();
      _usedDice = List<bool>.from(t.used);
    });
    _refreshHumanMoves();
  }

  void _confirm() {
    final BgTurnTracker? t = _tracker;
    if (t == null || !t.complete || _busy) return;
    _haptic();
    _sendTurn(t);
    _endTurn();
  }

  void _endTurn() {
    if (_finished || !mounted) return;
    setState(() {
      _turn = 1 - _turn;
      _tracker = null;
      _legal = <BgMove>[];
      _selected = null;
      _shownDice = <int>[];
      _usedDice = <bool>[];
      _phase = _Phase.awaitRoll;
      if (_isRemote(_turn)) {
        _status('نوبت ${_name(_turn)} — منتظر تاس…',
            "${_name(_turn, fa: false)}'s turn — waiting…");
      } else if (_isBot(_turn)) {
        _status('نوبت ${_name(1)}', "${_name(1, fa: false)}'s turn");
      } else {
        _status('نوبت ${_name(_turn)} — تاس بریز',
            '${_name(_turn, fa: false)} — roll the dice');
      }
    });
    _l.net?.turnSeat = _turn;
    if (_isBot(_turn)) _botTurn();
  }

  Future<void> _botTurn() async {
    setState(() => _phase = _Phase.bot);
    await _wait(500 + Random().nextInt(400));
    if (!mounted || _finished) return;
    setState(() => _phase = _Phase.rolling);
    if (!await _run(_rollCtl)) return;
    _startTurnWithDice(<int>[_dice.roll(), _dice.roll()]);
  }

  Future<void> _botPlay(BgTurnTracker t) async {
    setState(() {
      _phase = _Phase.bot;
      _status('${_name(1)} فکر می‌کند…', '${_name(1, fa: false)} is thinking…');
    });
    await _wait(500 + _l.difficulty.index * 150);
    if (!mounted) return;
    final List<BgMove> plan = _bot.choose(_s, t.player, t.rolled);
    if (plan.isEmpty) {
      setState(() => _status(
          '${_name(1)} حرکتی ندارد', '${_name(1, fa: false)} cannot move'));
      await _wait(1200);
      if (!mounted) return;
      _endTurn();
      return;
    }
    for (final BgMove m in plan) {
      if (!mounted || _finished) return;
      final BgState before = _s.copy();
      final BgMove? played = t.play(m);
      if (played == null) break;
      await _animateMove(played, t.player, before, t.state.copy());
      if (!mounted) return;
      setState(() => _usedDice = List<bool>.from(t.used));
      if (_s.winner != null) {
        _gameOver();
        return;
      }
      await _wait(240);
    }
    if (!mounted) return;
    await _wait(250);
    if (!mounted) return;
    _endTurn();
  }

  Offset _sourcePos(BgState s, int p, int from) {
    if (from == kBgBar) {
      final int c = s.bar[p];
      return BgGeom.barCenter(p, max(0, c - 1), max(1, c));
    }
    final int c = s.own(p, from);
    return BgGeom.checkerCenter(from, max(0, c - 1), max(1, c));
  }

  Offset _destPos(BgState s, int p, int to) {
    if (to == kBgOff) return BgGeom.slabCenter(p, s.off[p]);
    final int c = s.own(p, to);
    return BgGeom.checkerCenter(to, c, c + 1);
  }

  Future<void> _animateMove(
      BgMove m, int p, BgState before, BgState after) async {
    final Offset from = _sourcePos(before, p, m.from);
    final Offset to = _destPos(before, p, m.to);
    setState(() {
      _s = before;
      _liftPlayer = p;
      _liftPlace = m.from;
      _flyFrom = from;
      _flyTo = to;
      _flyPlayer = p;
    });
    if (!await _run(_flyCtl)) return;
    _haptic(heavy: m.hit);
    setState(() {
      _s = after;
      _liftPlayer = null;
      _liftPlace = null;
      _flyFrom = null;
      _flyTo = null;
    });
    if (m.hit) {
      final int o = 1 - p;
      final int c = after.bar[o];
      final Offset barTo = BgGeom.barCenter(o, max(0, c - 1), max(1, c));
      setState(() {
        _flashAt = to;
        _liftPlayer = o;
        _liftPlace = kBgBar;
        _flyFrom = to;
        _flyTo = barTo;
        _flyPlayer = o;
      });
      if (_fancy) _flashCtl.forward(from: 0);
      if (!await _run(_flyCtl)) return;
      setState(() {
        _liftPlayer = null;
        _liftPlace = null;
        _flyFrom = null;
        _flyTo = null;
      });
    }
  }

  void _gameOver() {
    if (_finished) return;
    _finished = true;
    final int w = _s.winner ?? 0;
    final int mult = BgRules.resultMultiplier(_s, w);
    final String kindFa =
        mult == 3 ? 'بک‌گمون' : (mult == 2 ? 'گمون' : 'برد ساده');
    final String kindEn =
        mult == 3 ? 'Backgammon' : (mult == 2 ? 'Gammon' : 'Single game');
    _haptic(heavy: true);
    setState(() {
      _phase = _Phase.gameOver;
      _bannerFa = '$kindFa! ${_name(w)} برد';
      _bannerEn = '$kindEn! ${_name(w, fa: false)} wins';
      _status('$kindFa — $mult امتیاز',
          '$kindEn — $mult point${mult > 1 ? 's' : ''}');
    });
    final int loser = 1 - w;
    final String sumFa =
        '$kindFa: ${_name(w)} با $mult امتیاز برد. ${_name(loser)} ${_s.off[loser]} مهره خارج کرده بود (پیپ باقی‌مانده ${_s.pip(loser)}).';
    final String sumEn =
        '$kindEn: ${_name(w, fa: false)} won $mult point${mult > 1 ? 's' : ''}. ${_name(loser, fa: false)} had borne off ${_s.off[loser]} (pips left ${_s.pip(loser)}).';
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      _l.onFinish(GameResult(
        outcome: w == _me ? GameOutcome.win : GameOutcome.loss,
        score: w == _me ? mult : 0,
        opponentScore: w != _me ? mult : 0,
        winnerSeats: <int>[w],
        scores: <int>[w == 0 ? mult : 0, w == 1 ? mult : 0],
        summaryFa: sumFa,
        summaryEn: sumEn,
      ));
    });
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
            child: BgSpaceBackground(
                fancy: _fancy, visual: NxThemeColors.of(context))),
        SafeArea(
          child: Column(
            children: <Widget>[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _playersBar(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _boardArea(),
                ),
              ),
              _controls(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  Widget _playersBar() {
    return Row(
      children: <Widget>[
        Expanded(child: _playerCard(0)),
        const SizedBox(width: 6),
        Nx2BoardButton(onTap: _nextSkin, size: 34),
        const SizedBox(width: 6),
        Expanded(child: _playerCard(1)),
      ],
    );
  }

  Widget _playerCard(int p) {
    final bool active = _turn == p && _phase != _Phase.opening && !_openingRoll;
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color accent = p == 0 ? visual.accent : visual.accentSecondary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: active ? accent.withValues(alpha: 0.18) : visual.surface,
        border: Border.all(
            color: active ? accent : visual.border.withValues(alpha: 0.55),
            width: active ? 1.8 : 1),
        boxShadow: active && _fancy
            ? <BoxShadow>[
                BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 18)
              ]
            : null,
      ),
      child: Row(
        children: <Widget>[
          BgChecker(player: p, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _nameL(p),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: visual.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 13),
                ),
                Text(
                  '${_l.tx('پیپ', 'Pips')} ${_s.pip(p)} • ${_l.tx('خارج', 'Off')} ${_s.off[p]}/15',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: visual.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardArea() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool portrait = c.maxHeight > c.maxWidth * 1.05;
        Widget board = SizedBox(
          width: BgGeom.w,
          height: BgGeom.h,
          child: _boardStack(),
        );
        if (portrait) board = RotatedBox(quarterTurns: 1, child: board);
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: FittedBox(fit: BoxFit.contain, child: board)),
        );
      },
    );
  }

  Widget _boardStack() {
    final BgTurnTracker? t = _tracker;
    final int hp = t?.player ?? _turn;
    final Set<int> dests = <int>{};
    bool destOff = false;
    final Set<int> sources = <int>{};
    if (_phase == _Phase.playing && !_busy && _human(_turn)) {
      for (final BgMove m in _legal) {
        sources.add(m.from);
        if (m.from == _selected) {
          if (m.to == kBgOff) {
            destOff = true;
          } else {
            dests.add(m.to);
          }
        }
      }
    }
    final List<Widget> layers = <Widget>[
      Positioned.fill(
        child: Nx2ArtCanvas(
          asset: kBgSkins[_skin].asset,
          size: const Size(BgGeom.w, BgGeom.h),
          painter: (ui.Image img) => BgSkinPainter(img, kBgSkins[_skin]),
          fallback: const CustomPaint(painter: BgFallbackBoardPainter()),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: BgHighlightPainter(
              accent: NxThemeColors.of(context).accent,
              accentSecondary: NxThemeColors.of(context).accentSecondary,
              state: _s,
              player: hp,
              destinations: dests,
              destOff: destOff,
              sources: sources,
              selected: _selected,
              pulse: _pulseCtl,
              fancy: _fancy,
            ),
          ),
        ),
      ),
    ];
    layers.addAll(_trayLayers());
    layers.addAll(_checkerLayers());
    layers.add(_diceLayer());
    layers.add(_flashLayer());
    layers.add(_flyLayer());
    if (_bannerFa != null) layers.add(_bannerLayer());
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (TapUpDetails d) => _onBoardTap(d.localPosition),
      child: Stack(clipBehavior: Clip.none, children: layers),
    );
  }

  int _shownCount(int p, int place) {
    int c = place == kBgBar ? _s.bar[p] : _s.own(p, place);
    if (_liftPlayer == p && _liftPlace == place) c -= 1;
    return max(0, c);
  }

  Widget _checkerAt(Offset c, int p) => Positioned(
        left: c.dx - BgGeom.d / 2,
        top: c.dy - BgGeom.d / 2,
        width: BgGeom.d,
        height: BgGeom.d,
        child: IgnorePointer(child: BgChecker(player: p)),
      );

  List<Widget> _checkerLayers() {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < 24; i++) {
      for (int p = 0; p < 2; p++) {
        final int c = _shownCount(p, i);
        for (int k = 0; k < c; k++) {
          out.add(_checkerAt(BgGeom.checkerCenter(i, k, c), p));
        }
      }
    }
    for (int p = 0; p < 2; p++) {
      final int c = _shownCount(p, kBgBar);
      for (int k = 0; k < c; k++) {
        out.add(_checkerAt(BgGeom.barCenter(p, k, c), p));
      }
    }
    return out;
  }

  List<Widget> _trayLayers() {
    final List<Widget> out = <Widget>[];
    for (int p = 0; p < 2; p++) {
      final List<Color> cols = p == 0
          ? const <Color>[Color(0xFFF6D9A4), Color(0xFFC08A48)]
          : const <Color>[Color(0xFF8A4E2E), Color(0xFF3A1C0D)];
      for (int k = 0; k < _s.off[p]; k++) {
        final Offset c = BgGeom.slabCenter(p, k);
        out.add(Positioned(
          left: c.dx - BgGeom.slabW / 2,
          top: c.dy - BgGeom.slabH / 2,
          width: BgGeom.slabW,
          height: BgGeom.slabH,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: LinearGradient(
                    colors: cols,
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter),
                border: Border.all(color: const Color(0x99FFC857), width: 1),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                      color: Color(0x88000000),
                      blurRadius: 3,
                      offset: Offset(0, 2)),
                ],
              ),
            ),
          ),
        ));
      }
    }
    return out;
  }

  Widget _diceLayer() {
    const double size = 92;
    final int n = _shownDice.length;
    final bool rolling = _phase == _Phase.rolling;
    final int count = rolling ? 2 : n;
    if (count == 0) {
      if (_phase == _Phase.awaitRoll && _human(_turn)) {
        return Positioned(
          left: BgGeom.diceCenter.dx - 120,
          top: BgGeom.diceCenter.dy - 50,
          width: 240,
          height: 100,
          child: AnimatedBuilder(
            animation: _pulseCtl,
            builder: (BuildContext c, Widget? child) => Opacity(
              opacity: 0.55 + 0.45 * _pulseCtl.value,
              child: child,
            ),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                color: const Color(0x66000000),
                border: Border.all(color: const Color(0xFFFFC857), width: 3),
              ),
              child: Text(
                _l.tx('🎲 بریز', '🎲 ROLL'),
                style: TextStyle(
                    color: NxThemeColors.of(context).accent,
                    fontSize: 34,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    final double gap = count > 2 ? 10 : 26;
    final double dieSize = count > 2 ? 74 : size;
    final double totalW = count * dieSize + (count - 1) * gap;
    return Positioned(
      left: BgGeom.diceCenter.dx - totalW / 2,
      top: BgGeom.diceCenter.dy - dieSize / 2,
      width: totalW,
      height: dieSize,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _rollCtl,
          builder: (BuildContext c, Widget? child) {
            final List<Widget> dice = <Widget>[];
            for (int i = 0; i < count; i++) {
              if (i > 0) dice.add(SizedBox(width: gap));
              dice.add(SizedBox(
                width: dieSize,
                height: dieSize,
                child: BgDie(
                  value: rolling ? 1 : _shownDice[i],
                  size: dieSize,
                  used: !rolling && i < _usedDice.length && _usedDice[i],
                  rolling: rolling,
                  t: _rollCtl.value,
                  variant: i,
                  accent: NxThemeColors.of(context).accent,
                ),
              ));
            }
            return Row(mainAxisSize: MainAxisSize.min, children: dice);
          },
        ),
      ),
    );
  }

  Widget _flyLayer() {
    final Offset? from = _flyFrom;
    final Offset? to = _flyTo;
    if (from == null || to == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _flyCtl,
      builder: (BuildContext c, Widget? child) {
        final double t = Curves.easeInOutCubic.transform(_flyCtl.value);
        final Offset pos = Offset.lerp(from, to, t)!;
        final double lift =
            sin(t * pi) * min(120.0, (to - from).distance * 0.25);
        final double scale = 1 + sin(t * pi) * 0.18;
        return Positioned(
          left: pos.dx - BgGeom.d / 2,
          top: pos.dy - BgGeom.d / 2 - lift,
          width: BgGeom.d,
          height: BgGeom.d,
          child:
              IgnorePointer(child: Transform.scale(scale: scale, child: child)),
        );
      },
      child: BgChecker(player: _flyPlayer),
    );
  }

  Widget _flashLayer() {
    final Offset? at = _flashAt;
    if (at == null || !_fancy) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _flashCtl,
      builder: (BuildContext c, Widget? child) {
        final double t = _flashCtl.value;
        if (t <= 0 || t >= 1) return const SizedBox.shrink();
        final double r = 40 + 140 * t;
        return Positioned(
          left: at.dx - r,
          top: at.dy - r,
          width: r * 2,
          height: r * 2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: <Color>[
                  const Color(0xFFFF4FA3).withValues(alpha: 0.7 * (1 - t)),
                  const Color(0xFFFFC857).withValues(alpha: 0.35 * (1 - t)),
                  const Color(0x00FFC857),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bannerLayer() {
    return Positioned(
      left: 300,
      right: 300,
      top: 400,
      height: 200,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (BuildContext c, double v, Widget? child) =>
              Transform.scale(scale: v, child: child),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              color: NxThemeColors.of(context)
                  .surfaceRaised
                  .withValues(alpha: 0.94),
              border:
                  Border.all(color: NxThemeColors.of(context).accent, width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                    color: NxThemeColors.of(context)
                        .accent
                        .withValues(alpha: 0.24),
                    blurRadius: 32),
              ],
            ),
            child: Text(
              _l.isFa ? (_bannerFa ?? '') : (_bannerEn ?? ''),
              textAlign: TextAlign.center,
              textDirection: _l.isFa ? TextDirection.rtl : TextDirection.ltr,
              style: TextStyle(
                  color: NxThemeColors.of(context).accent,
                  fontSize: 52,
                  fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final BgTurnTracker? t = _tracker;
    final bool humanTurn = _human(_turn) && !_finished;
    final List<Widget> buttons = <Widget>[];
    if (humanTurn && _phase == _Phase.awaitRoll) {
      buttons.add(BgButton(
        label: _l.tx('ریختن تاس', 'Roll dice'),
        icon: Icons.casino_rounded,
        primary: true,
        onTap: _rollHuman,
      ));
    }
    if (humanTurn && _phase == _Phase.playing && t != null && t.total > 0) {
      buttons.add(BgButton(
        label: _l.tx('برگرداندن', 'Undo'),
        icon: Icons.undo_rounded,
        onTap: t.canUndo && !_busy ? _undo : null,
      ));
      buttons.add(const SizedBox(width: 10));
      buttons.add(BgButton(
        label: _l.tx('تأیید', 'Confirm'),
        icon: Icons.check_rounded,
        primary: true,
        onTap: t.complete && !_busy ? _confirm : null,
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: NxThemeColors.of(context).surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color:
                      NxThemeColors.of(context).border.withValues(alpha: 0.6)),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                _l.isFa ? _statusFa : _statusEn,
                key: ValueKey<String>(_statusFa + _statusEn),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: NxThemeColors.of(context).text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center, children: buttons),
          ),
        ],
      ),
    );
  }
}
