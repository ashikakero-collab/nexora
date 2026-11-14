// Port of src/ui/kit.tsx (+ Space.tsx): the neon/glass widget kit.
// Performance rules: no BackdropFilter / saveLayer, shadows only in "high" quality, images cached by
// Flutter's ImageCache with cacheWidth set to the drawn size, every animated piece is wrapped in a
// RepaintBoundary so it never repaints its siblings.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/theme.dart';

final _faRe = RegExp(r'[\u0600-\u06FF]');
bool isFa(String s) => _faRe.hasMatch(s);

/// High graphics (shadows, glows, parallax). "Smooth" (low) mode turns them off.
bool get hq => Store.i.p.quality == 'high';

TextStyle ts({double size = 14, Color color = C.text, String family = F.body, double weight = 600, double spacing = 0, double? height, List<Shadow>? shadows}) =>
    TextStyle(fontFamily: family, fontSize: size, color: color, letterSpacing: spacing, height: height, shadows: shadows, fontVariations: [FontVariation('wght', weight)]);

/// Text: Persian strings switch to Vazirmatn automatically (Orbitron/Exo have no Persian glyphs) and drop letter-spacing.
class T extends StatelessWidget {
  final String s;
  final double size;
  final Color color;
  final String family;
  final double weight;
  final double spacing;
  final int? lines;
  final TextAlign? align;
  final List<Shadow>? shadows;
  final double? height;
  const T(this.s, {super.key, this.size = 14, this.color = C.text, this.family = F.body, this.weight = 600, this.spacing = 0, this.lines, this.align, this.shadows, this.height});

  @override
  Widget build(BuildContext context) {
    var fam = family, sz = size, w = weight, sp = spacing;
    final rtl = isFa(s);
    if (rtl) {
      final heavy = weight >= 700;
      fam = F.fa;
      w = heavy ? 800 : 500;
      sp = 0;
      if (heavy) sz = (size * (size < 12 ? 1.2 : 1.03)).roundToDouble();
    }
    return Text(s,
        maxLines: lines,
        overflow: lines != null ? TextOverflow.ellipsis : null,
        textAlign: align ?? (rtl ? TextAlign.right : null),
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        style: ts(size: sz, color: color, family: fam, weight: w, spacing: sp, shadows: shadows, height: height));
  }
}

/// Title-weight text helpers
T tTitle(String s, {double size = 20, Color color = C.text, List<Shadow>? shadows, TextAlign? align, int? lines}) =>
    T(s, size: size, color: color, family: F.title, weight: 900, shadows: shadows, align: align, lines: lines);
T tHead(String s, {double size = 10, Color color = C.cyan, double spacing = 3, TextAlign? align}) => T(s, size: size, color: color, family: F.head, weight: 700, spacing: spacing, align: align);
T tBold(String s, {double size = 14, Color color = C.text, int? lines, TextAlign? align}) => T(s, size: size, color: color, family: F.bold, weight: 800, lines: lines, align: align);

/// Asset / network image with decode size bound to the drawn size (lighter memory, faster decode).
class Img extends StatelessWidget {
  final String src;
  final double? w, h;
  final BoxFit fit;
  final double radius;
  final double opacity;
  const Img(this.src, {super.key, this.w, this.h, this.fit = BoxFit.contain, this.radius = 0, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cw = w != null ? (w! * dpr).round() : null;
    final ImageProvider prov = src.startsWith('http') ? NetworkImage(src) : AssetImage(src);
    final provider = cw != null && cw > 0 ? ResizeImage(prov, width: cw, policy: ResizeImagePolicy.fit, allowUpscaling: false) : prov;
    Widget im = Image(
      image: provider,
      width: w,
      height: h,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      opacity: opacity < 1 ? AlwaysStoppedAnimation(opacity) : null,
      errorBuilder: (_, __, ___) => SizedBox(width: w, height: h),
    );
    if (radius > 0) im = ClipRRect(borderRadius: BorderRadius.circular(radius), child: im);
    return im;
  }
}

/// Press: spring scale, sound + haptic on tap.
class Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLong;
  final bool sound, haptic, disabled;
  final double scaleTo;
  const Press({super.key, required this.child, this.onTap, this.onLong, this.sound = true, this.haptic = true, this.disabled = false, this.scaleTo = .94});
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final dis = widget.disabled || widget.onTap == null && widget.onLong == null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: dis ? null : (_) => setState(() => _down = true),
      onTapCancel: dis ? null : () => setState(() => _down = false),
      onTapUp: dis ? null : (_) => setState(() => _down = false),
      onLongPress: dis ? null : widget.onLong,
      onTap: dis
          ? null
          : () {
              if (widget.sound) sfx(Snd.ui);
              if (widget.haptic) buzz();
              widget.onTap?.call();
            },
      child: AnimatedScale(
        scale: _down ? widget.scaleTo : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: Opacity(opacity: widget.disabled ? .45 : 1, child: widget.child),
      ),
    );
  }
}

