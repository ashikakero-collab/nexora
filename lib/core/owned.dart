// v4: one place that answers "does the player own X?" for teams/discs, balls, fields and goal skins.
// kUnlockAllShop (owner request 2026-11-14): everything is owned and selectable for testing; prices stay displayed.
import '../game/data.dart';
import '../net/discs.dart';
import 'store.dart';

const bool kUnlockAllShop = true;

bool ownsTeam(String id) => kUnlockAllShop || Discs.i.has(id) || Store.i.p.ownedTeams.contains(id);
bool ownsBall(int i) => kUnlockAllShop || Store.i.p.ownedBalls.contains(i);
bool ownsField(int i) => kUnlockAllShop || Store.i.p.ownedFields.contains(i);
bool ownsGoal(int i) => kUnlockAllShop || i == 0 || Store.i.p.ownedGoals.contains(i);

/// Price label of a team: gems when the online catalog sells it, else coins (local purchase).
(int, bool) teamCost(Team t) {
  final row = Discs.i.catalog[t.id];
  if (row != null) return (row.priceGems, true);
  return (teamPrice(t), false);
}
