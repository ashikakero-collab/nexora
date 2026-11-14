// Port of App.tsx (Shell / ShellInner): intro -> home, bottom tabs, full-screen overlay stack, back rules,
// cross-fade veil, match rewards (+streaks, cup progression), daily reward, chests, report_offline rpc,
// password-recovery card and the Oracle layer.
//
// The Flutter port is Navigator based: every screen is its own page (Scaffold + Header -> Navigator.pop), so the RN
// route state ('tabs' | 'match' | 'result' | 'online') and the overlay list map onto routes of [navKey]:
//   root page      = tabs (Hud + tab body + NavBar)
//   match / result = one page each, pushed above root (result replaces match)
//   online         = OnlineRoot page (handles its own back)
//   overlays       = profile / chat / club / team pages, de-duplicated by key, at most 6 deep (pushOverlay)
//   sheet / modal  = showSheet / showCard routes
import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Tab;

import '../core/sound.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../game/meta.dart';
import '../intro/intro.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../online/online_root.dart';
import '../oracle/oracle.dart';
import '../screens/home.dart';
import '../screens/match.dart';
import '../screens/play.dart';
import '../screens/profile.dart';
import '../screens/result.dart';
import '../screens/settings.dart';
import '../screens/setup.dart';
import '../screens/shop.dart';
import '../screens/team.dart';
import '../social/social.dart' as social;
import '../ui/chrome.dart';
import '../ui/kit.dart';

const int kDayMs = 86400000;

/// Reward multiplier per offline mode (MULT in App.tsx).
double modeMult(ModeKey m) => switch (m) { ModeKey.quick => 1, ModeKey.cup => 2, ModeKey.galaxy => 3, ModeKey.train => .3, ModeKey.local => 0 };

class MatchOutcome {
  final Reward? reward;
  final CupInfo? cup;
  final int? levelUp;
  const MatchOutcome(this.reward, this.cup, this.levelUp);
}

/// Pure reward formula of App.tsx onFinish (exposed for tests).
MatchOutcome computeOutcome(MatchResult r, Launch l, Profile p) {
  if (!r.ai) return const MatchOutcome(null, null, null);
  final a = r.score[0], b = r.score[1], win = a > b, draw = a == b;
  final mult = const [1.0, 1.5, 2.2][r.aiLvl.clamp(0, 2)] * modeMult(l.mode);
  CupInfo? cup;
  if (l.mode == ModeKey.cup) cup = CupInfo(l.stage, win, win && l.stage >= 2);
  final rw = Reward(
    ((win ? 60 : draw ? 25 : 12) * mult + a * 5).round(),
    ((win ? 50 : 20) * math.max(.3, mult)).round(),
    l.mode == ModeKey.train ? 0 : win ? (20 * mult).round() : draw ? 0 : -8,
    0,
  );
  if (cup?.champion == true) rw.coins += 400;
  final before = level(p.xp).level, after = level(p.xp + rw.xp).level;
  return MatchOutcome(rw, cup, after > before ? after : null);
}

/// Shell services other modules can call (NavCtx in the RN app).
class AppNav {
  static _ShellState? _s;
  static void openOnline([String entry = 'hub', String? quick]) => _s?.openOnline(entry, quick);
  static void openTeam() => _s?.openTeam();
  static void openProfile(String id) => _s?.openProfile(id);
  static void openChat(String id) => _s?.openChat(id);
  static void openClub(String id) => _s?.openClub(id);

  /// Push a full-screen overlay page; an existing overlay with the same key is moved to the top, max 6 kept.
  static void pushOverlay(String key, WidgetBuilder b) => _s?.pushOverlay(key, b);
}

