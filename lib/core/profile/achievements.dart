import 'profile_service.dart';

/// Achievement rule (extensible: each world can add its own rule here).
class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.asset,
    required this.nameFa,
    required this.nameEn,
    required this.descFa,
    required this.descEn,
    required this.check,
    this.coinReward = 50,
  });
  final String id;
  final String asset; // file name in assets/progression/achievements
  final String nameFa;
  final String nameEn;
  final String descFa;
  final String descEn;
  final bool Function(ProfileService p) check;
  final int coinReward;
}

bool _identity(ProfileService p) => p.hasIdentity;
bool _firstGame(ProfileService p) => p.totalGamesPlayed >= 1;
bool _gamer(ProfileService p) => p.totalGamesPlayed >= 25;
bool _champion(ProfileService p) => p.totalWins >= 10;
bool _legend(ProfileService p) => p.level >= 20;
bool _explorer(ProfileService p) => p.counter('worlds.visited') >= 7;
bool _daily(ProfileService p) => p.streak >= 3;
bool _idea(ProfileService p) => p.counter('oracle.asked') >= 10;
bool _team(ProfileService p) => p.counter('social.joined') >= 1;
bool _planet(ProfileService p) => p.decorLayout.length >= 5;
bool _starElite(ProfileService p) => p.stats.values.where((s) => s.won > 0).length >= 5;
bool _summit(ProfileService p) => p.level >= 10;
bool _crown(ProfileService p) => p.totalWins >= 50;
bool _crystal(ProfileService p) => p.counter('nova.posts') >= 5;
bool _orb(ProfileService p) => p.counter('shop.bought') >= 5;
bool _silver(ProfileService p) => p.counter('orbit.sent') >= 20;
bool _wings(ProfileService p) => p.stats.length >= 9;

const kAchievements = <AchievementDef>[
  AchievementDef(id: 'identity', asset: 'badge_explorer', nameFa: 'اکتشافگر', nameEn: 'Explorer',
      descFa: 'هویت دیجیتال خود را ساختی', descEn: 'Created your digital identity', check: _identity),
  AchievementDef(id: 'first_game', asset: 'badge_gamer', nameFa: 'اولین بازی', nameEn: 'First Match',
      descFa: 'اولین بازی را در آرکید انجام دادی', descEn: 'Played your first Arcade match', check: _firstGame),
  AchievementDef(id: 'gamer', asset: 'trophy_silver', nameFa: 'گیمر واقعی', nameEn: 'True Gamer',
      descFa: '۲۵ بازی انجام بده', descEn: 'Play 25 matches', check: _gamer, coinReward: 150),
  AchievementDef(id: 'champion', asset: 'badge_champion', nameFa: 'قهرمان', nameEn: 'Champion',
      descFa: '۱۰ برد', descEn: 'Win 10 matches', check: _champion, coinReward: 150),
  AchievementDef(id: 'crown', asset: 'trophy_crown', nameFa: 'تاج آرکید', nameEn: 'Arcade Crown',
      descFa: '۵۰ برد', descEn: 'Win 50 matches', check: _crown, coinReward: 400),
  AchievementDef(id: 'star_elite', asset: 'badge_star_elite', nameFa: 'نخبه‌ی ستاره', nameEn: 'Star Elite',
      descFa: 'در ۵ بازی مختلف ببر', descEn: 'Win in 5 different games', check: _starElite, coinReward: 200),
  AchievementDef(id: 'all_games', asset: 'trophy_wings', nameFa: 'بال‌های آرکید', nameEn: 'Arcade Wings',
      descFa: 'هر ۹ بازی را امتحان کن', descEn: 'Try all 9 games', check: _wings, coinReward: 250),
  AchievementDef(id: 'explorer', asset: 'badge_planet', nameFa: 'جهان‌گرد', nameEn: 'World Traveler',
      descFa: 'به هر ۷ دنیا سر بزن', descEn: 'Visit all 7 worlds', check: _explorer, coinReward: 120),
  AchievementDef(id: 'daily', asset: 'badge_daily', nameFa: 'وفادار', nameEn: 'Loyal',
      descFa: '۳ روز پیاپی جایزه‌ی روزانه', descEn: '3-day daily streak', check: _daily),
  AchievementDef(id: 'idea', asset: 'badge_idea', nameFa: 'کنجکاو', nameEn: 'Curious Mind',
      descFa: '۱۰ سؤال از ORACLE', descEn: 'Ask ORACLE 10 things', check: _idea),
  AchievementDef(id: 'team', asset: 'badge_team', nameFa: 'هم‌تیمی', nameEn: 'Team Player',
      descFa: 'یک اجتماع بساز یا عضو شو', descEn: 'Create or join a community', check: _team),
  AchievementDef(id: 'decorator', asset: 'trophy_orb', nameFa: 'معمار مدار', nameEn: 'Orbit Architect',
      descFa: '۵ تزئین در فضای شخصی', descEn: 'Place 5 decor items', check: _planet),
  AchievementDef(id: 'creator', asset: 'trophy_crystal', nameFa: 'خالق', nameEn: 'Creator',
      descFa: '۵ پست در Nova Gallery', descEn: 'Publish 5 Nova posts', check: _crystal),
  AchievementDef(id: 'collector', asset: 'badge_summit', nameFa: 'کلکسیونر', nameEn: 'Collector',
      descFa: '۵ خرید از Exchange', descEn: 'Buy 5 Exchange items', check: _orb),
  AchievementDef(id: 'chatter', asset: 'badge_team', nameFa: 'پرحرف', nameEn: 'Communicator',
      descFa: '۲۰ پیام در Orbit Network', descEn: 'Send 20 messages', check: _silver),
  AchievementDef(id: 'summit', asset: 'badge_summit', nameFa: 'قله', nameEn: 'Summit',
      descFa: 'به سطح ۱۰ برس', descEn: 'Reach level 10', check: _summit, coinReward: 200),
  AchievementDef(id: 'legend', asset: 'badge_legend', nameFa: 'افسانه', nameEn: 'Legend',
      descFa: 'به سطح ۲۰ برس', descEn: 'Reach level 20', check: _legend, coinReward: 500),
];
