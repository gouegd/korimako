// Prints the system-wide "Now Playing" info dict via the private MediaRemote
// framework. Used to confirm sound-keko registered metadata system-wide.
//   swiftc -o /tmp/npinfo scripts/verify-nowplaying.swift && /tmp/npinfo
import Foundation

let handle = dlopen(
    "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)!
typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
let get = unsafeBitCast(dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")!, to: GetInfoFn.self)

get(DispatchQueue.main) { info in
    guard let info else {
        print("info == nil (no active system Now Playing app)")
        exit(0)
    }
    print("info has \(CFDictionaryGetCount(info)) entries")
    guard let dict = info as? [String: Any] else {
        print("(could not bridge CFDictionary to [String: Any])")
        exit(0)
    }
    for key in dict.keys.sorted() {
        let value = dict[key]!
        if let data = value as? Data {
            print("\(key) = <\(data.count) bytes>")
        } else {
            print("\(key) = \(value)")
        }
    }
    exit(0)
}
RunLoop.main.run(until: Date().addingTimeInterval(3))
print("(timed out waiting for Now Playing info)")
