// Port of src/online/Lobby.tsx + Hub.tsx: room lobby (seats, spectators, ready/start, auto-start countdown for
// quick/arena rooms, host settings + kick, chat, voice, share code) and the online hub (profile strip, quick
// match 1v1/2v2/3v3, shortcuts, create room, join by code, live room list).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../net/auth.dart';
import '../net/discs.dart';
import '../net/supabase.dart';
import '../oracle/oracle.dart';
import '../screens/team.dart' show StatBars;
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'link.dart';
import 'online_match.dart' show ruleLabel;
import 'room_ui.dart';
import 'ui.dart';

const kModesOnline = ['1v1', '2v2', '3v3'];
const kModeFa = {'1v1': 'تک به تک', '2v2': '۲ به ۲', '3v3': '۳ به ۳'};
const kKindFa = {'casual': ('دوستانه', C.green), 'quick': ('سریع', C.cyan), 'arena': ('آرنا', C.violet), 'tournament': ('تورنمنت', C.orange)};
const kRules = [('g3', 'تا ۳ گل'), ('g5', 'تا ۵ گل'), ('t3', '۳ دقیقه'), ('t5', '۵ دقیقه')];
Map<String, dynamic> ruleToSettings(String r) => r == 'g3' ? {'goals': 3, 'time': 0} : r == 'g5' ? {'goals': 5, 'time': 0} : r == 't5' ? {'goals': 3, 'time': 300} : {'goals': 3, 'time': 180};
String settingsToRule(Rec s) => s.d('time') >= 300 ? 't5' : s.d('time') > 0 ? 't3' : s.i('goals', 3) >= 5 ? 'g5' : 'g3';

// =============================================================== lobby
class LobbyScreen extends StatefulWidget {
  final RoomLink link;
  final VoidCallback onLeave, onWatch;
  const LobbyScreen({super.key, required this.link, required this.onLeave, required this.onWatch});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  RoomLink get link => widget.link;
  String? busy;
  int count = 0;
  Timer? _cd;
  bool _auto = false;

