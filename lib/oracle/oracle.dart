// Port of src/oracle/Oracle.tsx (+ coach.ts): the floating Oracle assistant: greeting, reactions to events,
// match coach toasts, a chat panel answering from the local knowledge base, and smart actions.
import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../net/discs.dart';
import '../net/supabase.dart';
import '../ui/kit.dart';
import 'kb.dart';

final _rnd = math.Random();

const kTips = [
  'از دیواره‌ها برای ضربه‌ی کمانه‌ای استفاده کن؛ دروازه‌بان‌ها انتظارش رو ندارن.',
  'همیشه قدرت کامل لازم نیست؛ ضربه‌ی متوسط توپ رو کنترل‌شده‌تر می‌بره.',
  'یک دیسک رو جلوی دروازه نگه دار تا ضدحمله‌ها رو خنثی کنه.',
  'قبل از شوت، پیش‌نمایش مسیر رو نگاه کن؛ دیسک‌های دقیق‌تر مسیر بلندتری نشون می‌دن.',
  'با ضربه‌ی اول نمی‌شه گل زد؛ اول توپ رو به موقعیت خوب برسون.',
  'اگر زمان نوبت کمه، یک ضربه‌ی امن دفاعی بهتر از از دست دادن نوبته.',
];
String tip() => kTips[_rnd.nextInt(kTips.length)];

(String, String) resultLine(String out) {
  if (out == 'victory') return (_rnd.nextDouble() < .5 ? 'joy' : 'laugh', ['عالی بود کاپیتان! 🏆', 'چه بردی! کهکشان به احترامت ایستاده. ✨', 'همین‌طوری ادامه بده، قهرمان! 🔥'][_rnd.nextInt(3)]);
  if (out == 'defeat') return ('calm', 'اشکالی نداره، دست بعدی مال ماست. 💙 نکته: ${tip()}');
  return ('content', 'مساوی! فقط یک ضربه تا برد فاصله داشتیم. 🤝');
}

const _soft = [
  'نزدیک بود! از دیواره کمانه بزن؛ زاویه‌ی بهتری به توپ می‌رسه. 🎯',
  'دیسکی رو انتخاب کن که مسیر مستقیم‌تری تا توپ داره. 👀',
  'پیش‌نمایش مسیر رو دنبال کن؛ نقطه‌ها نشون می‌دن دیسک کجا می‌ره.',
  'گاهی یک ضربه‌ی کوتاه برای بستن مسیر حریف بهترین حرکته. 🛡',
];

/// coach.ts: tip after a shot that did not touch the ball
String? coachMiss(double power, int misses) {
  if (power > .92) return 'قدرت خیلی زیاد بود؛ با کشیدن کمتر ضربه کنترل‌شده‌تر می‌شه. 💡';
  if (power < .18) return 'ضربه خیلی آروم بود؛ کمی بیشتر بکش تا به توپ برسی. 💪';
  if (misses % 2 == 1) return _soft[_rnd.nextInt(_soft.length)];
  return null;
}

class OracleMsg {
  final int id;
  final String text, mood;
  final List<String> actions;
  OracleMsg(this.text, this.mood, [this.actions = const []]) : id = DateTime.now().microsecondsSinceEpoch;
}

/// Navigation hooks the shell provides.
class OracleActions {
  final void Function(String tab) goTab;
  final void Function(String entry, String? quick) openOnline;
  final VoidCallback openSettings, openTeam;
  const OracleActions({required this.goTab, required this.openOnline, required this.openSettings, required this.openTeam});
}

Future<List<Rec>> loadChallenges() async => recs(await rpc('get_daily_challenges'));

class Oracle extends ChangeNotifier {
  Oracle._();
  static final Oracle i = Oracle._();
  OracleActions? actions;
  String scene = 'ui';
  OracleMsg? msg, coachMsg;
  String mood = 'idle';
  bool sleeping = false;
  final Set<String> quiet = {};
  final Map<String, int> _last = {};
  Timer? _hide, _coachT, _idle;
  RealtimeChannel? _ch;
  String? _chFor;
  Set<String> _completed = {};
  bool _primed = false;

  bool get enabled => Store.i.p.oracle;

  void init() {
    Auth.i.addListener(_onAuth);
    poke();
  }

