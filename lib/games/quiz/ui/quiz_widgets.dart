import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../core/question_model.dart';

/// Icon per category; null = mixed.
IconData quizCategoryIcon(QuizCategory? c) {
  if (c == null) return Icons.shuffle_rounded;
  return switch (c) {
    QuizCategory.space => Icons.rocket_launch_rounded,
    QuizCategory.science => Icons.science_rounded,
    QuizCategory.geography => Icons.public_rounded,
    QuizCategory.history => Icons.account_balance_rounded,
    QuizCategory.sports => Icons.sports_soccer_rounded,
    QuizCategory.technology => Icons.memory_rounded,
    QuizCategory.iran => Icons.auto_stories_rounded,
    QuizCategory.general => Icons.lightbulb_rounded,
    QuizCategory.media => Icons.sports_esports_rounded,
  };
}

Color quizCategoryColor(QuizCategory? c) {
  if (c == null) return NxColors.gold;
  return switch (c) {
    QuizCategory.space => const Color(0xFF9D7BFF),
    QuizCategory.science => NxColors.turquoise,
    QuizCategory.geography => const Color(0xFF4FD1FF),
    QuizCategory.history => const Color(0xFFFFB020),
    QuizCategory.sports => const Color(0xFF7CFF8A),
    QuizCategory.technology => NxColors.electricBlue,
    QuizCategory.iran => const Color(0xFFFF6FB5),
    QuizCategory.general => const Color(0xFFFFE6A8),
    QuizCategory.media => const Color(0xFFFF4F6E),
  };
}

/// One tile of the category picker grid.
class QuizCategoryTile extends StatelessWidget {
  const QuizCategoryTile({
    super.key,
    required this.category,
    required this.label,
    required this.countLabel,
    required this.enabled,
    required this.onTap,
  });