/// Counts routes above the root page so the shell knows when the tabs are visible (Oracle bubble).
class _DepthObserver extends NavigatorObserver {
  final ValueNotifier<int> depth;
  _DepthObserver(this.depth);
  @override
  void didPush(Route route, Route? previousRoute) => _bump(route, 1);
  @override
  void didPop(Route route, Route? previousRoute) => _bump(route, -1);
  @override
  void didRemove(Route route, Route? previousRoute) => _bump(route, -1);
  void _bump(Route r, int d) {
    if (r.isFirst && d > 0) return;
    // defer: observer callbacks fire during navigator build/locking
    scheduleMicrotask(() => depth.value = math.max(0, depth.value + d));
  }
}

class NexoraApp extends StatefulWidget {
  const NexoraApp({super.key});
  @override
  State<NexoraApp> createState() => _ShellState();
}

class _ShellState extends State<NexoraApp> with SingleTickerProviderStateMixin {
  late final AnimationController veil = AnimationController(vsync: this, duration: const Duration(milliseconds: 170));
  final depth = ValueNotifier<int>(0);
  late final _DepthObserver _obs = _DepthObserver(depth);
  final tab = ValueNotifier<Tab>(Tab.arcade);
  bool intro = true;
  bool _recoveryShown = false;
  Launch? launch;
  int matchKey = 0;
  final List<(String, Route)> _overlays = [];

  NavigatorState get nav => navKey.currentState!;
  BuildContext get ctx => navKey.currentContext!;
  Profile get p => Store.i.p;

  @override
  void initState() {
    super.initState();
    AppNav._s = this;
    toastListeners.add(Oracle.i.onToast);
    Oracle.i.actions = OracleActions(
      goTab: (t) {
        _closeOverlays();
        nav.popUntil((r) => r.isFirst);
        _goTabByName(t);
      },
      openOnline: (e, q) => openOnline(e.isEmpty ? 'hub' : e, q),
      openSettings: openSettings,
      openTeam: openTeam,
    );
    Store.i.addListener(_onStore);
    Auth.i.addListener(_onAuth);
    _onStore();
  }

  @override
  void dispose() {
    toastListeners.remove(Oracle.i.onToast);
    Store.i.removeListener(_onStore);
    Auth.i.removeListener(_onAuth);
    if (AppNav._s == this) AppNav._s = null;
    veil.dispose();
    super.dispose();
  }

  // ---------------- audio prefs / recovery ----------------
  (bool, bool, bool, double)? _audio;
  void _onStore() {
    final a = (p.sound, p.music, p.haptics, p.volume);
    if (a != _audio) {
      _audio = a;
      Sound.prefs(sound: p.sound, music: p.music, haptics: p.haptics, volume: p.volume);
    }
  }

