#!/bin/zsh
# Собирает релиз: универсальное «Cloudex Shield.app» (Apple Silicon и Intel, macOS 13+),
# dist/CloudexShield.dmg (перетащить в «Программы»), dist/CloudexShield-macos.zip для install.sh
# и dist/SHA256SUMS.txt. Ничего не устанавливает и не запускает.
set -e
cd "$(dirname "$0")"
VERSION="${1:?укажите версию, например 1.0.0}"
DIST=../dist
APP="$DIST/Cloudex Shield.app"
rm -rf "$DIST" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Cloudex Shield</string>
  <key>CFBundleDisplayName</key><string>Cloudex Shield</string>
  <key>CFBundleIdentifier</key><string>io.github.trapastnik.cloudex-shield</string>
  <key>CFBundleExecutable</key><string>CloudexShield</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13" *.swift -o "$DIST/CloudexShield-$arch"
done
lipo -create "$DIST/CloudexShield-arm64" "$DIST/CloudexShield-x86_64" -output "$APP/Contents/MacOS/CloudexShield"
rm "$DIST/CloudexShield-arm64" "$DIST/CloudexShield-x86_64"
[ -f ../assets/AppIcon.icns ] && cp ../assets/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

(cd "$DIST" && ditto -c -k --keepParent "Cloudex Shield.app" CloudexShield-macos.zip)

# DMG: приложение и ярлык «Программы» — перетащить одно на другое.
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Cloudex Shield" -srcfolder "$STAGE" -ov -format UDZO "$DIST/CloudexShield.dmg"
rm -rf "$STAGE"

(cd "$DIST" && shasum -a 256 CloudexShield.dmg CloudexShield-macos.zip > SHA256SUMS.txt)
lipo -info "$APP/Contents/MacOS/CloudexShield"
cat "$DIST/SHA256SUMS.txt"