  Future<void> run(String key, Future<void> Function() fn, [String? ok]) async {
    if (busy != null) return;
    setState(() => busy = key);
    try {
      await fn();
      link.ping();
      await link.refresh();
      if (ok != null) toast(ok, 'ok');
    } catch (e) {
      toast(errFa(e), 'err');
      buzz('heavy');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  void dispose() {
    _cd?.cancel();
    super.dispose();
  }

  void _checkAuto(bool auto, bool isHost) {
    if (auto == _auto) return;
    _auto = auto;
    _cd?.cancel();
    if (!auto) {
      if (count != 0) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() => count = 0) : null);
      return;
    }
    var n = 3;
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() => count = n) : null);
    sfx(Snd.tick);
    buzz();
    _cd = Timer.periodic(const Duration(seconds: 1), (t) {
      n--;
      if (n > 0) {
        setState(() => count = n);
        sfx(Snd.tick);
        buzz();
        return;
      }
      t.cancel();
      setState(() => count = 0);
      final room = link.room;
      if (isHost && room != null) run('start', () async => rpc('start_match', {'p_room': room.s('id')}));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([link, link.voice]),
      builder: (context, _) {
        final room = link.room;
        if (room == null) return const Scaffold(backgroundColor: C.bg, body: Center(child: Spinner(size: 36)));
        final me = link.me, n = teamSize(room.s('mode', '1v1'));
        final seats = [List<Rec?>.filled(n, null), List<Rec?>.filled(n, null)];
        for (final p in link.players) {
          final t = p.i('team', -1), sl = p.m['slot'] is num ? p.i('slot') : -1;
          if (p.s('role') == 'player' && (t == 0 || t == 1) && sl >= 0 && sl < n) seats[t][sl] = p;
        }
        final specs = link.players.where((p) => p.s('role') == 'spectator').toList();
        final meP = link.players.where((p) => p.s('user_id') == me).firstOrNull;
        final isHost = room.s('host') == me, amPlayer = meP?.s('role') == 'player';
        final full = seats[0].every((x) => x != null) && seats[1].every((x) => x != null);
        final notReady = link.players.where((p) => p.s('role') == 'player' && !p.b('ready') && p.s('user_id') != room.s('host')).toList();
        final playing = room.s('status') == 'playing';
        final block = link.protoBlock; // v4: protocol version mismatch -> no start
        final canStart = isHost && full && notReady.isEmpty && room.s('status') == 'waiting' && block == null;
        final kind = room.s('kind', 'casual');
        _checkAuto((kind == 'quick' || kind == 'arena') && room.s('status') == 'waiting' && full && notReady.isEmpty && block == null, isHost);
        final speaking = link.voice.speaking.toSet();
        final reason = block ?? (!full ? 'منتظر پر شدن جایگاه‌ها…' : notReady.isNotEmpty ? 'منتظر آماده شدن ${fa(notReady.length)} بازیکن…' : '');
        final ins = MediaQuery.paddingOf(context);
        return Scaffold(
          backgroundColor: C.bg,
          body: Stack(children: [
            const Space(theme: SpaceTheme.base, dim: .2),
            Column(children: [
              Header(title: room.s('name'), en: 'LOBBY · ${room.s('mode').toUpperCase()}', onBack: widget.onLeave, right: PingBadge(link: link)),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 150), children: [
                  if (block != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Panel(accent: C.red, child: Row(textDirection: TextDirection.rtl, children: [
                        const Icon(Icons.system_update, color: C.red, size: 26),
                        const SizedBox(width: 10),
                        Expanded(child: T(block, size: 12, color: Colors.white, align: TextAlign.right)),
                      ])),
                    ),
                  Panel(
                    accent: C.cyan,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(textDirection: TextDirection.rtl, children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const T('کد اتاق', size: 11, color: C.dim), T(room.s('code'), size: 24, family: F.title, weight: 900, spacing: 4, color: C.cyan)])),
                        _small('کپی', () async {
                          await Clipboard.setData(ClipboardData(text: room.s('code')));
                          toast('کد اتاق کپی شد', 'ok');
                        }),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(textDirection: TextDirection.rtl, runSpacing: 4, children: [
                        Badge2(ruleLabel(room.rec('settings')), color: C.violet),
                        Badge2(kFields[room.rec('settings').i('field').clamp(0, kFields.length - 1)].name, color: C.sky),
                        Badge2(room.b('ranked') ? 'رتبه‌ای' : 'دوستانه', color: room.b('ranked') ? C.gold : C.green),
                        if (room.b('is_private')) const Badge2('خصوصی', color: C.pink),
                        if (room.str('tournament_match_id') != null) const Badge2('تورنمنت', color: C.orange),
                        if (playing) const Badge2('در حال بازی', color: C.red, live: true),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Row(textDirection: TextDirection.rtl, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var t = 0; t < 2; t++) ...[
                      if (t == 1) const SizedBox(width: 8),
                      Expanded(
                        child: Column(children: [
                          Container(
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: (t == 0 ? C.cyan : C.red).withValues(alpha: .4)), color: (t == 0 ? C.cyan : C.red).withValues(alpha: .12)),
                            child: tBold(t == 0 ? 'تیم آبی' : 'تیم قرمز', size: 14, color: t == 0 ? C.cyan : C.red),
                          ),
                          for (var i = 0; i < n; i++)
                            seats[t][i] != null
                                ? _Seat(p: seats[t][i]!, team: link.teamFor(seats[t][i]!.s('user_id')), me: me, host: room.s('host'), online: link.online.containsKey(seats[t][i]!.s('user_id')), talking: speaking.contains(seats[t][i]!.s('user_id')),
                                    color: t == 0 ? C.cyan : C.red, canKick: isHost && seats[t][i]!.s('user_id') != me && !playing,
                                    onKick: () => run('kick', () async => rpc('kick', {'p_room': room.s('id'), 'p_user': seats[t][i]!.s('user_id')}), 'بازیکن اخراج شد'))
                                : Press(
                                    onTap: playing || busy != null ? null : () => run('seat$t$i', () async => rpc('take_seat', {'p_room': room.s('id'), 'p_team': t, 'p_slot': i})),
                                    child: Container(
                                      height: 64,
                                      margin: const EdgeInsets.only(top: 8),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                                      child: busy == 'seat$t$i' ? const Spinner(size: 20) : const T('+ نشستن', size: 12, color: C.dim),
                                    ),
                                  ),
                        ]),
                      ),
                    ],
                  ]),
                  Panel(
                    margin: const EdgeInsets.only(top: 12),
                    accent: Colors.transparent,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(textDirection: TextDirection.rtl, children: [
                        Expanded(child: tBold('تماشاگرها (${fa(specs.length)})', size: 12)),
                        if (amPlayer && !playing) _small('فقط تماشا', () => run('spec', () async => rpc('spectate', {'p_room': room.s('id')}))),
                      ]),
                      const SizedBox(height: 6),
                      specs.isEmpty
                          ? const T('کسی تماشا نمی‌کند', size: 11, color: C.dim2, align: TextAlign.right)
                          : SizedBox(
                              height: 62,
                              child: ListView(scrollDirection: Axis.horizontal, reverse: true, children: [
                                for (final p in specs)
                                  SizedBox(
                                      width: 64,
                                      child: Column(children: [
                                        Avatar(avatar: p.rec('profiles').str('equipped_disc'), url: p.rec('profiles').str('avatar_url'), size: 40, ring: speaking.contains(p.s('user_id')) ? C.green : C.dim2, dim: !link.online.containsKey(p.s('user_id'))),
                                        T(p.rec('profiles').s('username', '…'), size: 10, color: C.dim, lines: 1),
                                      ])),
                              ]),
                            ),
                    ]),
                  ),
                  Panel(
                    margin: const EdgeInsets.only(top: 12),
                    accent: Colors.transparent,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [tBold('چت صوتی', size: 12, align: TextAlign.right), const SizedBox(height: 8), VoiceBar(link: link, enabled: room.b('voice'))]),
                  ),
                  Press(
                    onTap: () => showSheet(context, title: 'گفتگو', en: 'ROOM CHAT', height: .72, child: (_) => ChatPanel(link: link)),
                    scaleTo: .98,
                    child: Panel(
                      margin: const EdgeInsets.only(top: 12),
                      accent: Colors.transparent,
                      child: Row(textDirection: TextDirection.rtl, children: [
                        Img(ui2('c_bell'), w: 32, h: 32),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            tBold('گفتگوی اتاق', size: 12),
                            T(link.chat.isNotEmpty ? '${link.chat.last.name}: ${link.chat.last.text}' : 'برای نوشتن پیام لمس کن', size: 11, color: C.dim, lines: 1),
                          ]),
                        ),
                        if (link.unread > 0)
                          Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(10)),
                              child: tBold(fa(link.unread.clamp(0, 99)), size: 10, color: Colors.white)),
                      ]),
                    ),
                  ),
                  if (isHost && !playing && room.str('tournament_match_id') == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Btn('تنظیمات اتاق', small: true, colors: G.dark, onTap: () => showSheet(context, title: 'تنظیمات اتاق', en: 'ROOM SETTINGS', height: .8, child: (ctx) => _RoomSettings(link: link))),
                    ),
                ]),
              ),
            ]),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 20, 16, ins.bottom < 12 ? 12 : ins.bottom),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x0002040e), Color(0xeb02040e), Color(0xfa02040e)])),
                child: playing
                    ? Btn('ورود به بازی زنده', colors: G.red, onTap: widget.onWatch)
                    : (kind == 'quick' || kind == 'arena')
                        ? tBold(full ? 'آماده‌ی شروع…' : 'در جستجوی حریف… (${fa(link.players.where((p) => p.s('role') == 'player').length)}/${fa(n * 2)})', size: 14, color: C.cyan, align: TextAlign.center)
                        : isHost
                            ? Column(mainAxisSize: MainAxisSize.min, children: [
                                if (reason.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: T(reason, size: 11, color: C.dim)),
                                Btn(busy == 'start' ? 'در حال شروع…' : 'شروع بازی',
                                    disabled: !canStart || busy != null, colors: canStart ? G.gold : G.dark, onTap: () => run('start', () async {
                                          await rpc('start_match', {'p_room': room.s('id')});
                                          buzz('heavy');
                                        })),
                              ])
                            : amPlayer
                                ? Btn(meP!.b('ready') ? 'آماده‌ام ✓' : 'اعلام آمادگی', colors: meP.b('ready') ? G.green : G.primary, disabled: busy != null, onTap: () => run('ready', () async {
                                      await rpc('set_ready', {'p_room': room.s('id'), 'p_ready': !meP.b('ready')});
                                      sfx(Snd.ready);
                                      buzz('medium');
                                    }))
                                : const T('برای بازی روی یک جایگاه خالی بزن', size: 12, color: C.dim, align: TextAlign.center),
              ),
            ),
            if (count > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: const Color(0x8802040e),
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        tTitle(fa(count), size: 96, shadows: const [Shadow(color: C.cyan, blurRadius: 30)]),
                        tBold('بازی شروع می‌شود', size: 16, color: C.cyan),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }

  Widget _small(String l, VoidCallback on) => Press(
      onTap: on,
      child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line), color: const Color(0xcc0a1030)),
          child: tBold(l, size: 12)));
}

