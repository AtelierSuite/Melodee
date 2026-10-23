import AppKit

struct MissingCapture: Error {
    let url: URL
}

/// Draws the gradient and copy, and returns how far down from the top the copy ends.
@MainActor
func drawBackground(_ screenshot: Screenshot, copy: Copy, in canvas: NSRect, device: Device) -> CGFloat {
    NSGradient(
        colors: screenshot.theme.stops.map(\.0),
        atLocations: screenshot.theme.stops.map(\.1),
        colorSpace: .sRGB
    )?.draw(in: canvas, angle: 90)

    let header = Line(copy.header, size: device.headerSize, weight: .bold,
                      color: screenshot.theme.text, maxWidth: device.textWidth)
    let headerTop = canvas.maxY - device.textTop
    header.draw(top: headerTop, centerX: canvas.midX)
    let caption = Line(copy.caption, size: device.captionSize, weight: .medium,
                       color: screenshot.theme.text.withAlphaComponent(0.75), maxWidth: device.textWidth)
    let captionTop = headerTop - header.size.height - 12
    caption.draw(top: captionTop, centerX: canvas.midX)
    return canvas.maxY - (captionTop - caption.size.height)
}

/// Draws the hardware with the capture clipped to its display.
@MainActor
func drawDevice(_ capture: CGImage, device: Device, canvasHeight: CGFloat, copyBottom: CGFloat, context: CGContext) {
    let frame = DeviceFrames.frame(for: device)
    let scale = device.placementWidth / frame.hardwareSize.width
    let size = NSSize(width: frame.hardwareSize.width * scale, height: frame.hardwareSize.height * scale)
    let center = NSPoint(x: device.canvasSize.width / 2, y: (copyBottom + canvasHeight) / 2)
    let hardwareRect = CGRect(
        x: center.x - size.width / 2, y: canvasHeight - center.y - size.height / 2,
        width: size.width, height: size.height
    )

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 60,
                      color: NSColor.black.withAlphaComponent(0.25).cgColor)
    context.draw(frame.hardware, in: hardwareRect)
    context.restoreGState()

    // The display origin is measured from the hardware's top left, and CoreGraphics counts up.
    let displayRect = CGRect(
        x: hardwareRect.minX + frame.displayOrigin.x * scale,
        y: hardwareRect.maxY - (frame.displayOrigin.y + frame.displaySize.height) * scale,
        width: frame.displaySize.width * scale,
        height: frame.displaySize.height * scale
    )
    context.saveGState()
    context.clip(to: displayRect, mask: frame.display)
    context.interpolationQuality = .high
    context.draw(capture, in: displayRect)
    context.restoreGState()
}

@MainActor
func render(_ screenshot: Screenshot, copy: Copy, device: Device, language: String) throws -> NSBitmapImageRep? {
    let captureURL = device.rawURL("\(screenshot.name).png", language: language)
    guard let capture = loadImage(captureURL) else { throw MissingCapture(url: captureURL) }
    let canvasSize = device.canvasSize
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width), pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )?.retagging(with: .sRGB), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = graphics
    let canvas = NSRect(origin: .zero, size: canvasSize)
    let copyBottom = drawBackground(screenshot, copy: copy, in: canvas, device: device)
    drawDevice(capture, device: device, canvasHeight: canvasSize.height, copyBottom: copyBottom,
               context: graphics.cgContext)
    graphics.flushGraphics()
    return bitmap
}

@MainActor
func compose(_ screenshot: Screenshot, device: Device, language: String) -> Bool {
    guard let copy = screenshot.copy[language] else { return true }
    let outDir = device.outDir(language)
    let outURL = outDir.appendingPathComponent("\(screenshot.name).png")
    do {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        guard let bitmap = try render(screenshot, copy: copy, device: device, language: language),
              let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        try png.write(to: outURL)
        print("wrote \(outURL.path.replacingOccurrences(of: assetsDir.path + "/", with: ""))")
        return true
    } catch let error as MissingCapture {
        print("missing raw capture: \(error.url.path)")
        return false
    } catch {
        print("failed to write \(outURL.path): \(error)")
        return false
    }
}
