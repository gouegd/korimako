import AppKit

/// Dev tool: render a cover URL through a style and write an
/// [original | styled] side-by-side PNG. Invoked via `korimako --render`.
/// Reuses the exact `ArtworkTransform` pipeline so the preview matches what
/// Control Center shows.
enum ArtworkPreview {
    static func renderComparison(coverURL: String, style: ArtworkStyle, outPath: String) {
        guard let url = URL(string: coverURL),
              let data = try? Data(contentsOf: url),
              let original = NSImage(data: data) else {
            FileHandle.standardError.write("preview: failed to load \(coverURL)\n".data(using: .utf8)!)
            return
        }
        let styled = ArtworkTransform.apply(original, style: style)

        let w = original.size.width, h = original.size.height
        let gap: CGFloat = 16
        let cw = Int(w * 2 + gap), ch = Int(h)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: cw, pixelsHigh: ch,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: cw, height: ch).fill()
        original.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        styled.draw(in: NSRect(x: w + gap, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()

        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: outPath))
            print(outPath)
        }
    }
}
