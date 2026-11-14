// Online match screen: Flame host + NetMatch controller (netcode.dart) + HUD (turn owner, timer, voice,
// chat, ping), result reporting (report_match) and abort handling. Port of src/online/OnlineMatch.tsx.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:material_ui/material_ui.dart';

import '../core/sound.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../game/engine.dart';
import '../game/game.dart';
import '../game/render.dart';
import '../net/discs.dart';
import '../net/supabase.dart';
import '../oracle/oracle.dart';
import '../screens/match.dart';
import '../ui/kit.dart';
import '../ui/v4.dart';
import 'link.dart';
import 'netcode.dart';
import 'room_ui.dart';
import 'ui.dart';

class OnlineOutcome {
  final String matchId;
  final List<int> score;
  final int winner; // -1 draw
  final int? ratingDelta, myTeam;
  final List<Team> teams;
  final List<String> names;
  final bool reported, ranked;
  OnlineOutcome(this.matchId, this.score, this.winner, this.ratingDelta, this.myTeam, this.teams, this.names, this.reported, this.ranked);
}

MatchCfg cfgFromRoom(Rec room) {
  final s = room.rec('settings');
  final time = s.d('time').clamp(0, 99999).toDouble(), goals = s.i('goals', 3).clamp(1, 99);
  final turn = s.m['turn'] == 0 ? 0.0 : (s.d('turn', 15) < 5 ? 5.0 : s.d('turn', 15));
  return MatchCfg(
      field: s.i('field').clamp(0, kFields.length - 1),
      ball: s.i('ball').clamp(0, 35),
      forms: [0, 0],
      ai: false,
      aiLvl: 1,
      limit: time > 0 ? 99 : goals,
      matchTime: time,
      turnTime: turn,
      vip: [false, false],
      first: 0);
}

String ruleLabel(Rec s) => s.d('time') > 0 ? '${fa((s.d('time') / 60).round())} دقیقه' : 'تا ${fa(s.i('goals', 3))} گل';
String discOf(Rec p) => p.str('disc_id') ?? p.rec('profiles').str('equipped_disc') ?? p.rec('profiles').str('avatar') ?? 'club0';
List<Rec> teamOf(List<Rec> ps, int t) => ps.where((p) => p.s('role') == 'player' && p.i('team', -1) == t).toList()..sort((a, b) => a.i('slot').compareTo(b.i('slot')));

class _Port implements NetPort {
  final RoomLink link;
  _Port(this.link);
  @override
  String get me => link.me;
  @override
  void send(Map<String, dynamic> m) => link.sendGame(m);
  @override
  bool isOnline(String uid) => link.online.containsKey(uid);
  @override
  bool get allFlutter => link.allFlutter;
  @override
  int get peers => (link.online.length - 1).clamp(1, 99);
  @override
  List<Player> get players => [
        for (final p in link.players)
          if (p.s('role') == 'player' && (p.i('team', -1) == 0 || p.i('team', -1) == 1)) Player(p.s('user_id'), p.i('team'), p.i('slot'), discOf(p)),
      ];
  @override
  DiscStats statsFor(String disc) => Discs.i.stats(disc);
}

class OnlineMatchScreen extends StatefulWidget {
  final RoomLink link;
  final String matchId;
  final void Function(OnlineOutcome) onFinish;
  final void Function(String why) onExit;
  const OnlineMatchScreen({super.key, required this.link, required this.matchId, required this.onFinish, required this.onExit});
  @override
  State<OnlineMatchScreen> createState() => _OnlineMatchScreenState();
}

