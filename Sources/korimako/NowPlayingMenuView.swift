import AppKit

final class NowPlayingMenuView: NSView {

    // MARK: – Callbacks
    var onPrevious: (() -> Void)?
    var onNext:     (() -> Void)?
    var onArtTap:   (() -> Void)?

    // MARK: – Geometry
    static let preferredWidth:        CGFloat = 280
    static let heightWithoutPrevious: CGFloat = 345
    static let heightWithPrevious:    CGFloat = 482

    // MARK: – Main section subviews
    private let artView           = FlickerImageView()
    private let pauseRevealOverlay = PassthroughView()  // thermal art through pause-symbol mask
    private let artOverlayView    = PassthroughView()  // border overlay above artView
    private let textAreaOverlay   = TapView()          // click catcher for text area
    private let artistMarquee   = MarqueeLabel()
    private let titleMarquee    = MarqueeLabel()
    private let prevButton      = NSButton()
    private let nextButton      = NSButton()
    private let timeLabel       = NSTextField(labelWithString: "–:–– / –:––")

    // MARK: – Previous track row subviews
    private let separatorLine      = NSBox()
    private let prevHeaderLabel    = NSTextField(labelWithString: "Previous Track")
    private let prevArtView        = NSImageView()
    private let prevArtistLabel    = NSTextField(labelWithString: "")
    private let prevTitleLabel     = NSTextField(labelWithString: "")

    // MARK: – State
    private var lastArtTap:    Date = .distantPast
    private var isPlaying    = false
    private var isHovering   = false
    private var revealMask:    CAShapeLayer?

    // MARK: – Init

