import '../assets/app_assets.dart';

/// Item categories in NEXORA EXCHANGE / inventory.
enum ItemCategory { avatarGear, decor, puck, striker, cue, theme, frame, badge }

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.category,
    required this.nameFa,
    required this.nameEn,
    required this.price,
    required this.asset,
    this.slot,
    this.minLevel = 1,
    this.rarity = 'common',
  });
  final String id;
  final ItemCategory category;
  final String nameFa;
  final String nameEn;

  /// Price in coins (earned by playing). 0 = free starter item.
  final int price;
  final String asset;

  /// Equip slot (avatar gear slot, or 'puck' / 'striker' / 'cue' / 'theme' / 'frame').
  final String? slot;
  final int minLevel;
  final String rarity; // common, rare, epic, legendary (fixed, never random)
}

CatalogItem _gear(String id, String slot, String fa, String en, int price, {int lvl = 1, String r = 'common'}) =>
    CatalogItem(id: 'gear_$id', category: ItemCategory.avatarGear, nameFa: fa, nameEn: en, price: price,
        asset: AppAssets.gear(id), slot: slot, minLevel: lvl, rarity: r);
CatalogItem _decor(String id, String fa, String en, int price, {int lvl = 1, String r = 'common'}) =>
    CatalogItem(id: 'decor_$id', category: ItemCategory.decor, nameFa: fa, nameEn: en, price: price,
        asset: AppAssets.decor(id), minLevel: lvl, rarity: r);
CatalogItem _puck(String id, String fa, String en, int price, {int lvl = 1, String r = 'common'}) =>
    CatalogItem(id: 'puck_$id', category: ItemCategory.puck, nameFa: fa, nameEn: en, price: price,
        asset: AppAssets.puckIso(id), slot: 'puck', minLevel: lvl, rarity: r);
CatalogItem _striker(String id, String fa, String en, int price, {int lvl = 1, String r = 'common'}) =>
    CatalogItem(id: 'striker_$id', category: ItemCategory.striker, nameFa: fa, nameEn: en, price: price,
        asset: AppAssets.disc('striker_$id'), slot: 'striker', minLevel: lvl, rarity: r);

