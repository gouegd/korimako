// Downloads an album cover URL, applies the same CIComicEffect korimako uses,
// and writes a side-by-side [original | cartoon] PNG you can `open`. POC aid.
//   swiftc -o /tmp/cartoonprev scripts/cartoon-preview.swift
//   /tmp/cartoonprev "<cover_url>" [out.png]
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

func die(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2, let url = URL(string: args[1]) else {
    die("usage: cartoon-preview <cover_url> [out.png]")
}
let outPath = args.count >= 3 ? args[2] : "/tmp/korimako-cartoon-poc.png"

guard let data = try? Data(contentsOf: url), let original = NSImage(data: data) else {
    die("failed to download/decode \(url)")
}

let ciContext = CIContext(options: nil)
func cartoon(_ image: NSImage) -> NSImage {
    var rect = NSRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return image }
    let f = CIFilter.comicEffect()
    f.inputImage = CIImage(cgImage: cg)
    guard let out = f.outputImage, let r = ciContext.createCGImage(out, from: out.extent) else { return image }
    return NSImage(cgImage: r, size: NSSize(width: r.width, height: r.height))
}

let styled = cartoon(original)

// Compose side-by-side into a bitmap-backed context (no window-server needed).
let w = original.size.width, h = original.size.height
let gap: CGFloat = 16
let cw = Int(w * 2 + gap), ch = Int(h)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: cw, pixelsHigh: ch,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    die("failed to allocate bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.black.setFill()
NSRect(x: 0, y: 0, width: cw, height: ch).fill()
original.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
styled.draw(in: NSRect(x: w + gap, y: 0, width: w, height: h))
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    die("failed to encode PNG")
}
do { try png.write(to: URL(fileURLWithPath: outPath)) } catch { die("write failed: \(error)") }
print(outPath)
