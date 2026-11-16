import 'package:flutter/material.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';

/// Theme-aware colors shared across the Personal Orbit subtabs.
class PoColors {
  PoColors._();

  static NxThemeColors visual(BuildContext context) =>
      NxThemeColors.of(context);
  static Color ink(BuildContext context) => visual(context).text;
  static Color inkDim(BuildContext context) => visual(context).muted;
  static Color mint(BuildContext context) => visual(context).accent;
  static Color lilac(BuildContext context) => visual(context).accentSecondary;
  static Color card(BuildContext context) => visual(context).surface;
  static Color cardBorder(BuildContext context) =>
      visual(context).border.withValues(alpha: 0.58);
  static Color locked(BuildContext context) =>
      visual(context).muted.withValues(alpha: 0.58);
}

/// Converts western digits to Persian digits in Persian UI.
String poDigits(BuildContext context, String s) {
  if (!context.isFa) return s;
  const String fa = '۰۱۲۳۴۵۶۷۸۹';
  final StringBuffer b = StringBuffer();
  for (final int c in s.codeUnits) {
    if (c >= 48 && c <= 57) {
      b.write(fa[c - 48]);
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

String _two(int v) => v < 10 ? '0$v' : '$v';

String poDate(BuildContext context, DateTime d) =>
    poDigits(context, '${d.year}/${_two(d.month)}/${_two(d.day)}');

String poDateTime(BuildContext context, DateTime d) => poDigits(context,
    '${d.year}/${_two(d.month)}/${_two(d.day)}  ${_two(d.hour)}:${_two(d.minute)}');

/// Relative time ("5 min ago").
String poAgo(BuildContext context, DateTime at, DateTime now) {
  final Duration d = now.difference(at);
  if (d.inMinutes < 1) return context.tx('همین حالا', 'just now');
  if (d.inMinutes < 60)
    return poDigits(context,
        context.tx('${d.inMinutes} دقیقه پیش', '${d.inMinutes} min ago'));
  if (d.inHours < 24)
    return poDigits(
        context, context.tx('${d.inHours} ساعت پیش', '${d.inHours} h ago'));
  if (d.inDays < 7)
    return poDigits(
        context, context.tx('${d.inDays} روز پیش', '${d.inDays} d ago'));
  return poDate(context, at);
}

/// Premium inset panel used throughout the subtabs.
class PoCard extends StatelessWidget {
  const PoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NxSpace.md),
    this.color,
    this.borderColor,
    this.onTap,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final BorderRadius r = BorderRadius.circular(NxRadius.lg);
    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? visual.surface) : null,
        gradient: gradient,
        borderRadius: r,
        border: Border.all(
            color: borderColor ?? visual.border.withValues(alpha: 0.58)),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 18,
              offset: const Offset(0, 7)),
          BoxShadow(
              color: visual.accent.withValues(alpha: 0.055), blurRadius: 20),
        ],
      ),
      child: child,
    );
    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: r, onTap: onTap, child: body),
      );
    }
    return body;
  }
}

class PoSectionTitle extends StatelessWidget {
  const PoSectionTitle(this.text, {super.key, this.icon, this.trailing});
  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, NxSpace.md, 4, NxSpace.sm),
      child: Row(children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 18, color: visual.accent),
          const SizedBox(width: 6)
        ],
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: visual.text,
                  letterSpacing: 0.4)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Rounded progress bar using the active theme's two signature accents.
class PoProgressBar extends StatelessWidget {
  const PoProgressBar(
      {super.key, required this.value, this.height = 8, this.colors});
  final double value;
  final double height;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final double v = value.isNaN ? 0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(children: <Widget>[
        Container(height: height, color: visual.border.withValues(alpha: 0.22)),
        FractionallySizedBox(
          widthFactor: v,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors:
                      colors ?? <Color>[visual.accent, visual.accentSecondary]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Greyscale filter for locked items.
const ColorFilter kPoGreyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 0.55, 0, //
]);

String poRarityName(BuildContext context, String r) {
  switch (r) {
    case 'rare':
      return context.tx('کمیاب', 'Rare');
    case 'epic':
      return context.tx('حماسی', 'Epic');
    case 'legendary':
      return context.tx('افسانه‌ای', 'Legendary');
    default:
      return context.tx('معمولی', 'Common');
  }
}

Color poRarityColor(String r) {
  switch (r) {
    case 'rare':
      return const Color(0xFF2F8CFF);
    case 'epic':
      return const Color(0xFF9B4DFF);
    case 'legendary':
      return const Color(0xFFE09A00);
    default:
      return const Color(0xFF6B7591);
  }
}
