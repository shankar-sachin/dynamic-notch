import AppKit
import SwiftUI

/// Pulls a usable accent colour out of album art.
///
/// A plain average goes muddy brown on most covers, so pixels are weighted by
/// saturation — the vivid minority wins over the grey majority — and the result
/// is floored in saturation and brightness so it stays legible against black.
enum ArtworkAnalyzer {
    static func accent(for image: NSImage, fallback: Color = .white) -> Color {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fallback
        }

        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return fallback }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var totals = (r: 0.0, g: 0.0, b: 0.0, weight: 0.0)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255

            let high = max(r, g, b)
            let low = min(r, g, b)
            let saturation = high <= 0 ? 0 : (high - low) / high
            // Square the saturation so colourful pixels dominate, and drop
            // near-black pixels which carry no useful hue.
            let weight = saturation * saturation * high + 0.02
            totals.r += r * weight
            totals.g += g * weight
            totals.b += b * weight
            totals.weight += weight
        }

        guard totals.weight > 0 else { return fallback }
        let color = NSColor(
            red: totals.r / totals.weight,
            green: totals.g / totals.weight,
            blue: totals.b / totals.weight,
            alpha: 1
        )
        guard let hsb = color.usingColorSpace(.deviceRGB) else { return fallback }

        return Color(
            hue: Double(hsb.hueComponent),
            saturation: Double(max(0.42, min(0.95, hsb.saturationComponent))),
            brightness: Double(max(0.72, min(1.0, hsb.brightnessComponent + 0.12)))
        )
    }
}
