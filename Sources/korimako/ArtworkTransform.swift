import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Album-art styles selectable from the menu bar. Each maps to a Core Image
/// effect applied after download, before the art reaches the system Now Playing
/// UI. Hook point: `NowPlayingController.applyArtwork`.
enum ArtworkStyle: String, CaseIterable {
    case original, flame, thermalClick, noir, sepia, pixel, thermal

    var displayName: String {
        switch self {
        case .original:     return "Original"
        case .flame:        return "Flame"
        case .thermalClick: return "Thermal Click"
        case .noir:         return "Noir"
        case .sepia:        return "Sepia"
        case .pixel:        return "Pixel"
        case .thermal:      return "Thermal"
        }
    }
}

enum ArtworkTransform {
    private static let defaultsKey = "ArtworkStyle"
    private static let context = CIContext(options: nil)

    /// Currently selected style, persisted across launches.
    static var current: ArtworkStyle {
        get { ArtworkStyle(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .original }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    static func apply(_ image: NSImage) -> NSImage {
        apply(image, style: current)
    }

    /// Returns the best image for the hover reveal overlay.
    /// Uses thermal for most images. Falls back to dark sepia for warm light greens,
    /// where thermal maps to a similar yellow-green family and the mask becomes unreadable.
    /// Dark greens and mint/teal are excluded — they shift dramatically in thermal.
    static func revealImage(for original: NSImage, displayedAs displayedArt: NSImage) -> NSImage {
        guard let (r, g, b) = sampleAvgColor(original, inset: 0.2) else {
            return apply(original, style: .thermal)
        }
        let brightness    = (r + g + b) / 3
        let greenOverRed  = g - r   // warm-green dominance over red
        let greenOverBlue = g - b   // excludes teal/mint/cyan (those have g-b < ~0.12)
        Log.debug("reveal avg  r=\(String(format:"%.2f",r)) g=\(String(format:"%.2f",g)) b=\(String(format:"%.2f",b))  brightness=\(String(format:"%.2f",brightness))  g-r=\(String(format:"%.2f",greenOverRed))  g-b=\(String(format:"%.2f",greenOverBlue))")
        if greenOverRed > 0.05 && greenOverBlue > 0.15 && brightness > 0.30 {
            return filter(original) { input in
                let sepia = CIFilter.sepiaTone()
                sepia.inputImage = input
                sepia.intensity = 1.0
                guard let sepiaOut = sepia.outputImage else { return nil }
                let exp = CIFilter.exposureAdjust()
                exp.inputImage = sepiaOut
                exp.ev = -1.5
                return exp.outputImage
            }
        }
        return apply(original, style: .thermal)
    }

    /// Average RGB of the centre region (inset by `inset` fraction on each side), 0–1 per channel.
    private static func sampleAvgColor(_ image: NSImage, inset: CGFloat) -> (Float, Float, Float)? {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let ci     = CIImage(cgImage: cg)
        let center = ci.extent.insetBy(dx: ci.extent.width * inset, dy: ci.extent.height * inset)
        guard let f = CIFilter(name: "CIAreaAverage") else { return nil }
        f.setValue(ci.cropped(to: center), forKey: kCIInputImageKey)
        f.setValue(CIVector(cgRect: center), forKey: "inputExtent")
        guard let out  = f.outputImage,
              let cgOut = context.createCGImage(out, from: CGRect(x: 0, y: 0, width: 1, height: 1)),
              let data   = cgOut.dataProvider?.data,
              CFDataGetLength(data) >= 3
        else { return nil }
        let p = CFDataGetBytePtr(data)!
        return (Float(p[0]) / 255, Float(p[1]) / 255, Float(p[2]) / 255)
    }

    static func apply(_ image: NSImage, style: ArtworkStyle) -> NSImage {
        switch style {
        case .original, .flame, .thermalClick:
            return image
        case .noir:
            return filter(image) { let f = CIFilter.photoEffectNoir(); f.inputImage = $0; return f.outputImage }
        case .sepia:
            return filter(image) { let f = CIFilter.sepiaTone(); f.inputImage = $0; f.intensity = 1.0; return f.outputImage }
        case .pixel:
            return filter(image) { input in
                let f = CIFilter.pixellate()
                f.inputImage = input
                f.scale = Float(max(6, input.extent.width / 28))   // chunky regardless of cover size
                f.center = CGPoint(x: input.extent.midX, y: input.extent.midY)
                return f.outputImage
            }
        case .thermal:
            return filter(image) { let f = CIFilter.thermal(); f.inputImage = $0; return f.outputImage }
        }
    }

    /// Render `image` through a Core Image pipeline, cropping back to the
    /// original frame so effects that expand the extent stay the same size.
    private static func filter(_ image: NSImage, _ build: (CIImage) -> CIImage?) -> NSImage {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return image
        }
        let input = CIImage(cgImage: cgImage)
        guard let output = build(input)?.cropped(to: input.extent),
              let rendered = context.createCGImage(output, from: input.extent) else {
            return image
        }
        return NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
    }
}
