// NEXORA v4 design kit (the owner's reference art, 2026-11): deep navy/indigo space, dark glossy glass panels with
// ORANGE neon rims (optionally an orange->pink->blue gradient rim), a pill orange primary button, neon line icons,
// a raised centre Play button in the bottom nav. Everything is drawn with Canvas/gradients (no shaders) and sized
// from a ~400 dp design width with clamps, so it renders identically on 720x1600, 1080x2400, 16:9 and 20:9 phones.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/sound.dart';
import '../core/theme.dart';
import 'kit.dart';

/// v4 art (assets/g/v4/, cut from the owner's uploads by /workspace/work/v4/proc.py).
class V4 {
  static const _d = 'assets/g/v4/';
  static const bgMode = '${_d}bg_mode.webp', bgTeam = '${_d}bg_team.webp', bgSpace = '${_d}bg_space.webp';
  static const bgPortal1 = '${_d}bg_portal1.webp', bgPortal2 = '${_d}bg_portal2.webp', bgPortal3 = '${_d}bg_portal3.webp', bgPortal4 = '${_d}bg_portal4.webp';
  static const bgFrame = '${_d}bg_frame.webp', bgStadium = '${_d}bg_stadium.webp', bgPanel = '${_d}bg_panel.webp', arena = '${_d}arena.webp';
  static const logo = '${_d}logo.webp', heroPlanet = '${_d}hero_planet.webp', holoBall = '${_d}holo_ball.webp', trophy = '${_d}trophy.webp';
  static const local = '${_d}local.webp', wheel = '${_d}wheel.webp', oracle = '${_d}oracle_static.webp';
  static const cardMode = '${_d}card_mode.webp', cardModeSel = '${_d}card_mode_sel2.webp', cardTeam = '${_d}card_team.webp';
  static const panelGlass = '${_d}panel_glass.webp', panelSettings = '${_d}panel_settings.webp', btnPrimary = '${_d}btn_primary.webp';
  static const frameCircle = '${_d}frame_circle.webp', frameSquare = '${_d}frame_square.webp';
  static String ic(String k) => '${_d}ic_$k.webp'; // neon line icons: bag friends trophy gear gem gift bell sound power wifi swap compass search next exit lock locked
  static String h(String k) => '${_d}h_$k.webp'; // blue holo icons: ball trophy stadium shield players tactics gift chest calendar gear mega bell star coin gem profile
  static const all = [bgMode, bgTeam, bgSpace, bgPortal1, bgPortal2, bgPortal3, bgPortal4, bgFrame, bgStadium, logo, heroPlanet, oracle];
}

/// Neon palette of the reference art.
class N {
  static const orange = Color(0xffff8a2a);
  static const orange2 = Color(0xffff5a1f);
  static const amber = Color(0xffffb35c);
  static const pink = Color(0xffff4f9a);
  static const blue = Color(0xff4f7dff);
  static const cyan = Color(0xff58c8ff);
  static const navy = Color(0xff050a26);
  static const navy2 = Color(0xff0b1440);
  static const glass = Color(0xe00a1032);
  static const rim = [orange, Color(0xffff6a3d), pink];
  static const rimBlue = [orange, pink, blue];
}

/// UI scale from a 400 dp design width, clamped (small 360 dp phones -> .9, tablets capped at 1.2).
double uiK(BuildContext c) => (MediaQuery.sizeOf(c).width / 400).clamp(.88, 1.2);

// ------------------------------------------------------------------ space background
/// Space backdrop: an art background (BoxFit.cover, centred, never stretched) with a very slow parallax drift, two
/// procedural star layers drifting at different speeds and a vignette. Falls back to a navy gradient instantly.
class SpaceBg extends StatefulWidget {
  final String? image;
  final double dim;
  final Alignment align;
  final bool stars;
  const SpaceBg({super.key, this.image = V4.bgSpace, this.dim = 0, this.align = Alignment.center, this.stars = true});
  @override
  State<SpaceBg> createState() => _SpaceBgState();
}

