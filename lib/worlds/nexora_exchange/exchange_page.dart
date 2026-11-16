import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog.dart';
import '../../core/profile/achievements.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/ui2/nx2_assets.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/widgets/nx_widgets.dart';
import 'core/exchange_rules.dart';
import 'core/exchange_service.dart';

/// NEXORA EXCHANGE (STEP_28): transparent cosmetic shop paid with earned coins.
/// No loot boxes, no gambling, no random paid rewards; real money is disabled.
class ExchangePage extends ConsumerStatefulWidget {
  const ExchangePage({super.key});

  @override
  ConsumerState<ExchangePage> createState() => _ExchangePageState();
}

const List<ItemCategory> _kTabs = <ItemCategory>[
  ItemCategory.avatarGear,
  ItemCategory.decor,
  ItemCategory.puck,
  ItemCategory.striker,
  ItemCategory.cue,
  ItemCategory.theme,
  ItemCategory.frame,
  ItemCategory.badge,
];

String _digits(BuildContext context, String s) {
  if (!context.isFa) return s;
  const String fa = '۰۱۲۳۴۵۶۷۸۹';
  final StringBuffer b = StringBuffer();
  for (final int c in s.codeUnits) {
    if (c >= 48 && c <= 57) {
      b.write(fa[c - 48]);
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

String _categoryName(BuildContext context, ItemCategory c) {
  switch (c) {
    case ItemCategory.avatarGear:
      return context.tx('پوشش آواتار', 'Avatar gear');
    case ItemCategory.decor:
      return context.tx('دکور فضای شخصی', 'Room decor');
    case ItemCategory.puck:
      return context.tx('مهره‌ی فوتبال', 'Pucks');
    case ItemCategory.striker:
      return context.tx('استرایکر کارم', 'Strikers');
    case ItemCategory.cue:
      return context.tx('چوب بیلیارد', 'Cues');
    case ItemCategory.theme:
      return context.tx('تم', 'Themes');
    case ItemCategory.frame:
      return context.tx('قاب پروفایل', 'Frames');
    case ItemCategory.badge:
      return context.tx('نشان', 'Badges');
  }
}

IconData _categoryIcon(ItemCategory c) {
  switch (c) {
    case ItemCategory.avatarGear:
      return Icons.checkroom_rounded;
    case ItemCategory.decor:
      return Icons.chair_rounded;
    case ItemCategory.puck:
      return Icons.sports_soccer_rounded;
    case ItemCategory.striker:
      return Icons.adjust_rounded;
    case ItemCategory.cue:
      return Icons.sports_rounded;
    case ItemCategory.theme:
      return Icons.palette_rounded;
    case ItemCategory.frame:
      return Icons.crop_square_rounded;
    case ItemCategory.badge:
      return Icons.military_tech_rounded;
  }
}

Color rarityColor(String rarity) {
  switch (rarity) {
    case 'legendary':
      return NxColors.gold;
    case 'epic':
      return const Color(0xFFD068FF);
    case 'rare':
      return const Color(0xFF35D6FF);
    default:
      return const Color(0xFF9FB3C8);
  }
}

String _rarityName(BuildContext context, String rarity) {
  switch (rarity) {
    case 'legendary':
      return context.tx('افسانه‌ای', 'Legendary');
    case 'epic':
      return context.tx('حماسی', 'Epic');
    case 'rare':
      return context.tx('کمیاب', 'Rare');
    default:
      return context.tx('معمولی', 'Common');
  }
}

class _ExchangePageState extends ConsumerState<ExchangePage> {
  DateTime _day = DateTime.now();

  void _onRotate() {
    if (!mounted) return;
    setState(() => _day = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final List<CatalogItem> featured = featuredForDate(_day);
    final NxThemeColors visual = NxThemeColors.of(context);
    final int tabCount = _kTabs.length + 1;
    return NxWorldScaffold(
      title: 'NEXORA EXCHANGE',
      palette: WorldPalette.exchange,
      body: DefaultTabController(
        length: tabCount,
        child: NestedScrollView(
          headerSliverBuilder: (BuildContext ctx, bool inner) => <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    NxSpace.md, NxSpace.sm, NxSpace.md, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(bottom: NxSpace.sm),
                      child: Text(
                        context.tx('کلکسیونی شفاف؛ آیتم‌های ظاهری با قیمت روشن',
                            'A transparent collection of cosmetic items, with clear prices'),
                        style: TextStyle(
                            color: visual.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const _WalletPanel(),
                    const SizedBox(height: NxSpace.md),
                    const _RarityTiers(),
                    const SizedBox(height: NxSpace.md),
                    _FeaturedStrip(items: featured, onRotate: _onRotate),
                    const SizedBox(height: NxSpace.sm),
                  ],
                ),
              ),
            ),
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
              sliver: SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: visual.accent,
                    labelColor: visual.accent,
                    unselectedLabelColor: visual.muted,
                    dividerColor: Colors.transparent,
                    tabs: <Widget>[
                      for (final ItemCategory c in _kTabs)
                        Tab(
                            icon: Icon(_categoryIcon(c), size: 18),
                            text: _categoryName(context, c),
                            iconMargin: EdgeInsets.zero),
                      Tab(
                        icon: const Icon(Icons.receipt_long_rounded, size: 18),
                        text: context.tx('تاریخچه', 'History'),
                        iconMargin: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: <Widget>[
              for (final ItemCategory c in _kTabs) _CategoryGrid(category: c),
              const _HistoryTab(),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => 76;
  @override
  double get maxExtent => 76;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: visual.backgroundMid.withValues(alpha: 0.96),
        border: Border(
            bottom: BorderSide(color: visual.border.withValues(alpha: 0.56))),
      ),
      alignment: Alignment.center,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}

// ---------------------------------------------------------------- wallet

/// Chest art of the four rarity tiers. Prices are fixed and shown up front: these are tier
/// emblems, not random loot boxes (the shop never sells chance).
String rarityChest(String rarity) {
  switch (rarity) {
    case 'legendary':
      return Nx2Assets.chestsChestLegendary;
    case 'epic':
      return Nx2Assets.chestsChestEpic;
    case 'rare':
      return Nx2Assets.chestsChestRare;
    default:
      return Nx2Assets.chestsChestStandard;
  }
}

class _RarityTiers extends StatelessWidget {
  const _RarityTiers();

  @override
  Widget build(BuildContext context) {
    const List<String> tiers = <String>['common', 'rare', 'epic', 'legendary'];
    return Nx2Panel(
      gems: true,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      child: Column(children: <Widget>[
        Nx2SectionHeader(
            title: context.tx('سطح کمیابی آیتم‌ها', 'Item rarity tiers')),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          for (final String r in tiers)
            Expanded(
              child: Column(children: <Widget>[
                SizedBox(
                  height: 64,
                  child: Image.asset(rarityChest(r),
                      cacheWidth: 200,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
                const SizedBox(height: 4),
                Text(_rarityName(context, r),
                    style: TextStyle(
                        color: rarityColor(r),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900)),
              ]),
            ),
        ]),
        const SizedBox(height: 6),
        Text(
            context.tx('قیمت‌ها ثابت و شفاف‌اند؛ هیچ جعبه‌ی شانسی در کار نیست.',
                'Fixed, transparent prices — no random boxes.'),
            style: const TextStyle(color: Nx2.muted, fontSize: 11)),
      ]),
    );
  }
}

class _WalletPanel extends ConsumerWidget {
  const _WalletPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final NxThemeColors visual = NxThemeColors.of(context);
    return GlassPanel(
      borderColor: visual.border.withValues(alpha: 0.72),
      padding: const EdgeInsets.all(NxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: <Color>[
                  visual.accent.withValues(alpha: 0.55),
                  visual.accent,
                  visual.accentSecondary
                ]),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: NxColors.gold.withValues(alpha: 0.5),
                      blurRadius: 18)
                ],
              ),
              child:
                  Icon(Icons.toll_rounded, color: visual.background, size: 30),
            ),
            const SizedBox(width: NxSpace.md),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(context.tx('کیف سکه', 'Coin wallet'),
                        style: TextStyle(color: visual.muted, fontSize: 12)),
                    Text(_digits(context, '${p.coins}'),
                        style: TextStyle(
                            color: visual.accent,
                            fontSize: 30,
                            fontWeight: FontWeight.w900)),
                    Text(
                        '${context.tx('سطح', 'Level')} ${_digits(context, '${p.level}')} · ${context.tx(p.rankTitleFa, p.rankTitleEn)}',
                        style: TextStyle(color: visual.text, fontSize: 12)),
                  ]),
            ),
            if (p.canClaimDaily)
              Flexible(child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: visual.accent,
                    foregroundColor: visual.background),
                onPressed: () {
                  final AwardOutcome? o =
                      ref.read(profileProvider).claimDaily();
                  if (o != null) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            '${context.tx('جایزه‌ی روزانه', 'Daily bonus')}: +${_digits(context, '${o.coins}')}')));
                    showAwardOutcome(context, o);
                  }
                },
                icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                label: Text(context.tx('جایزه‌ی روزانه', 'Daily bonus')),
              )),
          ]),
          const SizedBox(height: NxSpace.sm),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: NxSpace.sm),
              iconColor: visual.accent,
              collapsedIconColor: visual.accent,
              title: Text(
                  context.tx('سکه از کجا می‌آید؟', 'How do I earn coins?'),
                  style: TextStyle(
                      color: visual.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              children: <Widget>[
                _earnLine(
                    context,
                    Icons.emoji_events_rounded,
                    context.tx('برد در هر بازی آرکید: ۴۰ سکه',
                        'Win an Arcade game: 40 coins')),
                _earnLine(
                    context,
                    Icons.handshake_rounded,
                    context.tx('مساوی: ۱۵ سکه · باخت: ۵ سکه',
                        'Draw: 15 coins · Loss: 5 coins')),
                _earnLine(
                    context,
                    Icons.calendar_today_rounded,
                    context.tx('جایزه‌ی روزانه: ۵۰ سکه + پاداش زنجیره‌ی روزها',
                        'Daily bonus: 50 coins + streak bonus')),
                _earnLine(
                    context,
                    Icons.military_tech_rounded,
                    context.tx('هر دستاورد جدید سکه‌ی جایزه دارد',
                        'Every new achievement pays a coin reward')),
                _earnLine(
                    context,
                    Icons.block_rounded,
                    context.tx(
                        'سکه با پول واقعی خریده نمی‌شود (فعلاً غیرفعال).',
                        'Coins cannot be bought with real money (disabled for now).')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _earnLine(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: <Widget>[
          Icon(icon, size: 16, color: NxThemeColors.of(context).accent),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: NxThemeColors.of(context).muted, fontSize: 12.5))),
        ]),
      );
}