class _Seat extends StatelessWidget {
  final Rec p;
  final String me, host;
  final String? team; // v4: presence-advertised team (local selection), wins over the server disc
  final bool online, talking, canKick;
  final Color color;
  final VoidCallback onKick;
  const _Seat({required this.p, this.team, required this.me, required this.host, required this.online, required this.talking, required this.color, required this.canKick, required this.onKick});
  @override
  Widget build(BuildContext context) {
    final isHost = p.s('user_id') == host, pr = p.rec('profiles');
    final st = Discs.i.stats(team ?? p.str('disc_id') ?? pr.str('equipped_disc'));
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xd10a0e28), borderRadius: BorderRadius.circular(14), border: Border.all(color: talking ? C.green : p.s('user_id') == me ? color : C.line)),
      child: Row(textDirection: TextDirection.rtl, children: [
        Stack(children: [
          Avatar(avatar: team ?? pr.str('equipped_disc') ?? pr.str('avatar'), url: team != null ? null : pr.str('avatar_url'), size: 40, ring: talking ? C.green : color, dim: !online),
          Positioned(bottom: 0, left: 0, child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? C.green : C.dim2, border: Border.all(color: C.bg, width: 1.5)))),
        ]),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            tBold('${isHost ? '👑 ' : ''}${pr.s('username', '…')}', size: 12, lines: 1),
            T(isHost ? 'میزبان' : p.b('ready') ? 'آماده ✓' : 'آماده نیست', size: 10, color: isHost ? C.gold : p.b('ready') ? C.green : C.dim2),
            StatBars(power: st.power, accuracy: st.accuracy, compact: true),
          ]),
        ),
        if (canKick) GestureDetector(onTap: onKick, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 16, color: C.red))),
      ]),
    );
  }
}

class FieldPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChange;
  const FieldPicker({super.key, required this.value, required this.onChange});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 92,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          reverse: true,
          itemCount: kFields.length,
          itemBuilder: (_, i) => Press(
            onTap: () => onChange(i),
            child: Container(
              width: 76,
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: i == value ? C.cyan : C.line), color: i == value ? const Color(0x1f4fe3ff) : null),
              child: Column(children: [Img(fieldThumb(i), w: 44, h: 58, fit: BoxFit.cover, radius: 6), T(kFields[i].name, size: 10, color: i == value ? C.text : C.dim, lines: 1)]),
            ),
          ),
        ),
      );
}

class _RoomSettings extends StatefulWidget {
  final RoomLink link;
  const _RoomSettings({required this.link});
  @override
  State<_RoomSettings> createState() => _RoomSettingsState();
}

class _RoomSettingsState extends State<_RoomSettings> {
  late final Rec room = widget.link.room!;
  late final name = TextEditingController(text: room.s('name'));
  late String rule = settingsToRule(room.rec('settings'));
  late int turn = room.rec('settings').i('turn', 15), field = room.rec('settings').i('field');
  late final String mode0 = kModesOnline.contains(room.s('mode')) ? room.s('mode') : '1v1';
  late String mode = mode0;
  bool busy = false;

  /// PostgREST answers PGRST202 when the server has no update_room(p_mode) overload yet
  /// (Godot migration 20261114000000_lobby_mode_change.sql not applied).
  static bool _noModeRpc(Object e) {
    final m = e is PostgrestException ? '${e.code} ${e.message}' : '$e';
    return m.contains('PGRST202') || RegExp('could not find the function', caseSensitive: false).hasMatch(m);
  }

