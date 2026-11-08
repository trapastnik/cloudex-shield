// Запуск при входе и перенос настроек из Cloudex Guard 1.1 (там страж сети жил до разделения).

import AppKit

enum Login {
  static let label = "io.github.trapastnik.cloudex-shield"
  static let agent = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/\(label).plist")

  // Агент вызывает /usr/bin/open — как двойной клик — и раз в минуту поднимает упавшее
  // приложение, чтобы оно отпустило замороженные программы. Пишется при каждом запуске,
  // если приложение переехало (например, из ~/Applications в /Applications).
  // Первый запуск — спросить; дальше — держать агент в порядке, если пользователь согласился.
  static func onLaunch() {
    let defaults = UserDefaults.standard
    if FileManager.default.fileExists(atPath: agent.path) { ensure(); return }
    guard defaults.object(forKey: "loginAsked") == nil else { return }
    defaults.set(true, forKey: "loginAsked")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = t("Start Cloudex Shield at login?", "Запускать Cloudex Shield при входе?")
      alert.informativeText = t(
        "Recommended: the guard only protects while it runs, and the login item also restarts it within a minute if it ever crashes — so paused apps are always released.",
        "Рекомендуется: защита работает, только пока приложение запущено, а автозапуск ещё и поднимет его за минуту, если оно упадёт, — замороженные программы всегда будут отпущены.")
      alert.addButton(withTitle: t("Start at login", "Запускать"))
      alert.addButton(withTitle: t("Not now", "Не сейчас"))
      if alert.runModal() == .alertFirstButtonReturn { ensure() }
    }
  }

  static func ensure() {
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key><string>\(label)</string>
      <key>ProgramArguments</key>
      <array><string>/usr/bin/open</string><string>-g</string><string>\(Bundle.main.bundlePath)</string></array>
      <key>RunAtLoad</key><true/>
      <key>StartInterval</key><integer>60</integer>
    </dict>
    </plist>
    """
    if (try? String(contentsOf: agent, encoding: .utf8)) == plist { return }
    try? FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard (try? plist.write(to: agent, atomically: true, encoding: .utf8)) != nil else { return }
    let uid = getuid()
    for arguments in [["bootout", "gui/\(uid)/\(label)"], ["bootstrap", "gui/\(uid)", agent.path]] {
      let launchctl = Process()
      launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
      launchctl.arguments = arguments
      launchctl.standardError = FileHandle.nullDevice
      try? launchctl.run()
      launchctl.waitUntilExit()
    }
  }
}

enum Migration {
  static let oldDomain = "io.github.trapastnik.cloudex-guard"

  // Один раз: разрешённые страны, программы и выключатель берутся из Cloudex Guard 1.1,
  // а программы, которые тот мог оставить замороженными, — отпускаются.
  static func run() {
    let mine = UserDefaults.standard
    guard !mine.bool(forKey: "migratedFromGuard"), let old = UserDefaults(suiteName: oldDomain) else { return }
    for key in ["allowedCountries", "guardedApps", "guardEnabled"] where mine.object(forKey: key) == nil {
      if let value = old.object(forKey: key) { mine.set(value, forKey: key) }
    }
    if let stale = old.array(forKey: "frozenProcs") as? [[Int64]] {
      for pair in stale where pair.count == 2 { Procs.send(Proc(pid: Int32(pair[0]), start: pair[1]), SIGCONT) }
    }
    mine.set(true, forKey: "migratedFromGuard")
  }
}
