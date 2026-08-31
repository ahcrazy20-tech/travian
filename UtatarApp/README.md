# 🎮 تطبيق عصر التتار - UtatarApp

تطبيق iOS يفتح لعبة عصر التتار (utatar.com) مع **بوت تجسس وهجوم أوتوماتك** مدمج! 🕵️⚔️

## ✨ المميزات

### 🌐 WebView كامل
- فتح موقع اللعبة مباشرة في التطبيق
- دعم كامل لل.touches والgestures
- تصميم مظلم مريح للعينين

### 🕵️ بوت التجسس (Spy Bot)
- **اكتشاف القرى** - بيكتشف القرى حواليك أوتوماتك
- **فحص الموارد** - بيشوف كل قرية فيها كام مورد
- **تحليل الأهداف** - بيصنف القرى حسب صعوبة الهجوم
- **مسح الخريطة** - بيمسح منطقة كاملة على الخريطة
- **تفاصيل القرية** - بيشوف الجنود والجدار والمباني

### ⚔️ بوت الهجوم (Attack Bot)
- **هجوم تلقائي** - بيهجم على القرى الغنية أوتوماتك
- **اختيار ذكي** - بيختار الأهداف الأسهل والأغنى
- **تحديد الجنود** - بيحدد عدد الجنود المناسب لكل هدف
- **تجاهل الخطير** - بيجاهل القرى المسلحة والجدور العالية
- **سجل الهجمات** - بيسجل كل هجوم و نتيجته

### 🤖 مساعد الأوتوماتك
- **جمع الموارد تلقائي** - يلم الموارد والبونصات أوتوماتك
- **بناء تلقائي** - يبني المباني الجديدة أوتوماتك
- **تدريب جنود تلقائي** - يدرب جنود أوتوماتك
- **تنبيهات الهجمات** - بيلقط أي هجوم جاي
- **تنبيه مخزن مليان** - بنبهك لما المخزن يملي

### 📊 متابعة الموارد
- عرض الموارد الحالية (خشب، طين، حديد، قمح)
- تحديث تلقائي كل 30 ثانية

### 💻 كونسول JavaScript
- تنفيذ أوامر JS مخصصة على صفحة اللعبة

---

## 🎯 كيف بوت التجسس والهجوم بيشتغل

### 1️⃣ مرحلة التجسس
```
البوت بيمسح الخريطة → بيكتشف القرى → بيفحص الموارد → بيسجل البيانات
```

### 2️⃣ مرحلة التحليل
```
بيصنف القرى → بيحدد الغنية → بيقيس المسافة → بيقيس الخطورة
```

### 3️⃣ مرحلة الهجوم
```
بيختار الأفضل → بيحسب الجنود → بيبعت هجوم → بيسجل النتيجة
```

---

## ⚙️ إعدادات البوت

### إعدادات التجسس
| الإعداد | الوصف | القيمة الافتراضية |
|---------|-------|-------------------|
| تجسس تلقائي | يمسح الخريطة أوتوماتك | ✅ مفعّل |
| فترة التجسس | كل كم دقيقة يمسح | 5 دقائق |
| تجاهل اللاعبين النشطين | ميهجمش قرى مسلحة | ✅ مفعّل |
| أقصى مستوى جدار | ميهجمش لو الجدار عالي | 5 |

### إعدادات الهجوم
| الإعداد | الوصف | القيمة الافتراضية |
|---------|-------|-------------------|
| هجوم تلقائي | بيهجم أوتوماتك | ❌ موقف |
| أقل موارد للهجوم | ميهجمش لو الموارد قليلة | 500 |
| أقصى مسافة | ميهجمش لو بعيد | 20 |
| هجمات/ساعة | عدد الهجمات في الساعة | 10 |
| جنود للهجوم | عدد الجنود لكل هجوم | 1-20 |

---

## 📱 طريقة التثبيت

### الطريقة 1: Xcode (على Mac)
1. افتح المجلد `UtatarApp` في Xcode
2. اختر iPhone Simulator أو جهازك
3. اضغط Run (▶️)

