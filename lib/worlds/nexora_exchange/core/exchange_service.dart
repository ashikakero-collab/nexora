import '../../../core/catalog/catalog.dart';
import '../../../core/profile/profile_service.dart';
import 'exchange_rules.dart';

/// Glue between the pure rules and the local [ProfileService] wallet.
/// Offline the profile is authoritative; online the same calls go through a
/// server RPC that performs the atomic transaction (STEP_28).
class ExchangeService {
  ExchangeService._();

  static PurchaseStatus status(ProfileService p, CatalogItem item) =>
      checkPurchase(item: item, level: p.level, coins: p.coins, owned: p.owns(item.id));

  /// Buys [item]. Coins move only when every rule passes; never negative, never twice.
  static PurchaseStatus buy(ProfileService p, CatalogItem item) {
    final PurchaseStatus st = status(p, item);
    if (st != PurchaseStatus.ok) return st;
    final bool ok = p.purchase(item.id, item.price, nameFa: item.nameFa, nameEn: item.nameEn);
    if (ok) return PurchaseStatus.ok;
    return p.owns(item.id) ? PurchaseStatus.alreadyOwned : PurchaseStatus.notEnoughCoins;
  }

  static bool isEquipped(ProfileService p, CatalogItem item) {
    if (item.category == ItemCategory.theme) return p.orbitTheme == themeNameOf(item.id);
    if (item.category == ItemCategory.decor) return p.decorLayout.containsKey(item.id);
    final String? slot = item.slot;
    if (slot == null) return false;
    return p.equipped[slot] == item.id;
  }

  /// Equips (or for decor: places in the Personal Orbit room). Owned items only.
  static bool equip(ProfileService p, CatalogItem item) {
    if (!p.owns(item.id)) return false;
    if (item.category == ItemCategory.theme) {
      p.setOrbitTheme(themeNameOf(item.id));
      return true;
    }
    if (item.category == ItemCategory.decor) {
      if (!p.decorLayout.containsKey(item.id)) {
        final int n = p.decorLayout.length;
        final double x = 0.25 + (n % 3) * 0.25;
        final double y = 0.55 + ((n ~/ 3) % 3) * 0.12;
        p.placeDecor(item.id, x, y, 1.0);
      }
      return true;
    }
    final String? slot = item.slot;
    if (slot == null) return false;
    p.equip(slot, item.id);
    return true;
  }

  /// Unequips / removes from room. Themes cannot be unequipped (one is always active).
  static bool unequip(ProfileService p, CatalogItem item) {
    if (item.category == ItemCategory.theme) return false;
    if (item.category == ItemCategory.decor) {
      p.removeDecor(item.id);
      return true;
    }
    final String? slot = item.slot;
    if (slot == null || p.equipped[slot] != item.id) return false;
    p.unequip(slot);
    return true;
  }

  /// Purchases recorded in the activity timeline (newest first).
  static List<ActivityEntry> purchaseHistory(ProfileService p) =>
      p.activity.where((ActivityEntry a) => a.kind == 'shop').toList();
}
