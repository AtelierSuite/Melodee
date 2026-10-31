import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Runs before any scene connects, so the phone UI and CarPlay both start from the same state
        AppServices.shared.start()
        return true
    }
}
