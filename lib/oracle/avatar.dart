// v4 animated Oracle: the owner's waving-robot video cut into 46 alpha frames (assets/g/v4/oracle_wave/w00..w45,
// 360 px tall, keyed from black). Plays the wave on greeting / tap, otherwise idles with a procedural float, a
// breathing scale and an orange glow pulse; reacts to moods (goal, win, loss, tips) with a hop / shake and pops the
// matching pose from assets/g/oracle/oracle_<mood>.webp as a small hologram emote. Plus a typewriter speech bubble.
import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/theme.dart';
import '../ui/kit.dart';
import '../ui/v4.dart';
import 'oracle.dart';

const int kOracleFrames = 46;
String oracleFrame(int i) => 'assets/g/v4/oracle_wave/w${i.toString().padLeft(2, '0')}.webp';

/// Decode every wave frame once (call early: intro / home) so the loop never flickers.
Future<void> precacheOracle(BuildContext context, {double height = 220}) async {
  final h = (height * MediaQuery.devicePixelRatioOf(context)).round().clamp(64, 360);
  for (var i = 0; i < kOracleFrames; i++) {
    if (!context.mounted) return;
    await precacheImage(ResizeImage(AssetImage(oracleFrame(i)), height: h, policy: ResizeImagePolicy.fit), context).catchError((_) {});
  }
}

class OracleAvatar extends StatefulWidget {
  final double size; // height in dp
  final bool waveOnStart;
  final bool listen; // follow Oracle.i.mood (reactions) automatically
  final String? mood; // explicit mood (overrides listen)
  final VoidCallback? onTap;
  final bool glow;
  const OracleAvatar({super.key, this.size = 160, this.waveOnStart = true, this.listen = true, this.mood, this.onTap, this.glow = true});
  @override
  State<OracleAvatar> createState() => OracleAvatarState();
}

