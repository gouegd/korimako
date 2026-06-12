import AppKit

// Headless preview mode (dev tool): render a cover through a style and exit.
//   korimako --render <style> <coverURL> [outPath]
let arguments = CommandLine.arguments
if arguments.count >= 4, arguments[1] == "--render" {
    let style = ArtworkStyle(rawValue: arguments[2]) ?? .cartoon
    let outPath = arguments.count >= 5 ? arguments[4] : "/tmp/korimako-style.png"
    ArtworkPreview.renderComparison(coverURL: arguments[3], style: style, outPath: outPath)
    exit(0)
}

// Pure menubar (accessory) app — no Dock icon, no main window.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
