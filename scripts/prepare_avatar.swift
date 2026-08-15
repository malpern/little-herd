import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 4,
      let outputSize = Int(CommandLine.arguments[3]),
      outputSize > 0
else {
    fputs("usage: swift prepare_avatar.swift INPUT.png OUTPUT.png SIZE\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("unable to read source image\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
let pixelCount = height * bytesPerRow
let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
pixels.initialize(repeating: 0, count: pixelCount)
defer {
    pixels.deinitialize(count: pixelCount)
    pixels.deallocate()
}
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    | CGBitmapInfo.byteOrder32Big.rawValue

guard let context = CGContext(
    data: pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fputs("unable to create bitmap context\n", stderr)
    exit(1)
}

context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

if ProcessInfo.processInfo.environment["AVATAR_DEBUG"] == "1" {
    let samples = [(0, 0), (width / 2, height / 2), (width / 2, height / 4)]
    for (sampleX, sampleY) in samples {
        let sampleIndex = sampleY * bytesPerRow + sampleX * bytesPerPixel
        fputs("sample \(sampleX),\(sampleY): \(pixels[sampleIndex]),\(pixels[sampleIndex + 1]),\(pixels[sampleIndex + 2]),\(pixels[sampleIndex + 3])\n", stderr)
    }
}

// Image generation slightly softens the requested #FF00FF matte. Treat that
// near-magenta field as transparent while preserving warm reds in the art.
let transparentDistance = 70.0
let opaqueDistance = 170.0
var minX = width
var minY = height
var maxX = -1
var maxY = -1

for y in 0 ..< height {
    for x in 0 ..< width {
        let index = y * bytesPerRow + x * bytesPerPixel
        let red = Double(pixels[index])
        let green = Double(pixels[index + 1])
        let blue = Double(pixels[index + 2])
        let originalAlpha = Double(pixels[index + 3]) / 255.0
        let distance = sqrt(
            pow(red - 255.0, 2)
                + pow(green, 2)
                + pow(blue - 255.0, 2)
        )

        let normalized = min(
            max((distance - transparentDistance) / (opaqueDistance - transparentDistance), 0),
            1
        )
        let smooth = normalized * normalized * (3 - 2 * normalized)
        let alpha = UInt8((255.0 * originalAlpha * smooth).rounded())
        pixels[index] = UInt8((red * smooth).rounded())
        pixels[index + 1] = UInt8((green * smooth).rounded())
        pixels[index + 2] = UInt8((blue * smooth).rounded())
        pixels[index + 3] = alpha

        if alpha > 12 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
}

guard minX <= maxX, minY <= maxY else {
    fputs("no foreground subject found\n", stderr)
    exit(1)
}

guard let keyedContext = CGContext(
    data: pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: bitmapInfo
), let keyedImage = keyedContext.makeImage() else {
    fputs("unable to create chroma-keyed image\n", stderr)
    exit(1)
}

let subjectRect = CGRect(
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1
)

guard let croppedImage = keyedImage.cropping(to: subjectRect) else {
    fputs("unable to crop foreground subject\n", stderr)
    exit(1)
}

let outputWidth = outputSize
let outputHeight = outputSize
let outputBytesPerRow = outputWidth * bytesPerPixel
let outputPixelCount = outputHeight * outputBytesPerRow
let outputPixels = UnsafeMutablePointer<UInt8>.allocate(capacity: outputPixelCount)
outputPixels.initialize(repeating: 0, count: outputPixelCount)
defer {
    outputPixels.deinitialize(count: outputPixelCount)
    outputPixels.deallocate()
}

guard let outputContext = CGContext(
    data: outputPixels,
    width: outputWidth,
    height: outputHeight,
    bitsPerComponent: 8,
    bytesPerRow: outputBytesPerRow,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fputs("unable to create output context\n", stderr)
    exit(1)
}

outputContext.interpolationQuality = .high
let padding = CGFloat(outputSize) * 0.08
let available = CGFloat(outputSize) - padding * 2
let scale = min(
    available / CGFloat(croppedImage.width),
    available / CGFloat(croppedImage.height)
)
let drawWidth = CGFloat(croppedImage.width) * scale
let drawHeight = CGFloat(croppedImage.height) * scale
let drawRect = CGRect(
    x: (CGFloat(outputSize) - drawWidth) / 2,
    y: (CGFloat(outputSize) - drawHeight) / 2,
    width: drawWidth,
    height: drawHeight
)
outputContext.draw(croppedImage, in: drawRect)

guard let outputImage = outputContext.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL,
          UTType.png.identifier as CFString,
          1,
          nil
      )
else {
    fputs("unable to create PNG destination\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("unable to write PNG\n", stderr)
    exit(1)
}
