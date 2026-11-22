// Renders the spec's app icon (spec/brand/icon.svg) into the asset catalog at build time;
// the spec forbids committing renders (spec/brand/README.md).
// iOS masks the corners itself and rejects icons with alpha, so the SVG is drawn over an opaque
// square of its tile color, the tokens' color.surface.background.
// Usage: swift scripts/render-icon.swift <icon.svg> <tokens.json> <out.png>
import AppKit
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("render-icon: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 4 else { fail("usage: render-icon <icon.svg> <tokens.json> <out.png>") }
let size = 1024
var rect = NSRect(x: 0, y: 0, width: size, height: size)
guard let svg = NSImage(contentsOfFile: args[1]), svg.isValid,
      let art = svg.cgImage(forProposedRect: &rect, context: nil, hints: nil)
else { fail("can't load \(args[1]) as an image") }

let tokens = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2])))) as? [String: Any]
let background = ((tokens?["color"] as? [String: Any])?["surface"] as? [String: Any])?["background"] as? [String: Any]
guard let hexString = background?["$value"] as? String, let hex = Int(hexString.dropFirst(), radix: 16)
else { fail("no color.surface.background in \(args[2])") }

// noneSkipLast: an opaque RGB context, so the PNG carries no alpha channel.
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fail("can't create a bitmap context") }
ctx.setFillColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                 blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
ctx.fill(rect)
ctx.draw(art, in: rect)

let out = URL(fileURLWithPath: args[3])
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fail("can't write \(args[3])") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fail("can't write \(args[3])") }
