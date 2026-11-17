import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:nexora/core/assets/app_assets.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/ui2/nx2_board_art.dart';
import '../core/pool_config.dart';

/// Billiards table skins. The NX2 tables are landscape art drawn rotated a quarter turn and fitted with knot
/// maps so their pockets land on [PoolConfig.pockets] (art space = 1024x1536, cloth at artClothLeft/Top).
/// Geometry used by the physics is untouched.
class PoolTableSkin {
  const PoolTableSkin(this.id, this.asset, this.nameFa, this.nameEn, this.map, this.glow);
  final String id;
  final String asset;
  final String nameFa;
  final String nameEn;

  /// null = classic art drawn 1:1 (it IS the geometry reference).
  final Nx2ArtMap? map;
  final Color glow;
}

// Physics pocket centres in art space.
const double _cl = PoolConfig.artClothLeft, _ct = PoolConfig.artClothTop;
const double _pxL = -7 + _cl, _pxR = PoolConfig.tableW + 7 + _cl; // corner columns
const double _sxL = -33 + _cl, _sxR = PoolConfig.tableW + 33 + _cl; // side pockets
const double _pyT = 3 + _ct, _pyB = PoolConfig.tableH + 5 + _ct, _syM = 680 + _ct;

const List<PoolTableSkin> kPoolSkins = <PoolTableSkin>[
  PoolTableSkin('nx_green', 'assets/ui/nx2/boards/billiards_green.webp', 'نئون سبز', 'Neon green',
      Nx2ArtMap(quarterTurns: 1, xs: <List<double>>[
        <double>[0, 0], <double>[56, _sxL], <double>[86, _pxL], <double>[665, _pxR], <double>[684, _sxR],
        <double>[789, PoolConfig.artW],
      ], ys: <List<double>>[
        <double>[0, 0], <double>[106, _pyT], <double>[650, _syM], <double>[1198, _pyB], <double>[1280, PoolConfig.artH],
      ]),
      Color(0xFF59E33A)),
  PoolTableSkin('nx_orange', 'assets/ui/nx2/boards/billiards_orange.webp', 'نئون نارنجی', 'Neon orange',
      Nx2ArtMap(quarterTurns: 1, xs: <List<double>>[
        <double>[0, 0], <double>[65, _sxL], <double>[87, _pxL], <double>[663, _pxR], <double>[674, _sxR],
        <double>[803, PoolConfig.artW],
      ], ys: <List<double>>[
        <double>[0, 0], <double>[110.5, _pyT], <double>[651, _syM], <double>[1194.6, _pyB], <double>[1280, PoolConfig.artH],
      ]),
      Color(0xFFFF8A1E)),
  PoolTableSkin('classic', AppAssets.gamesBilliardsTableGreen, 'کلاسیک سبز', 'Classic green', null,
      Color(0xFFF3C56B)),
];

const String kPoolSkinKey = 'billiards.board_skin';
int poolSkinIndex() => (LocalStore.instance.getInt(kPoolSkinKey) ?? 0) % kPoolSkins.length;
Future<void> poolSetSkin(int i) => LocalStore.instance.setInt(kPoolSkinKey, i % kPoolSkins.length);

/// Debug switch for render tests: outlines the physics cushions and pockets over the art.
bool poolDebugGeometry = false;

class PoolSkinPainter extends CustomPainter {
  PoolSkinPainter(this.img, this.skin);
  final ui.Image img;
  final PoolTableSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / PoolConfig.artW;
    canvas.save();
    canvas.scale(s, s);
    final Nx2ArtMap? m = skin.map;
    if (m == null) {
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          const Rect.fromLTWH(0, 0, PoolConfig.artW, PoolConfig.artH), Paint()..filterQuality = FilterQuality.medium);
    } else {
      canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, PoolConfig.artW, PoolConfig.artH), const Radius.circular(48)),
          Paint()..color = const Color(0xFF07060C));
      nx2PaintMappedArt(canvas, img, m);
    }
    if (poolDebugGeometry) {
      canvas.translate(_cl, _ct);
      final Paint c = Paint()
        ..color = const Color(0xFFFF00FF)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      for (final List<double> g in PoolConfig.cushions) {
        canvas.drawLine(Offset(g[0], g[1]), Offset(g[2], g[3]), c);
      }
      for (int p = 0; p < 6; p++) {
        canvas.drawCircle(Offset(PoolConfig.pockets[p][0], PoolConfig.pockets[p][1]), PoolConfig.captureR(p), c);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PoolSkinPainter old) => old.img != img || old.skin != skin;
}
