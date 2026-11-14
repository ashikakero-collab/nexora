// Ports of src/online/OnlineResult.tsx, Arena.tsx, Ranks.tsx, Challenges.tsx and Tournaments.tsx.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../oracle/oracle.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'online_match.dart';
import 'ui.dart';

Widget _page(BuildContext context, String title, String en, VoidCallback onBack, List<Widget> children, {Future<void> Function()? onRefresh, Color accent = C.cyan}) {
  final list = ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24), children: [Header(title: title, en: en, onBack: onBack), ...children]);
  return Scaffold(
    backgroundColor: C.bg,
    body: Stack(children: [const Space(theme: SpaceTheme.base, dim: .15), onRefresh != null ? RefreshIndicator(onRefresh: onRefresh, color: accent, child: list) : list]),
  );
}

// =============================================================== result
class OnlineResultScreen extends StatefulWidget {
  final OnlineOutcome o;
  final Rec? before;
  final VoidCallback onLobby, onLeave;
  const OnlineResultScreen({super.key, required this.o, required this.before, required this.onLobby, required this.onLeave});
  @override
  State<OnlineResultScreen> createState() => _OnlineResultScreenState();
}

class _OnlineResultScreenState extends State<OnlineResultScreen> {
  Rec? after;
  @override
  void initState() {
    super.initState();
    final w = widget.o.winner, my = widget.o.myTeam;
    if (my != null) {
      sfx(w == my ? Snd.win : w == -1 ? Snd.ready : Snd.lose);
      final (mood, text) = resultLine(w == my ? 'victory' : w == -1 ? 'draw' : 'defeat');
      Timer(const Duration(milliseconds: 900), () => Oracle.i.coach(text, mood));
    }
    _load(0);
  }

  Future<void> _load(int n) async {
    final p = await Auth.i.refreshProfile();
    if (!mounted) return;
    final b = widget.before;
    if (p != null && (b == null || p.i('xp') != b.i('xp') || n >= 2)) {
      setState(() => after = p);
    } else if (n < 2) {
      Timer(const Duration(milliseconds: 1200), () => _load(n + 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.o, b = widget.before, a = after;
    final my = o.myTeam;
    final out = my == null ? 'draw' : o.winner == my ? 'victory' : o.winner == -1 ? 'draw' : 'defeat';
    final col = out == 'victory' ? C.gold : out == 'defeat' ? C.red : C.cyan;
    final dXp = a != null && b != null ? a.i('xp') - b.i('xp') : null;
    final dRating = a != null && b != null ? a.i('rating') - b.i('rating') : o.ratingDelta;
    final dArena = a != null && b != null ? a.i('arena_points') - b.i('arena_points') : null;
    final lvUp = a != null && b != null && a.i('level') > b.i('level') ? a.i('level') : null;
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        Space(theme: out == 'victory' ? SpaceTheme.win : out == 'defeat' ? SpaceTheme.lose : SpaceTheme.system),
        ListView(padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 12, 16, 32), children: [
          SizedBox(height: w * .5, child: Stack(alignment: Alignment.center, children: [Pulse(size: w * .4, color: col.withValues(alpha: .25)), Img(ui(my == null ? 'draw' : out), w: w * .8, h: w * .5)])),
          Panel(
            accent: col,
            glowOn: true,
            child: Row(children: [
              Expanded(child: Column(children: [Disc(discImg(o.teams[0].id), size: 54, ring: C.cyan), tBold(o.names[0], size: 12, lines: 1)])),
              tTitle('${o.score[0]} : ${o.score[1]}', size: 38, shadows: [Shadow(color: col, blurRadius: 14)]),
              Expanded(child: Column(children: [Disc(discImg(o.teams[1].id), size: 54, ring: C.red), tBold(o.names[1], size: 12, lines: 1)])),
            ]),
          ),
          const SizedBox(height: 12),
          Row(textDirection: TextDirection.rtl, children: [
            _stat('امتیاز', dRating == null ? '—' : '${dRating >= 0 ? '+' : ''}${fa(dRating)}', dRating == null || dRating >= 0 ? C.green : C.red),
            _stat('XP', dXp == null ? '…' : '+${fa(dXp)}', C.cyan),
            if (dArena != null && dArena != 0) _stat('آرنا', '${dArena >= 0 ? '+' : ''}${fa(dArena)}', C.violet),
          ]),
          if (!o.reported) const Padding(padding: EdgeInsets.only(top: 8), child: T('نتیجه هنوز روی سرور ثبت نشده است', size: 11, color: C.orange, align: TextAlign.center)),
          if (!o.ranked) const Padding(padding: EdgeInsets.only(top: 8), child: T('مسابقه‌ی دوستانه · روی امتیاز اثری ندارد', size: 11, color: C.dim, align: TextAlign.center)),
          if (lvUp != null)
            Panel(margin: const EdgeInsets.only(top: 12), accent: C.violet, glowOn: true, child: Row(textDirection: TextDirection.rtl, children: [Img(ui2('x_crown'), w: 44, h: 44), const SizedBox(width: 8), tTitle('سطح ${fa(lvUp)}!', size: 18, color: const Color(0xffd6b8ff))])),
          if (a != null) ...[
            const SizedBox(height: 12),
            Bar(v: levelProgress(a.i('xp')).frac, color: C.cyan, color2: C.violet, h: 10),
            T('سطح ${fa(levelProgress(a.i('xp')).level)} · ${fa(levelProgress(a.i('xp')).cur)} / ${fa(levelProgress(a.i('xp')).need)} XP', size: 10, color: C.dim, align: TextAlign.center),
          ],
          const SizedBox(height: 18),
          Btn('بازگشت به لابی', colors: G.primary, onTap: widget.onLobby),
          const SizedBox(height: 10),
          Btn('خروج از اتاق', small: true, colors: G.dark, onTap: widget.onLeave),
        ]),
      ]),
    );
  }

  Widget _stat(String l, String v, Color c) => Expanded(
      child: Padding(padding: const EdgeInsets.all(4), child: Panel(accent: c, padding: const EdgeInsets.symmetric(vertical: 10), child: Column(children: [tTitle(v, size: 18, color: c), T(l, size: 11, color: C.dim)]))));
}