  void _onAuth() {
    if (Auth.i.recovery && !_recoveryShown) {
      _recoveryShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = navKey.currentContext;
        if (c == null) return;
        showRecovery(c).whenComplete(() => _recoveryShown = false);
      });
    }
  }

  // ---------------- veil cross-fade ----------------
  void transition(VoidCallback fn) {
    veil.animateTo(1, duration: const Duration(milliseconds: 170), curve: Curves.easeInQuad);
    Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      fn();
      veil.animateTo(0, duration: const Duration(milliseconds: 340), curve: Curves.easeOutCubic);
    });
  }

  void _toRoot() {
    _overlays.clear();
    nav.popUntil((r) => r.isFirst);
  }

  void goHome() => transition(() {
        _toRoot();
        tab.value = Tab.arcade;
        Sound.scene(AudioScene.menu);
      });

  // ---------------- tabs ----------------
  void _goTabByName(String t) {
    switch (t) {
      case 'home' || 'arcade':
        tab.value = Tab.arcade;
      case 'social' || 'chat':
        tab.value = Tab.chat;
      case 'play':
        tab.value = Tab.arcade;
        _push(PlayScreen(onMode: openMode, onOnline: (e) => openOnline(e)));
      case 'shop':
        tab.value = Tab.arcade;
        _push(ShopScreen(onChest: openChest));
      case 'profile':
        tab.value = Tab.arcade;
        _push(ProfileScreen(onOnline: (e) => openOnline(e)));
      default:
        tab.value = Tab.arcade;
    }
  }

  void onTab(Tab t) {
    switch (t) {
      case Tab.arcade || Tab.chat:
        tab.value = t;
      case Tab.reward:
        openDaily();
      case Tab.shop:
        _push(ShopScreen(onChest: openChest));
      case Tab.menu:
        openSettings();
    }
  }

  void onWorld(String w) {
    switch (w) {
      case 'arcade':
        _push(PlayScreen(onMode: openMode, onOnline: (e) => openOnline(e)));
      case 'online':
        openOnline('hub');
      case 'challenges':
        openOnline('challenges');
      case 'social':
        tab.value = Tab.chat;
      case 'oracle':
        _push(const OraclePanel());
      case 'profile':
        _push(ProfileScreen(onOnline: (e) => openOnline(e)));
      case 'shop':
        _push(ShopScreen(onChest: openChest));
      case 'gallery' || 'team':
        openTeam();
      case 'cup':
        openMode(kModes.firstWhere((m) => m.k == ModeKey.cup));
      default:
        toast('به‌زودی', 'info');
    }
  }

  Future<R?> _push<R>(Widget page) => nav.push<R>(fadeRoute(page));

  // ---------------- overlays ----------------
  void pushOverlay(String key, WidgetBuilder b) {
    for (final o in List.of(_overlays)) {
      if (o.$1 == key) {
        _overlays.remove(o);
        if (o.$2.isActive) nav.removeRoute(o.$2);
      }
    }
    final r = fadeRoute<void>(Builder(builder: b));
    final entry = (key, r);
    _overlays.add(entry);
    nav.push(r).whenComplete(() => _overlays.remove(entry));
    while (_overlays.length > 6) {
      final old = _overlays.removeAt(0);
      if (old.$2.isActive) nav.removeRoute(old.$2);
    }
  }

  void _closeOverlays() {
    for (final o in List.of(_overlays)) {
      if (o.$2.isActive) nav.removeRoute(o.$2);
    }
    _overlays.clear();
  }

  void openTeam() => pushOverlay('team', (_) => const TeamScreen());
  void openProfile(String id) => social.openPublicProfile(ctx, id);
  void openChat(String id) => social.openChat(ctx, id);
  void openClub(String id) => social.openClub(ctx, id);

  // ---------------- sheets ----------------
  void openMode(Mode m) => showSheet(ctx,
      title: m.name,
      en: m.en,
      accent: m.color,
      height: .9,
      child: (sc) => SetupSheet(
            mode: m,
            onStart: startMatch,
            onTeam: () {
              Navigator.pop(sc);
              openTeam();
            },
          ));

  void openSettings() => showSheet(ctx,
      title: 'تنظیمات',
      en: 'SYSTEMS',
      accent: C.sky,
      height: .78,
      child: (sc) => SettingsSheet(replayIntro: () {
            Navigator.pop(sc);
            setState(() => intro = true);
          }));

  // ---------------- online ----------------
  void openOnline(String entry, [String? quick]) => transition(() {
        _toRoot();
        _push(OnlineRoot(entry: entry, quick: quick)).whenComplete(() {
          Sound.scene(AudioScene.menu);
          Oracle.i.setScene('ui');
        });
      });

  // ---------------- match / result ----------------
  void startMatch(Launch l) {
    launch = l;
    matchKey++;
    transition(() {
      _toRoot();
      Sound.scene(AudioScene.match);
      _push(MatchScreen(key: ValueKey('m$matchKey'), cfg: l.cfg, teams: l.teams, names: l.names, onFinish: onFinish, onQuit: goHome));
    });
  }

  void onFinish(MatchResult r) {
    final l = launch!;
    final o = computeOutcome(r, l, p);
    final a = r.score[0], b = r.score[1], win = a > b, draw = a == b;
    if (r.ai && o.reward != null) {
      final rw = o.reward!;
      Store.i.set((q) {
        final ws = win ? q.winStreak + 1 : 0;
        q.coins += rw.coins + (o.levelUp != null ? 100 : 0);
        q.gems += rw.gems;
        q.xp += rw.xp;
        q.trophies = math.max(0, q.trophies + rw.trophies);
        q.played += 1;
        if (win) q.wins += 1;
        if (!win && !draw) q.losses += 1;
        if (draw) q.draws += 1;
        q.goalsFor += a;
        q.goalsAgainst += b;
        q.winStreak = ws;
        q.bestStreak = math.max(q.bestStreak, ws);
        if (o.cup?.champion == true) q.cupsWon += 1;
      });
      if (win) buzz('success');
      if (o.levelUp != null) Oracle.i.react('levelup', fa(o.levelUp!));
      // offline bot wins feed the server-side "beat the bot" daily challenge
      if (Auth.i.uid != null && l.mode != ModeKey.train) {
        try {
          rpc('report_offline', {'p_won': win}).then((_) {}, onError: (_) {});
        } catch (_) {}
      }
    }
    transition(() {
      Sound.scene(AudioScene.menu);
      nav.pushReplacement(fadeRoute(_ResultPage(
        r: r,
        reward: o.reward,
        names: l.names,
        cup: o.cup,
        levelUp: o.levelUp,
        onAgain: () => _again(o.cup),
        onHome: goHome,
      )));
    });
  }

  void _again(CupInfo? cup) {
    final l = launch!;
    if (cup != null) {
      if (cup.won && !cup.champion) {
        nextCup();
      } else {
        startMatch(buildLaunch(ModeKey.cup, p, lvl: 0, rule: 'g3', tt: p.turnTime, opp: l.teams[1], stage: 0));
      }
      return;
    }
    final c = l.cfg;
    startMatch(buildLaunch(l.mode, p, lvl: c.aiLvl, rule: c.matchTime == 180 ? 't3' : c.limit == 5 ? 'g5' : 'g3', tt: c.turnTime.round(), opp: l.teams[1], stage: 0));
  }

  void nextCup() {
    final l = launch!, st = l.stage + 1;
    final pool = kTeams.where((t) => t.cat == 'club' || t.cat == 'nat' || t.cat == 'elite').toList();
    startMatch(buildLaunch(ModeKey.cup, p, lvl: 1, rule: 'g3', tt: p.turnTime, opp: pool[math.Random().nextInt(pool.length)], stage: st));
  }

  // ---------------- daily reward / chests ----------------
  int get _now => DateTime.now().millisecondsSinceEpoch;
  bool get dailyReady => _now - p.lastDaily > kDayMs;
  bool get chestReady => _now - p.lastChest > kChestEvery;

  void openDaily() => showCard(ctx,
      child: (cc) => ListenableBuilder(
            listenable: Store.i,
            builder: (_, _) => DailyCard(ready: dailyReady, streak: p.streak, lastDaily: p.lastDaily, onClaim: () => claimDaily(cc)),
          ));

  void claimDaily(BuildContext cc) {
    if (!dailyReady) return;
    final now = _now;
    final streak = now - p.lastDaily < 2 * kDayMs ? (p.streak % 7) + 1 : 1;
    final rw = kDaily[streak - 1];
    Store.i.set((q) {
      q.lastDaily = now;
      q.streak = streak;
      q.coins += rw.$1;
      q.gems += rw.$2;
    });
    sfx(Snd.goal);
    buzz('success');
    toast('+${fa(rw.$1)} سکه${rw.$2 > 0 ? ' · +${fa(rw.$2)} الماس' : ''}', 'ok');
    Navigator.of(cc).maybePop();
  }

  void openChest(bool premium) {
    if (!premium && !chestReady) {
      toast('صندوقچه‌ی رایگان هنوز آماده نیست', 'info');
      return;
    }
    if (premium && p.coins < 600) {
      toast('۶۰۰ سکه لازمه', 'err');
      return;
    }
    final prize = rollChest(p, premium);
    final now = _now;
    Store.i.set((q) {
      if (prize.item != null) grant(prize.item!, q);
      q.coins += prize.coins - (premium ? 600 : 0);
      q.gems += prize.gems;
      if (!premium) q.lastChest = now;
      q.chests += 1;
    });
    showCard(ctx, accent: premium ? C.gold : C.cyan, child: (_) => ChestOpen(prize: prize, premium: premium));
  }

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEXORA',
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      navigatorObservers: [_obs],
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: C.bg, fontFamily: F.body, useMaterial3: true),
      builder: (context, child) => Stack(children: [
        child ?? const SizedBox.shrink(),
        // Oracle coach + bubble (bubble only while the tabs are visible)
        Positioned.fill(
          child: ValueListenableBuilder<int>(
            valueListenable: depth,
            builder: (_, d, _) => OracleLayer(bubble: d == 0 && !intro, onOpenPanel: () => _push(const OraclePanel())),
          ),
        ),
        // cross-fade veil between tabs / match / result / online
        Positioned.fill(
          child: IgnorePointer(child: FadeTransition(opacity: veil, child: const ColoredBox(color: Color(0xff02030b)))),
        ),
        if (intro)
          Positioned.fill(
            child: Intro(onDone: () {
              setState(() => intro = false);
              Oracle.i.greet();
            }),
          ),
      ]),
      home: _TabsPage(shell: this),
    );
  }
}

