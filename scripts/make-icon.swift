import AppKit

// Генератор иконки приложения: рисует набор PNG для .iconset, дальше iconutil соберёт .icns.
// Запуск: swift scripts/make-icon.swift  (вызывается из build.sh).

let outDir = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Цвета фонового градиента и красного «kill»-акцента.
let gradientTop = NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.42, alpha: 1)   // индиго
let gradientBottom = NSColor(calibratedRed: 0.09, green: 0.55, blue: 0.62, alpha: 1) // бирюза
let killRed = NSColor(calibratedRed: 0.90, green: 0.20, blue: 0.20, alpha: 1)

/// Перекрашивает template-символ в сплошной цвет через sourceAtop.
func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    color.set()
    let rect = NSRect(origin: .zero, size: image.size)
    image.draw(in: rect)
    rect.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg)
}

func drawCentered(_ image: NSImage, in box: NSRect) {
    let s = image.size
    let origin = NSPoint(x: box.midX - s.width / 2, y: box.midY - s.height / 2)
    image.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
}

func renderIcon(size: CGFloat) -> Data? {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    // Скруглённый квадрат (squircle-ish) + градиент.
    let radius = size * 0.225
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    bg.addClip()
    NSGradient(colors: [gradientTop, gradientBottom])?.draw(in: bg, angle: -90)

    // Основной глиф — network, белым, крупно.
    if let net = symbol("network", pointSize: size * 0.52, weight: .semibold) {
        drawCentered(tinted(net, .white), in: rect)
    }

    // Красный «kill»-бейдж в правом нижнем углу: круг + белый xmark.
    let badgeD = size * 0.42
    let badgeRect = NSRect(x: size - badgeD * 0.92, y: size * 0.06,
                           width: badgeD, height: badgeD)
    // Тонкая тёмная подложка-обводка, чтобы бейдж не сливался с фоном.
    let ringRect = badgeRect.insetBy(dx: -size * 0.02, dy: -size * 0.02)
    NSColor(calibratedWhite: 0.05, alpha: 0.55).setFill()
    NSBezierPath(ovalIn: ringRect).fill()
    killRed.setFill()
    NSBezierPath(ovalIn: badgeRect).fill()
    if let x = symbol("xmark", pointSize: badgeD * 0.58, weight: .bold) {
        drawCentered(tinted(x, .white), in: badgeRect)
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        return nil
    }
    return png
}

// Имена файлов iconset: базовый размер + @2x.
let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for v in variants {
    guard let data = renderIcon(size: v.size) else {
        FileHandle.standardError.write(Data("не смог отрендерить \(v.name)\n".utf8))
        exit(1)
    }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(v.name)"))
}

print("iconset готов: \(outDir)")
