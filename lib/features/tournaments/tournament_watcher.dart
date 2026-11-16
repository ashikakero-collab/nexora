import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/online/online_service.dart';
import '../../core/settings/app_settings.dart';
import 'data/models.dart';
import 'data/tournament_repository.dart';

/// Device notifications (the app has no FCM): immediate ones for tournament events that arrive while the
/// app runs in the background, and scheduled 10-minute reminders that fire even when the app is closed.
class TLocalNotifier {
  TLocalNotifier._();
  static final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static void Function(String? payload)? onTap;

  static const AndroidNotificationDetails _android = AndroidNotificationDetails(
    'nx_tournaments',
    'Tournaments',
    channelDescription: 'Match ready, reminders, results and prizes',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const NotificationDetails _details = NotificationDetails(android: _android);

  static Future<void> init() async {
    if (_ready || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      tzdata.initializeTimeZones();
      await _p.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (NotificationResponse r) => onTap?.call(r.payload),
      );
      await _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('local notifications unavailable: $e');
    }
  }

  static int idFor(String key) => key.hashCode & 0x3fffffff;

  static Future<void> show(String key, String title, String body, {String? payload}) async {
    if (!_ready) return;
    try {
      await _p.show(idFor(key), title, body, _details, payload: payload);
    } catch (e) {
      debugPrint('notify: $e');
    }
  }

  static Future<void> scheduleAt(String key, DateTime utc, String title, String body, {String? payload}) async {
    if (!_ready || !utc.isAfter(DateTime.now().toUtc().add(const Duration(seconds: 20)))) return;
    try {
      await _p.zonedSchedule(
        idFor(key),
        title,
        body,
        tz.TZDateTime.from(utc.toUtc(), tz.UTC),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      debugPrint('schedule: $e');
    }
  }
}

/// Watches the signed-in player's tournament notifications (Realtime on nx_t_notifications):
/// in-app banner while the app is open, device notification while it is in the background,
/// and keeps the 10-minute reminders of upcoming tournaments / matches scheduled on the device.
class TournamentWatcher with WidgetsBindingObserver {
  TournamentWatcher(this._ref, this._messenger, this._open);

  final WidgetRef _ref;
  final GlobalKey<ScaffoldMessengerState> _messenger;

  /// Opens a route (e.g. /tournaments/<id>).
  final void Function(String route) _open;

  RealtimeChannel? _ch;
  String? _uid;
  bool _foreground = true;
  final Set<int> _seen = <int>{};
  Timer? _reschedule;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    TLocalNotifier.onTap = (String? payload) {
      if (payload != null && payload.startsWith('/')) _open(payload);
    };
    unawaited(TLocalNotifier.init());
    _reschedule = Timer.periodic(const Duration(minutes: 10), (_) => unawaited(_scheduleReminders()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_scheduleReminders());
  }

  void sync() {
    final OnlineService o = _ref.read(onlineProvider);
    final String? uid = o.isOnline ? o.uid : null;
    if (uid == _uid) return;
    _detach();
    _uid = uid;
    final SupabaseClient? c = o.client;
    if (uid == null || c == null) return;
    _ch = c
        .channel('nxtn:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'nx_t_notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (PostgresChangePayload p) => _show(TNotification(p.newRecord)),
        )
        .subscribe();
    unawaited(_scheduleReminders());
  }

