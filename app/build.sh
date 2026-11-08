#!/bin/zsh
# Собирает Cloudex Shield.app в ~/Applications и перезапускает его.
set -e
cd "$(dirname "$0")"
VERSION=1.0.0
APP="$HOME/Applications/Cloudex Shield.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Cloudex Shield</string>
  <key>CFBundleIdentifier</key><string>io.github.trapastnik.cloudex-shield</string>
  <key>CFBundleExecutable</key><string>CloudexShield</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
# Собираем рядом и подменяем файл целиком: перезапись на месте ломает подпись,
# и macOS убивает приложение при запуске (Code Signature Invalid).
swiftc -O -target "$(uname -m)-apple-macos13" *.swift -o "$APP/Contents/MacOS/CloudexShield.new"
mv -f "$APP/Contents/MacOS/CloudexShield.new" "$APP/Contents/MacOS/CloudexShield"
[ -f ../assets/AppIcon.icns ] && cp ../assets/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
# Чистый выход (SIGTERM) отпускает замороженные программы.
pkill -x CloudexShield || true
sleep 1
open -g "$APP"
echo "built $APP"
