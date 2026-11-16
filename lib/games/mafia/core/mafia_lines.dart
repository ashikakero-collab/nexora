import 'dart:math';

import 'mafia_models.dart';

/// What a player (bot or human) says during the day. Speech acts are the
/// public events every bot's suspicion model listens to; the text is only
/// their bilingual rendering.
enum SpeechType {
  accuse,
  defend,
  claimRole,
  reportCheck,
  vague,
  selfDefense,
  agree,
  plea,
  lastWords,
}

/// Bot personalities flavour the wording and drive behaviour weights.
enum BotPersonality { hothead, analyst, cautious, joker, schemer }

class SpeechAct {
  const SpeechAct({
    required this.speaker,
    required this.type,
    this.target,
    this.role,
    this.checkMafia,
    this.strength = 0.6,
    this.secondary,
  });

  final int speaker;
  final SpeechType type;
  final int? target;

  /// Claimed role (claimRole) — may be a bluff.
  final MafiaRole? role;

  /// Claimed investigation result (reportCheck).
  final bool? checkMafia;

  /// 0..1 how forceful an accusation is.
  final double strength;

  /// Second name used by `agree` (who made the original accusation).
  final int? secondary;
}

class LinePair {
  const LinePair(this.fa, this.en);
  final String fa;
  final String en;
}

class MafiaLines {
  MafiaLines._();

  static LinePair render(
    SpeechAct act, {
    required String Function(int id) nameOf,
    required BotPersonality personality,
    required Random rng,
    bool withFlavor = true,
  }) {
    final List<LinePair> pool = _pool(act);
    final LinePair base = pool[rng.nextInt(pool.length)];
    final String tName = act.target == null ? '' : nameOf(act.target!);
    final String sName = act.secondary == null ? '' : nameOf(act.secondary!);
    final MafiaRole role = act.role ?? MafiaRole.citizen;
    String fa = base.fa
        .replaceAll('{t}', tName)
        .replaceAll('{s}', sName)
        .replaceAll('{r}', role.labelFa)
        .replaceAll('{x}', act.checkMafia == true ? 'مافیا' : 'بی‌گناه');
    String en = base.en
        .replaceAll('{t}', tName)
        .replaceAll('{s}', sName)
        .replaceAll('{r}', role.labelEn)
        .replaceAll('{x}', act.checkMafia == true ? 'MAFIA' : 'innocent');
    if (withFlavor && rng.nextDouble() < 0.45) {
      final List<LinePair> f = _flavor[personality]!;
      final LinePair pre = f[rng.nextInt(f.length)];
      fa = '${pre.fa} $fa';
      en = '${pre.en} $en';
    }
    return LinePair(fa, en);
  }

  static List<LinePair> _pool(SpeechAct act) {
    switch (act.type) {
      case SpeechType.accuse:
        return act.strength >= 0.7 ? _accuseStrong : _accuseSoft;
      case SpeechType.defend:
        return _defend;
      case SpeechType.claimRole:
        return act.role == MafiaRole.citizen ? _claimCitizen : _claimRole;
      case SpeechType.reportCheck:
        return act.checkMafia == true ? _reportMafia : _reportInnocent;
      case SpeechType.vague:
        return _vague;
      case SpeechType.selfDefense:
        return _selfDefense;
      case SpeechType.agree:
        return _agree;
      case SpeechType.plea:
        return _plea;
      case SpeechType.lastWords:
        return _lastWords;
    }
  }

