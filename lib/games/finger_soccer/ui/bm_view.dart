// BERMUDA NXG disc football inside the NEXORA hub: pre-match setup (team / formation / field / ball),
// the match (engine + painter + HUD) and the online wiring over the hub's NetLink (Supabase move log).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexora/games/core/game_contract.dart';
import '../core/bm_data.dart';
import '../core/bm_engine.dart';
import 'bm_audio.dart';
import 'bm_ball.dart';
import 'bm_painter.dart';

const String _a = 'assets/games/bermuda/';

/// Online match settings (config.js MATCH_SECONDS / TURN_SECONDS).
const int kBmMatchSeconds = 300;
const double kBmOnlineTurnSeconds = 15;

class BermudaView extends StatefulWidget {
  const BermudaView({super.key, required this.launch, this.autoStart = false});
  final GameLaunch launch;

  /// Offline only: skip the setup screen with the saved/default picks (used by tests).
  final bool autoStart;

  @override
  State<BermudaView> createState() => _BermudaViewState();
}

class _Setup {
  _Setup(this.team, this.form, this.field, this.ball);
  String team;
  int form, field, ball;
  Map<String, dynamic> toJson() => <String, dynamic>{
        'a': 'setup',
        'team': team,
        'form': form,
        'field': field,
        'ball': ball
      };
  static _Setup? fromJson(Map<String, dynamic> d) {
    final String? t = d['team'] as String?;
    if (t == null) return null;
    int i(String k) => (d[k] as num?)?.toInt() ?? 0;
    return _Setup(
        t,
        i('form').clamp(0, kBmForms.length - 1).toInt(),
        i('field').clamp(0, kBmFields.length - 1).toInt(),
        i('ball').clamp(0, NB - 1).toInt());
  }
}

