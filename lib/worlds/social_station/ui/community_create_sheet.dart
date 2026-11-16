import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../orbit_network/models/arcade_refs.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_widgets.dart';

class _EditorResult {
  const _EditorResult(this.community, this.outcome);
  final Community community;
  final AwardOutcome? outcome;
}

/// Opens the create (or edit, when [existing] is given) community sheet.
/// Returns the created/edited community, or null when cancelled.
Future<Community?> showCommunityEditor(BuildContext context, {Community? existing}) async {
  final _EditorResult? r = await showModalBottomSheet<_EditorResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xF20B2B33),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(NxRadius.lg))),
    builder: (BuildContext c) => _CommunityEditor(existing: existing),
  );
  if (r == null) return null;
  final AwardOutcome? o = r.outcome;
  if (o != null && context.mounted) await showAwardOutcome(context, o);
  return r.community;
}

class _CommunityEditor extends ConsumerStatefulWidget {
  const _CommunityEditor({this.existing});
  final Community? existing;

  @override
  ConsumerState<_CommunityEditor> createState() => _CommunityEditorState();
}

class _CommunityEditorState extends ConsumerState<_CommunityEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _rules = TextEditingController(text: (widget.existing?.rules ?? const <String>[]).join('\n'));
  late CommunityKind _kind = widget.existing?.kind ?? CommunityKind.public;
  late String _badge = widget.existing?.badgeId ?? kCommunityBadges.first;
  late String? _gameId = widget.existing?.gameId;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _rules.dispose();
    super.dispose();
  }

  bool get _needsGame => _kind == CommunityKind.game || _kind == CommunityKind.tournament;

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.length < 3) {
      socialSnack(context, 'نام جامعه باید دست‌کم ۳ حرف باشد.', 'The name needs at least 3 characters.');
      return;
    }
    if (_needsGame && _gameId == null) {
      socialSnack(context, 'یک بازی برای این جامعه انتخاب کن.', 'Pick a game for this community.');
      return;
    }
    setState(() => _busy = true);
    final SocialController ctrl = ref.read(socialControllerProvider);
    final SocialMe me = socialMe(ref);
    final List<String> rules = _rules.text.split('\n');
    final Community? existing = widget.existing;
    if (existing != null) {
      final bool ok = await ctrl.editInfo(existing.id, me.id,
          name: name, kind: _kind, badgeId: _badge, description: _desc.text, rules: rules, gameId: _needsGame ? _gameId : null);
      if (!mounted) return;
      if (!ok) {
        setState(() => _busy = false);
        socialSnack(context, 'فقط مالک و مدیران می‌توانند اطلاعات را ویرایش کنند.', 'Only the owner and admins can edit info.');
        return;
      }
      Navigator.of(context).pop(_EditorResult(ctrl.byId(existing.id) ?? existing, null));
      return;
    }
    final Community c = await ctrl.create(
      name: name,
      kind: _kind,
      badgeId: _badge,
      ownerId: me.id,
      ownerName: me.name,
      description: _desc.text,
      rules: rules,
      gameId: _needsGame ? _gameId : null,
    );
    final ProfileService profile = ref.read(profileProvider);
    profile.bump('social.joined');
    final AwardOutcome o = profile.award(
      'social.create',
      xp: 60,
      coins: 10,
      fa: 'جامعه «${c.name}» ساخته شد',
      en: 'Founded the community "${c.name}"',
    );
    if (!mounted) return;
    Navigator.of(context).pop(_EditorResult(c, o));
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.existing != null;
    final Color accent = kindColor(_kind);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.md, NxSpace.md, NxSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(color: NxColors.textDim, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: <Widget>[
            AnimatedSwitcher(
              duration: NxMotion.normal,
              child: CommunityBadge(key: ValueKey<String>(_badge), badgeId: _badge, size: 64, glow: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                editing ? context.tx('ویرایش جامعه', 'Edit community') : context.tx('جامعه تازه', 'New community'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            maxLength: 40,
            decoration: InputDecoration(labelText: context.tx('نام جامعه', 'Community name'), prefixIcon: const Icon(Icons.badge_rounded)),
          ),
          SocialSectionTitle(context.tx('نوع جامعه', 'Kind')),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            for (final CommunityKind k in CommunityKind.values)
              ChoiceChip(
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
                avatar: Icon(kindIcon(k), size: 16, color: _kind == k ? NxColors.navyDeep : kindColor(k)),
                label: Text(kindLabel(context, k)),
                selectedColor: kindColor(k),
                showCheckmark: false,
                labelStyle: TextStyle(color: _kind == k ? NxColors.navyDeep : NxColors.iceWhite, fontWeight: FontWeight.w700),
              ),
          ]),
          if (_kind == CommunityKind.private)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.tx('جامعه خصوصی فقط با کد دعوت قابل ورود است.', 'Private communities can only be joined with the invite code.'),
                style: const TextStyle(color: NxColors.textDim, fontSize: 12),
              ),
            ),
          if (_needsGame) ...<Widget>[
            SocialSectionTitle(context.tx('بازی اصلی', 'Main game')),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              for (final ArcadeGameRef g in kArcadeGames)
                ChoiceChip(
                  selected: _gameId == g.id,
                  onSelected: (_) => setState(() => _gameId = g.id),
                  label: Text(context.tx(g.nameFa, g.nameEn)),
                  selectedColor: kSocialPalette.secondary,
                  showCheckmark: false,
                  labelStyle: TextStyle(color: _gameId == g.id ? NxColors.navyDeep : NxColors.iceWhite, fontWeight: FontWeight.w700),
                ),
            ]),
          ],
          SocialSectionTitle(context.tx('نشان باشگاه', 'Club badge')),
          SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (final String b in kCommunityBadges)
                  GestureDetector(
                    onTap: () => setState(() => _badge = b),
                    child: AnimatedContainer(
                      duration: NxMotion.fast,
                      margin: const EdgeInsetsDirectional.only(end: 10),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _badge == b ? accent : Colors.transparent, width: 2.5),
                      ),
                      child: CommunityBadge(badgeId: b, size: 60, glow: _badge == b ? accent : NxColors.textDim),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _desc,
            maxLength: 240,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(labelText: context.tx('توضیح', 'Description'), prefixIcon: const Icon(Icons.notes_rounded)),
          ),
          TextField(
            controller: _rules,
            maxLines: 5,
            minLines: 2,
            decoration: InputDecoration(
              labelText: context.tx('قوانین (هر خط یک قانون)', 'Rules (one per line)'),
              prefixIcon: const Icon(Icons.gavel_rounded),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: NxColors.navyDeep,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _busy ? null : _save,
            icon: Icon(editing ? Icons.save_rounded : Icons.rocket_launch_rounded),
            label: Text(
              editing ? context.tx('ذخیره', 'Save') : context.tx('ساخت جامعه (+۶۰ XP)', 'Create community (+60 XP)'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ]),
      ),
    );
  }
}
