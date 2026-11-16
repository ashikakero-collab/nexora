import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../games/core/net_link.dart';

/// Final state of a match as stored on the server.
class MatchEnd {
  const MatchEnd({required this.winners, required this.reason, this.scores});
  final List<int> winners;
  final String reason;
  final List<int>? scores;
  bool get isForfeit => reason.startsWith('forfeit');
  int? get forfeitSeat => isForfeit ? int.tryParse(reason.split(':').last) : null;
}

/// Supabase implementation of [NetLink].
///
/// * Ordered log: table nx_match_moves (insert through RPC nx_push_move, seq = last+1).
/// * Delivery: Realtime postgres_changes + a catch-up poll (never misses a move).
/// * Presence + ephemeral 'live' messages: Realtime channel `nxm:<matchId>`.
class SupabaseMatchLink extends ChangeNotifier implements NetLink {
  SupabaseMatchLink._(this._c, this.matchId, this._uid, Map<String, dynamic> m) {
    _players = (m['players'] as List<dynamic>).map((dynamic e) => '$e').toList();
    names = ((m['names'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => '$e').toList();
    while (names.length < _players.length) {
      names.add('Pilot ${names.length + 1}');
    }
    seed = (m['seed'] as num).toInt();
    game = '${m['game']}';
    roomId = m['room_id'] as String?;
    settings = Map<String, dynamic>.from((m['settings'] as Map?) ?? const <String, dynamic>{});
    mySeat = _players.indexOf(_uid);
    _status = '${m['status']}';
    if (_status != 'playing') _end = _endFrom(m);
  }

  static Future<SupabaseMatchLink> open(SupabaseClient c, String matchId) async {
    final String uid = c.auth.currentUser!.id;
    final Map<String, dynamic> m = await c.from('nx_matches').select().eq('id', matchId).single();
    final SupabaseMatchLink link = SupabaseMatchLink._(c, matchId, uid, m);
    link._connect();
    return link;
  }

  final SupabaseClient _c;
  final String _uid;
  @override
  final String matchId;
  late final List<String> _players;
  @override
  late final List<String> names;
  @override
  late final int seed;
  late final String game;
  String? roomId;
  @override
  late final Map<String, dynamic> settings;
  @override
  late final int mySeat;

  String _status = 'playing';
  MatchEnd? _end;
  MatchEnd? get end => _end;
  bool get isOver => _status != 'playing';

  RealtimeChannel? _ch;
  Timer? _poll;
  Timer? _watch;
  bool _disposed = false;

  final Map<int, NetMove> _rows = <int, NetMove>{};
  final Map<int, String> _rowUser = <int, String>{};
  final Set<int> _server = <int>{}; // seqs confirmed by the server log
  int _delivered = 0; // highest seq handed to the current listener (or sent by us)
  final Set<int> _ownSeqs = <int>{};
  void Function(NetMove)? _listener;
  bool _replaying = false;
  Future<void> _sendChain = Future<void>.value();

  final Set<int> _connected = <int>{};
  final Set<int> _forfeited = <int>{};
  final Map<int, DateTime> _absentSince = <int, DateTime>{};
  final StreamController<NetLiveMessage> _live = StreamController<NetLiveMessage>.broadcast();
  int? _turnSeat;
  int _desyncs = 0;

  /// Fires when this phone's view diverged from the log (e.g. a send lost a race): rebuild + replay.
  final ValueNotifier<int> resyncRequests = ValueNotifier<int>(0);

  @override
  int get seatCount => _players.length;
  @override
  Set<int> get connectedSeats => Set<int>.unmodifiable(_connected);
  @override
  Set<int> get forfeitedSeats => Set<int>.unmodifiable(_forfeited);
  @override
  Listenable get changes => this;
  @override
  bool get replaying => _replaying;
  @override
  Stream<NetLiveMessage> get live => _live.stream;
  @override
  int get desyncs => _desyncs;
  @override
  set turnSeat(int? seat) => _turnSeat = seat;

  @override
  bool get isAuthority {
    final List<int> alive = <int>[
      for (int s = 0; s < seatCount; s++)
        if (!_forfeited.contains(s) && (_connected.contains(s) || s == mySeat)) s,
    ];
    if (alive.isEmpty) return mySeat == 0;
    return alive.first == mySeat;
  }

  MatchEnd _endFrom(Map<String, dynamic> m) => MatchEnd(
        winners: ((m['winner_seats'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic e) => (e as num).toInt()).toList(),
        reason: '${m['reason'] ?? 'finished'}',
        scores: (m['scores'] as List<dynamic>?)?.map((dynamic e) => (e as num).toInt()).toList(),
      );

  void _connect() {
    final RealtimeChannel ch = _c.channel('nxm:$matchId', opts: RealtimeChannelConfig(key: '$mySeat', self: false));
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'nx_match_moves',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'match_id', value: matchId),
          callback: (PostgresChangePayload p) => _onRow(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'nx_matches',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: matchId),
          callback: (PostgresChangePayload p) => _onMatch(p.newRecord),
        )
        .onBroadcast(
          event: 'live',
          callback: (Map<String, dynamic> p) {
            final dynamic payload = p['payload'] ?? p;
            if (payload is Map) {
              final Map<String, dynamic> d = Map<String, dynamic>.from(payload);
              _live.add(NetLiveMessage((d['s'] as num?)?.toInt() ?? -1, '${d['e']}',
                  Map<String, dynamic>.from((d['d'] as Map?) ?? const <String, dynamic>{})));
            }
          },
        )
        .onPresenceSync((_) => _syncPresence())
        .onPresenceJoin((_) => _syncPresence())
        .onPresenceLeave((_) => _syncPresence())
        .subscribe((RealtimeSubscribeStatus status, Object? error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(ch.track(<String, dynamic>{'seat': mySeat, 'uid': _uid}));
            unawaited(_catchUp());
          }
        });
    _ch = ch;
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => unawaited(_catchUp()));
    _watch = Timer.periodic(const Duration(seconds: 5), (_) => _watchAbsent());
  }

  void _syncPresence() {
    final RealtimeChannel? ch = _ch;
    if (ch == null) return;
    final Set<int> now = <int>{};
    for (final SinglePresenceState st in ch.presenceState()) {
      for (final Presence p in st.presences) {
        final dynamic s = p.payload['seat'];
        if (s is num) now.add(s.toInt());
      }
    }
    now.add(mySeat);
    if (!setEquals(now, _connected)) {
      _connected
        ..clear()
        ..addAll(now);
      for (final int s in now) {
        _absentSince.remove(s);
      }
      if (!_disposed) notifyListeners();
    }
  }

  void _watchAbsent() {
    if (isOver || !isAuthority) return;
    final DateTime now = DateTime.now();
    for (int s = 0; s < seatCount; s++) {
      if (s == mySeat || _forfeited.contains(s) || _connected.contains(s)) continue;
      final DateTime since = _absentSince.putIfAbsent(s, () => now);
      // Tournament games carry settings.grace_sec (60 s reconnect grace); lobby games keep 40 s / 90 s.
      final int? grace = (settings['grace_sec'] as num?)?.toInt();
      final int limit = grace ?? (s == _turnSeat ? 40 : 90);
      if (now.difference(since).inSeconds >= limit) {
        _absentSince.remove(s);
        unawaited(_forfeitSeat(s));
      }
    }
  }

  Future<void> _forfeitSeat(int seat) async {
    try {
      await _c.rpc('nx_forfeit', params: <String, dynamic>{'p_match': matchId, 'p_seat': seat});
      await _catchUp();
    } catch (e) {
      debugPrint('forfeit seat $seat failed: $e');
    }
  }

  void _onMatch(Map<String, dynamic> m) {
    final String st = '${m['status']}';
    if (st != 'playing' && _status == 'playing') {
      _status = st;
      _end = _endFrom(m);
      if (!_disposed) notifyListeners();
    }
  }

  void _onRow(Map<String, dynamic> r) {
    final int seq = (r['seq'] as num).toInt();
    if (_rows.containsKey(seq) && !_ownSeqs.contains(seq)) return;
    final NetMove m = NetMove(
      seq: seq,
      seat: (r['seat'] as num).toInt(),
      kind: '${r['kind']}',
      data: Map<String, dynamic>.from((r['move'] as Map?) ?? const <String, dynamic>{}),
      hash: r['hash'] as String?,
    );
    if (_ownSeqs.contains(seq) && r['by_user'] != _uid) {
      // Our optimistic seq was taken by someone else: the phone must resync.
      _rows[seq] = m;
      _rowUser[seq] = '${r['by_user']}';
      _server.add(seq);
      _requestResync();
      return;
    }
    _rows[seq] = m;
    _rowUser[seq] = '${r['by_user']}';
    _server.add(seq);
    if (m.isForfeit) {
      final int s = (m.data['seat'] as num?)?.toInt() ?? m.seat;
      if (_forfeited.add(s) && !_disposed) notifyListeners();
    }
    _drain();
  }

  void _drain() {
    if (_replaying) return;
    while (_rows.containsKey(_delivered + 1)) {
      _delivered++;
      if (_ownSeqs.contains(_delivered)) continue;
      final NetMove m = _rows[_delivered]!;
      _listener?.call(m);
    }
  }

  Future<void> _catchUp() async {
    if (_disposed) return;
    try {
      int from = 0;
      while (_server.contains(from + 1)) {
        from++;
      }
      final List<dynamic> rows = await _c
          .from('nx_match_moves')
          .select('seq, seat, kind, move, hash, by_user')
          .eq('match_id', matchId)
          .gt('seq', from)
          .order('seq');
      for (final dynamic r in rows) {
        _onRow(Map<String, dynamic>.from(r as Map));
      }
      if (_status == 'playing') {
        final Map<String, dynamic>? m =
            await _c.from('nx_matches').select('status, winner_seats, reason, scores').eq('id', matchId).maybeSingle();
        if (m != null) _onMatch(m);
      }
    } catch (e) {
      debugPrint('catch-up failed: $e');
    }
  }

  void _requestResync() {
    _ownSeqs.clear();
    resyncRequests.value = resyncRequests.value + 1;
  }

  @override
  void listen(void Function(NetMove move) onMove, {VoidCallback? onReplayDone}) {
    _listener = onMove;
    _delivered = 0;
    _ownSeqs.clear();
    _replaying = true;
    unawaited(() async {
      await _catchUp();
      int seq = 1;
      while (_rows.containsKey(seq)) {
        final NetMove r = _rows[seq]!;
        if (_listener != onMove) return; // replaced by a newer game instance
        onMove(NetMove(seq: r.seq, seat: r.seat, kind: r.kind, data: r.data, hash: r.hash, replay: true));
        _delivered = seq;
        seq++;
      }
      _replaying = false;
      onReplayDone?.call();
      _drain();
    }());
  }

  @override
  Future<bool> send(Map<String, dynamic> data, {String kind = 'move', String? hash, int? asSeat}) {
    if (isOver) return Future<bool>.value(false);
    final int seq = _delivered + 1;
    _delivered = seq;
    _ownSeqs.add(seq);
    final int seat = asSeat ?? mySeat;
    _rows[seq] = NetMove(seq: seq, seat: seat, kind: kind, data: data, hash: hash);
    _rowUser[seq] = _uid;
    final Completer<bool> done = Completer<bool>();
    _sendChain = _sendChain.then((_) async {
      bool ok = false;
      for (int attempt = 0; attempt < 3 && !ok; attempt++) {
        try {
          final dynamic r = await _c.rpc('nx_push_move', params: <String, dynamic>{
            'p_match': matchId,
            'p_seq': seq,
            'p_kind': kind,
            'p_move': data,
            'p_hash': hash,
            'p_seat': seat,
          });
          if (r is Map && r['ok'] == true) {
            ok = true;
          } else if (r is Map && r['reason'] == 'seq') {
            // Someone else's move landed first (e.g. a timeout): replay from the log.
            await _catchUp();
            if (_rowUser[seq] != _uid) _requestResync();
            break;
          } else {
            break;
          }
        } catch (e) {
          debugPrint('push move $seq failed (try $attempt): $e');
          await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
        }
      }
      if (!ok && !isOver) {
        await _catchUp();
        final String? owner = _rowUser[seq];
        if (owner != _uid) _requestResync();
      }
      done.complete(ok);
    });
    return done.future;
  }

  @override
  void sendLive(String event, Map<String, dynamic> data) {
    final RealtimeChannel? ch = _ch;
    if (ch == null) return;
    unawaited(ch.sendBroadcastMessage(event: 'live', payload: <String, dynamic>{'s': mySeat, 'e': event, 'd': data}));
  }

  @override
  Future<void> putSecret(int seat, String slot, Map<String, dynamic> data) async {
    if (seat < 0 || seat >= seatCount) return;
    await _c.rpc('nx_put_secret', params: <String, dynamic>{
      'p_match': matchId,
      'p_user': _players[seat],
      'p_slot': slot,
      'p_data': data,
    });
  }

  @override
  Future<Map<String, dynamic>?> readSecret(String slot) async {
    try {
      final Map<String, dynamic>? r = await _c
          .from('nx_match_secrets')
          .select('data')
          .eq('match_id', matchId)
          .eq('user_id', _uid)
          .eq('slot', slot)
          .maybeSingle();
      final dynamic d = r?['data'];
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void verify(int seq, String? expected, String actual) {
    if (expected == null || expected == actual) return;
    _desyncs++;
    debugPrint('NEXORA desync at seq $seq: expected $expected got $actual');
  }

  /// Report the final result (first report wins server-side; all phones computed the same state).
  Future<MatchEnd?> report(List<int> winners, List<int>? scores, {String? hash}) async {
    try {
      await _c.rpc('nx_finish_match', params: <String, dynamic>{
        'p_match': matchId,
        'p_winners': winners,
        'p_scores': scores,
        'p_hash': hash,
        'p_reason': 'finished',
      });
      final Map<String, dynamic>? m =
          await _c.from('nx_matches').select('status, winner_seats, reason, scores').eq('id', matchId).maybeSingle();
      if (m != null) {
        _status = '${m['status']}';
        _end = _endFrom(m);
      }
      return _end;
    } catch (e) {
      debugPrint('report failed: $e');
      return null;
    }
  }

  /// Leave the running match (counts as forfeit).
  Future<void> forfeit() async {
    if (isOver) return;
    try {
      await _c.rpc('nx_forfeit', params: <String, dynamic>{'p_match': matchId});
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _listener = null;
    _poll?.cancel();
    _watch?.cancel();
    final RealtimeChannel? ch = _ch;
    if (ch != null) unawaited(_c.removeChannel(ch));
    unawaited(_live.close());
    resyncRequests.dispose();
    super.dispose();
  }
}
