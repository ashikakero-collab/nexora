import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../models/art_asset.dart';
import '../models/nova_models.dart';

/// A named cosmic gradient used for post cards, stories and motion posts.
class NovaGradientStyle {
  const NovaGradientStyle(this.nameFa, this.nameEn, this.colors);
  final String nameFa;
  final String nameEn;
  final List<Color> colors;
}

const List<NovaGradientStyle> kNovaGradients = <NovaGradientStyle>[
  NovaGradientStyle('سحابی صورتی', 'Pink Nebula', <Color>[Color(0xFFFF6FB5), Color(0xFF7B3FF2), Color(0xFF1A0B2E)]),
  NovaGradientStyle('شفق طلایی', 'Golden Aurora', <Color>[Color(0xFFFFC857), Color(0xFFFF6FB5), Color(0xFF5A1E4F)]),
  NovaGradientStyle('افق یخی', 'Ice Horizon', <Color>[Color(0xFF2EE6D6), Color(0xFF00C2FF), Color(0xFF0A0F2C)]),
  NovaGradientStyle('ابرنواختر', 'Supernova', <Color>[Color(0xFFFF4F6E), Color(0xFFFFB020), Color(0xFF2A0B3A)]),
  NovaGradientStyle('کهکشان بنفش', 'Violet Galaxy', <Color>[Color(0xFF9D7BFF), Color(0xFF7B3FF2), Color(0xFF0B0820)]),
  NovaGradientStyle('سیاه‌چاله', 'Black Hole', <Color>[Color(0xFF050818), Color(0xFF141B45), Color(0xFFFF6FB5)]),
  NovaGradientStyle('زمرد کیهانی', 'Cosmic Emerald', <Color>[Color(0xFF7CFF8A), Color(0xFF2EE6D6), Color(0xFF04141F)]),
  NovaGradientStyle('طلوع مریخ', 'Mars Dawn', <Color>[Color(0xFFFF8A5B), Color(0xFFFF4FA3), Color(0xFF3B1450)]),
];

NovaGradientStyle novaGradient(int i) => kNovaGradients[i.abs() % kNovaGradients.length];

/// Display name for the current user.
String novaMyName(BuildContext context, ProfileService p) => p.username.isEmpty ? context.tx('کاوشگر', 'Explorer') : p.username;

/// Relative time, bilingual.
String novaAgo(BuildContext context, DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return context.tx('همین حالا', 'just now');
  if (d.inMinutes < 60) return context.tx('${d.inMinutes} دقیقه پیش', '${d.inMinutes}m ago');
  if (d.inHours < 24) return context.tx('${d.inHours} ساعت پیش', '${d.inHours}h ago');
  if (d.inDays < 30) return context.tx('${d.inDays} روز پیش', '${d.inDays}d ago');
  return '${t.year}/${t.month}/${t.day}';
}

/// Round avatar with initial (official channel shows the NEXORA mark).
class NovaAvatar extends StatelessWidget {
  const NovaAvatar({super.key, required this.name, this.official = false, this.size = 40, this.ring = false});
  final String name;
  final bool official;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final String initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final List<Color> colors =
        official ? const <Color>[NxColors.electricBlue, NxColors.violet] : novaGradient(name.hashCode).colors.take(2).toList();
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring ? 2.5 : 0),
      decoration: ring
          ? const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(colors: <Color>[Color(0xFFFF6FB5), Color(0xFFFFC857), Color(0xFFFF6FB5)]),
            )
          : null,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white24),
        ),
        alignment: Alignment.center,
        child: official
            ? Icon(Icons.auto_awesome, color: Colors.white, size: size * 0.5)
            : Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.42)),
      ),
    );
  }
}

/// Text with tappable #hashtags and @mentions.
class NovaRichText extends StatefulWidget {
  const NovaRichText({
    super.key,
    required this.text,
    this.style,
    this.onHashtag,
    this.onMention,
    this.maxLines,
    this.textAlign = TextAlign.start,
  });
  final String text;
  final TextStyle? style;
  final ValueChanged<String>? onHashtag;
  final ValueChanged<String>? onMention;
  final int? maxLines;
  final TextAlign textAlign;

  @override
  State<NovaRichText> createState() => _NovaRichTextState();
}

class _NovaRichTextState extends State<NovaRichText> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final base = widget.style ?? const TextStyle(fontSize: 15, height: 1.5, color: NxColors.iceWhite);
    final spans = <InlineSpan>[];
    for (final t in NovaText.parse(widget.text)) {
      switch (t.kind) {
        case NovaTokenKind.text:
          spans.add(TextSpan(text: t.value));
          break;
        case NovaTokenKind.hashtag:
          final r = TapGestureRecognizer()..onTap = () => widget.onHashtag?.call(t.value);
          _recognizers.add(r);
          spans.add(TextSpan(
            text: t.display,
            recognizer: r,
            style: const TextStyle(color: NxColors.gold, fontWeight: FontWeight.w700),
          ));
          break;
        case NovaTokenKind.mention:
          final r = TapGestureRecognizer()..onTap = () => widget.onMention?.call(t.value);
          _recognizers.add(r);
          spans.add(TextSpan(
            text: t.display,
            recognizer: r,
            style: const TextStyle(color: Color(0xFFFF9BD0), fontWeight: FontWeight.w700),
          ));
          break;
      }
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      textAlign: widget.textAlign,
    );
  }
}

