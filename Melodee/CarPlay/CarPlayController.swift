import CarPlay
import SFBAudioEngine
import UIKit

/// Builds the CarPlay templates for browsing files, playlists and the queue,
/// and drives playback through the same MediaPlayerManager as the phone UI.
@MainActor
final class CarPlayController: NSObject {

    // CarPlay limits audio apps to this many templates in the navigation stack
    private static let maximumTemplateDepth = 5

    private let interfaceController: CPInterfaceController
    private let services: AppServices
    private var mediaPlayer: MediaPlayerManager { services.mediaPlayerManager }

    private var sourcesTemplate: CPListTemplate?
    private let queueTemplates = NSHashTable<CPListTemplate>.weakObjects()
    private var isConnected: Bool = false

    init(interfaceController: CPInterfaceController, services: AppServices) {
        self.interfaceController = interfaceController
        self.services = services
        super.init()
    }

    func connect() {
        isConnected = true
        interfaceController.delegate = self
        let sourcesTemplate = makeSourcesTemplate()
        self.sourcesTemplate = sourcesTemplate
        let queueTemplate = makeQueueTemplate()
        queueTemplate.tabTitle = String(localized: "Shared.Queue")
        queueTemplate.tabImage = UIImage(systemName: "list.bullet")
        let tabBarTemplate = CPTabBarTemplate(templates: [sourcesTemplate, queueTemplate])
        interfaceController.setRootTemplate(tabBarTemplate, animated: false, completion: nil)
        configureNowPlayingTemplate()
        observePlayer()
    }

    func disconnect() {
        isConnected = false
        CPNowPlayingTemplate.shared.remove(self)
    }

    // MARK: - Sources