// ---------------------------------------------------------------- featured

class _FeaturedStrip extends StatelessWidget {
  const _FeaturedStrip({required this.items, required this.onRotate});
  final List<CatalogItem> items;
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(children: <Widget>[
            Icon(Icons.auto_awesome_rounded, color: visual.accent, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text(context.tx('ویژه‌ی امروز', 'Featured today'),
                  style: TextStyle(
                      color: visual.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6)),
            ),
            _RotationCountdown(onRotate: onRotate),
          ]),
          const SizedBox(height: NxSpace.sm),
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: NxSpace.sm),
              itemBuilder: (BuildContext ctx, int i) => SizedBox(
                  width: 140, child: _ItemCard(item: items[i], featured: true)),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: <Widget>[
            const Icon(Icons.verified_user_rounded,
                size: 14, color: NxColors.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                context.tx(
                    'شفاف: فهرست ویژه فقط بر اساس تاریخ امروز چرخش می‌کند و برای همه یکسان است. قیمت‌ها ثابت و کامل نمایش داده می‌شوند؛ بدون لوت‌باکس، بدون قمار و بدون جایزه‌ی تصادفی.',
                    'Transparent: the featured list rotates by today\'s date only and is the same for everyone. Prices are fixed and fully shown; no loot boxes, no gambling, no random rewards.'),
                style: TextStyle(
                    color: NxThemeColors.of(context).muted, fontSize: 11.5),
              ),
            ),
          ]),
        ]);
  }
}

