# NEXORA — تجربه‌ی بازطراحی‌شده (NXG UI Refresh)

> NEXORA is a connected cosmic digital universe where social interaction, communication, gaming, AI, communities and personal digital identity exist together in one immersive experience.
> **YOUR UNIVERSE. YOUR IDENTITY. YOUR EXPERIENCE.**

اپ Flutter برای Android با مسیر ورود، هاب، آرکید، پروفایل، اجتماع و فروشگاه بازطراحی‌شده. پوسته‌ی سراسری بین دو سبک ذخیره‌شونده قابل انتخاب است: **Gold Luxe** (سرمه‌ای/طلایی) و **Cosmic Neon** (سرمه‌ای/نئون آبی و بنفش). بازی‌های محلی و بخش‌های آفلاین بدون اتصال در دسترس‌اند؛ امکانات آنلاین به اتصال شبکه نیاز دارند (راهنما: `docs/ONLINE_SETUP.md`).

## بازطراحی NX2 (شاخه‌ی online-redesign)
رابط کاربری کاملاً نو با هنر اختصاصی: پس‌زمینه‌ی قلعه‌ی کیهانی، پنل‌ها و دکمه‌های نئونی، داک پایین با گوی ORACLE،
ربات متحرک ORACLE با حالت‌های مختلف، صندوق‌های کمیابی در فروشگاه، جام‌ها در رتبه‌بندی و تورنمنت، موسیقی منو و ویدیوی آغاز.
جزئیات: `docs/REDESIGN.md`. هر push به `online-redesign` APKهای split-per-abi و universal را در Release (`redesign-vN`) منتشر می‌کند.

## دریافت APK
هر push به `main` ابتدا تحلیل Flutter و تست‌ها را اجرا می‌کند، سپس APK و Android App Bundle می‌سازد و امضای بسته/شناسه‌ی Android را بررسی می‌کند. دریافت در GitHub: تب **Actions** ← آخرین اجرای «NEXORA Android Build» ← **Artifacts** ← `NEXORA-release-builds`؛ در صورت موفقیت، فایل‌ها در یک prerelease خصوصی نیز پیوست می‌شوند.

- `NEXORA-NXG.apk`: فایل یکپارچه برای نصب مستقیم روی دستگاه Android.
- `NEXORA-NXG.aab`: بسته‌ی Android App Bundle؛ برای نصب مستقیم APK را بگیرید. انتشار در فروشگاه به upload-key تولیدیِ مالک نیاز دارد؛ کلید پایدار فعلی CI صرفاً برای نصب/تست است.

## آنچه در این نسخه هست
| بخش | وضعیت آفلاین |
|---|---|
| UI و تم‌ها | همه‌ی صفحات اپ با پوسته‌ی تیره‌ی طلایی یا نئون؛ انتخاب تم در تنظیمات ذخیره می‌شود. در فوتبال انگشتی فقط فیزیک، زمین، توپ و دیسک‌ها ثابت می‌مانند؛ HUD و تنظیمات نیز بازطراحی می‌شوند. |
| THE FIRST JOURNEY | سفر سینمایی ~۵۶ ثانیه، Skip، نسخه‌ی کوتاه، کاهش حرکت |
| هویت دیجیتال | Explorer ID، نام، آواتار، سطح/XP، سکه، دستاوردها — ذخیره روی گوشی |
| NEXORA HUB | حلقه‌ی مداری ۲.۵بعدی پورتال‌ها، جستجوی سراسری، منوی سریع، گوی ORACLE |
| NEXORA ARCADE | ۹ بازی: فوتبال انگشتی، کارم، بیلیارد، تخته‌نرد، لودو، مار و پله، کارت‌های NX (سبک UNO)، کوییز، مافیا |
| PERSONAL ORBIT | آواتار و کمد لباس، فضای شخصی با تزئین، دستاورد، آمار، فعالیت، جایزه‌ی روزانه و چالش‌ها |
| NEXORA EXCHANGE | فروشگاه شفاف با سکه‌ی داخلی (بدون قمار/جعبه‌ی شانسی) |
| ORACLE CORE | دستیار آفلاین فارسی/انگلیسی: راهنما، قوانین بازی‌ها، آمار، ناوبری و تغییر تنظیمات |
| NOVA GALLERY | پست، استوری، ریلز حرکتی، هشتگ، لایک/کامنت/ذخیره، جستجو |
| ORBIT NETWORK | چت ذخیره، گروه و کانال محلی، اشتراک از دنیاها، دعوت به بازی |
| SOCIAL STATION | اجتماعات، نقش‌ها، رویداد، مسابقه‌ی محلی با براکت |

آنچه واقعاً اینترنت لازم دارد (کاربران واقعی، تماس، بازی آنلاین، رتبه‌ی جهانی، مدل زبانی) در اپ با برچسب صادقانه «نیاز به اتصال آنلاین» مشخص است — هیچ چیز ساختگی نیست.

## ساختار
```
lib/
  app/            MaterialApp، روتر و انتقال‌های سینمایی
  core/           تم، تنظیمات، ذخیره‌ی محلی، هویت/پیشرفت، کاتالوگ، ویجت‌ها، درز بک‌اند
  games/          ۹ ماژول بازی (هر کدام core خالص Dart + ui) + قرارداد و رجیستری
  worlds/         journey، onboarding، hub، arcade و ۶ دنیای دیگر
assets/           ۲۳۰ دارایی گرافیکی WebP
supabase/         migrationها و Edge Function برای آنلاین شدن
docs/             کیت اصلی پروژه، راهنمای آنلاین، پیشرفت و تصمیم‌ها
.github/workflows ساخت APK
```

## توسعه
```bash
flutter create --platforms=android --org com.nexora --project-name nexora .   # یک‌بار، پوشه‌ی android
flutter pub get
flutter analyze && flutter test
flutter run
```
