import 'dart:async';

import 'package:flutter/foundation.dart';

/// ===================== NEXORA ONLINE MATCH LINK =====================
/// Transport-agnostic seam between a game widget and the online match.
///
/// Model: every phone runs the SAME pure-Dart core with the SAME seed. Players only
/// exchange inputs ("moves"). The server keeps one ordered move log (seq 1,2,3…;
/// first writer wins), so every phone applies the same moves in the same order.
///  * Seats are GLOBAL (0..n-1, host = 0). [mySeat] is this phone's seat.
///  * A game sends a move for its own seat with [send] and applies it locally at once.
///  * [listen] delivers every other move in order. After a (re)join the whole log is
///    replayed first with [NetMove.replay] = true (apply instantly, no animation), then
///    `onReplayDone` fires and live moves follow.
///  * Physics games: the authority ([isAuthority]) posts a 'snap' (full snapshot +
///    hash) after each shot settles; everyone adopts it, so the boards never drift.
///  * [hashOf] gives a stable FNV-1a hash of a state string (platform independent).
/// =====================================================================

class NetMove {
  const NetMove({
    required this.seq,
    required this.seat,
    required this.kind,
    required this.data,
    this.hash,
    this.replay = false,
  });

  final int seq;
  final int seat;

  /// 'move' | 'snap' | 'forfeit' | 'timeout' | 'system'
  final String kind;
  final Map<String, dynamic> data;
  final String? hash;
  final bool replay;

  bool get isForfeit => kind == 'forfeit';
  bool get isSnap => kind == 'snap';
  bool get isTimeout => kind == 'timeout';
}

abstract class NetLink {
  String get matchId;
  int get mySeat;
  int get seatCount;
  int get seed;
  Map<String, dynamic> get settings;

  /// Display names per global seat.
  List<String> get names;

  /// Seats currently connected (Realtime presence).
  Set<int> get connectedSeats;

  /// Seats that left / forfeited (they are skipped by turn order).
  Set<int> get forfeitedSeats;

  /// The lowest connected, non-forfeited seat. Posts snapshots and handles absent players.
  bool get isAuthority;

  /// Fires when presence / authority / forfeits change.
  Listenable get changes;

  /// True while the history is being replayed into a fresh game.
  bool get replaying;

  /// Register the game. History is replayed first, then [onReplayDone], then live moves.
  void listen(void Function(NetMove move) onMove, {VoidCallback? onReplayDone});

  /// Send an input for [asSeat] (defaults to [mySeat]). Applied locally by the caller.
  Future<bool> send(Map<String, dynamic> data, {String kind = 'move', String? hash, int? asSeat});

  /// Ephemeral, unordered real-time messages (aim previews, emotes, chat). Not logged.
  void sendLive(String event, Map<String, dynamic> data);
  Stream<NetLiveMessage> get live;

  /// Tell the link whose turn it is (lets the authority time out absent players).
  set turnSeat(int? seat);

  /// Private per-player data (e.g. Mafia roles): only the addressee can read it.
  Future<void> putSecret(int seat, String slot, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> readSecret(String slot);

  /// Report a state hash after applying a move; mismatches are counted (diagnostics).
  void verify(int seq, String? expected, String actual);

  /// Number of hash mismatches seen (0 means every phone agreed).
  int get desyncs;
}

class NetLiveMessage {
  const NetLiveMessage(this.seat, this.event, this.data);
  final int seat;
  final String event;
  final Map<String, dynamic> data;
}

/// Stable 32-bit FNV-1a hash rendered as hex (identical on every platform).
String hashOf(String s) {
  int h = 0x811c9dc5;
  for (int i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i) & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
    h ^= (s.codeUnitAt(i) >> 8) & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// Processes incoming moves strictly one at a time (awaiting animations between them).
class NetInbox {
  NetInbox(this._handle);

  final Future<void> Function(NetMove m) _handle;
  final List<NetMove> _queue = <NetMove>[];
  bool _running = false;
  bool _closed = false;

  void add(NetMove m) {
    if (_closed) return;
    _queue.add(m);
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && !_closed) {
        final NetMove m = _queue.removeAt(0);
        try {
          await _handle(m);
        } catch (e) {
          debugPrint('net move ${m.seq} failed: $e');
        }
      }
    } finally {
      _running = false;
    }
  }

  void close() {
    _closed = true;
    _queue.clear();
  }
}
