import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../nova_gallery/models/art_asset.dart';
import '../../nova_gallery/ui/nova_composer.dart' show showArtAssetPicker;
import '../models/orbit_models.dart';
import '../../../core/online/online_service.dart';
import '../data/supabase_orbit_repository.dart';
import '../state/orbit_controller.dart';
import 'orbit_call_page.dart';
import 'orbit_bubbles.dart';
import 'orbit_sheets.dart';

/// One conversation (Saved Orbit, group or channel).
class OrbitChatPage extends ConsumerStatefulWidget {
  const OrbitChatPage({super.key, required this.chatId, this.focusMessageId});
  final String chatId;
  final String? focusMessageId;

  @override
  ConsumerState<OrbitChatPage> createState() => _OrbitChatPageState();
}

class _OrbitChatPageState extends ConsumerState<OrbitChatPage> {
  late final OrbitController _ctrl = ref.read(orbitControllerProvider);
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  OrbitMessage? _replyTo;
  OrbitMessage? _editing;
  bool _emoji = false;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _ctrl.openChat(widget.chatId);
    _text.addListener(_onText);
  }

  void _onText() => setState(() {});

  @override
  void dispose() {
    _ctrl.closeChat(widget.chatId);
    _text.removeListener(_onText);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _insertEmoji(String e) {
    final String t = _text.text;
    final TextSelection sel = _text.selection;
    final int start = sel.isValid ? sel.start : t.length;
    final int end = sel.isValid ? sel.end : t.length;
    final String nt = t.replaceRange(start, end, e);
    _text.value = TextEditingValue(
        text: nt, selection: TextSelection.collapsed(offset: start + e.length));
  }

  Future<void> _afterSend() async {
    final profile = ref.read(profileProvider);
    final AwardOutcome outcome = await _ctrl.reward(profile);
    if (ref.read(settingsProvider).haptics) HapticFeedback.selectionClick();
    if (!mounted) return;
    await showAwardOutcome(context, outcome);
  }

  Future<void> _send() async {
    final String t = _text.text.trim();
    if (t.isEmpty) return;
    final editing = _editing;
    if (editing != null) {
      await _ctrl.edit(widget.chatId, editing.id, t);
      setState(() {
        _editing = null;
        _text.clear();
      });
      return;
    }
    final String name = orbitMyName(context, ref.read(profileProvider));
    final String? replyId = _replyTo?.id;
    _text.clear();
    setState(() => _replyTo = null);
    await _ctrl.send(widget.chatId,
        authorName: name, text: t, replyToId: replyId);
    await _afterSend();
  }

  Future<void> _attach() async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(
            leading: const Icon(Icons.collections_rounded,
                color: NxColors.turquoise),
            title: Text(c.tx('اثر هنری NEXORA', 'NEXORA art')),
            subtitle: Text(
                c.tx('از کتابخانه‌ی هنری اپ', "From the app's art library")),
            onTap: () => Navigator.of(c).pop('art'),
          ),
          ListTile(
            leading: Icon(Icons.sports_esports_rounded,
                color: WorldPalette.arcade.primary),
            title: Text(c.tx('دعوت به آرکید', 'Invite to Arcade')),
            onTap: () => Navigator.of(c).pop('invite'),
          ),
          ListTile(
            leading: Icon(Icons.move_to_inbox_rounded,
                color: WorldPalette.nova.primary),
            title: Text(c.tx('از صندوق اشتراک (${_ctrl.inboxItems.length})',
                'From share inbox (${_ctrl.inboxItems.length})')),
            onTap: () => Navigator.of(c).pop('inbox'),
          ),
          ListTile(
            leading:
                const Icon(Icons.perm_media_rounded, color: NxColors.textDim),
            title: Text(c.tx('عکس، ویدئو، فایل، پیام صوتی',
                'Photo, video, file, voice note')),
            subtitle: Text(c.tx('بعد از اتصال سرور (آپلود امن)',
                'After the server connects (secure upload)')),
            onTap: () => Navigator.of(c).pop('media'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    final String name = orbitMyName(context, ref.read(profileProvider));
    switch (choice) {
      case 'art':
        final ArtAsset? a = await showArtAssetPicker(context);
        if (a == null) return;
        final String caption = _text.text.trim();
        _text.clear();
        await _ctrl.send(widget.chatId,
            authorName: name,
            kind: OrbitMessageKind.art,
            text: caption,
            payload: <String, dynamic>{'asset': a.ref});
        await _afterSend();
        break;
      case 'invite':
        final String? g = await showArcadeGamePicker(context);
        if (g == null) return;
        final OrbitChat? target = _ctrl.chatById(widget.chatId);
        final client = ref.read(onlineProvider).client;
        if (target != null && target.online && client != null) {
          // A real private room; the card lets every member join it.
          try {
            final dynamic r =
                await client.rpc('nx_create_room', params: <String, dynamic>{
              'p_game': g,
              'p_seats': 10,
              'p_private': true,
              'p_quick': false,
              'p_settings': <String, dynamic>{},
            });
            final String code = '${(r as Map)['code']}';
            await _ctrl.send(widget.chatId,
                authorName: name,
                kind: OrbitMessageKind.invite,
                payload: <String, dynamic>{'gameId': g, 'code': code});
            await _afterSend();
            if (mounted) context.push('/online/$g?code=$code');
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(context.tx('ساخت اتاق آنلاین ممکن نشد.',
                      'Could not create the online room.'))));
            }
          }
          break;
        }
        await _ctrl.send(widget.chatId,
            authorName: name,
            kind: OrbitMessageKind.invite,
            payload: <String, dynamic>{'gameId': g});
        await _afterSend();
        break;
      case 'inbox':
        if (!mounted) return;
        await showSharedInbox(context, chatId: widget.chatId);
        break;
      case 'media':
        if (!mounted) return;
        await showOrbitOnlineOnly(context,
            fa: 'ارسال رسانه و پیام صوتی',
            en: 'Sending media and voice notes',
            icon: Icons.attach_file_rounded);
        break;
    }
  }

  void _call(OrbitChat chat, {required bool video}) {
    if (!chat.online) {
      showOrbitOnlineOnly(context,
          fa: video ? 'تماس تصویری' : 'تماس صوتی',
          en: video ? 'Video calls' : 'Voice calls',
          icon: video ? Icons.videocam_rounded : Icons.call_rounded);
      return;
    }
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext c) => OrbitCallPage(
          chatId: chat.id, title: orbitChatTitle(c, chat), video: video),
    ));
  }

  Future<void> _addMembers(BuildContext cc, OrbitChat chat) async {
    final Set<String> picked = <String>{};
    final Set<String> already =
        (await _ctrl.members(chat.id)).map((OrbitMember m) => m.id).toSet();
    if (!cc.mounted) return;
    final bool? ok = await showModalBottomSheet<bool>(
      context: cc,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext b) => StatefulBuilder(
        builder: (BuildContext b2, StateSetter set) => SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.lg),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OrbitFriendPicker(
                    selected: picked,
                    exclude: already,
                    onChanged: () => set(() {})),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed:
                      picked.isEmpty ? null : () => Navigator.pop(b2, true),
                  child: Text(b2.tx(
                      'افزودن (${picked.length})', 'Add (${picked.length})')),
                ),
              ]),
        ),
      ),
    );
    if (ok == true) {
      try {
        await _ctrl.addMembers(chat.id, picked.toList());
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(context.tx('فقط مدیران می‌توانند عضو اضافه کنند.',
                  'Only admins can add members.'))));
        }
      }
    }
  }

  Future<void> _actions(OrbitMessage m, bool mine) async {
    if (m.kind == OrbitMessageKind.system) return;
    final String? a = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (!m.deleted)
            ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(c.tx('پاسخ', 'Reply')),
                onTap: () => Navigator.pop(c, 'reply')),
          if (mine && m.editable)
            ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text(c.tx('ویرایش', 'Edit')),
                onTap: () => Navigator.pop(c, 'edit')),
          if (!m.deleted && m.text.isNotEmpty)
            ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(c.tx('کپی', 'Copy')),
                onTap: () => Navigator.pop(c, 'copy')),
          if (!m.deleted)
            ListTile(
              leading: const Icon(Icons.push_pin_rounded),
              title: Text(m.pinned
                  ? c.tx('برداشتن سنجاق', 'Unpin')
                  : c.tx('سنجاق کردن', 'Pin')),
              onTap: () => Navigator.pop(c, 'pin'),
            ),
          if (!m.deleted)
            ListTile(
              leading: const Icon(Icons.star_rounded),
              title: Text(m.starred
                  ? c.tx('برداشتن ستاره', 'Unstar')
                  : c.tx('ستاره‌دار کردن', 'Star')),
              onTap: () => Navigator.pop(c, 'star'),
            ),
          if (mine && !m.deleted)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: NxColors.danger),
              title: Text(c.tx('حذف', 'Delete'),
                  style: const TextStyle(color: NxColors.danger)),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
        ]),
      ),
    );
    if (a == null || !mounted) return;
    switch (a) {
      case 'reply':
        setState(() {
          _replyTo = m;
          _editing = null;
        });
        _focus.requestFocus();
        break;
      case 'edit':
        setState(() {
          _editing = m;
          _replyTo = null;
          _text.text = m.text;
        });
        _focus.requestFocus();
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.text));
        break;
      case 'pin':
        await _ctrl.togglePin(widget.chatId, m.id);
        break;
      case 'star':
        await _ctrl.toggleStar(widget.chatId, m.id);
        break;
      case 'delete':
        await _ctrl.delete(widget.chatId, m.id);
        break;
    }
  }

  void _showPinned(List<OrbitMessage> pinned) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext c) =>
          ListView(shrinkWrap: true, children: <Widget>[
        Center(
            child: Text(c.tx('پیام‌های سنجاق‌شده', 'Pinned messages'),
                style: const TextStyle(fontWeight: FontWeight.w900))),
        for (final OrbitMessage m in pinned.reversed)
          ListTile(
            leading: const Icon(Icons.push_pin_rounded, color: NxColors.gold),
            title: Text(m.preview(fa: c.isFa),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${m.authorName} · ${orbitTime(m.createdAt)}'),
            trailing: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _ctrl.togglePin(widget.chatId, m.id);
                Navigator.of(c).pop();
              },
            ),
          ),
      ]),
    );
  }

  Future<void> _info(OrbitChat chat) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext c) =>
          Consumer(builder: (BuildContext cc, WidgetRef ref, Widget? _) {
        final ctrl = ref.watch(orbitControllerProvider);
        final OrbitChat? live = ctrl.chatById(chat.id);
        if (live == null) return const SizedBox(height: 120);
        final profile = ref.watch(profileProvider);
        return SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.lg),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(child: OrbitChatAvatar(chat: live, size: 84)),
                const SizedBox(height: 8),
                Text(orbitChatTitle(cc, live),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 20)),
                if (live.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(live.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: NxColors.textDim)),
                  ),
                if (live.isSaved)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      cc.tx(
                          'یادداشت‌ها، لینک‌ها و اشتراک‌های خودت. فقط روی دستگاه تو.',
                          'Your own notes, links and shares. Only on your device.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: NxColors.textDim),
                    ),
                  ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: live.pinned,
                  title: Text(cc.tx('سنجاق در بالای فهرست', 'Pin to top')),
                  onChanged: (bool v) {
                    live.pinned = v;
                    ctrl.updateChat(live);
                  },
                ),
                SwitchListTile(
                  value: live.muted,
                  title: Text(cc.tx('بی‌صدا', 'Mute')),
                  onChanged: (bool v) {
                    live.muted = v;
                    ctrl.updateChat(live);
                  },
                ),
                if (!live.isSaved) ...<Widget>[
                  const Divider(),
                  Text(cc.tx('اعضا', 'Members'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (live.online)
                    FutureBuilder<List<OrbitMember>>(
                      future: ctrl.members(live.id),
                      builder: (BuildContext fc,
                          AsyncSnapshot<List<OrbitMember>> snap) {
                        final List<OrbitMember> mem =
                            snap.data ?? const <OrbitMember>[];
                        if (!snap.hasData) {
                          return const Padding(
                              padding: EdgeInsets.all(12),
                              child:
                                  Center(child: CircularProgressIndicator()));
                        }
                        return Column(children: <Widget>[
                          for (final OrbitMember m in mem)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(
                                m.role == 'owner'
                                    ? Icons.verified_user_rounded
                                    : (m.role == 'admin'
                                        ? Icons.shield_rounded
                                        : Icons.person_rounded),
                                color: m.role == 'member'
                                    ? NxColors.textDim
                                    : NxColors.gold,
                              ),
                              title: Text(m.id == ctrl.ownerId
                                  ? '${m.name} (${fc.tx('تو', 'you')})'
                                  : m.name),
                              subtitle: Text(m.role == 'owner'
                                  ? fc.tx('مالک', 'Owner')
                                  : (m.role == 'admin'
                                      ? fc.tx('مدیر', 'Admin')
                                      : fc.tx('عضو', 'Member'))),
                              trailing: m.onlineNow
                                  ? const Icon(Icons.circle,
                                      size: 10, color: NxColors.success)
                                  : null,
                              onLongPress: live.role == 'owner' &&
                                      m.role != 'owner' &&
                                      !live.isDirect
                                  ? () async {
                                      await ctrl.online?.setRole(
                                          live.id,
                                          m.id,
                                          m.role == 'admin'
                                              ? 'member'
                                              : 'admin');
                                      await ctrl.refresh();
                                    }
                                  : null,
                            ),
                        ]);
                      },
                    )
                  else ...<Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.verified_user_rounded,
                          color: NxColors.gold),
                      title: Text(orbitMyName(cc, profile)),
                      subtitle: Text(cc.tx('مالک · ${profile.explorerId}',
                          'Owner · ${profile.explorerId}')),
                    ),
                    const OnlineOnlyNotice(
                        featureFa: 'دعوت دوستان به این گفت‌وگو',
                        featureEn: 'Inviting friends to this chat'),
                  ],
                  if (live.online &&
                      !live.isDirect &&
                      (live.isAdmin || !live.isChannel))
                    OutlinedButton.icon(
                      onPressed: () => _addMembers(cc, live),
                      icon: const Icon(Icons.group_add_rounded),
                      label: Text(cc.tx('افزودن دوستان', 'Add friends')),
                    ),
                  const SizedBox(height: 10),
                  if (!live.isDirect && (!live.online || live.isAdmin))
                    OutlinedButton.icon(
                      onPressed: () async {
                        await showOrbitChatEditor(cc,
                            kind: live.kind, editing: live);
                      },
                      icon: const Icon(Icons.edit_rounded),
                      label: Text(cc.tx('ویرایش نام، توضیحات و نشان',
                          'Edit name, description and badge')),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: NxColors.danger),
                    onPressed: () async {
                      final bool? ok = await showDialog<bool>(
                        context: cc,
                        builder: (BuildContext d) => AlertDialog(
                          title: Text(live.online && live.role != 'owner'
                              ? d.tx('ترک گفت‌وگو؟', 'Leave chat?')
                              : d.tx('حذف گفت‌وگو؟', 'Delete chat?')),
                          content: Text(!live.online
                              ? d.tx(
                                  'همه‌ی پیام‌های آن از این دستگاه پاک می‌شود.',
                                  'All its messages are removed from this device.')
                              : (live.role == 'owner' && !live.isDirect
                                  ? d.tx('گفت‌وگو برای همه‌ی اعضا حذف می‌شود.',
                                      'The chat is deleted for every member.')
                                  : d.tx('از این گفت‌وگو خارج می‌شوی.',
                                      'You leave this chat.'))),
                          actions: <Widget>[
                            TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: Text(d.tx('انصراف', 'Cancel'))),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: NxColors.danger),
                              onPressed: () => Navigator.pop(d, true),
                              child: Text(d.tx('حذف', 'Delete')),
                            ),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      await ctrl.deleteChat(live.id);
                      if (cc.mounted) Navigator.of(cc).pop();
                      if (mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: Text(cc.tx('حذف گفت‌وگو', 'Delete chat')),
                  ),
                ],
              ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(orbitControllerProvider);
    final OrbitChat? chat = ctrl.chatById(widget.chatId);
    final NxThemeColors visual = NxThemeColors.of(context);
    if (chat == null) {
      return Scaffold(
        backgroundColor: visual.background,
        body: Center(child: CircularProgressIndicator(color: visual.accent)),
      );
    }
    final String me = ctrl.ownerId;
    final List<OrbitMessage> all = ctrl.messagesOf(widget.chatId);
    final List<OrbitMessage> pinned =
        all.where((OrbitMessage m) => m.pinned && !m.deleted).toList();
    final List<OrbitMessage> shown = _searching && _query.trim().isNotEmpty
        ? all
            .where((OrbitMessage m) =>
                m.kind != OrbitMessageKind.system &&
                m
                    .preview(fa: context.isFa)
                    .toLowerCase()
                    .contains(_query.toLowerCase()))
            .toList()
        : all;
    final bool canPost = chat.canPost(me);

    return Scaffold(
      backgroundColor: visual.background,
      appBar: AppBar(
        backgroundColor: visual.surfaceRaised.withValues(alpha: 0.98),
        titleSpacing: 0,
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText:
                      context.tx('جستجو در این گفت‌وگو…', 'Search this chat…'),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (String v) => setState(() => _query = v),
              )
            : InkWell(
                onTap: () => _info(chat),
                child: Row(children: <Widget>[
                  OrbitChatAvatar(chat: chat, size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(orbitChatTitle(context, chat),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          Text(
                            chat.isSaved
                                ? context.tx('فقط تو · روی همین دستگاه',
                                    'Only you · on this device')
                                : chat.isDirect
                                    ? (chat.peerOnlineNow
                                        ? context.tx('آنلاین', 'online')
                                        : context.tx(
                                            'گفت‌وگوی خصوصی', 'Private chat'))
                                    : !chat.online
                                        ? (chat.isChannel
                                            ? context.tx(
                                                'کانال · ۱ عضو (آفلاین)',
                                                'Channel · 1 member (offline)')
                                            : context.tx(
                                                'گروه · ۱ عضو (آفلاین)',
                                                'Group · 1 member (offline)'))
                                        : (chat.isChannel
                                            ? context.tx(
                                                'کانال · ${chat.memberCount} عضو',
                                                'Channel · ${chat.memberCount} members')
                                            : context.tx(
                                                'گروه · ${chat.memberCount} عضو',
                                                'Group · ${chat.memberCount} members')),
                            style: const TextStyle(
                                fontSize: 11, color: NxColors.textDim),
                          ),
                        ]),
                  ),
                ]),
              ),
        actions: <Widget>[
          IconButton(
            tooltip: context.tx('جستجو', 'Search'),
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              _query = '';
            }),
          ),
          if (!chat.isSaved && !_searching) ...<Widget>[
            IconButton(
              tooltip: context.tx('تماس صوتی', 'Voice call'),
              icon: const Icon(Icons.call_rounded),
              onPressed: () => _call(chat, video: false),
            ),
            IconButton(
              tooltip: context.tx('تماس تصویری', 'Video call'),
              icon: const Icon(Icons.videocam_rounded),
              onPressed: () => _call(chat, video: true),
            ),
          ],
        ],
      ),
      body: NxBrandBackground(
        child: Column(children: <Widget>[
          if (pinned.isNotEmpty && !_searching)
            Material(
              color: visual.surface.withValues(alpha: 0.92),
              child: InkWell(
                onTap: () => _showPinned(pinned),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(children: <Widget>[
                    const Icon(Icons.push_pin_rounded,
                        size: 16, color: NxColors.gold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(pinned.last.preview(fa: context.isFa),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (pinned.length > 1)
                      NxPill(label: '${pinned.length}', color: NxColors.gold),
                  ]),
                ),
              ),
            ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(NxSpace.lg),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            OracleAvatar(
                                pose: _searching ? 'confused' : 'hero_wave',
                                size: 96),
                            const SizedBox(height: 10),
                            GlassPanel(
                              child: Text(
                                _searching
                                    ? context.tx('پیامی با این متن پیدا نشد.',
                                        'No message matches.')
                                    : (chat.isSaved
                                        ? context.tx(
                                            'مدار ذخیره، دفترچه‌ی شخصی توست: یادداشت بنویس، اثر هنری بفرست یا پست‌های Nova را اینجا نگه دار.',
                                            'Saved Orbit is your personal notebook: write notes, send art or keep Nova posts here.')
                                        : context.tx('اولین پیام را بفرست.',
                                            'Send the first message.')),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ]),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: shown.length,
                    itemBuilder: (BuildContext c, int i) {
                      final OrbitMessage m = shown[shown.length - 1 - i];
                      final bool mine = m.authorId == me;
                      return OrbitMessageBubble(
                        key: ValueKey<String>(m.id),
                        message: m,
                        mine: mine,
                        highlight: _searching ? _query : '',
                        replyTo: ctrl.messageById(widget.chatId, m.replyToId),
                        onLongPress: () => _actions(m, mine),
                      );
                    },
                  ),
          ),
          if (canPost) _composer(context) else _readOnlyBar(context),
        ]),
      ),
    );
  }

  Widget _readOnlyBar(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
              context.tx('در این کانال فقط مدیران منتشر می‌کنند.',
                  'Only admins can post in this channel.'),
              style: const TextStyle(color: NxColors.textDim)),
        ),
      );

  Widget _composer(BuildContext context) {
    final pal = WorldPalette.orbit;
    final NxThemeColors visual = NxThemeColors.of(context);
    final OrbitMessage? quote = _editing ?? _replyTo;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: visual.surfaceRaised.withValues(alpha: 0.98),
          border: Border(
              top: BorderSide(color: visual.border.withValues(alpha: 0.62))),
        ),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (quote != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 4, 6),
              child: Row(children: <Widget>[
                Icon(
                    _editing != null ? Icons.edit_rounded : Icons.reply_rounded,
                    size: 18,
                    color: pal.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                            _editing != null
                                ? context.tx('ویرایش پیام', 'Editing message')
                                : quote.authorName,
                            style: TextStyle(
                                color: pal.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12)),
                        Text(quote.preview(fa: context.isFa),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: NxColors.textDim, fontSize: 12)),
                      ]),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() {
                    if (_editing != null) _text.clear();
                    _editing = null;
                    _replyTo = null;
                  }),
                ),
              ]),
            ),
          AnimatedSize(
            duration: NxMotion.fast,
            child: _emoji
                ? SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: <Widget>[
                        for (final String e in kOrbitEmoji)
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _insertEmoji(e),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              child:
                                  Text(e, style: const TextStyle(fontSize: 24)),
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
            IconButton(
              tooltip: context.tx('شکلک', 'Emoji'),
              icon: Icon(
                  _emoji
                      ? Icons.keyboard_rounded
                      : Icons.emoji_emotions_rounded,
                  color: pal.primary),
              onPressed: () => setState(() => _emoji = !_emoji),
            ),
            IconButton(
              tooltip: context.tx('پیوست', 'Attach'),
              icon: Icon(Icons.add_circle_rounded, color: pal.primary),
              onPressed: _editing == null ? _attach : null,
            ),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                minLines: 1,
                maxLines: 5,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  hintText: context.tx('پیام…', 'Message…'),
                ),
              ),
            ),
            const SizedBox(width: 4),
            AnimatedScale(
              duration: NxMotion.fast,
              scale: _text.text.trim().isEmpty ? 0.85 : 1,
              child: IconButton.filled(
                style: IconButton.styleFrom(
                    backgroundColor: visual.accent,
                    foregroundColor: visual.background),
                onPressed: _text.text.trim().isEmpty ? null : _send,
                icon: Icon(_editing != null
                    ? Icons.check_rounded
                    : Icons.send_rounded),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
