import 'package:supabase_flutter/supabase_flutter.dart';

import '../online/online_service.dart';
import 'backend_gateway.dart';

/// Online implementation of [BackendGateway] (Supabase + Edge Functions).
class SupabaseBackend extends BackendGateway {
  SupabaseBackend(this._online);

  final OnlineService _online;

  SupabaseClient? get _c => _online.client;

  @override
  BackendStatus get status => _online.status;

  @override
  Future<bool> signInWithEmailOtp(String email) async {
    final SupabaseClient? c = _c;
    if (c == null) return false;
    try {
      await c.auth.signInWithOtp(email: email.trim(), shouldCreateUser: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> submitXpEvent(String event, {required String idempotencyKey}) async {
    try {
      await _online.rpc('nx_award', <String, dynamic>{'p_event': event, 'p_xp': 0, 'p_coins': 0, 'p_key': idempotencyKey});
    } catch (_) {}
  }

  @override
  Future<Map<String, dynamic>?> submitMove(String gameId, String matchId, Map<String, dynamic> move) async {
    try {
      final dynamic r = await _online.rpc('nx_push_move', <String, dynamic>{
        'p_match': matchId,
        'p_seq': move['seq'],
        'p_kind': move['kind'] ?? 'move',
        'p_move': move['data'] ?? move,
        'p_hash': move['hash'],
      });
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (_) {
      return null;
    }
  }

  /// Short-lived LiveKit token from the `nx-call-token` Edge Function (Orbit Network calls).
  @override
  Future<String?> liveKitToken(String room) async {
    final Map<String, dynamic>? r = await liveKitGrant(room);
    return r?['token'] as String?;
  }

  Future<Map<String, dynamic>?> liveKitGrant(String room, {bool video = false}) async {
    final SupabaseClient? c = _c;
    if (c == null || c.auth.currentSession == null) return null;
    try {
      final FunctionResponse r = await c.functions.invoke('nx-call-token', body: <String, dynamic>{'room': room, 'video': video});
      final dynamic d = r.data;
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  /// ORACLE remote replies through the existing `oracle-chat` Edge Function (key lives server-side).
  @override
  Future<String?> oracleRemote(String prompt, {required String languageCode}) async {
    final Map<String, dynamic>? r = await oracleInvoke(<String, dynamic>{
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': prompt},
      ],
      'ctx': <String, dynamic>{'app': 'NEXORA hub (Flutter); answer in text only', 'language': languageCode},
    });
    final Object? m = r?['message'];
    return m is Map ? m['content'] as String? : null;
  }

  /// Raw call to `oracle-chat` (JSON in → JSON out). Throws on network/HTTP errors.
  Future<Map<String, dynamic>?> oracleInvoke(Map<String, dynamic> body) async {
    final SupabaseClient? c = _c;
    if (c == null || c.auth.currentSession == null) return null;
    final FunctionResponse r = await c.functions.invoke('oracle-chat', body: body).timeout(const Duration(seconds: 25));
    final dynamic d = r.data;
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }
}
