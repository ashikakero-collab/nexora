// Dev-only snapshot of the match renderer (not in test/, CI does not run it):
//   flutter test tool/snap/render_snap_test.dart  -> /tmp/nx_snap_*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';
import 'package:nexora/game/render.dart';
import 'package:nexora/screens/match.dart';
import 'package:nexora/game/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final ball in [0, 5]) {
    testWidgets('snap ball $ball', (t) async {
      await t.runAsync(() async {
        final cfg = MatchCfg(field: kDefaultField, ball: ball, forms: [0, 0], ai: true, aiLvl: 1, limit: 3, matchTime: 0, turnTime: 15, vip: [false, false], first: 0);
        final e = Engine(cfg);
        e.ball.x = e.ball.px = e.CX + 60;
        e.ball.y = e.ball.py = e.goals[0].y + 90 * e.goals[0].d * -1;
        final im = await loadMatchImages(cfg, kTeams[0], kTeams[1]);
        const W = 412.0, H = 892.0;
        final v = computeView(e, W, H, 86, 22);
        final r = MatchRenderer(e, im, ball, v, dpr: 2);
        await r.prepare();
        final rec = ui.PictureRecorder();
        final c = ui.Canvas(rec);
        c.scale(2);
        r.render(c, 0);
        final img = await rec.endRecording().toImage((W * 2).round(), (H * 2).round());
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        File('/tmp/nx_snap_$ball.png').writeAsBytesSync(bd!.buffer.asUint8List());
      });
    });
  }
}
