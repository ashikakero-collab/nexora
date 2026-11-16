/// ORACLE CORE — offline intent engine (pure Dart, NO Flutter imports).
///
/// Understands Persian and English, never pretends: when something is not
/// possible offline it says so. Actions it returns are executed by the UI
/// (real navigation / real setting changes).
library;

import 'oracle_knowledge.dart';
import 'oracle_models.dart';
import 'oracle_text.dart';

export 'oracle_knowledge.dart';
export 'oracle_models.dart';
export 'oracle_text.dart';

// ======================= Vocabulary =======================

const List<String> _navVerbs = <String>[
  'go', 'go to', 'open', 'take me', 'bring me', 'navigate', 'show me', 'launch', 'enter', 'visit', 'lets go',
  'let s go', 'ببر', 'منو ببر', 'برو', 'بریم', 'برم', 'باز کن', 'بازش کن', 'نشون بده', 'نشان بده', 'نمایش بده',
  'وارد', 'ورود',
];
const List<String> _playWords = <String>[
  'play', 'start', 'new game', 'new match', 'room', 'create', 'make', 'host', 'match', 'بازی کن', 'بزن بریم',
  'شروع', 'اتاق', 'بساز', 'راه بنداز', 'یه دست', 'یک دست',
];
const List<String> _rulesWords = <String>[
  'rule*', 'how to play', 'how do i play', 'how do you play', 'how does it work', 'instructions', 'قانون', 'قوانین',
  'چطور بازی', 'چطوری بازی', 'چگونه بازی', 'چجوری بازی', 'طرز بازی', 'روش بازی', 'راهنمای بازی',
];
const List<String> _explainWords = <String>[
  'explain', 'tutorial', 'teach', 'how does', 'how to win', 'guide', 'توضیح', 'اموزش', 'یاد بده', 'یادم بده',
  'چطوریه', 'چجوریه', 'راهنما',
];
const List<String> _howWords = <String>[
  'how', 'where', 'can i', 'چطور', 'چطوری', 'چگونه', 'چجوری', 'کجا', 'میشه', 'میتونم',
];
const List<String> _statsWords = <String>[
  'stat*', 'record', 'records', 'win rate', 'winrate', 'score', 'scores', 'history', 'how many games',
  'how many wins', 'performance', 'آمار', 'امار', 'رکورد', 'نرخ برد', 'درصد برد', 'چند بار بردم', 'چندبار بردم',
  'چندتا بردم', 'چند بازی', 'نتایج', 'عملکرد', 'امتیاز بازی',
];
const List<String> _levelWords = <String>[
  'level', 'levels', 'lvl', 'xp', 'experience', 'rank', 'لول', 'سطح', 'رتبه', 'تجربه', 'امتیاز', 'ایکس پی',
];
const List<String> _coinWords = <String>[
  'coin', 'coins', 'wallet', 'balance', 'money', 'credits', 'سکه', 'کوین', 'کیف پول', 'موجودی', 'پول',
];
const List<String> _earnWords = <String>[
  'earn', 'earning', 'get', 'gain', 'more', 'collect', 'بگیرم', 'بدست', 'به دست', 'کسب', 'دربیار', 'در بیار',
  'جمع کنم', 'بیشتر',
];
const List<String> _recommendWords = <String>[
  'recommend*', 'suggest*', 'what should i play', 'what to play', 'bored', 'something to play', 'پیشنهاد',
  'چی بازی کنم', 'حوصله', 'کدوم بازی', 'کدام بازی', 'چی بازی',
];
const List<String> _dailyWords = <String>[
  'daily', 'streak', 'reward', 'rewards', 'login bonus', 'روزانه', 'جایزه', 'استریک', 'پاداش',
];
const List<String> _challengeWords = <String>['challenge*', 'mission*', 'quest*', 'چالش', 'ماموریت'];
const List<String> _achievementWords = <String>[
  'achievement*', 'badge*', 'trophy', 'trophies', 'medal*', 'دستاورد', 'مدال', 'نشان ها', 'نشانها', 'افتخارات',
];
const List<String> _hubWords = <String>[
  'hub', 'home', 'main menu', 'lobby', 'هاب', 'خانه', 'خونه', 'ایستگاه', 'منوی اصلی',
];
const List<String> _settingsWords = <String>['settings', 'setting', 'تنظیمات'];
const List<String> _offlineLimitWords = <String>[
  'weather', 'forecast', 'news', 'stock', 'stocks', 'bitcoin', 'crypto', 'google', 'search the web',
  'search online', 'wikipedia', 'alarm', 'remind me', 'reminder', 'translate', 'dollar', 'exchange rate',
  'order food', 'book a', 'آب و هوا', 'هواشناسی', 'پیش بینی هوا', 'اخبار', 'بورس', 'بیت کوین', 'ارز دیجیتال',
  'دلار', 'گوگل', 'سرچ کن', 'جستجو کن', 'ویکی', 'زنگ هشدار', 'یادم بنداز', 'یاداوری', 'ترجمه', 'سفارش غذا',
  'رزرو',
];
const List<String> _sendVerbs = <String>['send', 'text', 'بفرست', 'ارسال کن', 'پیام بده', 'پیام بدی'];
const List<String> _messageWords = <String>['message', 'messages', 'msg', 'sms', 'email', 'پیام', 'ایمیل'];

const List<String> _greetWords = <String>[
  'hi', 'hello', 'hey', 'yo', 'salam', 'hiya', 'good morning', 'good evening', 'good afternoon', 'سلام', 'درود',
  'صبح بخیر', 'عصر بخیر', 'وقت بخیر',
];
const List<String> _thanksWords = <String>[
  'thanks', 'thank you', 'thx', 'ty', 'merci', 'مرسی', 'ممنون', 'متشکر', 'سپاس', 'دمت گرم', 'مچکر', 'تشکر',
];
const List<String> _howAreYouWords = <String>[
  'how are you', 'how r u', 'what s up', 'whats up', 'sup', 'wassup', 'چطوری', 'خوبی', 'حالت', 'چه خبر',
];
const List<String> _whoWords = <String>[
  'who are you', 'what are you', 'your name', 'are you human', 'are you real', 'are you ai', 'introduce yourself',
  'اسمت', 'تو کی هستی', 'کی هستی', 'تو چی هستی', 'خودتو معرفی', 'معرفی کن', 'ادمی', 'ربات',
];
const List<String> _helpWords = <String>[
  'help', 'what can you do', 'capabilit*', 'features', 'commands', 'کمک', 'چه کارهایی', 'چکار میتونی',
  'چیکار میتونی', 'چه کار میتونی', 'قابلیت', 'راهنمایی', 'چه کاری',
];
const List<String> _jokeWords = <String>['joke', 'funny', 'make me laugh', 'جوک', 'لطیفه', 'بخندون', 'شوخی'];
const List<String> _byeWords = <String>[
  'bye', 'goodbye', 'see you', 'good night', 'later', 'خداحافظ', 'بای=', 'فعلا', 'شب بخیر', 'بدرود',
];
const List<String> _loveWords = <String>['love you', 'i love', 'دوستت دارم', 'عاشقتم'];
const List<String> _ackWords = <String>['ok', 'okay', 'cool', 'nice', 'great', 'باشه', 'اوکی', 'خب', 'عالی', 'حله', 'اوکیه'];
const List<String> _timeWords = <String>[
  'what time', 'the time', 'what date', 'today s date', 'what day', 'ساعت چند', 'تاریخ', 'امروز چندمه', 'چندمه',
];

