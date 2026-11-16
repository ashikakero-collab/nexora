# STEP_02 — CI/CD با GitHub Actions

> مرحله 2 از ۳۰ | قبلی: [STEP_01 — پایه مخزن و پروژه Flutter](STEP_01.md) | بعدی: [STEP_03 — معماری نرم‌افزار و قرارداد ماژول دنیاها](STEP_03.md)

## ورودی (آنچه باید از قبل آماده باشد)
مخزن و پروژه Flutter از STEP_01.
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
ساخت خودکار APK/AAB و اجرای تحلیل و تست با هر push تا کل چرخه از گوشی قابل کنترل باشد.

## دستورالعمل‌ها
1. workflow `ci.yml`: روی هر PR اجرای `flutter pub get`، analyze، test، و گزارش پوشش.
2. workflow `build-android.yml`: ساخت APK debug و release، و AAB برای release؛ آپلود artifact.
3. امضا: keystore را در GitHub Secrets (Base64) نگه دار و در workflow بازسازی کن؛ هرگز در مخزن نگذار.
4. نسخه‌دهی خودکار از روی tag (`vX.Y.Z`) و شماره build از `github.run_number`.
5. cache برای Gradle و pub تنظیم کن تا زمان build کم شود.
6. راهنمای `docs/BUILD.md` را بنویس که به زبان ساده بگوید چگونه از گوشی artifact را دانلود و نصب کنند.

## تأکید گرافیک و معماری
اسکریپتی در CI اضافه کن که اندازه APK را گزارش دهد و اگر از بودجه P15 بیشتر شد هشدار بدهد؛ بودجه حجم از روز اول کنترل می‌شود.

## خروجی‌های تحویلی
- workflowهای CI و Build
- docs/BUILD.md
- اولین APK قابل نصب با صفحه خالی NEXORA

## معیار پذیرش (Definition of Done)
- [ ] Push روی main یک APK قابل دانلود تولید می‌کند
- [ ] Secrets بدون نشت در لاگ‌ها
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
نام secrets مورد نیاز و مسیر artifact را در HANDOFF.md بنویس.
بعد از تأیید DoD، فایل `STEP_03.md` را باز کن.

## ابزار ترمینال
GitHub (gh)، Supabase (supabase CLI) و LiveKit (lk) در دسترس‌اند؛ همه‌ی کارهای استقرار/secret/migration را خودت انجام بده. جزئیات و قواعد ایمنی: `05_TOOLING_ACCESS.md`.