List<BoxShadow>? glow(Color c, [double r = 14, double o = .6]) => hq ? [BoxShadow(color: c.withValues(alpha: o), blurRadius: r, spreadRadius: 0)] : null;

/// Glass panel: gradient body, top highlight and accent line.
class Panel extends StatelessWidget {
  final Widget? child;
  final Color? accent;
  final bool glowOn;
  final EdgeInsets padding;
  final double radius;
  final EdgeInsets margin;
  final double? width, height;
  const Panel({super.key, this.child, this.accent, this.glowOn = false, this.padding = const EdgeInsets.all(12), this.radius = 20, this.margin = EdgeInsets.zero, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final a = accent ?? C.lineHi;
    final noAccent = accent == Colors.transparent;
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: glowOn ? a.withValues(alpha: .4) : C.line),
        gradient: const LinearGradient(begin: Alignment(-1, -1), end: Alignment(-.3, 1), colors: [Color(0x9e22347c), Color(0xdb0c1234), Color(0xf006091c)]),
        boxShadow: glowOn ? glow(a, 16, .5) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(children: [
          const Positioned.fill(
              child: IgnorePointer(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0x1affffff), Color(0x00ffffff)]))))),
          if (!noAccent) Positioned(top: 0, left: 28, right: 28, height: 2, child: DecoratedBox(decoration: BoxDecoration(color: a.withValues(alpha: .9), borderRadius: BorderRadius.circular(2)))),
          Padding(padding: padding, child: child),
        ]),
      ),
    );
  }
}

class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final List<Color> colors;
  final String? icon;
  final bool small, disabled, dark;
  final String? sub;
  const Btn(this.label, {super.key, this.onTap, this.colors = G.primary, this.icon, this.small = false, this.disabled = false, this.sub, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final r = small ? 14.0 : 18.0;
    return Press(
      onTap: onTap,
      disabled: disabled,
      child: Container(
        height: small ? 44 : 58,
        padding: EdgeInsets.symmetric(horizontal: small ? 16 : 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          border: Border.all(color: const Color(0x59ffffff)),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Positioned(
              top: 0,
              left: -22,
              right: -22,
              height: small ? 22 : 30,
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(r)),
                      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x61ffffff), Color(0x0fffffff), Color(0x00ffffff)])))),
          Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) Padding(padding: const EdgeInsets.only(right: 8), child: Img(icon!, w: small ? 20 : 24, h: small ? 20 : 24)),
            Flexible(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                T(label,
                    size: small ? 14 : 18,
                    family: F.title,
                    weight: 900,
                    spacing: small ? 1.5 : 3,
                    lines: 1,
                    color: dark ? const Color(0xff06122a) : Colors.white,
                    shadows: dark ? null : const [Shadow(color: Color(0x73000000), blurRadius: 6)]),
                if (sub != null) T(sub!, size: 10, color: const Color(0xd9ffffff), family: F.head, weight: 700, spacing: 1.5),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String icon;
  final String v;
  final Color tint;
  final VoidCallback? onTap;
  final bool plus;
  const Pill({super.key, required this.icon, required this.v, this.tint = C.text, this.onTap, this.plus = false});
  @override
  Widget build(BuildContext context) {
    final body = Container(
      height: 32,
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.only(left: 4, right: 4),
      decoration: BoxDecoration(color: const Color(0xc7060a1e), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Img(icon, w: 24, h: 24),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: T(v, size: 12, family: F.num, weight: 700, color: tint)),
        if (plus)
          Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: C.green, shape: BoxShape.circle),
              child: const T('+', size: 12, family: F.title, weight: 900, color: Color(0xff04122a))),
      ]),
    );
    return onTap != null ? Press(onTap: onTap, child: body) : body;
  }
}