// ======================= Engine =======================

class OracleBrain {
  OracleBrain({Map<String, OracleGameInfo>? games}) : games = games ?? const <String, OracleGameInfo>{};

  /// gameId -> metadata (rules) provided by the UI from the Arcade registry.
  final Map<String, OracleGameInfo> games;

  static String normalize(String input) => normalizeOracleText(input);

  List<String> get gameIds {
    final List<String> ids = <String>[...games.keys];
    for (final OracleGameAlias a in kOracleGameAliases) {
      if (!ids.contains(a.id)) ids.add(a.id);
    }
    return ids;
  }

  String gameNameFa(String id) {
    final OracleGameInfo? g = games[id];
    if (g != null && g.nameFa.isNotEmpty) return g.nameFa;
    for (final OracleGameAlias a in kOracleGameAliases) {
      if (a.id == id) return a.nameFa;
    }
    return id;
  }

  String gameNameEn(String id) {
    final OracleGameInfo? g = games[id];
    if (g != null && g.nameEn.isNotEmpty) return g.nameEn;
    for (final OracleGameAlias a in kOracleGameAliases) {
      if (a.id == id) return a.nameEn;
    }
    return id;
  }

  /// Detects a game by its longest matching alias (registry names included).
  String? detectGame(String normalized) {
    final String padded = ' $normalized ';
    String? best;
    int bestLen = 0;
    for (final OracleGameAlias a in kOracleGameAliases) {
      for (final String alias in a.aliases) {
        final int l = oracleMatchLen(padded, alias);
        if (l > bestLen) {
          bestLen = l;
          best = a.id;
        }
      }
    }
    for (final OracleGameInfo g in games.values) {
      for (final String name in <String>[g.nameFa, g.nameEn]) {
        if (name.trim().isEmpty) continue;
        final int l = oracleMatchLen(padded, name);
        if (l > bestLen) {
          bestLen = l;
          best = g.id;
        }
      }
    }
    return best;
  }

  /// Detects a world by its longest matching alias.
  OracleWorld? detectWorld(String normalized) {
    final String padded = ' $normalized ';
    OracleWorld? best;
    int bestLen = 0;
    for (final OracleWorld w in kOracleWorlds) {
      for (final String alias in w.aliases) {
        final int l = oracleMatchLen(padded, alias);
        if (l > bestLen) {
          bestLen = l;
          best = w;
        }
      }
    }
    return best;
  }

  OracleReply respond(String input, OracleContext ctx) {
    final String t = normalizeOracleText(input);
    if (t.isEmpty) {
      return const OracleReply(
        textFa: 'هر سؤالی درباره‌ی NEXORA داری بپرس، یا بگو کجا ببرمت.',
        textEn: 'Ask me anything about NEXORA, or tell me where to take you.',
        pose: 'calm',
        intent: 'empty',
      );
    }
    final int tokens = t.split(' ').length;
    final String? gameId = detectGame(t);
    final OracleWorld? world = detectWorld(t);
    final bool navVerb = hasOracleKeyword(t, _navVerbs);
    final bool howQ = hasOracleKeyword(t, _howWords);

    final OracleReply? setting = _settingIntent(t, ctx);
    if (setting != null) return setting;

    if (hasOracleKeyword(t, _offlineLimitWords)) return _offlineLimit();

    if (!howQ && hasOracleKeyword(t, _sendVerbs) && hasOracleKeyword(t, _messageWords)) return _cannotSend();

    final OracleFaq? priority = _matchFaq(t, world != null, priorityOnly: true);
    if (priority != null) return _faqReply(priority);

    if (gameId != null) return _gameIntent(t, gameId, ctx, navVerb);

    if (hasOracleKeyword(t, _rulesWords)) return _askWhichGame();

    if (hasOracleKeyword(t, _coinWords)) {
      return hasOracleKeyword(t, _earnWords) ? _earnCoins(ctx) : _coinBalance(ctx);
    }
    if (hasOracleKeyword(t, _recommendWords)) return recommend(ctx);
    if (hasOracleKeyword(t, _achievementWords)) return _achievements(ctx);
    if (hasOracleKeyword(t, _dailyWords) && !hasOracleKeyword(t, _challengeWords)) return _daily(ctx);
    if (hasOracleKeyword(t, _statsWords)) return _stats(ctx);
    if (hasOracleKeyword(t, _levelWords)) return _level(ctx);

    final bool hub = hasOracleKeyword(t, _hubWords);
    final bool settingsWord = hasOracleKeyword(t, _settingsWords);
    if (navVerb || tokens <= 2) {
      if (world != null) return _navWorld(world, auto: true);
      if (settingsWord) return _navSettings(auto: true);
      if (hub) return _navHub(auto: true);
    }

    final OracleFaq? faq = _matchFaq(t, world != null, priorityOnly: false);
    if (faq != null) return _faqReply(faq);

    if (world != null) return _navWorld(world, auto: false);
    if (settingsWord) return _navSettings(auto: false);
    if (hub && navVerb) return _navHub(auto: true);

    final OracleReply? talk = _smallTalk(t, ctx, tokens);
    if (talk != null) return talk;

    return fallback();
  }

  // ---------------- settings ----------------