class _RotationCountdown extends StatefulWidget {
  const _RotationCountdown({required this.onRotate});
  final VoidCallback onRotate;

  @override
  State<_RotationCountdown> createState() => _RotationCountdownState();
}

class _RotationCountdownState extends State<_RotationCountdown> {
  Timer? _timer;
  Duration _left = timeUntilRotation(DateTime.now());

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final Duration next = timeUntilRotation(DateTime.now());
      final bool rolled = next > _left;
      setState(() => _left = next);
      if (rolled) widget.onRotate();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String two(int v) => v.toString().padLeft(2, '0');
    final int h = _left.inHours;
    final int m = _left.inMinutes % 60;
    final int s = _left.inSeconds % 60;
    final String t = _digits(context, '${two(h)}:${two(m)}:${two(s)}');
    return NxPill(
        label: '${context.tx('چرخش بعدی', 'Next rotation')} $t',
        icon: Icons.timer_outlined,
        color: NxThemeColors.of(context).accent);
  }
}

// ---------------------------------------------------------------- grid

class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid({required this.category});
  final ItemCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<CatalogItem> items = itemsInCategory(category)
      ..sort((CatalogItem a, CatalogItem b) {
        final int r = rarityRank(a.rarity).compareTo(rarityRank(b.rarity));
        if (r != 0) return r;
        return a.price.compareTo(b.price);
      });
    return Builder(builder: (BuildContext ctx) {
      return CustomScrollView(
        key: PageStorageKey<String>('exchange.${category.name}'),
        slivers: <Widget>[
          SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx)),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(NxSpace.lg),
                  child: Text(
                    context.tx('در این دسته هنوز آیتمی منتشر نشده است.',
                        'No items have been released in this category yet.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NxThemeColors.of(context).muted),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.xl),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisSpacing: NxSpace.sm,
                  crossAxisSpacing: NxSpace.sm,
                  childAspectRatio: 0.76,
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext c, int i) => _ItemCard(item: items[i]),
                  childCount: items.length,
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({required this.item, this.featured = false});
  final CatalogItem item;
  final bool featured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final bool owned = p.owns(item.id);
    final bool equipped = owned && ExchangeService.isEquipped(p, item);
    final bool locked = !owned && p.level < item.minLevel;
    final Color rc = rarityColor(item.rarity);
    final NxThemeColors visual = NxThemeColors.of(context);
    return GestureDetector(
      onTap: () => showItemSheet(context, item),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NxRadius.md),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color.lerp(visual.surfaceRaised, rc, 0.24)!,
              visual.surface.withValues(alpha: 0.96)
            ],
          ),
          border: Border.all(
              color: rc.withValues(alpha: featured ? 0.9 : 0.55),
              width: featured ? 1.6 : 1),
          boxShadow: featured
              ? <BoxShadow>[
                  BoxShadow(color: rc.withValues(alpha: 0.35), blurRadius: 14)
                ]
              : null,
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Stack(children: <Widget>[
                  PositionedDirectional(
                    bottom: 0,
                    end: 0,
                    child: Opacity(
                      opacity: 0.9,
                      child: Image.asset(rarityChest(item.rarity),
                          width: 30,
                          height: 30,
                          cacheWidth: 90,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    ),
                  ),
                  Positioned.fill(child: ItemPreview(item: item, size: 90)),
                  if (equipped)
                    PositionedDirectional(
                        top: 0,
                        start: 0,
                        child: _badge(
                            context.tx('فعال', 'Equipped'), NxColors.success))
                  else if (owned)
                    PositionedDirectional(
                        top: 0,
                        start: 0,
                        child: _badge(
                            context.tx('داری', 'Owned'), NxColors.turquoise)),
                  if (locked)
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: _badge(
                          '🔒 ${_digits(context, '${item.minLevel}')}',
                          NxColors.danger),
                    ),
                ]),
              ),
              const SizedBox(height: 4),
              Text(context.tx(item.nameFa, item.nameEn),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: visual.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
              Row(children: <Widget>[
                Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: rc, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(_rarityName(context, item.rarity),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: rc, fontSize: 11)),
                ),
                if (item.price == 0)
                  Text(context.tx('رایگان', 'Free'),
                      style: TextStyle(
                          color: visual.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800))
                else ...<Widget>[
                  Icon(Icons.toll_rounded, size: 13, color: visual.accent),
                  const SizedBox(width: 2),
                  Text(_digits(context, '${item.price}'),
                      style: TextStyle(
                          color: visual.accent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800)),
                ],
              ]),
            ]),
      ),
    );
  }

  Widget _badge(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: 0.8)),
        ),
        child: Text(text,
            style:
                TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w800)),
      );
}