  Future<void> _save() async {
    setState(() => busy = true);
    final args = <String, dynamic>{
      'p_room': room.s('id'),
      'p_settings': {...room.rec('settings').m, ...ruleToSettings(rule), 'turn': turn, 'field': field},
      'p_name': name.text.trim().substring(0, name.text.trim().length.clamp(0, 40)),
    };
    try {
      var modeOk = true;
      if (mode != mode0) {
        // same RPC as Godot commit bda7b64: update_room(p_room, p_settings, p_name, p_mode)
        try {
          await rpc('update_room', {...args, 'p_mode': mode});
        } catch (e) {
          if (!_noModeRpc(e)) rethrow;
          modeOk = false;
          await rpc('update_room', args); // still save the other settings on an older server
        }
      } else {
        await rpc('update_room', args);
      }
      widget.link.ping();
      await widget.link.refresh();
      if (!modeOk) {
        toast('تغییر حالت اتاق روی سرور فعال نیست؛ بقیه‌ی تنظیمات ذخیره شد', 'err');
      } else {
        toast('تنظیمات ذخیره شد', 'ok');
      }
      if (mounted && context.mounted) Navigator.pop(context);
    } catch (e) {
      toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Field2(name, label: 'نام اتاق', maxLength: 40),
        _lbl('حالت'),
        Segment<String>(value: mode, onChange: (v) => setState(() => mode = v), items: [for (final m in kModesOnline) (m, kModeFa[m]!)], accent: C.sky),
        if (teamSize(mode) < teamSize(mode0))
          Padding(padding: const EdgeInsets.only(top: 6), child: T('بازیکن‌های صندلی‌های اضافه تماشاگر می‌شوند', size: 11, color: C.dim, align: TextAlign.right)),
        _lbl('قانون بازی'),
        Segment<String>(value: rule, onChange: (v) => setState(() => rule = v), items: kRules, accent: C.violet),
        _lbl('زمان هر نوبت'),
        Segment<int>(value: turn, onChange: (v) => setState(() => turn = v), items: const [(10, '۱۰ث'), (15, '۱۵ث'), (20, '۲۰ث'), (0, 'بدون')], accent: C.green),
        _lbl('زمین'),
        FieldPicker(value: field, onChange: (v) => setState(() => field = v)),
        const SizedBox(height: 16),
        Btn(busy ? 'در حال ذخیره…' : 'ذخیره', disabled: busy, onTap: _save),
      ]);
}

Widget _lbl(String s) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: tBold(s, size: 13, color: C.dim, align: TextAlign.right));

// =============================================================== hub
class HubScreen extends StatefulWidget {
  final VoidCallback onBack;
  final void Function(Rec room) onRoom;
  final void Function(String nav) onNav;
  const HubScreen({super.key, required this.onBack, required this.onRoom, required this.onNav});
  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  List<Rec>? rows;
  String? err, busy;
  String filter = 'all';
  final code = TextEditingController();
  RealtimeChannel? _ch;
  Timer? _t, _poll;

