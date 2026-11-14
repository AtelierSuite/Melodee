import SwiftUI

/// Trims one audio or video file: a waveform with start and end handles, and their times above it.
struct TrimmerView: View {

    @Environment(\.dismiss) var dismiss
    @Environment(MediaPlayerManager.self) var mediaPlayer

    var file: FSFile
    /// Called after the file was trimmed or restored, so the file list can refresh.
    var onChange: () -> Void

    @State var source: TrimSource?
    @State var waveform: Waveform?
    @State var player: TrimPreviewPlayer?
    @State var range: ClosedRange<TimeInterval> = 0...0
    @State var initialRange: ClosedRange<TimeInterval> = 0...0
    @State var mode: TrimMode = .trim
    @State var hasOriginal: Bool = false
    @State var isSaving: Bool = false
    @State var progress: Double = 0
    @State var errorText: String?
    @State var isRestoreConfirmationPresented: Bool = false

    var hasChanges: Bool {
        abs(range.lowerBound - initialRange.lowerBound) > 0.005 ||
            abs(range.upperBound - initialRange.upperBound) > 0.005
    }

    /// Whether the selection covers the whole original, which undoes any trim.
    var isFullLength: Bool {
        guard let waveform else { return false }
        return range.lowerBound < 0.005 && waveform.duration - range.upperBound < 0.005
    }

    var body: some View {
        NavigationStack {
            content
                .padding(.horizontal, 20.0)
                .padding(.vertical, 12.0)
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle(Text(verbatim: file.name))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .disabled(isSaving)
                .overlay {
                    if isSaving {
                        ProgressView(value: progress)
                            .progressViewStyle(.circular)
                            .controlSize(.large)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isSaving)
        .task {
            await load()
        }
        .onDisappear {
            player?.stop()
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .trim {
                player?.pause()
            }
        }
        .onChange(of: range) { _, newRange in
            // Keep the playhead inside the selection
            if let player, !newRange.contains(player.currentTime) {
                player.seek(to: min(max(player.currentTime, newRange.lowerBound), newRange.upperBound))
            }
        }
        .alert("Trim.Error.Title", isPresented: Binding(get: { errorText != nil },
                                                         set: { if !$0 { errorText = nil } })) {
            Button("Shared.OK", role: .cancel) { }
        } message: {
            Text(verbatim: errorText ?? "")
        }
        .confirmationDialog("Trim.Restore", isPresented: $isRestoreConfirmationPresented,
                            titleVisibility: .visible) {
            Button("Trim.Restore", role: .destructive) {
                restoreOriginal()
            }
        } message: {
            Text("Trim.Restore.Message.\(file.name)")
        }
    }

    @ViewBuilder
    var content: some View {
        if let waveform {
            VStack(alignment: .center, spacing: 20.0) {
                HStack(alignment: .top) {
                    timeLabel("Trim.Start", range.lowerBound, alignment: .leading)
                    Spacer()
                    timeLabel("Trim.Length", range.upperBound - range.lowerBound, alignment: .center)
                    Spacer()
                    timeLabel("Trim.End", range.upperBound, alignment: .trailing)
                }
                WaveformTrimmer(
                    waveform: waveform,
                    range: $range,
                    playhead: player?.currentTime ?? range.lowerBound,
                    mode: mode
                ) { time, _ in
                    player?.seek(to: time)
                }
                .frame(height: 120.0)
                Picker("Trim.Mode", selection: $mode) {
                    Text("Trim.Mode.Preview").tag(TrimMode.preview)
                    Text("Trim.Action").tag(TrimMode.trim)
                }
                .pickerStyle(.segmented)
                if mode == .preview {
                    playButton
                }
                Text(originalFootnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else if errorText == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: 200.0)
        }
    }

    func timeLabel(_ title: LocalizedStringKey, _ time: TimeInterval, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2.0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: TrimTime.string(time))
                .font(.title3.monospacedDigit())
                .fontWeight(.semibold)
                .contentTransition(.numericText())
        }
    }

    var playButton: some View {
        Button {
            guard let player else { return }
            if player.isPlaying {
                player.pause()
            } else {
                // Start over when the playhead is at the end of the selection
                if player.currentTime >= range.upperBound - 0.05 || player.currentTime < range.lowerBound {
                    player.seek(to: range.lowerBound)
                }
                player.play(until: range.upperBound)
            }
        } label: {
            Image(systemName: player?.isPlaying == true ? "pause.fill" : "play.fill")
                .font(.title2)
                .frame(width: 56.0, height: 56.0)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(player?.isPlaying == true ? "Trim.Pause" : "Shared.Play"))
    }

    var originalFootnote: String {
        if hasOriginal, let expiry = TrimBackups.expiryDate(for: URL(filePath: file.path)) {
            return String(localized: "Trim.OriginalKeptUntil.\(expiry.formatted(date: .abbreviated, time: .omitted))")
        }
        return String(localized: "Trim.OriginalWillBeKept")
    }

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(role: .close) {
                dismiss()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    if let waveform {
                        CopiedTrim.clipboard = CopiedTrim(range: range, duration: waveform.duration,
                                                          sourceName: file.name)
                    }
                } label: {
                    Label("Trim.Copy", systemImage: "doc.on.doc")
                }
                .disabled(waveform == nil)
                if let copiedTrim = CopiedTrim.clipboard, let waveform {
                    Button {
                        if let pasted = copiedTrim.range(forDuration: waveform.duration, anchor: .endOfFile) {
                            withAnimation(.snappy) {
                                range = pasted
                            }
                        }
                    } label: {
                        Label("Trim.Paste", systemImage: "doc.on.clipboard")
                    }
                    .disabled(copiedTrim.range(forDuration: waveform.duration, anchor: .endOfFile) == nil)
                }
                if hasOriginal {
                    Divider()
                    Button(role: .destructive) {
                        isRestoreConfirmationPresented = true
                    } label: {
                        Label("Trim.Restore", systemImage: "arrow.uturn.backward")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .confirm) {
                save()
            }
            .disabled(!hasChanges || waveform == nil || isSaving)
        }
    }

