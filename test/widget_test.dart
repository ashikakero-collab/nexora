import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/catalog/catalog.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
  });

  test('new profile has explorer id, starter coins and free items', () {
    final p = ProfileService(LocalStore.instance);
    expect(p.explorerId, matches(RegExp(r'^NX-[A-Z0-9]{4}-[A-Z0-9]{4}$')));
    expect(p.coins, 500);
    expect(p.owns('puck_nx_green'), isTrue);
    expect(p.level, 1);
  });

  test('xp levels and daily cap', () {
    final p = ProfileService(LocalStore.instance);
    p.award('test', xp: 100);
    expect(p.level, 2);
    p.award('farm', xp: 999999);
    expect(p.xp, ProfileService.dailyXpCap);
  });

  test('recordGame updates stats and unlocks first-game achievement', () {
    final p = ProfileService(LocalStore.instance);
    final o = p.recordGame(gameId: 'quiz', gameNameFa: 'کوییز', gameNameEn: 'Quiz', outcome: 'win', score: 9);
    expect(p.stats['quiz']!.won, 1);
    expect(o.unlocked.any((a) => a.id == 'first_game'), isTrue);
    expect(p.achievements.contains('first_game'), isTrue);
  });

  test('purchase is deterministic and cannot overspend', () {
    final p = ProfileService(LocalStore.instance);
    final item = catalogItem('gear_sunglasses')!;
    expect(p.purchase(item.id, item.price), isTrue);
    expect(p.purchase(item.id, item.price), isFalse, reason: 'already owned');
    expect(p.purchase('gear_planet_orb', 999999), isFalse);
  });

  test('profile persists across reloads', () {
    final p = ProfileService(LocalStore.instance);
    p.award('x', xp: 40, coins: 10);
    final again = ProfileService(LocalStore.instance);
    expect(again.explorerId, p.explorerId);
    expect(again.xp, 40);
    expect(again.coins, 510);
  });

  test('daily reward only once per day', () {
    final p = ProfileService(LocalStore.instance);
    expect(p.claimDaily(), isNotNull);
    expect(p.claimDaily(), isNull);
    expect(p.streak, 1);
  });
}