class _SpaceBgState extends State<SpaceBg> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dim.clamp(0.0, 1.0);
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(builder: (ctx, box) {
          final w = box.maxWidth, h = box.maxHeight;
          return Stack(fit: StackFit.expand, children: [
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xff070b2e), Color(0xff0a0c3a), Color(0xff1a0b3c)]))),
            if (widget.image != null)
              AnimatedBuilder(
                animation: c,
                builder: (_, ch) {
                  final a = c.value * 2 * math.pi;
                  return Transform.translate(offset: Offset(math.sin(a) * w * .012, math.cos(a) * h * .008), child: Transform.scale(scale: 1.04, child: ch));
                },
                child: Image.asset(widget.image!, fit: BoxFit.cover, alignment: widget.align, width: w, height: h, gaplessPlayback: true, filterQuality: FilterQuality.medium,
                    cacheWidth: (w * MediaQuery.devicePixelRatioOf(ctx)).round().clamp(1, 1080), errorBuilder: (_, __, ___) => const SizedBox.shrink())),
            if (widget.stars && hq) CustomPaint(painter: _StarsPainter(c, 70, 1, 7), size: Size(w, h)),
            if (widget.stars) CustomPaint(painter: _StarsPainter(c, 36, 2.2, 3), size: Size(w, h)),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(radius: 1.15, colors: [Color.fromRGBO(3, 4, 20, d * .6), Color.fromRGBO(3, 4, 20, (.45 + d * .5).clamp(0, 1))], stops: const [.55, 1]),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  final Animation<double> a;
  final int n;
  final double speed, seed;
  _StarsPainter(this.a, this.n, this.speed, this.seed) : super(repaint: a);
  final Paint _p = Paint()..isAntiAlias = true;
  @override
  void paint(Canvas c, Size s) {
    final r = math.Random(seed.toInt());
    final t = a.value;
    for (var i = 0; i < n; i++) {
      final x = r.nextDouble() * s.width;
      final y0 = r.nextDouble();
      final sz = .5 + r.nextDouble() * (speed > 1.5 ? 1.6 : .9);
      final tw = .45 + .55 * (.5 + .5 * math.sin(t * 2 * math.pi * (2 + r.nextInt(5)) + i));
      final y = ((y0 + t * speed * .15) % 1) * s.height;
      _p.color = (i % 7 == 0 ? const Color(0xffffc58a) : i % 5 == 0 ? const Color(0xff9fc2ff) : Colors.white).withValues(alpha: .25 + .55 * tw);
      c.drawCircle(Offset(x, y), sz, _p);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter o) => false;
}

// ------------------------------------------------------------------ panel
/// Dark glass panel with a neon rim. [rim] null -> orange->pink gradient; [selected] adds an outer glow.
class NeonPanel extends StatelessWidget {
  final Widget? child;
  final EdgeInsets padding, margin;
  final double radius;
  final List<Color>? rim;
  final bool selected, glowOn;
  final double? width, height;
  final double rimW;
  final List<Color>? fill;
  const NeonPanel({super.key, this.child, this.padding = const EdgeInsets.all(14), this.margin = EdgeInsets.zero, this.radius = 20, this.rim, this.selected = false, this.glowOn = false, this.width, this.height, this.rimW = 1.6, this.fill});

