// Cloudex Shield — kill switch для отдельных программ: страна выхода в строке меню, заморозка
// выбранных программ (вместе со всем, что они запустили), пока адрес неожиданный, и проверка утечек.
// Трафик не меняется и не перенаправляется: программы только ставятся на паузу на этом Маке.

import AppKit

let siteURL = "https://medfab-dev.tech/cloudex-shield/"
let supportURL = "https://github.com/trapastnik/cloudex-shield#support"
let guardURL = "https://medfab-dev.tech/cloudex-guard/"

func ago(_ date: Date) -> String {
  let minutes = Int(-date.timeIntervalSinceNow / 60)
  if minutes < 60 { return "\(max(minutes, 0)) " + t("min", "мин") }
  if minutes < 60 * 24 { return "\(minutes / 60) " + t("h", "ч") }
  return "\(minutes / 60 / 24) " + t("d", "дн")
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
  let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

  func applicationDidFinishLaunching(_ note: Notification) {
    if isDemo { Demo.prepare() }
    item.autosaveName = isDemo ? "Cloudex Shield Demo" : "Cloudex Shield"
    item.button?.toolTip = "Cloudex Shield"
    item.menu = NSMenu()
    item.menu?.delegate = self
    item.menu?.autoenablesItems = false
    if !isDemo {  // в демо сеть не проверяется и ничего не замораживается
      Migration.run()
      NetGuard.shared.onChange = { [weak self] in self?.refresh() }
      NetGuard.shared.start()
      Login.onLaunch()
    } else {
      // Фазы демо переключает demo.sh через файл — следим за ним раз в полсекунды.
      let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
      RunLoop.main.add(timer, forMode: .common)
    }
    refresh()
  }

  // Выход через меню приложений, выход из системы, quit от другой программы — отпускаем замороженных.
  func applicationWillTerminate(_ note: Notification) {
    if !isDemo { NetGuard.shared.releaseAll() }
  }

  // Значок в строке меню: флаг страны; ⚠︎ — адрес не разрешён; ❄︎ — программы на паузе.
  func refresh() {
    let title = NSMutableAttributedString(attributedString: networkTitle())
    if title.length == 0 { title.append(NSAttributedString(string: "◌ net")) }
    item.button?.attributedTitle = title
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    if isDemo { Demo.addNetworkSection(to: menu) } else { addNetworkSection(to: menu) }
    menu.addItem(withTitle: t("About Cloudex Shield…", "О Cloudex Shield…"), action: #selector(openSite), keyEquivalent: "").target = self
    menu.addItem(withTitle: t("Also from us: Cloudex Guard — Claude Code context per chat ↗", "Ещё от нас: Cloudex Guard — контекст чатов Claude Code ↗"),
                 action: #selector(openGuard), keyEquivalent: "").target = self
    menu.addItem(withTitle: t("Support Cloudex Shield ♥", "Поддержать Cloudex Shield ♥"), action: #selector(support), keyEquivalent: "").target = self
    menu.addItem(withTitle: t("Quit Cloudex Shield", "Выйти из Cloudex Shield"), action: #selector(quit), keyEquivalent: "q").target = self
  }

  @objc func openSite() { open(siteURL) }
  @objc func openGuard() { open(guardURL) }
  @objc func support() { open(supportURL) }
  private func open(_ link: String) { if let url = URL(string: link) { NSWorkspace.shared.open(url) } }

  @objc func quit() {
    if !isDemo { NetGuard.shared.releaseAll() }  // выход не должен оставить программы замороженными
    NSApp.terminate(nil)
  }
}

// Место значка по умолчанию — правее, ближе к часам: левые значки при переполненной
// строке меню уходят под вырез экрана и пропадают.
let positionKey = "NSStatusItem Preferred Position Cloudex Shield"
if UserDefaults.standard.object(forKey: positionKey) == nil {
  UserDefaults.standard.set(250.0, forKey: positionKey)
}

// Служебная проверка из терминала: CloudexShield --speedtest
if CommandLine.arguments.contains("--speedtest") {
  SpeedTest.shared.onChange = {
    guard !SpeedTest.shared.isRunning else { return }
    print(SpeedTest.shared.summary)
    exit(0)
  }
  SpeedTest.shared.run()
  RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
