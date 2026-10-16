import AppKit

enum PatternVerification {
    static func run(controller: AppController, output: URL) throws -> [String] {
        let model = controller.model!, view = controller.workspace!, window = controller.window!
        let originalFrame = window.frame
        defer {
            model.newDocument(); model.patternIndex = 0; model.chooseTool(.brush)
            window.setFrame(originalFrame, display: true); view.refresh()
        }
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func grid(_ dialog: ClassicDialogView) -> Pattern {
            let image = dialog.renderDialog()
            return Pattern((0..<8).map { y in
                (0..<8).reduce(UInt8(0)) { row, x in image[16 + x * 8, 16 + y * 8] ? row | (0x80 >> x) : row }
            })
        }
        func mouse(_ type: NSEvent.EventType, at p: PixelPoint) -> NSEvent {
            let scale = max(1, min(floor(view.bounds.width / 512), floor(view.bounds.height / 342)))
            let offset = NSPoint(x: floor((view.bounds.width - 512 * scale) / 2), y: floor((view.bounds.height - 342 * scale) / 2))
            let location = view.convert(NSPoint(x: offset.x + CGFloat(p.x) * scale, y: offset.y + CGFloat(p.y) * scale), to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func sample(_ point: PixelPoint, expected: Pattern, accept: Bool, snapshot: String, keyboard: Bool = false) throws {
            var observed: Pattern?, posted = false, closing = false, captured = false, placement = false
            let deadline = Date().addingTimeInterval(2)
            var sampleDeadline = deadline
            let timer = Timer(timeInterval: 0.02, repeats: true) { timer in
                guard let panel = NSApp.modalWindow, let dialog = panel.contentView as? ClassicDialogView, dialog.kind == "pattern" else {
                    if Date() > deadline { timer.invalidate(); NSApp.abortModal() }
                    return
                }
                if !posted {
                    let scale = max(1, min(floor(view.bounds.width / 512), floor(view.bounds.height / 342)))
                    let expectedCorner = window.convertPoint(toScreen: view.convert(view.viewPoint(PixelPoint(x: 116, y: 76)), to: nil))
                    placement = abs(panel.frame.minX - expectedCorner.x) < 0.5 && abs(panel.frame.maxY - expectedCorner.y) < 0.5
                        && abs(panel.frame.width - 176 * scale) < 0.5 && abs(panel.frame.height - 128 * scale) < 0.5
                    posted = true; sampleDeadline = Date().addingTimeInterval(0.5)
                    NSApp.postEvent(mouse(.leftMouseDown, at: point), atStart: false)
                    NSApp.postEvent(mouse(.leftMouseUp, at: point), atStart: false)
                } else if !closing {
                    observed = grid(dialog)
                    if observed == expected || Date() > sampleDeadline {
                        if let rep = dialog.bitmapImageRepForCachingDisplay(in: dialog.bounds) {
                            dialog.cacheDisplay(in: dialog.bounds, to: rep)
                            if let png = rep.representation(using: .png, properties: [:]) {
                                captured = (try? png.write(to: output.appendingPathComponent(snapshot))) != nil
                            }
                        }
                        closing = true
                        if keyboard {
                            NSApp.postEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                                characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!, atStart: false)
                        } else {
                            let location = dialog.convert(NSPoint(x: (accept ? 48 : 128) * dialog.bounds.width / 176,
                                                                  y: 102 * dialog.bounds.height / 128), to: nil)
                            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                                NSApp.postEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!, atStart: false)
                            }
                        }
                    }
                }
                if Date() > deadline { timer.invalidate(); NSApp.abortModal() }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            controller.perform("pattern"); timer.invalidate()
            guard observed == expected, captured, placement else {
                throw Verification.Failure(description: "Pattern sampler expected rows \(expected.rows), actual \(observed?.rows ?? []), snapshot=\(captured), originalPlacement=\(placement)")
            }
        }
        let diagonal = Pattern([0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01])
        func reset() {
            model.newDocument(); model.setOrigin(PixelPoint(x: 13, y: 19)); model.patternIndex = 2
            model.patterns[2] = .white
            for y in 0..<8 { for x in 0..<8 { model.bitmap[400 + x, 136 + y] = diagonal.pixel(x, y) } }
            model.markSaved(); view.refresh()
        }
        reset(); let drawing = model.displayBitmap
        try sample(PixelPoint(x: 464, y: 168), expected: diagonal, accept: true, snapshot: "Pattern-Sample.png")
        try check(model.pattern == diagonal, "pattern editor samples the visible canvas using original rounding with a scrolled origin")
        try check(model.displayBitmap == drawing, "sampling through the modal editor leaves every drawing pixel unchanged")
        try check(model.isDirty, "accepting a different sampled pattern marks the document dirty")
        let saved = try MacPaintFile.decode(MacPaintFile.encode(model.displayBitmap, patterns: model.patterns))
        try check(saved.patterns?[2] == diagonal, "MacPaint file stores the accepted sampled pattern")
        reset()
        try sample(PixelPoint(x: 464, y: 168), expected: diagonal, accept: false, snapshot: "Pattern-Cancel.png")
        try check(model.pattern == .white && !model.isDirty && model.displayBitmap == drawing,
                  "Cancel discards a sampled pattern without dirtying or changing the drawing")
        reset(); model.setOrigin(.zero); model.bitmap = Bitmap(); model.markSaved(); view.refresh()
        let border = Pattern(Array(repeating: 0x08, count: 8))
        try sample(PixelPoint(x: 115, y: 145), expected: border, accept: true, snapshot: "Pattern-Dialog-Edge.png")
        try check(model.pattern == border, "a sample crossing the editor edge includes its visible black border")
        reset(); model.setOrigin(.zero); model.bitmap.fill(model.bitmap.bounds, pattern: .black)
        model.toggleFatBits(); model.markSaved(); view.refresh()
        let enlarged = Pattern([0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0])
        try sample(PixelPoint(x: 464, y: 168), expected: enlarged, accept: true, snapshot: "Pattern-FatBits.png", keyboard: true)
        try check(model.pattern == enlarged && model.fatBits, "FatBits sampling reads the visible seven-pixel cells and white grid, as GetPixel does")
        window.setContentSize(NSSize(width: 512, height: 342))
        reset()
        try sample(PixelPoint(x: 464, y: 168), expected: diagonal, accept: true, snapshot: "Pattern-Sample-1x.png")
        try check(model.pattern == diagonal, "pattern sampling follows native view coordinates at workspace scale one")
        try JSONSerialization.data(withJSONObject: ["checks": checks], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Patterns.json"))
        return checks
    }
}
