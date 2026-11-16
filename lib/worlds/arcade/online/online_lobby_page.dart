import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/online/online_service.dart';
import '../../../core/online/social_api.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../../games/game_registry.dart';
import 'online_match_page.dart';

class _Seat {
  _Seat(
      {required this.userId,
      required this.seat,
      required this.ready,
      required this.name});
  final String userId;
  final int seat;
  final bool ready;
  final String name;
}

/// Online lobby for one game: quick match, private room by code, open rooms, invite friends.
class OnlineLobbyPage extends ConsumerStatefulWidget {
  const OnlineLobbyPage(
      {super.key, required this.gameId, this.joinCode, this.roomId});
  final String gameId;
  final String? joinCode;
  final String? roomId;

  @override
  ConsumerState<OnlineLobbyPage> createState() => _OnlineLobbyPageState();
}

class _OnlineLobbyPageState extends ConsumerState<OnlineLobbyPage> {
  final TextEditingController _code = TextEditingController();
  String? _roomId;
  Map<String, dynamic>? _room;
  List<_Seat> _seats = <_Seat>[];
  List<Map<String, dynamic>> _open = <Map<String, dynamic>>[];
  final Set<int> _present = <int>{};
  RealtimeChannel? _ch;
  Timer? _poll;
  bool _busy = false;
  bool _realtimeConnected = false;
  String? _error;
  int _wantSeats = 2;
  bool _inMatch = false;
  String? _lastMatchSeen;

  SupabaseClient? get _c => ref.read(onlineProvider).client;
  String? get _me => ref.read(onlineProvider).uid;
  GameInfo? get _game => gameById(widget.gameId);

