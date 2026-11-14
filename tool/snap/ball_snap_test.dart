// Dev-only: rolling sphere ball frames -> /tmp/nx_ball_<k>.png (flutter test tool/snap/ball_snap_test.dart)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/assets.dart';
import 'package:nexora/game/data.dart';
import 'package:nexora/game/engine.dart';
import 'package:nexora/game/render.dart';
import 'package:nexora/screens/match.dart' show ballShader;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('ball', (t) async {
    await t.runAsync(() async {
      final cfg = MatchCfg(field: kDefaultField, ball: 0, forms: [0, 0], ai: true, aiLvl: 1, limit: 3, matchTime: 0, turnTime: 15, vip: [false, false], first: 0);
      final e = Engine(cfg);
      final f = kFields[cfg.field];
      final im = MatchImages(await loadImage(kFIELD_IMG[f.id]!, width: 1100), await loadImage(ballImg(0), width: 256), await loadImage(teamImg(kTeams[0]), width: 192),
          await loadImage(teamImg(kTeams[1]), width: 192), null, null, null, null);
      const W = 412.0, H = 892.0;
      final sh = await ballShader();
      // ignore: avoid_print
      print('shader: ${sh != null}');
      final r = MatchRenderer(e, im, 0, computeView(e, W, H, 86, 22), dpr: 3, ballShader: sh);
      await r.prepare();
      final b = e.ball;
      for (var k = 0; k < 4; k++) {
        b.x = b.px = e.CX + k * b.r * .8;
        b.y = b.py = e.CY;
        final rec = ui.PictureRecorder();
        final c = ui.Canvas(rec)..scale(3);
        r.render(c, k / 60);
        final img = await rec.endRecording().toImage((W * 3).round(), (H * 3).round());
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        File('/tmp/nx_ball_$k.png').writeAsBytesSync(bd!.buffer.asUint8List());
      }
    });
  });
}
