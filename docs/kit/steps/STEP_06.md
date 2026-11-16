# STEP_06 — بک‌اند Supabase: اسکیمای هسته

> مرحله 6 از ۳۰ | قبلی: [STEP_05 — معماری گرافیک، کیفیت و استراتژی سه‌بعدی](STEP_05.md) | بعدی: [STEP_07 — امنیت: RLS، سیاست‌ها و قوانین سمت سرور](STEP_07.md)

## ورودی (آنچه باید از قبل آماده باشد)
قرارداد معماری (STEP_03) و پارامترهای P17، P18.
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
ساخت پایگاه داده پایه با migration نسخه‌دار برای هویت واحد و موجودیت‌های مشترک.

## دستورالعمل‌ها
1. پروژه Supabase و پوشه `supabase/migrations` با فایل‌های SQL شماره‌دار.
2. جدول‌ها: `profiles` (id=auth.users.id، explorer_id یکتا، username، display_name، avatar_config JSON، level، xp، created_at)، `friendships`، `blocks`، `notifications`، `device_tokens`، `user_settings`.
3. تابع تولید Explorer ID یکتا (قالب خوانا مثل NX-XXXX-XXXX) سمت دیتابیس.
4. ایندکس‌ها، قیدها (constraint) و trigger ساخت پروفایل بعد از ثبت‌نام.
5. برای هر دنیای بعدی جدول‌ها را **همین‌جا طراحی نکن**؛ هر مرحله migration خودش را اضافه می‌کند ولی از profiles به‌عنوان کلید اصلی هویت استفاده می‌کند.
6. سیدینگ (seed) برای محیط dev و اسکریپت reset.

## تأکید گرافیک و معماری
داده‌های گرافیکی کاربر (پیکربندی آواتار، تم فضای شخصی) را به‌صورت JSON نسخه‌دار ذخیره کن (`schema_version`) تا بعداً بدون شکستن کاربران قدیمی گسترش یابد.

## خروجی‌های تحویلی
- migrationهای هسته
- docs/DATA_MODEL.md با ERD
- seed dev

## معیار پذیرش (Definition of Done)
- [ ] اجرای migration روی پروژه تازه بدون خطا
- [ ] ثبت‌نام یک کاربر آزمایشی پروفایل با Explorer ID می‌سازد
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
نام جدول‌ها، ستون‌ها و توابع را در HANDOFF.md ثبت کن؛ STEP_07 روی همین‌ها RLS می‌گذارد.
بعد از تأیید DoD، فایل `STEP_07.md` را باز کن.

## ابزار ترمینال
GitHub (gh)، Supabase (supabase CLI) و LiveKit (lk) در دسترس‌اند؛ همه‌ی کارهای استقرار/secret/migration را خودت انجام بده. جزئیات و قواعد ایمنی: `05_TOOLING_ACCESS.md`.
