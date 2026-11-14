// Port of src/social/Chat.tsx: conversation screen (DM / group / channel / club). Realtime messages
// (postgres_changes INSERT/UPDATE on `messages`, member changes), images (bucket `chat` via pickAndUpload),
// reply, delete own (soft: deleted=true, body=null), typing indicator over broadcast, read receipts
// (conversation_members.last_read_at), paging (40 per page, older loaded near the top), info sheet for groups.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../online/ui.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'social.dart' show openPublicProfile;

const _kPage = 40;

class ChatScreen extends StatefulWidget {
  final String chatId;
  const ChatScreen({super.key, required this.chatId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  String get id => widget.chatId;
  String? get uid => Auth.i.uid;

  Rec? conv;
  List<Rec> members = [];
  Map<String, Rec> byId = {};
  List<Rec>? msgs; // newest first (reverse ListView)
  bool more = true, loadingMore = false, sending = false;
  Rec? reply;
  final Map<String, int> typing = {};
  final txt = TextEditingController();
  final scroll = ScrollController();
  RealtimeChannel? _ch;
  Timer? _tick;
  int _lastTyping = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
    _loadMsgs();
    _markRead();
    _subscribe();
    _tick = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final before = typing.length;
      typing.removeWhere((_, t) => now - t >= 4000);
      if (typing.length != before) _set(() {});
    });
    scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    final c = _ch;
    _ch = null;
    if (c != null) sb.removeChannel(c);
    _markRead();
    scroll.dispose();
    txt.dispose();
    super.dispose();
  }

  void _set(VoidCallback f) {
    if (!_disposed && mounted) setState(f);
  }

  // ---------------- data ----------------
  void _markRead() {
    final u = uid;
    if (u == null) return;
    sb.from('conversation_members').update({'last_read_at': DateTime.now().toUtc().toIso8601String()}).eq('conversation_id', id).eq('user_id', u).then((_) {}, onError: (_) {});
  }

  Future<void> _loadMeta() async {
    try {
      final r = await Future.wait<dynamic>([
        sb.from('conversations').select().eq('id', id).maybeSingle(),
        sb.from('conversation_members').select('user_id, role, profiles(username, avatar, avatar_url, online_at)').eq('conversation_id', id).limit(500),
      ]);
      _set(() {
        if (r[0] != null) conv = Rec.of(r[0]);
        members = recs(r[1]);
        byId = {for (final m in members) m.s('user_id'): m};
      });
    } catch (e) {
      // meta failure is non-fatal; messages may still load
    }
  }

  Future<void> _loadMsgs([String? before]) async {
    try {
      var q = sb.from('messages').select().eq('conversation_id', id);
      if (before != null) q = q.lt('created_at', before);
      final rows = recs(await q.order('created_at', ascending: false).limit(_kPage));
      _set(() {
        more = rows.length == _kPage;
        if (before == null) {
          msgs = rows;
        } else {
          final have = {for (final m in msgs ?? <Rec>[]) m.i('id')};
          msgs = [...?msgs, ...rows.where((r) => !have.contains(r.i('id')))];
        }
      });
    } catch (e) {
      toast(errFa(e), 'err');
      if (before == null) _set(() => msgs = []);
    }
  }

  void _onScroll() {
    // reversed list: maxScrollExtent is the top (oldest)
    if (!scroll.hasClients || loadingMore || !more || (msgs?.isEmpty ?? true)) return;
    if (scroll.position.pixels > scroll.position.maxScrollExtent - 400) {
      loadingMore = true;
      _loadMsgs(msgs!.last.s('created_at')).whenComplete(() => loadingMore = false);
    }
  }

  void _subscribe() {
    PostgresChangeFilter f(String col) => PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: col, value: id);
    final c = sb.channel('conv:$id', opts: const RealtimeChannelConfig(self: false));
    c
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: f('conversation_id'),
            callback: (p) {
              final m = Rec.of(p.newRecord);
              final s = m.str('sender');
              _set(() {
                final cur = msgs ?? <Rec>[];
                if (!cur.any((x) => x.i('id') == m.i('id'))) msgs = [m, ...cur];
                if (s != null) typing.remove(s);
              });
              if (s != uid) {
                sfx(Snd.chat);
                _markRead();
              }
            })
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'messages',
            filter: f('conversation_id'),
            callback: (p) {
              final m = Rec.of(p.newRecord);
              _set(() => msgs = msgs?.map((x) => x.i('id') == m.i('id') ? m : x).toList());
            })
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'conversation_members', filter: f('conversation_id'), callback: (_) => _loadMeta())
        .onBroadcast(
            event: 'typing',
            callback: (p) {
              final inner = p['payload'] is Map ? p['payload'] as Map : p;
              final u = inner['u']?.toString();
              if (u != null && u != uid) _set(() => typing[u] = DateTime.now().millisecondsSinceEpoch);
            })
        .subscribe();
    _ch = c;
  }

  // ---------------- actions ----------------
  void _onType(String v) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (v.isNotEmpty && now - _lastTyping > 2500) {
      _lastTyping = now;
      _ch?.sendBroadcastMessage(event: 'typing', payload: {'u': uid}).then((_) {}, onError: (_) {});
    }
    _set(() {});
  }

  Future<void> _send([String? imageUrl]) async {
    final body = txt.text.trim();
    final u = uid;
    if (u == null || (body.isEmpty && imageUrl == null) || sending) return;
    _set(() => sending = true);
    try {
      final data = await sb
          .from('messages')
          .insert({
            'conversation_id': id,
            'sender': u,
            'body': body.isEmpty ? null : (body.length > 2000 ? body.substring(0, 2000) : body),
            'image_url': imageUrl,
            'reply_to': reply?.m['id'],
          })
          .select()
          .single();
      final m = Rec.of(data);
      txt.clear();
      buzz('light');
      _set(() {
        sending = false;
        reply = null;
        final cur = msgs ?? <Rec>[];
        if (!cur.any((x) => x.i('id') == m.i('id'))) msgs = [m, ...cur];
      });
    } catch (e) {
      _set(() => sending = false);
      toast(errFa(e), 'err');
    }
  }

  Future<void> _sendImage() async {
    final u = uid;
    if (u == null || sending) return;
    _set(() => sending = true);
    final (url, err) = await pickAndUpload('chat', u, size: 1280);
    _set(() => sending = false);
    if (url == null) {
      if (err != null) toast(err, 'err');
      return;
    }
    await _send(url);
  }

  Future<void> _del(Rec m) async {
    try {
      await sb.from('messages').update({'deleted': true, 'body': null}).eq('id', m.m['id']);
    } catch (e) {
      toast(errFa(e), 'err');
    }
  }

  Future<void> _join() async {
    try {
      await rpc('join_conversation', {'p_conv': id});
      await _loadMeta();
    } catch (e) {
      toast(errFa(e), 'err');
    }
  }

  String _name(String? u) => u == null ? '' : byId[u]?.rec('profiles').str('username') ?? '';

  void _menu(Rec m, bool canPost) {
    if (m.b('deleted')) return;
    final s = m.str('sender');
    showCard<void>(context,
        accent: C.cyan,
        child: (ctx) => SizedBox(
              width: 260,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (canPost)
                  _MenuItem('پاسخ', onTap: () {
                    Navigator.of(ctx).pop();
                    _set(() => reply = m);
                  }),
                if (s != null && s != uid)
                  _MenuItem('مشاهده‌ی پروفایل', onTap: () {
                    Navigator.of(ctx).pop();
                    openPublicProfile(context, s);
                  }),
                if (s == uid)
                  _MenuItem('حذف پیام', color: C.red, onTap: () {
                    Navigator.of(ctx).pop();
                    _del(m);
                  }),
                _MenuItem('انصراف', color: C.dim, onTap: () => Navigator.of(ctx).pop()),
              ]),
            ));
  }

  void _viewImage(String url) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'img',
      barrierColor: const Color(0xd101030c),
      pageBuilder: (ctx, _, _) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Center(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox()))),
      ),
    );
  }

  void _info(Rec c, String? myRole) {
    showSheet<void>(context,
        title: c.str('title') ?? kKindLabel[c.s('kind')] ?? '',
        en: '${c.s('kind').toUpperCase()} INFO',
        height: .85,
        child: (ctx) => _ConvInfo(
              conv: c,
              initial: members,
              myRole: myRole,
              reload: () async {
                await _loadMeta();
                return members;
              },
              onLeft: () {
                Navigator.of(ctx).pop();
                if (mounted) Navigator.of(context).maybePop();
              },
            ));
  }

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    final c = conv;
    final me = uid == null ? null : byId[uid];
    final kind = c?.s('kind') ?? '';
    final peer = kind == 'dm' ? members.where((m) => m.s('user_id') != uid).firstOrNull : null;
    final myRole = me?.s('role');
    final canPost = me != null && (kind != 'channel' || myRole == 'owner' || myRole == 'admin');
    final peerP = peer?.rec('profiles');
    final title = kind == 'dm' ? (peerP?.str('username') ?? 'گفتگو') : (c?.str('title') ?? 'گفتگو');
    final enSub = c == null
        ? null
        : kind == 'dm'
            ? (isOnline(peerP?.str('online_at')) ? 'ONLINE' : 'DIRECT')
            : '${kKindLabel[kind] ?? kind} · ${fa(members.length)} عضو';
    final msgById = {for (final m in msgs ?? <Rec>[]) m.i('id'): m};
    final typers = typing.keys.map(_name).where((s) => s.isNotEmpty).toList();
    final ins = MediaQuery.paddingOf(context);
    final list = msgs;

    Widget? right;
    if (kind == 'dm' && peer != null) {
      right = Press(
          onTap: () => openPublicProfile(context, peer.s('user_id')),
          child: Avatar(avatar: peerP?.str('avatar'), url: peerP?.str('avatar_url'), size: 40, ring: isOnline(peerP?.str('online_at')) ? C.green : C.line));
    } else if (c != null) {
      right = Press(
        onTap: () => _info(c, myRole),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xd9080e28), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
          child: const T('ⓘ', size: 20, color: C.cyan),
        ),
      );
    }

    return Scaffold(
      backgroundColor: C.bg,
      resizeToAvoidBottomInset: true,
      body: Column(children: [
        Header(title: title, en: enSub, onBack: () => Navigator.of(context).maybePop(), right: right),
        Expanded(
          child: list == null
              ? const Center(child: Spinner())
              : list.isEmpty
                  ? Center(child: EmptyState('اولین پیام را بفرست!', icon: ui2('c_mega')))
                  : ListView.builder(
                      controller: scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: list.length + (more ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i >= list.length) return const Padding(padding: EdgeInsets.all(12), child: Center(child: Spinner(size: 20)));
                        final m = list[i];
                        final prev = i + 1 < list.length ? list[i + 1] : null;
                        final s = m.str('sender');
                        final mine = s != null && s == uid;
                        final rt = m.m['reply_to'] == null ? null : msgById[m.i('reply_to')];
                        return _Bubble(
                          key: ValueKey(m.m['id']),
                          m: m,
                          mine: mine,
                          showName: kind != 'dm' && !mine && prev?.str('sender') != s,
                          name: s == null ? '' : (_name(s).isEmpty ? '…' : _name(s)),
                          replyTo: rt,
                          replyName: rt == null ? '' : _name(rt.str('sender')),
                          onLong: () => _menu(m, canPost),
                          onImage: _viewImage,
                        );
                      },
                    ),
        ),
        if (typers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Align(alignment: Alignment.centerRight, child: T('${typers.join('، ')} در حال نوشتن…', size: 11, color: C.cyan, lines: 1)),
          ),
        if (reply != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(color: Color(0xf20a102c), border: Border(top: BorderSide(color: C.line))),
            child: Row(children: [
              Press(onTap: () => _set(() => reply = null), child: const SizedBox(width: 44, height: 44, child: Center(child: T('✕', color: C.dim)))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  T('پاسخ به ${_name(reply!.str('sender'))}', size: 10, color: C.cyan),
                  T(reply!.str('body') ?? '📷 عکس', size: 12, lines: 1),
                ]),
              ),
            ]),
          ),
        if (canPost)
          Container(
            padding: EdgeInsets.fromLTRB(8, 8, 8, ins.bottom > 8 ? ins.bottom : 8),
            decoration: const BoxDecoration(color: Color(0xf5040818), border: Border(top: BorderSide(color: C.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Press(
                onTap: () => _send(),
                disabled: txt.text.trim().isEmpty || sending,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x2e4fe3ff), border: Border.all(color: C.cyan)),
                  child: sending ? const Spinner(size: 20) : Img(ui2('c_mega'), w: 24, h: 24),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: txt,
                  onChanged: _onType,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  cursorColor: C.cyan,
                  style: ts(size: 14, family: F.fa, weight: 500),
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    hintText: 'پیام…',
                    hintTextDirection: TextDirection.rtl,
                    hintStyle: ts(size: 13, color: C.dim2, family: F.fa),
                    filled: true,
                    fillColor: const Color(0xd9060a1e),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: C.line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: C.line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: C.cyan)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Press(
                onTap: _sendImage,
                disabled: sending,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.line)),
                  child: const T('🖼', size: 20),
                ),
              ),
            ]),
          )
        else if (c != null && me == null && c.b('is_public'))
          Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, ins.bottom > 12 ? ins.bottom : 12), child: Btn('پیوستن', colors: G.green, onTap: _join))
        else if (c != null)
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, ins.bottom > 12 ? ins.bottom : 12),
            child: T(kind == 'channel' ? 'فقط مدیران کانال می‌توانند پیام بفرستند' : 'امکان ارسال پیام نیست', size: 12, color: C.dim, align: TextAlign.center),
          ),
      ]),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _MenuItem(this.label, {required this.onTap, this.color = C.text});
  @override
  Widget build(BuildContext context) => Press(
      onTap: onTap,
      scaleTo: .98,
      child: SizedBox(height: 52, child: Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: tBold(label, color: color)))));
}