  @override
  Widget build(BuildContext context) {
    final rc = rim ?? N.rim;
    final g = selected || glowOn;
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: g && hq
          ? BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: [BoxShadow(color: rc.first.withValues(alpha: selected ? .55 : .3), blurRadius: selected ? 22 : 14)])
          : null,
      child: CustomPaint(
        painter: _PanelPainter(radius, rc, rimW * (selected ? 1.35 : 1), fill),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _PanelPainter extends CustomPainter {
  final double r, w;
  final List<Color> rim;
  final List<Color>? fill;
  _PanelPainter(this.r, this.rim, this.w, this.fill);
  @override
  void paint(Canvas c, Size s) {
    final rect = Offset.zero & s;
    final rr = RRect.fromRectAndRadius(rect.deflate(w / 2), Radius.circular(r));
    c.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: fill ?? const [Color(0xf0141b4a), Color(0xf00a0f30), Color(0xf5060920)], stops: fill == null ? const [0, .55, 1] : null)
              .createShader(rect));
    // glossy top sheen
    c.save();
    c.clipRRect(rr);
    c.drawRect(
        Rect.fromLTWH(0, 0, s.width, math.min(s.height * .45, 60)),
        Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x1fffffff), Color(0x00ffffff)]).createShader(Rect.fromLTWH(0, 0, s.width, math.min(s.height * .45, 60))));
    c.restore();
    // soft outer rim glow + crisp rim
    if (hq) {
      c.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 3.2
            ..shader = SweepGradient(colors: [...rim.map((x) => x.withValues(alpha: .16)), rim.first.withValues(alpha: .16)]).createShader(rect));
    }
    c.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: rim).createShader(rect));
    // small bright highlight on the top edge
    c.drawLine(Offset(r + 6, w / 2), Offset(math.min(s.width - r, r + 46), w / 2),
        Paint()
          ..color = const Color(0xccffe2c4)
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_PanelPainter o) => o.r != r || o.w != w || o.rim != rim || o.fill != fill;
}

// ------------------------------------------------------------------ button
enum NeonKind { primary, ghost, gold, green, red, blue, violet }

/// Pill button with press-scale and a slow breathing glow (orange primary by default).
class NeonButton extends StatefulWidget {
  final String label;
  final String? sub, icon;
  final IconData? iconData;
  final VoidCallback? onTap;
  final NeonKind kind;
  final bool small, disabled, pulse;
  final double? width;
  const NeonButton(this.label, {super.key, this.onTap, this.kind = NeonKind.primary, this.small = false, this.disabled = false, this.sub, this.icon, this.iconData, this.pulse = false, this.width});
  @override
  State<NeonButton> createState() => _NeonButtonState();
}

List<Color> neonColors(NeonKind k) => switch (k) {
      NeonKind.primary => const [Color(0xffffb15a), Color(0xffff7a2a), Color(0xffff4d1f)],
      NeonKind.ghost => const [Color(0xff1a2258), Color(0xff0e1440), Color(0xff0a0f30)],
      NeonKind.gold => const [Color(0xffffe08a), Color(0xffe2a52c), Color(0xffa86a10)],
      NeonKind.green => const [Color(0xff7dffc8), Color(0xff1cc884), Color(0xff0b7a52)],
      NeonKind.red => const [Color(0xffff8a9a), Color(0xffe33a55), Color(0xff8a1430)],
      NeonKind.blue => const [Color(0xff8fd0ff), Color(0xff3b82ff), Color(0xff2a3fb8)],
      NeonKind.violet => const [Color(0xffd0a8ff), Color(0xff8b5bff), Color(0xff4a2aa8)],
    };

Color neonGlow(NeonKind k) => switch (k) {
      NeonKind.primary || NeonKind.ghost => N.orange,
      NeonKind.gold => C.gold,
      NeonKind.green => C.green,
      NeonKind.red => C.red,
      NeonKind.blue => N.blue,
      NeonKind.violet => C.violet,
    };