  static const Map<BotPersonality, List<LinePair>> _flavor = <BotPersonality, List<LinePair>>{
    BotPersonality.hothead: <LinePair>[
      LinePair('گوش کنید!', 'Listen up!'),
      LinePair('بس کنید دیگه!', 'Enough!'),
      LinePair('من رک می‌گم:', "I'll be blunt:"),
    ],
    BotPersonality.analyst: <LinePair>[
      LinePair('منطقی که نگاه کنیم،', 'Logically speaking,'),
      LinePair('بر اساس رأی‌ها،', 'Going by the votes,'),
      LinePair('داده‌ها می‌گن', 'The data says'),
    ],
    BotPersonality.cautious: <LinePair>[
      LinePair('مطمئن نیستم، ولی', "I'm not certain, but"),
      LinePair('با احتیاط می‌گم،', 'Carefully now,'),
      LinePair('شاید اشتباه کنم، اما', 'I might be wrong, but'),
    ],
    BotPersonality.joker: <LinePair>[
      LinePair('خب خب خب...', 'Well well well...'),
      LinePair('ستاره‌ها بهم گفتن', 'The stars told me'),
      LinePair('بی‌شوخی این بار،', 'No jokes this time,'),
    ],
    BotPersonality.schemer: <LinePair>[
      LinePair('یه نکته‌ی جالب:', 'Interesting detail:'),
      LinePair('دقت کردید که', 'Did you notice that'),
      LinePair('بین خودمون باشه،', 'Between us,'),
    ],
  };

  static const List<LinePair> _accuseStrong = <LinePair>[
    LinePair('من مطمئنم {t} مافیاست. امروز باید بره.', "I'm sure {t} is Mafia. They go today."),
    LinePair('همه‌ی نشانه‌ها به {t} اشاره می‌کنه. رأی من به {t}.', 'Every sign points to {t}. My vote is on {t}.'),
    LinePair('{t} از اول بازی داره بازی رو می‌چرخونه. مافیاست.', '{t} has been steering this game from the start. Mafia.'),
    LinePair('رأی‌های {t} رو نگاه کنید؛ همیشه به نفع مافیاست.', "Look at {t}'s votes — always in the Mafia's favour."),
    LinePair('اگه {t} امروز نره، فردا یکی دیگه از ما رو از دست می‌دیم.', "If {t} survives today, we lose another one of us tonight."),
    LinePair('{t}، دیگه نمی‌تونی پنهان بشی.', "{t}, you can't hide anymore."),
  ];

  static const List<LinePair> _accuseSoft = <LinePair>[
    LinePair('به {t} کمی شک دارم.', "I'm a bit suspicious of {t}."),
    LinePair('{t} زیادی ساکته، این برام عجیبه.', "{t} is too quiet. That's odd to me."),
    LinePair('حرف‌های {t} با رأی‌هاش جور درنمیاد.', "{t}'s words don't match their votes."),
    LinePair('فعلاً چشمم روی {t} هست.', 'For now, my eyes are on {t}.'),
    LinePair('{t} خیلی سریع موضوع رو عوض کرد.', '{t} changed the subject very quickly.'),
    LinePair('یه حس بد درباره‌ی {t} دارم.', 'I have a bad feeling about {t}.'),
  ];

  static const List<LinePair> _defend = <LinePair>[
    LinePair('من به {t} اعتماد دارم؛ دنبال کس دیگه‌ای بگردید.', 'I trust {t}; look somewhere else.'),
    LinePair('{t} از اول شفاف بازی کرده.', '{t} has played transparently from the start.'),
    LinePair('حذف {t} دقیقاً همون چیزیه که مافیا می‌خواد.', 'Eliminating {t} is exactly what the Mafia wants.'),
    LinePair('رأی‌های {t} منطقی بوده. ولش کنید.', "{t}'s votes have been sensible. Leave them be."),
    LinePair('فشار روی {t} زیادی مشکوکه.', 'All this pressure on {t} is suspicious itself.'),
  ];

  static const List<LinePair> _claimRole = <LinePair>[
    LinePair('وقتشه بگم: من {r} هستم.', "Time to say it: I am the {r}."),
    LinePair('نقشم رو رو می‌کنم — {r}.', "I'm revealing my role — {r}."),
    LinePair('من {r}م و دلیلی برای دروغ ندارم.', "I'm the {r}, and I have no reason to lie."),
    LinePair('به عنوان {r} حرف می‌زنم، خوب گوش بدید.', 'I speak as the {r}. Listen carefully.'),
  ];

  static const List<LinePair> _claimCitizen = <LinePair>[
    LinePair('من یه شهروند ساده‌ام، همین.', "I'm a plain citizen, that's all."),
    LinePair('نقش خاصی ندارم، ولی ذهنم کار می‌کنه.', 'No special role, but my mind works fine.'),
    LinePair('شهروندم؛ حذف من فقط به مافیا کمک می‌کنه.', "I'm a citizen; voting me out only helps the Mafia."),
  ];

