// Dev-only snapshot of the v4 goal skins + net ripple: flutter test tool/snap/goal_snap_test.dart -> /tmp/nx_goal_<id>.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/assets.dart';
import 'package:nexora/game/data.dart';
import 'package:nexora/game/engine.dart';
import 'package:nexora/game/goal_skins.dart';
import 'package:nexora/game/render.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final id in ['classic', 'ice', 'wood', 'gold', 'silver', 'black']) {
    testWidgets('goal $id', (t) async {
      await t.runAsync(() async {
        final cfg = MatchCfg(field: kDefaultField, ball: 0, forms: [0, 0], ai: true, aiLvl: 1, limit: 3, matchTime: 0, turnTime: 15, vip: [false, false], first: 0);
        final e = Engine(cfg);
        final skin = kGoalSkins.firstWhere((s) => s.id == id);
        final net = skin.net == null ? null : await loadImage(skin.net!);
        final f = kFields[cfg.field];
        final im = MatchImages(await loadImage(kFIELD_IMG[f.id]!, width: 1100), await proceduralBall(), await loadImage(teamImg(kTeams[0]), width: 192),
            await loadImage(teamImg(kTeams[1]), width: 192), null, null, null, null, skin: skin, net: net);
        const W = 412.0, H = 892.0;
        final v = computeView(e, W, H, 86, 22);
        final r = MatchRenderer(e, im, 0, v, dpr: 2);
        await r.prepare();
        Future<void> shot(String tag, double tt) async {
          final rec = ui.PictureRecorder();
          final c = ui.Canvas(rec);
          c.scale(2);
          r.render(c, tt);
          final img = await rec.endRecording().toImage((W * 2).round(), (H * 2).round());
          final bd = await img.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/nx_goal_${id}_$tag.png').writeAsBytesSync(bd!.buffer.asUint8List());
        }

        await shot('still', 0);
        e.ripple[1] = 1; // goal at the bottom -> ripple
        e.rippleX[1] = e.CX + 40;
        r.render(ui.Canvas(ui.PictureRecorder()), 0.01);
        await shot('ripple', 0.2);
      });
    });
  }
}