// ---------------------------------------------------------------- previews

/// Item preview: the item's image, or a procedural drawing for cues / themes.
class ItemPreview extends StatelessWidget {
  const ItemPreview({super.key, required this.item, this.size = 90});
  final CatalogItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (item.category == ItemCategory.cue) {
      return CustomPaint(
          painter: _CuePainter(cueColors(item.id)), size: Size.infinite);
    }
    if (item.category == ItemCategory.theme || item.asset.isEmpty) {
      return _ThemeSwatch(colors: themeColors(themeNameOf(item.id)));
    }
    final int cache = (size * 2.5).round();
    return Center(
      child: Image.asset(
        item.asset,
        cacheWidth: cache,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_rounded,
            size: size * 0.5, color: rarityColor(item.rarity)),
      ),
    );
  }
}

/// Colors for a procedurally drawn cue: [tip, ferrule, shaft, ring, butt, cap].
List<Color> cueColors(String id) {
  switch (id) {
    case 'cue_neon':
      return const <Color>[
        Color(0xFF00E5FF),
        Color(0xFFEAF6FF),
        Color(0xFF0D1B3A),
        Color(0xFF00E5FF),
        Color(0xFF0A1230),
        Color(0xFF00C2FF)
      ];
    case 'cue_gold':
      return const <Color>[
        Color(0xFF3A6BD8),
        Color(0xFFFFF4D6),
        Color(0xFFF3D27A),
        Color(0xFF1A1206),
        Color(0xFF1A1206),
        NxColors.gold
      ];
    default:
      return const <Color>[
        Color(0xFF3A6BD8),
        Color(0xFFF5EEDC),
        Color(0xFFE2C08A),
        Color(0xFF2B1A0E),
        Color(0xFF6B3A1C),
        Color(0xFF1E120A)
      ];
  }
}