// =============================================================== arena
class ArenaScreen extends StatefulWidget {
  final VoidCallback onBack;
  final void Function(Rec room) onRoom;
  const ArenaScreen({super.key, required this.onBack, required this.onRoom});
  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen> {
  List<Rec>? top;
  String? busy;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await sb.from('profiles').select('id, username, avatar, avatar_url, equipped_disc, level, rating, league, arena_points').gt('arena_points', 0).order('arena_points', ascending: false).limit(50);
      if (mounted) setState(() => top = recs(d));
    } catch (_) {
      if (mounted) setState(() => top = []);
    }
  }

  Future<void> go(String m) async {
    if (busy != null) return;
    setState(() => busy = m);
    Oracle.i.react('search');
    try {
      final r = Rec.of(await rpc('quick_match', {'p_mode': m, 'p_kind': 'arena'}));
      sfx(Snd.join);
      widget.onRoom(r);
    } catch (e) {
      toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pr = Auth.i.profile;
    return _page(context, 'آرنا', 'ARENA LADDER', widget.onBack, onRefresh: load, accent: C.violet, [
      Panel(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        accent: C.violet,
        glowOn: true,
        child: Column(children: [
          Img(ui2('x_crown'), w: 80, h: 80),
          tTitle(fa(pr?.i('arena_points') ?? 0), size: 30, color: const Color(0xffd6b8ff)),
          const T('امتیاز آرنا · هر برد ۳۰+ و برای برد پیاپی تا ۲۵+ اضافه، هر باخت ۲۰−', size: 11, color: C.dim, align: TextAlign.center),
          const SizedBox(height: 12),
          Row(textDirection: TextDirection.rtl, children: [
            for (final m in ['1v1', '2v2', '3v3']) ...[
              if (m != '1v1') const SizedBox(width: 8),
              Expanded(child: Btn(busy == m ? '…' : m.toUpperCase(), small: true, colors: G.violet, disabled: busy != null, onTap: () => go(m))),
            ],
          ]),
        ]),
      ),
      const TitleBar('برترین‌های آرنا', en: 'TOP 50', accent: C.violet),
      if (top == null)
        const LoadingList()
      else if (top!.isEmpty)
        const EmptyState('هنوز کسی در آرنا امتیاز نگرفته؛ اولین نفر باش!')
      else
        for (var i = 0; i < top!.length; i++)
          ListRow(
            leading: SizedBox(width: 28, child: tTitle(fa(i + 1), size: 14, color: i < 3 ? C.gold : C.dim)),
            title: top![i].s('username'),
            sub: 'سطح ${fa(top![i].i('level'))} · امتیاز ${fa(top![i].i('rating'))}',
            right: tTitle(fa(top![i].i('arena_points')), size: 15, color: const Color(0xffd6b8ff)),
          ),
    ]);
  }
}

