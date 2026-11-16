import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/worlds/oracle_core/core/oracle_brain.dart';

const Map<String, OracleGameInfo> _games = <String, OracleGameInfo>{
  'finger_soccer': OracleGameInfo(id: 'finger_soccer', nameFa: 'فوتبال دستی', nameEn: 'Finger Soccer', rulesFa: 'قانون فوتبال', rulesEn: 'Flick to score.'),
  'carrom': OracleGameInfo(id: 'carrom', nameFa: 'کرام', nameEn: 'Carrom', rulesFa: 'قانون کرام', rulesEn: 'Pocket your men.'),
  'backgammon': OracleGameInfo(
      id: 'backgammon', nameFa: 'تخته‌نرد', nameEn: 'Backgammon', rulesFa: 'مهره‌ها را به خانه ببر', rulesEn: 'Bear off all checkers first.'),
  'ludo': OracleGameInfo(id: 'ludo', nameFa: 'لودو', nameEn: 'Ludo', rulesFa: 'با شش وارد شو', rulesEn: 'Roll a six to enter.'),
  'uno': OracleGameInfo(id: 'uno', nameFa: 'اونو', nameEn: 'UNO', rulesFa: 'رنگ یا عدد را جور کن', rulesEn: 'Match colour or number.'),
  'mafia': OracleGameInfo(id: 'mafia', nameFa: 'مافیا', nameEn: 'Mafia'),
};

OracleBrain _brain() => OracleBrain(games: _games);