  final QuizCategory? category;
  final String label;
  final String countLabel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color c =
        category == null ? visual.accent : quizCategoryColor(category);
    return Opacity(
      opacity: enabled ? 1.0 : 0.58,
      child: GlassPanel(
        blur: false,
        padding: const EdgeInsets.all(10),
        radius: NxRadius.md,
        tint: c.withValues(alpha: 0.10),
        borderColor: enabled
            ? c.withValues(alpha: 0.72)
            : visual.border.withValues(alpha: 0.65),
        onTap: enabled ? onTap : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: <Color>[
                  c.withValues(alpha: 0.55),
                  c.withValues(alpha: 0.08)
                ]),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: 16)
                ],
              ),
              child: Icon(quizCategoryIcon(category),
                  color: Colors.white, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: visual.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(countLabel,
                style: TextStyle(color: visual.muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Circular countdown ring with seconds in the centre.
class QuizTimerRing extends StatelessWidget {
  const QuizTimerRing(
      {super.key,
      required this.fraction,
      required this.seconds,
      this.size = 74});

  final double fraction;
  final int seconds;
  final double size;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color color = fraction > 0.5
        ? visual.accent
        : fraction > 0.25
            ? visual.accentSecondary
            : NxColors.danger;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(fraction: fraction, color: color),
        child: Center(
          child: Text(
            '$seconds',
            style: TextStyle(
              color: color,
              fontSize: size * 0.34,
              fontWeight: FontWeight.w900,
              shadows: <Shadow>[
                Shadow(color: color.withValues(alpha: 0.8), blurRadius: 12)
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double r = size.shortestSide / 2 - 5;
    final Paint bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawCircle(center, r, bg);
    final Paint glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final Paint fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color;
    final Rect rect = Rect.fromCircle(center: center, radius: r);
    final double sweep = 2 * math.pi * fraction.clamp(0.0, 1.0);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, glow);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.color != color;
}

/// Visual state of an answer button.
enum QuizOptionState { idle, picked, correct, wrong, dimmed }

class QuizAnswerButton extends StatelessWidget {
  const QuizAnswerButton({
    super.key,
    required this.index,
    required this.text,
    required this.state,
    required this.reveal,
    required this.onTap,
    this.markerIcon,
    this.compact = false,
  });

  final int index;
  final String text;
  final QuizOptionState state;

  /// 0..1 reveal animation progress (for pop / shake).
  final double reveal;
  final VoidCallback? onTap;

  /// Small marker (e.g. the bot's pick) shown at the end.
  final IconData? markerIcon;
  final bool compact;

  static const List<String> _letters = <String>['A', 'B', 'C', 'D'];

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    Color accent = visual.accent;
    Color fill = visual.surface;
    switch (state) {
      case QuizOptionState.idle:
        accent = visual.accent;
        fill = visual.surface;
      case QuizOptionState.picked:
        accent = visual.accentSecondary;
        fill = visual.accentSecondary.withValues(alpha: 0.20);
      case QuizOptionState.correct:
        accent = NxColors.success;
        fill = NxColors.success.withValues(alpha: 0.30);
      case QuizOptionState.wrong:
        accent = NxColors.danger;
        fill = NxColors.danger.withValues(alpha: 0.30);
      case QuizOptionState.dimmed:
        accent = visual.muted.withValues(alpha: 0.65);
        fill = visual.surface.withValues(alpha: 0.35);
    }
    double scale = 1.0;
    double dx = 0;
    if (state == QuizOptionState.correct) {
      scale = 1.0 + 0.06 * math.sin(reveal * math.pi);
    } else if (state == QuizOptionState.wrong) {
      dx = 8 * math.sin(reveal * math.pi * 6) * (1 - reveal);
    }
    final bool glow =
        state == QuizOptionState.correct || state == QuizOptionState.picked;
    return Transform.translate(
      offset: Offset(dx, 0),
      child: Transform.scale(
        scale: scale,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(NxRadius.md),
            child: AnimatedContainer(
              duration: NxMotion.normal,
              curve: NxMotion.curve,
              padding: EdgeInsets.symmetric(
                  horizontal: 12, vertical: compact ? 8 : 12),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(NxRadius.md),
                border: Border.all(
                    color: accent.withValues(alpha: 0.8), width: 1.4),
                boxShadow: glow
                    ? <BoxShadow>[
                        BoxShadow(
                            color: accent.withValues(alpha: 0.45),
                            blurRadius: 18)
                      ]
                    : null,
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: compact ? 24 : 30,
                    height: compact ? 24 : 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.25)),
                    child: Text(_letters[index % 4],
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: compact ? 11 : 13)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: state == QuizOptionState.dimmed
                            ? visual.muted
                            : visual.text,
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 13 : 15,
                      ),
                    ),
                  ),
                  if (state == QuizOptionState.correct)
                    const Icon(Icons.check_circle_rounded,
                        color: NxColors.success, size: 20),
                  if (state == QuizOptionState.wrong)
                    const Icon(Icons.cancel_rounded,
                        color: NxColors.danger, size: 20),
                  if (markerIcon != null) ...<Widget>[
                    const SizedBox(width: 4),
                    Icon(markerIcon, color: NxColors.gold, size: 18),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass card with the question text and its category.
class QuizQuestionCard extends StatelessWidget {
  const QuizQuestionCard({
    super.key,
    required this.category,
    required this.categoryLabel,
    required this.roundLabel,
    required this.text,
    this.compact = false,
  });

  final QuizCategory category;
  final String categoryLabel;
  final String roundLabel;
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color c = quizCategoryColor(category);
    return GlassPanel(
      blur: false,
      padding: EdgeInsets.all(compact ? 10 : NxSpace.md),
      tint: visual.surfaceRaised.withValues(alpha: 0.92),
      borderColor: c.withValues(alpha: 0.62),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _CategoryPill(
                      label: categoryLabel,
                      icon: quizCategoryIcon(category),
                      color: c),
                ),
              ),
              const SizedBox(width: 6),
              Text(roundLabel,
                  style: TextStyle(
                      color: visual.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ],
          ),
          SizedBox(height: compact ? 6 : 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: visual.text,
              fontSize: compact ? 15 : 19,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: compact ? 2 : 6),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill(
      {required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Player score chip with an optional status line (e.g. bot thinking).
class QuizScoreChip extends StatelessWidget {
  const QuizScoreChip({
    super.key,
    required this.name,
    required this.score,
    required this.color,
    required this.icon,
    this.status,
    this.statusColor = NxColors.textDim,
    this.active = false,
  });

  final String name;
  final int score;
  final Color color;
  final IconData icon;
  final String? status;
  final Color statusColor;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return AnimatedContainer(
      duration: NxMotion.normal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: visual.surfaceRaised.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(NxRadius.md),
        border: Border.all(
            color: active ? color : visual.border.withValues(alpha: 0.72),
            width: active ? 1.8 : 1),
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14)
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: visual.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: score.toDouble()),
                  duration: NxMotion.slow,
                  builder: (BuildContext context, double v, Widget? _) => Text(
                    '${v.round()}',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 18),
                  ),
                ),
                if (status != null)
                  Text(status!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating "+points" badge shown on reveal.
class QuizPointsBadge extends StatelessWidget {
  const QuizPointsBadge(
      {super.key, required this.points, required this.progress});

  final int points;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final bool ok = points > 0;
    final Color c = ok ? NxColors.success : NxColors.danger;
    return Opacity(
      opacity: (1 - (progress - 0.7).clamp(0.0, 0.3) / 0.3).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, -18 * progress),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: c),
          ),
          child: Text(ok ? '+$points' : '+0',
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w900, fontSize: 16)),
        ),
      ),
    );
  }
}
