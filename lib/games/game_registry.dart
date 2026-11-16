import 'package:flutter/material.dart';

import 'backgammon/backgammon_entry.dart';
import 'billiards/billiards_entry.dart';
import 'carrom/carrom_entry.dart';
import 'core/game_contract.dart';
import 'finger_soccer/finger_soccer_entry.dart';
import 'ludo/ludo_entry.dart';
import 'mafia/mafia_entry.dart';
import 'quiz/quiz_entry.dart';
import 'snakes_ladders/snakes_ladders_entry.dart';
import 'uno/uno_entry.dart';

export 'core/game_contract.dart';

/// GameRegistry (STEP_16): the nine NEXORA ARCADE games.
final List<GameInfo> kGames = <GameInfo>[
  GameInfo(
    id: 'finger_soccer',
    nameFa: 'فوتبال انگشتی',
    nameEn: 'Finger Soccer',
    taglineFa: 'فلاخن بکش، شوت بزن، گل کن',
    taglineEn: 'Pull, flick, score',
    rulesFa: 'تیم، ترکیب (۶ ترکیب)، زمین و توپ را انتخاب کن. نوبتی یکی از مهره‌های خودت را بکش و رها کن؛ هرچه بیشتر بکشی ضربه محکم‌تر است. '
        'وقتی همه‌چیز ایستاد نوبت عوض می‌شود. توپ باید از خط دروازه رد شود؛ گلِ مستقیم از ضربه‌ی شروع حساب نمی‌شود. '
        'هر بازی ۵ دقیقه است و در تساوی، گل طلایی برنده را تعیین می‌کند. در بازی آنلاین هر نوبت ۱۵ ثانیه است.',
    rulesEn: 'Pick your team, formation (6 shapes), field and ball. On your turn drag one of your discs back and release; the longer the pull, the harder the shot. '
        'Turns swap when everything stops. The ball must cross the goal line; a direct goal from the kick-off shot does not count. '
        'Matches last 5 minutes and a golden goal decides a tie. Online turns are 15 seconds.',
    minPlayers: 2,
    maxPlayers: 2,
    accent: const Color(0xFF3DDC97),
    builder: buildFingerSoccerGame,
    supportsOnline: true,
  ),
  GameInfo(
    id: 'carrom',
    nameFa: 'کارم',
    nameEn: 'Carrom',
    taglineFa: 'تخته‌ی مشکی‌طلایی NX',
    taglineEn: 'The NX black-gold board',
    rulesFa: 'استرایکر را روی خط پایه بگذار، نشانه بگیر و ضربه بزن تا مهره‌های رنگ خودت را در چهار گوشه بیندازی. '
        'انداختن مهره‌ی خودی یعنی نوبت دوباره. ملکه‌ی قرمز را باید با انداختن یک مهره‌ی خودی بلافاصله پوشش دهی. '
        'انداختن استرایکر خطاست: یک مهره برمی‌گردد و نوبت می‌سوزد. کسی که همه‌ی مهره‌هایش را بیندازد برنده است.',
    rulesEn: 'Place the striker on your baseline, aim and flick to pocket your own colour into the four corners. '
        'Pocketing your coin earns another shot. The red queen must be covered by pocketing one of your coins right after. '
        'Pocketing the striker is a foul: a coin returns and you lose the turn. Clear all your coins to win.',
    minPlayers: 2,
    maxPlayers: 2,
    accent: const Color(0xFFFFC857),
    builder: buildCarromGame,
    supportsOnline: true,
  ),
  GameInfo(
    id: 'billiards',
    nameFa: 'بیلیارد',
    nameEn: 'Billiards',
    taglineFa: 'ایت‌بال با خط راهنمای هوشمند',
    taglineEn: '8-ball with smart aim guide',
    rulesFa: 'ایت‌بال: بعد از بریک، اولین توپی که بیندازی گروه تو را (ساده یا راه‌راه) تعیین می‌کند. '
        'همه‌ی توپ‌های گروهت را بینداز و بعد توپ ۸. خطا (افتادن توپ سفید، برخورد اول به توپ اشتباه) = توپ در دست حریف. '
        'انداختن توپ ۸ زودتر از موعد یا همراه با سفید = باخت.',
    rulesEn: '8-ball: after the break, the first ball you pot decides your group (solids or stripes). '
        'Pot your whole group, then the 8. Fouls (scratch, wrong ball first) give ball-in-hand to the opponent. '
        'Potting the 8 early or with the cue ball loses.',
    minPlayers: 2,
    maxPlayers: 2,
    accent: const Color(0xFF00C2FF),
    builder: buildBilliardsGame,
    supportsOnline: true,
  ),
  GameInfo(
    id: 'backgammon',
    nameFa: 'تخته‌نرد',
    nameEn: 'Backgammon',
    taglineFa: 'تخته‌ی طلایی NX',
    taglineEn: 'The NX gold board',
    rulesFa: 'دو تاس بینداز و مهره‌ها را به اندازه‌ی هر تاس جلو ببر. جفت = چهار حرکت. '
        'مهره‌ی تنها را می‌توان زد و به بار فرستاد؛ باید اول آن را وارد کنی. '
        'وقتی همه‌ی مهره‌ها در خانه‌ی تو هستند، شروع به برداشتن کن. اولین نفری که همه را بردارد برنده است (مارس و مارس ترکی هم حساب می‌شود).',
    rulesEn: 'Roll two dice and move checkers by each die. Doubles = four moves. '
        'A single checker can be hit and sent to the bar; you must re-enter it first. '
        'Once all your checkers are home, bear them off. First to bear off all wins (gammons and backgammons count).',
    minPlayers: 2,
    maxPlayers: 2,
    accent: const Color(0xFFE0B252),
    builder: buildBackgammonGame,
    supportsOnline: true,
  ),
  GameInfo(
    id: 'ludo',
    nameFa: 'لودو (منچ)',
    nameEn: 'Ludo',
    taglineFa: '۲ تا ۴ بازیکن کیهانی',
    taglineEn: '2–4 cosmic players',
    rulesFa: 'با ۶ مهره را از پایگاه بیرون بیاور. ۶ یعنی نوبت اضافه (سه ۶ پشت سر هم نوبت را می‌سوزاند). '
        'روی مهره‌ی حریف بنشینی او را به پایگاه می‌فرستی، مگر روی خانه‌های ستاره‌دار امن. '
        'هر چهار مهره را با عدد دقیق به مرکز برسان.',
    rulesEn: 'Roll a 6 to leave base. A 6 grants another roll (three 6s in a row forfeit). '
        'Landing on an opponent sends it home, except on safe star squares. '
        'Bring all four tokens to the center with an exact roll.',
    minPlayers: 2,
    maxPlayers: 4,
    defaultPlayers: 4,
    accent: const Color(0xFFFF4FA3),
    builder: buildLudoGame,
    supportsOnline: true,
  ),
  GameInfo(
    id: 'snakes_ladders',
    nameFa: 'مار و پله',
    nameEn: 'Snakes & Ladders',
    taglineFa: 'پل‌های نور و مارهای کهکشانی',
    taglineEn: 'Light bridges & galactic serpents',
    rulesFa: 'تاس بینداز و جلو برو. پای پل نور بالا می‌روی و روی سر مار پایین می‌آیی. '
        'برای رسیدن به ۱۰۰ عدد دقیق لازم است؛ اضافه برگشت می‌خوری. ۶ یعنی نوبت دوباره.',
    rulesEn: 'Roll and move. Climb light-bridge ladders, slide down serpents. '
        'You need an exact roll to land on 100; extra steps bounce back. A 6 rolls again.',
    minPlayers: 2,
    maxPlayers: 4,
    defaultPlayers: 2,
    accent: const Color(0xFF7CFF8A),
    builder: buildSnakesLaddersGame,
    supportsOnline: true,
  ),
  GameInfo(
    id: 'uno',
    nameFa: 'کارت‌های NX',
    nameEn: 'NX Cards',
    taglineFa: 'کارتی به سبک UNO',
    taglineEn: 'UNO-style card game',
    rulesFa: 'کارتی بازی کن که رنگ، عدد یا نماد آن با کارت وسط یکی باشد. رد، برعکس و +۲ و کارت‌های وحشی را هوشمندانه استفاده کن. '
        'وقتی یک کارت ماند دکمه‌ی NX! را بزن وگرنه ۲ کارت جریمه می‌شوی. اولین کسی که دستش خالی شود برنده است.',
    rulesEn: 'Play a card matching the top card by colour, number or symbol. Use Skip, Reverse, +2 and Wilds wisely. '
        'Hit NX! when you have one card left or draw 2 as a penalty. First to empty their hand wins.',
    minPlayers: 2,
    maxPlayers: 4,
    defaultPlayers: 4,
    accent: const Color(0xFF9D7BFF),
    builder: buildUnoGame,
    supportsOnline: true,
  ),
  GameInfo(
    id: 'quiz',
    nameFa: 'کوییز نکسورا',
    nameEn: 'NEXORA Quiz',
    taglineFa: 'دوئل دانش در ۱۰ راند',
    taglineEn: '10-round knowledge duel',
    rulesFa: '۱۰ سؤال، هر کدام ۱۵ ثانیه. پاسخ درست امتیاز دارد و سرعت جایزه‌ی اضافه. دسته را انتخاب کن و حریف را شکست بده.',
    rulesEn: '10 questions, 15 seconds each. Correct answers score, speed adds a bonus. Pick a category and beat your rival.',
    minPlayers: 2,
    maxPlayers: 2,
    accent: const Color(0xFF2EE6D6),
    builder: buildQuizGame,
    supportsOnline: true,
  ),
  GameInfo(
    id: 'mafia',
    nameFa: 'مافیا',
    nameEn: 'Mafia',
    taglineFa: 'نقش‌های مخفی در ایستگاه مهتابی',
    taglineEn: 'Hidden roles on a moonlit station',
    rulesFa: 'شهروندان باید مافیا را پیدا و حذف کنند؛ مافیا شب‌ها یک نفر را حذف می‌کند. پزشک نجات می‌دهد، کارآگاه استعلام می‌گیرد '
        '(پدرخوانده بی‌گناه نشان داده می‌شود). روزها بحث و رأی‌گیری است. حالت راوی برای بازی با دوستان روی یک گوشی است.',
    rulesEn: 'Citizens must find and eliminate the Mafia; the Mafia removes one player each night. The Doctor saves, the Detective investigates '
        '(the Godfather appears innocent). Days are for debate and voting. Narrator mode runs a party game for friends on one phone.',
    minPlayers: 6,
    maxPlayers: 12,
    defaultPlayers: 8,
    accent: const Color(0xFFFF5A6E),
    builder: buildMafiaGame,
    supportsOnline: true,
  ),
];

GameInfo? gameById(String id) {
  for (final g in kGames) {
    if (g.id == id) return g;
  }
  return null;
}
