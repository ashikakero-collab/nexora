// App chrome: toast, bottom sheet, modal card, top HUD and bottom navigation (port of src/ui/Chrome.tsx,
// restyled after the owner's current hub screenshot: avatar + coins + Lv on top, Arcade/Chat/Reward/Shop/Menu below).
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../tutorial/keys.dart';
import 'kit.dart';
import 'v4.dart';

final navKey = GlobalKey<NavigatorState>();

// ---------------- toast ----------------
OverlayEntry? _toastEntry;
Timer? _toastTimer;
final List<void Function(String m, String k)> toastListeners = [];

void toast(String m, [String k = 'info']) {
  for (final l in toastListeners) {
    l(m, k);
  }
  final ov = navKey.currentState?.overlay;
  if (ov == null) return;
  _toastEntry?.remove();
  _toastTimer?.cancel();
  final entry = OverlayEntry(builder: (ctx) => _Toast(m: m, k: k, key: UniqueKey()));
  _toastEntry = entry;
  ov.insert(entry);
  _toastTimer = Timer(const Duration(milliseconds: 2200), () {
    if (_toastEntry == entry) {
      entry.remove();
      _toastEntry = null;
    }
  });
}

class _Toast extends StatelessWidget {
  final String m, k;
  const _Toast({super.key, required this.m, required this.k});
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 64;
    final c = k == 'err' ? C.red : k == 'ok' ? C.green : N.orange;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          builder: (_, v, ch) => Opacity(opacity: v.clamp(0, 1), child: Transform.translate(offset: Offset(0, -20 + v * 20), child: ch)),
          child: Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .9),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xf5141b4a), Color(0xf5080d2c)]),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c, width: 1.3),
                boxShadow: hq ? [BoxShadow(color: c.withValues(alpha: .35), blurRadius: 14)] : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [
                Img(k == 'err' ? kit('bell') : k == 'ok' ? kit('star') : kit('mega'), w: 26, h: 26),
                const SizedBox(width: 6),
                Flexible(child: tBold(m, size: 14)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- page transitions ----------------
Route<T> fadeRoute<T>(Widget page, {bool opaque = true}) => neonRoute<T>(page, opaque: opaque);

Future<T?> push<T>(Widget page) => navKey.currentState!.push<T>(neonRoute(page));

// ---------------- bottom sheet ----------------
Future<T?> showSheet<T>(BuildContext context, {required String title, String? en, Color accent = C.cyan, double height = .84, required Widget Function(BuildContext) child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xb801030c),
    builder: (ctx) {
      final h = MediaQuery.sizeOf(ctx).height;
      final ins = MediaQuery.paddingOf(ctx);
      return Container(
        height: (h * height).clamp(200, h - ins.top - 20),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: N.orange.withValues(alpha: .7), width: 1.4),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xff161d52), Color(0xff0b1138), Color(0xff060a24)]),
          boxShadow: hq ? [BoxShadow(color: N.orange.withValues(alpha: .25), blurRadius: 24)] : null,
        ),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 46, height: 5, decoration: BoxDecoration(gradient: const LinearGradient(colors: [N.orange, N.pink]), borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(children: [
              NeonIconButton(iconData: Icons.close_rounded, size: 40, onTap: () => Navigator.of(ctx).pop()),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (en != null) tHead(en, size: 9, color: N.amber),
                  tTitle(title, size: 20, lines: 1),
                ]),
              ),
            ]),
          ),
          Expanded(child: Padding(padding: EdgeInsets.only(bottom: ins.bottom), child: child(ctx))),
        ]),
      );
    },
  );
}

// ---------------- modal card ----------------
Future<T?> showCard<T>(BuildContext context, {Color accent = C.gold, required Widget Function(BuildContext) child, bool dismissible = true}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'x',
    barrierColor: const Color(0xcc01030c),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, _, __) => Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: (MediaQuery.sizeOf(ctx).width * .88).clamp(0, 420),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Color.lerp(accent, N.orange, .6)!, width: 1.5),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xff1a2160), Color(0xff0c1238), Color(0xff070a24)]),
            boxShadow: glow(N.orange, 30, .45),
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(26), child: SingleChildScrollView(child: child(ctx))),
        ),
      ),
    ),
    transitionBuilder: (_, a, __, ch) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .6, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: ch)),
  );
}

Future<bool> confirm(BuildContext context, String title, String body, {String yes = 'تأیید', String no = 'انصراف', Color accent = C.red}) async {
  final r = await showCard<bool>(context,
      accent: accent,
      child: (ctx) => Padding(
            padding: const EdgeInsets.all(SP.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              tTitle(title, size: 20, align: TextAlign.center),
              const SizedBox(height: SP.s),
              T(body, size: 12, color: C.dim, align: TextAlign.center),
              const SizedBox(height: SP.l),
              Btn(no, onTap: () => Navigator.pop(ctx, false)),
              const SizedBox(height: SP.s),
              Btn(yes, small: true, colors: G.red, onTap: () => Navigator.pop(ctx, true)),
            ]),
          ));
  return r == true;
}

