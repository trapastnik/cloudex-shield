// Страж сети: внешний IP и страна, заморозка выбранных программ, когда адрес не тот.
// Идеи взяты из Kordon (github.com/ef1m03/kordon, открытая GPL-версия): IP подтверждают
// два сервиса, ИИ-сервис спрашивается сам (видно раздельную маршрутизацию VPN), заморозка —
// SIGSTOP всего дерева процессов, при возвращении адреса — SIGCONT. Код свой.

import AppKit
import Network

// MARK: - Сетевые запросы

enum Net {
  // Новая сессия на каждую проверку: переиспользованное соединение остаётся на старом
  // маршруте и после переключения VPN показывает прежний адрес.
  static func session(direct: Bool = false) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    // Короткие таймауты: один зависший сервис не должен растягивать проверку,
    // от её скорости зависит, как быстро оттают программы.
    config.timeoutIntervalForRequest = 4
    config.timeoutIntervalForResource = 5
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.httpMaximumConnectionsPerHost = 1
    if direct {
      // Мимо системного прокси — так ходят терминал, git, Claude Code.
      config.connectionProxyDictionary = [
        kCFNetworkProxiesHTTPEnable as String: 0,
        kCFNetworkProxiesHTTPSEnable as String: 0,
        kCFNetworkProxiesSOCKSEnable as String: 0,
      ]
    }
    return URLSession(configuration: config)
  }

  static func text(_ url: String, in session: URLSession) async -> String? {
    guard let url = URL(string: url) else { return nil }
    var request = URLRequest(url: url)
    request.setValue("curl/8.7.1", forHTTPHeaderField: "User-Agent")  // сервисы отвечают curl простым текстом
    request.setValue("close", forHTTPHeaderField: "Connection")
    guard let (data, response) = try? await session.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    return String(decoding: data.prefix(4096), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // Адрес из сервиса вида «только IP»; nil, если ответ не похож на адрес нужного семейства.
  static func ip(_ url: String, v6: Bool, in session: URLSession) async -> String? {
    guard let answer = await text(url, in: session) else { return nil }
    let isV6 = answer.contains(":")
    let looksLikeIP = answer.allSatisfy { $0.isHexDigit || $0 == "." || $0 == ":" }
    return looksLikeIP && isV6 == v6 && !answer.isEmpty ? answer : nil
  }

  // Cloudflare /cdn-cgi/trace: адрес и страна так, как их видит этот сайт.
  static func trace(_ host: String, in session: URLSession) async -> View? {
    guard let answer = await text("https://\(host)/cdn-cgi/trace", in: session) else { return nil }
    var fields: [String: String] = [:]
    for line in answer.split(separator: "\n") {
      let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
      if pair.count == 2 { fields[pair[0]] = pair[1] }
    }
    guard let ip = fields["ip"], let loc = fields["loc"] else { return nil }
    return View(ip: ip, country: loc.uppercased())
  }

  // Страна адреса; кэш на всё время работы, адреса VPN повторяются.
  private static var geoCache: [String: String] = [:]
  private static let geoLock = NSLock()

  private static func cached(_ ip: String) -> String? {
    geoLock.lock(); defer { geoLock.unlock() }
    return geoCache[ip]
  }

  private static func remember(_ ip: String, _ country: String) {
    geoLock.lock(); defer { geoLock.unlock() }
    geoCache[ip] = country
  }

  static func country(of ip: String) async -> String? {
    if let cached = cached(ip) { return cached }
    let session = session()
    defer { session.invalidateAndCancel() }
    // ipinfo — база, по которой страну определяют многие сайты; country.is — запасная.
    // Базы расходятся: один и тот же адрес VPN бывает «DE» в одной и «US» в другой.
    var found: String?
    if let plain = await text("https://ipinfo.io/\(ip)/country", in: session), plain.count == 2 {
      found = plain
    }
    if found == nil, let json = await text("https://api.country.is/\(ip)", in: session),
       let data = json.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      found = object["country"] as? String
    }
    guard let country = found?.uppercased(), country.count == 2 else { return nil }
    remember(ip, country)
    return country
  }
}

