// Port of src/social/Social.tsx: Social tab — messages (inbox + user search + discover groups/channels + new
// group/channel), clubs (top list, search, create), friends (following / followers). Plus the overlay openers
// used by the shell (AppNav.openChat / openClub / openProfile).
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel, PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType;

import '../app/shell.dart' show AppNav;
import '../core/assets.dart';
import '../core/sound.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../online/ui.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'chat.dart';
import 'club.dart';
import 'public_profile.dart';

// ---------------- overlay openers (shell API) ----------------
Future<void> openChat(BuildContext context, String chatId) async =>
    AppNav.pushOverlay('chat:$chatId', (_) => ChatScreen(chatId: chatId));
Future<void> openClub(BuildContext context, String clubId) async =>
    AppNav.pushOverlay('club:$clubId', (_) => ClubScreen(clubId: clubId));
Future<void> openPublicProfile(BuildContext context, String userId) async =>
    AppNav.pushOverlay('profile:$userId', (_) => PublicProfileScreen(userId: userId));

/// Starts (or reuses) a DM with [userId] via `open_dm` and opens it. Shared with the public profile.
Future<void> openDm(BuildContext context, String userId) async {
  try {
    final cid = await rpc('open_dm', {'p_user': userId});
    if (context.mounted) await openChat(context, '$cid');
  } catch (e) {
    toast(errFa(e), 'err');
  }
}

// ---------------- shared bits ----------------
const kClubEmblems = ['emb0', 'emb1', 'emb2', 'emb3', 'emb4', 'emb5', 'emb6', 'emb7', 'emb8', 'emb9', 'emb10', 'emb11', 'emb12', 'emb13', 'emb14', 'emb15'];

BoxDecoration socialRowDeco([Color? border]) => BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: border ?? C.line),
      color: const Color(0xdb0a102c),
    );

/// The RN `st.row`: rtl row card.
class SRow extends StatelessWidget {
  final List<Widget> children;
  final double? height;
  final Color? border;
  const SRow({super.key, required this.children, this.height, this.border});
  @override
  Widget build(BuildContext context) => Container(
        constraints: BoxConstraints(minHeight: height ?? 60),
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: SP.s),
        margin: const EdgeInsets.only(bottom: SP.s),
        decoration: socialRowDeco(border),
        child: Row(textDirection: TextDirection.rtl, children: children),
      );
}

class SPill extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const SPill(this.label, {super.key, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: SP.m),
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line), color: const Color(0xd9080e28)),
          child: T(label, size: 12, family: F.bold, weight: 800, color: color),
        ),
      );
}

class _ConvIcon extends StatelessWidget {
  final String kind;
  final String? url;
  const _ConvIcon(this.kind, {this.url});
  static const double size = 48;
  @override
  Widget build(BuildContext context) {
    final c = kind == 'club' ? C.gold : kind == 'channel' ? C.violet : C.cyan;
    final img = url ?? (kind == 'club' ? ui2('x_shield') : kind == 'channel' ? ui2('c_mega') : ui2('x_team'));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: 2), color: const Color(0xff050816)),
      child: url != null ? ClipOval(child: Img(img, w: size - 6, h: size - 6, fit: BoxFit.cover)) : Img(img, w: size * .66, h: size * .66),
    );
  }
}

Widget _textCol(List<Widget> c) => Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: SP.s),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: c),
      ),
    );

class _Empty extends StatelessWidget {
  final String? img;
  final String title;
  final String? sub, action;
  final VoidCallback? onAction;
  const _Empty({this.img, required this.title, this.sub, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(SP.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Img(img ?? kit('star'), w: 72, h: 72, opacity: .85),
          const SizedBox(height: SP.s),
          tBold(title, size: 16, align: TextAlign.center),
          if (sub != null) ...[const SizedBox(height: 4), T(sub!, size: 12, color: C.dim, align: TextAlign.center)],
          if (action != null) ...[const SizedBox(height: SP.l), SizedBox(width: 220, child: Btn(action!, small: true, onTap: onAction))],
        ]),
      );
}

