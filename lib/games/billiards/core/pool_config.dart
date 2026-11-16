/// Pure-Dart constants and table geometry for NEXORA 8-ball billiards.
///
/// Units are "table units": the playing surface (cushion nose to cushion nose)
/// is [PoolConfig.tableW] x [PoolConfig.tableH], measured 1:1 in pixels on the
/// portrait art `assets/games/billiards/table_green.webp` (1024x1536), whose
/// cloth rectangle starts at ([PoolConfig.artClothLeft], [PoolConfig.artClothTop]).
/// The head (break) end is at the bottom (large y), the rack at the top.
///
/// Determinism contract (same as Finger Soccer): fixed step 1/120 s, split into
/// [PoolConfig.substeps] equal sub-steps; only + - * / and sqrt inside physics.
class PoolConfig {
  PoolConfig._();

  // ---------------------------------------------------------------- art mapping
  static const double artW = 1024;
  static const double artH = 1536;
  static const double artClothLeft = 110;
  static const double artClothTop = 88;

  // ---------------------------------------------------------------- table
  static const double tableW = 803;
  static const double tableH = 1342;
  static const double ballR = 22;

  /// Kitchen (behind the head string) = y >= headStringY.
  static const double headStringY = tableH * 0.75;
  static const double footSpotX = tableW / 2;
  static const double footSpotY = tableH * 0.25;
  static const double breakCueX = tableW / 2;
  static const double breakCueY = tableH * 0.82;

  // ---------------------------------------------------------------- physics
  static const double dt = 1 / 120;
  static const int substeps = 3;

  /// Max cue-ball launch speed (units/s). Per sub-step travel stays < ballR so
  /// nothing can tunnel through a cushion line or another ball.
  static const double maxShotSpeed = 4800;
  static const double minShotPower = 0.03;

  /// Rolling resistance: constant deceleration (units/s^2) + linear drag (1/s).
  static const double rollDecel = 240;
  static const double linearDrag = 0.35;
  static const double stopSpeed = 5;

  static const double eBall = 0.97;
  static const double eCushion = 0.82;

  /// Simple spin model: follow/draw added to the cue ball after its first
  /// object-ball contact, side spin changes cushion rebounds.
  static const double followFactor = 0.55;
  static const double sideFactor = 0.30;

  /// Hard safety cap for a shot simulation: 24 s.
  static const int maxSteps = 2880;

  // ---------------------------------------------------------------- pockets
  static const double cornerCaptureR = 36;
  static const double sideCaptureR = 36;

  /// Pocket centres (table units) measured on the art. Order: TL, TR, ML, MR, BL, BR.
  static const List<List<double>> pockets = <List<double>>[
    <double>[-7, 3],
    <double>[tableW + 7, 3],
    <double>[-33, 680],
    <double>[tableW + 33, 680],
    <double>[-7, tableH + 5],
    <double>[tableW + 7, tableH + 5],
  ];

  static double captureR(int pocket) => (pocket == 2 || pocket == 3) ? sideCaptureR : cornerCaptureR;

  /// Point a shot should be sent to for each pocket (slightly inside the mouth).
  static const List<List<double>> pocketAim = <List<double>>[
    <double>[14, 14],
    <double>[tableW - 14, 14],
    <double>[-4, 680],
    <double>[tableW + 4, 680],
    <double>[14, tableH - 14],
    <double>[tableW - 14, tableH - 14],
  ];

  // jaw geometry (nose points where the straight cushion ends, and where the
  // angled jaw meets the rail back) measured on the art.
  static const double cornerJawNose = 76;
  static const double jawBack = -31;
  static const double cornerJawBackAlong = 45;
  static const double sideMouthTop = 607;
  static const double sideMouthBottom = 754;
  static const double sideJawBackTop = 627;
  static const double sideJawBackBottom = 734;

  /// Cushion segments [x1, y1, x2, y2]: straight rails between the jaws plus
  /// the angled jaw faces. Endpoints act as rounded knuckles.
  static final List<List<double>> cushions = _buildCushions();

  static List<List<double>> _buildCushions() {
    const double w = tableW, h = tableH;
    const double n = cornerJawNose, b = jawBack, a = cornerJawBackAlong;
    final List<List<double>> s = <List<double>>[];
    // straight rails
    s.add(<double>[n, 0, w - n, 0]); // top
    s.add(<double>[n, h, w - n, h]); // bottom
    s.add(<double>[0, n, 0, sideMouthTop]); // left upper
    s.add(<double>[0, sideMouthBottom, 0, h - n]); // left lower
    s.add(<double>[w, n, w, sideMouthTop]); // right upper
    s.add(<double>[w, sideMouthBottom, w, h - n]); // right lower
    // corner jaws
    s.add(<double>[n, 0, a, b]); // TL top
    s.add(<double>[0, n, b, a]); // TL left
    s.add(<double>[w - n, 0, w - a, b]); // TR top
    s.add(<double>[w, n, w - b, a]); // TR right
    s.add(<double>[n, h, a, h - b]); // BL bottom
    s.add(<double>[0, h - n, b, h - a]); // BL left
    s.add(<double>[w - n, h, w - a, h - b]); // BR bottom
    s.add(<double>[w, h - n, w - b, h - a]); // BR right
    // side jaws
    s.add(<double>[0, sideMouthTop, b, sideJawBackTop]);
    s.add(<double>[0, sideMouthBottom, b, sideJawBackBottom]);
    s.add(<double>[w, sideMouthTop, w - b, sideJawBackTop]);
    s.add(<double>[w, sideMouthBottom, w - b, sideJawBackBottom]);
    return s;
  }
}

/// Which balls a player must pocket.
enum PoolGroup { none, solids, stripes }

bool poolIsSolid(int id) => id >= 1 && id <= 7;
bool poolIsStripe(int id) => id >= 9 && id <= 15;

PoolGroup poolGroupOf(int id) {
  if (poolIsSolid(id)) return PoolGroup.solids;
  if (poolIsStripe(id)) return PoolGroup.stripes;
  return PoolGroup.none;
}

PoolGroup poolOtherGroup(PoolGroup g) {
  switch (g) {
    case PoolGroup.solids:
      return PoolGroup.stripes;
    case PoolGroup.stripes:
      return PoolGroup.solids;
    case PoolGroup.none:
      return PoolGroup.none;
  }
}
