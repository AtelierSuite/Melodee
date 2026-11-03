// Cuts a window out of a capture of the whole screen, with its corners rounded off as
// macOS draws them, as the VM can't capture the window on its own (see capture-mac.sh).
//
//     crop <screen.png> <scale> <margin> <out.png> <x> <y> <width> <height> <radius> [<x> <y> <width> <height> <radius>]...
//
// The first frame is the window's, and any after it are popovers' bodies, which can
// reach past the window. Frames and radii are in points from the screen's top left, and
// scale is pixels per point. The window is set in a transparent margin of the same size
// on every side, so it sits at the same place in every capture, whatever reaches past it.
import AppKit
import ImageIO
import SwiftUI

let arguments = CommandLine.arguments
let numbers = arguments.dropFirst(5).compactMap { Double($0) }
guard arguments.count >= 10, (arguments.count - 5) % 5 == 0, numbers.count == arguments.count - 5,
      let scale = Double(arguments[2]), let margin = Double(arguments[3]),
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let screen = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("usage: crop <screen.png> <scale> <margin> <out.png> <x> <y> <width> <height> <radius>...")
    exit(2)
}

struct Shape {
    let frame: CGRect
    let radius: CGFloat
}
let shapes = stride(from: 0, to: numbers.count, by: 5).map { index in
    Shape(frame: CGRect(x: numbers[index], y: numbers[index + 1], width: numbers[index + 2], height: numbers[index + 3]),
          radius: numbers[index + 4])
}
let window = shapes[0].frame
// The window and its margin, in points on the screen.
let area = window.insetBy(dx: -margin, dy: -margin)
let width = Int(area.width * scale), height = Int(area.height * scale)
let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

/// A frame on the screen, in the output's pixels, which CoreGraphics counts from the bottom.
func pixels(_ frame: CGRect) -> CGRect {
    CGRect(x: (frame.minX - area.minX) * scale, y: (area.maxY - frame.maxY) * scale,
           width: frame.width * scale, height: frame.height * scale)
}

// Each mask is a pixel in from the edge, leaving out the edge's antialiasing, which is
// blended with the desktop behind it.
for shape in shapes {
    let mask = pixels(shape.frame).insetBy(dx: 1, dy: 1)
    context.addPath(RoundedRectangle(cornerRadius: shape.radius * scale - 1, style: .continuous).path(in: mask).cgPath)
}
context.clip()
// The part of the screen under the output, clamped to the screen.
let screenBounds = CGRect(x: 0, y: 0, width: screen.width, height: screen.height)
let sourceRect = CGRect(x: area.minX * scale, y: area.minY * scale, width: area.width * scale, height: area.height * scale)
    .intersection(screenBounds)
guard let visible = screen.cropping(to: sourceRect) else {
    print("the window isn't on the screen")
    exit(1)
}
context.draw(visible, in: pixels(CGRect(x: sourceRect.minX / scale, y: sourceRect.minY / scale,
                                        width: sourceRect.width / scale, height: sourceRect.height / scale)))

let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[4]))
