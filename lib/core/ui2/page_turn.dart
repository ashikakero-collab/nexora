import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paper page-turn transition: the new page swings in like a book page hinged on the start edge, with a
/// moving crease shadow and a paper highlight; the page underneath darkens. Reduced motion -> plain fade.
class NxPageTurn extends StatelessWidget {
  const NxPageTurn({super.key, required this.animation, required this.secondary, required this.child});
  final Animation<double> animation;
  final Animation<double> secondary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return FadeTransition(opacity: animation, child: child);
    }
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[animation, secondary]),
      child: child,
      builder: (BuildContext context, Widget? c) {
        final double t = Curves.easeOutCubic.transform(animation.value);
        final double under = Curves.easeOut.transform(secondary.value);
        // angle 0 = flat; the page arrives from -100deg (folded back over the hinge)
        final double a = (1 - t) * 100 * math.pi / 180 * (rtl ? 1 : -1);
        final Matrix4 m = Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(a);
        final double crease = (1 - t);
        Widget page = Transform(
          alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
          transform: m,
          child: Stack(fit: StackFit.passthrough, children: <Widget>[
            c!,
            if (crease > 0.01)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
                        end: rtl ? Alignment.centerLeft : Alignment.centerRight,
                        colors: <Color>[
                          Colors.black.withValues(alpha: 0.55 * crease),
                          Colors.white.withValues(alpha: 0.10 * crease),
                          Colors.black.withValues(alpha: 0.25 * crease),
                        ],
                        stops: const <double>[0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        );
        if (under > 0.001) {
          page = Stack(fit: StackFit.passthrough, children: <Widget>[
            page,
            Positioned.fill(
                child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: 0.35 * under)))),
          ]);
        }
        return page;
      },
    );
  }
}

/// Global builder so every MaterialPageRoute turns like a page.
class NxPageTurnTransitionsBuilder extends PageTransitionsBuilder {
  const NxPageTurnTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      NxPageTurn(animation: animation, secondary: secondaryAnimation, child: child);
}
