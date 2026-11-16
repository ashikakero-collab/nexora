import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/core/game_contract.dart';

import '../core/ludo_bot.dart';
import '../core/ludo_rules.dart';
import 'ludo_board.dart';
import 'ludo_die.dart';

class _Flight {
  const _Flight(this.seat, this.token, this.path);
  final int seat;
  final int token;
  final List<Offset> path;
}

class LudoGame extends StatefulWidget {
  const LudoGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<LudoGame> createState() => _LudoGameState();
}

class _LudoGameState extends State<LudoGame> with TickerProviderStateMixin {
  late LudoEngine _engine;
  late List<LudoBot?> _bots;
  late AnimationController _rollCtl;
  late AnimationController _hopCtl;
  late AnimationController _pulseCtl;
  late AnimationController _flashCtl;

  int? _dieValue;
  bool _rolling = false;
  bool _busy = false;
  bool _finished = false;
  List<LudoMove> _moves = <LudoMove>[];
  List<_Flight> _flights = <_Flight>[];
  late List<int> _captures;
  Offset? _flashAt;
  int _lastHopSegment = -1;
  String _statusFa = '';
  String _statusEn = '';
  String? _bannerFa;
  String? _bannerEn;

  // ------------------------------------------------------------- online
  NetInbox? _inbox;
  final Set<int> _out = <int>{};
  List<LudoMove> _replayPending = <LudoMove>[];

  GameLaunch get _l => widget.launch;
  bool _isRemote(int seat) => _l.isRemoteSeat(seat);
  int get _me => _l.mySeat;
  bool get _fancy => _l.fancyEffects && !_l.reducedMotion;
  LudoState get _s => _engine.state;
  int get _n => _s.playerCount;

