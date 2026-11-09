import SwiftUI
import TipKit

struct MainView: View {

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(ExternalFoldersManager.self) var externalFolders: ExternalFoldersManager

    @AppStorage("SelectedLibrarySource") var selectedSource: LibrarySource = .local
    @AppStorage("LastOnboardedVersion") var lastOnboardedVersion: String = ""
    @State var path: [ViewPath] = []
    @State var isOnboardingPresented: Bool = false
    @State var containerSize: CGSize = .zero
    @State var isNowPlayingFullScreen: Bool = false

    // Show Now Playing in its own column when iOS reports enough horizontal room and the
    // window is landscape; otherwise fall back to the floating Now Playing bar.
    var isTwoColumnLayout: Bool {
        horizontalSizeClass == .regular && containerSize.width > containerSize.height
    }

    var nowPlayingColumnWidth: CGFloat {
        min(max(containerSize.width * 0.4, 360.0), 480.0)
    }

    var body: some View {
        let configuration = rootConfiguration()
        HStack(spacing: 0.0) {
            NavigationStack(path: $path) {
                FolderView(
                    currentDirectory: configuration.directory,
                    overrideStorageLocation: configuration.storageLocation,
                    isLibraryRoot: true
                )
                .id(configuration.source)
                .hasFileBrowserNavigationDestinations()
            }
            .resumePlaybackAlert(for: .fileBrowser)
            .playbackBarAccessory(isEnabled: !isTwoColumnLayout)
            .accessibilityHidden(isTwoColumnLayout && isNowPlayingFullScreen)
            if isTwoColumnLayout {
                Divider()
                    .ignoresSafeArea()
                // Holds the column's place; Now Playing is laid over it so it can grow to fill
                // the window without the file browser being squeezed underneath it.
                Color.clear
                    .frame(width: nowPlayingColumnWidth)
            }
        }
        .overlay(alignment: .trailing) {
            if isTwoColumnLayout {
                // Hosted in its own navigation stack so the full screen toggle sits in a real
                // toolbar, lined up with and sized like the file browser's toolbar buttons.
                NavigationStack {
                    NowPlayingView(presentation: isNowPlayingFullScreen ? .fullScreen : .column)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                fullScreenButton
                            }
                        }
                }
                .frame(width: isNowPlayingFullScreen ? containerSize.width : nowPlayingColumnWidth)
            }
        }
        // The column is not animated in: UIKit-backed viewers (text, PDF) keep their text laid out
        // for the old, wider frame when it shrinks inside an animation, leaving it cut off by the column.
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            containerSize = size
        }
        .onChange(of: isTwoColumnLayout) { _, isTwoColumnLayout in
            // Full screen only applies to the column, so start from the column next time.
            if !isTwoColumnLayout {
                isNowPlayingFullScreen = false
            }
        }
        .onChange(of: selectedSource) {
            path.removeAll()
        }
        .onAppear {
            normalizeSelectedSource()
            presentOnboardingIfNeeded()
        }
        .onOpenURL { url in
            // melodee://reonboard re-opens the onboarding sheet on demand.
            if url.scheme == "melodee", url.host == "reonboard" {
                presentOnboarding()
            }
        }
        .sheet(isPresented: $isOnboardingPresented, onDismiss: {
            NPQueueTip.isOnboardingActive = false
        }) {
            OnboardingView {
                lastOnboardedVersion = OnboardingView.appVersion
                isOnboardingPresented = false
            }
        }
        .task {
            try? Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
        }
    }

    var fullScreenButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.4)) {
                isNowPlayingFullScreen.toggle()
            }
        } label: {
            // Horizontal arrows, as the column only grows and shrinks sideways
            Image(systemName: isNowPlayingFullScreen ?
                  "arrow.right.and.line.vertical.and.arrow.left" :
                  "arrow.left.and.line.vertical.and.arrow.right")
        }
        .accessibilityLabel(
            isNowPlayingFullScreen ?
            String(localized: "NowPlaying.ExitFullScreen") :
            String(localized: "NowPlaying.EnterFullScreen")
        )
    }

    // Show onboarding on first launch and whenever the major/minor version is bumped.
    func presentOnboardingIfNeeded() {
        if OnboardingView.shouldShow(
            currentVersion: OnboardingView.appVersion,
            lastSeenVersion: lastOnboardedVersion
        ) {
            presentOnboarding()
        }
    }

    func presentOnboarding() {
        // Mark onboarding active before presenting so popover tips stay hidden.
        NPQueueTip.isOnboardingActive = true
        isOnboardingPresented = true
    }

    // MARK: - Source resolution

    struct RootConfiguration {
        var source: LibrarySource
        var directory: FSDirectory?
        var storageLocation: StorageLocation
    }

    func rootConfiguration() -> RootConfiguration {
        switch selectedSource {
        case .cloud where FileManager.default.ubiquityIdentityToken != nil:
            return RootConfiguration(source: .cloud, directory: nil, storageLocation: .cloud)
        case .external(let id):
            if let bookmark = externalFolders.bookmark(with: id),
               let url = externalFolders.resolveBookmark(bookmark) {
                let directory = FSDirectory(
                    name: bookmark.name,
                    path: url.path(percentEncoded: false),
                    files: []
                )
                return RootConfiguration(source: .external(id), directory: directory, storageLocation: .external)
            }
            return RootConfiguration(source: .local, directory: nil, storageLocation: .local)
        default:
            return RootConfiguration(source: .local, directory: nil, storageLocation: .local)
        }
    }

    func normalizeSelectedSource() {
        let resolved = rootConfiguration().source
        if resolved != selectedSource {
            selectedSource = resolved
        }
    }
}
