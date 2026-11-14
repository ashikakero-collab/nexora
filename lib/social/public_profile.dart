// Port of src/social/PublicProfile.tsx: public profile of any player — avatar/photo, level, league, stats,
// followers, follow/unfollow, message, block, club.
import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../net/discs.dart';
import '../net/supabase.dart';
import '../online/ui.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'social.dart' show openClub, openDm;

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  const PublicProfileScreen({super.key, required this.userId});
  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Rec? p, club, lg;
  int? followers, followingN;
  bool following = false, blocked = false, busy = false;
  String? err;

  String get id => widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<dynamic> _maybe(Future<dynamic> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final uid = Auth.i.uid;
    Map<String, dynamic>? data;
    try {
      data = await sb.from('profiles').select().eq('id', id).maybeSingle();
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
      return;
    }
    if (!mounted) return;
    if (data == null) {
      setState(() => err = 'بازیکن پیدا نشد · Player not found');
      return;
    }
    final pr = Rec.of(data);
    setState(() {
      p = pr;
      err = null;
    });
    final clubId = pr.str('club_id');
    final res = await Future.wait([
      _maybe(sb.from('profile_stats').select().eq('id', id).maybeSingle()),
      uid != null ? _maybe(sb.from('follows').select('followee').eq('follower', uid).eq('followee', id).maybeSingle()) : Future.value(null),
      uid != null ? _maybe(sb.from('user_blocks').select('blocked').eq('blocker', uid).eq('blocked', id).maybeSingle()) : Future.value(null),
      clubId != null && clubId.isNotEmpty ? _maybe(sb.from('clubs').select('id, name, tag, emblem').eq('id', clubId).maybeSingle()) : Future.value(null),
      leagues(),
    ]);
    if (!mounted) return;
    final s = res[0] is Map ? Rec.of(res[0]) : null;
    final ls = res[4] as List<Rec>;
    setState(() {
      followers = s?.i('followers') ?? 0;
      followingN = s?.i('following') ?? 0;
      following = res[1] != null;
      blocked = res[2] != null;
      club = res[3] is Map ? Rec.of(res[3]) : null;
      lg = ls.where((l) => l.s('id') == pr.s('league')).firstOrNull;
    });
  }

  Future<void> _toggleFollow() async {
    final uid = Auth.i.uid;
    if (uid == null || busy) return;
    setState(() => busy = true);
    final was = following;
    try {
      if (was) {
        await sb.from('follows').delete().eq('follower', uid).eq('followee', id);
      } else {
        await sb.from('follows').insert({'follower': uid, 'followee': id});
      }
      if (!mounted) return;
      setState(() {
        following = !was;
        if (followers != null) followers = followers! + (was ? -1 : 1);
      });
      buzz('medium');
      if (!was) sfx(Snd.ready);
    } catch (e) {
      toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _toggleBlock() async {
    final uid = Auth.i.uid;
    if (uid == null) return;
    final was = blocked;
    try {
      if (was) {
        await sb.from('user_blocks').delete().eq('blocker', uid).eq('blocked', id);
      } else {
        await sb.from('user_blocks').insert({'blocker': uid, 'blocked': id});
      }
      if (mounted) setState(() => blocked = !was);
      toast(was ? 'از مسدودی خارج شد · Unblocked' : 'کاربر مسدود شد · Blocked', 'ok');
    } catch (e) {
      toast(errFa(e), 'err');
    }
  }

  void _back() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (err != null) {
      body = Column(children: [
        Header(title: 'پروفایل', en: 'PILOT PROFILE', onBack: _back),
        const SizedBox(height: 60),
        ErrorState(err!, onRetry: _load),
      ]);
    } else if (p == null) {
      body = Column(children: [
        Header(title: 'پروفایل', en: 'PILOT PROFILE', onBack: _back),
        const Expanded(child: Center(child: Spinner(size: 36))),
      ]);
    } else {
      body = _profile(p!);
    }
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        const Positioned.fill(child: Space(theme: SpaceTheme.base, dim: .15)),
        Positioned.fill(child: body),
      ]),
    );
  }

  Widget _profile(Rec p) {
    final uid = Auth.i.uid;
    final me = uid == id;
    final lp = levelProgress(p.i('xp'));
    final lc = lg != null ? hexColor(lg!.s('color', '#4fe3ff')) : C.cyan;
    final wins = p.i('wins'), losses = p.i('losses'), draws = p.i('draws');
    final played = wins + losses + draws, wr = played > 0 ? (wins / played * 100).round() : 0;
    final eq = p.str('equipped_disc');
    final ds = Discs.i.stats(eq);
    final on = isOnline(p.str('online_at'));
    final bio = p.s('bio');
    final stats = <(String, String, String)>[
      (ui2('x_ball'), 'بازی', fa(played)),
      (ui2('x_medal'), 'برد', fa(wins)),
      (ui2('x_shield'), 'باخت', fa(losses)),
      (ui2('x_star'), 'درصد برد', '${fa(wr)}٪'),
      (ui2('x_statue'), 'گل', fa(p.i('goals'))),
      (ui2('x_crown'), 'آرنا', fa(p.i('arena_points'))),
    ];
    Widget statCell((String, String, String) s) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(SP.xs),
            child: Panel(
              accent: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: SP.s),
              child: Column(children: [
                Img(s.$1, w: 34, h: 34),
                const SizedBox(height: 2),
                T(s.$3, size: 16, family: F.title, weight: 900),
                T(s.$2, size: 10, color: C.dim),
              ]),
            ),
          ),
        );
    Widget count(int v, String l) => Expanded(
          child: Column(children: [T(fa(v), size: 18, family: F.title, weight: 900), T(l, size: 10, color: C.dim)]),
        );
    Widget statBar(String l, double v, Color c) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(textDirection: TextDirection.rtl, children: [
            SizedBox(width: 44, child: T(l, size: 10, color: C.dim, align: TextAlign.right)),
            const SizedBox(width: 6),
            Expanded(child: Bar(v: (v / 10).clamp(0, 1).toDouble(), color: c, color2: C.violet, h: 6)),
            const SizedBox(width: 6),
            SizedBox(width: 26, child: T(fa(v.round()), size: 10, color: C.text)),
          ]),
        );

    return ListView(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + SP.xl),
      children: [
        Header(title: p.s('username'), en: 'PILOT PROFILE', onBack: _back),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SP.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Panel(
              accent: lc,
              glowOn: true,
              padding: const EdgeInsets.all(SP.l),
              child: Column(children: [
                Stack(clipBehavior: Clip.none, children: [
                  Avatar(avatar: eq ?? p.str('avatar'), url: p.str('avatar_url'), size: 104, ring: lc),
                  if (on)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: C.green, border: Border.all(color: const Color(0xff0b1236), width: 3))),
                    ),
                ]),
                const SizedBox(height: SP.s),
                tTitle(p.s('username'), size: 20, align: TextAlign.center, lines: 1),
                T(on ? 'آنلاین · Online' : 'آخرین بازدید ${timeAgo(p.str('online_at'))} پیش', size: 11, color: on ? C.green : C.dim),
                if (bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: SP.s), child: T(bio, size: 12, color: const Color(0xffcfe0ff), align: TextAlign.center)),
                const SizedBox(height: SP.s),
                Wrap(textDirection: TextDirection.rtl, alignment: WrapAlignment.center, runSpacing: 4, children: [
                  Badge2('سطح ${fa(p.i('level', lp.level))}', color: C.gold),
                  if (lg != null) Badge2('لیگ ${lg!.s('name_fa')}', color: lc),
                  if (p.b('is_guest')) const Badge2('مهمان', color: C.dim),
                  if (club != null) Badge2('[${club!.s('tag')}] ${club!.s('name')}', color: C.orange),
                ]),
                const SizedBox(height: SP.m),
                Bar(v: lp.frac.clamp(0, 1).toDouble(), color: C.cyan, color2: C.violet, h: 8),
                const SizedBox(height: SP.xs),
                T('${fa(lp.cur)} / ${fa(lp.need)} XP تا سطح ${fa(lp.level + 1)}', size: 10, color: C.dim),
                const SizedBox(height: SP.m),
                Row(textDirection: TextDirection.rtl, children: [
                  count(followers ?? 0, 'دنبال‌کننده'),
                  count(followingN ?? 0, 'دنبال‌شده'),
                  count(p.i('trophies'), 'جام'),
                ]),
                if (!me && uid != null) ...[
                  const SizedBox(height: SP.m),
                  Row(textDirection: TextDirection.rtl, children: [
                    Expanded(child: Btn(following ? 'دنبال می‌کنی ✓' : 'دنبال کردن · Follow', small: true, colors: following ? G.dark : G.primary, disabled: busy, onTap: _toggleFollow)),
                    const SizedBox(width: SP.s),
                    Expanded(child: Btn('پیام · Message', small: true, colors: G.green, onTap: () => openDm(context, id))),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: SP.m),
            Row(textDirection: TextDirection.rtl, children: [for (final s in stats.take(3)) statCell(s)]),
            Row(textDirection: TextDirection.rtl, children: [for (final s in stats.skip(3)) statCell(s)]),
            const SizedBox(height: SP.s),
            Panel(
              accent: Colors.transparent,
              padding: const EdgeInsets.all(SP.m),
              child: Row(textDirection: TextDirection.rtl, children: [
                Img(discImg(eq), w: 56, h: 56),
                const SizedBox(width: SP.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const T('دیسک فعال · Active disc', size: 12, family: F.bold, weight: 800, align: TextAlign.right),
                    statBar('قدرت', ds.power, C.orange),
                    statBar('دقت', ds.accuracy, C.cyan),
                  ]),
                ),
                if (lg != null) ...[const SizedBox(width: SP.s), Img(ui(kLeagueImg[lg!.s('id')] ?? 'medal_bronze'), w: 48, h: 48)],
              ]),
            ),
            if (club != null) ...[
              const SizedBox(height: SP.m),
              Btn('باشگاه ${club!.s('name')}', small: true, colors: G.gold, onTap: () => openClub(context, club!.s('id'))),
            ],
            if (!me && uid != null)
              Press(
                onTap: _toggleBlock,
                child: Container(
                  margin: const EdgeInsets.only(top: SP.m),
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  child: T(blocked ? 'رفع مسدودی · Unblock' : 'مسدود کردن این کاربر · Block', size: 12, color: C.red, align: TextAlign.center),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}
