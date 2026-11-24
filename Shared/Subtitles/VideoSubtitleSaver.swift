import CoreMedia
import Foundation
import Prelude
import Videoglot

/// Saves edited subtitle and lyrics tracks either as sidecar files, embedded container tracks, or file lyrics tags.
/// Embedding into a video container keeps a backup of the original file via ``TrimBackups``, matching trimming.
enum VideoSubtitleSaver {

    /// Saves `document` as a sidecar file (`.srt`, `.vtt`, or `.lrc`).
    @discardableResult
    static func saveSidecar(
        _ document: TimedTextDocument,
        for videoURL: URL,
        format: TimedTextFormat,
        destinationURL: URL? = nil
    ) throws -> URL {
        let targetURL = destinationURL ?? SidecarTimedTextFile.suggestedURL(
            for: videoURL,
            format: format,
            languageCode: document.languageCode,
            title: document.title
        )
        try TimedTextCodec.write(document, to: targetURL, format: format)
        return targetURL
    }

    /// Whether subtitles can be embedded directly into the video file's container.
    static func canEmbed(into videoURL: URL) -> Bool {
        Videoglot.subtitleEmbeddableExtensions.contains(videoURL.pathExtension.lowercased())
    }

    /// Whether lyrics metadata (`LYRICS` / `©lyr`) can be written directly into the video file via TagLib.
    static func canSaveLyricsTag(to videoURL: URL) -> Bool {
        TagLibFile.supportedExtensions().contains(videoURL.pathExtension.lowercased())
    }

    /// Embeds `document` as a `tx3g` subtitle track in `videoURL`, keeping a backup of the original via ``TrimBackups``.
    static func embed(
        _ document: TimedTextDocument,
        into videoURL: URL,
        replacingTrackID: CMPersistentTrackID? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let manager = FileManager.default
        let workDirectory = try manager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: videoURL,
            create: true
        )
        defer { try? manager.removeItem(at: workDirectory) }
        let stagedURL = workDirectory.appending(path: videoURL.lastPathComponent)

        try await Videoglot.embedSubtitles(
            document,
            into: videoURL,
            outputURL: stagedURL,
            replacingTrackID: replacingTrackID,
            progress: progress
        )

        // Preserve any TagLib tags (title, artwork, lyrics, etc.) on the video container
        await copyTags(from: videoURL, to: stagedURL)

        let backupURL = TrimBackups.backupURL(for: videoURL)
        if TrimBackups.hasBackup(for: videoURL) {
            _ = try manager.replaceItemAt(videoURL, withItemAt: stagedURL)
        } else {
            try manager.moveItem(at: videoURL, to: backupURL)
            do {
                try manager.moveItem(at: stagedURL, to: videoURL)
            } catch {
                try? manager.moveItem(at: backupURL, to: videoURL)
                throw error
            }
        }
        // Restart the 30-day retention clock on the original backup
        try? manager.setAttributes([.modificationDate: Date.now], ofItemAtPath: backupURL.path(percentEncoded: false))
    }

    /// Saves synced LRC lyrics (or plain text if no cues) into the file's `LYRICS` tag, staying consistent with
    /// the tag editor's lyrics field.
    static func saveLyricsTag(_ document: TimedTextDocument, to videoURL: URL) async throws {
        let lrcText = document.hasTimedCues
            ? TimedTextCodec.serialize(document, as: .lrc).trimmingCharacters(in: .whitespacesAndNewlines)
            : (document.unsyncedText ?? "")
        let path = videoURL.path(percentEncoded: false)
        let saved = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard let tagFile = TagLibFile(path: path) else { return false }
            tagFile.setValues(lrcText.isEmpty ? nil : [lrcText], forProperty: "LYRICS")
            return tagFile.save()
        }.value
        if !saved {
            throw VideoglotError.subtitleWriteFailed
        }
    }

    private static func copyTags(from sourceURL: URL, to destinationURL: URL) async {
        await Task.detached(priority: .userInitiated) {
            guard TagLibFile.supportedExtensions().contains(destinationURL.pathExtension.lowercased()),
                  let source = TagLibFile(path: sourceURL.path(percentEncoded: false)),
                  let destination = TagLibFile(path: destinationURL.path(percentEncoded: false)) else { return }
            for (key, values) in source.properties {
                destination.setValues(values, forProperty: key)
            }
            if let cover = source.frontCover {
                destination.setFrontCover(cover)
            }
            _ = destination.save()
        }.value
    }
}
