// v4 goal skins (owner art, cut by tool/import_goals.py, nets + palettes by tool/goal_meta.py).
// Index 0 = the classic procedural white goal. The chosen skin (Store.p.goal) is purely cosmetic and local:
// collision geometry never changes and online peers may each see their own skin.
import 'goal_skins_gen.dart';

class GoalSkin {
  final String id, name;
  final int price, rar;

  /// crossbar/post gradient across the bar: dark edge, highlight, mid, dark edge (ARGB)
  final List<int> pal;

  /// mean colour of the net strands (used for the side-wall mesh lines)
  final int netCol;
  const GoalSkin(this.id, this.name, this.price, this.rar, this.pal, this.netCol);

  bool get classic => id == 'classic';
  String get img => 'assets/g/goals4/$id.webp';
  String? get net => classic ? null : 'assets/g/goals4/net_$id.webp';
}

const _classicPal = [0xff7a8292, 0xffffffff, 0xffd9dee7, 0xff596173];

GoalSkin _g(String id, String name, int price, int rar, {List<int>? pal}) {
  final m = kGoalSkinMeta[id]!;
  return GoalSkin(id, name, price, rar, pal ?? m.$1, m.$2);
}

final List<GoalSkin> kGoalSkins = [
  const GoalSkin('classic', 'کلاسیک', 0, 0, _classicPal, 0xffe8edf5),
  _g('white', 'سفید کندویی', 120, 1, pal: const [0xff8f96a3, 0xffffffff, 0xffe3e7ee, 0xff6d7482]),
  _g('silver', 'نقره‌ای', 180, 1, pal: const [0xff6f7782, 0xfffdfeff, 0xffc9ced6, 0xff5a616c]),
  _g('black', 'کربن مشکی', 220, 1, pal: const [0xff0b0c0e, 0xff8d939b, 0xff2b2e33, 0xff050506]),
  _g('red', 'قرمز آتشین', 220, 1),
  _g('blue', 'آبی اقیانوسی', 220, 1),
  _g('wood', 'چوب گردو', 300, 2),
  _g('woodhc', 'چوب و طناب', 300, 2),
  _g('ice', 'یخ قطبی', 420, 2, pal: const [0xff2f8fd6, 0xffe9fbff, 0xff6cc6f2, 0xff1d6fb5]),
  _g('gold', 'طلای سلطنتی', 600, 3, pal: const [0xff6b4a06, 0xfffff2b0, 0xffd9a521, 0xff5a3c04]),
];

GoalSkin goalSkin(int i) => kGoalSkins[i.clamp(0, kGoalSkins.length - 1)];
