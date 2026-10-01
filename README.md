# স্বাস্থ্য ডায়েরি (Health Diary)

পরিবারের স্বাস্থ্য তথ্য এক জায়গায়। **একটি অ্যাপ, দুইটি রোল** — Google দিয়ে লগইনের পর বেছে নিন:

| রোল | কী করে |
|---|---|
| **রোগী / পরিবার** | প্রোফাইল (একাধিক সদস্য), ভিজিট, ওষুধ (ডোজ রিমাইন্ডার + শেষ হওয়ার সতর্কতা), টেস্ট, প্রেসক্রিপশনের ছবি, ফার্মেসিতে ওষুধ আছে কি না দেখা ও অনুরোধ পাঠানো |
| **ফার্মেসি মালিক** | দোকান নিবন্ধন (লাইসেন্সসহ যাচাই), স্টক (আছে/কম/নেই), রোগীর অনুরোধে উত্তর, আয়-ব্যয়, বাকির খাতা |

## ডাটা কোথায় থাকে

- **রোগীর স্বাস্থ্য তথ্য** (ভিজিট, ওষুধ, টেস্ট, ছবি) শুধু **ফোনের SQLite-এ**; ব্যাকআপ নিজের Google Drive-এর hidden app-data ফোল্ডারে (`drive.appdata` স্কোপ, শেষ ১০টি রাখা হয়)। আমাদের সার্ভারে যায় না।
- **Firebase (Spark / ফ্রি প্ল্যান)** শুধু শেয়ার্ড অংশ: Auth (Google), Firestore-এ রোল, ফার্মেসি, স্টক স্ট্যাটাস, অনুরোধ, মালিকের হিসাব। Firebase ফ্রি প্ল্যানে প্রজেক্ট নিষ্ক্রিয় থাকলেও **ঘুমিয়ে/পজ হয় না**। নিয়ম: [`firebase/firestore.rules`](firebase/firestore.rules)।
- গোপনীয়তা: দাম/পরিমাণ/ব্যাচ থাকে `pharmacies/{id}/stock` (শুধু মালিক)। রোগী পড়ে শুধু `stockPublic/{id}` (নাম + আছে/কম/নেই), প্রতি ফার্মেসিতে ১টি রিড, তাই ফ্রি কোটায় থাকে। ফার্মেসির `status` (যাচাই) মালিক বদলাতে পারে না।
- রিমাইন্ডার লোকাল নোটিফিকেশন, ইন্টারনেট ছাড়াই চলে।
- লাইসেন্সের ছবি: Firebase Storage-এ এখন পেইড প্ল্যান লাগে, তাই ছোট করে (≤৭০০ KB) মালিক-গোপন Firestore ডকুমেন্টে রাখা হয়।

## চালানোর ধাপ

1. [Firebase console](https://console.firebase.google.com)-এ প্রজেক্ট খুলুন (Spark প্ল্যান)। Authentication → Sign-in method → **Google** চালু করুন। **Firestore Database** বানান (production mode)।
2. Firestore → Rules-এ `firebase/firestore.rules`-এর লেখা পেস্ট করে Publish করুন।
3. Project settings → Android app যোগ করুন: package `com.healthdiary.health_app` + আপনার SHA-1। সেখান থেকে `apiKey`, `appId`, `projectId`, `messagingSenderId` নিন। Authentication → Google প্রোভাইডারের **Web client ID**-ই `GOOGLE_SERVER_CLIENT_ID`। Drive ব্যাকআপের জন্য Google Cloud-এ OAuth consent screen-এ `drive.appdata` স্কোপ যোগ করুন।
4. চালান:

```sh
flutter pub get
flutter run \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_SENDER_ID=... \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>.apps.googleusercontent.com
```

Firebase কনফিগ না থাকলে লগইন স্ক্রিনে **অফলাইন মোড** আসে (শুধু রোগী অংশ)।

5. ফার্মেসি যাচাই (অ্যাডমিন): Firestore-এ `pharmacies/{মালিকের uid}` ডকুমেন্টে `status` = `verified` করুন (লাইসেন্স দেখতে `licenses/{uid}.image` — base64 ছবি)। যাচাই না হওয়া পর্যন্ত রোগীরা দোকান দেখে না।

## কাঠামো

```
lib/
  core/       থিম (রোগী: টিল, মালিক: ইন্ডিগো), বাংলা সংখ্যা/তারিখ, শেয়ার্ড উইজেট
  data/       SQLite (রোগীর ডাটা) + মডেল
  services/   auth (Google→Firebase), নোটিফিকেশন, Drive ব্যাকআপ, অ্যাপ স্টেট
  features/
    auth/     অনবোর্ডিং, লগইন, রোল বাছাই
    patient/  হোম, ওষুধ, ভিজিট+টেস্ট, ফার্মেসি, সেটিংস
    owner/    রেজিস্ট্রেশন, হোম, অনুরোধ, স্টক, হিসাব+বাকি, প্রোফাইল
firebase/firestore.rules
```

## এখনো করা হয়নি

OCR/AI প্রেসক্রিপশন স্ক্যান, PDF শেয়ার, ভাইটাল লগ, টিকা ট্র্যাকার, জরুরি কার্ড, ইংরেজি ভাষা, মালিকের জন্য বারকোড স্ক্যান / Excel ইমপোর্ট, নতুন অনুরোধের পুশ নোটিফিকেশন (এখন অ্যাপ খুললে দেখা যায়), iOS কনফিগ। লোকাল ডাটা অ্যাকাউন্ট-ভিত্তিক নয় — একই ফোনে অন্য Google অ্যাকাউন্টে ঢুকলে আগের ডাটা ফোনেই থাকে।