### الطريقة 2: بناء IPA
1. افتح المشروع في Xcode
2. اختر Product → Archive
3. اختر Distribute App → Development
4. هتطلع ملف IPA تقدر تنزله على تلفونك

### الطريقة 3: AltStore (بدون Mac)
1. حمل AltStore على تلفونك
2. ابعت ملف المشروع لجهاز Mac أو استخدم خدمة بناء
3. حمل IPA على تلفونك عن طريق AltStore

---

## 🏗️ البناء (GitHub Actions - من غير Mac)

أي push لفرع `main` (أو `arena/*`) أو PR بيشغّل workflow كامل أوتوماتك:
`.github/workflows/build.yml`

| Job | بيعمل إيه |
|-----|-----------|
| 🔍 `checks` | فحص المشروع على Linux في ثواني (ملفات ناقصة، إعلانات مكرّرة، Info.plist، الأصول) |
| 📱 `build-simulator` | بناء للمحاكي (Debug) + رفع `UtatarApp-simulator-app` artifact |
| 📦 `build-ipa` | Archive للجهاز (Release) + ملف **IPA غير موقّع** تقدر توقّعه بـ Sideloadly/AltStore |
| 🚀 `release` | بينزل Release على GitHub - بس لو شغّلت workflow يدوي وعلّمت `publish_release` |

**النتايج**: روح تبويب **Actions** في المستودع → آخر run → قسم *Artifacts* → حمّل الـ IPA.

لو البناء فشل، آخر step باسم **🧯 Show the exact compiler errors** بيطبع كل أسطر `error:`
اللي Xcode قالها - ده أول مكان تدوّر فيه على السبب.

### عايز IPA موقّع يركّب على طول؟
ضيف secrets في المستودع (Settings → Secrets and variables → Actions):
`P12_BASE64`, `P12_PASSWORD`, `TEAM_ID`, `PROVISIONING_PROFILE` — والـ workflow
هيعمل الأرشيف بالتوقيع أوتوماتك.

## 📲 ملف الـ IPA وتركيبه بـ TrolStore

### ⛑️ لو عندك الـ zip القديم دلوقتي وعايز الـ IPA حالاً
ملفات الـ `UtatarApp.xcarchive` اللي جوّه الـ zip فيها الـ `.app` الجاهز — وحدها الـ IPA
(الـ IPA = `Payload/UtatarApp.app` مضغوط zip). على كمبيوتر:

```bash
unzip UtatarApp-IPA.zip -d utatar
APP=$(find utatar -name "UtatarApp.app" -maxdepth 6 | head -1)
mkdir -p Payload && cp -R "$APP" Payload/
zip -qry UtatarApp.ipa Payload && rm -rf Payload
# → UtatarApp.ipa جاهز للتركيب بـ TrollStore / TrolStore
```
> ملاحظة: البناء القديم ده اتعمل قبل ما نزّل الـ target لـ iOS 15 — فبرضه محتاج iOS 16.4+.
> بعد ما تحدّث الـ workflow من `ci/build.yml` مفيش حاجة من دي محتاجا: الـ IPA بينزل لوحده في Releases.

### 🚨 ليه اللي نزل كان zip؟
كل **Artifacts** في GitHub Actions بتنزل كملف `.zip` (دي سياسة GitHub، مش مشكلة في
البناء). ملف الـ IPA الحقيقي جوه الـ zip.

- ❌ متعملش rename للـ `.zip` ويصير `.ipa` — الملف هيظل zip والتثبيت هيفشل
- ✅ فك الضغط (Files app على الآيفون فيه زر فك الضغط، أو على الكمبيوتر) → هتلاقي `UtatarApp.ipa`

### ✅ الطريقة الصح: نحمّل الـ IPA مباشرة من Releases
البناء بقى بينشر ملف **`UtatarApp.ipa`** كمرفق على **Releases** (ملف حقيقي، مش zip):