class _Skeleton extends StatelessWidget {
  final int rows;
  final double h;
  const _Skeleton({this.rows = 4, this.h = 60});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: SP.l),
        child: Column(children: [
          for (var i = 0; i < rows; i++)
            Container(height: h, margin: const EdgeInsets.only(bottom: SP.s), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: const Color(0x590e163a), border: Border.all(color: const Color(0x1f6eaaff)))),
        ]),
      );
}

// ======================= root =======================
class SocialRoot extends StatefulWidget {
  final double top, bottom;
  const SocialRoot({super.key, this.top = 0, this.bottom = 0});
  @override
  State<SocialRoot> createState() => _SocialRootState();
}

class _SocialRootState extends State<SocialRoot> {
  String tab = 'msg';
  bool busy = false;

  Future<void> _guest() async {
    setState(() => busy = true);
    try {
      final id = await Auth.i.ensure();
      if (id == null) toast('اتصال برقرار نشد · Connection failed', 'err');
    } catch (_) {
      toast('اتصال برقرار نشد · Connection failed', 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Auth.i,
        builder: (context, _) {
          final uid = Auth.i.uid;
          if (uid == null) {
            return Padding(
              padding: EdgeInsets.only(top: widget.top, bottom: widget.bottom),
              child: Center(
                child: _Empty(
                  img: ui2('c_profile'),
                  title: 'اجتماعی · Social',
                  sub: 'برای پیام، باشگاه و دوستان وارد بخش آنلاین شو (مهمان هم می‌شود)\nSign in (guest works) for messages, clubs and friends',
                  action: busy ? '…' : 'ورود به‌عنوان مهمان · Guest',
                  onAction: busy ? null : _guest,
                ),
              ),
            );
          }
          return Padding(
            padding: EdgeInsets.only(top: widget.top),
            child: Column(children: [
              Tabs2<String>(items: const [('msg', 'پیام‌ها'), ('club', 'باشگاه‌ها'), ('friends', 'دوستان')], value: tab, onChange: (v) => setState(() => tab = v)),
              const SizedBox(height: SP.xs),
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey('$tab:$uid'),
                  child: tab == 'msg'
                      ? _Messages(uid: uid, bottom: widget.bottom)
                      : tab == 'club'
                          ? _Clubs(bottom: widget.bottom)
                          : _Friends(uid: uid, bottom: widget.bottom),
                ),
              ),
            ]),
          );
        },
      );
}

// ======================= messages =======================
class _Messages extends StatefulWidget {
  final String uid;
  final double bottom;
  const _Messages({required this.uid, required this.bottom});
  @override
  State<_Messages> createState() => _MessagesState();
}

class _MessagesState extends State<_Messages> {
  List<Rec>? rows;
  String? err;
  List<Rec>? found;
  final q = TextEditingController();
  String _lastQ = '';
  Timer? _soon, _search;
  RealtimeChannel? _ch;

