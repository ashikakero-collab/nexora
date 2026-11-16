// خالص Dart: بدون Flutter. قابل تست واحد و قابل استفاده روی سرور.
//
// نسخه‌ی کامل: حدود ۵۶ ثانیه (بازه‌ی ۴۵–۶۰ ثانیه‌ی P-spec).
// نسخه‌ی کوتاه: ۱۰ ثانیه برای ورودهای بعدی و حالت «کاهش حرکت».

enum JourneyScene { identity, cruiser, interior, departure, stationReveal, landing, hub }

class _Spec {
  const _Spec(this.scene, this.full, this.short, {this.inShort = false});
  final JourneyScene scene;
  final Duration full;
  final Duration short;
  final bool inShort;
}

class CinematicFrame {
  const CinematicFrame({
    required this.scene,
    required this.progress,
    required this.index,
    required this.finished,
  });

  final JourneyScene scene;
  /// پیشرفت درون این صحنه، بین ۰ و ۱
  final double progress;
  final int index;
  final bool finished;
}

class CinematicTimeline {
  CinematicTimeline({this.short = false})
      : _entries = [
          for (final s in _specs)
            if (!short || s.inShort) (s.scene, short ? s.short : s.full),
        ];

  static const List<_Spec> _specs = [
    _Spec(JourneyScene.identity, Duration(seconds: 6), Duration(seconds: 2), inShort: true),
    _Spec(JourneyScene.cruiser, Duration(seconds: 6), Duration(seconds: 2), inShort: true),
    _Spec(JourneyScene.interior, Duration(seconds: 8), Duration.zero),
    _Spec(JourneyScene.departure, Duration(seconds: 12), Duration.zero),
    _Spec(JourneyScene.stationReveal, Duration(seconds: 8), Duration(seconds: 3), inShort: true),
    _Spec(JourneyScene.landing, Duration(seconds: 8), Duration.zero),
    _Spec(JourneyScene.hub, Duration(seconds: 8), Duration(seconds: 3), inShort: true),
  ];

  final bool short;
  final List<(JourneyScene, Duration)> _entries;

  Duration get total => _entries.fold(Duration.zero, (sum, e) => sum + e.$2);

  List<JourneyScene> get scenes => [for (final e in _entries) e.$1];

  CinematicFrame frameAt(Duration t) {
    var start = Duration.zero;
    for (var i = 0; i < _entries.length; i++) {
      final (scene, length) = _entries[i];
      final end = start + length;
      if (t < end) {
        final local = (t - start).inMicroseconds / length.inMicroseconds;
        return CinematicFrame(
          scene: scene,
          progress: local.clamp(0.0, 1.0).toDouble(),
          index: i,
          finished: false,
        );
      }
      start = end;
    }
    final last = _entries.length - 1;
    return CinematicFrame(
      scene: _entries[last].$1,
      progress: 1.0,
      index: last,
      finished: true,
    );
  }
}
