import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let ipc = NcspotIPC()
    private let nowPlaying = NowPlayingController()

    private var connected = false

    /// Recently played, most-recent-first; index 0 is the current track.
    /// Capped at `historyLimit` (current + the latest two).
    private struct TrackEntry {
        let id: String
        let title: String
        let artist: String
        let coverURL: String?
    }
    private var history: [TrackEntry] = []
    private static let historyLimit = 3

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        setIcon("music.note")

        let menu = NSMenu()
        menu.delegate = self                 // rebuilt on open via menuNeedsUpdate
        menu.autoenablesItems = false        // let informational track rows render normally
        statusItem.menu = menu
        populate(menu)

        nowPlaying.onCommand = { [weak self] command in self?.ipc.send(command) }
        ipc.onConnected = { [weak self] connected in self?.handleConnection(connected) }
        ipc.onStatus = { [weak self] status in self?.handleStatus(status) }
        ipc.start()
    }

    // MARK: - IPC callbacks

    private func handleConnection(_ connected: Bool) {
        self.connected = connected
        if !connected {
            nowPlaying.clear()
            render(nil)
        }
    }

    private func handleStatus(_ status: NcspotStatus) {
        nowPlaying.update(status: status)   // fetches/caches current cover first
        updateHistory(status)
        render(status)
    }

    private func updateHistory(_ status: NcspotStatus) {
        guard let track = status.playable, let id = track.id else { return }
        guard history.first?.id != id else { return }   // same track (pause / seek / tick)
        history.insert(TrackEntry(id: id,
                                  title: track.title ?? "Unknown",
                                  artist: track.artists?.first ?? "",
                                  coverURL: track.cover_url),
                       at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        Log.debug("history: \(history.map(\.title))")
    }

    // MARK: - Menubar icon + title (updates live)

    private func render(_ status: NcspotStatus?) {
        guard connected, let status, let track = status.playable else {
            setIcon("music.note")
            statusItem.button?.title = ""
            return
        }
        let artist = track.artists?.first ?? ""
        let title = track.title ?? ""
        let label = artist.isEmpty ? title : "\(artist) – \(title)"
        switch status.mode {
        case .playing: setIcon("play.fill")
        case .paused:  setIcon("pause.fill")
        case .stopped: setIcon("music.note")
        }
        statusItem.button?.title = " " + truncate(label, max: 45)
    }

    private func setIcon(_ symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "sound-keko")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func truncate(_ s: String, max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }

    // MARK: - Menu (rebuilt each time it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Now playing (▶) + recently played, each with its album art.
        if connected, !history.isEmpty {
            for (index, entry) in history.enumerated() {
                if index == 1 { menu.addItem(sectionHeader("Recently played")) }
                menu.addItem(trackItem(entry, index: index))
            }
        } else {
            let placeholder = NSMenuItem(
                title: connected ? "Nothing playing" : "ncspot not running",
                action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        }
        menu.addItem(.separator())

        // Artwork style picker.
        let styleItem = NSMenuItem(title: "Artwork Style", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for style in ArtworkStyle.allCases {
            let item = NSMenuItem(
                title: style.displayName, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == ArtworkTransform.current ? .on : .off
            styleMenu.addItem(item)
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)
        menu.addItem(.separator())

        // Launch at Login.
        let launch = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launch)
        menu.addItem(.separator())

        // Quit.
        let quit = NSMenuItem(title: "Quit sound-keko", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func sectionHeader(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return item
    }

    private func trackItem(_ entry: TrackEntry, index: Int) -> NSMenuItem {
        let isCurrent = index == 0
        let item = NSMenuItem(
            title: entry.title,
            action: isCurrent ? #selector(togglePlayPause) : #selector(playPrevious(_:)),
            keyEquivalent: "")
        item.target = self
        item.attributedTitle = trackTitle(entry, isCurrent: isCurrent)

        if isCurrent {
            // Only the current track shows art, styled to match the active selection.
            if let url = entry.coverURL, let original = nowPlaying.cachedArtwork(for: url) {
                let styled = ArtworkTransform.apply(original, style: ArtworkTransform.current)
                styled.size = NSSize(width: 38, height: 38)
                item.image = styled
            }
        } else {
            // Clicking a recent track navigates back to it (ncspot `previous`
            // follows play history). Item at index i → send `previous` i times.
            item.representedObject = index
        }
        return item
    }

    private func trackTitle(_ entry: TrackEntry, isCurrent: Bool) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let titleText = (isCurrent ? "▶ " : "") + (entry.title.isEmpty ? "Unknown" : entry.title)
        let result = NSMutableAttributedString(string: titleText, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ])
        if !entry.artist.isEmpty {
            result.append(NSAttributedString(string: "\n" + entry.artist, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: para,
            ]))
        }
        return result
    }

    // MARK: - Actions

    @objc private func togglePlayPause() {
        ipc.send("playpause")
    }

    /// Step back through play history to the clicked recent track.
    @objc private func playPrevious(_ sender: NSMenuItem) {
        let steps = (sender.representedObject as? Int) ?? 1
        for _ in 0..<steps { ipc.send("previous") }
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = ArtworkStyle(rawValue: raw) else { return }
        ArtworkTransform.current = style
        nowPlaying.restyleCurrentArtwork()
        Log.debug("artwork style -> \(style.rawValue)")
    }

    private var isLaunchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("sound-keko: launch-at-login toggle failed: \(error)")
        }
    }

    @objc private func quit() {
        ipc.stop()
        NSApp.terminate(nil)
    }
}
