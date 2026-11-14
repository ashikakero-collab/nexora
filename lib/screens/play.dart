// Port of src/screens/Play.tsx (+ OnlineCard.tsx): online entry card, offline mode carousel, league road.
import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'setup.dart';

const _medal = ['medal_bronze', 'medal_silver', 'medal_gold', 'medal_epic', 'shield_epic', 'shield_crown'];

class PlayScreen extends StatefulWidget {
  final void Function(Mode) onMode;
  final void Function(String entry) onOnline;
  const PlayScreen({super.key, required this.onMode, required this.onOnline});
  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  late final PageController pc = PageController(viewportFraction: .74);
  double page = 0;

  @override
  void initState() {
    super.initState();
    pc.addListener(() => setState(() => page = pc.page ?? 0));
  }

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final p = Store.i.p, lg = league(p.trophies);
    final idx = page.round().clamp(0, kModes.length - 1);
    final m = kModes[idx];
    final cw = (w * .72).clamp(0, 330).toDouble();
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        const Space(theme: SpaceTheme.holo),
        ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 20), children: [
          Header(title: 'آرکید نکسورا', en: 'PORTAL · SELECT', onBack: () => Navigator.pop(context)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: OnlineCard(onOnline: widget.onOnline)),
          const TitleBar('آفلاین', en: 'OFFLINE · BOT & LOCAL'),
          SizedBox(
            height: cw * 1.32 + 32,
            child: PageView.builder(
              controller: pc,
              itemCount: kModes.length,
              itemBuilder: (_, i) {
                final d = (page - i);
                final mm = kModes[i];
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, .001)
                    ..rotateY(d.clamp(-1.0, 1.0) * -.45)
                    ..scaleByDouble(1 - d.abs().clamp(0.0, 1.0) * .16, 1 - d.abs().clamp(0.0, 1.0) * .16, 1, 1),
                  child: Opacity(
                    opacity: (1 - d.abs() * .45).clamp(.25, 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 16),
                      child: Press(
                        onTap: () => widget.onMode(mm),
                        scaleTo: .97,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(color: mm.color.withValues(alpha: .53), width: 1.5),
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [mm.color.withValues(alpha: .33), const Color(0xd90e1640), const Color(0xfa050818)]),
                            boxShadow: glow(mm.color, 18, .35),
                          ),
                          child: Stack(alignment: Alignment.topCenter, children: [
                            Positioned(top: 10, child: Img(ui2('portal'), w: cw * 1.05, h: cw * .7, opacity: .42)),
                            Positioned(
                              top: cw * .1,
                              child: Transform.translate(
                                offset: Offset(d * 40, 0),
                                child: Stack(alignment: Alignment.center, children: [Pulse(size: cw * .45, color: mm.color.withValues(alpha: .33)), FloatY(child: Img(mm.img, w: cw * .58, h: cw * .62))]),
                              ),
                            ),
                            Positioned(
                              bottom: 18,
                              left: 16,
                              right: 16,
                              child: Column(children: [
                                tHead(mm.en, size: 10, color: mm.color),
                                tTitle(mm.name, size: 24, shadows: [Shadow(color: mm.color, blurRadius: 14)]),
                                const SizedBox(height: 4),
                                T(mm.desc, size: 12, color: const Color(0xffc6dbff), align: TextAlign.center, lines: 2),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: mm.color.withValues(alpha: .4))),
                                  child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [Img(ui2('c_coin'), w: 20, h: 20), const SizedBox(width: 4), T(mm.reward, size: 11, color: const Color(0xffffe9a8), lines: 1)]),
                                ),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < kModes.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 8 + (1 - (page - i).abs()).clamp(0.0, 1.0) * 18,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(color: kModes[i].color.withValues(alpha: .35 + (1 - (page - i).abs()).clamp(0.0, 1.0) * .65), borderRadius: BorderRadius.circular(4)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: Btn('ورود به ${m.name}',
                colors: m.k == ModeKey.cup ? G.gold : m.k == ModeKey.galaxy ? G.violet : m.k == ModeKey.local ? G.green : G.primary, onTap: () => widget.onMode(m)),
          ),
          const TitleBar('جاده‌ی لیگ', en: 'LEAGUE ROAD', accent: C.gold),
          SizedBox(
            height: 130,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (var i = 0; i < kLeagues.length; i++) ...[
                if (i > 0) Center(child: Container(width: 22, height: 3, color: p.trophies >= kLeagues[i].$2 ? C.gold : const Color(0x26ffffff))),
                Container(
                  width: 92,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: i == lg.idx ? C.gold : C.line),
                    color: i == lg.idx ? const Color(0x1fffd257) : const Color(0x99080c22),
                    boxShadow: i == lg.idx ? glow(C.gold, 12, .6) : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Img(ui(_medal[i]), w: 54, h: 54, opacity: p.trophies >= kLeagues[i].$2 ? 1 : .35),
                    T(kLeagueFa[kLeagues[i].$1]!, size: 11, color: p.trophies >= kLeagues[i].$2 ? Colors.white : C.dim2),
                    T(fa(kLeagues[i].$2), size: 9, family: F.head, weight: 700, color: p.trophies >= kLeagues[i].$2 ? C.gold : C.dim2),
                  ]),
                ),
              ],
            ]),
          ),
        ]),
      ]),
    );
  }
}

class OnlineCard extends StatelessWidget {
  final void Function(String entry) onOnline;
  const OnlineCard({super.key, required this.onOnline});
  @override
  Widget build(BuildContext context) {
    final links = [('arena', 'آرنا', ui2('x_crown')), ('tours', 'تورنمنت', ui2('x_trophy')), ('leagues', 'لیگ', ui2('x_medal')), ('challenges', 'چالش', ui2('c_calendar'))];
    return ListenableBuilder(
      listenable: Auth.i,
      builder: (_, __) {
        final pr = Auth.i.profile;
        return Column(children: [
          Press(
            onTap: () => onOnline('hub'),
            scaleTo: .97,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0x8c78dcff)),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff3a1d8a), Color(0xff1b2f8f), Color(0xff0a5a8a)]),
                boxShadow: glow(C.cyan, 16, .35),
              ),
              child: Row(children: [
                Img(ui('portal_globe'), w: 84, h: 84),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(8)),
                        child: const T('LIVE', size: 9, family: F.head, weight: 700, color: Colors.white, spacing: 1),
                      ),
                      const SizedBox(width: 8),
                      tTitle('آنلاین', size: 24, shadows: const [Shadow(color: C.cyan, blurRadius: 12)]),
                    ]),
                    const T('مسابقه با بازیکن‌های واقعی · ۱ به ۱، ۲ به ۲، ۳ به ۳', size: 12, color: Color(0xffd6e6ff), lines: 2),
                    if (pr != null) tBold('امتیاز ${fa(pr.i('rating'))} · 💎 ${fa(pr.i('gems'))}', size: 11, color: C.gold),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Row(textDirection: TextDirection.rtl, children: [
            for (final (k, l, img) in links)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Press(
                    onTap: () => onOnline(k),
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(color: const Color(0xcc0a1030), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, textDirection: TextDirection.rtl, children: [Img(img, w: 24, h: 24), const SizedBox(width: 4), tBold(l, size: 11, lines: 1)]),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      },
    );
  }
}