  void say(String text, [String m = 'content', List<String> acts = const []]) {
    sleeping = false;
    mood = m;
    msg = OracleMsg(text, m, acts);
    _hide?.cancel();
    _hide = Timer(Duration(milliseconds: math.min(14000, 4500 + text.length * 55)), () {
      msg = null;
      mood = 'idle';
      notifyListeners();
    });
    notifyListeners();
  }

  void coach(String text, [String m = 'idea']) {
    if (!enabled) return;
    coachMsg = OracleMsg(text, m);
    _coachT?.cancel();
    _coachT = Timer(const Duration(milliseconds: 3600), () {
      coachMsg = null;
      notifyListeners();
    });
    notifyListeners();
  }

  bool bubbleVisible = false;
  void announce(String text, String m, [List<String> acts = const []]) => bubbleVisible ? say(text, m, acts) : coach(text, m);

  static const _gap = {'goal': 3000, 'reward': 2500, 'levelup': 1000, 'purchase': 2000, 'nogems': 15000, 'error': 20000, 'search': 5000, 'challengeDone': 4000, 'message': 8000, 'follow': 5000, 'tourReady': 10000};

  void react(String ev, [String? detail]) {
    if (!enabled) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_last[ev] ?? 0) < (_gap[ev] ?? 3000)) return;
    _last[ev] = now;
    if (ev == 'message' && quiet.contains('chat')) return;
    switch (ev) {
      case 'goal':
        coach(['گووووول! 🔥', 'چه ضربه‌ای! 😄', 'تور دروازه لرزید! ⚡'][_rnd.nextInt(3)], _rnd.nextDouble() < .5 ? 'excited' : 'laugh');
      case 'reward':
        announce(detail != null ? 'جایزه رسید: $detail 🎁' : 'جایزه‌ات رسید! 🎁', 'joy');
      case 'levelup':
        announce(detail != null ? 'سطح $detail! داری قوی‌تر می‌شی کاپیتان 🚀' : 'سطح جدید! 🚀', 'spin');
      case 'purchase':
        announce('مبارکت باشه! با این یکی حسابی می‌درخشی ✨', 'happy');
      case 'nogems':
        announce('الماس کافی نداری 🤔 چالش‌های روزانه (تا ۵)، جایزه‌ی فصل (تا ۳۰) و قهرمانی تورنمنت (تا ۳۰) الماس می‌دن.', 'confused', ['challenges', 'tours']);
      case 'error':
        announce('اوه! ${detail ?? 'یه مشکلی پیش اومد'} — نگران نباش، دوباره امتحان می‌کنیم.', 'alert');
      case 'search':
        coach('دارم حریف پیدا می‌کنم… 🔭', 'spin');
      case 'challengeDone':
        announce('چالش «${detail ?? ''}» کامل شد! جایزه‌ات رو بگیر 🎉', 'excited', ['claim']);
      case 'message':
        announce(detail != null ? 'پیام جدید از $detail 💬' : 'پیام جدید داری 💬', 'curious', ['messages']);
      case 'follow':
        announce(detail != null ? '$detail دنبالت کرد! 👀' : 'یک دنبال‌کننده‌ی جدید داری 👀', 'curious');
      case 'tourReady':
        announce('مسابقه‌ی تورنمنتت آماده‌ست! ⚠️ زود وارد شو.', 'alert', ['tours']);
    }
  }

  /// shell toast bridge (App.tsx ShellInner.toast)
  void onToast(String m, String k) {
    if (k == 'err') {
      if (m.contains('الماس')) {
        react('nogems');
      } else {
        react('error', m);
      }
    } else if (k == 'ok') {
      if (RegExp('باز شد|خرید').hasMatch(m)) {
        react('purchase');
      } else if (RegExp('الماس|XP|سکه|جایزه').hasMatch(m)) {
        react('reward', m);
      }
    }
  }

  void dismiss() {
    msg = null;
    mood = 'idle';
    notifyListeners();
  }

  void setScene(String s) {
    scene = s;
    notifyListeners();
  }

  void poke() {
    _idle?.cancel();
    if (sleeping) {
      sleeping = false;
      mood = 'idle';
      notifyListeners();
    }
    _idle = Timer(const Duration(seconds: 45), () {
      if (bubbleVisible) {
        sleeping = true;
        msg = null;
        mood = 'sleep';
        notifyListeners();
      }
    });
  }

  bool _greeted = false;
  void greet() {
    if (_greeted || !enabled) return;
    _greeted = true;
    Timer(const Duration(milliseconds: 2600), () {
      final p = Store.i.p;
      if (!p.oracleTour) {
        Store.i.set((q) => q.oracleTour = true);
        say('سلام کاپیتان! 👋 من اوراکل‌ام، دستیار کهکشانی NEXORA. از دروازه‌ها وارد هر دنیا شو؛ «بازی» برای مسابقه، «فروشگاه» برای خرید و «گفتگو» برای دوستانت. هر وقت سؤالی داشتی روی من بزن! 💙', 'wave', ['quick']);
        return;
      }
      final h = DateTime.now().hour;
      final g = h >= 5 && h < 12 ? 'صبح بخیر' : h < 17 ? 'روز بخیر' : h < 21 ? 'عصر بخیر' : 'شب بخیر';
      final name = Auth.i.profile?.s('username') ?? p.name;
      say('$g $name! 👋 آماده‌ی یک مسابقه‌ی کهکشانی هستی؟', h >= 5 && h < 12 ? 'hello' : 'wave', ['quick', 'challenges']);
    });
  }

  void _onAuth() {
    final uid = Auth.i.uid;
    if (uid == _chFor) return;
    _chFor = uid;
    if (_ch != null) sb.removeChannel(_ch!);
    _ch = null;
    if (uid == null) return;
    _primed = false;
    Future<void> check() async {
      try {
        final list = await loadChallenges();
        final now = {for (final c in list) if (c.i('progress') >= c.i('target') && !c.b('claimed')) c.s('def_id')};
        if (_primed) {
          for (final c in list) {
            if (now.contains(c.s('def_id')) && !_completed.contains(c.s('def_id'))) react('challengeDone', c.s('title_fa'));
          }
        }
        _completed = now;
        _primed = true;
      } catch (_) {}
    }

    check();
    _ch = sb
        .channel('oracle:$uid')
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'user_challenges',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
            callback: (_) => check())
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'follows',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'followee', value: uid),
            callback: (pl) async {
              final d = await sb.from('profiles').select('username').eq('id', pl.newRecord['follower']).maybeSingle();
              react('follow', d?['username']?.toString());
            })
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            callback: (pl) async {
              final m = pl.newRecord;
              if (m['sender'] == uid) return;
              final d = await sb.from('profiles').select('username').eq('id', m['sender']).maybeSingle();
              react('message', d?['username']?.toString());
            })
        .subscribe();
  }

  // ---------- smart actions ----------
  Future<OracleMsg?> runAction(String id) async {
    final a = actions;
    Future<bool> needOnline() async {
      if (Auth.i.uid != null) return true;
      try {
        return await Auth.i.ensure() != null;
      } catch (_) {
        return false;
      }
    }

    final p = Store.i.p;
    switch (id) {
      case 'quick':
        a?.openOnline('hub', '1v1');
        return OracleMsg('دارم یک حریف هم‌سطح برات پیدا می‌کنم… 🔭', 'spin');
      case 'shop':
        a?.goTab('shop');
        return OracleMsg('فروشگاه باز شد! 🛍', 'happy');
      case 'tours':
        a?.openOnline('tours', null);
        return OracleMsg('بریم سراغ تورنمنت‌ها! 🏆', 'excited');
      case 'clubs':
      case 'messages':
        a?.goTab('social');
        return OracleMsg(id == 'clubs' ? 'باشگاه‌ها در تب «گفتگو» هستن 🛡' : 'پیام‌هات این‌جاست 💬', 'curious');
      case 'online':
        a?.openOnline('hub', null);
        return OracleMsg('به بخش آنلاین خوش اومدی! 🌐', 'wave');
      case 'arena':
        a?.openOnline('arena', null);
        return OracleMsg('آرنا منتظرته! ⚔️', 'excited');
      case 'leagues':
        a?.openOnline('leagues', null);
        return OracleMsg('لیگ‌ها و جایزه‌های فصل 🥇', 'present');
      case 'team':
        a?.openTeam();
        return OracleMsg('تیم و دیسک‌هات این‌جاست ⚽', 'present');
      case 'settings':
        a?.openSettings();
        return OracleMsg('تنظیمات باز شد ⚙️', 'neutral');
      case 'challenges':
        if (!await needOnline()) return OracleMsg('برای چالش‌ها باید آنلاین باشی 📶', 'alert');
        try {
          final list = await loadChallenges();
          final lines = list.map((c) =>
              '${c.b('claimed') ? '✅' : c.i('progress') >= c.i('target') ? '🎁' : '▫️'} ${c.s('title_fa')} — ${fa(math.min(c.i('progress'), c.i('target')))}/${fa(c.i('target'))} (💎${fa(c.i('reward_gems'))})');
          return OracleMsg('چالش‌های امروز:\n${lines.join('\n')}', 'present', list.any((c) => c.i('progress') >= c.i('target') && !c.b('claimed')) ? ['claim'] : const []);
        } catch (e) {
          return OracleMsg(errFa(e), 'alert');
        }
      case 'claim':
        if (!await needOnline()) return OracleMsg('برای گرفتن جایزه باید آنلاین باشی 📶', 'alert');
        var gems = 0, xp = 0, n = 0;
        try {
          for (final c in await loadChallenges()) {
            if (c.i('progress') >= c.i('target') && !c.b('claimed')) {
              try {
                final r = Rec.of(await rpc('claim_challenge', {'p_def': c.s('def_id')}));
                gems += r.i('gems');
                xp += r.i('xp');
                n++;
              } catch (_) {}
            }
          }
        } catch (_) {}
        var season = 0;
        try {
          season = Rec.of(await rpc('claim_season_reward')).i('gems');
          gems += season;
        } catch (_) {}
        if (n == 0 && season == 0) return OracleMsg('فعلاً جایزه‌ی آماده‌ای نداری. چالش‌های امروز رو کامل کن تا الماس بگیری! 💪', 'calm', ['challenges']);
        sfx(Snd.win);
        buzz('success');
        Auth.i.refreshProfile();
        return OracleMsg(
            'گرفتمشون! 🎉 ${n > 0 ? '${fa(n)} چالش' : ''}${n > 0 && season > 0 ? ' و ' : ''}${season > 0 ? 'جایزه‌ی فصل' : ''}: +${fa(gems)} الماس${xp > 0 ? ' · +${fa(xp)} XP' : ''}', 'joy');
      case 'disc':
        final cat = Discs.i.catalog.values.toList();
        if (cat.isEmpty) return OracleMsg('کاتالوگ دیسک‌ها هنوز بارگذاری نشده؛ یک لحظه بعد دوباره بپرس.', 'confused');
        final gems = Auth.i.profile?.i('gems') ?? 0;
        double score(DiscRow d) => d.power + d.accuracy;
        final afford = cat.where((d) => !Discs.i.has(d.id) && d.priceGems > 0 && d.priceGems <= gems).toList()
          ..sort((a, b) => score(b) != score(a) ? score(b).compareTo(score(a)) : a.priceGems.compareTo(b.priceGems));
        final owned = cat.where((d) => Discs.i.has(d.id)).toList()..sort((a, b) => score(b).compareTo(score(a)));
        final next = cat.where((d) => !Discs.i.has(d.id) && d.priceGems > gems).toList()
          ..sort((a, b) => a.priceGems != b.priceGems ? a.priceGems.compareTo(b.priceGems) : score(b).compareTo(score(a)));
        final lines = <String>[];
        if (afford.isNotEmpty) {
          final d = afford.first;
          lines.add('با ${fa(gems)} الماست بهترین انتخاب «${d.name}» است: قدرت ${fa(d.power)}، دقت ${fa(d.accuracy)} به قیمت 💎${fa(d.priceGems)}.');
        }
        if (owned.isNotEmpty) {
          final d = owned.first;
          lines.add('بهترین دیسکی که الان داری «${d.name}» است (قدرت ${fa(d.power)}، دقت ${fa(d.accuracy)})${p.team != d.id ? ' — مجهزش کن!' : ' و فعاله ✅'}');
        }
        if (afford.isEmpty && next.isNotEmpty) {
          final d = next.first;
          lines.add('هدف بعدی: «${d.name}» با 💎${fa(d.priceGems)}؛ ${fa(d.priceGems - gems)} الماس دیگه لازم داری.');
        }
        return OracleMsg(lines.isEmpty ? 'همه‌ی دیسک‌ها رو داری، اسطوره! 🤯' : lines.join('\n'), 'idea', ['team', 'shop']);
      case 'stats':
        final pr = Auth.i.profile;
        if (pr != null) {
          final pl = pr.i('wins') + pr.i('losses') + pr.i('draws');
          final wr = pl > 0 ? (pr.i('wins') / pl * 100).round() : 0;
          final lp = levelProgress(pr.i('xp'));
          String nxt = '';
          try {
            final lg = recs(await sb.from('leagues').select().order('min_rating'));
            final nx = lg.where((l) => l.i('min_rating') > pr.i('rating')).firstOrNull;
            if (nx != null) nxt = ' — ${fa(nx.i('min_rating') - pr.i('rating'))} تا ${nx.s('name_fa')}';
          } catch (_) {}
          return OracleMsg(
              '📊 ${pr.s('username')}\n• سطح ${fa(lp.level)} — ${fa(lp.need - lp.cur)} XP تا سطح بعد\n• ${fa(pl)} بازی آنلاین، درصد برد ${fa(wr)}٪\n• برد پیاپی ${fa(pr.i('win_streak'))} (رکورد ${fa(pr.i('best_streak'))})\n• امتیاز ${fa(pr.i('rating'))}$nxt\n• الماس ${fa(pr.i('gems'))}',
              'present',
              ['disc', 'challenges']);
        }
        final lv = level(p.xp);
        final wr = p.played > 0 ? (p.wins / p.played * 100).round() : 0;
        return OracleMsg('📊 آمار آفلاین\n• سطح ${fa(lv.level)}\n• ${fa(p.played)} بازی، درصد برد ${fa(wr)}٪\n• بهترین برد پیاپی ${fa(p.bestStreak)}\nبرای آمار آنلاین وارد بخش آنلاین شو.', 'present', ['online']);
    }
    return null;
  }
}

