import CoreGraphics
import SwiftUI

/// Picks out the colors that stand out in album art, for coloring the visualizer.
enum ImagePalette {

    /// Up to `count` vivid colors that stand out in the image, most prominent first.
    ///
    /// Grays and very dark pixels are ignored, so an image without any clear color returns an empty array.
    /// Colors are brightened enough to be seen against a dark background.
    static func prominentColors(in cgImage: CGImage, count: Int = 2) -> [Color] {
        let side = 32
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * bytesPerRow)
        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress,
                                          width: side,
                                          height: side,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard didDraw else { return [] }

        // Group pixels by hue, weighting each by how vivid it is
        let bucketCount = 18
        var weights = [CGFloat](repeating: 0, count: bucketCount)
        var sums = [(hue: CGFloat, saturation: CGFloat, brightness: CGFloat)](
            repeating: (0, 0, 0), count: bucketCount
        )
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = CGFloat(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            let (hue, saturation, brightness) = hsb(red: CGFloat(pixels[offset]) / 255 / alpha,
                                                    green: CGFloat(pixels[offset + 1]) / 255 / alpha,
                                                    blue: CGFloat(pixels[offset + 2]) / 255 / alpha)
            guard saturation > 0.2, brightness > 0.2 else { continue }
            let weight = saturation * brightness
            let bucket = min(Int(hue * CGFloat(bucketCount)), bucketCount - 1)
            weights[bucket] += weight
            sums[bucket].hue += hue * weight
            sums[bucket].saturation += saturation * weight
            sums[bucket].brightness += brightness * weight
        }

        // Ignore hues that only appear in a few pixels
        let minimumWeight = CGFloat(side * side) * 0.01
        var colors: [Color] = []
        var usedBuckets: [Int] = []
        for bucket in weights.indices.sorted(by: { weights[$0] > weights[$1] }) {
            guard colors.count < count, weights[bucket] >= minimumWeight else { break }
            // Skip hues next to one already picked, so the colors differ visibly
            let isNearUsedBucket = usedBuckets.contains { used in
                let distance = abs(used - bucket)
                return min(distance, bucketCount - distance) <= 1
            }
            guard !isNearUsedBucket else { continue }
            usedBuckets.append(bucket)
            let weight = weights[bucket]
            colors.append(Color(hue: sums[bucket].hue / weight,
                                saturation: min(max(sums[bucket].saturation / weight, 0.45), 0.9),
                                brightness: max(sums[bucket].brightness / weight, 0.75)))
        }
        return colors
    }

    /// Converts a color's red, green and blue, each from 0 to 1, to hue, saturation and brightness, each from 0 to 1.
    private static func hsb(red: CGFloat, green: CGFloat, blue: CGFloat)
        -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        let red = min(max(red, 0), 1), green = min(max(green, 0), 1), blue = min(max(blue, 0), 1)
        let maximum = max(red, green, blue)
        let delta = maximum - min(red, green, blue)
        let saturation = maximum > 0 ? delta / maximum : 0
        guard delta > 0 else { return (0, saturation, maximum) }
        var hue: CGFloat
        if maximum == red {
            hue = (green - blue) / delta
        } else if maximum == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, saturation, maximum)
    }
}
