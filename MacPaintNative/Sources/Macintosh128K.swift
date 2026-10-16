import AppKit

/// An approximate native profile, not a 68000 or System emulator.
final class Macintosh128K {
    static let totalBytes = 131_072
    static let screenBytes = 21_888
    static let workingBufferBytes = 12_480
    static let stackBytes = 9_216
    // Provisional system/code/resource reservation; requires hardware calibration.
    static let systemAndProgramBytes = 50_432
    static let heapBytes = totalBytes - screenBytes - stackBytes - workingBufferBytes * 2 - systemAndProgramBytes
    private let preferences: UserDefaults
    var modsEnabled = false
    var enabled: Bool {
        get { preferences.bool(forKey: "macintosh128K.enabled") }
        set { preferences.set(newValue, forKey: "macintosh128K.enabled") }
    }
    var operationTiming: Bool {
        get { preferences.object(forKey: "macintosh128K.timing") as? Bool ?? true }
        set { preferences.set(newValue, forKey: "macintosh128K.timing") }
    }
    var mouseScaling: Bool {
        get { preferences.bool(forKey: "macintosh128K.mouse") }
        set { preferences.set(newValue, forKey: "macintosh128K.mouse") }
    }
    var active: Bool { modsEnabled && enabled }
    var timed: Bool { active && operationTiming }
    init(preferences: UserDefaults) { self.preferences = preferences }

    func delay(for command: String) -> TimeInterval {
        guard timed else { return 0 }
        switch command {
        case "save", "saveAs", "open": return 0.9
        case "scroll", "page": return 0.3
        case "paste", "bucket", "fill", "edges", "rotate", "horizontal", "vertical": return 0.4
        default: return 0
        }
    }
}

/// NSEvent positions already include modern acceleration. Apply this optional
/// approximation in logical pixels and warp the visible cursor to that point.
struct Macintosh128KMouse {
    private var anchor: PixelPoint?
    private var tick: Int?
    private var distance = 0
    mutating func reset() { anchor = nil; tick = nil; distance = 0 }
    mutating func move(to point: PixelPoint, timestamp: TimeInterval) -> PixelPoint {
        let currentTick = Int(timestamp * 60)
        if tick != currentTick { tick = currentTick; distance = 0 }
        guard let previous = anchor else { anchor = point; return point }
        let dx = point.x - previous.x, dy = point.y - previous.y
        distance += abs(dx) + abs(dy)
        let multiplier = distance > 6 ? 2 : 1
        let mapped = PixelPoint(x: max(80, min(495, previous.x + dx * multiplier)),
                                y: max(48, min(287, previous.y + dy * multiplier)))
        anchor = mapped
        return mapped
    }
}

final class Macintosh128KPanel: NSView {
    let profile: Macintosh128K
    let model: PaintModel
    let onChange: () -> Void
    weak var panel: NSPanel?
    private let memoryLabel = NSTextField(labelWithString: "")
    private var controls = [NSButton]()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(profile: Macintosh128K, model: PaintModel, scale: CGFloat, onChange: @escaping () -> Void) {
        self.profile = profile; self.model = model; self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 400 * scale, height: 264 * scale))
        func label(_ text: String, y: CGFloat, height: CGFloat = 18, bold: Bool = false) {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = bold ? .boldSystemFont(ofSize: 14) : .systemFont(ofSize: 12)
            field.frame = NSRect(x: 16, y: y, width: 368, height: height)
            addSubview(field)
        }
        label("Macintosh 128K", y: 14, bold: true)
        for (index, title) in ["Enable Macintosh 128K mode", "Operation and floppy delays", "Classic mouse acceleration (approximate)"].enumerated() {
            let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(change(_:)))
            checkbox.tag = index; checkbox.font = .systemFont(ofSize: 12)
            checkbox.frame = NSRect(x: 16, y: 44 + index * 26, width: 368, height: 22)
            controls.append(checkbox); addSubview(checkbox)
        }
        label("512 × 342 screen · 576 × 720 page · 1-bit pixels", y: 126)
        memoryLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        memoryLabel.frame = NSRect(x: 16, y: 149, width: 368, height: 18); addSubview(memoryLabel)
        label("Approximate heap and timing; not calibrated to hardware.\nMouse scaling uses input already processed by macOS.", y: 176, height: 36)
        let done = NSButton(title: "Done", target: self, action: #selector(closePanel))
        done.bezelStyle = .rounded; done.keyEquivalent = "\r"
        done.frame = NSRect(x: 298, y: 226, width: 86, height: 26); addSubview(done)
        // Match the integer scale of the classic workspace, including controls.
        bounds = NSRect(x: 0, y: 0, width: 400, height: 264)
        updateControls()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func updateControls() {
        controls[0].state = profile.enabled ? .on : .off
        controls[1].state = profile.operationTiming ? .on : .off
        controls[2].state = profile.mouseScaling ? .on : .off
        controls[1].isEnabled = profile.enabled; controls[2].isEnabled = profile.enabled
        memoryLabel.stringValue = "Virtual heap: \(max(0, Macintosh128K.heapBytes - model.virtualHeapUsed)) / \(Macintosh128K.heapBytes) bytes free"
    }
    @objc private func change(_ sender: NSButton) {
        switch sender.tag {
        case 0: profile.enabled = sender.state == .on
        case 1: profile.operationTiming = sender.state == .on
        default: profile.mouseScaling = sender.state == .on
        }
        onChange(); updateControls()
    }
    @objc private func closePanel() { NSApp.stopModal(); panel?.orderOut(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 36 { closePanel() }
        else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSColor.black.setStroke(); NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}