class _Bubble extends StatelessWidget {
  final Rec m;
  final bool mine, showName;
  final String name, replyName;
  final Rec? replyTo;
  final VoidCallback onLong;
  final ValueChanged<String> onImage;
  const _Bubble({super.key, required this.m, required this.mine, required this.showName, required this.name, required this.replyTo, required this.replyName, required this.onLong, required this.onImage});

  @override
  Widget build(BuildContext context) {
    final deleted = m.b('deleted');
    final img = m.str('image_url');
    final body = m.str('body');
    const r = Radius.circular(16), tail = Radius.circular(4);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Align(
        alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
        child: Press(
          onLong: onLong,
          onTap: img != null && !deleted ? () => onImage(img) : null,
          sound: false,
          haptic: false,
          scaleTo: .98,
          child: Opacity(
            opacity: deleted ? .5 : 1,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 290),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: mine ? const Color(0x294fe3ff) : const Color(0xeb141e46),
                border: Border.all(color: mine ? const Color(0x594fe3ff) : C.line),
                borderRadius: mine ? const BorderRadius.only(topLeft: r, topRight: r, bottomRight: r, bottomLeft: tail) : const BorderRadius.only(topLeft: r, topRight: r, bottomLeft: r, bottomRight: tail),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                if (showName) T(name, size: 10, color: C.cyan, family: F.bold, weight: 800, lines: 1),
                if (replyTo != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.only(right: 6, top: 2, bottom: 2, left: 6),
                    decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(6), border: const Border(right: BorderSide(color: C.cyan, width: 3))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                      T(replyName, size: 10, color: C.cyan),
                      T(replyTo!.b('deleted') ? 'پیام حذف شده' : (replyTo!.str('body') ?? '📷 عکس'), size: 11, color: C.dim, lines: 1),
                    ]),
                  ),
                if (deleted)
                  const T('🚫 این پیام حذف شد', size: 12, color: C.dim)
                else ...[
                  if (img != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Img(img, w: 220, h: 220, fit: BoxFit.cover, radius: 12),
                    ),
                  if (body != null && body.isNotEmpty) T(body, size: 14, height: 1.55, align: TextAlign.right),
                ],
                const SizedBox(height: 2),
                Align(alignment: mine ? Alignment.centerLeft : Alignment.centerRight, child: T(timeAgo(m.str('created_at')), size: 9, color: C.dim2)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Group / channel / club info: about, add member (admins), member list with promote/demote/remove, leave.
class _ConvInfo extends StatefulWidget {
  final Rec conv;
  final List<Rec> initial;
  final String? myRole;
  final Future<List<Rec>> Function() reload;
  final VoidCallback onLeft;
  const _ConvInfo({required this.conv, required this.initial, required this.myRole, required this.reload, required this.onLeft});
  @override
  State<_ConvInfo> createState() => _ConvInfoState();
}

class _ConvInfoState extends State<_ConvInfo> {
  late List<Rec> members = widget.initial;
  final q = TextEditingController();
  List<Rec> found = [];
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    q.addListener(_search);
  }

  @override
  void dispose() {
    _deb?.cancel();
    q.dispose();
    super.dispose();
  }

  void _search() {
    _deb?.cancel();
    final term = q.text.trim();
    if (term.length < 2) {
      if (found.isNotEmpty) setState(() => found = []);
      return;
    }
    _deb = Timer(const Duration(milliseconds: 300), () async {
      try {
        final d = await sb.from('profiles').select('id, username, avatar, avatar_url').ilike('username', '%${term.replaceAll(RegExp(r'[%_]'), '')}%').limit(10);
        if (mounted) setState(() => found = recs(d));
      } catch (_) {}
    });
  }

  Future<void> _act(String u, String a) async {
    try {
      await rpc('manage_member', {'p_conv': widget.conv.s('id'), 'p_user': u, 'p_action': a});
      final m = await widget.reload();
      if (mounted) setState(() => members = m);
      buzz('light');
    } catch (e) {
      toast(errFa(e), 'err');
    }
  }

  Future<void> _leave() async {
    try {
      await rpc('leave_conversation', {'p_conv': widget.conv.s('id')});
      toast('خارج شدی', 'ok');
      widget.onLeft();
    } catch (e) {
      toast(errFa(e), 'err');
    }
  }

  Widget _small(String label, Color color, VoidCallback onTap) =>
      Press(onTap: onTap, child: SizedBox(height: 44, child: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: T(label, size: 11, color: color)))));

