//
//  SubtitleEditorMacView.swift
//  Melodee
//

import SwiftUI
import Videoglot

/// Desktop Lyrics & Subtitle Editor view for macOS, with live video preview, tap-to-time controls,
/// cue list, nudging, timing shift, track language/title metadata, and sidecar or container-embedded saving.
struct SubtitleEditorMacView: View {

    let file: FSFile
    @Bindable var model: SubtitleEditorModel
    var onSaved: (Bool) -> Void

    @State private var isShiftPopoverPresented = false
    @State private var isImportSheetPresented = false
    @State private var shiftOffsetSeconds: Double = 0
    @State private var importLyricsText: String = ""
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    leftVideoPane
                        .frame(minWidth: 380, idealWidth: 480)
                    rightCuePane
                        .frame(minWidth: 340, idealWidth: 460)
                }
            }
        }
        .overlay {
            if model.isSaving {
                savingOverlay
            }
        }
        .disabled(model.isSaving)
        .task {
            if MacServices.shared.player.isPlaying {
                MacServices.shared.player.pause()
            }
            let subtitles = MacServices.shared.player.subtitleController
            let isPlayingThisFile = subtitles.videoURL?.standardizedFileURL == URL(filePath: file.path).standardizedFileURL
            await model.load(preferring: isPlayingThisFile ? subtitles.selectedTrack?.source : nil)
        }
        .alert(
            MacText.shared("SubtitleEditor.Error.Title"),
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button(MacText.shared("Shared.OK"), role: .cancel) { }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
        .sheet(isPresented: $isImportSheetPresented) {
            importPlainLyricsSheet
        }
    }

    // MARK: - Left Pane: Video Preview, Transport, Live Timing, Track Details

    private var leftVideoPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sourcePickerRow

                SubtitleEditorVideoPreview(model: model, isCompact: false)
                    .frame(maxHeight: 300)

                transportBar
                liveTimingBar

                Divider()

                trackDetailsSection
            }
            .padding(16)
        }
    }

    private var sourcePickerRow: some View {
        HStack(spacing: 8) {
            Picker(
                MacText.shared("SubtitleEditor.Tracks"),
                selection: Binding(
                    get: { model.activeSource },
                    set: { newSource in
                        Task { await model.openSource(newSource) }
                    }
                )
            ) {
                ForEach(model.allSources) { source in
                    Text(verbatim: source.displayName).tag(source)
                }
            }
            .labelsHidden()

            Button {
                importLyricsText = model.document.plainText()
                isImportSheetPresented = true
            } label: {
                Label(MacText.shared("SubtitleEditor.ImportPlainLyrics"), systemImage: "text.alignleft")
            }
            .controlSize(.small)
        }
    }

    private var transportBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(verbatim: SubtitleEditorModel.formatCueTime(isScrubbing ? scrubTime : model.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubTime : model.currentTime },
                        set: { value in
                            scrubTime = value
                            model.seek(to: value)
                        }
                    ),
                    in: 0...max(model.totalDuration, 1.0),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                    }
                )

                Text(verbatim: SubtitleEditorModel.formatCueTime(model.totalDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }

            HStack(spacing: 12) {
                Picker("", selection: $model.previewRate) {
                    ForEach([Float(0.5), 0.75, 1.0, 1.25], id: \.self) { rate in
                        Text(verbatim: PlaybackSpeed.label(for: Double(rate))).tag(rate)
                    }
                }
                .labelsHidden()
                .frame(width: 72)

                Spacer()

                Button { model.step(by: -5) } label: { Image(systemName: "gobackward.5") }
                Button { model.step(by: -1) } label: { Image(systemName: "backward.frame") }
                Button {
                    model.togglePlayPause()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 24)
                }
                .keyboardShortcut(.space, modifiers: [])
                Button { model.step(by: 1) } label: { Image(systemName: "forward.frame") }
                Button { model.step(by: 5) } label: { Image(systemName: "goforward.5") }

                Spacer()

                Button {
                    model.addCueAtPlayhead()
                } label: {
                    Label(MacText.shared("SubtitleEditor.AddCue"), systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var liveTimingBar: some View {
        HStack(spacing: 8) {
            Button {
                model.markStartAtPlayhead()
            } label: {
                Label(MacText.shared("SubtitleEditor.MarkStart"), systemImage: "arrow.right.to.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("[", modifiers: .command)

            Button {
                model.markEndAtPlayhead(advanceToNext: false)
            } label: {
                Label(MacText.shared("SubtitleEditor.MarkEnd"), systemImage: "arrow.left.to.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedCueID == nil)
            .keyboardShortcut("]", modifiers: .command)

            Button {
                model.markAndAdvanceToNextCue()
            } label: {
                Label(MacText.shared("SubtitleEditor.NextCue"), systemImage: "forward.end")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.document.cues.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var trackDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(MacText.shared("SubtitleEditor.TrackDetails"))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(MacText.shared("SubtitleEditor.TrackTitle"))
                        .foregroundStyle(.secondary)
                    TextField(
                        "",
                        text: Binding(
                            get: { model.document.title ?? "" },
                            set: { model.document.title = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(MacText.shared("SubtitleEditor.Language"))
                        .foregroundStyle(.secondary)
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.document.languageCode ?? "" },
                            set: { model.document.languageCode = $0.isEmpty ? nil : $0 }
                        )
                    ) {
                        ForEach(SubtitleLanguage.options(including: model.document.languageCode)) { lang in
                            Text(verbatim: lang.displayName).tag(lang.code)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Color.clear.frame(height: 1)
                    Toggle(MacText.shared("SubtitleEditor.IsSyncedLyrics"), isOn: $model.document.isLyrics)
                }
            }
        }
    }

    // MARK: - Right Pane: Cue List, Cue Editor, Bottom Save Bar

    private var rightCuePane: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: String(localized: "SubtitleEditor.CueCount.\(model.document.cues.count)"))
                    .font(.headline)
                Spacer()
                Button {
                    shiftOffsetSeconds = 0
                    isShiftPopoverPresented = true
                } label: {
                    Label(MacText.shared("SubtitleEditor.ShiftTimings"), systemImage: "clock.arrow.2.circlepath")
                }
                .controlSize(.small)
                .disabled(model.document.cues.isEmpty)
                .popover(isPresented: $isShiftPopoverPresented) {
                    shiftTimingsPopover
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if model.document.cues.isEmpty {
                ContentUnavailableView {
                    Label(MacText.shared("SubtitleEditor.NoCues.Title"), systemImage: "captions.bubble")
                } description: {
                    Text(MacText.shared("SubtitleEditor.NoCues.Description"))
                } actions: {
                    Button(MacText.shared("SubtitleEditor.AddCue")) {
                        model.addCueAtPlayhead()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selectedCueID) {
                    ForEach(Array(model.document.cues.enumerated()), id: \.element.id) { index, cue in
                        cueRow(index: index, cue: cue)
                            .tag(cue.id)
                    }
                }
                .listStyle(.inset)
            }

            if model.selectedCueIndex != nil {
                Divider()
                selectedCueEditor
                    .padding(14)
                    .background(.windowBackground)
            }

            Divider()
            bottomActionBar
        }
    }

    private func cueRow(index: Int, cue: TimedTextCue) -> some View {
        let isActive = cue.isActive(at: model.currentTime)
        return HStack(alignment: .top, spacing: 8) {
            Text(verbatim: "\(index + 1)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "\(SubtitleEditorModel.formatCueTime(cue.startTime)) → \(SubtitleEditorModel.formatCueTime(cue.endTime))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                Text(verbatim: cue.text.isEmpty ? MacText.shared("SubtitleEditor.CuePlaceholder") : cue.text)
                    .foregroundStyle(cue.text.isEmpty ? .tertiary : .primary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.seekToCue(id: cue.id)
        }
        .contextMenu {
            Button(MacText.shared("SubtitleEditor.JumpToCue")) {
                model.seekToCue(id: cue.id)
            }
            Button(MacText.shared("SubtitleEditor.SplitCue")) {
                model.splitCue(id: cue.id)
            }
            if index + 1 < model.document.cues.count {
                Button(MacText.shared("SubtitleEditor.MergeNext")) {
                    model.mergeCueWithNext(id: cue.id)
                }
            }
            Divider()
            Button(MacText.shared("Shared.Delete"), role: .destructive) {
                model.deleteCue(id: cue.id)
            }
        }
    }

    @ViewBuilder
    private var selectedCueEditor: some View {
        if let index = model.selectedCueIndex, model.document.cues.indices.contains(index) {
            let cue = model.document.cues[index]
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(
                    text: Binding(
                        get: { model.document.cues.indices.contains(index) ? model.document.cues[index].text : "" },
                        set: { model.updateCueText(id: cue.id, text: $0) }
                    )
                )
                .font(.body)
                .frame(height: 62)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

                nudgeRow(
                    title: MacText.shared("Trim.Start"),
                    time: cue.startTime,
                    onNudge: { model.nudgeSelectedCue(startDelta: $0) }
                )

                nudgeRow(
                    title: MacText.shared("Trim.End"),
                    time: cue.endTime,
                    onNudge: { model.nudgeSelectedCue(endDelta: $0) }
                )

                HStack(spacing: 8) {
                    Button {
                        model.seekToCue(id: cue.id)
                    } label: {
                        Label(MacText.shared("SubtitleEditor.JumpToCue"), systemImage: "play")
                    }
                    Button {
                        model.splitCue(id: cue.id)
                    } label: {
                        Label(MacText.shared("SubtitleEditor.SplitCue"), systemImage: "scissors")
                    }
                    Button {
                        model.mergeCueWithNext(id: cue.id)
                    } label: {
                        Label(MacText.shared("SubtitleEditor.MergeNext"), systemImage: "arrow.triangle.merge")
                    }
                    .disabled(!model.canMergeSelectedWithNext)
                    Spacer()
                    Button(role: .destructive) {
                        model.deleteCue(id: cue.id)
                    } label: {
                        Label(MacText.shared("Shared.Delete"), systemImage: "trash")
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func nudgeRow(
        title: String,
        time: TimeInterval,
        onNudge: @escaping (TimeInterval) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(verbatim: SubtitleEditorModel.formatCueTime(time))
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 64, alignment: .leading)
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

    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            if let savedNotice = model.savedNotice {
                Label(savedNotice, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if model.canEmbedInVideo {
                Text(MacText.shared("Trim.OriginalWillBeKept"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Section(MacText.shared("SubtitleEditor.SaveSidecar")) {
                    ForEach(TimedTextFormat.writableSidecarFormats) { format in
                        Button {
                            performSave(.sidecar(format))
                        } label: {
                            Label(
                                String(localized: "SubtitleEditor.SaveAsSidecar.\(format.displayName)"),
                                systemImage: "doc.text"
                            )
                        }
                    }
                }
                if model.canEmbedInVideo {
                    Section(MacText.shared("SubtitleEditor.SaveEmbedded")) {
                        if model.editingEmbeddedTrackID != nil {
                            Button {
                                performSave(.embedInVideo(replaceExisting: true))
                            } label: {
                                Label(MacText.shared("SubtitleEditor.EmbedReplaceTrack"), systemImage: "film")
                            }
                        }
                        Button {
                            performSave(.embedInVideo(replaceExisting: false))
                        } label: {
                            Label(MacText.shared("SubtitleEditor.EmbedAddTrack"), systemImage: "film.stack")
                        }
                    }
                }
                if model.canSaveLyricsTag {
                    Section {
                        Button {
                            performSave(.lyricsTag)
                        } label: {
                            Label(MacText.shared("SubtitleEditor.SaveToLyricsTag"), systemImage: "music.note")
                        }
                    }
                }
            } label: {
                Text(MacText.shared("Shared.Save"))
            } primaryAction: {
                performSave(.sidecar(model.preferredSidecarFormat))
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isSaving)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Popovers & Sheets

    private var shiftTimingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(MacText.shared("SubtitleEditor.ShiftTimings"))
                .font(.headline)

            HStack {
                Text(MacText.shared("SubtitleEditor.ShiftOffset"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: String(format: "%+.2f s", shiftOffsetSeconds))
                    .font(.body.monospacedDigit().weight(.semibold))
            }

            HStack(spacing: 6) {
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

            HStack {
                Spacer()
                Button(MacText.shared("Shared.Cancel")) {
                    isShiftPopoverPresented = false
                }
                Button(MacText.shared("SubtitleEditor.ApplyShift")) {
                    model.shiftAllTimings(by: shiftOffsetSeconds)
                    isShiftPopoverPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(abs(shiftOffsetSeconds) < 0.001)
            }
        }
        .padding(16)
        .frame(width: 310)
    }

    private var importPlainLyricsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(MacText.shared("SubtitleEditor.ImportPlainLyrics"))
                .font(.headline)
            Text(MacText.shared("SubtitleEditor.ImportPlainLyrics.Description"))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $importLyricsText)
                .font(.body)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            HStack {
                Spacer()
                Button(MacText.shared("Shared.Cancel")) {
                    isImportSheetPresented = false
                }
                Button(MacText.shared("SubtitleEditor.Import")) {
                    model.importPlainLyrics(importLyricsText)
                    isImportSheetPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(importLyricsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440, height: 340)
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
            VStack(spacing: 10) {
                if model.saveProgress > 0 && model.saveProgress < 1 {
                    ProgressView(value: model.saveProgress)
                        .frame(width: 180)
                } else {
                    ProgressView()
                }
                Text(MacText.shared("SubtitleEditor.Saving"))
                    .font(.headline)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func performSave(_ destination: SubtitleSaveDestination) {
        Task {
            let fileChangedOnDisk = await model.save(to: destination)
            if model.errorMessage == nil {
                MacServices.shared.player.subtitlesDidChange(
                    forPath: file.path,
                    videoFileChangedOnDisk: fileChangedOnDisk
                )
                onSaved(fileChangedOnDisk)
            }
        }
    }
}
