// Renders the spec's app icon (spec/brand/icon.svg) into the asset catalog at build time;
// the spec forbids committing renders (spec/brand/README.md).
// iOS masks the corners itself and rejects icons with alpha, so the SVG is drawn over an opaque
// square of its tile color, the tokens' color.surface.background.
// Usage: swift scripts/render-icon.swift <icon.svg> <tokens.json> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let svg = NSImage(contentsOfFile: args[1]), svg.isValid else {
    FileHandle.standardError.write(Data("render-icon: can't load \(args.dropFirst().first ?? "?") as an image\n".utf8))
    exit(1)
}
let tokens = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as? [String: Any]
let background = ((tokens?["color"] as? [String: Any])?["surface"] as? [String: Any])?["background"] as? [String: Any]
let hex = Int((background?["$value"] as? String ?? "#000000").dropFirst(), radix: 16) ?? 0
let tile = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                   blue: CGFloat(hex & 0xFF) / 255, alpha: 1)

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
tile.setFill()
rect.fill()
svg.draw(in: rect)
NSGraphicsContext.restoreGraphicsState()

let out = URL(fileURLWithPath: args[3])
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
try rep.representation(using: .png, properties: [:])!.write(to: out)
