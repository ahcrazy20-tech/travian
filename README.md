# travian — عصر التتار (UtatarApp)

تطبيق iOS (Swift + SwiftUI) بيفتح لعبة **عصر التتار** في WebView، مع بوت تجسس
وهجوم أوتوماتك ومساعد أوتوماتك للموارد والبناء والتدريب.

📦 الكود والتفاصيل: [`UtatarApp/`](UtatarApp/) · 🧭 ملخص المشروع: [`PROJECT_SUMMARY.md`](PROJECT_SUMMARY.md)

## 🏗️ البناء

البناء بيتعمل أوتوماتك على **GitHub Actions** من غير ما يكون عندك Mac — أي push
لـ `main` أو `arena/*` بيشغّل [`.github/workflows/build.yml`](.github/workflows/build.yml):

1. 🔍 `checks` — فحص ساكن للمشروع (بيكشف الملفات الناقصة / الإعلانات المكررة / `Info.plist` الفاسد)
2. 📱 `build-simulator` — بناء Debug لمحاكي iOS
3. 📦 `build-ipa` — Archive لـ iOS + ملف **IPA غير موقّع** في الـ artifacts

الحمولة بتاعت البناء (`.app` / `.ipa`) بتلاقيها في تبويب **Actions** ← آخر run ← **Artifacts**.
لو فيه فشل، افتح step **🧯 Show the exact compiler errors** وهتلاقي رسالة Xcode بالضبط.

على Mac (اختياري):

```bash
./UtatarApp/build.sh check      # فحص بس
./UtatarApp/build.sh            # بناء للمحاكي
./UtatarApp/build.sh ipa        # بناء + IPA
```

فحص المشروع من غير Xcode (بيشتغل على أي نظام):

```bash
python3 scripts/check_project.py .
```

## ⚠️ بعد ما تدمج التعديلات

لو الـ build لسه مش بيبدأ من GitHub: لازم ملف [`.github/workflows/build.yml`](.github/workflows/build.yml)
يتحدّث من النسخة الجديدة في [`ci/build.yml`](ci/build.yml) — GitHub بيمنع الـ App
اللي بيكتب الكود ده إنه يلمس ملفات `.github/workflows/`. التفاصيل والخطوات في
[`UtatarApp/README.md`](UtatarApp/README.md#️-خطوة-واحدة-لازم-تعملها-انت-تحديث-ملف-الـ-workflow).
