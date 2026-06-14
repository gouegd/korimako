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