  OracleReply? _settingIntent(String t, OracleContext ctx) {
    // Language
    final bool langSubject = hasOracleKeyword(t, <String>['language', 'lang', 'زبان']);
    final int enIdx = oracleLastIndex(t, <String>['english', 'انگلیسی']);
    final int faIdx = oracleLastIndex(t, <String>['persian', 'farsi', 'فارسی', 'پارسی']);
    final bool langVerb = hasOracleKeyword(t, <String>[
      'switch', 'change', 'speak', 'talk', 'set', 'use', 'reply', 'answer', 'عوض', 'تغییر', 'حرف بزن', 'صحبت',
      'بنویس', 'جواب بده', 'کن=',
    ]);
    if ((enIdx >= 0 || faIdx >= 0) && (langSubject || langVerb)) {
      final String target = enIdx > faIdx ? 'en' : 'fa';
      if (target == ctx.languageCode) {
        return OracleReply(
          textFa: 'زبان برنامه همین الان ${target == 'fa' ? 'فارسی' : 'انگلیسی'} است.',
          textEn: 'The app language is already ${target == 'fa' ? 'Persian' : 'English'}.',
          pose: 'calm',
          intent: 'setting_same',
        );
      }
      return OracleReply(
        textFa: target == 'fa' ? 'زبان را به فارسی تغییر می‌دهم.' : 'زبان را به انگلیسی تغییر می‌دهم.',
        textEn: target == 'fa' ? 'Switching the language to Persian.' : 'Switching the language to English.',
        actions: <OracleAction>[
          OracleAction.setting(OracleSettingKeys.language, target,
              labelFa: target == 'fa' ? 'زبان: فارسی' : 'زبان: انگلیسی',
              labelEn: target == 'fa' ? 'Language: Persian' : 'Language: English'),
        ],
        pose: 'power',
        intent: 'setting',
        autoRun: true,
      );
    }
    if (langSubject) {
      return OracleReply(
        textFa: 'زبان فعلی ${ctx.languageCode == 'fa' ? 'فارسی' : 'انگلیسی'} است. کدام را می‌خواهی؟',
        textEn: 'The current language is ${ctx.languageCode == 'fa' ? 'Persian' : 'English'}. Which one do you want?',
        actions: const <OracleAction>[
          OracleAction.setting(OracleSettingKeys.language, 'fa', labelFa: 'فارسی', labelEn: 'Persian'),
          OracleAction.setting(OracleSettingKeys.language, 'en', labelFa: 'انگلیسی', labelEn: 'English'),
        ],
        pose: 'present',
        intent: 'setting_info',
      );
    }

    // Performance help
    if (hasOracleKeyword(t, <String>['lag', 'laggy', 'slow', 'stutter*', 'battery', 'hot', 'کند شده', 'کنده', 'لگ', 'هنگ', 'داغ', 'باتری'])) {
      return const OracleReply(
        textFa: 'اگر گوشی کند یا داغ می‌شود، کیفیت گرافیک را «پایین» بگذار و «کاهش حرکت» را روشن کن. هر دو را با یک لمس اینجا تغییر می‌دهم.',
        textEn: 'If the phone feels slow or hot, set graphics quality to Low and turn on Reduced Motion. Tap below and I\'ll change them.',
        actions: <OracleAction>[
          OracleAction.setting(OracleSettingKeys.quality, 'low', labelFa: 'کیفیت: پایین', labelEn: 'Quality: Low'),
          OracleAction.setting(OracleSettingKeys.reducedMotion, 'true',
              labelFa: 'روشن کردن کاهش حرکت', labelEn: 'Turn on Reduced Motion'),
        ],
        pose: 'alert',
        intent: 'performance',
      );
    }

    // Reduced motion
    final bool rmPhrase = hasOracleKeyword(t, <String>[
      'reduce motion', 'reduced motion', 'reduce animations', 'less motion', 'motion', 'کاهش حرکت', 'حرکت کم',
      'کم کردن حرکت',
    ]);
    final bool animSubject = hasOracleKeyword(t, <String>['animation', 'animations', 'effects', 'انیمیشن', 'افکت', 'جلوه']);
    if (rmPhrase || animSubject) {
      bool? value;
      if (rmPhrase) {
        final bool off = hasOracleKeyword(t, <String>[
          'off', 'disable', 'turn off', 'stop', 'خاموش', 'غیرفعال', 'قطع', 'بردار', 'نمیخوام', 'نمی خوام',
        ]);
        final bool on = hasOracleKeyword(t, <String>['on', 'enable', 'turn on', 'activate', 'روشن', 'فعال', 'بذار']);
        if (off && !on) {
          value = false;
        } else if (on && !off) {
          value = true;
        }
      } else {
        final bool less = hasOracleKeyword(t, <String>[
          'less', 'fewer', 'reduce', 'disable', 'off', 'stop', 'کم', 'کمتر', 'خاموش', 'غیرفعال', 'قطع', 'نمیخوام',
          'حذف',
        ]);
        final bool more = hasOracleKeyword(t, <String>['more', 'enable', 'on', 'back', 'بیشتر', 'روشن', 'فعال', 'زیاد', 'برگردون']);
        if (less && !more) {
          value = true;
        } else if (more && !less) {
          value = false;
        }
      }
      if (value == null && hasOracleKeyword(t, <String>['toggle', 'عوض', 'تغییر'])) value = !ctx.reducedMotion;
      if (value == null) {
        return OracleReply(
          textFa: 'کاهش حرکت الان ${ctx.reducedMotion ? 'روشن' : 'خاموش'} است. وقتی روشن باشد انیمیشن‌های طولانی، ذرات و حرکت دوربین حذف می‌شوند.',
          textEn: 'Reduced Motion is currently ${ctx.reducedMotion ? 'on' : 'off'}. When on, long animations, particles and camera motion are removed.',
          actions: const <OracleAction>[
            OracleAction.setting(OracleSettingKeys.reducedMotion, 'true', labelFa: 'روشن کن', labelEn: 'Turn on'),
            OracleAction.setting(OracleSettingKeys.reducedMotion, 'false', labelFa: 'خاموش کن', labelEn: 'Turn off'),
          ],
          pose: 'present',
          intent: 'setting_info',
        );
      }
      if (value == ctx.reducedMotion) {
        return OracleReply(
          textFa: 'کاهش حرکت از قبل ${value ? 'روشن' : 'خاموش'} است.',
          textEn: 'Reduced Motion is already ${value ? 'on' : 'off'}.',
          pose: 'calm',
          intent: 'setting_same',
        );
      }
      return OracleReply(
        textFa: value ? 'کاهش حرکت را روشن می‌کنم.' : 'کاهش حرکت را خاموش می‌کنم تا انیمیشن‌ها برگردند.',
        textEn: value ? 'Turning Reduced Motion on.' : 'Turning Reduced Motion off so animations come back.',
        actions: <OracleAction>[
          OracleAction.setting(OracleSettingKeys.reducedMotion, value ? 'true' : 'false',
              labelFa: value ? 'روشن کردن کاهش حرکت' : 'خاموش کردن کاهش حرکت',
              labelEn: value ? 'Turn on Reduced Motion' : 'Turn off Reduced Motion'),
        ],
        pose: 'power',
        intent: 'setting',
        autoRun: true,
      );
    }

    // Graphics quality
    if (hasOracleKeyword(t, <String>['quality', 'graphics', 'graphic', 'گرافیک', 'کیفیت'])) {
      String? q;
      if (hasOracleKeyword(t, <String>['ultra', 'max', 'maximum', 'highest', 'اولترا', 'حداکثر', 'بیشترین', 'بالاترین', 'فوق'])) {
        q = 'ultra';
      } else if (hasOracleKeyword(t, <String>['low', 'lowest', 'minimum', 'min', 'کم', 'پایین', 'ضعیف', 'حداقل'])) {
        q = 'low';
      } else if (hasOracleKeyword(t, <String>['medium', 'mid', 'normal', 'متوسط', 'معمولی', 'وسط'])) {
        q = 'medium';
      } else if (hasOracleKeyword(t, <String>['high', 'بالا', 'زیاد', 'خوب'])) {
        q = 'high';
      }
      if (q == null) {
        return OracleReply(
          textFa: 'کیفیت گرافیک فعلی: ${_qualityFa(ctx.quality)}. کدام سطح را می‌خواهی؟',
          textEn: 'Current graphics quality: ${_qualityEn(ctx.quality)}. Which level do you want?',
          actions: <OracleAction>[
            for (final String v in const <String>['low', 'medium', 'high', 'ultra'])
              OracleAction.setting(OracleSettingKeys.quality, v, labelFa: _qualityFa(v), labelEn: _qualityEn(v)),
          ],
          pose: 'present',
          intent: 'setting_info',
        );
      }
      if (q == ctx.quality) {
        return OracleReply(
          textFa: 'کیفیت گرافیک از قبل ${_qualityFa(q)} است.',
          textEn: 'Graphics quality is already ${_qualityEn(q)}.',
          pose: 'calm',
          intent: 'setting_same',
        );
      }
      return OracleReply(
        textFa: 'کیفیت گرافیک را روی ${_qualityFa(q)} می‌گذارم.',
        textEn: 'Setting graphics quality to ${_qualityEn(q)}.',
        actions: <OracleAction>[
          OracleAction.setting(OracleSettingKeys.quality, q,
              labelFa: 'کیفیت: ${_qualityFa(q)}', labelEn: 'Quality: ${_qualityEn(q)}'),
        ],
        pose: 'power',
        intent: 'setting',
        autoRun: true,
      );
    }
    return null;
  }

