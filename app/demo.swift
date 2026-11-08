// Демо-режим для записи GIF и роликов: настоящее приложение, но без настоящей сети.
// Запуск: CLOUDEX_DEMO=1 (см. app/demo.sh). Что меняется:
// - сеть не проверяется и ничего не замораживается — это только отображение;
// - адреса — из диапазонов для документации (RFC 5737), не чьи-то настоящие;
// - интерфейс на английском (CLOUDEX_DEMO_LANG=ru — на русском);
// - не трогаются настройки и автозапуск настоящего приложения.
// Фазу сценария (ok / jump) demo.sh пишет в файл net-phase; приложение следит за ним.

import AppKit

let isDemo = ProcessInfo.processInfo.environment["CLOUDEX_DEMO"] == "1"

enum Demo {
  static let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cloudex-shield-demo")
  static let phaseFile = dir.appendingPathComponent("net-phase")
  static let country = "US"
  static let ip = "203.0.113.24"
  static let jumpCountry = "BR"
  static let jumpIP = "198.51.100.7"
  static let guardedApps = [("Claude", "com.anthropic.claudefordesktop"), ("ChatGPT", "com.openai.chat")]

  static func prepare() {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: phaseFile.path) {
      try? "ok".write(to: phaseFile, atomically: true, encoding: .utf8)
    }
  }

  static var isJumped: Bool {
    (try? String(contentsOf: phaseFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == "jump"
  }

  // Значок в строке меню — как у настоящего приложения: флаг или красное «❄︎BR».
  static func networkTitle() -> NSAttributedString {
    if isJumped {
      return NSAttributedString(string: "❄︎\(jumpCountry)", attributes: [
        .foregroundColor: NSColor.systemRed, .font: NSFont.boldSystemFont(ofSize: 13),
      ])
    }
    return NSAttributedString(string: flag(country) + " " + country)
  }

  // Меню в демо: те же строки, что у настоящего приложения, но без действий.
  static func addNetworkSection(to menu: NSMenu) {
    let jumped = isJumped
    let text = NSMutableAttributedString(string: "\(flag(jumped ? jumpCountry : country)) \(jumped ? jumpCountry : country)  ", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
    text.append(NSAttributedString(string: jumped ? jumpIP : ip, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]))
    text.append(NSAttributedString(string: "   0 " + t("min", "мин"), attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.menuFont(ofSize: 12)]))
    menu.addItem(plain(text))
    if jumped {
      let names = guardedApps.map(\.0).sorted().joined(separator: ", ")
      let line = "❄︎ " + t("Paused: ", "Заморожено: ") + names + t(" — resumes when your address is allowed again", " — отпущу, когда адрес станет разрешённым")
      menu.addItem(plain(NSAttributedString(string: line, attributes: [.foregroundColor: NSColor.systemRed])))
      menu.addItem(plain(NSAttributedString(string: t("Resume and leave alone for 15 minutes", "Разморозить и не трогать 15 минут"))))
    }
    let protection = NSMenuItem(title: t("Network guard", "Защита"), action: nil, keyEquivalent: "")
    protection.submenu = protectionMenu()
    menu.addItem(protection)
    menu.addItem(plain(NSAttributedString(string: t("Check address now", "Проверить адрес сейчас"))))
    menu.addItem(plain(NSAttributedString(string: t("How others see us…", "Как нас видят…"))))
    menu.addItem(plain(NSAttributedString(string: "↓ 182 Mbit/s · ↑ 41 Mbit/s · 38 " + t("ms", "мс"))))
    menu.addItem(.separator())
  }

  // Подменю «Защита» как у настоящего приложения: программы и разрешённые страны с галочками.
  static func protectionMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(checked(t("Pause apps on a wrong network", "Заморозка включена"), true))
    menu.addItem(.separator())
    menu.addItem(header(t("Apps — paused together with everything they started", "Программы — замораживаются вместе со всем, что запустили")))
    for (name, bundleID) in guardedApps {
      let item = checked(name, true)
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        item.image = NSWorkspace.shared.icon(forFile: url.path)
        item.image?.size = NSSize(width: 16, height: 16)
      }
      menu.addItem(item)
    }
    menu.addItem(.separator())
    menu.addItem(header(t("Allowed countries — apps run only from these", "Разрешённые страны — с них программы работают")))
    menu.addItem(checked("\(flag(jumpCountry)) \(jumpCountry)", false))
    menu.addItem(checked("\(flag(country)) \(country)", true))
    menu.addItem(.separator())
    menu.addItem(checked(t("Pause guard for 15 minutes", "Пауза на 15 минут"), false))
    return menu
  }

  private static func plain(_ text: NSAttributedString) -> NSMenuItem {
    let item = NSMenuItem(title: text.string, action: nil, keyEquivalent: "")
    item.attributedTitle = text
    item.isEnabled = true
    return item
  }

  private static func checked(_ title: String, _ on: Bool) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.state = on ? .on : .off
    item.isEnabled = true
    return item
  }

  private static func header(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }
}
