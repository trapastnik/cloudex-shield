// «Как нас видят»: разовая проверка — что видят разные сайты и программы, утечки IPv6 и DNS,
// часовой пояс против страны IP. Окно заполняется по мере ответов.

import AppKit

struct Line {
  enum Mark { case good, warn, info, none }
  let mark: Mark
  let label: String
  let value: String
}

final class LeakWindow: NSObject, NSWindowDelegate {
  static var current: LeakWindow?

  let window: NSWindow
  let text = NSTextView()
  var sections: [(title: String, lines: [Line])] = []
  var problems: [String] = []
  var isDone = false

  static func show() {
    if let current { current.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
    let leak = LeakWindow()
    current = leak
    leak.run()
  }

  override init() {
    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
                      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    super.init()
    window.title = t("How others see us", "Как нас видят")
    window.isReleasedWhenClosed = false
    window.delegate = self
    let scroll = NSScrollView(frame: window.contentView!.bounds)
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    text.isEditable = false
    text.textContainerInset = NSSize(width: 16, height: 14)
    text.autoresizingMask = [.width]
    text.frame = scroll.bounds
    scroll.documentView = text
    window.contentView?.addSubview(scroll)
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    render()
  }

  func windowWillClose(_ notification: Notification) { LeakWindow.current = nil }

  // Страна «правильная»: в списке разрешённых, а если он пуст — совпадает с тем, что видит Claude.
  func isFine(_ country: String?, reference: String?) -> Bool {
    guard let country else { return false }
    let allowed = NetGuard.shared.allowed
    if !allowed.isEmpty { return allowed.contains(country) }
    return reference == nil || country == reference
  }

  func add(_ title: String, _ lines: [Line]) {
    sections.append((title, lines))
    render()
  }

  func run() {
    Task.detached { [weak self] in
      let viaProxy = Net.session()
      // 1. Сайты сами говорят, с какого адреса к ним пришли.
      let sites = [("Claude", "claude.ai"), ("Claude Code / API", "api.anthropic.com"),
                   ("ChatGPT", "chatgpt.com"), ("Cloudflare 1.1.1.1", "1.1.1.1")]
      var siteViews: [(String, View?)] = []
      for (name, host) in sites { siteViews.append((name, await Net.trace(host, in: viaProxy))) }
      let reference = siteViews.first?.1?.country
      let siteList = siteViews
      await MainActor.run { [weak self] in
        guard let self else { return }
        self.add(t("What sites see", "Что видят сайты"), siteList.map { name, view in
          guard let view else { return Line(mark: .warn, label: name, value: t("no answer", "нет ответа")) }
          let ok = self.isFine(view.country, reference: reference)
          return Line(mark: ok ? .good : .warn, label: name, value: "\(flag(view.country)) \(view.country)  \(view.ip)")
        })
        let countries = Set(siteList.compactMap { $0.1?.country })
        if countries.count > 1 {
          self.problems.append(t("Sites see different countries", "Сайты видят разные страны") + " (\(countries.sorted().joined(separator: ", "))): " + t("your VPN routes part of the traffic another way.", "VPN пускает часть трафика другим путём."))
        }
      }

      // 2. Обычные сервисы определения IP, по одному — расхождение тоже признак утечки.
      let services = ["https://api.ipify.org", "https://ipv4.icanhazip.com", "https://checkip.amazonaws.com", "https://v4.ident.me"]
      var answers: [(String, String?, String?)] = []
      for url in services {
        let ip = await Net.ip(url, v6: false, in: viaProxy)
        let country: String? = ip == nil ? nil : await Net.country(of: ip!)
        answers.append((URL(string: url)?.host ?? url, ip, country))
      }
      let answerList = answers
      await MainActor.run { [weak self] in
        guard let self else { return }
        self.add(t("IP services (IPv4, as browsers and apps)", "Сервисы IP (IPv4, как браузер и приложения)"), answerList.map { host, ip, country in
          guard let ip else { return Line(mark: .warn, label: host, value: t("no answer", "нет ответа")) }
          let ok = self.isFine(country, reference: reference)
          return Line(mark: ok ? .good : .warn, label: host, value: "\(country.map { flag($0) + " " + $0 } ?? "??")  \(ip)")
        })
        if Set(answerList.compactMap { $0.1 }).count > 1 { self.problems.append(t("IP services report different addresses.", "Сервисы IP называют разные адреса.")) }
      }

      // 3. Мимо системного прокси (терминал, git, Claude Code) — только если прокси включён.
      let proxy = Self.systemProxy()
      if let proxy {
        let direct = Net.session(direct: true)
        let claude = await Net.trace("claude.ai", in: direct)
        let plain = await Net.ip("https://api.ipify.org", v6: false, in: direct)
        let plainCountry: String? = plain == nil ? nil : await Net.country(of: plain!)
        direct.invalidateAndCancel()
        await MainActor.run { [weak self] in
          guard let self else { return }
          var lines = [Line(mark: .info, label: t("System proxy", "Системный прокси"), value: proxy)]
          if let claude {
            lines.append(Line(mark: self.isFine(claude.country, reference: reference) ? .good : .warn,
                              label: t("claude.ai direct", "claude.ai напрямую"), value: "\(flag(claude.country)) \(claude.country)  \(claude.ip)"))
          } else {
            lines.append(Line(mark: .info, label: t("claude.ai direct", "claude.ai напрямую"), value: t("no answer — there is no way out around the proxy", "нет ответа — мимо прокси выхода нет")))
          }
          if let plain {
            lines.append(Line(mark: self.isFine(plainCountry, reference: reference) ? .good : .warn,
                              label: t("api.ipify.org direct", "api.ipify.org напрямую"), value: "\(plainCountry.map { flag($0) + " " + $0 } ?? "??")  \(plain)"))
          }
          self.add(t("Apps that ignore the proxy", "Программы мимо прокси"), lines)
          if let claude, !self.isFine(claude.country, reference: reference) {
            self.problems.append(t("Apps that ignore the proxy (terminal, Claude Code) go out through ", "Программы, которые не смотрят на прокси (терминал, Claude Code), выходят через ") + claude.country + ".")
          }
        }
      }

      // 4. IPv6: многие VPN заворачивают только IPv4.
      var six: [(String, String?, String?)] = []
      for url in ["https://api6.ipify.org", "https://ipv6.icanhazip.com"] {
        let ip = await Net.ip(url, v6: true, in: viaProxy)
        let country: String? = ip == nil ? nil : await Net.country(of: ip!)
        six.append((URL(string: url)?.host ?? url, ip, country))
      }
      let sixList = six
      await MainActor.run { [weak self] in
        guard let self else { return }
        if sixList.allSatisfy({ $0.1 == nil }) {
          self.add("IPv6", [Line(mark: .good, label: "IPv6", value: t("not connected — no IPv6 leak", "нет подключения — утечки через IPv6 нет"))])
        } else {
          self.add("IPv6", sixList.map { host, ip, country in
            guard let ip else { return Line(mark: .info, label: host, value: t("no answer", "нет ответа")) }
            let ok = self.isFine(country, reference: reference)
            if !ok { self.problems.append(t("IPv6 bypasses the VPN: ", "IPv6 идёт мимо VPN: ") + "\(country ?? "??") \(ip).") }
            return Line(mark: ok ? .good : .warn, label: host, value: "\(country.map { flag($0) + " " + $0 } ?? "??")  \(ip)")
          })
        }
      }

      // 5. DNS: whoami.akamai.net отвечает адресом того сервера, что задал вопрос.
      let resolver = Self.resolve("whoami.akamai.net")
      var resolverInfo: [String: Any] = [:]
      if let resolver, let json = await Net.text("https://ipinfo.io/\(resolver)/json", in: viaProxy),
         let data = json.data(using: .utf8),
         let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        resolverInfo = object
      }
      // 6. Часовой пояс адреса — для сравнения с часами Мака.
      var hereInfo: [String: Any] = [:]
      if let json = await Net.text("https://ipinfo.io/json", in: viaProxy),
         let data = json.data(using: .utf8),
         let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        hereInfo = object
      }
      viaProxy.invalidateAndCancel()
      let resolverFacts = resolverInfo
      let hereFacts = hereInfo
      await MainActor.run { [weak self] in
        guard let self else { return }
        if let resolver {
          let country = resolverFacts["country"] as? String
          let org = resolverFacts["org"] as? String ?? ""
          let ok = self.isFine(country, reference: reference)
          self.add("DNS", [Line(mark: ok ? .good : .warn, label: t("DNS server", "Сервер DNS"),
                                value: "\(country.map { flag($0) + " " + $0 } ?? "??")  \(resolver)  \(org)")])
          if !ok, let country { self.problems.append(t("DNS queries go through \(country): your provider may see which sites you open.", "Запросы DNS уходят через \(country): провайдер может видеть, какие сайты вы открываете.")) }
        } else {
          self.add("DNS", [Line(mark: .info, label: t("DNS server", "Сервер DNS"), value: t("could not detect", "не удалось определить"))])
        }

        let localZone = TimeZone.current
        var zoneLines = [Line(mark: .info, label: t("Mac clock", "Часы Мака"), value: "\(localZone.identifier)  UTC\(Self.offset(localZone))")]
        if let ipZoneName = hereFacts["timezone"] as? String, let ipZone = TimeZone(identifier: ipZoneName) {
          let same = ipZone.secondsFromGMT() == localZone.secondsFromGMT()
          zoneLines.append(Line(mark: same ? .good : .warn, label: t("Time zone of the IP", "Пояс по адресу IP"), value: "\(ipZoneName)  UTC\(Self.offset(ipZone))"))
          if !same { self.problems.append(t("Your Mac’s time zone (UTC\(Self.offset(localZone))) differs from the IP’s (UTC\(Self.offset(ipZone))); sites can notice that.", "Часовой пояс Мака (UTC\(Self.offset(localZone))) не совпадает с поясом страны IP (UTC\(Self.offset(ipZone))); сайты могут это заметить.")) }
        }
        let region = Locale.current.region?.identifier ?? "?"
        let languages = Locale.preferredLanguages.prefix(3).joined(separator: ", ")
        zoneLines.append(Line(mark: .info, label: t("System region and languages", "Регион и языки системы"), value: "\(region) · \(languages)"))
        self.add(t("Time zone and language", "Часовой пояс и язык"), zoneLines)
        self.isDone = true
        self.render()
      }
    }
  }

  // Системный прокси (HTTPS или SOCKS), как его видит macOS; nil — не задан.
  static func systemProxy() -> String? {
    guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return nil }
    for (enable, host, port) in [(kCFNetworkProxiesHTTPSEnable, kCFNetworkProxiesHTTPSProxy, kCFNetworkProxiesHTTPSPort),
                                 (kCFNetworkProxiesSOCKSEnable, kCFNetworkProxiesSOCKSProxy, kCFNetworkProxiesSOCKSPort),
                                 (kCFNetworkProxiesHTTPEnable, kCFNetworkProxiesHTTPProxy, kCFNetworkProxiesHTTPPort)] {
      if (settings[enable as String] as? Int) == 1, let name = settings[host as String] as? String {
        return "\(name):\(settings[port as String] as? Int ?? 0)"
      }
    }
    return nil
  }

  // Системный резолвер, как у любой программы.
  static func resolve(_ host: String) -> String? {
    var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                         ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
    defer { freeaddrinfo(result) }
    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    guard getnameinfo(first.pointee.ai_addr, first.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
    else { return nil }
    return String(cString: buffer)
  }

  static func offset(_ zone: TimeZone) -> String {
    let minutes = zone.secondsFromGMT() / 60
    let sign = minutes >= 0 ? "+" : "−"
    return minutes % 60 == 0 ? "\(sign)\(abs(minutes) / 60)" : String(format: "%@%d:%02d", sign, abs(minutes) / 60, abs(minutes) % 60)
  }

  func render() {
    let out = NSMutableAttributedString()
    let body = NSFont.systemFont(ofSize: 13)
    let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let head = NSFont.boldSystemFont(ofSize: 14)
    let gray = NSColor.secondaryLabelColor

    if isDone {
      let verdict = problems.isEmpty ? t("✓ No leaks found", "✓ Утечек не видно") : t("⚠︎ Found: ", "⚠︎ Найдено: ") + "\(problems.count)"
      out.append(NSAttributedString(string: verdict + "\n", attributes: [
        .font: NSFont.boldSystemFont(ofSize: 16),
        .foregroundColor: problems.isEmpty ? NSColor.systemGreen : NSColor.systemOrange,
      ]))
      for problem in problems {
        out.append(NSAttributedString(string: "• " + problem + "\n", attributes: [.font: body, .foregroundColor: NSColor.labelColor]))
      }
      out.append(NSAttributedString(string: "\n"))
    } else {
      out.append(NSAttributedString(string: t("Checking…", "Проверяю…") + "\n\n", attributes: [.font: head, .foregroundColor: gray]))
    }

    for section in sections {
      out.append(NSAttributedString(string: section.title + "\n", attributes: [.font: head, .foregroundColor: NSColor.labelColor]))
      for line in section.lines {
        let (mark, color): (String, NSColor) = {
          switch line.mark {
          case .good: return ("✓ ", .systemGreen)
          case .warn: return ("⚠︎ ", .systemOrange)
          case .info: return ("· ", gray)
          case .none: return ("  ", gray)
          }
        }()
        out.append(NSAttributedString(string: mark, attributes: [.font: body, .foregroundColor: color]))
        out.append(NSAttributedString(string: line.label.padding(toLength: 26, withPad: " ", startingAt: 0), attributes: [.font: mono, .foregroundColor: gray]))
        out.append(NSAttributedString(string: line.value + "\n", attributes: [.font: mono, .foregroundColor: NSColor.labelColor]))
      }
      out.append(NSAttributedString(string: "\n"))
    }
    text.textStorage?.setAttributedString(out)
  }
}
