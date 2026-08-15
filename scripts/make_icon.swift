import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("usage: swift make_icon.swift INPUT.png OUTPUT.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = NSImage(contentsOf: inputURL) else {
    fputs("unable to read source icon\n", stderr)
    exit(1)
}

let canvasSize = NSSize(width: 1024, height: 1024)
let artwork = NSImage(size: canvasSize)
artwork.lockFocus()

NSGraphicsContext.current?.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let tileBounds = NSRect(x: 76, y: 76, width: 872, height: 872)
let tileMask = NSBezierPath(
    roundedRect: tileBounds,
    xRadius: 198,
    yRadius: 198
)
tileMask.addClip()

source.draw(
    in: NSRect(origin: .zero, size: canvasSize),
    from: NSRect(origin: .zero, size: source.size),
    operation: .copy,
    fraction: 1
)

artwork.unlockFocus()

guard let tiff = artwork.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("unable to encode icon\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
