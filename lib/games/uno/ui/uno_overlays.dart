import 'package:flutter/material.dart';

import '../../../core/theme/nx_theme.dart';
import 'uno_table_widgets.dart';

/// Opaque screen shown between turns in pass-and-play so hands stay hidden.
class UnoPassScreen extends StatelessWidget {
  const UnoPassScreen({
    super.key,
    required this.isFa,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.button,
    required this.onReveal,
  });

  final bool isFa;
  final Color color;
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final TextDirection dir = isFa ? TextDirection.rtl : TextDirection.ltr;
    final NxThemeColors visual = NxThemeColors.of(context);
    return Material(
      color: visual.background.withValues(alpha: 0.97),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(NxSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.phonelink_lock_rounded, size: 64, color: color),
              const SizedBox(height: NxSpace.md),
              Text(
                title,
                textAlign: TextAlign.center,
                textDirection: dir,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: visual.text),
              ),
              const SizedBox(height: NxSpace.sm),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                textDirection: dir,
                style: TextStyle(fontSize: 14, color: visual.muted),
              ),
              const SizedBox(height: NxSpace.lg),
              UnoActionButton(
                  label: button,
                  color: color,
                  icon: Icons.visibility_rounded,
                  onTap: onReveal),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trophy card shown when a player empties their hand.
class UnoWinOverlay extends StatelessWidget {
  const UnoWinOverlay(
      {super.key,
      required this.isFa,
      required this.title,
      required this.subtitle,
      this.animate = true});

  final bool isFa;
  final String title;
  final String subtitle;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final TextDirection dir = isFa ? TextDirection.rtl : TextDirection.ltr;
    return IgnorePointer(
      child: Container(
        color: const Color(0x99050818),
        alignment: Alignment.center,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: animate ? 0.6 : 1, end: 1),
          duration: animate ? NxMotion.slow : Duration.zero,
          curve: Curves.easeOutBack,
          builder: (BuildContext context, double s, Widget? child) =>
              Transform.scale(scale: s, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NxRadius.lg),
              gradient: LinearGradient(
                  colors: <Color>[visual.surfaceRaised, visual.surface]),
              border: Border.all(color: visual.accent, width: 1.5),
              boxShadow: <BoxShadow>[
                BoxShadow(
                    color: visual.accent.withValues(alpha: 0.28),
                    blurRadius: 32)
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.emoji_events_rounded,
                    size: 56, color: visual.accent),
                const SizedBox(height: 8),
                Text(
                  title,
                  textDirection: dir,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: visual.text),
                ),
                const SizedBox(height: 6),
                Text(subtitle,
                    textDirection: dir,
                    style: TextStyle(fontSize: 14, color: visual.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pop-in banner for table events (skip, reverse, NX!, penalties).
class UnoToast extends StatelessWidget {
  const UnoToast(
      {super.key,
      required this.text,
      required this.color,
      required this.serial,
      required this.isFa,
      this.animate = true});

  final String? text;
  final Color color;
  final int serial;
  final bool isFa;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final String? t = text;
    return IgnorePointer(
      child: Center(
        child: AnimatedSwitcher(
          duration: animate ? NxMotion.normal : Duration.zero,
          transitionBuilder: (Widget child, Animation<double> a) =>
              ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1).animate(a),
            child: FadeTransition(opacity: a, child: child),
          ),
          child: t == null
              ? const SizedBox.shrink()
              : Container(
                  key: ValueKey<int>(serial),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: visual.surfaceRaised.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                          color: color.withValues(alpha: 0.45), blurRadius: 18)
                    ],
                  ),
                  child: Text(
                    t,
                    textAlign: TextAlign.center,
                    textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: visual.text),
                  ),
                ),
        ),
      ),
    );
  }
}
