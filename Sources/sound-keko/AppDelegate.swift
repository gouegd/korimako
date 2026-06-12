import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let ipc = NcspotIPC()
    private let nowPlaying = NowPlayingController()

    private var connected = false
    private var menuIsOpen = false

    /// When the user clicks a recent track we step back to it by repeatedly
    /// sending `previous` until ncspot's current track matches this id (the
    /// first `previous` may just restart the current track, so we can't count).
    private var navTarget: (id: String, attemptsLeft: Int)?

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
        menu.delegate = self
        menu.autoenablesItems = false        // let informational rows render normally
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
            refreshMenuIfOpen()
        }
    }

    private func handleStatus(_ status: NcspotStatus) {
        nowPlaying.update(status: status)         // fetches/caches current cover first
        let trackChanged = updateHistory(status)
        render(status)
        advanceNavigation(currentId: status.playable?.id)
        if trackChanged { refreshMenuIfOpen() }   // keep an open menu live
    }

    /// Returns true if the current track changed. De-dupes so navigating back
    /// to an already-listed track doesn't show it twice.
    @discardableResult
    private func updateHistory(_ status: NcspotStatus) -> Bool {
        guard let track = status.playable, let id = track.id else { return false }
        guard history.first?.id != id else { return false }   // same track (pause/seek/tick)
        history.removeAll { $0.id == id }
        history.insert(TrackEntry(id: id,
                                  title: track.title ?? "Unknown",
                                  artist: track.artists?.first ?? "",
                                  coverURL: track.cover_url),
                       at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        Log.debug("history: \(history.map(\.title))")
        return true
    }

    /// Drive the "click a recent track → step back to it" navigation.
    private func advanceNavigation(currentId: String?) {
        guard let nav = navTarget else { return }
        if currentId == nav.id {
            navTarget = nil                                   // arrived
        } else if nav.attemptsLeft > 0 {
            navTarget = (nav.id, nav.attemptsLeft - 1)
            ipc.send("previous")
        } else {
            navTarget = nil                                   // give up, don't loop forever
        }
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

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }
    func menuNeedsUpdate(_ menu: NSMenu) { populate(menu) }

    private func refreshMenuIfOpen() {
        guard menuIsOpen, let menu = statusItem.menu else { return }
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Now playing (▶) + recently played.
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
            item.representedObject = entry.id   // navigation target for playPrevious
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

    /// Step back through play history to the clicked recent track (by id).
    @objc private func playPrevious(_ sender: NSMenuItem) {
        guard let targetId = sender.representedObject as? String else { return }
        navTarget = (targetId, 8)
        ipc.send("previous")
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = ArtworkStyle(rawValue: raw) else { return }
        ArtworkTransform.current = style
        nowPlaying.restyleCurrentArtwork()
        refreshMenuIfOpen()
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