    init() {
        super.init(frame: NSRect(x: 0, y: 0,
                                 width:  Self.preferredWidth,
                                 height: Self.heightWithoutPrevious))
        wantsLayer = true
        setupSubviews()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    // MARK: – Setup

    private func setupSubviews() {
        configureImageView(artView,     cornerRadius: 8)
        configureImageView(prevArtView, cornerRadius: 5)

        // Thermal pause-symbol reveal: shown on hover while playing.
        pauseRevealOverlay.wantsLayer           = true
        pauseRevealOverlay.layer?.cornerRadius  = 8
        pauseRevealOverlay.layer?.masksToBounds = true
        pauseRevealOverlay.isHidden             = true
        let maskLayer = CAShapeLayer()
        revealMask = maskLayer
        pauseRevealOverlay.layer?.mask = maskLayer

        artView.onHoverChanged = { [weak self] hovering in
            self?.isHovering = hovering
            self?.updatePauseOverlay()
        }
        textAreaOverlay.onHoverChanged = { [weak self] hovering in
            self?.isHovering = hovering
            self?.updatePauseOverlay()
        }

        // Hairline border overlay: must live in its own view above artView because
        // NSImageView renders its image via a private sublayer that sits on top of
        // anything added to artView.layer directly.
        artOverlayView.wantsLayer            = true
        artOverlayView.layer?.cornerRadius   = 8
        artOverlayView.layer?.masksToBounds  = true
        artOverlayView.layer?.borderWidth    = 1
        updateBorderColor()

        configureButton(prevButton, symbol: "backward.fill", pointSize: 15)
        configureButton(nextButton, symbol: "forward.fill",  pointSize: 15)
        prevButton.target = self; prevButton.action = #selector(didTapPrev)
        nextButton.target = self; nextButton.action = #selector(didTapNext)

        artView.onTap           = { [weak self] in self?.didTapArt() }
        textAreaOverlay.onTap   = { [weak self] in self?.onArtTap?() }

        artistMarquee.configure(
            font:  .boldSystemFont(ofSize: NSFont.systemFontSize),
            color: .labelColor)
        titleMarquee.configure(
            font:  .systemFont(ofSize: NSFont.smallSystemFontSize),
            color: .secondaryLabelColor)

        timeLabel.font                 = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
        timeLabel.textColor            = .tertiaryLabelColor
        timeLabel.alignment            = .center
        timeLabel.maximumNumberOfLines = 1

        separatorLine.boxType = .separator

        let baseFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        prevHeaderLabel.stringValue          = "(previously)"
        prevHeaderLabel.font                 = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        prevHeaderLabel.textColor            = .tertiaryLabelColor
        prevHeaderLabel.alignment            = .center
        prevHeaderLabel.maximumNumberOfLines = 1

        prevArtistLabel.font                 = .systemFont(ofSize: NSFont.systemFontSize - 1)
        prevArtistLabel.textColor            = .secondaryLabelColor
        prevArtistLabel.alignment            = .center
        prevArtistLabel.lineBreakMode        = .byTruncatingTail
        prevArtistLabel.maximumNumberOfLines = 1

        prevTitleLabel.font                  = .systemFont(ofSize: NSFont.smallSystemFontSize)
        prevTitleLabel.textColor             = .tertiaryLabelColor
        prevTitleLabel.alignment             = .center
        prevTitleLabel.lineBreakMode         = .byTruncatingTail
        prevTitleLabel.maximumNumberOfLines  = 1

        for v in [artView, pauseRevealOverlay, artOverlayView, artistMarquee, titleMarquee,
                  timeLabel, textAreaOverlay, prevButton, nextButton] as [NSView] {
            addSubview(v)
        }
        for v in [separatorLine, prevHeaderLabel, prevArtView,
                  prevArtistLabel, prevTitleLabel] as [NSView] {
            v.isHidden = true
            addSubview(v)
        }

        layoutAll()
    }

    private func configureImageView(_ iv: NSImageView, cornerRadius: CGFloat) {
        iv.imageScaling          = .scaleAxesIndependently
        iv.wantsLayer            = true
        iv.layer?.cornerRadius   = cornerRadius
        iv.layer?.masksToBounds  = true
    }

    private func configureButton(_ btn: NSButton, symbol: String, pointSize: CGFloat) {
        btn.title        = ""
        btn.bezelStyle   = .regularSquare
        btn.isBordered   = false
        btn.imageScaling = .scaleNone
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
    }

    // MARK: – Layout

    override func layout() {
        super.layout()
        layoutAll()
    }

    private func layoutAll() {
        let w = bounds.width > 0 ? bounds.width : Self.preferredWidth

        // artSz = 256 → (280−256)/2 = 12px margin, matching prevArtView's x=12
        let artSz: CGFloat = 256
        let artFrame = NSRect(x: (w - artSz) / 2, y: 8, width: artSz, height: artSz)
        artView.frame              = artFrame
        pauseRevealOverlay.frame   = artFrame
        artOverlayView.frame       = artFrame

        // Prev/next buttons flank the text block, flush with art edges (x=12 / x=268)
        let artX:  CGFloat = (w - 256) / 2   // = 12 at w=280
        let btnW:  CGFloat = 22
        let nudge: CGFloat = 4
        let textX          = artX + btnW + nudge
        let textW          = 256 - 2 * (btnW + nudge)

        // Text block: artist (18) + gap (4) + title (15) + gap (4) + time (16) = 57
        prevButton.frame = NSRect(x: artX,              y: 274, width: btnW, height: 57)
        nextButton.frame = NSRect(x: artX + 256 - btnW, y: 274, width: btnW, height: 57)

        artistMarquee.frame = NSRect(x: textX, y: 274, width: textW, height: 18)
        titleMarquee.frame  = NSRect(x: textX, y: 296, width: textW, height: 15)
        timeLabel.frame     = NSRect(x: textX, y: 315, width: textW, height: 16)

        // Transparent overlay for text area clicks (plays/pauses)
        textAreaOverlay.frame = NSRect(x: textX, y: 274, width: textW, height: 57)

        // Previous section
        separatorLine.frame = NSRect(x: 0, y: 345, width: w, height: 1)

        let prevArtSz: CGFloat = 112
        let prevArtY:  CGFloat = 364
        prevArtView.frame = NSRect(x: 12, y: prevArtY, width: prevArtSz, height: prevArtSz)

        let prevTextX: CGFloat = 132   // 12 + 112 + 8
        let prevTextW          = w - prevTextX - 12

        // Text block: "Just played:" + gap + artist + title, vertically centred in art
        let justPlayedH: CGFloat = 13
        let labelGap:    CGFloat = justPlayedH               // one full line gap
        let artistH:     CGFloat = 17
        let titleH:      CGFloat = 14
        let blockH = artistH + 3 + titleH + labelGap + justPlayedH
        let blockY = prevArtY + floor((prevArtSz - blockH) / 2)
        prevArtistLabel.frame  = NSRect(x: prevTextX, y: blockY,                                        width: prevTextW, height: artistH)
        prevTitleLabel.frame   = NSRect(x: prevTextX, y: blockY + artistH + 3,                          width: prevTextW, height: titleH)
        prevHeaderLabel.frame  = NSRect(x: prevTextX, y: blockY + artistH + 3 + titleH + labelGap,      width: prevTextW, height: justPlayedH)
    }

    // MARK: – Update

    func update(title: String, artist: String, year: Int?, artwork: NSImage?,
                flickerArtwork: NSImage?, flickerMode: FlickerImageView.FlickerMode,
                isPlaying: Bool, elapsed: TimeInterval, duration: TimeInterval,
                prevTitle: String?, prevArtist: String?, prevYear: Int?, prevArtwork: NSImage?) {
        artistMarquee.stringValue = artistString(artist, year: year)
        titleMarquee.stringValue  = title.isEmpty ? "Nothing playing" : title
        artView.flickerMode  = flickerMode
        artView.baseImage    = artwork
        artView.flickerImage = flickerArtwork

        self.isPlaying = isPlaying
        pauseRevealOverlay.layer?.contents = flickerArtwork.flatMap {
            $0.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        updatePauseOverlay()

        timeLabel.stringValue = "\(formatTime(elapsed)) / \(formatTime(duration > 0 ? duration : 0))"

        let hasPrev = prevTitle != nil
        let targetH = hasPrev ? Self.heightWithPrevious : Self.heightWithoutPrevious
        if frame.height != targetH {
            frame.size.height = targetH
            needsLayout = true
        }
        for v in [separatorLine, prevHeaderLabel, prevArtView,
                  prevArtistLabel, prevTitleLabel] as [NSView] {
            v.isHidden = !hasPrev
        }
        if hasPrev {
            prevArtistLabel.stringValue = artistString(prevArtist ?? "", year: prevYear)
            prevTitleLabel.stringValue  = prevTitle!
            prevArtView.image = prevArtwork
        }
    }

    private func artistString(_ artist: String, year: Int?) -> String {
        guard let y = year else { return artist }
        return "\(artist) (\(y))"
    }

    private func formatTime(_ s: TimeInterval) -> String {
        let t = max(0, Int(s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    // MARK: – Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColor()
    }

    private func updateBorderColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.artOverlayView.layer?.borderColor = NSColor(white: 1, alpha: 0.15).cgColor
        }
    }

    // MARK: – Pause reveal overlay

    private func updatePauseOverlay() {
        guard isHovering, let mask = revealMask else {
            pauseRevealOverlay.isHidden = true
            return
        }
        let artRect = CGRect(origin: .zero, size: CGSize(width: 256, height: 256))
        mask.path = isPlaying ? pauseBarPath(in: artRect) : playTrianglePath(in: artRect)
        pauseRevealOverlay.isHidden = false
    }

    private func pauseBarPath(in rect: CGRect) -> CGPath {
        let path    = CGMutablePath()
        let symbolH = rect.height * 0.5
        let barW    = symbolH * 0.22
        let gap     = barW * 0.8
        let totalW  = barW * 2 + gap
        let ox      = (rect.width  - totalW) / 2
        let oy      = (rect.height - symbolH) / 2
        let r       = barW * 0.3
        path.addRoundedRect(in: CGRect(x: ox,              y: oy, width: barW, height: symbolH), cornerWidth: r, cornerHeight: r)
        path.addRoundedRect(in: CGRect(x: ox + barW + gap, y: oy, width: barW, height: symbolH), cornerWidth: r, cornerHeight: r)
        return path
    }

    private func playTrianglePath(in rect: CGRect) -> CGPath {
        let path    = CGMutablePath()
        let symbolH = rect.height * 0.5
        let symbolW = symbolH * 0.85
        let ox      = rect.width  / 2 - symbolW / 3   // centroid-aligned, not bbox-centered
        let oy      = (rect.height - symbolH) / 2
        let r: CGFloat = 10
        // Rounded right-pointing triangle: top-left → right-tip → bottom-left
        path.move(to: CGPoint(x: ox, y: oy + r))
        path.addArc(tangent1End: CGPoint(x: ox,           y: oy),
                    tangent2End: CGPoint(x: ox + symbolW, y: oy + symbolH / 2), radius: r)
        path.addArc(tangent1End: CGPoint(x: ox + symbolW, y: oy + symbolH / 2),
                    tangent2End: CGPoint(x: ox,            y: oy + symbolH),    radius: r)
        path.addArc(tangent1End: CGPoint(x: ox,           y: oy + symbolH),
                    tangent2End: CGPoint(x: ox,            y: oy),              radius: r)
        path.closeSubpath()
        return path
    }

    // MARK: – Actions
    @objc private func didTapPrev() { onPrevious?() }
    @objc private func didTapNext() { onNext?() }

    @objc private func didTapArt() {
        guard Date().timeIntervalSince(lastArtTap) >= 1.0 else { return }
        lastArtTap = Date()
        onArtTap?()
    }

}

// Transparent to hit-testing so mouse events fall through to siblings below.
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// Simple press-to-tap view using NSPressGestureRecognizer (works inside NSMenu's event loop).
private final class TapView: NSView {
    var onTap: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    private var pressDownPoint = NSPoint.zero
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let press = NSPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        addGestureRecognizer(press)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeAlways],
                                owner: self, userInfo: nil)
        trackingArea = ta
        addTrackingArea(ta)
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent)  { onHoverChanged?(false) }

    @objc private func handlePress(_ gr: NSPressGestureRecognizer) {
        switch gr.state {
        case .began:
            pressDownPoint = gr.location(in: self)
        case .ended:
            let d = gr.location(in: self)
            let dx = d.x - pressDownPoint.x, dy = d.y - pressDownPoint.y
            if (dx*dx + dy*dy).squareRoot() <= 4 { onTap?() }
        default: break
        }
    }
}
