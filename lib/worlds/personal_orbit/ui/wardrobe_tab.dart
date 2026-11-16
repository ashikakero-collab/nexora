import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/catalog/catalog.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import 'avatar_view.dart';
import 'po_common.dart';

/// Wardrobe: avatar gear grouped by slot + holo frames. Owned items equip /
/// unequip; unowned ones are shown locked and lead to the Exchange.
class WardrobeTab extends ConsumerWidget {
  const WardrobeTab({super.key});

  void _toggle(BuildContext context, ProfileService p, CatalogItem item) {
    final String? slot = item.slot;
    if (slot == null) return;
    if (!p.owns(item.id)) {
      _openShop(context, item);
      return;
    }
    if (p.equipped[slot] == item.id) {
      p.unequip(slot);
    } else {
      p.equip(slot, item.id);
    }
  }

  void _openShop(BuildContext context, CatalogItem item) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(poDigits(
          context,
          context.tx(
              '«${item.nameFa}» را می‌توانی با ${item.price} سکه از Exchange بخری.',
              '"${item.nameEn}" is available in the Exchange for ${item.price} coins.'))),
      action: SnackBarAction(
        label: context.tx('رفتن به Exchange', 'Open Exchange'),
        onPressed: () => context.push('/world/nexora_exchange'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final List<String> groups = <String>[...kAvatarSlots, 'frame'];
    final Map<String, List<CatalogItem>> bySlot = <String, List<CatalogItem>>{};
    for (final CatalogItem it in kCatalog) {
      final bool wearable = it.category == ItemCategory.avatarGear ||
          it.category == ItemCategory.frame;
      final String? slot = it.slot;
      if (!wearable || slot == null) continue;
      bySlot.putIfAbsent(slot, () => <CatalogItem>[]).add(it);
    }
    int owned = 0;
    int total = 0;
    for (final List<CatalogItem> l in bySlot.values) {
      for (final CatalogItem it in l) {
        total++;
        if (p.owns(it.id)) owned++;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.xl),
      children: <Widget>[
        PoCard(
          child: Row(children: <Widget>[
            const OrbitAvatar(size: 110),
            const SizedBox(width: NxSpace.md),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(context.tx('کمد لباس', 'Wardrobe'),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: PoColors.ink(context))),
                    const SizedBox(height: 4),
                    Text(
                        poDigits(
                            context,
                            context.tx('$owned از $total آیتم را داری',
                                'You own $owned of $total items')),
                        style: TextStyle(color: PoColors.inkDim(context))),
                    const SizedBox(height: 8),
                    PoProgressBar(value: total == 0 ? 0 : owned / total),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/world/nexora_exchange'),
                      icon: const Icon(Icons.storefront_rounded, size: 18),
                      label:
                          Text(context.tx('خرید آیتم جدید', 'Get new items')),
                    ),
                  ]),
            ),
          ]),
        ),
        for (final String slot in groups)
          if (bySlot[slot] != null) ...<Widget>[
            PoSectionTitle(
              avatarSlotName(context, slot),
              icon: slot == 'frame'
                  ? Icons.crop_square_rounded
                  : Icons.checkroom_rounded,
              trailing: p.equipped[slot] != null
                  ? TextButton(
                      onPressed: () => p.unequip(slot),
                      child: Text(context.tx('درآوردن', 'Unequip')),
                    )
                  : null,
            ),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: bySlot[slot]!.length,
                separatorBuilder: (BuildContext _, int __) =>
                    const SizedBox(width: NxSpace.sm),
                itemBuilder: (BuildContext ctx, int i) {
                  final CatalogItem it = bySlot[slot]![i];
                  return _GearTile(
                    item: it,
                    owned: p.owns(it.id),
                    equipped: p.equipped[slot] == it.id,
                    levelLocked: p.level < it.minLevel,
                    onTap: () => _toggle(ctx, p, it),
                  );
                },
              ),
            ),
          ],
      ],
    );
  }
}

class _GearTile extends StatelessWidget {
  const _GearTile({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.levelLocked,
    required this.onTap,
  });

  final CatalogItem item;
  final bool owned;
  final bool equipped;
  final bool levelLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color rc = poRarityColor(item.rarity);
    Widget img = Image.asset(
      item.asset,
      width: 64,
      height: 64,
      cacheWidth: 160,
      fit: BoxFit.contain,
      errorBuilder: (BuildContext _, Object __, StackTrace? ___) => Icon(
          Icons.auto_awesome,
          size: 40,
          color: owned ? rc : PoColors.locked(context)),
    );
    if (!owned) img = ColorFiltered(colorFilter: kPoGreyscale, child: img);

    return SizedBox(
      width: 112,
      child: Material(
        color: equipped ? visual.surfaceRaised : visual.surface,
        borderRadius: BorderRadius.circular(NxRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(NxRadius.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NxRadius.md),
              border: Border.all(
                  color: equipped
                      ? PoColors.mint(context)
                      : rc.withValues(alpha: owned ? 0.45 : 0.2),
                  width: equipped ? 2 : 1),
            ),
            child: Column(children: <Widget>[
              Stack(clipBehavior: Clip.none, children: <Widget>[
                img,
                if (!owned)
                  PositionedDirectional(
                    end: -4,
                    top: -4,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: PoColors.ink(context),
                      child: Icon(Icons.lock_rounded,
                          size: 13, color: Colors.white),
                    ),
                  ),
                if (equipped)
                  PositionedDirectional(
                    end: -4,
                    top: -4,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: PoColors.mint(context),
                      child: Icon(Icons.check_rounded,
                          size: 14, color: Colors.white),
                    ),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(
                context.tx(item.nameFa, item.nameEn),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: owned
                        ? PoColors.ink(context)
                        : PoColors.inkDim(context)),
              ),
              const SizedBox(height: 2),
              Text(
                owned
                    ? (equipped
                        ? context.tx('پوشیده', 'Equipped')
                        : context.tx('بپوش', 'Equip'))
                    : levelLocked
                        ? poDigits(
                            context,
                            context.tx('سطح ${item.minLevel}',
                                'Level ${item.minLevel}'))
                        : poDigits(context, '${item.price} 🪙'),
                style: TextStyle(
                    fontSize: 11,
                    color: owned
                        ? (equipped ? PoColors.mint(context) : rc)
                        : PoColors.inkDim(context),
                    fontWeight: FontWeight.w700),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
