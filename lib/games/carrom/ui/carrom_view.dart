import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:nexora/core/assets/app_assets.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/core/game_contract.dart';
import '../core/carrom_config.dart';
import '../core/carrom_match.dart';
import 'cr_controller.dart';
import 'cr_fx.dart';
import 'cr_painter.dart';

const String _kRulesFa =
    'هدف: هر ۹ مهره‌ی رنگ خودت را (سفید برای پایین، مشکی برای بالا) به چاله‌ها بینداز و ملکه‌ی قرمز را پوشش بده.\n\n'
    '• استرایکر را با اسلایدر روی خط پایه جابه‌جا کن، سپس روی صفحه بکش و رها کن؛ هرچه بیشتر بکشی ضربه قوی‌تر است.\n'
    '• اگر مهره‌ی خودت یا ملکه را بیندازی دوباره نوبت توست.\n'
    '• ملکه: بعد از انداختنش باید در همان ضربه یا ضربه‌ی بعد یک مهره‌ی خودی بیندازی (پوشش)، وگرنه ملکه به مرکز برمی‌گردد. ملکه‌ی پوشش‌داده‌شده ۳ امتیاز دارد.\n'
    '• خطا: افتادن استرایکر؛ مهره‌های خودی همان ضربه و یکی از مهره‌های قبلی‌ات برمی‌گردند و نوبت تمام می‌شود.\n'
    '• مهره‌ی حریف که بیندازی برای حریف حساب می‌شود.\n'
    '• آخرین مهره‌ی یک رنگ قبل از پوشش ملکه مجاز نیست و برمی‌گردد.\n'
    '• هر نوبت ۳۰ ثانیه وقت دارد.';

const String _kRulesEn =
    'Goal: pocket all 9 coins of your colour (white for the bottom player, black for the top) and cover the red queen.\n\n'
    '• Slide the striker along your baseline with the slider, then drag on the board and release — the longer the pull, the harder the shot.\n'
    '• Pocket one of your coins or the queen and you shoot again.\n'
    '• Queen: after pocketing it you must pocket one of your own coins in the same or next shot (cover it), otherwise it returns to the centre. A covered queen is worth 3 points.\n'
    '• Foul: pocketing the striker. Your coins from that shot plus one already-pocketed coin return, and your turn ends.\n'
    '• Opponent coins you pocket count for the opponent.\n'
    '• Your last coin cannot go down before the queen is covered — it is returned.\n'
    '• Each turn has a 30-second timer.';

