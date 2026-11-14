// Port of src/screens/Setup.tsx: game modes, launch config and the pre-match sheet.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../game/engine.dart';
import '../net/discs.dart';
import '../ui/kit.dart';

enum ModeKey { quick, local, cup, galaxy, train }

class Mode {
  final ModeKey k;
  final String img, name, en, desc, reward;
  final Color color;
  const Mode(this.k, this.img, this.name, this.en, this.desc, this.reward, this.color);
}

final kModes = [
  Mode(ModeKey.quick, ui('portal_gamepad'), 'بازی سریع', 'QUICK MATCH', 'یک مسابقه‌ی فوری مقابل هوش مصنوعی', 'سکه، XP و جام', C.cyan),
  Mode(ModeKey.cup, ui('portal_globe'), 'جام نکسورا', 'NEXORA CUP', 'سه حریف پشت سر هم تا فینال؛ هر مرحله سخت‌تر', '۲ برابر جایزه + ۲۰ الماس قهرمانی', C.gold),
  Mode(ModeKey.galaxy, ui('portal_galaxy'), 'چالش کهکشانی', 'GALAXY CHALLENGE', 'دو دقیقه مقابل ربات افسانه‌ای', '۳ برابر جایزه', C.violet),
  Mode(ModeKey.local, ui('portal_friends'), 'دو نفره', 'LOCAL 2 PLAYER', 'با دوستت روی یک گوشی بازی کن', 'فقط برای افتخار', C.green),
  Mode(ModeKey.train, ui('portal_brain'), 'تمرین', 'TRAINING', 'بدون تایمر، ربات آسان، برای گرم کردن دست', 'XP کم، بدون جام', C.sky),
];

class Launch {
  final MatchCfg cfg;
  final List<Team> teams;
  final List<String> names;
  final ModeKey mode;
  final int stage;
  Launch(this.cfg, this.teams, this.names, this.mode, this.stage);
}

final _rng = math.Random();
List<Team> _pool() => kTeams.where((t) => t.cat == 'club' || t.cat == 'nat' || t.cat == 'elite').toList();
Team pickOpp() {
  final p = _pool();
  return p[_rng.nextInt(p.length)];
}

bool _boosted(Team t) => t.cat == 'vip' || t.cat == 'leg';

/// rule: 'g3' | 'g5' | 't3'
Launch buildLaunch(ModeKey mode, Profile p, {required int lvl, required String rule, required int tt, required Team opp, int stage = 0}) {
  final me = teamById(p.team), oppForm = _rng.nextInt(kForms.length);
  final ai = mode != ModeKey.local;
  var l = lvl, limit = rule == 'g5' ? 5 : 3, matchTime = rule == 't3' ? 180.0 : 0.0, t = tt;
  if (mode == ModeKey.cup) {
    l = math.min(2, stage);
    limit = 3;
    matchTime = 0;
  }
  if (mode == ModeKey.galaxy) {
    l = 2;
    matchTime = 120;
    limit = 99;
  }
  if (mode == ModeKey.train) {
    l = 0;
    t = 0;
  }
  final cfg = MatchCfg(
    field: p.field,
    ball: p.ball,
    forms: [p.form, ai ? oppForm : p.form],
    ai: ai,
    aiLvl: l,
    limit: limit,
    matchTime: matchTime,
    turnTime: t.toDouble(),
    vip: [_boosted(me), _boosted(opp)],
    first: 0,
    stats: [Discs.i.stats(me.id), Discs.i.stats(opp.id)],
  );
  return Launch(cfg, [me, opp], [p.name, ai ? opp.name : 'بازیکن ۲'], mode, stage);
}

