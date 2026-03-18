#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/LemonTimer.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# 1. Resources 폴더 생성
mkdir -p "$RESOURCES"

# 2. 아이콘 생성 (iconset → .icns)
if [ -d "$SCRIPT_DIR/LemonTimer.iconset" ]; then
  echo "🎨 Generating app icon..."
  iconutil -c icns "$SCRIPT_DIR/LemonTimer.iconset" -o "$RESOURCES/AppIcon.icns"
fi

# 3. 오디오 파일 복사
if [ -f "$SCRIPT_DIR/cafe_loop.m4a" ]; then
  echo "🎵 Copying cafe_loop.m4a..."
  cp "$SCRIPT_DIR/cafe_loop.m4a" "$RESOURCES/cafe_loop.m4a"
fi

# 4. 컴파일
echo "🔨 Compiling LemonTimer..."
swiftc "$SCRIPT_DIR/FlowTimer.swift" \
  -framework Cocoa \
  -framework UserNotifications \
  -framework AVFoundation \
  -o "$MACOS/LemonTimer"

# 5. Ad-hoc 코드 서명
echo "🔏 Signing app..."
codesign --force --deep --sign - "$APP"

# 6. 기존 앱 제거 + 새로 복사
echo "📦 Installing to Applications..."
rm -rf /Applications/LemonTimer.app
cp -r "$APP" /Applications/LemonTimer.app

# 7. LaunchServices에 앱 등록 (알림 + 아이콘 인식에 필요)
echo "📋 Registering with system..."
$LSREGISTER -f /Applications/LemonTimer.app

# 8. 아이콘 캐시 초기화
echo "🧹 Clearing icon cache..."
rm -rf ~/Library/Caches/com.apple.iconservices* 2>/dev/null
rm -rf ~/Library/Caches/com.apple.dock.iconcache 2>/dev/null
killall Dock 2>/dev/null || true

echo ""
echo "✅ Build + Install complete!"
echo "🍋 Launching LemonTimer..."
open /Applications/LemonTimer.app