/// Animated progress bar.
class Bar extends StatelessWidget {
  final double v;
  final Color color, color2;
  final double h;
  const Bar({super.key, required this.v, this.color = C.cyan, this.color2 = C.indigo, this.h = 8});
  @override
  Widget build(BuildContext context) {
    final f = v.clamp(.02, 1.0);
    return Container(
      height: h,
      decoration: BoxDecoration(color: const Color(0x14ffffff), borderRadius: BorderRadius.circular(h), border: Border.all(color: const Color(0x1affffff), width: .5)),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: f),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, x, __) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: x,
          child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(h), gradient: LinearGradient(colors: [color2, color]))),
        ),
      ),
    );
  }
}

class Chip2 extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  final Color accent;
  final String? icon;
  const Chip2(this.label, {super.key, this.on = false, this.onTap, this.accent = C.cyan, this.icon});
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        child: Container(
          height: 36,
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: on ? accent.withValues(alpha: .16) : const Color(0xb3080c22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? accent : C.line),
            boxShadow: on ? glow(accent, 8, .5) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) Padding(padding: const EdgeInsets.only(right: 5), child: Img(icon!, w: 20, h: 20)),
            tBold(label, size: 12, color: on ? Colors.white : C.dim),
          ]),
        ),
      );
}

/// Segmented control with a sliding highlight (items laid out right-to-left like the RN app).
class Segment<V> extends StatelessWidget {
  final List<(V, String)> items;
  final V value;
  final ValueChanged<V> onChange;
  final Color accent;
  const Segment({super.key, required this.items, required this.value, required this.onChange, this.accent = C.cyan});
  @override
  Widget build(BuildContext context) {
    final idx = math.max(0, items.indexWhere((e) => e.$1 == value));
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xcc060a1e), borderRadius: BorderRadius.circular(22), border: Border.all(color: C.line)),
      child: LayoutBuilder(builder: (ctx, c) {
        final cw = c.maxWidth / items.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            top: 0,
            bottom: 0,
            right: idx * cw,
            width: cw,
            child: Container(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: accent),
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [accent.withValues(alpha: .33), accent.withValues(alpha: .09)]))),
          ),
          Row(textDirection: TextDirection.rtl, children: [
            for (final it in items)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    sfx(Snd.ui);
                    buzz();
                    onChange(it.$1);
                  },
                  child: Center(child: tBold(it.$2, size: 12, color: it.$1 == value ? Colors.white : C.dim)),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

class Toggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChange;
  final Color accent;
  const Toggle({super.key, required this.on, required this.onChange, this.accent = C.cyan});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          sfx(Snd.ui);
          buzz();
          onChange(!on);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 54,
          height: 30,
          decoration: BoxDecoration(color: on ? accent : const Color(0x1fffffff), borderRadius: BorderRadius.circular(15)),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(margin: const EdgeInsets.all(3), width: 24, height: 24, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          ),
        ),
      );
}

/// Section title: Persian title on the right, English caption, divider line.
class TitleBar extends StatelessWidget {
  final String s;
  final String? en;
  final Color accent;
  final Widget? right;
  const TitleBar(this.s, {super.key, this.en, this.accent = C.cyan, this.right});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Row(children: [
          if (right != null) right!,
          Expanded(child: Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 10), color: const Color(0x2e78b4ff))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            tBold(s, size: 16),
            if (en != null) tHead(en!, size: 8, color: accent),
          ]),
        ]),
      );
}

class Section extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget child;
  const Section({super.key, required this.title, this.action, this.onAction, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: SP.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SP.l),
            child: Row(textDirection: TextDirection.rtl, children: [
              Container(width: 3, height: 16, margin: const EdgeInsets.only(left: SP.s), decoration: BoxDecoration(color: C.cyan, borderRadius: BorderRadius.circular(2))),
              Expanded(child: tBold(title, size: 16, align: TextAlign.right)),
              if (action != null) Press(onTap: onAction, child: Padding(padding: const EdgeInsets.all(SP.s), child: T(action!, size: 12, color: C.cyan))),
            ]),
          ),
          const SizedBox(height: SP.s),
          child,
        ]),
      );
}

class ListRow extends StatelessWidget {
  final String? icon;
  final Widget? leading;
  final String title;
  final String? sub;
  final Widget? right;
  final VoidCallback? onTap;
  const ListRow({super.key, this.icon, this.leading, required this.title, this.sub, this.right, this.onTap});
  @override
  Widget build(BuildContext context) {
    final body = Container(
      constraints: const BoxConstraints(minHeight: 56),
      margin: const EdgeInsets.fromLTRB(SP.l, 0, SP.l, SP.s),
      padding: const EdgeInsets.symmetric(horizontal: SP.m, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xd10a0e28), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
      child: Row(textDirection: TextDirection.rtl, children: [
        if (leading != null) leading!,
        if (icon != null) Img(icon!, w: 28, h: 28),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SP.m),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              tBold(title, size: 14, lines: 1),
              if (sub != null) T(sub!, size: 11, color: C.dim, lines: 1),
            ]),
          ),
        ),
        if (right != null) right!,
      ]),
    );
    return onTap != null ? Press(onTap: onTap, scaleTo: .98, child: body) : body;
  }
}

