// Port of src/screens/Profile.tsx + OnlineProfileCard.tsx: online card (photo, bio, level, league, XP history),
// offline career, league, win-rate ring, stats grid, achievements. Card style follows the profile mockup.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../game/meta.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../online/ui.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';

const _medal = ['medal_bronze', 'medal_silver', 'medal_gold', 'medal_epic', 'shield_epic', 'shield_crown'];

class ProfileScreen extends StatefulWidget {
  final void Function(String entry) onOnline;
  const ProfileScreen({super.key, required this.onOnline});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final name = TextEditingController(text: Store.i.p.name);

  void commit() => Store.i.set((q) {
        final n = name.text.trim();
        q.name = n.isEmpty ? 'Pilot' : n.substring(0, math.min(16, n.length));
      });

  void claim(Ach a) {
    final p = Store.i.p;
    if (p.claimedAch.contains(a.id)) return;
    Store.i.set((q) {
      q.claimedAch = [...q.claimedAch, a.id];
      q.coins += a.coins;
      q.gems += a.gems;
    });
    sfx(Snd.goal);
    buzz('success');
    toast('+${fa(a.coins)} سکه', 'ok');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: Stack(children: [
          const Space(theme: SpaceTheme.base, dim: .15),
          ListenableBuilder(
            listenable: Store.i,
            builder: (_, __) {
              final p = Store.i.p, lv = level(p.xp), lg = league(p.trophies), t = teamById(p.team);
              final wr = p.played > 0 ? (p.wins / p.played * 100).round() : 0;
              final stats = [
                (ui2('x_ball'), 'بازی', p.played), (ui2('x_medal'), 'برد', p.wins), (ui2('x_shield'), 'باخت', p.losses),
                (ui2('x_star'), 'مساوی', p.draws), (ui2('x_statue'), 'گل زده', p.goalsFor), (ui2('x_trophy'), 'جام قهرمانی', p.cupsWon),
              ];
              return ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 20), children: [
                Header(title: 'مدار شخصی', en: 'PERSONAL ORBIT · PROFILE', onBack: () => Navigator.pop(context)),
                OnlineProfileCard(onOnline: widget.onOnline),
                const TitleBar('پروفایل آفلاین', en: 'OFFLINE CAREER', accent: Color(0xffff7bd5)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Panel(
                    accent: const Color(0xffff7bd5),
                    glowOn: true,
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Row(children: [
                        Img(ui2('d_banner'), w: 34, h: 92, opacity: .8),
                        Expanded(
                          child: SizedBox(
                            height: 130,
                            child: Stack(alignment: Alignment.center, children: [
                              const Pulse(size: 110, color: Color(0x59ff7bd5)),
                              Disc(teamImg(t), size: 104, ring: const Color(0xffff7bd5), ringW: 3),
                              Positioned(
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(10)),
                                  child: tBold('سطح ${fa(lv.level)}', size: 11, color: const Color(0xff1b0e00)),
                                ),
                              ),
                            ]),
                          ),
                        ),
                        Img(ui2('d_banner'), w: 34, h: 92, opacity: .8),
                      ]),
                      TextField(
                        controller: name,
                        maxLength: 16,
                        textAlign: TextAlign.center,
                        onSubmitted: (_) => commit(),
                        onTapOutside: (_) {
                          commit();
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                        style: ts(size: 20, family: isFa(name.text) ? F.faB : F.title, weight: 900),
                        decoration: const InputDecoration(counterText: '', border: InputBorder.none, isDense: true),
                      ),
                      const T('برای تغییر نام لمس کن', size: 10, color: C.dim2),
                      const SizedBox(height: 10),
                      Bar(v: lv.cur / lv.need, color: const Color(0xffff7bd5), color2: C.violet, h: 10),
                      const SizedBox(height: 4),
                      T('${lv.cur} / ${lv.need} XP', size: 10, family: F.head, weight: 700, color: C.dim),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Panel(
                    accent: C.gold,
                    child: Row(textDirection: TextDirection.rtl, children: [
                      FloatY(amp: 3, child: Img(ui(_medal[math.min(lg.idx, 5)]), w: 66, h: 66)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          tTitle('لیگ ${kLeagueFa[lg.name]}', size: 17),
                          const SizedBox(height: 6),
                          Bar(v: (p.trophies - lg.from) / (lg.to - lg.from), color: C.gold, color2: C.orange),
                          const SizedBox(height: 4),
                          T('${fa(p.trophies)} از ${fa(lg.to)} جام', size: 11, color: C.dim),
                        ]),
                      ),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Panel(
                    padding: const EdgeInsets.all(14),
                    child: Row(textDirection: TextDirection.rtl, children: [
                      _Ring(v: wr),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(children: [
                          _kv('بهترین رکورد برد پیاپی', fa(p.bestStreak)),
                          _kv('برد پیاپی فعلی', fa(p.winStreak)),
                          _kv('تفاضل گل', '${p.goalsFor - p.goalsAgainst >= 0 ? '+' : ''}${fa(p.goalsFor - p.goalsAgainst)}'),
                          _kv('دیسک‌های باز شده', fa(p.ownedTeams.length)),
                        ]),
                      ),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: Directionality(textDirection: TextDirection.rtl, child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.05,
                    children: [
                      for (final (img, k, v) in stats)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: Panel(
                            accent: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Img(img, w: 40, h: 40), tTitle(fa(v), size: 18), T(k, size: 10, color: C.dim)]),
                          ),
                        ),
                    ],
                  )),
                ),
                const TitleBar('دستاوردها', en: 'ACHIEVEMENTS', accent: C.green),
                for (final a in kAchs)
                  Builder(builder: (_) {
                    final cur = math.min(a.max, a.cur(p)), done = cur >= a.max, claimed = p.claimedAch.contains(a.id);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Opacity(
                        opacity: claimed ? .6 : 1,
                        child: Panel(
                          accent: done && !claimed ? C.green : Colors.transparent,
                          glowOn: done && !claimed,
                          padding: const EdgeInsets.all(10),
                          child: Row(textDirection: TextDirection.rtl, children: [
                            Img(ui2(a.icon), w: 44, h: 44),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                tBold(a.name, size: 14),
                                T(a.desc, size: 11, color: C.dim),
                                const SizedBox(height: 4),
                                Bar(v: cur / a.max, h: 6, color: done ? C.green : C.cyan),
                                T('${fa(cur)} / ${fa(a.max)}', size: 9, color: C.dim),
                              ]),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 84,
                              child: claimed
                                  ? const T('✓ گرفتی', size: 11, color: C.green, align: TextAlign.center)
                                  : done
                                      ? Btn('+${fa(a.coins)}', small: true, colors: G.green, onTap: () => claim(a))
                                      : T('${fa(a.coins)} سکه', size: 11, color: C.gold, align: TextAlign.center),
                            ),
                          ]),
                        ),
                      ),
                    );
                  }),
              ]);
            },
          ),
        ]),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(textDirection: TextDirection.rtl, children: [Expanded(child: T(k, size: 12, color: C.dim)), tBold(v, size: 13)]),
      );
}

