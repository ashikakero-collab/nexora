import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/assets/app_assets.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../nova_gallery/models/art_asset.dart';
import '../../nova_gallery/models/nova_models.dart';
import '../../nova_gallery/ui/nova_visuals.dart';
import '../data/orbit_shared_inbox.dart';
import '../models/arcade_refs.dart';
import '../models/orbit_models.dart';

String orbitTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Honest bottom sheet for features that require the server (calls, contacts...).
Future<void> showOrbitOnlineOnly(BuildContext context,
    {required String fa, required String en, IconData icon = Icons.call_rounded}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext c) => Padding(
      padding: const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.lg),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(icon, size: 44, color: WorldPalette.orbit.primary),
        const SizedBox(height: 10),
        OnlineOnlyNotice(featureFa: fa, featureEn: en),
        const SizedBox(height: 10),
        Text(
          c.tx('تماس‌ها از طریق LiveKit و سرور NEXORA برقرار می‌شوند؛ تا آن زمان هیچ تماسی شبیه‌سازی نمی‌شود.',
              'Calls run through LiveKit and the NEXORA server; until then no call is simulated.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: NxColors.textDim, fontSize: 12),
        ),
      ]),
    ),
  );
}

/// Club badge or a fallback icon for a chat.
class OrbitChatAvatar extends StatelessWidget {
  const OrbitChatAvatar({super.key, required this.chat, this.size = 46});
  final OrbitChat chat;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pal = WorldPalette.orbit;
    Widget inner;
    if (chat.isSaved) {
      inner = Icon(Icons.bookmark_rounded, color: NxColors.navyDeep, size: size * 0.5);
    } else if (chat.badgeId.isNotEmpty) {
      inner = Padding(
        padding: EdgeInsets.all(size * 0.08),
        child: Image.asset(
          AppAssets.clubBadge(chat.badgeId),
          cacheWidth: (size * 2.5).round(),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(Icons.groups_rounded, color: Colors.white, size: size * 0.5),
        ),
      );
    } else {
      inner = Icon(chat.isChannel ? Icons.campaign_rounded : Icons.groups_rounded, color: Colors.white, size: size * 0.5);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: chat.isSaved
            ? LinearGradient(colors: <Color>[pal.primary, pal.secondary])
            : const LinearGradient(colors: <Color>[Color(0xFF0B3B55), Color(0xFF06324A)]),
        border: Border.all(color: pal.primary.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}

class OrbitDeliveryIcon extends StatelessWidget {
  const OrbitDeliveryIcon({super.key, required this.delivery});
  final OrbitDelivery delivery;

  @override
  Widget build(BuildContext context) {
    switch (delivery) {
      case OrbitDelivery.queued:
        return Tooltip(
          message: context.tx(
              'روی دستگاه ذخیره شد؛ بعد از اتصال سرور ارسال می‌شود', 'Saved on device; sends once the server is connected'),
          child: const Icon(Icons.schedule_rounded, size: 14, color: NxColors.textDim),
        );
      case OrbitDelivery.sent:
        return const Icon(Icons.done_rounded, size: 14, color: NxColors.textDim);
      case OrbitDelivery.delivered:
        return const Icon(Icons.done_all_rounded, size: 14, color: NxColors.textDim);
      case OrbitDelivery.read:
        return const Icon(Icons.done_all_rounded, size: 14, color: NxColors.turquoise);
    }
  }
}

/// A single chat bubble (text, art, shared card, arcade invite or system line).
class OrbitMessageBubble extends StatelessWidget {
  const OrbitMessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.replyTo,
    this.highlight = '',
    this.onLongPress,
    this.onReplyTap,
  });
  final OrbitMessage message;
  final bool mine;
  final OrbitMessage? replyTo;
  final String highlight;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.kind == OrbitMessageKind.system) {
      final String by = '${m.payload['by'] ?? ''}';
      final bool channel = m.text == 'channel_created';
      if (m.text == 'member_added') {
        final String who = '${m.payload['who'] ?? ''}';
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: NxPill(
              icon: Icons.person_add_alt_1_rounded,
              color: WorldPalette.orbit.primary,
              label: context.tx('$by، $who را اضافه کرد', '$by added $who'),
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: NxPill(
            icon: channel ? Icons.campaign_rounded : Icons.groups_rounded,
            color: WorldPalette.orbit.primary,
            label: channel
                ? context.tx('کانال توسط $by ساخته شد', 'Channel created by $by')
                : context.tx('گروه توسط $by ساخته شد', 'Group created by $by'),
          ),
        ),
      );
    }
    final pal = WorldPalette.orbit;
    final double maxW = MediaQuery.of(context).size.width * 0.78;
    final bool hl = highlight.isNotEmpty && m.text.toLowerCase().contains(highlight.toLowerCase());
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!mine)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(m.authorName, style: TextStyle(color: pal.primary, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        if (replyTo != null)
          GestureDetector(
            onTap: onReplyTap,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              decoration: BoxDecoration(
                color: pal.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: pal.primary.withValues(alpha: 0.45)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Icon(Icons.reply_rounded, size: 12, color: pal.primary),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(replyTo!.authorName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: pal.primary, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ]),
                Text(replyTo!.preview(fa: context.isFa),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: NxColors.textDim)),
              ]),
            ),
          ),
        if (m.deleted)
          Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Icon(Icons.block_rounded, size: 14, color: NxColors.textDim),
            const SizedBox(width: 4),
            Text(context.tx('این پیام حذف شد', 'This message was deleted'),
                style: const TextStyle(fontStyle: FontStyle.italic, color: NxColors.textDim)),
          ])
        else ...<Widget>[
          if (m.kind == OrbitMessageKind.art) _ArtBody(assetRef: '${m.payload['asset'] ?? ''}'),
          if (m.kind == OrbitMessageKind.shared) OrbitSharedCard(payload: m.payload),
          if (m.kind == OrbitMessageKind.invite)
            OrbitInviteCard(gameId: '${m.payload['gameId'] ?? ''}', code: '${m.payload['code'] ?? ''}'),
          if (m.kind == OrbitMessageKind.call) OrbitCallCard(message: m, mine: mine),
          if (m.text.isNotEmpty && m.kind != OrbitMessageKind.shared && m.kind != OrbitMessageKind.invite)
            Padding(
              padding: EdgeInsets.only(top: m.kind == OrbitMessageKind.art ? 6 : 0),
              child: Text(m.text, style: const TextStyle(fontSize: 15, height: 1.4)),
            ),
        ],
        const SizedBox(height: 3),
        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (m.pinned)
            const Padding(
                padding: EdgeInsetsDirectional.only(end: 3), child: Icon(Icons.push_pin_rounded, size: 12, color: NxColors.gold)),
          if (m.starred)
            const Padding(
                padding: EdgeInsetsDirectional.only(end: 3), child: Icon(Icons.star_rounded, size: 13, color: NxColors.gold)),
          if (m.editedAt != null && !m.deleted)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Text(context.tx('ویرایش‌شده', 'edited'), style: const TextStyle(fontSize: 10, color: NxColors.textDim)),
            ),
          Text(orbitTime(m.createdAt), style: const TextStyle(fontSize: 10, color: NxColors.textDim)),
          if (mine) ...<Widget>[const SizedBox(width: 3), OrbitDeliveryIcon(delivery: m.delivery)],
        ]),
      ],
    );

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            decoration: BoxDecoration(
              gradient: mine
                  ? LinearGradient(colors: <Color>[
                      pal.primary.withValues(alpha: 0.32),
                      pal.secondary.withValues(alpha: 0.24),
                    ])
                  : null,
              color: mine ? null : const Color(0x1FFFFFFF),
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(18),
                topEnd: const Radius.circular(18),
                bottomStart: Radius.circular(mine ? 18 : 4),
                bottomEnd: Radius.circular(mine ? 4 : 18),
              ),
              border: Border.all(color: hl ? NxColors.gold : const Color(0x33FFFFFF), width: hl ? 1.6 : 1),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _ArtBody extends StatelessWidget {
  const _ArtBody({required this.assetRef});
  final String assetRef;

  @override
  Widget build(BuildContext context) {
    final ArtAsset? a = ArtAsset.parse(assetRef);
    if (a == null) return const Icon(Icons.image_not_supported_outlined);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 160,
        width: 220,
        decoration: const BoxDecoration(
          gradient: RadialGradient(colors: <Color>[Color(0x552EE6D6), Color(0x1100C2FF)]),
        ),
        padding: const EdgeInsets.all(10),
        child: Image.asset(
          a.path,
          cacheHeight: 320,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined),
        ),
      ),
    );
  }
}

