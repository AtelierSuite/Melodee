//
//  TagInspectorModel.swift
//  Melodee
//

import Foundation
import Observation
import Prelude

/// Reads the tags of the files chosen with Edit Track Information, and writes edits back to all of them.
@MainActor @Observable
final class TagInspectorModel {

    private static let maxConcurrentSaves = 4

    private(set) var files: [FSFile] = []
    private(set) var loadedFiles: [FSFile] = []
    private(set) var loadedTag = Tag()
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var savedFileCount = 0
    private(set) var loadedExtendedFields: [ExtendedTagField] = []
    private(set) var unsupportedKeys: [String] = []
    var isShowingSaveError = false
    var isShowingRemoveTagsError = false
    var isShowingUnsupportedKeys = false
    var isShowingOnlineLookup = false
    var isShowingSaveBeforeOnlineLookup = false
    var tag = Tag() {
        didSet { notifyDirtyChangeIfNeeded() }
    }
    var isAlbumArtRemoved = false {
        didSet { notifyDirtyChangeIfNeeded() }
    }
    /// The file's tags that the standard fields don't cover, read only when editing a single file.
    var extendedFields: [ExtendedTagField] = [] {
        didSet { notifyDirtyChangeIfNeeded() }
    }

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var wasDirty = false
    /// Called with the files whose tags were written, and whether the inspector should close.
    @ObservationIgnored var onSave: ((_ files: [FSFile], _ closesInspector: Bool) -> Void)?
    /// Called when Cancel is clicked.
    @ObservationIgnored var onCancel: (() -> Void)?
    @ObservationIgnored var onDirtyChange: ((Bool) -> Void)?

    var isBatchEditing: Bool {
        loadedFiles.count > 1
    }

    var isDirty: Bool {
        !loadedFiles.isEmpty && (tag != loadedTag || isAlbumArtRemoved || extendedFields != loadedExtendedFields)
    }

    var canEditExtendedTags: Bool {
        loadedFiles.count == 1
    }

    var canSave: Bool {
        isDirty && !isLoading && !isSaving && tag.hasValidNumbersAllowingTokens && loadedFiles == files
    }

    func edit(_ newFiles: [FSFile]) {
        loadTask?.cancel()
        files = newFiles
        show(Tag(), extendedFields: [], for: [])
        guard !newFiles.isEmpty else { return }
        isLoading = true
        loadTask = Task { [weak self] in
            await self?.load(newFiles)
        }
    }

    func cancel() {
        onCancel?()
    }

    func save() {
        guard canSave else { return }
        let savingFiles = files
        let savingTag = tag
        let albumArtRemoved = isAlbumArtRemoved
        let savingProperties = extendedFields != loadedExtendedFields ? extendedPropertyChanges() : [:]
        isSaving = true
        savedFileCount = 0
        Task {
            let allSaved = await withTaskGroup(of: Bool.self) { group in
                var iterator = savingFiles.makeIterator()
                var allSaved = true
                func addNext() -> Bool {
                    guard let file = iterator.next() else { return false }
                    group.addTask {
                        await TagFileIO.save(savingTag, to: file, albumArtRemoved: albumArtRemoved,
                                             properties: savingProperties)
                    }
                    return true
                }
                var startedSaves = 0
                while startedSaves < Self.maxConcurrentSaves && addNext() {
                    startedSaves += 1
                }
                while let saved = await group.next() {
                    allSaved = allSaved && saved
                    savedFileCount += 1
                    _ = addNext()
                }
                return allSaved
            }
            await finishWriting(savingFiles, succeeded: allSaved, properties: savingProperties) {
                self.isShowingSaveError = true
            }
        }
    }

    /// Opens the online lookup, which writes to the files directly, so unsaved edits have to be saved first.
    func lookUpOnline() {
        guard !loadedFiles.isEmpty, !isLoading, !isSaving else { return }
        if isDirty {
            isShowingSaveBeforeOnlineLookup = true
        } else {
            isShowingOnlineLookup = true
        }
    }

    /// Reads the files again after the online lookup wrote to them, keeping the inspector open to show the result.
    func didApplyOnlineLookup() {
        let appliedFiles = loadedFiles
        edit(appliedFiles)
        onSave?(appliedFiles, false)
    }

    func addExtendedField(key: String, value: String) {
        extendedFields.append(ExtendedTagField(key: key, value: value))
    }

