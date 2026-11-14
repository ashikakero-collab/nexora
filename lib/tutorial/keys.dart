// GlobalKeys of the real widgets the first-run tour spotlights (each attached in exactly one place).
import 'package:material_ui/material_ui.dart';

import '../ui/v4.dart';

class TourKeys {
  static final profile = GlobalKey(debugLabel: 'tour.profile');
  static final currencies = GlobalKey(debugLabel: 'tour.currencies');
  static final quick = GlobalKey(debugLabel: 'tour.quick');
  static final shop = GlobalKey(debugLabel: 'tour.shop');
  static final social = GlobalKey(debugLabel: 'tour.social');
  static final rank = GlobalKey(debugLabel: 'tour.rank');
  static final gift = GlobalKey(debugLabel: 'tour.gift');
  static final settings = GlobalKey(debugLabel: 'tour.settings');
  static final level = GlobalKey(debugLabel: 'tour.level');
  static final nav = {for (final t in NavTab.values) t: GlobalKey(debugLabel: 'tour.nav.${t.name}')};
  static final modes = GlobalKey(debugLabel: 'tour.modes');
  static final online = GlobalKey(debugLabel: 'tour.online');
  static final teamTabs = GlobalKey(debugLabel: 'tour.teamTabs');
  static final teamHero = GlobalKey(debugLabel: 'tour.teamHero');
}