  @override
  Widget build(BuildContext context) {
    final c = widget.conv, kind = c.s('kind'), uid = Auth.i.uid, myRole = widget.myRole;
    final admin = myRole == 'owner' || myRole == 'admin';
    final about = c.str('about');
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 48), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
      if (about != null && about.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: T(about, color: C.dim, align: TextAlign.right)),
      if (admin && kind != 'club') ...[
        Field2(q, label: 'افزودن عضو', hint: 'نام کاربری…', ltr: true, maxLength: 20),
        for (final f in found.where((f) => !members.any((m) => m.s('user_id') == f.s('id'))))
          _row([
            Avatar(avatar: f.str('avatar'), url: f.str('avatar_url'), size: 36),
            const SizedBox(width: 8),
            Expanded(child: T(f.s('username'), lines: 1, align: TextAlign.right)),
            _small('افزودن', C.green, () {
              _act(f.s('id'), 'add');
              q.clear();
            }),
          ]),
      ],
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: tBold('اعضا (${fa(members.length)})', size: 16, align: TextAlign.right)),
      for (final m in members)
        Builder(builder: (_) {
          final p = m.rec('profiles'), mu = m.s('user_id'), role = m.s('role');
          return _row([
            Press(onTap: () => openPublicProfile(context, mu), child: Avatar(avatar: p.str('avatar'), url: p.str('avatar_url'), size: 40, ring: isOnline(p.str('online_at')) ? C.green : C.line)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                tBold('${p.s('username', '…')}${mu == uid ? ' (تو)' : ''}', lines: 1),
                if (role != 'member') Badge2(role == 'owner' ? 'مالک' : 'مدیر', color: role == 'owner' ? C.gold : C.cyan),
              ]),
            ),
            if (myRole == 'owner' && mu != uid && kind != 'club') _small(role == 'admin' ? 'برکناری' : 'مدیر کن', C.cyan, () => _act(mu, role == 'admin' ? 'demote' : 'promote')),
            if (admin && mu != uid && role != 'owner' && kind != 'club') _small('حذف', C.red, () => _act(mu, 'remove')),
          ]);
        }),
      if (kind != 'club' && kind != 'dm') Padding(padding: const EdgeInsets.only(top: 16), child: Btn('خروج از گفتگو', small: true, colors: G.red, onTap: _leave)),
    ]);
  }

  // RN uses row-reverse: children listed in visual right-to-left order -> lay out RTL.
  Widget _row(List<Widget> children) => Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x14ffffff), width: .5))),
        child: Row(textDirection: TextDirection.rtl, children: children),
      );
}
