import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../core/game_contract.dart';
import '../core/mafia_engine.dart';
import '../core/mafia_lines.dart';
import '../core/mafia_match.dart';
import '../core/mafia_models.dart';
import 'mafia_visuals.dart';
import 'mafia_widgets.dart';

enum _Stage {
  reveal,
  nightIntro,
  nightAction,
  nightWait,
  dawn,
  selfOut,
  discussion,
  nominationVote,
  tally,
  defense,
  finalVote,
  verdict,
  over,
}

/// Player + AI citizens on the moonlit station.
class MafiaVsBotView extends StatefulWidget {
  const MafiaVsBotView({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<MafiaVsBotView> createState() => _MafiaVsBotViewState();
}

class _MafiaVsBotViewState extends State<MafiaVsBotView> {
  late final MafiaMatch _m;
  _Stage _stage = _Stage.reveal;
  bool _flipped = false;
  int? _selected;
  int? _suggestion;
  final List<Timer> _timers = <Timer>[];
  final List<SpeechLine> _shown = <SpeechLine>[];
  bool _talking = false;
  int? _speakingId;
  int _rounds = 0;
  Map<int, int> _liveVotes = <int, int>{};
  final List<MapEntry<int, int?>> _voteFeed = <MapEntry<int, int?>>[];
  bool _tallyFinal = false;
  bool _tallyDone = false;
  List<int> _defendants = <int>[];
  NightResult? _night;
  FinalVoteResult? _final;
  SpeechLine? _lastWords;
  bool _humanDefended = false;
  bool _spectating = false;
  bool _finished = false;
  VoidCallback? _afterSelfOut;

  GameLaunch get _l => widget.launch;
  bool get _fa => _l.isFa;
  String _t(String fa, String en) => _l.tx(fa, en);
  bool get _fx => _l.fancyEffects && !_l.reducedMotion;
  MafiaEngine get _e => _m.engine;

  @override
  void initState() {
    super.initState();
    MafiaSkill skill = MafiaSkill.normal;
    if (_l.difficulty == BotDifficulty.easy) skill = MafiaSkill.easy;
    if (_l.difficulty == BotDifficulty.hard) skill = MafiaSkill.hard;
    _m = MafiaMatch.create(
      humanName: _l.playerName,
      isFa: _l.isFa,
      totalPlayers: _l.playerCount,
      skill: skill,
      seed: _l.seed ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  void dispose() {
    for (final Timer t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  // ----------------------------------------------------------------- utils
  void _after(int ms, VoidCallback f) {
    final int d = _l.reducedMotion ? (ms * 0.6).round() : ms;
    _timers.add(Timer(Duration(milliseconds: d), () {
      if (mounted) f();
    }));
  }

  void _haptic() {
    if (_l.soundOn) HapticFeedback.mediumImpact();
  }

  double _hue(int id) => id == MafiaMatch.humanId ? 265 : (_m.personas[id]?.hue ?? 200);
  String? _emblem(int id) => _m.personas[id]?.emblem;
  String _name(int id) => _m.nameOf(id);

  // ------------------------------------------------------------------ flow
  void _beginNight() {
    setState(() {
      _stage = _Stage.nightIntro;
      _selected = null;
      _defendants = <int>[];
      _liveVotes = <int, int>{};
      _speakingId = null;
    });
    _after(1600, () {
      final List<int> opts = _m.humanNightOptions();
      if (opts.isNotEmpty) {
        setState(() {
          _stage = _Stage.nightAction;
          _suggestion = _m.humanRole.isMafia ? _m.mafiaSuggestion() : null;
        });
      } else {
        setState(() => _stage = _Stage.nightWait);
        _after(1900, () => _resolveNight(null));
      }
    });
  }

  void _resolveNight(int? choice) {
    final NightResult r = _m.playNight(humanChoice: choice);
    if (r.deaths.isNotEmpty) _haptic();
    setState(() {
      _night = r;
      _stage = _Stage.dawn;
      _selected = null;
      _suggestion = null;
      _shown.clear();
      _humanDefended = false;
    });
  }

  void _afterDawn() {
    if (_m.isOver) {
      _toOver();
      return;
    }
    if (!_m.humanAlive && !_spectating) {
      _goSelfOut(_startDiscussion);
      return;
    }
    _startDiscussion();
  }

  void _goSelfOut(VoidCallback next) {
    setState(() {
      _afterSelfOut = next;
      _stage = _Stage.selfOut;
    });
  }

  void _startDiscussion() {
    setState(() {
      _stage = _Stage.discussion;
      _rounds = 0;
    });
    _runBotRound();
  }

  void _runBotRound({int maxLines = 5}) {
    if (_talking) return;
    _rounds++;
    final List<SpeechLine> lines = _m.discussionRound(maxLines: maxLines);
    setState(() => _talking = true);
    _playLines(lines, () {
      setState(() {
        _talking = false;
        _speakingId = null;
      });
      if (!_m.humanAlive && _stage == _Stage.discussion) {
        if (_rounds < 2) {
          _after(500, () => _runBotRound());
        } else {
          _after(700, _startNomination);
        }
      }
    });
  }

  void _playLines(List<SpeechLine> lines, VoidCallback done) {
    if (lines.isEmpty) {
      _after(450, done);
      return;
    }
    void step(int i) {
      if (i >= lines.length) {
        _after(350, done);
        return;
      }
      setState(() {
        _shown.add(lines[i]);
        _speakingId = lines[i].speaker;
      });
      final int len = (_fa ? lines[i].fa : lines[i].en).length;
      _after((700 + len * 14).clamp(900, 2300).toInt(), () => step(i + 1));
    }

    step(0);
  }

  void _humanSay(SpeechAct act, {bool react = true}) {
    final SpeechLine line = _m.say(act);
    setState(() => _shown.add(line));
    if (react && _stage == _Stage.discussion) {
      _after(500, () {
        if (_stage == _Stage.discussion) _runBotRound(maxLines: 2);
      });
    }
  }

  void _startNomination() {
    if (_m.isOver) return;
    if (_m.humanAlive) {
      setState(() {
        _stage = _Stage.nominationVote;
        _selected = null;
      });
    } else {
      _runTally(final_: false, humanVote: null);
    }
  }

  void _runTally({required bool final_, required int? humanVote}) {
    final Map<int, int?> votes = final_
        ? _m.collectFinalVotes(_defendants, humanVote: humanVote)
        : _m.collectNominationVotes(humanVote: humanVote);
    final List<MapEntry<int, int?>> entries = votes.entries.toList();
    setState(() {
      _stage = _Stage.tally;
      _tallyFinal = final_;
      _tallyDone = false;
      _liveVotes = <int, int>{};
      _voteFeed.clear();
      _selected = null;
    });
    void step(int i) {
      if (i >= entries.length) {
        _after(600, () => _finishTally(votes));
        return;
      }
      final MapEntry<int, int?> en = entries[i];
      setState(() {
        _voteFeed.add(en);
        if (en.value != null) _liveVotes[en.value!] = (_liveVotes[en.value!] ?? 0) + 1;
      });
      if (en.value != null && _l.soundOn) HapticFeedback.selectionClick();
      _after(420, () => step(i + 1));
    }

    _after(400, () => step(0));
  }

  void _finishTally(Map<int, int?> votes) {
    if (!_tallyFinal) {
      final NominationResult r = _m.nominate(votes);
      setState(() {
        _defendants = r.defendants;
        _tallyDone = true;
      });
      if (r.defendants.isNotEmpty) _after(1400, _startDefense);
      if (r.defendants.isEmpty && !_m.humanAlive) _after(1600, _endDay);
    } else {
      final FinalVoteResult r = _m.finalVote(votes, _defendants);
      if (r.eliminated != null) _haptic();
      setState(() {
        _final = r;
        _tallyDone = true;
        _lastWords = r.eliminated == null ? null : _m.lastWords(r.eliminated!);
      });
      _after(1300, () => setState(() => _stage = _Stage.verdict));
    }
  }

  void _startDefense() {
    final List<SpeechLine> lines = _m.defenseSpeeches(_defendants);
    setState(() {
      _stage = _Stage.defense;
      _liveVotes = <int, int>{};
      _talking = true;
      _shown.clear();
    });
    _playLines(lines, () {
      setState(() {
        _talking = false;
        _speakingId = null;
      });
      if (!_m.humanAlive) _after(800, _startFinal);
    });
  }

  void _startFinal() {
    final bool canVote = _m.humanAlive && _defendants.any((int d) => d != MafiaMatch.humanId);
    if (canVote) {
      setState(() {
        _stage = _Stage.finalVote;
        _selected = null;
      });
    } else {
      _runTally(final_: true, humanVote: null);
    }
  }

  void _afterVerdict() {
    if (_m.isOver) {
      _toOver();
      return;
    }
    if (_final?.eliminated == MafiaMatch.humanId && !_spectating) {
      _goSelfOut(_endDay);
      return;
    }
    _endDay();
  }

  void _endDay() {
    if (_m.isOver) {
      _toOver();
      return;
    }
    _m.startNight();
    _beginNight();
  }

  void _skipToEnd() {
    _m.autoPlayToEnd();
    _toOver();
  }

  void _toOver() {
    setState(() {
      _stage = _Stage.over;
      _talking = false;
      _speakingId = null;
    });
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    final MafiaTeam w = _e.winner ?? MafiaTeam.town;
    final MafiaTeam mine = _m.humanRole.team;
    final int mineAlive = _e.players.where((MafiaPlayer p) => p.alive && p.role.team == mine).length;
    final int otherAlive = _e.players.where((MafiaPlayer p) => p.alive && p.role.team != mine).length;
    _l.onFinish(GameResult(
      outcome: _m.humanWon ? GameOutcome.win : GameOutcome.loss,
      score: mineAlive,
      opponentScore: otherAlive,
      summaryFa: '${teamLabel(w, true)} در روز ${_e.day} پیروز شد. نقش تو: ${_m.humanRole.labelFa}.',
      summaryEn: '${teamLabel(w, false)} won on day ${_e.day}. Your role: ${_m.humanRole.labelEn}.',
    ));
  }

  // ----------------------------------------------------------- quick chat
  List<int> _othersAlive() => _e.aliveIds.where((int i) => i != MafiaMatch.humanId).toList();

  Future<void> _qcAccuse() async {
    final int? t = await pickPlayer(context,
        title: _t('به چه کسی مشکوکی؟', 'Who do you suspect?'),
        options: _othersAlive(),
        nameOf: _name,
        hueOf: _hue,
        emblemOf: _emblem);
    if (t == null || !mounted) return;
    _humanSay(SpeechAct(speaker: MafiaMatch.humanId, type: SpeechType.accuse, target: t, strength: 0.8));
  }

  Future<void> _qcDefend() async {
    final int? t = await pickPlayer(context,
        title: _t('از چه کسی دفاع می‌کنی؟', 'Who do you defend?'),
        options: _othersAlive(),
        nameOf: _name,
        hueOf: _hue,
        emblemOf: _emblem);
    if (t == null || !mounted) return;
    _humanSay(SpeechAct(speaker: MafiaMatch.humanId, type: SpeechType.defend, target: t));
  }

  List<MafiaRole> _claimableRoles() {
    final List<MafiaRole> r = <MafiaRole>[MafiaRole.citizen, MafiaRole.detective, MafiaRole.doctor];
    if (_e.holderOf(MafiaRole.sniper) != null) r.add(MafiaRole.sniper);
    return r;
  }

  Future<void> _qcClaim({bool react = true}) async {
    final MafiaRole? r = await pickRole(context,
        title: _t('چه نقشی را اعلام می‌کنی؟ (می‌توانی بلوف بزنی)', 'Which role do you claim? (bluffing allowed)'),
        isFa: _fa,
        roles: _claimableRoles());
    if (r == null || !mounted) return;
    _humanSay(SpeechAct(speaker: MafiaMatch.humanId, type: SpeechType.claimRole, role: r), react: react);
  }

  Future<void> _qcReport() async {
    final int? t = await pickPlayer(context,
        title: _t('نتیجه‌ی استعلام چه کسی؟', 'Investigation result for whom?'),
        options: _othersAlive(),
        nameOf: _name,
        hueOf: _hue,
        emblemOf: _emblem);
    if (t == null || !mounted) return;
    final bool? mafia = await pickBool(context,
        title: _t('نتیجه‌ی ${_name(t)}', 'Result for ${_name(t)}'),
        yes: _t('مافیا', 'Mafia'),
        no: _t('بی‌گناه', 'Innocent'));
    if (mafia == null || !mounted) return;
    _humanSay(SpeechAct(speaker: MafiaMatch.humanId, type: SpeechType.reportCheck, target: t, checkMafia: mafia));
  }

  void _showMyRole() {
    final List<int> mates = _m.humanTeammates();
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          RoleCard(role: _m.humanRole, flipped: true, isFa: _fa, animate: false, width: 230),
          const SizedBox(height: 10),
          if (mates.isNotEmpty) _mateLine(mates),
          if (_m.humanRole == MafiaRole.detective && _e.detectiveResults.isNotEmpty)
            MafiaPanel(
              accent: NxColors.electricBlue,
              child: Column(children: <Widget>[
                for (final MapEntry<int, bool> r in _e.detectiveResults.entries)
                  Text('${_name(r.key)}: ${r.value ? _t('مافیا', 'MAFIA') : _t('بی‌گناه', 'innocent')}',
                      style: TextStyle(color: r.value ? MafiaStyle.blood : NxColors.turquoise, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _mateLine(List<int> mates) {
    return MafiaPanel(
      accent: MafiaStyle.blood,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        '${_t('هم‌تیمی‌ها', 'Partners')}: ${mates.map((int i) => '${_name(i)} (${_fa ? _e.player(i).role.labelFa : _e.player(i).role.labelEn})').join(_fa ? '، ' : ', ')}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ----------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final bool night = _stage == _Stage.reveal ||
        _stage == _Stage.nightIntro ||
        _stage == _Stage.nightAction ||
        _stage == _Stage.nightWait;
    return MoonlitBackground(
      night: night,
      animate: _fx,
      child: SafeArea(
        child: _stage == _Stage.reveal ? _revealScreen() : (_stage == _Stage.over ? _overScreen() : _tableScreen()),
      ),
    );
  }

  Widget _revealScreen() {
    final List<int> mates = _m.humanTeammates();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(_t('ایستگاه مهتاب · ${_e.playerCount} مسافر', 'Moonlit Station · ${_e.playerCount} crew'),
              style: const TextStyle(color: NxColors.textDim, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_t('نقش مخفی تو', 'Your secret role'),
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          RoleCard(
            role: _m.humanRole,
            flipped: _flipped,
            isFa: _fa,
            animate: _fx,
            onTap: () {
              setState(() => _flipped = true);
              _haptic();
            },
          ),
          const SizedBox(height: 16),
          AnimatedOpacity(
            opacity: _flipped ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: Column(children: <Widget>[
              if (mates.isNotEmpty) _mateLine(mates),
              const SizedBox(height: 10),
              Text(
                _t('${MafiaEngine.mafiaCountFor(_e.playerCount)} مافیا بین شما هستند.',
                    '${MafiaEngine.mafiaCountFor(_e.playerCount)} Mafia hide among you.'),
                style: const TextStyle(color: NxColors.textDim),
              ),
              const SizedBox(height: 14),
              GlowButton(
                label: _t('شروع شب اول', 'Begin the first night'),
                icon: Icons.nightlight_round,
                color: NxColors.violet,
                onTap: _flipped ? _beginNight : null,
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  List<SeatInfo> _seats() {
    final List<int> nightOpts = _stage == _Stage.nightAction ? _m.humanNightOptions() : const <int>[];
    final List<SeatInfo> out = <SeatInfo>[];
    for (final MafiaPlayer p in _e.players) {
      bool selectable = false;
      if (_stage == _Stage.nightAction) selectable = nightOpts.contains(p.id);
      if (_stage == _Stage.nominationVote) selectable = _e.legalVoteTargets(MafiaMatch.humanId).contains(p.id);
      if (_stage == _Stage.finalVote) selectable = _defendants.contains(p.id) && p.id != MafiaMatch.humanId;
      final bool trial = _defendants.contains(p.id) &&
          (_stage == _Stage.defense || _stage == _Stage.finalVote || (_stage == _Stage.tally && _tallyFinal));
      out.add(SeatInfo(
        id: p.id,
        name: p.name,
        hue: _hue(p.id),
        emblem: _emblem(p.id),
        alive: p.alive,
        isYou: p.id == MafiaMatch.humanId,
        role: _e.visibleRole(MafiaMatch.humanId, p.id),
        votes: _liveVotes[p.id] ?? 0,
        selectable: selectable,
        selected: _selected == p.id,
        speaking: _speakingId == p.id,
        defendant: trial,
        suggested: _stage == _Stage.nightAction && _suggestion == p.id,
      ));
    }
    return out;
  }

  Widget _tableScreen() {
    final bool night = _e.isNight;
    return Column(children: <Widget>[
      SizedBox(
        height: 56,
        child: Row(children: <Widget>[
          const SizedBox(width: 60),
          NxPill(
            label: night ? _t('شب ${_e.day}', 'Night ${_e.day}') : _t('روز ${_e.day}', 'Day ${_e.day}'),
            icon: night ? Icons.nightlight_round : Icons.wb_sunny,
            color: night ? NxColors.violet : NxColors.gold,
          ),
          const SizedBox(width: 8),
          NxPill(label: '${_e.aliveCount}/${_e.playerCount}', icon: Icons.people_alt, color: NxColors.turquoise),
          const Spacer(),
          IconButton(
            tooltip: _t('نقش من', 'My role'),
            onPressed: _showMyRole,
            icon: Icon(MafiaStyle.roleIcon(_m.humanRole), color: MafiaStyle.roleColor(_m.humanRole)),
          ),
          IconButton(
            tooltip: _t('گزارش', 'Log'),
            onPressed: () => showMafiaLog(context, _e.logFor(MafiaMatch.humanId), _fa),
            icon: const Icon(Icons.receipt_long, color: NxColors.iceWhite),
          ),
          const SizedBox(width: 4),
        ]),
      ),
      Expanded(
        flex: 11,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SeatRing(
            seats: _seats(),
            isFa: _fa,
            center: _centerHolo(),
            onTap: (int id) {
              setState(() => _selected = id);
              if (_l.soundOn) HapticFeedback.selectionClick();
            },
          ),
        ),
      ),
      Expanded(
        flex: 10,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: MafiaPanel(
            accent: _e.isNight ? NxColors.violet : NxColors.gold,
            child: AnimatedSwitcher(
              duration: _fx ? const Duration(milliseconds: 350) : Duration.zero,
              child: KeyedSubtree(key: ValueKey<_Stage>(_stage), child: _panel()),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _centerHolo() {
    final bool night = _e.isNight;
    return FittedBox(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(night ? Icons.nightlight_round : Icons.wb_sunny,
            color: night ? MafiaStyle.moon : NxColors.gold,
            size: 30,
            shadows: <Shadow>[Shadow(color: night ? NxColors.violet : NxColors.gold, blurRadius: 18)]),
        const SizedBox(height: 4),
        Text('${_t('مافیا', 'Mafia')} ${_e.config.revealRoleOnDeath ? _e.mafiaAlive : '?'} · ${_t('شهر', 'Town')} ${_e.config.revealRoleOnDeath ? _e.townAlive : '?'}',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _panel() {
    switch (_stage) {
      case _Stage.reveal:
      case _Stage.over:
        return const SizedBox.shrink();
      case _Stage.nightIntro:
        return Center(
          child: PhaseBanner(
            title: _t('شب ${_e.day}', 'NIGHT ${_e.day}'),
            subtitle: _t('همه چشم‌ها را می‌بندند...', 'Everyone closes their eyes...'),
            icon: Icons.nightlight_round,
            color: NxColors.violet,
            animate: _fx,
          ),
        );
      case _Stage.nightWait:
        return Center(
          child: PhaseBanner(
            title: _t('ایستگاه در خواب است', 'The station sleeps'),
            subtitle: _m.humanAlive
                ? _t('نقش‌های شب در حال انجام کارشان هستند.', 'The night roles are at work.')
                : _t('تو تماشاگری.', 'You are spectating.'),
            icon: Icons.bedtime,
            color: NxColors.electricBlue,
            animate: _fx,
          ),
        );
      case _Stage.nightAction:
        return _nightActionPanel();
      case _Stage.dawn:
        return _dawnPanel();
      case _Stage.selfOut:
        return _selfOutPanel();
      case _Stage.discussion:
        return _discussionPanel();
      case _Stage.nominationVote:
        return _votePanel(final_: false);
      case _Stage.finalVote:
        return _votePanel(final_: true);
      case _Stage.tally:
        return _tallyPanel();
      case _Stage.defense:
        return _defensePanel();
      case _Stage.verdict:
        return _verdictPanel();
    }
  }

  Widget _title(String s, {Color color = Colors.white}) => Text(s,
      textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900));

  Widget _nightActionPanel() {
    final MafiaRole r = _m.humanRole;
    String prompt = '';
    switch (r) {
      case MafiaRole.godfather:
      case MafiaRole.mafia:
        prompt = _t('قربانی امشب را انتخاب کن. (علامت قرمز = پیشنهاد هم‌تیمی‌ها)',
            "Choose tonight's target. (red mark = your partners' pick)");
        break;
      case MafiaRole.doctor:
        prompt = _t('چه کسی را امشب نجات می‌دهی؟', 'Who do you protect tonight?');
        break;
      case MafiaRole.detective:
        prompt = _t('هویت چه کسی را استعلام می‌کنی؟', 'Whom do you investigate?');
        break;
      case MafiaRole.sniper:
        prompt = _t('گلوله‌ی تو: شلیک کن یا صبر کن. شلیک به بی‌گناه = حذف خودت.',
            'Your bullet: shoot or hold. Hitting an innocent takes you out.');
        break;
      case MafiaRole.citizen:
        prompt = '';
        break;
    }
    final Color c = MafiaStyle.roleColor(r);
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
      Icon(MafiaStyle.roleIcon(r), color: c, size: 34),
      const SizedBox(height: 6),
      _title(_fa ? r.labelFa : r.labelEn, color: c),
      const SizedBox(height: 6),
      Text(prompt, textAlign: TextAlign.center, style: const TextStyle(color: NxColors.textDim)),
      const SizedBox(height: 8),
      Text(_selected == null ? _t('یک صندلی را لمس کن', 'Tap a seat') : _name(_selected!),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: <Widget>[
        GlowButton(
          label: _t('تأیید', 'Confirm'),
          icon: Icons.check,
          color: c,
          onTap: _selected == null ? null : () => _resolveNight(_selected),
        ),
        if (r == MafiaRole.sniper || r == MafiaRole.doctor || r == MafiaRole.detective)
          GhostButton(
            label: r == MafiaRole.sniper ? _t('شلیک نکن', 'Hold fire') : _t('رد شدن', 'Skip'),
            onTap: () => _resolveNight(null),
          ),
      ]),
    ]);
  }

  Widget _dawnPanel() {
    final NightResult? r = _night;
    final List<Widget> rows = <Widget>[];
    if (r != null) {
      if (r.deaths.isEmpty) {
        rows.add(Text(_t('دیشب کسی کشته نشد.', 'Nobody died last night.'),
            style: const TextStyle(color: NxColors.success, fontWeight: FontWeight.w800)));
      }
      for (final int d in r.deaths) {
        final MafiaPlayer p = _e.player(d);
        final MafiaRole? vr = _e.visibleRole(MafiaMatch.humanId, d);
        String how = '';
        switch (r.causes[d]!) {
          case DeathCause.nightKill:
            how = _t('به دست مافیا', 'by the Mafia');
            break;
          case DeathCause.sniperShot:
            how = _t('با شلیک تک‌تیرانداز', 'by the Sniper');
            break;
          case DeathCause.sniperBackfire:
            how = _t('شلیک اشتباه', 'a misfire');
            break;
          case DeathCause.vote:
            how = '';
            break;
        }
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            CrewAvatar(name: p.name, hue: _hue(d), size: 34, emblem: _emblem(d), dead: true),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${p.name} — $how${vr != null ? ' · ${_fa ? vr.labelFa : vr.labelEn}' : ''}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ));
      }
      if (r.savedSomeone && _e.config.announceSave) {
        rows.add(Text(_t('دکتر جان یک نفر را نجات داد.', 'The Doctor saved someone.'),
            style: const TextStyle(color: NxColors.success)));
      }
      if (_m.humanRole == MafiaRole.detective && r.checkedId != null && r.checkedIsMafia != null) {
        rows.add(const SizedBox(height: 6));
        rows.add(MafiaPanel(
          accent: NxColors.electricBlue,
          padding: const EdgeInsets.all(8),
          child: Text(
            '${_t('استعلام خصوصی', 'Private result')}: ${_name(r.checkedId!)} ${r.checkedIsMafia! ? _t('مافیاست!', 'is MAFIA!') : _t('بی‌گناه است.', 'appears innocent.')}',
            textAlign: TextAlign.center,
            style: TextStyle(color: r.checkedIsMafia! ? MafiaStyle.blood : NxColors.turquoise, fontWeight: FontWeight.w800),
          ),
        ));
      }
      if (_m.humanRole == MafiaRole.doctor && r.savedId != null && _m.humanAlive) {
        rows.add(Text(_t('محافظت تو جان ${_name(r.savedId!)} را نجات داد!', 'Your protection saved ${_name(r.savedId!)}!'),
            style: const TextStyle(color: NxColors.success, fontWeight: FontWeight.w800)));
      }
    }
    return SingleChildScrollView(
      child: Column(children: <Widget>[
        PhaseBanner(
          title: _t('روز ${_e.day}', 'DAY ${_e.day}'),
          subtitle: _t('ایستگاه بیدار می‌شود.', 'The station wakes up.'),
          icon: Icons.wb_sunny,
          color: NxColors.gold,
          animate: _fx,
        ),
        const SizedBox(height: 8),
        ...rows,
        const SizedBox(height: 12),
        GlowButton(label: _t('ادامه', 'Continue'), icon: Icons.arrow_forward, color: NxColors.gold, onTap: _afterDawn),
      ]),
    );
  }

  Widget _selfOutPanel() {
    return SingleChildScrollView(
      child: Column(children: <Widget>[
        const Icon(Icons.dangerous, color: MafiaStyle.blood, size: 40),
        const SizedBox(height: 6),
        _title(_t('تو از بازی حذف شدی', 'You have been eliminated')),
        const SizedBox(height: 6),
        Text(
          _t('نتیجه بر اساس پیروزی تیم تو (${teamLabel(_m.humanRole.team, true)}) حساب می‌شود.',
              "Your result follows your team's (${teamLabel(_m.humanRole.team, false)}) fate."),
          textAlign: TextAlign.center,
          style: const TextStyle(color: NxColors.textDim),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: <Widget>[
          GlowButton(
            label: _t('تماشای ادامه', 'Keep watching'),
            icon: Icons.visibility,
            onTap: () {
              _spectating = true;
              final VoidCallback? n = _afterSelfOut;
              _afterSelfOut = null;
              if (n != null) n();
            },
          ),
          GhostButton(label: _t('پرش به پایان', 'Skip to the end'), icon: Icons.fast_forward, onTap: _skipToEnd),
        ]),
      ]),
    );
  }

  Widget _chatList() {
    if (_shown.isEmpty) {
      return Center(
        child: Text(_talking ? '...' : _t('سکوت در ایستگاه...', 'Silence on the station...'),
            style: const TextStyle(color: NxColors.textDim)),
      );
    }
    return ListView.builder(
      reverse: true,
      itemCount: _shown.length,
      itemBuilder: (BuildContext c, int i) {
        final SpeechLine s = _shown[_shown.length - 1 - i];
        final bool mine = s.speaker == MafiaMatch.humanId;
        Color? accent;
        if (s.act.type == SpeechType.accuse || s.act.type == SpeechType.agree) accent = MafiaStyle.blood;
        if (s.act.type == SpeechType.claimRole || s.act.type == SpeechType.reportCheck) accent = NxColors.gold;
        if (s.act.type == SpeechType.defend) accent = NxColors.success;
        return ChatBubble(
          name: _name(s.speaker),
          text: _fa ? s.fa : s.en,
          hue: _hue(s.speaker),
          emblem: _emblem(s.speaker),
          mine: mine,
          accent: mine ? NxColors.violet : accent,
        );
      },
    );
  }

  Widget _discussionPanel() {
    final bool canTalk = _m.humanAlive && !_talking;
    return Column(children: <Widget>[
      Row(children: <Widget>[
        const Icon(Icons.forum, color: NxColors.gold, size: 18),
        const SizedBox(width: 6),
        Expanded(
            child: Text(_t('بحث روز', 'Day discussion'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
        if (_talking) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      const SizedBox(height: 6),
      Expanded(child: _chatList()),
      const SizedBox(height: 6),
      if (_m.humanAlive)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: <Widget>[
            GhostButton(label: _t('متهم کن', 'Accuse'), icon: Icons.priority_high, color: MafiaStyle.blood, onTap: canTalk ? _qcAccuse : null),
            const SizedBox(width: 6),
            GhostButton(label: _t('دفاع کن', 'Defend'), icon: Icons.shield, color: NxColors.success, onTap: canTalk ? _qcDefend : null),
            const SizedBox(width: 6),
            GhostButton(label: _t('اعلام نقش', 'Claim role'), icon: Icons.badge, color: NxColors.gold, onTap: canTalk ? () => _qcClaim() : null),
            const SizedBox(width: 6),
            GhostButton(label: _t('گزارش استعلام', 'Report check'), icon: Icons.search, color: NxColors.electricBlue, onTap: canTalk ? _qcReport : null),
          ]),
        ),
      if (_m.humanAlive) const SizedBox(height: 8),
      if (_m.humanAlive)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          GhostButton(
            label: _t('ادامه‌ی بحث', 'More talk'),
            icon: Icons.chat,
            onTap: (!_talking && _rounds < 4) ? () => _runBotRound() : null,
          ),
          const SizedBox(width: 10),
          GlowButton(
            label: _t('رأی‌گیری', 'Go to vote'),
            icon: Icons.how_to_vote,
            color: NxColors.gold,
            onTap: _talking ? null : _startNomination,
          ),
        ]),
    ]);
  }

  Widget _votePanel({required bool final_}) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
      Icon(final_ ? Icons.gavel : Icons.how_to_vote, color: NxColors.gold, size: 34),
      const SizedBox(height: 6),
      _title(final_ ? _t('رأی نهایی', 'Final vote') : _t('رأی‌گیری برای دفاع', 'Vote to put on trial')),
      const SizedBox(height: 6),
      Text(
        final_
            ? _t('یکی از متهمان را برای حذف انتخاب کن یا او را ببخش.', 'Pick a defendant to eliminate, or spare them.')
            : _t('چه کسی باید به دفاع برود؟ (حداقل ${_e.nominationThreshold} رأی)',
                'Who should stand trial? (at least ${_e.nominationThreshold} votes)'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: NxColors.textDim),
      ),
      const SizedBox(height: 8),
      Text(_selected == null ? _t('یک صندلی را لمس کن', 'Tap a seat') : _name(_selected!),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: <Widget>[
        GlowButton(
          label: _t('ثبت رأی', 'Cast vote'),
          icon: Icons.check,
          color: NxColors.gold,
          onTap: _selected == null ? null : () => _runTally(final_: final_, humanVote: _selected),
        ),
        GhostButton(
          label: final_ ? _t('ببخش', 'Spare') : _t('رأی ممتنع', 'Abstain'),
          onTap: () => _runTally(final_: final_, humanVote: null),
        ),
      ]),
    ]);
  }

  Widget _tallyPanel() {
    final List<Widget> feed = <Widget>[];
    for (final MapEntry<int, int?> v in _voteFeed.reversed) {
      feed.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: <Widget>[
          CrewAvatar(name: _name(v.key), hue: _hue(v.key), size: 22, emblem: _emblem(v.key)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              v.value == null
                  ? '${_name(v.key)} → ${_tallyFinal ? _t('می‌بخشد', 'spares') : _t('ممتنع', 'abstains')}'
                  : '${_name(v.key)} → ${_name(v.value!)}',
              style: TextStyle(color: v.value == null ? NxColors.textDim : Colors.white, fontSize: 13),
            ),
          ),
        ]),
      ));
    }
    String? result;
    Color resultColor = NxColors.gold;
    if (_tallyDone && !_tallyFinal) {
      result = _defendants.isEmpty
          ? _t('کسی به دفاع نرفت.', 'Nobody goes on trial.')
          : _t('به دفاع می‌روند: ${_defendants.map(_name).join('، ')}', 'On trial: ${_defendants.map(_name).join(', ')}');
    }
    if (_tallyDone && _tallyFinal && _final != null) {
      result = _final!.eliminated == null
          ? _t('رأی کافی نبود؛ کسی حذف نمی‌شود.', 'Not enough votes; nobody is eliminated.')
          : _t('${_name(_final!.eliminated!)} حذف می‌شود!', '${_name(_final!.eliminated!)} is eliminated!');
      if (_final!.eliminated != null) resultColor = MafiaStyle.blood;
    }
    return Column(children: <Widget>[
      _title(_tallyFinal ? _t('شمارش رأی نهایی', 'Final tally') : _t('شمارش آرا', 'Vote tally')),
      const SizedBox(height: 6),
      Expanded(child: ListView(children: feed)),
      if (result != null) ...<Widget>[
        const SizedBox(height: 6),
        Text(result, textAlign: TextAlign.center, style: TextStyle(color: resultColor, fontWeight: FontWeight.w900, fontSize: 15)),
      ],
      if (_tallyDone && !_tallyFinal && _defendants.isEmpty && _m.humanAlive) ...<Widget>[
        const SizedBox(height: 8),
        GlowButton(label: _t('شب فرا می‌رسد', 'Night falls'), icon: Icons.nightlight_round, color: NxColors.violet, onTap: _endDay),
      ],
    ]);
  }

  Widget _defensePanel() {
    final bool onTrial = _defendants.contains(MafiaMatch.humanId) && _m.humanAlive;
    return Column(children: <Widget>[
      Row(children: <Widget>[
        const Icon(Icons.gavel, color: NxColors.gold, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text('${_t('دفاعیه', 'Defense')}: ${_defendants.map(_name).join(_fa ? '، ' : ', ')}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ),
      ]),
      const SizedBox(height: 6),
      Expanded(child: _chatList()),
      const SizedBox(height: 6),
      if (onTrial && !_humanDefended)
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: <Widget>[
          GhostButton(
            label: _t('اعلام نقش', 'Claim role'),
            icon: Icons.badge,
            color: NxColors.gold,
            onTap: _talking
                ? null
                : () async {
                    await _qcClaim(react: false);
                    if (mounted) setState(() => _humanDefended = true);
                  },
          ),
          GhostButton(
            label: _t('دفاع از خودم', 'Defend myself'),
            icon: Icons.shield,
            color: NxColors.success,
            onTap: _talking
                ? null
                : () {
                    _humanSay(const SpeechAct(speaker: MafiaMatch.humanId, type: SpeechType.selfDefense), react: false);
                    setState(() => _humanDefended = true);
                  },
          ),
          GhostButton(
            label: _t('التماس', 'Plea'),
            icon: Icons.volunteer_activism,
            onTap: _talking
                ? null
                : () {
                    _humanSay(const SpeechAct(speaker: MafiaMatch.humanId, type: SpeechType.plea), react: false);
                    setState(() => _humanDefended = true);
                  },
          ),
        ]),
      if (_m.humanAlive) ...<Widget>[
        const SizedBox(height: 8),
        GlowButton(
          label: _t('رأی نهایی', 'Final vote'),
          icon: Icons.gavel,
          color: NxColors.gold,
          onTap: _talking ? null : _startFinal,
        ),
      ],
    ]);
  }

  Widget _verdictPanel() {
    final int? out = _final?.eliminated;
    final List<Widget> children = <Widget>[];
    if (out == null) {
      children.add(PhaseBanner(
        title: _t('بخشیده شد', 'Spared'),
        subtitle: _t('شهر به توافق نرسید.', 'The town could not agree.'),
        icon: Icons.gavel,
        color: NxColors.turquoise,
        animate: _fx,
      ));
    } else {
      final MafiaRole? vr = _e.visibleRole(MafiaMatch.humanId, out);
      children.add(CrewAvatar(name: _name(out), hue: _hue(out), size: 54, emblem: _emblem(out), dead: true));
      children.add(const SizedBox(height: 6));
      children.add(_title(_t('${_name(out)} حذف شد', '${_name(out)} is out'), color: MafiaStyle.blood));
      children.add(const SizedBox(height: 4));
      if (vr != null) {
        children.add(TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: _fx ? 0 : 1, end: 1),
          duration: const Duration(milliseconds: 700),
          builder: (BuildContext c, double v, Widget? child) => Opacity(opacity: v, child: Transform.scale(scale: 0.7 + 0.3 * v, child: child)),
          child: NxPill(label: _fa ? vr.labelFa : vr.labelEn, icon: MafiaStyle.roleIcon(vr), color: MafiaStyle.roleColor(vr)),
        ));
      } else {
        children.add(Text(_t('نقش او مخفی می‌ماند.', 'Their role stays secret.'), style: const TextStyle(color: NxColors.textDim)));
      }
      if (_lastWords != null) {
        children.add(const SizedBox(height: 6));
        children.add(Text('« ${_fa ? _lastWords!.fa : _lastWords!.en} »',
            textAlign: TextAlign.center, style: const TextStyle(color: NxColors.textDim, fontStyle: FontStyle.italic)));
      }
    }
    children.add(const SizedBox(height: 12));
    children.add(GlowButton(
      label: _m.isOver ? _t('پایان بازی', 'Game over') : _t('شب فرا می‌رسد', 'Night falls'),
      icon: _m.isOver ? Icons.flag : Icons.nightlight_round,
      color: _m.isOver ? NxColors.gold : NxColors.violet,
      onTap: _afterVerdict,
    ));
    return SingleChildScrollView(child: Column(children: children));
  }

  Widget _overScreen() {
    final MafiaTeam w = _e.winner ?? MafiaTeam.town;
    final Color c = MafiaStyle.teamColor(w);
    return Column(children: <Widget>[
      const SizedBox(height: 60),
      PhaseBanner(
        title: w == MafiaTeam.town ? _t('شهر پیروز شد', 'TOWN WINS') : _t('مافیا پیروز شد', 'MAFIA WINS'),
        subtitle: _m.humanWon ? _t('تیم تو برنده شد!', 'Your team won!') : _t('تیم تو باخت.', 'Your team lost.'),
        icon: w == MafiaTeam.town ? Icons.wb_sunny : Icons.theater_comedy,
        color: c,
        animate: _fx,
      ),
      const SizedBox(height: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: MafiaPanel(
            accent: c,
            child: ListView(children: <Widget>[
              for (final MafiaPlayer p in _e.players)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: <Widget>[
                    CrewAvatar(name: p.name, hue: _hue(p.id), size: 34, emblem: _emblem(p.id), dead: !p.alive),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(p.id == MafiaMatch.humanId ? '${p.name} ${_t('(تو)', '(you)')}' : p.name,
                          style: TextStyle(color: Colors.white, fontWeight: p.id == MafiaMatch.humanId ? FontWeight.w900 : FontWeight.w600)),
                    ),
                    NxPill(label: _fa ? p.role.labelFa : p.role.labelEn, icon: MafiaStyle.roleIcon(p.role), color: MafiaStyle.roleColor(p.role)),
                  ]),
                ),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          GhostButton(
            label: _t('گزارش کامل', 'Full log'),
            icon: Icons.receipt_long,
            onTap: () => showMafiaLog(context, _e.logFor(MafiaMatch.humanId), _fa),
          ),
          const SizedBox(width: 10),
          GlowButton(label: _t('نتیجه', 'See result'), icon: Icons.emoji_events, color: c, onTap: _finish),
        ]),
      ),
    ]);
  }
}