  static String _qualityFa(String q) {
    switch (q) {
      case 'low':
        return 'پایین';
      case 'medium':
        return 'متوسط';
      case 'ultra':
        return 'اولترا';
      default:
        return 'بالا';
    }
  }

  static String _qualityEn(String q) {
    switch (q) {
      case 'low':
        return 'Low';
      case 'medium':
        return 'Medium';
      case 'ultra':
        return 'Ultra';
      default:
        return 'High';
    }
  }

  // ---------------- honesty ----------------

  OracleReply _offlineLimit() => const OracleReply(
        textFa: 'این کار به اینترنت یا اطلاعات زنده نیاز دارد و من الان کاملاً آفلاین هستم، پس هنوز نمی‌توانم انجامش بدهم. چیزی از خودم نمی‌سازم. در عوض می‌توانم تو را به دنیاها و بازی‌ها ببرم یا درباره‌ی NEXORA کمک کنم.',
        textEn: 'That needs the internet or live information, and I\'m fully offline right now, so I can\'t do it yet. I won\'t make something up. I can take you to worlds and games or help with anything inside NEXORA instead.',
        pose: 'alert',
        intent: 'offline_limit',
      );

  OracleReply _cannotSend() => const OracleReply(
        textFa: 'من نمی‌توانم از طرف تو پیام بفرستم. خودت می‌توانی در اوربیت نتورک پیام بنویسی؛ ارسال به کاربران واقعی دیگر بعد از اتصال سرور فعال می‌شود.',
        textEn: 'I can\'t send messages on your behalf. You can write them yourself in Orbit Network; delivery to other real users turns on once the server is connected.',
        actions: <OracleAction>[kGoOrbitNet],
        pose: 'alert',
        intent: 'cannot_send',
      );

  /// Honest fallback: never pretends to have done anything.
  OracleReply fallback() => const OracleReply(
        textFa: 'صادقانه بگویم: این را نفهمیدم یا هنوز به‌صورت آفلاین نمی‌توانم انجامش بدهم. من می‌توانم تو را به هر دنیا یا بازی ببرم، قوانین بازی‌ها را توضیح بدهم، آمار و سطح و سکه‌هایت را بگویم، بازی پیشنهاد کنم و تنظیمات را تغییر بدهم.',
        textEn: 'Honestly, I didn\'t understand that, or I can\'t do it offline yet. I can take you to any world or game, explain game rules, tell you your stats, level and coins, recommend a game, and change settings.',
        pose: 'confused',
        intent: 'fallback',
        followUpsFa: <String>['منو ببر به آرکید', 'قوانین لودو', 'آمار من', 'چی بازی کنم؟'],
        followUpsEn: <String>['Take me to the Arcade', 'Ludo rules', 'My stats', 'What should I play?'],
      );

  // ---------------- FAQ ----------------

  OracleFaq? _matchFaq(String t, bool worldMentioned, {required bool priorityOnly}) {
    for (final OracleFaq f in kOracleFaq) {
      if (priorityOnly && !f.priority) continue;
      if (!priorityOnly && f.priority) continue;
      if (f.skipWhenWorld && worldMentioned) continue;
      bool all = true;
      for (final List<String> group in f.must) {
        if (!hasOracleKeyword(t, group)) {
          all = false;
          break;
        }
      }
      if (all) return f;
    }
    return null;
  }

  OracleReply _faqReply(OracleFaq f) => OracleReply(
        textFa: f.textFa,
        textEn: f.textEn,
        actions: f.actions,
        pose: f.pose,
        intent: 'faq_${f.id}',
      );

  // ---------------- navigation ----------------

