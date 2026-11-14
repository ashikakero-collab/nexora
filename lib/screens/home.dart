// Home hub (Arcade tab): the owner's current hub design (search, portal world of seven gates, featured world
// card with Enter) merged with the RN Home (selected disc hero, quick match, quick actions, daily reward, challenges).
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../oracle/avatar.dart';
import '../oracle/oracle.dart';
import '../tutorial/keys.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import '../ui/v4.dart';

class World {
  final String key, name, fa, sub, img;
  final Color color;
  const World(this.key, this.name, this.fa, this.sub, this.img, this.color);
}

final kWorlds = [
  World('arcade', 'NEXORA ARCADE', 'آرکید نکسورا', 'بازی سریع، جام، چالش کهکشانی و دو نفره', ui('portal_gamepad'), const Color(0xff4d8dff)),
  World('online', 'ORBIT NETWORK', 'شبکه‌ی مدار', 'بازی آنلاین، آرنا، رتبه‌ها و تورنمنت‌ها', ui('portal_globe'), const Color(0xff42dccb)),
  World('social', 'SOCIAL STATION', 'ایستگاه اجتماعی', 'گفتگو، گروه‌ها، باشگاه‌ها و دوستان', ui('portal_friends'), const Color(0xff4ed9c2)),
  World('oracle', 'ORACLE CORE', 'هسته‌ی اوراکل', 'دستیار هوشمند، راهنما و مربی', ui('portal_brain'), const Color(0xffc18bff)),
  World('profile', 'PERSONAL ORBIT', 'مدار شخصی', 'پروفایل، آمار و دستاوردها', ui('portal_profile'), const Color(0xff67b8ff)),
  World('shop', 'NEXORA EXCHANGE', 'بازار نکسورا', 'دیسک‌ها، توپ‌ها، زمین‌ها و صندوقچه‌ها', ui('portal_shop'), const Color(0xffa58bff)),
  World('gallery', 'NOVA GALLERY', 'گالری نوا', 'تیم من: دیسک، توپ، زمین و ترکیب', ui('portal_galaxy'), const Color(0xff8b6cff)),
];

