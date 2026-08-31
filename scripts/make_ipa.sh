#!/usr/bin/env bash
#
# 📦 make_ipa.sh — turn ANY of these into a real, installable UtatarApp.ipa:
#
#   ./scripts/make_ipa.sh ~/Downloads/UtatarApp-IPA.zip      # a CI artifact (always a zip!)
#   ./scripts/make_ipa.sh build/UtatarApp.xcarchive          # an Xcode archive
#   ./scripts/make_ipa.sh .../Release-iphoneos/UtatarApp.app # a built .app
#   ./scripts/make_ipa.sh broken.ipa -o fixed.ipa               # re-pack a bad ipa
#
# An .ipa is just a zip whose ROOT is  Payload/<Name>.app  — that's all this does.
# It ad-hoc signs the bundle when `codesign` exists (TrollStore wants ad-hoc or no
# signature; this kills "Code Signature Invalid") and verifies the layout so
# TrollStore never says "Invalid IPA / missing Info.plist".
#
set -euo pipefail

OUT="UtatarApp.ipa"
IN=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '3,16p' "$0"; exit 0 ;;
    *) IN="$1"; shift ;;
  esac
done
[ -n "$IN" ] || { echo "usage: $0 [-o out.ipa] <artifact.zip | X.xcarchive | X.app>" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

case "$IN" in
  *.app)
    APP="$IN" ;;
  *.xcarchive)
    [ -d "$IN" ] || { echo "❌ not a folder: $IN" >&2; exit 1; }
    APP="$(find "$IN/Products/Applications" -maxdepth 1 -name '*.app' 2>/dev/null | head -n1)" ;;
  *.zip|*.ipa)
    # a "renamed zip" or a badly packed .ipa lands here too: we unpack and re-pack it right
    unzip -q -o "$IN" -d "$TMP/unz" || { echo "❌ $IN is not a zip archive (a renamed file is not an .ipa!)" >&2; exit 1; }
    find "$TMP/unz" \( -name '__MACOSX' -o -name '._*' \) -prune -exec rm -rf {} + 2>/dev/null || true
    find "$TMP/unz" -name '.DS_Store' -delete 2>/dev/null || true
    APP="$(find "$TMP/unz" -name '*.app' -path '*Products/Applications*' 2>/dev/null | head -n1)"
    [ -n "$APP" ] || APP="$(find "$TMP/unz" -maxdepth 8 -name '*.app' 2>/dev/null | head -n1)" ;;
  *)
    echo "❌ unsupported input: $IN (pass a .zip, .xcarchive or .app)" >&2; exit 1 ;;
esac

if [ -z "${APP:-}" ] || [ ! -d "$APP" ]; then
  echo "❌ لم أجد ملف .app جوّه: $IN" >&2
  echo "   لو الجاي artifact قديم من CI: ممكن يكون فيه UtatarApp.xcarchive بس." >&2
  echo "   جرّب: ./scripts/make_ipa.sh <(unzip -d folder)  أو استخدم ci/ipa.yml الجديد" >&2
  exit 1
fi

NAME="$(basename "$APP" .app)"
echo "📱 app      : $APP"

# --- what will the phone get? -------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
  python3 - "$APP" <<'PYEOF' || echo "   ⚠️ could not read Info.plist"
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
d = plistlib.loads((app / "Info.plist").read_bytes())
print("   bundle id :", d.get("CFBundleIdentifier"))
print("   version   :", d.get("CFBundleShortVersionString"), "build", d.get("CFBundleVersion"))
print("   min iOS   :", d.get("MinimumOSVersion"), " (device must run iOS >= this)")
print("   families  :", d.get("UIDeviceFamily"))
exe = app / (d.get("CFBundleExecutable") or "")
if exe.exists():
    magic = exe.read_bytes()[:4]
    known = {b"\xca\xfe\xba\xbe": "Mach-O fat/universal", b"\xcf\xfa\xed\xfe": "Mach-O arm64",
             b"\xce\xfa\xed\xfe": "Mach-O x86_64", b"\xfe\xed\xfa\xcf": "Mach-O arm64 (LE)"}
    print("   binary    :", known.get(magic, "unrecognised header: %r" % magic))
    if magic not in known:
        print("   ⚠️ if this says arm64 is missing, the phone will refuse to launch it")
else:
    print("   ❌ executable %s missing from the bundle" % (d.get("CFBundleExecutable"),))
PYEOF
fi

# --- ad-hoc sign (optional) ---------------------------------------------------
if command -v codesign >/dev/null 2>&1; then
  echo "🔏 ad-hoc signing (codesign -s -)"
  codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
    || echo "   ⚠️ codesign failed — continuing unsigned (TrollStore still accepts it)"
else
  echo "ℹ️  no codesign on this machine → bundle stays unsigned; TrollStore accepts that"
fi

# --- build the Payload layout ------------------------------------------------
STAGE="$TMP/pkg"
rm -rf "$STAGE" && mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
find "$STAGE" \( -name '.DS_Store' -o -name '__MACOSX' \) -prune -exec rm -rf {} + 2>/dev/null || true

OUT_DIR="$(dirname "$OUT")"; mkdir -p "$OUT_DIR"
OUT="$(cd "$OUT_DIR" && pwd)/$(basename "$OUT")"
rm -f "$OUT"
# -X no extra file attributes, -y preserve symlinks: installers care about both
(cd "$STAGE" && zip -qryX "$OUT" Payload)

echo "✅ wrote $OUT ($(du -h "$OUT" | cut -f1 | tr -d ' '))"

# --- verify: installers refuse an .ipa unless Payload/<App>.app is at the root
echo "🔎 verifying layout…"
LIST="$(unzip -l "$OUT")"
echo "$LIST" | sed -n '4,7p'
fail=0
echo "$LIST" | grep -q "Payload/${NAME}.app/Info.plist" || { echo "   ❌ Info.plist is not at Payload/${NAME}.app/ → installers will reject"; fail=1; }
echo "$LIST" | grep -q "__MACOSX" && { echo "   ❌ contains __MACOSX junk → re-zip"; fail=1; }
if [ "$fail" -eq 0 ]; then
  echo "   ✅ layout OK"
  echo
  echo " install: AirDrop/Files أوّل حاجة الملف ده للآيفون، وبعدين:"
  echo "   • TrollStore  → افتح الملف من Files (Long press → Share → TrollStore) أو Store → +"
  echo "   • TrolStore   → Add app / install by URL أو من Files"
  echo "   ملاحظة: لازم يكون iOS الجهاز ≥ الحد الأدنى فوق، وTrollStore بيدعم iOS 14.0–16.6.1 (و17.0 betas)."
fi
exit "$fail"
