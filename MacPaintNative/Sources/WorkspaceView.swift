import AppKit

struct ClassicMenuItem {
    var title: String
    var command: String
    var shortcut: String = ""
    var checked = false
    var enabled = true
    var isSeparator: Bool { title == "-" }
}

struct ClassicMenu {
    var title: String
    var items: [ClassicMenuItem]
}

final class WorkspaceView: NSView {
    let model: PaintModel
    weak var controller: AppController?
    var menus = [ClassicMenu]()
    var documentTitle = "Untitled"
    var documentOpen = true
    var helpID: Int?
    var pageOverview: Bool {
        get { overview != nil }
        set {
            if newValue && overview == nil {
                overview = model.beginPageOverview(); popup = nil; helpID = nil; handStart = nil
            } else if !newValue { overview = nil; pageButton = nil }
        }
    }
    private var overview: PageOverview?
    private enum PageButton: String, CaseIterable {
        case ok = "OK", cancel = "Cancel"
        var rect: PixelRect { PixelRect(x: 400, y: self == .ok ? 220 : 254, width: 80, height: 18) }
    }
    private var pageButton: PageButton?
    var popup: Int?
    var popupHover: Int?
    var antsPhase = 0
    private var caretVisible = true
    private var nextCaretChange: TimeInterval = 0
    var animationTimer: Timer?
    private var handStart: (screen: PixelPoint, origin: PixelPoint)?
    private var pendingHandOrigin: PixelPoint?
    private var lastPointer = PixelPoint.zero
    private var pointerInside = false
    private var mouse128K = Macintosh128KMouse()
    func reset128KMouse() { mouse128K.reset() }
    private struct CursorKey: Hashable {
        let code: UInt8
        let mask: UInt8
        let scale: Int
    }
    private var toolCursors = [CursorKey: NSCursor]()
    private var scale: CGFloat { max(1, min(floor(bounds.width / 512), floor(bounds.height / 342))) }
    private var workspaceOrigin: NSPoint { NSPoint(x: floor((bounds.width - 512 * scale) / 2), y: floor((bounds.height - 342 * scale) / 2)) }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(model: PaintModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 1024, height: 684))
        wantsLayer = true
        setAccessibilityElement(false)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.model.selection != nil {
                self.antsPhase = (self.antsPhase + 1) & 7; self.needsDisplay = true
            }
            if self.model.textOrigin != nil && ProcessInfo.processInfo.systemUptime >= self.nextCaretChange {
                self.caretVisible.toggle(); self.nextCaretChange = ProcessInfo.processInfo.systemUptime + 0.5
                self.needsDisplay = true
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }
    deinit { animationTimer?.invalidate() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
                                                .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag], owner: self))
    }
    private func trackPointer(_ event: NSEvent) {
        let point = screenPoint(event)
        lastPointer = point
        pointerInside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard controller?.macintosh128K.active == true, controller?.macintosh128K.mouseScaling == true,
              controller?.pending128KOperation == nil, NSApp.modalWindow == nil, window?.attachedSheet == nil,
              window?.isKeyWindow == true, popup == nil, helpID == nil, !pageOverview, documentOpen,
              PixelRect(x: 80, y: 48, width: 416, height: 240).contains(point) else {
            mouse128K.reset(); return
        }
        if [.leftMouseDown, .mouseEntered, .cursorUpdate].contains(event.type) { mouse128K.reset() }
        let mapped = mouse128K.move(to: point, timestamp: event.timestamp)
        lastPointer = mapped
        if mapped != point, let window {
            let global = window.convertPoint(toScreen: convert(viewPoint(mapped), to: nil))
            let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
            CGWarpMouseCursorPosition(CGPoint(x: global.x, y: desktopTop - global.y))
        }
    }
    override func cursorUpdate(with event: NSEvent) {
        trackPointer(event); updatePointerCursor()
    }
    override func mouseEntered(with event: NSEvent) {
        trackPointer(event); updatePointerCursor()
    }
    override func mouseExited(with event: NSEvent) {
        pointerInside = false; mouse128K.reset(); NSCursor.arrow.set()
    }
    func screenPoint(_ event: NSEvent) -> PixelPoint {
        let p = convert(event.locationInWindow, from: nil), offset = workspaceOrigin
        return PixelPoint(x: Int(floor((p.x - offset.x) / scale)), y: Int(floor((p.y - offset.y) / scale)))
    }
    func viewPoint(_ point: PixelPoint) -> NSPoint {
        NSPoint(x: workspaceOrigin.x + CGFloat(point.x) * scale, y: workspaceOrigin.y + CGFloat(point.y) * scale)
    }
    func documentPoint(_ p: PixelPoint) -> PixelPoint {
        if model.fatBits {
            let bias = model.tool == .eraser ? 0 : 4
            return PixelPoint(x: model.fatCenter.x - 26 + Int(floor(Double(p.x - 80 - bias) / 8)),
                              y: model.fatCenter.y - 15 + Int(floor(Double(p.y - 48 - bias) / 8)))
        }
        return PixelPoint(x: p.x - 80 + model.origin.x, y: p.y - 48 + model.origin.y)
    }
    func workspacePoint(_ p: PixelPoint) -> PixelPoint {
        if model.fatBits {
            return PixelPoint(x: (p.x - model.fatCenter.x + 26) * 8 + 80, y: (p.y - model.fatCenter.y + 15) * 8 + 48)
        }
        return PixelPoint(x: p.x - model.origin.x + 80, y: p.y - model.origin.y + 48)
    }
    private func modifiers(_ event: NSEvent) -> PaintModifiers {
        var result: PaintModifiers = []
        if event.modifierFlags.contains(.shift) { result.insert(.shift) }
        if event.modifierFlags.contains(.option) { result.insert(.option) }
        if event.modifierFlags.contains(.command) { result.insert(.command) }
        return result
    }
    func refresh() {
        controller?.refreshMenus(); needsDisplay = true; window?.isDocumentEdited = model.isDirty
        controller?.scheduleRecovery()
        caretVisible = model.textOrigin != nil
        nextCaretChange = ProcessInfo.processInfo.systemUptime + 0.5
        if pointerInside && window?.isKeyWindow == true { updatePointerCursor() }
        controller?.show128KMemoryRefusal()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.2, alpha: 1).setFill(); bounds.fill()
        let screen = renderWorkspace()
        let image = NSImage(cgImage: screen.cgImage(), size: NSSize(width: 512, height: 342))
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: NSRect(origin: workspaceOrigin, size: NSSize(width: 512 * scale, height: 342 * scale)),
                   from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
    }
    func renderWorkspace() -> Bitmap {
        let font = model.resources.chicago, icons = model.resources.paintFont
        var screen = Bitmap(width: 512, height: 342)
        screen.fill(screen.bounds, pattern: .gray)
        screen.fill(PixelRect(x: 0, y: 0, width: 512, height: 20), pattern: .white)
        screen.line(from: PixelPoint(x: 0, y: 19), to: PixelPoint(x: 511, y: 19))
        var menuX = 10
        for (index, menu) in menus.enumerated() {
            font.draw(menu.title, in: &screen, at: PixelPoint(x: menuX, y: 15))
            let width = font.width(of: menu.title) + 14
            if popup == index { screen.invert(PixelRect(x: menuX - 5, y: 0, width: width, height: 19)) }
            menuX += width
        }
        // The palette geometry and glyph positioning are from MacPaint.p:3399.
        let toolRect = PixelRect(x: 15, y: 28, width: 53, height: 221)
        screen.fill(PixelRect(x: 16, y: 29, width: 53, height: 221), pattern: .black)
        screen.fill(toolRect, pattern: .white); screen.frame(toolRect)
        screen.line(from: PixelPoint(x: 41, y: 28), to: PixelPoint(x: 41, y: 248))
        for row in 0..<10 {
            for col in 0..<2 {
                let char = UInt8(69 + row * 2 + col)
                let x = (col == 0 ? 15 : 41) + 14 - icons.advance(char) / 2
                icons.draw(String(UnicodeScalar(char)), in: &screen, at: PixelPoint(x: x, y: 32 + row * 22))
            }
            if row < 9 { screen.line(from: PixelPoint(x: 15, y: 50 + row * 22), to: PixelPoint(x: 67, y: 50 + row * 22)) }
        }
        screen.invert(PixelRect(x: model.tool.rawValue % 2 == 0 ? 16 : 42,
                                y: 29 + model.tool.rawValue / 2 * 22, width: 25, height: 21))
        let lineRect = PixelRect(x: 15, y: 258, width: 53, height: 77)
        screen.fill(PixelRect(x: 16, y: 259, width: 53, height: 77), pattern: .black)
        screen.fill(lineRect, pattern: .white); screen.frame(lineRect)
        screen.fill(PixelRect(x: 32, y: 270, width: 29, height: 1), pattern: Pattern([0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22]))
        for (width, y) in [(1, 281), (2, 291), (4, 302), (8, 315)] {
            screen.fill(PixelRect(x: 32, y: y, width: 29, height: width), pattern: .black)
        }
        let checkY = !model.border ? 263 : [1: 273, 2: 284, 4: 296, 8: 310][model.lineWidth]!
        icons.draw("A", in: &screen, at: PixelPoint(x: 17, y: checkY))
        let patternRect = PixelRect(x: 77, y: 300, width: 423, height: 35)
        screen.fill(PixelRect(x: 78, y: 301, width: 423, height: 35), pattern: .black)
        screen.fill(patternRect, pattern: .white); screen.frame(patternRect)
        screen.frame(PixelRect(x: 85, y: 306, width: 28, height: 23))
        screen.fill(PixelRect(x: 86, y: 307, width: 26, height: 21), pattern: model.pattern)
        screen.fill(PixelRect(x: 119, y: 301, width: 380, height: 33), pattern: .black)
        for i in 0..<38 {
            screen.fill(PixelRect(x: 120 + (i % 19) * 20, y: i < 19 ? 301 : 318, width: 19, height: 16), pattern: model.patterns[i])
        }
        if documentOpen {
        screen.fill(PixelRect(x: 79, y: 28, width: 419, height: 262), pattern: .white)
        screen.frame(PixelRect(x: 79, y: 28, width: 419, height: 262))
        screen.line(from: PixelPoint(x: 80, y: 47), to: PixelPoint(x: 496, y: 47))
        screen.line(from: PixelPoint(x: 498, y: 30), to: PixelPoint(x: 498, y: 290))
        screen.line(from: PixelPoint(x: 81, y: 290), to: PixelPoint(x: 498, y: 290))
        for y in stride(from: 31, through: 43, by: 2) {
            screen.line(from: PixelPoint(x: 82, y: y), to: PixelPoint(x: 494, y: y))
        }
        let titleWidth = font.width(of: documentTitle), titleX = 288 - titleWidth / 2
        screen.fill(PixelRect(x: titleX - 5, y: 29, width: titleWidth + 10, height: 17), pattern: .white)
        font.draw(documentTitle, in: &screen, at: PixelPoint(x: titleX, y: 41))
        screen.fill(PixelRect(x: 86, y: 31, width: 13, height: 13), pattern: .white)
        screen.frame(PixelRect(x: 87, y: 32, width: 11, height: 11))
        let bitmap = model.displayBitmap
        if let helpID, let help = model.resources.help[helpID] {
            screen.copy(help, at: PixelPoint(x: 80, y: 48))
        } else if let overview {
            let lightGray = Pattern([0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22])
            for y in 48..<288 { for x in 80..<496 {
                screen[x, y] = lightGray.pixel(x - 80 + model.origin.x, y - 48 + model.origin.y)
            } }
            for y in 0..<240 { for x in 0..<192 {
                screen[192 + x, 48 + y] = overview.image[x - overview.imageShift.x, y - overview.imageShift.y]
            } }
            screen.frame(PixelRect(x: 191, y: 47, width: 194, height: 242))
            let r = PixelRect(x: 192 + overview.viewport.x, y: 48 + overview.viewport.y,
                              width: overview.viewport.width, height: overview.viewport.height)
            for y in r.y..<r.bottom { for x in r.x..<r.right {
                if (y == r.y || y == r.bottom - 1 || x == r.x || x == r.right - 1)
                    && Pattern.gray.pixel(x - 80 + model.origin.x, y - 48 + model.origin.y) { screen[x, y].toggle() }
            } }
            for button in PageButton.allCases {
                screen.fill(button.rect, pattern: .white); screen.frame(button.rect)
                font.draw(button.rawValue, in: &screen,
                          at: PixelPoint(x: 440 - font.width(of: button.rawValue) / 2, y: button.rect.y + 13))
                if pageButton == button && button.rect.contains(lastPointer) { screen.invert(button.rect) }
            }
        } else if model.fatBits {
            for y in 0..<240 { for x in 0..<416 {
                screen[80 + x, 48 + y] = (x & 7 != 7) && (y & 7 != 7) && bitmap[model.fatCenter.x - 26 + x / 8, model.fatCenter.y - 15 + y / 8]
            } }
            // PaintAsm.a:2290 FatToScrn reserves the top-left 56 × 32 pixels
            // for an actual-size preview, including its right and bottom border.
            for y in 0..<32 { for x in 0..<56 {
                screen[80 + x, 48 + y] = x < 52 && y < 30 ? bitmap[model.fatCenter.x - 26 + x, model.fatCenter.y - 15 + y]
                    : (x == 52 && y <= 30) || (y == 30 && x <= 52)
            } }
        } else {
            screen.copy(bitmap.cropped(to: model.visibleRect), at: PixelPoint(x: 80, y: 48))
        }
        if helpID == nil && !pageOverview {
            if let selection = model.selection {
                let mask = selection.mask
                for y in 0..<mask.height { for x in 0..<mask.width where mask[x, y] {
                    if !mask[x - 1, y] || !mask[x + 1, y] || !mask[x, y - 1] || !mask[x, y + 1] {
                        let p = workspacePoint(PixelPoint(x: selection.origin.x + x, y: selection.origin.y + y))
                        if (80..<496).contains(p.x) && (48..<288).contains(p.y) {
                            screen[p.x, p.y] = (p.x + p.y + antsPhase) & 7 < 4
                        }
                    }
                } }
            }
            let preview = model.selectionPreview ?? model.polygonPoints
            if preview.count > 1 {
                for i in 1..<preview.count {
                    screen.line(from: workspacePoint(preview[i - 1]), to: workspacePoint(preview[i]), pattern: .gray)
                }
            }
            if let last = model.polygonPoints.last, (80..<496).contains(lastPointer.x), (48..<288).contains(lastPointer.y) {
                screen.line(from: workspacePoint(last), to: lastPointer)
            }
            if caretVisible, let caret = model.textCaretRect {
                let canvas = PixelRect(x: 80, y: 48, width: 416, height: 240)
                for y in caret.y..<caret.bottom {
                    let p = workspacePoint(PixelPoint(x: caret.x, y: y))
                    let rect = model.fatBits ? PixelRect(x: p.x + 1, y: p.y + 1, width: 7, height: 7)
                                             : PixelRect(x: p.x, y: p.y, width: 1, height: 1)
                    screen.invert(rect.intersect(canvas))
                }
            }
        }
        }
        if let index = popup {
            let rect = menuRect(index)
            screen.fill(PixelRect(x: rect.x + 2, y: rect.y + 2, width: rect.width, height: rect.height), pattern: .black)
            screen.fill(rect, pattern: .white); screen.frame(rect)
            for (i, item) in menus[index].items.enumerated() {
                let y = rect.y + 3 + i * 18
                if item.isSeparator {
                    screen.line(from: PixelPoint(x: rect.x + 1, y: y + 8), to: PixelPoint(x: rect.right - 2, y: y + 8), pattern: .gray)
                    continue
                }
                font.draw(item.title, in: &screen, at: PixelPoint(x: rect.x + 18, y: y + 12))
                if item.checked { icons.draw("A", in: &screen, at: PixelPoint(x: rect.x + 3, y: y + 3)) }
                if !item.shortcut.isEmpty { font.draw(item.shortcut, in: &screen, at: PixelPoint(x: rect.right - font.width(of: item.shortcut) - 8, y: y + 12)) }
                if !item.enabled {
                    for py in y..<(y + 15) { for px in (rect.x + 1)..<(rect.right - 1) where (px + py) & 1 == 0 { screen[px, py] = false } }
                }
                if popupHover == i && item.enabled { screen.invert(PixelRect(x: rect.x + 1, y: y - 1, width: rect.width - 2, height: 18)) }
            }
        }
        if let operation = controller?.pending128KOperation {
            let rect = PixelRect(x: 138, y: 124, width: 280, height: 88)
            screen.fill(rect, pattern: .white); screen.frame(rect, width: 2)
            font.draw("Macintosh 128K", in: &screen, at: PixelPoint(x: 154, y: 145))
            font.draw(operation, in: &screen, at: PixelPoint(x: 154, y: 170))
            font.draw("Esc or click to cancel", in: &screen, at: PixelPoint(x: 154, y: 195))
        }
        return screen
    }
    private func menuRect(_ index: Int) -> PixelRect {
        let font = model.resources.chicago
        let x = 5 + menus.prefix(index).reduce(0) { $0 + font.width(of: $1.title) + 14 }
        let width = max(120, menus[index].items.map { font.width(of: $0.title) + font.width(of: $0.shortcut) + 42 }.max() ?? 120)
        return PixelRect(x: min(x, 511 - width), y: 19, width: width, height: menus[index].items.count * 18 + 6)
    }
    private func menuAt(_ p: PixelPoint) -> Int? {
        guard p.y >= 0 && p.y < 19 else { return nil }
        var x = 5
        for (i, menu) in menus.enumerated() {
            let width = model.resources.chicago.width(of: menu.title) + 14
            if p.x >= x && p.x < x + width { return i }
            x += width
        }
        return nil
    }
    override func mouseDown(with event: NSEvent) {
        if controller?.pending128KOperation != nil { controller?.cancel128KOperation(); return }
        window?.makeFirstResponder(self)
        trackPointer(event)
        defer { updatePointerCursor() }
        let p = lastPointer
        if pageOverview {
            pageButton = PageButton.allCases.first { $0.rect.contains(p) }
            if pageButton == nil && (192..<384).contains(p.x) && (48..<288).contains(p.y) {
                overview?.beginDrag(at: PixelPoint(x: p.x - 192, y: p.y - 48), constrained: event.modifierFlags.contains(.shift))
            }
            refresh(); return
        }
        if let index = menuAt(p) { popup = popup == index ? nil : index; popupHover = nil; needsDisplay = true; return }
        if let menu = popup {
            let r = menuRect(menu), i = (p.y - r.y - 3) / 18
            var command: String?
            if r.contains(p) && i >= 0 && i < menus[menu].items.count {
                let item = menus[menu].items[i]
                if item.enabled && !item.isSeparator { command = item.command }
            }
            popup = nil; popupHover = nil
            if let command { controller?.perform(command, modifiers: modifiers(event)) }
            refresh(); return
        }
        if helpID != nil { helpID = nil; refresh(); return }
        if (15..<68).contains(p.x) && (28..<249).contains(p.y) {
            let tool = PaintTool(rawValue: min(9, (p.y - 28) / 22) * 2 + (p.x > 41 ? 1 : 0))!
            model.chooseTool(tool)
            if event.clickCount > 1 {
                switch tool {
                case .eraser: model.eraseWindow(); model.chooseTool(model.previousTool)
                case .pencil: model.toggleFatBits()
                case .selection: model.selectAll()
                case .hand: pageOverview = true
                case .brush: controller?.perform("brush")
                default: break
                }
            }
        } else if (15..<68).contains(p.x) && (258..<335).contains(p.y) {
            model.border = p.y > 276
            model.lineWidth = p.y > 310 ? 8 : p.y > 297 ? 4 : p.y > 286 ? 2 : 1
        } else if (77..<500).contains(p.x) && (300..<335).contains(p.y) {
            if p.x >= 120 { model.patternIndex = min(37, (p.x - 120) / 20 + (p.y > 317 ? 19 : 0)) }
            if event.clickCount > 1 { controller?.perform("pattern") }
        } else if documentOpen && (87..<98).contains(p.x) && (32..<43).contains(p.y) {
            controller?.perform("close")
        } else if documentOpen && (80..<496).contains(p.x) && (48..<288).contains(p.y) {
            let point = documentPoint(p)
            if model.fatBits && p.x <= 135 && p.y <= 79 {
                model.toggleFatBits()
            } else if model.tool == .hand || (model.tool == .pencil && event.modifierFlags.contains(.option)) {
                handStart = (p, model.fatBits ? model.fatCenter : model.origin); pendingHandOrigin = nil
            } else if model.tool == .pencil && event.modifierFlags.contains(.command) {
                model.toggleFatBits(at: point)
            } else {
                let flags = modifiers(event), clicks = event.clickCount
                if model.tool == .bucket, controller?.schedule128KOperation("bucket", label: "Paint Bucket...", action: { [weak self] in
                    guard let self else { return }
                    self.model.begin(at: point, modifiers: flags, clickCount: clicks)
                    self.model.end(at: point, modifiers: flags)
                }) == true { return }
                model.begin(at: point, modifiers: flags, clickCount: clicks)
            }
        }
        refresh()
    }
    override func mouseDragged(with event: NSEvent) {
        guard controller?.pending128KOperation == nil else { return }
        trackPointer(event)
        let p = lastPointer
        if popup != nil { mouseMoved(with: event); return }
        if pageOverview {
            overview?.drag(to: PixelPoint(x: p.x - 192, y: p.y - 48))
            refresh(); return
        }
        if let hand = handStart {
            var dx = hand.screen.x - p.x, dy = hand.screen.y - p.y
            if event.modifierFlags.contains(.shift) { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
            if model.fatBits {
                model.fatCenter = PixelPoint(x: max(model.origin.x + 26, min(model.origin.x + 390, hand.origin.x + dx / 3)),
                                             y: max(model.origin.y + 15, min(model.origin.y + 225, hand.origin.y + dy / 3)))
            } else if controller?.macintosh128K.timed == true {
                pendingHandOrigin = PixelPoint(x: hand.origin.x + dx, y: hand.origin.y + dy)
            } else { model.setOrigin(PixelPoint(x: hand.origin.x + dx, y: hand.origin.y + dy)) }
        } else { model.drag(to: documentPoint(p), modifiers: modifiers(event)) }
        refresh()
    }
    override func mouseUp(with event: NSEvent) {
        guard controller?.pending128KOperation == nil else { return }
        trackPointer(event)
        if pageOverview {
            overview?.drag(to: PixelPoint(x: lastPointer.x - 192, y: lastPointer.y - 48))
            if let button = pageButton, button.rect.contains(lastPointer) { endPageOverview(accept: button == .ok) }
            overview?.endDrag(); pageButton = nil; refresh(); return
        }
        if let menu = popup {
            let p = screenPoint(event), rect = menuRect(menu)
            if rect.contains(p) {
                let index = (p.y - rect.y - 3) / 18
                if menus[menu].items.indices.contains(index) {
                    let item = menus[menu].items[index]
                    popup = nil; popupHover = nil
                    if item.enabled && !item.isSeparator { controller?.perform(item.command, modifiers: modifiers(event)) }
                }
            }
            refresh(); return
        }
        if handStart != nil {
            handStart = nil
            if let target = pendingHandOrigin {
                pendingHandOrigin = nil
                if controller?.schedule128KOperation("scroll", label: "Reading floppy...", action: { [weak self] in
                    self?.model.setOrigin(target)
                }) == true { return }
            }
        }
        else if popup == nil { model.end(at: documentPoint(lastPointer), modifiers: modifiers(event)) }
        refresh()
    }
    override func mouseMoved(with event: NSEvent) {
        trackPointer(event)
        let p = lastPointer
        if let current = popup {
            if let next = menuAt(p), next != current { popup = next; popupHover = nil }
            else {
                let rect = menuRect(current)
                popupHover = rect.contains(p) ? max(0, min(menus[current].items.count - 1, (p.y - rect.y - 3) / 18)) : nil
            }
            needsDisplay = true
        }
        if !model.polygonPoints.isEmpty { needsDisplay = true }
        updatePointerCursor()
    }
    private func updatePointerCursor() {
        guard controller?.pending128KOperation == nil, pointerInside, documentOpen, popup == nil, helpID == nil, !pageOverview,
              (80..<496).contains(lastPointer.x), (48..<288).contains(lastPointer.y) else {
            NSCursor.arrow.set(); return
        }
        if let selection = model.selection {
            let p = documentPoint(lastPointer)
            if selection.rect.contains(p) && selection.mask[p.x - selection.origin.x, p.y - selection.origin.y] { NSCursor.arrow.set(); return }
        }
        let codes: [PaintTool: Int] = [.lasso: 69, .selection: 114, .hand: 71, .text: 110, .bucket: 73, .spray: 111, .pencil: 76, .eraser: 119]
        let code = UInt8(model.tool == .brush ? 120 + model.brushIndex : codes[model.tool] ?? [1: 89, 2: 90, 4: 91, 8: 92][model.lineWidth]!)
        let maskCode: [PaintTool: UInt8] = [.selection: 115, .hand: 109, .bucket: 93, .pencil: 116, .eraser: 120]
        let key = CursorKey(code: code, mask: maskCode[model.tool] ?? 97, scale: Int(scale))
        if let cursor = toolCursors[key] { cursor.set(); return }
        let bitmap = model.resources.paintFont.cursorSprite(code)
        let mask = model.resources.paintFont.cursorSprite(key.mask)
        let hot: PixelPoint
        switch model.tool {
        case .lasso: hot = PixelPoint(x: 2, y: 15)
        case .text: hot = PixelPoint(x: 8, y: 13)
        case .pencil: hot = PixelPoint(x: 3, y: 16)
        case .bucket: hot = PixelPoint(x: 13, y: 16)
        default: hot = PixelPoint(x: 8, y: 8)
        }
        // AppKit has no QuickDraw XOR cursor. Keep the original ink and mask,
        // with a white edge and black outer edge. A white edge alone can match
        // the canvas exactly after this same brush has stamped beneath it.
        let imageSize = NSSize(width: 20 * scale, height: 20 * scale)
        let image = NSImage(size: imageSize)
        for density in [1, 2] {
            let factor = key.scale * density, size = 20 * factor
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: size * 4, bitsPerPixel: 32)!
            let pixels = rep.bitmapData!
            for y in 0..<size { for x in 0..<size {
                let sx = x / factor - 2, sy = y / factor - 2, ink = bitmap[sx, sy]
                var opaque = ink || mask[sx, sy]
                if !opaque {
                    for dy in -1...1 { for dx in -1...1 where bitmap[sx + dx, sy + dy] { opaque = true } }
                }
                var black = ink
                if !opaque {
                    for dy in -2...2 { for dx in -2...2 where bitmap[sx + dx, sy + dy] { black = true } }
                    opaque = black
                }
                let offset = y * rep.bytesPerRow + x * 4
                let value: UInt8 = black || !opaque ? 0 : 255
                pixels[offset] = value; pixels[offset + 1] = value; pixels[offset + 2] = value
                pixels[offset + 3] = opaque ? 255 : 0
            } }
            rep.size = imageSize
            image.addRepresentation(rep)
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: CGFloat(hot.x + 2) * scale, y: CGFloat(hot.y + 2) * scale))
        toolCursors[key] = cursor
        cursor.set()
    }
    override func scrollWheel(with event: NSEvent) {
        guard documentOpen, !pageOverview, controller?.pending128KOperation == nil else { return }
        if !model.fatBits {
            let target = PixelPoint(x: model.origin.x + Int(event.scrollingDeltaX), y: model.origin.y + Int(event.scrollingDeltaY))
            if controller?.schedule128KOperation("scroll", label: "Reading floppy...", action: { [weak self] in
                self?.model.setOrigin(target)
            }) == true { return }
        }
        if model.fatBits {
            model.fatCenter = PixelPoint(x: max(model.origin.x + 26, min(model.origin.x + 390, model.fatCenter.x + Int(event.scrollingDeltaX) / 3)),
                                         y: max(model.origin.y + 15, min(model.origin.y + 225, model.fatCenter.y + Int(event.scrollingDeltaY) / 3)))
        } else { model.setOrigin(PixelPoint(x: model.origin.x + Int(event.scrollingDeltaX), y: model.origin.y + Int(event.scrollingDeltaY))) }
        refresh()
    }
    override func keyDown(with event: NSEvent) {
        if controller?.pending128KOperation != nil {
            if event.keyCode == 53 { controller?.cancel128KOperation() }
            return
        }
        guard !pageOverview else { return }
        if event.keyCode == 53 && model.textOrigin != nil && helpID == nil && !pageOverview {
            refresh(); return
        }
        if event.keyCode == 53 {
            helpID = nil; popup = nil; model.finishPolygon(); model.commitText(); model.acceptSelection()
        } else if model.textOrigin != nil {
            if event.keyCode == 51 { model.updateText(String(model.text.dropLast())) }
            else if event.keyCode == 36 { model.updateText(model.text + "\n") }
            else if event.keyCode == 76 { model.continueText() }
            else if let text = event.characters, !event.modifierFlags.contains(.command) {
                let printable = text.unicodeScalars.filter { $0.value >= 32 && !(0xF700...0xF8FF).contains($0.value) }
                if !printable.isEmpty { model.updateText(model.text + String(String.UnicodeScalarView(printable))) }
            }
        } else {
            switch event.keyCode {
            case 51, 117: model.editSelection("clear")
            case 36: model.finishPolygon()
            default:
                if event.characters == "`" { model.undo() }
            }
        }
        refresh()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if controller?.pending128KOperation != nil { return true }
        if pageOverview { return true }
        if documentOpen, event.modifierFlags.contains([.command, .shift]),
           event.charactersIgnoringModifiers?.lowercased() == "e", model.selection?.isLasso == false {
            controller?.perform("edges", modifiers: modifiers(event))
            return true
        }
        if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers,
           [",", ".", "<", ">"].contains(key) {
            let step = key == "," || key == "<" ? -1 : 1
            if event.modifierFlags.contains(.shift) {
                let fonts = ["Chicago", "Geneva", "New York", "Monaco", "Times", "Helvetica", "Courier"]
                let index = fonts.firstIndex(of: model.textFont) ?? 1
                controller?.perform("font:\(fonts[max(0, min(fonts.count - 1, index + step))])")
            } else {
                let sizes = [9, 10, 12, 14, 18, 24, 36, 48, 72]
                let index = sizes.firstIndex(of: model.textSize) ?? 2
                controller?.perform("size:\(sizes[max(0, min(sizes.count - 1, index + step))])")
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    private func endPageOverview(accept: Bool) {
        guard let overview else { return }
        if accept { model.applyPageOverview(overview) }
        pageOverview = false
    }
}