class _OnlineMatchScreenState extends State<OnlineMatchScreen> {
  RoomLink get link => widget.link;
  late final Rec room0 = link.room!;
  late final bool isHost = room0.s('host') == link.me;
  late final MatchCfg cfg = () {
    final c = cfgFromRoom(room0);
    Rec? cap(int t) => teamOf(link.players, t).firstOrNull;
    c.stats = [Discs.i.stats(cap(0) == null ? null : discOf(cap(0)!)), Discs.i.stats(cap(1) == null ? null : discOf(cap(1)!))];
    // v4: each team lines up in its captain's formation (advertised in presence 'f'; 0 when unknown/older build).
    // The host's snapshots stay authoritative for positions, so a peer that saw stale presence is corrected.
    int formOf(int t) {
      final uid = cap(t)?.s('user_id');
      final f = uid == null ? null : (uid == link.me ? Store.i.p.form : link.online[uid]?.form);
      return f != null && f >= 0 && f < kForms.length ? f : 0;
    }
    c.forms = [formOf(0), formOf(1)];
    return c;
  }();
  /// Physics profile of this match: host picks it at open (pickProfile), clients take it from the first
  /// host snapshot. eng/net/game are lazy and must not be touched before it is known (see netcode.dart header).
  String? pf;
  final List<(Map<String, dynamic>, String?)> _early = [];
  Timer? _pfWait;
  late final Engine eng = Engine(cfg..profile = pf ?? 'classic');
  late final NetMatch net = NetMatch(eng: eng, isHost: isHost, port: _Port(link), onEvent: _onEvent);
  late final MatchGame game = MatchGame(e: eng, onTick: _tick);
  late final int? myTeam = () {
    final meP = link.players.where((p) => p.s('user_id') == link.me).firstOrNull;
    return meP != null && meP.s('role') == 'player' && (meP.i('team', -1) == 0 || meP.i('team', -1) == 1) ? meP.i('team') : null;
  }();
  late final List<String> names = [_nm(teamOf(link.players, 0), 'آبی'), _nm(teamOf(link.players, 1), 'قرمز')];
  late final List<Team> teams = [teamOfAvatar(_cap(0)), teamOfAvatar(_cap(1))];
  late final bool ranked = room0.b('ranked');
  String? _cap(int t) {
    final c = teamOf(link.players, t).firstOrNull;
    return c == null ? null : discOf(c);
  }

  String _nm(List<Rec> t, String d) => (t.firstOrNull?.rec('profiles').str('username') ?? d) + (t.length > 1 ? ' +${fa(t.length - 1)}' : '');
  String nameOf(String? uid) => uid == null ? 'ربات' : link.players.where((p) => p.s('user_id') == uid).firstOrNull?.rec('profiles').s('username', '…') ?? '…';

  final hud = ValueNotifier(const HudState(0, 0, 0, '', 1, false));
  final ctrlN = ValueNotifier<String?>(null);
  final banner = ValueNotifier<BannerMsg?>(null);
  final debug = ValueNotifier('');
  String done = 'no'; // no | ended | finished | aborted
  int endAt = 0, t0 = DateTime.now().millisecondsSinceEpoch, tickAt = -1;
  bool loading = true, mineShot = false, touched = false;
  int misses = 0, lastTip = 0, turnN = 0, reminded = -1, sentAim = 0;
  double power = 0;
  MatchImages? _im;
  Size? _size;
  EdgeInsets _ins = EdgeInsets.zero;
  VoidCallback? _offGame, _offRe;
  int _lastMsgs = 0, _msgRate = 0, _lastRateAt = 0;