```
https://github.com/ahcrazy20-tech/travian/releases/download/ipa-main/UtatarApp.ipa
```

الرابط ده **ثابت** — كل build على `main` بيحدّث نفس الملف، فممكن تحطه مرة واحدة في TrolStore
ويفضل بيجيب آخر نسخة. الرابط بيتحط كمان في صفحة **Summary** بتاعة كل run تحت عنوان
**📲 Your IPA is ready**.

### 🛫 التثبيت بـ TrolStore / TrollStore
1. افتح رابط الـ IPA على الآيفون (Safari) → **Save to Files**
2. TrolStore → *Add app / install by URL* → الصق الرابط نفسه (أو اختار الملف من Files)
3. Install → التطبيق هيظهر على الشاشة الرئيسية من غير ما تحتاج كمبيوتر

> الـ IPA بيطلع **ad-hoc signed** (`codesign -s -`) من الـ CI — ده المطلوب لـ TrollStore/TrolStore،
> وبيمنع خطأ `Code Signature Invalid` اللي بييجي مع الملفات غير الموقعة خالص.

### 📱 إصدار iOS المطلوب
التطبيق بقى مطلوبه **iOS 15.0+** (كان 16.4) عشان يغطي كل نطاق TrollStore:

| iOS الجهاز | الطريق |
|------------|--------|
| 14.0 – 16.6.1 (و 17.0 betas) | TrollStore / TrolStore مباشرة ✅ |
| 17.x – 18.x | TrollStore ما بيشتغلش — استخدم **Sideloadly** أو **AltStore** يوقّعوا نفس الـ IPA بـ Apple ID (7 أيام، 3 أجهزة) |
| 14.0 – 14.8 | نزّل `IPHONEOS_DEPLOYMENT_TARGET` لـ 14.0 لو محتاج (هتحتاج تبدّل `TextField(value:format:)` في `FarmingSettingsView`) |

### 🔑 عايز IPA موقّع بحسابك من CI من الأول؟
ضيف secrets: `P12_BASE64`, `P12_PASSWORD`, `TEAM_ID`, `PROVISIONING_PROFILE` — الـ workflow
هيعمل signing أوتوماتك والـ IPA ينزل موقّع بموبايلك من أول مرة.

## 🛠️ البناء من المصدر (Mac + Xcode)

```bash
# من جذر المستودع أو من مجلد UtatarApp/
./UtatarApp/build.sh check       # فحص المشروع بس (مش محتاج Xcode)
./UtatarApp/build.sh             # بناء للمحاكي (Debug)
./UtatarApp/build.sh run         # بناء + تشغيل على المحاكي
./UtatarApp/build.sh device      # بناء Release للجهاز
./UtatarApp/build.sh ipa         # بناء + تحضير ملف IPA
```

الفحص ده هو نفس اللي CI بيبدأ بيه:

```bash
python3 scripts/check_project.py .
```

### ⚠️ خطوة واحدة لازم تعملها انت (تحديث ملف الـ workflow)

GitHub **بيمنع** أي GitHub App (وده الحساب اللي بيبنّي المستودع هنا) إنه يعدّل ملفات جوّه
`.github/workflows/` — رسالة الخطأ بتكون:
`refusing to allow a GitHub App to create or update workflow ... without 'workflows' permission`.

عشان كده النسخة الصحيحة من الـ workflow محفوظة في **[`ci/build.yml`](../ci/build.yml)** ولازم
تنسخها فوق الملف القديم بنفسك (دقيقتين من المتصفح، من غير أي أدوات):

1. افتح: `https://github.com/ahcrazy20-tech/travian/edit/main/.github/workflows/build.yml`
2. امسح **كل** المحتوى والصق مكانه محتوى [`ci/build.yml`](../ci/build.yml) كامل
3. `Commit changes` (على فرع `main`)
4. افتح تبويب **Actions** ← **🎮 Build UtatarApp iOS** ← **Run workflow**

