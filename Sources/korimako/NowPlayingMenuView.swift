import AppKit

final class NowPlayingMenuView: NSView {

    // MARK: – Callbacks
    var onPrevious:  (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext:      (() -> Void)?
    var onArtTap: (() -> Void)?   // tapping current art → play/pause

    // MARK: – Geometry
    static let preferredWidth:        CGFloat = 280
    static let heightWithoutPrevious: CGFloat = 393
    static let heightWithPrevious:    CGFloat = 542

    // MARK: – Main section subviews
    private let artView         = FlickerImageView()
    private let artistMarquee   = MarqueeLabel()
    private let titleMarquee    = MarqueeLabel()
    private let prevButton      = NSButton()
    private let playPauseButton = NSButton()
    private let nextButton      = NSButton()
    private let timeLabel       = NSTextField(labelWithString: "–:–– / –:––")

    // MARK: – Previous track row subviews
    private let separatorLine      = NSBox()
    private let prevHeaderLabel    = NSTextField(labelWithString: "Previous Track")
    private let prevArtView        = NSImageView()
    private let prevArtistMarquee  = MarqueeLabel()
    private let prevTitleMarquee   = MarqueeLabel()

    // MARK: – Hover
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    // MARK: – Tap debounce
    private var lastArtTap: Date = .distantPast

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

        configureButton(prevButton,      symbol: "backward.fill", pointSize: 17)
        configureButton(playPauseButton, symbol: "play.fill",     pointSize: 17)
        configureButton(nextButton,      symbol: "forward.fill",  pointSize: 17)
        prevButton.target      = self; prevButton.action      = #selector(didTapPrev)
        playPauseButton.target = self; playPauseButton.action = #selector(didTapPlayPause)
        nextButton.target      = self; nextButton.action      = #selector(didTapNext)

        artView.onTap = { [weak self] in self?.didTapArt() }

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

        prevHeaderLabel.font                 = .systemFont(ofSize: NSFont.smallSystemFontSize)
        prevHeaderLabel.textColor            = .tertiaryLabelColor
        prevHeaderLabel.alignment            = .center
        prevHeaderLabel.maximumNumberOfLines = 1

        prevArtistMarquee.configure(
            font:  .systemFont(ofSize: NSFont.systemFontSize - 1),
            color: .secondaryLabelColor)
        prevTitleMarquee.configure(
            font:  .systemFont(ofSize: NSFont.smallSystemFontSize),
            color: .tertiaryLabelColor)

        for v in [artView, artistMarquee, titleMarquee,
                  prevButton, playPauseButton, nextButton,
                  timeLabel] as [NSView] {
            addSubview(v)
        }
        for v in [separatorLine, prevHeaderLabel, prevArtView,
                  prevArtistMarquee, prevTitleMarquee] as [NSView] {
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
        artView.frame = NSRect(x: (w - artSz) / 2, y: 12, width: artSz, height: artSz)

        artistMarquee.frame = NSRect(x: 16, y: 278, width: w - 32, height: 18)
        titleMarquee.frame  = NSRect(x: 16, y: 300, width: w - 32, height: 15)

        let btnSz: CGFloat = 36
        let gap: CGFloat   = (w - btnSz * 3) / 4
        prevButton.frame      = NSRect(x: gap,                 y: 323, width: btnSz, height: btnSz)
        playPauseButton.frame = NSRect(x: gap * 2 + btnSz,     y: 323, width: btnSz, height: btnSz)
        nextButton.frame      = NSRect(x: gap * 3 + btnSz * 2, y: 323, width: btnSz, height: btnSz)

        timeLabel.frame = NSRect(x: 16, y: 367, width: w - 32, height: 16)

        // Previous section
        separatorLine.frame   = NSRect(x: 0,  y: 393, width: w,      height: 1)
        prevHeaderLabel.frame = NSRect(x: 16, y: 401, width: w - 32, height: 14)

        let prevArtSz: CGFloat = 112
        let prevArtY:  CGFloat = 420
        prevArtView.frame = NSRect(x: 12, y: prevArtY, width: prevArtSz, height: prevArtSz)

        let prevTextX: CGFloat = 132   // 12 + 112 + 8
        let prevTextW          = w - prevTextX - 12
        let prevPairH: CGFloat = 17 + 4 + 15
        let prevPairY          = prevArtY + (prevArtSz - prevPairH) / 2
        prevArtistMarquee.frame = NSRect(x: prevTextX, y: prevPairY,      width: prevTextW, height: 17)
        prevTitleMarquee.frame  = NSRect(x: prevTextX, y: prevPairY + 21, width: prevTextW, height: 15)
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

        let ppSymbol = isPlaying ? "pause.fill" : "play.fill"
        let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        playPauseButton.image = NSImage(systemSymbolName: ppSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)

        timeLabel.stringValue = "\(formatTime(elapsed)) / \(formatTime(duration > 0 ? duration : 0))"

        let hasPrev = prevTitle != nil
        let targetH = hasPrev ? Self.heightWithPrevious : Self.heightWithoutPrevious
        if frame.height != targetH {
            frame.size.height = targetH
            needsLayout = true
        }
        for v in [separatorLine, prevHeaderLabel, prevArtView,
                  prevArtistMarquee, prevTitleMarquee] as [NSView] {
            v.isHidden = !hasPrev
        }
        if hasPrev {
            prevArtistMarquee.stringValue = artistString(prevArtist ?? "", year: prevYear)
            prevTitleMarquee.stringValue  = prevTitle!
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

    // MARK: – Actions
    @objc private func didTapPrev()      { onPrevious?() }
    @objc private func didTapNext()      { onNext?() }
    @objc private func didTapPlayPause() { onPlayPause?() }

    @objc private func didTapArt() {
        guard Date().timeIntervalSince(lastArtTap) >= 1.0 else { return }
        lastArtTap = Date()
        onArtTap?()
    }


    // MARK: – Hover highlight

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeAlways],
                                owner: self, userInfo: nil)
        trackingArea = ta
        addTrackingArea(ta)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}
