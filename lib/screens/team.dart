// Port of src/screens/Team.tsx (discs / balls / fields / formation), keeping the old Persian flow from the
// owner's refs: a disc carousel with left/right arrows + stat card + select/shop, and a formation picker grid
// of mini pitches with «انتخاب» buttons.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/owned.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../game/engine.dart' show powerFrac, aimDevDeg, aimPreview;
import '../net/auth.dart';
import '../net/discs.dart';
import '../ui/chrome.dart';
import '../tutorial/keys.dart';
import '../ui/kit.dart';
import '../ui/v4.dart';

const kCatFa = {'club': 'باشگاه', 'nat': 'ملی', 'elite': 'الیت', 'emb': 'نشان', 'leg': 'افسانه', 'vip': 'VIP', 'chrome': 'کروم', 'car': 'خودرو', 'lux': 'لوکس', 'spt': 'ورزشی'};
const kCatOrder = ['club', 'nat', 'elite', 'emb', 'leg', 'vip', 'chrome', 'car', 'lux', 'spt'];

class TeamScreen extends StatefulWidget {
  final String initial;
  const TeamScreen({super.key, this.initial = 'disc'});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  late String sub = widget.initial;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: Stack(children: [
          const SpaceBg(image: V4.bgTeam, dim: .1),
          Column(children: [
            Header(title: 'تیم من', en: 'SQUAD · DISCS · LOADOUT', onBack: () => Navigator.pop(context)),
            Padding(
              key: TourKeys.teamTabs,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Segment<String>(value: sub, onChange: (v) => setState(() => sub = v), items: const [('disc', 'دیسک'), ('ball', 'توپ'), ('field', 'زمین'), ('form', 'ترکیب')]),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([Store.i, Discs.i, Auth.i]),
                builder: (_, __) => switch (sub) { 'ball' => const _Balls(), 'field' => const _Fields(), 'form' => const _Formation(), _ => const _Discs() },
              ),
            ),
          ]),
        ]),
      );
}

class StatBars extends StatelessWidget {
  final double power, accuracy;
  final bool compact;
  const StatBars({super.key, required this.power, required this.accuracy, this.compact = false});
  @override
  Widget build(BuildContext context) {
    Widget row(String l, double v, Color c) => Padding(
          padding: EdgeInsets.only(top: compact ? 2 : 6),
          child: Row(textDirection: TextDirection.rtl, children: [
            SizedBox(width: compact ? 30 : 44, child: T(l, size: compact ? 9 : 12, color: C.dim)),
            Expanded(child: Bar(v: v / 10, h: compact ? 4 : 8, color: c)),
            SizedBox(width: compact ? 16 : 24, child: T(fa(v), size: compact ? 9 : 12, family: F.num, weight: 700, color: c, align: TextAlign.center)),
          ]),
        );
    return Column(children: [row('قدرت', power, C.orange), row('دقت', accuracy, C.cyan)]);
  }
}

// ---------- discs (carousel + grid) ----------
class _Discs extends StatefulWidget {
  const _Discs();
  @override
  State<_Discs> createState() => _DiscsState();
}

class _DiscsState extends State<_Discs> {
  late String cat = teamById(Store.i.p.team).cat;
  late String focus = Store.i.p.team;
  bool busy = false;

  List<Team> get list => kTeams.where((t) => t.cat == cat).toList();

  void step(int d) {
    final l = list;
    var i = l.indexWhere((t) => t.id == focus);
    if (i < 0) i = 0;
    i = (i + d) % l.length;
    if (i < 0) i += l.length;
    setState(() => focus = l[i].id);
    sfx(Snd.ui);
  }

