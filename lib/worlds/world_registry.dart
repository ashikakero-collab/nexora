import 'package:flutter/material.dart';

import '../core/theme/nx_theme.dart';

/// The seven worlds of NEXORA (Vision §5). Single registry used by Hub,
/// router, ORACLE and search.
class NexoraWorld {
  const NexoraWorld({
    required this.id,
    required this.name,
    required this.nameFa,
    required this.taglineFa,
    required this.taglineEn,
    required this.icon,
    required this.palette,
    this.keywords = const [],
  });

  /// Same as portal file name in assets/worlds/hub/portals/.
  final String id;
  final String name;
  final String nameFa;
  final String taglineFa;
  final String taglineEn;
  final IconData icon;
  final WorldPalette palette;
  final List<String> keywords;
}

const kWorlds = <NexoraWorld>[
  NexoraWorld(
    id: 'nova_gallery',
    name: 'NOVA GALLERY',
    nameFa: 'نوا گالری',
    taglineFa: 'پست، استوری و ریلز — دنیای اجتماعی',
    taglineEn: 'Posts, stories & reels — the social world',
    icon: Icons.photo_library_rounded,
    palette: WorldPalette.nova,
    keywords: ['post', 'social', 'پست', 'گالری', 'استوری'],
  ),
  NexoraWorld(
    id: 'orbit_network',
    name: 'ORBIT NETWORK',
    nameFa: 'شبکه‌ی مدار',
    taglineFa: 'پیام، گروه، کانال و تماس',
    taglineEn: 'Messages, groups, channels & calls',
    icon: Icons.forum_rounded,
    palette: WorldPalette.orbit,
    keywords: ['chat', 'message', 'پیام', 'چت'],
  ),
  NexoraWorld(
    id: 'nexora_arcade',
    name: 'NEXORA ARCADE',
    nameFa: 'آرکید نکسورا',
    taglineFa: '۹ بازی، بات هوشمند و بازی دونفره',
    taglineEn: '9 games, smart bots & local multiplayer',
    icon: Icons.sports_esports_rounded,
    palette: WorldPalette.arcade,
    keywords: ['game', 'arcade', 'بازی', 'آرکید'],
  ),
  NexoraWorld(
    id: 'oracle_core',
    name: 'ORACLE CORE',
    nameFa: 'هسته‌ی اوراکل',
    taglineFa: 'دستیار هوشمند همراه تو',
    taglineEn: 'Your intelligent companion',
    icon: Icons.blur_circular_rounded,
    palette: WorldPalette.oracle,
    keywords: ['ai', 'oracle', 'اوراکل', 'دستیار'],
  ),
  NexoraWorld(
    id: 'personal_orbit',
    name: 'PERSONAL ORBIT',
    nameFa: 'مدار شخصی',
    taglineFa: 'آواتار، فضای شخصی و دستاوردها',
    taglineEn: 'Avatar, your space & achievements',
    icon: Icons.person_pin_circle_rounded,
    palette: WorldPalette.personal,
    keywords: ['profile', 'avatar', 'پروفایل', 'آواتار'],
  ),
  NexoraWorld(
    id: 'social_station',
    name: 'SOCIAL STATION',
    nameFa: 'ایستگاه اجتماعی',
    taglineFa: 'اجتماعات، رویدادها و مسابقات',
    taglineEn: 'Communities, events & tournaments',
    icon: Icons.groups_rounded,
    palette: WorldPalette.social,
    keywords: ['community', 'club', 'اجتماع', 'کلاب'],
  ),
  NexoraWorld(
    id: 'nexora_exchange',
    name: 'NEXORA EXCHANGE',
    nameFa: 'بازار نکسورا',
    taglineFa: 'آیتم‌های آواتار، تزئین و پوسته',
    taglineEn: 'Avatar items, decor & skins',
    icon: Icons.storefront_rounded,
    palette: WorldPalette.exchange,
    keywords: ['shop', 'store', 'فروشگاه', 'بازار'],
  ),
];

NexoraWorld? worldById(String id) {
  for (final w in kWorlds) {
    if (w.id == id) return w;
  }
  return null;
}