// =============================================================== ranks + leagues + season
class RanksScreen extends StatefulWidget {
  final VoidCallback onBack;
  final String tab;
  const RanksScreen({super.key, required this.onBack, this.tab = 'top'});
  @override
  State<RanksScreen> createState() => _RanksScreenState();
}

class _RanksScreenState extends State<RanksScreen> {
  late String tab = widget.tab;
  List<Rec>? top, ls;
  Rec? mine, season;
  Map<String, int> rewards = {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final uid = Auth.i.uid;
    try {
      final r = await Future.wait([
        sb.from('leaderboard').select().order('rank').limit(100),
        uid != null ? sb.from('leaderboard').select().eq('id', uid).maybeSingle() : Future.value(null),
        leagues(),
      ]);
      Rec? s;
      try {
        s = Rec.of(await rpc('current_season'));
      } catch (_) {}
      Map<String, int> rw = {};
      try {
        for (final x in recs(await sb.from('season_rewards').select())) {
          rw[x.s('league')] = x.i('gems');
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        top = recs(r[0]);
        mine = r[1] == null ? null : Rec.of(r[1]);
        ls = r[2] as List<Rec>;
        season = s;
        rewards = rw;
      });
    } catch (e) {
      if (mounted) setState(() => top = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pr = Auth.i.profile;
    final ends = season != null ? DateTime.tryParse(season!.s('ends_at')) : null;
    final left = ends?.difference(DateTime.now());
    return _page(context, 'رده‌بندی', 'RANKS · LEAGUES · SEASON', widget.onBack, onRefresh: load, accent: C.gold, [
      Tabs2<String>(items: const [('top', 'برترین‌ها'), ('leagues', 'لیگ‌ها و فصل')], value: tab, onChange: (v) => setState(() => tab = v)),
      if (tab == 'top') ...[
        if (mine != null)
          ListRow(
              leading: SizedBox(width: 36, child: tTitle('#${fa(mine!.i('rank'))}', size: 13, color: C.cyan)),
              title: '${mine!.s('username')} (تو)',
              sub: 'سطح ${fa(mine!.i('level'))}',
              right: tTitle(fa(mine!.i('rating')), size: 15, color: C.gold)),
        if (top == null)
          const LoadingList()
        else
          for (final r in top!)
            ListRow(
              leading: SizedBox(width: 36, child: tTitle(fa(r.i('rank')), size: 14, color: r.i('rank') <= 3 ? C.gold : C.dim)),
              icon: ui(kLeagueImg[r.s('league')] ?? 'medal_bronze'),
              title: r.s('username'),
              sub: 'سطح ${fa(r.i('level'))} · ${fa(r.i('wins'))} برد',
              right: tTitle(fa(r.i('rating')), size: 15, color: C.gold),
            ),
      ] else ...[
        if (season != null)
          Panel(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            accent: C.gold,
            child: Column(children: [
              tTitle(season!.s('name', 'فصل'), size: 18),
              T(left == null ? '' : left.isNegative ? 'فصل تمام شده' : '${fa(left.inDays)} روز و ${fa(left.inHours % 24)} ساعت تا پایان فصل', size: 12, color: C.dim),
              const SizedBox(height: 10),
              Btn(busy ? '…' : 'دریافت جایزه‌ی فصل', small: true, colors: G.gold, onTap: () async {
                setState(() => busy = true);
                try {
                  final r = Rec.of(await rpc('claim_season_reward'));
                  toast('+${fa(r.i('gems'))} الماس', 'ok');
                  Auth.i.refreshProfile();
                } catch (e) {
                  toast(errFa(e), 'err');
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              }),
            ]),
          ),
        const SizedBox(height: 8),
        for (final l in ls ?? const <Rec>[])
          ListRow(
            icon: ui(kLeagueImg[l.s('id')] ?? 'medal_bronze'),
            title: 'لیگ ${l.s('name_fa')}',
            sub: 'از امتیاز ${fa(l.i('min_rating'))}${rewards[l.s('id')] != null ? ' · جایزه‌ی فصل 💎${fa(rewards[l.s('id')]!)}' : ''}',
            right: pr != null && leagueFor(ls!, pr.i('rating'))?.s('id') == l.s('id') ? const Badge2('لیگ تو', color: C.gold) : null,
          ),
      ],
    ]);
  }
}

// =============================================================== challenges
class ChallengesScreen extends StatefulWidget {
  final VoidCallback onBack;
  const ChallengesScreen({super.key, required this.onBack});
  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  List<Rec>? list;
  String? err;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final l = await loadChallenges();
      if (mounted) setState(() => list = l);
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  @override
  Widget build(BuildContext context) => _page(context, 'چالش‌های روزانه', 'DAILY CHALLENGES', widget.onBack, onRefresh: load, accent: C.green, [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: T('هر روز ساعت ۰۰:۰۰ تهران ۴ چالش جدید؛ پیشرفت خودکار از مسابقه‌های آنلاین حساب می‌شود.', size: 11, color: C.dim, align: TextAlign.right)),
        const SizedBox(height: 8),
        if (err != null)
          ErrorState(err!, onRetry: load)
        else if (list == null)
          const LoadingList()
        else
          for (final c in list!)
            Panel(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              accent: c.i('progress') >= c.i('target') && !c.b('claimed') ? C.green : Colors.transparent,
              glowOn: c.i('progress') >= c.i('target') && !c.b('claimed'),
              child: Row(textDirection: TextDirection.rtl, children: [
                Img(c.b('claimed') ? kit('star') : kit('calendar'), w: 44, h: 44),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    tBold(c.s('title_fa'), size: 14),
                    if (c.str('desc_fa') != null) T(c.s('desc_fa'), size: 11, color: C.dim),
                    const SizedBox(height: 4),
                    Bar(v: c.i('target') > 0 ? c.i('progress') / c.i('target') : 0, h: 6, color: c.b('claimed') ? C.green : C.cyan),
                    T('${fa(c.i('progress').clamp(0, c.i('target')))}/${fa(c.i('target'))} · 💎${fa(c.i('reward_gems'))} · ${fa(c.i('reward_xp'))} XP', size: 10, color: C.dim),
                  ]),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: c.b('claimed')
                      ? const T('✓ گرفتی', size: 11, color: C.green, align: TextAlign.center)
                      : c.i('progress') >= c.i('target')
                          ? Btn('دریافت', small: true, colors: G.gold, onTap: () async {
                              try {
                                final r = Rec.of(await rpc('claim_challenge', {'p_def': c.s('def_id')}));
                                toast('+${fa(r.i('gems'))} الماس · +${fa(r.i('xp'))} XP', 'ok');
                                sfx(Snd.win);
                                Auth.i.refreshProfile();
                                load();
                              } catch (e) {
                                toast(errFa(e), 'err');
                              }
                            })
                          : const SizedBox.shrink(),
                ),
              ]),
            ),
      ]);
}

