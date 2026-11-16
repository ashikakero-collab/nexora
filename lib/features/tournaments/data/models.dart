import '../domain/bracket.dart';

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? d);
bool _b(Object? v, [bool d = false]) => v is bool ? v : d;
DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toUtc();
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// List tabs of the tournaments page.
enum TTab { registering, upcoming, live, finished, mine }

class Tournament {
  Tournament(this.raw)
      : id = '${raw['id']}',
        title = '${raw['title'] ?? ''}',
        description = '${raw['description'] ?? ''}',
        rules = '${raw['rules'] ?? ''}',
        game = '${raw['game'] ?? 'finger_soccer'}',
        createdBy = '${raw['created_by'] ?? ''}',
        status = '${raw['status'] ?? 'draft'}',
        paused = _b(raw['paused']),
        format = TFormatCode.parse(raw['format'] as String?),
        capacity = _i(raw['capacity'], 2),
        minPlayers = _i(raw['min_players'], 2),
        config = _m(raw['config']),
        regMode = '${raw['reg_mode'] ?? 'open'}',
        minLevel = _i(raw['min_level']),
        minXp = _i(raw['min_xp']),
        minRating = _i(raw['min_rating']),
        feeCoins = _i(raw['fee_coins']),
        feeGems = _i(raw['fee_gems']),
        prize = _m(raw['prize']),
        regOpenAt = _t(raw['reg_open_at']) ?? DateTime.now().toUtc(),
        regCloseAt = _t(raw['reg_close_at']) ?? DateTime.now().toUtc(),
        drawAt = _t(raw['draw_at']) ?? DateTime.now().toUtc(),
        startAt = _t(raw['start_at']) ?? DateTime.now().toUtc(),
        seeding = '${raw['seeding'] ?? 'random'}',
        stage = '${raw['stage'] ?? 'main'}',
        escrowCoins = _i(raw['escrow_coins']),
        escrowGems = _i(raw['escrow_gems']),
        paidOut = _b(raw['paid_out']),
        cancelReason = raw['cancel_reason'] as String?,
        winner = raw['winner'] as String?,
        finishedAt = _t(raw['finished_at']);

  final Map<String, dynamic> raw;
  final String id;
  final String title;
  final String description;
  final String rules;
  final String game;
  final String createdBy;
  final String status;
  final bool paused;
  final TFormat format;
  final int capacity;
  final int minPlayers;
  final Map<String, dynamic> config;
  final String regMode;
  final int minLevel;
  final int minXp;
  final int minRating;
  final int feeCoins;
  final int feeGems;
  final Map<String, dynamic> prize;
  final DateTime regOpenAt;
  final DateTime regCloseAt;
  final DateTime drawAt;
  final DateTime startAt;
  final String seeding;
  final String stage;
  final int escrowCoins;
  final int escrowGems;
  final bool paidOut;
  final String? cancelReason;
  final String? winner;
  final DateTime? finishedAt;

  int cfg(String k, int d) => _i(config[k], d);
  bool cfgB(String k, bool d) => config[k] is bool ? config[k] as bool : d;

  bool get isFree => feeCoins == 0 && feeGems == 0;
  bool get needsCode => regMode == 'code' || regMode == 'code_approval';
  bool get needsApproval => regMode == 'approval' || regMode == 'code_approval';
  bool get canRegister => status == 'registering';
  bool get isOver => status == 'finished' || status == 'cancelled';

  TTab get tab => switch (status) {
        'registering' => TTab.registering,
        'live' => TTab.live,
        'finished' || 'cancelled' => TTab.finished,
        _ => TTab.upcoming,
      };

  /// Next scheduled moment for the countdown: (label code, time) or null.
  (String, DateTime)? get nextMoment => switch (status) {
        'draft' || 'scheduled' => ('reg_opens', regOpenAt),
        'registering' => ('reg_closes', regCloseAt),
        'closed' => ('draw', drawAt),
        'drawn' => ('start', startAt),
        _ => null,
      };
}

class TEntry {
  TEntry(Map<String, dynamic> r)
      : tournamentId = '${r['tournament_id']}',
        userId = '${r['user_id']}',
        status = '${r['status']}',
        seed = r['seed'] == null ? null : _i(r['seed']),
        groupNo = r['group_no'] == null ? null : _i(r['group_no']),
        rating = _i(r['rating'], 1000),
        place = r['place'] == null ? null : _i(r['place']),
        paidCoins = _i(r['paid_coins']),
        paidGems = _i(r['paid_gems']),
        note = r['note'] as String?,
        createdAt = _t(r['created_at']),
        username = '${_m(r['profiles'])['username'] ?? 'Pilot'}';

