import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets/app_assets.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import 'journey_strings.dart';
import 'cinematic_timeline.dart';
import 'starfield_painter.dart';

/// THE FIRST JOURNEY: سفر سینمایی ورود.
/// - قابل رد کردن در هر لحظه (Skip)
/// - حالت کوتاه با [short] یا وقتی کاهش حرکت روشن است
/// - دوربین فقط وقتی کاهش حرکت خاموش است حرکت می‌کند
class JourneyPage extends ConsumerStatefulWidget {
  const JourneyPage({super.key, this.short = false, this.explorerId});

  final bool short;

  /// شناسه‌ی اکتشافگر از سرور. تا STEP_06/08 نیست، null می‌ماند و پیام انتظار نشان داده می‌شود.
  final String? explorerId;

  @override
  ConsumerState<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends ConsumerState<JourneyPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  CinematicTimeline? _timeline;
  bool _reduced = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _finish();
          });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timeline != null) return;

    _reduced = ref.read(settingsProvider).reducedMotion ||
        MediaQuery.disableAnimationsOf(context);
    final timeline = CinematicTimeline(short: widget.short || _reduced);
    _timeline = timeline;
    _controller.duration = timeline.total;

    for (final path in [
      AppAssets.worldsHubShipNexoraCruiserNx01,
      AppAssets.worldsHubPropsCommandPlatformWide,
      AppAssets.worldsHubPropsCommandDeskMain
    ]) {
      precacheImage(AssetImage(path), context);
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    ref.read(settingsProvider).markJourneySeen();
    if (!mounted) return;
    final hasId = ref.read(profileProvider).hasIdentity;
    context.go(hasId ? '/hub' : '/onboarding');
  }

  void _skip() {
    _controller.stop();
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timeline;
    if (timeline == null) return const ColoredBox(color: NxColors.navy);
    final quality = ref.watch(settingsProvider).quality;
    final visual = NxThemeColors.of(context);

    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final elapsed = Duration(
            microseconds:
                (timeline.total.inMicroseconds * _controller.value).round(),
          );
          final frame = timeline.frameAt(elapsed);
          return Stack(
            fit: StackFit.expand,
            children: [
              _SceneStage(
                frame: frame,
                quality: quality,
                reduced: _reduced,
                explorerId:
                    widget.explorerId ?? ref.read(profileProvider).explorerId,
              ),
              PositionedDirectional(
                top: MediaQuery.paddingOf(context).top + 8,
                end: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: visual.background.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: visual.border.withValues(alpha: 0.7)),
                  ),
                  child: TextButton(
                    onPressed: _skip,
                    style: TextButton.styleFrom(foregroundColor: visual.text),
                    child: Text(tr('journey_skip', fa: context.isFa)),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 56,
                child: _Caption(scene: frame.scene),
              ),
              if (frame.finished)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 140,
                  child: Center(
                    child: FilledButton(
                      onPressed: _finish,
                      child: Text(tr('journey_continue', fa: context.isFa)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SceneStage extends StatelessWidget {
  const _SceneStage({
    required this.frame,
    required this.quality,
    required this.reduced,
    this.explorerId,
  });

  final CinematicFrame frame;
  final GraphicsQuality quality;
  final bool reduced;
  final String? explorerId;

  @override
  Widget build(BuildContext context) {
    final cam = _cameraFor(frame.scene, frame.progress, reduced);
    return LayoutBuilder(
      builder: (context, box) {
        return ClipRect(
          child: Transform.translate(
            offset: Offset(cam.dx * box.maxWidth, cam.dy * box.maxHeight),
            child: Transform.scale(
              scale: cam.scale,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                child: KeyedSubtree(
                  key: ValueKey(frame.scene),
                  child: _content(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content() {
    final stars = switch (quality) {
      GraphicsQuality.low => 50,
      GraphicsQuality.medium => 120,
      GraphicsQuality.high => 220,
      GraphicsQuality.ultra => 320,
    };
    final p = frame.progress;

    switch (frame.scene) {
      case JourneyScene.identity:
        return _layer(
          stars: stars,
          child: Center(child: _IdentityCard(explorerId: explorerId)),
        );

      case JourneyScene.cruiser:
        return _layer(
          stars: stars,
          child: Center(
            child: Opacity(
              opacity: _fade(p),
              child: Image.asset(AppAssets.worldsHubShipNexoraCruiserNx01,
                  width: 300),
            ),
          ),
        );

      case JourneyScene.interior:
        return SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(AppAssets.worldsHubPropsCommandDeskMain,
                  fit: BoxFit.contain),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC0A0F2C)],
                  ),
                ),
              ),
            ],
          ),
        );

      case JourneyScene.departure:
        return _layer(
          stars: stars,
          warp: p,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned(
                right: 24,
                top: 90,
                child: _Planet(
                  size: 140,
                  colors: [NxColors.turquoise, NxColors.violet, NxColors.navy],
                ),
              ),
              const Positioned(
                left: -60,
                bottom: 80,
                child: _Planet(
                  size: 220,
                  colors: [NxColors.electricBlue, NxColors.navy],
                ),
              ),
              Center(
                child: Transform.translate(
                  offset: Offset(0, -p * 160),
                  child: Opacity(
                    opacity: 1 - p * 0.6,
                    child: Image.asset(AppAssets.worldsHubShipNexoraCruiserNx01,
                        width: 260),
                  ),
                ),
              ),
            ],
          ),
        );

      case JourneyScene.stationReveal:
        return _layer(
          stars: stars,
          child: Center(
            child: Opacity(
              opacity: _fade(p),
              child: Transform.scale(
                scale: 0.9 + 0.1 * p,
                child: Image.asset(AppAssets.worldsHubPropsCommandPlatformWide,
                    width: 300),
              ),
            ),
          ),
        );

      case JourneyScene.landing:
        return SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                  child: Image.asset(
                      AppAssets.worldsHubPropsCommandPlatformWide,
                      width: 320)),
              _Doors(progress: p),
            ],
          ),
        );

      case JourneyScene.hub:
        return _layer(
          stars: stars,
          child: Center(
            child: Opacity(
              opacity: _fade(p),
              child: Image.asset(AppAssets.charactersOraclePosesHeroWave,
                  height: 320),
            ),
          ),
        );
    }
  }

  Widget _layer({required int stars, double warp = 0, required Widget child}) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: StarfieldPainter(count: stars, warp: warp),
        child: child,
      ),
    );
  }
}

