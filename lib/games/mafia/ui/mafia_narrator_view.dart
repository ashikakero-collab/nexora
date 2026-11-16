import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/nx_theme.dart';
import '../../core/game_contract.dart';
import '../core/mafia_engine.dart';
import '../core/mafia_models.dart';
import 'mafia_visuals.dart';
import 'mafia_widgets.dart';

enum _NStage { setup, pass, nightIntro, nightStep, detectiveAnswer, dawn, day, nominate, defense, vote, verdict, over }

enum _NightStep { mafia, doctor, detective, sniper }

/// Pass-and-play narrator for 6..12 real players sharing one phone. The phone
/// plays the narrator: it deals secret roles, walks everyone through the night,
/// keeps the day/defense clocks and applies the rules engine for every result.
class MafiaNarratorView extends StatefulWidget {
  const MafiaNarratorView({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<MafiaNarratorView> createState() => _MafiaNarratorViewState();
}

class _MafiaNarratorViewState extends State<MafiaNarratorView> {
  static const int _defenseSeconds = 60;

  // ------------------------------------------------------------- setup state
  int _count = 8;
  bool _useSniper = true;
  bool _revealRole = true;
  int _dayMinutes = 3;
  final List<TextEditingController> _names = <TextEditingController>[];

  // -------------------------------------------------------------- game state
  MafiaEngine? _engine;
  late Random _rng;
  _NStage _stage = _NStage.setup;
  int _passIdx = 0;
  bool _peeking = false;
  bool _peekedOnce = false;

  List<_NightStep> _steps = <_NightStep>[];
  int _stepIdx = 0;
  bool _stepActive = false;
  int? _sel;
  int? _mafiaPick;
  int? _doctorPick;
  int? _detectivePick;
  int? _sniperPick;
  Timer? _fakeTimer;
  NightResult? _night;

  Timer? _clock;
  int _secondsLeft = 0;
  int _secondsTotal = 0;
  bool _paused = false;

  List<int> _defendants = <int>[];
  int _defIdx = 0;
  Map<int, int> _counts = <int, int>{};
  FinalVoteResult? _verdict;
  bool _finished = false;

  GameLaunch get _l => widget.launch;
  bool get _fa => _l.isFa;
  String _t(String fa, String en) => _l.tx(fa, en);
  bool get _fx => _l.fancyEffects && !_l.reducedMotion;
  MafiaEngine get _e => _engine!;

  @override
  void initState() {
    super.initState();
    final int pc = _l.playerCount;
    _count = pc < MafiaEngine.minPlayers ? 8 : pc.clamp(MafiaEngine.minPlayers, MafiaEngine.maxPlayers).toInt();
    for (int i = 0; i < MafiaEngine.maxPlayers; i++) {
      final String def = i == 0 && _l.playerName.trim().isNotEmpty ? _l.playerName.trim() : _defaultName(i);
      _names.add(TextEditingController(text: def));
    }
    _rng = Random(_l.seed ?? DateTime.now().microsecondsSinceEpoch);
  }

  @override
  void dispose() {
    _fakeTimer?.cancel();
    _clock?.cancel();
    for (final TextEditingController c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  String _defaultName(int i) => _t('بازیکن ${i + 1}', 'Player ${i + 1}');
  String _name(int id) => _e.player(id).name;
  double _hue(int id) => (200 + id * 360.0 / max(1, _engine?.playerCount ?? _count)) % 360;
  String _roleLabel(MafiaRole r) => _fa ? r.labelFa : r.labelEn;
  String _join(Iterable<String> xs) => xs.join(_fa ? '، ' : ', ');

  void _haptic() {
    if (_l.soundOn) HapticFeedback.mediumImpact();
  }

  // ===================================================================== flow
  void _startGame() {
    final List<String> names = <String>[];
    for (int i = 0; i < _count; i++) {
      String n = _names[i].text.trim();
      if (n.isEmpty) n = _defaultName(i);
      // Keep names unique so announcements are unambiguous.
      String unique = n;
      int k = 2;
      while (names.contains(unique)) {
        unique = '$n $k';
        k++;
      }
      names.add(unique);
    }
    _engine = MafiaEngine.create(
      names: names,
      config: MafiaConfig(useSniper: _useSniper, revealRoleOnDeath: _revealRole),
      rng: _rng,
    );
    setState(() {
      _stage = _NStage.pass;
      _passIdx = 0;
      _peeking = false;
      _peekedOnce = false;
    });
  }

  void _nextPass() {
    setState(() {
      _peeking = false;
      _peekedOnce = false;
      _passIdx++;
      if (_passIdx >= _e.playerCount) _stage = _NStage.nightIntro;
    });
  }

  void _beginNight() {
    final List<_NightStep> steps = <_NightStep>[_NightStep.mafia];
    if (_e.holderOf(MafiaRole.doctor) != null) steps.add(_NightStep.doctor);
    if (_e.holderOf(MafiaRole.detective) != null) steps.add(_NightStep.detective);
    if (_e.holderOf(MafiaRole.sniper) != null) steps.add(_NightStep.sniper);
    _steps = steps;
    _stepIdx = 0;
    _mafiaPick = null;
    _doctorPick = null;
    _detectivePick = null;
    _sniperPick = null;
    _enterStep();
  }

  List<int> _optionsFor(_NightStep s) {
    switch (s) {
      case _NightStep.mafia:
        return _e.legalMafiaTargets();
      case _NightStep.doctor:
        return _e.legalDoctorTargets();
      case _NightStep.detective:
        return _e.legalDetectiveTargets();
      case _NightStep.sniper:
        return _e.legalSniperTargets();
    }
  }

  void _enterStep() {
    _fakeTimer?.cancel();
    if (_stepIdx >= _steps.length) {
      _resolveNight();
      return;
    }
    final _NightStep s = _steps[_stepIdx];
    final bool active = _optionsFor(s).isNotEmpty;
    setState(() {
      _stage = _NStage.nightStep;
      _stepActive = active;
      _sel = null;
    });
    if (!active) {
      // The role is dead or out of ammo: the narrator still calls it and waits
      // a natural-looking moment so nobody can tell.
      final int ms = 4500 + _rng.nextInt(3500);
      _fakeTimer = Timer(Duration(milliseconds: ms), () {
        if (!mounted) return;
        _advanceStep();
      });
    }
  }

  void _advanceStep() {
    _stepIdx++;
    _enterStep();
  }

  void _confirmStep(int? choice) {
    final _NightStep s = _steps[_stepIdx];
    _haptic();
    switch (s) {
      case _NightStep.mafia:
        _mafiaPick = choice;
        break;
      case _NightStep.doctor:
        _doctorPick = choice;
        break;
      case _NightStep.detective:
        _detectivePick = choice;
        break;
      case _NightStep.sniper:
        _sniperPick = choice;
        break;
    }
    if (s == _NightStep.detective && choice != null) {
      setState(() => _stage = _NStage.detectiveAnswer);
      return;
    }
    _advanceStep();
  }

  void _resolveNight() {
    final NightResult r = _e.resolveNight(NightActions(
      mafiaTarget: _mafiaPick,
      doctorSave: _doctorPick,
      detectiveCheck: _detectivePick,
      sniperTarget: _sniperPick,
    ));
    _haptic();
    setState(() {
      _night = r;
      _stage = _NStage.dawn;
    });
  }

  void _afterDawn() {
    if (_e.isOver) {
      _toOver();
      return;
    }
    setState(() {
      _stage = _NStage.day;
      _defendants = <int>[];
    });
    _startClock(_dayMinutes * 60);
  }

  void _startClock(int seconds) {
    _clock?.cancel();
    _secondsLeft = seconds;
    _secondsTotal = seconds;
    _paused = false;
    _clock = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted || _paused) return;
      if (_secondsLeft <= 0) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft == 0 && _l.soundOn) HapticFeedback.heavyImpact();
    });
  }