> ملف `.github/workflows/build.yml` في مساحة الشغل بتاعتك متصلّح بالفعل (نفس محتوى `ci/build.yml`)،
> اللي ناقص هو رفعه على GitHub.

**ليه البناء كان مش يبدأ أصلاً؟** الملف القديم كان فيه فلتر:

```yaml
paths:
  - 'UtatarApp/**'
```

والـ commit اللي بيّه اتعمل ملف `build.yml` غيّر ملف الـ workflow **بس** (من غير مجلد `UtatarApp/`)،
فـ GitHub ما لقاش ملف مطابق للفيلتر ← **صفر runs**. كمان `runs-on: macos-14` اتقاعد،
و `Xcode 15.0` مبقاش موجود على الصورة، و `xcpretty` مش مثبت (فأي نجاح كان هيطلع فشل)،
و `actions/cache@v3` بيشتغل على Node 16 اللي اتقفل. كل ده اتصلّح في `ci/build.yml`.


### ❌ أخطاء البناء اللي اتصلّحت (٢٠٢٦-٠٨-٣١)

| # | المشكلة | التأثير | الحل |
|---|---------|---------|------|
| 1 | `sendAttackManually(to:)` معرّف مرتين: extension في `SpyAttackBot.swift` و extension تاني في `SpyAttackPanelView.swift` | `invalid redeclaration` - البناء بيرفض | اتشال الـ extension المكرر من `SpyAttackPanelView.swift` |
| 2 | نفس الـ extension كان بينادي `sendAttack(to:)` وهو `private` في ملف تاني | `cannot find 'sendAttack' in scope` | اتحل مع #1 (اللي فاضل هو extension نفس الملف) |
| 3 | `AppIcon.appiconset` من غير أي صورة | actool بيرفض/يطلع أيقونة فاضية | اتحطت أيقونة 1024×1024 حقيقية + `filename` في `Contents.json` |
| 4 | `UILaunchStoryboardName = LaunchScreen` وملف الـ storyboard مش موجود | launch screen مكسور / فشل التحقق | اتشال المفتاح (Xcode بيولّد `UILaunchScreen` تلقائي) |
| 5 | `UIRequiredDeviceCapabilities = armv7` | مفيش موبايل iOS 16+ فيه armv7 → فشل التحقق | اتشال المفتاح |
| 6 | مفيش shared scheme في `.xcodeproj` | `xcodebuild -scheme` على CI بيحتاج scheme محفوظ | اتضاف `xcshareddata/xcschemes/UtatarApp.xcscheme` |
| 7 | CI كان بيستخدم `runs-on: macos-14` + `setup-xcode 15.0` + `xcpretty` + `actions/cache@v3` + فلتر `paths:` | الـ build **مارضيش يبدأ** أصلاً، وكان بيفشل على أي صورة قديمة | `macos-latest` بدون تثبيت Xcode، بدون xcpretty، بدون cache، وبدون فلتر paths |
| 8 | نسخة التطبيق مكتوبة باليد في `Info.plist` مع `MARKETING_VERSION` | تعارض في إصدار التطبيق | `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` |
| 9 | أيقونة بحجم واحد (universal 1024) مع target أقل من iOS 17 | `actool` محتاج الحجم الكامل على الإصدارات القديمة | اتحطت مجموعة أيقونات كاملة (18 حجم iPhone/iPad + 1024 marketing) |
| 10 | `IPHONEOS_DEPLOYMENT_TARGET = 16.4` + `.tint()` (iOS 16+) | التطبيق مكنش بيركب على iOS 15.x ولا على 16.0–16.3 (كلها نطاق TrollStore) | بقى **15.0** و `.tint()` اتلفّ بـ `utatarTint()` في `Compatibility.swift` بينادي `accentColor` على iOS 15 |
| 11 | مخرج الـ CI كان artifact بصيغة zip | مفيش ملف IPA للتحميل المباشر | بقى بينشر **`UtatarApp.ipa`** في Releases + بيوقّعه ad-hoc للتركيب بـ TrollStore/TrolStore |