class _NeonButtonState extends State<NeonButton> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  @override
  void initState() {
    super.initState();
    if (widget.pulse && hq) _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = uiK(context);
    final h = (widget.small ? 44.0 : 56.0) * k.clamp(.92, 1.1);
    final cols = neonColors(widget.kind);
    final gc = neonGlow(widget.kind);
    final ghost = widget.kind == NeonKind.ghost;
    final dark = widget.kind == NeonKind.gold;
    Widget body(double p) => Container(
          height: h,
          width: widget.width,
          padding: EdgeInsets.symmetric(horizontal: widget.small ? 16 : 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(h / 2),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: cols),
            border: Border.all(color: ghost ? N.orange.withValues(alpha: .9) : const Color(0x66ffffff), width: ghost ? 1.4 : 1),
            boxShadow: hq && !widget.disabled ? [BoxShadow(color: gc.withValues(alpha: (ghost ? .22 : .38) + p * .25), blurRadius: 14 + p * 10, spreadRadius: p * 1.5)] : null,
          ),
          child: Stack(alignment: Alignment.center, children: [
            // glossy upper half
            Positioned(
              top: 2,
              left: h * .3,
              right: h * .3,
              height: h * .42,
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(h),
                      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x59ffffff), Color(0x00ffffff)]))),
            ),
            Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (widget.icon != null) Padding(padding: const EdgeInsets.only(right: 8), child: Img(widget.icon!, w: h * .46, h: h * .46)),
              if (widget.iconData != null) Padding(padding: const EdgeInsets.only(right: 6), child: Icon(widget.iconData, size: h * .42, color: dark ? const Color(0xff2a1600) : Colors.white)),
              Flexible(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  T(widget.label,
                      size: (widget.small ? 14 : 17) * k.clamp(.92, 1.08),
                      family: F.title,
                      weight: 900,
                      spacing: widget.small ? 1 : 2,
                      lines: 1,
                      color: dark ? const Color(0xff2a1600) : Colors.white,
                      shadows: dark ? null : const [Shadow(color: Color(0x80300a00), blurRadius: 6)]),
                  if (widget.sub != null) T(widget.sub!, size: 10, color: const Color(0xe6ffffff), family: F.head, weight: 700, spacing: 1, lines: 1),
                ]),
              ),
            ]),
          ]),
        );
    return Press(
      onTap: widget.onTap,
      disabled: widget.disabled,
      scaleTo: .93,
      child: _c == null ? body(0) : AnimatedBuilder(animation: _c!, builder: (_, __) => body(Curves.easeInOut.transform(_c!.value))),
    );
  }
}

// ------------------------------------------------------------------ icon button
/// Square glass tile with an orange rim, an icon image and an optional label underneath.
class NeonIconButton extends StatelessWidget {
  final String? icon;
  final IconData? iconData;
  final String? label;
  final VoidCallback? onTap;
  final double size;
  final Object? badge;
  final bool selected;
  final bool circle;
  const NeonIconButton({super.key, this.icon, this.iconData, this.label, this.onTap, this.size = 58, this.badge, this.selected = false, this.circle = false});
  @override
  Widget build(BuildContext context) {
    final s = size;
    final showBadge = badge == true || (badge is int && badge as int > 0);
    return Press(
      onTap: onTap,
      scaleTo: .88,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: s,
          height: s,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: NeonPanel(
                radius: circle ? s / 2 : s * .28,
                padding: EdgeInsets.all(s * .16),
                selected: selected,
                rimW: 1.4,
                child: Center(
                  child: icon != null ? Img(icon!, w: s * .66, h: s * .66) : Icon(iconData ?? Icons.circle, size: s * .46, color: N.amber),
                ),
              ),
            ),
            if (showBadge)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(8), border: Border.all(color: N.navy, width: 1.5)),
                  child: badge is int ? T((badge as int) > 9 ? '9+' : '$badge', size: 9, family: F.bold, weight: 800, color: Colors.white) : null,
                ),
              ),
          ]),
        ),
        if (label != null) Padding(padding: const EdgeInsets.only(top: 5), child: SizedBox(width: s + 18, child: T(label!, size: 10.5, color: const Color(0xffdfe6ff), align: TextAlign.center, lines: 1))),
      ]),
    );
  }
}