// =============================================================== tournaments
const kFormatFa = {'single_elim': 'حذفی تک', 'double_elim': 'حذفی دوگانه', 'round_robin': 'دوره‌ای', 'swiss': 'سوئیسی', 'league': 'لیگ'};
const kTourStatus = {'registration': ('ثبت‌نام', C.green), 'running': ('در جریان', C.orange), 'finished': ('پایان‌یافته', C.dim)};
bool isElim(String f) => f == 'single_elim' || f == 'double_elim';

class ToursScreen extends StatefulWidget {
  final VoidCallback onBack;
  final void Function(String id) onOpen;
  const ToursScreen({super.key, required this.onBack, required this.onOpen});
  @override
  State<ToursScreen> createState() => _ToursScreenState();
}

class _ToursScreenState extends State<ToursScreen> {
  String tab = 'registration';
  List<Rec>? list;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => list = null);
    try {
      final d = await sb.from('tournaments').select('*, entries:tournament_entries(count)').eq('status', tab).order('created_at', ascending: false).limit(50);
      if (mounted) setState(() => list = recs(d));
    } catch (e) {
      if (mounted) setState(() => list = []);
    }
  }

  @override
  Widget build(BuildContext context) => _page(context, 'تورنمنت‌ها', 'TOURNAMENTS', widget.onBack, onRefresh: load, accent: C.orange, [
        Tabs2<String>(
            items: const [('registration', 'ثبت‌نام'), ('running', 'در جریان'), ('finished', 'پایان‌یافته')],
            value: tab,
            onChange: (v) {
              tab = v;
              load();
            }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Btn('ساخت تورنمنت', small: true, colors: G.gold, onTap: () => showSheet(context, title: 'ساخت تورنمنت', en: 'CREATE TOURNAMENT', accent: C.orange, child: (ctx) => _CreateTour(onCreated: (id) {
                    Navigator.pop(ctx);
                    widget.onOpen(id);
                  }))),
        ),
        if (list == null)
          const LoadingList()
        else if (list!.isEmpty)
          const EmptyState('تورنمنتی در این بخش نیست')
        else
          for (final t in list!)
            ListRow(
              icon: ui2('x_trophy'),
              title: t.s('name'),
              sub: '${kFormatFa[t.s('format')] ?? t.s('format')} · ${t.s('mode').toUpperCase()} · ${fa(t.list('entries').firstOrNull?.i('count') ?? 0)}/${fa(t.i('max_entries'))} · 💎${fa(t.i('prize_gems'))}',
              right: Badge2(kTourStatus[t.s('status')]?.$1 ?? '', color: kTourStatus[t.s('status')]?.$2 ?? C.dim, live: t.s('status') == 'running'),
              onTap: () => widget.onOpen(t.s('id')),
            ),
      ]);
}

