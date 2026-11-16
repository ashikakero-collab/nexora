import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../models/nova_models.dart';
import '../state/nova_controller.dart';
import 'nova_visuals.dart';

/// Opens the full-screen story viewer.
Future<void> openNovaStories(BuildContext context, List<NovaStory> stories, int initial) {
  if (stories.isEmpty) return Future<void>.value();
  return Navigator.of(context).push<void>(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: NxMotion.normal,
    pageBuilder: (BuildContext c, Animation<double> a, Animation<double> b) =>
        NovaStoryViewer(stories: List<NovaStory>.from(stories), initialIndex: initial),
    transitionsBuilder: (BuildContext c, Animation<double> a, Animation<double> b, Widget child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(a), child: child),
    ),
  ));
}

/// Story viewer with progress bars, tap left/right, long-press to pause.
class NovaStoryViewer extends ConsumerStatefulWidget {
  const NovaStoryViewer({super.key, required this.stories, this.initialIndex = 0});
  final List<NovaStory> stories;
  final int initialIndex;

  @override
  ConsumerState<NovaStoryViewer> createState() => _NovaStoryViewerState();
}

class _NovaStoryViewerState extends ConsumerState<NovaStoryViewer> with SingleTickerProviderStateMixin {
  static const Duration _perStory = Duration(seconds: 6);
  late final AnimationController _progress = AnimationController(vsync: this, duration: _perStory);
  late int _index = widget.initialIndex.clamp(0, widget.stories.length - 1).toInt();

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed) _next();
    });
    _start();
  }

  void _start() {
    _progress.forward(from: 0);
    final s = widget.stories[_index];
    ref.read(novaControllerProvider).markStoryViewed(s.id);
  }

  void _next() {
    if (_index < widget.stories.length - 1) {
      setState(() => _index++);
      _start();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
    }
    _start();
  }

  Future<void> _delete(NovaStory s) async {
    _progress.stop();
    await ref.read(novaControllerProvider).deleteStory(s.id);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stories[_index];
    final bool mine = s.authorId == ref.watch(profileProvider).explorerId;
    final Duration left = s.expiresAt.difference(DateTime.now());
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => _progress.stop(),
        onLongPressEnd: (_) => _progress.forward(),
        onVerticalDragEnd: (DragEndDetails d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).maybePop();
        },
        onTapUp: (TapUpDetails d) {
          final w = MediaQuery.of(context).size.width;
          final bool leftSide = d.globalPosition.dx < w / 3;
          final bool rtl = Directionality.of(context) == TextDirection.rtl;
          // "Back" is the start side of the reading direction.
          final bool back = rtl ? d.globalPosition.dx > w * 2 / 3 : leftSide;
          if (back) {
            _prev();
          } else {
            _next();
          }
        },
        child: Stack(fit: StackFit.expand, children: <Widget>[
          AnimatedSwitcher(
            duration: NxMotion.normal,
            child: NovaMotionCanvas(
              key: ValueKey<String>(s.id),
              gradient: s.gradient,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: NovaRichText(
                    text: s.text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      height: 1.4,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: <Shadow>[Shadow(color: Colors.black54, blurRadius: 16)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Column(children: <Widget>[
                Row(children: <Widget>[
                  for (var i = 0; i < widget.stories.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            height: 3.5,
                            child: i == _index
                                ? AnimatedBuilder(
                                    animation: _progress,
                                    builder: (BuildContext c, Widget? _) => LinearProgressIndicator(
                                      value: _progress.value,
                                      backgroundColor: Colors.white24,
                                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : LinearProgressIndicator(
                                    value: i < _index ? 1 : 0,
                                    backgroundColor: Colors.white24,
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                          ),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 10),
                Row(children: <Widget>[
                  NovaAvatar(name: s.authorName, size: 36),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(s.authorName, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                      Text(
                        context.tx('${novaAgo(context, s.createdAt)} · ${left.inHours} ساعت مانده',
                            '${novaAgo(context, s.createdAt)} · ${left.inHours}h left'),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ]),
                  ),
                  if (mine)
                    IconButton(
                      tooltip: context.tx('حذف استوری', 'Delete story'),
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                      onPressed: () => _delete(s),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
