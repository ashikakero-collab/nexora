// Port of src/screens/Result.tsx: victory/defeat/draw banner, score, animated rewards, level-up, Oracle line.
import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/theme.dart';
import '../oracle/oracle.dart';
import '../ui/kit.dart';
import 'match.dart';

class Reward {
  int coins, xp, trophies, gems;
  Reward(this.coins, this.xp, this.trophies, this.gems);
}

class CupInfo {
  final int stage;
  final bool won, champion;
  const CupInfo(this.stage, this.won, this.champion);
}

class ResultScreen extends StatefulWidget {
  final MatchResult r;
  final Reward? reward;
  final List<String> names;
  final VoidCallback onAgain, onHome;
  final CupInfo? cup;
  final int? levelUp;
  const ResultScreen({super.key, required this.r, this.reward, required this.names, required this.onAgain, required this.onHome, this.cup, this.levelUp});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final String out = widget.r.score[0] > widget.r.score[1] ? 'victory' : widget.r.score[0] < widget.r.score[1] ? 'defeat' : 'draw';
  late final (String, String) line = resultLine(out);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width, ins = MediaQuery.paddingOf(context);
    final col = out == 'victory' ? C.gold : out == 'defeat' ? C.red : C.cyan;
    final bw = (w * .9).clamp(0, 380).toDouble();
    final a = widget.r.score[0], b = widget.r.score[1];
    final rw = widget.reward, cup = widget.cup;
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        Space(theme: out == 'victory' ? SpaceTheme.win : out == 'defeat' ? SpaceTheme.lose : SpaceTheme.system),
        ListView(padding: EdgeInsets.fromLTRB(16, ins.top + 10, 16, ins.bottom + 24), children: [
          SizedBox(
            height: bw * .66,
            child: Stack(alignment: Alignment.center, children: [
              Spin(ms: 20000, child: Img(ui2('ring'), w: bw * .95, h: bw * .95, opacity: .5)),
              Pulse(size: bw * .5, color: col.withValues(alpha: .27)),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.elasticOut,
                builder: (_, v, ch) => Opacity(opacity: (v * 1.4).clamp(0, 1), child: Transform.scale(scale: .4 + v * .6, child: ch)),
                child: Img(ui(out), w: bw, h: bw * .62),
              ),
            ]),
          ),
          Panel(
            accent: col,
            glowOn: true,
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: _side(teamImg(widget.r.teams[0]), widget.names[0], C.cyan)),
              Column(children: [
                tTitle('$a : $b', size: 40, shadows: [Shadow(color: col, blurRadius: 16)]),
                tHead('FINAL', size: 9, color: C.dim, spacing: 4),
              ]),
              Expanded(child: _side(teamImg(widget.r.teams[1]), widget.names[1], C.red)),
            ]),
          ),
          if (rw != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(textDirection: TextDirection.rtl, children: [
                _Rw(img: ui2('c_coin'), v: rw.coins, c: C.gold, delay: 200),
                _Rw(img: ui2('x_star'), v: rw.xp, c: C.cyan, delay: 350, label: 'XP'),
                _Rw(img: ui2('x_trophy'), v: rw.trophies, c: rw.trophies >= 0 ? C.green : C.red, delay: 500),
                if (rw.gems > 0) _Rw(img: ui2('x_gem'), v: rw.gems, c: const Color(0xff9fd8ff), delay: 650),
              ]),
            ),
          if (widget.levelUp != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Panel(
                accent: C.violet,
                glowOn: true,
                child: Row(textDirection: TextDirection.rtl, children: [
                  Img(ui2('x_crown'), w: 50, h: 50),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      tTitle('سطح ${fa(widget.levelUp!)}!', size: 18, color: const Color(0xffd6b8ff)),
                      const T('به سطح جدید رسیدی · ۱۰۰+ سکه هدیه', size: 11, color: C.dim),
                    ]),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 14),
          Row(textDirection: TextDirection.rtl, crossAxisAlignment: CrossAxisAlignment.end, children: [
            FloatY(amp: 4, child: Img(oracleImg(line.$1), w: 96, h: 104)),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xe60e1e50), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x665ce1ff))),
                child: T(line.$2, size: 12, height: 1.6, color: const Color(0xffe6f4ff)),
              ),
            ),
          ]),
          if (cup != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: tTitle(cup.champion ? 'قهرمان جام نکسورا! ۴۰۰+ سکه' : cup.won ? 'مرحله‌ی ${['یک', 'دو', 'سه'][cup.stage.clamp(0, 2)]} از سه رد شد' : 'از جام حذف شدی',
                  size: 16, color: cup.won ? C.gold : C.red, align: TextAlign.center),
            ),
          const SizedBox(height: 14),
          Btn(cup != null ? (cup.won && !cup.champion ? 'مرحله‌ی بعد' : 'جام دوباره') : 'بازی دوباره', colors: out == 'victory' ? G.gold : G.primary, onTap: widget.onAgain),
          const SizedBox(height: 10),
          Btn('بازگشت به خانه', small: true, colors: G.dark, onTap: widget.onHome),
        ]),
      ]),
    );
  }

  Widget _side(String img, String name, Color c) => Column(children: [Disc(img, size: 58, ring: c), const SizedBox(height: 4), tBold(name, size: 12, lines: 1)]);
}

class _Rw extends StatelessWidget {
  final String img;
  final int v, delay;
  final Color c;
  final String? label;
  const _Rw({required this.img, required this.v, required this.c, required this.delay, this.label});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 900 + delay),
            builder: (_, t, __) {
              final k = ((t * (900 + delay) - delay) / 600).clamp(0.0, 1.0);
              final n = (v * k).round();
              return Opacity(
                opacity: k,
                child: Transform.scale(
                  scale: .5 + Curves.easeOutBack.transform(k) * .5,
                  child: Panel(
                    accent: c,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(children: [
                      Img(img, w: 40, h: 40),
                      const SizedBox(height: 2),
                      tTitle('${n >= 0 ? '+' : ''}$n${label != null ? ' $label' : ''}', size: 15, color: c),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      );
}