/// Coach toast + floating bubble, drawn above the app (Shell decides when the bubble is visible).
class OracleLayer extends StatelessWidget {
  final bool bubble;
  final VoidCallback onOpenPanel;
  const OracleLayer({super.key, required this.bubble, required this.onOpenPanel});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Oracle.i,
      builder: (context, _) {
        final o = Oracle.i;
        o.bubbleVisible = bubble && o.enabled && o.scene == 'ui';
        final ins = MediaQuery.paddingOf(context);
        return Stack(children: [
          if (o.coachMsg != null && o.enabled)
            Positioned(
              key: ValueKey(o.coachMsg!.id),
              left: 12,
              right: 12,
              top: o.scene == 'match' ? ins.top + 104 : ins.top + 70,
              child: IgnorePointer(
                child: Enter(
                  child: Row(textDirection: TextDirection.rtl, children: [
                    Img(oracleImg(o.coachMsg!.mood), w: 54, h: 54),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xeb0e1e50), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x665ce1ff))),
                        child: T(o.coachMsg!.text, size: 12, color: const Color(0xffe6f4ff)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          if (o.bubbleVisible && o.msg != null)
            Positioned(
              key: ValueKey(o.msg!.id),
              right: 12,
              left: 40,
              bottom: ins.bottom + 96,
              child: Enter(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xf00e1e50), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0x805ce1ff)), boxShadow: glow(C.cyan, 14, .3)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Row(textDirection: TextDirection.rtl, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GestureDetector(onTap: onOpenPanel, child: Img(oracleImg(o.msg!.mood), w: 52, h: 52)),
                      const SizedBox(width: 8),
                      Expanded(child: T(o.msg!.text, size: 12, height: 1.6, color: const Color(0xffe6f4ff))),
                      GestureDetector(
                          onTap: () => o.dismiss(),
                          child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 18, color: C.dim))),
                    ]),
                    if (o.msg!.actions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: [
                          for (final a in o.msg!.actions)
                            Press(
                              onTap: () async {
                                o.dismiss();
                                final r = await o.runAction(a);
                                if (r != null) o.say(r.text, r.mood, r.actions);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: const Color(0x334fe3ff), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.cyan.withValues(alpha: .6))),
                                child: T(kActionLabel[a] ?? a, size: 11),
                              ),
                            ),
                        ]),
                      ),
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