/// دوربین: (مقیاس، جابه‌جایی افقی و عمودی به‌صورت کسری از اندازه‌ی صفحه)
({double scale, double dx, double dy}) _cameraFor(
  JourneyScene scene,
  double p,
  bool reduced,
) {
  if (reduced) return (scale: 1.0, dx: 0.0, dy: 0.0);
  double ease(double a, double b) =>
      a + (b - a) * Curves.easeInOut.transform(p);
  switch (scene) {
    case JourneyScene.identity:
      return (scale: 1.0, dx: 0.0, dy: 0.0);
    case JourneyScene.cruiser:
      return (scale: ease(1.0, 1.08), dx: 0.0, dy: 0.0);
    case JourneyScene.interior:
      return (scale: 1.1, dx: ease(0.12, -0.12), dy: 0.0);
    case JourneyScene.departure:
      return (scale: ease(1.3, 1.0), dx: 0.0, dy: 0.0);
    case JourneyScene.stationReveal:
      return (scale: ease(0.6, 1.0), dx: 0.0, dy: 0.0);
    case JourneyScene.landing:
      return (scale: ease(1.0, 1.3), dx: 0.0, dy: 0.0);
    case JourneyScene.hub:
      return (scale: 1.0, dx: 0.0, dy: 0.0);
  }
}

double _fade(double p) => (p * 2).clamp(0.0, 1.0).toDouble();

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({this.explorerId});
  final String? explorerId;

  @override
  Widget build(BuildContext context) {
    final visual = NxThemeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: visual.accent.withAlpha(190)),
        color: visual.surfaceRaised.withAlpha(230),
        boxShadow: [
          BoxShadow(
              color: visual.accent.withValues(alpha: 0.14), blurRadius: 26)
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('identity_label', fa: context.isFa),
              style: TextStyle(color: visual.text)),
          const SizedBox(height: 8),
          Text(
            explorerId ?? tr('identity_pending', fa: context.isFa),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: visual.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _Planet extends StatelessWidget {
  const _Planet({required this.size, required this.colors});
  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient:
            RadialGradient(center: const Alignment(-0.3, -0.3), colors: colors),
      ),
    );
  }
}

/// درهای ایستگاه: در ابتدا بسته‌اند و با پیشرفت باز می‌شوند.
class _Doors extends StatelessWidget {
  const _Doors({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth / 2) * (1 - progress);
        const door =
            DecoratedBox(decoration: BoxDecoration(color: NxColors.navy));
        return Stack(
          children: [
            Positioned(left: 0, top: 0, bottom: 0, width: width, child: door),
            Positioned(right: 0, top: 0, bottom: 0, width: width, child: door),
          ],
        );
      },
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.scene});
  final JourneyScene scene;

  static String _titleKey(JourneyScene s) => switch (s) {
        JourneyScene.identity => 'scene_identity_title',
        JourneyScene.cruiser => 'scene_cruiser_title',
        JourneyScene.interior => 'scene_interior_title',
        JourneyScene.departure => 'scene_departure_title',
        JourneyScene.stationReveal => 'scene_station_title',
        JourneyScene.landing => 'scene_landing_title',
        JourneyScene.hub => 'scene_hub_title',
      };

  static String _subKey(JourneyScene s) => switch (s) {
        JourneyScene.identity => 'scene_identity_sub',
        JourneyScene.cruiser => 'scene_cruiser_sub',
        JourneyScene.interior => 'scene_interior_sub',
        JourneyScene.departure => 'scene_departure_sub',
        JourneyScene.stationReveal => 'scene_station_sub',
        JourneyScene.landing => 'scene_landing_sub',
        JourneyScene.hub => 'scene_hub_sub',
      };

  @override
  Widget build(BuildContext context) {
    final visual = NxThemeColors.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Column(
        key: ValueKey(scene),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr(_titleKey(scene), fa: context.isFa),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: visual.text,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(_subKey(scene), fa: context.isFa),
            textAlign: TextAlign.center,
            style: TextStyle(color: visual.accent),
          ),
        ],
      ),
    );
  }
}