/// Gradient colors for a Personal Orbit theme swatch.
List<Color> themeColors(String theme) {
  switch (theme) {
    case 'nebula':
      return const <Color>[
        Color(0xFF2A0B4A),
        Color(0xFF8E2DE2),
        Color(0xFFFF4FA3)
      ];
    case 'crystal':
      return const <Color>[
        Color(0xFFEAF6FF),
        Color(0xFFBFE3FF),
        Color(0xFFB79CFF)
      ];
    case 'solar':
      return const <Color>[Color(0xFF3A0F00), Color(0xFFFF7A18), NxColors.gold];
    default:
      return const <Color>[
        Color(0xFF041B2D),
        NxColors.turquoise,
        Color(0xFF7B3FF2)
      ];
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.colors});
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NxRadius.md),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors),
        boxShadow: <BoxShadow>[
          BoxShadow(color: colors[1].withValues(alpha: 0.45), blurRadius: 16)
        ],
      ),
      child: CustomPaint(painter: _SwatchStars(), size: Size.infinite),
    );
  }
}

class _SwatchStars extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final math.Random r = math.Random(11);
    final Paint p = Paint()..color = Colors.white.withValues(alpha: 0.75);
    for (int i = 0; i < 18; i++) {
      canvas.drawCircle(
          Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
          0.6 + r.nextDouble() * 1.4,
          p);
    }
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(size.width * 0.5, size.height * 0.55),
            width: size.width * 0.7,
            height: size.height * 0.22),
        ring);
    canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.55),
        math.min(size.width, size.height) * 0.14,
        Paint()..color = Colors.white.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(covariant _SwatchStars oldDelegate) => false;
}

