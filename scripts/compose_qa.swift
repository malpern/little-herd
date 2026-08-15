import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    fatalError("usage: compose_qa.swift SOURCE IMPLEMENTATION OUTPUT")
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let implementationURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

guard let source = NSImage(contentsOf: sourceURL),
      let implementation = NSImage(contentsOf: implementationURL)
else {
    fatalError("unable to read QA images")
}

let height: CGFloat = 842
let sourceWidth = round(source.size.width / source.size.height * height)
let implementationWidth = round(
    implementation.size.width / implementation.size.height * height
)
let gap: CGFloat = 32
let canvasSize = NSSize(
    width: sourceWidth + gap + implementationWidth,
    height: height
)
let canvas = NSImage(size: canvasSize)

canvas.lockFocus()
NSColor(calibratedWhite: 0.91, alpha: 1).setFill()
NSRect(origin: .zero, size: canvasSize).fill()
source.draw(
    in: NSRect(x: 0, y: 0, width: sourceWidth, height: height),
    from: .zero,
    operation: .copy,
    fraction: 1
)
implementation.draw(
    in: NSRect(
        x: sourceWidth + gap,
        y: 0,
        width: implementationWidth,
        height: height
    ),
    from: .zero,
    operation: .copy,
    fraction: 1
)
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("unable to encode QA comparison")
}
try png.write(to: outputURL, options: .atomic)