  @override
  void initState() {
    super.initState();
    Oracle.i.setScene('match');
    sfx(Snd.whistle);
    Sound.playLoop(Snd.crowd);
    Sound.scene(AudioScene.match);
    // v4 handshake guard: never share a match with a Flutter peer on another protocol version
    final block = link.protoBlock;
    if (block != null) {
      done = 'aborted';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _toast(block);
        if (mounted) widget.onExit('version');
      });
      return;
    }
    if (isHost) {
      _setProfile(pickProfile(
          me: link.me, members: link.players.map((p) => p.s('user_id')), online: {for (final e in link.online.entries) e.key: e.value.flutter}));
    } else {
      _pfWait = Timer(const Duration(seconds: 10), () {
        if (pf != null || !mounted || done != 'no') return;
        done = 'aborted';
        _toast('ارتباط با میزبان قطع شد');
        widget.onExit('hostLost');
      });
    }
    _offGame = link.onGame((m, from) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (m['k'] == 'abort' && !isHost && done != 'finished') {
        done = 'aborted';
        _toast('میزبان بازی را لغو کرد');
        widget.onExit('aborted');
        return;
      }
      if (done == 'aborted') return;
      if (pf == null) {
        final sm = m['k'] == 's' && m['s'] is Map ? snapProtoCheck(m['s'] as Map) : null;
        if (sm != null) {
          done = 'aborted';
          _pfWait?.cancel();
          _toast(sm);
          widget.onExit('version');
          return;
        }
        final p = msgProfile(m);
        if (p == null) {
          if (_early.length < 40) _early.add((m, from));
          return;
        }
        _setProfile(p);
      }
      net.onMessage(m, from, now);
    });
    _offRe = link.onReconnect(() {
      if (pf != null) net.resync(DateTime.now().millisecondsSinceEpoch);
    });
  }

  /// Fix the match's physics profile, then build engine/netcode/renderer.
  void _setProfile(String p) {
    if (pf != null) return;
    pf = p;
    _pfWait?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;
    net.lastRecv = now;
    for (final (m, from) in _early) {
      net.onMessage(m, from, now);
    }
    _early.clear();
    if (mounted) setState(() {});
    _load();
  }

  void _toast(String m) => Oracle.i.coach(m, 'alert');

  Future<void> _load() async {
    _im = await loadMatchImages(cfg, teams[0], teams[1]);
    await _buildRenderer();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _buildRenderer() async {
    final s = _size, im = _im;
    if (s == null || im == null) return;
    final flipped = myTeam == 1;
    final top = _ins.top + 92, bot = _ins.bottom + 72;
    final v = computeView(eng, s.width, s.height, flipped ? bot : top, flipped ? top : bot, flipped: flipped);
    final r = MatchRenderer(eng, im, cfg.ball, v, dpr: ui.PlatformDispatcher.instance.views.first.devicePixelRatio, hq: hq, ballShader: MatchRenderer.useBallShader ? await ballShader() : null);
    await r.prepare();
    game.r = r;
  }

  @override
  void dispose() {
    _offGame?.call();
    _offRe?.call();
    _pfWait?.cancel();
    Sound.stopLoop(Snd.crowd);
    Oracle.i.setScene('ui');
    if (isHost && done == 'no') {
      link.sendGame({'k': 'abort'});
      rpc('abandon_match', {'p_match': widget.matchId}).catchError((_) => null);
    }
    super.dispose();
  }

  OnlineOutcome outcome(List<int> score, int? d, bool reported) {
    final w = score[0] > score[1] ? 0 : score[1] > score[0] ? 1 : -1;
    final rd = d == null ? null : !ranked ? 0 : myTeam == 1 ? -d : myTeam == 0 ? d : null;
    return OnlineOutcome(widget.matchId, score, w, rd, myTeam, teams, names, reported, ranked);
  }

  void _banner(String t, String s, Color c) => banner.value = BannerMsg(t, s, c);

  void _onEvent(EngineEvent ev, bool local) {
    switch (ev.t) {
      case EvType.shot:
        mineShot = net.controller == link.me;
        touched = false;
        if (mineShot) power = eng.lastPower;
        buzz();
      case EvType.hit:
        if (ev.ball) touched = true;
        sfx(ev.ball ? Snd.hitb : Snd.hitp, ev.power);
        if (ev.power > .35) buzz(ev.power > .7 ? 'medium' : 'light');
      case EvType.wall:
        sfx(Snd.wall, ev.power);
      case EvType.post:
        sfx(Snd.post, ev.power);
        buzz('medium');
      case EvType.turn:
        turnN++;
        if (mineShot && !touched) {
          misses++;
          final t = coachMiss(power, misses);
          final now = DateTime.now().millisecondsSinceEpoch;
          if (t != null && now - lastTip > 18000) {
            lastTip = now;
            Oracle.i.coach(t, power > .9 ? 'focus' : 'idea');
          }
        }
        mineShot = false;
      case EvType.goal:
        if (ev.nogoal) {
          _banner('گل مردود', 'با ضربه‌ی اول نمی‌شه گل زد', C.dim);
        } else {
          touched = true;
          sfx(Snd.goal);
          sfx(Snd.roar);
          buzz('heavy');
          _banner('گل!', names[ev.team], ev.team == 0 ? C.cyanOld : C.red);
          if (ev.team == myTeam) Oracle.i.react('goal');
        }
      case EvType.clock:
        _banner('گل طلایی', 'گل بعدی برنده‌ست', C.gold);
      case EvType.end:
        if (done == 'no') {
          done = 'ended';
          sfx(Snd.finalW);
          Sound.stopLoop(Snd.crowd);
          if (isHost) {
            _hostReport([ev.s0, ev.s1]);
          } else {
            endAt = DateTime.now().millisecondsSinceEpoch;
          }
        }
    }
  }

  Future<void> _hostReport(List<int> score) async {
    net.sendSnap(DateTime.now().millisecondsSinceEpoch, force: true);
    final dur = ((DateTime.now().millisecondsSinceEpoch - t0) / 1000).round();
    int? d;
    var ok = false;
    for (var i = 0; i < 3 && !ok; i++) {
      try {
        final r = Rec.of(await rpc('report_match', {'p_match': widget.matchId, 'p_score_a': score[0], 'p_score_b': score[1], 'p_duration': dur}));
        d = r.i('rating_delta');
        ok = true;
      } catch (e) {
        if (RegExp('not live', caseSensitive: false).hasMatch('$e')) break;
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    }
    if (!ok) _toast('ثبت نتیجه ناموفق بود');
    link.sendGame({'k': 'res', 'winner': score[0] > score[1] ? 0 : score[1] > score[0] ? 1 : -1, 'rd': d ?? 0, 'score': score, 'ok': ok});
    link.ping();
    Timer(const Duration(milliseconds: 1100), () {
      if (done == 'ended') {
        done = 'finished';
        widget.onFinish(outcome(score, d, ok));
      }
    });
  }

  void _tick(double dt) {
    if (loading || pf == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    net.tick(dt, now);
    if (!isHost) {
      if (done == 'no' && now - net.lastRecv > 8000) {
        done = 'aborted';
        _toast('ارتباط با میزبان قطع شد');
        widget.onExit('hostLost');
        return;
      }
      if (done == 'ended') {
        final res = net.result;
        if (res != null && now - endAt > 900) {
          done = 'finished';
          final sc = (res['score'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [eng.score[0], eng.score[1]];
          widget.onFinish(outcome(sc, (res['rd'] as num?)?.toInt(), res['ok'] == true));
        } else if (res == null && now - endAt > 10000) {
          done = 'finished';
          sb.from('matches').select('score_a, score_b, status').eq('id', widget.matchId).maybeSingle().then((d) {
            final r = Rec.of(d);
            final sc = r.s('status') == 'done' ? [r.i('score_a', eng.score[0]), r.i('score_b', eng.score[1])] : [eng.score[0], eng.score[1]];
            widget.onFinish(outcome(sc, null, r.s('status') == 'done'));
          }, onError: (_) => widget.onFinish(outcome([eng.score[0], eng.score[1]], null, false)));
        }
      }
    }
    final ctrl = net.controller;
    if (ctrlN.value != ctrl) {
      ctrlN.value = ctrl;
      if (ctrl == link.me && eng.phase == Phase.aim) {
        sfx(Snd.ready);
        buzz('medium');
      }
    }
    final m = eng.mleft.ceil().clamp(0, 99999);
    final clock = cfg.matchTime > 0 ? (eng.sudden ? 'گل طلایی' : '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}') : 'تا ${fa(cfg.limit)} گل';
    final tl = cfg.turnTime > 0 && eng.phase == Phase.aim ? (eng.tleft / cfg.turnTime).clamp(0.0, 1.0) : 1.0;
    if (ctrl == link.me && eng.phase == Phase.aim && cfg.turnTime > 0 && eng.tleft < 5 && eng.tleft > 0 && reminded != turnN) {
      reminded = turnN;
      Oracle.i.coach('نوبت توئه و ۵ ثانیه مونده! ⏱', 'alert');
    }
    if (ctrl == link.me && eng.phase == Phase.aim && cfg.turnTime > 0) {
      final sec = eng.tleft.ceil();
      if (sec <= 3 && sec > 0 && sec != tickAt) {
        tickAt = sec;
        sfx(Snd.tick);
      }
    } else {
      tickAt = -1;
    }
    final h = HudState(eng.score[0], eng.score[1], eng.turn, clock, tl, eng.sudden);
    if (h != hud.value) hud.value = h;
    if (Store.i.p.debugOverlay) {
      if (now - _lastRateAt >= 1000) {
        _msgRate = link.recvMsgs + link.sentMsgs - _lastMsgs;
        _lastMsgs = link.recvMsgs + link.sentMsgs;
        _lastRateAt = now;
      }
      final s = 'FPS ${(1000 / game.frameMs).toStringAsFixed(0)} · step ${game.stepMs.toStringAsFixed(2)}ms · ${net.mode.name.toUpperCase()} ${eng.cfg.profile} · RTT ${link.rtt ?? '-'}ms · $_msgRate msg/s · desync ${net.desyncs}';
      if (s != debug.value) debug.value = s;
    }
  }

  // ---- input ----
  void _down(PointerDownEvent e) {
    if (pf == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!net.canAct(now)) return;
    final w = game.toWorld(e.localPosition);
    if (w != null && eng.pick(w.dx, w.dy)) buzz();
  }

  void _move(PointerMoveEvent e) {
    if (pf == null) return;
    final d = eng.drag;
    if (d == null || d.ai) return;
    final w = game.toWorld(e.localPosition);
    if (w == null) return;
    eng.move(w.dx, w.dy);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - sentAim > 120) {
      sentAim = now;
      link.sendGame({'k': 'aim', 'b': d.b.id, 'dx': (d.sx - d.cx).round(), 'dy': (d.sy - d.cy).round()});
    }
  }

  void _up() {
    if (pf == null) return;
    final d = eng.drag;
    if (d == null || d.ai) return;
    net.release(DateTime.now().millisecondsSinceEpoch, d);
  }

  Future<void> _quit() async {
    final ok = await confirmQuit(context, isHost);
    if (!ok) return;
    if (isHost) {
      done = 'aborted';
      link.sendGame({'k': 'abort'});
      rpc('abandon_match', {'p_match': widget.matchId}).catchError((_) => null);
      link.ping();
    }
    widget.onExit('quit');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context), ins = MediaQuery.paddingOf(context);
    if (_size != size || _ins != ins) {
      _size = size;
      _ins = ins;
      if (_im != null) _buildRenderer();
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) _quit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xff02040c),
        body: Stack(children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: (_) => _up(),
              onPointerCancel: (_) {
                if (pf != null && eng.drag?.ai == false) eng.drag = null;
                link.sendGame({'k': 'aim', 'b': -1});
              },
              child: pf == null ? const SizedBox.expand() : RepaintBoundary(child: GameWidget(game: game)),
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
                    onTap: _quit,
                    child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: const Color(0xd9080c22), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
                        child: const Icon(Icons.close_rounded, color: C.dim)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Panel(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      accent: h.turn == 0 ? C.cyanOld : C.red,
                      child: Row(children: [
                        Expanded(child: MatchSide(team: teams[0], name: names[0], on: h.turn == 0, color: C.cyanOld)),
                        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          tTitle('${h.s0} : ${h.s1}', size: 24),
                          T(h.clock, size: 9, family: F.head, weight: 700, spacing: 2, color: h.sudden ? C.gold : C.dim),
                        ]),
                        Expanded(child: MatchSide(team: teams[1], name: names[1], on: h.turn == 1, color: C.red, right: true)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PingBadge(link: link),
                ]),
                const SizedBox(height: 6),
                ValueListenableBuilder<String?>(
                  valueListenable: ctrlN,
                  builder: (_, c, __) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                        color: c == link.me ? const Color(0x333dffa8) : const Color(0xb3080c22), borderRadius: BorderRadius.circular(14), border: Border.all(color: c == link.me ? C.green : C.line)),
                    child: tBold(c == link.me ? 'نوبت توئه!' : 'نوبت: ${nameOf(c)}', size: 12, color: c == link.me ? C.green : C.text),
                  ),
                ),
                if (cfg.turnTime > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(color: const Color(0x14ffffff), borderRadius: BorderRadius.circular(3)),
                      child: FractionallySizedBox(
                        alignment: h.turn == 0 ? Alignment.centerLeft : Alignment.centerRight,
                        widthFactor: h.tl,
                        child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), gradient: LinearGradient(colors: h.turn == 0 ? const [C.cyanOld, C.blue] : const [C.red, C.orange]))),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: ins.bottom + 10,
            child: Row(children: [
              ChatButton(link: link),
              const Spacer(),
              VoiceBar(link: link, enabled: room0.b('voice'), compact: true),
            ]),
          ),
          GoalBanner(banner: banner),
          if (Store.i.p.debugOverlay)
            Positioned(
              left: 8,
              right: 8,
              top: ins.top + 130,
              child: IgnorePointer(
                child: ValueListenableBuilder<String>(
                  valueListenable: debug,
                  builder: (_, s, __) => Text(s, textAlign: TextAlign.center, style: const TextStyle(fontFamily: F.num, fontSize: 10, color: C.green, backgroundColor: Color(0xaa000000))),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