  Future<void> act() async {
    final dz = Discs.i, ft = teamById(focus), p0 = Store.i.p;
    if (busy) return;
    if (ownsTeam(ft.id)) {
      Store.i.set((q) => q.team = ft.id);
      buzz('success');
      toast('${ft.name} انتخاب شد', 'ok');
      if (Auth.i.uid != null) dz.equip(ft.id).then((r) => r.$1 ? null : toast(r.$2!, 'err'));
      return;
    }
    final (cost, gemsCur) = teamCost(ft);
    if (!gemsCur) {
      if (p0.coins < cost) {
        toast('سکه کافی نداری', 'err');
        buzz('medium');
        return;
      }
      Store.i.set((q) {
        q.coins -= cost;
        q.ownedTeams = [...q.ownedTeams, ft.id];
        q.team = ft.id;
      });
      sfx(Snd.win);
      buzz('success');
      toast('${ft.name} باز شد!', 'ok');
      return;
    }
    setState(() => busy = true);
    try {
      if (Auth.i.uid == null && await Auth.i.ensure() == null) {
        toast('برای خرید باید آنلاین باشی', 'err');
        return;
      }
      final price = dz.catalog[ft.id]?.priceGems ?? (dz.isFree(ft.id) ? 0 : teamPrice(ft));
      final g = Auth.i.profile?.i('gems') ?? 0;
      if (Auth.i.profile != null && g < price) {
        toast('${fa(price - g)} الماس دیگر لازم داری · چالش‌های روزانه و تورنمنت‌ها الماس می‌دهند', 'err');
        buzz('medium');
        return;
      }
      final r = await dz.buy(ft.id);
      if (!r.$1) {
        toast(r.$2!, 'err');
        return;
      }
      await dz.equip(ft.id);
      Store.i.set((q) => q.team = ft.id);
      sfx(Snd.win);
      buzz('success');
      toast('${ft.name} باز شد! · 💎 ${fa(r.$3 ?? 0)} باقی‌مانده', 'ok');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dz = Discs.i, p = Store.i.p, w = MediaQuery.sizeOf(context).width;
    final ft = teamById(focus), owned = ownsTeam(ft.id);
    final (price, gemCur) = teamCost(ft);
    final ds = dz.stats(ft.id), rr = kRarity[rarity(ft)], rc = Color(rr.c);
    final gems = Auth.i.profile?.i('gems') ?? 0;
    final cell = (w - 32 - 3 * 8) / 4;
    final l = list;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Column(children: [
          // hero with the disc-ring art and left/right arrows (old Persian flow)
          SizedBox(
            key: TourKeys.teamHero,
            height: 240,
            child: Row(children: [
              _Arrow(left: true, onTap: () => step(-1)),
              Expanded(
                child: Stack(alignment: Alignment.center, children: [
                  Positioned(bottom: 0, child: Img(ui('holopad'), w: 230, h: 82, opacity: .9)),
                  Pulse(size: 150, color: rc.withValues(alpha: .33)),
                  Spin(ms: 24000, child: Img(discRing, w: 220, h: 220, opacity: .55)),
                  TweenAnimationBuilder<double>(
                    key: ValueKey(ft.id),
                    tween: Tween(begin: .75, end: 1),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.elasticOut,
                    builder: (_, v, ch) => Transform.scale(scale: v, child: ch),
                    child: Disc(teamImg(ft), size: 148, ring: rc, ringW: 3, glowOn: true),
                  ),
                ]),
              ),
              _Arrow(left: false, onTap: () => step(1)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(color: rc.withValues(alpha: .11), borderRadius: BorderRadius.circular(10), border: Border.all(color: rc.withValues(alpha: .53))),
            child: tHead(rr.n, size: 9, color: rc),
          ),
          const SizedBox(height: 4),
          tTitle(ft.name.toUpperCase(), size: 20, lines: 1),
          Panel(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            accent: rc,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StatBars(power: ds.power, accuracy: ds.accuracy),
              const SizedBox(height: 6),
              // v4: the numbers that really change play (Engine: powerMul / aimDevDeg / aimPreview)
              Row(textDirection: TextDirection.rtl, children: [
                for (final (l, v) in [
                  ('ضربه', '${(powerFrac(ds.power) * 100).toStringAsFixed(0)}٪'),
                  ('انحراف', '${aimDevDeg(ds.accuracy).toStringAsFixed(1)}°'),
                  ('خط نشانه', '×${aimPreview(ds.accuracy).toStringAsFixed(2)}'),
                ])
                  Expanded(child: Column(children: [T(l, size: 10, color: C.dim), T(v, size: 13, family: F.num, weight: 700)])),
              ]),
              const SizedBox(height: 6),
              const T('قدرت = سرعت بیشینه‌ی ضربه · دقت = انحراف کمتر و پیش‌نمایش مسیر بلندتر', size: 10, color: C.dim, align: TextAlign.right),
              const SizedBox(height: 10),
              p.team == ft.id
                  ? const Btn('انتخاب‌شده ✓', small: true, colors: G.dark, disabled: true)
                  : owned
                      ? Btn('انتخاب این دیسک', small: true, onTap: act)
                      : Btn(busy ? '…' : gemCur ? 'خرید · 💎 ${fa(price)}' : 'خرید · 🪙 ${fa(price)}',
                          sub: gemCur ? (Auth.i.profile != null ? 'موجودی: ${fa(gems)} الماس' : null) : 'موجودی: ${fa(p.coins)} سکه', small: true, colors: G.violet, onTap: act, disabled: busy),
            ]),
          ),
          SizedBox(
            height: 50,
            child: ListView(scrollDirection: Axis.horizontal, reverse: true, padding: const EdgeInsets.fromLTRB(8, 14, 8, 0), children: [
              for (final k in kCatOrder)
                if (kCats.any((c) => c.k == k))
                  Chip2(kCatFa[k] ?? k,
                      on: cat == k,
                      accent: k == 'leg' || k == 'vip' ? C.gold : k == 'emb' || k == 'chrome' ? C.violet : C.cyan,
                      onTap: () => setState(() {
                            cat = k;
                            focus = kTeams.firstWhere((t) => t.cat == k).id;
                          })),
            ]),
          ),
          const SizedBox(height: 10),
        ]),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 10),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: cell / (cell + 20)),
          delegate: SliverChildBuilderDelegate(childCount: l.length, (_, i) {
            final t = l[i], own = ownsTeam(t.id), sel = t.id == focus, eq = t.id == p.team, c = Color(kRarity[rarity(t)].c);
            return Press(
              onTap: () => setState(() => focus = t.id),
              scaleTo: .92,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sel ? [c.withValues(alpha: .25), const Color(0xe60a0f30)] : const [Color(0xd9121a48), Color(0xe6080c2a)]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: sel ? N.orange : const Color(0x55ff8a2a), width: sel ? 1.6 : 1),
                  boxShadow: sel && hq ? [BoxShadow(color: N.orange.withValues(alpha: .4), blurRadius: 10)] : null,
                ),
                child: Stack(children: [
                  Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      ClipOval(child: Img(teamImg(t), w: cell - 16, h: cell - 16, opacity: own ? 1 : .5)),
                      if (eq)
                        const T('● فعال', size: 9, color: C.green)
                      else if (own)
                        const T(' ', size: 9)
                      else
                        Row(mainAxisSize: MainAxisSize.min, children: [Img(teamCost(t).$2 ? ui2('x_gem') : ui2('c_coin'), w: 12, h: 12), T(' ${teamCost(t).$1}', size: 8, family: F.head, weight: 700, color: const Color(0xff9fd8ff))]),
                    ]),
                  ),
                  if (!own) const Positioned(top: 4, right: 4, child: Icon(Icons.lock_rounded, size: 11, color: C.dim)),
                ]),
              ),
            );
          }),
        ),
      ),
    ]);
  }
}

