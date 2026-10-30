import SwiftUI

@main
struct MelodeeApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let services = AppServices.shared
    @State var nowPlayingBarManager: NowPlayingBarManager = NowPlayingBarManager()

    var body: some Scene {
        WindowGroup {
            MainView()
                .onAppear {
                    // NSAccentColorName isn't applied to SwiftUI's window, so tint the window directly
                    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                        scene.windows.forEach { $0.tintColor = .accent }
                    }
                }
                .environment(services.fileManager)
                .environment(services.mediaPlayerManager)
                .environment(nowPlayingBarManager)
                .environment(services.fileDownloadManager)
                .environment(services.externalFoldersManager)
        }
    }
}
