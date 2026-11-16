import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';
import 'nx2_assets.dart';

/// What ORACLE feels right now; each mood has its own pose from the owner's robot art.
enum OracleMood {
  idle,
  greet,
  happy,
  think,
  error,
  win,
  play,
  curious,
  calm,
  alert,
  sleep,
  laugh,
  spin,
  question,
  point,
  holo,
}

String oracleMoodPose(OracleMood m) => switch (m) {
      OracleMood.idle => 'hero',
      OracleMood.greet => 'smile',
      OracleMood.happy => 'happy',
      OracleMood.think => 'focus',
      OracleMood.error => 'confused',
      OracleMood.win => 'excited',
      OracleMood.play => 'play',
      OracleMood.curious => 'curious',
      OracleMood.calm => 'content',
      OracleMood.alert => 'alert',
      OracleMood.sleep => 'sleep',
      OracleMood.laugh => 'laugh',
      OracleMood.spin => 'spin',
      OracleMood.question => 'question',
      OracleMood.point => 'point',
      OracleMood.holo => 'holo',
    };

/// Maps the legacy pose names used across the app to a mood.
OracleMood oracleMoodFromLegacy(String pose) => switch (pose) {
      'idle' || 'hero_wave' => OracleMood.idle,
      'happy' || 'cheer' => OracleMood.happy,
      'alert' => OracleMood.alert,
      'calm' => OracleMood.calm,
      'confused' => OracleMood.error,
      'craft' || 'present' => OracleMood.holo,
      'power' => OracleMood.win,
      'sleep' => OracleMood.sleep,
      'spin' => OracleMood.spin,
      'think' || 'focus' => OracleMood.think,
      'play' => OracleMood.play,
      'win' || 'excited' => OracleMood.win,
      'greet' || 'wave' => OracleMood.greet,
      _ => OracleMood.idle,
    };

enum _Reaction { none, giggle, spin, wink }

/// Animated ORACLE robot: floats, blinks, pulses its glow, tilts its head, switches pose by
/// [mood] and reacts to taps (giggle, spin, wink). Respects reduced motion.
class OracleMascot extends ConsumerStatefulWidget {
  const OracleMascot({
    super.key,
    this.mood = OracleMood.idle,
    this.size = 120,
    this.interactive = true,
    this.glow = true,
    this.onTap,
    this.onLongPress,
  });
  final OracleMood mood;
  final double size;
  final bool interactive;
  final bool glow;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  ConsumerState<OracleMascot> createState() => _OracleMascotState();
}

class _OracleMascotState extends ConsumerState<OracleMascot>
    with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3600));
  late final AnimationController _react = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 820));
  final math.Random _rng = math.Random();
  Timer? _blinkTimer;
  bool _blink = false;
  _Reaction _reaction = _Reaction.none;
  int _tapCount = 0;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    _react.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _reaction = _Reaction.none);
      }
    });
    _scheduleBlink();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    final int cw = (widget.size * 2.2).round();
    for (final String p in <String>['content', 'laugh', 'spin', 'excited']) {
      precacheImage(
              ResizeImage(AssetImage(Nx2Assets.oracle(p)), width: cw), context)
          .catchError((Object _) {});
    }
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer =
        Timer(Duration(milliseconds: 2600 + _rng.nextInt(3200)), () {
      if (!mounted) return;
      final bool reduced = ref.read(settingsProvider).reducedMotion;
      if (!reduced && _reaction == _Reaction.none && _blinkable) {
        setState(() => _blink = true);
        Timer(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _blink = false);
        });
      }
      _scheduleBlink();
    });
  }

  bool get _blinkable =>
      widget.mood == OracleMood.idle ||
      widget.mood == OracleMood.happy ||
      widget.mood == OracleMood.greet;

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _loop.dispose();
    _react.dispose();
    super.dispose();
  }

  void _tap() {
    if (!widget.interactive) {
      widget.onTap?.call();
      return;
    }
    HapticFeedback.lightImpact();
    const List<_Reaction> order = <_Reaction>[
      _Reaction.giggle,
      _Reaction.spin,
      _Reaction.wink
    ];
    setState(() {
      _reaction = order[_tapCount % order.length];
      _tapCount++;
    });
    _react.forward(from: 0);
    widget.onTap?.call();
  }

  String get _pose {
    switch (_reaction) {
      case _Reaction.giggle:
        return 'laugh';
      case _Reaction.spin:
        return 'spin';
      case _Reaction.wink:
        return 'excited';
      case _Reaction.none:
        break;
    }
    if (_blink) return 'content';
    return oracleMoodPose(widget.mood);
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = ref.watch(settingsProvider).reducedMotion;
    if (reduced) {
      if (_loop.isAnimating) _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
    final double s = widget.size;
    final Widget img = Image.asset(
      Nx2Assets.oracle(_pose),
      key: ValueKey<String>(_pose),
      width: s,
      height: s,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      cacheWidth: (s * 2.2).round(),
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.smart_toy_rounded, size: s * 0.7, color: const Color(0xFF35D6FF)),
    );
    final Widget body = AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_loop, _react]),
      child: img,
      builder: (BuildContext context, Widget? child) {
        final double t = _loop.value * 2 * math.pi;
        final double bob = reduced ? 0 : math.sin(t) * s * 0.035;
        final double tilt = reduced ? 0 : math.sin(t * 0.5 + 0.6) * 0.045;
        final double pulse = reduced ? 0.5 : 0.5 + 0.5 * math.sin(t * 1.5);
        final double r = _react.value;
        double dx = 0, dy = 0, rot = tilt, sc = 1;
        switch (_reaction) {
          case _Reaction.giggle:
            dx = math.sin(r * math.pi * 10) * s * 0.03 * (1 - r);
            sc = 1 + 0.06 * math.sin(r * math.pi);
          case _Reaction.spin:
            rot = tilt + Curves.easeInOutBack.transform(r) * 2 * math.pi;
          case _Reaction.wink:
            dy = -math.sin(r * math.pi) * s * 0.16;
            sc = 1 + 0.08 * math.sin(r * math.pi);
          case _Reaction.none:
            break;
        }
        return SizedBox(
          width: s,
          height: s,
          child: Stack(alignment: Alignment.center, children: <Widget>[
            if (widget.glow)
              Positioned(
                bottom: s * 0.02,
                child: Container(
                  width: s * (0.62 + 0.08 * pulse),
                  height: s * 0.16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.elliptical(s, s * 0.2)),
                    gradient: RadialGradient(colors: <Color>[
                      const Color(0xFF35D6FF).withValues(alpha: 0.35 + 0.3 * pulse),
                      const Color(0x0035D6FF),
                    ]),
                  ),
                ),
              ),
            if (widget.glow)
              Container(
                width: s * 0.8,
                height: s * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: <Color>[
                    const Color(0xFF8B3DFF).withValues(alpha: 0.16 + 0.14 * pulse),
                    const Color(0x008B3DFF),
                  ]),
                ),
              ),
            Transform.translate(
              offset: Offset(dx, bob + dy),
              child: Transform.rotate(
                angle: rot,
                child: Transform.scale(scale: sc, child: child),
              ),
            ),
          ]),
        );
      },
    );
    if (!widget.interactive && widget.onTap == null && widget.onLongPress == null) {
      return ExcludeSemantics(child: body);
    }
    return Semantics(
      button: true,
      label: 'ORACLE',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        onLongPress: widget.onLongPress,
        child: body,
      ),
    );
  }
}

