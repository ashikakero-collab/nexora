// Port of src/net/voice.ts: LiveKit voice per room. Token from the existing `livekit-token` edge function
// ({room_id} -> {url, token, canPublish}); players publish their mic, spectators listen. Never throws to callers.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/sound.dart';
import '../net/supabase.dart';

enum VoiceStatus { off, connecting, on, error }

class Voice extends ChangeNotifier {
  final String roomId;
  final String _vid = 'v${DateTime.now().microsecondsSinceEpoch}';
  VoiceStatus status = VoiceStatus.off;
  bool mic = false, speaker = true, canPublish = false;
  List<String> speaking = const [];
  String? error;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _ls;
  bool _alive = true;

  Voice(this.roomId);

  void _set() {
    Sound.voiceActive(_vid, status == VoiceStatus.on || mic);
    if (_alive) notifyListeners();
  }

  Future<void> join() async {
    if (status == VoiceStatus.connecting || status == VoiceStatus.on) return;
    status = VoiceStatus.connecting;
    error = null;
    _set();
    try {
      Map<String, dynamic> data;
      try {
        final r = await sb.functions.invoke('livekit-token', body: {'room_id': roomId});
        data = Map<String, dynamic>.from(r.data as Map);
      } on FunctionException catch (e) {
        final body = e.details is Map ? e.details as Map : const {};
        if (e.status == 503 || body['error'] == 'voice_not_configured') throw 'چت صوتی هنوز فعال نشده';
        if (e.status == 403) throw 'برای چت صوتی باید داخل اتاق باشی';
        throw 'اتصال به سرور صدا ناموفق بود';
      }
      if (!_alive) return;
      var pub = data['canPublish'] == true;
      if (pub) {
        final g = await Permission.microphone.request();
        if (!g.isGranted) pub = false;
      }
      final room = lk.Room(roomOptions: const lk.RoomOptions(adaptiveStream: false, dynacast: false));
      _room = room;
      final ls = room.createListener();
      _ls = ls;
      ls
        ..on<lk.ActiveSpeakersChangedEvent>((e) {
          speaking = e.speakers.map((p) => p.identity).toList();
          _set();
        })
        ..on<lk.RoomDisconnectedEvent>((_) {
          if (!_alive) return;
          status = VoiceStatus.off;
          mic = false;
          speaking = const [];
          _set();
        })
        ..on<lk.TrackSubscribedEvent>((e) {
          if (!speaker) e.track.disable();
        });
      await room.connect(data['url'].toString(), data['token'].toString(), connectOptions: const lk.ConnectOptions(autoSubscribe: true));
      if (!_alive) {
        await room.disconnect();
        return;
      }
      status = VoiceStatus.on;
      canPublish = pub;
      mic = false;
      _set();
      if (pub) await setMic(true);
    } catch (e) {
      status = VoiceStatus.error;
      error = e is String ? e : 'اتصال صدا ناموفق بود';
      _set();
      leave(keepError: true);
    }
  }

  Future<void> setMic(bool on) async {
    final r = _room;
    if (r == null || !canPublish) return;
    try {
      await r.localParticipant?.setMicrophoneEnabled(on);
      mic = on;
    } catch (_) {
      mic = false;
    }
    _set();
  }

  void setSpeaker(bool on) {
    speaker = on;
    try {
      for (final p in _room?.remoteParticipants.values ?? const <lk.RemoteParticipant>[]) {
        for (final t in p.audioTrackPublications) {
          final tr = t.track;
          if (tr == null) continue;
          on ? tr.enable() : tr.disable();
        }
      }
    } catch (_) {}
    _set();
  }

  void leave({bool keepError = false}) {
    final r = _room;
    _room = null;
    _ls?.dispose();
    _ls = null;
    if (r != null) unawaited(r.disconnect().catchError((_) {}));
    if (!keepError) {
      status = VoiceStatus.off;
      mic = false;
      speaking = const [];
      _set();
    }
  }

  void destroy() {
    leave();
    _alive = false;
    Sound.voiceActive(_vid, false);
  }
}
