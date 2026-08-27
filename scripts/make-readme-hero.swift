import AppKit
import Foundation

// Bakes the README's hero: the site's art, the site's scrim, the site's
// wordmark. The page gets this composition from CSS at render time; a README
// has no CSS, so the same picture has to be flattened into one file or the
// repo's front door and the website stop looking like the same product.
//
// usage: make-readme-hero.swift OUTPUT ART WORDMARK-PNG

guard CommandLine.arguments.count == 4 else {
    fatalError("usage: make-readme-hero.swift OUTPUT ART WORDMARK-PNG")
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let art = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])),
      let wordmark = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
else { fatalError("could not read the art or the wordmark") }

// Wider than the source, because a README column is wide and short. The art is
// anchored right, exactly as the site anchors it, so the animals stay whole and
// the calm left third — which the art was generated to have — takes the type.
let size = NSSize(width: 1600, height: 620)
// Straight into a bitmap rather than `NSImage.lockFocus`, which leaves the
// focus held while anything reads the image back — the read then fails with a
// CGImageDestination error that names neither the cause nor the lock.
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("could not make the canvas") }

let context = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

NSColor(srgbRed: 0.047, green: 0.169, blue: 0.141, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

// Cover-fit, pinned right.
let artSize = art.size
let scale = max(size.width / artSize.width, size.height / artSize.height)
let scaled = NSSize(width: artSize.width * scale, height: artSize.height * scale)
art.draw(
    in: NSRect(
        x: size.width - scaled.width,
        y: (size.height - scaled.height) / 2,
        width: scaled.width,
        height: scaled.height
    ),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)

// The site's scrim, same stops: opaque at the left so white type is safe,
// gone by three quarters so the animals are never veiled.
let ink = NSColor(srgbRed: 0.027, green: 0.125, blue: 0.102, alpha: 1)
let scrim = NSGradient(
    colors: [
        ink.withAlphaComponent(0.97),
        ink.withAlphaComponent(0.93),
        ink.withAlphaComponent(0.62),
        ink.withAlphaComponent(0),
    ],
    atLocations: [0, 0.34, 0.52, 0.80],
    colorSpace: .sRGB
)
scrim?.draw(in: NSRect(origin: .zero, size: size), angle: 0)

let margin: CGFloat = 96
let columnWidth: CGFloat = 540

/// Lays the block out from the top down, which is how anyone reads it, and
/// converts once at the end. AppKit's origin is bottom-left but `draw(with:)`
/// flows text downward from the *top* of the rect it is given, so positioning
/// by a bottom edge and a guessed height silently stacks the lines in the
/// wrong order — the first attempt printed the subtitle above the headline and
/// through the wordmark.
var cursor = size.height - 140

func drawText(_ text: String, size fontSize: CGFloat, weight: NSFont.Weight, alpha: CGFloat, gap: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineHeightMultiple = 1.22
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: NSColor(srgbRed: 0.957, green: 0.973, blue: 0.957, alpha: alpha),
        .paragraphStyle: paragraph,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let bounds = attributed.boundingRect(
        with: NSSize(width: columnWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin]
    )
    let height = ceil(bounds.height)
    cursor -= height
    attributed.draw(
        with: NSRect(x: margin, y: cursor, width: columnWidth, height: height),
        options: [.usesLineFragmentOrigin]
    )
    cursor -= gap
}

let markWidth: CGFloat = 470
let markHeight = markWidth * (wordmark.size.height / wordmark.size.width)
cursor -= markHeight
wordmark.draw(
    in: NSRect(x: margin, y: cursor, width: markWidth, height: markHeight),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)
cursor -= 44

// The same line the app opens with and the website leads on. Three places
// saying one thing, rather than three products.
drawText(
    "Put your herd to work.",
    size: 38, weight: .semibold, alpha: 1, gap: 22
)
drawText(
    "See the load across your machines and the AI sessions running on them \u{2014} then pick the right one for the next job.",
    size: 23, weight: .regular, alpha: 0.78, gap: 0
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:])
else { fatalError("could not encode the hero") }
try png.write(to: outputURL)
FileHandle.standardError.write("wrote \(outputURL.path)\n".data(using: .utf8)!)
