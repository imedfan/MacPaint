import AppKit

final class ClassicDialogView: NSView, NSWindowDelegate {
    let model: PaintModel
    let kind: String
    weak var panel: NSPanel? { didSet { panel?.delegate = self; panel?.makeFirstResponder(self) } }
    private var draftPattern: Pattern
    private var paintBlack = true
    private var lastPainted: PixelPoint?
    var logicalRect: PixelRect { model.resources.dialogs[kind == "pattern" ? 2003 : kind == "brush" ? 2004 : kind == "symmetry" ? 2005 : 2006]! }
    private var logicalSize: NSSize { NSSize(width: logicalRect.width, height: logicalRect.height) }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(model: PaintModel, kind: String) {
        self.model = model; self.kind = kind; draftPattern = model.pattern
        super.init(frame: NSRect(x: 0, y: 0, width: 576, height: 360))
        frame.size = NSSize(width: logicalSize.width * 2, height: logicalSize.height * 2)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let screen = renderDialog()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: screen.cgImage(), size: logicalSize).draw(in: bounds, from: .zero,
            operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
    func renderDialog() -> Bitmap {
        let font = model.resources.chicago
        var screen = Bitmap(width: Int(logicalSize.width), height: Int(logicalSize.height))
        func button(_ title: String, _ r: PixelRect) {
            screen.frame(r)
            font.draw(title, in: &screen, at: PixelPoint(x: r.x + (r.width - font.width(of: title)) / 2, y: r.y + 13))
        }
        switch kind {
        case "brush":
            for col in 0..<8 { for row in 0..<4 {
                let code = UInt8(120 + col * 4 + row)
                model.resources.paintFont.drawGlyph(code, in: &screen, at: PixelPoint(x: 24 + col * 32, y: 24 + row * 32))
                if model.brushIndex == col * 4 + row { screen.frame(PixelRect(x: 16 + col * 32, y: 16 + row * 32, width: 32, height: 32), width: 2) }
            } }
        case "pattern":
            for y in 0..<8 { for x in 0..<8 {
                screen.fill(PixelRect(x: 16 + x * 8, y: 16 + y * 8, width: 7, height: 7), pattern: draftPattern.pixel(x, y) ? .black : .white)
            } }
            screen.frame(PixelRect(x: 15, y: 15, width: 65, height: 65))
            screen.fill(PixelRect(x: 96, y: 16, width: 63, height: 63), pattern: draftPattern)
            screen.frame(PixelRect(x: 95, y: 15, width: 65, height: 65))
            button("OK", PixelRect(x: 16, y: 94, width: 64, height: 18))
            button("Cancel", PixelRect(x: 96, y: 94, width: 64, height: 18))
        case "symmetry":
            let r = PixelRect(x: 32, y: 16, width: 112, height: 112)
            screen.frame(r)
            let clip = PixelRect(x: 33, y: 17, width: 110, height: 110)
            screen.line(from: PixelPoint(x: 88, y: 16), to: PixelPoint(x: 88, y: 128), width: model.symmetryHorizontal ? 3 : 1, clip: clip)
            screen.line(from: PixelPoint(x: 32, y: 72), to: PixelPoint(x: 144, y: 72), width: model.symmetryVertical ? 3 : 1, clip: clip)
            screen.line(from: PixelPoint(x: 32, y: 16), to: PixelPoint(x: 144, y: 128), width: model.symmetryDiagonal ? 3 : 1, clip: clip)
            screen.line(from: PixelPoint(x: 32, y: 128), to: PixelPoint(x: 144, y: 16), width: model.symmetryOtherDiagonal ? 3 : 1, clip: clip)
            button("OK", PixelRect(x: 16, y: 144, width: 64, height: 16))
            button("None", PixelRect(x: 96, y: 144, width: 64, height: 16))
        default:
            font.draw("MacPaint version 1.3", in: &screen, at: PixelPoint(x: 6, y: 26))
            font.draw("written by Bill Atkinson", in: &screen, at: PixelPoint(x: 6, y: 50))
            font.draw("Copyright 1983, Apple Computer Inc.", in: &screen, at: PixelPoint(x: 6, y: 74))
            font.draw("Native ARM64 adaptation", in: &screen, at: PixelPoint(x: 6, y: 104))
            button("OK", PixelRect(x: 274, y: 56, width: 71, height: 20))
        }
        screen.frame(screen.bounds)
        return screen
    }
    private func close(accept: Bool) {
        if accept && kind == "pattern" { model.patterns[model.patternIndex] = draftPattern }
        NSApp.stopModal(); panel?.orderOut(nil)
    }
    func samplePattern(from workspace: WorkspaceView, event: NSEvent) -> Bool {
        guard kind == "pattern", let panel, NSApp.modalWindow === panel, let sourceWindow = workspace.window,
              event.window === sourceWindow else { return false }
        let global = sourceWindow.convertPoint(toScreen: event.locationInWindow)
        let point = workspace.screenPoint(event)
        guard workspace.documentOpen, !panel.frame.contains(global),
              PixelRect(x: 80, y: 48, width: 416, height: 240).contains(point) else { return false }
        // EditPat rounds document-port coordinates, then GetPixel reads the
        // displayed pixels, including FatBits, rather than the page buffer.
        let origin = model.origin
        let left = ((point.x - 80 + origin.x + 4) & ~7) - origin.x + 80
        let top = ((point.y - 48 + origin.y + 4) & ~7) - origin.y + 48
        let image = workspace.renderWorkspace(), dialog = renderDialog()
        var rows = Array(repeating: UInt8(0), count: 8)
        for y in 0..<8 { for x in 0..<8 {
            let local = workspace.viewPoint(PixelPoint(x: left + x, y: top + y))
            let globalPixel = sourceWindow.convertPoint(toScreen: workspace.convert(local, to: nil))
            let black: Bool
            if panel.frame.contains(globalPixel) {
                let p = convert(panel.convertPoint(fromScreen: globalPixel), from: nil)
                black = dialog[Int(p.x * logicalSize.width / bounds.width), Int(p.y * logicalSize.height / bounds.height)]
            } else { black = image[left + x, top + y] }
            if black { rows[y] |= 0x80 >> x }
        } }
        draftPattern = Pattern(rows); lastPainted = nil; needsDisplay = true
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { close(accept: false); return true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close(accept: false) }
        else if event.keyCode == 36 { close(accept: true) }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let x = Int(point.x * logicalSize.width / bounds.width), y = Int(point.y * logicalSize.height / bounds.height)
        if kind == "about", (274..<345).contains(x), (56..<76).contains(y) { close(accept: true) }
        else if kind == "pattern", (94..<112).contains(y) {
            if (16..<80).contains(x) { close(accept: true) }
            if (96..<160).contains(x) { close(accept: false) }
        } else if kind == "symmetry", (144..<160).contains(y) {
            if (96..<160).contains(x) {
                model.symmetryHorizontal = false; model.symmetryVertical = false
                model.symmetryDiagonal = false; model.symmetryOtherDiagonal = false
            }
            close(accept: true)
        } else if kind == "brush", (16..<272).contains(x), (16..<144).contains(y) {
            model.brushIndex = (x - 16) / 32 * 4 + (y - 16) / 32; close(accept: true)
        } else if kind == "pattern", (16..<80).contains(x), (16..<80).contains(y) {
            let column = (x - 16) / 8, row = (y - 16) / 8
            paintBlack = !draftPattern.pixel(column, row); lastPainted = nil
            plotPattern(x: column, y: row)
        } else if kind == "symmetry", (32..<144).contains(x), (16..<128).contains(y) {
            let dx = x - 88, dy = y - 72
            if abs(dx) > 2 * abs(dy) { model.symmetryVertical.toggle() }
            else if abs(dy) > 2 * abs(dx) { model.symmetryHorizontal.toggle() }
            else if (dx < 0) == (dy < 0) { model.symmetryDiagonal.toggle() }
            else { model.symmetryOtherDiagonal.toggle() }
        }
        needsDisplay = true
    }
    private func plotPattern(x: Int, y: Int) {
        let p = PixelPoint(x: x, y: y)
        guard lastPainted != p else { return }
        if paintBlack { draftPattern.rows[y] |= 0x80 >> x } else { draftPattern.rows[y] &= ~(0x80 >> x) }
        lastPainted = p
    }
    override func mouseDragged(with event: NSEvent) {
        guard kind == "pattern", lastPainted != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        let x = max(0, min(7, (Int(p.x * logicalSize.width / bounds.width) - 16) / 8))
        let y = max(0, min(7, (Int(p.y * logicalSize.height / bounds.height) - 16) / 8))
        plotPattern(x: x, y: y); needsDisplay = true
    }
}

final class ClassicPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
