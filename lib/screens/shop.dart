// Port of src/screens/Shop.tsx (legend discs, chests, daily deals, catalogue) laid out like the shop mockup
// (category tabs + items on glowing pedestals), plus the chest-opening and daily-reward cards from App.tsx.
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/owned.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../game/meta.dart';
import '../net/auth.dart';
import '../net/discs.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import '../ui/v4.dart';
import 'team.dart' show StatBars;

const _rc = [Color(0xff8ea3d6), Color(0xff4fe3ff), Color(0xffb46bff), Color(0xffffd257)];

String fmtLeft(int ms) {
  final m = (ms / 60000).ceil(), h = m ~/ 60;
  return h > 0 ? '${fa(h)}س ${fa(m % 60)}د' : '${fa(m)} دقیقه';
}

class ShopScreen extends StatefulWidget {
  final void Function(bool premium) onChest;
  const ShopScreen({super.key, required this.onChest});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  String kind = 'team';
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void buy(Item it) {
    final p = Store.i.p;
    if (p.coins < it.price) {
      toast('سکه کافی نداری', 'err');
      buzz('medium');
      return;
    }
    Store.i.set((q) {
      q.coins -= it.price;
      grant(it, q);
    });
    sfx(Snd.goal);
    buzz('success');
    toast('${it.name} باز شد!', 'ok');
  }

  String tcat = 'vip';

  bool _owns(Item it) => switch (it.kind) { ItemKind.ball => ownsBall(it.idx), ItemKind.field => ownsField(it.idx), ItemKind.goal => ownsGoal(it.idx), ItemKind.team => ownsTeam(it.id) };

  bool _equipped(Item it, Profile p) => switch (it.kind) { ItemKind.ball => p.ball == it.idx, ItemKind.field => p.field == it.idx, ItemKind.goal => p.goal == it.idx, ItemKind.team => p.team == it.id };

  void _equip(Item it) {
    Store.i.set((q) {
      if (it.kind == ItemKind.ball) q.ball = it.idx;
      if (it.kind == ItemKind.field) q.field = it.idx;
      if (it.kind == ItemKind.team) q.team = it.id;
      if (it.kind == ItemKind.goal) q.goal = it.idx;
    });
    buzz('success');
    toast('${it.name} انتخاب شد', 'ok');
  }

  void _equipTeam(Team t) {
    Store.i.set((q) => q.team = t.id);
    if (Auth.i.uid != null && Discs.i.catalog.containsKey(t.id)) Discs.i.equip(t.id);
    buzz('success');
    toast('${t.name} انتخاب شد', 'ok');
  }

  void _buyTeam(Team t) {
    final (cost, gem) = teamCost(t);
    if (gem) {
      buyDisc(t.id, t.name);
      return;
    }
    if (Store.i.p.coins < cost) {
      toast('سکه کافی نداری', 'err');
      return;
    }
    Store.i.set((q) {
      q.coins -= cost;
      q.ownedTeams = [...q.ownedTeams, t.id];
      q.team = t.id;
    });
    sfx(Snd.goal);
    toast('${t.name} باز شد!', 'ok');
  }

