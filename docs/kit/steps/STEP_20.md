# STEP_20 — بازی‌های فیزیکی: Carrom، Billiards و Finger Soccer

> مرحله 20 از ۳۰ | قبلی: [STEP_19 — بازی‌های نوبتی استراتژیک: UNO، Backgammon و Quiz](STEP_19.md) | بعدی: [STEP_21 — Mafia — بازی اجتماعی اطلاعات پنهان](STEP_21.md)

## ورودی (آنچه باید از قبل آماده باشد)
فیزیک و جزئیات چارچوب (STEP_16)، چندنفره (STEP_17)، شبکه‌سازی لحظه‌ای.
قبل از شروع `docs/HANDOFF.md` را بخوان و مطمئن شو معیار پذیرش مرحله قبل برقرار است.

## هدف
سه بازی لحظه‌ای/فیزیکی با بالاترین استاندارد گرافیک و حس بازی.

## دستورالعمل‌ها
1. انتخاب و بسته‌بندی موتور فیزیک (Forge2D/Flame) با شبیه‌سازی **قطعی (deterministic)** با گام ثابت تا نتیجه روی سرور و کلاینت قابل بازتولید باشد.
2. **Carrom:** تخته، مهره‌ها، قوانین رسمی/ساده‌شده، ضربه با کشیدن، سیستم امتیاز، آفلاین و آنلاین.
3. **Billiards:** 8-ball و در صورت امکان 9-ball، میز، ضربه با کنترل زاویه/قدرت/اسپین، قوانین خطا.
4. **Finger Soccer:** زمین، مهره‌ها، ضربه انگشتی، گل، نوبتی و/یا لحظه‌ای.
5. مدل شبکه: هر ضربه به‌صورت ورودی (زاویه، قدرت) به سرور می‌رود؛ سرور با همان شبیه‌سازی قطعی نتیجه را محاسبه/اعتبارسنجی می‌کند؛ کلاینت‌ها شبیه‌سازی را بازپخش می‌کنند.
6. بات با هدف‌گیری قابل‌تنظیم برای آفلاین.

## تأکید گرافیک و معماری
این سنگین‌ترین بخش گرافیکی بازی‌هاست: متریال واقعی (چوب، شیشه، فلز)، انعکاس و نور، سایه نرم، ذرات برخورد، دوربین پویا (zoom روی ضربه)، تراک ردپا (trail)، و صدای برخورد واقعی. بازی «اسباب‌بازی» نباشد.

## خروجی‌های تحویلی
- Carrom
- Billiards
- Finger Soccer
- فیزیک قطعی مشترک

## معیار پذیرش (Definition of Done)
- [ ] شبیه‌سازی روی دو دستگاه نتیجه یکسان می‌دهد (تست)
- [ ] حداقل 60fps در High میان‌رده
- [ ] `flutter analyze` و تست‌های این مرحله و مراحل قبل سبز است
- [ ] `PROGRESS.md`، `DECISIONS.md` و `HANDOFF.md` به‌روز شده‌اند
- [ ] هیچ بخش ساختگی (fake) در این مرحله وجود ندارد

## تحویل به مرحله بعد
ماژول فیزیک قطعی و مدل شبکه ضربه را در HANDOFF.md مستند کن.
بعد از تأیید DoD، فایل `STEP_21.md` را باز کن.

## دارایی‌های آماده برای این مرحله
(جزئیات: `03_ASSET_GUIDE.md` و `assets_manifest.json`)
- `assets/arcade/pedestals/` (9): carrom, finger_soccer, snakes_ladders, quiz, backgammon, billiards …
- `assets/games/carrom/` (2): board_nx_black_gold, board_classic_wood
- `assets/games/billiards/` (1): table_green
- `assets/games/shared/discs/` (32): disc_cream, disc_black, disc_red, disc_cream_crown, disc_black_crown, disc_red_crown …
- `assets/games/finger_soccer/pucks/iso/` (11): puck_frost_b_iso, puck_noble_lion_iso, puck_cosmic_crown_iso, puck_eagle_gold_iso, puck_nx_green_iso, puck_royal_lion_iso …
- `assets/games/finger_soccer/pucks/top/` (11): puck_frost_b_top, puck_noble_lion_top, puck_cosmic_crown_top, puck_eagle_gold_top, puck_nx_green_top, puck_royal_lion_top …
- `assets/games/finger_soccer/pucks/thumb/` (11): puck_frost_b_thumb, puck_noble_lion_thumb, puck_cosmic_crown_thumb, puck_eagle_gold_thumb, puck_nx_green_thumb, puck_royal_lion_thumb …
- `assets/games/finger_soccer/pucks_PLACEHOLDER_LICENSED/iso/` (6): puck_nat_spain_iso, puck_nat_portugal_iso, puck_nat_england_iso, puck_nat_japan_iso, puck_nat_france_iso, puck_nat_netherlands_iso
- `assets/games/finger_soccer/pucks_PLACEHOLDER_LICENSED/top/` (6): puck_nat_spain_top, puck_nat_portugal_top, puck_nat_england_top, puck_nat_japan_top, puck_nat_france_top, puck_nat_netherlands_top
- `assets/games/finger_soccer/pucks_PLACEHOLDER_LICENSED/thumb/` (6): puck_nat_spain_thumb, puck_nat_portugal_thumb, puck_nat_england_thumb, puck_nat_japan_thumb, puck_nat_france_thumb, puck_nat_netherlands_thumb
- `assets/games/finger_soccer/` (2): pitch, ball
- **نمونه‌ی مرجع کامل بازی فیزیکی:** `samples/finger_soccer/` و مشخصات در `04_FINGER_SOCCER_SPEC.md` (فیزیک قطعی، بات، آنلاین سرور-محور). Carrom و Billiards را با همان الگو بساز.
