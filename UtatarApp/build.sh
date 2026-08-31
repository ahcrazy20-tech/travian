#!/usr/bin/env bash
#
# 🎮 UtatarApp — build helper for Mac + Xcode
#
#   ./build.sh              build for the iOS Simulator (Debug)
#   ./build.sh run          build + boot a simulator and install the app
#   ./build.sh device       build for a real device (Release, unsigned)
#   ./build.sh ipa          build + package an .ipa you can re-sign with Sideloadly/AltStore
#   ./build.sh check        run the project sanity checks only
#
set -euo pipefail

# --- locate the project (works from the repo root or from this folder) -------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$HERE"
PROJECT="$PROJ_DIR/UtatarApp.xcodeproj"
SCHEME="UtatarApp"
DERIVED="$PROJ_DIR/build/DerivedData"
MODE="${1:-simulator}"

if [ ! -d "$PROJECT" ]; then
  echo "❌ لم أجد UtatarApp.xcodeproj بجوار هذا السكريبت" >&2
  exit 1
fi

banner() { printf "\n\033[1m%s\033[0m\n" "$1"; }

mkdir -p "$PROJ_DIR/build"

# --- optional static checks (same script CI runs) ----------------------------
CHECK="$PROJ_DIR/../scripts/check_project.py"
if [ -f "$CHECK" ] && command -v python3 >/dev/null 2>&1; then
  banner "🔍 فحص المشروع"
  python3 "$CHECK" "$PROJ_DIR/.." || { echo "⚠️  فيه مشاكل في المشروع — صلّحها الأول"; exit 1; }
fi

if [ "$MODE" = "check" ]; then
  banner "✅ الفحص خلص"
  exit 0
fi

# --- no Xcode → tell the user what to do instead of failing cryptically ------
if [ "$MODE" != "check" ] && ! command -v xcodebuild >/dev/null 2>&1; then
  banner "❌ Xcode مش موجود على الجهاز ده"
  echo "   ثبّت Xcode من App Store، وبعدين شغّل:"
  echo "     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "   (أو استخدم GitHub Actions: أي push لفرع main بيبني التطبيق أوتوماتك)"
  exit 1
fi

banner "🛠️  Xcode"
xcodebuild -version
echo "project: $PROJECT"


COMMON_FLAGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -derivedDataPath "$DERIVED"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=""
)

case "$MODE" in
  simulator|run)
    banner "📱 بناء لمحاكي iOS (Debug)"
    xcodebuild clean build "${COMMON_FLAGS[@]}" \
      -destination 'generic/platform=iOS Simulator' \
      -configuration Debug 2>&1 | tee "$PROJ_DIR/build/simulator.log" || {
        echo; echo "===== الأخطاء ====="; grep -nE "error:|The following build commands failed" "$PROJ_DIR/build/simulator.log" | head -40
        exit 1; }
    APP="$DERIVED/Build/Products/Debug-iphonesimulator/$SCHEME.app"
    echo "✅ التطبيق: $APP"
    [ -d "$APP" ] || { echo "❌ ملف الـ .app مش موجود بعد البناء" >&2; exit 1; }

    if [ "$MODE" = "run" ]; then
      banner "🚀 تشغيل على المحاكي"
      UDID="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
data=json.load(sys.stdin)
for runtime, devs in data["devices"].items():
    if "iOS" not in runtime: continue
    for d in reversed(devs):
        if d.get("isAvailable"):
            print(d["udid"]); raise SystemExit
print("", end="")')"
      if [ -z "$UDID" ]; then
        echo "❌ مفيش محاكي iOS متاح — اعمل واحد من Xcode > Settings > Components" >&2
        exit 1
      fi
      xcrun simctl boot "$UDID" 2>/dev/null || true
      open -a Simulator
      xcrun simctl install "$UDID" "$APP"
      xcrun simctl launch "$UDID" com.utatar.app
    fi
    ;;

  device|ipa)
    banner "📦 بناء للجهاز (Release)"
    ARCHIVE="$PROJ_DIR/build/$SCHEME.xcarchive"
    xcodebuild clean archive "${COMMON_FLAGS[@]}" \
      -destination 'generic/platform=iOS' \
      -configuration Release \
      -archivePath "$ARCHIVE" \
      ENABLE_BITCODE=NO 2>&1 | tee "$PROJ_DIR/build/archive.log" || {
        echo; echo "===== الأخطاء ====="; grep -nE "error:|The following build commands failed" "$PROJ_DIR/build/archive.log" | head -40
        exit 1; }
    echo "✅ الأرشيف: $ARCHIVE"

    if [ "$MODE" = "ipa" ]; then
      banner "📄 تحضير ملف IPA"
      APP="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -n1)"
      [ -n "$APP" ] || { echo "❌ مفيش .app جوّه الأرشيف" >&2; exit 1; }
      rm -rf "$PROJ_DIR/build/ipa"
      mkdir -p "$PROJ_DIR/build/ipa/Payload"
      cp -R "$APP" "$PROJ_DIR/build/ipa/Payload/"
      (cd "$PROJ_DIR/build/ipa" && zip -qry "$PROJ_DIR/build/$SCHEME-unsigned.ipa" Payload)
      echo "✅ IPA (غير موقّع): $PROJ_DIR/build/$SCHEME-unsigned.ipa"
      echo "   وقّعه بـ Sideloadly أو AltStore عشان تركّبه على التلفون."
    fi
    ;;

  *)
    echo "استخدام: $0 [simulator|run|device|ipa|check]" >&2
    exit 2
    ;;
esac

banner "🎮 تمام! التطبيق اتبنى"