// ------------------------------------------------------------------ toggle
class NeonToggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChange;
  const NeonToggle({super.key, required this.on, required this.onChange});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          sfx(Snd.ui);
          buzz();
          onChange(!on);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 56,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: on ? null : const Color(0xff0b1033),
            gradient: on ? const LinearGradient(colors: [Color(0xffff4d1f), Color(0xffff9a3c)]) : null,
            border: Border.all(color: on ? const Color(0xffffc08a) : const Color(0x55ff8a2a), width: 1.2),
            boxShadow: on && hq ? [BoxShadow(color: N.orange.withValues(alpha: .55), blurRadius: 12)] : null,
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.all(3),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xff3a4170), Color(0xff0a0e28)]),
                border: Border.all(color: on ? Colors.white : N.orange, width: 1.6),
              ),
            ),
          ),
        ),
      );
}

// ------------------------------------------------------------------ section header
/// Persian title (right), English caption in Orbitron, orange gradient line.
class NeonHeader extends StatelessWidget {
  final String title;
  final String? en;
  final Widget? trailing;
  final EdgeInsets padding;
  const NeonHeader(this.title, {super.key, this.en, this.trailing, this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 10)});
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          if (trailing != null) trailing!,
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(1), gradient: const LinearGradient(colors: [Color(0x00ff8a2a), Color(0xccff8a2a), Color(0xffff4f9a)])),
            ),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            tBold(title, size: 16),
            if (en != null) T(en!, size: 8.5, family: F.head, weight: 700, spacing: 2.5, color: N.amber),
          ]),
        ]),
      );
}

// ------------------------------------------------------------------ bottom nav
enum NavTab { home, rank, play, team, social }

const kNavTabs = [
  (NavTab.home, 'Home', 'خانه', Icons.home_rounded),
  (NavTab.rank, 'Rank', 'رتبه', Icons.leaderboard_rounded),
  (NavTab.play, 'Play', 'بازی', Icons.play_arrow_rounded),
  (NavTab.team, 'Team', 'تیم', Icons.shield_rounded),
  (NavTab.social, 'Social', 'اجتماعی', Icons.groups_rounded),
];
const double kNavH = 80;

/// Glass bottom bar with the centre Play button raised above it. [keys] (optional) receive each tab's GlobalKey for the tutorial.
class NeonNavBar extends StatelessWidget {
  final NavTab tab;
  final ValueChanged<NavTab> onTab;
  final Set<NavTab> badges;
  final bool fa;
  final Map<NavTab, GlobalKey>? keys;
  const NeonNavBar({super.key, required this.tab, required this.onTab, this.badges = const {}, this.fa = true, this.keys});
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, math.max(8.0, bottom)),
      child: SizedBox(
        height: kNavH,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 62,
            child: NeonPanel(radius: 24, padding: EdgeInsets.zero, rim: const [Color(0xaaff8a2a), Color(0x66ff4f9a), Color(0xaa4f7dff)], rimW: 1.2),
          ),
          Positioned.fill(
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final t in kNavTabs) Expanded(child: KeyedSubtree(key: keys?[t.$1], child: t.$1 == NavTab.play ? _play(t) : _item(t))),
            ]),
          ),
        ]),
      ),
    );
  }

  void _tap(NavTab t) {
    if (t != tab) {
      sfx(Snd.ui);
      buzz();
    }
    onTab(t);
  }

  Widget _item((NavTab, String, String, IconData) t) {
    final on = t.$1 == tab;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(t.$1),
      child: SizedBox(
        height: 62,
        child: Stack(alignment: Alignment.center, children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: on ? const Color(0x33ff8a2a) : Colors.transparent,
                boxShadow: on && hq ? [BoxShadow(color: N.orange.withValues(alpha: .35), blurRadius: 10)] : null,
              ),
              child: Icon(t.$4, size: 24, color: on ? N.amber : const Color(0xff8e9ac8)),
            ),
            const SizedBox(height: 2),
            T(fa ? t.$3 : t.$2, size: 10.5, family: F.bold, weight: 800, color: on ? N.amber : const Color(0xff8e9ac8), lines: 1),
          ]),
          if (badges.contains(t.$1))
            Positioned(top: 8, right: 14, child: Container(width: 9, height: 9, decoration: BoxDecoration(color: C.red, shape: BoxShape.circle, border: Border.all(color: N.navy, width: 1.5)))),
        ]),
      ),
    );
  }

  Widget _play((NavTab, String, String, IconData) t) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tap(t.$1),
        child: SizedBox(
          height: kNavH,
          child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
            _GlowPulse(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xffffc27a), Color(0xffff7a2a), Color(0xffd8401a)]),
                  border: Border.all(color: const Color(0xfffff0e0), width: 2),
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 36, color: Colors.white),
              ),
            ),
            const SizedBox(height: 1),
            T(fa ? t.$3 : t.$2, size: 10.5, family: F.bold, weight: 800, color: N.amber, lines: 1),
          ]),
        ),
      );
}