/// Root page: Space backdrop, tab body (fade between tabs), HUD and bottom navigation. Back on a non-home tab -> home.
class _TabsPage extends StatelessWidget {
  final _ShellState shell;
  const _TabsPage({required this.shell});

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    final top = ins.top + 62, bottom = kTabH + math.max(10.0, ins.bottom) + 6;
    return ValueListenableBuilder<Tab>(
      valueListenable: shell.tab,
      builder: (context, tab, _) => PopScope(
        canPop: tab == Tab.arcade,
        onPopInvokedWithResult: (did, _) {
          if (!did && tab != Tab.arcade) shell.tab.value = Tab.arcade;
        },
        child: Scaffold(
          backgroundColor: C.bg,
          body: ListenableBuilder(
            listenable: Store.i,
            builder: (context, _) {
              final dailyReady = shell.dailyReady, chestReady = shell.chestReady;
              return Stack(children: [
                Positioned.fill(child: Space(theme: tab == Tab.arcade ? SpaceTheme.stadium : SpaceTheme.base, dim: tab == Tab.arcade ? 0 : .15)),
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    reverseDuration: const Duration(milliseconds: 120),
                    child: KeyedSubtree(
                      key: ValueKey(tab),
                      child: tab == Tab.chat
                          ? social.SocialRoot(top: top, bottom: bottom)
                          : HomeScreen(
                              top: top,
                              bottom: bottom,
                              onWorld: shell.onWorld,
                              onQuick: () => shell.openMode(kModes.first),
                              onDaily: shell.openDaily,
                              onChest: () => shell.openChest(false),
                              dailyReady: dailyReady,
                              chestReady: chestReady,
                            ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Hud(
                    onProfile: () => shell._push(ProfileScreen(onOnline: (e) => shell.openOnline(e))),
                    onShop: () => shell._push(ShopScreen(onChest: shell.openChest)),
                    onDaily: shell.openDaily,
                    onOracle: () => shell._push(const OraclePanel()),
                    dailyReady: dailyReady,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: NavBar(tab: tab, onTab: shell.onTab, badges: {if (chestReady) Tab.shop, if (dailyReady) Tab.reward}),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// Result page: back goes home (App.tsx: route === 'result' -> goHome).
class _ResultPage extends StatelessWidget {
  final MatchResult r;
  final Reward? reward;
  final List<String> names;
  final CupInfo? cup;
  final int? levelUp;
  final VoidCallback onAgain, onHome;
  const _ResultPage({required this.r, required this.reward, required this.names, required this.cup, required this.levelUp, required this.onAgain, required this.onHome});
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (did, _) {
          if (!did) onHome();
        },
        child: ResultScreen(r: r, reward: reward, names: names, cup: cup, levelUp: levelUp, onAgain: onAgain, onHome: onHome),
      );
}
