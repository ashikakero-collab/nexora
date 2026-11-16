import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/audio/music_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/ui2/nx2_widgets.dart';

/// Launch intro: the owner's 10 s video, full screen (cover), with its own sound.
/// Skip appears after ~1 s; when it ends (or fails to load) the app continues to [next]
/// and the menu music starts.
class IntroVideoPage extends StatefulWidget {
  const IntroVideoPage({super.key, required this.next});
  final String next;

  static const String asset = 'assets/media/intro_app.mp4';

  @override
  State<IntroVideoPage> createState() => _IntroVideoPageState();
}

class _IntroVideoPageState extends State<IntroVideoPage> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _skip = false;
  bool _left = false;
  Timer? _skipTimer;
  Timer? _guard;

  @override
  void initState() {
    super.initState();
    _skipTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _skip = true);
    });
    // Never trap the user on the intro (slow decoder / missing codec).
    _guard = Timer(const Duration(seconds: 16), _leave);
    _start();
  }

  Future<void> _start() async {
    try {
      final VideoPlayerController c = VideoPlayerController.asset(IntroVideoPage.asset);
      _c = c;
      await c.initialize().timeout(const Duration(seconds: 5));
      if (!mounted) return;
      c.addListener(_onTick);
      await c.setVolume(1);
      await c.play();
      setState(() => _ready = true);
    } catch (e) {
      debugPrint('intro video: $e');
      _leave();
    }
  }

  void _onTick() {
    final VideoPlayerController? c = _c;
    if (c == null) return;
    final VideoPlayerValue v = c.value;
    if (v.hasError) {
      _leave();
      return;
    }
    if (v.isInitialized &&
        v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 120) &&
        !v.isPlaying) {
      _leave();
    }
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    _c?.pause();
    MusicService.instance.start();
    context.go(widget.next);
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    _guard?.cancel();
    _c?.removeListener(_onTick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: <Widget>[
        if (_ready && c != null)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          )
        else
          const Center(
              child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2))),
        SafeArea(
          child: Align(
            alignment: AlignmentDirectional.topEnd,
            child: AnimatedOpacity(
              opacity: _skip ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !_skip,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    width: 132,
                    child: Nx2Button(
                      label: context.tx('رد شدن', 'SKIP'),
                      icon: Icons.skip_next_rounded,
                      height: 44,
                      fontSize: 14,
                      onTap: _leave,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
