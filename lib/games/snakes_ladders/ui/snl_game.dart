import 'dart:math';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/ui2/nx2_board_art.dart';
import 'package:flutter/services.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/core/game_contract.dart';

import '../core/snl_rules.dart';
import 'snl_board.dart';

class SnlGame extends StatefulWidget {
  const SnlGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<SnlGame> createState() => _SnlGameState();
}

class _SnlGameState extends State<SnlGame> with TickerProviderStateMixin {
  /// 0 = NX2 dragon board, 1 = neon classic.
  int _skin = (LocalStore.instance.getInt('snakes_ladders.board_skin') ?? 0) % 2;
  void _nextSkin() {
    setState(() => _skin = (_skin + 1) % 2);
    LocalStore.instance.setInt('snakes_ladders.board_skin', _skin);
  }

  late SnlEngine _engine;
  late AnimationController _rollCtl;
  late AnimationController _hopCtl;
  late AnimationController _glideCtl;
  late AnimationController _pulseCtl;
  late AnimationController _ambientCtl;
  late AnimationController _burstCtl;

  /// Squares currently shown on screen per seat (lags the engine during moves).
  late List<int> _shown;
  late List<int> _climbs;
  late List<int> _bites;

  int? _dieValue;
  bool _rolling = false;
  bool _busy = false;
  bool _finished = false;
  bool _resultSent = false;
  int _uiTurn = 0;

  int? _movingSeat;
  List<Offset> _hopPath = <Offset>[];
  List<Offset> _glidePath = <Offset>[];
  bool _gliding = false;
  int _lastHopSegment = -1;

  Offset? _burstAt;
  Color _burstColor = Colors.white;

  String _statusFa = '';
  String _statusEn = '';
  String? _bannerFa;
  String? _bannerEn;

  // ------------------------------------------------------------- online
  NetInbox? _inbox;
  final Set<int> _out = <int>{}; // forfeited seats (online)

  GameLaunch get _l => widget.launch;
  bool _isRemote(int seat) => _l.isRemoteSeat(seat);
  int get _me => _l.mySeat;
  bool get _fancy => _l.fancyEffects && !_l.reducedMotion;
  int get _n => _engine.playerCount;

