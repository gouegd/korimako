import Foundation

/// One status frame streamed by ncspot over its IPC socket
/// (newline-delimited JSON). Examples:
///   {"mode":{"Paused":{"secs":62,"nanos":315000000}},"playable":{...}}
///   {"mode":{"Playing":{"secs_since_epoch":1781235611,"nanos_since_epoch":...}},"playable":{...}}
struct NcspotStatus: Decodable {
    let mode: PlayMode
    let playable: Playable?

    private enum CodingKeys: String, CodingKey { case mode, playable }
    private struct VariantKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playable = try container.decodeIfPresent(Playable.self, forKey: .playable)

        // `mode` is an externally-tagged Rust enum. The carried value differs
        // per variant:
        //   "Stopped"                                         -> bare string
        //   {"Playing":{secs_since_epoch,nanos_since_epoch}}  -> SystemTime (start instant)
        //   {"Paused":{secs,nanos}}                           -> Duration (elapsed position)
        if (try? container.decode(String.self, forKey: .mode)) != nil {
            mode = .stopped   // only "Stopped" serializes as a bare string
        } else {
            let variant = try container.nestedContainer(keyedBy: VariantKey.self, forKey: .mode)
            switch variant.allKeys.first?.stringValue {
            case "Playing":
                let key = VariantKey(stringValue: "Playing")!
                let t = try variant.decode(NcspotSystemTime.self, forKey: key)
                mode = .playing(startedAt: t.epochSeconds)
            case "Paused":
                let key = VariantKey(stringValue: "Paused")!
                let d = try variant.decode(NcspotDuration.self, forKey: key)
                mode = .paused(elapsed: d.seconds)
            default:
                mode = .stopped
            }
        }
    }
}

enum PlayMode {
    case stopped
    /// Unix-epoch instant corresponding to playback position 0
    /// (current position = now − startedAt).
    case playing(startedAt: TimeInterval)
    /// Fixed elapsed position while paused.
    case paused(elapsed: TimeInterval)
}

struct NcspotDuration: Decodable {
    let secs: Double
    let nanos: Double
    var seconds: TimeInterval { secs + nanos / 1_000_000_000 }
}

struct NcspotSystemTime: Decodable {
    let secs_since_epoch: Double
    let nanos_since_epoch: Double
    var epochSeconds: TimeInterval { secs_since_epoch + nanos_since_epoch / 1_000_000_000 }
}

/// The currently loaded track/episode. ncspot sends far more than this;
/// we decode only what we need for NowPlaying + the menubar.
struct Playable: Decodable {
    let id: String?
    let type: String?
    let title: String?
    let artists: [String]?
    let album: String?
    let duration: Int?       // milliseconds
    let cover_url: String?
    let year: Int?

    var artistString: String { (artists ?? []).joined(separator: ", ") }
    var durationSeconds: TimeInterval? { duration.map { Double($0) / 1000.0 } }
}
