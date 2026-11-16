// Prize maths shared by the admin wizard preview and the tests. Mirrors _nx_t_prize_total and
// _nx_t_split in supabase/migrations/20261116000100_nx_tournaments_engine.sql (integer maths,
// floor division, remainder to the champion).

class PrizeConfig {
  const PrizeConfig({this.fixed = 0, this.poolPct = 0, this.feePct = 0, this.dist = const <int>[60, 30, 10]});

  factory PrizeConfig.fromJson(Map<String, dynamic>? j, {String currency = 'coins'}) {
    final Map<String, dynamic> m = j ?? const <String, dynamic>{};
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    final List<dynamic> d = (m['dist'] as List<dynamic>?) ?? const <dynamic>[60, 30, 10];
    return PrizeConfig(
      fixed: n(m[currency == 'gems' ? 'fixed_gems' : 'fixed_coins']),
      poolPct: n(m['pool_pct']),
      feePct: n(m['fee_pct']),
      dist: d.map(n).toList(),
    );
  }

  /// Fixed prize (minted by an admin).
  final int fixed;

  /// Share of the escrowed entry fees that goes into the prize pool (0..100).
  final int poolPct;

  /// House fee taken from that pool part (0..50).
  final int feePct;

  /// Percent of the total per place (index 0 = 1st place).
  final List<int> dist;
}

class PrizeSplit {
  const PrizeSplit._();

  static int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  /// Pool part of the escrow = escrow * pool% (floor).
  static int poolPart(int escrow, int poolPct) => (escrow < 0 ? 0 : escrow) * _clamp(poolPct, 0, 100) ~/ 100;

  /// House fee = pool part * fee% (floor).
  static int houseFee(int escrow, int poolPct, int feePct) => poolPart(escrow, poolPct) * _clamp(feePct, 0, 100) ~/ 100;

  /// Total paid to players.
  static int total(PrizeConfig c, int escrow) =>
      (c.fixed < 0 ? 0 : c.fixed) + poolPart(escrow, c.poolPct) - houseFee(escrow, c.poolPct, c.feePct);

  /// Amount per player. [places] maps player → place (1-based; equal places share). [order] breaks ties for
  /// who receives the rounding remainder (the first champion in this order, like `order by seed` on the server).
  static Map<String, int> split(int total, List<int> dist, Map<String, int> places, {List<String>? order}) {
    final Map<String, int> out = <String, int>{};
    if (total <= 0 || places.isEmpty) return out;
    final List<String> ord = order ?? (places.keys.toList()..sort());
    final Map<int, List<String>> byPlace = <int, List<String>>{};
    for (final String p in ord) {
      final int? pl = places[p];
      if (pl == null) continue;
      byPlace.putIfAbsent(pl, () => <String>[]).add(p);
    }
    final List<int> pls = byPlace.keys.toList()..sort();
    int dsum = 0;
    for (final int d in dist) {
      dsum += d < 0 ? 0 : d;
    }
    int paid = 0;
    String? top;
    for (final int pl in pls) {
      final List<String> us = byPlace[pl]!;
      int share = 0;
      for (int i = pl; i < pl + us.length; i++) {
        if (i <= dist.length) share += dist[i - 1] < 0 ? 0 : dist[i - 1];
      }
      if (share <= 0) continue;
      final int each = total * share ~/ 100 ~/ us.length;
      for (final String u in us) {
        out[u] = (out[u] ?? 0) + each;
        paid += each;
        if (top == null && pl == pls.first) top = u;
      }
    }
    final int target = total * (dsum > 100 ? 100 : dsum) ~/ 100;
    if (top != null && target - paid > 0) out[top] = out[top]! + target - paid;
    return out;
  }

  /// Preview of the amount for each place when nobody shares a place.
  static List<int> perPlace(int total, List<int> dist) {
    final Map<String, int> places = <String, int>{for (int i = 1; i <= dist.length; i++) 'p$i': i};
    final Map<String, int> s = split(total, dist, places, order: <String>[for (int i = 1; i <= dist.length; i++) 'p$i']);
    return <int>[for (int i = 1; i <= dist.length; i++) s['p$i'] ?? 0];
  }
}
