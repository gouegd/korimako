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
    /// Uses thermal for clean/simple artwork; falls back to dark sepia for busy
    /// artwork where thermal blends into the visual noise.
    static func revealImage(for original: NSImage, displayedAs displayedArt: NSImage) -> NSImage {
        let score = busynessScore(original)
        Log.debug("art busyness score: \(String(format: "%.3f", score))")
        return score <= 0.17
            ? apply(original, style: .thermal)
            : filter(original) { input in
                let sepia = CIFilter.sepiaTone()
                sepia.inputImage = input
                sepia.intensity = 1.0
                guard let sepiaOut = sepia.outputImage else { return nil }
                let exp = CIFilter.exposureAdjust()
                exp.inputImage = sepiaOut
                exp.ev = -1.5   // ~35% brightness; dark mask is clearly readable on busy/bright art
                return exp.outputImage
            }
    }

    /// Mean edge intensity in the center 60% of the image (0–1).
    /// High values = busy/complex artwork with many competing edges.
    /// Low values = clean/simple artwork where thermal reads clearly.
    private static func busynessScore(_ image: NSImage) -> Float {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return 0 }
        let ci = CIImage(cgImage: cg)
        let center = ci.extent.insetBy(dx: ci.extent.width * 0.2, dy: ci.extent.height * 0.2)
        let cropped = ci.cropped(to: center)
        guard let edgeImg = CIFilter(name: "CIEdges",
                                     parameters: [kCIInputImageKey: cropped,
                                                  "inputIntensity": 1.0 as AnyObject])?.outputImage
        else { return 0 }
        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return 0 }
        avgFilter.setValue(edgeImg, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: center), forKey: "inputExtent")
        guard let avgImg = avgFilter.outputImage,
              let cgAvg  = context.createCGImage(avgImg, from: CGRect(x: 0, y: 0, width: 1, height: 1)),
              let data    = cgAvg.dataProvider?.data,
              CFDataGetLength(data) >= 3
        else { return 0 }
        let p = CFDataGetBytePtr(data)!
        return (Float(p[0]) + Float(p[1]) + Float(p[2])) / (255 * 3)
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
