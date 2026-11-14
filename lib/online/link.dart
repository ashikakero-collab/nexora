// Port of src/online/link.ts: one realtime connection per joined room, shared by the lobby and the online match.
//  - postgres_changes on rooms / room_players  -> refetch room state (debounced)
//  - broadcast 'chat'                           -> text chat
//  - broadcast 'g'                              -> match netcode (online_match.dart)
//  - broadcast 'sync'                           -> "please refetch" pings
//  - broadcast 'pi'/'po'                        -> RTT probe (never touches the DB)
//  - presence (key = user id)                   -> who is connected right now
// Additive (Flutter): presence payload carries {c: 'fl', v: 2} so a Flutter host knows every peer understands
// the low-bandwidth lockstep protocol; RN peers simply ignore the extra keys.
// v4 adds 'pv' (protocol/physics version, kProtoVersion): Flutter peers with another pv can't share a match.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/sound.dart';
import '../core/store.dart';
import '../net/supabase.dart';
import 'netcode.dart' show kProtoVersion, protoCheck;
import 'voice.dart';

class ChatMsg {
  final String id, uid, name, text;
  final int ts;
  ChatMsg(this.id, this.uid, this.name, this.text, this.ts);
  Map<String, dynamic> toJson() => {'id': id, 'uid': uid, 'name': name, 'text': text, 'ts': ts};
}

class Peer {
  final String name;
  final bool flutter;
  final int? form; // v4: formation index advertised in presence ('f'), null for older builds
  final int? pv; // v4: protocol/physics version advertised in presence ('pv'); null = Flutter v1-v3 or RN/Godot
  const Peer(this.name, this.flutter, [this.form, this.pv]);
}

class RoomLink extends ChangeNotifier {
  final String id, me;
  String myName;
  Rec? room;
  List<Rec> players = [];
  Map<String, Peer> online = {};
  List<ChatMsg> chat = [];
  bool connected = false, loaded = false, gone = false;
  int unread = 0;
  int? rtt;
  bool chatOpen = false;
  late final Voice voice = Voice(id);

  RealtimeChannel? _ch;
  Timer? _soon, _poll, _beat, _pinger;
  bool _dead = false;
  final Set<String> _seen = {};
  final List<void Function(Map<String, dynamic> m, String? from)> _gl = [];
  final List<VoidCallback> _onReconnect = [];
  bool _wasConnected = false;

  // traffic counters for the debug overlay
  int sentMsgs = 0, recvMsgs = 0, sentBytes = 0;

  /// v4 handshake guard: null when every Flutter peer in the room runs this protocol version, else the
  /// Persian "please update" message to show (see protoCheck in netcode.dart).
  String? get protoBlock => protoCheck(me: me, online: {for (final e in online.entries) e.key: (e.value.flutter, e.value.pv)});