/// Full-screen Carrom match (the host provides Scaffold, exit button and result screen).
class CarromView extends StatefulWidget {
  const CarromView({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<CarromView> createState() => _CarromViewState();
}

class _CarromViewState extends State<CarromView>
    with SingleTickerProviderStateMixin {
  late final CrController _c;
  late final Ticker _ticker;
  final CrImages _images = CrImages();
  Duration _last = Duration.zero;
  int _skin = LocalStore.instance.getInt('carrom.board_skin') ?? 0;

  /// Cycles the table art (wood → black/green → silver → classic), remembered on the device.
  Future<void> _nextSkin() async {
    _skin = (_skin + 1) % kCrBoardSkins.length;
    await LocalStore.instance.setInt('carrom.board_skin', _skin);
    await _loadImages();
  }

  @override
  void initState() {
    super.initState();
    _c = CrController(widget.launch);
    _ticker = createTicker(_onTick);
    _ticker.start();
    _loadImages();
  }

  Future<void> _loadImages() async {
    final CrBoardSkin skin = crBoardSkin(_skin);
    final board = await crLoadImage(skin.asset, 1024);
    final white = await crLoadImage(AppAssets.gamesSharedDiscsDiscCream, 96);
    final black = await crLoadImage(AppAssets.gamesSharedDiscsDiscBlack, 96);
    final queen = await crLoadImage(AppAssets.disc('disc_red'), 96);
    final s0 = await crLoadImage(AppAssets.disc(_c.strikerSkin0), 128);
    final s1 = await crLoadImage(AppAssets.disc(_c.strikerSkin1), 128);
    if (!mounted) return;
    setState(() {
      _images.board = board;
      _images.boardPockets = skin.pockets;
      _images.white = white;
      _images.black = black;
      _images.queen = queen;
      _images.striker0 = s0;
      _images.striker1 = s1;
    });
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    if (dt < 0) dt = 0;
    if (dt > 0.05) dt = 0.05;
    _c.tick(dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _c.dispose();
    super.dispose();
  }

  void _showRules() {
    final launch = widget.launch;
    final NxThemeColors theme = NxThemeColors.of(context);
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return Directionality(
          textDirection: launch.isFa ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            backgroundColor: theme.surfaceRaised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: theme.border),
            ),
            title: Text(
              launch.tx('قوانین کارم', 'Carrom rules'),
              style:
                  TextStyle(color: theme.accent, fontWeight: FontWeight.w800),
            ),
            content: SingleChildScrollView(
              child: Text(
                launch.tx(_kRulesFa, _kRulesEn),
                style: TextStyle(color: theme.text, fontSize: 14, height: 1.55),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(launch.tx('فهمیدم', 'Got it'),
                    style: TextStyle(color: theme.accent)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final launch = widget.launch;
    final NxThemeColors theme = NxThemeColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 1.25,
              colors: <Color>[
                theme.backgroundMid,
                theme.background,
                scheme.surface
              ],
              stops: <double>[0, 0.55, 1],
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                  child: IgnorePointer(
                      child: CustomPaint(
                          painter: _CrBackdropPainter(accent: theme.accent)))),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    // Top bar keeps 64px free on both sides (host exit button sits top-start, LTR or RTL).
                    Padding(
                      padding: const EdgeInsets.fromLTRB(64, 6, 64, 0),
                      child: ValueListenableBuilder<CrHudData>(
                        valueListenable: _c.hud,
                        builder:
                            (BuildContext context, CrHudData h, Widget? _) =>
                                _CrHud(
                                    hud: h,
                                    c: _c,
                                    launch: launch,
                                    onRules: _showRules,
                                    onSkin: _nextSkin,
                                    theme: theme,
                                    error: scheme.error),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: LayoutBuilder(
                          builder: (BuildContext context, BoxConstraints cons) {
                            _c.viewSize = Size(cons.maxWidth, cons.maxHeight);
                            final Widget board = GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (DragStartDetails d) =>
                                  _c.onPanStart(d.localPosition),
                              onPanUpdate: (DragUpdateDetails d) =>
                                  _c.onPanUpdate(d.localPosition),
                              onPanEnd: (DragEndDetails d) => _c.onPanEnd(),
                              onPanCancel: _c.onPanCancel,
                              child: CustomPaint(
                                size: Size(cons.maxWidth, cons.maxHeight),
                                painter: CrPainter(_c, _images,
                                    accent: theme.accent,
                                    accentSecondary: theme.accentSecondary,
                                    error: scheme.error),
                              ),
                            );
                            // Online seat 1: board rotated so your baseline is at the bottom.
                            return _c.flipped
                                ? Transform.rotate(angle: math.pi, child: board)
                                : board;
                          },
                        ),
                      ),
                    ),
                    _CrPlacementBar(c: _c, launch: launch),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faint gold constellation rings behind the board.
class _CrBackdropPainter extends CustomPainter {
  const _CrBackdropPainter({this.accent = const Color(0xFFF3C56B)});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.46);
    final maxR = math.max(size.width, size.height) * 0.75;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= 5; i++) {
      ring.color = accent.withOpacity(0.05 - i * 0.006);
      canvas.drawCircle(center, maxR * i / 5, ring);
    }
    final dot = Paint()..color = const Color(0x55EAF6FF);
    final rnd = math.Random(7);
    for (var i = 0; i < 70; i++) {
      final p =
          Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawCircle(p, 0.5 + rnd.nextDouble() * 1.2, dot);
    }
    final glow = Paint()
      ..shader = RadialGradient(
              colors: <Color>[accent.withOpacity(0.15), accent.withOpacity(0)])
          .createShader(
              Rect.fromCircle(center: center, radius: size.shortestSide * 0.6));
    canvas.drawCircle(center, size.shortestSide * 0.6, glow);
  }

  @override
  bool shouldRepaint(covariant _CrBackdropPainter oldDelegate) => false;
}

class _CrHud extends StatelessWidget {
  const _CrHud(
      {required this.hud,
      required this.c,
      required this.launch,
      required this.onRules,
      required this.onSkin,
      required this.theme,
      required this.error});
  final CrHudData hud;
  final CrController c;
  final GameLaunch launch;
  final VoidCallback onRules;
  final VoidCallback onSkin;
  final NxThemeColors theme;
  final Color error;
  bool get _motion => launch.fancyEffects && !launch.reducedMotion;

  String _queenText() {
    if (hud.queenCoveredBy >= 0) {
      return launch.tx('ملکه: ', 'Queen: ') + c.seatName(hud.queenCoveredBy);
    }
    if (hud.queenPendingFor >= 0) {
      return launch.tx('ملکه منتظر پوشش', 'Queen awaiting cover');
    }
    return launch.tx('ملکه روی تخته', 'Queen on board');
  }

  @override
  Widget build(BuildContext context) {
    final finished = hud.phase == CrPhase.finished;
    final turnColor = hud.turn == 0 ? theme.accent : theme.accentSecondary;
    String status;
    if (finished) {
      status = launch.tx('پایان بازی', 'Game over');
    } else if (hud.botThinking) {
      status = launch.tx('ربات فکر می‌کند…', 'Bot is thinking…');
    } else if (hud.phase == CrPhase.simulating) {
      status = launch.tx('…', '…');
    } else if (launch.online) {
      status = hud.turn == launch.mySeat
          ? launch.tx('نوبت شما', 'Your turn')
          : launch.tx('نوبت حریف', 'Opponent\'s turn');
    } else if (launch.vsBot) {
      status = hud.turn == 0
          ? launch.tx('نوبت شما', 'Your turn')
          : launch.tx('نوبت ربات', 'Bot\'s turn');
    } else {
      status = launch.tx('نوبت ', 'Turn: ') + c.seatName(hud.turn);
    }
    final double timerValue =
        (hud.timeLeft / CrConfig.turnSeconds).clamp(0.0, 1.0).toDouble();
    final Color timerColor = hud.timeLeft <= 5 ? error : turnColor;
    final TextDirection textDir =
        launch.isFa ? TextDirection.rtl : TextDirection.ltr;
    final queenColor = hud.queenCoveredBy >= 0
        ? theme.accent
        : (hud.queenPendingFor >= 0
            ? const Color(0xFFFF4F6E)
            : const Color(0x99EAF6FF));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.surface.withOpacity(0.97),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.border.withOpacity(0.85)),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x33000000), blurRadius: 14)
            ],
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _CrSeatCard(
                  name: c.seatName(0),
                  count: hud.pocketed0,
                  color: theme.accent,
                  active: !finished && hud.turn == 0,
                  queen: hud.queenCoveredBy == 0,
                  alignEnd: false,
                  theme: theme,
                  motion: _motion,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 46,
                        height: 46,
                        child: CircularProgressIndicator(
                          value: finished ? 0 : timerValue,
                          strokeWidth: 4,
                          backgroundColor: const Color(0x22FFFFFF),
                          valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                        ),
                      ),
                      Text(
                        finished ? '–' : '${hud.timeLeft}',
                        style: TextStyle(
                            color: timerColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _CrSeatCard(
                  name: c.seatName(1),
                  count: hud.pocketed1,
                  color: theme.accentSecondary,
                  active: !finished && hud.turn == 1,
                  queen: hud.queenCoveredBy == 1,
                  alignEnd: true,
                  theme: theme,
                  motion: _motion,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: queenColor.withOpacity(0.6)),
                color: queenColor.withOpacity(0.10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.diamond_rounded, size: 13, color: queenColor),
                  const SizedBox(width: 4),
                  Text(_queenText(),
                      textDirection: textDir,
                      style: TextStyle(
                          color: queenColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration:
                    _motion ? const Duration(milliseconds: 220) : Duration.zero,
                child: Text(
                  hud.toast.isNotEmpty ? hud.toast : status,
                  key: ValueKey<String>(
                      hud.toast.isNotEmpty ? hud.toast : status),
                  textAlign: TextAlign.center,
                  textDirection: textDir,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hud.toast.isNotEmpty ? hud.toastColor : turnColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: onSkin,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.border.withOpacity(0.85)),
                  color: theme.accent.withOpacity(0.12),
                ),
                child: Icon(Icons.palette_rounded,
                    size: 16, color: theme.accent),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: onRules,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.border.withOpacity(0.85)),
                  color: theme.accent.withOpacity(0.12),
                ),
                child: Icon(Icons.menu_book_rounded,
                    size: 16, color: theme.accent),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CrSeatCard extends StatelessWidget {
  const _CrSeatCard({
    required this.name,
    required this.count,
    required this.color,
    required this.active,
    required this.queen,
    required this.alignEnd,
    required this.theme,
    required this.motion,
  });

  final String name;
  final int count;
  final Color color;
  final bool active;
  final bool queen;
  final bool alignEnd;
  final NxThemeColors theme;
  final bool motion;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(color: color.withOpacity(0.8), blurRadius: 10)
              ]
            : null,
      ),
    );
    final texts = Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: active ? color : theme.muted,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (queen && alignEnd)
              const Icon(Icons.diamond_rounded,
                  size: 12, color: Color(0xFFFF4F6E)),
            Text(
              '$count/${CrConfig.coinsPerSide}',
              style: TextStyle(
                  color: theme.text, fontSize: 16, fontWeight: FontWeight.w900),
            ),
            if (queen && !alignEnd)
              const Icon(Icons.diamond_rounded,
                  size: 12, color: Color(0xFFFF4F6E)),
          ],
        ),
      ],
    );
    return AnimatedOpacity(
      duration: motion ? const Duration(milliseconds: 240) : Duration.zero,
      opacity: active ? 1 : 0.7,
      child: Row(
        mainAxisAlignment:
            alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: alignEnd
            ? <Widget>[Flexible(child: texts), const SizedBox(width: 6), dot]
            : <Widget>[dot, const SizedBox(width: 6), Flexible(child: texts)],
      ),
    );
  }
}