/// Renders a post visual: a cosmic gradient card or an art asset on a glowing backdrop.
class NovaVisualView extends StatelessWidget {
  const NovaVisualView({
    super.key,
    required this.visual,
    this.caption,
    this.height = 220,
    this.radius = NxRadius.md,
    this.animated = false,
  });
  final NovaVisual visual;
  final String? caption;
  final double height;
  final double radius;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    if (visual.isNone) return const SizedBox.shrink();
    if (visual.kind == NovaVisualKind.photo && visual.url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Image.network(
            visual.url,
            fit: BoxFit.cover,
            cacheWidth: 1080,
            loadingBuilder: (BuildContext c, Widget child, ImageChunkEvent? p) =>
                p == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 40)),
          ),
        ),
      );
    }
    final style = novaGradient(visual.gradient);
    final ArtAsset? art = visual.kind == NovaVisualKind.asset ? ArtAsset.parse(visual.asset) : null;
    final Widget backdrop = animated
        ? NovaMotionCanvas(gradient: visual.gradient)
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: style.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: CustomPaint(painter: _OrbitRingsPainter(Colors.white.withValues(alpha: 0.18))),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(fit: StackFit.expand, children: <Widget>[
          backdrop,
          if (art != null)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Image.asset(
                art.path,
                fit: BoxFit.contain,
                cacheHeight: (height * 2).round(),
                errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 42),
              ),
            ),
          if (art == null && caption != null && caption!.trim().isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Text(
                  caption!,
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.4,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: <Shadow>[Shadow(color: Colors.black45, blurRadius: 12)],
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _OrbitRingsPainter extends CustomPainter {
  _OrbitRingsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    final c = Offset(size.width * 0.82, size.height * 0.18);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(c, size.shortestSide * 0.16 * i, p);
    }
    final dot = Paint()..color = color.withValues(alpha: 0.6);
    canvas.drawCircle(Offset(size.width * 0.12, size.height * 0.8), 3, dot);
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.12), 2, dot);
    canvas.drawCircle(Offset(size.width * 0.6, size.height * 0.9), 2.5, dot);
  }

  @override
  bool shouldRepaint(covariant _OrbitRingsPainter oldDelegate) => oldDelegate.color != color;
}

/// Animated gradient used for motion posts (Reels) and stories.
/// Static when reduced motion is on.
class NovaMotionCanvas extends ConsumerStatefulWidget {
  const NovaMotionCanvas({super.key, required this.gradient, this.child});
  final int gradient;
  final Widget? child;

  @override
  ConsumerState<NovaMotionCanvas> createState() => _NovaMotionCanvasState();
}

class _NovaMotionCanvasState extends ConsumerState<NovaMotionCanvas> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 9));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final bool animate = !settings.reducedMotion;
    if (animate && !_c.isAnimating) _c.repeat();
    if (!animate && _c.isAnimating) _c.stop();
    final style = novaGradient(widget.gradient);
    final bool fancy = settings.fancyEffects;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? child) {
          final t = _c.value;
          return Stack(fit: StackFit.expand, children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: style.colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: GradientRotation(t * 2 * pi),
                ),
              ),
            ),
            CustomPaint(painter: _MotionOrbsPainter(t, style.colors.first, fancy ? 9 : 4)),
            if (child != null) child,
          ]);
        },
        child: widget.child,
      ),
    );
  }
}

class _MotionOrbsPainter extends CustomPainter {
  _MotionOrbsPainter(this.t, this.color, this.count);
  final double t;
  final Color color;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < count; i++) {
      final phase = i / count;
      final a = (t + phase) * 2 * pi;
      final cx = size.width * (0.5 + 0.38 * cos(a * (i.isEven ? 1 : -1) + i));
      final cy = size.height * (0.5 + 0.38 * sin(a + i * 1.7));
      final r = size.shortestSide * (0.08 + 0.05 * ((i * 37) % 5) / 5);
      final paint = Paint()
        ..shader = RadialGradient(colors: <Color>[
          Colors.white.withValues(alpha: 0.28),
          color.withValues(alpha: 0.12),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MotionOrbsPainter oldDelegate) => oldDelegate.t != t || oldDelegate.count != count;
}

/// Empty state with ORACLE giving a hint.
class NovaEmptyState extends StatelessWidget {
  const NovaEmptyState({super.key, required this.fa, required this.en, this.action, this.pose = 'present'});
  final String fa;
  final String en;
  final Widget? action;
  final String pose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NxSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          OracleAvatar(pose: pose, size: 96),
          const SizedBox(height: 12),
          GlassPanel(
            child: Text(context.tx(fa, en),
                textAlign: TextAlign.center, style: const TextStyle(color: NxColors.iceWhite, height: 1.5)),
          ),
          if (action != null) ...<Widget>[const SizedBox(height: 14), action!],
        ]),
      ),
    );
  }
}
