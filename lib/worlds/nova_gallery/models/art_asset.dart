import '../../../core/assets/app_assets.dart';

/// Categories of built-in NEXORA art that can be attached to posts and messages.
/// (No image_picker package: the app's own art library is the honest offline source.)
enum ArtCategory { gear, decor, pedestal, badge }

/// A reference to one built-in art asset, serialised as `'<category>:<id>'`
/// (e.g. `gear:helmet`). Paths are always resolved through [AppAssets] helpers.
class ArtAsset {
  const ArtAsset(this.category, this.id);
  final ArtCategory category;
  final String id;

  String get ref => '${category.name}:$id';

  String get path {
    switch (category) {
      case ArtCategory.gear:
        return AppAssets.gear(id);
      case ArtCategory.decor:
        return AppAssets.decor(id);
      case ArtCategory.pedestal:
        return AppAssets.pedestal(id);
      case ArtCategory.badge:
        return AppAssets.clubBadge(id);
    }
  }

  /// Human readable label (ids are snake_case).
  String get label => id.replaceAll('badge_club_', '').replaceAll('_', ' ');

  static ArtAsset? parse(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    final i = ref.indexOf(':');
    if (i <= 0 || i >= ref.length - 1) return null;
    final cat = ref.substring(0, i);
    final id = ref.substring(i + 1);
    ArtCategory? c;
    for (final v in ArtCategory.values) {
      if (v.name == cat) c = v;
    }
    if (c == null) return null;
    if (!(kArtIds[c] ?? const <String>[]).contains(id)) return null;
    return ArtAsset(c, id);
  }

  static String categoryFa(ArtCategory c) {
    switch (c) {
      case ArtCategory.gear:
        return 'تجهیزات آواتار';
      case ArtCategory.decor:
        return 'تزئینات مدار';
      case ArtCategory.pedestal:
        return 'سکوهای آرکید';
      case ArtCategory.badge:
        return 'نشان باشگاه‌ها';
    }
  }

  static String categoryEn(ArtCategory c) {
    switch (c) {
      case ArtCategory.gear:
        return 'Avatar gear';
      case ArtCategory.decor:
        return 'Orbit decor';
      case ArtCategory.pedestal:
        return 'Arcade pedestals';
      case ArtCategory.badge:
        return 'Club badges';
    }
  }

  static List<ArtAsset> all(ArtCategory c) =>
      (kArtIds[c] ?? const <String>[]).map((String id) => ArtAsset(c, id)).toList();
}

/// Every built-in asset id that exists in the bundle (see pubspec assets).
const Map<ArtCategory, List<String>> kArtIds = <ArtCategory, List<String>>{
  ArtCategory.gear: <String>[
    'armor_vest', 'backpack', 'belt', 'boots', 'bracelet', 'crystal_shards', 'glove', 'headphones',
    'helmet', 'jacket', 'planet_orb', 'scarf', 'sunglasses', 'tiara', 'visor_panel', 'watch',
  ],
  ArtCategory.decor: <String>[
    'banner', 'crystal_arch', 'crystal_cluster', 'curved_arch', 'diamond_spinner', 'dna_tube',
    'light_pillar', 'orb_rings', 'planet_globe', 'plant_bowl', 'purple_tree_pot', 'ring_sculpture',
    'satellite', 'spire_tower', 'tablet_stand', 'terrarium_globe',
  ],
  ArtCategory.pedestal: <String>[
    'finger_soccer', 'carrom', 'billiards', 'backgammon', 'ludo', 'snakes_ladders', 'uno', 'quiz', 'mafia',
  ],
  ArtCategory.badge: <String>[
    'badge_club_scorpion', 'badge_club_wolf', 'badge_club_yakuza', 'badge_club_monster',
    'badge_club_bermuda', 'badge_club_stone',
  ],
};