class HomeScreen extends StatefulWidget {
  final double top, bottom;
  final void Function(String world) onWorld;
  final VoidCallback onQuick, onDaily, onChest;
  final VoidCallback? onShop, onSocial, onRank, onSettings, onOracle;
  final bool dailyReady, chestReady;
  const HomeScreen(
      {super.key,
      required this.top,
      required this.bottom,
      required this.onWorld,
      required this.onQuick,
      required this.onDaily,
      required this.onChest,
      required this.dailyReady,
      required this.chestReady,
      this.onShop,
      this.onSocial,
      this.onRank,
      this.onSettings,
      this.onOracle});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// v4 home (owner mockup): Oracle robot + NEXORA title hero, Quick Match pill, a row of five neon icon tiles
/// (shop, friends, rank, daily gift, settings), the level/XP card, quick world cards, daily reward, challenges.
class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final k = uiK(context);
    final w = MediaQuery.sizeOf(context).width;
    final p = Store.i.p, me = teamById(p.team);
    final lv = level(p.xp), lg = league(p.trophies);
    final heroH = (w * .72).clamp(240.0, 340.0);
    final tile = ((w - 32) / 5 - 20).clamp(42.0, 64.0); // each tile column is tile + 18 wide (label)
    return ListView(padding: EdgeInsets.only(top: widget.top, bottom: widget.bottom + SP.l), children: [
      // hero: planet glow, animated Oracle, NEXORA logo
      SizedBox(
        height: heroH,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            right: -w * .12,
            top: heroH * .02,
            width: w * .8,
            child: Opacity(opacity: .55, child: FloatY(amp: 5, ms: 5200, child: Image.asset(V4.heroPlanet, fit: BoxFit.contain))),
          ),
          Positioned(
            left: 4,
            bottom: 0,
            child: OracleAvatar(size: math.min(heroH * .9, w * .62), onTap: widget.onOracle),
          ),
          Positioned(
            right: 10,
            top: heroH * .14,
            width: w * .44,
            child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
              FloatY(amp: 4, ms: 3600, child: NexoraLogo(width: w * .42)),
              const SizedBox(height: 6),
              T('FINGER SOCCER', size: 9.5 * k, family: F.head, weight: 700, spacing: 2.2, color: N.amber, align: TextAlign.center, lines: 1),
              const SizedBox(height: 4),
              T('سلام ${p.name}! آماده‌ی یک مسابقه‌ای؟', size: 12 * k, color: const Color(0xffdfe6ff), align: TextAlign.center, lines: 2),
            ]),
          ),
        ]),
      ),
      // quick match
      Padding(
        padding: const EdgeInsets.fromLTRB(SP.l, SP.s, SP.l, 0),
        child: KeyedSubtree(
          key: TourKeys.quick,
          child: NeonButton('بازی سریع', sub: 'QUICK MATCH · ${me.name.toUpperCase()}', iconData: Icons.play_arrow_rounded, pulse: true, onTap: widget.onQuick),
        ),
      ),
      // five neon tiles
      Padding(
        padding: const EdgeInsets.fromLTRB(SP.l, SP.l, SP.l, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, textDirection: TextDirection.rtl, children: [
          NeonIconButton(key: TourKeys.shop, icon: V4.ic('bag'), label: 'فروشگاه', size: tile, onTap: widget.onShop ?? () => widget.onWorld('shop')),
          NeonIconButton(key: TourKeys.social, icon: V4.ic('friends'), label: 'دوستان', size: tile, onTap: widget.onSocial ?? () => widget.onWorld('social')),
          NeonIconButton(key: TourKeys.rank, icon: V4.ic('trophy'), label: 'رتبه‌ها', size: tile, onTap: widget.onRank ?? () => widget.onWorld('online')),
          NeonIconButton(key: TourKeys.gift, icon: V4.ic('gift'), label: 'جایزه', size: tile, badge: widget.dailyReady, selected: widget.dailyReady, onTap: widget.onDaily),
          NeonIconButton(key: TourKeys.settings, icon: V4.ic('gear'), label: 'تنظیمات', size: tile, onTap: widget.onSettings ?? () => toast('به‌زودی')),
        ]),
      ),
      // level / XP card
      Padding(
        padding: const EdgeInsets.fromLTRB(SP.l, SP.l, SP.l, 0),
        child: NeonPanel(
          key: TourKeys.level,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(textDirection: TextDirection.rtl, children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(colors: [Color(0xff2a1a5a), Color(0xff0a0f30)]),
                border: Border.all(color: N.orange, width: 2),
                boxShadow: glow(N.orange, 10, .5),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const T('LV', size: 8, family: F.head, weight: 700, color: N.amber),
                T('${lv.level}', size: 18, family: F.num, weight: 800, color: Colors.white),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(textDirection: TextDirection.rtl, children: [
                  tBold('سطح ${fa(lv.level)}', size: 14),
                  const Spacer(),
                  T('${en(lv.cur)} / ${en(lv.need)} XP', size: 11, family: F.num, weight: 700, color: N.amber),
                ]),
                const SizedBox(height: 6),
                Bar(v: lv.need > 0 ? lv.cur / lv.need : 0, h: 9, color: N.amber, color2: N.orange2),
                const SizedBox(height: 6),
                Row(textDirection: TextDirection.rtl, children: [
                  Img(V4.h('trophy'), w: 20, h: 20),
                  const SizedBox(width: 4),
                  T('${fa(p.trophies)} · لیگ ${kLeagueFa[lg.name]}', size: 11, color: C.dim),
                  const Spacer(),
                  T('${fa(p.wins)} برد · ${fa(p.played)} بازی', size: 11, color: C.dim),
                ]),
              ]),
            ),
          ]),
        ),
      ),
      // quick world cards
      Padding(
        padding: const EdgeInsets.fromLTRB(SP.m, SP.l, SP.m, 0),
        child: Row(textDirection: TextDirection.rtl, children: [
          _quick(V4.holoBall, 'آنلاین', 'ONLINE', () => widget.onWorld('online')),
          _quick(V4.h('trophy'), 'جام نکسورا', 'CUP', () => widget.onWorld('cup')),
          _quick(V4.h('shield'), 'تیم من', 'TEAM', () => widget.onWorld('gallery')),
          _quick(V4.h('chest'), 'صندوقچه', 'CHEST', widget.onChest, dot: widget.chestReady),
        ]),
      ),
      Section(
        title: 'جایزه‌ی روزانه',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SP.l),
          child: Press(
            onTap: widget.onDaily,
            scaleTo: .98,
            child: Panel(
              accent: widget.dailyReady ? C.gold : Colors.transparent,
              glowOn: widget.dailyReady,
              child: Row(textDirection: TextDirection.rtl, children: [
                Img(V4.h('gift'), w: 46, h: 46),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SP.m),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      tBold(widget.dailyReady ? 'جایزه‌ی امروز آماده‌ست!' : 'روز ${fa(p.streak)} از ۷', size: 14),
                      T(widget.dailyReady ? 'سکه‌ی رایگان؛ هر روز بزرگ‌تر' : 'فردا دوباره سر بزن', size: 11, color: C.dim),
                    ]),
                  ),
                ),
                SizedBox(width: 92, child: NeonButton(widget.dailyReady ? 'دریافت' : 'جزئیات', small: true, kind: widget.dailyReady ? NeonKind.primary : NeonKind.ghost, onTap: widget.onDaily)),
              ]),
            ),
          ),
        ),
      ),
      Section(title: 'چالش‌های امروز', action: 'همه ›', onAction: () => widget.onWorld('challenges'), child: const Padding(padding: EdgeInsets.symmetric(horizontal: SP.l), child: HomeChallenges())),
    ]);
  }

  Widget _quick(String img, String label, String en, VoidCallback on, {bool dot = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SP.xs),
          child: Press(
            onTap: on,
            child: SizedBox(
              height: 104,
              child: NeonPanel(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                radius: 18,
                rim: const [Color(0xaaff8a2a), Color(0x88ff4f9a), Color(0xaa4f7dff)],
                child: Stack(alignment: Alignment.center, children: [
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Img(img, w: 54, h: 54),
                    const SizedBox(height: 2),
                    tBold(label, size: 11, lines: 1),
                    T(en, size: 7.5, family: F.head, weight: 700, spacing: 1.5, color: N.amber, lines: 1),
                  ]),
                  if (dot) Positioned(top: 2, right: 4, child: Container(width: 9, height: 9, decoration: const BoxDecoration(color: C.red, shape: BoxShape.circle))),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Seven gates on an elliptical platform; the selected gate is centred, larger and lit.
class _PortalWorld extends StatelessWidget {
  final int sel;
  final double drag;
  final ValueChanged<int> onSel;
  const _PortalWorld({required this.sel, required this.drag, required this.onSel});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final n = kWorlds.length;
      final items = <(double, Widget)>[];
      for (var i = 0; i < n; i++) {
        var rel = (i - sel) % n;
        if (rel > n / 2) rel -= n;
        final a = rel / n * 2 * math.pi + drag / 220;
        final x = w / 2 + math.sin(a) * w * .40;
        final depth = (math.cos(a) + 1) / 2; // 1 = front
        final y = h * .30 + depth * h * .26;
        final s = .45 + depth * .55;
        final gw = w * .34 * s;
        final world = kWorlds[i];
        items.add((
          depth,
          Positioned(
            left: x - gw / 2,
            top: y - gw * .6,
            width: gw,
            height: gw * 1.25,
            child: GestureDetector(
              onTap: () => onSel(i),
              child: Opacity(
                opacity: .45 + depth * .55,
                child: Stack(alignment: Alignment.bottomCenter, children: [
                  if (i == sel) Positioned.fill(child: Pulse(size: gw * .8, color: world.color.withValues(alpha: .35))),
                  Img(world.img, w: gw, h: gw * 1.25),
                ]),
              ),
            ),
          ),
        ));
      }
      items.sort((a, b) => a.$1.compareTo(b.$1));
      return Stack(clipBehavior: Clip.none, children: [
        Positioned(left: w * .02, right: w * .02, top: h * .52, child: Img(menu('pedestal'), w: w * .96, h: h * .42, opacity: .95)),
        Positioned(left: w * .3, right: w * .3, top: h * .02, child: Img(ui2('portal'), w: w * .4, h: h * .34, opacity: .5)),
        for (final it in items) it.$2,
      ]);
    });
  }
}

/// Daily challenges summary (signed in) for Home.
class HomeChallenges extends StatefulWidget {
  const HomeChallenges({super.key});
  @override
  State<HomeChallenges> createState() => _HomeChallengesState();
}

class _HomeChallengesState extends State<HomeChallenges> {
  List<Rec>? list;
  String? err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (Auth.i.uid == null) {
      setState(() => err = 'offline');
      return;
    }
    try {
      final l = await loadChallenges();
      if (mounted) setState(() => list = l);
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  Future<void> claim(Rec c) async {
    try {
      final r = Rec.of(await rpc('claim_challenge', {'p_def': c.s('def_id')}));
      toast('+${fa(r.i('gems'))} الماس · +${fa(r.i('xp'))} XP', 'ok');
      Auth.i.refreshProfile();
      _load();
    } catch (e) {
      toast(errFa(e), 'err');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (err == 'offline') {
      return Panel(accent: Colors.transparent, child: Row(textDirection: TextDirection.rtl, children: [
        Img(kit('calendar'), w: 40, h: 40),
        const SizedBox(width: 8),
        const Expanded(child: T('برای چالش‌های روزانه و الماس، وارد بخش آنلاین شو (حتی به‌صورت مهمان).', size: 12, color: C.dim)),
      ]));
    }
    if (err != null) return T(err!, size: 12, color: C.dim, align: TextAlign.center);
    if (list == null) return const Center(child: Padding(padding: EdgeInsets.all(12), child: Spinner(size: 22)));
    return Column(children: [
      for (final c in list!.take(4))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            accent: Colors.transparent,
            padding: const EdgeInsets.all(10),
            child: Row(textDirection: TextDirection.rtl, children: [
              Img(c.b('claimed') ? kit('star') : kit('calendar'), w: 34, h: 34),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  tBold(c.s('title_fa'), size: 13, lines: 1),
                  const SizedBox(height: 4),
                  Bar(v: c.i('target') > 0 ? c.i('progress') / c.i('target') : 0, h: 6, color: c.b('claimed') ? C.green : C.cyan),
                  const SizedBox(height: 2),
                  T('${fa(math.min(c.i('progress'), c.i('target')))}/${fa(c.i('target'))} · 💎${fa(c.i('reward_gems'))}', size: 10, color: C.dim),
                ]),
              ),
              const SizedBox(width: 8),
              if (!c.b('claimed') && c.i('progress') >= c.i('target')) SizedBox(width: 84, child: Btn('دریافت', small: true, colors: G.gold, onTap: () => claim(c))),
            ]),
          ),
        ),
    ]);
  }
}