class OracleAvatarState extends State<OracleAvatar> with TickerProviderStateMixin {
  late final AnimationController idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();
  late final AnimationController wave = AnimationController(vsync: this, duration: const Duration(milliseconds: kOracleFrames * 95));
  late final AnimationController hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  String? emote, _lastMood;
  String _react = 'hop';
  Timer? _emoteT, _auto;
  bool _cached = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.mood != null) {
        react(widget.mood!);
      } else if (widget.waveOnStart) {
        playWave();
      }
    });
    if (widget.listen) Oracle.i.addListener(_onOracle);
    _scheduleAuto();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_cached) {
      _cached = true;
      precacheOracle(context, height: widget.size);
    }
  }

  @override
  void didUpdateWidget(OracleAvatar o) {
    super.didUpdateWidget(o);
    if (widget.mood != o.mood && widget.mood != null) react(widget.mood!);
  }

  void _onOracle() {
    final m = Oracle.i.mood;
    if (m == _lastMood) return;
    _lastMood = m;
    if (m != 'idle' && m != 'sleep') react(m);
  }

  void _scheduleAuto() {
    _auto?.cancel();
    _auto = Timer(Duration(seconds: 9 + math.Random().nextInt(8)), () {
      if (!mounted) return;
      if (TickerMode.valuesOf(context).enabled && !wave.isAnimating) playWave();
      _scheduleAuto();
    });
  }

  void playWave() {
    if (!mounted) return;
    wave.forward(from: 0);
  }

  /// Show a reaction: excited/joy/laugh/happy hop, alert/confused shake, idea/present nod, wave/hello waves.
  void react(String mood) {
    if (!mounted) return;
    if (mood == 'wave' || mood == 'hello') {
      playWave();
      return;
    }
    _react = switch (mood) { 'alert' || 'confused' || 'sleep' => 'shake', 'idea' || 'present' || 'focus' || 'curious' => 'nod', _ => 'hop' };
    hop.forward(from: 0);
    if (kORACLE.containsKey(mood)) {
      setState(() => emote = mood);
      _emoteT?.cancel();
      _emoteT = Timer(const Duration(milliseconds: 2400), () {
        if (mounted) setState(() => emote = null);
      });
    }
    if (mood == 'excited' || mood == 'joy' || mood == 'happy' || mood == 'laugh' || mood == 'spin') {
      Timer(const Duration(milliseconds: 250), playWave);
    }
  }

  @override
  void dispose() {
    if (widget.listen) Oracle.i.removeListener(_onOracle);
    _emoteT?.cancel();
    _auto?.cancel();
    idle.dispose();
    wave.dispose();
    hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size, w = s * 315 / 360;
    final hpx = (s * MediaQuery.devicePixelRatioOf(context)).round().clamp(64, 360);
    return GestureDetector(
      onTap: () {
        playWave();
        widget.onTap?.call();
      },
      child: SizedBox(
        width: w,
        height: s,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([idle, wave, hop]),
            builder: (_, __) {
              final t = idle.value * 2 * math.pi;
              final bob = math.sin(t) * s * .025;
              final breath = 1 + math.sin(t * 2) * .012;
              final gp = .5 + .5 * math.sin(t);
              final hv = hop.value;
              double dx = 0, dy = 0, rot = 0;
              if (hop.isAnimating || (hv > 0 && hv < 1)) {
                switch (_react) {
                  case 'shake':
                    dx = math.sin(hv * math.pi * 8) * s * .03 * (1 - hv);
                  case 'nod':
                    rot = math.sin(hv * math.pi * 2) * .06 * (1 - hv);
                  default:
                    dy = -math.sin(hv * math.pi) * s * .12;
                }
              }
              final fi = wave.isAnimating ? (wave.value * (kOracleFrames - 1)).round().clamp(0, kOracleFrames - 1) : 0;
              return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                if (widget.glow)
                  Positioned(
                    bottom: s * .02,
                    child: Container(
                      width: w * (.75 + gp * .1),
                      height: s * .16,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(s),
                        gradient: RadialGradient(colors: [N.orange.withValues(alpha: .45 + gp * .25), N.orange.withValues(alpha: 0)]),
                      ),
                    ),
                  ),
                if (widget.glow && hq)
                  Container(
                    width: w * .8,
                    height: w * .8,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [N.orange.withValues(alpha: .14 + gp * .1), N.orange.withValues(alpha: 0)])),
                  ),
                Transform.translate(
                  offset: Offset(dx, bob + dy),
                  child: Transform.rotate(
                    angle: rot,
                    child: Transform.scale(
                      scale: breath,
                      child: Image(
                        image: ResizeImage(AssetImage(oracleFrame(fi)), height: hpx, policy: ResizeImagePolicy.fit),
                        width: w,
                        height: s,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, __, ___) => Image.asset(V4.oracle, width: w, height: s, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
                if (emote != null)
                  Positioned(
                    top: -s * .02,
                    right: -s * .08,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(emote),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutBack,
                      builder: (_, v, ch) => Opacity(opacity: v.clamp(0, 1), child: Transform.scale(scale: .4 + v * .6, child: ch)),
                      child: Container(
                        width: s * .36,
                        height: s * .36,
                        padding: EdgeInsets.all(s * .03),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xcc0a1236),
                          border: Border.all(color: N.orange.withValues(alpha: .8), width: 1.4),
                          boxShadow: hq ? [BoxShadow(color: N.orange.withValues(alpha: .4), blurRadius: 10)] : null,
                        ),
                        child: Img(oracleImg(emote!), w: s * .3, h: s * .3),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// Speech bubble with a typewriter reveal (restarts whenever [text] changes).
class OracleBubble extends StatelessWidget {
  final String text;
  final Widget? footer;
  final VoidCallback? onClose;
  final double maxWidth;
  final int msPerChar;
  const OracleBubble(this.text, {super.key, this.footer, this.onClose, this.maxWidth = 320, this.msPerChar = 24});
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: NeonPanel(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          glowOn: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (onClose != null) GestureDetector(onTap: onClose, child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close_rounded, size: 18, color: C.dim))),
              Expanded(
                child: TweenAnimationBuilder<int>(
                  key: ValueKey(text),
                  tween: IntTween(begin: 0, end: text.characters.length),
                  duration: Duration(milliseconds: math.min(4000, text.characters.length * msPerChar)),
                  builder: (_, n, __) => Stack(children: [
                    // invisible full text reserves the final size (no jumping layout)
                    Opacity(opacity: 0, child: T(text, size: 13, height: 1.65, align: TextAlign.right)),
                    T(text.characters.take(n).toString(), size: 13, height: 1.65, color: const Color(0xfff2f5ff), align: TextAlign.right),
                  ]),
                ),
              ),
            ]),
            if (footer != null) Padding(padding: const EdgeInsets.only(top: 10), child: footer!),
          ]),
        ),
      );
}