/// Playful ORACLE that now and then peeks in from the screen edge or pokes the coin counter.
/// Put it in a Stack over a page. Does nothing with reduced motion.
class OracleMischief extends ConsumerStatefulWidget {
  const OracleMischief({super.key, this.coinPoke, this.onCaught});

  /// Incremented when ORACLE pokes the coins (the coin pill listens and wiggles).
  final ValueNotifier<int>? coinPoke;

  /// Tapping the peeking robot (e.g. open ORACLE).
  final VoidCallback? onCaught;

  @override
  ConsumerState<OracleMischief> createState() => _OracleMischiefState();
}

enum _Prank { none, peek, poke }

class _OracleMischiefState extends ConsumerState<OracleMischief>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3400));
  final math.Random _rng = math.Random();
  Timer? _next;
  _Prank _prank = _Prank.none;
  double _y = 0.4;
  bool _poked = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    _c.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _prank = _Prank.none);
        _schedule();
      }
    });
    _schedule(first: true);
  }

  void _schedule({bool first = false}) {
    _next?.cancel();
    final int base = first ? 9000 : 24000;
    _next = Timer(Duration(milliseconds: base + _rng.nextInt(16000)), () {
      if (!mounted) return;
      if (ref.read(settingsProvider).reducedMotion) {
        _schedule();
        return;
      }
      setState(() {
        _prank = _rng.nextBool() ? _Prank.peek : _Prank.poke;
        _y = 0.3 + _rng.nextDouble() * 0.35;
        _poked = false;
      });
      _c.forward(from: 0);
    });
  }

  void _onTick() {
    if (_prank == _Prank.poke && !_poked && _c.value > 0.42) {
      _poked = true;
      final ValueNotifier<int>? n = widget.coinPoke;
      if (n != null) n.value = n.value + 1;
    }
  }

  @override
  void dispose() {
    _next?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// 0 hidden → 1 fully in → hold → 0.
  double get _inOut {
    final double v = _c.value;
    if (v < 0.2) return Curves.easeOutBack.transform(v / 0.2);
    if (v > 0.8) return Curves.easeIn.transform(1 - (v - 0.8) / 0.2);
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    if (_prank == _Prank.none) return const SizedBox.shrink();
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      return AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? _) {
          final double k = _inOut;
          if (_prank == _Prank.peek) {
            const double size = 96;
            // Peeks from the end edge, leaning in.
            final double hidden = size * 0.95;
            final double shown = size * 0.42;
            final double off = hidden - (hidden - shown) * k;
            return Stack(children: <Widget>[
              Positioned(
                top: c.maxHeight * _y,
                right: rtl ? null : -off,
                left: rtl ? -off : null,
                child: Transform.rotate(
                  angle: rtl ? 0.35 : -0.35,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _c.animateTo(1, duration: const Duration(milliseconds: 300));
                      widget.onCaught?.call();
                    },
                    child: const OracleMascot(
                        size: size,
                        mood: OracleMood.curious,
                        interactive: false,
                        glow: false),
                  ),
                ),
              ),
            ]);
          }
          // Poke: drops in from the top next to the coin counter (top end) and points at it.
          const double size = 64;
          final double top = -size + (size + 58) * k;
          return Stack(children: <Widget>[
            Positioned(
              top: top,
              right: rtl ? null : 92,
              left: rtl ? 92 : null,
              child: Transform.scale(
                scaleX: rtl ? 1 : -1,
                child: const OracleMascot(
                    size: size,
                    mood: OracleMood.point,
                    interactive: false,
                    glow: false),
              ),
            ),
          ]);
        },
      );
    });
  }
}