class _CreateTour extends StatefulWidget {
  final void Function(String id) onCreated;
  const _CreateTour({required this.onCreated});
  @override
  State<_CreateTour> createState() => _CreateTourState();
}

class _CreateTourState extends State<_CreateTour> {
  final name = TextEditingController();
  String format = 'single_elim', mode = '1v1';
  int max = 8, rounds = 3, gems = 0, minLv = 1;
  bool busy = false;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Field2(name, label: 'نام تورنمنت', maxLength: 40),
        _l('فرمت'),
        Wrap(textDirection: TextDirection.rtl, runSpacing: 6, children: [for (final f in kFormatFa.entries) Chip2(f.value, on: format == f.key, onTap: () => setState(() => format = f.key), accent: C.violet)]),
        _l('حالت'),
        Segment<String>(value: mode, onChange: (v) => setState(() => mode = v), items: const [('1v1', '۱ به ۱'), ('2v2', '۲ به ۲'), ('3v3', '۳ به ۳')]),
        _l('ظرفیت'),
        Segment<int>(value: max, onChange: (v) => setState(() => max = v), items: const [(4, '۴'), (8, '۸'), (16, '۱۶'), (32, '۳۲')], accent: C.green),
        if (format == 'league' || format == 'swiss') ...[
          _l(format == 'league' ? 'تعداد دور رفت و برگشت' : 'تعداد دورها'),
          Segment<int>(
              value: rounds,
              onChange: (v) => setState(() => rounds = v),
              items: format == 'league' ? const [(1, 'یک'), (2, 'دو'), (3, 'سه')] : const [(3, '۳'), (4, '۴'), (5, '۵'), (6, '۶')],
              accent: C.violet),
        ],
        _l('جایزه‌ی الماس قهرمان'),
        Segment<int>(value: gems, onChange: (v) => setState(() => gems = v), items: const [(0, '۰'), (10, '۱۰'), (20, '۲۰'), (30, '۳۰')], accent: C.gold),
        _l('حداقل سطح'),
        Segment<int>(value: minLv, onChange: (v) => setState(() => minLv = v), items: const [(1, '۱'), (3, '۳'), (5, '۵'), (10, '۱۰')]),
        const SizedBox(height: 18),
        Btn(busy ? '…' : 'ساخت', colors: G.gold, disabled: busy, onTap: () async {
          if (name.text.trim().isEmpty) return toast('عنوان لازم است', 'err');
          if (format == 'league' || format == 'swiss') {
            if (format == 'league' && rounds > 3) rounds = 1;
            if (format == 'swiss' && rounds < 3) rounds = 3;
          }
          setState(() => busy = true);
          try {
            final t = Rec.of(await rpc('create_tournament', {
              'p_name': name.text.trim(), 'p_format': format, 'p_mode': mode, 'p_max': max,
              'p_rounds': format == 'league' || format == 'swiss' ? rounds : null, 'p_prize_gems': gems, 'p_starts': null, 'p_min_level': minLv,
            }));
            toast('تورنمنت ساخته شد', 'ok');
            widget.onCreated(t.s('id'));
          } catch (e) {
            toast(errFa(e), 'err');
          } finally {
            if (mounted) setState(() => busy = false);
          }
        }),
      ]);
}

