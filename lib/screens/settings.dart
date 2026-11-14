// Port of src/screens/Settings.tsx + Account.tsx: online account (guest/email, sign up/in, upgrade, reset,
// sign out, username), audio/haptics/Oracle toggles, volume, graphics quality (High / Smooth), bot level,
// language, FPS/latency debug overlay, replay intro, reset progress. Plus the password-recovery card.
import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../online/ui.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';

class SettingsSheet extends StatefulWidget {
  final VoidCallback replayIntro;
  const SettingsSheet({super.key, required this.replayIntro});
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  bool sure = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (_, __) {
          final p = Store.i.p;
          Widget toggle(String img, String n, String d, bool v, void Function(Profile, bool) set) => Panel(
                margin: const EdgeInsets.only(bottom: 10),
                accent: Colors.transparent,
                child: Row(textDirection: TextDirection.rtl, children: [
                  Img(img, w: 44, h: 44),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [tBold(n, size: 15), T(d, size: 11, color: C.dim)])),
                  Toggle(on: v, onChange: (x) => Store.i.set((q) => set(q, x))),
                ]),
              );
          Widget seg(String title, String? sub, Widget s) => Panel(
                margin: const EdgeInsets.only(bottom: 10),
                accent: Colors.transparent,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  tBold(title, size: 15, align: TextAlign.right),
                  if (sub != null) T(sub, size: 11, color: C.dim, align: TextAlign.right),
                  const SizedBox(height: 8),
                  s,
                ]),
              );
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
            const AccountPanel(),
            toggle(kit('mega'), 'صداها', 'ضربه، گل، تماشاگر', p.sound, (q, v) => q.sound = v),
            toggle(kit('bell'), 'موسیقی', 'موسیقی منو', p.music, (q, v) => q.music = v),
            toggle(kit('gear'), 'لرزش', 'بازخورد لمسی هنگام برخورد', p.haptics, (q, v) => q.haptics = v),
            toggle(oracleImg('idle'), 'نمایش اوراکل', 'دستیار شناور، مربی بازی و راهنما', p.oracle, (q, v) => q.oracle = v),
            seg('بلندی صدا', null, Segment<double>(value: p.volume, onChange: (v) => Store.i.set((q) => q.volume = v), items: const [(.25, '۲۵٪'), (.5, '۵۰٪'), (.75, '۷۵٪'), (1.0, '۱۰۰٪')])),
            seg('کیفیت گرافیک', 'روی گوشی‌های ضعیف «روان» را انتخاب کن (بدون سایه، ستاره و ذرات اضافه)',
                Segment<String>(value: p.quality, onChange: (v) => Store.i.set((q) => q.quality = v), items: const [('high', 'بالا'), ('low', 'روان')], accent: C.violet)),
            seg('سختی پیش‌فرض ربات', null, Segment<int>(value: p.aiLvl, onChange: (v) => Store.i.set((q) => q.aiLvl = v), items: const [(0, 'آسان'), (1, 'معمولی'), (2, 'سخت')])),
            seg('زبان منو', 'Language of navigation labels', Segment<String>(value: p.lang, onChange: (v) => Store.i.set((q) => q.lang = v), items: const [('fa', 'فارسی'), ('en', 'English')], accent: C.green)),
            toggle(kit('tactics'), 'نمایش FPS و تأخیر', 'برای عیب‌یابی: نرخ فریم، زمان شبیه‌سازی و پینگ آنلاین', p.debugOverlay, (q, v) => q.debugOverlay = v),
            const SizedBox(height: 8),
            Btn('پخش دوباره‌ی اینترو', small: true, colors: G.dark, onTap: widget.replayIntro),
            const SizedBox(height: 10),
            Btn(sure ? 'مطمئنی؟ دوباره بزن' : 'پاک کردن پیشرفت', small: true, colors: G.red, onTap: () {
              if (!sure) {
                setState(() => sure = true);
                return;
              }
              Store.i.reset();
              setState(() => sure = false);
              toast('پیشرفت پاک شد', 'ok');
            }),
            const SizedBox(height: 24),
            const T('NEXORA · Finger Soccer · v4 (Flutter 0.4.0)', size: 10, family: F.head, weight: 700, spacing: 2, color: C.dim2, align: TextAlign.center),
          ]);
        },
      );
}

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key});
  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  String mode = 'up';
  final email = TextEditingController(), pass = TextEditingController(), pass2 = TextEditingController(), name = TextEditingController();
  bool editName = false, busy = false, sureOut = false;
  String? sent, err;

  bool done(Res r, [String? ok]) {
    if (!r.ok) {
      setState(() => err = r.error ?? 'خطا');
      buzz('heavy');
      return false;
    }
    setState(() => err = null);
    if (ok != null) toast(ok, 'ok');
    buzz('success');
    return true;
  }

  Future<void> submit() async {
    final a = Auth.i;
    setState(() => err = null);
    if (!_emailRe.hasMatch(email.text.trim())) return setState(() => err = 'ایمیل معتبر نیست');
    if (mode != 'forgot' && pass.text.length < 6) return setState(() => err = 'رمز عبور حداقل ۶ کاراکتر');
    if (mode == 'up' && pass.text != pass2.text) return setState(() => err = 'تکرار رمز عبور یکسان نیست');
    setState(() => busy = true);
    try {
      if (mode == 'forgot') {
        if (done(await a.resetPassword(email.text))) setState(() => sent = 'reset');
      } else if (mode == 'in') {
        if (done(await a.signIn(email.text, pass.text), 'وارد شدی')) pass.clear();
      } else if (a.uid != null && a.isGuest) {
        if (done(await a.upgrade(email.text, pass.text))) setState(() => sent = 'upgrade');
      } else {
        final r = await a.signUp(email.text, pass.text);
        if (done(r)) setState(() => sent = r.info == 'confirm' ? 'confirm' : null);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Auth.i,
        builder: (_, __) {
          final a = Auth.i, pr = a.profile;
          final signedEmail = a.uid != null && !a.isGuest;
          return Panel(
            margin: const EdgeInsets.only(bottom: 10),
            accent: C.cyan,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(textDirection: TextDirection.rtl, children: [
                pr != null ? Avatar(avatar: pr.str('equipped_disc') ?? pr.str('avatar'), url: pr.str('avatar_url'), size: 48) : Img(kit('profile'), w: 44, h: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    tBold('حساب آنلاین', size: 15),
                    T(a.uid == null ? 'وارد نشده‌ای' : a.isGuest ? 'مهمان · ${pr?.s('username') ?? ''}' : '${a.email} · ${pr?.s('username') ?? ''}', size: 11, color: C.dim, lines: 1),
                  ]),
                ),
                if (pr != null) tBold('سطح ${fa(pr.i('level'))}', size: 11, color: C.gold),
              ]),
              if (pr != null)
                editName
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(children: [
                          Field2(name, label: 'نام کاربری جدید (۳ تا ۲۰ کاراکتر)', maxLength: 20),
                          Row(textDirection: TextDirection.rtl, children: [
                            Expanded(
                                child: Btn(busy ? '…' : 'ذخیره', small: true, disabled: busy, onTap: () async {
                              setState(() => busy = true);
                              final r = await a.setUsername(name.text);
                              setState(() => busy = false);
                              if (done(r, 'نام کاربری تغییر کرد')) setState(() => editName = false);
                            })),
                            const SizedBox(width: 8),
                            Expanded(child: Btn('انصراف', small: true, colors: G.dark, onTap: () => setState(() => editName = false))),
                          ]),
                        ]),
                      )
                    : Press(
                        onTap: () => setState(() {
                              name.text = pr.s('username');
                              editName = true;
                            }),
                        child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: T('✎ تغییر نام کاربری', size: 12, color: C.cyan, align: TextAlign.right))),
              if (sent != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0x143dffa8), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.green.withValues(alpha: .33))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    T(
                        sent == 'reset'
                            ? 'لینک تغییر رمز به ایمیلت فرستاده شد. لینک را روی همین گوشی باز کن تا رمز جدید را این‌جا وارد کنی.'
                            : sent == 'upgrade'
                                ? 'لینک تأیید به ایمیلت فرستاده شد. بعد از باز کردن لینک، حساب مهمانت با همه‌ی پیشرفت‌ها به ایمیل وصل می‌شود.'
                                : 'حسابت ساخته شد! لینک تأیید را در ایمیلت باز کن، سپس وارد شو.',
                        size: 12,
                        height: 1.7),
                    const SizedBox(height: 8),
                    Row(textDirection: TextDirection.rtl, children: [
                      if (sent == 'confirm') Expanded(child: Btn('ارسال دوباره', small: true, colors: G.dark, onTap: () async => done(await a.resend(email.text), 'دوباره فرستاده شد'))),
                      if (sent == 'confirm') const SizedBox(width: 8),
                      Expanded(
                          child: Btn('باشه', small: true, onTap: () => setState(() {
                                if (sent == 'confirm') mode = 'in';
                                sent = null;
                              }))),
                    ]),
                  ]),
                )
              else if (!signedEmail) ...[
                const SizedBox(height: 12),
                Segment<String>(value: mode, onChange: (v) => setState(() {
                      mode = v;
                      err = null;
                    }), items: [('up', a.isGuest ? 'ثبت ایمیل' : 'ثبت‌نام'), ('in', 'ورود'), ('forgot', 'فراموشی رمز')]),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: T(
                      mode == 'up'
                          ? (a.isGuest ? 'با ثبت ایمیل، پیشرفت حساب مهمان حفظ می‌شود و روی هر گوشی وارد می‌شوی.' : 'حساب بساز تا پیشرفتت روی سرور ذخیره شود.')
                          : mode == 'in'
                              ? (a.isGuest ? 'ورود به حساب دیگر، حساب مهمان فعلی را کنار می‌گذارد.' : 'با ایمیل و رمز وارد شو.')
                              : 'ایمیلت را وارد کن تا لینک تغییر رمز برایت فرستاده شود.',
                      size: 11,
                      color: C.dim,
                      height: 1.6),
                ),
                Field2(email, hint: 'ایمیل', ltr: true, kb: TextInputType.emailAddress),
                if (mode != 'forgot') Field2(pass, hint: 'رمز عبور', ltr: true, secure: true),
                if (mode == 'up') Field2(pass2, hint: 'تکرار رمز عبور', ltr: true, secure: true),
                if (err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: T(err!, size: 12, color: C.red, align: TextAlign.right)),
                Btn(busy ? 'لطفاً صبر کن…' : mode == 'up' ? (a.isGuest ? 'ثبت ایمیل و حفظ پیشرفت' : 'ساخت حساب') : mode == 'in' ? 'ورود' : 'ارسال لینک', small: true, onTap: submit, disabled: busy),
                if (a.uid == null) ...[
                  const SizedBox(height: 8),
                  Btn('ادامه به‌عنوان مهمان', small: true, colors: G.dark, onTap: () async {
                    setState(() => busy = true);
                    try {
                      await a.ensure();
                      toast('به‌عنوان مهمان وارد شدی', 'ok');
                    } catch (_) {
                      toast('اتصال برقرار نشد', 'err');
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  }),
                ],
              ] else if (err != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: T(err!, size: 12, color: C.red, align: TextAlign.right)),
              if (a.uid != null) ...[
                const SizedBox(height: 12),
                Btn(sureOut ? (a.isGuest ? 'پیشرفت مهمان از دست می‌رود! دوباره بزن' : 'مطمئنی؟ دوباره بزن') : 'خروج از حساب', small: true, colors: G.red, onTap: () async {
                  if (!sureOut) return setState(() => sureOut = true);
                  setState(() => sureOut = false);
                  await a.signOut();
                  toast('از حساب خارج شدی', 'ok');
                }),
              ],
            ]),
          );
        },
      );
}

