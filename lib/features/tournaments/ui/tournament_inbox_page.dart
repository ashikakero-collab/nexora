import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../data/models.dart';
import '../data/tournament_repository.dart';
import 't_common.dart';

/// In-app tournament notifications (nx_t_notifications).
class TournamentInboxPage extends ConsumerStatefulWidget {
  const TournamentInboxPage({super.key});

  @override
  ConsumerState<TournamentInboxPage> createState() =>
      _TournamentInboxPageState();
}

class _TournamentInboxPageState extends ConsumerState<TournamentInboxPage> {
  List<TNotification> _items = <TNotification>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final TournamentRepository repo = ref.read(tournamentRepoProvider);
    try {
      final List<TNotification> items = await repo.notifications();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
      if (items.any((TNotification n) => !n.read)) unawaited(repo.markRead());
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _icon(String kind) => switch (kind) {
        'match_ready' || 'match_soon' => Icons.sports_esports_rounded,
        'starting_soon' ||
        'started' ||
        'time_changed' =>
          Icons.schedule_rounded,
        'prize' => Icons.emoji_events_rounded,
        'refund' => Icons.currency_exchange_rounded,
        'eliminated' || 'rejected' || 'cancelled' => Icons.cancel_rounded,
        'dispute' => Icons.gavel_rounded,
        _ => Icons.notifications_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return NxWorldScaffold(
      title: context.tx('اعلان‌های تورنمنت', 'TOURNAMENT INBOX'),
      palette: WorldPalette.arcade,
      showWallet: false,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: <Widget>[
                      const SizedBox(height: 120),
                      Center(
                          child: Text(
                              context.tx('اعلانی نداری', 'No notifications'),
                              style: const TextStyle(color: NxColors.textDim))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(NxSpace.md),
                      itemCount: _items.length,
                      itemBuilder: (BuildContext context, int i) {
                        final TNotification n = _items[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassPanel(
                            blur: false,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            borderColor: n.read
                                ? null
                                : tAccent(context).withValues(alpha: 0.8),
                            onTap: n.tournamentId == null
                                ? null
                                : () => context
                                    .push('/tournaments/${n.tournamentId}'),
                            child: Row(children: <Widget>[
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (n.read
                                          ? NxThemeColors.of(context).muted
                                          : tAccent(context))
                                      .withValues(alpha: 0.14),
                                  border: Border.all(
                                    color: (n.read
                                            ? NxThemeColors.of(context).border
                                            : tAccent(context))
                                        .withValues(alpha: 0.52),
                                  ),
                                ),
                                child: Icon(_icon(n.kind),
                                    color: n.read
                                        ? NxThemeColors.of(context).muted
                                        : tAccent(context)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(n.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: NxThemeColors.of(context)
                                                  .muted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 3),
                                      Text(notifText(context, n),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              height: 1.25)),
                                      const SizedBox(height: 4),
                                      Text(fmtWhen(n.createdAt, withUtc: false),
                                          style: TextStyle(
                                              color: NxThemeColors.of(context)
                                                  .muted,
                                              fontSize: 10)),
                                    ]),
                              ),
                              if (!n.read) ...<Widget>[
                                const SizedBox(width: 8),
                                NxPill(
                                    label: context.tx('جدید', 'NEW'),
                                    color: tAccent(context)),
                              ],
                            ]),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
