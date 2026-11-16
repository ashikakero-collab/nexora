# STEP_03 — معماری نرم‌افزار و قرارداد ماژول دنیاها

> مرحله 3 از ۳۰ | قبلی: [STEP_02 — CI/CD با GitHub Actions](STEP_02.md) | بعدی: [STEP_04 — سیستم طراحی (Design System)](STEP_04.md)

## ورودی (آنچه باید از قبل آماده باشد)
پروژه و CI سالم از STEP_01 و STEP_02 (پارامترهای P05، P06، P07).
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
طراحی معماری Clean و feature-first با یک قرارداد استاندارد که هر دنیا از آن پیروی کند.

## دستورالعمل‌ها
1. لایه‌ها: `core/` (مشترک)، `shared/` (ویجت و سرویس‌های مشترک)، `worlds/<world>/` با زیرلایه‌های `data / domain / presentation`.
2. اینترفیس `NexoraWorld` تعریف کن: id، نام، پالت بصری، مسیرهای route، `entryExperience`، `bootstrap()`، `dispose()`، و `capabilities` (برای ORACLE و جستجو).
3. یک `WorldRegistry` بساز که دنیاها را ثبت می‌کند؛ Hub و ORACLE از همین رجیستری می‌خوانند.
4. Riverpod را برای state، با تفکیک provider سطح برنامه و سطح دنیا تنظیم کن.
5. `go_router` با deep link، guard احراز هویت، و transition builder سفارشی (برای انتقال سینمایی بین دنیاها).
6. `EventBus` داخلی (typed) برای ارتباط بین دنیاها بنویس: مثلاً `SharePostToChat`, `InviteToGame`. دنیاها مستقیماً به هم import نمی‌کنند.

## تأکید گرافیک و معماری
تعامل میان دنیاها فقط از طریق Contract و EventBus است. رندر هر دنیا ایزوله است تا مشکل گرافیکی یک دنیا بقیه را نخواباند.

## خروجی‌های تحویلی
- ساختار کد و WorldRegistry
- EventBus و ناوبری
- docs/ARCHITECTURE.md با دیاگرام

## معیار پذیرش (Definition of Done)
- [ ] افزودن یک دنیای نمونه فقط با ثبت در Registry ممکن است
- [ ] هیچ import مستقیم بین worlds/* وجود ندارد (قانون lint)
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
قرارداد NexoraWorld و نحوه ثبت دنیا را دقیق در HANDOFF.md بنویس؛ STEP_04 تا آخر به آن تکیه دارند.
بعد از تأیید DoD، فایل `STEP_04.md` را باز کن.
