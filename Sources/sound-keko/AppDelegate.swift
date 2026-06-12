import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let ipc = NcspotIPC()
    private let nowPlaying = NowPlayingController()

    private var connected = false
    private let trackItem = NSMenuItem(title: "Connecting…", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(
        title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let styleSubmenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        setIcon("music.note")
        buildMenu()

        nowPlaying.onCommand = { [weak self] command in self?.ipc.send(command) }
        ipc.onConnected = { [weak self] connected in self?.handleConnection(connected) }
        ipc.onStatus = { [weak self] status in self?.handleStatus(status) }
        ipc.start()
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        trackItem.isEnabled = false
        menu.addItem(trackItem)
        menu.addItem(.separator())

        // Artwork style picker (live: re-renders the current cover on change).
        let styleItem = NSMenuItem(title: "Artwork Style", action: nil, keyEquivalent: "")
        for style in ArtworkStyle.allCases {
            let item = NSMenuItem(
                title: style.displayName, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == ArtworkTransform.current ? .on : .off
            styleSubmenu.addItem(item)
        }
        styleItem.submenu = styleSubmenu
        menu.addItem(styleItem)
        menu.addItem(.separator())

        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit sound-keko", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
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
        nowPlaying.update(status: status)
        render(status)
    }

    // MARK: - Menubar rendering

    private func render(_ status: NcspotStatus?) {
        guard connected, let status, let track = status.playable else {
            setIcon("music.note")
            statusItem.button?.title = ""
            trackItem.title = connected ? "Nothing playing" : "ncspot not running"
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
        trackItem.title = label
    }

    private func setIcon(_ symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "sound-keko")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func truncate(_ s: String, max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }

    // MARK: - Launch at login

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
        launchAtLoginItem.state = isLaunchAtLoginEnabled ? .on : .off
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = ArtworkStyle(rawValue: raw) else { return }
        ArtworkTransform.current = style
        for item in styleSubmenu.items {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }
        nowPlaying.restyleCurrentArtwork()
        Log.debug("artwork style -> \(style.rawValue)")
    }

    @objc private func quit() {
        ipc.stop()
        NSApp.terminate(nil)
    }
}