Future<void> showRecovery(BuildContext context) => showCard(context, accent: C.cyan, child: (ctx) => const _Recovery());

class _Recovery extends StatefulWidget {
  const _Recovery();
  @override
  State<_Recovery> createState() => _RecoveryState();
}

class _RecoveryState extends State<_Recovery> {
  final p1 = TextEditingController(), p2 = TextEditingController();
  String? err;
  bool busy = false;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tTitle('رمز عبور جدید', size: 20, align: TextAlign.center),
          const SizedBox(height: 12),
          Field2(p1, hint: 'رمز جدید', ltr: true, secure: true),
          Field2(p2, hint: 'تکرار رمز جدید', ltr: true, secure: true),
          if (err != null) T(err!, size: 12, color: C.red, align: TextAlign.right),
          Btn(busy ? '…' : 'ذخیره', disabled: busy, onTap: () async {
            if (p1.text.length < 6) return setState(() => err = 'رمز عبور حداقل ۶ کاراکتر');
            if (p1.text != p2.text) return setState(() => err = 'تکرار رمز یکسان نیست');
            setState(() => busy = true);
            final r = await Auth.i.setNewPassword(p1.text);
            if (!mounted) return;
            setState(() => busy = false);
            if (!r.ok) return setState(() => err = r.error);
            toast('رمز عبور تغییر کرد', 'ok');
            Navigator.pop(context);
          }),
          const SizedBox(height: 8),
          Btn('بعداً', small: true, colors: G.dark, onTap: () {
            Auth.i.endRecovery();
            Navigator.pop(context);
          }),
        ]),
      );
}