  RoomLink(this.id, this.me, this.myName) {
    _connect();
    refresh();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => refresh());
    // server sweeps players without a heartbeat for 45 s
    _beat = Timer.periodic(const Duration(seconds: 15), (_) => _heartbeat());
    _heartbeat();
    _pinger = Timer.periodic(const Duration(seconds: 3), (_) => _probe());
  }

  void _heartbeat() => rpc('heartbeat', {'p_room': id}).then((_) {}, onError: (_) {});

  bool get allFlutter => online.entries.where((e) => e.key != me).every((e) => e.value.flutter);

  static Map<String, dynamic> _inner(Map<String, dynamic> p) => p['payload'] is Map ? Map<String, dynamic>.from(p['payload'] as Map) : p;

  void _connect() {
    final ch = sb.channel('room:$id', opts: RealtimeChannelConfig(self: false, ack: false, key: me, enabled: true));
    ch
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'rooms',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
            callback: (_) => soon())
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'room_players',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: id),
            callback: (_) => soon())
        .onBroadcast(event: 'sync', callback: (_) => soon())
        .onBroadcast(event: 'chat', callback: (p) => _addChat(_inner(p)))
        .onBroadcast(
            event: 'pi',
            callback: (p) {
              final m = _inner(p);
              if (m['to'] == me) _send('po', {'t': m['t'], 'to': m['f']});
            })
        .onBroadcast(
            event: 'po',
            callback: (p) {
              final m = _inner(p);
              if (m['to'] != me || m['t'] is! num) return;
              final r = math.max(1, DateTime.now().millisecondsSinceEpoch - (m['t'] as num).toInt());
              if (r > 10000) return;
              rtt = rtt == null ? r : (rtt! * .6 + r * .4).round();
              notifyListeners();
            })
        .onBroadcast(
            event: 'g',
            callback: (p) {
              final m = _inner(p);
              recvMsgs++;
              final from = m['from']?.toString();
              for (final f in List.of(_gl)) {
                f(m, from);
              }
            })
        .onPresenceSync((_) {
          final ps = ch.presenceState();
          final on = <String, Peer>{};
          for (final s in ps) {
            final pl = s.presences.isNotEmpty ? s.presences.first.payload : const <String, dynamic>{};
            on[s.key] = Peer(pl['name']?.toString() ?? '', pl['c'] == 'fl', pl['f'] is num ? (pl['f'] as num).toInt() : null, pl['pv'] is num ? (pl['pv'] as num).toInt() : null);
          }
          for (final k in on.keys) {
            if (!_seen.contains(k)) {
              _seen.add(k);
              if (k != me && connected) sfx(Snd.join);
            }
          }
          for (final k in _seen.toList()) {
            if (!on.containsKey(k)) {
              _seen.remove(k);
              if (k != me) sfx(Snd.leave);
            }
          }
          online = on;
          notifyListeners();
          soon();
        })
        .subscribe((st, _) async {
          if (_dead) return;
          if (st == RealtimeSubscribeStatus.subscribed) {
            connected = true;
            notifyListeners();
            try {
              await ch.track({'name': myName, 'c': 'fl', 'v': 2, 'f': Store.i.p.form, 'pv': kProtoVersion});
            } catch (_) {}
            refresh();
            if (_wasConnected) {
              for (final f in List.of(_onReconnect)) {
                f();
              }
            }
            _wasConnected = true;
          } else {
            connected = false;
            notifyListeners();
          }
        });
    _ch = ch;
  }

  void _probe() {
    if (_ch == null || !connected) return;
    final host = room?.str('host');
    final to = host != null && host != me && online.containsKey(host) ? host : online.keys.where((k) => k != me).firstOrNull;
    if (to == null) {
      if (rtt != null) {
        rtt = null;
        notifyListeners();
      }
      return;
    }
    _send('pi', {'t': DateTime.now().millisecondsSinceEpoch, 'f': me, 'to': to});
  }

  void _send(String event, Map<String, dynamic> payload) {
    final ch = _ch;
    if (ch == null) return;
    ch.sendBroadcastMessage(event: event, payload: payload).then((_) {}, onError: (_) {});
  }

  void soon() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 150), refresh);
  }

  Future<void> refresh() async {
    if (_dead) return;
    try {
      final r = await Future.wait([
        sb.from('rooms').select().eq('id', id).maybeSingle(),
        sb.from('room_players').select('*, profiles(username, avatar, avatar_url, level, rating, league, equipped_disc)').eq('room_id', id).order('joined_at'),
      ]);
      if (_dead) return;
      final ps = recs(r[1]);
      room = r[0] == null ? room : Rec.of(r[0]);
      players = ps;
      loaded = true;
      gone = r[0] == null || !ps.any((x) => x.s('user_id') == me);
      notifyListeners();
    } catch (_) {}
  }

  void ping() => _send('sync', {});

  void _addChat(Map<String, dynamic> c) {
    if (c['text'] is! String) return;
    final t = c['text'] as String;
    final m = ChatMsg(c['id']?.toString() ?? '${DateTime.now().millisecondsSinceEpoch}', c['uid']?.toString() ?? '', c['name']?.toString() ?? '', t.substring(0, math.min(200, t.length)),
        (c['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch);
    chat = [...chat, m];
    if (chat.length > 80) chat = chat.sublist(chat.length - 80);
    if (m.uid != me) sfx(Snd.chat);
    unread = chatOpen || m.uid == me ? 0 : unread + 1;
    notifyListeners();
  }

  void sendChat(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final c = ChatMsg('${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 30).toRadixString(36)}', me, myName, t.substring(0, math.min(200, t.length)), DateTime.now().millisecondsSinceEpoch);
    _addChat(c.toJson());
    _send('chat', c.toJson());
  }

  void markRead() {
    if (unread > 0) {
      unread = 0;
      notifyListeners();
    }
  }

  VoidCallback onGame(void Function(Map<String, dynamic> m, String? from) f) {
    _gl.add(f);
    return () => _gl.remove(f);
  }

  VoidCallback onReconnect(VoidCallback f) {
    _onReconnect.add(f);
    return () => _onReconnect.remove(f);
  }

  void sendGame(Map<String, dynamic> m) {
    sentMsgs++;
    _send('g', {...m, 'from': me});
  }

  @override
  void dispose() {
    _dead = true;
    _soon?.cancel();
    _poll?.cancel();
    _beat?.cancel();
    _pinger?.cancel();
    voice.destroy();
    final c = _ch;
    _ch = null;
    if (c != null) {
      // untrack may fail on a dead socket; always remove the channel afterwards, swallow both errors
      c.untrack().then((_) {}, onError: (_) {}).whenComplete(() => sb.removeChannel(c).then((_) {}, onError: (_) {}));
    }
    _gl.clear();
    super.dispose();
  }
}
