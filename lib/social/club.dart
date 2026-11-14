// Port of src/social/ClubPage.tsx: emblem, tag, description, stats, members with roles, join/request,
// requests management (officers), invite (officers), club chat, leave. Realtime on club_members/club_requests.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/sound.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../online/ui.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'social.dart' show openChat, openPublicProfile;

const _kRoleFa = {'leader': ('رهبر', C.gold), 'officer': ('افسر', C.cyan), 'member': ('عضو', C.dim)};
const _kOrder = {'leader': 0, 'officer': 1, 'member': 2};

class ClubScreen extends StatefulWidget {
  final String clubId;
  const ClubScreen({super.key, required this.clubId});
  @override
  State<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends State<ClubScreen> {
  String get id => widget.clubId;
  Rec? club;
  List<Rec> members = [], reqs = [];
  String? err, busy;
  bool sureLeave = false;
  final msg = TextEditingController();
  final inv = TextEditingController();
  List<Rec> found = [];
  RealtimeChannel? _ch;
  Timer? _deb, _soon;

  @override
  void initState() {
    super.initState();
    _load();
    PostgresChangeFilter f() => PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'club_id', value: id);
    _ch = sb
        .channel('club:$id')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'club_members', filter: f(), callback: (_) => _later())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'club_requests', filter: f(), callback: (_) => _later())
        .subscribe();
    inv.addListener(_search);
    Auth.i.addListener(_onAuth);
  }

  @override
  void dispose() {
    Auth.i.removeListener(_onAuth);
    _deb?.cancel();
    _soon?.cancel();
    final c = _ch;
    _ch = null;
    if (c != null) sb.removeChannel(c);
    msg.dispose();
    inv.dispose();
    super.dispose();
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  void _later() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([
        sb.from('club_list').select().eq('id', id).maybeSingle(),
        sb.from('club_members').select('user_id, role, joined_at, profiles(username, avatar, avatar_url, level, rating, online_at)').eq('club_id', id),
        sb.from('club_requests').select('user_id, kind, message, created_at, profiles(username, avatar, avatar_url, level)').eq('club_id', id),
      ]);
      if (!mounted) return;
      if (r[0] == null) {
        setState(() => err = 'باشگاه پیدا نشد');
        return;
      }
      final ms = recs(r[1])
        ..sort((a, b) {
          final o = (_kOrder[a.s('role')] ?? 3) - (_kOrder[b.s('role')] ?? 3);
          return o != 0 ? o : b.rec('profiles').i('rating').compareTo(a.rec('profiles').i('rating'));
        });
      setState(() {
        err = null;
        club = Rec.of(r[0]);
        members = ms;
        reqs = recs(r[2]);
      });
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  void _search() {
    _deb?.cancel();
    final term = inv.text.trim();
    if (term.length < 2) {
      if (found.isNotEmpty) setState(() => found = []);
      return;
    }
    _deb = Timer(const Duration(milliseconds: 300), () async {
      try {
        final d = await sb.from('profiles').select('id, username, avatar, avatar_url, club_id').ilike('username', '%${term.replaceAll(RegExp(r'[%_]'), '')}%').isFilter('club_id', null).limit(8);
        if (mounted) setState(() => found = recs(d));
      } catch (_) {}
    });
  }

  Future<bool> _run(String k, Future<dynamic> Function() fn, [String? ok]) async {
    if (busy != null) return false;
    setState(() => busy = k);
    try {
      await fn();
      if (ok != null) toast(ok, 'ok');
      buzz('success');
      await _load();
      Auth.i.refreshProfile();
      return true;
    } catch (e) {
      toast(errFa(e), 'err');
      buzz('heavy');
      return false;
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  void _join() => _run('join', () async {
        final r = await rpc('join_club', {'p_club': id, 'p_message': msg.text.trim().isEmpty ? null : msg.text.trim()});
        if (r == 'joined') {
          sfx(Snd.win);
          toast('به باشگاه پیوستی!', 'ok');
        } else {
          toast('درخواستت ارسال شد', 'ok');
        }
      });

  void _back() => Navigator.of(context).maybePop();

  Widget _sm(Widget child, VoidCallback onTap) => Press(onTap: onTap, disabled: busy != null, child: SizedBox(width: 40, height: 44, child: Center(child: child)));

  Widget _row(List<Widget> children) => Container(
        constraints: const BoxConstraints(minHeight: 60),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: const Color(0xdb0a102c), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
        child: Row(textDirection: TextDirection.rtl, children: children),
      );

  Widget _h(String s) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: tBold(s, size: 16, align: TextAlign.right));

  @override
  Widget build(BuildContext context) {
    if (err != null) {
      return Scaffold(
        backgroundColor: C.bg,
        body: Column(children: [Header(title: 'باشگاه', onBack: _back), Expanded(child: Center(child: ErrorState(err!, onRetry: _load)))]),
      );
    }
    final c = club;
    if (c == null) {
      return Scaffold(backgroundColor: C.bg, body: Column(children: [Header(title: 'باشگاه', onBack: _back), const Expanded(child: Center(child: Spinner(size: 36)))]));
    }
    final uid = Auth.i.uid;
    final mine = members.where((m) => m.s('user_id') == uid).firstOrNull;
    final role = mine?.str('role');
    final officer = role == 'leader' || role == 'officer';
    final myReq = reqs.where((r) => r.s('user_id') == uid).firstOrNull;
    final requests = reqs.where((r) => r.s('kind') == 'request').toList();
    final policy = c.s('join_policy');
    final ins = MediaQuery.paddingOf(context);
    final convId = c.str('conversation_id');
    final desc = c.str('description');

    final stats = [
      ('${fa(c.i('members'))}/${fa(c.i('max_members'))}', 'اعضا'),
      (fa(c.i('power')), 'قدرت'),
      (policy == 'open' ? 'آزاد' : policy == 'request' ? 'درخواست' : 'دعوت', 'عضوگیری'),
      (fa(c.i('min_level')), 'حداقل سطح'),
    ];

    Widget joinArea;
    if (mine != null) {
      joinArea = Row(textDirection: TextDirection.rtl, children: [
        if (convId != null) ...[
          Expanded(
              child: Btn('چت باشگاه', small: true, colors: G.green, onTap: () => openChat(context, convId))),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Btn(sureLeave ? 'مطمئنی؟' : 'ترک باشگاه', small: true, colors: G.red, onTap: () async {
            if (!sureLeave) {
              setState(() => sureLeave = true);
              return;
            }
            final ok = await _run('leave', () => rpc('leave_club'), 'از باشگاه خارج شدی');
            if (ok && mounted) _back();
          }),
        ),
      ]);
    } else if (Auth.i.profile?.str('club_id') != null) {
      joinArea = const T('تو عضو باشگاه دیگری هستی', color: C.dim, align: TextAlign.center);
    } else if (myReq?.s('kind') == 'request') {
      joinArea = const T('درخواست عضویتت در انتظار بررسی است', color: C.cyan, align: TextAlign.center);
    } else if (policy == 'invite' && myReq?.s('kind') != 'invite') {
      joinArea = const T('این باشگاه فقط با دعوت عضو می‌گیرد', color: C.dim, align: TextAlign.center);
    } else {
      final invited = myReq?.s('kind') == 'invite';
      joinArea = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (policy == 'request' && !invited) Field2(msg, label: 'پیام برای رهبر (اختیاری)', maxLength: 120),
        Btn(busy == 'join' ? '…' : invited ? 'پذیرفتن دعوت' : policy == 'open' ? 'پیوستن' : 'ارسال درخواست', colors: G.gold, onTap: _join, disabled: busy != null),
      ]);
    }

    return Scaffold(
      backgroundColor: C.bg,
      body: Column(children: [
        Header(title: c.s('name'), en: 'CLUB · ${c.s('tag')}', onBack: _back),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, ins.bottom + 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Panel(
                accent: C.gold,
                glowOn: true,
                padding: const EdgeInsets.all(16),
                child: Stack(children: [
                  const Positioned.fill(
                      child: IgnorePointer(
                          child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x38ffd257), Color(0x00ffd257)]))))),
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Center(child: Img(discImg(c.str('emblem')), w: 96, h: 96)),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.center, textDirection: TextDirection.rtl, children: [
                      Flexible(child: tTitle(c.s('name'), size: 20, lines: 1)),
                      const SizedBox(width: 6),
                      Badge2(c.s('tag'), color: C.gold),
                    ]),
                    if (desc != null && desc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: T(desc, size: 12, color: const Color(0xffd9e6ff), align: TextAlign.center)),
                    const SizedBox(height: 12),
                    Row(textDirection: TextDirection.rtl, children: [
                      for (final (v, l) in stats)
                        Expanded(child: Column(children: [tBold(v, size: 14, align: TextAlign.center), T(l, size: 10, color: C.dim, align: TextAlign.center)])),
                    ]),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              joinArea,
              if (officer && requests.isNotEmpty) ...[
                _h('درخواست‌ها (${fa(requests.length)})'),
                for (final r in requests)
                  _row([
                    Avatar(avatar: r.rec('profiles').str('avatar'), url: r.rec('profiles').str('avatar_url'), size: 40),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        tBold(r.rec('profiles').s('username', '…'), lines: 1),
                        if ((r.str('message') ?? '').isNotEmpty) T(r.s('message'), size: 11, color: C.dim, lines: 2),
                      ]),
                    ),
                    _sm(const T('✓', size: 18, color: C.green), () => _run('d${r.s('user_id')}', () => rpc('club_decide', {'p_club': id, 'p_user': r.s('user_id'), 'p_accept': true}), 'پذیرفته شد')),
                    _sm(const T('✕', size: 16, color: C.red), () => _run('d${r.s('user_id')}', () => rpc('club_decide', {'p_club': id, 'p_user': r.s('user_id'), 'p_accept': false}))),
                  ]),
              ],
              if (officer) ...[
                _h('دعوت بازیکن'),
                Field2(inv, hint: 'نام کاربری…', ltr: true, maxLength: 20),
                for (final f in found)
                  _row([
                    Avatar(avatar: f.str('avatar'), url: f.str('avatar_url'), size: 36),
                    const SizedBox(width: 8),
                    Expanded(child: T(f.s('username'), lines: 1, align: TextAlign.right)),
                    Press(
                      onTap: () {
                        _run('inv', () => rpc('club_invite', {'p_club': id, 'p_user': f.s('id')}), 'دعوت فرستاده شد');
                        inv.clear();
                      },
                      child: const SizedBox(height: 44, child: Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: T('دعوت', size: 12, color: C.gold)))),
                    ),
                  ]),
              ],
              _h('اعضا (${fa(members.length)})'),
              for (final m in members) _member(m, uid, role, officer),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _member(Rec m, String? uid, String? role, bool officer) {
    final p = m.rec('profiles'), mu = m.s('user_id'), mr = m.s('role');
    final (rl, rc) = _kRoleFa[mr] ?? ('عضو', C.dim);
    final canKick = officer && mu != uid && (mr == 'member' || (role == 'leader' && mr == 'officer'));
    return _row([
      Press(onTap: () => openPublicProfile(context, mu), child: Avatar(avatar: p.str('avatar'), url: p.str('avatar_url'), size: 42, ring: isOnline(p.str('online_at')) ? C.green : C.line)),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          tBold('${p.s('username', '…')}${mu == uid ? ' (تو)' : ''}', lines: 1),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [Badge2(rl, color: rc), Badge2('سطح ${fa(p.i('level', 1))}', color: C.sky)]),
        ]),
      ),
      if (role == 'leader' && mu != uid) ...[
        _sm(T(mr == 'officer' ? '⬇' : '⬆', size: 16, color: C.cyan),
            () => _run('a$mu', () => rpc('club_member_action', {'p_club': id, 'p_user': mu, 'p_action': mr == 'officer' ? 'demote' : 'promote'}))),
        _sm(const T('👑', size: 14), () => _run('a$mu', () => rpc('club_member_action', {'p_club': id, 'p_user': mu, 'p_action': 'transfer'}), 'رهبری منتقل شد')),
      ],
      if (canKick) _sm(const T('✕', color: C.red), () => _run('a$mu', () => rpc('club_member_action', {'p_club': id, 'p_user': mu, 'p_action': 'kick'}), 'اخراج شد')),
    ]);
  }
}