final kCatalog = <CatalogItem>[
  // Avatar gear
  _gear('helmet', 'head', 'کلاه فضایی', 'Space Helmet', 300, r: 'rare'),
  _gear('visor_panel', 'head', 'وایزر هولوگرافیک', 'Holo Visor', 260),
  _gear('tiara', 'head', 'تاج ستاره', 'Star Tiara', 480, lvl: 6, r: 'epic'),
  _gear('headphones', 'head', 'هدفون مداری', 'Orbit Headphones', 180),
  _gear('sunglasses', 'face', 'عینک نئونی', 'Neon Shades', 120),
  _gear('jacket', 'body', 'کاپشن کاوشگر', 'Explorer Jacket', 350, r: 'rare'),
  _gear('armor_vest', 'body', 'زره سبک', 'Light Armor', 520, lvl: 5, r: 'epic'),
  _gear('scarf', 'neck', 'شال کهکشانی', 'Galaxy Scarf', 140),
  _gear('glove', 'hands', 'دستکش انرژی', 'Energy Glove', 200),
  _gear('bracelet', 'wrist', 'دستبند کریستالی', 'Crystal Bracelet', 160),
  _gear('watch', 'wrist', 'ساعت زمان‌سنج', 'Chrono Watch', 220),
  _gear('belt', 'waist', 'کمربند ابزار', 'Utility Belt', 150),
  _gear('boots', 'feet', 'چکمه‌ی جاذبه', 'Gravity Boots', 280, r: 'rare'),
  _gear('backpack', 'back', 'کوله‌ی جت', 'Jet Pack', 600, lvl: 8, r: 'epic'),
  _gear('planet_orb', 'aura', 'گوی سیاره', 'Planet Orb', 900, lvl: 12, r: 'legendary'),
  _gear('crystal_shards', 'aura', 'هاله‌ی کریستال', 'Crystal Aura', 750, lvl: 10, r: 'legendary'),
  // Personal Orbit decor
  _decor('planet_globe', 'کره‌ی سیاره', 'Planet Globe', 120),
  _decor('terrarium_globe', 'تراریوم', 'Terrarium', 150),
  _decor('plant_bowl', 'گلدان گیاه', 'Plant Bowl', 80),
  _decor('purple_tree_pot', 'درخت بنفش', 'Purple Tree', 110),
  _decor('light_pillar', 'ستون نور', 'Light Pillar', 140),
  _decor('crystal_cluster', 'خوشه‌ی کریستال', 'Crystal Cluster', 200, r: 'rare'),
  _decor('crystal_arch', 'طاق کریستالی', 'Crystal Arch', 320, lvl: 4, r: 'rare'),
  _decor('curved_arch', 'طاق خمیده', 'Curved Arch', 260),
  _decor('diamond_spinner', 'الماس چرخان', 'Diamond Spinner', 380, lvl: 5, r: 'epic'),
  _decor('dna_tube', 'لوله‌ی DNA', 'DNA Tube', 240),
  _decor('orb_rings', 'گوی حلقه‌دار', 'Ringed Orb', 300, r: 'rare'),
  _decor('ring_sculpture', 'مجسمه‌ی حلقه', 'Ring Sculpture', 280),
  _decor('satellite', 'ماهواره', 'Satellite', 220),
  _decor('spire_tower', 'برج نوک‌تیز', 'Spire Tower', 420, lvl: 7, r: 'epic'),
  _decor('tablet_stand', 'پایه‌ی تبلت', 'Tablet Stand', 90),
  _decor('banner', 'پرچم NEXORA', 'NEXORA Banner', 60),
  // Finger Soccer pucks
  _puck('nx_green', 'NX سبز', 'NX Green', 0),
  _puck('tech_nx', 'تک NX', 'Tech NX', 0),
  _puck('frost', 'یخی', 'Frost', 150),
  _puck('frost_b', 'یخی آبی', 'Frost Blue', 150),
  _puck('eagle_marble', 'عقاب مرمری', 'Marble Eagle', 220),
  _puck('eagle_gold', 'عقاب طلایی', 'Golden Eagle', 350, r: 'rare'),
  _puck('noble_lion', 'شیر نجیب', 'Noble Lion', 300, r: 'rare'),
  _puck('royal_lion', 'شیر سلطنتی', 'Royal Lion', 450, lvl: 5, r: 'epic'),
  _puck('phoenix_purple', 'ققنوس بنفش', 'Purple Phoenix', 500, lvl: 6, r: 'epic'),
  _puck('dragon_fire', 'اژدهای آتش', 'Fire Dragon', 650, lvl: 8, r: 'legendary'),
  _puck('cosmic_crown', 'تاج کیهانی', 'Cosmic Crown', 800, lvl: 10, r: 'legendary'),
  // Carrom strikers
  _striker('soccer', 'استرایکر توپ', 'Soccer Striker', 0),
  _striker('compass', 'قطب‌نما', 'Compass', 140),
  _striker('eagle', 'عقاب', 'Eagle', 200),
  _striker('wolf', 'گرگ', 'Wolf', 240, r: 'rare'),
  _striker('lion', 'شیر', 'Lion', 260, r: 'rare'),
  _striker('fire', 'آتش', 'Fire', 320, lvl: 4, r: 'epic'),
  _striker('dragon', 'اژدها', 'Dragon', 420, lvl: 6, r: 'epic'),
  _striker('galaxy', 'کهکشان', 'Galaxy', 600, lvl: 9, r: 'legendary'),
  // Billiard cues (drawn procedurally)
  const CatalogItem(id: 'cue_classic', category: ItemCategory.cue, nameFa: 'چوب کلاسیک', nameEn: 'Classic Cue',
      price: 0, asset: '', slot: 'cue'),
  const CatalogItem(id: 'cue_neon', category: ItemCategory.cue, nameFa: 'چوب نئونی', nameEn: 'Neon Cue',
      price: 250, asset: '', slot: 'cue', rarity: 'rare'),
  const CatalogItem(id: 'cue_gold', category: ItemCategory.cue, nameFa: 'چوب طلایی', nameEn: 'Gold Cue',
      price: 500, asset: '', slot: 'cue', minLevel: 6, rarity: 'epic'),
  // Personal Orbit themes
  const CatalogItem(id: 'theme_aurora', category: ItemCategory.theme, nameFa: 'شفق', nameEn: 'Aurora',
      price: 0, asset: '', slot: 'theme'),
  const CatalogItem(id: 'theme_nebula', category: ItemCategory.theme, nameFa: 'سحابی', nameEn: 'Nebula',
      price: 200, asset: '', slot: 'theme'),
  const CatalogItem(id: 'theme_crystal', category: ItemCategory.theme, nameFa: 'کریستال سفید', nameEn: 'White Crystal',
      price: 300, asset: '', slot: 'theme', rarity: 'rare'),
  const CatalogItem(id: 'theme_solar', category: ItemCategory.theme, nameFa: 'خورشیدی', nameEn: 'Solar',
      price: 400, asset: '', slot: 'theme', minLevel: 5, rarity: 'epic'),
  // Profile frames
  for (var i = 1; i <= 8; i++)
    CatalogItem(
        id: 'frame_holo_$i', category: ItemCategory.frame, nameFa: 'قاب هولو $i', nameEn: 'Holo Frame $i',
        price: 100 + i * 40, asset: 'assets/ui/holo_frames/holo_frame_0$i.webp', slot: 'frame',
        rarity: i > 6 ? 'epic' : i > 3 ? 'rare' : 'common'),
];

CatalogItem? catalogItem(String id) {
  for (final i in kCatalog) {
    if (i.id == id) return i;
  }
  return null;
}
