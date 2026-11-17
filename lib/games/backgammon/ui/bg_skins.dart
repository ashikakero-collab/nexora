import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:nexora/core/assets/app_assets.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/ui2/nx2_board_art.dart';
import 'bg_geometry.dart';

/// Backgammon board skins. NX2 boards are fitted onto [BgGeom] with knot maps: every triangle tip of the art
/// lands on the BgGeom point centre, field edges on the field edges, the hinge on the bar. The top/bottom
/// frame strips are redrawn with their own map so the NEXORA plaques keep a sane aspect.
class BgBoardSkin {
  const BgBoardSkin(this.id, this.asset, this.nameFa, this.nameEn,
      {this.map, this.top, this.bottom, this.plaqueX = const <double>[470, 763]});
  final String id;
  final String asset;
  final String nameFa;
  final String nameEn;
  final Nx2ArtMap? map;

  /// Art y range of the top / bottom frame strip.
  final List<double>? top;
  final List<double>? bottom;
  final List<double> plaqueX;
}

List<List<double>> _xs(double w, double l0, List<double> tipsL, double l1, double r0, List<double> tipsR, double r1) {
  final List<List<double>> k = <List<double>>[<double>[0, 0], <double>[l0, BgGeom.left[0] - BgGeom.pointW / 2]];
  for (int i = 0; i < 6; i++) {
    k.add(<double>[tipsL[i], BgGeom.left[i]]);
  }
  k.add(<double>[l1, BgGeom.left[5] + BgGeom.pointW / 2]);
  k.add(<double>[r0, BgGeom.right[0] - BgGeom.pointW / 2]);
  for (int i = 0; i < 6; i++) {
    k.add(<double>[tipsR[i], BgGeom.right[i]]);
  }
  k.add(<double>[r1, BgGeom.right[5] + BgGeom.pointW / 2]);
  k.add(<double>[w, BgGeom.w]);
  return k;
}

final List<BgBoardSkin> kBgSkins = <BgBoardSkin>[
  BgBoardSkin('nx_wood', 'assets/ui/nx2/boards/backgammon_wood.webp', 'چوب گردو', 'Walnut',
      map: Nx2ArtMap(
          xs: _xs(1233, 121, const <double>[154, 232, 310, 388, 466, 544], 582, 651,
              const <double>[689, 767, 846, 923.6, 1003, 1080], 1112),
          ys: const <List<double>>[
            <double>[0, 0], <double>[110, BgGeom.top], <double>[464, BgGeom.topTip],
            <double>[766, BgGeom.bottomTip], <double>[1118, BgGeom.bottom], <double>[1227, BgGeom.h],
          ]),
      top: const <double>[0, 110],
      bottom: const <double>[1118, 1227]),
  BgBoardSkin('nx_silver', 'assets/ui/nx2/boards/backgammon_silver.webp', 'نقره‌ای', 'Silver',
      map: Nx2ArtMap(
          xs: _xs(1237, 118, const <double>[155.7, 233.6, 311, 389, 467, 544], 587, 653,
              const <double>[692, 770.7, 848, 925.7, 1003.6, 1081], 1119),
          ys: const <List<double>>[
            <double>[0, 0], <double>[107, BgGeom.top], <double>[446, BgGeom.topTip],
            <double>[748.6, BgGeom.bottomTip], <double>[1093, BgGeom.bottom], <double>[1199, BgGeom.h],
          ]),
      top: const <double>[0, 107],
      bottom: const <double>[1093, 1199],
      plaqueX: const <double>[472, 765]),
  const BgBoardSkin('classic', AppAssets.gamesBackgammonBoardNxGold, 'مشکی طلایی', 'Black & gold'),
];

const String kBgSkinKey = 'backgammon.board_skin';
int bgSkinIndex() => (LocalStore.instance.getInt(kBgSkinKey) ?? 0) % kBgSkins.length;
Future<void> bgSetSkin(int i) => LocalStore.instance.setInt(kBgSkinKey, i % kBgSkins.length);
bool bgDebugGeometry = false;

class BgSkinPainter extends CustomPainter {
  BgSkinPainter(this.img, this.skin);
  final ui.Image img;
  final BgBoardSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / BgGeom.w, size.height / BgGeom.h);
    final Paint p = Paint()..filterQuality = FilterQuality.medium;
    final Nx2ArtMap? m = skin.map;
    if (m == null) {
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          const Rect.fromLTWH(0, 0, BgGeom.w, BgGeom.h), p);
    } else {
      nx2PaintMappedArt(canvas, img, m, paint: p);
      // frame strips with their own x-map so the plaques are not squashed 3:1
      final double aw = img.width.toDouble();
      final double px0 = skin.plaqueX[0], px1 = skin.plaqueX[1];
      for (final List<double>? band in <List<double>?>[skin.top, skin.bottom]) {
        if (band == null) continue;
        final double d0 = m.dstY(band[0]), d1 = m.dstY(band[1]);
        final double sy = (d1 - d0) / (band[1] - band[0]);
        final double half = (px1 - px0) / 2 * sy * 1.25;
        final double cx = (BgGeom.barLeft + BgGeom.barRight) / 2;
        nx2PaintMappedArt(
            canvas,
            img,
            Nx2ArtMap(xs: <List<double>>[
              <double>[0, 0], <double>[px0, cx - half], <double>[px1, cx + half], <double>[aw, BgGeom.w],
            ], ys: <List<double>>[<double>[band[0], d0], <double>[band[1], d1]]),
            paint: p);
      }
    }
    if (bgDebugGeometry) {
      final Paint c = Paint()
        ..color = const Color(0xFFFF00FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      for (int i = 0; i < 24; i++) {
        canvas.drawPath(BgGeom.trianglePath(i), c);
      }
      canvas.drawRect(BgGeom.barRect, c);
      canvas.drawRect(BgGeom.trayRect(0), c);
      canvas.drawRect(BgGeom.trayRect(1), c);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BgSkinPainter old) => old.img != img || old.skin != skin;
}
