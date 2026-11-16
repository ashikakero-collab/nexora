import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/catalog/catalog.dart';
import '../../../core/online/online_service.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import 'avatar_view.dart';
import 'po_common.dart';

/// Identity: avatar, name, Explorer ID, bio, rank, XP, join date.
class IdentityTab extends ConsumerWidget {
  const IdentityTab({super.key});

  Future<void> _editProfile(BuildContext context, ProfileService p) async {
    final TextEditingController name = TextEditingController(text: p.username);
    final TextEditingController bio = TextEditingController(text: p.bio);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(ctx.tx('ویرایش پروفایل', 'Edit profile')),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(
              controller: name,
              maxLength: 24,
              decoration:
                  InputDecoration(labelText: ctx.tx('نام کاربری', 'Username')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bio,
              maxLength: 160,
              maxLines: 3,
              decoration:
                  InputDecoration(labelText: ctx.tx('درباره‌ی من', 'Bio')),
            ),
          ]),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tx('ذخیره', 'Save'))),
        ],
      ),
    );
    if (ok == true) {
      await p.updateProfile(name: name.text, newBio: bio.text.trim());
    }
    name.dispose();
    bio.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final NxThemeColors visual = NxThemeColors.of(context);
    final String? frameId = p.equipped['frame'];
    final CatalogItem? frame = frameId == null ? null : catalogItem(frameId);
    final int gearCount =
        kAvatarSlots.where((String s) => p.equipped.containsKey(s)).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.xl),
      children: <Widget>[
        PoCard(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[visual.surfaceRaised, visual.surface],
          ),
          child: Column(children: <Widget>[
            const SizedBox(height: 8),
            const Center(child: OrbitAvatar(size: 190)),
            const SizedBox(height: 12),
            Text(
              p.username.isEmpty
                  ? context.tx('کاوشگر بی‌نام', 'Unnamed explorer')
                  : p.username,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: PoColors.ink(context)),
            ),
            const SizedBox(height: 4),
            Text(context.tx(p.rankTitleFa, p.rankTitleEn),
                style: TextStyle(
                    color: PoColors.lilac(context),
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _ExplorerIdChip(id: p.explorerId),
            const SizedBox(height: 12),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  NxPill(
                      label: poDigits(
                          context, '${context.tx('سطح', 'Level')} ${p.level}'),
                      icon: Icons.bolt_rounded,
                      color: PoColors.mint(context)),
                  NxPill(
                      label: poDigits(context, '${p.coins}'),
                      icon: Icons.toll_rounded,
                      color: const Color(0xFFD69A00)),
                  NxPill(
                      label: poDigits(context,
                          '${p.achievements.length} ${context.tx('دستاورد', 'badges')}'),
                      icon: Icons.emoji_events_rounded,
                      color: PoColors.lilac(context)),
                  if (frame != null)
                    NxPill(
                        label: context.tx(frame.nameFa, frame.nameEn),
                        icon: Icons.crop_square_rounded,
                        color: const Color(0xFF2F8CFF)),
                ]),
            const SizedBox(height: 8),
          ]),
        ),
        const SizedBox(height: NxSpace.md),
        // XP on a dark card so the shared XpBar keeps its intended contrast.
        Container(
          padding: const EdgeInsets.all(NxSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NxRadius.lg),
            gradient: LinearGradient(
                colors: <Color>[visual.backgroundMid, visual.surfaceRaised]),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                  color: Color(0x332A1E6E),
                  blurRadius: 18,
                  offset: Offset(0, 6))
            ],
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: NxColors.iceWhite),
            child: Theme(
              data: ThemeData.dark(useMaterial3: true),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: NxColors.iceWhite),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const XpBar(height: 12),
                      const SizedBox(height: 10),
                      Text(
                        poDigits(
                            context,
                            context.tx('کل امتیاز تجربه: ${p.xp} XP',
                                'Total experience: ${p.xp} XP')),
                        style: TextStyle(color: visual.muted, fontSize: 12),
                      ),
                    ]),
              ),
            ),
          ),
        ),
        PoSectionTitle(context.tx('درباره‌ی من', 'About me'),
            icon: Icons.person_rounded,
            trailing: TextButton.icon(
              onPressed: () => _editProfile(context, p),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: Text(context.tx('ویرایش', 'Edit')),
            )),
        PoCard(
          onTap: () => _editProfile(context, p),
          child: Text(
            p.bio.isEmpty
                ? context.tx('هنوز چیزی ننوشته‌ای. برای نوشتن بیوگرافی بزن.',
                    'No bio yet. Tap to write one.')
                : p.bio,
            style: TextStyle(
                color: p.bio.isEmpty
                    ? PoColors.inkDim(context)
                    : PoColors.ink(context),
                height: 1.5),
          ),
        ),
        PoSectionTitle(context.tx('اطلاعات حساب', 'Account'),
            icon: Icons.info_outline_rounded),
        PoCard(
          child: Column(children: <Widget>[
            _InfoRow(
                icon: Icons.event_rounded,
                label: context.tx('تاریخ پیوستن', 'Joined'),
                value: poDate(context, p.createdAt)),
            _InfoRow(
                icon: Icons.local_fire_department_rounded,
                label: context.tx('رکورد روزانه', 'Daily streak'),
                value: poDigits(context,
                    context.tx('${p.streak} روز', '${p.streak} days'))),
            _InfoRow(
                icon: Icons.sports_esports_rounded,
                label: context.tx('مسابقه‌ها', 'Matches'),
                value: poDigits(context, '${p.totalGamesPlayed}')),
            _InfoRow(
                icon: Icons.checkroom_rounded,
                label: context.tx('تجهیزات پوشیده', 'Gear equipped'),
                value: poDigits(context, '$gearCount/${kAvatarSlots.length}')),
            _InfoRow(
                icon: Icons.inventory_2_rounded,
                label: context.tx('آیتم‌های مالکیت', 'Items owned'),
                value: poDigits(context, '${p.inventory.length}')),
          ]),
        ),
        PoSectionTitle(context.tx('میانبرها', 'Quick links'),
            icon: Icons.bolt_rounded),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          ActionChip(
            avatar: const Icon(Icons.storefront_rounded, size: 18),
            label: Text(context.tx('NEXORA Exchange', 'NEXORA Exchange')),
            onPressed: () => context.push('/world/nexora_exchange'),
          ),
          ActionChip(
            avatar: const Icon(Icons.sports_esports_rounded, size: 18),
            label: Text(context.tx('آرکید', 'Arcade')),
            onPressed: () => context.push('/world/nexora_arcade'),
          ),
          ActionChip(
            avatar: const Icon(Icons.settings_rounded, size: 18),
            label: Text(context.tx('تنظیمات', 'Settings')),
            onPressed: () => context.push('/settings'),
          ),
        ]),
        PoSectionTitle(context.tx('دوستان', 'Friends'),
            icon: Icons.group_rounded),
        Theme(
          data: ThemeData.dark(useMaterial3: true),
          child: Container(
            decoration: BoxDecoration(
                color: NxColors.navy,
                borderRadius: BorderRadius.circular(NxRadius.lg)),
            child: ref.watch(onlineProvider).isOnline
                ? ListTile(
                    leading: Icon(Icons.group_rounded, color: visual.accent),
                    title: Text(context.tx('دوستان، درخواست‌ها و جستجو',
                        'Friends, requests and search')),
                    subtitle: Text(context.tx('در ORBIT NETWORK › مخاطبان',
                        'In ORBIT NETWORK › Contacts')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/world/orbit_network'),
                  )
                : const OnlineOnlyNotice(
                    featureFa: 'فهرست دوستان', featureEn: 'The friends list'),
          ),
        ),
      ],
    );
  }
}

class _ExplorerIdChip extends StatelessWidget {
  const _ExplorerIdChip({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x147B5CE6),
      borderRadius: BorderRadius.circular(40),
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: id));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    context.tx('Explorer ID کپی شد', 'Explorer ID copied'))),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Icon(Icons.fingerprint_rounded,
                  size: 18, color: PoColors.lilac(context)),
              const SizedBox(width: 6),
              Text(id,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      color: PoColors.ink(context),
                      fontFamily: 'monospace')),
              const SizedBox(width: 8),
              Icon(Icons.copy_rounded,
                  size: 16, color: PoColors.inkDim(context)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: <Widget>[
        Icon(icon, size: 18, color: PoColors.lilac(context)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Text(label, style: TextStyle(color: PoColors.inkDim(context)))),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w800, color: PoColors.ink(context))),
      ]),
    );
  }
}