void main() {
  group('normalization', () {
    test('Arabic letters, Persian digits and half-spaces are normalized', () {
      expect(normalizeOracleText('كتاب ي'), 'کتاب ی');
      expect(normalizeOracleText('۱۲۳ و ٤٥'), '123 و 45');
      expect(normalizeOracleText('بازی\u200cها'), 'بازی ها');
      expect(normalizeOracleText('  Hello,   WORLD!! '), 'hello world');
      expect(normalizeOracleText('آرکید'), 'ارکید');
    });

    test('faDigits converts to Persian digits', () {
      expect(faDigits(2026), '۲۰۲۶');
    });
  });

  group('navigation intents', () {
    const OracleContext ctx = OracleContext();

    test('fa: take me to the arcade', () {
      final OracleReply r = _brain().respond('منو ببر به آرکید', ctx);
      expect(r.intent, 'navigate');
      expect(r.autoRun, isTrue);
      expect(r.actions.first.type, OracleActionType.navigate);
      expect(r.actions.first.route, '/world/nexora_arcade');
    });

    test('en: take me to the exchange', () {
      final OracleReply r = _brain().respond('Take me to the Exchange', ctx);
      expect(r.actions.first.route, '/world/nexora_exchange');
    });

    test('personal orbit wins over orbit network', () {
      final OracleReply r = _brain().respond('open personal orbit', ctx);
      expect(r.actions.first.route, '/world/personal_orbit');
      final OracleReply r2 = _brain().respond('open orbit network', ctx);
      expect(r2.actions.first.route, '/world/orbit_network');
    });

    test('settings and hub', () {
      expect(_brain().respond('برو تنظیمات', ctx).actions.first.route, '/settings');
      expect(_brain().respond('go home', ctx).actions.first.route, '/hub');
    });

    test('play a game opens its setup (fa + en, Arabic letters)', () {
      final OracleReply r = _brain().respond('بیا لودو بازی کنیم', ctx);
      expect(r.intent, 'play_game');
      expect(r.actions.first.route, '/arcade/ludo');
      final OracleReply r2 = _brain().respond('take me to the arcade and create a ludo room', ctx);
      expect(r2.actions.first.route, '/arcade/ludo');
      final OracleReply r3 = _brain().respond('play uno', ctx);
      expect(r3.actions.first.route, '/arcade/uno');
    });
  });

  group('rules', () {
    const OracleContext ctx = OracleContext();

    test('fa rules for backgammon', () {
      final OracleReply r = _brain().respond('قوانین تخته نرد رو بگو', ctx);
      expect(r.intent, 'rules');
      expect(r.textFa, contains('مهره‌ها را به خانه ببر'));
      expect(r.textEn, contains('Bear off'));
    });

    test('en rules for UNO', () {
      final OracleReply r = _brain().respond('How do I play UNO?', ctx);
      expect(r.intent, 'rules');
      expect(r.textEn, contains('Match colour'));
    });

    test('missing rules are reported honestly', () {
      final OracleReply r = _brain().respond('rules of mafia', ctx);
      expect(r.intent, 'rules_missing');
      expect(r.textEn, contains("won't make them up"));
    });

    test('rules without a game asks which game', () {
      expect(_brain().respond('قوانین بازی چیه؟', ctx).intent, 'rules_which');
    });
  });

  group('personal data', () {
    final OracleContext ctx = OracleContext(
      level: 4,
      xpIntoLevel: 50,
      xpForNextLevel: 325,
      rankFa: 'ناوبر',
      rankEn: 'Navigator',
      coins: 740,
      achievementsUnlocked: 2,
      achievementsTotal: 17,
      canClaimDaily: true,
      streak: 2,
      stats: const <String, OracleGameStat>{
        'finger_soccer': OracleGameStat(played: 5, won: 4, lost: 1),
        'carrom': OracleGameStat(played: 3, won: 1, lost: 2),
        'backgammon': OracleGameStat(played: 2, won: 0, lost: 2),
        'ludo': OracleGameStat(played: 2, won: 1, lost: 1),
        'uno': OracleGameStat(played: 1, won: 1),
        'mafia': OracleGameStat(played: 1),
      },
    );

    test('coins with Arabic letters', () {
      final OracleReply r = _brain().respond('سكه هاي من چقدره؟', ctx);
      expect(r.intent, 'coins');
      expect(r.textEn, contains('740'));
      expect(r.textFa, contains('۷۴۰'));
    });

    test('how to earn coins', () {
      expect(_brain().respond('how can I earn more coins?', ctx).intent, 'earn_coins');
    });

    test('level and stats', () {
      expect(_brain().respond("what's my level?", ctx).intent, 'level');
      final OracleReply s = _brain().respond('آمار من', ctx);
      expect(s.intent, 'stats');
      expect(s.textEn, contains('14 matches'));
      final OracleReply g = _brain().respond('my stats in finger soccer', ctx);
      expect(g.intent, 'game_stats');
      expect(g.textEn, contains('80%'));
    });

    test('achievements and daily', () {
      expect(_brain().respond('دستاوردهای من', ctx).intent, 'achievements');
      final OracleReply d = _brain().respond('daily reward', ctx);
      expect(d.intent, 'daily');
      expect(d.textEn, contains('ready'));
    });

    test('recommendation picks the least played game', () {
      final OracleReply r = _brain().respond('چی بازی کنم؟', ctx);
      expect(r.intent, 'recommend');
      // snakes_ladders, billiards and quiz were never played; the first unplayed
      // in order (registry games first, then built-in ids) is snakes_ladders.
      expect(r.actions.first.route, '/arcade/snakes_ladders');
      expect(r.textEn, contains('Finger Soccer'));
    });

    test('recommendation with all games played uses least played', () {
      final OracleBrain b = OracleBrain(games: const <String, OracleGameInfo>{
        'ludo': OracleGameInfo(id: 'ludo', nameFa: 'لودو', nameEn: 'Ludo'),
      });
      final Map<String, OracleGameStat> all = <String, OracleGameStat>{
        for (final String id in b.gameIds) id: const OracleGameStat(played: 5, won: 2),
      };
      all['quiz'] = const OracleGameStat(played: 1);
      final OracleReply r = b.recommend(OracleContext(stats: all));
      expect(r.actions.first.route, '/arcade/quiz');
    });
  });

  group('settings actions', () {
    const OracleContext ctx = OracleContext(quality: 'high', reducedMotion: false, languageCode: 'fa');

    test('quality low in Persian', () {
      final OracleReply r = _brain().respond('کیفیت گرافیک رو بذار روی پایین', ctx);
      expect(r.intent, 'setting');
      expect(r.actions.single.type, OracleActionType.setting);
      expect(r.actions.single.settingKey, OracleSettingKeys.quality);
      expect(r.actions.single.settingValue, 'low');
    });

    test('reduced motion on (en) and animations less (fa)', () {
      final OracleReply r = _brain().respond('turn on reduced motion', ctx);
      expect(r.actions.single.settingKey, OracleSettingKeys.reducedMotion);
      expect(r.actions.single.settingValue, 'true');
      final OracleReply r2 = _brain().respond('انیمیشن ها رو کم کن', ctx);
      expect(r2.actions.single.settingValue, 'true');
    });

    test('language switch to English', () {
      final OracleReply r = _brain().respond('switch to english', ctx);
      expect(r.actions.single.settingKey, OracleSettingKeys.language);
      expect(r.actions.single.settingValue, 'en');
      final OracleReply same = _brain().respond('زبان رو فارسی کن', ctx);
      expect(same.intent, 'setting_same');
      expect(same.actions, isEmpty);
    });
  });

  group('honesty', () {
    const OracleContext ctx = OracleContext();

    test('unknown input falls back honestly with no actions', () {
      final OracleReply r = _brain().respond('qwzx blorf', ctx);
      expect(r.intent, 'fallback');
      expect(r.isHonestLimit, isTrue);
      expect(r.actions, isEmpty);
      expect(r.textEn, contains("can't do it offline yet"));
      expect(r.pose, 'confused');
    });

    test('internet-only requests are declined, not faked', () {
      final OracleReply r = _brain().respond("what's the weather tomorrow?", ctx);
      expect(r.intent, 'offline_limit');
      expect(r.actions, isEmpty);
      final OracleReply r2 = _brain().respond('اخبار امروز رو بگو', ctx);
      expect(r2.intent, 'offline_limit');
    });

    test('cannot send messages on behalf of the user', () {
      final OracleReply r = _brain().respond('send a message to Sara', ctx);
      expect(r.intent, 'cannot_send');
      expect(r.textEn, contains("can't send"));
    });

    test('calls are labelled online-only', () {
      expect(_brain().respond('can I make a video call?', ctx).intent, 'faq_calls');
    });

    test('small talk', () {
      expect(_brain().respond('سلام', ctx).intent, 'greet');
      expect(_brain().respond('hello', ctx).pose, 'happy');
      expect(_brain().respond('مرسی', ctx).intent, 'thanks');
      expect(_brain().respond('who are you?', ctx).textEn, contains('not a person'));
    });

    test('FAQ answers', () {
      expect(_brain().respond('How do I buy items?', ctx).intent, 'faq_buy');
      expect(_brain().respond('loot boxes?', ctx).intent, 'faq_gambling');
      expect(_brain().respond('چطور اتاقم رو تزئین کنم', ctx).intent, 'faq_decor');
    });

    test('offline engine is async and identical', () async {
      final OfflineOracleEngine e = OfflineOracleEngine(games: _games);
      final OracleReply r = await e.ask('منو ببر به آرکید', ctx);
      expect(r.actions.first.route, '/world/nexora_arcade');
    });

    test('actions round-trip through json', () {
      const OracleAction a = OracleAction.setting(OracleSettingKeys.quality, 'low', labelFa: 'ک', labelEn: 'Q');
      final OracleAction b = OracleAction.fromJson(a.toJson());
      expect(b.type, OracleActionType.setting);
      expect(b.settingValue, 'low');
      expect(b.labelEn, 'Q');
    });
  });
}
