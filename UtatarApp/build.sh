#!/bin/bash

# 🎮 UtatarApp Build Script
# هذا السكريبت بيبني التطبيق على Mac مع Xcode

set -e

echo "🎮 بناء تطبيق عصر التتار..."
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode مش موجود! لازم تثبت Xcode من App Store"
    exit 1
fi

# Clean build
echo "🧹 نظف البناء القديم..."
xcodebuild clean -scheme UtatarApp -quiet

# Build for simulator
echo "📱 بناء للمحاكي..."
xcodebuild build \
    -scheme UtatarApp \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 14' \
    -configuration Debug \
    -quiet

echo ""
echo "✅ البناء تم بنجاح!"
echo ""
echo "لتشغيل على المحاكي:"
echo "  xcodebuild -scheme UtatarApp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 14' build"
echo ""
echo "لبناء IPA للجهاز:"
echo "  1. افتح UtatarApp.xcodeproj في Xcode"
echo "  2. اختر Product → Archive"
echo "  3. اختر Distribute App"
echo ""
echo "🎮 استمتع باللعبة!"
