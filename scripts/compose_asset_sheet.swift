import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fatalError("usage: compose_asset_sheet.swift OUTPUT INPUT...")
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let inputURLs = CommandLine.arguments.dropFirst(2).map(URL.init(fileURLWithPath:))
let columns = 4
let tileSize = NSSize(width: 220, height: 230)
let rows = Int(ceil(Double(inputURLs.count) / Double(columns)))
let canvasSize = NSSize(
    width: tileSize.width * CGFloat(columns),
    height: tileSize.height * CGFloat(rows)
)
let canvas = NSImage(size: canvasSize)

canvas.lockFocus()
NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.91, alpha: 1).setFill()
NSRect(origin: .zero, size: canvasSize).fill()

for (index, inputURL) in inputURLs.enumerated() {
    guard let image = NSImage(contentsOf: inputURL) else { continue }
    let column = index % columns
    let row = index / columns
    let tileOrigin = NSPoint(
        x: CGFloat(column) * tileSize.width,
        y: canvasSize.height - CGFloat(row + 1) * tileSize.height
    )
    let tileRect = NSRect(origin: tileOrigin, size: tileSize).insetBy(dx: 10, dy: 10)
    let cardPath = NSBezierPath(roundedRect: tileRect, xRadius: 18, yRadius: 18)
    NSColor(calibratedWhite: 1, alpha: 0.72).setFill()
    cardPath.fill()

    image.draw(
        in: NSRect(x: tileOrigin.x + 30, y: tileOrigin.y + 38, width: 160, height: 160),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    let label = inputURL.deletingPathExtension().lastPathComponent
        .replacingOccurrences(of: "-", with: " ")
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1),
    ]
    let labelSize = label.size(withAttributes: attributes)
    label.draw(
        at: NSPoint(
            x: tileOrigin.x + (tileSize.width - labelSize.width) / 2,
            y: tileOrigin.y + 16
        ),
        withAttributes: attributes
    )
}
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("unable to encode asset sheet")
}
try png.write(to: outputURL, options: .atomic)