  Future<void> buyDisc(String id, String name) => Discs.i.buyAndEquip(id, name, onEquipped: (id) {
        Store.i.set((q) => q.team = id);
        sfx(Snd.win);
        buzz('success');
      });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        const SpaceBg(image: V4.bgPanel, dim: .05),
        ListenableBuilder(
          listenable: Listenable.merge([Store.i, Discs.i, Auth.i]),
          builder: (_, __) {
            final p = Store.i.p, dz = Discs.i;
            final deals = dailyDeals(p);
            final legends = kTeams.where((t) => t.cat == 'leg').toList();
            final now = DateTime.now().millisecondsSinceEpoch, freeIn = (p.lastChest + kChestEvery - now).clamp(0, kChestEvery);
            final list = allItems(p, all: true).where((i) => i.kind.name == kind).toList();
            final shopTeams = [for (final t in kTeams) if (teamCost(t).$1 > 0) t];
            final cell = (w - 32 - 16) / 3;
            final hero = legends[(now ~/ 86400000) % legends.length];
            return ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 20), children: [
              Header(title: 'بازار نکسورا', en: 'NEXORA EXCHANGE · SHOP', onBack: () => Navigator.pop(context), right: Pill(icon: menu('g_coin'), v: en(p.coins), tint: C.gold)),
              // category tabs (mockup: gift / ball / kit / boots / energy)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(textDirection: TextDirection.rtl, children: [
                  for (final (k, icon, label) in [('team', V4.h('shield'), 'دیسک'), ('ball', V4.h('ball'), 'توپ'), ('field', V4.h('stadium'), 'زمین'), ('goal', V4.h('trophy'), 'دروازه'), ('chest', V4.h('chest'), 'صندوقچه')])
                    Expanded(
                      child: Press(
                        onTap: () => setState(() => kind = k),
                        child: Container(
                          height: 64,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kind == k ? N.orange : C.line, width: kind == k ? 1.6 : 1),
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: kind == k ? const [Color(0x66ff8a2a), Color(0xcc0a1236)] : const [Color(0x99142060), Color(0xcc080c22)]),
                            boxShadow: kind == k ? glow(N.orange, 12, .5) : null,
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Img(icon, w: 36, h: 36), T(label, size: 10, color: kind == k ? Colors.white : C.dim)]),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              // legends banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: C.gold.withValues(alpha: .5)),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff3b1a00), Color(0xff1a0d3a), Color(0xff070a22)]),
                  ),
                  child: Row(children: [
                    Padding(padding: const EdgeInsets.all(10), child: FloatY(child: Stack(alignment: Alignment.bottomCenter, children: [Img(menu('pedestal'), w: 130, h: 50), Padding(padding: const EdgeInsets.only(bottom: 18), child: Img(teamImg(hero), w: 104, h: 104))]))),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                          tHead('LEGENDARY DISCS', size: 9, color: C.gold),
                          tTitle('دیسک‌های افسانه‌ای', size: 19),
                          const T('قدرت و دقت بالا · با الماس', size: 11, color: Color(0xffe8d7ad)),
                          const SizedBox(height: 6),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(10)), child: tBold('محدود', size: 11, color: const Color(0xff1b0e00))),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              SizedBox(
                height: 170,
                child: ListView(scrollDirection: Axis.horizontal, reverse: true, padding: const EdgeInsets.fromLTRB(12, 10, 12, 0), children: [
                  for (final t in legends)
                    Press(
                      onTap: dz.has(t.id) ? null : () => buyDisc(t.id, t.name),
                      child: Opacity(
                        opacity: dz.has(t.id) ? .6 : 1,
                        child: Container(
                          width: 120,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: C.gold.withValues(alpha: .4)), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x40ffd257), Color(0xe60a0c22)])),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Img(teamImg(t), w: 92, h: 92),
                            tBold(t.name, size: 11, lines: 1),
                            dz.has(t.id) ? const T('✓ داری', size: 11, color: C.green) : _Price(v: dz.price(t.id), gem: true),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
              const TitleBar('صندوقچه‌ها', en: 'SUPPLY CHESTS', accent: C.violet),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(textDirection: TextDirection.rtl, children: [
                  Expanded(child: _ChestCard(img: kit('chest'), title: 'صندوقچه‌ی رایگان', sub: 'هر ۴ ساعت', accent: C.cyan, ready: freeIn == 0, btn: Btn(freeIn > 0 ? fmtLeft(freeIn) : 'باز کن', small: true, disabled: freeIn > 0, onTap: () => widget.onChest(false)))),
                  Expanded(
                      child: _ChestCard(img: world('crate'), title: 'صندوقچه‌ی سلطنتی', sub: 'آیتم کمیاب تضمینی‌تر', accent: C.gold, ready: true, btn: Btn('۶۰۰ سکه', small: true, icon: ui2('c_coin'), colors: G.violet, onTap: () {
                    if (p.coins < 600) return toast('۶۰۰ سکه لازمه', 'err');
                    widget.onChest(true);
                  }))),
                ]),
              ),
              if (deals.isNotEmpty) const TitleBar('پیشنهاد امروز', en: 'DAILY DEALS · -30%', accent: C.green),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(textDirection: TextDirection.rtl, spacing: 8, runSpacing: 8, children: [
                  for (final it in deals)
                    SizedBox(
                      width: (w - 32 - 8) / 2,
                      child: Press(
                        onTap: () => buy(it),
                        child: Panel(
                          accent: _rc[it.rar],
                          padding: const EdgeInsets.all(10),
                          child: Row(textDirection: TextDirection.rtl, children: [
                            it.kind == ItemKind.field ? Img(it.img, w: 40, h: 54, fit: BoxFit.cover, radius: 6) : ClipOval(child: Img(it.img, w: 54, h: 54)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                tBold(it.name, size: 12, lines: 1),
                                Container(padding: const EdgeInsets.symmetric(horizontal: 6), decoration: BoxDecoration(color: C.green, borderRadius: BorderRadius.circular(8)), child: tBold('-۳۰٪', size: 10, color: const Color(0xff03140c))),
                                _Price(v: it.price),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
              const TitleBar('همه‌ی تجهیزات', en: 'CATALOGUE'),
              if (kind == 'chest')
                const EmptyState('صندوقچه‌ها را از بخش بالا باز کن.')
              else if (kind == 'team') ...[
                if (Auth.i.profile == null)
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: T('قیمت دیسک‌ها به الماس است؛ با ورود آنلاین (حتی مهمان) ۱۵۰ الماس هدیه می‌گیری.', size: 11, color: C.dim, align: TextAlign.right)),
                // v4: the disc catalogue is the game's own team list (every entry has art + data and is playable);
                // gem prices come from the online catalog when it sells the disc, otherwise coins.
                SizedBox(
                  height: 44,
                  child: ListView(scrollDirection: Axis.horizontal, reverse: true, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                    for (final c in kCats)
                      if (shopTeams.any((t) => t.cat == c.k)) Chip2(c.name, on: tcat == c.k, onTap: () => setState(() => tcat = c.k)),
                  ]),
                ),
                const SizedBox(height: 8),
                _grid(cell, [
                  for (final t in shopTeams.where((t) => t.cat == (shopTeams.any((x) => x.cat == tcat) ? tcat : shopTeams.first.cat)))
                    _Pedestal(
                      onTap: () => ownsTeam(t.id) ? _equipTeam(t) : _buyTeam(t),
                      color: _rc[rarity(t)],
                      img: teamImg(t),
                      cell: cell,
                      round: true,
                      name: p.team == t.id ? '● ${t.name}' : t.name,
                      extra: StatBars(power: dz.stats(t.id).power, accuracy: dz.stats(t.id).accuracy, compact: true),
                      price: _Price(v: teamCost(t).$1, gem: teamCost(t).$2),
                    ),
                ]),
              ] else ...[
                _grid(cell, [
                  for (final it in list.take(80))
                    _Pedestal(
                        onTap: () => _owns(it) ? _equip(it) : buy(it),
                        color: _rc[it.rar],
                        img: it.img,
                        cell: cell,
                        round: it.kind != ItemKind.field && it.kind != ItemKind.goal,
                        wide: it.kind == ItemKind.goal,
                        name: _equipped(it, p) ? '● ${it.name}' : it.name,
                        price: it.price == 0 ? const T('رایگان', size: 10, color: C.green) : _Price(v: it.price)),
                ]),
                if (list.isEmpty) const EmptyState('همه‌چیز این بخش رو داری، اسطوره!'),
              ],
            ]);
          },
        ),
      ]),
    );
  }

  Widget _grid(double cell, List<Widget> kids) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(textDirection: TextDirection.rtl, spacing: 8, runSpacing: 8, children: [for (final k in kids) SizedBox(width: cell, child: k)]),
      );
}

