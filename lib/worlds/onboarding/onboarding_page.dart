import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets/app_assets.dart';
import '../../core/online/cloud_profile_sync.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';

/// Digital identity creation (STEP_08/09, offline guest identity).
/// Online later: the same identity is linked to a Supabase account.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _name = TextEditingController();
  String _avatar = 'hero_front';
  int _step = 0;

  static const _avatars = <String, String>{
    'hero_front': AppAssets.charactersOracleEmotesHeroFront,
    'emote_wave': AppAssets.charactersOracleEmotesEmoteWave,
    'emote_smile': AppAssets.charactersOracleEmotesEmoteSmile,
    'emote_cheer': AppAssets.charactersOracleEmotesEmoteCheer,
    'emote_point': AppAssets.charactersOracleEmotesEmotePoint,
    'emote_alert': AppAssets.charactersOracleEmotesEmoteAlert,
  };

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tx('نام کاربری حداقل ۲ حرف باشد',
              'Username must be at least 2 characters'))));
      return;
    }
    HapticFeedback.mediumImpact();
    final p = ref.read(profileProvider);
    await p.createIdentity(name: name, avatar: _avatar);
    final outcome = p.award('identity.created', xp: 50, coins: 0);
    ref.read(settingsProvider).markOnboarded();
    unawaited(ref.read(cloudSyncProvider).identityCreated());
    if (!mounted) return;
    await showAwardOutcome(context, outcome);
    if (mounted) context.go('/hub');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final p = ref.watch(profileProvider);
    return Scaffold(
      backgroundColor: NxThemeColors.of(context).background,
      body: NxBrandBackground(
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: NxMotion.slow,
            child: _step == 0 ? _language(s) : _identity(p),
          ),
        ),
      ),
    );
  }

  Widget _language(AppSettings s) {
    final visual = NxThemeColors.of(context);
    return Padding(
      key: const ValueKey('lang'),
      padding: const EdgeInsets.all(NxSpace.md),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                const SizedBox(height: NxSpace.lg),
                const OracleAvatar(pose: 'hero_wave', size: 200),
                const SizedBox(height: NxSpace.lg),
                Text(
                    context.tx('سلام اکتشافگر! من ORACLE هستم.',
                        'Hello Explorer! I am ORACLE.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 25,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                        color: visual.text)),
                const SizedBox(height: NxSpace.sm),
                Text(
                    context.tx(
                        'زبان خودت را انتخاب کن', 'Choose your language'),
                    style: TextStyle(color: visual.muted)),
                const SizedBox(height: NxSpace.lg),
                Row(children: [
                  Expanded(child: _langButton('fa', 'فارسی', s)),
                  const SizedBox(width: NxSpace.md),
                  Expanded(child: _langButton('en', 'English', s)),
                ]),
                const SizedBox(height: NxSpace.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => setState(() => _step = 1),
                    child: Text(context.tx('ادامه', 'Continue')),
                  ),
                ),
                const SizedBox(height: NxSpace.md),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _langButton(String code, String label, AppSettings s) {
    final visual = NxThemeColors.of(context);
    final selected = s.languageCode == code;
    return GlassPanel(
      onTap: () => s.languageCode = code,
      borderColor: selected ? visual.accent : null,
      tint: selected ? visual.accent.withValues(alpha: 0.15) : null,
      child: Center(
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (selected) ...[
            Icon(Icons.check_circle_rounded, color: visual.accent, size: 18),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: selected ? visual.accent : visual.text)),
        ]),
      ),
    );
  }

  Widget _identity(ProfileService p) {
    final visual = NxThemeColors.of(context);
    return ListView(
      key: const ValueKey('identity'),
      padding: const EdgeInsets.all(NxSpace.lg),
      children: [
        Text(context.tx('هویت دیجیتال تو', 'Your digital identity'),
            style: TextStyle(
                fontSize: 28,
                height: 1.15,
                fontWeight: FontWeight.w900,
                color: visual.text)),
        const SizedBox(height: 6),
        Text(
          context.tx('این هویت در همه‌ی دنیاهای NEXORA با تو است.',
              'This identity follows you across every NEXORA world.'),
          style: TextStyle(color: visual.muted, height: 1.45),
        ),
        const SizedBox(height: NxSpace.lg),
        GlassPanel(
          child: Row(children: [
            Icon(Icons.badge_rounded, color: visual.accent),
            const SizedBox(width: 10),
            Text('Explorer ID',
                style: const TextStyle(color: NxColors.textDim)),
            const Spacer(),
            Flexible(
                child: Text(p.explorerId,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: visual.accent))),
          ]),
        ),
        const SizedBox(height: NxSpace.md),
        TextField(
          controller: _name,
          maxLength: 20,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: context.tx('نام کاربری', 'Username'),
            prefixIcon: const Icon(Icons.alternate_email_rounded),
          ),
        ),
        const SizedBox(height: NxSpace.sm),
        Text(context.tx('ظاهر پایه‌ی آواتار', 'Avatar base look'),
            style: TextStyle(fontWeight: FontWeight.w800, color: visual.text)),
        const SizedBox(height: NxSpace.sm),
        SizedBox(
          height: 130,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final e in _avatars.entries)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _avatar = e.key),
                    child: AnimatedContainer(
                      duration: NxMotion.normal,
                      width: 100,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(NxRadius.md),
                        color: _avatar == e.key
                            ? visual.accent.withValues(alpha: 0.18)
                            : visual.surface,
                        border: Border.all(
                            color: _avatar == e.key
                                ? visual.accent
                                : visual.border.withValues(alpha: 0.6),
                            width: _avatar == e.key ? 2 : 1),
                      ),
                      child: Image.asset(e.value,
                          cacheHeight: 300, fit: BoxFit.contain),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: NxSpace.lg),
        GlassPanel(
          child: Row(children: [
            const Icon(Icons.cloud_done_rounded, color: NxColors.turquoise),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tx(
                    'با ورود، یک حساب مهمان آنلاین برایت ساخته می‌شود. بعداً از تنظیمات ← حساب کاربری می‌توانی ایمیل و رمز ثبت کنی یا وارد حساب قبلی‌ات شوی.',
                    'Entering creates an online guest account. Later, in Settings → Account, add email + password or sign in to an existing account.'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: NxSpace.lg),
        FilledButton.icon(
          onPressed: _finish,
          icon: const Icon(Icons.rocket_launch_rounded),
          label: Text(context.tx('ورود به NEXORA', 'Enter NEXORA')),
        ),
      ],
    );
  }
}
