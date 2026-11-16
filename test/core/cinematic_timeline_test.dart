import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/worlds/journey/cinematic_timeline.dart';

void main() {
  test('نسخه‌ی کامل بین ۴۵ و ۶۰ ثانیه است', () {
    final t = CinematicTimeline();
    expect(t.total.inSeconds, inInclusiveRange(45, 60));
  });

  test('نسخه‌ی کوتاه ۱۰ ثانیه است و صحنه‌های کوتاه را دارد', () {
    final t = CinematicTimeline(short: true);
    expect(t.total.inSeconds, 10);
    expect(t.scenes, [
      JourneyScene.identity,
      JourneyScene.cruiser,
      JourneyScene.stationReveal,
      JourneyScene.hub,
    ]);
  });

  test('ترتیب صحنه‌های کامل همان سفر تعریف‌شده است', () {
    expect(CinematicTimeline().scenes, [
      JourneyScene.identity,
      JourneyScene.cruiser,
      JourneyScene.interior,
      JourneyScene.departure,
      JourneyScene.stationReveal,
      JourneyScene.landing,
      JourneyScene.hub,
    ]);
  });

  test('لحظه‌ی صفر اولین صحنه و پیشرفت صفر است', () {
    final f = CinematicTimeline().frameAt(Duration.zero);
    expect(f.scene, JourneyScene.identity);
    expect(f.progress, 0.0);
    expect(f.finished, isFalse);
  });

  test('بعد از پایان مدت، finished و آخرین صحنه برمی‌گردد', () {
    final t = CinematicTimeline();
    final f = t.frameAt(t.total + const Duration(seconds: 1));
    expect(f.finished, isTrue);
    expect(f.scene, JourneyScene.hub);
    expect(f.progress, 1.0);
  });

  test('مرز بین دو صحنه درست جابه‌جا می‌شود', () {
    final t = CinematicTimeline();
    // صحنه‌ی اول ۶ ثانیه است؛ در ۶.۵ ثانیه باید صحنه‌ی دوم باشد
    final f = t.frameAt(const Duration(milliseconds: 6500));
    expect(f.scene, JourneyScene.cruiser);
    expect(f.index, 1);
    expect(f.progress, closeTo(0.5 / 6, 0.001));
  });
}