  @override
  void initState() {
    super.initState();
    _load();
    q.addListener(_onQ);
    // RLS limits message events to conversations I belong to
    _ch = sb
        .channel('inbox:${widget.uid}')
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'messages', callback: (_) => _later())
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'conversation_members',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: widget.uid),
            callback: (_) => _later())
        .subscribe();
  }

  void _later() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _load() async {
    try {
      final d = await sb.from('inbox').select().order('last_message_at', ascending: false).limit(100);
      if (!mounted) return;
      setState(() {
        err = null;
        rows = recs(d);
      });
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  void _onQ() {
    final term = q.text.trim();
    if (term == _lastQ) return;
    _lastQ = term;
    _search?.cancel();
    if (term.length < 2) {
      if (found != null) setState(() => found = null);
      return;
    }
    _search = Timer(const Duration(milliseconds: 300), () async {
      try {
        final d = await sb
            .from('profiles')
            .select('id, username, avatar, avatar_url, level, online_at')
            .ilike('username', '%${term.replaceAll(RegExp(r'[%_]'), '')}%')
            .neq('id', widget.uid)
            .limit(20);
        if (mounted && _lastQ == term) setState(() => found = recs(d));
      } catch (_) {
        if (mounted && _lastQ == term) setState(() => found = []);
      }
    });
  }

  Future<void> _dm(String id) async {
    q.clear();
    await openDm(context, id);
  }

  void _sheet(bool isNew) => showSheet(context,
      title: isNew ? 'گروه یا کانال جدید' : 'کشف گروه‌ها و کانال‌ها',
      en: isNew ? 'NEW CONVERSATION' : 'DISCOVER',
      height: .82,
      child: (ctx) => isNew
          ? _NewConv(onDone: (id) {
              Navigator.of(ctx).pop();
              openChat(context, id);
            })
          : _Discover(onOpen: (id) {
              Navigator.of(ctx).pop();
              openChat(context, id);
            }));

  @override
  void dispose() {
    _soon?.cancel();
    _search?.cancel();
    if (_ch != null) sb.removeChannel(_ch!);
    q.dispose();
    super.dispose();
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: SP.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Field2(q, hint: 'جستجوی بازیکن با نام کاربری… · Search players', maxLength: 40),
          if (found != null)
            Padding(
              padding: const EdgeInsets.only(bottom: SP.m),
              child: found!.isEmpty
                  ? const Padding(padding: EdgeInsets.only(bottom: SP.s), child: T('کسی پیدا نشد · No one found', color: C.dim, align: TextAlign.center))
                  : Column(children: [
                      for (final p in found!)
                        SRow(children: [
                          Press(
                            onTap: () => openPublicProfile(context, p.s('id')),
                            child: Avatar(avatar: p.str('avatar'), url: p.str('avatar_url'), size: 40, ring: isOnline(p.str('online_at')) ? C.green : C.line),
                          ),
                          _textCol([tBold(p.s('username'), size: 14, lines: 1), T('سطح ${fa(p.i('level', 1))}', size: 10, color: C.dim)]),
                          SPill('پیام', color: C.cyan, onTap: () => _dm(p.s('id'))),
                        ]),
                    ]),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: SP.m),
            child: Row(textDirection: TextDirection.rtl, children: [
              Expanded(child: Btn('گروه / کانال جدید', small: true, colors: G.green, onTap: () => _sheet(true))),
              const SizedBox(width: SP.s),
              Expanded(child: Btn('کشف گروه‌ها', small: true, colors: G.dark, onTap: () => _sheet(false))),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final list = rows ?? const <Rec>[];
    final Widget empty = err != null
        ? Padding(padding: const EdgeInsets.all(SP.xl), child: ErrorState(err!, onRetry: _load))
        : rows == null
            ? const _Skeleton(rows: 5, h: 64)
            : _Empty(img: ui2('c_mega'), title: 'هنوز گفتگویی نداری', sub: 'یک بازیکن را جستجو کن یا به یک گروه بپیوند\nSearch a player or join a group');
    return RefreshIndicator(
      color: C.cyan,
      backgroundColor: C.bg2,
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(bottom: widget.bottom + SP.l),
        itemCount: 1 + (list.isEmpty ? 1 : list.length),
        itemBuilder: (_, i) {
          if (i == 0) return _header();
          if (list.isEmpty) return empty;
          final r = list[i - 1];
          return _InboxItem(r: r, onTap: () => openChat(context, r.s('id')));
        },
      ),
    );
  }
}

class _InboxItem extends StatelessWidget {
  final Rec r;
  final VoidCallback onTap;
  const _InboxItem({required this.r, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final kind = r.s('kind', 'dm');
    final peer = r['peer'] is Map ? r.rec('peer') : null;
    final title = kind == 'dm' ? (peer?.str('username') ?? 'گفتگو') : (r.str('title') ?? kKindLabel[kind] ?? '');
    final lm = r['last_message'] is Map ? r.rec('last_message') : null;
    final unread = r.i('unread');
    final on = kind == 'dm' && isOnline(peer?.str('online_at'));
    final kc = kind == 'club' ? C.gold : kind == 'channel' ? C.violet : C.cyan;
    final preview = lm == null ? 'بدون پیام' : (lm.str('image_url') != null && (lm.str('body') ?? '').isEmpty ? '📷 عکس' : lm.s('body'));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SP.l),
      child: Press(
        onTap: onTap,
        scaleTo: .98,
        child: SRow(height: 72, children: [
          Stack(clipBehavior: Clip.none, children: [
            kind == 'dm' ? Avatar(avatar: peer?.str('avatar'), url: peer?.str('avatar_url'), size: 48, ring: on ? C.green : C.line) : _ConvIcon(kind, url: r.str('avatar_url')),
            if (on)
              Positioned(
                bottom: 1,
                left: 1,
                child: Container(width: 13, height: 13, decoration: BoxDecoration(shape: BoxShape.circle, color: C.green, border: Border.all(color: const Color(0xff0b1236), width: 2))),
              ),
          ]),
          _textCol([
            Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 170), child: tBold(title, size: 14, lines: 1)),
              if (kind != 'dm') Padding(padding: const EdgeInsets.only(right: 4), child: Badge2(kKindLabel[kind] ?? kind, color: kc)),
            ]),
            const SizedBox(height: 2),
            T(preview, size: 12, color: unread > 0 ? C.text : C.dim, lines: 1),
          ]),
          SizedBox(
            width: 52,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              T(timeAgo(lm?.str('created_at') ?? r.str('last_message_at')), size: 10, color: C.dim, lines: 1),
              if (unread > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 22,
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(11)),
                  child: T(fa(unread > 99 ? 99 : unread), size: 10, family: F.bold, weight: 800, color: Colors.white),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _NewConv extends StatefulWidget {
  final ValueChanged<String> onDone;
  const _NewConv({required this.onDone});
  @override
  State<_NewConv> createState() => _NewConvState();
}

class _NewConvState extends State<_NewConv> {
  String kind = 'group';
  final title = TextEditingController(), about = TextEditingController();
  bool pub = true, busy = false;

  Future<void> _go() async {
    if (title.text.trim().length < 2) {
      toast('عنوان لازم است · Title required', 'err');
      return;
    }
    setState(() => busy = true);
    try {
      final id = await rpc('create_conversation', {
        'p_kind': kind,
        'p_title': title.text.trim(),
        'p_about': about.text.trim().isEmpty ? null : about.text.trim(),
        'p_public': pub,
        'p_members': <String>[],
      });
      sfx(Snd.ready);
      widget.onDone('$id');
    } catch (e) {
      toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    title.dispose();
    about.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(SP.l), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
        Segment<String>(value: kind, onChange: (v) => setState(() => kind = v), items: const [('group', 'گروه'), ('channel', 'کانال')]),
        Padding(
          padding: const EdgeInsets.only(top: SP.s, bottom: SP.m),
          child: T(kind == 'group' ? 'در گروه همه‌ی اعضا پیام می‌فرستند. · Everyone can post.' : 'در کانال فقط مالک و مدیرها پیام می‌فرستند. · Only owner/admins post.',
              size: 11, color: C.dim, align: TextAlign.right),
        ),
        Field2(title, label: 'عنوان · Title', maxLength: 40),
        Field2(about, label: 'توضیح (اختیاری) · About', maxLength: 200, lines: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(textDirection: TextDirection.rtl, children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                T('عمومی · Public', family: F.bold, weight: 800),
                T('در بخش «کشف» دیده شود و همه بتوانند بپیوندند', size: 11, color: C.dim, align: TextAlign.right),
              ]),
            ),
            const SizedBox(width: SP.s),
            Toggle(on: pub, onChange: (v) => setState(() => pub = v)),
          ]),
        ),
        const SizedBox(height: SP.l),
        Btn(busy ? '…' : 'ساختن · Create', colors: G.green, disabled: busy, onTap: _go),
      ]);
}

