# STEP_01 — پایه مخزن و پروژه Flutter

> مرحله 1 از ۳۰ | قبلی: — (اولین مرحله؛ ورودی: فایل‌های 00 و 01 و 02) | بعدی: [STEP_02 — CI/CD با GitHub Actions](STEP_02.md)

## ورودی (آنچه باید از قبل آماده باشد)
فایل‌های 00، 01 و 02 این بسته (پارامترهای P01، P02، P04).
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
ساخت اسکلت مخزن GitHub و پروژه Flutter با قراردادهای تیمی تا همه مراحل بعد روی پایه یکسان بسازند.

## دستورالعمل‌ها
1. مخزن را با ساختار `app/` (Flutter)، `supabase/` (migrations و functions)، `docs/`، `assets/`، `tools/` بساز.
2. پروژه Flutter را با نام بسته `com.nexora.universe` (قابل تغییر) فقط برای Android بساز و flavorهای `dev` و `prod` را تعریف کن.
3. lints سخت‌گیرانه (very_good_analysis یا مشابه) و فرمت‌دهی یکسان تنظیم کن.
4. `docs/UNDERSTANDING.md`، `PROGRESS.md`، `DECISIONS.md`، `HANDOFF.md` را بساز.
5. قرارداد شاخه‌ها و commit (Conventional Commits) و PR template را بنویس.
6. `.gitignore` را طوری تنظیم کن که هیچ کلید یا keystore وارد مخزن نشود.

## تأکید گرافیک و معماری
از همین مرحله ساختار assets را برای گرافیک آماده کن: `assets/{ui,worlds/<world>,games/<game>,audio,fonts,shaders,rive,lottie}` تا بعداً هر دنیا دارایی‌های مستقل داشته باشد.

## خروجی‌های تحویلی
- مخزن آماده و اولین commit
- پروژه Flutter که اجرا و analyze می‌شود
- چهار فایل docs

## معیار پذیرش (Definition of Done)
- [ ] `flutter analyze` و `flutter test` بدون خطا
- [ ] ساختار پوشه‌ها با P01-P02 مطابق است
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
مسیر پروژه، نام بسته و flavorها را در HANDOFF.md ثبت کن.
بعد از تأیید DoD، فایل `STEP_02.md` را باز کن.