class IconBtn extends StatelessWidget {
  final String src;
  final VoidCallback? onTap;
  final Object? badge; // bool or int
  final double size;
  const IconBtn(this.src, {super.key, this.onTap, this.badge, this.size = 40});
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        scaleTo: .88,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Img(src, w: size, h: size),
            if (badge == true || (badge is int && badge as int > 0))
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 14),
                  height: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0xff0b1236), width: 1.5)),
                  child: badge is int ? T((badge as int) > 9 ? '9+' : '$badge', size: 8, family: F.bold, weight: 800, color: Colors.white) : null,
                ),
              ),
          ]),
        ),
      );
}

/// Slow breathing radial glow (no blur: a radial gradient is GPU-cheap).
class Pulse extends StatefulWidget {
  final double size;
  final Color color;
  const Pulse({super.key, required this.size, required this.color});
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: c,
          builder: (_, __) {
            final p = Curves.easeInOut.transform(c.value);
            return Opacity(
              opacity: .35 + p * .4,
              child: Transform.scale(
                scale: .9 + p * .12,
                child: Container(
                  width: widget.size * 1.5,
                  height: widget.size * 1.5,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [widget.color, widget.color.withValues(alpha: 0)], stops: const [.45, 1])),
                ),
              ),
            );
          },
        ),
      );
}

/// Gentle vertical float.
class FloatY extends StatefulWidget {
  final Widget child;
  final double amp;
  final int ms;
  const FloatY({super.key, required this.child, this.amp = 6, this.ms = 2600});
  @override
  State<FloatY> createState() => _FloatYState();
}

class _FloatYState extends State<FloatY> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms))..repeat(reverse: true);
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
          builder: (_, ch) => Transform.translate(offset: Offset(0, widget.amp - Curves.easeInOut.transform(c.value) * widget.amp * 2), child: ch),
        ),
      );
}

/// Continuous rotation (rings, rays).
class Spin extends StatefulWidget {
  final Widget child;
  final int ms;
  final bool reverse;
  const Spin({super.key, required this.child, this.ms = 12000, this.reverse = false});
  @override
  State<Spin> createState() => _SpinState();
}

class _SpinState extends State<Spin> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: RotationTransition(turns: widget.reverse ? ReverseAnimation(c) : c, child: widget.child));
}

/// Fade+slide-up entrance, staggered by index.
class Enter extends StatelessWidget {
  final Widget child;
  final int i;
  const Enter({super.key, required this.child, this.i = 0});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 380 + math.min(i, 10) * 45),
        curve: Curves.easeOutBack,
        child: child,
        builder: (_, v, ch) => Opacity(opacity: v.clamp(0, 1), child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: ch)),
      );
}

enum SpaceTheme { base, win, lose, system, hub, stadium, holo }

/// Deep-space backdrop: nebula + two scrolling star layers. One shared ticker, pre-baked images, RepaintBoundary.
class Space extends StatefulWidget {
  final SpaceTheme theme;
  final double dim;
  const Space({super.key, this.theme = SpaceTheme.base, this.dim = 0});
  @override
  State<Space> createState() => _SpaceState();
}

