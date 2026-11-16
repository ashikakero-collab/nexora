import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets/app_assets.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';
import '../../games/game_registry.dart';
import 'game_host_page.dart';
import 'online/online_lobby_page.dart';

/// Pre-game screen: mode, difficulty, seats, rules.
class GameSetupPage extends ConsumerStatefulWidget {
  const GameSetupPage({super.key, required this.gameId});
  final String gameId;

  @override
  ConsumerState<GameSetupPage> createState() => _GameSetupPageState();
}

class _GameSetupPageState extends ConsumerState<GameSetupPage> {
  GameMode _mode = GameMode.vsBot;
  BotDifficulty _difficulty = BotDifficulty.normal;
  int _players = 2;
  bool _init = false;

  @override
  Widget build(BuildContext context) {
    final game = gameById(widget.gameId);
    if (game == null) {
      return NxWorldScaffold(
        title: 'ARCADE',
        palette: WorldPalette.arcade,
        body: Center(
            child: Text(context.tx('این بازی پیدا نشد', 'Game not found'))),
      );
    }
    if (!_init) {
      _init = true;
      _players = game.defaultPlayers;
    }
    final stats = ref.watch(profileProvider).stats[game.id];
    final visual = NxThemeColors.of(context);
    return NxWorldScaffold(
      title: context.tx(game.nameFa, game.nameEn).toUpperCase(),
      palette: WorldPalette.arcade,
      body: ListView(
        padding: const EdgeInsets.all(NxSpace.md),
        children: [
          SizedBox(
            height: 190,
            child: Hero(
              tag: 'pedestal_${game.id}',
              child: Image.asset(AppAssets.pedestal(game.id),
                  cacheWidth: 600, fit: BoxFit.contain),
            ),
          ),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            borderColor: game.accent.withValues(alpha: 0.48),
            child: Column(children: [
              Text(context.tx(game.nameFa, game.nameEn),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: visual.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(context.tx(game.taglineFa, game.taglineEn),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: game.accent, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (stats != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: Text(
                    context.tx('برد ${stats.won} از ${stats.played}',
                        '${stats.won} wins of ${stats.played}'),
                    style: TextStyle(color: visual.muted, fontSize: 12)),
              ),
            ),
          const SizedBox(height: NxSpace.md),
          GlassPanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tx('حالت بازی', 'Mode'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SegmentedButton<GameMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: GameMode.vsBot,
                      icon: const Icon(Icons.smart_toy_rounded),
                      label: Text(context.tx('با بات', 'vs Bot'))),
                  ButtonSegment(
                      value: GameMode.local,
                      icon: const Icon(Icons.groups_rounded),
                      label: Text(game.id == 'mafia'
                          ? context.tx('حالت راوی', 'Narrator')
                          : context.tx('دو نفره', 'Local'))),
                  if (game.supportsOnline)
                    ButtonSegment(
                        value: GameMode.online,
                        icon: const Icon(Icons.public_rounded),
                        label: Text(context.tx('آنلاین', 'Online'))),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
              if (_mode == GameMode.vsBot) ...[
                const SizedBox(height: 14),
                Text(context.tx('سختی', 'Difficulty'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                SegmentedButton<BotDifficulty>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: BotDifficulty.easy,
                        label: Text(context.tx('آسان', 'Easy'))),
                    ButtonSegment(
                        value: BotDifficulty.normal,
                        label: Text(context.tx('معمولی', 'Normal'))),
                    ButtonSegment(
                        value: BotDifficulty.hard,
                        label: Text(context.tx('سخت', 'Hard'))),
                  ],
                  selected: {_difficulty},
                  onSelectionChanged: (v) =>
                      setState(() => _difficulty = v.first),
                ),
              ],
              if (_mode == GameMode.online) ...[
                const SizedBox(height: 12),
                Text(
                  context.tx(
                      'با بازیکنان واقعی: بازی سریع، اتاق خصوصی با کد، یا دعوت دوستان.',
                      'Real players: quick match, private room by code, or invite friends.'),
                  style:
                      TextStyle(color: visual.muted, fontSize: 12, height: 1.4),
                ),
              ],
              if (game.maxPlayers > 2 && _mode != GameMode.online) ...[
                const SizedBox(height: 14),
                Row(children: [
                  Text(context.tx('تعداد بازیکن', 'Players'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    onPressed: _players > game.minPlayers
                        ? () => setState(() => _players--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_players',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900)),
                  IconButton(
                    onPressed: _players < game.maxPlayers
                        ? () => setState(() => _players++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: NxSpace.md),
          GlassPanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.menu_book_rounded, color: NxColors.turquoise),
                const SizedBox(width: 8),
                Text(context.tx('قوانین', 'Rules'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 8),
              Text(context.tx(game.rulesFa, game.rulesEn),
                  style: const TextStyle(height: 1.6, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: NxSpace.lg),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: game.accent,
              minimumSize: const Size.fromHeight(58),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(NxRadius.md)),
            ),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _mode == GameMode.online
                  ? OnlineLobbyPage(gameId: game.id)
                  : GameHostPage(
                      game: game,
                      mode: _mode,
                      difficulty: _difficulty,
                      players: _players),
            )),
            icon: Icon(_mode == GameMode.online
                ? Icons.public_rounded
                : Icons.play_arrow_rounded),
            label: Text(
                _mode == GameMode.online
                    ? context.tx('ورود به لابی آنلاین', 'Enter online lobby')
                    : context.tx('شروع بازی', 'Start match'),
                style: const TextStyle(fontSize: 17)),
          ),
          if (game.supportsOnline &&
              game.maxPlayers == 2 &&
              game.id != 'mafia') ...[
            const SizedBox(height: NxSpace.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: NxColors.gold),
              onPressed: () => context.push('/tournaments?game=${game.id}'),
              icon: const Icon(Icons.emoji_events_rounded),
              label: Text(context.tx(
                  'تورنمنت‌های این بازی', 'Tournaments for this game')),
            ),
          ],
        ],
      ),
    );
  }
}
