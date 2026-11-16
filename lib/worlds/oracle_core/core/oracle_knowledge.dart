/// ORACLE CORE offline knowledge base (pure Dart). Bilingual facts about every
/// NEXORA world and feature. Every statement here describes how the offline
/// build really behaves; anything that needs the server is labelled honestly.
library;

import 'oracle_models.dart';

class OracleWorld {
  const OracleWorld({
    required this.id,
    required this.nameFa,
    required this.nameEn,
    required this.descFa,
    required this.descEn,
    required this.aliases,
  });
  final String id;
  final String nameFa;
  final String nameEn;
  final String descFa;
  final String descEn;
  final List<String> aliases;
}

/// Keyword syntax (see OracleBrain): plain Persian keyword = prefix match at a
/// word start, plain ASCII keyword = whole word, `*` suffix = prefix match,
/// `=` suffix = whole word.
const List<OracleWorld> kOracleWorlds = <OracleWorld>[
  OracleWorld(
    id: 'personal_orbit',
    nameFa: 'پرسنال اوربیت',
    nameEn: 'Personal Orbit',
    descFa: 'خانه‌ی شخصی تو: آواتار و لباس‌ها، Explorer ID، اتاق مداری قابل چیدمان، دستاوردها، آمار، فعالیت‌ها و چالش‌های روزانه.',
    descEn: 'Your personal home: avatar and gear, Explorer ID, a room you can decorate, achievements, stats, activity and daily challenges.',
    aliases: <String>[
      'personal orbit', 'personal', 'پرسنال', 'پرسونال', 'فضای شخصی', 'فضای من', 'اتاق من', 'اتاقم', 'my room',
      'my space', 'profile', 'پروفایل', 'avatar*', 'اواتار', 'wardrobe', 'کمد', 'my profile',
    ],
  ),
  OracleWorld(
    id: 'orbit_network',
    nameFa: 'اوربیت نتورک',
    nameEn: 'Orbit Network',
    descFa: 'پیام‌رسان NEXORA: چت خصوصی، گروه و کانال. پیام به کاربران واقعی و تماس‌ها بعد از اتصال سرور فعال می‌شوند.',
    descEn: 'The NEXORA messenger: private chats, groups and channels. Messaging real users and calls turn on once the server is connected.',
    aliases: <String>[
      'orbit network', 'network', 'نتورک', 'اوربیت', 'orbit', 'messenger', 'messages', 'chats', 'chat',
      'پیام رسان', 'پیامرسان', 'چت',
    ],
  ),
  OracleWorld(
    id: 'nexora_arcade',
    nameFa: 'آرکید NEXORA',
    nameEn: 'NEXORA Arcade',
    descFa: 'سالن بازی‌ها: کرام، فوتبال دستی، مار و پله، کوییز، تخته‌نرد، بیلیارد، UNO، لودو و مافیا؛ با ربات آفلاین یا دونفره روی همین گوشی.',
    descEn: 'The games hall: Carrom, Finger Soccer, Snakes & Ladders, Quiz, Backgammon, Billiards, UNO, Ludo and Mafia — vs offline bots or pass-and-play on this device.',
    aliases: <String>['arcade', 'nexora arcade', 'ارکید', 'game room', 'gaming', 'گیم', 'سالن بازی'],
  ),
  OracleWorld(
    id: 'oracle_core',
    nameFa: 'اوراکل کور',
    nameEn: 'Oracle Core',
    descFa: 'همین‌جا! خانه‌ی من، ORACLE، دستیار NEXORA.',
    descEn: 'Right here! My home — ORACLE, the NEXORA assistant.',
    aliases: <String>['oracle core', 'اوراکل کور'],
  ),
  OracleWorld(
    id: 'social_station',
    nameFa: 'سوشال استیشن',
    nameEn: 'Social Station',
    descFa: 'اجتماعات NEXORA: ساخت و پیوستن به گروه‌ها و کلاب‌ها، رویدادها و اعلان‌ها.',
    descEn: 'NEXORA communities: create and join groups and clubs, events and announcements.',
    aliases: <String>[
      'social station', 'social', 'سوشال', 'استیشن', 'community', 'communities', 'club*', 'اجتماع', 'کامیونیتی',
      'کلاب', 'انجمن',
    ],
  ),
  OracleWorld(
    id: 'nexora_exchange',
    nameFa: 'اکسچنج NEXORA',
    nameEn: 'NEXORA Exchange',
    descFa: 'بازار آیتم‌های دیجیتال با سکه‌ای که از فعالیت به دست می‌آید: لباس آواتار، تزئین اتاق، تم، قاب پروفایل و آیتم بازی. قیمت‌ها شفاف و بدون قمار یا جعبه‌ی شانسی.',
    descEn: 'The digital item market, paid with coins you earn by playing: avatar gear, room decor, themes, profile frames and game items. Transparent prices, no gambling, no loot boxes.',
    aliases: <String>[
      'exchange', 'nexora exchange', 'shop', 'store', 'market*', 'اکسچنج', 'بازار', 'فروشگاه', 'مارکت',
    ],
  ),
  OracleWorld(
    id: 'nova_gallery',
    nameFa: 'نوا گالری',
    nameEn: 'Nova Gallery',
    descFa: 'شبکه‌ی اجتماعی NEXORA: پست، استوری، لایک و کامنت. پست‌هایت روی همین دستگاه ذخیره می‌شوند و انتشار عمومی بعد از اتصال سرور است.',
    descEn: 'The NEXORA social network: posts, stories, likes and comments. Your posts are saved on this device; public sharing comes with the server.',
    aliases: <String>[
      'nova gallery', 'nova', 'gallery', 'نوا', 'گالری', 'شبکه اجتماعی', 'social network', 'feed', 'فید',
      'reels', 'ریلز', 'story', 'stories', 'استوری',
    ],
  ),
];