// ---------------- top HUD (v4) ----------------
/// Profile chip (avatar in an orange neon ring, name, level bar) + currency pills (coins, gems). Tour keys attached.
class Hud extends StatelessWidget {
  final VoidCallback onProfile, onShop, onDaily, onOracle;
  final bool dailyReady;
  const Hud({super.key, required this.onProfile, required this.onShop, required this.onDaily, required this.onOracle, required this.dailyReady});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Store.i, Auth.i]),
      builder: (context, _) {
        final p = Store.i.p, prof = Auth.i.profile;
        final lp = prof != null ? levelProgress(prof.i('xp')) : null;
        final local = level(p.xp);
        final lvl = lp?.level ?? local.level;
        final frac = lp != null ? lp.frac : local.cur / local.need;
        final name = prof?.s('username') ?? p.name;
        final avatar = prof != null ? (prof.str('avatar_url') ?? teamImgById(prof.s('equipped_disc', 'club0'))) : teamImg(teamById(p.team));
        final gems = prof?.i('gems') ?? p.gems;
        final top = MediaQuery.paddingOf(context).top;
        return Container(
          padding: EdgeInsets.fromLTRB(12, top + 6, 12, 10),
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xe6050822), Color(0x80050822), Color(0x00050822)])),
          child: Row(children: [
            Flexible(
              child: Press(
                key: TourKeys.profile,
                onTap: onProfile,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(2.2),
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: const SweepGradient(colors: [N.orange, N.pink, N.blue, N.orange]), boxShadow: glow(N.orange, 10, .5)),
                    child: Disc(avatar, size: 44, ring: N.navy),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        tBold(name, size: 14, lines: 1),
                        const SizedBox(height: 3),
                        Row(children: [
                          T('Lv $lvl', size: 10, family: F.num, weight: 700, color: N.amber),
                          const SizedBox(width: 5),
                          Expanded(child: Bar(v: frac, h: 5, color: N.amber, color2: N.orange2)),
                        ]),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            Row(key: TourKeys.currencies, mainAxisSize: MainAxisSize.min, children: [
              NeonPill(icon: menu('g_coin'), text: en(p.coins), color: C.gold, onTap: onShop, plus: true),
              const SizedBox(width: 6),
              NeonPill(icon: V4.ic('gem'), text: en(gems), color: const Color(0xffff9ad0), onTap: onShop),
            ]),
          ]),
        );
      },
    );
  }
}

// ---------------- bottom navigation ----------------
enum Tab { arcade, chat, reward, shop, menu }

const kTabs = [
  (Tab.arcade, 'Arcade', 'بازی', Icons.sports_esports_rounded),
  (Tab.chat, 'Chat', 'گفتگو', Icons.forum_rounded),
  (Tab.reward, 'Reward', 'جایزه', Icons.redeem_rounded),
  (Tab.shop, 'Shop', 'فروشگاه', Icons.storefront_rounded),
  (Tab.menu, 'Menu', 'منو', Icons.menu_rounded),
];
const double kTabH = 74;

class NavBar extends StatelessWidget {
  final Tab tab;
  final ValueChanged<Tab> onTab;
  final Set<Tab> badges;
  const NavBar({super.key, required this.tab, required this.onTab, this.badges = const {}});
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final faLang = Store.i.p.lang == 'fa';
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom < 10 ? 10 : bottom),
      child: Container(
        height: kTabH - 8,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0x475ce1ff)),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xf5162256), Color(0xfa080c24)]),
          boxShadow: hq ? const [BoxShadow(color: Color(0x804c6bff), blurRadius: 20, offset: Offset(0, 4))] : null,
        ),
        child: LayoutBuilder(builder: (ctx, c) {
          final cw = c.maxWidth / kTabs.length;
          final idx = kTabs.indexWhere((t) => t.$1 == tab);
          return Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              left: idx * cw + 6,
              top: 5,
              bottom: 5,
              width: cw - 12,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x734fe3ff)),
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x474fe3ff), Color(0x1a6d5bff)]),
                ),
              ),
            ),
            Row(children: [
              for (final t in kTabs)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (t.$1 != tab) {
                        sfx(Snd.ui);
                        buzz();
                      }
                      onTab(t.$1);
                    },
                    child: Stack(alignment: Alignment.center, children: [
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        AnimatedScale(scale: t.$1 == tab ? 1.12 : 1, duration: const Duration(milliseconds: 220), child: Icon(t.$4, size: 26, color: t.$1 == tab ? Colors.white : C.dim)),
                        const SizedBox(height: 2),
                        T(faLang ? t.$3 : t.$2, size: 11, family: F.bold, weight: 800, color: t.$1 == tab ? C.cyan : C.dim),
                      ]),
                      if (badges.contains(t.$1))
                        Positioned(
                            top: 8,
                            right: cw * .26,
                            child: Container(width: 9, height: 9, decoration: BoxDecoration(color: C.red, shape: BoxShape.circle, border: Border.all(color: const Color(0xff0b1236), width: 1.5)))),
                    ]),
                  ),
                ),
            ]),
          ]);
        }),
      ),
    );
  }
}

/// Header for full-screen pages (glass back button + Persian title + English caption), SafeArea aware.
class Header extends StatelessWidget {
  final String title;
  final String? en;
  final VoidCallback onBack;
  final Widget? right;
  const Header({super.key, required this.title, this.en, required this.onBack, this.right});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(10, MediaQuery.paddingOf(context).top + 6, 14, 6),
        child: Row(children: [
          NeonIconButton(iconData: Icons.arrow_back_rounded, size: 42, onTap: onBack),
          if (right != null) ...[const SizedBox(width: 8), right!],
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (en != null) T(en!, size: 9, family: F.head, weight: 700, spacing: 2.5, color: N.amber, lines: 1),
              tTitle(title, size: 19, lines: 1, shadows: hq ? const [Shadow(color: Color(0x99ff8a2a), blurRadius: 12)] : null),
            ]),
          ),
        ]),
      );
}
