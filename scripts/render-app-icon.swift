// Renders the macOS app icon from the flat artwork in Resources/AppIconArtwork.png.
//
// macOS does not mask app icons, so the artwork is placed on the standard
// rounded-square tile (824 pt on a 1024 pt canvas, transparent margins, soft
// drop shadow) and the subject is scaled to fill most of the tile so it stays
// readable at Finder and menu sizes.
//
// Usage: swift scripts/render-app-icon.swift <artwork.png> <output directory>
// Writes AppIcon.png (1024 px) and AppIcon.iconset/ into the output directory.

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: render-app-icon.swift <artwork.png> <output directory>\n".utf8))
    exit(64)
}
let artworkURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let artwork = NSImage(contentsOf: artworkURL),
      let source = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("Cannot read artwork at \(artworkURL.path)\n".utf8))
    exit(66)
}

let canvas = 1024
let tileSize = 824.0
let tileOrigin = (Double(canvas) - tileSize) / 2
let cornerRadius = tileSize * 0.2237
/// Fraction of the tile the subject's longer side should span.
let subjectFill = 0.74

/// Finds the subject by comparing every pixel with the flat background colour
/// sampled at the top-left corner.
func subjectBounds(of image: CGImage) -> CGRect {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let background = (Int(pixels[0]), Int(pixels[1]), Int(pixels[2]))
    var minX = width, minY = height, maxX = 0, maxY = 0
    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            let distance = abs(Int(pixels[index]) - background.0)
                + abs(Int(pixels[index + 1]) - background.1)
                + abs(Int(pixels[index + 2]) - background.2)
            guard distance > 60 else { continue }
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func backgroundColor(of image: CGImage) -> CGColor {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return CGColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
}

func renderIcon(size: Int) -> CGImage {
    let scale = Double(size) / Double(canvas)
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.scaleBy(x: scale, y: scale)

    let tile = CGRect(x: tileOrigin, y: tileOrigin, width: tileSize, height: tileSize)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Shadow sits under the tile only; the artwork is clipped to the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.22))
    context.addPath(tilePath)
    context.setFillColor(backgroundColor(of: source))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    let bounds = subjectBounds(of: source)
    let subjectScale = tileSize * subjectFill / max(bounds.width, bounds.height)
    let drawWidth = Double(source.width) * subjectScale
    let drawHeight = Double(source.height) * subjectScale
    // Centre the subject on the tile. CGImage pixel rows count from the top,
    // while the context's y axis points up.
    let subjectCenterX = bounds.midX * subjectScale
    let subjectCenterY = (Double(source.height) - bounds.midY) * subjectScale
    let origin = CGPoint(
        x: tile.midX - subjectCenterX,
        y: tile.midY - subjectCenterY
    )
    context.draw(source, in: CGRect(origin: origin, size: CGSize(width: drawWidth, height: drawHeight)))
    context.restoreGState()

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

let iconsetURL = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

try writePNG(renderIcon(size: canvas), to: outputDirectory.appendingPathComponent("AppIcon.png"))
for base in [16, 32, 128, 256, 512] {
    try writePNG(renderIcon(size: base), to: iconsetURL.appendingPathComponent("icon_\(base)x\(base).png"))
    try writePNG(renderIcon(size: base * 2), to: iconsetURL.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Rendered AppIcon.png and AppIcon.iconset in \(outputDirectory.path)")
