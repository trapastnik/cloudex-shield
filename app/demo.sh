#!/bin/zsh
# Демо для записи GIF и роликов: настоящее приложение без настоящей сети (см. demo.swift).
#
#   zsh app/demo.sh        — VPN прыгает в другую страну → ❄︎ пауза → адрес вернулся (английский)
#   zsh app/demo.sh ru     — то же на русском
#   zsh app/demo.sh auto   — фазы по таймеру, без Enter (10 с 🇺🇸 → 12 с ❄︎BR → 10 с 🇺🇸), отсчёт в окне
#
# На время записи настоящие Cloudex Shield и Cloudex Guard выключаются (заморозка отпускается,
# автозапуск приостанавливается), чтобы в строке меню был один значок без вашего адреса и чатов.
# Фазы переключаются Enter в этом окне; настоящие программы не трогаются.
set -e
cd "$(dirname "$0")"
LANG_UI=en; AUTO=0
for a in "$@"; do case "$a" in ru|en) LANG_UI=$a;; auto) AUTO=1;; esac; done
PHASE="$(getconf DARWIN_USER_TEMP_DIR)cloudex-shield-demo/net-phase"
APP="${TMPDIR:-/tmp}/Cloudex Shield Demo.app"
ID=io.github.trapastnik.cloudex-shield.demo
AGENTS=("$HOME/Library/LaunchAgents/io.github.trapastnik.cloudex-shield.plist" "$HOME/Library/LaunchAgents/io.github.trapastnik.cloudex-guard.plist")

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$(dirname "$PHASE")"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Cloudex Shield Demo</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>CloudexShieldDemo</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
echo "Собираю демо…"
swiftc -O -target "$(uname -m)-apple-macos13" *.swift -o "$APP/Contents/MacOS/CloudexShieldDemo.new"
mv -f "$APP/Contents/MacOS/CloudexShieldDemo.new" "$APP/Contents/MacOS/CloudexShieldDemo"
[ -f ../assets/AppIcon.icns ] && cp ../assets/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
defaults write $ID "NSStatusItem Preferred Position Cloudex Shield Demo" -float 260

for a in "${AGENTS[@]}"; do [ -f "$a" ] && launchctl bootout "gui/$(id -u)" "$a" 2>/dev/null || true; done
osascript -e 'tell application id "io.github.trapastnik.cloudex-shield" to quit' 2>/dev/null || true
osascript -e 'tell application id "io.github.trapastnik.cloudex-guard" to quit' 2>/dev/null || true
sleep 1

echo ok > "$PHASE"
pkill -x CloudexShieldDemo 2>/dev/null || true
open -g --env CLOUDEX_DEMO=1 --env "CLOUDEX_DEMO_LANG=$LANG_UI" "$APP"
sleep 2
cat <<'TXT'

Демо запущено: в строке меню 🇺🇸 US — VPN в США, всё разрешено.

Подготовка: пустой рабочий стол (Mission Control → «+»), это окно — рядом, но ВНЕ области записи.
⌘⇧5 → «Записать выбранную область»: правый верхний угол экрана, ширина ~900 px
  (подменю «Network guard» открывается ВЛЕВО от меню), высота ~520 px → «Записать».

  1. Открыть меню, навести на «Network guard» — подменю с программами и 🇺🇸 US, 2 секунды. Esc.
  2. Enter в этом окне → в строке меню красное ❄︎BR. Подождать секунду.
  3. Открыть меню — красная строка «❄︎ Paused: ChatGPT, Claude…», держать 3 секунды. Esc.
  4. Enter в этом окне → снова 🇺🇸 US. Открыть меню на 2 секунды. Esc.
  5. Остановить запись (■) — ДО следующего Enter: после него вернутся настоящие приложения.

TXT
if [ "$AUTO" = 1 ]; then
  countdown() { for i in $(seq "$1" -1 1); do printf '\r  %s — ещё %2d с ' "$2" "$i"; sleep 1; done; printf '\n'; }
  echo "Режим auto: включите запись сейчас."
  countdown 10 "🇺🇸 US: откройте меню, наведите на «Network guard», Esc"
  echo jump > "$PHASE"
  countdown 12 "❄︎BR: откройте меню — красная строка «Paused», 3 секунды, Esc"
  echo ok > "$PHASE"
  countdown 10 "🇺🇸 US снова: откройте меню на 2 секунды, Esc, остановите запись"
else
  read "?Enter — сеть прыгнула в Бразилию (❄︎)… "
  echo jump > "$PHASE"
  read "?Enter — адрес вернулся (🇺🇸)… "
  echo ok > "$PHASE"
  read "?Enter — закрыть демо и вернуть настоящие приложения… "
fi

pkill -x CloudexShieldDemo 2>/dev/null || true
for a in "${AGENTS[@]}"; do [ -f "$a" ] && launchctl bootstrap "gui/$(id -u)" "$a" 2>/dev/null || true; done
for app in "Cloudex Shield" "Cloudex Guard"; do [ -d "$HOME/Applications/$app.app" ] && open -g "$HOME/Applications/$app.app"; done
sleep 2
pgrep -x CloudexShield >/dev/null && echo "Настоящий Cloudex Shield снова работает." || echo "Проверьте Cloudex Shield в ~/Applications."