  @override
  void initState() {
    super.initState();
    final int seed = _l.seed ?? DateTime.now().microsecondsSinceEpoch;
    _engine = LudoEngine(playerCount: _l.playerCount, seed: seed);
    _captures = List<int>.filled(_n, 0);
    _bots = List<LudoBot?>.generate(
        _n,
        (int i) => (_l.vsBot && i != 0)
            ? LudoBot(level: _l.difficulty.index, seed: seed + 31 * (i + 1))
            : null);
    _rollCtl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _l.reducedMotion ? 250 : 700));
    _hopCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _hopCtl.addListener(_onHopTick);
    _pulseCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    if (_l.reducedMotion) {
      _pulseCtl.value = 0.8;
    } else {
      _pulseCtl.repeat(reverse: true);
    }
    _flashCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _beginTurn());
    }
  }

  String _stateHash() {
    final StringBuffer b = StringBuffer('${_s.turn}|${_s.sixStreak}|');
    for (int i = 0; i < _n; i++) {
      b.write('${_s.tokens[i].join(',')};');
    }
    b.write('|${_out.join(',')}');
    return hashOf(b.toString());
  }

  void _skipOut() {
    int guard = 0;
    while (_out.contains(_s.turn) && guard < _n) {
      _engine.advanceTurn();
      guard++;
    }
  }

  bool _checkLastStanding() {
    if (!_l.online || _finished) return false;
    final List<int> alive = <int>[
      for (int i = 0; i < _n; i++)
        if (!_out.contains(i)) i
    ];
    if (alive.length == 1) {
      _gameOver(alive.first);
      return true;
    }
    return false;
  }

  LudoMove? _pick(List<LudoMove> moves, Map<String, dynamic> d) {
    final int t = (d['t'] as num?)?.toInt() ?? -1;
    final int to = (d['to'] as num?)?.toInt() ?? -999;
    for (final LudoMove m in moves) {
      if (m.token == t && m.to == to) return m;
    }
    for (final LudoMove m in moves) {
      if (m.token == t) return m;
    }
    return null;
  }

  /// Online: apply one logged move. Replay = rebuild state instantly.
  Future<void> _onNet(NetMove m) async {
    if (!mounted) return;
    if (m.kind == 'replayDone') {
      setState(() {});
      if (_s.winner != null) {
        _gameOver(_s.winner!);
      } else if (!_checkLastStanding()) {
        if (_replayPending.isNotEmpty && !_out.contains(_s.turn)) {
          final int seat = _s.turn;
          setState(() {
            _moves = _replayPending;
            if (_isRemote(seat)) {
              _status('${_nameFa(seat)} مهره انتخاب می‌کند…',
                  '${_nameEn(seat)} is choosing…');
            } else {
              _status('یک مهره‌ی درخشان را انتخاب کن', 'Pick a glowing token');
            }
          });
          _l.net?.turnSeat = seat;
        } else {
          _beginTurn();
        }
      }
      return;
    }
    if (m.isForfeit) {
      final int seat = (m.data['seat'] as num?)?.toInt() ?? m.seat;
      _out.add(seat);
      if (_s.turn == seat) {
        _engine.pendingRoll = null;
        _replayPending = <LudoMove>[];
        if (!m.replay) setState(() => _moves = <LudoMove>[]);
        _engine.advanceTurn();
      }
      if (m.replay) return;
      if (_checkLastStanding()) return;
      if (!_busy && !_rolling) _beginTurn();
      return;
    }
    if (m.kind != 'move' || m.seat != _s.turn || _s.winner != null) return;
    final String a = '${m.data['a']}';
    if (m.replay) {
      if (a == 'roll') {
        final LudoRollResult r = _engine.roll();
        _replayPending = <LudoMove>[];
        if (r.moves.isNotEmpty) {
          if (_allSame(r.moves)) {
            _replayApply(r.moves.first);
          } else {
            _replayPending = r.moves;
          }
        }
      } else if (a == 'play') {
        final LudoMove? mv = _pick(_replayPending, m.data);
        if (mv != null) _replayApply(mv);
        _replayPending = <LudoMove>[];
      }
      _skipOut();
      return;
    }
    while (_busy || _rolling) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
    }
    if (a == 'roll') {
      _l.net?.verify(m.seq, m.data['h'] as String?, _stateHash());
      await _roll(fromNet: true);
    } else if (a == 'play') {
      final LudoMove? mv = _pick(_moves, m.data);
      if (mv != null) await _playMove(mv);
    }
  }

  void _replayApply(LudoMove mv) {
    if (mv.captures.isNotEmpty) _captures[mv.seat] += mv.captures.length;
    _engine.play(mv);
  }

  @override
  void dispose() {
    _inbox?.close();
    _hopCtl.removeListener(_onHopTick);
    _rollCtl.dispose();
    _hopCtl.dispose();
    _pulseCtl.dispose();
    _flashCtl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- helpers
  bool _isBot(int seat) => _bots[seat] != null;

  Color _color(int seat) => kLudoSeatColors[seat % kLudoSeatColors.length];

  static const String _faDigits = '۰۱۲۳۴۵۶۷۸۹';
  String _faNum(int v) =>
      v.toString().split('').map((String c) => _faDigits[int.parse(c)]).join();

  String _nameFa(int seat) {
    final String? online = _l.netName(seat);
    if (online != null) return online;
    if (seat == 0) return _l.playerName;
    if (_l.vsBot) return _n == 2 ? 'ربات NX' : 'ربات ${_faNum(seat)}';
    return 'بازیکن ${_faNum(seat + 1)}';
  }

  String _nameEn(int seat) {
    final String? online = _l.netName(seat);
    if (online != null) return online;
    if (seat == 0) return _l.playerName;
    if (_l.vsBot) return _n == 2 ? 'NX Bot' : 'Bot $seat';
    return 'Player ${seat + 1}';
  }

  String _name(int seat) => _l.isFa ? _nameFa(seat) : _nameEn(seat);

  void _status(String fa, String en) {
    _statusFa = fa;
    _statusEn = en;
  }

  Future<void> _wait(int ms) => Future<void>.delayed(
      Duration(milliseconds: _l.reducedMotion ? (ms * 0.6).round() : ms));

  void _haptic({bool heavy = false}) {
    if (!_l.soundOn) return;
    if (heavy) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _onHopTick() {
    if (_flights.isEmpty) return;
    final int segs = _flights.first.path.length - 1;
    if (segs <= 0) return;
    final int seg = min(segs - 1, (_hopCtl.value * segs).floor());
    if (seg != _lastHopSegment) {
      _lastHopSegment = seg;
      if (seg > 0) _haptic();
    }
  }

  // ------------------------------------------------------------------ flow
  void _beginTurn() {
    if (!mounted || _finished) return;
    _skipOut();
    final int seat = _s.turn;
    _l.net?.turnSeat = seat;
    setState(() {
      _moves = <LudoMove>[];
      if (_isRemote(seat)) {
        _status('نوبت ${_nameFa(seat)} — منتظر حرکتش…',
            "${_nameEn(seat)}'s turn — waiting…");
      } else if (_isBot(seat)) {
        _status('نوبت ${_nameFa(seat)}', "${_nameEn(seat)}'s turn");
      } else {
        _status('نوبت ${_nameFa(seat)} — تاس را لمس کن',
            '${_nameEn(seat)} — tap the die');
      }
    });
    if (_isBot(seat)) _botTurn(seat);
  }

  Future<void> _botTurn(int seat) async {
    await _wait(550 + Random().nextInt(350));
    if (!mounted || _finished || _s.turn != seat) return;
    await _roll(fromBot: true);
  }

  Future<void> _roll({bool fromBot = false, bool fromNet = false}) async {
    if (_rolling || _busy || _moves.isNotEmpty || _finished) return;
    final int seat = _s.turn;
    if (_isBot(seat) && !fromBot) return;
    if (_isRemote(seat) && !fromNet) return;
    if (_l.online && !fromNet) {
      _l.net!.send(<String, dynamic>{'a': 'roll', 'h': _stateHash()});
    }
    setState(() => _rolling = true);
    _haptic();
    await _rollCtl.forward(from: 0);
    if (!mounted) return;
    final LudoRollResult r = _engine.roll();
    _haptic(heavy: true);
    setState(() {
      _rolling = false;
      _dieValue = r.roll;
    });
    if (r.forfeited) {
      setState(() => _status(
          'سه شش پشت سر هم — نوبت سوخت!', 'Three sixes in a row — turn lost!'));
      await _wait(1300);
      _beginTurn();
      return;
    }
    if (r.rollAgain) {
      setState(() => _status('حرکتی نیست، ولی شش آوردی — دوباره بریز',
          'No move, but a six — roll again'));
      await _wait(900);
      _beginTurn();
      return;
    }
    if (r.moves.isEmpty) {
      setState(() => _status('حرکتی ممکن نیست', 'No possible move'));
      await _wait(900);
      _beginTurn();
      return;
    }
    setState(() => _moves = r.moves);
    final LudoBot? bot = _bots[seat];
    if (bot != null) {
      setState(() => _status(
          '${_nameFa(seat)} فکر می‌کند…', '${_nameEn(seat)} is thinking…'));
      await _wait(420 + _l.difficulty.index * 120);
      if (!mounted) return;
      await _playMove(bot.choose(_s, r.moves));
      return;
    }
    if (_allSame(r.moves)) {
      await _wait(320);
      if (!mounted) return;
      await _playMove(r.moves.first);
      return;
    }
    if (_isRemote(seat)) {
      setState(() => _status('${_nameFa(seat)} مهره انتخاب می‌کند…',
          '${_nameEn(seat)} is choosing…'));
      return;
    }
    setState(
        () => _status('یک مهره‌ی درخشان را انتخاب کن', 'Pick a glowing token'));
  }

  bool _allSame(List<LudoMove> moves) {
    for (final LudoMove m in moves) {
      if (m.from != moves.first.from || m.to != moves.first.to) return false;
    }
    return true;
  }

  List<Offset> _pathFor(LudoState s, LudoMove m) {
    final List<Offset> path = <Offset>[];
    if (m.from == kLudoBase) {
      path.add(LudoGeom.cellFor(s, m.seat, m.token, kLudoBase));
      path.add(LudoGeom.cellFor(s, m.seat, m.token, 0));
      return path;
    }
    for (int p = m.from; p <= m.to; p++) {
      path.add(LudoGeom.cellFor(s, m.seat, m.token, p));
    }
    return path;
  }

  Future<void> _fly(List<_Flight> flights, int ms) async {
    _lastHopSegment = -1;
    setState(() => _flights = flights);
    _hopCtl.duration =
        Duration(milliseconds: max(120, _l.reducedMotion ? ms ~/ 2 : ms));
    await _hopCtl.forward(from: 0);
  }

  Future<void> _playMove(LudoMove m) async {
    if (_busy) return;
    _busy = true;
    setState(() => _moves = <LudoMove>[]);
    final LudoState before = _s.copy();
    final List<Offset> path = _pathFor(before, m);
    await _fly(
        <_Flight>[_Flight(m.seat, m.token, path)], (path.length - 1) * 165);
    if (!mounted) return;
    final Offset landing = path.last;
    final LudoPlayResult res = _engine.play(m);
    if (m.captures.isNotEmpty) {
      _captures[m.seat] += m.captures.length;
      final List<_Flight> back = m.captures
          .map((LudoCapture c) => _Flight(c.seat, c.token, <Offset>[
                landing,
                LudoGeom.cellFor(_s, c.seat, c.token, kLudoBase)
              ]))
          .toList();
      setState(() {
        _flights = <_Flight>[];
        _flashAt = landing;
        _status('ضربه! ${_nameFa(m.seat)} مهره را به پایگاه فرستاد',
            'Hit! ${_nameEn(m.seat)} sends a token back to base');
      });
      _haptic(heavy: true);
      if (_fancy) _flashCtl.forward(from: 0);
      await _fly(back, 480);
      if (!mounted) return;
    }
    setState(() => _flights = <_Flight>[]);
    _busy = false;
    if (res.won) {
      _gameOver(m.seat);
      return;
    }
    if (res.extraTurn) {
      setState(() {
        if (m.finishes) {
          _status(
              'مهره به خانه رسید — نوبت اضافه!', 'Token home — extra turn!');
        } else if (m.captures.isEmpty) {
          _status('شش! یک نوبت دیگر', 'Six! Roll again');
        }
      });
      await _wait(m.captures.isEmpty ? 380 : 650);
      if (!mounted) return;
      final int seat = _s.turn;
      if (_isBot(seat)) {
        _botTurn(seat);
      } else if (_isRemote(seat)) {
        setState(() => _status('${_nameFa(seat)} دوباره می‌ریزد…',
            '${_nameEn(seat)} rolls again…'));
      } else {
        setState(() => _status('${_nameFa(seat)}، دوباره تاس را لمس کن',
            '${_nameEn(seat)}, tap the die again'));
      }
      return;
    }
    await _wait(250);
    if (!mounted || _finished) return;
    _beginTurn();
  }

  void _onBoardTap(Offset local, double boardSize) {
    if (_moves.isEmpty || _busy || _isBot(_s.turn) || _isRemote(_s.turn)) {
      return;
    }
    final double u = boardSize / 15;
    final Offset p = local / u;
    LudoMove? best;
    double bestD = 0.9;
    for (final LudoMove m in _moves) {
      final Offset c = LudoGeom.cellFor(_s, m.seat, m.token, m.from);
      final double d = (c - p).distance;
      if (d < bestD) {
        bestD = d;
        best = m;
      }
    }
    final LudoMove? chosen = best;
    if (chosen != null) {
      if (_l.online) {
        _l.net!.send(
            <String, dynamic>{'a': 'play', 't': chosen.token, 'to': chosen.to});
      }
      _playMove(chosen);
    }
  }

  void _gameOver(int winner) {
    if (_finished) return;
    _finished = true;
    _haptic(heavy: true);
    setState(() {
      _bannerFa = '${_nameFa(winner)} برنده شد!';
      _bannerEn = '${_nameEn(winner)} wins!';
      _status('همه‌ی مهره‌ها در خانه', 'All tokens home');
    });
    int bestOther = 0;
    for (int i = 0; i < _n; i++) {
      if (i != _me) bestOther = max(bestOther, _s.homeCount(i));
    }
    final int mine = _s.homeCount(_me);
    final String fa =
        'برنده: ${_nameFa(winner)}. مهره‌های تو در خانه: ${_faNum(mine)}/۴ • ضربه‌های تو: ${_faNum(_captures[_me])} • بازیکنان: ${_faNum(_n)}';
    final String en =
        'Winner: ${_nameEn(winner)}. Your tokens home: $mine/4 • your captures: ${_captures[_me]} • players: $_n';
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      _l.onFinish(GameResult(
        outcome: winner == _me ? GameOutcome.win : GameOutcome.loss,
        score: mine,
        opponentScore: winner == _me ? bestOther : _s.homeCount(winner),
        winnerSeats: <int>[winner],
        scores: <int>[for (int i = 0; i < _n; i++) _s.homeCount(i)],
        summaryFa: fa,
        summaryEn: en,
      ));
    });
  }

  // ------------------------------------------------------------------ build
  List<LudoTokenDraw> _tokenDraws() {
    final Map<String, List<List<int>>> groups = <String, List<List<int>>>{};
    final Set<String> flying =
        _flights.map((_Flight f) => '${f.seat}:${f.token}').toSet();
    final Set<String> movable =
        _moves.map((LudoMove m) => '${m.seat}:${m.token}').toSet();
    for (int seat = 0; seat < _n; seat++) {
      for (int t = 0; t < kLudoTokens; t++) {
        if (flying.contains('$seat:$t')) continue;
        final Offset c = LudoGeom.cellFor(_s, seat, t, _s.tokens[seat][t]);
        final String key =
            '${c.dx.toStringAsFixed(2)},${c.dy.toStringAsFixed(2)}';
        groups.putIfAbsent(key, () => <List<int>>[]).add(<int>[seat, t]);
      }
    }
    final List<LudoTokenDraw> out = <LudoTokenDraw>[];
    groups.forEach((String key, List<List<int>> members) {
      final int n = members.length;
      for (int i = 0; i < n; i++) {
        final int seat = members[i][0];
        final int t = members[i][1];
        Offset c = LudoGeom.cellFor(_s, seat, t, _s.tokens[seat][t]);
        double scale = 1;
        if (n > 1) {
          scale = n == 2 ? 0.8 : 0.68;
          final double a = 2 * pi * i / n - pi / 4;
          c = c + Offset(cos(a), sin(a)) * 0.2;
        }
        out.add(LudoTokenDraw(
          pos: c,
          color: _color(seat),
          scale: scale,
          movable:
              movable.contains('$seat:$t') && !_isBot(seat) && !_isRemote(seat),
        ));
      }
    });
    final double v = _hopCtl.value;
    for (final _Flight f in _flights) {
      final int segs = f.path.length - 1;
      if (segs <= 0) {
        out.add(LudoTokenDraw(pos: f.path.first, color: _color(f.seat)));
        continue;
      }
      double x = v * segs;
      if (x < 0) x = 0;
      if (x > segs) x = segs.toDouble();
      final int i = min(segs - 1, x.floor());
      final double local = x - i;
      final Offset pos = Offset.lerp(f.path[i], f.path[i + 1], local)!;
      final double lift = sin(local * pi) * (segs == 1 ? 0.8 : 0.45);
      out.add(LudoTokenDraw(
          pos: pos, color: _color(f.seat), lift: lift, scale: 1.05));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(child: _background()),
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
                  padding: const EdgeInsets.all(10),
                  child: Center(child: _boardView()),
                ),
              ),
              _bottomBar(),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ],
    );
  }

  Widget _background() {
    final NxThemeColors visual = NxThemeColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.1),
          radius: 1.2,
          colors: <Color>[
            visual.backgroundMid,
            visual.background,
            visual.background
          ],
          stops: const <double>[0, 0.6, 1],
        ),
      ),
      child: CustomPaint(
          painter:
              _LudoStars(_fancy ? 130 : 50, NxThemeColors.of(context).accent)),
    );
  }

  Widget _playersBar() {
    final List<Widget> chips = <Widget>[];
    for (int seat = 0; seat < _n; seat++) {
      final bool active = _s.turn == seat && !_finished;
      final Color col = _color(seat);
      final NxThemeColors visual = NxThemeColors.of(context);
      chips.add(AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color:
              active ? visual.accent.withValues(alpha: 0.16) : visual.surface,
          border: Border.all(
              color: active
                  ? visual.accent
                  : visual.border.withValues(alpha: 0.55),
              width: active ? 1.8 : 1),
          boxShadow: active && _fancy
              ? <BoxShadow>[
                  BoxShadow(color: col.withValues(alpha: 0.4), blurRadius: 14)
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: col,
                boxShadow: <BoxShadow>[BoxShadow(color: col, blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                _name(seat),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: visual.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '★${_s.homeCount(seat)}/4',
              style: TextStyle(
                  color: col, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ],
        ),
      ));
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }

  Widget _boardView() {
    final List<Color?> cornerColors = List<Color?>.filled(4, null);
    for (int seat = 0; seat < _n; seat++) {
      cornerColors[_s.corners[seat]] = _color(seat);
    }
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double size = min(c.maxWidth, c.maxHeight);
          return Directionality(
            textDirection: TextDirection.ltr,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails d) => _onBoardTap(d.localPosition, size),
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: LudoBoardPainter(
                              cornerColors: cornerColors,
                              fancy: _fancy,
                              accent: NxThemeColors.of(context).accent,
                              accentSecondary:
                                  NxThemeColors.of(context).accentSecondary,
                              surface: NxThemeColors.of(context).surfaceRaised),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: Listenable.merge(
                            <Listenable>[_hopCtl, _pulseCtl, _flashCtl]),
                        builder: (BuildContext context, Widget? child) =>
                            CustomPaint(
                          painter: LudoTokensPainter(
                            tokens: _tokenDraws(),
                            pulse: _pulseCtl.value,
                            fancy: _fancy,
                            flashAt: _flashAt,
                            flash: _flashCtl.value,
                          ),
                        ),
                      ),
                    ),
                    if (_bannerFa != null) _banner(size),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _banner(double size) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.5, end: 1),
        duration: const Duration(milliseconds: 650),
        curve: Curves.elasticOut,
        builder: (BuildContext c, double v, Widget? child) =>
            Transform.scale(scale: v, child: child),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: size * 0.06, vertical: size * 0.04),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color:
                NxThemeColors.of(context).surfaceRaised.withValues(alpha: 0.96),
            border:
                Border.all(color: NxThemeColors.of(context).accent, width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                  color:
                      NxThemeColors.of(context).accent.withValues(alpha: 0.25),
                  blurRadius: 28)
            ],
          ),
          child: Text(
            _l.isFa ? (_bannerFa ?? '') : (_bannerEn ?? ''),
            textAlign: TextAlign.center,
            textDirection: _l.isFa ? TextDirection.rtl : TextDirection.ltr,
            style: TextStyle(
                color: NxThemeColors.of(context).accent,
                fontSize: size * 0.07,
                fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final int seat = _s.turn;
    final bool canTap = !_isBot(seat) &&
        !_isRemote(seat) &&
        !_rolling &&
        !_busy &&
        _moves.isEmpty &&
        !_finished;
    final Color col = _color(seat);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: canTap ? () => _roll() : null,
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_rollCtl, _pulseCtl]),
              builder: (BuildContext context, Widget? child) {
                final double breathe = canTap ? 1 + 0.06 * _pulseCtl.value : 1;
                return Transform.scale(
                  scale: breathe,
                  child: LudoDie(
                    value: _dieValue,
                    color: col,
                    size: 64,
                    rolling: _rolling,
                    t: _rollCtl.value,
                    glow: _fancy || canTap,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NxThemeColors.of(context).surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: NxThemeColors.of(context)
                        .border
                        .withValues(alpha: 0.6)),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  _l.isFa ? _statusFa : _statusEn,
                  key: ValueKey<String>(_statusFa + _statusEn),
                  textAlign: TextAlign.start,
                  style: TextStyle(
                      color: NxThemeColors.of(context).text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LudoStars extends CustomPainter {
  _LudoStars(this.count, this.accent);
  final int count;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Random r = Random(11);
    final Paint p = Paint();
    for (int i = 0; i < count; i++) {
      p.color = (i % 5 == 0 ? accent : const Color(0xFFEAF6FF))
          .withValues(alpha: 0.2 + r.nextDouble() * 0.6);
      canvas.drawCircle(
          Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
          r.nextDouble() * 1.5 + 0.3,
          p);
    }
  }

  @override
  bool shouldRepaint(covariant _LudoStars oldDelegate) =>
      oldDelegate.count != count || oldDelegate.accent != accent;
}
