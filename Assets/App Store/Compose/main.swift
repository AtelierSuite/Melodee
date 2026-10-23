import Foundation

let languages = ["en", "ja"]
/// The devices named on the command line (`./compose.sh iPad`), or all of them.
let requestedDevices = CommandLine.arguments.dropFirst().compactMap(Device.init(rawValue:))
let devices = requestedDevices.isEmpty ? [Device.iPhone, .iPad] : requestedDevices

var allComposed = true
for device in devices {
    for language in languages {
        for screenshot in Screenshots.all {
            allComposed = compose(screenshot, device: device, language: language) && allComposed
        }
    }
}
exit(allComposed ? 0 : 1)
