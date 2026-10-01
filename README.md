# স্বাস্থ্য ডায়েরি (Health Diary)

পরিবারের স্বাস্থ্য তথ্য এক জায়গায়। **একটি অ্যাপ, দুইটি রোল** — Google দিয়ে লগইনের পর বেছে নিন:

| রোল | কী করে |
|---|---|
| **রোগী / পরিবার** | প্রোফাইল (একাধিক সদস্য), ভিজিট, ওষুধ (ডোজ রিমাইন্ডার + শেষ হওয়ার সতর্কতা), টেস্ট, প্রেসক্রিপশনের ছবি, ফার্মেসিতে ওষুধ আছে কি না দেখা ও অনুরোধ পাঠানো |
| **ফার্মেসি মালিক** | দোকান নিবন্ধন (লাইসেন্সসহ যাচাই), স্টক (আছে/কম/নেই), রোগীর অনুরোধে উত্তর, আয়-ব্যয়, বাকির খাতা |

## ডাটা কোথায় থাকে

- **রোগীর স্বাস্থ্য তথ্য** (ভিজিট, ওষুধ, টেস্ট, ছবি) শুধু **ফোনের SQLite-এ**; ব্যাকআপ নিজের Google Drive-এর hidden app-data ফোল্ডারে (`drive.appdata` স্কোপ, শেষ ১০টি রাখা হয়)। আমাদের সার্ভারে যায় না।
- **Supabase** শুধু শেয়ার্ড অংশ: অ্যাকাউন্ট/রোল, ফার্মেসি, স্টক স্ট্যাটাস, অনুরোধ, মালিকের হিসাব। স্কিমা: [`supabase/schema.sql`](supabase/schema.sql) (সব টেবিলে RLS; রোগী দাম/পরিমাণ দেখতে পায় না, শুধু `search_stock()` RPC-এর `in/low/out`)।
- রিমাইন্ডার লোকাল নোটিফিকেশন, ইন্টারনেট ছাড়াই চলে।

## চালানোর ধাপ

1. Supabase প্রজেক্ট খুলে SQL editor-এ `supabase/schema.sql` চালান। Auth → Providers → Google চালু করুন।
2. Google Cloud Console-এ OAuth client বানান: **Web** client (এর ID-ই `GOOGLE_SERVER_CLIENT_ID`, Supabase-এও এটি দিন) এবং **Android** client (package `com.healthdiary.health_app` + SHA-1)। OAuth consent screen-এ `drive.appdata` স্কোপ যোগ করুন।
3. চালান:

```sh
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable/anon key> \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>.apps.googleusercontent.com
```

Supabase কনফিগার না থাকলে লগইন স্ক্রিনে **অফলাইন মোড** আসে (শুধু রোগী অংশ)।

4. ফার্মেসি যাচাই (অ্যাডমিন): `update public.pharmacies set status = 'verified' where id = '…';` — যাচাই না হওয়া পর্যন্ত রোগীরা দোকান দেখে না।

## কাঠামো

```
lib/
  core/       থিম (রোগী: টিল, মালিক: ইন্ডিগো), বাংলা সংখ্যা/তারিখ, শেয়ার্ড উইজেট
  data/       SQLite (রোগীর ডাটা) + মডেল
  services/   auth (Google→Supabase), নোটিফিকেশন, Drive ব্যাকআপ, অ্যাপ স্টেট
  features/
    auth/     অনবোর্ডিং, লগইন, রোল বাছাই
    patient/  হোম, ওষুধ, ভিজিট+টেস্ট, ফার্মেসি, সেটিংস
    owner/    রেজিস্ট্রেশন, হোম, অনুরোধ, স্টক, হিসাব+বাকি, প্রোফাইল
supabase/schema.sql
```

## এখনো করা হয়নি

OCR/AI প্রেসক্রিপশন স্ক্যান, PDF শেয়ার, ভাইটাল লগ, টিকা ট্র্যাকার, জরুরি কার্ড, ইংরেজি ভাষা, মালিকের জন্য বারকোড স্ক্যান / Excel ইমপোর্ট, নতুন অনুরোধের পুশ নোটিফিকেশন (এখন অ্যাপ খুললে দেখা যায়), iOS কনফিগ। লোকাল ডাটা অ্যাকাউন্ট-ভিত্তিক নয় — একই ফোনে অন্য Google অ্যাকাউন্টে ঢুকলে আগের ডাটা ফোনেই থাকে।