  @override
  void initState() {
    super.initState();
    load();
    void soon() {
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 600), load);
    }

    _ch = sb
        .channel('hub:rooms')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'rooms', callback: (_) => soon())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'room_players', callback: (_) => soon())
        .subscribe();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => load());
  }

  @override
  void dispose() {
    _t?.cancel();
    _poll?.cancel();
    if (_ch != null) sb.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await sb.from('room_list').select().order('created_at', ascending: false).limit(60);
      if (mounted) {
        setState(() {
          err = null;
          rows = recs(d);
        });
      }
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  Future<void> act(String key, Future<dynamic> Function() fn) async {
    if (busy != null) return;
    setState(() => busy = key);
    try {
      final r = Rec.of(await fn());
      sfx(Snd.join);
      buzz('medium');
      widget.onRoom(r);
    } catch (e) {
      toast(errFa(e), 'err');
      buzz('heavy');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  void quick(String m) {
    Oracle.i.react('search');
    act('quick$m', () => rpc('quick_match', {'p_mode': m, 'p_kind': 'quick'}));
  }

  void joinCode() {
    final c = code.text.trim().toUpperCase();
    if (c.length != 6) return toast('کد اتاق ۶ کاراکتر است', 'err');
    act('code', () => rpc('join_room', {'p_code': c}));
  }

  @override
  Widget build(BuildContext context) {
    final data = (rows ?? const <Rec>[]).where((r) => filter == 'all' || r.s('mode') == filter).toList();
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        const Space(theme: SpaceTheme.base, dim: .15),
        RefreshIndicator(
          onRefresh: load,
          color: C.cyan,
          child: ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24), children: [
            Header(title: 'آنلاین', en: 'ONLINE ARENA', onBack: widget.onBack),
            ListenableBuilder(
              listenable: Auth.i,
              builder: (_, __) {
                final pr = Auth.i.profile;
                if (pr == null) return const SizedBox.shrink();
                final lp = levelProgress(pr.i('xp'));
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Press(
                    onTap: () => widget.onNav('ranks'),
                    scaleTo: .98,
                    child: Panel(
                      accent: C.gold,
                      child: Row(textDirection: TextDirection.rtl, children: [
                        Avatar(avatar: pr.str('equipped_disc'), url: pr.str('avatar_url'), size: 52, ring: C.gold),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [Badge2('سطح ${fa(pr.i('level'))}', color: C.gold), const SizedBox(width: 4), Flexible(child: tBold(pr.s('username'), size: 16, lines: 1))]),
                            const SizedBox(height: 6),
                            Bar(v: lp.frac, h: 6, color: C.cyan, color2: C.violet),
                            T('${fa(lp.cur)} / ${fa(lp.need)} XP · امتیاز ${fa(pr.i('rating'))}', size: 10, color: C.dim),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Img(ui(kLeagueImg[pr.s('league')] ?? 'medal_bronze'), w: 48, h: 48),
                      ]),
                    ),
                  ),
                );
              },
            ),
            Panel(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              accent: C.cyan,
              glowOn: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(textDirection: TextDirection.rtl, children: [
                  Img(ui2('x_ball'), w: 36, h: 36),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [tTitle('مسابقه‌ی سریع', size: 16), const T('هم‌سطح‌ترین حریف آنلاین را پیدا کن', size: 11, color: C.dim)])),
                ]),
                const SizedBox(height: 8),
                Row(textDirection: TextDirection.rtl, children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: Btn(busy == 'quick${kModesOnline[i]}' ? '…' : kModesOnline[i].toUpperCase(), sub: kModeFa[kModesOnline[i]], small: true, disabled: busy != null, colors: [G.primary, G.violet, G.gold][i], onTap: () => quick(kModesOnline[i]))),
                  ],
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(textDirection: TextDirection.rtl, children: [
                for (final (k, l, img, c) in [('arena', 'آرنا', ui2('x_crown'), C.violet), ('tours', 'تورنمنت', ui2('x_trophy'), C.orange), ('ranks', 'رده‌بندی', ui2('x_medal'), C.gold), ('challenges', 'چالش‌ها', ui2('c_calendar'), C.green)])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Press(
                        onTap: () => widget.onNav(k),
                        child: Container(
                          height: 72,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: c.withValues(alpha: .4)), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withValues(alpha: .2), const Color(0xe6080c22)])),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Img(img, w: 36, h: 36), tBold(l, size: 11, lines: 1)]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(textDirection: TextDirection.rtl, children: [
                SizedBox(width: 120, child: Btn('ساخت اتاق', small: true, colors: G.green, onTap: () => showSheet(context, title: 'ساخت اتاق', en: 'CREATE ROOM', accent: C.green, height: .88, child: (ctx) => _CreateRoom(onCreate: (a) {
                          Navigator.pop(ctx);
                          act('create', () => rpc('create_room', a));
                        })))),
                const SizedBox(width: 8),
                Expanded(child: Field2(code, hint: 'کد ۶ رقمی', ltr: true, maxLength: 6, onSubmit: (_) => joinCode())),
                const SizedBox(width: 6),
                SizedBox(width: 64, child: Btn('ورود', small: true, colors: G.dark, onTap: joinCode)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(textDirection: TextDirection.rtl, children: [tBold('اتاق‌های باز', size: 16), const Spacer(), T(rows != null ? '${fa(data.length)} اتاق' : '', size: 11, color: C.dim)]),
            ),
            Tabs2<String>(items: const [('all', 'همه'), ('1v1', '1v1'), ('2v2', '2v2'), ('3v3', '3v3')], value: filter, onChange: (v) => setState(() => filter = v)),
            if (err != null)
              ErrorState(err!, onRetry: load)
            else if (rows == null)
              const LoadingList()
            else if (data.isEmpty)
              const EmptyState('فعلاً اتاقی باز نیست · یک اتاق بساز و دوستانت را با کد دعوت کن')
            else
              for (final r in data) _RoomRow(r: r, busy: busy, onJoin: (id, spec) => act((spec ? 'w' : 'j') + id, () => rpc('join_room', {'p_room': id, 'p_spectate': spec}))),
          ]),
        ),
      ]),
    );
  }
}

