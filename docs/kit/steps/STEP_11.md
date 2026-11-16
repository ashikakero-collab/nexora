# STEP_11 — NEXORA HUB — ایستگاه مرکزی

> مرحله 11 از ۳۰ | قبلی: [STEP_10 — THE FIRST JOURNEY — سفر سینمایی اول](STEP_10.md) | بعدی: [STEP_12 — پوسته اصلی برنامه، جستجو، اعلان و تنظیمات](STEP_12.md)

## ورودی (آنچه باید از قبل آماده باشد)
WorldRegistry (STEP_03)، تم‌ها (STEP_04)، رندر (STEP_05)، سفر (STEP_10).
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
ساخت مرکز جهان: ایستگاه قابل‌تجربه با درگاه‌های ورود به دنیاها، بدون آسیب به سرعت دسترسی.

## دستورالعمل‌ها
1. صحنه Hub: ایستگاه، سیاره عظیم پشت پنجره‌های پانورامیک، حلقه‌های مداری، سکوهای شناور، میز فرمان مرکزی، هولوگرام‌ها.
2. هفت درگاه (Portal) برای هفت دنیا؛ هر یک از WorldRegistry خوانده می‌شود و با لمس انتقال سینمایی کوتاه به دنیا انجام می‌دهد.
3. **مسیر سریع موازی (Quick Access):** نوار/منوی استاندارد با میانبر همه قابلیت‌ها؛ کاربر هیچ‌وقت مجبور نیست در صحنه سه‌بعدی بگردد.
4. حالت 2D ساده Hub برای دستگاه ضعیف یا ترجیح کاربر (لیست/شبکه دنیاها با همان هویت بصری).
5. نمایش وضعیت زنده: اعلان‌ها، دوستان آنلاین، چالش روز، دعوت‌ها.
6. گوی ORACLE شناور به‌صورت placeholder قابل‌لمس که در STEP_27 فعال می‌شود.

## تأکید گرافیک و معماری
دوربین پویا با حرکت آرام (idle sway)، نورپردازی سینمایی، ذرات فضایی، و انتقال با تغییر پالت به رنگ دنیای مقصد. اصل: چشم‌نوازی بدون کندی؛ RenderProfile و حالت 2D الزامی‌اند.

## خروجی‌های تحویلی
- صحنه Hub
- Portalها و انتقال‌ها
- Quick Access
- حالت 2D

## معیار پذیرش (Definition of Done)
- [ ] همه ۷ درگاه از Registry کار می‌کنند (حتی با صفحه «به‌زودی» صادق)
- [ ] رسیدن به هر قابلیت از Quick Access ≤ ۲ لمس
- [ ] عملکرد مطابق P14
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
API ثبت درگاه و Quick Access را در HANDOFF.md بنویس؛ هر دنیای بعدی با ثبت در Registry در Hub ظاهر می‌شود.
بعد از تأیید DoD، فایل `STEP_12.md` را باز کن.

## دارایی‌های آماده برای این مرحله
(جزئیات: `03_ASSET_GUIDE.md` و `assets_manifest.json`)
- `assets/characters/oracle/poses/` (12): hero_wave, idle, calm, happy, present, confused …
- `assets/characters/oracle/emotes/` (7): hero_front, emote_idle, emote_smile, emote_point, emote_wave, emote_cheer …
- `assets/characters/oracle/` (1): hero_orbit
- `assets/worlds/hub/props/` (6): command_platform_octagon, command_platform_wide, command_desk_main, captain_chair_blue, captain_chair_navy, podium_hologram
- `assets/worlds/hub/portals/` (8): arcade_gate_large, nova_gallery, orbit_network, nexora_arcade, oracle_core, personal_orbit …
- `assets/worlds/hub/props/set/` (13): command_desk, holo_chamber, orbital_globe, holo_projector, comms_terminal, portal_door …