  OracleReply _navWorld(OracleWorld w, {required bool auto}) {
    if (w.id == 'oracle_core') {
      return OracleReply(
        textFa: 'ما همین الان در اوراکل کور هستیم! ${w.descFa}',
        textEn: 'We\'re already in Oracle Core! ${w.descEn}',
        pose: 'happy',
        intent: 'navigate_self',
      );
    }
    return OracleReply(
      textFa: auto ? 'می‌رویم به ${w.nameFa}. ${w.descFa}' : '${w.nameFa}: ${w.descFa}',
      textEn: auto ? 'Heading to ${w.nameEn}. ${w.descEn}' : '${w.nameEn}: ${w.descEn}',
      actions: <OracleAction>[
        OracleAction.navigate('/world/${w.id}', labelFa: 'ورود به ${w.nameFa}', labelEn: 'Open ${w.nameEn}'),
      ],
      pose: 'present',
      intent: auto ? 'navigate' : 'world_info',
      autoRun: auto,
    );
  }

  OracleReply _navSettings({required bool auto}) => OracleReply(
        textFa: auto
            ? 'تنظیمات را باز می‌کنم. کیفیت، کاهش حرکت و زبان را من هم می‌توانم مستقیم عوض کنم.'
            : 'در تنظیمات کیفیت گرافیک، کاهش حرکت، زبان، صدا و لرزش را تغییر می‌دهی. بعضی را من هم مستقیم عوض می‌کنم؛ مثلاً بگو «کیفیت را پایین بگذار».',
        textEn: auto
            ? 'Opening Settings. I can also change quality, reduced motion and language directly.'
            : 'Settings controls graphics quality, reduced motion, language, sound and haptics. I can change some directly — e.g. say "set quality to low".',
        actions: const <OracleAction>[kGoSettings],
        pose: 'present',
        intent: auto ? 'navigate' : 'settings_info',
        autoRun: auto,
      );

  OracleReply _navHub({required bool auto}) => OracleReply(
        textFa: 'برمی‌گردیم به ایستگاه NEXORA.',
        textEn: 'Back to NEXORA Station.',
        actions: const <OracleAction>[
          OracleAction.navigate('/hub', labelFa: 'ایستگاه NEXORA', labelEn: 'NEXORA Station'),
        ],
        pose: 'present',
        intent: 'navigate',
        autoRun: auto,
      );

  // ---------------- games ----------------

  OracleAction _playAction(String id) =>
      OracleAction.navigate('/arcade/$id', labelFa: 'بازی ${gameNameFa(id)}', labelEn: 'Play ${gameNameEn(id)}');