  String _text(TNotification n, bool fa) {
    String t(String f, String e) => fa ? f : e;
    return switch (n.kind) {
      'match_ready' => t('بازی‌ات آماده است — «آماده‌ام» را بزن', 'Your match is ready — tap Ready'),
      'match_soon' => t('بازی‌ات ۱۰ دقیقه‌ی دیگر شروع می‌شود', 'Your match starts in 10 minutes'),
      'starting_soon' => t('تورنمنت ۱۰ دقیقه‌ی دیگر شروع می‌شود', 'The tournament starts in 10 minutes'),
      'approved' => t('ثبت‌نامت تأیید شد', 'Registration approved'),
      'promoted' => t('از لیست انتظار وارد شدی', 'You are in from the waitlist'),
      'rejected' => t('ثبت‌نامت رد شد', 'Registration declined'),
      'drawn' => t('قرعه‌کشی انجام شد', 'The draw is done'),
      'started' => t('تورنمنت شروع شد', 'The tournament started'),
      'result' => n.data['draw'] == true ? t('مساوی', 'Draw') : (n.data['won'] == true ? t('بردی!', 'You won!') : t('باختی', 'You lost')),
      'advanced' => t('به دور بعد رفتی', 'You advanced'),
      'eliminated' => t('حذف شدی', 'You were eliminated'),
      'prize' => t('جایزه‌ات واریز شد', 'Your prize was paid'),
      'time_changed' => t('زمان تورنمنت تغییر کرد', 'The schedule changed'),
      'cancelled' => t('تورنمنت لغو شد؛ ورودیه برگشت', 'Tournament cancelled — fee refunded'),
      'refund' => t('ورودیه برگشت داده شد', 'Entry fee refunded'),
      'walkover' => t('بازی واگذار شد', 'Walkover'),
      'dispute' => t('اختلاف در نتیجه', 'Result disputed'),
      'finished' => t('تورنمنت تمام شد', 'Tournament finished'),
      'approval_needed' => t('ثبت‌نام جدید منتظر تأیید', 'New registration to approve'),
      _ => n.kind,
    };
  }

  void _show(TNotification n) {
    if (!_seen.add(n.id)) return;
    final bool fa = _ref.read(settingsProvider).isFa;
    final String body = _text(n, fa);
    final String route = n.tournamentId == null ? '/tournaments' : '/tournaments/${n.tournamentId}';
    // same key as the scheduled reminder → replaces it instead of showing twice
    final String key = switch (n.kind) {
      'starting_soon' => 'soon:${n.tournamentId}',
      'match_soon' => 'msoon:${n.tmatch}',
      _ => 'n:${n.id}',
    };
    if (!_foreground) {
      unawaited(TLocalNotifier.show(key, n.title, body, payload: route));
      return;
    }
    final ScaffoldMessengerState? m = _messenger.currentState;
    if (m == null) return;
    final bool urgent = n.kind == 'match_ready';
    m.showSnackBar(SnackBar(
      duration: Duration(seconds: urgent ? 20 : 6),
      content: Text('🏆 ${n.title}: $body'),
      action: SnackBarAction(label: fa ? 'باز کن' : 'Open', onPressed: () => _open(route)),
    ));
  }

  /// Device-side 10-minute reminders for my approved tournaments and scheduled matches.
  Future<void> _scheduleReminders() async {
    if (_uid == null) return;
    final TournamentRepository repo = _ref.read(tournamentRepoProvider);
    if (!repo.available) return;
    final bool fa = _ref.read(settingsProvider).isFa;
    try {
      final Map<String, TEntry> mine = await repo.myEntries();
      final List<Tournament> all = await repo.list();
      for (final Tournament t in all) {
        final TEntry? e = mine[t.id];
        if (e == null || e.status != 'approved' || t.isOver || t.status == 'live') continue;
        await TLocalNotifier.scheduleAt('soon:${t.id}', t.startAt.subtract(const Duration(minutes: 10)), t.title,
            fa ? 'تورنمنت ۱۰ دقیقه‌ی دیگر شروع می‌شود' : 'The tournament starts in 10 minutes',
            payload: '/tournaments/${t.id}');
      }
      for (final TMatch m in await repo.myOpenMatches()) {
        final DateTime? at = m.scheduledAt;
        if (m.status != 'scheduled' || at == null) continue;
        final String title = all.where((Tournament t) => t.id == m.tournamentId).firstOrNull?.title ?? 'NEXORA';
        await TLocalNotifier.scheduleAt('msoon:${m.id}', at.subtract(const Duration(minutes: 10)), title,
            fa ? 'بازی‌ات ۱۰ دقیقه‌ی دیگر شروع می‌شود' : 'Your match starts in 10 minutes',
            payload: '/tournaments/${m.tournamentId}');
      }
    } catch (e) {
      debugPrint('reminders: $e');
    }
  }

  void _detach() {
    final RealtimeChannel? ch = _ch;
    final SupabaseClient? c = _ref.read(onlineProvider).client;
    if (ch != null && c != null) unawaited(c.removeChannel(ch));
    _ch = null;
  }

  void dispose() {
    _reschedule?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _detach();
  }
}
