import Foundation

/// Thin wrapper over the private MediaRemote.framework symbol that lets a
/// non-audio app declare itself eligible to be the system "Now Playing" app.
///
/// OFF by default. On macOS 13–26 the public MediaPlayer API alone is enough to
/// own the media keys, and skipping this nudge preserves the system's natural
/// now-playing handoff (pause ncspot → your browser gets the keys, like
/// Spotify/Music). Opt in with `SOUND_KEKO_USE_PRIVATE=1` only if a future macOS
/// stops routing media keys without it.
enum MediaRemoteShim {
    private typealias SetCanBeNowPlayingFn = @convention(c) (Bool) -> Void
    private static var setCanBeFn: SetCanBeNowPlayingFn?
    private static var loaded = false

    /// True if the private symbol resolved and the nudge is permitted.
    private(set) static var isAvailable = false

    private static var privateEnabled: Bool {
        ProcessInfo.processInfo.environment["SOUND_KEKO_USE_PRIVATE"] != nil
    }

    /// Declare (or revoke) eligibility to become the Now Playing app.
    /// No-op unless explicitly opted in (see above).
    static func setNowPlayingEligibility(_ enabled: Bool) {
        guard privateEnabled else { return }
        load()
        setCanBeFn?(enabled)
    }

    private static func load() {
        guard !loaded else { return }
        loaded = true
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        if let sym = dlsym(handle, "MRMediaRemoteSetCanBeNowPlayingApplication") {
            setCanBeFn = unsafeBitCast(sym, to: SetCanBeNowPlayingFn.self)
            isAvailable = true
        }
    }
}