/// Fallback names for the nine Arcade games (the registry is preferred).
class OracleGameAlias {
  const OracleGameAlias(this.id, this.nameFa, this.nameEn, this.aliases);
  final String id;
  final String nameFa;
  final String nameEn;
  final List<String> aliases;
}

const List<OracleGameAlias> kOracleGameAliases = <OracleGameAlias>[
  OracleGameAlias('snakes_ladders', 'مار و پله', 'Snakes & Ladders', <String>[
    'snakes and ladders', 'snakes & ladders', 'snakes', 'snake', 'ladders', 'ladder', 'مار و پله', 'مارو پله',
    'مار پله', 'مارپله', 'مار و نردبان',
  ]),
  OracleGameAlias('finger_soccer', 'فوتبال دستی', 'Finger Soccer', <String>[
    'finger soccer', 'finger football', 'fingersoccer', 'soccer', 'football', 'فوتبال دستی', 'فوتبال انگشتی',
    'فینگر', 'فوتبال',
  ]),
  OracleGameAlias('backgammon', 'تخته‌نرد', 'Backgammon', <String>[
    'backgammon', 'tavla', 'تخته نرد', 'تختنرد', 'تخته=', 'نرد=',
  ]),
  OracleGameAlias('billiards', 'بیلیارد', 'Billiards', <String>['billiard*', 'pool', 'snooker', 'بیلیارد', 'اسنوکر']),
  OracleGameAlias('carrom', 'کرام', 'Carrom', <String>['carrom*', 'کرام', 'کاروم']),
  OracleGameAlias('ludo', 'لودو', 'Ludo', <String>['ludo', 'لودو', 'منچ']),
  OracleGameAlias('uno', 'UNO', 'UNO', <String>['uno', 'اونو', 'یونو']),
  OracleGameAlias('quiz', 'کوییز', 'Quiz', <String>['quiz*', 'trivia', 'کوییز', 'کوئیز', 'مسابقه اطلاعات', 'اطلاعات عمومی']),
  OracleGameAlias('mafia', 'مافیا', 'Mafia', <String>['mafia', 'مافیا']),
];

