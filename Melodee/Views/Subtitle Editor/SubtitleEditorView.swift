import SwiftUI
import UIKit
import Videoglot

/// Full-featured lyrics and subtitle editor for videos on iOS and iPadOS.
/// Supports opening existing embedded/sidecar tracks or creating new ones, live video preview,
/// tap-to-time controls, cue splitting/merging/nudging, shifting all timings, and saving as sidecar or embedded track.
struct SubtitleEditorView: View {

    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(MediaPlayerManager.self) var mediaPlayer

    let file: FSFile
    var onChange: (() -> Void)? = nil

    @State private var model: SubtitleEditorModel
    @State private var isShiftSheetPresented = false
    @State private var isTrackInfoPresented = false
    @State private var isImportLyricsPresented = false
    @State private var isSaveSheetPresented = false
    @State private var shiftOffsetSeconds: Double = 0
    @State private var importLyricsText: String = ""
    @State private var isScrubbingTimeline = false
    @State private var scrubTime: TimeInterval = 0
    @FocusState private var isCueTextFocused: Bool

    init(file: FSFile, onChange: (() -> Void)? = nil) {
        self.file = file
        self.onChange = onChange
        _model = State(initialValue: SubtitleEditorModel(videoURL: URL(filePath: file.path)))
    }

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isWideLayout {
                    wideLayout
                } else {
                    compactLayout
                }
            }
            .navigationTitle(Text(verbatim: file.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .disabled(model.isSaving)
            .overlay {
                if model.isSaving {
                    savingOverlay
                }
            }
        }
        .interactiveDismissDisabled(model.isSaving)
        .task {
            if mediaPlayer.isEnginePlaying() {
                mediaPlayer.pause()
            }
            let subtitles = mediaPlayer.subtitleController
            let isPlayingThisFile = subtitles.videoURL?.standardizedFileURL == URL(filePath: file.path).standardizedFileURL
            await model.load(preferring: isPlayingThisFile ? subtitles.selectedTrack?.source : nil)
        }
        .onDisappear {
            model.tearDown()
        }
        .sheet(isPresented: $isShiftSheetPresented) {
            shiftTimingsSheet
        }
        .sheet(isPresented: $isTrackInfoPresented) {
            trackMetadataSheet
        }
        .sheet(isPresented: $isImportLyricsPresented) {
            importPlainLyricsSheet
        }
        .sheet(isPresented: $isSaveSheetPresented) {
            saveSheet
        }
        .alert(
            "SubtitleEditor.Error.Title",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("Shared.OK", role: .cancel) { }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                SubtitleEditorVideoPreview(model: model, isCompact: true)
                    .frame(maxHeight: 200)
                transportControls
                liveTimingBar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            cueListSection
        }
    }

    private var wideLayout: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SubtitleEditorVideoPreview(model: model, isCompact: false)
                    transportControls
                    liveTimingBar
                    selectedCueEditorCard
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity)

            Divider()

            cueListSection
                .frame(width: 380)
        }
    }

    // MARK: - Transport & Live Timing

    private var transportControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(verbatim: SubtitleEditorModel.formatCueTime(isScrubbingTimeline ? scrubTime : model.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 56, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { isScrubbingTimeline ? scrubTime : model.currentTime },
                        set: { newValue in
                            scrubTime = newValue
                            model.seek(to: newValue)
                        }
                    ),
                    in: 0...max(model.totalDuration, 1.0),
                    onEditingChanged: { editing in
                        isScrubbingTimeline = editing
                    }
                )

                Text(verbatim: SubtitleEditorModel.formatCueTime(model.totalDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 56, alignment: .trailing)
            }

            HStack(spacing: 16) {
                Menu {
                    ForEach([Float(0.5), 0.75, 1.0, 1.25], id: \.self) { rate in
                        Button {
                            model.previewRate = rate
                        } label: {
                            let label = PlaybackSpeed.label(for: Double(rate))
                            if model.previewRate == rate {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(verbatim: label)
                            }
                        }
                    }
                } label: {
                    Text(verbatim: PlaybackSpeed.label(for: Double(model.previewRate)))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }

                Spacer()

                Button { model.step(by: -5) } label: { Image(systemName: "gobackward.5") }
                Button { model.step(by: -1) } label: { Image(systemName: "backward.frame") }
                Button {
                    model.togglePlayPause()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
                Button { model.step(by: 1) } label: { Image(systemName: "forward.frame") }
                Button { model.step(by: 5) } label: { Image(systemName: "goforward.5") }

                Spacer()

                Button {
                    model.addCueAtPlayhead()
                } label: {
                    Label("SubtitleEditor.AddCue", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
            }
            .buttonStyle(.borderless)
        }
    }

    private var liveTimingBar: some View {
        HStack(spacing: 8) {
            Button {
                model.markStartAtPlayhead()
            } label: {
                Label("SubtitleEditor.MarkStart", systemImage: "arrow.right.to.line")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("[", modifiers: .command)

            Button {
                model.markEndAtPlayhead(advanceToNext: false)
            } label: {
                Label("SubtitleEditor.MarkEnd", systemImage: "arrow.left.to.line")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedCueID == nil)
            .keyboardShortcut("]", modifiers: .command)

            Button {
                model.markAndAdvanceToNextCue()
            } label: {
                Label("SubtitleEditor.NextCue", systemImage: "forward.end")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.document.cues.isEmpty)
        }
    }

    // MARK: - Cue List & Selected Cue Editor

    private var cueListSection: some View {
        List {
            if !isWideLayout, model.selectedCueIndex != nil {
                Section("SubtitleEditor.SelectedCue") {
                    selectedCueControls
                }
            }

            Section {
                if model.document.cues.isEmpty {
                    ContentUnavailableView {
                        Label("SubtitleEditor.NoCues.Title", systemImage: "captions.bubble")
                    } description: {
                        Text("SubtitleEditor.NoCues.Description")
                    } actions: {
                        Button("SubtitleEditor.AddCue") {
                            model.addCueAtPlayhead()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(model.document.cues.enumerated()), id: \.element.id) { index, cue in
                        cueRow(index: index, cue: cue)
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { model.document.cues[$0].id })
                        model.document.deleteCues(ids: ids)
                        if let selected = model.selectedCueID, ids.contains(selected) {
                            model.selectedCueID = model.document.cues.first?.id
                        }
                    }
                }
            } header: {
                HStack {
                    Text(verbatim: model.activeSource.displayName)
                    Spacer()
                    Text("SubtitleEditor.CueCount.\(model.document.cues.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func cueRow(index: Int, cue: TimedTextCue) -> some View {
        let isSelected = model.selectedCueID == cue.id
        let isActiveAtPlayhead = cue.isActive(at: model.currentTime)
        return Button {
            model.selectedCueID = cue.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(verbatim: "\(index + 1)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isActiveAtPlayhead ? Color.accentColor : .secondary)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(SubtitleEditorModel.formatCueTime(cue.startTime)) → \(SubtitleEditorModel.formatCueTime(cue.endTime))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isActiveAtPlayhead ? Color.accentColor : .secondary)

                    Text(verbatim: cue.text.isEmpty ? String(localized: "SubtitleEditor.CuePlaceholder") : cue.text)
                        .font(.body)
                        .foregroundStyle(cue.text.isEmpty ? .tertiary : .primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelected
                ? Color.accentColor.opacity(0.14)
                : (isActiveAtPlayhead ? Color.accentColor.opacity(0.06) : nil)
        )
        .contextMenu {
            Button {
                model.seekToCue(id: cue.id)
            } label: {
                Label("SubtitleEditor.JumpToCue", systemImage: "play")
            }
            Button {
                model.splitCue(id: cue.id)
            } label: {
                Label("SubtitleEditor.SplitCue", systemImage: "scissors")
            }
            if index + 1 < model.document.cues.count {
                Button {
                    model.mergeCueWithNext(id: cue.id)
                } label: {
                    Label("SubtitleEditor.MergeNext", systemImage: "arrow.triangle.merge")
                }
            }
            Divider()
            Button(role: .destructive) {
                model.deleteCue(id: cue.id)
            } label: {
                Label("Shared.Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var selectedCueEditorCard: some View {
        if model.selectedCueIndex != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("SubtitleEditor.SelectedCue")
                    .font(.headline)
                selectedCueControls
            }
            .padding(16)
            .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private var selectedCueControls: some View {
        if let index = model.selectedCueIndex, model.document.cues.indices.contains(index) {
            let cue = model.document.cues[index]
            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    "SubtitleEditor.CuePlaceholder",
                    text: Binding(
                        get: { model.document.cues.indices.contains(index) ? model.document.cues[index].text : "" },
                        set: { model.updateCueText(id: cue.id, text: $0) }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .focused($isCueTextFocused)

                nudgeRow(
                    title: "Trim.Start",
                    time: cue.startTime,
                    onNudge: { model.nudgeSelectedCue(startDelta: $0) }
                )

                nudgeRow(
                    title: "Trim.End",
                    time: cue.endTime,
                    onNudge: { model.nudgeSelectedCue(endDelta: $0) }
                )

                ViewThatFits(in: .horizontal) {
                    cueActionButtons(cue: cue, isIconOnly: false)
                    cueActionButtons(cue: cue, isIconOnly: true)
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
    }

    private func cueActionButtons(cue: TimedTextCue, isIconOnly: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                model.seekToCue(id: cue.id)
            } label: {
                Label("SubtitleEditor.JumpToCue", systemImage: "play")
            }
            Button {
                model.splitCue(id: cue.id)
            } label: {
                Label("SubtitleEditor.SplitCue", systemImage: "scissors")
            }
            Button {
                model.mergeCueWithNext(id: cue.id)
            } label: {
                Label("SubtitleEditor.MergeNext", systemImage: "arrow.triangle.merge")
            }
            .disabled(!model.canMergeSelectedWithNext)
            Spacer(minLength: 0)
            Button(role: .destructive) {
                model.deleteCue(id: cue.id)
            } label: {
                Image(systemName: "trash")
            }
        }
        .labelStyle(CueActionLabelStyle(isIconOnly: isIconOnly))
    }

    private func nudgeRow(
        title: LocalizedStringKey,
        time: TimeInterval,
        onNudge: @escaping (TimeInterval) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(verbatim: SubtitleEditorModel.formatCueTime(time))
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(minWidth: 56, alignment: .leading)
            Spacer()
            ForEach([-0.5, -0.1, 0.1, 0.5], id: \.self) { delta in
                Button {
                    onNudge(delta)
                } label: {
                    Text(verbatim: delta > 0 ? "+\(String(format: "%.1f", delta))" : String(format: "%.1f", delta))
                        .font(.caption2.monospacedDigit())
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(role: .close) {
                dismiss()
            }
        }

        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Shared.Done") {
                isCueTextFocused = false
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("SubtitleEditor.Tracks") {
                    ForEach(model.allSources) { source in
                        Button {
                            Task { await model.openSource(source) }
                        } label: {
                            if model.activeSource == source {
                                Label(source.displayName, systemImage: "checkmark")
                            } else {
                                Text(verbatim: source.displayName)
                            }
                        }
                    }
                }
                Divider()
                Button {
                    isTrackInfoPresented = true
                } label: {
                    Label("SubtitleEditor.TrackDetails", systemImage: "info.circle")
                }
                Button {
                    shiftOffsetSeconds = 0
                    isShiftSheetPresented = true
                } label: {
                    Label("SubtitleEditor.ShiftTimings", systemImage: "clock.arrow.2.circlepath")
                }
                .disabled(model.document.cues.isEmpty)
                Button {
                    importLyricsText = model.document.plainText()
                    isImportLyricsPresented = true
                } label: {
                    Label("SubtitleEditor.ImportPlainLyrics", systemImage: "text.alignleft")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button("Shared.Save") {
                isSaveSheetPresented = true
            }
            .fontWeight(.semibold)
            .disabled(model.isSaving)
        }
    }

    // MARK: - Sheets

    private var trackMetadataSheet: some View {
        NavigationStack {
            Form {
                Section("SubtitleEditor.TrackDetails") {
                    TextField(
                        "SubtitleEditor.TrackTitle",
                        text: Binding(
                            get: { model.document.title ?? "" },
                            set: { model.document.title = $0.isEmpty ? nil : $0 }
                        )
                    )
                    Picker(
                        "SubtitleEditor.Language",
                        selection: Binding(
                            get: { model.document.languageCode ?? "" },
                            set: { model.document.languageCode = $0.isEmpty ? nil : $0 }
                        )
                    ) {
                        ForEach(SubtitleLanguage.options(including: model.document.languageCode)) { lang in
                            Text(verbatim: lang.displayName).tag(lang.code)
                        }
                    }
                    Toggle("SubtitleEditor.IsSyncedLyrics", isOn: $model.document.isLyrics)
                }
            }
            .navigationTitle("SubtitleEditor.TrackDetails")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Shared.Done") {
                        isTrackInfoPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var shiftTimingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("SubtitleEditor.ShiftOffset")
                        Spacer()
                        Text(verbatim: String(format: "%+.2f s", shiftOffsetSeconds))
                            .font(.headline.monospacedDigit())
                    }
                    HStack(spacing: 8) {
                        ForEach([-1.0, -0.5, -0.1, 0.1, 0.5, 1.0], id: \.self) { delta in
                            Button {
                                shiftOffsetSeconds += delta
                            } label: {
                                Text(verbatim: delta > 0 ? "+\(String(format: "%.1f", delta))" : String(format: "%.1f", delta))
                                    .font(.caption.monospacedDigit())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } footer: {
                    Text("SubtitleEditor.ShiftFooter")
                }
            }
            .navigationTitle("SubtitleEditor.ShiftTimings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Shared.Cancel") {
                        isShiftSheetPresented = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("SubtitleEditor.ApplyShift") {
                        model.shiftAllTimings(by: shiftOffsetSeconds)
                        isShiftSheetPresented = false
                    }
                    .disabled(abs(shiftOffsetSeconds) < 0.001)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var importPlainLyricsSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("SubtitleEditor.ImportPlainLyrics.Description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                TextEditor(text: $importLyricsText)
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    .padding(.horizontal)
            }
            .padding(.top, 12)
            .navigationTitle("SubtitleEditor.ImportPlainLyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Shared.Cancel") {
                        isImportLyricsPresented = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("SubtitleEditor.Import") {
                        model.importPlainLyrics(importLyricsText)
                        isImportLyricsPresented = false
                    }
                    .disabled(importLyricsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var saveSheet: some View {
        NavigationStack {
            Form {
                Section("SubtitleEditor.SaveSidecar") {
                    Picker("SubtitleEditor.Format", selection: $model.preferredSidecarFormat) {
                        ForEach(TimedTextFormat.writableSidecarFormats) { format in
                            Text(verbatim: format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        isSaveSheetPresented = false
                        performSave(.sidecar(model.preferredSidecarFormat))
                    } label: {
                        Label("SubtitleEditor.SaveAsSidecar.\(model.preferredSidecarFormat.displayName)", systemImage: "doc.text")
                    }
                }

                if model.canEmbedInVideo {
                    Section {
                        if model.editingEmbeddedTrackID != nil {
                            Button {
                                isSaveSheetPresented = false
                                performSave(.embedInVideo(replaceExisting: true))
                            } label: {
                                Label("SubtitleEditor.EmbedReplaceTrack", systemImage: "film")
                            }
                        }
                        Button {
                            isSaveSheetPresented = false
                            performSave(.embedInVideo(replaceExisting: false))
                        } label: {
                            Label("SubtitleEditor.EmbedAddTrack", systemImage: "film.stack")
                        }
                    } header: {
                        Text("SubtitleEditor.SaveEmbedded")
                    } footer: {
                        Text("Trim.OriginalWillBeKept")
                    }
                }

                if model.canSaveLyricsTag {
                    Section {
                        Button {
                            isSaveSheetPresented = false
                            performSave(.lyricsTag)
                        } label: {
                            Label("SubtitleEditor.SaveToLyricsTag", systemImage: "music.note")
                        }
                    } footer: {
                        Text("SubtitleEditor.SaveToLyricsTag.Footer")
                    }
                }
            }
            .navigationTitle("Shared.Save")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Shared.Cancel") {
                        isSaveSheetPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                if model.saveProgress > 0 && model.saveProgress < 1 {
                    ProgressView(value: model.saveProgress)
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
                Text("SubtitleEditor.Saving")
                    .font(.headline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func performSave(_ destination: SubtitleSaveDestination) {
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            let fileChangedOnDisk = await model.save(to: destination)
            if model.errorMessage == nil {
                mediaPlayer.subtitlesDidChange(forPath: file.path, videoFileChangedOnDisk: fileChangedOnDisk)
                onChange?()
                dismiss()
            }
        }
    }
}

extension View {
    func subtitleEditorPresentation(
        _ presentation: Binding<SubtitleEditorPresentation?>,
        onChange: @escaping () -> Void
    ) -> some View {
        modifier(SubtitleEditorPresentationModifier(presentation: presentation, onChange: onChange))
    }
}

private struct SubtitleEditorPresentationModifier: ViewModifier {
    @Binding var presentation: SubtitleEditorPresentation?
    var onChange: () -> Void
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private var isWide: Bool {
        horizontalSizeClass == .regular
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: isWide ? .constant(nil) : $presentation) { item in
                SubtitleEditorView(file: item.file, onChange: onChange)
            }
            .fullScreenCover(item: isWide ? $presentation : .constant(nil)) { item in
                SubtitleEditorView(file: item.file, onChange: onChange)
            }
    }
}

private struct CueActionLabelStyle: LabelStyle {
    let isIconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isIconOnly {
            Label(configuration).labelStyle(.iconOnly)
        } else {
            Label(configuration).labelStyle(.titleAndIcon).fixedSize()
        }
    }
}