/// Slow orange glow pulse behind a child (circle).
class _GlowPulse extends StatefulWidget {
  final Widget child;
  const _GlowPulse({required this.child});
  @override
  State<_GlowPulse> createState() => _GlowPulseState();
}

class _GlowPulseState extends State<_GlowPulse> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat(reverse: true);
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !hq
      ? widget.child
      : AnimatedBuilder(
          animation: c,
          child: widget.child,
          builder: (_, ch) => DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: N.orange.withValues(alpha: .35 + c.value * .3), blurRadius: 16 + c.value * 12, spreadRadius: c.value * 2)]),
            child: ch,
          ),
        );
}

// ------------------------------------------------------------------ misc
/// Orange-rimmed currency / stat pill.
class NeonPill extends StatelessWidget {
  final String? icon;
  final IconData? iconData;
  final String text;
  final Color color;
  final VoidCallback? onTap;
  final bool plus;
  const NeonPill({super.key, this.icon, this.iconData, required this.text, this.color = N.amber, this.onTap, this.plus = false});
  @override
  Widget build(BuildContext context) {
    final body = Container(
      height: 32,
      padding: const EdgeInsets.only(left: 4, right: 8),
      decoration: BoxDecoration(
        color: const Color(0xd9080d2c),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: N.orange.withValues(alpha: .7), width: 1.1),
        boxShadow: hq ? [BoxShadow(color: N.orange.withValues(alpha: .18), blurRadius: 8)] : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) Img(icon!, w: 24, h: 24) else Icon(iconData ?? Icons.bolt, size: 18, color: color),
        const SizedBox(width: 4),
        T(text, size: 13, family: F.num, weight: 700, color: color),
        if (plus) ...[
          const SizedBox(width: 4),
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xffff9a3c), Color(0xffff4d1f)])),
            child: const Icon(Icons.add_rounded, size: 14, color: Colors.white),
          ),
        ],
      ]),
    );
    return onTap != null ? Press(onTap: onTap, child: body) : body;
  }
}

/// Fade + slight upward slide page transition (v4).
Route<T> neonRoute<T>(Widget page, {bool opaque = true}) => PageRouteBuilder<T>(
      opaque: opaque,
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, ch) {
        final cv = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: cv,
          child: SlideTransition(position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(cv), child: ScaleTransition(scale: Tween(begin: .985, end: 1.0).animate(cv), child: ch)),
        );
      },
    );

/// The NEXORA "N" logo with an optional slow glow pulse (title art).
class NexoraLogo extends StatelessWidget {
  final double width;
  const NexoraLogo({super.key, this.width = 220});
  @override
  Widget build(BuildContext context) => SizedBox(width: width, height: width * 536 / 900, child: Image.asset(V4.logo, fit: BoxFit.contain, filterQuality: FilterQuality.medium));
}
