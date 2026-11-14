// Port of src/screens/Match.tsx: offline match (vs bot or local 2P) on the Flame host, with HUD, goal banner,
// pause menu, coach tips and the optional FPS/step debug overlay.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../game/engine.dart';
import '../game/game.dart';
import '../game/render.dart';
import '../oracle/oracle.dart';
import '../ui/kit.dart';

class MatchResult {
  final List<int> score;
  final List<Team> teams;
  final bool ai;
  final int aiLvl;
  MatchResult(this.score, this.teams, this.ai, this.aiLvl);
}

ui.FragmentProgram? _ballProgram;
Future<ui.FragmentShader?> ballShader() async {
  try {
    _ballProgram ??= await ui.FragmentProgram.fromAsset('shaders/ball.frag');
    return _ballProgram!.fragmentShader();
  } catch (_) {
    return null;
  }
}

/// Load every image a match needs, decoded at the size it is drawn at.
Future<MatchImages> loadMatchImages(MatchCfg cfg, Team t0, Team t1) async {
  final f = kFields[cfg.field];
  final r = await Future.wait([
    loadImage(kFIELD_IMG[f.id]!, width: 1100),
    loadImage(ballImg(cfg.ball), width: 256),
    loadImage(teamImg(t0), width: 192),
    loadImage(teamImg(t1), width: 192),
    loadImage(kARROW_IMG['head_e']!),
    loadImage(kARROW_IMG['head_s']!),
    loadImage(kARROW_IMG['shaft_e']!),
    loadImage(kARROW_IMG['shaft_s']!),
  ]);
  return MatchImages(r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]);
}

class HudState {
  final int s0, s1, turn;
  final String clock;
  final double tl;
  final bool sudden;
  const HudState(this.s0, this.s1, this.turn, this.clock, this.tl, this.sudden);
  @override
  bool operator ==(Object o) => o is HudState && o.s0 == s0 && o.s1 == s1 && o.turn == turn && o.clock == clock && (o.tl - tl).abs() <= .02 && o.sudden == sudden;
  @override
  int get hashCode => Object.hash(s0, s1, turn, clock, sudden);
}

class BannerMsg {
  final String t, s;
  final Color c;
  final int id;
  BannerMsg(this.t, this.s, this.c) : id = DateTime.now().microsecondsSinceEpoch;
}

class MatchScreen extends StatefulWidget {
  final MatchCfg cfg;
  final List<Team> teams;
  final List<String> names;
  final void Function(MatchResult) onFinish;
  final VoidCallback onQuit;
  const MatchScreen({super.key, required this.cfg, required this.teams, required this.names, required this.onFinish, required this.onQuit});
  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  late final Engine eng = Engine(widget.cfg);
  late final MatchGame game = MatchGame(e: eng, onTick: _tick);
  final hud = ValueNotifier(const HudState(0, 0, 0, '', 1, false));
  final banner = ValueNotifier<BannerMsg?>(null);
  final debug = ValueNotifier('');
  bool paused = false, ended = false, loading = true;
  MatchImages? _im;
  int _shotTeam = -1, _misses = 0, _turnN = 0, _reminded = -1, _lastTip = 0;
  bool _touched = false;
  Size? _size;
  EdgeInsets _ins = EdgeInsets.zero;

  bool human(int t) => !(widget.cfg.ai && t == 1);

  @override
  void initState() {
    super.initState();
    Oracle.i.setScene('match');
    sfx(Snd.whistle);
    Sound.playLoop(Snd.crowd);
    Sound.scene(AudioScene.match);
    _load();
  }