  static const List<LinePair> _reportMafia = <LinePair>[
    LinePair('استعلام من: {t} مافیاست!', 'My investigation: {t} is MAFIA!'),
    LinePair('دیشب {t} رو چک کردم. جواب: مافیا.', 'Last night I checked {t}. Result: Mafia.'),
    LinePair('شک نکنید، {t} از تیم مافیاست.', 'No doubt — {t} is on the Mafia team.'),
  ];

  static const List<LinePair> _reportInnocent = <LinePair>[
    LinePair('{t} رو استعلام کردم؛ بی‌گناه بود.', 'I investigated {t}; innocent.'),
    LinePair('نتیجه‌ی {t}: {x}. بهش کاری نداشته باشید.', 'Result on {t}: {x}. Leave them alone.'),
    LinePair('{t} پاکه — حداقل طبق استعلام من.', '{t} is clean — at least by my check.'),
  ];

  static const List<LinePair> _vague = <LinePair>[
    LinePair('هنوز تصویر روشنی ندارم. رأی‌ها رو دنبال کنیم.', "No clear picture yet. Let's follow the votes."),
    LinePair('کسی که امروز بیشتر از همه هیاهو می‌کنه رو زیر نظر داشته باشید.', 'Watch whoever makes the most noise today.'),
    LinePair('مافیا همیشه سعی می‌کنه بی‌طرف به نظر برسه.', 'The Mafia always tries to look neutral.'),
    LinePair('بیاید عجله نکنیم؛ یه رأی اشتباه یعنی یه شهروند کمتر.', "Let's not rush; one wrong vote is one citizen fewer."),
    LinePair('ایستگاه امشب ساکت‌تر از همیشه‌ست...', 'The station is quieter than ever tonight...'),
    LinePair('قربانی دیشب احتمالاً به چیزی نزدیک شده بود.', "Last night's victim was probably onto something."),
  ];

  static const List<LinePair> _selfDefense = <LinePair>[
    LinePair('من مافیا نیستم! دارید وقت رو هدر می‌دید.', "I'm not Mafia! You're wasting time."),
    LinePair('اتهام به من فقط مافیا رو خوشحال می‌کنه.', 'Accusing me only makes the Mafia happy.'),
    LinePair('رأی‌های منو نگاه کنید؛ همیشه با شهر بودم.', "Check my votes — I've always sided with the town."),
    LinePair('کسی که منو متهم کرد خودش مشکوکه.', 'Whoever accused me is the suspicious one.'),
    LinePair('اگه منو حذف کنید، فردا پشیمون می‌شید.', "Vote me out and you'll regret it tomorrow."),
  ];

  static const List<LinePair> _agree = <LinePair>[
    LinePair('با {s} موافقم؛ {t} مشکوکه.', 'I agree with {s}; {t} is suspicious.'),
    LinePair('{s} درست می‌گه، {t} توضیح بده!', '{s} is right — {t}, explain yourself!'),
    LinePair('منم همین حس رو درباره‌ی {t} دارم.', 'I get the same feeling about {t}.'),
  ];

  static const List<LinePair> _plea = <LinePair>[
    LinePair('آخرین فرصتمه: من بی‌گناهم. به حرف‌هام فکر کنید.', 'My last chance: I am innocent. Think about what I said.'),
    LinePair('رأی به من، رأی به مافیاست.', 'A vote against me is a vote for the Mafia.'),
    LinePair('من فقط سعی کردم شهر رو نجات بدم.', 'All I tried to do was save the town.'),
    LinePair('بذارید یه روز دیگه بمونم تا ثابت کنم.', 'Give me one more day to prove it.'),
  ];

  static const List<LinePair> _lastWords = <LinePair>[
    LinePair('یادتون باشه کی منو هدف گرفت...', 'Remember who targeted me...'),
    LinePair('موفق باشید. مافیا هنوز بین شماست.', 'Good luck. The Mafia is still among you.'),
    LinePair('امیدوارم اشتباه کرده باشید که فهمیدید.', 'I hope you realise your mistake in time.'),
  ];
}
