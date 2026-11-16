# STEP_13 — سیستم پیشرفت: XP، سطح، دستاورد، چالش

> مرحله 13 از ۳۰ | قبلی: [STEP_12 — پوسته اصلی برنامه، جستجو، اعلان و تنظیمات](STEP_12.md) | بعدی: [STEP_14 — PERSONAL ORBIT — فضای شخصی](STEP_14.md)

## ورودی (آنچه باید از قبل آماده باشد)
امنیت و RPCها (STEP_07)، پروفایل (STEP_06)، EventBus (STEP_03)، کامپوننت XP (STEP_04).
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
موتور پیشرفت واقعی و غیرقابل‌دستکاری برای همه دنیاها.

## دستورالعمل‌ها
1. جدول‌ها: `xp_events`، `achievements`، `user_achievements`، `challenges`، `user_challenges`، `badges`.
2. Edge Function/RPC `award_xp(event)` که رویدادهای معتبر را تأیید و XP می‌دهد؛ کلاینت فقط رویداد خام می‌فرستد.
3. فرمول Explorer Level، سقف روزانه XP و جلوگیری از تکرار/سوءاستفاده (idempotency key).
4. چالش‌های روزانه و هفتگی با زمان‌بندی سرور و بازنشانی خودکار (cron).
5. دستاوردها با شرایط قابل توسعه (JSON rule) تا هر دنیا شرط خودش را ثبت کند.
6. UI: نوار XP، اعلان level-up، صفحه دستاوردها و چالش‌ها.

## تأکید گرافیک و معماری
لحظه Level-up و دریافت دستاورد باید رضایت‌بخش بصری باشد (ذرات، نور، صدا) ولی کوتاه و قابل رد کردن. نمایش‌ها از RenderProfile پیروی می‌کنند.

## خروجی‌های تحویلی
- موتور پیشرفت سمت سرور
- UI پیشرفت
- تست سوءاستفاده

## معیار پذیرش (Definition of Done)
- [ ] کلاینت نمی‌تواند XP را مستقیم تغییر دهد (تست)
- [ ] رویداد تکراری XP دوبار حساب نمی‌شود
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
قرارداد ارسال رویداد پیشرفت (نام رویدادها) را در HANDOFF.md بنویس تا بازی‌ها و دنیاها از آن استفاده کنند.
بعد از تأیید DoD، فایل `STEP_14.md` را باز کن.

## دارایی‌های آماده برای این مرحله
(جزئیات: `03_ASSET_GUIDE.md` و `assets_manifest.json`)
- `assets/progression/achievements/` (15): badge_explorer, badge_gamer, badge_champion, badge_team, badge_legend, badge_idea …
- `assets/progression/club_badges/` (6): badge_club_scorpion, badge_club_wolf, badge_club_yakuza, badge_club_monster, badge_club_bermuda, badge_club_stone
