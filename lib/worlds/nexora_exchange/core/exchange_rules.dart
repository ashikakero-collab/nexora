/// NEXORA EXCHANGE — pure economy rules (no Flutter imports).
///
/// P26 / Vision §5.7: transparent prices, no gambling, no betting, no random
/// paid rewards. "Featured today" is a deterministic rotation computed from
/// the calendar date only, so every user sees the same featured items on the
/// same day and nothing about money is random.
library;

import '../../../core/catalog/catalog.dart';

enum PurchaseStatus { ok, alreadyOwned, levelLocked, notEnoughCoins, unknownItem }

/// Validates a purchase before any coins move.
PurchaseStatus checkPurchase({
  required CatalogItem? item,
  required int level,
  required int coins,
  required bool owned,
}) {
  if (item == null) return PurchaseStatus.unknownItem;
  if (owned) return PurchaseStatus.alreadyOwned;
  if (level < item.minLevel) return PurchaseStatus.levelLocked;
  if (item.price < 0 || coins < item.price) return PurchaseStatus.notEnoughCoins;
  return PurchaseStatus.ok;
}

/// Seed derived from the local calendar date only.
int dateSeed(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

int _next(int s) => (s * 1103515245 + 12345) & 0x7fffffff;

/// Deterministic daily "Featured today" rotation. Only paid items are featured
/// (starter items are already owned). Same date => same list, always.
List<CatalogItem> featuredForDate(DateTime date, {List<CatalogItem>? pool, int count = 4}) {
  final List<CatalogItem> items =
      List<CatalogItem>.of((pool ?? kCatalog).where((CatalogItem i) => i.price > 0));
  items.sort((CatalogItem a, CatalogItem b) => a.id.compareTo(b.id));
  int s = dateSeed(date);
  // Warm up the generator so consecutive dates diverge quickly.
  for (int i = 0; i < 3; i++) {
    s = _next(s);
  }
  for (int i = items.length - 1; i > 0; i--) {
    s = _next(s);
    final int j = s % (i + 1);
    final CatalogItem tmp = items[i];
    items[i] = items[j];
    items[j] = tmp;
  }
  final int n = count < items.length ? count : items.length;
  return items.sublist(0, n);
}

/// Time left until the featured rotation changes (local midnight).
Duration timeUntilRotation(DateTime now) {
  final DateTime next = DateTime(now.year, now.month, now.day + 1);
  return next.difference(now);
}

List<CatalogItem> itemsInCategory(ItemCategory c) => kCatalog.where((CatalogItem i) => i.category == c).toList();

/// Fixed rarity order for sorting (purely visual, never random).
int rarityRank(String rarity) {
  switch (rarity) {
    case 'legendary':
      return 3;
    case 'epic':
      return 2;
    case 'rare':
      return 1;
    default:
      return 0;
  }
}

/// Theme id inside the Personal Orbit ('theme_nebula' -> 'nebula').
String themeNameOf(String itemId) => itemId.startsWith('theme_') ? itemId.substring(6) : itemId;