class _Arrow extends StatelessWidget {
  final bool left;
  final VoidCallback onTap;
  const _Arrow({required this.left, required this.onTap});
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CustomPaint(size: const Size(34, 46), painter: _ArrowPainter(left)),
        ),
      );
}

class _ArrowPainter extends CustomPainter {
  final bool left;
  _ArrowPainter(this.left);
  @override
  void paint(Canvas c, Size s) {
    final p = Path();
    if (left) {
      p
        ..moveTo(s.width, 0)
        ..lineTo(0, s.height / 2)
        ..lineTo(s.width, s.height)
        ..lineTo(s.width * .72, s.height / 2)
        ..close();
    } else {
      p
        ..moveTo(0, 0)
        ..lineTo(s.width, s.height / 2)
        ..lineTo(0, s.height)
        ..lineTo(s.width * .28, s.height / 2)
        ..close();
    }
    c.drawPath(p, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xffffe27a), Color(0xffffb400)]).createShader(Offset.zero & s));
    c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xaa7a4a00));
  }

  @override
  bool shouldRepaint(_ArrowPainter o) => o.left != left;
}

// ---------- balls ----------
class _Balls extends StatefulWidget {
  const _Balls();
  @override
  State<_Balls> createState() => _BallsState();
}

class _BallsState extends State<_Balls> {
  late int fb = Store.i.p.ball;
  @override
  Widget build(BuildContext context) {
    final p = Store.i.p, w = MediaQuery.sizeOf(context).width;
    final owned = ownsBall(fb), price = ballPrice(fb), eq = p.ball == fb, tr = kTrails[fb % kTrails.length].c;
    final cell = (w - 32 - 3 * 8) / 4;
    void act() {
      if (owned) {
        Store.i.set((q) => q.ball = fb);
        buzz('success');
        toast('توپ انتخاب شد', 'ok');
        return;
      }
      if (p.coins < price) {
        toast('سکه کافی نداری', 'err');
        return;
      }
      Store.i.set((q) {
        q.coins -= price;
        q.ownedBalls = [...q.ownedBalls, fb];
        q.ball = fb;
      });
      sfx(Snd.goal);
      buzz('success');
      toast('توپ جدید باز شد!', 'ok');
    }

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Column(children: [
          SizedBox(
            height: 220,
            child: Stack(alignment: Alignment.center, children: [
              Positioned(bottom: 6, child: Img(ui('holopad'), w: 230, h: 84)),
              Pulse(size: 130, color: const Color(0x593dffd8)),
              FloatY(amp: 7, ms: 1400, child: Spin(ms: 5000, child: ClipOval(child: Img(ballImg(fb), w: 132, h: 132)))),
            ]),
          ),
          tTitle(kBallNames[fb].toUpperCase(), size: 20),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final c in tr) Container(width: 28, height: 6, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: Color(c), borderRadius: BorderRadius.circular(3), boxShadow: glow(Color(c), 6, 1))),
          ]),
          const T('رنگ دنباله‌ی توپ', size: 10, color: C.dim),
          Padding(
            padding: const EdgeInsets.fromLTRB(50, 12, 50, 14),
            child: eq
                ? const Btn('انتخاب‌شده ✓', small: true, colors: G.dark, disabled: true)
                : owned
                    ? Btn('انتخاب', small: true, colors: G.green, onTap: act)
                    : Btn('خرید · $price', small: true, icon: ui2('c_coin'), colors: G.gold, onTap: act),
          ),
        ]),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 10),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: cell / (cell + 18)),
          delegate: SliverChildBuilderDelegate(childCount: 36, (_, i) {
            final own = ownsBall(i), sel = i == fb, e = p.ball == i;
            return Press(
              onTap: () => setState(() => fb = i),
              scaleTo: .92,
              child: Container(
                decoration: BoxDecoration(color: sel ? const Color(0x1f3dffa8) : const Color(0xb3080c22), borderRadius: BorderRadius.circular(16), border: Border.all(color: sel ? C.green : const Color(0x296eaaff))),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ClipOval(child: Img(ballImg(i), w: cell - 22, h: cell - 22, opacity: own ? 1 : .5)),
                  const SizedBox(height: 3),
                  T(e ? '● فعال' : own ? kBallNames[i] : '${ballPrice(i)} ◉', size: 9, color: e ? C.green : own ? C.dim : C.gold, lines: 1),
                ]),
              ),
            );
          }),
        ),
      ),
    ]);
  }
}

