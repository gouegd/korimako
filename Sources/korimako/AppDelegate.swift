import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let ipc = NcspotIPC()
    private let nowPlaying = NowPlayingController()

    private var connected = false
    private var menuIsOpen = false
    private var lastKnownMode: PlayMode = .stopped
    private var playbackTimer: Timer?

    /// Recently played, most-recent-first; index 0 is current, index 1 is previous.
    private struct TrackEntry {
        let id: String
        let title: String
        let artist: String
        let coverURL: String?
        let duration: Int?    // milliseconds
        let year: Int?
    }
    private var history: [TrackEntry] = []
    private static let historyLimit = 2

    /// Persisted across menu rebuilds; nil when not connected.
    private var nowPlayingView: NowPlayingMenuView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        setIcon("music.note")

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        populate(menu)

        nowPlaying.onCommand = { [weak self] command in self?.ipc.send(command) }
        nowPlaying.onArtworkLoaded = { [weak self] _ in
            guard let self, self.menuIsOpen else { return }
            self.updateNowPlayingView()
        }
        ipc.onConnected = { [weak self] connected in self?.handleConnection(connected) }
        ipc.onStatus    = { [weak self] status  in self?.handleStatus(status) }
        ipc.start()
    }

    // MARK: - IPC callbacks

    private func handleConnection(_ connected: Bool) {
        self.connected = connected
        if !connected {
            stopPlaybackTimer()
            nowPlayingView = nil
            nowPlaying.clear()
            render(nil)
            refreshMenuIfOpen()
        }
    }

    private func handleStatus(_ status: NcspotStatus) {
        lastKnownMode = status.mode
        nowPlaying.update(status: status)
        let trackChanged = updateHistory(status)
        render(status)
        switch status.mode {
        case .playing:
            startPlaybackTimer()
            if trackChanged { refreshMenuIfOpen() }
            else if menuIsOpen { updateNowPlayingView() }
        case .paused, .stopped:
            stopPlaybackTimer()
            if trackChanged { refreshMenuIfOpen() }
            else { updateNowPlayingView() }   // immediate label freeze on pause
        }
    }

    private func startPlaybackTimer() {
        guard playbackTimer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.menuIsOpen else { return }
            self.updateNowPlayingView()
        }
        // .common mode fires in both .default and .eventTracking — needed so
        // the timer ticks while NSMenu's event-tracking loop is running.
        RunLoop.main.add(t, forMode: .common)
        playbackTimer = t
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    @discardableResult
    private func updateHistory(_ status: NcspotStatus) -> Bool {
        guard let track = status.playable, let id = track.id else { return false }
        guard history.first?.id != id else { return false }
        history.removeAll { $0.id == id }
        history.insert(TrackEntry(id: id,
                                  title: track.title ?? "Unknown",
                                  artist: track.artistString,
                                  coverURL: track.cover_url,
                                  duration: track.duration,
                                  year: track.year),
                       at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        Log.debug("history: \(history.map(\.title))")
        return true
    }

    // MARK: - Menubar icon + title

    private func render(_ status: NcspotStatus?) {
        guard connected, let status, let track = status.playable else {
            setIcon("music.note")
            statusItem.button?.title = ""
            return
        }
        let title = track.title ?? ""
        switch status.mode {
        case .playing: setIcon("play.fill")
        case .paused:  setIcon("pause.fill")
        case .stopped: setIcon("music.note")
        }
        statusItem.button?.title = " " + truncate(title, max: 45)
    }

    private func setIcon(_ symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "korimako")
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

        // Widget (current track + optional previous track row)
        if connected {
            if nowPlayingView == nil {
                let view = NowPlayingMenuView()
                view.onPrevious   = { [weak self] in self?.ipc.send("previous") }
                view.onNext       = { [weak self] in self?.ipc.send("next") }
                view.onPlayPause  = { [weak self] in self?.ipc.send("playpause") }
                view.onArtTap = { [weak self] in self?.ipc.send("playpause") }
                nowPlayingView = view
            }
            updateNowPlayingView()          // sets correct height before item is added
            let item = NSMenuItem()
            item.view = nowPlayingView!
            menu.addItem(item)
        } else {
            let placeholder = NSMenuItem(title: "ncspot not running", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        }
        menu.addItem(.separator())

        // Artwork style picker
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

        // Launch at Login
        let launch = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state  = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launch)
        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit korimako", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func updateNowPlayingView() {
        guard let view = nowPlayingView else { return }

        let current = history.first
        let prev    = history.count > 1 ? history[1] : nil

        let artwork: NSImage? = current?.coverURL.flatMap { url in
            guard let orig = nowPlaying.cachedArtwork(for: url) else { return nil }
            return ArtworkTransform.apply(orig, style: ArtworkTransform.current)
        }
        let needsFlicker = ArtworkTransform.current == .flame || ArtworkTransform.current == .thermalClick
        let flickerArtwork: NSImage? = needsFlicker
            ? current?.coverURL.flatMap { url in
                guard let orig = nowPlaying.cachedArtwork(for: url) else { return nil }
                return ArtworkTransform.apply(orig, style: .thermal)
              }
            : nil
        let flickerMode: FlickerImageView.FlickerMode = {
            switch ArtworkTransform.current {
            case .flame:        return .flame
            case .thermalClick: return .onClick
            default:            return .none
            }
        }()

        let isPlaying: Bool
        let elapsed: TimeInterval
        switch lastKnownMode {
        case .playing(let startedAt):
            isPlaying = true
            elapsed   = max(0, Date().timeIntervalSince1970 - startedAt)
        case .paused(let e):
            isPlaying = false
            elapsed   = e
        case .stopped:
            isPlaying = false
            elapsed   = 0
        }
        let duration = TimeInterval(current?.duration ?? 0) / 1000.0

        let prevArtwork: NSImage? = prev?.coverURL.flatMap { url in
            guard let orig = nowPlaying.cachedArtwork(for: url) else { return nil }
            return ArtworkTransform.apply(orig, style: ArtworkTransform.current)
        }

        view.update(title: current?.title ?? "",
                    artist: current?.artist ?? "",
                    year: current?.year,
                    artwork: artwork,
                    flickerArtwork: flickerArtwork,
                    flickerMode: flickerMode,
                    isPlaying: isPlaying,
                    elapsed: elapsed,
                    duration: duration,
                    prevTitle: prev?.title,
                    prevArtist: prev?.artist,
                    prevYear: prev?.year,
                    prevArtwork: prevArtwork)
    }

    // MARK: - Actions

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = ArtworkStyle(rawValue: raw) else { return }
        ArtworkTransform.current = style
        nowPlaying.restyleCurrentArtwork()
        updateNowPlayingView()
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
            NSLog("korimako: launch-at-login toggle failed: \(error)")
        }
    }

    @objc private func quit() {
        ipc.stop()
        NSApp.terminate(nil)
    }
}
