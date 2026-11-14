// Port of src/sound.ts: pooled low-latency SFX (Android SoundPool via audioplayers lowLatency mode),
// one music manager with scenes (menu / room = ducked / match = off, voice active = off) and haptics.
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'assets.dart';

enum Snd { ui, hitb, hitp, goal, post, roar, whistle, finalW, wall, crowd, music, ready, chat, join, leave, win, lose, tick }

const Map<Snd, (String, double, int)> _map = {
  Snd.ui: ('select', .55, 2), Snd.hitb: ('hit_ball', .9, 3), Snd.hitp: ('hit_piece', .7, 3), Snd.goal: ('goal', .9, 1),
  Snd.post: ('ballHitsThePost', .8, 1), Snd.roar: ('goalHappened-01', .7, 1), Snd.whistle: ('startWistle', .8, 1),
  Snd.finalW: ('gameIsFinishedWistle', .8, 1), Snd.wall: ('BallHit-01', .55, 2), Snd.crowd: ('crowd-03', .25, 1),
  Snd.music: ('music', .35, 1), Snd.ready: ('nx_ready', .7, 1), Snd.chat: ('nx_chat', .55, 2), Snd.join: ('nx_join', .6, 1),
  Snd.leave: ('nx_leave', .5, 1), Snd.win: ('nx_win', .8, 1), Snd.lose: ('nx_lose', .75, 1), Snd.tick: ('nx_tick', .45, 2),
};

enum AudioScene { menu, room, match }

class Sound {
  static final Map<Snd, List<AudioPlayer>> _pools = {};
  static final Map<Snd, int> _idx = {};
  static final Map<Snd, int> _last = {};
  static bool sound = true, music = true, haptics = true;
  static double volume = 1;
  static bool _inited = false;
  static AudioScene _scene = AudioScene.menu;
  static final Set<String> _voices = {};
  static bool _musicPlaying = false, _crowdPlaying = false;

  static String _path(Snd k) => kSFX[_map[k]!.$1]!.replaceFirst('assets/', '');

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      await AudioPlayer.global.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
    } catch (_) {}
    for (final k in Snd.values) {
      final (_, vol, n) = _map[k]!;
      final loop = k == Snd.music || k == Snd.crowd;
      final list = <AudioPlayer>[];
      for (var i = 0; i < n; i++) {
        final p = AudioPlayer(playerId: 'nx_${k.name}_$i');
        try {
          await p.setPlayerMode(loop ? PlayerMode.mediaPlayer : PlayerMode.lowLatency);
          await p.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
          await p.setSource(AssetSource(_path(k)));
          await p.setVolume(vol);
        } catch (_) {}
        list.add(p);
      }
      _pools[k] = list;
      _idx[k] = 0;
    }
    _applyMusic();
  }

  static void prefs({required bool sound, required bool music, required bool haptics, required double volume}) {
    Sound.sound = sound;
    Sound.music = music;
    Sound.haptics = haptics;
    Sound.volume = volume.clamp(0, 1);
    final cr = _pools[Snd.crowd];
    if (cr != null && cr.isNotEmpty) cr[0].setVolume(_map[Snd.crowd]!.$2 * Sound.volume);
    if (!sound && _crowdPlaying) stopLoop(Snd.crowd);
    _applyMusic();
  }

  static void sfx(Snd k, [double vol = 1]) {
    if (!sound || volume <= 0) return;
    final pool = _pools[k];
    if (pool == null || pool.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (k != Snd.goal && now - (_last[k] ?? 0) < 45) return;
    _last[k] = now;
    final i = _idx[k]!;
    final p = pool[i];
    _idx[k] = (i + 1) % pool.length;
    final v = (_map[k]!.$2 * (vol < .15 ? .15 : vol) * volume).clamp(0.0, 1.0);
    p.setVolume(v);
    p.stop().then((_) => p.resume()).catchError((_) {});
  }

  static void _applyMusic() {
    final l = _pools[Snd.music];
    if (l == null || l.isEmpty) return;
    final p = l[0];
    final want = sound && music && volume > 0 && _scene != AudioScene.match && _voices.isEmpty;
    if (!want) {
      if (_musicPlaying) p.pause();
      _musicPlaying = false;
      return;
    }
    p.setVolume(_map[Snd.music]!.$2 * volume * (_scene == AudioScene.room ? .22 : 1));
    if (!_musicPlaying) {
      p.resume().catchError((_) {});
      _musicPlaying = true;
    }
  }

  static void scene(AudioScene s) {
    if (_scene == s) return;
    _scene = s;
    _applyMusic();
  }

  static void voiceActive(String id, bool on) {
    final had = _voices.contains(id);
    if (on) {
      _voices.add(id);
    } else {
      _voices.remove(id);
    }
    if (had != on) _applyMusic();
  }

  static void playLoop(Snd k) {
    if (k == Snd.music) {
      _applyMusic();
      return;
    }
    if (!sound || volume <= 0) return;
    final p = _pools[k]?.firstOrNull;
    if (p == null || _crowdPlaying) return;
    _crowdPlaying = true;
    p.resume().catchError((_) {});
  }

  static void stopLoop(Snd k) {
    final p = _pools[k]?.firstOrNull;
    if (p == null) return;
    if (k == Snd.crowd) _crowdPlaying = false;
    if (k == Snd.music) _musicPlaying = false;
    p.pause().catchError((_) {});
  }

  static void buzz([String kind = 'light']) {
    if (!haptics) return;
    switch (kind) {
      case 'success':
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 90), HapticFeedback.lightImpact);
      case 'heavy':
        HapticFeedback.heavyImpact();
      case 'medium':
        HapticFeedback.mediumImpact();
      default:
        HapticFeedback.lightImpact();
    }
  }
}

void sfx(Snd k, [double vol = 1]) => Sound.sfx(k, vol);
void buzz([String kind = 'light']) => Sound.buzz(kind);
