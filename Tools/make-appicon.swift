#!/usr/bin/env swift
//
// Menü çubuğu sembolünden macOS uygulama ikonu üretir.
// Kullanım: swift Tools/make-appicon.swift Lift/Assets.xcassets/AppIcon.appiconset
//

import AppKit

let symbolName = "cursorarrow.rays"
let sizes: [(px: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("kullanım: make-appicon.swift <appiconset yolu>\n".data(using: .utf8)!)
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])

func renderIcon(pixels: Int) -> Data? {
    let side = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                        pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4,
                                        hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // macOS ikonları tuvalin tamamını doldurmaz; kenarlarda boşluk bırakılır.
    let inset = side * 0.086
    let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let cornerRadius = plate.width * 0.2237   // macOS "squircle" oranı

    let path = NSBezierPath(roundedRect: plate, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.29, green: 0.36, blue: 0.94, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.68, alpha: 1),
    ])
    gradient?.draw(in: path, angle: -90)

    // Sembolü plakanın ortasına, beyaz olarak çiz.
    let glyphSide = plate.width * 0.58
    let configuration = NSImage.SymbolConfiguration(pointSize: glyphSide, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return nil }

    let tinted = NSImage(size: symbol.size, flipped: false) { rect in
        NSColor.white.set()
        rect.fill()
        symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        return true
    }

    let glyphRect = NSRect(x: plate.midX - tinted.size.width / 2,
                           y: plate.midY - tinted.size.height / 2,
                           width: tinted.size.width,
                           height: tinted.size.height)
    tinted.draw(in: glyphRect)

    return bitmap.representation(using: .png, properties: [:])
}

var manifest: [[String: String]] = []
for (pixels, name) in sizes {
    guard let data = renderIcon(pixels: pixels) else {
        FileHandle.standardError.write("render başarısız: \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    let file = outputDirectory.appendingPathComponent("\(name).png")
    try! data.write(to: file)

    let base = name.replacingOccurrences(of: "@2x", with: "")
        .replacingOccurrences(of: "icon_", with: "")
    manifest.append([
        "idiom": "mac",
        "size": base,
        "scale": name.hasSuffix("@2x") ? "2x" : "1x",
        "filename": "\(name).png",
    ])
    print("  \(name).png  (\(pixels)px)")
}

let contents: [String: Any] = [
    "images": manifest,
    "info": ["author": "xcode", "version": 1],
]
let json = try! JSONSerialization.data(withJSONObject: contents,
                                       options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("Contents.json yazıldı")