struct View: Equatable {
  let ip: String
  let country: String
}

func flag(_ country: String) -> String {
  let base: UInt32 = 0x1F1E6 - 65
  let scalars = country.uppercased().unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
  return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : country
}

// MARK: - Процессы

struct Proc: Hashable {
  let pid: Int32
  let start: Int64  // время старта — чтобы не отправить сигнал чужому процессу с тем же номером
}

struct ProcInfo {
  let proc: Proc
  let ppid: Int32
  let path: String
  let isStopped: Bool  // уже остановлен кем-то другим (Ctrl-Z в терминале) — не трогаем
}

enum Procs {
  // Все процессы; nil — не удалось прочитать список (тогда ничего не меняем).
  static func list() -> [ProcInfo]? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    let stride = MemoryLayout<kinfo_proc>.stride
    for _ in 0..<3 {  // процессов может стать больше между двумя вызовами — повторяем с запасом
      var size = 0
      guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return nil }
      var items = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 256)
      size = items.count * stride
      guard sysctl(&mib, 4, &items, &size, nil, 0) == 0 else { continue }
      var out: [ProcInfo] = []
      var buffer = [CChar](repeating: 0, count: 4096)
      for item in items.prefix(size / stride) {
        let pid = item.kp_proc.p_pid
        guard pid > 0 else { continue }
        let started = item.kp_proc.p_un.__p_starttime
        let start = Int64(started.tv_sec) * 1_000_000 + Int64(started.tv_usec)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let path = length > 0 ? String(cString: buffer) : ""
        out.append(ProcInfo(proc: Proc(pid: pid, start: start), ppid: item.kp_eproc.e_ppid,
                            path: path, isStopped: Int32(item.kp_proc.p_stat) == SSTOP))
      }
      return out.isEmpty ? nil : out
    }
    return nil
  }

  static func startOf(_ pid: Int32) -> Int64? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var item = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    guard sysctl(&mib, 4, &item, &size, nil, 0) == 0, size > 0, item.kp_proc.p_pid == pid else { return nil }
    let started = item.kp_proc.p_un.__p_starttime
    return Int64(started.tv_sec) * 1_000_000 + Int64(started.tv_usec)
  }

  // Сигнал, только если номер всё ещё принадлежит тому же процессу.
  static func send(_ proc: Proc, _ signal: Int32) {
    guard startOf(proc.pid) == proc.start else { return }
    kill(proc.pid, signal)
  }

  // Процессы программы и всё, что они запустили (у Claude это и Claude Code, и MCP).
  // Программа находится и по пути внутри бандла, и по идентификатору среди запущенных —
  // так ловится и копия из «Загрузок», и запуск через ссылку.
  static func tree(of app: Guarded, in all: [ProcInfo]) -> [ProcInfo] {
    let me = getpid()
    var roots = Set<Int32>()
    let byPID = Dictionary(all.map { ($0.proc.pid, $0) }, uniquingKeysWith: { first, _ in first })
    for item in all where item.path.hasPrefix(app.path + "/") { roots.insert(item.proc.pid) }
    if let bundleID = app.bundleID ?? Bundle(path: app.path)?.bundleIdentifier {
      for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
        roots.insert(running.processIdentifier)
      }
    }
    // Сами программы — никогда не системные; а всё, что они запустили (git, curl, MCP), замораживается.
    roots = roots.filter { byPID[$0].map { !Guarded.isSystem($0.path) } ?? false }
    var picked = roots
    var grew = true
    while grew {
      grew = false
      for item in all where !picked.contains(item.proc.pid) && picked.contains(item.ppid) {
        picked.insert(item.proc.pid)
        grew = true
      }
    }
    return all.filter { picked.contains($0.proc.pid) && $0.proc.pid != me && $0.proc.pid > 1 }
  }
}

// MARK: - Защищаемые программы

struct Guarded: Codable, Hashable {
  let name: String
  let path: String       // путь к .app
  let probe: String?     // сайт, у которого спрашивать, каким адресом видна программа
  var bundleID: String? = nil