class _Discover extends StatefulWidget {
  final ValueChanged<String> onOpen;
  const _Discover({required this.onOpen});
  @override
  State<_Discover> createState() => _DiscoverState();
}

class _DiscoverState extends State<_Discover> {
  List<Rec>? rows;
  @override
  void initState() {
    super.initState();
    sb.from('public_conversations').select().order('members', ascending: false).limit(50).then((d) {
      if (mounted) setState(() => rows = recs(d));
    }, onError: (_) {
      if (mounted) setState(() => rows = []);
    });
  }

  Future<void> _join(String id) async {
    try {
      await rpc('join_conversation', {'p_conv': id});
      sfx(Snd.join);
      widget.onOpen(id);
    } catch (e) {
      toast(errFa(e), 'err');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (rows == null) return const Padding(padding: EdgeInsets.only(top: SP.l), child: _Skeleton(rows: 4));
    if (rows!.isEmpty) return const _Empty(title: 'هنوز گروه عمومی‌ای نیست', sub: 'اولین گروه را خودت بساز · Create the first one');
    return ListView.builder(
      padding: const EdgeInsets.all(SP.l),
      itemCount: rows!.length,
      itemBuilder: (_, i) {
        final it = rows![i];
        final kind = it.s('kind', 'group');
        final about = it.s('about');
        return SRow(children: [
          _ConvIcon(kind),
          _textCol([
            tBold(it.s('title'), lines: 1),
            T('${kKindLabel[kind] ?? kind} · ${fa(it.i('members'))} عضو${about.isNotEmpty ? ' · $about' : ''}', size: 11, color: C.dim, lines: 1),
          ]),
          SPill('پیوستن', color: C.green, onTap: () => _join(it.s('id'))),
        ]);
      },
    );
  }
}

// ======================= clubs =======================
class _Clubs extends StatefulWidget {
  final double bottom;
  const _Clubs({required this.bottom});
  @override
  State<_Clubs> createState() => _ClubsState();
}

class _ClubsState extends State<_Clubs> {
  List<Rec>? rows;
  final q = TextEditingController();
  String _lastQ = '';
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    q.addListener(() {
      if (q.text == _lastQ) return;
      _lastQ = q.text;
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 250), _load);
    });
  }

  Future<void> _load() async {
    final term = q.text.trim().replaceAll(RegExp(r'[%_,()]'), '');
    try {
      var f = sb.from('club_list').select();
      if (term.isNotEmpty) f = f.or('name.ilike.%$term%,tag.ilike.%$term%');
      final d = await f.order('power', ascending: false).limit(50);
      if (mounted && q.text.trim().replaceAll(RegExp(r'[%_,()]'), '') == term) setState(() => rows = recs(d));
    } catch (_) {
      if (mounted) setState(() => rows = []);
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    q.dispose();
    super.dispose();
  }

  void _create() => showSheet(context,
      title: 'ساخت باشگاه',
      en: 'NEW CLUB',
      accent: C.gold,
      height: .9,
      child: (ctx) => _CreateClub(onDone: (id) {
            Navigator.of(ctx).pop();
            openClub(context, id);
          }));

  String _policy(String p) => p == 'open' ? 'آزاد' : p == 'request' ? 'با درخواست' : 'فقط دعوت';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Auth.i,
        builder: (context, _) {
          final myClub = Auth.i.profile?.str('club_id');
          final list = rows ?? const <Rec>[];
          return ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: widget.bottom + SP.l),
            itemCount: 1 + (list.isEmpty ? 1 : list.length),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SP.l),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: SP.s),
                      child: myClub != null && myClub.isNotEmpty
                          ? Btn('باشگاه من · My club', colors: G.gold, small: true, onTap: () => openClub(context, myClub))
                          : Btn('ساخت باشگاه (۵۰ الماس)', colors: G.green, small: true, onTap: _create),
                    ),
                    Field2(q, hint: 'جستجوی نام یا تگ باشگاه… · Search clubs', maxLength: 24),
                    const Padding(padding: EdgeInsets.only(bottom: SP.s), child: T('برترین باشگاه‌ها · Top clubs', size: 16, family: F.bold, weight: 800, align: TextAlign.right)),
                  ]),
                );
              }
              if (list.isEmpty) return rows == null ? const _Skeleton(rows: 5, h: 70) : _Empty(img: ui2('x_shield'), title: 'باشگاهی پیدا نشد · No clubs found');
              final idx = i - 1, it = list[idx];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: SP.l),
                child: Press(
                  onTap: () => openClub(context, it.s('id')),
                  scaleTo: .98,
                  child: SRow(height: 70, border: it.s('id') == myClub ? C.gold : null, children: [
                    SizedBox(width: 28, child: T(fa(idx + 1), family: F.title, weight: 900, color: idx < 3 ? C.gold : C.dim, align: TextAlign.center)),
                    Img(discImg(it.str('emblem')), w: 46, h: 46),
                    _textCol([
                      Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [
                        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: tBold(it.s('name'), lines: 1)),
                        Padding(padding: const EdgeInsets.only(right: 4), child: Badge2(it.s('tag'), color: C.gold)),
                      ]),
                      T('${fa(it.i('members'))}/${fa(it.i('max_members'))} عضو · ${_policy(it.s('join_policy'))}', size: 11, color: C.dim, lines: 1),
                    ]),
                    SizedBox(
                      width: 64,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        T(fa(it.i('power')), size: 13, family: F.title, weight: 900, color: C.orange),
                        const T('قدرت', size: 9, color: C.dim),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      );
}