    private func makeSourcesTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: String(localized: "ViewTitle.Files"), sections: [])
        template.tabTitle = String(localized: "ViewTitle.Files")
        template.tabImage = UIImage(systemName: "folder")
        updateSources(of: template)
        return template
    }

    private func updateSources(of template: CPListTemplate) {
        let fileManager = services.fileManager
        var items: [CPListItem] = []
        if let url = fileManager.documentsDirectoryURL {
            items.append(folderItem(title: String(localized: "Shared.OnMyDevice"),
                                    url: url,
                                    image: UIImage(systemName: "iphone")))
        }
        if FileManager.default.ubiquityIdentityToken != nil,
           let url = fileManager.cloudDocumentsDirectoryURL {
            items.append(folderItem(title: String(localized: "Shared.iCloudDrive"),
                                    url: url,
                                    image: UIImage(systemName: "icloud")))
        }
        var sections = [CPListSection(items: items)]
        let externalFolders = services.externalFoldersManager
        let externalItems = externalFolders.bookmarks.compactMap { bookmark -> CPListItem? in
            guard let url = externalFolders.resolveBookmark(bookmark) else { return nil }
            return folderItem(title: bookmark.name, url: url, image: UIImage(systemName: "externaldrive"))
        }
        if !externalItems.isEmpty {
            sections.append(CPListSection(items: externalItems,
                                          header: String(localized: "Tab.ExternalFolders"),
                                          sectionIndexTitle: nil))
        }
        template.updateSections(sections)
    }

    // MARK: - Folders

    private func makeFolderTemplate(title: String, url: URL) -> CPListTemplate {
        let contents = services.fileManager.files(in: url, recursive: false)
        let folders = contents.compactMap { $0 as? FSDirectory }
        let files = contents.compactMap { $0 as? FSFile }
        let playlists = files.filter { $0.type == .playlist }
        // Video and other non-audio files can't be shown while driving
        let audioFiles = files.filter { $0.type == .audio }

        var sections: [CPListSection] = []
        if !audioFiles.isEmpty {
            sections.append(CPListSection(items: playbackActionItems(for: audioFiles)))
        }
        let folderItems = folders.map { folder in
            folderItem(title: folder.name,
                       url: URL(filePath: folder.path),
                       image: UIImage(systemName: "folder"))
        }
        let playlistItems = playlists.map { playlistItem(for: $0) }
        if !(folderItems + playlistItems).isEmpty {
            sections.append(CPListSection(items: folderItems + playlistItems))
        }
        if !audioFiles.isEmpty {
            sections.append(CPListSection(items: audioItems(for: audioFiles)))
        }

        let template = CPListTemplate(title: title, sections: limited(sections))
        template.emptyViewTitleVariants = [String(localized: "Playlists.Detail.Empty.Title")]
        return template
    }

    private func folderItem(title: String, url: URL, image: UIImage?) -> CPListItem {
        let item = CPListItem(text: title, detailText: nil, image: image)
        item.accessoryType = .disclosureIndicator
        item.handler = { [weak self] _, completion in
            self?.openFolder(title: title, url: url)
            completion()
        }
        return item
    }

    private func openFolder(title: String, url: URL) {
        if interfaceController.templates.count < Self.maximumTemplateDepth {
            interfaceController.pushTemplate(makeFolderTemplate(title: title, url: url),
                                             animated: true,
                                             completion: nil)
        } else {
            // CarPlay can't go any deeper, so play everything inside the folder instead
            let audioFiles = audioFiles(in: services.fileManager.files(in: url, recursive: true))
            guard !audioFiles.isEmpty else { return }
            play(audioFiles, startingAt: 0)
        }
    }

    private func audioFiles(in contents: [any FilesystemObject]) -> [FSFile] {
        contents.flatMap { object -> [FSFile] in
            if let directory = object as? FSDirectory {
                return audioFiles(in: directory.files)
            } else if let file = object as? FSFile, file.type == .audio {
                return [file]
            }
            return []
        }
    }

    // MARK: - Playlists

    private func playlistItem(for file: FSFile) -> CPListItem {
        let item = CPListItem(text: file.name, detailText: nil, image: UIImage(systemName: "music.note.list"))
        item.accessoryType = .disclosureIndicator
        item.handler = { [weak self] _, completion in
            self?.openPlaylist(file)
            completion()
        }
        return item
    }

    private func openPlaylist(_ file: FSFile) {
        let fileURL = URL(fileURLWithPath: file.path)
        let baseURL = fileURL.deletingLastPathComponent()
        let audioFiles = (PlaylistManager.load(from: fileURL)?.files ?? [])
            .compactMap { $0.resolve(relativeTo: baseURL) }
            .filter { $0.type == .audio }
        guard interfaceController.templates.count < Self.maximumTemplateDepth else {
            if !audioFiles.isEmpty {
                play(audioFiles, startingAt: 0)
            }
            return
        }
        var sections: [CPListSection] = []
        if !audioFiles.isEmpty {
            sections.append(CPListSection(items: playbackActionItems(for: audioFiles)))
            sections.append(CPListSection(items: audioItems(for: audioFiles)))
        }
        let template = CPListTemplate(title: file.name, sections: limited(sections))
        template.emptyViewTitleVariants = [String(localized: "Playlists.Detail.Empty.Title")]
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Audio files

    private func playbackActionItems(for audioFiles: [FSFile]) -> [CPListItem] {
        let playAllItem = CPListItem(text: String(localized: "Shared.PlayAll"),
                                     detailText: nil,
                                     image: UIImage(systemName: "play.fill"))
        playAllItem.handler = { [weak self] _, completion in
            self?.play(audioFiles, startingAt: 0)
            completion()
        }
        let shuffleItem = CPListItem(text: String(localized: "Shared.Shuffle"),
                                     detailText: nil,
                                     image: UIImage(systemName: "shuffle"))
        shuffleItem.handler = { [weak self] _, completion in
            self?.play(audioFiles.shuffled(), startingAt: 0)
            completion()
        }
        return [playAllItem, shuffleItem]
    }

    private func audioItems(for audioFiles: [FSFile]) -> [CPListItem] {
        let items = audioFiles.enumerated().map { index, file in
            let item = CPListItem(text: file.name, detailText: nil, image: UIImage(systemName: "music.note"))
            if file.isEvicted() {
                item.accessoryType = .cloud
            }
            item.handler = { [weak self] _, completion in
                self?.play(audioFiles, startingAt: index)
                completion()
            }
            return item
        }
        loadAlbumArt(for: Array(zip(items, audioFiles)))
        return items
    }

    /// Loads album art one file at a time in the background and sets it on the list items.
    private func loadAlbumArt(for entries: [(item: CPListItem, file: FSFile)]) {
        let imageSize = CPListItem.maximumImageSize
        let files = entries.map { $0.file }
        let items = entries.map { $0.item }
        Task.detached(priority: .utility) {
            for (index, file) in files.enumerated() where !file.isEvicted() {
                guard let image = AudioFile.read(for: file)?.coverImage,
                      let thumbnail = await image.byPreparingThumbnail(ofSize: imageSize) else { continue }
                await MainActor.run {
                    items[index].setImage(thumbnail)
                }
            }
        }
    }

    /// Trims sections so the total number of items stays within CarPlay's list limit.
    private func limited(_ sections: [CPListSection]) -> [CPListSection] {
        var remainingItems = CPListTemplate.maximumItemCount
        var limitedSections: [CPListSection] = []
        for section in sections.prefix(CPListTemplate.maximumSectionCount) {
            guard remainingItems > 0 else { break }
            let items = Array(section.items.prefix(remainingItems))
            remainingItems -= items.count
            limitedSections.append(CPListSection(items: items,
                                                 header: section.header,
                                                 sectionIndexTitle: section.sectionIndexTitle))
        }
        return limitedSections
    }

    // MARK: - Playback

    private func play(_ audioFiles: [FSFile], startingAt index: Int) {
        mediaPlayer.stop()
        for file in audioFiles {
            mediaPlayer.queueLast(file: file)
        }
        guard index < mediaPlayer.queue.count else { return }
        mediaPlayer.playImmediately(mediaPlayer.queue[index], addToQueue: false)
        showNowPlaying()
    }

    private func showNowPlaying() {
        guard interfaceController.topTemplate !== CPNowPlayingTemplate.shared else { return }
        interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }

    // MARK: - Queue

    private func makeQueueTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: String(localized: "Shared.Queue"), sections: [])
        template.emptyViewTitleVariants = [String(localized: "Shared.NoFilePlaying")]
        queueTemplates.add(template)
        updateQueue(of: template)
        return template
    }

    private func updateQueue(of template: CPListTemplate) {
        let items = mediaPlayer.queue.map { file in
            let item = CPListItem(text: file.name, detailText: nil, image: UIImage(systemName: "music.note"))
            if file.playbackQueueID == mediaPlayer.currentlyPlayingID {
                item.isPlaying = true
                item.playingIndicatorLocation = .trailing
            }
            item.handler = { [weak self] _, completion in
                self?.mediaPlayer.playImmediately(file, addToQueue: false)
                self?.showNowPlaying()
                completion()
            }
            return item
        }
        template.updateSections(items.isEmpty ? [] : limited([CPListSection(items: items)]))
    }

    /// Keeps the queue lists in sync with changes made from either the phone or CarPlay.
    private func observePlayer() {
        guard isConnected else { return }
        withObservationTracking {
            _ = mediaPlayer.queue
            _ = mediaPlayer.currentlyPlayingID
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isConnected else { return }
                for template in self.queueTemplates.allObjects {
                    self.updateQueue(of: template)
                }
                self.observePlayer()
            }
        }
    }

    // MARK: - Now Playing

    private func configureNowPlayingTemplate() {
        let nowPlayingTemplate = CPNowPlayingTemplate.shared
        nowPlayingTemplate.isUpNextButtonEnabled = true
        nowPlayingTemplate.upNextTitle = String(localized: "Shared.Queue")
        nowPlayingTemplate.add(self)
        let repeatButton = CPNowPlayingRepeatButton { [weak self] _ in
            guard let mediaPlayer = self?.mediaPlayer else { return }
            switch mediaPlayer.repeatMode {
            case .none: mediaPlayer.repeatMode = .single
            case .single: mediaPlayer.repeatMode = .all
            case .all: mediaPlayer.repeatMode = .none
            }
        }
        nowPlayingTemplate.updateNowPlayingButtons([repeatButton])
    }
}

extension CarPlayController: CPNowPlayingTemplateObserver {
    nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        MainActor.assumeIsolated {
            interfaceController.pushTemplate(makeQueueTemplate(), animated: true, completion: nil)
        }
    }
}

extension CarPlayController: CPInterfaceControllerDelegate {
    nonisolated func templateWillAppear(_ aTemplate: CPTemplate, animated: Bool) {
        MainActor.assumeIsolated {
            // External folders may have been added or removed on the phone since the list was built
            if let sourcesTemplate, aTemplate === sourcesTemplate {
                updateSources(of: sourcesTemplate)
            }
        }
    }
}
