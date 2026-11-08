// Тест скорости по кнопке: загрузка и отдача через speed.cloudflare.com, задержка до Claude,
// его API и ChatGPT. В фоне ничего не гоняет — только когда попросили.

import Foundation

struct SpeedResult {
  let down: Double?               // Мбит/с
  let up: Double?
  let pings: [(String, Int?)]     // сайт → мс
  let at: Date
}

final class SpeedTest: @unchecked Sendable {  // состояние трогается только на главном потоке
  static let shared = SpeedTest()
  private(set) var last: SpeedResult?
  private(set) var isRunning = false
  var onChange: (() -> Void)?

  static let targets = [("Claude", "claude.ai"), ("API", "api.anthropic.com"), ("ChatGPT", "chatgpt.com")]

  func run() {
    guard !isRunning else { return }
    isRunning = true
    onChange?()
    Task.detached { [weak self] in
      var pings: [(String, Int?)] = []
      for (name, host) in Self.targets { pings.append((name, await Self.ping(host))) }
      let down = await Self.download()
      let up = await Self.upload()
      let result = SpeedResult(down: down, up: up, pings: pings, at: Date())
      DispatchQueue.main.async {
        self?.last = result
        self?.isRunning = false
        self?.onChange?()
      }
    }
  }

  // Задержка: лучший из трёх запросов в уже открытом соединении — без времени на TLS,
  // так видно сам путь до сайта, а не установку соединения.
  static func ping(_ host: String) async -> Int? {
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    guard let url = URL(string: "https://\(host)/cdn-cgi/trace") else { return nil }
    var best: Double?
    for attempt in 0..<4 {
      var request = URLRequest(url: url, timeoutInterval: 5)
      request.setValue("curl/8.7.1", forHTTPHeaderField: "User-Agent")
      let started = Date()
      guard (try? await session.data(for: request)) != nil else { return nil }
      let took = Date().timeIntervalSince(started)
      if attempt > 0 { best = min(best ?? took, took) }  // первый запрос открывает соединение
    }
    return best.map { Int(($0 * 1000).rounded()) }
  }

  // Сессия с жёстким потолком на весь запрос: медленный канал не растягивает тест.
  static func capped(_ seconds: TimeInterval) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = seconds
    config.timeoutIntervalForResource = seconds
    return URLSession(configuration: config)
  }

  // Загрузка: до 25 МБ или 6 секунд, что раньше.
  static func download() async -> Double? {
    guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000") else { return nil }
    let session = capped(10)
    defer { session.invalidateAndCancel() }
    let started = Date()
    guard let (bytes, _) = try? await session.bytes(from: url) else { return nil }
    var count = 0
    do {
      for try await _ in bytes {
        count += 1
        if count % 65536 == 0 && Date().timeIntervalSince(started) > 6 { break }
      }
    } catch {}
    let seconds = Date().timeIntervalSince(started)
    return count > 0 && seconds > 0 ? Double(count) * 8 / seconds / 1_000_000 : nil
  }

  // Отдача: 1,5 МБ, не дольше 15 секунд — у VPN отдача часто в разы медленнее загрузки.
  static func upload() async -> Double? {
    guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return nil }
    let session = capped(15)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    let payload = Data(count: 1_500_000)
    let started = Date()
    guard let (_, response) = try? await session.upload(for: request, from: payload),
          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    let seconds = Date().timeIntervalSince(started)
    return Double(payload.count) * 8 / seconds / 1_000_000
  }

  // Одна строка для меню: «↓48 ↑12 Мбит/с · Claude 180 · API 210 · ChatGPT 160 мс · 12:05».
  var summary: String {
    if isRunning { return t("Speed test: measuring…", "Тест скорости: замеряю…") }
    guard let last else { return t("Speed test", "Тест скорости") }
    let speed = (last.down.map { String(format: "↓%.0f", $0) } ?? "↓—") + " " + (last.up.map { String(format: "↑%.0f", $0) } ?? "↑—") + t(" Mbps", " Мбит/с")
    let pings = last.pings.map { "\($0.0) \($0.1.map(String.init) ?? "—")" }.joined(separator: " · ")
    return "\(speed) · \(pings) \(t("ms", "мс")) · \(App.clock(last.at))"
  }
}