كمان `bot.scanVillageDetails(...)` بقى بيحدّث القرى في القائمة فعلياً بعد الفحص
(`SpyAttackBot.updateVillage(_:)`) بدل ما كان تعليق فاضي.

---

## ⚠️ ملاحظات مهمة

1. **الأوتوماتك**: التطبيق بحاول يكتشف عناصر اللعبة أوتوماتك، بس ممكن يحتاج تعديل حسب تحديثات الموقع
2. **التحديثات**: لو اللعبة غيّرت تصميمها، ممكن الأوتوماتك يحتاج تعديل
3. **الاستخدام**: استخدم الأوتوماتك بحكمة - كتير من الألعاب بتحظر الاستخدام المفرط
4. **التجسس**: البوت بيشتغل على الصفحة الحالية - محتاج تكون على صفحة الخريطة أو القرية

---

## 📁 هيكل المشروع

```
UtatarApp/
├── UtatarApp.xcodeproj/        # مشروع Xcode
├── UtatarApp/
│   ├── UtatarApp.swift         # نقطة البداية
│   ├── AppDelegate.swift       # إعداد التطبيق
│   ├── ContentView.swift       # الشاشة الرئيسية
│   ├── WebViewModel.swift      # منطق الأوتوماتك
│   ├── WebViewContainer.swift  # WebView
│   ├── AutomationPanelView.swift  # لوحة التحكم
│   ├── SettingsView.swift      # الإعدادات
│   ├── SpyAttackBot.swift      # 🕵️ بوت التجسس والهجوم
│   ├── SpyAttackPanelView.swift # لوحة بوت التجسس
│   ├── Info.plist              # إعدادات التطبيق
│   └── Assets.xcassets/        # الأيقونات
└── README.md                   # هذا الملف
```

---

## 🎮 كيفية الاستخدام

### 1. افتح التطبيق
هيفتح موقع عصر التتار مباشرة

### 2. سجّل دخولك
ادخل حسابك في اللعبة

### 3. فعّل بوت التجسس
- اضغط على زرار العين 👁️
- اضغط "ابدأ تجسس"
- البوت هيمسح الخريطة ويكتشف القرى

### 4. شوف الأهداف
- اضغط على تاب "🎯 أهداف"
- هتشوف القرى الغنية متصنفة حسب الخطورة
- كل هدف مكتوب فيه الموارد والجنود المطلوبين

### 5. فعّل الهجوم التلقائي
- اضغط "هجوم تلقائي" ⚔️
- البوت هيهجم على الأهداف الأفضل أوتوماتك
- هتوصلك إشعارات بكل هجوم

### 6. راقب السجل
- اضغط على تاب "📜 سجل"
- هتشوف كل الهجمات و نتايجها

---

## 🔧 الأوامر المخصصة (كونسول JS)

لو عايز تعمل حاجة مخصصة، استخدم كونسول JavaScript:

```javascript
// مسح قرية معينة
scanVillage(10, 20)

// هجوم على إحداثيات
sendAttack(10, 20, 50) // x, y, عدد الجنود

// عرض كل القرى المكتشفة
showDiscoveredVillages()
```

---

## 📊 إحصائيات البوت

البوت بيتتبع:
- ✅ عدد القرى المكتشفة
- ✅ القرى الغنية (أكثر من 1000 مورد)
- ✅ القرى المسلحة
- ✅ عدد الهجمات المرسلة
- ✅ الهجمات الناجحة
- ✅ إجمالي الغنائم

---

## 🚀 النسخة القادمة

- [ ] تحسين كشف عناصر الصفحة
- [ ] إضافة خريطة بصرية للقرى
- [ ] تحسين خوارزمية اختيار الأهداف
- [ ] إضافة وضع الدفاع التلقائي
- [ ] دعم قرى متعددة
- [ ] تصدير التقارير

---

**Enjoy the game! 🎮⚔️🏰🕵️**
