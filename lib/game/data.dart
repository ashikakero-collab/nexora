// Port of src/game/data.ts + src/game/util.ts (static game data).
part 'data_gen.dart';

class Field {
  final String id, name;
  final int W, H, L, R, T, B, cs, g;
  final String gs;
  const Field(this.id, this.name, this.W, this.H, this.L, this.R, this.T, this.B, this.cs, this.g, this.gs);
}

class Cat {
  final String k, name;
  final List<String> list;
  const Cat(this.k, this.name, this.list);
}

class FormRow {
  final double ny;
  final int c;
  const FormRow(this.ny, this.c);
}

class Formation {
  final String code, name;
  final List<FormRow> rows;
  const Formation(this.code, this.name, this.rows);
}

class TrailStyle {
  final String k;
  final List<int> c;
  const TrailStyle(this.k, this.c);
}

class FieldFx {
  final int k;
  final List<int> c;
  final int g;
  const FieldFx(this.k, this.c, this.g);
}

class Team {
  final String id, cat, name;
  final int idx;
  const Team(this.id, this.cat, this.name, this.idx);
}

final List<Team> kTeams = [
  for (final c in kCats)
    for (var i = 0; i < c.list.length; i++) Team('${c.k}$i', c.k, c.list[i], i),
];
final Map<String, String> kCatLabel = {for (final c in kCats) c.k: c.name};

int teamPrice(Team t) => t.cat == 'vip'
    ? (t.idx < kVipPrices.length && kVipPrices[t.idx] != 0 ? kVipPrices[t.idx] : 250)
    : t.cat == 'club' || t.cat == 'nat'
        ? 0
        : t.cat == 'leg'
            ? 520
            : t.cat == 'emb'
                ? 220
                : t.cat == 'elite'
                    ? (t.idx == 0 ? 0 : 160)
                    : t.cat == 'chrome'
                        ? 180
                        : 120;
int ballPrice(int i) => i < 6 ? 0 : 60 + (i % 7) * 20;
int fieldPrice(int i) => i < 5 ? 0 : 80 + ((i - 1) % 5) * 20;
const int kDefaultField = 0;
const int kFieldsVersion = 2;

/// Formation slots: normalized [nx, ny] per disc (same order as data.ts `slots`).
List<List<double>> slots(int fi) {
  final o = <List<double>>[];
  for (final r in kForms[fi].rows) {
    for (var i = 0; i < r.c; i++) {
      o.add([r.c == 1 ? .5 : r.c == 2 ? .27 + .46 * i : .17 + .33 * i, r.ny]);
    }
  }
  return o;
}

// ---- util.ts ----
String teamKey(Team t) => t.cat + t.idx.toString().padLeft(2, '0');
Team teamById(String id) => kTeams.firstWhere((t) => t.id == id, orElse: () => kTeams[0]);

/// FNV-1a 32 bit (matches util.ts `hash`).
int hashStr(String s) {
  var h = 2166136261;
  for (final cu in s.codeUnits) {
    h ^= cu;
    h = (h * 16777619) & 0xffffffff;
  }
  return h;
}

class CardStats {
  final int power, control, speed, spin;
  const CardStats(this.power, this.control, this.speed, this.spin);
}

CardStats cardStats(String seed) {
  final h = hashStr(seed);
  // JS `>>` works on int32; h fits in uint32, convert to int32 first
  final s = h >= 0x80000000 ? h - 0x100000000 : h;
  return CardStats(60 + (h % 37), 55 + (s >> 6).remainder(42), 58 + (s >> 12).remainder(40), 50 + (s >> 18).remainder(46));
}

int rarity(Team t) => t.cat == 'vip' || t.cat == 'leg'
    ? 3
    : t.cat == 'lux' || t.cat == 'car' || t.cat == 'emb' || t.cat == 'chrome'
        ? 2
        : t.cat == 'spt' || t.cat == 'elite'
            ? 1
            : 0;

class Rarity {
  final String n;
  final int c;
  const Rarity(this.n, this.c);
}

const kRarity = [Rarity('COMMON', 0xff8ea3d6), Rarity('RARE', 0xff4fe3ff), Rarity('EPIC', 0xffb46bff), Rarity('LEGENDARY', 0xffffd257)];