/// Striker placement slider (enabled only while the local human can aim).
class _CrPlacementBar extends StatelessWidget {
  const _CrPlacementBar({required this.c, required this.launch});
  final CrController c;
  final GameLaunch launch;

  @override
  Widget build(BuildContext context) {
    final theme = NxThemeColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, Widget? _) {
        final enabled = c.humanCanAim && !c.aiming;
        final seat = c.match.turn;
        final col = c.placementValid
            ? (seat == 0 ? theme.accent : theme.accentSecondary)
            : scheme.error;
        final value =
            c.strikerX.clamp(CrConfig.baseMinX, CrConfig.baseMaxX).toDouble();
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.swap_horiz_rounded,
                      size: 18, color: enabled ? col : const Color(0x55EAF6FF)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: col.withOpacity(0.82),
                        inactiveTrackColor: theme.border.withOpacity(0.5),
                        thumbColor: col,
                        overlayColor: col.withOpacity(0.15),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        min: CrConfig.baseMinX,
                        max: CrConfig.baseMaxX,
                        value: c.flipped
                            ? CrConfig.baseMinX + CrConfig.baseMaxX - value
                            : value,
                        onChanged: enabled
                            ? (double v) => c.setPlacement(c.flipped
                                ? CrConfig.baseMinX + CrConfig.baseMaxX - v
                                : v)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                enabled
                    ? launch.tx(
                        'استرایکر را جابه‌جا کن، سپس روی تخته بکش و رها کن',
                        'Slide the striker, then drag on the board and release')
                    : (c.isBotTurn
                        ? launch.tx('ربات در حال بازی…', 'Bot is playing…')
                        : ' '),
                textAlign: TextAlign.center,
                textDirection:
                    launch.isFa ? TextDirection.rtl : TextDirection.ltr,
                style: TextStyle(color: theme.muted, fontSize: 11.5),
              ),
            ],
          ),
        );
      },
    );
  }
}