  // Известные программы: ищутся среди установленных по идентификатору.
  static let known: [(name: String, bundleID: String, probe: String?)] = [
    ("Claude", "com.anthropic.claudefordesktop", "claude.ai"),
    ("ChatGPT", "com.openai.chat", "chatgpt.com"),
    ("Codex", "com.openai.codex", "chatgpt.com"),
    ("Cursor", "com.todesktop.230313mzl4w4u92", nil),
    ("Perplexity", "ai.perplexity.mac", "www.perplexity.ai"),
    ("Telegram", "ru.keepcoder.Telegram", nil),
    ("Telegram", "org.telegram.desktop", nil),
  ]

  static func installed() -> [Guarded] {
    known.compactMap { item in
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID)
        .map { Guarded(name: item.name, path: $0.path, probe: item.probe, bundleID: item.bundleID) }
    }
  }

  // Системные процессы не замораживаются никогда: замёрзший Dock или loginwindow вешает весь Мак.
  static func isSystem(_ path: String) -> Bool {
    let own = Bundle.main.bundlePath
    return ["/System/Library/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
      || path.hasPrefix(own + "/")
  }

  // Почему эту программу нельзя защищать: системная, сам Cloudex Shield или VPN —
  // замороженный VPN-клиент не сможет переподключиться, и программы не оттают никогда.
  static func refusal(for url: URL) -> String? {
    let path = url.path
    if isSystem(path + "/") || path == Bundle.main.bundlePath { return t("It is a system app or Cloudex Shield itself.", "Это системная программа или сам Cloudex Shield.") }
    let contents = url.appendingPathComponent("Contents")
    if FileManager.default.fileExists(atPath: contents.appendingPathComponent("Library/SystemExtensions").path) {
      return t("Looks like a VPN or network filter: the app has a system extension.", "Похоже на VPN или сетевой фильтр: у программы есть системное расширение.")
    }
    let plugins = contents.appendingPathComponent("PlugIns")
    for appex in (try? FileManager.default.contentsOfDirectory(atPath: plugins.path)) ?? [] {
      let info = NSDictionary(contentsOf: plugins.appendingPathComponent(appex).appendingPathComponent("Contents/Info.plist"))
      let point = (info?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String ?? ""
      if point.hasPrefix("com.apple.networkextension") { return t("It is a VPN or network filter.", "Это VPN или сетевой фильтр.") }
    }
    let name = url.deletingPathExtension().lastPathComponent.lowercased()
    let vpnWords = ["vpn", "wireguard", "clash", "v2ray", "hiddify", "outline", "tunnelblick", "shadowrocket",
                    "surge", "streisand", "nekoray", "foxray", "amnezia", "happ", "sing-box", "proxy"]
    if vpnWords.contains(where: { name.contains($0) }) { return t("By its name it looks like a VPN or proxy.", "По названию похоже на VPN или прокси.") }
    return nil
  }
}

// MARK: - Страж

enum Health { case ok, bad, unknown }

final class NetGuard: @unchecked Sendable {  // состояние трогается только на главном потоке
  static let shared = NetGuard()

  // Настройки
  private let defaults = UserDefaults.standard
  var allowed: Set<String> {
    get { Set(defaults.stringArray(forKey: "allowedCountries") ?? []) }
    set { defaults.set(newValue.sorted(), forKey: "allowedCountries"); enforce() }
  }
  var guarded: [Guarded] {
    get { (defaults.data(forKey: "guardedApps")).flatMap { try? JSONDecoder().decode([Guarded].self, from: $0) } ?? [] }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "guardedApps"); enforce(); schedule() }
  }
  var isEnabled: Bool {
    get { defaults.object(forKey: "guardEnabled") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "guardEnabled"); enforce(); schedule() }
  }
  var pausedUntil: Date? { didSet { enforce(); schedule() } }

  // Что видно снаружи
  private(set) var general: View?             // адрес по сервисам IP
  private(set) var other: View?               // второй сервис назвал другой адрес — признак раздельной маршрутизации
  private(set) var v6: View?                  // адрес IPv6, если он есть
  private(set) var bypass: View?              // адрес мимо системного прокси (терминал, Claude Code), если прокси включён
  private(set) var views: [String: View] = [:] // как нас видят сами сайты (claude.ai, chatgpt.com)
  private(set) var checkedAt: Date?
  private(set) var isChecking = false

  // Заморожено сейчас: процесс → имя программы
  private(set) var frozen: [Proc: String] = [:]
  private var suspect = false  // сеть сменилась, адрес ещё не подтверждён
  private var generation = 0   // растёт при каждой смене сети: результат старой проверки не годится

  var onChange: (() -> Void)?
  private var monitor: NWPathMonitor?
  private var seenFirstPath = false
  private var timer: Timer?
  private var signalSources: [DispatchSourceSignal] = []

  private init() {}

  func start() {
    releaseStale()
    // Перезапуск сборкой (pkill), выход по сигналу — отпускаем всех, а не оставляем замороженными.
    for sig in [SIGTERM, SIGINT, SIGHUP] {
      signal(sig, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
      source.setEventHandler { [weak self] in self?.releaseAll(); exit(0) }
      source.resume()
      signalSources.append(source)
    }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] _ in
      DispatchQueue.main.async { self?.networkChanged() }
    }
    monitor.start(queue: .global(qos: .utility))
    self.monitor = monitor
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.networkChanged() }
    check()
  }

  // Сменилась сеть или Мак проснулся: сразу замораживаем, потом проверяем — так программа
  // не успевает отправить запрос с неправильного адреса.
  private func networkChanged() {
    guard seenFirstPath else { seenFirstPath = true; return }
    generation += 1
    if canFreeze { suspect = true; enforce() }
    check(force: true)
  }

  private var canFreeze: Bool {
    isEnabled && !(pausedUntil.map { $0 > Date() } ?? false) && !allowed.isEmpty && !guarded.isEmpty
  }

  // Чей взгляд решает для программы: её сайт, а если он молчит — общий адрес.
  func health(for app: Guarded) -> Health {
    if suspect { return .unknown }
    if let v6, !allowed.contains(v6.country) { return .bad }  // IPv6 мимо VPN
    if let probe = app.probe, let view = views[probe] { return allowed.contains(view.country) ? .ok : .bad }
    guard let general else { return .unknown }
    if let other, !allowed.contains(other.country) { return .bad }
    return allowed.contains(general.country) ? .ok : .bad
  }

  // Общее состояние для строки меню: худшее по программам; без программ — по общему адресу.
  var overall: Health {
    if allowed.isEmpty { return general == nil && views.isEmpty ? .unknown : .ok }
    let apps = guarded
    if apps.isEmpty {
      guard let country = shownCountry else { return .unknown }
      return allowed.contains(country) ? .ok : .bad
    }
    let states = apps.map(health(for:))
    if states.contains(.bad) { return .bad }
    return states.contains(.unknown) ? .unknown : .ok
  }

  // Страна, которую показываем: так видит Claude, иначе общий адрес.
  var shownCountry: String? { views["claude.ai"]?.country ?? general?.country }

  func check(force: Bool = false) {
    guard !isChecking || force else { return }
    isChecking = true
    let round = generation
    let probes = Set(guarded.compactMap(\.probe)).union(["claude.ai"])
    let proxy = LeakWindow.systemProxy()
    Task.detached { [weak self] in
      let session = Net.session()
      async let first = Net.ip("https://api.ipify.org", v6: false, in: session)
      async let second = Net.ip("https://ipv4.icanhazip.com", v6: false, in: session)
      async let six = Net.ip("https://api6.ipify.org", v6: true, in: session)
      // Сайты — параллельно: на мёртвой сети каждый ждёт до таймаута.
      let seen = await withTaskGroup(of: (String, View?).self) { group in
        for probe in probes { group.addTask { (probe, await Net.trace(probe, in: session)) } }
        var out: [String: View] = [:]
        for await (probe, view) in group { if let view { out[probe] = view } }
        return out
      }
      let (a, b, ip6) = await (first, second, six)
      session.invalidateAndCancel()
      // Страна адреса; если базы молчат, а адрес тот же, что видит claude.ai, — его страна.
      @Sendable func view(of ip: String?) async -> View? {
        guard let ip else { return nil }
        if let country = await Net.country(of: ip) { return View(ip: ip, country: country) }
        if let claude = seen["claude.ai"], claude.ip == ip { return claude }
        return nil
      }
      async let generalView = view(of: a ?? b)
      async let otherView = (a != nil && b != nil && a != b) ? view(of: b) : nil
      async let v6View = view(of: ip6)
      let (general, other, v6) = await (generalView, otherView, v6View)
      // Мимо системного прокси выходят терминал и Claude Code: проверяем, только если прокси включён.
      var bypass: View?
      if proxy != nil {
        let direct = Net.session(direct: true)
        bypass = await view(of: await Net.ip("https://api.ipify.org", v6: false, in: direct))
        direct.invalidateAndCancel()
      }
      let result = (general, other, v6, bypass, seen)
      DispatchQueue.main.async {
        guard let self else { return }
        guard round == self.generation else {  // сеть сменилась, пока шла проверка — ответ устарел
          self.isChecking = false
          self.check()
          return
        }
        self.apply(general: result.0, other: result.1, v6: result.2, bypass: result.3, views: result.4)
      }
    }
  }

  private func apply(general: View?, other: View?, v6: View?, bypass: View?, views: [String: View]) {
    self.general = general
    self.other = other
    self.v6 = v6
    self.bypass = bypass
    self.views = views
    checkedAt = Date()
    isChecking = false
    suspect = false
    enforce()
    schedule()
  }

  // Часто проверяем, только когда это что-то решает: программы заморожены или вот-вот будут.
  // Иначе — раз в 20 секунд, даже если страна не та (например, в поездке с выключенной защитой).
  private func schedule() {
    timer?.invalidate()
    let isUrgent = canFreeze && (!frozen.isEmpty || overall != .ok)
    let interval: TimeInterval = isUrgent ? 3 : 20
    let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.check() }
    timer.tolerance = isUrgent ? 0.5 : 5
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  // Приводит заморозку в соответствие с состоянием.
  func enforce() {
    defer { saveFrozen(); onChange?() }
    let toFreeze = canFreeze ? guarded.filter { health(for: $0) != .ok } : []
    if toFreeze.isEmpty && frozen.isEmpty { return }  // всё спокойно — процессы даже не перебираем
    guard let all = Procs.list() else { return }      // список не прочитался — ничего не меняем
    var wanted: [Proc: String] = [:]
    for app in toFreeze {
      for item in Procs.tree(of: app, in: all) where frozen[item.proc] != nil || !item.isStopped {
        wanted[item.proc] = app.name
      }
    }
    for (proc, _) in frozen where wanted[proc] == nil { Procs.send(proc, SIGCONT) }
    for (proc, _) in wanted where frozen[proc] == nil { Procs.send(proc, SIGSTOP) }
    if frozen.isEmpty && !wanted.isEmpty { NSSound(named: "Funk")?.play() }
    let alive = Set(all.map(\.proc))
    frozen = wanted.filter { alive.contains($0.key) }
  }

  func releaseAll() {
    for proc in frozen.keys { Procs.send(proc, SIGCONT) }
    frozen = [:]
    saveFrozen()
  }

  // Номера замороженных сохраняются: если приложение упало, при следующем старте отпустит их.
  private func saveFrozen() {
    defaults.set(frozen.keys.map { [Int64($0.pid), $0.start] }, forKey: "frozenProcs")
  }

  private func releaseStale() {
    let saved = defaults.array(forKey: "frozenProcs") as? [[Int64]] ?? []
    for pair in saved where pair.count == 2 { Procs.send(Proc(pid: Int32(pair[0]), start: pair[1]), SIGCONT) }
    defaults.removeObject(forKey: "frozenProcs")
  }

  var frozenApps: [String] { Array(Set(frozen.values)).sorted() }
}