/// FAQ entry: every group in [must] needs at least one keyword hit.
class OracleFaq {
  const OracleFaq({
    required this.id,
    required this.must,
    required this.textFa,
    required this.textEn,
    this.actions = const <OracleAction>[],
    this.pose = 'present',
    this.priority = false,
    this.skipWhenWorld = false,
  });
  final String id;
  final List<List<String>> must;
  final String textFa;
  final String textEn;
  final List<OracleAction> actions;
  final String pose;

  /// Priority entries are checked before personal-data intents.
  final bool priority;

  /// Skip when the text names a specific world (e.g. "open NEXORA Exchange").
  final bool skipWhenWorld;
}

const OracleAction kGoPersonal =
    OracleAction.navigate('/world/personal_orbit', labelFa: 'ورود به پرسنال اوربیت', labelEn: 'Open Personal Orbit');
const OracleAction kGoArcade =
    OracleAction.navigate('/world/nexora_arcade', labelFa: 'ورود به آرکید', labelEn: 'Open Arcade');
const OracleAction kGoExchange =
    OracleAction.navigate('/world/nexora_exchange', labelFa: 'ورود به اکسچنج', labelEn: 'Open Exchange');
const OracleAction kGoNova =
    OracleAction.navigate('/world/nova_gallery', labelFa: 'ورود به نوا گالری', labelEn: 'Open Nova Gallery');
const OracleAction kGoOrbitNet =
    OracleAction.navigate('/world/orbit_network', labelFa: 'ورود به اوربیت نتورک', labelEn: 'Open Orbit Network');
const OracleAction kGoSocial =
    OracleAction.navigate('/world/social_station', labelFa: 'ورود به سوشال استیشن', labelEn: 'Open Social Station');
const OracleAction kGoSettings = OracleAction.navigate('/settings', labelFa: 'باز کردن تنظیمات', labelEn: 'Open Settings');

