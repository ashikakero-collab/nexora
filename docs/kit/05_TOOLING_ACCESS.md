# دسترسی ابزارها — Supabase، GitHub، LiveKit (ترمینال)

صاحب پروژه تأیید کرده که **ایجنت از داخل ترمینال به Supabase، LiveKit و GitHub دسترسی کامل دارد**. پس ایجنت باید هر کاری را خودش تا آخر انجام دهد و کار را نیمه‌کاره به صاحب پروژه برنگرداند: ساخت مخزن، migration، مستقر کردن توابع، تنظیم secret، اجرای workflow، دانلود artifact.

## قبل از هر کاری
```bash
supabase --version; gh --version; lk --version 2>/dev/null || livekit-cli --version
gh auth status; supabase projects list
```
اگر ابزاری نصب یا لاگین نبود، **خودت نصب/لاگین کن** (توکن‌ها در متغیرهای محیطی). اگر شبکه یا دسترسی نبود، دقیقاً خطا را در `docs/OPS_LOG.md` بنویس و فقط همان مورد را از صاحب پروژه بخواه.

## GitHub (gh)
```bash
gh repo create nexora --private --source=. --push
gh secret set ANDROID_KEYSTORE_B64 < <(base64 -w0 release.jks)
gh secret set SUPABASE_ACCESS_TOKEN --body "$SUPABASE_ACCESS_TOKEN"
gh workflow run build-android.yml && gh run watch
gh run download <run-id> -n app-release-apk -D build_out/
gh pr create --fill ; gh pr merge --squash
```
## Supabase (supabase CLI)
```bash
supabase login --token "$SUPABASE_ACCESS_TOKEN"
supabase init
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase migration new core_schema           # SQL در supabase/migrations
supabase db push                              # اعمال migrationها روی پروژه‌ی لینک‌شده
supabase functions deploy submit_shot
supabase secrets set LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=... LLM_API_KEY=...
supabase db dump --schema public > docs/schema_snapshot.sql
```
- فقط با **migration** اسکیما را تغییر بده (نه با ادیت دستی در داشبورد).
- `supabase start` به Docker نیاز دارد؛ اگر در محیط نیست، از یک پروژه‌ی **dev جدا** استفاده کن.
## LiveKit (lk)
```bash
lk cloud auth                                 # یا lk project add با URL/API key/secret
lk project list
lk room list ; lk token create --room test --identity dev --join
```
(پرچم‌ها ممکن است تغییر کنند؛ `lk --help` را بخوان.) کلید و secret فقط در `supabase secrets` ذخیره می‌شوند و Edge Function توکن کوتاه‌عمر می‌سازد. پیش از انتخاب پلن، هزینه/سقف را در `DECISIONS.md` ثبت کن.

## قواعد ایمنی عملیات
1. هرگز secret/token را در لاگ، commit، پیام یا فایل‌های مخزن چاپ نکن (`.env` در `.gitignore`؛ از `gh secret` و `supabase secrets` استفاده کن).
2. دو محیط جدا: `dev` (آزادانه تغییر بده) و `prod` (فقط با migration و بعد از پاس شدن تست‌ها).
3. این کارها **فقط با تأیید صریح صاحب پروژه**: حذف پروژه/دیتابیس prod، `db reset` روی prod، force-push روی main، چرخش keystore امضای منتشرشده (از دست رفتنش = از دست رفتن امکان آپدیت)، هر هزینه‌ی پولی.
4. هر فرمان مهم را با زمان و نتیجه در `docs/OPS_LOG.md` ثبت کن تا مرحله‌ی بعد/ایجنت بعدی بداند چه شده.
5. بعد از هر deploy، یک تست دودی (smoke test) بزن و نتیجه را ثبت کن.
6. کار را تا نتیجه‌ی واقعی ادامه بده: «کد نوشتم» کافی نیست؛ باید build سبز، migration اعمال‌شده، تابع مستقر‌شده و تست عبوری وجود داشته باشد.
