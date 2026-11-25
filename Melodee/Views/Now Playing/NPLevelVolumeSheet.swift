import SwiftUI

/// Turns Level Volume on or off, and shows how much the playing track is being raised or lowered.
struct NPLevelVolumeSheet: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer
    @Environment(\.dismiss) var dismiss

    @State private var contentHeight: CGFloat = 320.0
    @State private var bottomInset: CGFloat = 0.0

    var body: some View {
        @Bindable var levelVolume = mediaPlayer.levelVolume
        NavigationStack {
            LevelVolumeMeter(levelVolume: levelVolume)
            .opacity(levelVolume.isOn ? 1.0 : 0.6)
            .padding(.horizontal, 16.0)
            .padding(.top, 8.0)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height + proxy.safeAreaInsets.top
            } action: { newValue in
                contentHeight = newValue
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.bottom
            } action: { newValue in
                bottomInset = newValue
            }
            .navigationTitle("LevelVolume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $levelVolume.isOn.animation()) {
                        Label("LevelVolume.On", systemImage: "power")
                    }
                    .tint(.green)
                }
            }
        }
        .presentationDetents([.height(contentHeight + 16.0 - bottomInset)])
    }
}