class _Pedestal extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;
  final String img, name;
  final double cell;
  final bool round, wide;
  final Widget? extra;
  final Widget price;
  const _Pedestal({required this.onTap, required this.color, required this.img, required this.cell, required this.round, required this.name, this.extra, required this.price, this.wide = false});
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        scaleTo: .93,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: .4)),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: .19), const Color(0x33080c22)]),
          ),
          child: Column(children: [
            SizedBox(
              height: cell * .78,
              child: Stack(alignment: Alignment.bottomCenter, children: [
                Positioned(bottom: 0, child: Img(menu('pedestal'), w: cell * .9, h: cell * .3, opacity: .9)),
                Positioned(
                    bottom: cell * .1,
                    child: wide
                        ? Img(img, w: cell * .9, h: cell * .5, fit: BoxFit.contain)
                        : round
                            ? ClipOval(child: Img(img, w: cell * .6, h: cell * .6))
                            : Img(img, w: cell * .48, h: cell * .64, fit: BoxFit.cover, radius: 6)),
              ]),
            ),
            const SizedBox(height: 4),
            tBold(name, size: 10, lines: 1),
            if (extra != null) extra!,
            price,
          ]),
        ),
      );
}

class _Price extends StatelessWidget {
  final int v;
  final bool gem;
  const _Price({required this.v, this.gem = false});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xb3060a1e), borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Img(gem ? ui2('x_gem') : ui2('c_coin'), w: 16, h: 16), const SizedBox(width: 3), T('$v', size: 10, family: F.head, weight: 700, color: gem ? const Color(0xff9fd8ff) : C.gold)]),
      );
}

class _ChestCard extends StatelessWidget {
  final String img, title, sub;
  final Color accent;
  final bool ready;
  final Widget btn;
  const _ChestCard({required this.img, required this.title, required this.sub, required this.accent, required this.ready, required this.btn});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(4),
        child: Panel(
          accent: accent,
          glowOn: ready,
          child: Column(children: [
            ready ? _Shake(child: Img(img, w: 96, h: 96)) : Img(img, w: 96, h: 96),
            tBold(title, size: 13),
            T(sub, size: 10, color: C.dim),
            const SizedBox(height: 8),
            btn,
          ]),
        ),
      );
}

