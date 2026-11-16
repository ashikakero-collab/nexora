/// Backend seam for going online later (P17, P21, P23, P24, P25).
///
/// Offline build: [OfflineBackend] — everything is local and honest about it.
/// Online build (owner, later): implement [BackendGateway] with Supabase
/// (supabase_flutter) + LiveKit (livekit_client) and swap it in `backendProvider`.
/// See docs/ONLINE_SETUP.md for the exact steps and the SQL in supabase/migrations.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../online/online_service.dart';
import 'supabase_backend.dart';

enum BackendStatus { offline, connecting, online }

abstract class BackendGateway {
  BackendStatus get status;
  bool get isOnline => status == BackendStatus.online;

  /// Auth (STEP_08): email OTP / Google. Offline: unsupported.
  Future<bool> signInWithEmailOtp(String email);

  /// Server-authoritative XP (STEP_13): send raw event, server validates.
  Future<void> submitXpEvent(String event, {required String idempotencyKey});

  /// Online match shot / move submission (STEP_17).
  Future<Map<String, dynamic>?> submitMove(String gameId, String matchId, Map<String, dynamic> move);

  /// Short-lived LiveKit token minted by an Edge Function (STEP_24).
  Future<String?> liveKitToken(String room);

  /// LLM reply through Edge Function (STEP_27). Offline returns null.
  Future<String?> oracleRemote(String prompt, {required String languageCode});
}

class OfflineBackend extends BackendGateway {
  @override
  BackendStatus get status => BackendStatus.offline;

  @override
  Future<bool> signInWithEmailOtp(String email) async => false;

  @override
  Future<void> submitXpEvent(String event, {required String idempotencyKey}) async {}

  @override
  Future<Map<String, dynamic>?> submitMove(String gameId, String matchId, Map<String, dynamic> move) async => null;

  @override
  Future<String?> liveKitToken(String room) async => null;

  @override
  Future<String?> oracleRemote(String prompt, {required String languageCode}) async => null;
}

/// Supabase when the build carries the online config, otherwise the honest offline backend.
final backendProvider = Provider<BackendGateway>((ref) {
  final OnlineService online = ref.watch(onlineProvider);
  if (!online.configured) return OfflineBackend();
  return SupabaseBackend(online);
});
