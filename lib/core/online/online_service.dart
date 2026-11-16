import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/backend_gateway.dart';
import 'online_config.dart';

/// Initialise Supabase once at startup (no network needed: the session is restored from disk).
Future<void> initOnline() async {
  if (!OnlineConfig.enabled) return;
  try {
    await Supabase.initialize(url: OnlineConfig.supabaseUrl, anonKey: OnlineConfig.supabaseAnonKey);
    OnlineService._ready = true;
  } catch (e) {
    debugPrint('NEXORA online init failed: $e');
  }
}

/// Auth + connection state for the whole app.
///
/// * Guest = Supabase anonymous user (created silently once the explorer identity exists).
/// * A guest can upgrade to email + password and keeps the same account (same uid, same progress).
/// * Offline / no config: [status] stays [BackendStatus.offline] and every world keeps working locally.
class OnlineService extends ChangeNotifier {
  OnlineService() {
    if (!_ready) return;
    _sub = client!.auth.onAuthStateChange.listen((AuthState s) {
      _status = s.session != null ? BackendStatus.online : BackendStatus.offline;
      notifyListeners();
    }, onError: (Object e) => debugPrint('auth stream: $e'));
    if (client!.auth.currentSession != null) _status = BackendStatus.online;
  }

  static bool _ready = false;
  StreamSubscription<AuthState>? _sub;
  BackendStatus _status = BackendStatus.offline;
  String? lastError;
  bool busy = false;

  bool get configured => _ready;
  SupabaseClient? get client => _ready ? Supabase.instance.client : null;
  BackendStatus get status => _status;
  bool get isOnline => _status == BackendStatus.online && user != null;
  User? get user => client?.auth.currentUser;
  String? get uid => user?.id;
  bool get isGuest => user?.isAnonymous ?? true;
  String? get email => user?.email;

  /// Make sure there is a session; creates a guest account the first time.
  Future<bool> ensureSession() async {
    final SupabaseClient? c = client;
    if (c == null) return false;
    if (c.auth.currentSession != null) {
      _status = BackendStatus.online;
      return true;
    }
    _status = BackendStatus.connecting;
    notifyListeners();
    try {
      await c.auth.signInAnonymously();
      _status = BackendStatus.online;
      lastError = null;
    } catch (e) {
      _status = BackendStatus.offline;
      lastError = '$e';
    }
    notifyListeners();
    return _status == BackendStatus.online;
  }

  String _friendly(Object e) {
    if (e is AuthException) {
      final String m = e.message.toLowerCase();
      if (m.contains('invalid login')) return 'invalid_login';
      if (m.contains('already') || m.contains('registered')) return 'email_taken';
      if (m.contains('password')) return 'weak_password';
      return e.message;
    }
    final String s = '$e';
    if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException')) {
      return 'network';
    }
    return s;
  }

  Future<T?> _run<T>(Future<T> Function(SupabaseClient c) f) async {
    final SupabaseClient? c = client;
    if (c == null) {
      lastError = 'not_configured';
      return null;
    }
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final T r = await f(c);
      return r;
    } catch (e) {
      lastError = _friendly(e);
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Guest → permanent account (same uid, all progress kept). Without a guest: new account.
  Future<bool> registerEmail(String email, String password, {String? username}) async {
    final bool? ok = await _run<bool>((SupabaseClient c) async {
      final User? u = c.auth.currentUser;
      if (u != null && u.isAnonymous) {
        await c.auth.updateUser(UserAttributes(email: email.trim(), password: password));
      } else {
        await c.auth.signUp(
          email: email.trim(),
          password: password,
          data: username == null ? null : <String, dynamic>{'username': username},
        );
      }
      return true;
    });
    return ok ?? false;
  }

  Future<bool> signInEmail(String email, String password) async {
    final bool? ok = await _run<bool>((SupabaseClient c) async {
      await c.auth.signInWithPassword(email: email.trim(), password: password);
      return true;
    });
    return ok ?? false;
  }

  Future<bool> resetPassword(String email) async {
    final bool? ok = await _run<bool>((SupabaseClient c) async {
      await c.auth.resetPasswordForEmail(email.trim());
      return true;
    });
    return ok ?? false;
  }

  /// Sign out, then continue as a fresh guest so online play keeps working.
  Future<void> signOut({bool continueAsGuest = true}) async {
    await _run<bool>((SupabaseClient c) async {
      await c.auth.signOut();
      return true;
    });
    if (continueAsGuest) await ensureSession();
  }

  /// Small helper for RPC calls that should never throw into the UI.
  Future<dynamic> rpc(String fn, [Map<String, dynamic>? params]) async {
    final SupabaseClient? c = client;
    if (c == null || c.auth.currentSession == null) return null;
    return c.rpc(fn, params: params);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final onlineProvider = ChangeNotifierProvider<OnlineService>((ref) => OnlineService());