class _CreateClub extends StatefulWidget {
  final ValueChanged<String> onDone;
  const _CreateClub({required this.onDone});
  @override
  State<_CreateClub> createState() => _CreateClubState();
}

class _CreateClubState extends State<_CreateClub> {
  final name = TextEditingController(), tag = TextEditingController(), desc = TextEditingController();
  String emblem = 'emb0', policy = 'open';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    tag.addListener(() {
      final v = tag.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final c = v.length > 5 ? v.substring(0, 5) : v;
      if (c != tag.text) tag.value = TextEditingValue(text: c, selection: TextSelection.collapsed(offset: c.length));
    });
  }

  Future<void> _go() async {
    final n = name.text.trim(), t = tag.text;
    if (n.length < 3 || n.length > 24) {
      toast('نام باشگاه ۳ تا ۲۴ کاراکتر · Name 3–24 chars', 'err');
      return;
    }
    if (!RegExp(r'^[A-Z0-9]{2,5}$').hasMatch(t)) {
      toast('تگ: ۲ تا ۵ حرف/عدد انگلیسی بزرگ · Tag A–Z/0–9, 2–5', 'err');
      return;
    }
    if ((Auth.i.profile?.i('gems') ?? 0) < 50) {
      toast('۵۰ الماس لازم داری · Need 50 gems', 'err');
      return;
    }
    setState(() => busy = true);
    try {
      final id = await rpc('create_club', {
        'p_name': n,
        'p_tag': t,
        'p_emblem': emblem,
        'p_desc': desc.text.trim().isEmpty ? null : desc.text.trim(),
        'p_policy': policy,
        'p_min_level': 1,
      });
      sfx(Snd.win);
      buzz('success');
      toast('باشگاه ساخته شد! · Club created!', 'ok');
      Auth.i.refreshProfile();
      widget.onDone('$id');
    } catch (e) {
      toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    tag.dispose();
    desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(SP.l, SP.l, SP.l, SP.xl * 2), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
        Field2(name, label: 'نام باشگاه · Club name', maxLength: 24),
        Field2(tag, label: 'تگ (۲ تا ۵ حرف انگلیسی) · Tag', maxLength: 5, ltr: true),
        Field2(desc, label: 'توضیح · Description', maxLength: 300, lines: 3),
        const Padding(padding: EdgeInsets.only(bottom: SP.s), child: T('نشان · Emblem', size: 12, family: F.bold, weight: 800, color: C.dim, align: TextAlign.right)),
        Wrap(textDirection: TextDirection.rtl, spacing: SP.s, runSpacing: SP.s, children: [
          for (final e in kClubEmblems)
            Press(
              onTap: () => setState(() => emblem = e),
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: e == emblem ? C.gold : C.line),
                  color: e == emblem ? const Color(0x26ffd257) : null,
                ),
                child: Img(discImg(e), w: 40, h: 40),
              ),
            ),
        ]),
        const Padding(padding: EdgeInsets.only(top: SP.l, bottom: SP.s), child: T('عضوگیری · Join policy', size: 12, family: F.bold, weight: 800, color: C.dim, align: TextAlign.right)),
        Segment<String>(value: policy, onChange: (v) => setState(() => policy = v), accent: C.gold, items: const [('open', 'آزاد'), ('request', 'با درخواست'), ('invite', 'فقط دعوت')]),
        const SizedBox(height: SP.l),
        Btn(busy ? '…' : 'ساخت باشگاه · ۵۰ الماس', colors: G.gold, disabled: busy, onTap: _go),
      ]);
}

