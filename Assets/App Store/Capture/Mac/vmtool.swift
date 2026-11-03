// What capture-mac.sh needs done inside the VM, built on the host and copied in,
// as the VM has no developer tools.
//
//     vmtool display          the main display's size in points
//     vmtool windows <pid>    the process's on-screen windows, front to back:
//                             id, then x y width height in points from the top left
//     vmtool covered <pid>    other apps' windows in front of the process's,
//                             which would show in its capture
//     vmtool park-pointer     moves the pointer to the middle of the screen's
//                             right edge, out of the window
import CoreGraphics
import Foundation

func onScreen() -> [[String: Any]] {
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
}

func frame(_ window: [String: Any]) -> CGRect {
    let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    return CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
}

func owner(_ window: [String: Any]) -> Int32 { window[kCGWindowOwnerPID as String] as? Int32 ?? 0 }
func layer(_ window: [String: Any]) -> Int { window[kCGWindowLayer as String] as? Int ?? 0 }

let arguments = CommandLine.arguments
let pid = arguments.count > 2 ? Int32(arguments[2]) ?? 0 : 0
let display = CGDisplayBounds(CGMainDisplayID())

switch arguments.count > 1 ? arguments[1] : "" {
case "display":
    print("\(Int(display.width)) \(Int(display.height))")
case "windows":
    for window in onScreen() where owner(window) == pid && layer(window) == 0 {
        let bounds = frame(window)
        print("\(window[kCGWindowNumber as String] ?? 0)\t\(Int(bounds.minX))\t\(Int(bounds.minY))\t\(Int(bounds.width))\t\(Int(bounds.height))")
    }
case "covered":
    // Front to back, so whatever comes before the process's first window and overlaps
    // one of them is over it, up to the Dock's level. The menu bar's is left out, as the
    // window sits below it, and so are the process's own popovers.
    let windows = onScreen()
    let ours = windows.filter { owner($0) == pid && layer($0) == 0 }.map(frame)
    for window in windows {
        if owner(window) == pid { break }
        guard (0...Int(CGWindowLevelForKey(.dockWindow))).contains(layer(window)),
              ours.contains(where: { $0.intersects(frame(window)) }) else { continue }
        print("\(window[kCGWindowOwnerName as String] ?? "?")\t\(frame(window))")
    }
case "park-pointer":
    CGWarpMouseCursorPosition(CGPoint(x: display.maxX - 1, y: display.midY))
default:
    print("usage: vmtool display | windows <pid> | covered <pid> | park-pointer")
    exit(2)
}