/// Rich card for an item shared from another world.
class OrbitSharedCard extends StatelessWidget {
  const OrbitSharedCard({super.key, required this.payload, this.compact = false});
  final Map<String, dynamic> payload;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final SharedItem? item = SharedItem.fromJson(payload);
    if (item == null) return Text('${payload['text'] ?? ''}');
    if (item.type == SharedItem.gameInvite) return OrbitInviteCard(gameId: item.gameId ?? '', note: item.text);
    final bool nova = item.type == SharedItem.novaPost;
    final bool community = item.type == SharedItem.communityInvite;
    final Color accent = nova ? WorldPalette.nova.primary : (community ? WorldPalette.social.primary : NxColors.electricBlue);
    NovaVisual visual = NovaVisual.none;
    if (nova) {
      final String vk = '${item.extra['visual'] ?? 'none'}';
      final int g = (item.extra['gradient'] is num) ? (item.extra['gradient'] as num).toInt() : 0;
      final String asset = '${item.extra['asset'] ?? ''}';
      if (vk == NovaVisualKind.asset.name && ArtAsset.parse(asset) != null) {
        visual = NovaVisual(kind: NovaVisualKind.asset, gradient: g, asset: asset);
      } else {
        visual = NovaVisual(kind: NovaVisualKind.gradient, gradient: g);
      }
    }
    final String author = '${item.extra['author'] ?? item.extra['name'] ?? ''}';
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: const Color(0x22000000),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(children: <Widget>[
            Icon(nova ? Icons.auto_awesome : (community ? Icons.public_rounded : Icons.link_rounded), size: 16, color: accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                nova ? 'NOVA GALLERY' : (community ? 'SOCIAL STATION' : 'NEXORA'),
                style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2),
              ),
            ),
          ]),
        ),
        if (nova && !compact)
          NovaVisualView(visual: visual, caption: item.text.length <= 60 ? item.text : null, height: 110, radius: 0),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            if (author.isNotEmpty) Text(author, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            Text(item.text,
                maxLines: compact ? 2 : 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.35)),
          ]),
        ),
        TextButton.icon(
          onPressed: () => context.push(nova ? '/world/nova_gallery' : (community ? '/world/social_station' : '/hub')),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(nova
              ? context.tx('باز کردن در Nova', 'Open in Nova')
              : (community ? context.tx('باز کردن Social Station', 'Open Social Station') : context.tx('باز کردن', 'Open'))),
        ),
      ]),
    );
  }
}

