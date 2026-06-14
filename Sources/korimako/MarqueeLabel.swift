import AppKit

/// A single-line label that scrolls horizontally when its text is wider than the view.
/// When text fits, it is horizontally centered. When it overflows, it pauses, scrolls
/// to the end, pauses again, then resets — matching macOS Now Playing widget behaviour.
final class MarqueeLabel: NSView {

    // MARK: – Public

    var stringValue: String {
        get { label.stringValue }
        set { label.stringValue = newValue; resetAndRelayout() }
    }

    func configure(font: NSFont, color: NSColor) {
        label.font      = font
        label.textColor = color
    }

    // MARK: – Private

    private let label = NSTextField(labelWithString: "")

    private var scrollTimer: Timer?
    private var scrollOffset: CGFloat = 0
    private var phase: Phase = .pauseAtStart(tick: 0)

    private enum Phase {
        case pauseAtStart(tick: Int)
        case scrolling
        case pauseAtEnd(tick: Int)
    }

    private let pauseTicksStart: Int  = 30    // 1.5 s at 20 Hz
    private let pauseTicksEnd:   Int  = 20    // 1.0 s at 20 Hz
    private let pxPerTick: CGFloat    = 1.5   // ≈ 30 px/s at 20 Hz

    override var isFlipped: Bool { true }

    // MARK: – Init

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds  = true
        label.lineBreakMode        = .byClipping
        label.maximumNumberOfLines = 1
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: – Layout

    override func layout() {
        super.layout()
        placeLabel()
        let overflows = naturalWidth() > bounds.width
        if overflows, scrollTimer == nil { startTimer() }
        else if !overflows { stopTimer(); scrollOffset = 0; placeLabel() }
    }

    private func naturalWidth() -> CGFloat {
        guard let font = label.font, !label.stringValue.isEmpty else { return 0 }
        return ceil((label.stringValue as NSString)
            .size(withAttributes: [.font: font]).width) + 2
    }

    private func placeLabel() {
        let h  = bounds.height
        let w  = bounds.width
        let nw = naturalWidth()
        if nw <= w {
            label.frame = NSRect(x: (w - nw) / 2, y: 0, width: nw, height: h)
        } else {
            label.frame = NSRect(x: -scrollOffset, y: 0, width: nw + 8, height: h)
        }
    }

    // MARK: – Timer

    private func startTimer() {
        scrollOffset = 0
        phase = .pauseAtStart(tick: 0)
        let t = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        scrollTimer = t
    }

    private func stopTimer() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    private func resetAndRelayout() {
        stopTimer()
        scrollOffset = 0
        phase = .pauseAtStart(tick: 0)
        needsLayout = true
    }

    private func tick() {
        guard !isHidden, window != nil else { return }
        let overflow = naturalWidth() - bounds.width + 8

        switch phase {
        case .pauseAtStart(let n):
            phase = n + 1 >= pauseTicksStart ? .scrolling : .pauseAtStart(tick: n + 1)

        case .scrolling:
            scrollOffset = min(scrollOffset + pxPerTick, overflow)
            placeLabel()
            if scrollOffset >= overflow { phase = .pauseAtEnd(tick: 0) }

        case .pauseAtEnd(let n):
            if n + 1 >= pauseTicksEnd {
                scrollOffset = 0
                phase = .pauseAtStart(tick: 0)
                placeLabel()
            } else {
                phase = .pauseAtEnd(tick: n + 1)
            }
        }
    }
}
