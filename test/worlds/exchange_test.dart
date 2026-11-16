import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/catalog/catalog.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/worlds/nexora_exchange/core/exchange_rules.dart';
import 'package:nexora/worlds/nexora_exchange/core/exchange_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<String> _ids(List<CatalogItem> l) => l.map((CatalogItem i) => i.id).toList();

void main() {
  group('featured rotation', () {
    test('same date gives the same featured items (deterministic)', () {
      final DateTime d = DateTime(2026, 11, 12, 9, 30);
      final List<String> a = _ids(featuredForDate(d));
      final List<String> b = _ids(featuredForDate(DateTime(2026, 11, 12, 23, 59)));
      expect(a, b);
      expect(a.length, 4);
      expect(a.toSet().length, 4, reason: 'no duplicates');
    });

    test('only paid items are featured and the list changes across days', () {
      final Set<String> seen = <String>{};
      for (int i = 0; i < 7; i++) {
        final List<CatalogItem> f = featuredForDate(DateTime(2026, 1, 1).add(Duration(days: i)));
        for (final CatalogItem it in f) {
          expect(it.price, greaterThan(0));
        }
        seen.add(_ids(f).join(','));
      }
      expect(seen.length, greaterThan(1));
    });

    test('rotation countdown reaches local midnight', () {
      final Duration left = timeUntilRotation(DateTime(2026, 11, 12, 23, 0, 0));
      expect(left, const Duration(hours: 1));
      final Duration full = timeUntilRotation(DateTime(2026, 11, 12));
      expect(full.inHours, 24);
    });
  });

  group('purchase rules', () {
    final CatalogItem frame = catalogItem('frame_holo_8')!;
    final CatalogItem tiara = catalogItem('gear_tiara')!;

    test('checkPurchase order of checks', () {
      expect(checkPurchase(item: null, level: 1, coins: 999, owned: false), PurchaseStatus.unknownItem);
      expect(checkPurchase(item: frame, level: 1, coins: 999, owned: true), PurchaseStatus.alreadyOwned);
      expect(checkPurchase(item: tiara, level: 1, coins: 9999, owned: false), PurchaseStatus.levelLocked);
      expect(checkPurchase(item: frame, level: 1, coins: frame.price - 1, owned: false), PurchaseStatus.notEnoughCoins);
      expect(checkPurchase(item: frame, level: 1, coins: frame.price, owned: false), PurchaseStatus.ok);
    });

    test('rarity rank is fixed', () {
      expect(rarityRank('legendary') > rarityRank('epic'), isTrue);
      expect(rarityRank('epic') > rarityRank('rare'), isTrue);
      expect(rarityRank('rare') > rarityRank('common'), isTrue);
      expect(themeNameOf('theme_nebula'), 'nebula');
    });
  });

  group('exchange service with wallet', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalStore.init();
    });

    test('buy moves coins once, never twice, never negative', () {
      final ProfileService p = ProfileService(LocalStore.instance);
      final CatalogItem frame = catalogItem('frame_holo_8')!;
      final int start = p.coins;
      expect(ExchangeService.buy(p, frame), PurchaseStatus.ok);
      expect(p.coins, start - frame.price);
      expect(p.owns(frame.id), isTrue);
      // Double spend attempt.
      expect(ExchangeService.buy(p, frame), PurchaseStatus.alreadyOwned);
      expect(p.coins, start - frame.price);
      // Not enough coins: nothing moves.
      final CatalogItem jacket = catalogItem('gear_jacket')!;
      final int before = p.coins;
      expect(before < jacket.price, isTrue);
      expect(ExchangeService.buy(p, jacket), PurchaseStatus.notEnoughCoins);
      expect(p.coins, before);
      expect(p.owns(jacket.id), isFalse);
      expect(p.coins >= 0, isTrue);
      expect(ExchangeService.purchaseHistory(p).length, 1);
    });

    test('level lock blocks purchase even with coins', () {
      final ProfileService p = ProfileService(LocalStore.instance);
      p.award('test', coins: 5000);
      final CatalogItem orb = catalogItem('gear_planet_orb')!;
      final int coins = p.coins;
      expect(ExchangeService.buy(p, orb), PurchaseStatus.levelLocked);
      expect(p.coins, coins);
      expect(p.owns(orb.id), isFalse);
    });

    test('equip only owned items; themes switch orbit theme', () {
      final ProfileService p = ProfileService(LocalStore.instance);
      final CatalogItem nebula = catalogItem('theme_nebula')!;
      expect(ExchangeService.equip(p, nebula), isFalse);
      expect(ExchangeService.buy(p, nebula), PurchaseStatus.ok);
      expect(ExchangeService.equip(p, nebula), isTrue);
      expect(p.orbitTheme, 'nebula');
      expect(ExchangeService.isEquipped(p, nebula), isTrue);
      expect(ExchangeService.unequip(p, nebula), isFalse);
    });
  });
}