class _CuePainter extends CustomPainter {
  _CuePainter(this.colors);
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final double len =
        math.sqrt(size.width * size.width + size.height * size.height) * 0.82;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 4);
    final double start = -len / 2;
    double hw(double d) => 1.6 + 3.4 * (d / len);
    void sec(double d0, double d1, Color c) {
      final Path path = Path()
        ..moveTo(start + d0, -hw(d0))
        ..lineTo(start + d1, -hw(d1))
        ..lineTo(start + d1, hw(d1))
        ..lineTo(start + d0, hw(d0))
        ..close();
      canvas.drawPath(path, Paint()..color = c);
    }

    final Path glow = Path()
      ..moveTo(start, -2)
      ..lineTo(start + len, -6)
      ..lineTo(start + len, 6)
      ..lineTo(start, 2)
      ..close();
    canvas.drawPath(
        glow,
        Paint()
          ..color = colors[5].withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    sec(0, len * 0.02, colors[0]);
    sec(len * 0.02, len * 0.06, colors[1]);
    sec(len * 0.06, len * 0.62, colors[2]);
    sec(len * 0.62, len * 0.65, colors[3]);
    sec(len * 0.65, len * 0.96, colors[4]);
    sec(len * 0.96, len, colors[5]);
    // Highlight line along the shaft.
    canvas.drawLine(
      Offset(start + len * 0.06, -0.8),
      Offset(start + len * 0.95, -1.6),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 0.9,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CuePainter oldDelegate) =>
      oldDelegate.colors != colors;
}

// ---------------------------------------------------------------- detail sheet

Future<void> showItemSheet(BuildContext context, CatalogItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NxThemeColors.of(context).backgroundMid,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(NxRadius.lg))),
    builder: (BuildContext ctx) => _ItemSheet(item: item),
  );
}

