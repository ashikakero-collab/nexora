import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../games/game_registry.dart';
import '../settings/app_settings.dart';
import 'online_service.dart';

/// Shows real-time game invitations from friends anywhere in the app.
class InviteWatcher {
  InviteWatcher(this._ref, this._messenger, this._open);

  final WidgetRef _ref;
  final GlobalKey<ScaffoldMessengerState> _messenger;

  /// Opens the online lobby for (gameId, code).
  final void Function(String gameId, String code) _open;

  RealtimeChannel? _ch;
  String? _uid;
  final Set<int> _seen = <int>{};

  void sync() {
    final OnlineService o = _ref.read(onlineProvider);
    final String? uid = o.isOnline ? o.uid : null;
    if (uid == _uid) return;
    _detach();
    _uid = uid;
    final SupabaseClient? c = o.client;
    if (uid == null || c == null) return;
    _ch = c
        .channel('nxinv:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'nx_invites',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'to_user', value: uid),
          callback: (PostgresChangePayload p) => _show(p.newRecord),
        )
        .subscribe();
    unawaited(_pending(c, uid));
  }

  Future<void> _pending(SupabaseClient c, String uid) async {
    try {
      final List<dynamic> rows = await c
          .from('nx_invites')
          .select()
          .eq('to_user', uid)
          .eq('status', 'pending')
          .gte('created_at', DateTime.now().toUtc().subtract(const Duration(minutes: 10)).toIso8601String())
          .order('created_at', ascending: false)
          .limit(1);
      for (final dynamic r in rows) {
        _show(Map<String, dynamic>.from(r as Map));
      }
    } catch (_) {}
  }

  void _show(Map<String, dynamic> r) {
    final int id = (r['id'] as num?)?.toInt() ?? -1;
    if (!_seen.add(id)) return;
    final Map<String, dynamic> p = Map<String, dynamic>.from((r['payload'] as Map?) ?? const <String, dynamic>{});
    final String game = '${p['game'] ?? ''}';
    final String code = '${p['code'] ?? ''}';
    final String from = '${p['from_name'] ?? 'Pilot'}';
    final GameInfo? g = gameById(game);
    final bool fa = _ref.read(settingsProvider).isFa;
    final String gameName = g == null ? game : (fa ? g.nameFa : g.nameEn);
    final ScaffoldMessengerState? m = _messenger.currentState;
    if (m == null || code.isEmpty) return;
    m.showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      content: Text(fa ? '$from تو را به $gameName دعوت کرد' : '$from invited you to $gameName'),
      action: SnackBarAction(
        label: fa ? 'ورود' : 'Join',
        onPressed: () {
          final SupabaseClient? c = _ref.read(onlineProvider).client;
          if (c != null && id >= 0) {
            unawaited(c.from('nx_invites').update(<String, dynamic>{'status': 'accepted'}).eq('id', id).then((_) {}, onError: (Object _) {}));
          }
          _open(game, code);
        },
      ),
    ));
  }

  void _detach() {
    final RealtimeChannel? ch = _ch;
    final SupabaseClient? c = _ref.read(onlineProvider).client;
    if (ch != null && c != null) unawaited(c.removeChannel(ch));
    _ch = null;
  }

  void dispose() => _detach();
}