  OracleReply _gameIntent(String t, String id, OracleContext ctx, bool navVerb) {
    final bool rules = hasOracleKeyword(t, _rulesWords) || hasOracleKeyword(t, _explainWords);
    if (rules) return rulesFor(id);
    if (hasOracleKeyword(t, _statsWords) ||
        hasOracleKeyword(t, <String>['how many', 'win', 'wins', 'won', 'چند بار', 'چندبار', 'بردم', 'باختم'])) {
      return _gameStats(id, ctx);
    }
    if (navVerb || hasOracleKeyword(t, _playWords)) {
      return OracleReply(
        textFa: 'صفحه‌ی ${gameNameFa(id)} را باز می‌کنم؛ آنجا حالت (ربات یا دونفره) و سختی را انتخاب کن.',
        textEn: 'Opening ${gameNameEn(id)} setup — pick the mode (bot or local) and difficulty there.',
        actions: <OracleAction>[_playAction(id)],
        pose: 'cheer',
        intent: 'play_game',
        autoRun: true,
      );
    }
    final OracleGameInfo? g = games[id];
    final OracleGameStat? s = ctx.stats[id];
    final int played = s?.played ?? 0;
    return OracleReply(
      textFa: '${gameNameFa(id)}: ${played == 0 ? 'هنوز بازی‌اش نکرده‌ای.' : '${faDigits(played)} بار بازی کرده‌ای و ${faDigits(s?.won ?? 0)} بار برده‌ای.'}'
          '${g != null && g.rulesFa.isNotEmpty ? '\n\n${_short(g.rulesFa)}' : ''}\n\nبگو «قوانین ${gameNameFa(id)}» تا کامل توضیح بدهم، یا همین الان بازی کن.',
      textEn: '${gameNameEn(id)}: ${played == 0 ? 'you haven\'t played it yet.' : 'you\'ve played $played times and won ${s?.won ?? 0}.'}'
          '${g != null && g.rulesEn.isNotEmpty ? '\n\n${_short(g.rulesEn)}' : ''}\n\nSay "${gameNameEn(id)} rules" for the full rules, or play now.',
      actions: <OracleAction>[_playAction(id)],
      pose: 'present',
      intent: 'game_info',
    );
  }

  static String _short(String s) {
    final String one = s.trim();
    if (one.length <= 220) return one;
    return '${one.substring(0, 217)}…';
  }

  /// Full rules for [id], or an honest note when the registry has none.
  OracleReply rulesFor(String id) {
    final OracleGameInfo? g = games[id];
    if (g == null || (g.rulesFa.trim().isEmpty && g.rulesEn.trim().isEmpty)) {
      return OracleReply(
        textFa: 'قوانین ${gameNameFa(id)} در این نسخه برای من بارگذاری نشده، پس چیزی از خودم نمی‌سازم. صفحه‌ی بازی را باز کن؛ راهنمای داخل خود بازی معتبر است.',
        textEn: 'The ${gameNameEn(id)} rules aren\'t loaded for me in this build, so I won\'t make them up. Open the game — its built-in guide is the reliable source.',
        actions: <OracleAction>[_playAction(id)],
        pose: 'confused',
        intent: 'rules_missing',
      );
    }
    final String fa = g.rulesFa.trim().isNotEmpty ? g.rulesFa.trim() : g.rulesEn.trim();
    final String en = g.rulesEn.trim().isNotEmpty ? g.rulesEn.trim() : g.rulesFa.trim();
    return OracleReply(
      textFa: 'قوانین ${gameNameFa(id)}:\n$fa',
      textEn: '${gameNameEn(id)} rules:\n$en',
      actions: <OracleAction>[_playAction(id)],
      pose: 'present',
      intent: 'rules',
    );
  }

  OracleReply _askWhichGame() {
    final List<String> ids = gameIds;
    return OracleReply(
      textFa: 'قوانین کدام بازی؟ ${ids.map(gameNameFa).join('، ')}',
      textEn: 'Rules for which game? ${ids.map(gameNameEn).join(', ')}',
      pose: 'confused',
      intent: 'rules_which',
      followUpsFa: <String>[for (final String id in ids.take(4)) 'قوانین ${gameNameFa(id)}'],
      followUpsEn: <String>[for (final String id in ids.take(4)) '${gameNameEn(id)} rules'],
    );
  }

  OracleReply _gameStats(String id, OracleContext ctx) {
    final OracleGameStat? s = ctx.stats[id];
    if (s == null || s.played == 0) {
      return OracleReply(
        textFa: 'هنوز ${gameNameFa(id)} بازی نکرده‌ای، پس آماری برایش نیست. یک دست امتحان کن!',
        textEn: 'You haven\'t played ${gameNameEn(id)} yet, so there are no stats. Give it a try!',
        actions: <OracleAction>[_playAction(id)],
        pose: 'calm',
        intent: 'game_stats',
      );
    }
    return OracleReply(
      textFa: 'آمار ${gameNameFa(id)}: ${faDigits(s.played)} بازی، ${faDigits(s.won)} برد، ${faDigits(s.lost)} باخت، ${faDigits(s.draw)} مساوی — نرخ برد ${faDigits(s.winRate)}٪. بهترین امتیاز: ${faDigits(s.best)}.',
      textEn: '${gameNameEn(id)} stats: ${s.played} played, ${s.won} won, ${s.lost} lost, ${s.draw} draws — ${s.winRate}% win rate. Best score: ${s.best}.',
      actions: <OracleAction>[_playAction(id)],
      pose: s.winRate >= 50 ? 'cheer' : 'calm',
      intent: 'game_stats',
    );
  }

  /// Recommends the least-played game (ties: registry order) and mentions the best one.
  OracleReply recommend(OracleContext ctx) {
    final List<String> ids = gameIds;
    String pick = ids.first;
    int minPlayed = 1 << 30;
    for (final String id in ids) {
      final int p = ctx.stats[id]?.played ?? 0;
      if (p < minPlayed) {
        minPlayed = p;
        pick = id;
      }
    }
    String? best;
    int bestRate = -1;
    for (final String id in ids) {
      final OracleGameStat? s = ctx.stats[id];
      if (s == null || s.played < 2) continue;
      if (s.winRate > bestRate) {
        bestRate = s.winRate;
        best = id;
      }
    }
    final String whyFa = minPlayed == 0 ? 'هنوز امتحانش نکرده‌ای' : 'کمتر از بقیه بازی‌اش کرده‌ای (${faDigits(minPlayed)} بار)';
    final String whyEn = minPlayed == 0 ? 'you haven\'t tried it yet' : 'it\'s your least played ($minPlayed times)';
    final String bestFa = best == null || best == pick
        ? ''
        : '\nبهترین بازی‌ات ${gameNameFa(best)} است با نرخ برد ${faDigits(bestRate)}٪.';
    final String bestEn =
        best == null || best == pick ? '' : '\nYour best game is ${gameNameEn(best)} with a $bestRate% win rate.';
    return OracleReply(
      textFa: 'پیشنهاد من: ${gameNameFa(pick)} — چون $whyFa.$bestFa',
      textEn: 'My pick: ${gameNameEn(pick)} — $whyEn.$bestEn',
      actions: <OracleAction>[
        _playAction(pick),
        if (best != null && best != pick) _playAction(best),
      ],
      pose: 'power',
      intent: 'recommend',
    );
  }

  // ---------------- personal data ----------------

  OracleReply _coinBalance(OracleContext ctx) => OracleReply(
        textFa: 'موجودی تو ${faDigits(ctx.coins)} سکه است. سکه از بازی، دستاورد، جایزه‌ی روزانه و چالش‌ها به دست می‌آید.',
        textEn: 'You have ${ctx.coins} coins. Coins come from matches, achievements, the daily reward and challenges.',
        actions: const <OracleAction>[kGoExchange],
        pose: 'happy',
        intent: 'coins',
      );

  OracleReply _earnCoins(OracleContext ctx) => OracleReply(
        textFa: 'راه‌های واقعی کسب سکه:\n• بازی در آرکید: برد ۴۰، مساوی ۱۵، باخت ۵ سکه\n• جایزه‌ی روزانه: ۶۰ تا ۱۲۰ سکه بسته به روزهای پیاپی\n• چالش‌های روزانه و هفتگی\n• باز کردن دستاوردها\nخرید سکه با پول واقعی وجود ندارد. موجودی فعلی: ${faDigits(ctx.coins)} سکه.',
        textEn: 'Real ways to earn coins:\n• Arcade matches: win 40, draw 15, loss 5\n• Daily reward: 60–120 depending on your streak\n• Daily and weekly challenges\n• Unlocking achievements\nThere is no buying coins with real money. Current balance: ${ctx.coins}.',
        actions: const <OracleAction>[kGoArcade, kGoPersonal],
        pose: 'present',
        intent: 'earn_coins',
      );

  OracleReply _level(OracleContext ctx) {
    final int left = ctx.xpForNextLevel - ctx.xpIntoLevel;
    return OracleReply(
      textFa: 'تو در سطح ${faDigits(ctx.level)} هستی (${ctx.rankFa}). ${faDigits(left)} XP تا سطح بعد مانده. XP از بازی (برد ۶۰، مساوی ۳۰، باخت ۱۵)، جایزه‌ی روزانه و چالش‌ها می‌آید؛ سقف روزانه ۳۰۰۰ XP است.',
      textEn: 'You\'re level ${ctx.level} (${ctx.rankEn}). $left XP to the next level. XP comes from matches (win 60, draw 30, loss 15), the daily reward and challenges; the daily cap is 3000 XP.',
      actions: const <OracleAction>[kGoPersonal],
      pose: 'cheer',
      intent: 'level',
    );
  }

  OracleReply _achievements(OracleContext ctx) {
    final StringBuffer fa = StringBuffer(
        'دستاوردها: ${faDigits(ctx.achievementsUnlocked)} از ${faDigits(ctx.achievementsTotal)} باز شده.');
    final StringBuffer en = StringBuffer('Achievements: ${ctx.achievementsUnlocked} of ${ctx.achievementsTotal} unlocked.');
    if (ctx.lockedAchievements.isNotEmpty) {
      fa.write('\nبعدی‌ها:');
      en.write('\nNext up:');
      for (final OracleAchievementHint h in ctx.lockedAchievements.take(3)) {
        fa.write('\n• ${h.nameFa}: ${h.descFa}');
        en.write('\n• ${h.nameEn}: ${h.descEn}');
      }
    } else if (ctx.achievementsTotal > 0) {
      fa.write('\nهمه را باز کرده‌ای! 🏆');
      en.write('\nYou unlocked them all! 🏆');
    }
    return OracleReply(
      textFa: fa.toString(),
      textEn: en.toString(),
      actions: const <OracleAction>[kGoPersonal],
      pose: ctx.achievementsUnlocked > 0 ? 'cheer' : 'present',
      intent: 'achievements',
    );
  }

  OracleReply _daily(OracleContext ctx) {
    if (ctx.canClaimDaily) {
      return OracleReply(
        textFa: 'جایزه‌ی روزانه‌ات آماده است! در پرسنال اوربیت دریافتش کن. ${ctx.streak > 0 ? 'رکورد پیاپی فعلی: ${faDigits(ctx.streak)} روز.' : ''}',
        textEn: 'Your daily reward is ready! Claim it in Personal Orbit. ${ctx.streak > 0 ? 'Current streak: ${ctx.streak} days.' : ''}',
        actions: const <OracleAction>[kGoPersonal],
        pose: 'cheer',
        intent: 'daily',
      );
    }
    return OracleReply(
      textFa: 'جایزه‌ی امروز را گرفته‌ای. رکورد پیاپی: ${faDigits(ctx.streak)} روز. فردا دوباره سر بزن تا زنجیره نشکند.',
      textEn: 'You already claimed today\'s reward. Streak: ${ctx.streak} days. Come back tomorrow to keep it going.',
      actions: const <OracleAction>[kGoPersonal],
      pose: 'calm',
      intent: 'daily',
    );
  }

  OracleReply _stats(OracleContext ctx) {
    if (ctx.totalPlayed == 0) {
      return const OracleReply(
        textFa: 'هنوز هیچ مسابقه‌ای ثبت نشده. اولین بازی‌ات را در آرکید شروع کن تا آمار واقعی ساخته شود.',
        textEn: 'No matches recorded yet. Start your first one in the Arcade and real stats will appear.',
        actions: <OracleAction>[kGoArcade],
        pose: 'calm',
        intent: 'stats',
      );
    }
    String top = '';
    int topPlayed = -1;
    ctx.stats.forEach((String id, OracleGameStat s) {
      if (s.played > topPlayed) {
        topPlayed = s.played;
        top = id;
      }
    });
    final int rate = ((ctx.totalWon * 100) / ctx.totalPlayed).round();
    return OracleReply(
      textFa: 'آمار کلی: ${faDigits(ctx.totalPlayed)} مسابقه، ${faDigits(ctx.totalWon)} برد (نرخ برد ${faDigits(rate)}٪). بیشترین بازی‌ات: ${gameNameFa(top)} (${faDigits(topPlayed)} بار).',
      textEn: 'Overall: ${ctx.totalPlayed} matches, ${ctx.totalWon} wins ($rate% win rate). Most played: ${gameNameEn(top)} ($topPlayed times).',
      actions: const <OracleAction>[kGoPersonal],
      pose: rate >= 50 ? 'cheer' : 'calm',
      intent: 'stats',
    );
  }

  // ---------------- small talk ----------------

  OracleReply? _smallTalk(String t, OracleContext ctx, int tokens) {
    final String nameFa = ctx.username.isEmpty ? '' : ' ${ctx.username}';
    final String nameEn = ctx.username.isEmpty ? '' : ', ${ctx.username}';
    if (hasOracleKeyword(t, _whoWords)) {
      return const OracleReply(
        textFa: 'من ORACLE هستم، دستیار NEXORA. یک برنامه‌ام، نه یک انسان؛ کاملاً روی دستگاه خودت و آفلاین کار می‌کنم، پس فقط چیزهایی را می‌دانم که در NEXORA و پیشرفت محلی تو هست — و هیچ‌وقت وانمود نمی‌کنم کاری را کرده‌ام که نکرده‌ام.',
        textEn: 'I\'m ORACLE, the NEXORA assistant. I\'m a program, not a person; I run fully offline on your device, so I only know what\'s in NEXORA and your local progress — and I never pretend to have done something I haven\'t.',
        pose: 'present',
        intent: 'who',
      );
    }
    if (hasOracleKeyword(t, _helpWords)) {
      return const OracleReply(
        textFa: 'کارهایی که واقعاً انجام می‌دهم:\n• بردن تو به هر دنیا یا بازی («منو ببر آرکید»)\n• توضیح قوانین هر بازی («قوانین تخته‌نرد»)\n• گفتن آمار، سطح، سکه و دستاوردها\n• پیشنهاد بازی\n• تغییر کیفیت گرافیک، کاهش حرکت و زبان\n• پاسخ به سؤال‌ها درباره‌ی همه‌ی دنیاهای NEXORA',
        textEn: 'What I can really do:\n• Take you to any world or game ("take me to the Arcade")\n• Explain any game\'s rules ("backgammon rules")\n• Tell your stats, level, coins and achievements\n• Recommend a game\n• Change graphics quality, reduced motion and language\n• Answer questions about every NEXORA world',
        pose: 'present',
        intent: 'help',
        followUpsFa: <String>['منو ببر به آرکید', 'قوانین تخته نرد', 'سطح من چنده؟', 'چی بازی کنم؟'],
        followUpsEn: <String>['Take me to the Arcade', 'Backgammon rules', 'What\'s my level?', 'What should I play?'],
      );
    }
    if (hasOracleKeyword(t, _jokeWords)) {
      final int i = t.length % kJokesFa.length;
      return OracleReply(textFa: kJokesFa[i], textEn: kJokesEn[i % kJokesEn.length], pose: 'spin', intent: 'joke');
    }
    if (hasOracleKeyword(t, _loveWords)) {
      return const OracleReply(
        textFa: 'لطف داری! من یک برنامه‌ام و احساس ندارم، ولی خوشحال می‌شوم کمکت کنم. بعد از اینجا، یک بازی با دوستانت روی همین گوشی بهتر از هر چیزی است. 😊',
        textEn: 'That\'s kind! I\'m a program without feelings, but I\'m glad to help. A pass-and-play match with friends on this phone beats any chat. 😊',
        actions: <OracleAction>[kGoArcade],
        pose: 'happy',
        intent: 'kind',
      );
    }
    if (hasOracleKeyword(t, _timeWords)) {
      final DateTime n = ctx.now ?? DateTime.now();
      String two(int v) => v < 10 ? '0$v' : '$v';
      final String time = '${two(n.hour)}:${two(n.minute)}';
      final String date = '${n.year}/${two(n.month)}/${two(n.day)}';
      return OracleReply(
        textFa: 'طبق ساعت دستگاهت، ساعت ${faDigits(time)} و تاریخ میلادی ${faDigits(date)} است.',
        textEn: 'By your device clock it\'s $time on $date.',
        pose: 'calm',
        intent: 'time',
      );
    }
    if (hasOracleKeyword(t, _thanksWords)) {
      return OracleReply(
        textFa: 'خواهش می‌کنم$nameFa! کار دیگری هست؟',
        textEn: 'You\'re welcome$nameEn! Anything else?',
        pose: 'happy',
        intent: 'thanks',
      );
    }
    if (hasOracleKeyword(t, _byeWords)) {
      return OracleReply(
        textFa: 'به امید دیدار$nameFa! هر وقت برگردی، من همین‌جا در مدارم. 🌙',
        textEn: 'See you$nameEn! I\'ll be right here in orbit when you\'re back. 🌙',
        pose: 'sleep',
        intent: 'bye',
      );
    }
    if (tokens <= 5 && hasOracleKeyword(t, _howAreYouWords)) {
      return OracleReply(
        textFa: 'همه‌ی سیستم‌هایم روشن و آماده‌اند ✨ تو چطوری$nameFa؟ می‌خواهی بازی کنیم یا جایی ببرمت؟',
        textEn: 'All systems are glowing and ready ✨ How about you$nameEn? Want to play something or go somewhere?',
        pose: 'happy',
        intent: 'how_are_you',
        followUpsFa: const <String>['چی بازی کنم؟', 'جایزه روزانه'],
        followUpsEn: const <String>['What should I play?', 'Daily reward'],
      );
    }
    if (hasOracleKeyword(t, _greetWords)) {
      return OracleReply(
        textFa: 'سلام$nameFa! من ORACLE هستم. می‌توانم تو را به دنیاها ببرم، قوانین بازی‌ها را بگویم یا پیشرفتت را نشان بدهم. از کجا شروع کنیم؟',
        textEn: 'Hi$nameEn! I\'m ORACLE. I can take you to any world, explain game rules or show your progress. Where shall we start?',
        pose: 'happy',
        intent: 'greet',
        followUpsFa: const <String>['چی بازی کنم؟', 'سطح من چنده؟', 'منو ببر به اکسچنج'],
        followUpsEn: const <String>['What should I play?', 'What\'s my level?', 'Take me to the Exchange'],
      );
    }
    if (tokens <= 2 && hasOracleKeyword(t, _ackWords)) {
      return const OracleReply(
        textFa: 'باشه! هر وقت خواستی بگو.',
        textEn: 'Got it! Just ask whenever you need me.',
        pose: 'calm',
        intent: 'ack',
      );
    }
    return null;
  }
}

