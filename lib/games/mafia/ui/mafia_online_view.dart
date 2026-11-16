import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/core/widgets/nx_widgets.dart';
import 'package:nexora/games/core/game_contract.dart';

import '../core/mafia_engine.dart';
import '../core/mafia_models.dart';

enum _Stage { intro, night, nominate, finalVote, over }

/// Online Mafia: every phone runs the same seeded [MafiaEngine] (same roles, same rules as the
/// offline game) and applies the same ordered inputs: ready, night actions, nomination and final
/// votes. Each phone only shows what its own player may know ([MafiaEngine.visibleRole], private log).
/// Day discussion is a live chat between the phones.
class MafiaOnlineView extends StatefulWidget {
  const MafiaOnlineView({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<MafiaOnlineView> createState() => _MafiaOnlineViewState();
}

class _MafiaOnlineViewState extends State<MafiaOnlineView> {
  late final MafiaEngine _e;
  late final NetLink _net;
  NetInbox? _inbox;
  StreamSubscription<NetLiveMessage>? _liveSub;
  bool _ready = false; // replay finished

  _Stage _stage = _Stage.intro;
  final Set<int> _readySeats = <int>{};
  final Map<int, int?> _night = <int, int?>{}; // role key (seat) -> target
  final Map<int, int?> _votes = <int, int?>{};
  List<int> _defendants = <int>[];
  final Set<int> _out = <int>{};
  final List<_Chat> _chat = <_Chat>[];
  final TextEditingController _msg = TextEditingController();
  DateTime _stageSince = DateTime.now();
  bool _finished = false;
  int? _pick;

  GameLaunch get _l => widget.launch;
  int get _me => _net.mySeat;
  MafiaPlayer get _mine => _e.player(_me);

  @override
  void initState() {
    super.initState();
    _net = _l.net!;
    _e = MafiaEngine.create(
      names: List<String>.generate(_net.seatCount, (int i) => _l.netName(i) ?? 'Pilot ${i + 1}'),
      config: const MafiaConfig(),
      rng: Random(_net.seed),
    );
    final NetInbox inbox = NetInbox(_onNet);
    _inbox = inbox;
    _net.listen(inbox.add,
        onReplayDone: () => inbox.add(const NetMove(seq: -1, seat: -1, kind: 'replayDone', data: <String, dynamic>{})));
    _liveSub = _net.live.listen(_onLive);
  }

  @override
  void dispose() {
    _inbox?.close();
    _liveSub?.cancel();
    _msg.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ rules glue
  int? get _mafiaLead {
    final MafiaPlayer? gf = _e.aliveHolderOf(MafiaRole.godfather);
    if (gf != null) return gf.id;
    for (final MafiaPlayer p in _e.players) {
      if (p.alive && p.isMafia) return p.id;
    }
    return null;
  }

  /// Seats that must act tonight (role holders alive and still in the match).
  List<int> get _nightActors {
    final List<int> out = <int>[];
    final int? lead = _mafiaLead;
    if (lead != null) out.add(lead);
    for (final MafiaRole r in <MafiaRole>[MafiaRole.doctor, MafiaRole.detective, MafiaRole.sniper]) {
      final MafiaPlayer? h = _e.aliveHolderOf(r);
      if (h == null) continue;
      if (r == MafiaRole.sniper && _e.sniperBullets <= 0) continue;
      out.add(h.id);
    }
    return out;
  }

  List<int> get _voters => _e.aliveIds;

  void _setStage(_Stage s) {
    _stage = s;
    _stageSince = DateTime.now();
    _pick = null;
    _votes.clear();
    _night.clear();
  }

  void _maybeAdvance() {
    if (_e.isOver) {
      _stage = _Stage.over;
      return;
    }
    switch (_stage) {
      case _Stage.intro:
        if (_net.seatCount > 0 && _e.players.every((MafiaPlayer p) => _readySeats.contains(p.id) || !p.alive)) {
          _setStage(_Stage.night);
        }
      case _Stage.night:
        if (_nightActors.every(_night.containsKey)) {
          final int? lead = _mafiaLead;
          final MafiaPlayer? doc = _e.aliveHolderOf(MafiaRole.doctor);
          final MafiaPlayer? det = _e.aliveHolderOf(MafiaRole.detective);
          final MafiaPlayer? sn = _e.aliveHolderOf(MafiaRole.sniper);
          _e.resolveNight(NightActions(
            mafiaTarget: lead == null ? null : _night[lead],
            doctorSave: doc == null ? null : _night[doc.id],
            detectiveCheck: det == null ? null : _night[det.id],
            sniperTarget: sn == null ? null : _night[sn.id],
          ));
          _setStage(_e.isOver ? _Stage.over : _Stage.nominate);
        }
      case _Stage.nominate:
        if (_voters.every(_votes.containsKey)) {
          final NominationResult r = _e.tallyNomination(Map<int, int?>.from(_votes));
          if (r.defendants.isEmpty) {
            _e.startNight();
            _setStage(_Stage.night);
          } else {
            final List<int> d = r.defendants;
            _setStage(_Stage.finalVote);
            _defendants = d;
          }
        }
      case _Stage.finalVote:
        if (_voters.every(_votes.containsKey)) {
          _e.resolveFinalVote(Map<int, int?>.from(_votes), _defendants);
          _defendants = <int>[];
          if (_e.isOver) {
            _setStage(_Stage.over);
          } else {
            _e.startNight();
            _setStage(_Stage.night);
          }
        }
      case _Stage.over:
        break;
    }
  }

  void _apply(NetMove m) {
    if (m.isForfeit) {
      final int s = (m.data['seat'] as num?)?.toInt() ?? m.seat;
      if (_out.add(s)) _e.leave(s);
      _night.remove(s);
      _votes.remove(s);
      _maybeAdvance();
      return;
    }
    final String a = '${m.data['a']}';
    final int? t = (m.data['t'] as num?)?.toInt();
    final int day = (m.data['d'] as num?)?.toInt() ?? -1;
    switch (a) {
      case 'ready':
        if (_stage == _Stage.intro) _readySeats.add(m.seat);
      case 'night':
        if (_stage == _Stage.night && day == _e.day && _nightActors.contains(m.seat)) _night[m.seat] = t;
      case 'nom':
        if (_stage == _Stage.nominate && day == _e.day && _e.player(m.seat).alive) _votes[m.seat] = t;
      case 'final':
        if (_stage == _Stage.finalVote && day == _e.day && _e.player(m.seat).alive) _votes[m.seat] = t;
    }
    _maybeAdvance();
  }

  Future<void> _onNet(NetMove m) async {
    if (!mounted) return;
    if (m.kind == 'replayDone') {
      _ready = true;
      setState(() {});
      _checkOver();
      return;
    }
    final _Stage before = _stage;
    final int dayBefore = _e.day;
    _apply(m);
    if (m.replay) return;
    if (_stage != before || _e.day != dayBefore) {
      if (_l.soundOn) HapticFeedback.mediumImpact();
    }
    setState(() {});
    _checkOver();
  }

  void _send(String a, {int? t}) {
    final Map<String, dynamic> d = <String, dynamic>{'a': a, 'd': _e.day, 't': t};
    _net.send(d);
    _apply(NetMove(seq: 0, seat: _me, kind: 'move', data: d));
    setState(() {});
    _checkOver();
  }

  void _checkOver() {
    if (!_e.isOver || _finished) return;
    _finished = true;
    final MafiaTeam w = _e.winner!;
    final List<int> winners = <int>[for (final MafiaPlayer p in _e.players) if (p.role.team == w) p.id];
    final bool won = _mine.role.team == w;
    Future<void>.delayed(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      _l.onFinish(GameResult(
        outcome: won ? GameOutcome.win : GameOutcome.loss,
        winnerSeats: winners,
        summaryFa: '${teamLabel(w, true)} پیروز شد. نقش تو: ${_mine.role.labelFa}.',
        summaryEn: '${teamLabel(w, false)} won. Your role: ${_mine.role.labelEn}.',
      ));
    });
  }

  void _onLive(NetLiveMessage m) {
    if (!mounted || m.event != 'chat') return;
    final String text = '${m.data['t'] ?? ''}'.trim();
    if (text.isEmpty || m.seat < 0 || m.seat >= _e.playerCount) return;
    final bool mafiaOnly = m.data['m'] == true;
    if (mafiaOnly && !_mine.isMafia) return;
    setState(() {
      _chat.add(_Chat(m.seat, text.length > 240 ? text.substring(0, 240) : text, mafiaOnly));
      if (_chat.length > 80) _chat.removeAt(0);
    });
  }

  void _sendChat() {
    final String t = _msg.text.trim();
    if (t.isEmpty || !_mine.alive) return;
    final bool mafiaOnly = _stage == _Stage.night && _mine.isMafia;
    if (_stage == _Stage.night && !mafiaOnly) return;
    _net.sendLive('chat', <String, dynamic>{'t': t, 'm': mafiaOnly});
    setState(() {
      _chat.add(_Chat(_me, t, mafiaOnly));
      _msg.clear();
    });
  }

  /// Authority: players who are present but idle for too long are skipped (counted as "no choice").
  void _skipIdle() {
    final List<int> waiting = _waitingOn();
    for (final int s in waiting) {
      if (s == _me) continue;
      final String a = _stage == _Stage.night ? 'night' : (_stage == _Stage.nominate ? 'nom' : 'final');
      final Map<String, dynamic> d = <String, dynamic>{'a': a, 'd': _e.day, 't': null};
      _net.send(d, kind: 'timeout', asSeat: s);
      _apply(NetMove(seq: 0, seat: s, kind: 'timeout', data: d));
    }
    setState(() {});
    _checkOver();
  }

  List<int> _waitingOn() {
    switch (_stage) {
      case _Stage.intro:
        return <int>[for (final MafiaPlayer p in _e.players) if (p.alive && !_readySeats.contains(p.id)) p.id];
      case _Stage.night:
        return _nightActors.where((int s) => !_night.containsKey(s)).toList();
      case _Stage.nominate:
      case _Stage.finalVote:
        return _voters.where((int s) => !_votes.containsKey(s)).toList();
      case _Stage.over:
        return <int>[];
    }
  }

  // ------------------------------------------------------------------ UI
  String _t(String fa, String en) => _l.tx(fa, en);

  @override
  Widget build(BuildContext context) {
    final bool night = _stage == _Stage.night || _stage == _Stage.intro;
    return NxBackground(
      palette: night ? WorldPalette.oracle : WorldPalette.social,
      stars: _l.fancyEffects,
      child: SafeArea(
        child: !_ready
            ? const Center(child: CircularProgressIndicator())
            : Column(children: <Widget>[
                const SizedBox(height: 8),
                Padding(padding: const EdgeInsets.fromLTRB(64, 0, 40, 6), child: _header()),
                Expanded(
                  child: ListView(padding: const EdgeInsets.symmetric(horizontal: NxSpace.md), children: <Widget>[
                    _roleCard(),
                    const SizedBox(height: 10),
                    _actionPanel(),
                    const SizedBox(height: 10),
                    _playersGrid(),
                    const SizedBox(height: 10),
                    _logPanel(),
                    const SizedBox(height: 10),
                    _chatPanel(),
                    const SizedBox(height: 16),
                  ]),
                ),
                if (_mine.alive && _stage != _Stage.over && (_stage != _Stage.night || _mine.isMafia)) _chatInput(),
              ]),
      ),
    );
  }

  Widget _header() {
    final String phase = switch (_stage) {
      _Stage.intro => _t('آشنایی با نقش‌ها', 'Meet your role'),
      _Stage.night => _t('شب ${_e.day}', 'Night ${_e.day}'),
      _Stage.nominate => _t('روز ${_e.day} · رأی‌گیری اول', 'Day ${_e.day} · nomination'),
      _Stage.finalVote => _t('روز ${_e.day} · رأی نهایی', 'Day ${_e.day} · final vote'),
      _Stage.over => _t('پایان بازی', 'Game over'),
    };
    return Row(children: <Widget>[
      Icon(_stage == _Stage.night ? Icons.nightlight_round : Icons.wb_sunny_rounded,
          color: _stage == _Stage.night ? NxColors.violet : NxColors.gold),
      const SizedBox(width: 8),
      Expanded(child: Text(phase, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
      NxPill(label: '${_e.aliveCount}/${_e.playerCount}', icon: Icons.people_alt_rounded, color: NxColors.turquoise),
    ]);
  }

  Widget _roleCard() {
    final MafiaRole r = _mine.role;
    final List<String> partners = <String>[
      for (final MafiaPlayer p in _e.players)
        if (p.id != _me && _mine.isMafia && p.isMafia) '${p.name} (${_t(p.role.labelFa, p.role.labelEn)})',
    ];
    return GlassPanel(
      borderColor: (r.isMafia ? NxColors.danger : NxColors.turquoise).withValues(alpha: 0.6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Icon(r.isMafia ? Icons.masks_rounded : Icons.shield_rounded, color: r.isMafia ? NxColors.danger : NxColors.turquoise),
          const SizedBox(width: 8),
          Text(_t('نقش تو: ${r.labelFa}', 'Your role: ${r.labelEn}'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const Spacer(),
          if (!_mine.alive) NxPill(label: _t('حذف شده', 'Out'), icon: Icons.close_rounded, color: NxColors.danger),
        ]),
        const SizedBox(height: 6),
        Text(_t(r.descFa, r.descEn), style: const TextStyle(color: NxColors.textDim, fontSize: 12, height: 1.5)),
        if (partners.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(_t('هم‌تیمی‌ها: ${partners.join('، ')}', 'Partners: ${partners.join(', ')}'),
              style: const TextStyle(color: NxColors.danger, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
        if (r == MafiaRole.detective && _e.detectiveResults.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          for (final MapEntry<int, bool> en in _e.detectiveResults.entries)
            Text(
              _t('استعلام ${_e.player(en.key).name}: ${en.value ? 'مافیا' : 'بی‌گناه'}',
                  'Check ${_e.player(en.key).name}: ${en.value ? 'Mafia' : 'innocent'}'),
              style: TextStyle(color: en.value ? NxColors.danger : NxColors.success, fontSize: 12),
            ),
        ],
      ]),
    );
  }

  Widget _actionPanel() {
    final List<int> waiting = _waitingOn();
    final bool idleLong = DateTime.now().difference(_stageSince).inSeconds > 120;
    final Widget waitLine = Text(
      waiting.isEmpty
          ? ''
          : _t('در انتظار: ${waiting.map((int s) => _e.player(s).name).join('، ')}',
              'Waiting for: ${waiting.map((int s) => _e.player(s).name).join(', ')}'),
      style: const TextStyle(color: NxColors.textDim, fontSize: 12),
    );
    final Widget skip = _net.isAuthority && idleLong && waiting.any((int s) => s != _me)
        ? TextButton.icon(
            onPressed: _skipIdle,
            icon: const Icon(Icons.fast_forward_rounded),
            label: Text(_t('رد کردن بازیکنان غایب', 'Skip idle players')),
          )
        : const SizedBox.shrink();
    switch (_stage) {
      case _Stage.over:
        final MafiaTeam? w = _e.winner;
        return GlassPanel(
          child: Text(
            w == null ? '' : _t('${teamLabel(w, true)} پیروز شد!', '${teamLabel(w, false)} wins!'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: NxColors.gold),
          ),
        );
      case _Stage.intro:
        return GlassPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text(_t('نقشت را به خاطر بسپار و به کسی نشانش نده.', 'Remember your role and keep it secret.')),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _readySeats.contains(_me) ? null : () => _send('ready'),
              icon: const Icon(Icons.check_rounded),
              label: Text(_readySeats.contains(_me) ? _t('آماده‌ای ✓', 'Ready ✓') : _t('آماده‌ام', "I'm ready")),
            ),
            waitLine,
            skip,
          ]),
        );
      case _Stage.night:
        final bool actor = _nightActors.contains(_me);
        if (!actor || _night.containsKey(_me)) {
          return GlassPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Text(
                !_mine.alive
                    ? _t('تو از بازی خارج شده‌ای؛ تماشا کن.', 'You are out — watch the game.')
                    : actor
                        ? _t('انتخابت ثبت شد. منتظر بقیه…', 'Your choice is locked in. Waiting…')
                        : (_mine.isMafia
                            ? _t('رهبر مافیا قربانی را انتخاب می‌کند؛ در چت مافیا پیشنهاد بده.',
                                'Your leader picks the target — suggest one in the Mafia chat.')
                            : _t('شهر خواب است… چشم‌هایت را ببند.', 'The town sleeps… close your eyes.')),
              ),
              waitLine,
              skip,
            ]),
          );
        }
        final MafiaRole r = _mine.role;
        final List<int> legal = r.isMafia
            ? _e.legalMafiaTargets()
            : r == MafiaRole.doctor
                ? _e.legalDoctorTargets()
                : r == MafiaRole.detective
                    ? _e.legalDetectiveTargets()
                    : _e.legalSniperTargets();
        final String prompt = r.isMafia
            ? _t('امشب چه کسی را حذف می‌کنید؟', 'Who do you eliminate tonight?')
            : r == MafiaRole.doctor
                ? _t('چه کسی را نجات می‌دهی؟', 'Who do you save?')
                : r == MafiaRole.detective
                    ? _t('هویت چه کسی را استعلام می‌کنی؟', 'Whom do you investigate?')
                    : _t('شلیک می‌کنی؟ (یک گلوله)', 'Fire your single bullet?');
        return _picker(prompt, legal, (int? t) => _send('night', t: t),
            allowNone: r == MafiaRole.sniper, noneLabel: _t('شلیک نمی‌کنم', 'Hold fire'), extra: <Widget>[waitLine, skip]);
      case _Stage.nominate:
        if (!_mine.alive || _votes.containsKey(_me)) {
          return GlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text(_mine.alive ? _t('رأیت ثبت شد.', 'Vote recorded.') : _t('تو از بازی خارج شده‌ای.', 'You are out.')),
            waitLine,
            skip,
          ]));
        }
        return _picker(_t('گفتگو کنید، بعد به کسی که مشکوک است رأی بده.', 'Discuss, then vote for a suspect.'),
            _e.legalVoteTargets(_me), (int? t) => _send('nom', t: t),
            allowNone: true, noneLabel: _t('رأی نمی‌دهم', 'Skip'), extra: <Widget>[waitLine, skip]);
      case _Stage.finalVote:
        if (!_mine.alive || _votes.containsKey(_me)) {
          return GlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text(_t('به دفاع: ${_defendants.map((int d) => _e.player(d).name).join('، ')}',
                'On trial: ${_defendants.map((int d) => _e.player(d).name).join(', ')}')),
            waitLine,
            skip,
          ]));
        }
        return _picker(
            _t('دفاع شنیده شد. چه کسی حذف شود؟', 'Defences heard. Who should leave?'),
            _defendants.where((int d) => d != _me).toList(),
            (int? t) => _send('final', t: t),
            allowNone: true,
            noneLabel: _t('هیچ‌کس (بخشش)', 'Nobody (spare)'),
            extra: <Widget>[waitLine, skip]);
    }
  }

  Widget _picker(String prompt, List<int> legal, void Function(int?) onConfirm,
      {bool allowNone = false, String noneLabel = '', List<Widget> extra = const <Widget>[]}) {
    return GlassPanel(
      borderColor: NxColors.gold.withValues(alpha: 0.6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text(prompt, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          for (final int id in legal)
            ChoiceChip(
              label: Text(_e.player(id).name),
              selected: _pick == id,
              onSelected: (_) => setState(() => _pick = id),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          if (allowNone)
            Expanded(child: OutlinedButton(onPressed: () => onConfirm(null), child: Text(noneLabel))),
          if (allowNone) const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: _pick == null || !legal.contains(_pick) ? null : () => onConfirm(_pick),
              child: Text(_t('تأیید', 'Confirm')),
            ),
          ),
        ]),
        ...extra,
      ]),
    );
  }

  Widget _playersGrid() {
    return GlassPanel(
      child: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
        for (final MafiaPlayer p in _e.players)
          Builder(builder: (BuildContext context) {
            final MafiaRole? role = _e.visibleRole(_me, p.id);
            final bool online = _net.connectedSeats.contains(p.id);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: p.alive ? NxColors.glass : Colors.black26,
                border: Border.all(color: p.id == _me ? NxColors.gold : NxColors.glassBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: online ? NxColors.success : NxColors.textDim),
                ),
                const SizedBox(width: 6),
                Text(p.name,
                    style: TextStyle(
                        decoration: p.alive ? null : TextDecoration.lineThrough,
                        color: p.alive ? NxColors.iceWhite : NxColors.textDim,
                        fontWeight: FontWeight.w700)),
                if (role != null && p.id != _me) ...<Widget>[
                  const SizedBox(width: 4),
                  Text('· ${_t(role.labelFa, role.labelEn)}',
                      style: TextStyle(color: role.isMafia ? NxColors.danger : NxColors.turquoise, fontSize: 11)),
                ],
              ]),
            );
          }),
      ]),
    );
  }

  Widget _logPanel() {
    final List<GameLogEntry> log = _e.logFor(_me);
    final List<GameLogEntry> last = log.length > 12 ? log.sublist(log.length - 12) : log;
    return GlassPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(_t('رویدادها', 'Events'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final GameLogEntry e in last.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(_t(e.fa, e.en),
                style: TextStyle(
                    fontSize: 12,
                    color: e.kind == LogKind.death
                        ? NxColors.danger
                        : (e.visibleTo != null ? NxColors.gold : NxColors.iceWhite))),
          ),
      ]),
    );
  }

  Widget _chatPanel() {
    if (_chat.isEmpty) return const SizedBox.shrink();
    return GlassPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(_t('گفتگو', 'Discussion'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final _Chat c in _chat.length > 30 ? _chat.sublist(_chat.length - 30) : _chat)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(TextSpan(children: <InlineSpan>[
              TextSpan(
                text: '${_e.player(c.seat).name}${c.mafiaOnly ? ' 🔒' : ''}: ',
                style: TextStyle(fontWeight: FontWeight.w800, color: c.mafiaOnly ? NxColors.danger : NxColors.turquoise),
              ),
              TextSpan(text: c.text),
            ]), style: const TextStyle(fontSize: 13)),
          ),
      ]),
    );
  }

  Widget _chatInput() {
    final bool mafiaOnly = _stage == _Stage.night && _mine.isMafia;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(children: <Widget>[
        Expanded(
          child: TextField(
            controller: _msg,
            maxLength: 240,
            decoration: InputDecoration(
              counterText: '',
              hintText: mafiaOnly ? _t('چت مخفی مافیا…', 'Secret Mafia chat…') : _t('حرفت را بزن…', 'Say something…'),
            ),
            onSubmitted: (_) => _sendChat(),
          ),
        ),
        IconButton(onPressed: _sendChat, icon: const Icon(Icons.send_rounded, color: NxColors.turquoise)),
      ]),
    );
  }
}

class _Chat {
  _Chat(this.seat, this.text, this.mafiaOnly);
  final int seat;
  final String text;
  final bool mafiaOnly;
}