class SetupSheet extends StatefulWidget {
  final Mode mode;
  final void Function(Launch) onStart;
  final VoidCallback onTeam;
  const SetupSheet({super.key, required this.mode, required this.onStart, required this.onTeam});
  @override
  State<SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<SetupSheet> {
  late int lvl = Store.i.p.aiLvl;
  late String rule = Store.i.p.limit == 5 ? 'g5' : 'g3';
  late int tt = Store.i.p.turnTime;
  Team opp = pickOpp();

  @override
  Widget build(BuildContext context) {
    final p = Store.i.p, m = widget.mode, me = teamById(p.team);
    final showLvl = m.k == ModeKey.quick, showRule = m.k == ModeKey.quick || m.k == ModeKey.local, showTT = m.k != ModeKey.train;
    Widget row(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [tBold(label, size: 13, color: C.dim, align: TextAlign.right), const SizedBox(height: 6), child]));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 30), children: [
      SizedBox(height: 150, child: Stack(alignment: Alignment.center, children: [Pulse(size: 120, color: m.color.withValues(alpha: .33)), FloatY(amp: 5, child: Img(m.img, w: 140, h: 150))])),
      T(m.desc, size: 14, color: const Color(0xffc8e2ff), align: TextAlign.center),
      const SizedBox(height: 10),
      Center(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: m.color.withValues(alpha: .1), borderRadius: BorderRadius.circular(16), border: Border.all(color: m.color.withValues(alpha: .4))),
          child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [Img(ui2('c_coin'), w: 22, h: 22), const SizedBox(width: 6), T(m.reward, size: 12, color: const Color(0xffffe9a8))]),
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: C.line),
            gradient: const LinearGradient(colors: [Color(0x2e4fe3ff), Color(0xd90a1230), Color(0x2eff4a5a)])),
        child: Row(children: [
          Expanded(
              child: Press(
                  onTap: widget.onTeam,
                  child: Column(children: [
                    Disc(teamImg(me), size: 72, ring: C.cyan, ringW: 3, glowOn: true),
                    const SizedBox(height: 6),
                    tBold(me.name, size: 12, lines: 1),
                    const T('تغییر تیم', size: 10, color: C.cyan),
                  ]))),
          Img(ui('vs'), w: 70, h: 60),
          Expanded(
              child: Press(
                  onTap: m.k == ModeKey.local ? null : () => setState(() => opp = pickOpp()),
                  child: Column(children: [
                    Disc(m.k == ModeKey.local ? teamImg(me) : teamImg(opp), size: 72, ring: C.red, ringW: 3, glowOn: true),
                    const SizedBox(height: 6),
                    tBold(m.k == ModeKey.local ? 'بازیکن ۲' : opp.name, size: 12, lines: 1),
                    T(m.k == ModeKey.local ? ' ' : 'حریف دیگر ↻', size: 10, color: C.red),
                  ]))),
        ]),
      ),
      if (m.k == ModeKey.cup)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: const Color(0x12ffd257), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0x40ffd257))),
          child: Row(textDirection: TextDirection.rtl, children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Column(children: [
                  Img(i == 2 ? ui2('x_trophy') : ui2('x_medal'), w: 46, h: 46, opacity: i == 0 ? 1 : .55),
                  T(['یک‌چهارم', 'نیمه‌نهایی', 'فینال'][i], size: 11, color: i == 0 ? C.gold : C.dim),
                  T(['آسان', 'معمولی', 'سخت'][i], size: 10, color: C.dim2),
                ]),
              ),
          ]),
        ),
      if (showLvl) row('سختی', Segment<int>(value: lvl, onChange: (v) => setState(() => lvl = v), items: const [(0, 'آسان'), (1, 'معمولی'), (2, 'سخت')])),
      if (showRule) row('قانون', Segment<String>(value: rule, onChange: (v) => setState(() => rule = v), items: const [('g3', 'تا ۳ گل'), ('g5', 'تا ۵ گل'), ('t3', '۳ دقیقه')], accent: C.violet)),
      if (showTT) row('زمان نوبت', Segment<int>(value: tt, onChange: (v) => setState(() => tt = v), items: const [(0, 'خاموش'), (10, '۱۰ث'), (15, '۱۵ث'), (20, '۲۰ث')], accent: C.green)),
      const SizedBox(height: 16),
      Press(
        onTap: widget.onTeam,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xd90a1230), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
          child: Row(children: [
            ClipOval(child: Img(ballImg(p.ball), w: 38, h: 38)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  tBold('${kBallNames[p.ball]} · ${kFields[p.field].name}', size: 12, lines: 1),
                  T('ترکیب ${kForms[p.form].code} · تجهیزات', size: 11, color: C.dim),
                ]),
              ),
            ),
            Img(fieldThumb(p.field), w: 30, h: 40, fit: BoxFit.cover, radius: 6),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      Btn(m.k == ModeKey.cup ? 'شروع جام' : 'شروع بازی', colors: m.k == ModeKey.cup ? G.gold : G.primary, onTap: () {
        Store.i.set((q) {
          q.aiLvl = lvl;
          q.limit = rule == 'g5' ? 5 : 3;
          q.turnTime = tt;
        });
        widget.onStart(buildLaunch(m.k, Store.i.p, lvl: lvl, rule: rule, tt: tt, opp: opp));
      }),
    ]);
  }
}
