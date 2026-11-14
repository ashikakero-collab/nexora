// Port of src/net/auth.tsx: guest (anonymous) sign-in on demand, email sign-up/in, guest upgrade,
// password reset/recovery and the live own `profiles` row (Realtime postgres_changes).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase.dart';

const kAuthRedirect = 'nexora://auth';

class Res {
  final bool ok;
  final String? info, error;
  const Res.ok([this.info])
      : ok = true,
        error = null;
  const Res.err(this.error)
      : ok = false,
        info = null;
}

class Auth extends ChangeNotifier {
  Auth._();
  static final Auth i = Auth._();

  Session? session;
  Rec? profile;
  bool recovery = false;
  bool ready = false;
  RealtimeChannel? _ch;
  StreamSubscription<AuthState>? _sub;
  Future<String?>? _ensuring;
  String? _chFor;

  String? get uid => session?.user.id;
  String? get email => session?.user.email;
  bool get isGuest => session != null && (session!.user.isAnonymous || (session!.user.email ?? '').isEmpty);

  void init() {
    if (!supaReady) {
      ready = true;
      return;
    }
    session = sb.auth.currentSession;
    ready = true;
    _sub = sb.auth.onAuthStateChange.listen((s) {
      session = s.session;
      if (s.event == AuthChangeEvent.passwordRecovery) recovery = true;
      if (s.event == AuthChangeEvent.signedOut) profile = null;
      _watchProfile();
      notifyListeners();
    });
    _watchProfile();
  }

  void _watchProfile() {
    final id = uid;
    if (id == _chFor) return;
    _chFor = id;
    if (_ch != null) {
      sb.removeChannel(_ch!);
      _ch = null;
    }
    if (id == null) {
      profile = null;
      notifyListeners();
      return;
    }
    sb.from('profiles').select().eq('id', id).maybeSingle().then((d) {
      if (d != null && uid == id) {
        profile = Rec.of(d);
        notifyListeners();
      }
    }).catchError((_) {});
    sb.from('profiles').update({'online_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id).then((_) {}).catchError((_) {});
    _ch = sb
        .channel('profile:$id')
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'profiles',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
            callback: (pl) {
              profile = (profile ?? const Rec({})).merge(pl.newRecord);
              notifyListeners();
            })
        .subscribe();
  }

  Future<Rec?> refreshProfile() async {
    final id = uid;
    if (id == null) return null;
    try {
      final d = await sb.from('profiles').select().eq('id', id).maybeSingle();
      profile = d == null ? null : Rec.of(d);
      notifyListeners();
      return profile;
    } catch (_) {
      return null;
    }
  }

  /// Guests are signed in anonymously on demand.
  Future<String?> ensure() async {
    if (!supaReady) return null;
    final s = sb.auth.currentSession;
    if (s != null) return s.user.id;
    return _ensuring ??= () async {
      try {
        final r = await sb.auth.signInAnonymously();
        return r.user?.id;
      } finally {
        _ensuring = null;
      }
    }();
  }

  Future<Res> _wrap(Future<Res> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      return Res.err(errFa(e));
    }
  }

  Future<Res> signUp(String email, String password) => _wrap(() async {
        final r = await sb.auth.signUp(email: email.trim(), password: password, emailRedirectTo: kAuthRedirect);
        return r.session == null ? const Res.ok('confirm') : const Res.ok();
      });

  Future<Res> signIn(String email, String password) => _wrap(() async {
        await sb.auth.signInWithPassword(email: email.trim(), password: password);
        return const Res.ok();
      });

  Future<Res> upgrade(String email, String password) => _wrap(() async {
        await sb.auth.updateUser(UserAttributes(email: email.trim(), password: password), emailRedirectTo: kAuthRedirect);
        return const Res.ok('confirm');
      });

  Future<Res> resetPassword(String email) => _wrap(() async {
        await sb.auth.resetPasswordForEmail(email.trim(), redirectTo: kAuthRedirect);
        return const Res.ok();
      });

  Future<Res> setNewPassword(String password) => _wrap(() async {
        await sb.auth.updateUser(UserAttributes(password: password));
        recovery = false;
        notifyListeners();
        return const Res.ok();
      });

  Future<Res> resend(String email) => _wrap(() async {
        await sb.auth.resend(type: OtpType.signup, email: email.trim(), emailRedirectTo: kAuthRedirect);
        return const Res.ok();
      });

  Future<void> signOut() async {
    try {
      await rpc('leave_all_rooms');
    } catch (_) {}
    try {
      await sb.auth.signOut();
    } catch (_) {}
    profile = null;
    notifyListeners();
  }

  Future<Res> setUsername(String name) => _wrap(() async {
        final n = name.trim();
        if (n.length < 3 || n.length > 20) return const Res.err('نام کاربری باید ۳ تا ۲۰ کاراکتر باشد');
        if (!RegExp(r'^[A-Za-z0-9_.\- \u0600-\u06FF\u200c]+$').hasMatch(n)) return const Res.err('فقط حروف، عدد، فاصله و _ . - مجاز است');
        final id = uid;
        if (id == null) return const Res.err('اول وارد حساب شو');
        await sb.from('profiles').update({'username': n}).eq('id', id);
        profile = profile?.merge({'username': n});
        notifyListeners();
        return const Res.ok();
      });

  void endRecovery() {
    recovery = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