  @override
  void initState() {
    super.initState();
    final int seed = _l.seed ?? DateTime.now().microsecondsSinceEpoch;
    _engine = SnlEngine(playerCount: _l.playerCount, seed: seed);
    _shown = List<int>.filled(_n, 0);
    _climbs = List<int>.filled(_n, 0);
    _bites = List<int>.filled(_n, 0);
    _rollCtl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _l.reducedMotion ? 250 : 700));
    _hopCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _hopCtl.addListener(_onHopTick);
    _glideCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _pulseCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _ambientCtl =
        AnimationController(vsync: this, duration: const Duration(seconds: 4));
    if (_l.reducedMotion) {
      _pulseCtl.value = 0.8;
    } else {
      _pulseCtl.repeat(reverse: true);
    }
    if (_fancy) _ambientCtl.repeat();
    _burstCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
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

  String _stateHash() => hashOf(
      '${_engine.positions.join(',')}|${_engine.turn}|${_out.join(',')}');

  /// Online: apply one logged move. Replay = rebuild state instantly, no animation.
  Future<void> _onNet(NetMove m) async {
    if (!mounted) return;
    if (m.kind == 'replayDone') {
      setState(() {
        for (int i = 0; i < _n; i++) {
          _shown[i] = _engine.positions[i];
        }
        _dieValue = null;
      });
      if (_engine.winner != null) {
        _gameOver(_engine.winner!);
      } else if (!_checkLastStanding()) {
        _beginTurn();
      }
      return;
    }
    if (m.isForfeit) {
      final int seat = (m.data['seat'] as num?)?.toInt() ?? m.seat;
      _out.add(seat);
      if (m.replay) {
        if (_engine.turn == seat) _skipOut();
        return;
      }
      if (_checkLastStanding()) return;
      if (_engine.turn == seat && !_busy && !_rolling) _beginTurn();
      return;
    }
    if (m.kind != 'move' || m.data['a'] != 'roll') return;
    if (_engine.turn != m.seat || _engine.winner != null) return;
    _l.net?.verify(m.seq, m.data['h'] as String?, _stateHash());
    if (m.replay) {
      final int roll = _engine.rollDie();
      final SnlMoveResult res = _engine.move(roll);
      if (res.climbed) _climbs[res.seat]++;
      if (res.bitten) _bites[res.seat]++;
      _skipOut();
      return;
    }
    while (_busy || _rolling) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
    }
    await _roll(fromNet: true);
  }

  void _skipOut() {
    int guard = 0;
    while (_out.contains(_engine.turn) && guard < _n) {
      _engine.turn = (_engine.turn + 1) % _n;
      guard++;
    }
  }

  /// Online: when everyone else left, the last player standing wins.
  bool _checkLastStanding() {
    if (!_l.online || _finished) return false;
    final List<int> alive = <int>[
      for (int i = 0; i < _n; i++)
        if (!_out.contains(i)) i
    ];
    if (alive.length == 1) {
      _engine.winner = alive.first;
      _gameOver(alive.first);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _inbox?.close();
    _hopCtl.removeListener(_onHopTick);
    _rollCtl.dispose();
    _hopCtl.dispose();
    _glideCtl.dispose();
    _pulseCtl.dispose();
    _ambientCtl.dispose();
    _burstCtl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- helpers
  bool _isBot(int seat) => _l.vsBot && seat != 0;

  Color _color(int seat) => kSnlSeatColors[seat % kSnlSeatColors.length];

  String _faNum(int v) => snlNum(v, true);

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
    final int segs = _hopPath.length - 1;
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
    final int seat = _engine.turn;
    _l.net?.turnSeat = seat;
    setState(() {
      _uiTurn = seat;
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
    final int extra = _l.difficulty == BotDifficulty.easy ? 200 : 0;
    await _wait(600 + extra + Random().nextInt(450));
    if (!mounted || _finished || _engine.turn != seat) return;
    await _roll(fromBot: true);
  }

  Future<void> _roll({bool fromBot = false, bool fromNet = false}) async {
    if (_rolling || _busy || _finished) return;
    final int seat = _engine.turn;
    if (_isBot(seat) && !fromBot) return;
    if (_isRemote(seat) && !fromNet) return;
    if (_l.online && !fromNet) {
      // Our own roll: log it first so every phone rolls the same seeded die in the same order.
      _l.net!.send(<String, dynamic>{'a': 'roll', 'h': _stateHash()});
    }
    setState(() => _rolling = true);
    _haptic();
    await _rollCtl.forward(from: 0);
    if (!mounted) return;
    final int roll = _engine.rollDie();
    _haptic(heavy: true);
    setState(() {
      _rolling = false;
      _dieValue = roll;
    });
    await _wait(200);
    if (!mounted) return;
    final SnlMoveResult res = _engine.move(roll);
    await _animateMove(res);
  }

  Future<void> _animateMove(SnlMoveResult res) async {
    _busy = true;
    final int seat = res.seat;
    final bool bounced = res.steps.contains(kSnlGoal) && res.landed != kSnlGoal;
    // Hop square by square.
    final List<Offset> hop = <Offset>[SnlGeom.pos(res.from, seat)];
    for (final int sq in res.steps) {
      hop.add(SnlGeom.cell(sq));
    }
    _lastHopSegment = -1;
    setState(() {
      _movingSeat = seat;
      _hopPath = hop;
      _gliding = false;
      if (bounced) {
        _status('برگشت از ۱۰۰! باید دقیقاً به ۱۰۰ برسی',
            'Bounced off 100! You need an exact roll');
      }
    });
    final int hopMs =
        max(160, (hop.length - 1) * (_l.reducedMotion ? 110 : 170));
    _hopCtl.duration = Duration(milliseconds: hopMs);
    await _hopCtl.forward(from: 0);
    if (!mounted) return;

    if (res.climbed || res.bitten) {
      final Offset a = SnlGeom.cell(res.landed);
      final Offset b = SnlGeom.cell(res.finalPos);
      final List<Offset> glide = res.climbed
          ? <Offset>[a, b]
          : SnlGeom.snakePath(a, b,
              _fancy ? SnlOverlayPainter.snakePhase(_ambientCtl.value) : 0);
      if (res.climbed) {
        _climbs[seat]++;
      } else {
        _bites[seat]++;
      }
      setState(() {
        _shown[seat] = res.landed;
        _glidePath = glide;
        _gliding = true;
        if (res.climbed) {
          _status(
              'پل نور! ${_nameFa(seat)} تا ${_faNum(res.finalPos)} بالا رفت',
              'Light-bridge! ${_nameEn(seat)} climbs to ${res.finalPos}');
        } else {
          _status(
              'مار کیهانی! ${_nameFa(seat)} به ${_faNum(res.finalPos)} سُر خورد',
              'Cosmic serpent! ${_nameEn(seat)} slides to ${res.finalPos}');
        }
      });
      _haptic(heavy: true);
      await _wait(160);
      if (!mounted) return;
      final double dist = (b - a).distance;
      _glideCtl.duration = Duration(
          milliseconds: (_l.reducedMotion ? 300 : 450) + (dist * 45).round());
      await _glideCtl.forward(from: 0);
      if (!mounted) return;
      _burstAt = b;
      _burstColor =
          res.climbed ? const Color(0xFF2EE6D6) : const Color(0xFFFF4FA3);
      if (_fancy) _burstCtl.forward(from: 0);
    }

    setState(() {
      _shown[seat] = res.finalPos;
      _movingSeat = null;
      _hopPath = <Offset>[];
      _glidePath = <Offset>[];
      _gliding = false;
    });
    _busy = false;

    if (res.won) {
      _gameOver(seat);
      return;
    }
    if (res.extraTurn) {
      await _wait(res.climbed || res.bitten ? 650 : 380);
      if (!mounted || _finished) return;
      setState(() {
        _uiTurn = _engine.turn;
        _status('شش! ${_nameFa(seat)} دوباره می‌ریزد',
            'Six! ${_nameEn(seat)} rolls again');
      });
      if (_isBot(seat)) {
        _botTurn(seat);
      }
      return;
    }
    await _wait(res.climbed || res.bitten || bounced ? 700 : 280);
    if (!mounted || _finished) return;
    _beginTurn();
  }

  void _gameOver(int winner) {
    if (_finished) return;
    _finished = true;
    _haptic(heavy: true);
    _burstAt = SnlGeom.cell(kSnlGoal);
    _burstColor = const Color(0xFFFFC857);
    if (_fancy) _burstCtl.forward(from: 0);
    setState(() {
      _bannerFa = '${_nameFa(winner)} برنده شد!';
      _bannerEn = '${_nameEn(winner)} wins!';
      _status('رسید به ستاره‌ی ۱۰۰', 'Reached star 100');
    });
    int bestOther = 0;
    for (int i = 0; i < _n; i++) {
      if (i != _me) bestOther = max(bestOther, _engine.positions[i]);
    }
    final int mine = _engine.positions[_me];
    final String fa =
        'برنده: ${_nameFa(winner)}. خانه‌ی تو: ${_faNum(mine)} • پل‌های نور: ${_faNum(_climbs[_me])} • نیش مار: ${_faNum(_bites[_me])} • بازیکنان: ${_faNum(_n)}';
    final String en =
        'Winner: ${_nameEn(winner)}. Your square: $mine • ladders climbed: ${_climbs[_me]} • snake bites: ${_bites[_me]} • players: $_n';
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted || _resultSent) return;
      _resultSent = true;
      _l.onFinish(GameResult(
        outcome: winner == _me ? GameOutcome.win : GameOutcome.loss,
        winnerSeats: <int>[winner],
        scores: List<int>.from(_engine.positions),
        score: mine,
        opponentScore: bestOther,
        summaryFa: fa,
        summaryEn: en,
      ));
    });
  }

  // ------------------------------------------------------------------ build
  Offset _movingPos(double hopV, double glideV) {
    if (_gliding && _glidePath.isNotEmpty) {
      final double e = Curves.easeInOut.transform(glideV.clamp(0.0, 1.0));
      return SnlGeom.along(_glidePath, e);
    }
    final int segs = _hopPath.length - 1;
    if (segs <= 0) return _hopPath.isEmpty ? Offset.zero : _hopPath.first;
    double x = hopV * segs;
    if (x < 0) x = 0;
    if (x > segs) x = segs.toDouble();
    final int i = min(segs - 1, x.floor());
    final double local = x - i;
    return Offset.lerp(_hopPath[i], _hopPath[i + 1], local)!;
  }

  double _movingLift(double hopV) {
    if (_gliding) return 0.12;
    final int segs = _hopPath.length - 1;
    if (segs <= 0) return 0;
    double x = hopV * segs;
    if (x > segs) x = segs.toDouble();
    final int i = min(segs - 1, x.floor());
    final double local = x - i;
    return sin(local * pi) * 0.4;
  }

  List<SnlTokenDraw> _tokenDraws() {
    final Map<int, List<int>> groups = <int, List<int>>{};
    for (int seat = 0; seat < _n; seat++) {
      if (seat == _movingSeat) continue;
      final int sq = _shown[seat];
      if (sq <= 0) continue;
      groups.putIfAbsent(sq, () => <int>[]).add(seat);
    }
    final List<SnlTokenDraw> out = <SnlTokenDraw>[];
    final bool waiting = !_busy && !_finished;
    for (int seat = 0; seat < _n; seat++) {
      if (seat == _movingSeat || _shown[seat] > 0) continue;
      out.add(SnlTokenDraw(
          pos: SnlGeom.pad(seat),
          color: _color(seat),
          active: waiting && seat == _uiTurn));
    }
    groups.forEach((int sq, List<int> seats) {
      final int k = seats.length;
      for (int i = 0; i < k; i++) {
        Offset c = SnlGeom.cell(sq);
        double scale = 1;
        if (k > 1) {
          scale = k == 2 ? 0.78 : 0.64;
          final double a = 2 * pi * i / k - pi / 4;
          c = c + Offset(cos(a), sin(a)) * 0.2;
        }
        out.add(SnlTokenDraw(
          pos: c,
          color: _color(seats[i]),
          scale: scale,
          active: waiting && seats[i] == _uiTurn,
        ));
      }
    });
    final int? m = _movingSeat;
    if (m != null && (_hopPath.isNotEmpty || _glidePath.isNotEmpty)) {
      out.add(SnlTokenDraw(
        pos: _movingPos(_hopCtl.value, _glideCtl.value),
        color: _color(m),
        lift: _movingLift(_hopCtl.value),
        scale: 1.08,
      ));
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
          center: const Alignment(0, -0.2),
          radius: 1.25,
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
              _SnlStars(_fancy ? 140 : 50, NxThemeColors.of(context).accent)),
    );
  }

  Widget _playersBar() {
    final List<Widget> chips = <Widget>[];
    for (int seat = 0; seat < _n; seat++) {
      final bool active = _uiTurn == seat && !_finished;
      final Color col = _color(seat);
      final NxThemeColors visual = NxThemeColors.of(context);
      final int sq = _shown[seat];
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
              sq <= 0 ? '◎' : snlNum(sq, _l.isFa),
              style: TextStyle(
                  color: col, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ],
        ),
      ));
    }
    chips.add(Nx2BoardButton(onTap: _nextSkin, size: 30));
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }

  Widget _boardView() {
    if (_skin == 0) {
      const double fw = 10 + kSnlFrameL + kSnlFrameR, fh = 10 + kSnlFrameT + kSnlFrameB;
      return AspectRatio(
        aspectRatio: fw / fh,
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
          final double u = c.maxWidth / fw;
          return Stack(children: <Widget>[
            Positioned.fill(
              child: Nx2ArtCanvas(
                asset: kSnlDragonAsset,
                size: Size(c.maxWidth, c.maxHeight),
                painter: (ui.Image img) => SnlDragonFramePainter(img),
              ),
            ),
            Positioned(
              left: kSnlFrameL * u,
              top: kSnlFrameT * u,
              width: 10 * u,
              height: kSnlBoardRows * u,
              child: _boardCore(dragon: true),
            ),
          ]);
        }),
      );
    }
    return _boardCore(dragon: false);
  }

  Widget _boardCore({required bool dragon}) {
    return AspectRatio(
      aspectRatio: 10 / kSnlBoardRows,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          double w = c.maxWidth;
          if (w * kSnlBoardRows / 10 > c.maxHeight) {
            w = c.maxHeight * 10 / kSnlBoardRows;
          }
          final double h = w * kSnlBoardRows / 10;
          final Size boardSize = Size(w, w);
          return Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: dragon
                          ? CustomPaint(painter: SnlDragonCellsPainter(isFa: _l.isFa))
                          : CustomPaint(
                        painter: SnlBoardPainter(
                            fancy: _fancy,
                            isFa: _l.isFa,
                            accent: NxThemeColors.of(context).accent,
                            accentSecondary:
                                NxThemeColors.of(context).accentSecondary,
                            surface: NxThemeColors.of(context).surfaceRaised),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    width: boardSize.width,
                    height: boardSize.height,
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _ambientCtl,
                        builder: (BuildContext context, Widget? child) =>
                            CustomPaint(
                          painter: SnlOverlayPainter(
                              t: _ambientCtl.value,
                              fancy: _fancy,
                              accent: NxThemeColors.of(context).accent,
                              accentSecondary:
                                  NxThemeColors.of(context).accentSecondary),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: Listenable.merge(<Listenable>[
                        _hopCtl,
                        _glideCtl,
                        _pulseCtl,
                        _burstCtl
                      ]),
                      builder: (BuildContext context, Widget? child) =>
                          CustomPaint(
                        painter: SnlTokensPainter(
                          tokens: _tokenDraws(),
                          pulse: _pulseCtl.value,
                          fancy: _fancy,
                          burstAt: _burstAt,
                          burst: _burstCtl.value,
                          burstColor: _burstColor,
                        ),
                      ),
                    ),
                  ),
                  if (_bannerFa != null) _banner(w),
                ],
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
        duration: Duration(milliseconds: _l.reducedMotion ? 200 : 650),
        curve: _l.reducedMotion ? Curves.easeOut : Curves.elasticOut,
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
    final int seat = _uiTurn;
    final bool canTap = !_isBot(seat) &&
        !_isRemote(seat) &&
        !_rolling &&
        !_busy &&
        !_finished &&
        _engine.turn == seat;
    final Color col = _color(_movingSeat ?? seat);
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
                  child: SnlDie(
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

class _SnlStars extends CustomPainter {
  _SnlStars(this.count, this.accent);
  final int count;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Random r = Random(23);
    final Paint p = Paint();
    for (int i = 0; i < count; i++) {
      p.color = (i % 6 == 0 ? accent : const Color(0xFFEAF6FF))
          .withValues(alpha: 0.2 + r.nextDouble() * 0.6);
      canvas.drawCircle(
          Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
          r.nextDouble() * 1.5 + 0.3,
          p);
    }
  }

  @override
  bool shouldRepaint(covariant _SnlStars oldDelegate) =>
      oldDelegate.count != count || oldDelegate.accent != accent;
}
