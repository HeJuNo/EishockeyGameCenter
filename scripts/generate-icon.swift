#!/usr/bin/env swift
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

// Draws the app icon from flat shapes (no lighting, no rounded corners: the system adds both)
// and exports PNGs (1024) plus flat SVG layers for Icon Composer.
// Usage: swift generate-icon.swift candidates <outdir>
//        swift generate-icon.swift final <design> <outdir>      (design: stick | puck | cross)

enum Role { case mark, accent, accentDark }
enum Shape {
    case line(Double, Double, Double, Double, Double)   // x1 y1 x2 y2 width, round caps
    case rrect(Double, Double, Double, Double, Double)  // x y w h radius
    case ellipse(Double, Double, Double, Double)        // x y w h
}
struct Item { let role: Role; let shape: Shape }
struct Layer { let name: String; let items: [Item] }
struct Palette { let bgTop: String, bgBottom: String, mark: String, accent: String, accentDark: String }

let light = Palette(bgTop: "0f0c29", bgBottom: "302b63", mark: "ffffff", accent: "ff453a", accentDark: "d63031")
let dark = Palette(bgTop: "07061a", bgBottom: "1a1840", mark: "e8eaf6", accent: "ff453a", accentDark: "b8231f")
// Tinted must be strictly gray: the system overlays the user's tint on it.
let tinted = Palette(bgTop: "2a2a2a", bgBottom: "000000", mark: "b0b0b0", accent: "ffffff", accentDark: "8a8a8a")

// A puck seen slightly from above: dark side, then lighter top.
func puck(cx: Double, cy: Double, w: Double, h: Double, thickness: Double) -> [Item] {
    [Item(role: .accentDark, shape: .ellipse(cx - w / 2, cy - h / 2 + thickness, w, h)),
     Item(role: .accentDark, shape: .rrect(cx - w / 2, cy, w, thickness, 0)),
     Item(role: .accent, shape: .ellipse(cx - w / 2, cy - h / 2, w, h))]
}

let designs: [String: [Layer]] = [
    // One stick shooting a puck.
    "stick": [
        Layer(name: "2-stick", items: [
            Item(role: .mark, shape: .line(720, 150, 410, 690, 66)),
            Item(role: .mark, shape: .rrect(330, 664, 340, 84, 42))]),
        Layer(name: "3-puck", items: puck(cx: 790, cy: 704, w: 220, h: 116, thickness: 34))],
    // A big puck on an ice line.
    "puck": [
        Layer(name: "2-ice", items: [Item(role: .mark, shape: .rrect(222, 760, 580, 30, 15))]),
        Layer(name: "3-puck", items: puck(cx: 512, cy: 470, w: 600, h: 320, thickness: 110))],
    // Two crossed sticks over a puck.
    "cross": [
        Layer(name: "2-sticks", items: [
            Item(role: .mark, shape: .line(290, 170, 690, 700, 58)),
            Item(role: .mark, shape: .rrect(630, 676, 220, 70, 35)),
            Item(role: .mark, shape: .line(734, 170, 334, 700, 58)),
            Item(role: .mark, shape: .rrect(174, 676, 220, 70, 35))]),
        Layer(name: "3-puck", items: puck(cx: 512, cy: 820, w: 260, h: 120, thickness: 34))],
]

func rgb(_ hex: String) -> CGColor {
    let v = UInt32(hex, radix: 16)!
    return CGColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
func hexOf(_ role: Role, _ p: Palette) -> String { switch role { case .mark: p.mark; case .accent: p.accent; case .accentDark: p.accentDark } }

func makeContext(opaque: Bool, size: Int = 1024) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)  // top-left origin, 1024 units
    return ctx
}

func drawBackground(_ ctx: CGContext, _ p: Palette) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(p.bgTop), rgb(p.bgBottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func draw(_ layers: [Layer], _ p: Palette, in ctx: CGContext) {
    for item in layers.flatMap(\.items) {
        let color = rgb(hexOf(item.role, p))
        ctx.setFillColor(color); ctx.setStrokeColor(color)
        switch item.shape {
        case let .line(x1, y1, x2, y2, w):
            ctx.setLineCap(.round); ctx.setLineWidth(w)
            ctx.move(to: CGPoint(x: x1, y: y1)); ctx.addLine(to: CGPoint(x: x2, y: y2)); ctx.strokePath()
        case let .rrect(x, y, w, h, r):
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)); ctx.fillPath()
        case let .ellipse(x, y, w, h):
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
        }
    }
}

