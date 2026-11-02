import SwiftUI

/// Asks whether to continue a file from where it was last played, for prompts started from `source`.
struct ResumePlaybackAlert: ViewModifier {

    @Environment(MediaPlayerManager.self) var mediaPlayer

    var source: ResumePlaybackPrompt.Source

    func body(content: Content) -> some View {
        let prompt = mediaPlayer.resumePrompt.flatMap { $0.source == source ? $0 : nil }
        content
            .alert(
                "Alert.ResumePlayback.Title",
                isPresented: Binding(
                    get: { prompt != nil },
                    set: { isPresented in
                        if !isPresented, mediaPlayer.resumePrompt?.id == prompt?.id {
                            mediaPlayer.resumePrompt = nil
                        }
                    }
                ),
                presenting: prompt
            ) { prompt in
                Button("Alert.ResumePlayback.Continue \(Self.timeString(prompt.playTime))") {
                    mediaPlayer.answerResumePrompt(continueFromLastPosition: true)
                }
                .keyboardShortcut(.defaultAction)
                Button("Alert.ResumePlayback.StartOver") {
                    mediaPlayer.answerResumePrompt(continueFromLastPosition: false)
                }
                Button("Shared.Cancel", role: .cancel) {
                    mediaPlayer.resumePrompt = nil
                }
            } message: { prompt in
                Text("Alert.ResumePlayback.Text \(prompt.file.name) \(Self.timeString(prompt.playTime))")
            }
    }

    static func timeString(_ time: TimeInterval) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = time >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(time.rounded(.down)).formatted(.time(pattern: pattern))
    }
}

extension View {
    func resumePlaybackAlert(for source: ResumePlaybackPrompt.Source) -> some View {
        self.modifier(ResumePlaybackAlert(source: source))
    }
}
