//
//  make_appicon.swift
//  EU Enabler
//
//  Converts a "rounded square on a white background" artwork into a full-bleed,
//  opaque 1024x1024 app icon. iOS applies its own corner mask to app icons, so
//  shipping the white surround would show as white corners on the Home Screen.
//
//  It flood-fills the white surround (starting from the edges) with the icon's
//  dominant background colour. The artwork is enclosed by the rounded square, so
//  interior white -- the phone outline -- is left untouched.
//
//  Usage: swift scripts/make_appicon.swift <input.png> <output.png>
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: make_appicon.swift <in.png> <out.png>\n".data(using: .utf8)!)
    exit(2)
}

let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

guard let source = CGImageSourceCreateWithURL(inURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("failed to read input image\n".data(using: .utf8)!)
    exit(1)
}

let width = image.width
let height = image.height
let rowBytes = width * 4

let scratch = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: 16)
defer { scratch.deallocate() }
let px = scratch.assumingMemoryBound(to: UInt8.self)

guard let ctx = CGContext(data: scratch,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: rowBytes,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}
ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

// 1. Dominant non-white colour == the icon's background.
var histogram: [UInt32: Int] = [:]
for i in stride(from: 0, to: rowBytes * height, by: 4) {
    let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
    if r > 235 && g > 235 && b > 235 { continue }
    histogram[UInt32(r << 16 | g << 8 | b), default: 0] += 1
}

guard let dominant = histogram.max(by: { $0.value < $1.value })?.key else {
    FileHandle.standardError.write("could not determine background colour\n".data(using: .utf8)!)
    exit(1)
}

let bgR = UInt8((dominant >> 16) & 0xFF)
let bgG = UInt8((dominant >> 8) & 0xFF)
let bgB = UInt8(dominant & 0xFF)

// 2. Flood fill the white surround from every edge.
func isWhite(_ p: Int) -> Bool {
    let i = p * 4
    return px[i] > 210 && px[i + 1] > 210 && px[i + 2] > 210
}

var visited = [Bool](repeating: false, count: width * height)
var filled = [Bool](repeating: false, count: width * height)
var stack: [Int] = []
stack.reserveCapacity((width * height) / 4)
for x in 0..<width {
    stack.append(x)
    stack.append((height - 1) * width + x)
}
for y in 0..<height {
    stack.append(y * width)
    stack.append(y * width + width - 1)
}

while let p = stack.popLast() {
    if visited[p] { continue }
    visited[p] = true
    guard isWhite(p) else { continue }

    let i = p * 4
    px[i] = bgR
    px[i + 1] = bgG
    px[i + 2] = bgB
    px[i + 3] = 255
    filled[p] = true

    let x = p % width
    if x > 0 { stack.append(p - 1) }
    if x < width - 1 { stack.append(p + 1) }
    if p >= width { stack.append(p - width) }
    if p < width * (height - 1) { stack.append(p + width) }
}

// 2b. Despill. The flood fill stops at the anti-aliased edge of the rounded
//     square, leaving a faint light seam. Absorb anything that touches the
//     filled region until we reach the solid background colour again. It never
//     reaches the enclosed artwork: that is surrounded by solid background, and
//     is not adjacent to the filled region.
func distToBackground(_ r: Int, _ g: Int, _ b: Int) -> Int {
    abs(r - Int(bgR)) + abs(g - Int(bgG)) + abs(b - Int(bgB))
}

for _ in 0..<12 {
    var changed = false
    for p in 0..<(width * height) {
        if filled[p] { continue }
        let i = p * 4
        let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
        guard distToBackground(r, g, b) > 12 else { continue }

        let x = p % width
        let neighbours = [
            x > 0 ? p - 1 : -1,
            x < width - 1 ? p + 1 : -1,
            p >= width ? p - width : -1,
            p < width * (height - 1) ? p + width : -1
        ]
        guard neighbours.contains(where: { $0 >= 0 && filled[$0] }) else { continue }

        px[i] = bgR
        px[i + 1] = bgG
        px[i + 2] = bgB
        px[i + 3] = 255
        filled[p] = true
        changed = true
    }
    if !changed { break }
}

guard let filledImage = ctx.makeImage() else { exit(1) }

// 3. Scale to 1024x1024 with no alpha channel (app icons must be opaque).
let side = 1024
let outRowBytes = side * 4
let outBuf = UnsafeMutableRawPointer.allocate(byteCount: outRowBytes * side, alignment: 16)
defer { outBuf.deallocate() }

guard let outCtx = CGContext(data: outBuf,
                             width: side,
                             height: side,
                             bitsPerComponent: 8,
                             bytesPerRow: outRowBytes,
                             space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    exit(1)
}
outCtx.interpolationQuality = .high
outCtx.draw(filledImage, in: CGRect(x: 0, y: 0, width: side, height: side))

guard let outImage = outCtx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(dest, outImage, nil)

guard CGImageDestinationFinalize(dest) else { exit(1) }

print("wrote \(outURL.path) (\(side)x\(side), background #\(String(format: "%02X%02X%02X", bgR, bgG, bgB)))")