func svg(_ layer: Layer?, _ p: Palette) -> String {
    var s = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" width=\"1024\" height=\"1024\">\n"
    guard let layer else {
        return s + "<defs><linearGradient id=\"bg\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop offset=\"0\" stop-color=\"#\(p.bgTop)\"/><stop offset=\"1\" stop-color=\"#\(p.bgBottom)\"/></linearGradient></defs>\n<rect width=\"1024\" height=\"1024\" fill=\"url(#bg)\"/>\n</svg>\n"
    }
    for item in layer.items {
        let c = "#" + hexOf(item.role, p)
        switch item.shape {
        case let .line(x1, y1, x2, y2, w): s += "<line x1=\"\(x1)\" y1=\"\(y1)\" x2=\"\(x2)\" y2=\"\(y2)\" stroke=\"\(c)\" stroke-width=\"\(w)\" stroke-linecap=\"round\"/>\n"
        case let .rrect(x, y, w, h, r): s += "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(w)\" height=\"\(h)\" rx=\"\(r)\" fill=\"\(c)\"/>\n"
        case let .ellipse(x, y, w, h): s += "<ellipse cx=\"\(x + w / 2)\" cy=\"\(y + h / 2)\" rx=\"\(w / 2)\" ry=\"\(h / 2)\" fill=\"\(c)\"/>\n"
        }
    }
    return s + "</svg>\n"
}

func png(_ image: CGImage, to path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
}

func icon(_ layers: [Layer], _ p: Palette, size: Int = 1024) -> CGImage {
    let ctx = makeContext(opaque: true, size: size)
    drawBackground(ctx, p); draw(layers, p, in: ctx)
    return ctx.makeImage()!
}

func maxColorSpread(_ image: CGImage) -> Int {
    let ctx = makeContext(opaque: true, size: image.width)
    ctx.concatenate(ctx.ctm.inverted()); ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var spread = 0
    for i in stride(from: 0, to: image.width * image.height * 4, by: 4) {
        spread = max(spread, abs(Int(px[i]) - Int(px[i + 1])), abs(Int(px[i + 1]) - Int(px[i + 2])))
    }
    return spread
}

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: generate-icon.swift candidates <outdir> | final <design> <outdir>"); exit(1) }
let fm = FileManager.default

if args[1] == "candidates" {
    let out = args[2]; try fm.createDirectory(atPath: out, withIntermediateDirectories: true)
    let names = ["stick", "puck", "cross"]
    let w = 3 * 512 + 4 * 24, h = 24 + 512 + 24 + 120 + 24
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(rgb("e5e5ea")); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for (i, name) in names.enumerated() {
        let big = icon(designs[name]!, light), small = icon(designs[name]!, light, size: 120)
        png(big, to: "\(out)/candidate-\(name).png")
        ctx.draw(big, in: CGRect(x: 24 + i * (512 + 24), y: 24 + 120 + 24, width: 512, height: 512))
        ctx.draw(small, in: CGRect(x: 24 + i * (512 + 24) + 196, y: 24, width: 120, height: 120))  // 60 pt @2x
    }
    png(ctx.makeImage()!, to: "\(out)/candidates.png")
    print("wrote \(out)/candidates.png")
} else if args[1] == "final", args.count >= 4, let layers = designs[args[2]] {
    let out = args[3]; try fm.createDirectory(atPath: out + "/layers", withIntermediateDirectories: true)
    for (name, p) in [("light", light), ("dark", dark), ("tinted", tinted)] { png(icon(layers, p), to: "\(out)/AppIcon-\(name).png") }
    try svg(nil, light).write(toFile: "\(out)/layers/1-background.svg", atomically: true, encoding: .utf8)
    for layer in layers { try svg(layer, light).write(toFile: "\(out)/layers/\(layer.name).svg", atomically: true, encoding: .utf8) }
    print("tinted max color spread (must be 0): \(maxColorSpread(icon(layers, tinted)))")
} else { print("unknown design or mode"); exit(1) }