/// Invite card that launches the Arcade game setup.
class OrbitInviteCard extends StatelessWidget {
  const OrbitInviteCard({super.key, required this.gameId, this.note = '', this.code = ''});
  final String gameId;
  final String note;

  /// Online room code: Play joins that real room.
  final String code;

  @override
  Widget build(BuildContext context) {
    final ArcadeGameRef? g = arcadeGame(gameId);
    final Color accent = WorldPalette.arcade.primary;
    return Container(
      width: 250,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: <Color>[Color(0x552A0B3A), Color(0x333A0F2A)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
        Row(children: <Widget>[
          Icon(Icons.sports_esports_rounded, color: accent, size: 18),
          const SizedBox(width: 6),
          Text('NEXORA ARCADE', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2)),
        ]),
        const SizedBox(height: 6),
        if (g != null)
          SizedBox(
            height: 96,
            child: Image.asset(
              AppAssets.pedestal(g.id),
              cacheHeight: 220,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(Icons.sports_esports_rounded, size: 48, color: accent),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          g == null ? context.tx('بازی ناشناخته', 'Unknown game') : context.tx('دعوت به ${g.nameFa}', 'Invite to ${g.nameEn}'),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        if (note.isNotEmpty)
          Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
        const SizedBox(height: 6),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: accent, padding: const EdgeInsets.symmetric(vertical: 10)),
          onPressed: g == null ? null : () => context.push(code.isEmpty ? '/arcade/${g.id}' : '/online/${g.id}?code=$code'),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(code.isEmpty ? context.tx('بازی کن', 'Play') : context.tx('ورود به اتاق $code', 'Join room $code')),
        ),
      ]),
    );
  }
}

/// A call started in this chat (kind = call). Join opens the real LiveKit call.
class OrbitCallCard extends StatelessWidget {
  const OrbitCallCard({super.key, required this.message, required this.mine});
  final OrbitMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final bool video = message.payload['video'] == true;
    final bool recent = DateTime.now().difference(message.createdAt).inMinutes < 30;
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Icon(video ? Icons.videocam_rounded : Icons.call_rounded, color: WorldPalette.orbit.primary),
      const SizedBox(width: 8),
      Text(
        mine
            ? (video
                ? context.tx('تماس تصویری گرفتی', 'You started a video call')
                : context.tx('تماس صوتی گرفتی', 'You started a voice call'))
            : (video ? context.tx('تماس تصویری', 'Video call') : context.tx('تماس صوتی', 'Voice call')),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      if (recent) ...<Widget>[
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => context.push(Uri(path: '/call/${message.chatId}', queryParameters: <String, String>{
            'call': '${message.payload['call'] ?? ''}',
            'video': video ? '1' : '0',
            'title': message.authorName,
          }).toString()),
          child: Text(context.tx('پیوستن', 'Join')),
        ),
      ],
    ]);
  }
}
