import Foundation
import AppKit
import MediaPlayer

/// Owns the system NowPlaying registration:
///  - publishes track metadata + playback state so macUI/Control Center show it,
///  - registers remote-command handlers so hardware media keys route to us,
///  - emits the matching ncspot command token via `onCommand`.
final class NowPlayingController {
    /// Emits ncspot command tokens ("playpause" / "next" / "previous").
    var onCommand: ((String) -> Void)?

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    private var current: [String: Any] = [:]
    private var lastTrackId: String?
    private var originalCache: [String: NSImage] = [:]   // raw downloaded covers, keyed by URL
    private var currentCoverURL: String?

    init() { setupCommands() }

    // MARK: - Remote commands (hardware media keys)

    private func setupCommands() {
        let toggle: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
            Log.debug("remote command -> playpause")
            self?.onCommand?("playpause"); return .success
        }
        // Play / pause / toggle keys all map to ncspot's idempotent toggle.
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget(handler: toggle)
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget(handler: toggle)
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget(handler: toggle)

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Log.debug("remote command -> next")
            self?.onCommand?("next"); return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Log.debug("remote command -> previous")
            self?.onCommand?("previous"); return .success
        }

        // Control Center scrubber: drag to an absolute position. The event's
        // positionTime is in seconds; ncspot's `seek` takes an explicit unit.
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let ms = Int((event.positionTime * 1000).rounded())
            Log.debug("remote command -> seek \(ms)ms")
            self?.onCommand?("seek \(ms)ms")
            return .success
        }

        // Advertise that we don't handle these, so the UI hides them.
        for command in [
            commandCenter.seekForwardCommand, commandCenter.seekBackwardCommand,
            commandCenter.skipForwardCommand, commandCenter.skipBackwardCommand,
            commandCenter.changePlaybackRateCommand,
            commandCenter.ratingCommand, commandCenter.likeCommand,
            commandCenter.dislikeCommand, commandCenter.bookmarkCommand,
        ] {
            command.isEnabled = false
        }
    }

    // MARK: - NowPlaying metadata

    func update(status: NcspotStatus) {
        let track = status.playable
        let trackChanged = track?.id != lastTrackId
        lastTrackId = track?.id
        if trackChanged { current = [:] }   // drop stale artwork etc.

        current[MPMediaItemPropertyTitle] = track?.title ?? "ncspot"
        current[MPMediaItemPropertyArtist] = track?.artistString ?? ""
        current[MPMediaItemPropertyAlbumTitle] = track?.album ?? ""
        current[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        if let duration = track?.durationSeconds {
            current[MPMediaItemPropertyPlaybackDuration] = duration
        }

        switch status.mode {
        case .playing(let startedAt):
            let elapsed = max(0, Date().timeIntervalSince1970 - startedAt)
            current[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            current[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
            infoCenter.playbackState = .playing
        case .paused(let elapsed):
            current[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            current[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
            infoCenter.playbackState = .paused
        case .stopped:
            current[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
            current[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
            infoCenter.playbackState = .stopped
        }

        MediaRemoteShim.setNowPlayingEligibility(true)
        infoCenter.nowPlayingInfo = current
        Log.debug("nowPlaying set: \"\(track?.title ?? "-")\" state=\(infoCenter.playbackState.rawValue) privateNudge=\(MediaRemoteShim.isAvailable ? "on" : "off")")

        if let cover = track?.cover_url {
            currentCoverURL = cover
            applyArtwork(cover, forTrack: lastTrackId)
        } else {
            currentCoverURL = nil
        }
    }

    /// ncspot is gone — relinquish ownership so media keys fall back to
    /// whatever else (browser, Music) wants them.
    func clear() {
        current = [:]
        lastTrackId = nil
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
        MediaRemoteShim.setNowPlayingEligibility(false)
    }

    private func applyArtwork(_ url: String, forTrack trackId: String?) {
        if let original = originalCache[url] {
            setStyledArtwork(original)
            return
        }
        guard let u = URL(string: url) else { return }
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.originalCache[url] = image
                guard self.lastTrackId == trackId else { return }   // track moved on
                self.setStyledArtwork(image)
            }
        }.resume()
    }

    /// Apply the active ArtworkTransform to `original` and publish it.
    private func setStyledArtwork(_ original: NSImage) {
        let styled = ArtworkTransform.apply(original)
        current[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: styled.size) { _ in styled }
        infoCenter.nowPlayingInfo = current
    }

    /// Re-render the current cover with the (possibly changed) active style.
    /// Called when the user picks a different style from the menu.
    func restyleCurrentArtwork() {
        guard let url = currentCoverURL, let original = originalCache[url] else { return }
        setStyledArtwork(original)
    }
}