class _Shake extends StatefulWidget {
  final Widget child;
  const _Shake({required this.child});
  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2150))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: c,
          child: widget.child,
          builder: (_, ch) {
            final t = c.value * 2150;
            final r = t < 320 ? [1, -1, 1, 0][(t / 80).floor().clamp(0, 3)] * .1 : 0.0;
            return Transform.rotate(angle: r.toDouble(), child: ch);
          },
        ),
      );
}

/// Chest opening card (ChestOpen in Shop.tsx).
class ChestOpen extends StatefulWidget {
  final ChestPrize prize;
  final bool premium;
  const ChestOpen({super.key, required this.prize, required this.premium});
  @override
  State<ChestOpen> createState() => _ChestOpenState();
}

class _ChestOpenState extends State<ChestOpen> {
  bool open = false;
  Timer? t;
  @override
  void initState() {
    super.initState();
    t = Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() => open = true);
      sfx(Snd.goal);
      buzz('heavy');
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.prize.item;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        tTitle(widget.premium ? 'صندوقچه‌ی سلطنتی' : 'صندوقچه‌ی رایگان', size: 20),
        SizedBox(
          height: 220,
          child: Stack(alignment: Alignment.center, children: [
            Spin(ms: 9000, child: Img(ui2('ring'), w: 220, h: 220, opacity: open ? .8 : .3)),
            Pulse(size: 140, color: widget.premium ? const Color(0x66ffd257) : const Color(0x664fe3ff)),
            if (!open)
              _Shake(child: Img(widget.premium ? world('crate') : kit('chest'), w: 170, h: 170))
            else
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (_, v, ch) => Opacity(opacity: v.clamp(0, 1), child: Transform.scale(scale: .3 + v * .7, child: ch)),
                child: it != null
                    ? (it.kind == ItemKind.field ? Img(it.img, w: 110, h: 150, fit: BoxFit.cover, radius: 12) : ClipOval(child: Img(it.img, w: 150, h: 150)))
                    : Img(ui2('x_coins'), w: 150, h: 150),
              ),
          ]),
        ),
        if (open) ...[
          if (it != null) tTitle(it.name, size: 18, color: _rc[it.rar]),
          T([if (it != null) 'آیتم جدید باز شد!', if (widget.prize.coins > 0) '+${fa(widget.prize.coins)} سکه', if (widget.prize.gems > 0) '+${fa(widget.prize.gems)} الماس'].join(' · '), size: 14, color: C.dim, align: TextAlign.center),
          const SizedBox(height: 16),
          Btn('عالیه!', colors: G.gold, onTap: () => Navigator.pop(context)),
        ] else
          const T('در حال باز شدن...', size: 14, color: C.dim),
      ]),
    );
  }
}

const kDay = 86400000;

/// Daily reward card (DailyCard in App.tsx).
class DailyCard extends StatelessWidget {
  final bool ready;
  final int streak, lastDaily;
  final VoidCallback onClaim;
  const DailyCard({super.key, required this.ready, required this.streak, required this.lastDaily, required this.onClaim});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = ready ? (now - lastDaily < 2 * kDay ? (streak % 7) + 1 : 1) : streak;
    final left = (lastDaily + kDay - now).clamp(0, kDay), h = left ~/ 3600000, m = ((left % 3600000) / 60000).ceil();
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Img(kit('calendar'), w: 96, h: 96),
        tTitle('جایزه‌ی روزانه', size: 21),
        const T('هر روز سر بزن، جایزه‌ها بزرگ‌تر می‌شن', size: 12, color: C.dim),
        const SizedBox(height: 14),
        Wrap(textDirection: TextDirection.rtl, alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < kDaily.length; i++)
            Builder(builder: (_) {
              final day = i + 1, got = ready ? day < next : day <= next, cur = ready && day == next;
              return Container(
                width: day == 7 ? 132 : 62,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cur ? C.gold : got ? C.green : C.line),
                  color: cur ? const Color(0x29ffd257) : got ? const Color(0x1a3dffa8) : const Color(0xcc080c22),
                  boxShadow: cur ? glow(C.gold, 10, .8) : null,
                ),
                child: Stack(children: [
                  Center(
                    child: Column(children: [
                      T('روز ${fa(day)}', size: 10, color: cur ? C.gold : C.dim),
                      Img(day == 7 ? kit('chest') : kit('coin'), w: 34, h: 34),
                      tBold(fa(kDaily[i].$1), size: 10),
                    ]),
                  ),
                  if (got) const Positioned(top: 0, left: 4, child: Icon(Icons.check_circle_rounded, size: 16, color: C.green)),
                ]),
              );
            }),
        ]),
        const SizedBox(height: 16),
        ready ? Btn('دریافت جایزه‌ی روز ${fa(next)}', colors: G.gold, onTap: onClaim) : Btn('جایزه‌ی بعدی: ${fa(h)}س ${fa(m)}د', small: true, colors: G.dark, onTap: () => Navigator.pop(context)),
      ]),
    );
  }
}