const List<OracleFaq> kOracleFaq = <OracleFaq>[
  // ---------- priority (honesty-critical) ----------
  OracleFaq(
    id: 'gambling',
    priority: true,
    must: <List<String>>[
      <String>['gambl*', 'loot*', 'bet', 'bets', 'betting', 'casino', 'lucky box', 'mystery box', 'قمار', 'شرط بندی', 'شرطبندی', 'شانسی', 'جعبه شانس', 'لوت'],
    ],
    textFa: 'در NEXORA هیچ قمار، شرط‌بندی یا جعبه‌ی شانسی پولی وجود ندارد. هر آیتم قیمت ثابت و شفاف دارد و دقیقاً همان چیزی را می‌گیری که می‌بینی. حتی «پیشنهاد امروز» اکسچنج فقط از روی تاریخ چرخش می‌کند، نه شانس.',
    textEn: 'NEXORA has no gambling, no betting and no paid loot boxes. Every item has a fixed, visible price and you get exactly what you see. Even the Exchange\'s "Featured today" rotates by date, not by chance.',
    actions: <OracleAction>[kGoExchange],
    pose: 'calm',
  ),
  OracleFaq(
    id: 'leaderboard',
    priority: true,
    must: <List<String>>[
      <String>['leaderboard*', 'tournament*', 'league*', 'ranking', 'rankings', 'global rank', 'رتبه بندی', 'جدول رده', 'جدول رتبه', 'لیگ', 'تورنمنت', 'جام=', 'مسابقات'],
    ],
    textFa: 'جدول رتبه‌بندی جهانی، لیگ و تورنمنت به سرور نیاز دارند تا نتایج غیرقابل‌دستکاری باشند؛ بعد از اتصال آنلاین فعال می‌شوند. فعلاً آمار واقعی خودت را در پرسنال اوربیت ببین.',
    textEn: 'Global leaderboards, leagues and tournaments need the server so results can\'t be tampered with; they turn on once NEXORA is online. For now, your real stats are in Personal Orbit.',
    actions: <OracleAction>[kGoPersonal],
    pose: 'alert',
  ),
  OracleFaq(
    id: 'calls',
    priority: true,
    must: <List<String>>[
      <String>['call', 'calls', 'calling', 'voice call', 'video call', 'تماس', 'ویدیو کال', 'ویدئو کال', 'کال='],
    ],
    textFa: 'تماس صوتی و تصویری به سرور ارتباطی نیاز دارد و در نسخه‌ی آفلاین فعال نیست. نمی‌خواهم وانمود کنم که کار می‌کند؛ بعد از اتصال سرور در اوربیت نتورک روشن می‌شود.',
    textEn: 'Voice and video calls need the media server and are not active in the offline build. I won\'t pretend they work; they turn on in Orbit Network once the server is connected.',
    actions: <OracleAction>[kGoOrbitNet],
    pose: 'alert',
  ),
  OracleFaq(
    id: 'voice',
    priority: true,
    must: <List<String>>[
      <String>['voice', 'microphone', 'mic', 'speak to you', 'talk to you', 'صوتی', 'میکروفون', 'با صدا', 'حرف بزنم', 'صدام'],
    ],
    textFa: 'ورودی صوتی و پاسخ گفتاری من به موتور تشخیص گفتار نیاز دارد که در این نسخه‌ی آفلاین نصب نیست. فعلاً با تایپ با من حرف بزن؛ بعد از اتصال سرور صدا هم اضافه می‌شود.',
    textEn: 'Voice input and spoken replies need a speech engine that isn\'t in this offline build. Please type to me for now; voice arrives with the server.',
    pose: 'calm',
  ),
  OracleFaq(
    id: 'offline',
    priority: true,
    must: <List<String>>[
      <String>['offline', 'online', 'internet', 'server', 'sync', 'اینترنت', 'افلاین', 'انلاین', 'سرور', 'همگام'],
    ],
    textFa: 'این نسخه‌ی NEXORA کاملاً آفلاین کار می‌کند: بازی‌ها با ربات یا دونفره روی یک گوشی، پیشرفت، اکسچنج، فضای شخصی و من. چیزهایی که کاربر واقعی دیگر لازم دارند (تماس، مسابقه‌ی آنلاین، رتبه‌بندی جهانی) بعد از اتصال سرور فعال می‌شوند و تا آن موقع صادقانه اعلام می‌شوند.',
    textEn: 'This NEXORA build works fully offline: games vs bots or pass-and-play, progression, the Exchange, your Personal Orbit, and me. Things that need other real users (calls, online matches, global rankings) turn on with the server and are clearly labelled until then.',
    pose: 'calm',
  ),
  // ---------- regular ----------
  OracleFaq(
    id: 'buy',
    must: <List<String>>[
      <String>['buy', 'buying', 'purchase*', 'خرید', 'بخرم', 'بخر=', 'خریدن'],
    ],
    textFa: 'برای خرید به اکسچنج برو، دسته را انتخاب کن و روی آیتم بزن. قیمت به سکه است و بعد از تأیید، سکه کم و آیتم به کمدت اضافه می‌شود. بعضی آیتم‌ها حداقل سطح دارند. خرید با پول واقعی فعلاً غیرفعال است.',
    textEn: 'Go to the Exchange, pick a category and tap an item. Prices are in coins; after you confirm, the coins are deducted and the item goes to your wardrobe. Some items need a minimum level. Real-money purchases are disabled for now.',
    actions: <OracleAction>[kGoExchange],
  ),
  OracleFaq(
    id: 'equip',
    must: <List<String>>[
      <String>['equip*', 'wear', 'put on', 'outfit', 'gear', 'بپوشم', 'بپوش', 'پوشیدن', 'تجهیز', 'لباس'],
    ],
    textFa: 'در پرسنال اوربیت، بخش «کمد» را باز کن. آیتم‌ها بر اساس جایگاه (سر، صورت، بدن، دست، پا، پشت، هاله...) مرتب‌اند؛ با یک لمس می‌پوشی یا درمی‌آوری. آیتم‌های قفل مستقیم به اکسچنج می‌روند.',
    textEn: 'Open the Wardrobe tab in Personal Orbit. Items are grouped by slot (head, face, body, hands, feet, back, aura…); one tap equips or unequips. Locked items link straight to the Exchange.',
    actions: <OracleAction>[kGoPersonal, kGoExchange],
  ),
  OracleFaq(
    id: 'decor',
    must: <List<String>>[
      <String>['decor*', 'furniture', 'arrange', 'تزئین', 'تزیین', 'دکور', 'چیدمان'],
    ],
    textFa: 'در پرسنال اوربیت، بخش «فضای من» را باز کن: تزئین‌هایی که داری را اضافه کن، با کشیدن جابه‌جا کن، با دو انگشت یا اسلایدر اندازه بده و تم اتاق را عوض کن. چیدمان روی دستگاهت ذخیره می‌شود. پنج تزئین = دستاورد «معمار مدار».',
    textEn: 'Open My Space in Personal Orbit: add decor you own, drag to move, pinch or use the slider to scale, and switch the room theme. The layout is saved on your device. Five decor items unlock "Orbit Architect".',
    actions: <OracleAction>[kGoPersonal, kGoExchange],
  ),
  OracleFaq(
    id: 'themes',
    must: <List<String>>[
      <String>['theme', 'themes', 'تم=', 'تم ها', 'تمها', 'پس زمینه'],
    ],
    textFa: 'تم‌ها (شفق، سحابی، کریستال سفید، خورشیدی) نور و رنگ اتاق شخصی‌ات را عوض می‌کنند. شفق رایگان است و بقیه در اکسچنج هستند.',
    textEn: 'Themes (Aurora, Nebula, White Crystal, Solar) change the light and colours of your personal room. Aurora is free; the others are in the Exchange.',
    actions: <OracleAction>[kGoPersonal, kGoExchange],
  ),
  OracleFaq(
    id: 'frames',
    must: <List<String>>[
      <String>['frame', 'frames', 'قاب'],
    ],
    textFa: 'قاب‌های هولوگرافیک دور آواتارت در پروفایل نمایش داده می‌شوند. از اکسچنج بخر و در کمد پرسنال اوربیت تجهیز کن.',
    textEn: 'Holo frames surround your avatar on your profile. Buy them in the Exchange and equip them in the Personal Orbit wardrobe.',
    actions: <OracleAction>[kGoExchange],
  ),
  OracleFaq(
    id: 'skins',
    must: <List<String>>[
      <String>['puck', 'pucks', 'skin', 'skins', 'striker*', 'cue', 'cues', 'پوک', 'اسکین', 'استرایکر', 'چوب بیلیارد', 'مهره'],
    ],
    textFa: 'پوک‌های فوتبال دستی، استرایکرهای کرام و چوب‌های بیلیارد آیتم‌های بازی هستند. در اکسچنج بخر و تجهیز کن؛ بازی‌ها همان آیتم تجهیزشده را نشان می‌دهند.',
    textEn: 'Finger Soccer pucks, Carrom strikers and Billiards cues are game items. Buy and equip them in the Exchange; games use whatever you have equipped.',
    actions: <OracleAction>[kGoExchange],
  ),
  OracleFaq(
    id: 'challenges',
    must: <List<String>>[
      <String>['challenge*', 'mission*', 'quest*', 'چالش', 'ماموریت'],
    ],
    textFa: 'چالش‌های روزانه و هفتگی در پرسنال اوربیت هستند (مثلاً امروز ۳ مسابقه بازی کن، یک بار ببر، یک پست بگذار). پیشرفت از فعالیت واقعی‌ات حساب می‌شود و جایزه‌ی هرکدام فقط یک بار دریافت می‌شود. هفته از شنبه شروع می‌شود.',
    textEn: 'Daily and weekly challenges live in Personal Orbit (e.g. play 3 matches today, win once, post once). Progress comes from your real activity and each reward can be claimed once. Weeks start on Saturday.',
    actions: <OracleAction>[kGoPersonal],
  ),
  OracleFaq(
    id: 'explorer_id',
    must: <List<String>>[
      <String>['explorer id', 'explorer', 'my id', 'id', 'شناسه', 'ایدی'],
    ],
    textFa: 'Explorer ID شناسه‌ی یکتای توست که در همه‌ی دنیاها یکسان است. در پرسنال اوربیت می‌توانی آن را کپی کنی.',
    textEn: 'Your Explorer ID is your unique identity, the same across every world. You can copy it in Personal Orbit.',
    actions: <OracleAction>[kGoPersonal],
    pose: 'calm',
  ),
  OracleFaq(
    id: 'post',
    must: <List<String>>[
      <String>['post', 'posts', 'posting', 'publish', 'upload', 'پست', 'منتشر', 'انتشار', 'اپلود'],
    ],
    textFa: 'در نوا گالری پست بساز و منتشر کن. هر پست شمارنده‌ی دستاورد «خالق» و چالش روزانه را جلو می‌برد.',
    textEn: 'Create and publish posts in Nova Gallery. Each post counts toward the "Creator" achievement and the daily challenge.',
    actions: <OracleAction>[kGoNova],
  ),
  OracleFaq(
    id: 'messages',
    must: <List<String>>[
      <String>['message', 'messages', 'messaging', 'dm', 'پیام', 'گفتگو'],
    ],
    textFa: 'پیام‌ها در اوربیت نتورک هستند. ارسال پیام به کاربران واقعی دیگر بعد از اتصال سرور فعال می‌شود؛ هر پیام ارسالی برای چالش هفتگی و دستاورد «پرحرف» شمرده می‌شود.',
    textEn: 'Messages live in Orbit Network. Messaging other real users turns on with the server; every message you send counts toward the weekly challenge and the "Communicator" achievement.',
    actions: <OracleAction>[kGoOrbitNet],
  ),
  OracleFaq(
    id: 'community',
    must: <List<String>>[
      <String>['community', 'communities', 'club', 'clubs', 'group', 'groups', 'اجتماع', 'کامیونیتی', 'کلاب', 'گروه', 'انجمن'],
    ],
    textFa: 'در سوشال استیشن می‌توانی اجتماع بسازی یا عضو شوی. اولین عضویت دستاورد «هم‌تیمی» را باز می‌کند.',
    textEn: 'In Social Station you can create or join communities. Your first one unlocks the "Team Player" achievement.',
    actions: <OracleAction>[kGoSocial],
  ),
  OracleFaq(
    id: 'multiplayer',
    must: <List<String>>[
      <String>['multiplayer', 'friend', 'friends', 'together', 'two player', '2 player', 'pass and play', 'دو نفره', 'دونفره', 'چند نفره', 'چندنفره', 'با دوست', 'رفیق'],
    ],
    textFa: 'به‌صورت آفلاین می‌توانی با دوستانت روی همین گوشی (نوبتی) بازی کنی؛ در صفحه‌ی هر بازی حالت «محلی» را انتخاب کن. بازی آنلاین با کاربران دیگر و دعوت از راه دور بعد از اتصال سرور فعال می‌شود.',
    textEn: 'Offline you can play with friends on this same phone (pass-and-play): choose "Local" on any game\'s setup screen. Online matches and remote invites turn on with the server.',
    actions: <OracleAction>[kGoArcade],
  ),
  OracleFaq(
    id: 'games_list',
    must: <List<String>>[
      <String>['what games', 'which games', 'list of games', 'games list', 'all games', 'چه بازی هایی', 'کدوم بازی ها', 'کدام بازی ها', 'لیست بازی', 'بازی هایی'],
    ],
    textFa: 'در آرکید ۹ بازی داریم: کرام، فوتبال دستی، مار و پله، کوییز، تخته‌نرد، بیلیارد، UNO، لودو و مافیا. اسم هرکدام را بگو تا قوانینش را توضیح بدهم یا بازی را باز کنم.',
    textEn: 'The Arcade has 9 games: Carrom, Finger Soccer, Snakes & Ladders, Quiz, Backgammon, Billiards, UNO, Ludo and Mafia. Name one and I\'ll explain the rules or open it.',
    actions: <OracleAction>[kGoArcade],
  ),
  OracleFaq(
    id: 'account',
    must: <List<String>>[
      <String>['delete', 'reset', 'account', 'privacy', 'my data', 'حذف', 'ریست', 'حساب', 'حریم', 'اطلاعاتم', 'داده'],
    ],
    textFa: 'داده‌هایت فعلاً فقط روی همین دستگاه ذخیره می‌شوند. پاک کردن کامل هویت و پیشرفت از تنظیمات انجام می‌شود و برگشت‌پذیر نیست؛ من خودم هیچ‌وقت چیزی را پاک نمی‌کنم.',
    textEn: 'Your data is stored only on this device for now. Wiping your identity and progress is done from Settings and can\'t be undone; I never delete anything myself.',
    actions: <OracleAction>[kGoSettings],
    pose: 'calm',
  ),
  OracleFaq(
    id: 'worlds',
    must: <List<String>>[
      <String>['worlds', 'world', 'دنیا', 'جهان ها'],
    ],
    textFa: 'NEXORA هفت دنیا دارد: نوا گالری (شبکه‌ی اجتماعی)، اوربیت نتورک (پیام‌رسان)، آرکید (بازی‌ها)، اوراکل کور (من!)، پرسنال اوربیت (خانه‌ی تو)، سوشال استیشن (اجتماعات) و اکسچنج (بازار). کدام را باز کنم؟',
    textEn: 'NEXORA has seven worlds: Nova Gallery (social), Orbit Network (messenger), Arcade (games), Oracle Core (me!), Personal Orbit (your home), Social Station (communities) and the Exchange (market). Which one should I open?',
    actions: <OracleAction>[kGoArcade, kGoPersonal, kGoExchange, kGoNova, kGoOrbitNet, kGoSocial],
    skipWhenWorld: true,
  ),
  OracleFaq(
    id: 'nexora',
    must: <List<String>>[
      <String>['nexora', 'نکسورا', 'نکسرا'],
    ],
    textFa: 'NEXORA یک جهان دیجیتال کیهانی و یکپارچه است: یک هویت برای همه‌ی دنیاها، از شبکه‌ی اجتماعی و پیام‌رسان تا بازی، اجتماعات، بازار و من، ORACLE. «جهان تو. هویت تو. تجربه‌ی تو.»',
    textEn: 'NEXORA is one connected cosmic universe: a single identity across every world — social, messaging, games, communities, a market, and me, ORACLE. "Your universe. Your identity. Your experience."',
    pose: 'present',
    skipWhenWorld: true,
  ),
];

const List<String> kJokesFa = <String>[
  'چرا ستاره‌ها هیچ‌وقت دیر نمی‌کنند؟ چون همیشه در مدارشان هستند! ✨',
  'به سیاهچاله گفتم یک راز بگو؛ گفت هرچه بگویم دیگر بیرون نمی‌آید! 🕳️',
  'چرا فضانورد با ماه قهر کرد؟ چون به کمی «فضا» نیاز داشت! 🚀',
];

const List<String> kJokesEn = <String>[
  'Why are stars never late? They always stay in their orbit! ✨',
  'I asked a black hole for a secret. It said: once I take it in, it never comes out! 🕳️',
  'Why did the astronaut break up with the moon? It needed space. 🚀',
];
