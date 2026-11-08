// Рисует иконку приложения (тот же знак, что в mark.svg: щит и глобус) и собирает AppIcon.icns:
//   swift make-icon.swift && iconutil -c icns AppIcon.iconset
import AppKit

func draw(_ size: CGFloat) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let s = size / 100
  // Поле иконки по сетке macOS: отступ ~10%, скругление ~22%.
  let inset: CGFloat = 10 * s
  let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
  NSColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1).setFill()
  NSBezierPath(roundedRect: tile, xRadius: 18 * s, yRadius: 18 * s).fill()
  // Щит и глобус — как в mark.svg (координаты SVG 0…100, y вниз → AppKit, y вверх).
  let k = tile.width / 100
  func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: tile.minX + x * k, y: tile.maxY - y * k) }
  let shield = NSBezierPath()
  shield.move(to: p(50, 15)); shield.line(to: p(77, 25.5)); shield.line(to: p(77, 47))
  shield.curve(to: p(50, 85), controlPoint1: p(77, 65.5), controlPoint2: p(65, 77.5))
  shield.curve(to: p(23, 47), controlPoint1: p(35, 77.5), controlPoint2: p(23, 65.5))
  shield.line(to: p(23, 25.5)); shield.close()
  shield.lineWidth = 7 * k; shield.lineJoinStyle = .round
  NSColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 1).setStroke()
  shield.stroke()
  let center = p(50, 49)
  NSColor(white: 0.96, alpha: 1).setStroke()
  let globe = NSBezierPath(ovalIn: NSRect(x: center.x - 13 * k, y: center.y - 13 * k, width: 26 * k, height: 26 * k))
  let meridian = NSBezierPath(ovalIn: NSRect(x: center.x - 5.5 * k, y: center.y - 13 * k, width: 11 * k, height: 26 * k))
  let equator = NSBezierPath()
  equator.move(to: NSPoint(x: center.x - 13 * k, y: center.y)); equator.line(to: NSPoint(x: center.x + 13 * k, y: center.y))
  for path in [globe, meridian, equator] { path.lineWidth = 3.2 * k; path.stroke() }
  NSGraphicsContext.restoreGraphicsState()
  return rep
}

let folder = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let rep = draw(CGFloat(base * scale))
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
  }
}
try! draw(512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon-512.png"))