  void _stopClock() {
    _clock?.cancel();
    _clock = null;
  }

  void _toNominate() {
    _stopClock();
    setState(() {
      _stage = _NStage.nominate;
      _defendants = <int>[];
    });
  }

  void _toggleDefendant(int id) {
    if (!_e.player(id).alive) return;
    setState(() {
      if (_defendants.contains(id)) {
        _defendants.remove(id);
      } else if (_defendants.length < 3) {
        _defendants.add(id);
      }
    });
    if (_l.soundOn) HapticFeedback.selectionClick();
  }

  void _startDefense() {
    if (_defendants.isEmpty) return;
    _e.addLog(LogKind.vote, 'به دفاع رفتند: ${_defendants.map(_name).join('، ')}',
        'On trial: ${_defendants.map(_name).join(', ')}');
    setState(() {
      _stage = _NStage.defense;
      _defIdx = 0;
    });
    _startClock(_defenseSeconds);
  }

  void _nextDefense() {
    if (_defIdx + 1 < _defendants.length) {
      setState(() => _defIdx++);
      _startClock(_defenseSeconds);
      return;
    }
    _stopClock();
    setState(() {
      _stage = _NStage.vote;
      _counts = <int, int>{for (final int d in _defendants) d: 0};
    });
  }

  int get _votesUsed => _counts.values.fold<int>(0, (int a, int b) => a + b);