  Future<void> _load() async {
    final im = await loadMatchImages(widget.cfg, widget.teams[0], widget.teams[1]);
    _im = im;
    await _buildRenderer();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _buildRenderer() async {
    final s = _size, im = _im;
    if (s == null || im == null) return;
    final v = computeView(eng, s.width, s.height, _ins.top + 86, _ins.bottom + 22);
    final r = MatchRenderer(eng, im, widget.cfg.ball, v, dpr: ui.PlatformDispatcher.instance.views.first.devicePixelRatio, hq: hq, ballShader: await ballShader());
    await r.prepare();
    game.r = r;
  }

  @override
  void dispose() {
    Sound.stopLoop(Snd.crowd);
    Oracle.i.setScene('ui');
    hud.dispose();
    banner.dispose();
    debug.dispose();
    super.dispose();
  }

  void _banner(String t, String s, Color c) => banner.value = BannerMsg(t, s, c);

  void _tick(double dt) {
    if (paused || loading) return;
    eng.update(dt);
    for (var i = 0; i < eng.eventCount; i++) {
      final ev = eng.event(i);
      switch (ev.t) {
        case EvType.hit:
          if (ev.ball) _touched = true;
          sfx(ev.ball ? Snd.hitb : Snd.hitp, ev.power);
          if (ev.power > .35) buzz(ev.power > .7 ? 'medium' : 'light');
        case EvType.wall:
          sfx(Snd.wall, ev.power);
        case EvType.post:
          sfx(Snd.post, ev.power);
          buzz('medium');
        case EvType.shot:
          buzz();
          _shotTeam = ev.team;
          _touched = false;
        case EvType.turn:
          _turnN++;
          if (_shotTeam >= 0 && human(_shotTeam) && !_touched) {
            _misses++;
            final t = coachMiss(eng.lastPower, _misses);
            final now = DateTime.now().millisecondsSinceEpoch;
            if (t != null && now - _lastTip > 18000) {
              _lastTip = now;
              Oracle.i.coach(t, eng.lastPower > .9 ? 'focus' : 'idea');
            }
          }
          _shotTeam = -1;
        case EvType.goal:
          if (ev.nogoal) {
            _banner('گل مردود', 'با ضربه‌ی اول نمی‌شه گل زد', C.dim);
          } else {
            _touched = true;
            sfx(Snd.goal);
            sfx(Snd.roar);
            buzz('heavy');
            _banner('گل!', widget.names[ev.team], ev.team == 0 ? C.cyan : C.red);
            if (human(ev.team)) Oracle.i.react('goal');
          }
        case EvType.clock:
          _banner('گل طلایی', 'گل بعدی برنده‌ست', C.gold);
        case EvType.end:
          if (!ended) {
            ended = true;
            sfx(Snd.finalW);
            Sound.stopLoop(Snd.crowd);
            final sc = [ev.s0, ev.s1];
            Timer(const Duration(milliseconds: 900), () => widget.onFinish(MatchResult(sc, widget.teams, widget.cfg.ai, widget.cfg.aiLvl)));
          }
      }
    }
    eng.clearEvents();
    final cfg = widget.cfg;
    if (cfg.turnTime > 0 && eng.phase == Phase.aim && eng.tleft < 5 && eng.tleft > 0 && human(eng.turn) && _reminded != _turnN) {
      _reminded = _turnN;
      Oracle.i.coach('۵ ثانیه وقت داری! ⏱ یک ضربه بزن.', 'alert');
    }
    final m = eng.mleft.ceil().clamp(0, 99999);
    final clock = cfg.matchTime > 0 ? (eng.sudden ? 'گل طلایی' : '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}') : 'تا ${fa(cfg.limit)} گل';
    final tl = cfg.turnTime > 0 && eng.phase == Phase.aim ? (eng.tleft / cfg.turnTime).clamp(0.0, 1.0) : 1.0;
    final h = HudState(eng.score[0], eng.score[1], eng.turn, clock, tl, eng.sudden);
    if (h != hud.value) hud.value = h;
    if (Store.i.p.debugOverlay) {
      final s = 'FPS ${(1000 / game.frameMs).toStringAsFixed(0)} · frame ${game.frameMs.toStringAsFixed(1)}ms · step ${game.stepMs.toStringAsFixed(2)}ms';
      if (s != debug.value) debug.value = s;
    }
  }

  void _down(PointerDownEvent e) {
    final w = game.toWorld(e.localPosition);
    if (w != null && !paused && eng.pick(w.dx, w.dy)) buzz();
  }

  void _move(PointerMoveEvent e) {
    final w = game.toWorld(e.localPosition);
    if (w != null) eng.move(w.dx, w.dy);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ins = MediaQuery.paddingOf(context);
    if (_size != size || _ins != ins) {
      _size = size;
      _ins = ins;
      if (_im != null) _buildRenderer();
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) setState(() => paused = true);
      },
      child: Scaffold(
        backgroundColor: const Color(0xff02040c),
        body: Stack(children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: (_) => eng.release(),
              onPointerCancel: (_) => eng.cancel(),
              child: RepaintBoundary(child: GameWidget(game: game)),
            ),
          ),
          if (loading) const Center(child: Spinner(size: 40)),
          Positioned(
            top: ins.top + 8,
            left: 10,
            right: 10,
            child: ValueListenableBuilder<HudState>(
              valueListenable: hud,
              builder: (_, h, __) => Column(children: [
                Row(children: [
                  Press(
                    onTap: () => setState(() => paused = true),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: const Color(0xd9080c22), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
                      child: tTitle('II', size: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Panel(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      accent: h.turn == 0 ? C.cyan : C.red,
                      child: Row(children: [
                        Expanded(child: MatchSide(team: widget.teams[0], name: widget.names[0], on: h.turn == 0, color: C.cyan, sub: 'نوبت توئه')),
                        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Row(children: [tTitle('${h.s0}', size: 26), tTitle(' : ', size: 26, color: C.dim), tTitle('${h.s1}', size: 26)]),
                          T(h.clock, size: 9, family: F.head, weight: 700, spacing: 2, color: h.sudden ? C.gold : C.dim),
                        ]),
                        Expanded(child: MatchSide(team: widget.teams[1], name: widget.names[1], on: h.turn == 1, color: C.red, right: true, sub: 'نوبت توئه')),
                      ]),
                    ),
                  ),
                ]),
                if (widget.cfg.turnTime > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 50, top: 8),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(color: const Color(0x14ffffff), borderRadius: BorderRadius.circular(3)),
                      child: FractionallySizedBox(
                        alignment: h.turn == 0 ? Alignment.centerLeft : Alignment.centerRight,
                        widthFactor: h.tl,
                        child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), gradient: LinearGradient(colors: h.turn == 0 ? const [C.cyan, C.blue] : const [C.red, C.orange]))),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          GoalBanner(banner: banner),
          if (Store.i.p.debugOverlay) DebugOverlay(text: debug),
          if (paused)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xb302040e),
                child: Center(
                  child: SizedBox(
                    width: size.width * .82,
                    child: Panel(
                      glowOn: true,
                      padding: const EdgeInsets.all(22),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        tTitle('توقف', size: 24, align: TextAlign.center),
                        const SizedBox(height: 18),
                        Btn('ادامه', onTap: () => setState(() => paused = false)),
                        const SizedBox(height: 12),
                        Btn('شروع دوباره', small: true, colors: G.dark, onTap: () {
                          eng.score[0] = 0;
                          eng.score[1] = 0;
                          eng.mleft = widget.cfg.matchTime;
                          eng.sudden = false;
                          eng.reset(0);
                          setState(() => paused = false);
                        }),
                        const SizedBox(height: 12),
                        Btn('خروج', colors: G.red, onTap: () {
                          Sound.stopLoop(Snd.crowd);
                          widget.onQuit();
                        }),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class MatchSide extends StatelessWidget {
  final Team team;
  final String name;
  final bool on, right;
  final Color color;
  final String? sub;
  const MatchSide({super.key, required this.team, required this.name, required this.on, required this.color, this.right = false, this.sub});
  @override
  Widget build(BuildContext context) => Row(textDirection: right ? TextDirection.rtl : TextDirection.ltr, children: [
        Disc(teamImg(team), size: 40, ring: on ? color : const Color(0x26ffffff), glowOn: on),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              tBold(name, size: 12, lines: 1, color: on ? Colors.white : C.dim),
              if (sub != null) T(on ? sub! : ' ', size: 8, family: F.head, weight: 700, color: color),
            ]),
          ),
        ),
      ]);
}

class GoalBanner extends StatelessWidget {
  final ValueNotifier<BannerMsg?> banner;
  const GoalBanner({super.key, required this.banner});
  @override
  Widget build(BuildContext context) => Positioned(
        left: 0,
        right: 0,
        top: MediaQuery.sizeOf(context).height * .38,
        child: IgnorePointer(
          child: ValueListenableBuilder<BannerMsg?>(
            valueListenable: banner,
            builder: (_, b, __) => b == null
                ? const SizedBox.shrink()
                : TweenAnimationBuilder<double>(
                    key: ValueKey(b.id),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 1700),
                    builder: (_, v, __) {
                      final sc = v < .25 ? Curves.elasticOut.transform(v / .25) * .7 + .3 : v < .82 ? 1.0 : 1 + (v - .82) / .18 * .25;
                      final op = v < .05 ? v / .05 : v < .82 ? 1.0 : 1 - (v - .82) / .18;
                      return Opacity(
                        opacity: op.clamp(0, 1),
                        child: Transform.scale(
                          scale: sc,
                          child: Column(children: [
                            tTitle(b.t, size: 54, shadows: [Shadow(color: b.c, blurRadius: 24)]),
                            if (b.s.isNotEmpty) T(b.s, size: 13, family: F.head, weight: 700, spacing: 3, color: b.c, lines: 1),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
      );
}

class DebugOverlay extends StatelessWidget {
  final ValueNotifier<String> text;
  const DebugOverlay({super.key, required this.text});
  @override
  Widget build(BuildContext context) => Positioned(
        left: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 8,
        child: IgnorePointer(
          child: ValueListenableBuilder<String>(
            valueListenable: text,
            builder: (_, s, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xcc000000), borderRadius: BorderRadius.circular(8)),
              child: Text(s, style: const TextStyle(fontFamily: F.num, fontSize: 11, color: C.green)),
            ),
          ),
        ),
      );
}