Widget _l(String s) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: tBold(s, size: 13, color: C.dim, align: TextAlign.right));

class TourScreen extends StatefulWidget {
  final String id;
  final VoidCallback onBack;
  final void Function(Rec room) onRoom;
  const TourScreen({super.key, required this.id, required this.onBack, required this.onRoom});
  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  Rec? t;
  List<Rec> entries = [], matches = [];
  Map<String, String> names = {};
  String? err, busy;
  String tab = 'board';
  final teamName = TextEditingController();
  RealtimeChannel? _ch;
  Timer? _tm;
  String? _notified;

  @override
  void initState() {
    super.initState();
    load();
    void soon() {
      _tm?.cancel();
      _tm = Timer(const Duration(milliseconds: 300), load);
    }

    final id = widget.id;
    _ch = sb
        .channel('tour:$id')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'tournaments', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id), callback: (_) => soon())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'tournament_entries', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'tournament_id', value: id), callback: (_) => soon())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'tournament_matches', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'tournament_id', value: id), callback: (_) => soon())
        .subscribe();
  }

  @override
  void dispose() {
    _tm?.cancel();
    if (_ch != null) sb.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await Future.wait([
        sb.from('tournaments').select().eq('id', widget.id).maybeSingle(),
        sb.from('standings').select().eq('tournament_id', widget.id).order('pos'),
        sb.from('tournament_matches').select().eq('tournament_id', widget.id).order('round').order('idx'),
      ]);
      if (!mounted) return;
      setState(() {
        err = null;
        t = r[0] == null ? null : Rec.of(r[0]);
        entries = recs(r[1]);
        matches = recs(r[2]);
        names = {for (final e in entries) e.s('id'): e.s('team_name')};
      });
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  Future<void> run(String k, Future<void> Function() fn, [String? ok]) async {
    if (busy != null) return;
    setState(() => busy = k);
    try {
      await fn();
      if (ok != null) {
        toast(ok, 'ok');
        buzz('success');
      }
      await load();
    } catch (e) {
      toast(errFa(e), 'err');
      buzz('heavy');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Future<void> overrideMatch(Rec m) async {
    var a = 0, b = 0;
    await showCard(context, accent: C.orange, child: (ctx) => StatefulBuilder(builder: (ctx, set) {
          Widget sc(int v, ValueChanged<int> on) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(onPressed: () => on((v - 1).clamp(0, 20)), icon: const Icon(Icons.remove_circle_outline, color: C.dim)),
                tTitle(fa(v), size: 22),
                IconButton(onPressed: () => on((v + 1).clamp(0, 20)), icon: const Icon(Icons.add_circle_outline, color: C.dim)),
              ]);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              tTitle('ثبت دستی نتیجه', size: 18),
              const SizedBox(height: 8),
              T(names[m.s('entry_a')] ?? '؟', size: 13),
              sc(a, (v) => set(() => a = v)),
              T(names[m.s('entry_b')] ?? '؟', size: 13),
              sc(b, (v) => set(() => b = v)),
              const SizedBox(height: 12),
              Btn('ثبت', colors: G.gold, onTap: () {
                Navigator.pop(ctx);
                run('ovr', () async => rpc('set_tournament_result', {'p_tm': m.s('id'), 'p_sa': a, 'p_sb': b}), 'نتیجه ثبت شد');
              }),
            ]),
          );
        }));
  }

  @override
  Widget build(BuildContext context) {
    final tt = t;
    if (tt == null) {
      return _page(context, 'تورنمنت', 'TOURNAMENT', widget.onBack, [err != null ? ErrorState(err!, onRetry: load) : const LoadingList()]);
    }
    final uid = Auth.i.uid;
    final my = entries.where((e) => uid != null && (e.m['members'] is List) && (e.m['members'] as List).contains(uid)).firstOrNull;
    final isOrg = tt.s('created_by') == uid;
    final next = my == null ? null : matches.where((m) => (m.s('status') == 'ready' || m.s('status') == 'live') && (m.s('entry_a') == my.s('id') || m.s('entry_b') == my.s('id'))).firstOrNull;
    if (next != null && next.s('status') == 'ready' && _notified != next.s('id')) {
      _notified = next.s('id');
      Oracle.i.react('tourReady');
    }
    final (sl, sc) = kTourStatus[tt.s('status')] ?? ('', C.dim);
    final winner = tt.str('winner_entry') != null ? names[tt.s('winner_entry')] : null;
    final elim = isElim(tt.s('format'));
    return _page(context, tt.s('name'), '${kFormatFa[tt.s('format')]} · ${tt.s('mode').toUpperCase()}', widget.onBack, onRefresh: load, accent: C.orange, [
      Panel(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        accent: sc,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Wrap(textDirection: TextDirection.rtl, runSpacing: 4, children: [
            Badge2(sl, color: sc, live: tt.s('status') == 'running'),
            Badge2('${fa(entries.length)}/${fa(tt.i('max_entries'))} شرکت‌کننده', color: C.sky),
            Badge2('💎 ${fa(tt.i('prize_gems'))} قهرمان', color: const Color(0xff9fd8ff)),
            Badge2('${fa(tt.i('prize_xp'))} XP', color: C.cyan),
            if (tt.i('min_level') > 1) Badge2('حداقل سطح ${fa(tt.i('min_level'))}', color: C.green),
            if (tt.s('status') != 'registration' && tt.i('current_round') > 0) Badge2('دور ${fa(tt.i('current_round'))}', color: C.violet),
          ]),
          if (winner != null) Padding(padding: const EdgeInsets.only(top: 10), child: Row(textDirection: TextDirection.rtl, children: [Img(ui2('x_trophy'), w: 44, h: 44), const SizedBox(width: 8), tTitle('قهرمان: $winner', size: 16, color: C.gold)])),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (tt.s('status') == 'registration')
            if (my != null)
              Btn(busy == 'leave' ? '…' : 'انصراف از تورنمنت', small: true, colors: G.dark, onTap: () => run('leave', () async => rpc('leave_tournament', {'p_tid': tt.s('id')}), 'از تورنمنت خارج شدی'))
            else if (entries.length < tt.i('max_entries')) ...[
              if (tt.s('mode') != '1v1') Field2(teamName, label: 'نام تیم (اختیاری)', maxLength: 24),
              Btn(busy == 'join' ? '…' : 'ثبت‌نام', colors: G.green, onTap: () => run('join', () async => rpc('join_tournament', {'p_tid': tt.s('id'), 'p_team_name': teamName.text.trim().isEmpty ? null : teamName.text.trim(), 'p_members': null}), 'ثبت‌نام شدی!')),
            ] else
              const T('ظرفیت تکمیل است', size: 13, color: C.orange, align: TextAlign.center),
          if (isOrg && tt.s('status') == 'registration')
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Btn(busy == 'start' ? '…' : 'شروع تورنمنت (${fa(entries.length)} نفر)', colors: G.gold, disabled: entries.length < 2, onTap: () => run('start', () async => rpc('start_tournament', {'p_tid': tt.s('id')}), 'تورنمنت شروع شد'))),
          if (next != null)
            Panel(
              margin: const EdgeInsets.only(top: 12),
              accent: C.red,
              glowOn: true,
              child: Column(children: [
                tBold('مسابقه‌ی بعدی تو', size: 12, color: C.red),
                tTitle('${names[next.s('entry_a')] ?? '؟'}  vs  ${names[next.s('entry_b')] ?? '؟'}', size: 16, lines: 1),
                const SizedBox(height: 8),
                Btn(busy == 'room' ? '…' : 'ورود به مسابقه', colors: G.red, onTap: () => run('room', () async => widget.onRoom(Rec.of(await rpc('open_tournament_room', {'p_tm': next.s('id')}))))),
              ]),
            ),
        ]),
      ),
      Tabs2<String>(items: [('board', elim ? 'براکت' : 'جدول'), ('entries', 'شرکت‌کنندگان')], value: tab, onChange: (v) => setState(() => tab = v)),
      if (tab == 'entries')
        if (entries.isEmpty)
          const EmptyState('هنوز کسی ثبت‌نام نکرده')
        else
          for (final e in entries)
            ListRow(
              leading: SizedBox(width: 36, child: T(e.i('seed') > 0 ? '#${fa(e.i('seed'))}' : '•', size: 12, color: C.dim)),
              title: e.s('team_name'),
              right: e.b('eliminated') ? const Badge2('حذف', color: C.red) : e.i('final_rank') == 1 ? const Badge2('قهرمان', color: C.gold) : null,
            )
      else if (tt.s('status') == 'registration')
        const EmptyState('براکت بعد از شروع ساخته می‌شود · برگزارکننده تورنمنت را شروع می‌کند')
      else if (elim)
        ..._bracket(my?.s('id'), isOrg)
      else
        ..._standings(my?.s('id'), isOrg),
    ]);
  }

  List<Widget> _matchRows(Iterable<Rec> ms, String? my, bool isOrg) => [
        for (final m in ms)
          Press(
            onTap: isOrg && m.s('status') != 'done' ? () => overrideMatch(m) : null,
            scaleTo: .98,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xd10a0e28), borderRadius: BorderRadius.circular(12), border: Border.all(color: m.s('entry_a') == my || m.s('entry_b') == my ? C.cyan : C.line)),
              child: Row(textDirection: TextDirection.rtl, children: [
                Expanded(child: T(names[m.s('entry_a')] ?? '؟', size: 12, lines: 1, color: m.s('winner') == m.s('entry_a') && m.s('entry_a').isNotEmpty ? C.gold : C.text)),
                T(m.s('status') == 'done' ? '${fa(m.i('score_a'))} : ${fa(m.i('score_b'))}' : 'vs', size: 13, family: F.title, weight: 900, color: C.dim),
                Expanded(child: T(names[m.s('entry_b')] ?? '؟', size: 12, lines: 1, align: TextAlign.left, color: m.s('winner') == m.s('entry_b') && m.s('entry_b').isNotEmpty ? C.gold : C.text)),
                if (m.s('status') == 'live') const Badge2('زنده', color: C.red, live: true),
              ]),
            ),
          ),
      ];

  List<Widget> _bracket(String? my, bool isOrg) {
    final out = <Widget>[];
    final groups = <String, List<Rec>>{};
    for (final m in matches) {
      groups.putIfAbsent('${m.s('bracket', 'w')}:${m.i('round')}', () => []).add(m);
    }
    for (final e in groups.entries) {
      final br = e.key.split(':');
      out.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: tBold('${br[0] == 'l' ? 'جدول بازنده‌ها · ' : br[0] == 'gf' ? 'فینال بزرگ · ' : ''}دور ${fa(int.tryParse(br[1]) ?? 0)}', size: 13, color: br[0] == 'l' ? C.orange : C.cyan, align: TextAlign.right)));
      out.addAll(_matchRows(e.value, my, isOrg));
    }
    return out;
  }

  List<Widget> _standings(String? my, bool isOrg) {
    Widget td(String s, {double w = 30, bool flex = false, Color c = C.text, bool bold = false}) {
      final t = T(s, size: 11, color: c, align: flex ? TextAlign.right : TextAlign.center, lines: 1, family: bold ? F.bold : F.body, weight: bold ? 800 : 600);
      return flex ? Expanded(child: t) : SizedBox(width: w, child: t);
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(textDirection: TextDirection.rtl, children: [td('#', c: C.dim), td('تیم', flex: true, c: C.dim), td('بازی', c: C.dim), td('ب', c: C.dim), td('م', c: C.dim), td('ش', c: C.dim), td('گل', w: 44, c: C.dim), td('امتیاز', w: 40, c: C.dim)]),
      ),
      for (final e in entries)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: e.s('id') == my ? const Color(0x1a4fe3ff) : null, border: const Border(bottom: BorderSide(color: C.line))),
          child: Row(textDirection: TextDirection.rtl, children: [
            td(fa(e.i('pos'))),
            td(e.s('team_name'), flex: true, bold: true),
            td(fa(e.i('played'))),
            td(fa(e.i('wins'))),
            td(fa(e.i('draws'))),
            td(fa(e.i('losses'))),
            td('${fa(e.i('gf'))}:${fa(e.i('ga'))}', w: 44),
            td(fa(e.i('points')), w: 40, c: C.gold, bold: true),
          ]),
        ),
      if (matches.any((m) => m.s('status') == 'ready' || m.s('status') == 'live')) ...[
        const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 6), child: T('مسابقات باز', size: 14, align: TextAlign.right)),
        ..._matchRows(matches.where((m) => m.s('status') == 'ready' || m.s('status') == 'live'), my, isOrg),
      ],
    ];
  }
}
