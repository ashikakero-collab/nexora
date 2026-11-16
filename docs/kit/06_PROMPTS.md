# پرامپت‌های آماده — از توضیح تا نهایی شدن

## A) پرامپت شروع (Master Kickoff) — اولین پیامی که به ایجنت می‌دهی
```
تو ایجنت اصلی ساخت پروژه‌ی NEXORA هستی. محیط کاری: همین مخزن. ترمینال، GitHub (gh)، Supabase (supabase CLI) و LiveKit (lk) در اختیار تو است و باید همه‌ی کارها را خودت تا نتیجه‌ی واقعی انجام دهی.

1) به ترتیب بخوان و کامل بفهم: 00_START_HERE.md → 01_VISION_AND_CONTEXT.md → 02_ROADMAP_30_PARAMETERS.md → 03_ASSET_GUIDE.md → 04_FINGER_SOCCER_SPEC.md → 05_TOOLING_ACCESS.md.
2) خلاصه‌ی ۱۰ خطی درکت را در docs/UNDERSTANDING.md بنویس و ابهام‌های واقعی را (حداکثر ۵ سؤال کوتاه) بپرس؛ اگر ابهام جدی نیست ادامه بده.
3) دارایی‌های assets/ را به پروژه منتقل کن، کلاس AppAssets را از assets_manifest.json بساز.
4) steps/STEP_01 تا STEP_30 را دقیقاً به ترتیب اجرا کن. هر مرحله فقط وقتی تمام است که تمام موارد Definition of Done برقرار باشد. بعد از هر مرحله PROGRESS.md، DECISIONS.md، HANDOFF.md و OPS_LOG.md را به‌روز و commit/push کن.
5) هیچ قابلیت ساختگی (fake) نساز. ساخت APK/AAB فقط از GitHub Actions. اسرار را هرگز چاپ یا commit نکن.
6) پیش از شروع هر مرحله، HANDOFF.md مرحله‌ی قبل را بخوان.
7) هر وقت کار طولانی شد و context ات پر شد، وضعیت دقیق را در HANDOFF.md بنویس تا بتوانی با «پرامپت ادامه» ادامه دهی.
```

## B) پرامپت اجرای یک مرحله (جایگزین XX)
```
STEP_XX را اجرا کن. اول steps/STEP_XX.md و docs/HANDOFF.md را بخوان. همه‌ی دستورالعمل‌ها، بخش «تأکید گرافیک و معماری» و Definition of Done را انجام بده. تست بنویس و اجرا کن، GitHub Actions را سبز کن، فایل‌های docs را به‌روز کن، commit و push کن. در پایان گزارش کوتاه بده: چه ساخته شد، چه عددی اندازه‌گیری شد (FPS/حجم)، چه چیزی باز مانده. سپس منتظر دستور مرحله‌ی بعد نمان؛ اگر DoD کامل است مستقیم به مرحله‌ی بعد برو.
```

## C) پرامپت ادامه (بعد از قطع شدن یا پر شدن context)
```
docs/PROGRESS.md، DECISIONS.md، HANDOFF.md و OPS_LOG.md و git log -20 را بخوان. مشخص کن آخرین مرحله‌ی کامل کدام است و چه چیزی نیمه‌کاره مانده. همان‌جا ادامه بده؛ کار تمام‌شده را از نو نساز.
```

## D) پرامپت ممیزی (قبل از انتشار)
```
یک ممیزی کامل انجام بده: (1) هر قابلیت واقعی کار می‌کند یا ساختگی است؟ (2) RLS همه‌ی جدول‌ها و تست‌های امنیتی (3) ریشه‌یابی FPS/حافظه/حجم نسبت به بودجه‌ها (4) دسترسی‌پذیری و RTL (5) مجوز دارایی‌ها، به‌خصوص نشان‌های ملی و هر لوگو (6) نبودن secret در مخزن. گزارش را در docs/AUDIT.md بنویس و همه‌ی موارد بحرانی را همین‌جا رفع کن.
```

## E) پرامپت تولید دارایی‌های جدید (برای ابزار تصویرساز)
**لنگر سبک (به همه‌ی پرامپت‌ها اضافه کن):**
`cosmic navy and electric blue with violet and turquoise glow, brushed gunmetal armor with subtle gold trim, premium hybrid 3D game asset, clean readable silhouette, soft rim light, no text, no watermark, isolated on transparent or plain white background, consistent with NEXORA art direction`

| نیاز | پرامپت (به لنگر سبک اضافه کن) |
|---|---|
| پس‌زمینه‌ی Hub | `panoramic view from inside a huge space station through giant curved windows, enormous ringed planet, orbital rings, floating platforms, cinematic lighting, depth layers, 16:9` |
| لایه‌های parallax فضا | `seamless deep space layers: far stars, violet nebula, mid dust clouds, near sparkles, separate transparent layers` |
| داخل سفینه (Journey) | `luxury passenger starship interior corridor with large panoramic windows, space outside, warm and cool accent lights` |
| سیاره‌ها | `set of 6 stylized planets with atmosphere glow, different palettes, isolated, orthographic` |
| پاک top-down | `top-down orthographic view of a round game puck face only, flat front view, no side wall, [theme], metallic rim, NX monogram, square canvas` |
| UNO/کارت | `set of futuristic playing card faces and back with NX emblem, 4 colors, readable numbers, consistent frame` |
| تخته Ludo / مار و پله | `top-down premium game board, cosmic metal and glass frame, clear play areas, no pieces, square` |
| میز Mafia | `top-down dark mysterious round table with hologram candle, 10 seat positions, noir sci-fi mood` |
| آواتار پایه | `modular sci-fi explorer avatar body parts as separate layers, neutral pose, front view` |
| لوگو و آیکن | `app icon of letters NX with orbit ring and crown accent, gold and electric blue, rounded square, flat vector style` |

## F) نگاشت سریع: کدام دارایی در کدام مرحله
در انتهای هر فایل `steps/STEP_XX.md` بخش «دارایی‌های آماده» اضافه شده است.