class _RoomRow extends StatelessWidget {
  final Rec r;
  final String? busy;
  final void Function(String id, bool spectate) onJoin;
  const _RoomRow({required this.r, required this.busy, required this.onJoin});
  @override
  Widget build(BuildContext context) {
    final full = r.i('players') >= r.i('capacity'), playing = r.s('status') == 'playing';
    final (kl, kc) = kKindFa[r.s('kind')] ?? kKindFa['casual']!;
    return Panel(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      accent: Colors.transparent,
      child: Column(children: [
        Row(textDirection: TextDirection.rtl, children: [
          Avatar(avatar: r.str('host_avatar'), url: r.str('host_avatar_url'), size: 44, ring: playing ? C.red : C.cyan),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              tBold(r.s('name'), size: 14, lines: 1),
              T('${r.s('host_name')} · سطح ${fa(r.i('host_level'))} · ${ruleLabel(r.rec('settings'))}', size: 11, color: C.dim, lines: 1),
              const SizedBox(height: 4),
              Wrap(textDirection: TextDirection.rtl, children: [Badge2(r.s('mode').toUpperCase(), color: C.sky), Badge2(kl, color: kc), playing ? const Badge2('زنده', color: C.red, live: true) : const Badge2('در انتظار', color: C.green)]),
            ]),
          ),
          SizedBox(width: 64, child: Column(children: [tTitle('${fa(r.i('players'))}/${fa(r.i('capacity'))}', size: 16, color: full ? C.orange : C.text), T('👁 ${fa(r.i('spectators'))}', size: 10, color: C.dim)])),
        ]),
        const SizedBox(height: 8),
        Row(textDirection: TextDirection.rtl, children: [
          if (!playing && !full) ...[Expanded(child: Btn(busy == 'j${r.s('id')}' ? '…' : 'ورود', small: true, disabled: busy != null, onTap: () => onJoin(r.s('id'), false))), const SizedBox(width: 8)],
          Expanded(child: Btn(busy == 'w${r.s('id')}' ? '…' : 'تماشا', small: true, colors: G.dark, disabled: busy != null, onTap: () => onJoin(r.s('id'), true))),
        ]),
      ]),
    );
  }
}

class _CreateRoom extends StatefulWidget {
  final void Function(Map<String, dynamic>) onCreate;
  const _CreateRoom({required this.onCreate});
  @override
  State<_CreateRoom> createState() => _CreateRoomState();
}

class _CreateRoomState extends State<_CreateRoom> {
  final name = TextEditingController();
  String mode = '1v1', rule = 'g3';
  bool priv = false, ranked = true, voice = true;
  int turn = 15, field = 0;
  Widget opt(String l, String s, bool v, ValueChanged<bool> on) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(textDirection: TextDirection.rtl, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [tBold(l, size: 14), T(s, size: 11, color: C.dim)])),
          Toggle(on: v, onChange: on),
        ]),
      );
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 48), children: [
        Field2(name, label: 'نام اتاق', hint: 'مثلاً: فینال کهکشانی', maxLength: 40),
        _lbl('حالت'),
        Segment<String>(value: mode, onChange: (v) => setState(() => mode = v), items: [for (final m in kModesOnline) (m, kModeFa[m]!)]),
        _lbl('قانون'),
        Segment<String>(value: rule, onChange: (v) => setState(() => rule = v), items: kRules, accent: C.violet),
        _lbl('زمان هر نوبت'),
        Segment<int>(value: turn, onChange: (v) => setState(() => turn = v), items: const [(10, '۱۰ث'), (15, '۱۵ث'), (20, '۲۰ث'), (0, 'بدون')], accent: C.green),
        _lbl('زمین'),
        FieldPicker(value: field, onChange: (v) => setState(() => field = v)),
        opt('رتبه‌ای', 'نتیجه روی امتیاز و لیگ اثر دارد', ranked, (v) => setState(() => ranked = v)),
        opt('خصوصی', 'فقط با کد اتاق قابل ورود است', priv, (v) => setState(() => priv = v)),
        opt('چت صوتی', 'بازیکن‌ها می‌توانند با هم صحبت کنند', voice, (v) => setState(() => voice = v)),
        const SizedBox(height: 20),
        Btn('ساخت اتاق', colors: G.green, onTap: () {
          final n = name.text.trim();
          widget.onCreate({
            'p_mode': mode, 'p_name': n.isEmpty ? null : n, 'p_private': priv, 'p_ranked': ranked, 'p_voice': voice,
            'p_settings': {...ruleToSettings(rule), 'field': field, 'turn': turn, 'ball': 0},
          });
        }),
      ]);
}
