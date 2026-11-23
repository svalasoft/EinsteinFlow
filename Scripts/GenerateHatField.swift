import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main struct GenerateHatField {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            print("Usage: generate-hat-field /absolute/HatField.imageset")
            exit(2)
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tiles = HatTiling.patch(substitutions: HatFieldLayout.substitutions)
        let coverage = HatCoverage(tiles).validateSquare(samples: 240)
        precondition(coverage.holes == 0 && coverage.overlaps == 0, "The field crop must be completely covered exactly once.")
        let pixels = HatFieldLayout.pixels, extent = HatFieldLayout.halfExtent
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: pixels * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let outline = CGColor(red: 0.025, green: 0.055, blue: 0.10, alpha: 1)
        context.setFillColor(outline)
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let palette: [HatKind: CGColor] = [
            .reflected: CGColor(red: 0.32, green: 0.67, blue: 0.88, alpha: 1),
            .h: CGColor(red: 0.63, green: 0.87, blue: 0.92, alpha: 1),
            .t: CGColor(red: 0.80, green: 0.76, blue: 0.94, alpha: 1),
            .p: CGColor(red: 0.94, green: 0.93, blue: 0.85, alpha: 1),
            .f: CGColor(red: 0.88, green: 0.75, blue: 0.52, alpha: 1)
        ]
        let scale = Double(pixels) / (extent * 2)
        context.setShouldAntialias(true)
        context.setLineJoin(.round)
        context.setLineWidth(2.5)
        context.setStrokeColor(outline)
        var rendered = 0
        for tile in tiles {
            let xs = tile.vertices.map(\.x), ys = tile.vertices.map(\.y)
            guard xs.max()! >= -extent, xs.min()! <= extent,
                  ys.max()! >= -extent, ys.min()! <= extent else { continue }
            context.beginPath()
            for (index, point) in tile.vertices.enumerated() {
                let p = CGPoint(x: (point.x + extent) * scale, y: (point.y + extent) * scale)
                if index == 0 { context.move(to: p) } else { context.addLine(to: p) }
            }
            context.closePath()
            context.setFillColor(palette[tile.kind]!)
            context.drawPath(using: .fillStroke)
            rendered += 1
        }
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent("HatField.png") as CFURL,
            UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        let contents: [String: Any] = ["images": [["filename": "HatField.png", "idiom": "universal", "scale": "1x"]],
                                     "info": ["author": "xcode", "version": 1]]
        try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("Contents.json"))
        print("Generated \(pixels)×\(pixels) opaque HatField; \(tiles.count) hierarchy tiles, \(rendered) intersecting crop.")
        print("Coverage: 57,600 interior samples; \(coverage.holes) holes, \(coverage.overlaps) overlaps.")
    }
}
