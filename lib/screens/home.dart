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
import '../oracle/oracle.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';

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
  final bool dailyReady, chestReady;
  const HomeScreen({super.key, required this.top, required this.bottom, required this.onWorld, required this.onQuick, required this.onDaily, required this.onChest, required this.dailyReady, required this.chestReady});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int sel = 2; // Social Station is the hero card in the owner's screenshot
  double drag = 0;
  final search = TextEditingController();
  String q = '';

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final world = kWorlds[sel];
    final p = Store.i.p, me = teamById(p.team);
    final matches = q.isEmpty
        ? const <World>[]
        : kWorlds.where((x) => '${x.name} ${x.fa} ${x.sub}'.toLowerCase().contains(q.toLowerCase())).toList();
    return ListView(padding: EdgeInsets.only(top: widget.top, bottom: widget.bottom + SP.l), children: [
      // search worlds, games & features
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: SP.l),
        child: TextField(
          controller: search,
          onChanged: (v) => setState(() => q = v.trim()),
          style: ts(size: 14, family: isFa(q) ? F.fa : F.body),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, color: C.dim),
            hintText: Store.i.p.lang == 'fa' ? 'جستجوی دنیاها، بازی‌ها و امکانات' : 'Search worlds, games & features',
            hintStyle: ts(size: 14, color: C.dim, family: Store.i.p.lang == 'fa' ? F.fa : F.body),
            filled: true,
            fillColor: const Color(0x4d1a2456),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0x40a0b4ff))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0x40a0b4ff))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: C.cyan)),
          ),
        ),
      ),
      if (matches.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: SP.s),
          child: Column(children: [
            for (final m in matches)
              ListRow(icon: m.img, title: m.fa, sub: m.sub, onTap: () {
                search.clear();
                setState(() => q = '');
                widget.onWorld(m.key);
              }),
          ]),
        ),
      // portal world
      GestureDetector(
        onHorizontalDragUpdate: (d) => setState(() => drag += d.delta.dx),
        onHorizontalDragEnd: (d) {
          final steps = (-drag / 70).round();
          setState(() {
            sel = (sel + steps) % kWorlds.length;
            if (sel < 0) sel += kWorlds.length;
            drag = 0;
          });
        },
        child: SizedBox(height: w * .92, child: _PortalWorld(sel: sel, drag: drag, onSel: (i) => i == sel ? widget.onWorld(kWorlds[i].key) : setState(() => sel = i))),
      ),
      // featured world card
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: SP.l),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: Container(
            key: ValueKey(sel),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: world.color.withValues(alpha: .55)),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0x99283a7a), world.color.withValues(alpha: .12), const Color(0xcc161c4a)]),
              boxShadow: glow(world.color, 18, .25),
            ),
            child: Row(children: [
              Img(world.img, w: 52, h: 60),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  T(world.name, size: 20, family: F.title, weight: 900, color: world.color, spacing: 1),
                  const SizedBox(height: 2),
                  T(world.fa, size: 13, color: C.text),
                  T(world.sub, size: 12, color: C.dim),
                ]),
              ),
              Press(
                onTap: () => widget.onWorld(world.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(color: world.color, borderRadius: BorderRadius.circular(18), boxShadow: glow(world.color, 14, .5)),
                  child: T(Store.i.p.lang == 'fa' ? 'ورود' : 'Enter', size: 17, family: F.bold, weight: 800, color: const Color(0xff071028)),
                ),
              ),
            ]),
          ),
        ),
      ),
      // selected disc hero + quick match
      const SizedBox(height: SP.l),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: SP.l),
        child: Press(
          onTap: widget.onQuick,
          scaleTo: .96,
          child: Container(
            height: 78,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: G.primary), border: Border.all(color: const Color(0x66ffffff)), boxShadow: glow(C.cyan, 18, .45)),
            child: Row(children: [
              const SizedBox(width: 12),
              FloatY(amp: 3, child: Disc(teamImg(me), size: 56, ring: Colors.white, ringW: 2)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  tTitle('شروع بازی', size: 22, shadows: const [Shadow(color: Color(0x80000028), blurRadius: 8)]),
                  tHead('QUICK MATCH · ${me.name.toUpperCase()}', size: 9, color: const Color(0xd9ffffff)),
                ]),
              ),
              Img(menu('ic_play'), w: 44, h: 44),
              const SizedBox(width: 12),
            ]),
          ),
        ),
      ),
      // quick actions
      Padding(
        padding: const EdgeInsets.fromLTRB(SP.m, SP.l, SP.m, 0),
        child: Row(textDirection: TextDirection.rtl, children: [
          _quick(kit('team'), 'آنلاین', () => widget.onWorld('online')),
          _quick(kit('cup'), 'جام نکسورا', () => widget.onWorld('cup')),
          _quick(kit('shield'), 'تیم من', () => widget.onWorld('gallery')),
          _quick(kit('chest'), 'صندوقچه', widget.onChest, dot: widget.chestReady),
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
                Img(kit('gift'), w: 44, h: 44),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SP.m),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      tBold(widget.dailyReady ? 'جایزه‌ی امروز آماده‌ست!' : 'روز ${fa(p.streak)} از ۷', size: 14),
                      T(widget.dailyReady ? 'سکه‌ی رایگان؛ هر روز بزرگ‌تر' : 'فردا دوباره سر بزن', size: 11, color: C.dim),
                    ]),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: widget.dailyReady ? C.gold : C.line)),
                  child: tBold(widget.dailyReady ? 'دریافت' : 'جزئیات', size: 12, color: widget.dailyReady ? C.gold : C.dim),
                ),
              ]),
            ),
          ),
        ),
      ),
      Section(title: 'چالش‌های امروز', action: 'همه ›', onAction: () => widget.onWorld('challenges'), child: const Padding(padding: EdgeInsets.symmetric(horizontal: SP.l), child: HomeChallenges())),
    ]);
  }

  Widget _quick(String img, String label, VoidCallback on, {bool dot = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SP.xs),
          child: Press(
            onTap: on,
            child: Container(
              height: 88,
              decoration: BoxDecoration(color: const Color(0xcc0a1030), borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
              child: Stack(alignment: Alignment.center, children: [
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [Img(img, w: 48, h: 48), const SizedBox(height: 2), tBold(label, size: 11, lines: 1)]),
                if (dot) Positioned(top: 8, right: 10, child: Container(width: 9, height: 9, decoration: const BoxDecoration(color: C.red, shape: BoxShape.circle))),
              ]),
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