/// Full-screen Oracle chat (answers from the offline KB + runs smart actions).
class OraclePanel extends StatefulWidget {
  const OraclePanel({super.key});
  @override
  State<OraclePanel> createState() => _OraclePanelState();
}

class _OraclePanelState extends State<OraclePanel> {
  final List<(bool, OracleMsg)> log = [(false, OracleMsg('سلام! من اوراکل‌ام 🤖 هر سؤالی درباره‌ی NEXORA داری بپرس، یا یکی از کارهای سریع رو انتخاب کن.', 'wave', kSuggestions))];
  final ctl = TextEditingController();
  final sc = ScrollController();
  bool busy = false;

  Future<void> ask(String text) async {
    final t = text.trim();
    if (t.isEmpty || busy) return;
    ctl.clear();
    setState(() => log.add((true, OracleMsg(t, 'idle'))));
    final (intent, action) = matchIntent(t);
    OracleMsg? r;
    if (action != null) {
      setState(() => busy = true);
      r = await Oracle.i.runAction(action);
      busy = false;
    } else if (intent != null) {
      r = OracleMsg(intent.answer, intent.mood, intent.actions);
    }
    r ??= OracleMsg('این یکی رو هنوز بلد نیستم 🤔 می‌تونی درباره‌ی شوت، الماس، دیسک‌ها، تورنمنت، آرنا، باشگاه یا تنظیمات بپرسی.', 'confused', kSuggestions.take(3).toList());
    if (!mounted) return;
    setState(() => log.add((false, r!)));
    _down();
  }