  void _setCount(int id, int delta) {
    final int cur = _counts[id] ?? 0;
    final int next = cur + delta;
    if (next < 0) return;
    if (delta > 0 && _votesUsed >= _e.aliveCount) return;
    setState(() => _counts[id] = next);
  }

  void _resolveVote() {
    final FinalVoteResult r = _e.resolveFinalCounts(_counts, _defendants);
    _haptic();
    setState(() {
      _verdict = r;
      _stage = _NStage.verdict;
    });
  }

  void _afterVerdict() {
    if (_e.isOver) {
      _toOver();
      return;
    }
    _endDay();
  }

  void _endDay() {
    _stopClock();
    _e.startNight();
    setState(() {
      _stage = _NStage.nightIntro;
      _defendants = <int>[];
      _verdict = null;
    });
  }

  void _toOver() {
    _stopClock();
    _fakeTimer?.cancel();
    setState(() => _stage = _NStage.over);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    final MafiaTeam w = _e.winner ?? MafiaTeam.town;
    final List<String> winners =
        _e.players.where((MafiaPlayer p) => p.role.team == w).map((MafiaPlayer p) => p.name).toList();
    _l.onFinish(GameResult(
      outcome: GameOutcome.draw,
      score: _e.players.where((MafiaPlayer p) => p.alive && p.role.team == w).length,
      opponentScore: _e.players.where((MafiaPlayer p) => p.alive && p.role.team != w).length,
      summaryFa: 'تیم ${teamLabel(w, true)} در روز ${_e.day} پیروز شد: ${winners.join('، ')}.',
      summaryEn: 'Team ${teamLabel(w, false)} won on day ${_e.day}: ${winners.join(', ')}.',
    ));
  }