  final String tournamentId;
  final String userId;
  final String status;
  final int? seed;
  final int? groupNo;
  final int rating;
  final int? place;
  final int paidCoins;
  final int paidGems;
  final String? note;
  final DateTime? createdAt;
  final String username;

  bool get active => status == 'approved' || status == 'pending' || status == 'waitlist';
}

class TMatch {
  TMatch(Map<String, dynamic> r)
      : id = '${r['id']}',
        tournamentId = '${r['tournament_id']}',
        stage = '${r['stage'] ?? 'main'}',
        bracket = '${r['bracket']}',
        round = _i(r['round'], 1),
        idx = _i(r['idx']),
        groupNo = r['group_no'] == null ? null : _i(r['group_no']),
        label = r['label'] as String?,
        p1 = r['p1'] as String?,
        p2 = r['p2'] as String?,
        p1Set = _b(r['p1_set']),
        p2Set = _b(r['p2_set']),
        winTo = r['win_to'] as String?,
        bestOf = _i(r['best_of'], 1),
        aggregate = _b(r['aggregate']),
        status = '${r['status']}',
        scheduledAt = _t(r['scheduled_at']),
        readyDeadline = _t(r['ready_deadline']),
        p1Ready = _b(r['p1_ready']),
        p2Ready = _b(r['p2_ready']),
        games = _i(r['games']),
        w1 = _i(r['w1']),
        w2 = _i(r['w2']),
        g1 = _i(r['g1']),
        g2 = _i(r['g2']),
        winner = r['winner'] as String?,
        loser = r['loser'] as String?,
        isDraw = _b(r['is_draw']),
        gameMatch = r['game_match'] as String?,
        resultNote = r['result_note'] as String?;

  final String id;
  final String tournamentId;
  final String stage;
  final String bracket;
  final int round;
  final int idx;
  final int? groupNo;
  final String? label;
  final String? p1;
  final String? p2;
  final bool p1Set;
  final bool p2Set;
  final String? winTo;
  final int bestOf;
  final bool aggregate;
  final String status;
  final DateTime? scheduledAt;
  final DateTime? readyDeadline;
  final bool p1Ready;
  final bool p2Ready;
  final int games;
  final int w1;
  final int w2;
  final int g1;
  final int g2;
  final String? winner;
  final String? loser;
  final bool isDraw;
  final String? gameMatch;
  final String? resultNote;

  bool get isFinal => kFinalStatuses.contains(status);
  bool get isElim => kElimBrackets.contains(bracket);
  bool involves(String? uid) => uid != null && (p1 == uid || p2 == uid);

  /// Score shown on cards: series wins for Bo>1 (or aggregate goals for two legs), goals for Bo1.
  (int, int) get shownScore => aggregate || bestOf == 1 ? (g1, g2) : (w1, w2);
}

class TNotification {
  TNotification(Map<String, dynamic> r)
      : id = _i(r['id']),
        tournamentId = r['tournament_id'] as String?,
        tmatch = r['tmatch'] as String?,
        kind = '${r['kind']}',
        data = _m(r['data']),
        read = _b(r['read']),
        createdAt = _t(r['created_at']) ?? DateTime.now().toUtc();

  final int id;
  final String? tournamentId;
  final String? tmatch;
  final String kind;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime createdAt;

  String get title => '${data['title'] ?? 'NEXORA'}';
}

class StandingRow {
  StandingRow(Map<String, dynamic> r)
      : groupNo = r['group_no'] == null ? null : _i(r['group_no']),
        userId = '${r['user_id']}',
        username = '${r['username'] ?? 'Pilot'}',
        seed = _i(r['seed']),
        played = _i(r['played']),
        won = _i(r['won']),
        drawn = _i(r['drawn']),
        lost = _i(r['lost']),
        gf = _i(r['gf']),
        ga = _i(r['ga']),
        pts = _i(r['pts']),
        rank = _i(r['rank']);

  final int? groupNo;
  final String userId;
  final String username;
  final int seed;
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int gf;
  final int ga;
  final int pts;
  final int rank;
}

class TCode {
  TCode(Map<String, dynamic> r)
      : id = '${r['id']}',
        code = '${r['code']}',
        maxUses = _i(r['max_uses'], 1),
        uses = _i(r['uses']),
        expiresAt = _t(r['expires_at']),
        revoked = _b(r['revoked']),
        requiresApproval = _b(r['requires_approval']);

  final String id;
  final String code;
  final int maxUses;
  final int uses;
  final DateTime? expiresAt;
  final bool revoked;
  final bool requiresApproval;

  bool get usable => !revoked && uses < maxUses && (expiresAt == null || expiresAt!.isAfter(DateTime.now().toUtc()));
}