// ---------- fields ----------
class _Fields extends StatefulWidget {
  const _Fields();
  @override
  State<_Fields> createState() => _FieldsState();
}

class _FieldsState extends State<_Fields> {
  late int ff = Store.i.p.field;
  @override
  Widget build(BuildContext context) {
    final p = Store.i.p, w = MediaQuery.sizeOf(context).width;
    final owned = ownsField(ff), price = fieldPrice(ff), eq = p.field == ff;
    final cell = (w - 32 - 2 * 10) / 3;
    void act() {
      if (owned) {
        Store.i.set((q) => q.field = ff);
        buzz('success');
        toast('زمین انتخاب شد', 'ok');
        return;
      }
      if (p.coins < price) {
        toast('سکه کافی نداری', 'err');
        return;
      }
      Store.i.set((q) {
        q.coins -= price;
        q.ownedFields = [...q.ownedFields, ff];
        q.field = ff;
      });
      sfx(Snd.goal);
      buzz('success');
      toast('زمین جدید باز شد!', 'ok');
    }

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: C.cyan.withValues(alpha: .6)), boxShadow: glow(C.cyan, 16, .4)),
            child: Img(fieldThumb(ff), w: 160, h: 214, fit: BoxFit.cover, radius: 16),
          ),
          const SizedBox(height: 10),
          tTitle(kFields[ff].name.toUpperCase(), size: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(50, 12, 50, 14),
            child: eq
                ? const Btn('انتخاب‌شده ✓', small: true, colors: G.dark, disabled: true)
                : owned
                    ? Btn('انتخاب', small: true, colors: G.green, onTap: act)
                    : Btn('خرید · $price', small: true, icon: ui2('c_coin'), colors: G.gold, onTap: act),
          ),
        ]),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 10),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: cell / ((cell - 16) * 1.33 + 40)),
          delegate: SliverChildBuilderDelegate(childCount: kFields.length, (_, i) {
            final own = ownsField(i), sel = i == ff, e = p.field == i;
            return Press(
              onTap: () => setState(() => ff = i),
              scaleTo: .94,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: sel ? const Color(0x1f4fe3ff) : const Color(0xb3080c22), borderRadius: BorderRadius.circular(16), border: Border.all(color: sel ? C.cyan : const Color(0x296eaaff))),
                child: Column(children: [
                  Img(fieldThumb(i), w: cell - 16, h: (cell - 16) * 1.33, fit: BoxFit.cover, radius: 10, opacity: own ? 1 : .5),
                  const SizedBox(height: 4),
                  T(e ? '● فعال' : own ? kFields[i].name : '${fieldPrice(i)} ◉', size: 10, color: e ? C.green : own ? C.dim : C.gold, lines: 1),
                ]),
              ),
            );
          }),
        ),
      ),
    ]);
  }
}