class _Ring extends StatelessWidget {
  final int v;
  const _Ring({required this.v});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 84,
        height: 84,
        child: Stack(alignment: Alignment.center, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: v / 100),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, x, __) => CircularProgressIndicator(value: x, strokeWidth: 7, color: C.cyan, backgroundColor: const Color(0x1fffffff), constraints: const BoxConstraints.tightFor(width: 84, height: 84)),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [tTitle('${fa(v)}٪', size: 18), const T('برد', size: 10, color: C.dim)]),
        ]),
      );
}

class OnlineProfileCard extends StatefulWidget {
  final void Function(String entry) onOnline;
  const OnlineProfileCard({super.key, required this.onOnline});
  @override
  State<OnlineProfileCard> createState() => _OnlineProfileCardState();
}

class _OnlineProfileCardState extends State<OnlineProfileCard> {
  List<Rec>? events;
  List<Rec> ls = const [];
  bool up = false, busy = false, editBio = false;
  final bio = TextEditingController();
  int? _xpFor;

  @override
  void initState() {
    super.initState();
    leagues().then((l) => mounted ? setState(() => ls = l) : null);
  }

  void _loadEvents(String uid, int xp) {
    if (_xpFor == xp) return;
    _xpFor = xp;
    sb.from('xp_events').select('id, amount, reason, created_at').eq('user_id', uid).order('created_at', ascending: false).limit(10).then((d) {
      if (mounted) setState(() => events = recs(d));
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Auth.i,
        builder: (_, __) {
          final a = Auth.i, pr = a.profile, uid = a.uid;
          if (uid == null || pr == null) {
            return Panel(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              accent: C.cyan,
              child: Row(textDirection: TextDirection.rtl, children: [
                Img(ui('portal_globe'), w: 56, h: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    tBold('پروفایل آنلاین', size: 16),
                    const T('سطح، لیگ و آمار آنلاین بعد از ورود نمایش داده می‌شود', size: 11, color: C.dim),
                  ]),
                ),
                SizedBox(
                  width: 90,
                  child: Btn(busy ? '…' : 'ورود', small: true, onTap: () async {
                    setState(() => busy = true);
                    try {
                      await a.ensure();
                    } catch (_) {
                      toast('اتصال برقرار نشد', 'err');
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  }),
                ),
              ]),
            );
          }
          _loadEvents(uid, pr.i('xp'));
          final lp = levelProgress(pr.i('xp'));
          final cur = leagueFor(ls, pr.i('rating'));
          final nxt = ls.where((l) => l.i('min_rating') > pr.i('rating')).firstOrNull;
          final lc = cur != null ? hexColor(cur.s('color', '#4fe3ff')) : C.cyan;
          final played = pr.i('wins') + pr.i('losses') + pr.i('draws');
          return Column(children: [
            Panel(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              accent: lc,
              glowOn: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(textDirection: TextDirection.rtl, children: [
                  Press(
                    onTap: up
                        ? null
                        : () async {
                            setState(() => up = true);
                            final (url, err) = await pickAndUpload('avatars', uid, size: 512, square: true);
                            if (url != null) {
                              try {
                                await sb.from('profiles').update({'avatar_url': url}).eq('id', uid);
                                toast('عکس پروفایل به‌روز شد', 'ok');
                                buzz('success');
                              } catch (e) {
                                toast(errFa(e), 'err');
                              }
                            } else if (err != null) {
                              toast(err, 'err');
                            }
                            if (mounted) setState(() => up = false);
                          },
                    child: Stack(children: [
                      Avatar(avatar: pr.str('equipped_disc'), url: pr.str('avatar_url'), size: 76, ring: lc),
                      Positioned(
                          bottom: 0,
                          left: 0,
                          child: Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: const Color(0xff0a1236), shape: BoxShape.circle, border: Border.all(color: C.cyan)),
                              child: up ? const Spinner(size: 14) : const Icon(Icons.photo_camera_rounded, size: 14, color: C.cyan))),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      tTitle(pr.s('username'), size: 18, lines: 1),
                      const SizedBox(height: 4),
                      Wrap(textDirection: TextDirection.rtl, runSpacing: 4, children: [
                        Badge2('سطح ${fa(lp.level)}', color: C.gold),
                        if (cur != null) Badge2(cur.s('name_fa'), color: lc),
                        if (a.isGuest) const Badge2('مهمان', color: C.dim),
                      ]),
                      if (pr.str('avatar_url') != null)
                        Press(
                            onTap: () async {
                              await sb.from('profiles').update({'avatar_url': null}).eq('id', uid);
                              toast('عکس حذف شد؛ دیسک فعال نمایش داده می‌شود', 'ok');
                            },
                            child: const Padding(padding: EdgeInsets.all(6), child: T('حذف عکس', size: 10, color: C.dim))),
                    ]),
                  ),
                ]),
                if (editBio) ...[
                  const SizedBox(height: 12),
                  Field2(bio, hint: 'چند کلمه درباره‌ی خودت…', maxLength: 160, lines: 3),
                  Row(textDirection: TextDirection.rtl, children: [
                    Expanded(
                        child: Btn('ذخیره', small: true, onTap: () async {
                      try {
                        final b = bio.text.trim();
                        await sb.from('profiles').update({'bio': b.isEmpty ? null : b.substring(0, math.min(160, b.length))}).eq('id', uid);
                        setState(() => editBio = false);
                        toast('ذخیره شد', 'ok');
                      } catch (e) {
                        toast(errFa(e), 'err');
                      }
                    })),
                    const SizedBox(width: 8),
                    Expanded(child: Btn('انصراف', small: true, colors: G.dark, onTap: () => setState(() => editBio = false))),
                  ]),
                ] else
                  Press(
                    onTap: () => setState(() {
                      bio.text = pr.s('bio');
                      editBio = true;
                    }),
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: T(pr.str('bio') ?? '✎ افزودن بیو', size: 12, color: pr.str('bio') != null ? const Color(0xffd6e6ff) : C.cyan, align: TextAlign.right)),
                  ),
                Bar(v: lp.frac, color: C.cyan, color2: C.violet, h: 10),
                const SizedBox(height: 4),
                T('${fa(lp.cur)} / ${fa(lp.need)} XP تا سطح ${fa(lp.level + 1)}', size: 10, color: C.dim, align: TextAlign.center),
                const SizedBox(height: 12),
                Row(textDirection: TextDirection.rtl, children: [
                  for (final (v, l) in [(fa(pr.i('rating')), 'امتیاز'), (fa(pr.i('arena_points')), 'آرنا'), ('🔥${fa(pr.i('win_streak'))}', 'برد پیاپی'), (fa(played), 'بازی آنلاین')])
                    Expanded(child: Column(children: [tTitle(v, size: 15), T(l, size: 10, color: C.dim)])),
                ]),
              ]),
            ),
            if (cur != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Press(
                  onTap: () => widget.onOnline('leagues'),
                  scaleTo: .98,
                  child: Panel(
                    accent: lc,
                    child: Row(textDirection: TextDirection.rtl, children: [
                      Img(ui(kLeagueImg[cur.s('id')] ?? 'medal_bronze'), w: 52, h: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          tBold('لیگ ${cur.s('name_fa')}', size: 14, color: lc),
                          const SizedBox(height: 4),
                          Bar(v: nxt != null ? (pr.i('rating') - cur.i('min_rating')) / math.max(1, nxt.i('min_rating') - cur.i('min_rating')) : 1, color: lc, h: 6),
                          T(nxt != null ? '${fa(nxt.i('min_rating') - pr.i('rating'))} امتیاز تا ${nxt.s('name_fa')}' : 'بالاترین لیگ!', size: 10, color: C.dim),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            const TitleBar('تاریخچه‌ی XP', en: 'RECENT XP'),
            if (events == null)
              const Spinner()
            else if (events!.isEmpty)
              const T('هنوز XP آنلاینی نگرفتی؛ یک مسابقه‌ی سریع بزن!', size: 12, color: C.dim, align: TextAlign.center)
            else
              for (final e in events!)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xb30a0e28), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
                  child: Row(textDirection: TextDirection.rtl, children: [
                    Img(e.s('reason') == 'tournament' ? ui2('x_trophy') : e.s('reason') == 'challenge' ? ui2('c_calendar') : ui2('x_star'), w: 28, h: 28),
                    const SizedBox(width: 8),
                    Expanded(child: T(kReasonFa[e.s('reason')] ?? e.s('reason'), size: 12)),
                    T(timeAgo(e.str('created_at')), size: 10, color: C.dim),
                    const SizedBox(width: 8),
                    SizedBox(width: 64, child: tBold('${e.i('amount') >= 0 ? '+' : ''}${fa(e.i('amount'))} XP', size: 12, color: e.i('amount') >= 0 ? C.green : C.red)),
                  ]),
                ),
          ]);
        },
      );
}
