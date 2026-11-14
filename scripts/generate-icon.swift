#!/usr/bin/env swift
import AppKit
import CoreGraphics
import CoreText
import UniformTypeIdentifiers

// Draws the app icon from flat shapes: a blue/red split along the player silhouette (player.json holds its contours and the
// divider line, in source pixels), with the initials GC. No lighting and no rounded corners: the system adds both.
// Usage: swift generate-icon.swift player.json <outdir>
// Writes AppIcon-light/dark/tinted.png (1024, opaque) and flat SVG layers for Icon Composer in <outdir>/layers.

typealias P = (x: Double, y: Double)
enum Fill { case blue, red, white }
struct Palette { let blue: String, red: String, white: String }
let light = Palette(blue: "113e73", red: "dc4b31", white: "ffffff")
let dark = Palette(blue: "0a2347", red: "b8391f", white: "eef1fa")
// Tinted must be strictly gray: the system overlays the user's tint on it.
let tinted = Palette(blue: "1f1f1f", red: "6c6c6c", white: "ffffff")

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func hexValue(_ f: Fill, _ p: Palette) -> String { switch f { case .blue: p.blue; case .red: p.red; case .white: p.white } }
func color(_ f: Fill, _ p: Palette) -> CGColor {
    let v = UInt32(hexValue(f, p), radix: 16)!
    return CGColor(colorSpace: srgb, components: [CGFloat((v >> 16) & 255) / 255, CGFloat((v >> 8) & 255) / 255, CGFloat(v & 255) / 255, 1])!
}

// MARK: geometry
let square: [P] = [(0, 0), (1024, 0), (1024, 1024), (0, 1024)]
func clip(_ poly: [P], _ p1: P, _ p2: P, left: Bool) -> [P] {
    func side(_ p: P) -> Double { let c = (p2.x - p1.x) * (p.y - p1.y) - (p2.y - p1.y) * (p.x - p1.x); return left ? c : -c }
    var out: [P] = []
    for i in 0..<poly.count {
        let a = poly[i], b = poly[(i + 1) % poly.count], sa = side(a), sb = side(b)
        if sa >= 0 { out.append(a) }
        if (sa >= 0) != (sb >= 0) { let t = sa / (sa - sb); out.append((a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)) }
    }
    return out
}
let fontName = ["HelveticaNeue-CondensedBlack", "Impact", "Arial-BoldMT"].first { NSFont(name: $0, size: 10) != nil }!
/// Outlined italic text centered at (cx, cy), scaled to the given cap height (so the SVG needs no font).
func textPath(_ s: String, height: Double, cx: Double, cy: Double, tracking: CGFloat = 0, slant: Double = 0.2) -> CGPath {
    let font = CTFontCreateWithName(fontName as CFString, 100, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .kern: tracking]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let n = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs); CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
        let runFont = (CTRunGetAttributes(run) as! [CFString: Any])[kCTFontAttributeName] as! CTFont
        for i in 0..<n { if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) { path.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y)) } }
    }
    let b = path.boundingBox, k = height / Double(b.height)
    var t = CGAffineTransform(translationX: -b.midX, y: -b.midY).concatenating(CGAffineTransform(scaleX: k, y: -k))
        .concatenating(CGAffineTransform(a: 1, b: 0, c: -slant, d: 1, tx: 0, ty: 0)).concatenating(CGAffineTransform(translationX: cx, y: cy))
    return path.copy(using: &t)!
}
func svgD(_ path: CGPath) -> String {
    var d = ""
    func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    path.applyWithBlock { e in
        let p = e.pointee.points
        switch e.pointee.type {
        case .moveToPoint: d += "M\(f(p[0].x)) \(f(p[0].y)) "
        case .addLineToPoint: d += "L\(f(p[0].x)) \(f(p[0].y)) "
        case .addQuadCurveToPoint: d += "Q\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) "
        case .addCurveToPoint: d += "C\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) \(f(p[2].x)) \(f(p[2].y)) "
        case .closeSubpath: d += "Z "
        @unknown default: break
        }
    }
    return d
}