// ======================= friends =======================
class _Friends extends StatefulWidget {
  final String uid;
  final double bottom;
  const _Friends({required this.uid, required this.bottom});
  @override
  State<_Friends> createState() => _FriendsState();
}

class _FriendsState extends State<_Friends> {
  String mode = 'following';
  List<Rec>? rows;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = ++_gen;
    setState(() => rows = null);
    final col = mode == 'following' ? 'follower' : 'followee', other = mode == 'following' ? 'followee' : 'follower';
    try {
      final d = await sb.from('follows').select(other).eq(col, widget.uid).limit(200);
      final ids = [for (final r in recs(d)) r.s(other)].where((s) => s.isNotEmpty).toList();
      if (ids.isEmpty) {
        if (mounted && g == _gen) setState(() => rows = []);
        return;
      }
      final ps = recs(await sb.from('profiles').select('id, username, avatar, avatar_url, level, online_at, league').inFilter('id', ids));
      ps.sort((a, b) => (isOnline(b.str('online_at')) ? 1 : 0) - (isOnline(a.str('online_at')) ? 1 : 0));
      if (mounted && g == _gen) setState(() => rows = ps);
    } catch (_) {
      if (mounted && g == _gen) setState(() => rows = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = rows ?? const <Rec>[];
    return ListView.builder(
      padding: EdgeInsets.only(bottom: widget.bottom + SP.l),
      itemCount: 1 + (list.isEmpty ? 1 : list.length),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(SP.l, 0, SP.l, SP.s),
            child: Segment<String>(
              value: mode,
              accent: C.green,
              onChange: (v) {
                if (v == mode) return;
                mode = v;
                _load();
              },
              items: const [('following', 'دنبال‌شده‌ها'), ('followers', 'دنبال‌کننده‌ها')],
            ),
          );
        }
        if (list.isEmpty) {
          return rows == null
              ? const Padding(padding: EdgeInsets.all(SP.xl), child: Center(child: Spinner()))
              : _Empty(
                  img: ui2('x_player'),
                  title: mode == 'following' ? 'هنوز کسی را دنبال نمی‌کنی' : 'هنوز دنبال‌کننده‌ای نداری',
                  sub: 'از رده‌بندی یا جستجو بازیکن‌ها را پیدا کن\nFind players via leaderboards or search',
                );
        }
        final it = list[i - 1];
        final on = isOnline(it.str('online_at'));
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: SP.l),
          child: Press(
            onTap: () => openPublicProfile(context, it.s('id')),
            scaleTo: .98,
            child: SRow(children: [
              Avatar(avatar: it.str('avatar'), url: it.str('avatar_url'), size: 44, ring: on ? C.green : C.line),
              _textCol([
                tBold(it.s('username'), lines: 1),
                T(on ? 'آنلاین' : 'آخرین بازدید ${timeAgo(it.str('online_at'))} پیش', size: 11, color: on ? C.green : C.dim, lines: 1),
              ]),
              Badge2('سطح ${fa(it.i('level', 1))}', color: C.gold),
            ]),
          ),
        );
      },
    );
  }
}
