import Foundation
import Darwin

/// Talks to a running ncspot over its Unix domain socket.
///
/// A single connection is bidirectional: ncspot streams newline-delimited
/// JSON status frames, and we write plaintext command tokens
/// (`playpause`, `next`, `previous`) back over the same socket.
///
/// Runs a dedicated reader thread that auto-(re)connects with backoff, so it
/// transparently handles ncspot starting/stopping at any time.
final class NcspotIPC {
    /// Called on the main thread with each decoded status frame.
    var onStatus: ((NcspotStatus) -> Void)?
    /// Called on the main thread whenever the connection comes up / goes down.
    var onConnected: ((Bool) -> Void)?

    private var fd: Int32 = -1
    private let fdLock = NSLock()
    private var running = false
    private let queue = DispatchQueue(label: "app.soundkeko.ipc-reader")

    func start() {
        guard !running else { return }
        running = true
        queue.async { [weak self] in self?.runLoop() }
    }

    func stop() {
        running = false
        closeConnection()
    }

    /// Send a command token to ncspot (e.g. "playpause", "next", "previous").
    func send(_ command: String) {
        fdLock.lock(); let f = fd; fdLock.unlock()
        guard f >= 0 else { return }
        let bytes = Array((command + "\n").utf8)
        _ = bytes.withUnsafeBytes { write(f, $0.baseAddress, $0.count) }
    }

    // MARK: - Reader thread

    private func runLoop() {
        while running {
            guard let path = NcspotIPC.discoverSocketPath(),
                  let newFd = NcspotIPC.connectUnix(path) else {
                notifyConnected(false)
                Thread.sleep(forTimeInterval: 2.0)   // ncspot not up yet — retry
                continue
            }
            fdLock.lock(); fd = newFd; fdLock.unlock()
            notifyConnected(true)
            readUntilClosed(newFd)                   // blocks until EOF/error
            closeConnection()
            notifyConnected(false)
            if running { Thread.sleep(forTimeInterval: 1.0) }
        }
    }

    private func readUntilClosed(_ fd: Int32) {
        var buffer = Data()
        let chunkSize = 8192
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        while running {
            let n = recv(fd, &chunk, chunkSize, 0)
            if n <= 0 { break }                      // 0 = ncspot quit, <0 = error
            Log.debug("recv \(n) bytes")
            buffer.append(contentsOf: chunk[0..<n])
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if line.isEmpty { continue }
                do {
                    let status = try JSONDecoder().decode(NcspotStatus.self, from: line)
                    DispatchQueue.main.async { [weak self] in self?.onStatus?(status) }
                } catch {
                    Log.debug("decode failed: \(error) :: \(String(data: line, encoding: .utf8)?.prefix(180) ?? "")")
                }
            }
        }
    }

    private func closeConnection() {
        fdLock.lock()
        if fd >= 0 { close(fd); fd = -1 }
        fdLock.unlock()
    }

    private func notifyConnected(_ connected: Bool) {
        Log.debug("IPC \(connected ? "connected" : "disconnected")")
        DispatchQueue.main.async { [weak self] in self?.onConnected?(connected) }
    }

    // MARK: - Socket discovery

    private static var cachedSocketPath: String?

    /// Dynamic first (authoritative, respects custom basepaths), with a
    /// deterministic hardcoded fallback.
    static func discoverSocketPath() -> String? {
        if let p = socketPathFromNcspotInfo(), FileManager.default.fileExists(atPath: p) {
            return p
        }
        let fallback = "/tmp/ncspot-\(getuid())/ncspot.sock"
        return FileManager.default.fileExists(atPath: fallback) ? fallback : nil
    }

    /// Parse `ncspot info` -> `USER_RUNTIME_PATH <dir>` and append `/ncspot.sock`.
    /// Cached: ncspot computes this without a running instance, so one call suffices.
    private static func socketPathFromNcspotInfo() -> String? {
        if let cached = cachedSocketPath { return cached }
        guard let exe = findNcspot() else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = ["info"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, parts[0] == "USER_RUNTIME_PATH" {
                let path = parts[1].trimmingCharacters(in: .whitespaces) + "/ncspot.sock"
                cachedSocketPath = path
                return path
            }
        }
        return nil
    }

    private static func findNcspot() -> String? {
        let candidates = ["/opt/homebrew/bin/ncspot", "/usr/local/bin/ncspot", "/usr/bin/ncspot"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        // Fall back to PATH lookup.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["which", "ncspot"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    static func connectUnix(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else { close(fd); return nil }
        withUnsafeMutablePointer(to: &addr.sun_path.0) { dst in
            path.withCString { src in _ = strncpy(dst, src, maxLen - 1) }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.stride)
        var result: Int32 = -1
        withUnsafePointer(to: &addr) { aptr in
            aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sptr in
                result = connect(fd, sptr, size)
            }
        }
        if result != 0 { close(fd); return nil }
        return fd
    }
}
