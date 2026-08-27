import AppKit
import CoreText
import Foundation

// mark2.swift <font.ttf> <wght> <text> <out.svg> <dot-hex>
// Outlines the text, then lifts the tittle off the "i" and replaces it with a
// circle -- the app's own "this machine is live" dot.
let a = CommandLine.arguments
let descs = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: a[1]) as CFURL) as! [CTFontDescriptor]
let desc = CTFontDescriptorCreateCopyWithAttributes(descs[0],
    [kCTFontVariationAttribute: [0x77676874: Double(a[2])!]] as CFDictionary)
let font = CTFontCreateWithFontDescriptor(desc, 200, nil)
let line = CTLineCreateWithAttributedString(NSAttributedString(string: a[3], attributes: [.font: font]))

let combined = CGMutablePath()
for run in (CTLineGetGlyphRuns(line) as! [CTRun]) {
    let n = CTRunGetGlyphCount(run)
    var gs = [CGGlyph](repeating: 0, count: n), ps = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRangeMake(0, n), &gs); CTRunGetPositions(run, CFRangeMake(0, n), &ps)
    let rf = unsafeBitCast(CFDictionaryGetValue(CTRunGetAttributes(run),
             unsafeBitCast(kCTFontAttributeName, to: UnsafeRawPointer.self)), to: CTFont.self)
    for i in 0..<n {
        if let p = CTFontCreatePathForGlyph(rf, gs[i], nil) {
            combined.addPath(p, transform: CGAffineTransform(translationX: ps[i].x, y: ps[i].y))
        }
    }
}
let bb = combined.boundingBox
let flipped = CGMutablePath()
flipped.addPath(combined, transform: CGAffineTransform(scaleX: 1, y: -1)
    .translatedBy(x: -bb.minX, y: -bb.maxY))

// split into subpaths so the tittle can be pulled out
struct Sub { var d = ""; var pts: [CGPoint] = [] }
var subs: [Sub] = []
flipped.applyWithBlock { el in
    let p = el.pointee.points
    switch el.pointee.type {
    case .moveToPoint:
        subs.append(Sub(d: String(format: "M%.1f %.1f", p[0].x, p[0].y), pts: [p[0]]))
    case .addLineToPoint:
        subs[subs.count-1].d += String(format: "L%.1f %.1f", p[0].x, p[0].y); subs[subs.count-1].pts.append(p[0])
    case .addQuadCurveToPoint:
        subs[subs.count-1].d += String(format: "Q%.1f %.1f %.1f %.1f", p[0].x,p[0].y,p[1].x,p[1].y)
        subs[subs.count-1].pts += [p[0], p[1]]
    case .addCurveToPoint:
        subs[subs.count-1].d += String(format: "C%.1f %.1f %.1f %.1f %.1f %.1f", p[0].x,p[0].y,p[1].x,p[1].y,p[2].x,p[2].y)
        subs[subs.count-1].pts += [p[0], p[1], p[2]]
    case .closeSubpath: subs[subs.count-1].d += "Z"
    @unknown default: break
    }
}
func box(_ s: Sub) -> CGRect {
    let xs = s.pts.map(\.x), ys = s.pts.map(\.y)
    return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()!-xs.min()!, height: ys.max()!-ys.min()!)
}
let W = bb.width, H = bb.height
// the tittle: small, roughly square, sitting in the top third, left of centre
let idx = subs.indices.filter { i in
    let r = box(subs[i])
    return r.width < W*0.06 && r.height < H*0.30 && r.maxY < H*0.42
        && abs(r.width - r.height) < max(r.width, r.height)*0.45 && r.midX < W*0.5
}
guard idx.count == 1 else {
    fatalError("expected exactly one tittle, found \(idx.count): \(idx.map { box(subs[$0]) })")
}
let t = box(subs[idx[0]])
let letters = subs.indices.filter { $0 != idx[0] }.map { subs[$0].d }.joined()
// grow the dot a little: a status light should read as deliberate, not as a tittle
let r = max(t.width, t.height)/2 * 1.12

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(Int(W.rounded())) \(Int(H.rounded()))" \
role="img" aria-label="\(a[3])"><path fill="currentColor" d="\(letters)"/>\
<circle cx="\(String(format: "%.1f", t.midX))" cy="\(String(format: "%.1f", t.midY))" \
r="\(String(format: "%.1f", r))" fill="\(a[5])"/></svg>
"""
try! svg.write(to: URL(fileURLWithPath: a[4]), atomically: true, encoding: .utf8)
print("tittle at \(Int(t.midX)),\(Int(t.midY)) r=\(Int(r)) — box \(Int(W))x\(Int(H)), \(svg.count) bytes")