// MARK: the design
let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: generate-icon.swift player.json <outdir>"); exit(1) }
let data = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String: Any]
let polys = data["polygons"] as! [[[Double]]]
let plaque = (data["plaque"] as! [Int]).map(Double.init)   // x0 y0 x1 y1
let divider = data["divider"] as! [Double]                 // x = a + b * y
let bbox = (data["bbox"] as! [Int]).map(Double.init)

// The player is used unchanged (only scaled uniformly): its height fills the canvas, as it fills the plaque of the reference.
let scale = 1024 / (plaque[3] - plaque[1]), left = 70.0
func map(_ x: Double, _ y: Double) -> P { (left + (x - bbox[0]) * scale, (y - plaque[1]) * scale) }

let playerPath: CGPath = {
    let path = CGMutablePath()
    for poly in polys { let pts = poly.map { map($0[0], $0[1]) }.map { CGPoint(x: $0.x, y: $0.y) }; path.addLines(between: pts); path.closeSubpath() }
    return path
}()
let initialsPath = textPath("GC", height: 235, cx: 780, cy: 300, tracking: 4)
let lineA = map(divider[0] + divider[1] * -2000, -2000), lineB = map(divider[0] + divider[1] * 4000, 4000)
let bluePoly = clip(square, lineA, lineB, left: true), redPoly = clip(square, lineA, lineB, left: false)

// MARK: output
func render(_ p: Palette) -> CGImage {
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: 1, y: -1)
    for (fill, poly) in [(Fill.blue, bluePoly), (Fill.red, redPoly)] {
        ctx.setFillColor(color(fill, p)); ctx.addLines(between: poly.map { CGPoint(x: $0.x, y: $0.y) }); ctx.closePath(); ctx.fillPath()
    }
    ctx.setFillColor(color(.white, p))
    ctx.addPath(playerPath); ctx.fillPath(using: .evenOdd)
    ctx.addPath(initialsPath); ctx.fillPath(using: .evenOdd)
    return ctx.makeImage()!
}
func png(_ image: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
}
func maxColorSpread(_ image: CGImage) -> Int {
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let px = ctx.data!.assumingMemoryBound(to: UInt8.self), stride = ctx.bytesPerRow
    var spread = 0
    for y in 0..<image.height { for x in 0..<image.width { let i = y * stride + x * 4; spread = max(spread, abs(Int(px[i]) - Int(px[i + 1])), abs(Int(px[i + 1]) - Int(px[i + 2]))) } }
    return spread
}

let out = args[2]
try FileManager.default.createDirectory(atPath: out + "/layers", withIntermediateDirectories: true)
for (name, p) in [("light", light), ("dark", dark), ("tinted", tinted)] { png(render(p), "\(out)/AppIcon-\(name).png") }
func pts(_ poly: [P]) -> String { poly.map { String(format: "%.2f,%.2f", $0.x, $0.y) }.joined(separator: " ") }
let head = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" width=\"1024\" height=\"1024\">\n"
try (head + "<polygon points=\"\(pts(bluePoly))\" fill=\"#\(light.blue)\"/>\n<polygon points=\"\(pts(redPoly))\" fill=\"#\(light.red)\"/>\n</svg>\n")
    .write(toFile: "\(out)/layers/1-background.svg", atomically: true, encoding: .utf8)
try (head + "<path d=\"\(svgD(playerPath))\" fill=\"#\(light.white)\" fill-rule=\"evenodd\"/>\n</svg>\n").write(toFile: "\(out)/layers/2-player.svg", atomically: true, encoding: .utf8)
try (head + "<path d=\"\(svgD(initialsPath))\" fill=\"#\(light.white)\" fill-rule=\"evenodd\"/>\n</svg>\n").write(toFile: "\(out)/layers/3-initials.svg", atomically: true, encoding: .utf8)
print("tinted max color spread (must be 0): \(maxColorSpread(render(tinted)))")