  @override
  void initState() {
    super.initState();
    _wantSeats = _game?.defaultPlayers ?? 2;
    if (widget.gameId == 'mafia') _wantSeats = 6;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_boot()));
  }

  Future<void> _boot() async {
    final OnlineService o = ref.read(onlineProvider);
    if (!o.isOnline) await o.ensureSession();
    if (!mounted) return;
    if (widget.roomId != null) {
      await _guard(() async {
        final dynamic r = await _c!.rpc('nx_join_room',
            params: <String, dynamic>{'p_room': widget.roomId});
        await _enter('${(r as Map)['room_id']}');
      });
    } else if (widget.joinCode != null && widget.joinCode!.isNotEmpty) {
      _code.text = widget.joinCode!;
      await _joinByCode();
    } else {
      await _loadOpen();
    }
    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_roomId != null) {
        unawaited(_refresh());
      } else {
        unawaited(_loadOpen());
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _code.dispose();
    final RealtimeChannel? ch = _ch;
    final SupabaseClient? c = _c;
    if (ch != null && c != null) unawaited(c.removeChannel(ch));
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() f) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on PostgrestException catch (e) {
      _error = _pretty(e.message);
    } catch (e) {
      final String s = '$e';
      _error = s.contains('Socket') || s.contains('host lookup')
          ? context.tx('اتصال برقرار نیست', 'No connection')
          : s;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _pretty(String m) {
    if (m.contains('room not found'))
      return context.tx('اتاقی با این کد پیدا نشد', 'No room with that code');
    if (m.contains('room full'))
      return context.tx('اتاق پر است', 'The room is full');
    if (m.contains('already started'))
      return context.tx(
          'بازی این اتاق شروع شده', 'That room has already started');
    if (m.contains('need'))
      return context.tx('بازیکن کافی نیست', 'Not enough players yet');
    if (m.contains('not signed in'))
      return context.tx('اول آنلاین شو', 'Go online first');
    return m;
  }

  Future<void> _loadOpen() async {
    final SupabaseClient? c = _c;
    if (c == null || c.auth.currentSession == null) return;
    try {
      final List<dynamic> rows = await c
          .from('nx_rooms')
          .select('id, code, seats, host, created_at, nx_room_players(count)')
          .eq('game', widget.gameId)
          .eq('status', 'lobby')
          .eq('is_private', false)
          .eq('quick', false)
          .gte(
              'updated_at',
              DateTime.now()
                  .toUtc()
                  .subtract(const Duration(minutes: 20))
                  .toIso8601String())
          .order('created_at', ascending: false)
          .limit(20);
      if (!mounted) return;
      setState(() => _open = rows
          .map((dynamic r) => Map<String, dynamic>.from(r as Map))
          .toList());
    } catch (_) {}
  }

  Future<void> _quick() => _guard(() async {
        final dynamic r = await _c!.rpc('nx_quick', params: <String, dynamic>{
          'p_game': widget.gameId,
          'p_seats': _wantSeats
        });
        await _enter('${(r as Map)['room_id']}');
      });

  Future<void> _create(bool private) => _guard(() async {
        final dynamic r =
            await _c!.rpc('nx_create_room', params: <String, dynamic>{
          'p_game': widget.gameId,
          'p_seats': _wantSeats,
          'p_private': private,
          'p_quick': false,
          'p_settings': <String, dynamic>{},
        });
        await _enter('${(r as Map)['room_id']}');
      });

  Future<void> _joinByCode() => _guard(() async {
        final String code = _code.text.trim().toUpperCase();
        if (code.length < 4) return;
        final dynamic r = await _c!
            .rpc('nx_join_room', params: <String, dynamic>{'p_code': code});
        await _enter('${(r as Map)['room_id']}');
      });

  Future<void> _enter(String roomId) async {
    _roomId = roomId;
    await _refresh();
    _subscribe(roomId);
  }

  void _subscribe(String roomId) {
    final SupabaseClient c = _c!;
    final RealtimeChannel? old = _ch;
    if (old != null) unawaited(c.removeChannel(old));
    final RealtimeChannel ch =
        c.channel('nxr:$roomId', opts: RealtimeChannelConfig(key: _me ?? ''));
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nx_rooms',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq, column: 'id', value: roomId),
          callback: (_) => unawaited(_refresh()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nx_room_players',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: roomId),
          callback: (_) => unawaited(_refresh()),
        )
        .onPresenceSync((_) => _syncPresence())
        .onPresenceJoin((_) => _syncPresence())
        .onPresenceLeave((_) => _syncPresence())
        .subscribe((RealtimeSubscribeStatus s, Object? e) {
      if (mounted)
        setState(
            () => _realtimeConnected = s == RealtimeSubscribeStatus.subscribed);
      if (s == RealtimeSubscribeStatus.subscribed) {
        final int mySeat = _seats
                .where((_Seat x) => x.userId == _me)
                .map((_Seat x) => x.seat)
                .firstOrNull ??
            -1;
        unawaited(ch.track(<String, dynamic>{'uid': _me, 'seat': mySeat}));
      }
    });
    _ch = ch;
  }

  void _syncPresence() {
    final RealtimeChannel? ch = _ch;
    if (ch == null || !mounted) return;
    final Set<String> uids = <String>{};
    for (final SinglePresenceState st in ch.presenceState()) {
      for (final Presence p in st.presences) {
        uids.add('${p.payload['uid']}');
      }
    }
    setState(() {
      _present
        ..clear()
        ..addAll(_seats
            .where((_Seat s) => uids.contains(s.userId))
            .map((_Seat s) => s.seat));
    });
  }

  Future<void> _refresh() async {
    final String? id = _roomId;
    final SupabaseClient? c = _c;
    if (id == null || c == null) return;
    try {
      final Map<String, dynamic>? room =
          await c.from('nx_rooms').select().eq('id', id).maybeSingle();
      final List<dynamic> ps = await c
          .from('nx_room_players')
          .select('user_id, seat, ready, profiles(username)')
          .eq('room_id', id)
          .order('seat');
      if (!mounted) return;
      final List<_Seat> seats = ps.map((dynamic r) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(r as Map);
        final dynamic prof = m['profiles'];
        return _Seat(
          userId: '${m['user_id']}',
          seat: (m['seat'] as num).toInt(),
          ready: m['ready'] == true,
          name: prof is Map ? '${prof['username'] ?? 'Pilot'}' : 'Pilot',
        );
      }).toList();
      setState(() {
        _room = room;
        _seats = seats;
      });
      _syncPresence();
      final String? matchId = room?['match_id'] as String?;
      if (room != null &&
          room['status'] == 'playing' &&
          matchId != null &&
          !_inMatch &&
          matchId != _lastMatchSeen) {
        if (seats.any((_Seat s) => s.userId == _me))
          unawaited(_openMatch(matchId));
      }
    } catch (_) {}
  }

  Future<void> _openMatch(String matchId) async {
    _inMatch = true;
    _lastMatchSeen = matchId;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OnlineMatchPage(matchId: matchId, gameId: widget.gameId),
    ));
    _inMatch = false;
    if (mounted) await _refresh();
  }

  Future<void> _leave() async {
    final String? id = _roomId;
    if (id == null) return;
    await _guard(() async {
      await _c!.rpc('nx_leave_room', params: <String, dynamic>{'p_room': id});
    });
    final RealtimeChannel? ch = _ch;
    if (ch != null) unawaited(_c!.removeChannel(ch));
    _ch = null;
    if (!mounted) return;
    setState(() {
      _roomId = null;
      _room = null;
      _seats = <_Seat>[];
      _realtimeConnected = false;
    });
    unawaited(_loadOpen());
  }

  Future<void> _start() => _guard(() async {
        final dynamic r = await _c!.rpc('nx_start_match',
            params: <String, dynamic>{'p_room': _roomId});
        final String? mid = (r as Map)['match_id'] as String?;
        if (mid != null && !_inMatch) unawaited(_openMatch(mid));
      });

  Future<void> _setSeats(int n) => _guard(() async {
        await _c!.rpc('nx_update_room', params: <String, dynamic>{
          'p_room': _roomId,
          'p_seats': n,
          'p_settings': null
        });
        await _refresh();
      });

  Future<void> _toggleReady(bool v) => _guard(() async {
        await _c!.rpc('nx_set_ready',
            params: <String, dynamic>{'p_room': _roomId, 'p_ready': v});
        await _refresh();
      });

  Future<void> _invite() async {
    final SupabaseClient? c = _c;
    if (c == null || _roomId == null) return;
    List<NxUser> friends = <NxUser>[];
    try {
      friends = await SocialApi(c).friends();
    } catch (_) {}
    if (!mounted) return;
    final Set<String> inRoom = _seats.map((_Seat s) => s.userId).toSet();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NxColors.navy,
      builder: (BuildContext ctx) => SafeArea(
        child: friends.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(ctx.tx(
                    'هنوز دوستی نداری. از «اوربیت نتورک» دوست اضافه کن یا کد اتاق را بفرست.',
                    'No friends yet. Add friends in Orbit Network, or share the room code.')),
              )
            : ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final NxUser f in friends)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            f.isOnlineNow ? NxColors.success : NxColors.glass,
                        child: Text(f.username.isEmpty
                            ? '?'
                            : f.username.characters.first.toUpperCase()),
                      ),
                      title: Text(f.username),
                      subtitle: Text(f.isOnlineNow
                          ? ctx.tx('آنلاین', 'Online')
                          : ctx.tx('آفلاین', 'Offline')),
                      trailing: inRoom.contains(f.id)
                          ? const Icon(Icons.check_rounded,
                              color: NxColors.success)
                          : FilledButton(
                              onPressed: () async {
                                try {
                                  await c.rpc('nx_invite',
                                      params: <String, dynamic>{
                                        'p_room': _roomId,
                                        'p_user': f.id
                                      });
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(context.tx(
                                                'دعوت فرستاده شد',
                                                'Invite sent'))));
                                    Navigator.pop(ctx);
                                  }
                                } catch (_) {}
                              },
                              child: Text(ctx.tx('دعوت', 'Invite')),
                            ),
                    ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final OnlineService o = ref.watch(onlineProvider);
    final NxThemeColors visual = NxThemeColors.of(context);
    final GameInfo? game = _game;
    final String title = game == null
        ? 'ONLINE'
        : context.tx(game.nameFa, game.nameEn).toUpperCase();
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, _) {
        if (didPop && _roomId != null && _room?['status'] == 'lobby') {
          final SupabaseClient? c = _c;
          final String id = _roomId!;
          if (c != null)
            unawaited(c.rpc('nx_leave_room', params: <String, dynamic>{
              'p_room': id
            }).catchError((Object _) => null));
        }
      },
      child: NxWorldScaffold(
        title: '$title · ${context.tx('آنلاین', 'ONLINE')}',
        palette: WorldPalette.arcade,
        body: !o.configured
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(context.tx('این نسخه بدون سرور ساخته شده است.',
                      'This build has no server configured.')),
                ),
              )
            : !o.isOnline
                ? Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.wifi_off_rounded,
                              size: 48, color: visual.accent),
                          const SizedBox(height: 12),
                          Text(context.tx('اتصال به سرور برقرار نیست',
                              'Not connected to the server')),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed:
                                  o.busy ? null : () => unawaited(_boot()),
                              child: Text(context.tx('تلاش دوباره', 'Retry'))),
                        ]),
                  )
                : (_roomId == null
                    ? _menu(context, game)
                    : _roomView(context, game)),
      ),
    );
  }

  Widget _seatPicker(BuildContext context, GameInfo game, int value,
      ValueChanged<int> onPick) {
    final int min = widget.gameId == 'mafia' ? 6 : game.minPlayers;
    final int max = widget.gameId == 'mafia' ? 10 : game.maxPlayers;
    if (max <= min) return const SizedBox.shrink();
    final NxThemeColors visual = NxThemeColors.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
      for (int n = min; n <= max; n++)
        ChoiceChip(
          label: Text(context.tx('$n نفره', '$n players')),
          selected: value == n,
          selectedColor: visual.accent.withValues(alpha: 0.24),
          side: BorderSide(
              color: value == n
                  ? visual.accent
                  : visual.border.withValues(alpha: 0.55)),
          showCheckmark: false,
          onSelected: (_) => onPick(n),
        ),
    ]);
  }

  Widget _menu(BuildContext context, GameInfo? game) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return ListView(
        padding: const EdgeInsets.all(NxSpace.md),
        children: <Widget>[
          if (_error != null) _errorBox(),
          GlassPanel(
            blur: false,
            borderColor: visual.accent.withValues(alpha: 0.48),
            child: Row(children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LinearGradient(colors: <Color>[
                    visual.accent.withValues(alpha: 0.24),
                    visual.accentSecondary.withValues(alpha: 0.14)
                  ]),
                ),
                child: Icon(Icons.public_rounded, color: visual.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                          context.tx('اتصال آنلاین برقرار است',
                              'ONLINE CONNECTION READY'),
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(
                          context.tx(
                              'اتاق بساز، با کد وارد شو یا حریف پیدا کن.',
                              'Create a room, join by code, or find opponents.'),
                          style: TextStyle(color: visual.muted, fontSize: 12)),
                    ]),
              ),
              const Icon(Icons.check_circle_rounded, color: NxColors.success),
            ]),
          ),
          const SizedBox(height: NxSpace.sm),
          if (game != null) ...<Widget>[
            _seatPicker(context, game, _wantSeats,
                (int n) => setState(() => _wantSeats = n)),
            const SizedBox(height: NxSpace.sm),
          ],
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: visual.accent,
                minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _quick,
            icon: const Icon(Icons.bolt_rounded),
            label: Text(context.tx(
                'بازی سریع (پیدا کردن حریف)', 'Quick match (find opponents)')),
          ),
          const SizedBox(height: 10),
          Row(children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _create(true),
                icon: const Icon(Icons.lock_rounded),
                label: Text(context.tx('اتاق خصوصی', 'Private room')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _create(false),
                icon: const Icon(Icons.public_rounded),
                label: Text(context.tx('اتاق عمومی', 'Public room')),
              ),
            ),
          ]),
          const SizedBox(height: NxSpace.md),
          GlassPanel(
            child: Row(children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                      labelText: context.tx('کد اتاق', 'Room code'),
                      prefixIcon: const Icon(Icons.vpn_key_rounded)),
                  onSubmitted: (_) => _joinByCode(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                  onPressed: _busy ? null : _joinByCode,
                  child: Text(context.tx('ورود', 'Join'))),
            ]),
          ),
          const SizedBox(height: NxSpace.md),
          Text(context.tx('اتاق‌های باز', 'Open rooms'),
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          if (_open.isEmpty)
            Text(
                context.tx('الان اتاق بازی نیست؛ یکی بساز یا «بازی سریع» بزن.',
                    'No open rooms right now — create one or tap Quick match.'),
                style: const TextStyle(color: NxColors.textDim)),
          for (final Map<String, dynamic> r in _open)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassPanel(
                onTap: _busy
                    ? null
                    : () => _guard(() async {
                          final dynamic j = await _c!.rpc('nx_join_room',
                              params: <String, dynamic>{'p_room': r['id']});
                          await _enter('${(j as Map)['room_id']}');
                        }),
                child: Row(children: <Widget>[
                  Icon(Icons.meeting_room_rounded, color: visual.accent),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text('${r['code']}',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: visual.accent))),
                  NxPill(
                      label: '${_count(r)}/${r['seats']}',
                      icon: Icons.groups_rounded,
                      color: visual.accentSecondary),
                ]),
              ),
            ),
          if (_busy)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator())),
        ]);
  }

  int _count(Map<String, dynamic> r) {
    final dynamic l = r['nx_room_players'];
    if (l is List && l.isNotEmpty && l.first is Map)
      return ((l.first as Map)['count'] as num?)?.toInt() ?? 0;
    return 0;
  }

  Widget _errorBox() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassPanel(
          borderColor: NxColors.danger.withValues(alpha: 0.6),
          child: Text(_error!, style: const TextStyle(color: NxColors.danger)),
        ),
      );

  Widget _roomView(BuildContext context, GameInfo? game) {
    final Map<String, dynamic>? r = _room;
    if (r == null) return const Center(child: CircularProgressIndicator());
    final NxThemeColors visual = NxThemeColors.of(context);
    final bool host = r['host'] == _me;
    final int seats = (r['seats'] as num?)?.toInt() ?? 2;
    final bool quick = r['quick'] == true;
    final int minSeats = widget.gameId == 'mafia' ? 6 : (game?.minPlayers ?? 2);
    final bool canStart =
        host && _seats.length >= minSeats && r['status'] == 'lobby';
    final _Seat? mine = _seats.where((_Seat s) => s.userId == _me).firstOrNull;
    final bool allReady = _seats.every((_Seat s) => s.ready || s.seat == 0);
    return ListView(
        padding: const EdgeInsets.all(NxSpace.md),
        children: <Widget>[
          if (_error != null) _errorBox(),
          GlassPanel(
            borderColor: visual.accent.withValues(alpha: 0.56),
            child: Row(children: <Widget>[
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(children: <Widget>[
                        NxPill(
                          label: _realtimeConnected
                              ? context.tx('همگام', 'SYNCED')
                              : context.tx('در حال اتصال', 'CONNECTING'),
                          icon: _realtimeConnected
                              ? Icons.wifi_rounded
                              : Icons.wifi_tethering_rounded,
                          color: _realtimeConnected
                              ? NxColors.success
                              : visual.accentSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            quick
                                ? context.tx(
                                    'در جستجوی حریف…', 'Finding opponents…')
                                : context.tx('کد اتاق', 'Room code'),
                            textAlign: TextAlign.end,
                            style: TextStyle(color: visual.muted, fontSize: 12),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text('${r['code']}',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 6,
                              color: visual.accent)),
                      const SizedBox(height: 7),
                      Text(
                        context.tx(
                            '${_present.length} از ${_seats.length} بازیکن متصل · ${_seats.length}/$seats جایگاه',
                            '${_present.length} of ${_seats.length} connected · ${_seats.length}/$seats seats'),
                        style: TextStyle(color: visual.muted, fontSize: 11),
                      ),
                    ]),
              ),
              IconButton(
                tooltip: context.tx('کپی', 'Copy'),
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${r['code']}'));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(context.tx('کد کپی شد', 'Code copied'))));
                },
              ),
            ]),
          ),
          const SizedBox(height: NxSpace.sm),
          if (host && !quick && game != null)
            _seatPicker(context, game, seats, (int n) => _setSeats(n)),
          const SizedBox(height: NxSpace.sm),
          for (int s = 0; s < seats; s++) _seatTile(context, s, r),
          const SizedBox(height: NxSpace.md),
          if (r['status'] == 'playing' && r['match_id'] != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: visual.accent,
                  minimumSize: const Size.fromHeight(50)),
              onPressed: () => _openMatch('${r['match_id']}'),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(context.tx('بازگشت به بازی', 'Return to the match')),
            )
          else if (host)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: visual.accent,
                  minimumSize: const Size.fromHeight(50)),
              onPressed: canStart && !_busy ? _start : null,
              icon: const Icon(Icons.rocket_launch_rounded),
              label: Text(_seats.length < minSeats
                  ? context.tx('منتظر بازیکن‌ها (${_seats.length}/$minSeats)',
                      'Waiting for players (${_seats.length}/$minSeats)')
                  : allReady
                      ? context.tx('شروع بازی', 'Start match')
                      : context.tx('شروع (همه آماده نیستند)',
                          'Start (not everyone is ready)')),
            )
          else if (mine != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor:
                      mine.ready ? NxColors.navySoft : NxColors.success,
                  minimumSize: const Size.fromHeight(50)),
              onPressed: _busy ? null : () => _toggleReady(!mine.ready),
              icon: Icon(mine.ready
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded),
              label: Text(mine.ready
                  ? context.tx('آماده‌ام ✓', "I'm ready ✓")
                  : context.tx('اعلام آمادگی', 'Mark ready')),
            ),
          const SizedBox(height: 10),
          Row(children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _invite,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(context.tx('دعوت دوست', 'Invite a friend')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style:
                    OutlinedButton.styleFrom(foregroundColor: NxColors.danger),
                onPressed: _busy ? null : _leave,
                icon: const Icon(Icons.logout_rounded),
                label: Text(context.tx('ترک اتاق', 'Leave room')),
              ),
            ),
          ]),
        ]);
  }

  Widget _seatTile(BuildContext context, int s, Map<String, dynamic> r) {
    final _Seat? p = _seats.where((_Seat x) => x.seat == s).firstOrNull;
    final bool present = p != null && (_present.contains(s) || p.userId == _me);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        child: Row(children: <Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: p == null
                ? NxColors.glass
                : (present ? NxColors.success : NxColors.textDim),
            child: Text('${s + 1}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p == null
                  ? context.tx('جای خالی', 'Open seat')
                  : (p.userId == _me
                      ? '${p.name} (${context.tx('تو', 'you')})'
                      : p.name),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: p == null ? NxColors.textDim : null),
            ),
          ),
          if (p != null && r['host'] == p.userId)
            const NxPill(
                label: 'HOST', icon: Icons.star_rounded, color: NxColors.gold),
          if (p != null && r['host'] != p.userId) ...<Widget>[
            NxPill(
              label: present
                  ? context.tx('آنلاین', 'ONLINE')
                  : context.tx('آفلاین', 'OFFLINE'),
              icon: present ? Icons.circle_rounded : Icons.circle_outlined,
              color:
                  present ? NxColors.success : NxThemeColors.of(context).muted,
            ),
            const SizedBox(width: 6),
            Icon(
                p.ready
                    ? Icons.check_circle_rounded
                    : Icons.hourglass_empty_rounded,
                color: p.ready ? NxColors.success : NxColors.textDim),
          ],
        ]),
      ),
    );
  }
}
