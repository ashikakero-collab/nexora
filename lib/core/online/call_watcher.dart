import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../settings/app_settings.dart';
import 'online_service.dart';

/// Rings anywhere in the app when someone starts an Orbit Network call in one of my chats
/// (nx_calls inserts reach only chat members through RLS).
class CallWatcher {
  CallWatcher(this._ref, this._messenger, this._open);

  final WidgetRef _ref;
  final GlobalKey<ScaffoldMessengerState> _messenger;

  /// Opens the call page: (chatId, callId, video, title).
  final void Function(String chatId, String callId, bool video, String title) _open;

  RealtimeChannel? _ch;
  String? _uid;
  final Set<String> _seen = <String>{};

  void sync() {
    final OnlineService o = _ref.read(onlineProvider);
    final String? uid = o.isOnline ? o.uid : null;
    if (uid == _uid) return;
    _detach();
    _uid = uid;
    final SupabaseClient? c = o.client;
    if (uid == null || c == null) return;
    _ch = c
        .channel('nxcall:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'nx_calls',
          callback: (PostgresChangePayload p) => unawaited(_ring(c, uid, p.newRecord)),
        )
        .subscribe();
  }

  Future<void> _ring(SupabaseClient c, String uid, Map<String, dynamic> r) async {
    final String id = '${r['id']}';
    final String caller = '${r['caller']}';
    if (caller == uid || !_seen.add(id)) return;
    final String chatId = '${r['chat_id']}';
    final bool video = r['video'] == true;
    String who = 'Pilot';
    String title = who;
    try {
      final Map<String, dynamic>? p = await c.from('profiles').select('username').eq('id', caller).maybeSingle();
      who = '${p?['username'] ?? 'Pilot'}';
      final Map<String, dynamic>? ch = await c.from('nx_chats').select('kind, name').eq('id', chatId).maybeSingle();
      title = ch == null || ch['kind'] == 'direct' ? who : '${ch['name']}';
    } catch (_) {}
    final bool fa = _ref.read(settingsProvider).isFa;
    final ScaffoldMessengerState? m = _messenger.currentState;
    if (m == null) return;
    m.showSnackBar(SnackBar(
      duration: const Duration(seconds: 30),
      content: Row(children: <Widget>[
        Icon(video ? Icons.videocam_rounded : Icons.call_rounded, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title == who
              ? (fa ? '$who تماس ${video ? 'تصویری' : 'صوتی'} گرفته است' : '$who is calling you (${video ? 'video' : 'voice'})')
              : (fa ? '$who در «$title» تماس شروع کرد' : '$who started a call in "$title"')),
        ),
      ]),
      action: SnackBarAction(label: fa ? 'پاسخ' : 'Answer', onPressed: () => _open(chatId, id, video, title)),
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