  Future<void> act(String a) async {
    setState(() {
      log.add((true, OracleMsg(kActionLabel[a] ?? a, 'idle')));
      busy = true;
    });
    final r = await Oracle.i.runAction(a);
    if (!mounted) return;
    setState(() {
      busy = false;
      if (r != null) log.add((false, r));
    });
    _down();
  }

  void _down() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (sc.hasClients) sc.animateTo(sc.position.maxScrollExtent, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: C.bg,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        const Space(theme: SpaceTheme.system, dim: .2),
        Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(8, ins.top + 6, 12, 0),
            child: Row(children: [
              IconBtn(menu('g_x'), onTap: () => Navigator.pop(context)),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [tHead('ORACLE CORE', size: 9, color: C.violet), tTitle('اوراکل', size: 20)]),
              const SizedBox(width: 8),
              FloatY(child: Img(oracleImg(busy ? 'spin' : 'hero'), w: 64, h: 64)),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: log.length + (busy ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= log.length) return const Padding(padding: EdgeInsets.all(12), child: Center(child: Spinner(size: 22)));
                final (me, m) = log[i];
                return Align(
                  alignment: me ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: me ? const Color(0x664fe3ff) : const Color(0xe60e1e50),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: me ? C.cyan.withValues(alpha: .5) : const Color(0x665ce1ff)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      T(m.text, size: 13, height: 1.6),
                      if (!me && m.actions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: [
                            for (final a in m.actions) Chip2(kActionLabel[a] ?? a, onTap: () => act(a), accent: C.violet),
                          ]),
                        ),
                    ]),
                  ),
                );
              },
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, reverse: true, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
              for (final q in kQuestionChips) Padding(padding: const EdgeInsets.only(left: 6), child: Chip2(q, onTap: () => ask(q))),
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, ins.bottom + 10),
            child: Row(children: [
              IconBtn(menu('ic_play'), onTap: () => ask(ctl.text)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: ctl,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: ts(size: 14, family: F.fa),
                  onSubmitted: ask,
                  decoration: InputDecoration(
                    hintText: 'از اوراکل بپرس…',
                    hintTextDirection: TextDirection.rtl,
                    hintStyle: ts(size: 13, color: C.dim, family: F.fa),
                    filled: true,
                    fillColor: const Color(0xcc0a1030),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: C.line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: C.line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: C.cyan)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ]),
    );
  }
}
