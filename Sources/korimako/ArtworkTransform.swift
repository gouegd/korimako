import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Album-art styles selectable from the menu bar. Each maps to a Core Image
/// effect applied after download, before the art reaches the system Now Playing
/// UI. Hook point: `NowPlayingController.applyArtwork`.
enum ArtworkStyle: String, CaseIterable {
    case original, cartoon, comic, poster, ink, noir, sepia, pixel, thermal, edges

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .cartoon:  return "Cartoon"
        case .comic:    return "Comic"
        case .poster:   return "Poster"
        case .ink:      return "Ink Sketch"
        case .noir:     return "Noir"
        case .sepia:    return "Sepia"
        case .pixel:    return "Pixel"
        case .thermal:  return "Thermal"
        case .edges:    return "Neon Edges"
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
        case .original:
            return image
        case .cartoon:
            // Cel-shaded toon: strongly flattened colour fills + bold inked outlines.
            return filter(image) { input in
                // Fills: blur to merge detail into regions, punch colour, hard-band it.
                let blur = CIFilter.gaussianBlur()
                blur.inputImage = input.clampedToExtent()
                blur.radius = 4
                let controls = CIFilter.colorControls()
                controls.inputImage = blur.outputImage
                controls.saturation = 1.45
                controls.contrast = 1.05
                let poster = CIFilter.colorPosterize()
                poster.inputImage = controls.outputImage
                poster.levels = 4
                // Outlines: pre-blur (kill texture) -> edges -> greyscale -> threshold
                // to solid lines -> thicken -> invert to bold black-on-white.
                let edgeBlur = CIFilter.gaussianBlur(); edgeBlur.inputImage = input.clampedToExtent(); edgeBlur.radius = 1.5
                let edges = CIFilter.edges(); edges.inputImage = edgeBlur.outputImage; edges.intensity = 4.0
                let mono = CIFilter.colorControls(); mono.inputImage = edges.outputImage; mono.saturation = 0
                let thresh = CIFilter.colorThreshold(); thresh.inputImage = mono.outputImage; thresh.threshold = 0.22
                let thick = CIFilter.morphologyMaximum(); thick.inputImage = thresh.outputImage; thick.radius = 1.5
                let ink = CIFilter.colorInvert(); ink.inputImage = thick.outputImage
                // Multiply bold black lines over the flat colour base.
                let combine = CIFilter.multiplyBlendMode()
                combine.backgroundImage = poster.outputImage
                combine.inputImage = ink.outputImage
                return combine.outputImage
            }
        case .comic:
            return filter(image) { let f = CIFilter.comicEffect(); f.inputImage = $0; return f.outputImage }
        case .poster:
            return filter(image) { let f = CIFilter.colorPosterize(); f.inputImage = $0; f.levels = 6; return f.outputImage }
        case .ink:
            return filter(image) { let f = CIFilter.lineOverlay(); f.inputImage = $0; return f.outputImage }
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
        case .edges:
            return filter(image) { let f = CIFilter.edges(); f.inputImage = $0; f.intensity = 1.0; return f.outputImage }
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