class _BermudaViewState extends State<BermudaView>
    with TickerProviderStateMixin, WidgetsBindingObserver
    implements BmHooks {
  late final BmEngine e = BmEngine(this);
  final BmImages im = BmImages();
  final BmView view = BmView();
  late final BmAudio audio = BmAudio(enabled: widget.launch.soundOn);
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _nowMs = 0;
  late final AnimationController _goalAnim =
      AnimationController(vsync: this, duration: const Duration(seconds: 2));

  // setup
  String stage = 'setup'; // setup | waiting | match
  late _Setup my = _Setup('club0', 0, 6, 0);
  int _cat = 0;
  BmConfig? cfg;

  // toast
  String _toast = '';
  bool _toastBig = false;
  double _toastT = 0;

  // end
  double _finishIn = -1;
  bool _reported = false;
  bool _disposed = false;
  bool _paused = false;

  // online
  NetInbox? _inbox;
  bool _netReady = true;
  final Map<int, _Setup> _setups = <int, _Setup>{};
  Map<String, dynamic>? _pendingShot;
  int _pendingShotSeat = -1;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  GameLaunch get launch => widget.launch;
  bool get online => launch.online;
  int get mySeat => launch.mySeat;
  bool get isHostSeat => mySeat == 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addObserver(this);
    unawaited(audio.init());
    unawaited(_loadPrefs());
    final NetLink? net = launch.net;
    if (net != null) {
      _netReady = false;
      final NetInbox inbox = NetInbox(_onNet);
      _inbox = inbox;
      net.listen(inbox.add,
          onReplayDone: () => inbox.add(const NetMove(
              seq: -1,
              seat: -1,
              kind: 'replayDone',
              data: <String, dynamic>{})));
    } else if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && stage == 'setup') _startOffline();
      });
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String t = p.getString('bm.team') ?? 'club0';
      my = _Setup(
          kBmTeams.any((BmTeam x) => x.id == t) ? t : 'club0',
          (p.getInt('bm.form') ?? 0).clamp(0, kBmForms.length - 1).toInt(),
          (p.getInt('bm.field') ?? 6).clamp(0, kBmFields.length - 1).toInt(),
          (p.getInt('bm.ball') ?? 0).clamp(0, NB - 1).toInt());
      _cat = math.max(0,
          kBmCats.indexWhere((List<Object> c) => c[0] == bmTeam(my.team).cat));
      audio.announcer = p.getBool('bm.ann') ??
          false; // goal announcer voice: off unless the player turns it on
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString('bm.team', my.team);
      await p.setInt('bm.form', my.form);
      await p.setInt('bm.field', my.field);
      await p.setInt('bm.ball', my.ball);
    } catch (_) {}
  }

  // ------------------------------------------------------------------ loop
  void _onTick(Duration el) {
    double dt = (el - _last).inMicroseconds / 1e6;
    _last = el;
    if (dt < 0) dt = 0;
    _nowMs = el.inMicroseconds / 1000;
    audio.frame(dt);
    if (_toastT > 0) _toastT -= dt;
    if (stage == 'match') {
      _ensureBallRenderer();
      e.frame(dt);
      if (_waiters.isNotEmpty && e.phase != 'goal') {
        final List<Completer<void>> w = List<Completer<void>>.from(_waiters);
        _waiters.clear();
        for (final Completer<void> c in w) {
          if (!c.isCompleted) c.complete();
        }
      }
      if (_finishIn > 0) {
        _finishIn -= dt;
        if (_finishIn <= 0) _report();
      }
    }
    if (_disposed) return;
    _frame.value++;
  }

  void _ensureBallRenderer() {
    final ui.Image? b = im.ball;
    if (b == null || view.s <= 0) return;
    final double dpr =
        math.min(MediaQuery.maybeDevicePixelRatioOf(context) ?? 1, 1.75);
    final int n = math.max(
        40, math.min(96, math.max(2, (BR * 2 * view.s * dpr).round())));
    if (im.ballR == null || im.ballR!.n != n) {
      im.ballR?.dispose();
      final BmBallRenderer r = BmBallRenderer(n);
      im.ballR = r;
      unawaited(r.setTexture(b));
    }
  }

  // ------------------------------------------------------------------ hooks
  @override
  void sfx(String k, [double v = 1]) => audio.sfx(k, v);

  @override
  void tone(String k) => audio.tone(k);

  @override
  void vib(List<int> pattern) {
    if (!launch.soundOn) return;
    final int total = pattern.fold(0, (int a, int b) => a + b);
    if (total >= 100) {
      HapticFeedback.heavyImpact();
    } else if (total >= 30) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  @override
  void toast(String text, bool big) {
    _toast = text;
    _toastBig = big;
    _toastT = big ? 1.5 : 1.2;
  }

  @override
  void goalFx() {
    if (_disposed) return;
    _goalAnim.forward(from: 0);
  }

  @override
  void emit(String event, Map<String, dynamic> data) {
    final NetLink? net = launch.net;
    switch (event) {
      case 'shot':
        net?.send(<String, dynamic>{
          'a': 'shot',
          'cid': data['cid'],
          'vx': data['vx'],
          'vy': data['vy']
        });
        break;
      case 'settled':
        net?.send(<String, dynamic>{
          'a': 'settled',
          'snap': data['snap'],
          'mt': data['mt']
        });
        break;
      case 'goal':
        net?.send(<String, dynamic>{
          'a': 'goal',
          'team': data['team'],
          'nogoal': data['nogoal']
        });
        break;
      case 'timeout':
        net?.send(<String, dynamic>{'a': 'timeout', 'seat': data['team']});
        break;
      case 'turn':
        if (net != null) net.turnSeat = data['turn'] as int;
        break;
      case 'end':
        final List<int> local = (data['local'] as List<dynamic>).cast<int>();
        _end(local);
        break;
    }
  }

  // ------------------------------------------------------------------ start / end
  void _startOffline() {
    final math.Random r = math.Random(launch.seed);
    final List<BmTeam> clubs = kBmTeams
        .where((BmTeam t) => t.cat == 'club' && t.id != my.team)
        .toList();
    final String opp = clubs[r.nextInt(clubs.length)].id;
    final bool bot = launch.vsBot;
    final int lvl = switch (launch.difficulty) {
      BotDifficulty.easy => 0,
      BotDifficulty.normal => 1,
      BotDifficulty.hard => 2
    };
    final String me =
        launch.playerName.isEmpty ? 'Player 1' : launch.playerName;
    _begin(BmConfig(
      mode: bot ? 'bot' : 'local',
      teams: <String>[my.team, opp],
      form: <int>[my.form, r.nextInt(6)],
      names: bot
          ? <String>[
              me,
              'Bot ${<String>['Rookie', 'Pro', 'Legend'][lvl]}'
            ]
          : <String>['Player 1', 'Player 2'],
      field: my.field,
      ball: my.ball,
      limit: 0,
      matchTime: kBmMatchSeconds,
      turnTime: 0,
      ai: bot,
      aiLvl: lvl,
    ));
  }

  void _maybeStartOnline({bool quiet = false}) {
    if (stage == 'match') return;
    final _Setup? h = _setups[0], g = _setups[1];
    if (h == null || g == null) return;
    final NetLink net = launch.net!;
    _begin(
        BmConfig(
          mode: 'online',
          teams: <String>[h.team, g.team],
          form: <int>[h.form, g.form],
          names: <String>[
            for (int s = 0; s < 2; s++) s < net.names.length ? net.names[s] : ''
          ],
          field: h.field,
          ball: h.ball,
          limit: 0,
          matchTime: kBmMatchSeconds,
          turnTime: kBmOnlineTurnSeconds,
          mirror: mySeat == 1,
          first: 0,
        ),
        quiet: quiet);
  }

  void _begin(BmConfig c, {bool quiet = false}) {
    cfg = c;
    e.startMatch(c);
    if (quiet) e.menuOpen = false;
    stage = 'match';
    _finishIn = -1;
    _loadMatchImages(c);
    unawaited(audio.music(false));
    unawaited(audio.crowd(true));
    if (mounted) setState(() {});
  }

  Future<ui.Image?> _img(String path, {int? w}) async {
    try {
      final ByteData data = await DefaultAssetBundle.of(context).load(path);
      final ui.Codec codec = await ui
          .instantiateImageCodec(data.buffer.asUint8List(), targetWidth: w);
      final ui.FrameInfo f = await codec.getNextFrame();
      codec.dispose();
      return f.image;
    } catch (err) {
      debugPrint('bermuda image $path: $err');
      return null;
    }
  }

  Future<void> _loadMatchImages(BmConfig c) async {
    final BmFieldS f = kBmFields[c.field];
    final List<ui.Image?> r = await Future.wait(<Future<ui.Image?>>[
      _img('${_a}fields/${f.id}.webp'),
      _img('${_a}goals/${f.gs}.webp'),
      _img('${_a}balls/b${c.ball}.webp'),
      _img(bmTeam(c.teams[e.ct(0)]).asset, w: 192),
      _img(bmTeam(c.teams[e.ct(1)]).asset, w: 192),
    ]);
    if (!mounted || _disposed) {
      for (final ui.Image? i in r) {
        i?.dispose();
      }
      return;
    }
    im.dispose();
    im.field = r[0];
    im.goal = r[1];
    im.ball = r[2];
    im.team[0] = r[3];
    im.team[1] = r[4];
  }

  void _end(List<int> local) {
    if (_finishIn > 0 || _reported) return;
    _finishIn = 1.6;
    unawaited(audio.crowd(false));
  }

  void _report({bool forfeit = false}) {
    if (_reported) return;
    _reported = true;
    final List<int> sc = e.score; // local: [me, opponent]
    final bool won = !forfeit && sc[0] > sc[1];
    final bool draw = !forfeit && sc[0] == sc[1];
    final int winnerSeat = won ? mySeat : 1 - mySeat;
    final List<int> global = <int>[sc[e.ct(0)], sc[e.ct(1)]];
    launch.onFinish(GameResult(
      outcome:
          draw ? GameOutcome.draw : (won ? GameOutcome.win : GameOutcome.loss),
      score: sc[0],
      opponentScore: sc[1],
      winnerSeats: draw ? <int>[] : <int>[winnerSeat],
      scores: global,
      tournamentMatchId: launch.tournamentMatchId,
      summaryFa:
          'نتیجه‌ی فوتبال: ${sc[0]} - ${sc[1]}${forfeit ? ' (انصراف)' : ''}',
      summaryEn:
          'Football final: ${sc[0]} - ${sc[1]}${forfeit ? ' (forfeit)' : ''}',
    ));
  }

  // ------------------------------------------------------------------ online
  Future<void> _waitPlayable() async {
    if (stage == 'match' && e.phase != 'goal') return;
    final Completer<void> c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  Future<void> _onNet(NetMove m) async {
    if (_disposed) return;
    if (m.kind == 'replayDone') {
      _netReady = true;
      final Map<String, dynamic>? ps = _pendingShot;
      _pendingShot = null;
      if (stage == 'match') {
        e.menuOpen = false;
        if (ps != null && e.phase == 'aim') {
          if (_pendingShotSeat == mySeat) {
            // our own shot was logged but never settled: run it locally so we post the snapshot
            final int cid = (ps['cid'] as num).toInt();
            for (final BmBody b in e.bodies) {
              if (b.cid == cid) {
                final int sg = e.mirror ? -1 : 1;
                e.launch(b, (ps['vx'] as num).toDouble() * sg,
                    (ps['vy'] as num).toDouble() * sg, false);
              }
            }
          } else {
            e.remoteShot(ps);
          }
        }
      } else if (_setups.containsKey(mySeat)) {
        stage = 'waiting';
      }
      if (mounted) setState(() {});
      return;
    }
    if (m.kind != 'move' && m.kind != 'timeout') return;
    final Map<String, dynamic> d = m.data;
    final String a = '${d['a']}';
    if (a == 'setup') {
      final _Setup? s = _Setup.fromJson(d);
      if (s != null && !_setups.containsKey(m.seat)) _setups[m.seat] = s;
      _maybeStartOnline(quiet: m.replay);
      if (mounted) setState(() {});
      return;
    }
    if (stage != 'match') return;
    if (m.replay) {
      _replayMove(m.seat, a, d);
      return;
    }
    await _waitPlayable();
    if (_disposed) return;
    switch (a) {
      case 'shot':
        e.remoteShot(d);
        break;
      case 'settled':
        e.remoteSettled(d);
        break;
      case 'goal':
        e.remoteGoal(d);
        break;
      case 'timeout':
        e.remoteTimeout(d);
        break;
    }
  }

  /// Fast-forwards the logged match after a (re)join without animating shots.
  void _replayMove(int seat, String a, Map<String, dynamic> d) {
    switch (a) {
      case 'shot':
        _pendingShot = d;
        _pendingShotSeat = seat;
        break;
      case 'settled':
        _pendingShot = null;
        final Map<String, dynamic>? snap =
            (d['snap'] as Map?)?.cast<String, dynamic>();
        e.applySnapshot(snap);
        final List<dynamic>? sc = snap?['sc'] as List<dynamic>?;
        if (sc != null && sc.length == 2) {
          e.score[e.ct(0)] = (sc[0] as num).toInt();
          e.score[e.ct(1)] = (sc[1] as num).toInt();
        }
        final num? tn = snap?['tn'] as num?;
        if (tn != null) e.turn = e.ct(tn.toInt());
        e.phase = 'aim';
        e.remote = false;
        e.shots = 1;
        final num? mt = d['mt'] as num?;
        if (mt != null) e.mleft = mt.toDouble();
        break;
      case 'goal':
        _pendingShot = null;
        final int t = e.ct((d['team'] as num).toInt());
        final bool ng = d['nogoal'] == true;
        if (!ng) e.score[t]++;
        e.reset(ng ? e.turn : 1 - t);
        break;
      case 'timeout':
        final num? s = d['seat'] as num?;
        if (s == null || e.ct(e.turn) == s.toInt()) {
          e.turn = 1 - e.turn;
          e.phase = 'aim';
        }
        break;
    }
  }

  void _sendSetup() {
    final NetLink? net = launch.net;
    if (net == null) return;
    _setups[mySeat] = _Setup(my.team, my.form, my.field, my.ball);
    net.send(_setups[mySeat]!.toJson());
    stage = 'waiting';
    _maybeStartOnline();
    setState(() {});
  }

  // ------------------------------------------------------------------ pause (flow.js pause())
  Future<void> _pause() async {
    if (_reported || _finishIn > 0) return;
    final bool isOnline = online, bot = launch.vsBot;
    if (!isOnline) e.menuOpen = true;
    _paused = true;
    unawaited(audio
        .crowd(false)); // game.js crowdSync: no crowd while the menu is open
    final String? act = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => _BmDialog(
        title: launch.tx('توقف', 'Paused'),
        actions: <(String, String, IconData)>[
          (
            'continue',
            launch.tx('ادامه', 'Continue'),
            Icons.play_arrow_rounded
          ),
          if (!isOnline && !bot)
            (
              'restart',
              launch.tx('شروع دوباره', 'Restart'),
              Icons.refresh_rounded
            ),
          (
            'sound',
            launch.tx('صدا روشن/خاموش', 'Sound on/off'),
            Icons.volume_up_rounded
          ),
          (
            'ann',
            audio.announcer
                ? launch.tx('گزارشگر گل: روشن', 'Goal announcer: on')
                : launch.tx('گزارشگر گل: خاموش', 'Goal announcer: off'),
            Icons.record_voice_over_rounded
          ),
          ('leave', launch.tx('خروج', 'Leave'), Icons.logout_rounded),
        ],
      ),
    );
    _paused = false;
    if (!mounted) return;
    if (!isOnline) e.menuOpen = false;
    switch (act) {
      case 'restart':
        e.restart(0);
        break;
      case 'sound':
        audio.setMuted(!audio.muted);
        break;
      case 'ann':
        audio.announcer = !audio.announcer;
        unawaited(SharedPreferences.getInstance()
            .then((SharedPreferences p) => p.setBool('bm.ann', audio.announcer))
            .then((_) {}, onError: (Object _) {}));
        break;
      case 'leave':
        if (isOnline || bot) {
          // flow.js: leaving counts as a loss
          _report(forfeit: true);
        } else {
          unawaited(Navigator.of(context).maybePop());
        }
        break;
    }
    _crowdSync();
  }

  /// game.js crowdSync(): crowd ambience only while a match runs, the menu is closed and the app is visible.
  void _crowdSync() {
    if (_disposed || !mounted) return;
    final bool want = stage == 'match' &&
        !_paused &&
        !_reported &&
        _finishIn <= 0 &&
        _visible;
    unawaited(audio.crowd(want));
  }

  bool _visible = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // game.js musicSync/crowdSync stop on document.hidden
    _visible = state == AppLifecycleState.resumed;
    if (!_visible) unawaited(audio.music(false));
    _crowdSync();
    if (_visible && stage != 'match' && launch.soundOn && !_paused)
      unawaited(audio.music(true));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _goalAnim.dispose();
    _inbox?.close();
    for (final Completer<void> c in _waiters) {
      if (!c.isCompleted) c.complete();
    }
    audio.dispose();
    im.dispose();
    _frame.dispose();
    e.stop();
    super.dispose();
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    if (stage != 'match') {
      if (launch.soundOn && !_paused && _visible) unawaited(audio.music(true));
      return _setupScreen(context);
    }
    final double dpr = math.min(MediaQuery.devicePixelRatioOf(context), 1.75);
    final bool fancy = launch.fancyEffects && !launch.reducedMotion;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF03060D),
        child: Stack(children: <Widget>[
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (PointerDownEvent ev) {
                final Offset w = view.toWorld(ev.localPosition);
                e.pointerDown(w.dx, w.dy);
              },
              onPointerMove: (PointerMoveEvent ev) {
                final Offset w = view.toWorld(ev.localPosition);
                e.pointerMove(w.dx, w.dy);
              },
              onPointerUp: (_) => e.pointerUp(),
              onPointerCancel: (_) => e.pointerCancel(),
              child: CustomPaint(
                painter: BmPainter(e, im, view, () => _nowMs, dpr, fancy,
                    repaint: _frame),
                size: Size.infinite,
              ),
            ),
          ),
          // vignette (#vig)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: .95,
                    colors: <Color>[
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0x94050316)
                    ],
                    stops: <double>[0, .52, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
              left: 0, right: 0, top: 0, child: SafeArea(child: _scoreboard())),
          Positioned.fill(child: IgnorePointer(child: _overlays())),
          Positioned(
            left: 12,
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
            child: _RoundBtn(icon: Icons.pause_rounded, onTap: _pause),
          ),
        ]),
      ),
    );
  }

  Widget _overlays() {
    return ValueListenableBuilder<int>(
      valueListenable: _frame,
      builder: (BuildContext context, int _, Widget? __) {
        final Size sz = MediaQuery.sizeOf(context);
        return Stack(children: <Widget>[
          if (_toastT > 0)
            Positioned(
              left: 18,
              right: 18,
              top: sz.height * .30,
              child: Center(child: _ToastPill(text: _toast, big: _toastBig)),
            ),
          AnimatedBuilder(
            animation: _goalAnim,
            builder: (BuildContext context, Widget? child) {
              final double t = _goalAnim.value;
              if (t <= 0 || t >= 1 || !_goalAnim.isAnimating) {
                return const SizedBox.shrink();
              }
              // Keep the original goal-pop motion; only the surrounding HUD is restyled.
              double sc, op = 1, rot = 0, ty = 0;
              if (t < .14) {
                final double k = t / .14;
                sc = .25 + (1.2 - .25) * k;
                op = k;
                rot = -5 + 6 * k;
              } else if (t < .24) {
                final double k = (t - .14) / .10;
                sc = 1.2 + (.97 - 1.2) * k;
                rot = 1 - k;
              } else if (t < .32) {
                final double k = (t - .24) / .08;
                sc = .97 + (1.03 - .97) * k;
              } else if (t < .78) {
                sc = 1.03;
              } else {
                final double k = (t - .78) / .22;
                sc = 1.03 + (1.12 - 1.03) * k;
                op = 1 - k;
                ty = -16 * k;
              }
              return Positioned(
                left: 0,
                right: 0,
                top: sz.height * .22 + ty,
                child: Center(
                  child: Opacity(
                    opacity: op.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: rot * math.pi / 180,
                      child: Transform.scale(scale: sc, child: child),
                    ),
                  ),
                ),
              );
            },
            child: Image.asset('${_a}ui/goal.webp',
                width: math.min(sz.width * .82, 460)),
          ),
        ]);
      },
    );
  }

  Widget _scoreboard() {
    return ValueListenableBuilder<int>(
      valueListenable: _frame,
      builder: (BuildContext context, int _, Widget? __) {
        final NxThemeColors visual = NxThemeColors.of(context);
        final double screenWidth = MediaQuery.sizeOf(context).width;
        final double sw = math.max(0, math.min(screenWidth - 76, 500));
        final bool aim = e.phase == 'aim';
        String clock = '';
        bool low = false;
        if (e.mt > 0) {
          if (e.sd) {
            clock = 'GOLDEN';
          } else {
            final int t = math.max(0, e.mleft.ceil());
            clock = '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
            low = t <= 30;
          }
        }
        final int tl = math.max(0, e.tleft.ceil());

        Widget team(int t) {
          final bool on = aim && e.turn == t;
          final Color accent = t == 0 ? visual.accent : visual.accentSecondary;
          final Widget logo = Container(
            width: 30,
            height: 30,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: visual.background.withValues(alpha: .78),
              border: Border.all(
                  color: on ? accent : visual.border.withValues(alpha: .56),
                  width: on ? 1.6 : 1),
              boxShadow: on
                  ? <BoxShadow>[
                      BoxShadow(
                          color: accent.withValues(alpha: .42), blurRadius: 12)
                    ]
                  : null,
            ),
            child: ClipOval(
                child: Image.asset(bmTeam(e.sel[e.ct(t)]).asset,
                    cacheWidth: 96, fit: BoxFit.contain)),
          );
          final Widget identity = Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  t == 0 ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (on && t == 0) _TurnDot(color: accent),
                    if (on && t == 0) const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        e.nm(t),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: t == 0 ? TextAlign.left : TextAlign.right,
                        style: TextStyle(
                            color: visual.text,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (on && t == 1) const SizedBox(width: 4),
                    if (on && t == 1) _TurnDot(color: accent),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  '${e.score[t]}',
                  style: TextStyle(
                    color: on ? accent : visual.text,
                    fontSize: 27,
                    height: .98,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const <ui.FontFeature>[
                      ui.FontFeature.tabularFigures()
                    ],
                  ),
                ),
              ],
            ),
          );
          final List<Widget> children = t == 0
              ? <Widget>[logo, const SizedBox(width: 6), identity]
              : <Widget>[identity, const SizedBox(width: 6), logo];
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
              decoration: BoxDecoration(
                color: on ? accent.withValues(alpha: .13) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: on
                        ? accent.withValues(alpha: .72)
                        : Colors.transparent),
              ),
              child: Row(children: children),
            ),
          );
        }

        return Center(
          child: SizedBox(
            width: sw,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: visual.surface.withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: visual.border.withValues(alpha: .78)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                          color: Colors.black.withValues(alpha: .34),
                          blurRadius: 18,
                          offset: const Offset(0, 8)),
                      BoxShadow(
                          color: visual.accent.withValues(alpha: .10),
                          blurRadius: 20),
                    ],
                  ),
                  child: Row(
                    children: <Widget>[
                      team(0),
                      Container(
                        width: 67,
                        padding: const EdgeInsets.symmetric(
                            vertical: 7, horizontal: 3),
                        decoration: BoxDecoration(
                          color: visual.background.withValues(alpha: .76),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: (e.sd
                                      ? visual.accent
                                      : (low
                                          ? const Color(0xFFFF697A)
                                          : visual.border))
                                  .withValues(alpha: .72)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.timer_outlined,
                                size: 13,
                                color: e.sd
                                    ? visual.accent
                                    : (low
                                        ? const Color(0xFFFF8794)
                                        : visual.muted)),
                            const SizedBox(height: 1),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                clock,
                                maxLines: 1,
                                style: TextStyle(
                                  color: e.sd
                                      ? visual.accent
                                      : (low
                                          ? const Color(0xFFFF8794)
                                          : visual.text),
                                  fontSize: e.sd ? 10 : 16,
                                  height: 1.05,
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: const <ui.FontFeature>[
                                    ui.FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                            if (!e.sd)
                              Text(
                                launch.tx('بازی', 'MATCH'),
                                style: TextStyle(
                                    color: visual.muted,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1),
                              ),
                          ],
                        ),
                      ),
                      team(1),
                    ],
                  ),
                ),
                if (aim && e.tt > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: visual.surfaceRaised.withValues(alpha: .94),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: (e.tleft < 5
                                    ? const Color(0xFFFF697A)
                                    : visual.border)
                                .withValues(alpha: .8)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _TurnDot(
                                color: e.tleft < 5
                                    ? const Color(0xFFFF697A)
                                    : visual.accent),
                            const SizedBox(width: 5),
                            Text(
                              '${launch.tx('نوبت', 'TURN')} ${e.turn + 1}',
                              style: TextStyle(
                                  color: visual.muted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .5),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${tl}s',
                              style: TextStyle(
                                color: e.tleft < 5
                                    ? const Color(0xFFFF8794)
                                    : visual.text,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                fontFeatures: const <ui.FontFeature>[
                                  ui.FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------ setup screen
  Widget _setupScreen(BuildContext context) {
    final bool waiting = stage == 'waiting' || (online && !_netReady);
    final bool chooseArena = !online || isHostSeat;
    final List<BmTeam> teams =
        kBmTeams.where((BmTeam t) => t.cat == kBmCats[_cat][0]).toList();
    final NxThemeColors visual = NxThemeColors.of(context);

    Widget sectionTitle(String title, String hint, IconData icon) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: visual.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: visual.accent.withValues(alpha: .34)),
                ),
                child: Icon(icon, size: 17, color: visual.accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: TextStyle(
                            color: visual.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .4)),
                    const SizedBox(height: 1),
                    Text(hint,
                        style: TextStyle(color: visual.muted, fontSize: 10.5)),
                  ],
                ),
              ),
            ],
          ),
        );

    Widget section(Widget child) => Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: visual.surface.withValues(alpha: .86),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: visual.border.withValues(alpha: .48)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                  color: Colors.black.withValues(alpha: .12),
                  blurRadius: 14,
                  offset: const Offset(0, 5))
            ],
          ),
          child: child,
        );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              visual.background,
              visual.backgroundMid,
              visual.background
            ],
          ),
        ),
        child: SafeArea(
          child: AbsorbPointer(
            absorbing: waiting,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 17, 16, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        visual.surfaceRaised,
                        visual.surface.withValues(alpha: .82)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border:
                        Border.all(color: visual.accent.withValues(alpha: .38)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                          color: visual.accent.withValues(alpha: .09),
                          blurRadius: 26,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.sports_soccer_rounded,
                              size: 15, color: visual.accent),
                          const SizedBox(width: 6),
                          Text('NEXORA  /  MATCH LOBBY',
                              style: TextStyle(
                                  color: visual.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.8)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        launch.tx('فوتبال انگشتی', 'FINGER SOCCER'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: visual.text,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        online
                            ? launch.tx('تیم و ترکیبت را انتخاب کن',
                                'Choose your side and formation')
                            : launch.tx('۵ دقیقه · گل طلایی در تساوی',
                                'Five minutes · golden goal if tied'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: visual.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                section(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      sectionTitle(
                          launch.tx('تیم', 'YOUR TEAM'),
                          launch.tx('یک نشان را انتخاب کن', 'Choose your club'),
                          Icons.shield_outlined),
                      SizedBox(
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: <Widget>[
                            for (int i = 0; i < kBmCats.length; i++)
                              _Chip(
                                label: kBmCats[i][1] as String,
                                on: _cat == i,
                                onTap: () => setState(() {
                                  _cat = i;
                                  audio.sfx('ui');
                                }),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 106,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: teams.length,
                          itemBuilder: (BuildContext c, int i) {
                            final BmTeam t = teams[i];
                            final bool on = t.id == my.team;
                            return GestureDetector(
                              onTap: () => setState(() {
                                my.team = t.id;
                                audio.sfx('ui');
                                unawaited(_savePrefs());
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 82,
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(15),
                                  color: on
                                      ? visual.accent.withValues(alpha: .14)
                                      : visual.background
                                          .withValues(alpha: .52),
                                  border: Border.all(
                                      color: on
                                          ? visual.accent
                                          : visual.border
                                              .withValues(alpha: .42),
                                      width: on ? 1.6 : 1),
                                  boxShadow: on
                                      ? <BoxShadow>[
                                          BoxShadow(
                                              color: visual.accent
                                                  .withValues(alpha: .12),
                                              blurRadius: 12)
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  children: <Widget>[
                                    Expanded(
                                        child: Image.asset(t.asset,
                                            cacheWidth: 128)),
                                    const SizedBox(height: 3),
                                    Text(t.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color:
                                                on ? visual.text : visual.muted,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800)),
                                    if (on)
                                      Container(
                                          margin: const EdgeInsets.only(top: 3),
                                          width: 18,
                                          height: 2,
                                          decoration: BoxDecoration(
                                              color: visual.accent,
                                              borderRadius:
                                                  BorderRadius.circular(4))),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                section(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      sectionTitle(
                          launch.tx('ترکیب', 'FORMATION'),
                          launch.tx(
                              'آرایش مهره‌های تیم', 'Set your team shape'),
                          Icons.account_tree_outlined),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: <Widget>[
                          for (int i = 0; i < kBmForms.length; i++)
                            _Chip(
                              label: '${kBmForms[i][0]} · ${kBmForms[i][1]}',
                              on: my.form == i,
                              onTap: () => setState(() {
                                my.form = i;
                                audio.sfx('ui');
                                unawaited(_savePrefs());
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (chooseArena)
                  section(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        sectionTitle(
                            launch.tx('زمین', 'ARENA'),
                            launch.tx('محل مسابقه را برگزین',
                                'Choose the match venue'),
                            Icons.stadium_outlined),
                        SizedBox(
                          height: 146,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: kBmFields.length,
                            itemBuilder: (BuildContext c, int i) {
                              final bool on = my.field == i;
                              return GestureDetector(
                                onTap: () => setState(() {
                                  my.field = i;
                                  audio.sfx('ui');
                                  unawaited(_savePrefs());
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: 116,
                                  margin: const EdgeInsets.only(right: 9),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                        color: on
                                            ? visual.accent
                                            : visual.border
                                                .withValues(alpha: .48),
                                        width: on ? 1.8 : 1),
                                    boxShadow: on
                                        ? <BoxShadow>[
                                            BoxShadow(
                                                color: visual.accent
                                                    .withValues(alpha: .15),
                                                blurRadius: 12)
                                          ]
                                        : null,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: <Widget>[
                                      Image.asset(
                                          '${_a}thumbs/${kBmFields[i].id}.webp',
                                          fit: BoxFit.cover,
                                          cacheWidth: 220),
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 6),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: <Color>[
                                                  Colors.transparent,
                                                  Colors.black
                                                      .withValues(alpha: .88)
                                                ]),
                                          ),
                                          child: Text(kBmFields[i].name,
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800)),
                                        ),
                                      ),
                                      if (on)
                                        Positioned(
                                          right: 6,
                                          top: 6,
                                          child: Icon(
                                              Icons.check_circle_rounded,
                                              color: visual.accent,
                                              size: 18),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 13),
                        sectionTitle(
                            launch.tx('توپ', 'BALL'),
                            launch.tx('طرح مسابقه', 'Match ball design'),
                            Icons.sports_soccer_outlined),
                        SizedBox(
                          height: 98,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: NB,
                            itemBuilder: (BuildContext c, int i) {
                              final bool on = my.ball == i;
                              return GestureDetector(
                                onTap: () => setState(() {
                                  my.ball = i;
                                  audio.sfx('ui');
                                  unawaited(_savePrefs());
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: 78,
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: on
                                        ? visual.accent.withValues(alpha: .12)
                                        : visual.background
                                            .withValues(alpha: .48),
                                    border: Border.all(
                                        color: on
                                            ? visual.accent
                                            : visual.border
                                                .withValues(alpha: .42),
                                        width: on ? 1.6 : 1),
                                  ),
                                  child: Column(
                                    children: <Widget>[
                                      Expanded(
                                          child: Image.asset(
                                              '${_a}balls/b$i.webp',
                                              cacheWidth: 112)),
                                      Text(kBmBallN[i],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: on
                                                  ? visual.text
                                                  : visual.muted,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  section(
                    Row(
                      children: <Widget>[
                        Icon(Icons.info_outline_rounded,
                            color: visual.accent, size: 18),
                        const SizedBox(width: 9),
                        Expanded(
                            child: Text(
                                launch.tx('زمین و توپ را میزبان انتخاب می‌کند',
                                    'The host picks the field and the ball'),
                                style: TextStyle(
                                    color: visual.muted,
                                    fontSize: 12,
                                    height: 1.35))),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: waiting
                      ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                              color: visual.surface,
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(
                                  color: visual.border.withValues(alpha: .5))),
                          child: Column(
                            children: <Widget>[
                              SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: visual.accent)),
                              const SizedBox(height: 9),
                              Text(
                                  launch.tx('در انتظار حریف…',
                                      'Waiting for the opponent…'),
                                  style: TextStyle(
                                      color: visual.text,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        )
                      : SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: visual.accent,
                              foregroundColor: visual.background,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(17)),
                              elevation: 5,
                              shadowColor: visual.accent.withValues(alpha: .30),
                              textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: .5),
                            ),
                            onPressed: () {
                              audio.sfx('ui');
                              unawaited(_savePrefs());
                              if (online) {
                                _sendSetup();
                              } else {
                                _startOffline();
                              }
                            },
                            icon:
                                const Icon(Icons.play_arrow_rounded, size: 24),
                            label: Text(online
                                ? launch.tx('آماده‌ام', 'READY')
                                : launch.tx('شروع بازی', 'START MATCH')),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: on
                ? visual.accent
                : visual.surfaceRaised.withValues(alpha: .84),
            border: Border.all(
                color:
                    on ? visual.accent : visual.border.withValues(alpha: .55)),
            boxShadow: on
                ? <BoxShadow>[
                    BoxShadow(
                        color: visual.accent.withValues(alpha: .18),
                        blurRadius: 10)
                  ]
                : null,
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? visual.background : visual.text,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

class _TurnDot extends StatelessWidget {
  const _TurnDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(color: color.withValues(alpha: .62), blurRadius: 6)
          ]),
    );
  }
}

class _ToastPill extends StatelessWidget {
  const _ToastPill({required this.text, required this.big});
  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 36),
      padding: EdgeInsets.symmetric(
          horizontal: big ? 26 : 20, vertical: big ? 12 : 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: big
            ? LinearGradient(
                colors: <Color>[visual.accent, visual.accentSecondary])
            : null,
        color: big ? null : visual.surfaceRaised.withValues(alpha: .97),
        border:
            Border.all(color: visual.accent.withValues(alpha: .82), width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: visual.accent.withValues(alpha: .24),
              blurRadius: 26,
              offset: const Offset(0, 6))
        ],
      ),
      child: Text(
        text.toUpperCase(),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: big ? visual.background : visual.text,
            fontSize: big ? 30 : 15,
            fontWeight: FontWeight.w900,
            letterSpacing: .8),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Material(
      color: visual.surfaceRaised.withValues(alpha: .96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: visual.border.withValues(alpha: .72)),
      ),
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: .38),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: visual.accent, size: 23),
        ),
      ),
    );
  }
}

class _BmDialog extends StatelessWidget {
  const _BmDialog({required this.title, required this.actions});
  final String title;
  final List<(String, String, IconData)> actions;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Dialog(
      backgroundColor: visual.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: visual.border.withValues(alpha: .75)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: visual.accent.withValues(alpha: .12),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: visual.accent.withValues(alpha: .42))),
              child: Icon(Icons.pause_rounded, color: visual.accent, size: 24),
            ),
            const SizedBox(height: 9),
            Text(title,
                style: TextStyle(
                    color: visual.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            for (final (String, String, IconData) a in actions)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: a.$1 == 'continue'
                          ? visual.accent
                          : a.$1 == 'leave'
                              ? const Color(0xFFD9364A)
                              : visual.backgroundMid,
                      foregroundColor:
                          a.$1 == 'continue' ? visual.background : visual.text,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.of(context).pop(a.$1),
                    icon: Icon(a.$3),
                    label: Text(a.$2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