/// Offline engine: deterministic, instant, runs on device.
class OfflineOracleEngine implements OracleEngine {
  OfflineOracleEngine({Map<String, OracleGameInfo>? games}) : brain = OracleBrain(games: games);

  final OracleBrain brain;

  OracleReply answer(String input, OracleContext context) => brain.respond(input, context);

  @override
  Future<OracleReply> ask(String input, OracleContext context) async => brain.respond(input, context);
}

/// Online engine: the project's `oracle-chat` Edge Function (LLM key server-side, per-user daily limit).
///
/// Contract (deployed function): POST `{messages:[{role,content}], ctx}` with the user's JWT →
/// `{message:{role:'assistant', content, tool_calls?}, model}`. The function's tools belong to the other
/// NEXORA app, so this client never executes them: it answers each with `not_available_in_this_app` once and
/// asks again; anything still unusable falls back to the offline brain.
///
/// App-aware intents (navigation, settings, rules, stats, coins…) stay on the instant offline brain because it
/// reads real local data; open conversation goes to the LLM. Any network/limit error → offline reply.
class RemoteOracleEngine implements OracleEngine {
  RemoteOracleEngine({required this.invoke, required this.offline, this.appContext = const <String, dynamic>{}});

  /// Calls the Edge Function with a JSON body and returns its decoded JSON (or throws).
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic> body) invoke;
  final OfflineOracleEngine offline;
  final Map<String, dynamic> appContext;
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];

  static const Set<String> remoteIntents = <String>{
    'fallback', 'offline_limit', 'joke', 'how_are_you', 'kind', 'who', 'cannot_send', 'rules_missing', 'recommend', 'greet',
  };

  void _remember(String role, String content) {
    _history.add(<String, dynamic>{'role': role, 'content': content});
    if (_history.length > 16) _history.removeRange(0, _history.length - 16);
  }

  @override
  Future<OracleReply> ask(String input, OracleContext context) async {
    final OracleReply local = offline.answer(input, context);
    if (!remoteIntents.contains(local.intent)) {
      _remember('user', input);
      _remember('assistant', context.languageCode == 'fa' ? local.textFa : local.textEn);
      return local;
    }
    try {
      final String? text = await _remote(input, context);
      if (text == null || text.trim().isEmpty) return local;
      return OracleReply(
        textFa: text.trim(),
        textEn: text.trim(),
        actions: local.intent == 'fallback' ? const <OracleAction>[] : local.actions,
        pose: 'talk',
        intent: 'remote',
      );
    } catch (_) {
      return local;
    }
  }

  Future<String?> _remote(String input, OracleContext c) async {
    final List<Map<String, dynamic>> msgs = <Map<String, dynamic>>[
      ..._history,
      <String, dynamic>{'role': 'user', 'content': input},
    ];
    final Map<String, dynamic> ctx = <String, dynamic>{
      'app': 'NEXORA hub (Flutter): 7 worlds (Hub, Arcade with 9 games, Orbit Network messenger, Nova Gallery, '
          'Social Station, Personal Orbit, ORACLE Core). NOT the finger-football app: app tools are unavailable here, '
          'answer in plain text only, short, in the user\'s language.',
      'language': c.languageCode,
      'username': c.username,
      'level': c.level,
      'xp': c.xp,
      'coins': c.coins,
      'played': c.totalPlayed,
      'won': c.totalWon,
      ...appContext,
    };
    for (int round = 0; round < 2; round++) {
      final Map<String, dynamic>? r = await invoke(<String, dynamic>{'messages': msgs, 'ctx': ctx});
      if (r == null || r['error'] != null) return null;
      final Object? m = r['message'];
      if (m is! Map) return null;
      final Object? calls = m['tool_calls'];
      final String content = '${m['content'] ?? ''}';
      if (calls is List && calls.isNotEmpty) {
        msgs.add(<String, dynamic>{'role': 'assistant', 'content': m['content'], 'tool_calls': calls});
        for (final Object? tc in calls) {
          if (tc is! Map) continue;
          msgs.add(<String, dynamic>{
            'role': 'tool',
            'tool_call_id': '${tc['id']}',
            'content': '{"error":"not_available_in_this_app","hint":"answer in text only"}',
          });
        }
        continue;
      }
      if (content.trim().isEmpty) return null;
      _remember('user', input);
      _remember('assistant', content);
      return content;
    }
    return null;
  }
}
