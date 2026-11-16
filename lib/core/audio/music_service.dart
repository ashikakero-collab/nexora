import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

/// Looping menu music (assets/media/bgm_main.ogg).
///
/// * Starts only after [start] (the launch intro calls it when it ends) and only when the user's
///   Music setting is on.
/// * Fades out while a game is open ([enterGame]/[exitGame], counted so nested pages are safe)
///   and fades back in on return.
/// * Pauses when the app goes to the background and resumes when it comes back.
/// * Every platform call is guarded: no audio plugin (tests) never throws into the UI.
class MusicService with WidgetsBindingObserver {
  MusicService._();
  static final MusicService instance = MusicService._();

  static const String asset = 'media/bgm_main.ogg';
  static const Duration _fade = Duration(milliseconds: 900);

  AudioPlayer? _player;
  bool _started = false;
  bool _enabled = true;
  double _volume = 0.6;
  int _games = 0;
  bool _background = false;
  double _current = 0;
  Timer? _fadeTimer;
  bool _playing = false;

  /// True once the intro handed over to the app.
  bool get started => _started;
  bool get inGame => _games > 0;

  /// Applies the Settings values (call whenever they change).
  void configure({required bool enabled, required double volume}) {
    _enabled = enabled;
    _volume = volume.clamp(0.0, 1.0);
    _sync();
  }

  /// No audio plugin under `flutter test`.
  static final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

  Future<void> start() async {
    if (_started || _underTest) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  void enterGame() {
    _games++;
    _sync();
  }

  void exitGame() {
    if (_games > 0) _games--;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = state != AppLifecycleState.resumed;
    if (_background) {
      // Leave immediately (no fade) when the app is hidden.
      _fadeTimer?.cancel();
      _current = 0;
      _safe(() async {
        await _player?.setVolume(0);
        await _player?.pause();
      });
      _playing = false;
    } else {
      _sync();
    }
  }

  double get _target =>
      (_started && _enabled && _games == 0 && !_background) ? _volume : 0.0;

  void _sync() {
    if (!_started) return;
    final double target = _target;
    if (target > 0 && !_playing) {
      _playing = true;
      _safe(() async {
        final AudioPlayer p = await _ensure();
        if (p.state == PlayerState.paused) {
          await p.resume();
        } else if (p.state != PlayerState.playing) {
          await p.play(AssetSource(asset), volume: _current);
        }
      });
    }
    _fadeTo(target);
  }

  Future<AudioPlayer> _ensure() async {
    final AudioPlayer? existing = _player;
    if (existing != null) return existing;
    final AudioPlayer p = AudioPlayer(playerId: 'nx_bgm');
    _player = p;
    await p.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
    await p.setReleaseMode(ReleaseMode.loop);
    return p;
  }

  void _fadeTo(double target) {
    _fadeTimer?.cancel();
    const int steps = 18;
    final double from = _current;
    int i = 0;
    _fadeTimer = Timer.periodic(
        Duration(milliseconds: _fade.inMilliseconds ~/ steps), (Timer t) {
      i++;
      _current = from + (target - from) * (i / steps);
      final double v = _current;
      _safe(() async => _player?.setVolume(v));
      if (i >= steps) {
        t.cancel();
        if (target == 0 && _playing) {
          _playing = false;
          _safe(() async => _player?.pause());
        }
      }
    });
  }

  void _safe(Future<void> Function() f) {
    unawaited(f().catchError((Object e) {
      debugPrint('nx music: $e');
    }));
  }
}