    // MARK: Actions

    func load() async {
        if mediaPlayer.isEnginePlaying() {
            mediaPlayer.pause()
        }
        let fileURL = URL(filePath: file.path)
        hasOriginal = TrimBackups.hasBackup(for: fileURL)
        do {
            let source = try MediaTrimmer.openSource(for: file)
            let waveform = try await WaveformLoader.load(url: source.url, isVideo: file.type == .video)
            self.source = source
            player = TrimPreviewPlayer(url: source.url, isVideo: file.type == .video)
            var initial = 0...waveform.duration
            if hasOriginal, let stored = TrimBackups.storedRange(for: fileURL),
               stored.upperBound <= waveform.duration + 0.01 {
                initial = stored.lowerBound...min(stored.upperBound, waveform.duration)
            }
            range = initial
            initialRange = initial
            player?.currentTime = initial.lowerBound
            self.waveform = waveform
        } catch {
            errorText = error.localizedDescription
        }
    }

    func save() {
        player?.stop()
        isSaving = true
        progress = 0
        let range = range
        let restoresOriginal = isFullLength && hasOriginal
        // Locking the screen would suspend the app partway through the trim
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            do {
                if restoresOriginal {
                    try MediaTrimmer.restoreOriginal(of: file)
                } else {
                    try await MediaTrimmer.trim(file, to: range) { value in
                        Task { @MainActor in
                            progress = value
                        }
                    }
                }
                isSaving = false
                mediaPlayer.fileDidChangeOnDisk(atPath: file.path)
                onChange()
                dismiss()
            } catch {
                isSaving = false
                errorText = error.localizedDescription
            }
        }
    }

    func restoreOriginal() {
        player?.stop()
        do {
            try MediaTrimmer.restoreOriginal(of: file)
            mediaPlayer.fileDidChangeOnDisk(atPath: file.path)
            onChange()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
