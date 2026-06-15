import AppKit

/// A single-line label that scrolls horizontally when its text is wider than the view.
///
/// Uses a CATextLayer rather than an NSTextField: a layer-backed NSTextField inside a
/// masksToBounds superview has its backing store optimised down to the visible region,
/// so scrolling it merely slides an already-clipped bitmap and reveals blank space.
/// A CATextLayer always rasterises its full string into its own backing, so translating
/// it actually exposes the hidden text. Scrolling is driven by a keyframe animation on
/// the host layer's sublayerTransform (AppKit does not manage sublayerTransform, so the
/// layout system cannot reset it mid-animation).
final class MarqueeLabel: NSView {

    // MARK: – Public

    var stringValue: String {
        get { text }
        set {
            guard newValue != text else { return }
            text = newValue
            textLayer.string = newValue
            resetScroll()
        }
    }

    func configure(font: NSFont, color: NSColor) {
        self.font = font
        textLayer.font     = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = color.cgColor
        resetScroll()
    }

    // MARK: – Private

    private var text = ""
    private var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    private let textLayer = CATextLayer()
    private var lastLayoutWidth: CGFloat = 0

    // Not flipped: with a manually positioned sublayer we use the layer's native
    // (y-up) coordinate space and centre the text vertically ourselves.

    // MARK: – Init

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        textLayer.truncationMode = .none
        textLayer.isWrapped      = false
        textLayer.alignmentMode  = .left
        textLayer.contentsScale  = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(textLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: – Layout

    override func layout() {
        super.layout()
        let w = bounds.width
        guard w > 0 else { return }

        let nw         = naturalWidth()
        let animActive = layer?.animation(forKey: "marquee") != nil

        guard w != lastLayoutWidth || (nw > w && !animActive) else { return }
        lastLayoutWidth = w
        resetScroll()
    }

    private func naturalWidth() -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil((text as NSString)
            .size(withAttributes: [.font: font]).width) + 2
    }

    // MARK: – Scroll (Core Animation on sublayerTransform)

    private func resetScroll() {
        let w = bounds.width > 0 ? bounds.width : lastLayoutWidth
        guard w > 0 else { needsLayout = true; return }

        let nw = naturalWidth()
        let h  = bounds.height > 0 ? bounds.height : frame.height
        let lh = ceil(font.ascender - font.descender)
        let y  = ((h - lh) / 2).rounded()

        // Geometry reset must not itself animate.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.removeAnimation(forKey: "marquee")
        layer?.sublayerTransform = CATransform3DIdentity
        if nw <= w {
            textLayer.frame = NSRect(x: (w - nw) / 2, y: y, width: max(nw, 1), height: lh)
        } else {
            textLayer.frame = NSRect(x: 0, y: y, width: nw + 4, height: lh)
        }
        CATransaction.commit()

        if nw > w { animateScroll(overflow: nw - w + 8) }
    }

    private func animateScroll(overflow: CGFloat) {
        guard let lyr = layer else { needsLayout = true; return }

        let scrollDuration = Double(overflow) / 30.0
        let total          = 1.5 + scrollDuration + 1.0 + 0.02

        let t1 = NSNumber(value: 1.5 / total)
        let t2 = NSNumber(value: (1.5 + scrollDuration) / total)
        let t3 = NSNumber(value: (total - 0.02) / total)

        let anim             = CAKeyframeAnimation(keyPath: "sublayerTransform.translation.x")
        anim.values          = [0.0, 0.0, -overflow, -overflow, 0.0]
        anim.keyTimes        = [0,   t1,   t2,        t3,        1  ]
        anim.duration        = total
        anim.repeatCount     = .infinity
        anim.calculationMode = .linear
        anim.isRemovedOnCompletion = false
        lyr.add(anim, forKey: "marquee")
    }
}
