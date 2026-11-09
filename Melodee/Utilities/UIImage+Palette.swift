import UIKit

extension UIImage {

    /// Up to `count` vivid colors that stand out in the image, most prominent first.
    ///
    /// Grays and very dark pixels are ignored, so an image without any clear color returns an empty array.
    /// Colors are brightened enough to be seen against a dark background.
    func prominentColors(count: Int = 2) -> [UIColor] {
        guard let cgImage else { return [] }
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
            let color = UIColor(red: CGFloat(pixels[offset]) / 255 / alpha,
                                green: CGFloat(pixels[offset + 1]) / 255 / alpha,
                                blue: CGFloat(pixels[offset + 2]) / 255 / alpha,
                                alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
            guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil),
                  saturation > 0.2, brightness > 0.2 else { continue }
            let weight = saturation * brightness
            let bucket = min(Int(hue * CGFloat(bucketCount)), bucketCount - 1)
            weights[bucket] += weight
            sums[bucket].hue += hue * weight
            sums[bucket].saturation += saturation * weight
            sums[bucket].brightness += brightness * weight
        }

        // Ignore hues that only appear in a few pixels
        let minimumWeight = CGFloat(side * side) * 0.01
        var colors: [UIColor] = []
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
            colors.append(UIColor(hue: sums[bucket].hue / weight,
                                  saturation: min(max(sums[bucket].saturation / weight, 0.45), 0.9),
                                  brightness: max(sums[bucket].brightness / weight, 0.75),
                                  alpha: 1))
        }
        return colors
    }
}