class _SpaceState extends State<Space> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 120))..repeat();
  static const _neb = {
    SpaceTheme.base: 'neb_base', SpaceTheme.win: 'neb_win', SpaceTheme.lose: 'neb_lose', SpaceTheme.system: 'neb_system',
  };
  String get _src => switch (widget.theme) {
        SpaceTheme.hub => ui2('home_bg'),
        SpaceTheme.stadium => menu('bg_stadium'),
        SpaceTheme.holo => menu('bg_holo'),
        _ => ui(_neb[widget.theme]!),
      };
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dim;
    final dark = widget.theme == SpaceTheme.stadium || widget.theme == SpaceTheme.holo;
    final size = MediaQuery.sizeOf(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Color(0xff02030b)),
          AnimatedSwitcher(duration: const Duration(milliseconds: 600), child: Img(_src, key: ValueKey(_src), w: size.width, h: size.height, fit: BoxFit.cover)),
          if (hq) _Stars(c: c, src: ui('stars1'), speed: 1, opacity: .7),
          if (hq) _Stars(c: c, src: ui('stars2'), speed: 2, opacity: .75),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .45, 1],
                colors: dark
                    ? [Color.fromRGBO(5, 4, 14, (.55 + d).clamp(0, 1)), Color.fromRGBO(5, 4, 14, (.45 + d).clamp(0, 1)), Color.fromRGBO(5, 4, 14, (.82 + d).clamp(0, 1))]
                    : [Color.fromRGBO(2, 4, 14, (.35 + d).clamp(0, 1)), Color.fromRGBO(2, 4, 14, d.clamp(0, 1)), Color.fromRGBO(2, 4, 14, (.55 + d).clamp(0, 1))],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final AnimationController c;
  final String src;
  final double speed, opacity;
  const _Stars({required this.c, required this.src, required this.speed, required this.opacity});
  @override
  Widget build(BuildContext context) {
    const tile = 512.0;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: c,
        builder: (_, __) {
          final off = (c.value * speed * tile * 6) % tile;
          return Opacity(
            opacity: opacity,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(0, off - tile),
                  child: Image(image: ResizeImage(AssetImage(src), width: 512), repeat: ImageRepeat.repeat, width: 4000, height: 4000, alignment: Alignment.topLeft, fit: BoxFit.none),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Small helper: a round disc/avatar image in a coloured ring.
class Disc extends StatelessWidget {
  final String src;
  final double size;
  final Color ring;
  final double ringW;
  final bool glowOn;
  const Disc(this.src, {super.key, this.size = 40, this.ring = C.cyan, this.ringW = 2, this.glowOn = false});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xff050816), border: Border.all(color: ring, width: ringW), boxShadow: glowOn ? glow(ring, 12, .8) : null),
        child: ClipOval(child: Img(src, w: size - ringW * 2 - 2, h: size - ringW * 2 - 2, fit: src.startsWith('http') ? BoxFit.cover : BoxFit.contain)),
      );
}

class Spinner extends StatelessWidget {
  final double size;
  const Spinner({super.key, this.size = 28});
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: const CircularProgressIndicator(strokeWidth: 3, color: C.cyan));
}

class EmptyState extends StatelessWidget {
  final String msg;
  final String? icon;
  const EmptyState(this.msg, {super.key, this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Img(icon ?? kit('star'), w: 64, h: 64, opacity: .6),
          const SizedBox(height: 8),
          T(msg, size: 13, color: C.dim, align: TextAlign.center),
        ]),
      );
}

class ErrorState extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;
  const ErrorState(this.msg, {super.key, required this.onRetry});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Img(kit('bell'), w: 64, h: 64),
        const SizedBox(height: 8),
        T(msg, size: 13, color: C.dim, align: TextAlign.center),
        const SizedBox(height: 12),
        SizedBox(width: 160, child: Btn('تلاش دوباره', small: true, onTap: onRetry)),
      ]);
}

/// Neon sci-fi frame (chamfered corners) drawn with a CustomPainter: crisp at any size, no image, no blur.
class NeonFrame extends StatelessWidget {
  final Widget child;
  final Color color;
  final double cut;
  final EdgeInsets padding;
  const NeonFrame({super.key, required this.child, this.color = C.cyan, this.cut = 14, this.padding = const EdgeInsets.all(12)});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _FramePainter(color, cut), child: Padding(padding: padding, child: child));
}

class _FramePainter extends CustomPainter {
  final Color c;
  final double cut;
  _FramePainter(this.c, this.cut);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(cut, 0)
      ..lineTo(s.width - cut, 0)
      ..lineTo(s.width, cut)
      ..lineTo(s.width, s.height - cut)
      ..lineTo(s.width - cut, s.height)
      ..lineTo(cut, s.height)
      ..lineTo(0, s.height - cut)
      ..lineTo(0, cut)
      ..close();
    canvas.drawPath(
        p,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xb3142468), Color(0xe6060a22)]).createShader(Offset.zero & s));
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = c.withValues(alpha: .18));
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = c.withValues(alpha: .85));
    final hl = Paint()
      ..color = Colors.white.withValues(alpha: .8)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(cut + 6, 0), Offset(cut + 36, 0), hl);
    canvas.drawLine(Offset(s.width - cut - 36, s.height), Offset(s.width - cut - 6, s.height), hl);
  }

  @override
  bool shouldRepaint(_FramePainter o) => o.c != c || o.cut != cut;
}