// ---------- formation picker (grid of mini pitches, like the old Persian «انتخاب ترکیب» screen) ----------
class _Formation extends StatelessWidget {
  const _Formation();
  @override
  Widget build(BuildContext context) {
    final p = Store.i.p, w = MediaQuery.sizeOf(context).width;
    final me = teamById(p.team);
    final fw = math.min(w - 64, 300.0), fh = fw * 1.35;
    final pts = slots(p.form);
    return ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 10), children: [
      Center(
        child: Container(
          width: fw,
          height: fh,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: C.cyan.withValues(alpha: .5))),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned.fill(child: Img(fieldThumb(p.field), w: fw, h: fh, fit: BoxFit.cover)),
            const Positioned.fill(child: ColoredBox(color: Color(0x5902061e))),
            Positioned(left: 0, right: 0, top: fh / 2, child: Container(height: 1.5, color: const Color(0x66ffffff))),
            Positioned(left: fw / 2 - 30, top: fh / 2 - 30, child: Container(width: 60, height: 60, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x66ffffff), width: 1.5)))),
            for (var i = 0; i < pts.length; i++)
              AnimatedPositioned(
                key: ValueKey('s$i'),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutBack,
                left: 18 + pts[i][0] * (fw - 36) - 20,
                top: fh - pts[i][1] * fh * 1.9 - 20,
                child: Disc(teamImg(me), size: 40, ring: C.cyan, glowOn: true),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      tTitle('${kForms[p.form].code} · ${kForms[p.form].name}', size: 18, align: TextAlign.center),
      const SizedBox(height: 4),
      const T('انتخاب ترکیب', size: 16, align: TextAlign.center),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Directionality(textDirection: TextDirection.rtl, child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .62,
          children: [
            for (var i = 0; i < kForms.length; i++)
              Column(children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.form == i ? C.cyan : const Color(0x33ffffff), width: p.form == i ? 2 : 1)),
                    clipBehavior: Clip.antiAlias,
                    child: CustomPaint(painter: _MiniPitch(i), child: const SizedBox.expand()),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  color: const Color(0xcc0a0f22),
                  child: Column(children: [tBold(kForms[i].code, size: 12, align: TextAlign.center), T(kForms[i].name, size: 9, color: C.dim2, align: TextAlign.center)]),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 30,
                  width: double.infinity,
                  child: Press(
                    onTap: () => Store.i.set((q) => q.form = i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: p.form == i ? const [Color(0xffe8edf5), Color(0xffaab4c4)] : const [Color(0xff9dff3a), Color(0xff4caf14)]),
                      ),
                      child: T(p.form == i ? 'انتخاب شده' : 'انتخاب', size: 11, color: const Color(0xff10200a)),
                    ),
                  ),
                ),
              ]),
          ],
        )),
      ),
    ]);
  }
}

class _MiniPitch extends CustomPainter {
  final int form;
  _MiniPitch(this.form);
  @override
  void paint(Canvas c, Size s) {
    final stripe = Paint();
    for (var i = 0; i < 8; i++) {
      stripe.color = i.isEven ? const Color(0xff3f9a2a) : const Color(0xff4caf34);
      c.drawRect(Rect.fromLTWH(0, s.height * i / 8, s.width, s.height / 8), stripe);
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xb3ffffff);
    c.drawRect(Rect.fromLTWH(3, 3, s.width - 6, s.height - 6), line);
    c.drawLine(Offset(3, s.height / 2), Offset(s.width - 3, s.height / 2), line);
    c.drawCircle(Offset(s.width / 2, s.height / 2), s.width * .14, line);
    c.drawRect(Rect.fromLTWH(s.width * .3, s.height - 3 - s.height * .1, s.width * .4, s.height * .1), line);
    final dot = Paint()..color = const Color(0xffff3434);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white;
    for (final pt in slots(form)) {
      final o = Offset(8 + pt[0] * (s.width - 16), s.height - pt[1] * s.height * 1.9 - 4);
      c.drawCircle(o, 4.5, dot);
      c.drawCircle(o, 4.5, rim);
    }
  }

  @override
  bool shouldRepaint(_MiniPitch o) => o.form != form;
}
