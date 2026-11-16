import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/online/cloud_profile_sync.dart';
import '../../core/online/online_service.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';

String nxAuthError(BuildContext context, String? code) {
  switch (code) {
    case null:
      return '';
    case 'network':
      return context.tx(
          'اتصال به اینترنت برقرار نیست.', 'No internet connection.');
    case 'invalid_login':
      return context.tx(
          'ایمیل یا رمز عبور اشتباه است.', 'Wrong email or password.');
    case 'email_taken':
      return context.tx('این ایمیل قبلاً ثبت شده؛ از «ورود» استفاده کن.',
          'This email is already registered — use Sign in.');
    case 'weak_password':
      return context.tx('رمز عبور باید حداقل ۶ کاراکتر باشد.',
          'Password must be at least 6 characters.');
    case 'not_configured':
      return context.tx('این نسخه بدون سرور ساخته شده است.',
          'This build has no server configured.');
    default:
      return code;
  }
}

/// Compact account status card (Settings / Onboarding / Personal Orbit).
class AccountStatusCard extends ConsumerWidget {
  const AccountStatusCard({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OnlineService o = ref.watch(onlineProvider);
    final visual = NxThemeColors.of(context);
    final IconData icon;
    final Color color;
    final String title;
    final String sub;
    if (!o.configured) {
      icon = Icons.cloud_off_rounded;
      color = NxColors.gold;
      title = context.tx('حالت آفلاین', 'Offline build');
      sub = context.tx(
          'این نسخه بدون سرور است؛ همه‌چیز روی همین گوشی ذخیره می‌شود.',
          'This build has no server; everything is stored on this phone.');
    } else if (!o.isOnline) {
      icon = Icons.wifi_off_rounded;
      color = NxColors.gold;
      title = context.tx('در حال حاضر آفلاین', 'Offline right now');
      sub = context.tx(
          'پیشرفتت محلی ذخیره می‌شود و با اتصال دوباره همگام می‌شود.',
          'Progress is saved locally and syncs when you reconnect.');
    } else if (o.isGuest) {
      icon = Icons.person_outline_rounded;
      color = NxColors.turquoise;
      title = context.tx('آنلاین · حساب مهمان', 'Online · guest account');
      sub = context.tx('برای حفظ پیشرفت روی چند گوشی، ایمیل و رمز ثبت کن.',
          'Add email + password to keep your progress across phones.');
    } else {
      icon = Icons.verified_user_rounded;
      color = NxColors.success;
      title =
          context.tx('آنلاین · ${o.email ?? ''}', 'Online · ${o.email ?? ''}');
      sub = context.tx('پیشرفت، آیتم‌ها و دوستانت روی سرور همگام است.',
          'Progress, items and friends are synced.');
    }
    return GlassPanel(
      onTap: () => context.push('/account'),
      borderColor: color.withValues(alpha: 0.5),
      tint: color.withValues(alpha: 0.035),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    TextStyle(fontWeight: FontWeight.w800, color: visual.text)),
            if (!compact) ...[
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(
                      color: visual.muted, fontSize: 12, height: 1.4)),
            ],
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: NxColors.textDim),
      ]),
    );
  }
}

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  bool _signInMode = false;
  bool _obscure = true;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final OnlineService o = ref.read(onlineProvider);
    final String e = _email.text.trim();
    final String p = _pass.text;
    if (!e.contains('@') || p.length < 6) {
      setState(() => _info = context.tx(
          'ایمیل معتبر و رمز حداقل ۶ کاراکتری لازم است.',
          'A valid email and a 6+ character password are required.'));
      return;
    }
    setState(() => _info = null);
    bool ok;
    if (_signInMode) {
      if (o.isOnline && o.isGuest) {
        final bool? sure = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title:
                Text(ctx.tx('ورود به حساب دیگر', 'Sign in to another account')),
            content: Text(ctx.tx(
                'پیشرفت حساب مهمان فعلی با آن حساب ادغام نمی‌شود. اگر می‌خواهی همین پیشرفت را نگه داری، به‌جای ورود «ثبت‌نام» کن.',
                'This guest progress will not be merged into that account. To keep it, use Register instead.')),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(ctx.tx('انصراف', 'Cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.tx('ادامه', 'Continue'))),
            ],
          ),
        );
        if (sure != true) return;
      }
      ok = await o.signInEmail(e, p);
    } else {
      ok = await o.registerEmail(e, p,
          username: ref.read(profileProvider).username);
    }
    if (!mounted) return;
    setState(() => _info = ok
        ? context.tx('انجام شد ✓', 'Done ✓')
        : nxAuthError(context, o.lastError));
    if (ok) {
      _pass.clear();
      ref.read(cloudSyncProvider).start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final OnlineService o = ref.watch(onlineProvider);
    final ProfileService p = ref.watch(profileProvider);
    final visual = NxThemeColors.of(context);
    return NxWorldScaffold(
      title: context.tx('حساب کاربری', 'ACCOUNT'),
      palette: WorldPalette.hub,
      showWallet: false,
      body: ListView(
        padding: const EdgeInsets.all(NxSpace.md),
        children: <Widget>[
          const AccountStatusCard(),
          const SizedBox(height: NxSpace.md),
          GlassPanel(
            tint: visual.accent.withValues(alpha: 0.035),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                            colors: [visual.accent, visual.accentSecondary]),
                      ),
                      child: Icon(Icons.person_rounded,
                          color: visual.background, size: 27),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(p.username.isEmpty ? '—' : p.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: visual.text)),
                          Text('Explorer ID: ${p.explorerId}',
                              style:
                                  TextStyle(color: visual.muted, fontSize: 12)),
                        ])),
                  ]),
                  const SizedBox(height: 4),
                  if (o.uid != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 60),
                      child: Text('UID: ${o.uid!.substring(0, 8)}…',
                          style: TextStyle(color: visual.muted, fontSize: 12)),
                    ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                    NxPill(
                        label: 'XP ${p.xp}',
                        icon: Icons.bolt_rounded,
                        color: NxColors.electricBlue),
                    NxPill(
                        label: '${p.coins}',
                        icon: Icons.toll_rounded,
                        color: NxColors.gold),
                    NxPill(
                        label: context.tx('سطح ${p.level}', 'Level ${p.level}'),
                        icon: Icons.stars_rounded,
                        color: NxColors.violet),
                  ]),
                ]),
          ),
          const SizedBox(height: NxSpace.md),
          if (o.configured && !o.isOnline)
            FilledButton.icon(
              onPressed: o.busy
                  ? null
                  : () async {
                      await o.ensureSession();
                      ref.read(cloudSyncProvider).start();
                    },
              icon: const Icon(Icons.wifi_rounded),
              label: Text(context.tx('اتصال دوباره', 'Reconnect')),
            ),
          if (o.configured && (o.isGuest || !o.isOnline)) ...<Widget>[
            const SizedBox(height: NxSpace.sm),
            GlassPanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SegmentedButton<bool>(
                      segments: <ButtonSegment<bool>>[
                        ButtonSegment<bool>(
                            value: false,
                            label: Text(context.tx(
                                'ثبت‌نام / ارتقا', 'Register / upgrade'))),
                        ButtonSegment<bool>(
                            value: true,
                            label: Text(context.tx('ورود', 'Sign in'))),
                      ],
                      selected: <bool>{_signInMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (Set<bool> v) =>
                          setState(() => _signInMode = v.first),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _signInMode
                          ? context.tx(
                              'با ایمیل و رمز حسابی که قبلاً ساختی وارد شو.',
                              'Sign in with an account you already created.')
                          : context.tx(
                              'حساب مهمان فعلی‌ات با همین پیشرفت به حساب دائمی تبدیل می‌شود.',
                              'Your current guest account becomes permanent, keeping all progress.'),
                      style: const TextStyle(
                          color: NxColors.textDim, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                          labelText: context.tx('ایمیل', 'Email'),
                          prefixIcon:
                              const Icon(Icons.alternate_email_rounded)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _pass,
                      obscureText: _obscure,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: context.tx('رمز عبور', 'Password'),
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: o.busy ? null : _submit,
                      icon: o.busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(_signInMode
                              ? Icons.login_rounded
                              : Icons.verified_user_rounded),
                      label: Text(_signInMode
                          ? context.tx('ورود', 'Sign in')
                          : context.tx('ذخیره‌ی حساب', 'Save account')),
                    ),
                    if (_signInMode)
                      TextButton(
                        onPressed: o.busy
                            ? null
                            : () async {
                                if (!_email.text.contains('@')) return;
                                final bool ok =
                                    await o.resetPassword(_email.text);
                                if (!context.mounted) return;
                                setState(() => _info = ok
                                    ? context.tx(
                                        'لینک بازیابی به ایمیلت فرستاده شد.',
                                        'A reset link was sent to your email.')
                                    : nxAuthError(context, o.lastError));
                              },
                        child: Text(context.tx(
                            'رمز را فراموش کرده‌ام', 'Forgot password')),
                      ),
                    if (_info != null && _info!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(_info!,
                          style: const TextStyle(color: NxColors.gold)),
                    ],
                  ]),
            ),
          ],
          if (o.isOnline && !o.isGuest) ...<Widget>[
            const SizedBox(height: NxSpace.md),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout_rounded),
              label: Text(context.tx('خروج از حساب', 'Sign out')),
              onPressed: o.busy
                  ? null
                  : () async {
                      final bool? sure = await showDialog<bool>(
                        context: context,
                        builder: (BuildContext ctx) => AlertDialog(
                          title: Text(ctx.tx('خروج؟', 'Sign out?')),
                          content: Text(ctx.tx(
                              'پیشرفتت روی سرور امن است. بعد از خروج با یک حساب مهمان تازه ادامه می‌دهی.',
                              'Your progress is safe on the server. You continue with a fresh guest account.')),
                          actions: <Widget>[
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(ctx.tx('انصراف', 'Cancel'))),
                            FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(ctx.tx('خروج', 'Sign out'))),
                          ],
                        ),
                      );
                      if (sure == true) await o.signOut();
                    },
            ),
          ],
        ],
      ),
    );
  }
}
