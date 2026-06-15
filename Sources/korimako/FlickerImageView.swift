import AppKit

/// NSImageView that can switch between `baseImage` and `flickerImage` in two modes:
///   .flame    — hover triggers candle-rhythm animation
///   .onClick  — pressing shows flickerImage, releasing restores baseImage
final class FlickerImageView: NSImageView {

    enum FlickerMode { case none, flame, onClick }

    /// Called on mouse-up (regardless of flickerMode). Use instead of a separate NSClickGestureRecognizer.
    var onTap: (() -> Void)?

    /// Called whenever the mouse enters or exits this view's bounds.
    var onHoverChanged: ((Bool) -> Void)?

    var flickerMode: FlickerMode = .none {
        didSet {
            guard flickerMode != oldValue else { return }
            if flickerMode != .flame { stopFlicker() }
        }
    }

    /// The image shown at rest.
    var baseImage: NSImage? {
        didSet { if !showingFlicker { image = baseImage } }
    }

    /// The alternate image. Setting to nil stops any active effect.
    var flickerImage: NSImage? {
        didSet { if flickerImage == nil { stopFlicker() } }
    }

    private var showingFlicker   = false
    private var flickerTimer:    Timer?
    private var pressDownPoint   = NSPoint.zero
    private var ticks    = 0
    private var switchAt = 0
    private var trackingArea: NSTrackingArea?

    // MARK: – Init

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        // Non-blocking press detection for .onClick mode.
        // NSPressGestureRecognizer fires .began on mouseDown and .ended on mouseUp
        // without blocking the run loop, so the display update happens on the next
        // vsync after .began — unlike trackEvents which gates compositing behind events.
        let press = NSPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        addGestureRecognizer(press)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: – Press handling (.onClick mode)

    @objc private func handlePress(_ gr: NSPressGestureRecognizer) {
        switch gr.state {
        case .began:
            pressDownPoint = gr.location(in: self)
            if flickerMode == .onClick, flickerImage != nil {
                showingFlicker = true
                image = flickerImage
            }
        case .ended:
            if flickerMode == .onClick {
                showingFlicker = false
                image = baseImage
            }
            let d = gr.location(in: self)
            let dx = d.x - pressDownPoint.x, dy = d.y - pressDownPoint.y
            if (dx*dx + dy*dy).squareRoot() <= 4 { onTap?() }
        case .cancelled, .failed:
            if flickerMode == .onClick {
                showingFlicker = false
                image = baseImage
            }
        default: break
        }
    }

    // MARK: – Hover tracking (.flame mode)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeAlways],
                                owner: self, userInfo: nil)
        trackingArea = ta
        addTrackingArea(ta)
    }

    override func mouseEntered(with event: NSEvent) {
        if flickerMode == .flame { startFlicker() }
        onHoverChanged?(true)
    }
    override func mouseExited(with event: NSEvent) {
        if flickerMode == .flame { stopFlicker() }
        onHoverChanged?(false)
    }

    // MARK: – Flame flicker

    private func startFlicker() {
        guard flickerImage != nil, flickerTimer == nil else { return }
        ticks = 0
        showingFlicker = false
        scheduleNextSwitch()
        let t = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        flickerTimer = t
    }

    private func stopFlicker() {
        flickerTimer?.invalidate()
        flickerTimer = nil
        showingFlicker = false
        image = baseImage
    }

    private func tick() {
        ticks += 1
        guard ticks >= switchAt else { return }
        showingFlicker.toggle()
        image = showingFlicker ? flickerImage : baseImage
        ticks = 0
        scheduleNextSwitch()
    }

    private func scheduleNextSwitch() {
        // Candle rhythm at 20 Hz:
        //   thermal flash  →  50–200 ms  (1–4 ticks)
        //   calm original  → 400–1250 ms (8–25 ticks)
        switchAt = showingFlicker ? Int.random(in: 1...4) : Int.random(in: 8...25)
    }
}
