// Язык интерфейса: английский, а если система на русском — русский.
// Принудительно: defaults write io.github.trapastnik.cloudex-guard language ru (или en).

import Foundation

let isRussian: Bool = {
  // Демо (запись GIF) — по умолчанию английское, независимо от системы.
  if ProcessInfo.processInfo.environment["CLOUDEX_DEMO"] == "1" { return ProcessInfo.processInfo.environment["CLOUDEX_DEMO_LANG"] == "ru" }
  if let forced = UserDefaults.standard.string(forKey: "language") { return forced == "ru" }
  return Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
}()

// Строка интерфейса на двух языках: t("Quit", "Выход").
func t(_ en: String, _ ru: String) -> String { isRussian ? ru : en }
