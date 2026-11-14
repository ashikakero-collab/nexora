// v4 launch intro (owner request 2026-11-14): the two owner videos, complete and in order:
//   assets/video/intro1.mp4 (544x960, 12.25 s: spaceship through the portal to the NeXora logo)
//   assets/video/intro2.mp4 (512x768, 10.04 s: a character walks the tunnel into the NEXORA base)
// Full-screen BoxFit.cover centred on a black background (no stretch on any aspect). Video 2 is initialised while
// video 1 plays and both stay stacked, so the hand-over is just a visibility swap (no black gap). Skip appears
// after ~1 s and goes straight home. If a video can't initialise, [onFail] runs (the Flutter cinematic fallback).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/sound.dart';

class VideoIntro extends StatefulWidget {
  final VoidCallback onDone, onFail;
  const VideoIntro({super.key, required this.onDone, required this.onFail});
  static const clips = ['assets/video/intro1.mp4', 'assets/video/intro2.mp4'];
  @override
  State<VideoIntro> createState() => _VideoIntroState();
}

class _VideoIntroState extends State<VideoIntro> {
  final List<VideoPlayerController> _c = [for (final p in VideoIntro.clips) VideoPlayerController.asset(p)];
  final List<bool> _ready = [false, false];
  int _cur = 0;
  bool _skip = false, _done = false;
  Timer? _skipT, _guard;

  @override
  void initState() {
    super.initState();
    Sound.scene(AudioScene.match); // the menu music waits until the intro is over
    _skipT = Timer(const Duration(milliseconds: 1000), () => mounted ? setState(() => _skip = true) : null);
    // if the first clip hasn't started within 6 s, use the fallback cinematic
    _guard = Timer(const Duration(seconds: 6), () {
      if (!_ready[0]) _fail();
    });
    _init(0).then((ok) {
      if (!ok) return _fail();
      _c[0].play();
      _init(1); // pre-initialise clip 2 while clip 1 plays
    });
    _c[0].addListener(() => _watch(0));
    _c[1].addListener(() => _watch(1));
  }

  Future<bool> _init(int i) async {
    try {
      await _c[i].initialize();
      await _c[i].setLooping(false);
      if (mounted) setState(() => _ready[i] = true);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _watch(int i) {
    if (_done || i != _cur) return;
    final v = _c[i].value;
    if (v.hasError) return i == 0 ? _fail() : _finish();
    final end = v.isInitialized && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 40) && !v.isPlaying;
    if (!end) return;
    if (i == 0 && _ready[1]) {
      _c[1].play();
      setState(() => _cur = 1);
    } else if (i == 0) {
      // clip 2 still initialising: wait for it (rare), else finish
      _init(1).then((ok) {
        if (_done) return;
        if (!ok) return _finish();
        _c[1].play();
        setState(() => _cur = 1);
      });
    } else {
      _finish();
    }
  }

  void _fail() {
    if (_done) return;
    _done = true;
    Sound.scene(AudioScene.menu);
    widget.onFail();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    for (final c in _c) {
      c.pause();
    }
    Sound.scene(AudioScene.menu);
    widget.onDone();
  }

  @override
  void dispose() {
    _skipT?.cancel();
    _guard?.cancel();
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _clip(int i) {
    final c = _c[i];
    if (!_ready[i]) return const SizedBox.shrink();
    final s = c.value.size;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: s.width, height: s.height, child: VideoPlayer(c)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        // both clips stay in the tree; only the current one is visible (seamless swap)
        Offstage(offstage: _cur != 1, child: _clip(1)),
        Offstage(offstage: _cur != 0, child: _clip(0)),
        Positioned(
          top: pad.top + 12,
          left: 14,
          child: AnimatedOpacity(
            opacity: _skip ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_skip,
              child: GestureDetector(
                onTap: _finish,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0x8c000000), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x66ffffff))),
                  child: const Text('رد کردن  ›', textDirection: TextDirection.rtl, style: TextStyle(color: Colors.white, fontFamily: 'Vazirmatn', fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
