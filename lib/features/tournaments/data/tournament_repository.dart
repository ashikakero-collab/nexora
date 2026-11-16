import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/online/online_service.dart';
import 'models.dart';

/// Result of an RPC that answers {ok, error, ...}.
class TResult {
  const TResult(this.ok, this.error, this.data);
  final bool ok;
  final String? error;
  final Map<String, dynamic> data;
}

/// All tournament reads/writes. Every write is a SECURITY DEFINER RPC that checks the caller's role in
/// Postgres (supabase/migrations/20261116000200_nx_tournaments_api.sql); RLS only allows reads.
class TournamentRepository {
  TournamentRepository(this._online);
  final OnlineService _online;

  SupabaseClient? get _c => _online.client;
  String? get uid => _online.uid;
  bool get available => _online.isOnline && _c != null;

  Future<SupabaseClient> _client() async {
    if (_c == null) throw StateError('offline');
    if (!_online.isOnline) await _online.ensureSession();
    return _c!;
  }

  static const String _entrySelect =
      'tournament_id, user_id, status, seed, group_no, rating, place, paid_coins, paid_gems, note, created_at, profiles(username)';

  Future<List<Tournament>> list() async {
    final SupabaseClient c = await _client();
    final List<dynamic> rows = await c.from('nx_tournaments').select().order('start_at').limit(300);
    return rows.map((dynamic r) => Tournament(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<Tournament?> get(String id) async {
    final SupabaseClient c = await _client();
    final Map<String, dynamic>? r = await c.from('nx_tournaments').select().eq('id', id).maybeSingle();
    return r == null ? null : Tournament(r);
  }

  /// My entries: tournament id → entry.
  Future<Map<String, TEntry>> myEntries() async {
    final SupabaseClient c = await _client();
    final String? me = uid;
    if (me == null) return <String, TEntry>{};
    final List<dynamic> rows = await c.from('nx_t_entries').select(_entrySelect).eq('user_id', me).limit(500);
    return <String, TEntry>{
      for (final dynamic r in rows) '${(r as Map)['tournament_id']}': TEntry(Map<String, dynamic>.from(r)),
    };
  }

  Future<List<TEntry>> entries(String t) async {
    final SupabaseClient c = await _client();
    final List<dynamic> rows =
        await c.from('nx_t_entries').select(_entrySelect).eq('tournament_id', t).order('created_at').limit(500);
    return rows.map((dynamic r) => TEntry(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<List<TMatch>> matches(String t) async {
    final SupabaseClient c = await _client();
    final List<dynamic> rows = await c
        .from('nx_t_matches')
        .select()
        .eq('tournament_id', t)
        .order('round')
        .order('idx')
        .limit(1000);
    return rows.map((dynamic r) => TMatch(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Matches of mine across tournaments that still need me (scheduled / ready check / playing / disputed).
  Future<List<TMatch>> myOpenMatches() async {
    final SupabaseClient c = await _client();
    final String? me = uid;
    if (me == null) return <TMatch>[];
    final List<dynamic> rows = await c
        .from('nx_t_matches')
        .select()
        .or('p1.eq.$me,p2.eq.$me')
        .inFilter('status', <String>['scheduled', 'ready_check', 'playing', 'disputed'])
        .order('scheduled_at')
        .limit(50);
    return rows.map((dynamic r) => TMatch(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<List<StandingRow>> standings(String t) async {
    final SupabaseClient c = await _client();
    final dynamic rows = await c.rpc('nx_t_standings', params: <String, dynamic>{'p_t': t});
    if (rows is! List) return <StandingRow>[];
    return rows.map((dynamic r) => StandingRow(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<List<TCode>> codes(String t) async {
    final SupabaseClient c = await _client();
    final List<dynamic> rows =
        await c.from('nx_t_codes').select().eq('tournament_id', t).order('created_at', ascending: false).limit(300);
    return rows.map((dynamic r) => TCode(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<Map<String, String>> names(Iterable<String> ids) async {
    final List<String> list = ids.toSet().toList();
    if (list.isEmpty) return <String, String>{};
    final SupabaseClient c = await _client();
    final List<dynamic> rows = await c.from('profiles').select('id, username').inFilter('id', list);
    return <String, String>{for (final dynamic r in rows) '${(r as Map)['id']}': '${r['username'] ?? 'Pilot'}'};
  }

  Future<List<Map<String, dynamic>>> searchUsers(String q) async {
    final SupabaseClient c = await _client();
    final List<dynamic> rows = await c.from('profiles').select('id, username').ilike('username', '%$q%').limit(20);
    return rows.map((dynamic r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<List<TNotification>> notifications() async {
    final SupabaseClient c = await _client();
    final String? me = uid;
    if (me == null) return <TNotification>[];
    final List<dynamic> rows = await c
        .from('nx_t_notifications')
        .select()
        .eq('user_id', me)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map((dynamic r) => TNotification(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<void> markRead() async {
    final SupabaseClient c = await _client();
    await c.rpc('nx_t_mark_read');
  }

  Future<({bool admin, bool organizer})> myRole() async {
    try {
      final SupabaseClient c = await _client();
      final dynamic r = await c.rpc('nx_t_my_role');
      if (r is Map) return (admin: r['admin'] == true, organizer: r['organizer'] == true);
    } catch (e) {
      debugPrint('role: $e');
    }
    return (admin: false, organizer: false);
  }

  Future<Map<String, dynamic>> logs(String t) async {
    final SupabaseClient c = await _client();
    final dynamic r = await c.rpc('nx_t_logs', params: <String, dynamic>{'p_t': t});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  Future<TResult> _call(String fn, Map<String, dynamic> params) async {
    try {
      final SupabaseClient c = await _client();
      final dynamic r = await c.rpc(fn, params: params);
      if (r is Map) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(r);
        return TResult(m['ok'] == true, m['error'] as String?, m);
      }
      return TResult(true, null, <String, dynamic>{'value': r});
    } on PostgrestException catch (e) {
      return TResult(false, e.message, const <String, dynamic>{});
    } catch (e) {
      return TResult(false, e is StateError ? 'offline' : 'network', const <String, dynamic>{});
    }
  }

  Future<TResult> save(Map<String, dynamic> p) => _call('nx_t_save', <String, dynamic>{'p': p});
  Future<TResult> admin(String t, String action, [String? reason]) =>
      _call('nx_t_admin', <String, dynamic>{'p_t': t, 'p_action': action, 'p_reason': reason});
  Future<TResult> register(String t, [String? code]) =>
      _call('nx_t_register', <String, dynamic>{'p_t': t, 'p_code': code});
  Future<TResult> joinCode(String code) => _call('nx_t_join_code', <String, dynamic>{'p_code': code});
  Future<TResult> withdraw(String t) => _call('nx_t_withdraw', <String, dynamic>{'p_t': t});
  Future<TResult> decide(String t, String user, bool approve, [String? note]) => _call('nx_t_decide',
      <String, dynamic>{'p_t': t, 'p_user': user, 'p_approve': approve, 'p_note': note});
  Future<TResult> removeEntry(String t, String user, [String? note]) =>
      _call('nx_t_remove_entry', <String, dynamic>{'p_t': t, 'p_user': user, 'p_note': note});
  Future<TResult> setSeed(String t, String user, int seed) =>
      _call('nx_t_set_seed', <String, dynamic>{'p_t': t, 'p_user': user, 'p_seed': seed});
  Future<TResult> createCodes(String t, {int maxUses = 1, DateTime? expiresAt, bool requiresApproval = false, int count = 1}) =>
      _call('nx_t_code_create', <String, dynamic>{
        'p_t': t,
        'p_max_uses': maxUses,
        'p_expires_at': expiresAt?.toUtc().toIso8601String(),
        'p_requires_approval': requiresApproval,
        'p_count': count,
      });
  Future<TResult> revokeCode(String id) => _call('nx_t_code_revoke', <String, dynamic>{'p_code': id});
  Future<TResult> ready(String m) => _call('nx_t_ready', <String, dynamic>{'p_m': m});
  Future<TResult> report(String gameMatch, int winnerSeat, int s0, int s1) => _call('nx_t_report',
      <String, dynamic>{'p_game': gameMatch, 'p_winner_seat': winnerSeat, 'p_s0': s0, 'p_s1': s1});
  Future<TResult> dispute(String m, String reason) =>
      _call('nx_t_dispute', <String, dynamic>{'p_m': m, 'p_reason': reason});
  Future<TResult> adminMatch(String? m, String action, Map<String, dynamic> p) =>
      _call('nx_t_admin_match', <String, dynamic>{'p_m': m, 'p_action': action, 'p': p});
  Future<TResult> setRunner(String t, String user, bool add) =>
      _call('nx_t_set_runner', <String, dynamic>{'p_t': t, 'p_user': user, 'p_add': add});
  Future<TResult> setStaff(String user, String? role) =>
      _call('nx_t_set_staff', <String, dynamic>{'p_user': user, 'p_role': role});

  /// Realtime changes of one tournament (matches, entries, the row itself). Returns a cancel function.
  VoidCallback watchTournament(String t, VoidCallback onChange) {
    final SupabaseClient? c = _c;
    if (c == null) return () {};
    Timer? debounce;
    void fire() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 350), onChange);
    }

    final RealtimeChannel ch = c
        .channel('nxt:$t:${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nx_t_matches',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'tournament_id', value: t),
          callback: (_) => fire(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nx_t_entries',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'tournament_id', value: t),
          callback: (_) => fire(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'nx_tournaments',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: t),
          callback: (_) => fire(),
        )
        .subscribe();
    return () {
      debounce?.cancel();
      unawaited(c.removeChannel(ch));
    };
  }
}

final tournamentRepoProvider = Provider<TournamentRepository>((ref) => TournamentRepository(ref.watch(onlineProvider)));

/// Bilingual text for server error codes.
String tErrorText(String? code, bool fa) {
  String t(String f, String e) => fa ? f : e;
  return switch (code) {
    'not_signed_in' || 'offline' => t('اول آنلاین شو', 'Go online first'),
    'forbidden' => t('اجازه‌ی این کار را نداری', 'You are not allowed to do that'),
    'registration_closed' => t('ثبت‌نام بسته است', 'Registration is closed'),
    'code_required' => t('این تورنمنت کد دعوت لازم دارد', 'This tournament needs an invite code'),
    'bad_code' => t('کد اشتباه است', 'Wrong code'),
    'code_expired' => t('کد منقضی شده', 'The code has expired'),
    'code_used_up' => t('ظرفیت این کد پر شده', 'This code has been used up'),
    'code_revoked' => t('این کد باطل شده', 'This code was revoked'),
    'too_many_attempts' => t('تلاش‌های اشتباه زیاد بود؛ ۱۵ دقیقه بعد دوباره امتحان کن', 'Too many wrong tries; try again in 15 minutes'),
    'insufficient_funds' => t('سکه/جم کافی نداری', 'Not enough coins/gems'),
    'min_level' => t('سطحت کافی نیست', 'Your level is too low'),
    'min_xp' => t('XP کافی نداری', 'Not enough XP'),
    'min_rating' => t('امتیاز رتبه‌ات کافی نیست', 'Your rating is too low'),
    'not_allowed' => t('ثبت‌نام تو در این تورنمنت مجاز نیست', 'You cannot register for this tournament'),
    'too_late' => t('دیگر نمی‌شود', 'Too late for that'),
    'not_ready_time' => t('هنوز وقت آمادگی این بازی نرسیده', 'This match is not open yet'),
    'paused' => t('تورنمنت متوقف است', 'The tournament is paused'),
    'fee_locked' => t('بعد از پرداخت ورودیه‌ها، مبلغ ورودی قابل تغییر نیست', 'The entry fee is locked once players have paid'),
    'fixed_prize_admin_only' => t('جایزه‌ی ثابت فقط توسط ادمین', 'Only an admin can set a fixed prize'),
    'bad_times' => t('ترتیب زمان‌ها درست نیست', 'The times are not in order'),
    'bad_distribution' => t('جمع درصد جوایز بیشتر از ۱۰۰ است', 'Prize percentages add up to more than 100'),
    'downstream_started' => t('بازی بعدی شروع شده؛ اصلاح ممکن نیست', 'The next match already started'),
    'groups_need_4' => t('حالت گروهی حداقل ۴ نفر لازم دارد', 'Groups need at least 4 players'),
    _ => code == null ? t('خطا', 'Error') : code,
  };
}
