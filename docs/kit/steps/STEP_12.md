# STEP_12 — پوسته اصلی برنامه، جستجو، اعلان و تنظیمات

> مرحله 12 از ۳۰ | قبلی: [STEP_11 — NEXORA HUB — ایستگاه مرکزی](STEP_11.md) | بعدی: [STEP_13 — سیستم پیشرفت: XP، سطح، دستاورد، چالش](STEP_13.md)

## ورودی (آنچه باید از قبل آماده باشد)
Hub (STEP_11)، سیستم طراحی (STEP_04)، MotionPolicy/کیفیت (STEP_05)، جدول‌های notifications و user_settings (STEP_06).
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
ساخت اسکلت UI ثابت: ناوبری، جستجوی سراسری، مرکز اعلان و تنظیمات.

## دستورالعمل‌ها
1. پوسته: نوار ناوبری ثابت/شناور، دسترسی به Hub، Personal Orbit، ORACLE و اعلان‌ها از همه جا.
2. جستجوی سراسری که از `capabilities` دنیاها (STEP_03) تغذیه می‌شود؛ بعداً کاربران و محتوا هم اضافه می‌شوند.
3. مرکز اعلان: داخل‌برنامه + Push (FCM). ثبت device token، ترجیحات اعلان.
4. تنظیمات: کیفیت گرافیک، Reduced Motion، صدا، زبان (فارسی/English)، تم، حریم خصوصی، حساب، Replay سفر.
5. همگام‌سازی تنظیمات با سرور و ذخیره محلی.
6. صفحه‌های خطا/آفلاین/بروزرسانی اجباری.

## تأکید گرافیک و معماری
انتقال‌ها بین پوسته و دنیاها یکپارچه و کوتاه (≤ ۴۰۰ms) با پالت پویا. همه کنترل‌های دسترسی‌پذیری (کیفیت، کاهش حرکت، Skip) از اینجا در دسترس باشند.

## خروجی‌های تحویلی
- پوسته ناوبری
- جستجوی سراسری
- اعلان و تنظیمات

## معیار پذیرش (Definition of Done)
- [ ] تغییر کیفیت/Reduced Motion فوراً روی کل برنامه اثر می‌کند
- [ ] Push واقعی روی دستگاه دریافت می‌شود
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
نقاط افزونه (افزودن آیتم جستجو، نوع اعلان) را در HANDOFF.md ثبت کن.
بعد از تأیید DoD، فایل `STEP_13.md` را باز کن.

## دارایی‌های آماده برای این مرحله
(جزئیات: `03_ASSET_GUIDE.md` و `assets_manifest.json`)
- `assets/worlds/hub/portals/` (7): nova_gallery, orbit_network, nexora_arcade, oracle_core, personal_orbit, social_station …
- `assets/ui/holo_frames/` (10): holo_frame_01, holo_frame_02, holo_frame_03, holo_frame_04, holo_frame_05, holo_frame_06 …
- `assets/ui/kit/` (16): ui_element_01, ui_element_02, ui_element_03, ui_bar_04, ui_element_05, ui_icon_06 …