    func removeExtendedField(_ field: ExtendedTagField) {
        extendedFields.removeAll { $0.id == field.id }
    }

    func removeAllTags() {
        guard !loadedFiles.isEmpty, !isLoading, !isSaving else { return }
        let removingFiles = loadedFiles
        isSaving = true
        savedFileCount = 0
        Task {
            var allRemoved = true
            for file in removingFiles {
                let removed = await TagFileIO.removeAllTags(from: file)
                allRemoved = allRemoved && removed
                savedFileCount += 1
            }
            await finishWriting(removingFiles, succeeded: allRemoved, properties: [:]) {
                self.isShowingRemoveTagsError = true
            }
        }
    }

    /// Every extended property's new values, where an empty array removes a property that was deleted.
    private func extendedPropertyChanges() -> [String: [String]] {
        var changes: [String: [String]] = [:]
        for field in loadedExtendedFields {
            changes[field.key] = []
        }
        for field in extendedFields where !field.value.isEmpty {
            changes[field.key, default: []].append(field.value)
        }
        return changes
    }

    /// Closes the inspector once everything was written. If something failed, the inspector stays open
    /// with the files read again, so the error is shown next to what was actually saved.
    private func finishWriting(_ writtenFiles: [FSFile], succeeded: Bool, properties: [String: [String]],
                               onFailure: () -> Void) async {
        if succeeded, let missingKeys = await unsupportedKeys(in: properties, of: writtenFiles), !missingKeys.isEmpty {
            // Keep the inspector open to say which fields the format couldn't hold
            unsupportedKeys = missingKeys
            await load(writtenFiles)
            isSaving = false
            isShowingUnsupportedKeys = true
            onSave?(writtenFiles, false)
            return
        }
        if succeeded {
            isSaving = false
            onSave?(writtenFiles, true)
        } else {
            await load(writtenFiles)
            isSaving = false
            onSave?(writtenFiles, false)
            onFailure()
        }
    }

    /// The saved extended properties that didn't come back when the file was read again.
    private func unsupportedKeys(in properties: [String: [String]], of writtenFiles: [FSFile]) async -> [String]? {
        let savedKeys = properties.filter { !$0.value.isEmpty }.keys
        guard !savedKeys.isEmpty, let path = writtenFiles.first?.path, writtenFiles.count == 1 else { return nil }
        let readKeys = await Task.detached(priority: .userInitiated) {
            Set(TagLibFile(path: path)?.properties.keys.map { $0 } ?? [])
        }.value
        return savedKeys.filter { !readKeys.contains($0) }.map { TagKey.displayName(for: $0) }.sorted()
    }

    private func load(_ filesToLoad: [FSFile]) async {
        let paths = filesToLoad.map(\.path)
        let (snapshot, properties) = await Task.detached(priority: .userInitiated) {
            () -> (TagSnapshot?, [String: [String]]) in
            guard paths.count == 1 else { return (TagSnapshot.read(paths: paths), [:]) }
            guard let file = TagLibFile(path: paths[0]) else { return (nil, [:]) }
            return (TagSnapshot(file), file.properties)
        }.value
        guard !Task.isCancelled, filesToLoad == files else { return }
        show(snapshot.map { Tag(from: $0) } ?? Tag(), extendedFields: Self.extendedFields(from: properties),
             for: filesToLoad)
        isLoading = false
    }

    private static func extendedFields(from properties: [String: [String]]) -> [ExtendedTagField] {
        let sortedKeys = properties.keys.filter { !TagKey.editorKeys.contains($0) }.sorted {
            TagKey.displayName(for: $0).localizedStandardCompare(TagKey.displayName(for: $1)) == .orderedAscending
        }
        return sortedKeys.flatMap { key in
            (properties[key] ?? []).map { ExtendedTagField(key: key, value: $0) }
        }
    }

    private func show(_ newTag: Tag, extendedFields newExtendedFields: [ExtendedTagField], for newFiles: [FSFile]) {
        loadedFiles = newFiles
        loadedTag = newTag
        tag = newTag
        isAlbumArtRemoved = false
        loadedExtendedFields = newExtendedFields
        extendedFields = newExtendedFields
    }

    private func notifyDirtyChangeIfNeeded() {
        guard isDirty != wasDirty else { return }
        wasDirty = isDirty
        onDirtyChange?(isDirty)
    }
}

/// One value of a raw tag property. Properties with several values have a field for each.
struct ExtendedTagField: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}