class _ItemSheet extends ConsumerStatefulWidget {
  const _ItemSheet({required this.item});
  final CatalogItem item;

  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(settingsProvider).fancyEffects) _spin.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  String _statusText(PurchaseStatus st) {
    switch (st) {
      case PurchaseStatus.ok:
        return context.tx('خرید انجام شد!', 'Purchased!');
      case PurchaseStatus.alreadyOwned:
        return context.tx(
            'این آیتم را از قبل داری.', 'You already own this item.');
      case PurchaseStatus.levelLocked:
        return context.tx('سطحت هنوز به حد لازم نرسیده.',
            'Your level is too low for this item.');
      case PurchaseStatus.notEnoughCoins:
        return context.tx('سکه کافی نداری. با بازی کردن سکه جمع کن.',
            'Not enough coins. Play games to earn more.');
      case PurchaseStatus.unknownItem:
        return context.tx('این آیتم پیدا نشد.', 'Item not found.');
    }
  }

  Future<void> _buy() async {
    final CatalogItem item = widget.item;
    final NxThemeColors visual = NxThemeColors.of(context);
    final ProfileService p = ref.read(profileProvider);
    final PurchaseStatus pre = ExchangeService.status(p, item);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (pre != PurchaseStatus.ok) {
      messenger.showSnackBar(SnackBar(content: Text(_statusText(pre))));
      return;
    }
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(ctx.tx('تأیید خرید', 'Confirm purchase')),
        content: Text(ctx.tx(
          '«${item.nameFa}» را با ${_digits(ctx, '${item.price}')} سکه می‌خری؟\nموجودی بعد از خرید: ${_digits(ctx, '${p.coins - item.price}')} سکه',
          'Buy "${item.nameEn}" for ${item.price} coins?\nBalance after purchase: ${p.coins - item.price} coins',
        )),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: visual.accent,
                foregroundColor: visual.background),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tx('خرید', 'Buy')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || _busy) return;
    setState(() => _busy = true);
    final Set<String> before = Set<String>.of(p.achievements);
    final PurchaseStatus st = ExchangeService.buy(p, item);
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(_statusText(st))));
    if (st == PurchaseStatus.ok) {
      final List<AchievementDef> unlocked = kAchievements
          .where((AchievementDef a) =>
              p.achievements.contains(a.id) && !before.contains(a.id))
          .toList();
      if (unlocked.isNotEmpty && mounted) {
        await showAwardOutcome(
          context,
          AwardOutcome(
              xp: 0,
              coins: 0,
              levelUp: false,
              newLevel: p.level,
              unlocked: unlocked),
        );
      }
    }
  }

  void _toggleEquip(bool equipped) {
    final ProfileService p = ref.read(profileProvider);
    final CatalogItem item = widget.item;
    final bool ok = equipped
        ? ExchangeService.unequip(p, item)
        : ExchangeService.equip(p, item);
    final String msg;
    if (!ok) {
      msg = context.tx('این کار برای این آیتم ممکن نیست.',
          'That is not possible for this item.');
    } else if (equipped) {
      msg = context.tx('برداشته شد.', 'Removed.');
    } else if (item.category == ItemCategory.decor) {
      msg = context.tx(
          'در فضای شخصی‌ات قرار گرفت.', 'Placed in your Personal Orbit room.');
    } else {
      msg = context.tx('فعال شد!', 'Equipped!');
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final CatalogItem item = widget.item;
    final NxThemeColors visual = NxThemeColors.of(context);
    final ProfileService p = ref.watch(profileProvider);
    final bool owned = p.owns(item.id);
    final bool equipped = owned && ExchangeService.isEquipped(p, item);
    final bool locked = !owned && p.level < item.minLevel;
    final bool afford = p.coins >= item.price;
    final Color rc = rarityColor(item.rarity);
    final bool isDecor = item.category == ItemCategory.decor;
    final bool isTheme = item.category == ItemCategory.theme;
    final bool canUnequip = !isTheme;

    final Widget preview = AnimatedBuilder(
      animation: _spin,
      builder: (BuildContext c, Widget? child) {
        final double a = math.sin(_spin.value * 2 * math.pi) * 0.45;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(a),
          child: child,
        );
      },
      child: ItemPreview(item: item, size: 200),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            NxSpace.lg, NxSpace.sm, NxSpace.lg, NxSpace.lg),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                      color: visual.border.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: NxSpace.md),
              Container(
                height: 230,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(NxRadius.lg),
                  gradient: RadialGradient(colors: <Color>[
                    rc.withValues(alpha: 0.35),
                    Colors.transparent
                  ], radius: 0.8),
                ),
                padding: const EdgeInsets.all(NxSpace.md),
                child: preview,
              ),
              const SizedBox(height: NxSpace.md),
              Text(context.tx(item.nameFa, item.nameEn),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: visual.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: NxSpace.sm),
              Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    NxPill(
                        label: _rarityName(context, item.rarity),
                        icon: Icons.diamond_rounded,
                        color: rc),
                    NxPill(
                        label: _categoryName(context, item.category),
                        icon: _categoryIcon(item.category),
                        color: visual.accent),
                    NxPill(
                      label: item.price == 0
                          ? context.tx('رایگان', 'Free')
                          : '${_digits(context, '${item.price}')} ${context.tx('سکه', 'coins')}',
                      icon: Icons.toll_rounded,
                      color: visual.accent,
                    ),
                    if (item.minLevel > 1)
                      NxPill(
                        label:
                            '${context.tx('حداقل سطح', 'Min level')} ${_digits(context, '${item.minLevel}')}',
                        icon: locked
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        color: locked ? NxColors.danger : NxColors.success,
                      ),
                  ]),
              const SizedBox(height: NxSpace.sm),
              Text(
                context.tx(
                    'کمیابی فقط ظاهری است و تأثیری روی نتیجه‌ی بازی ندارد.',
                    'Rarity is cosmetic only and never affects gameplay.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: NxThemeColors.of(context).muted, fontSize: 11.5),
              ),
              const SizedBox(height: NxSpace.md),
              if (!owned) ...<Widget>[
                if (locked)
                  Text(
                    context.tx(
                        'برای باز شدن به سطح ${_digits(context, '${item.minLevel}')} برس (سطح فعلی: ${_digits(context, '${p.level}')}).',
                        'Reach level ${item.minLevel} to unlock (current: ${p.level}).'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: NxColors.danger),
                  )
                else if (!afford)
                  Text(
                    context.tx(
                        '${_digits(context, '${item.price - p.coins}')} سکه‌ی دیگر لازم داری.',
                        'You need ${item.price - p.coins} more coins.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NxThemeColors.of(context).muted),
                  ),
                const SizedBox(height: NxSpace.sm),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: visual.accent,
                    foregroundColor: visual.background,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: (locked || !afford || _busy) ? null : _buy,
                  icon: const Icon(Icons.shopping_bag_rounded),
                  label: Text(context.tx(
                      'خرید با ${_digits(context, '${item.price}')} سکه',
                      'Buy for ${item.price} coins')),
                ),
              ] else ...<Widget>[
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                          equipped
                              ? Icons.check_circle_rounded
                              : Icons.inventory_2_rounded,
                          color:
                              equipped ? NxColors.success : NxColors.turquoise),
                      const SizedBox(width: 6),
                      Text(
                        equipped
                            ? (isDecor
                                ? context.tx(
                                    'در فضای شخصی‌ات است', 'In your room')
                                : context.tx('فعال است', 'Equipped'))
                            : context.tx(
                                'در کلکسیون توست', 'In your collection'),
                        style: TextStyle(
                            color: equipped
                                ? NxColors.success
                                : NxColors.turquoise,
                            fontWeight: FontWeight.w800),
                      ),
                    ]),
                const SizedBox(height: NxSpace.sm),
                if (!equipped)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50)),
                    onPressed: () => _toggleEquip(false),
                    icon: Icon(
                        isDecor ? Icons.add_home_rounded : Icons.check_rounded),
                    label: Text(isDecor
                        ? context.tx(
                            'قرار دادن در فضای شخصی', 'Place in my room')
                        : context.tx('فعال کن', 'Equip')),
                  )
                else if (canUnequip)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50)),
                    onPressed: () => _toggleEquip(true),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    label: Text(isDecor
                        ? context.tx('برداشتن از اتاق', 'Remove from room')
                        : context.tx('برداشتن', 'Unequip')),
                  ),
              ],
            ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- history

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final List<ActivityEntry> history = ExchangeService.purchaseHistory(p);
    return Builder(builder: (BuildContext ctx) {
      return CustomScrollView(
        key: const PageStorageKey<String>('exchange.history'),
        slivers: <Widget>[
          SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                NxSpace.md, NxSpace.sm, NxSpace.md, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                context.tx(
                    'همه‌ی خریدها روی همین دستگاه ثبت می‌شوند و قابل بررسی‌اند.',
                    'Every purchase is recorded on this device and can be reviewed.'),
                style: TextStyle(
                    color: NxThemeColors.of(context).muted, fontSize: 12),
              ),
            ),
          ),
          if (history.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                    context.tx('هنوز خریدی نکرده‌ای.', 'No purchases yet.'),
                    style: TextStyle(color: NxThemeColors.of(context).muted)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.xl),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext c, int i) {
                    final ActivityEntry e = history[i];
                    final String d =
                        '${e.at.year}/${e.at.month.toString().padLeft(2, '0')}/${e.at.day.toString().padLeft(2, '0')} ${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: NxSpace.sm),
                      child: GlassPanel(
                        padding: const EdgeInsets.symmetric(
                            horizontal: NxSpace.md, vertical: 10),
                        child: Row(children: <Widget>[
                          Icon(Icons.shopping_bag_rounded,
                              color: NxThemeColors.of(context).accent),
                          const SizedBox(width: NxSpace.sm),
                          Expanded(
                            child: Text(context.tx(e.textFa, e.textEn),
                                style: TextStyle(
                                    color: NxThemeColors.of(context).text,
                                    fontWeight: FontWeight.w700)),
                          ),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(_digits(context, d),
                                style: TextStyle(
                                    color: NxThemeColors.of(context).muted,
                                    fontSize: 11)),
                          ),
                        ]),
                      ),
                    );
                  },
                  childCount: history.length,
                ),
              ),
            ),
        ],
      );
    });
  }
}