  // ==================================================================== build
  @override
  Widget build(BuildContext context) {
    final bool night = _stage == _NStage.setup ||
        _stage == _NStage.pass ||
        _stage == _NStage.nightIntro ||
        _stage == _NStage.nightStep ||
        _stage == _NStage.detectiveAnswer;
    Widget body;
    switch (_stage) {
      case _NStage.setup:
        body = _setupScreen();
        break;
      case _NStage.pass:
        body = _passScreen();
        break;
      case _NStage.nightIntro:
        body = _nightIntroScreen();
        break;
      case _NStage.nightStep:
        body = _nightStepScreen();
        break;
      case _NStage.detectiveAnswer:
        body = _detectiveAnswerScreen();
        break;
      case _NStage.dawn:
        body = _dawnScreen();
        break;
      case _NStage.day:
      case _NStage.nominate:
      case _NStage.defense:
      case _NStage.vote:
      case _NStage.verdict:
        body = _tableScreen();
        break;
      case _NStage.over:
        body = _overScreen();
        break;
    }
    return MoonlitBackground(
      night: night,
      animate: _fx,
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: _fx ? 350 : 0),
          child: KeyedSubtree(key: ValueKey<String>('${_stage.name}-$_passIdx-$_stepIdx'), child: body),
        ),
      ),
    );
  }

  TextStyle get _h1 => const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900);
  TextStyle get _dim => const TextStyle(color: NxColors.textDim, fontSize: 13);

  Widget _scroll(Widget child) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 64, 18, 24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: child),
      ),
    );
  }

  // ------------------------------------------------------------------ setup
  Widget _setupScreen() {
    final List<MafiaRole> roles = MafiaEngine.distributeRoles(_count, useSniper: _useSniper);
    final Map<MafiaRole, int> roleCount = <MafiaRole, int>{};
    for (final MafiaRole r in roles) {
      roleCount[r] = (roleCount[r] ?? 0) + 1;
    }
    return _scroll(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      PhaseBanner(
        title: _t('حالت راوی', 'Narrator mode'),
        subtitle: _t('یک گوشی، چند دوست، نقش‌های مخفی', 'One phone, friends around a table, secret roles'),
        icon: Icons.record_voice_over,
        color: MafiaStyle.blood,
        animate: _fx,
      ),
      const SizedBox(height: 16),
      MafiaPanel(
        accent: NxColors.electricBlue,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Text(_t('تعداد بازیکنان', 'Players'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            _stepper(_count, () => setState(() => _count = max(MafiaEngine.minPlayers, _count - 1)),
                () => setState(() => _count = min(MafiaEngine.maxPlayers, _count + 1))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            for (final MapEntry<MafiaRole, int> e in roleCount.entries)
              _roleChip(e.key, suffix: e.value > 1 ? ' ×${e.value}' : ''),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      MafiaPanel(
        accent: NxColors.violet,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text(_t('نام بازیکنان', 'Player names'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (int i = 0; i < _count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: <Widget>[
                CrewAvatar(name: _names[i].text, hue: (200 + i * 360.0 / _count) % 360, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _names[i],
                    maxLength: 16,
                    onChanged: (String _) => setState(() {}),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: _defaultName(i),
                      hintStyle: const TextStyle(color: NxColors.textDim),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      MafiaPanel(
        accent: NxColors.gold,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _useSniper,
            activeColor: NxColors.gold,
            onChanged: (bool v) => setState(() => _useSniper = v),
            title: Text(_t('تک‌تیرانداز', 'Sniper'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            subtitle: Text(_t('از ۷ بازیکن به بالا', 'From 7 players up'), style: _dim),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _revealRole,
            activeColor: NxColors.gold,
            onChanged: (bool v) => setState(() => _revealRole = v),
            title: Text(_t('افشای نقش هنگام حذف', 'Reveal role on elimination'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          Row(children: <Widget>[
            Expanded(
              child: Text(_t('زمان بحث روز (دقیقه)', 'Day discussion (minutes)'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            _stepper(_dayMinutes, () => setState(() => _dayMinutes = max(1, _dayMinutes - 1)),
                () => setState(() => _dayMinutes = min(15, _dayMinutes + 1))),
          ]),
        ]),
      ),
      const SizedBox(height: 18),
      Center(
        child: GlowButton(
          label: _t('پخش نقش‌ها', 'Deal the roles'),
          icon: Icons.style,
          color: MafiaStyle.blood,
          onTap: _startGame,
        ),
      ),
    ]));
  }

  Widget _stepper(int value, VoidCallback onMinus, VoidCallback onPlus) {
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      IconButton(onPressed: onMinus, icon: const Icon(Icons.remove_circle_outline, color: NxColors.iceWhite)),
      SizedBox(
        width: 30,
        child: Text('$value',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
      ),
      IconButton(onPressed: onPlus, icon: const Icon(Icons.add_circle_outline, color: NxColors.iceWhite)),
    ]);
  }

  Widget _roleChip(MafiaRole r, {String suffix = ''}) {
    final Color c = MafiaStyle.roleColor(r);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(MafiaStyle.roleIcon(r), size: 14, color: c),
        const SizedBox(width: 4),
        Text('${_roleLabel(r)}$suffix', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
    );
  }

  // ------------------------------------------------------------ role reveal
  Widget _passScreen() {
    final MafiaPlayer p = _e.player(_passIdx);
    final List<int> mates = p.isMafia ? _e.mafiaIds().where((int i) => i != p.id).toList() : <int>[];
    return _scroll(Column(children: <Widget>[
      Text('${_passIdx + 1} / ${_e.playerCount}', style: _dim),
      const SizedBox(height: 8),
      CrewAvatar(name: p.name, hue: _hue(p.id), size: 64, glow: NxColors.violet),
      const SizedBox(height: 10),
      Text(_t('گوشی را به ${p.name} بده', 'Pass the phone to ${p.name}'), textAlign: TextAlign.center, style: _h1),
      const SizedBox(height: 6),
      Text(_t('فقط خودت نگاه کن. برای دیدن نقش، کارت را نگه دار.', 'Only you look. Press and hold the card to see your role.'),
          textAlign: TextAlign.center, style: _dim),
      const SizedBox(height: 18),
      Listener(
        onPointerDown: (PointerDownEvent _) {
          setState(() {
            _peeking = true;
            _peekedOnce = true;
          });
          if (_l.soundOn) HapticFeedback.selectionClick();
        },
        onPointerUp: (PointerUpEvent _) => setState(() => _peeking = false),
        onPointerCancel: (PointerCancelEvent _) => setState(() => _peeking = false),
        child: RoleCard(role: p.role, flipped: _peeking, isFa: _fa, animate: _fx, width: 220),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 48,
        child: AnimatedOpacity(
          opacity: _peeking && mates.isNotEmpty ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Text(
            '${_t('هم‌تیمی‌ها', 'Partners')}: ${_join(mates.map((int i) => '${_name(i)} (${_roleLabel(_e.player(i).role)})'))}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: MafiaStyle.blood, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      const SizedBox(height: 8),
      GlowButton(
        label: _passIdx + 1 < _e.playerCount ? _t('پنهان کن و رد کن', 'Hide & pass on') : _t('همه نقششان را دیدند', 'Everyone has seen their role'),
        icon: Icons.visibility_off,
        color: NxColors.violet,
        onTap: _peekedOnce && !_peeking ? _nextPass : null,
      ),
    ]));
  }

  // ------------------------------------------------------------------ night
  Widget _nightIntroScreen() {
    return _scroll(Column(children: <Widget>[
      PhaseBanner(
        title: _t('شب ${_e.day}', 'Night ${_e.day}'),
        subtitle: _t('گوشی را وسط میز بگذارید. همه چشم‌ها را ببندند.', 'Put the phone in the middle. Everyone, close your eyes.'),
        icon: Icons.nightlight_round,
        color: NxColors.violet,
        animate: _fx,
      ),
      const SizedBox(height: 22),
      GlowButton(label: _t('شروع شب', 'Begin the night'), icon: Icons.play_arrow, color: NxColors.violet, onTap: _beginNight),
    ]));
  }

  String _stepTitle(_NightStep s) {
    switch (s) {
      case _NightStep.mafia:
        return _t('مافیا، بیدار شوید', 'Mafia, wake up');
      case _NightStep.doctor:
        return _t('دکتر، بیدار شو', 'Doctor, wake up');
      case _NightStep.detective:
        return _t('کارآگاه، بیدار شو', 'Detective, wake up');
      case _NightStep.sniper:
        return _t('تک‌تیرانداز، بیدار شو', 'Sniper, wake up');
    }
  }

  String _stepPrompt(_NightStep s) {
    switch (s) {
      case _NightStep.mafia:
        return _t('با اشاره توافق کنید و قربانی امشب را انتخاب کنید.', 'Agree silently and choose tonight\'s victim.');
      case _NightStep.doctor:
        return _t('چه کسی را امشب نجات می‌دهی؟', 'Who do you protect tonight?');
      case _NightStep.detective:
        return _t('هویت چه کسی را استعلام می‌کنی؟', 'Whom do you investigate?');
      case _NightStep.sniper:
        return _t('شلیک می‌کنی؟ اشتباه کنی، خودت حذف می‌شوی.', 'Will you fire? Hit an innocent and you are out.');
    }
  }

  MafiaRole _stepRole(_NightStep s) {
    switch (s) {
      case _NightStep.mafia:
        return MafiaRole.godfather;
      case _NightStep.doctor:
        return MafiaRole.doctor;
      case _NightStep.detective:
        return MafiaRole.detective;
      case _NightStep.sniper:
        return MafiaRole.sniper;
    }
  }

  Widget _nightStepScreen() {
    final _NightStep s = _steps[_stepIdx];
    final MafiaRole role = _stepRole(s);
    final Color c = MafiaStyle.roleColor(role);
    final Widget head = PhaseBanner(
      title: _stepTitle(s),
      subtitle: _stepActive ? _stepPrompt(s) : _t('…', '…'),
      icon: MafiaStyle.roleIcon(role),
      color: c,
      animate: _fx,
    );
    if (!_stepActive) {
      return _scroll(Column(children: <Widget>[
        head,
        const SizedBox(height: 26),
        SizedBox(width: 44, height: 44, child: CircularProgressIndicator(color: c, strokeWidth: 3)),
        const SizedBox(height: 14),
        Text(_t('صبر کنید…', 'Waiting…'), style: _dim),
      ]));
    }
    final List<int> options = _optionsFor(s);
    final bool canSkip = s == _NightStep.sniper;
    return _scroll(Column(children: <Widget>[
      head,
      const SizedBox(height: 16),
      MafiaPanel(accent: c, child: _targetGrid(options, c)),
      const SizedBox(height: 14),
      Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: <Widget>[
        GlowButton(
          label: _t('تأیید و خواب', 'Confirm & sleep'),
          icon: Icons.check,
          color: c,
          onTap: _sel == null ? null : () => _confirmStep(_sel),
        ),
        if (canSkip)
          GhostButton(label: _t('امشب شلیک نمی‌کنم', 'Hold fire tonight'), icon: Icons.block, onTap: () => _confirmStep(null)),
      ]),
    ]));
  }

  Widget _targetGrid(List<int> options, Color accent) {
    return Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: <Widget>[
      for (final int id in options)
        GestureDetector(
          onTap: () {
            setState(() => _sel = id);
            if (_l.soundOn) HapticFeedback.selectionClick();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 84,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: _sel == id ? accent.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: _sel == id ? accent : Colors.white24, width: _sel == id ? 2 : 1),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              CrewAvatar(name: _name(id), hue: _hue(id), size: 40, glow: _sel == id ? accent : null),
              const SizedBox(height: 4),
              Text(_name(id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
    ]);
  }

  Widget _detectiveAnswerScreen() {
    final int target = _detectivePick!;
    final bool mafia = _e.player(target).role.appearsMafiaToDetective;
    final Color c = mafia ? MafiaStyle.blood : NxColors.turquoise;
    return _scroll(Column(children: <Widget>[
      CrewAvatar(name: _name(target), hue: _hue(target), size: 72, glow: c),
      const SizedBox(height: 12),
      Text(_name(target), style: _h1),
      const SizedBox(height: 10),
      Icon(mafia ? Icons.thumb_down_alt : Icons.thumb_up_alt, color: c, size: 64, shadows: <Shadow>[Shadow(color: c, blurRadius: 20)]),
      const SizedBox(height: 8),
      Text(mafia ? _t('مافیا است', 'is MAFIA') : _t('بی‌گناه است', 'is innocent'),
          style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 22),
      GlowButton(label: _t('پنهان کن و بخواب', 'Hide & sleep'), icon: Icons.visibility_off, color: NxColors.violet, onTap: _advanceStep),
    ]));
  }

  // ------------------------------------------------------------------- dawn
  String _deathLine(int id, DeathCause cause) {
    final MafiaPlayer p = _e.player(id);
    final String role = p.roleRevealed ? ' (${_roleLabel(p.role)})' : '';
    switch (cause) {
      case DeathCause.nightKill:
        return _t('${p.name}$role دیشب کشته شد.', '${p.name}$role was killed last night.');
      case DeathCause.sniperShot:
        return _t('${p.name}$role با شلیک تک‌تیرانداز از پا درآمد.', '${p.name}$role was taken down by the Sniper.');
      case DeathCause.sniperBackfire:
        return _t('${p.name}$role به یک بی‌گناه شلیک کرد و حذف شد.', '${p.name}$role shot an innocent and is out.');
      case DeathCause.vote:
        return _t('${p.name}$role با رأی شهر حذف شد.', '${p.name}$role was voted out.');
    }
  }

  Widget _dawnScreen() {
    final NightResult? r = _night;
    final List<int> deaths = r?.deaths ?? <int>[];
    return _scroll(Column(children: <Widget>[
      PhaseBanner(
        title: _t('صبح روز ${_e.day}', 'Dawn of day ${_e.day}'),
        subtitle: _t('همه چشم‌ها را باز کنند.', 'Everyone, open your eyes.'),
        icon: Icons.wb_twilight,
        color: NxColors.gold,
        animate: _fx,
      ),
      const SizedBox(height: 18),
      MafiaPanel(
        accent: deaths.isEmpty ? NxColors.turquoise : MafiaStyle.blood,
        child: Column(children: <Widget>[
          if (deaths.isEmpty)
            Text(_t('دیشب کسی کشته نشد.', 'Nobody died last night.'),
                textAlign: TextAlign.center, style: const TextStyle(color: NxColors.turquoise, fontSize: 17, fontWeight: FontWeight.w800)),
          for (final int d in deaths)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: <Widget>[
                CrewAvatar(name: _name(d), hue: _hue(d), size: 40, dead: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_deathLine(d, r!.causes[d] ?? DeathCause.nightKill),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          if (r != null && r.savedSomeone && _e.config.announceSave) ...<Widget>[
            const SizedBox(height: 8),
            Text(_t('دکتر دیشب جان یک نفر را نجات داد.', 'The Doctor saved someone last night.'),
                textAlign: TextAlign.center, style: const TextStyle(color: NxColors.success, fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
      const SizedBox(height: 18),
      GlowButton(
        label: _e.isOver ? _t('پایان بازی', 'Game over') : _t('شروع بحث روز', 'Start the day talk'),
        icon: _e.isOver ? Icons.flag : Icons.wb_sunny,
        color: NxColors.gold,
        onTap: _afterDawn,
      ),
    ]));
  }

  // -------------------------------------------------------------- day table
  List<SeatInfo> _seats() {
    final List<SeatInfo> out = <SeatInfo>[];
    for (final MafiaPlayer p in _e.players) {
      final bool onTrial = _defendants.contains(p.id);
      out.add(SeatInfo(
        id: p.id,
        name: p.name,
        hue: _hue(p.id),
        alive: p.alive,
        role: p.roleRevealed ? p.role : null,
        votes: _stage == _NStage.vote || _stage == _NStage.verdict ? (_counts[p.id] ?? 0) : 0,
        selectable: _stage == _NStage.nominate && p.alive,
        selected: _stage == _NStage.nominate && onTrial,
        speaking: _stage == _NStage.defense && _defIdx < _defendants.length && _defendants[_defIdx] == p.id,
        defendant: onTrial && _stage != _NStage.nominate,
      ));
    }
    return out;
  }

  Widget _tableScreen() {
    return Column(children: <Widget>[
      SizedBox(
        height: 56,
        child: Row(children: <Widget>[
          const SizedBox(width: 60),
          NxPillLite(label: _t('روز ${_e.day}', 'Day ${_e.day}'), icon: Icons.wb_sunny, color: NxColors.gold),
          const SizedBox(width: 8),
          NxPillLite(label: '${_e.aliveCount}/${_e.playerCount}', icon: Icons.people_alt, color: NxColors.turquoise),
          const Spacer(),
          IconButton(
            tooltip: _t('گزارش', 'Log'),
            onPressed: () => showMafiaLog(context, _e.log.where((GameLogEntry g) => g.visibleTo == null).toList(), _fa),
            icon: const Icon(Icons.receipt_long, color: NxColors.iceWhite),
          ),
          const SizedBox(width: 4),
        ]),
      ),
      Expanded(
        flex: 10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SeatRing(
            seats: _seats(),
            isFa: _fa,
            center: _centerInfo(),
            onTap: _stage == _NStage.nominate ? _toggleDefendant : null,
          ),
        ),
      ),
      Expanded(
        flex: 9,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: MafiaPanel(
            accent: NxColors.gold,
            child: SingleChildScrollView(child: _controls()),
          ),
        ),
      ),
    ]);
  }

  Widget _centerInfo() {
    final int mafiaLeft = _e.mafiaAlive;
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      const Icon(Icons.wb_sunny, color: NxColors.gold, size: 26),
      const SizedBox(height: 4),
      Text(_t('${_e.aliveCount} زنده', '${_e.aliveCount} alive'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      if (_e.config.revealRoleOnDeath)
        Text(_t('مافیای باقی‌مانده: $mafiaLeft', 'Mafia left: $mafiaLeft'),
            style: const TextStyle(color: MafiaStyle.blood, fontSize: 11, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _clockView(Color c) {
    final int m = _secondsLeft ~/ 60;
    final int s = _secondsLeft % 60;
    final double frac = _secondsTotal == 0 ? 0 : _secondsLeft / _secondsTotal;
    final bool done = _secondsLeft == 0;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
      SizedBox(
        width: 58,
        height: 58,
        child: Stack(alignment: Alignment.center, children: <Widget>[
          SizedBox(
            width: 58,
            height: 58,
            child: CircularProgressIndicator(
              value: frac,
              strokeWidth: 4,
              color: done ? MafiaStyle.blood : c,
              backgroundColor: Colors.white12,
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('$m:${s.toString().padLeft(2, '0')}',
                style: TextStyle(color: done ? MafiaStyle.blood : Colors.white, fontWeight: FontWeight.w900)),
          ),
        ]),
      ),
      const SizedBox(width: 10),
      IconButton(
        tooltip: _paused ? _t('ادامه', 'Resume') : _t('توقف', 'Pause'),
        onPressed: () => setState(() => _paused = !_paused),
        icon: Icon(_paused ? Icons.play_circle : Icons.pause_circle, color: NxColors.iceWhite, size: 30),
      ),
      IconButton(
        tooltip: _t('۳۰ ثانیه بیشتر', '+30 seconds'),
        onPressed: () => setState(() {
          _secondsLeft += 30;
          _secondsTotal = max(_secondsTotal, _secondsLeft);
        }),
        icon: const Icon(Icons.more_time, color: NxColors.iceWhite, size: 28),
      ),
    ]);
  }

  Widget _controls() {
    switch (_stage) {
      case _NStage.day:
        return Column(children: <Widget>[
          Text(_t('بحث آزاد', 'Open discussion'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(_t('شهر حرف می‌زند؛ وقتی وقت تمام شد، متهمان را انتخاب کنید.', 'The town talks; when time is up, pick who goes on trial.'),
              textAlign: TextAlign.center, style: _dim),
          const SizedBox(height: 8),
          _clockView(NxColors.gold),
          const SizedBox(height: 8),
          GlowButton(label: _t('رفتن به رأی‌گیری', 'Go to nominations'), icon: Icons.how_to_vote, color: NxColors.gold, onTap: _toNominate),
        ]);
      case _NStage.nominate:
        return Column(children: <Widget>[
          Text(_t('چه کسانی به دفاع می‌روند؟', 'Who goes on trial?'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(_t('با دست رأی بدهید و تا ۳ متهم را روی میز لمس کنید.', 'Vote by hands, then tap up to 3 defendants on the table.'),
              textAlign: TextAlign.center, style: _dim),
          const SizedBox(height: 6),
          if (_defendants.isNotEmpty)
            Text(_join(_defendants.map(_name)),
                textAlign: TextAlign.center, style: const TextStyle(color: MafiaStyle.blood, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: <Widget>[
            GlowButton(
              label: _t('شروع دفاع', 'Start defense'),
              icon: Icons.gavel,
              color: MafiaStyle.blood,
              onTap: _defendants.isEmpty ? null : _startDefense,
            ),
            GhostButton(label: _t('کسی به دفاع نرفت', 'Nobody on trial'), icon: Icons.nightlight_round, onTap: _skipTrial),
          ]),
        ]);
      case _NStage.defense:
        final int d = _defendants[_defIdx];
        return Column(children: <Widget>[
          Text(_t('دفاعیه‌ی ${_name(d)}', '${_name(d)} defends'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('${_defIdx + 1} / ${_defendants.length}', style: _dim),
          const SizedBox(height: 8),
          _clockView(MafiaStyle.blood),
          const SizedBox(height: 8),
          GlowButton(
            label: _defIdx + 1 < _defendants.length ? _t('متهم بعدی', 'Next defendant') : _t('رأی نهایی', 'Final vote'),
            icon: Icons.skip_next,
            color: MafiaStyle.blood,
            onTap: _nextDefense,
          ),
        ]);
      case _NStage.vote:
        return Column(children: <Widget>[
          Text(_t('رأی نهایی', 'Final vote'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
              _t('تعداد دست‌ها برای هر متهم را وارد کنید (هر زنده یک رأی). بیشترین رأی، اگر از رأی‌های ممتنع بیشتر باشد، حذف می‌شود.',
                  'Enter raised hands per defendant (one per living player). A unique top count above the abstentions is eliminated.'),
              textAlign: TextAlign.center,
              style: _dim),
          const SizedBox(height: 6),
          for (final int d in _defendants)
            Row(children: <Widget>[
              CrewAvatar(name: _name(d), hue: _hue(d), size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_name(d),
                    overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              _stepper(_counts[d] ?? 0, () => _setCount(d, -1), () => _setCount(d, 1)),
            ]),
          Text(_t('ممتنع: ${max(0, _e.aliveCount - _votesUsed)}', 'Abstain: ${max(0, _e.aliveCount - _votesUsed)}'), style: _dim),
          const SizedBox(height: 8),
          GlowButton(label: _t('اعلام نتیجه', 'Announce verdict'), icon: Icons.gavel, color: MafiaStyle.blood, onTap: _resolveVote),
        ]);
      case _NStage.verdict:
        final int? out = _verdict?.eliminated;
        return Column(children: <Widget>[
          if (out != null) ...<Widget>[
            CrewAvatar(name: _name(out), hue: _hue(out), size: 48, dead: true),
            const SizedBox(height: 6),
            Text(_deathLine(out, DeathCause.vote),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          ] else
            Text(_t('رأی کافی نبود؛ کسی حذف نشد.', 'Not enough votes; nobody is eliminated.'),
                textAlign: TextAlign.center, style: const TextStyle(color: NxColors.turquoise, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          GlowButton(
            label: _e.isOver ? _t('پایان بازی', 'Game over') : _t('شب فرا می‌رسد', 'Night falls'),
            icon: _e.isOver ? Icons.flag : Icons.nightlight_round,
            color: NxColors.violet,
            onTap: _afterVerdict,
          ),
        ]);
      case _NStage.setup:
      case _NStage.pass:
      case _NStage.nightIntro:
      case _NStage.nightStep:
      case _NStage.detectiveAnswer:
      case _NStage.dawn:
      case _NStage.over:
        return const SizedBox.shrink();
    }
  }

  void _skipTrial() {
    _e.addLog(LogKind.vote, 'امروز کسی به دفاع نرفت.', 'Nobody went on trial today.');
    _endDay();
  }

  // ------------------------------------------------------------------- over
  Widget _overScreen() {
    final MafiaTeam w = _e.winner ?? MafiaTeam.town;
    final Color c = MafiaStyle.teamColor(w);
    return _scroll(Column(children: <Widget>[
      PhaseBanner(
        title: w == MafiaTeam.town ? _t('شهر پیروز شد', 'The Town wins') : _t('مافیا پیروز شد', 'The Mafia wins'),
        subtitle: _t('پایان بازی در روز ${_e.day} · همه‌ی نقش‌ها فاش شد', 'Ended on day ${_e.day} · every role revealed'),
        icon: w == MafiaTeam.town ? Icons.shield : Icons.dangerous,
        color: c,
        animate: _fx,
      ),
      const SizedBox(height: 16),
      MafiaPanel(
        accent: c,
        child: Column(children: <Widget>[
          for (final MafiaPlayer p in _e.players)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: <Widget>[
                CrewAvatar(
                  name: p.name,
                  hue: _hue(p.id),
                  size: 34,
                  dead: !p.alive,
                  glow: p.role.team == w ? c : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(p.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.alive ? Colors.white : NxColors.textDim,
                        fontWeight: FontWeight.w800,
                        decoration: p.alive ? null : TextDecoration.lineThrough,
                      )),
                ),
                _roleChip(p.role),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 18),
      GlowButton(label: _t('ثبت نتیجه', 'Finish'), icon: Icons.emoji_events, color: c, onTap: _finish),
    ]));
  }
}

/// Small pill used in the narrator header (kept local so it never depends on
/// the shared pill's sizing).
class NxPillLite extends StatelessWidget {
  const NxPillLite({super.key, required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
    );
  }
}
