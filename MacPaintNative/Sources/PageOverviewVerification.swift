import AppKit

enum PageOverviewVerification {
    static func model(resources: ClassicResources) throws -> [String] {
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        var bitmap = Bitmap()
        bitmap[1, 1] = true; bitmap[5, 2] = true; bitmap[575, 718] = true
        let original = PageOverview(bitmap: bitmap, origin: PixelPoint(x: 80, y: 120))
        var expected = Bitmap(width: 192, height: 240)
        expected[0, 0] = true; expected[1, 1] = true; expected[191, 239] = true
        try check(original.image == expected, "Show Page shrink merges horizontal ink and uses QuickDraw's vertical band phase")
        var boundaries = Bitmap(); boundaries[10, 47] = true; boundaries[10, 48] = true
        var reduced = Bitmap(width: 192, height: 240); reduced[3, 16] = true
        try check(PageOverview(bitmap: boundaries, origin: .zero).image == reduced,
                  "Show Page restarts the vertical shrink DDA for each 48-row band")
        try check(original.viewport == PixelRect(x: 27, y: 40, width: 138, height: 80),
                  "Show Page rounds both viewport corners through QuickDraw MapRect")
        try check(PageOverview(bitmap: bitmap, origin: .zero).viewport == PixelRect(x: 0, y: 0, width: 139, height: 80),
                  "Show Page retains the initial 139-pixel frame when corner rounding requires it")
        var page = original
        page.beginDrag(at: PixelPoint(x: 40, y: 50), constrained: false)
        page.drag(to: PixelPoint(x: 45, y: 57)); page.endDrag()
        try check(page.documentOrigin == PixelPoint(x: 95, y: 141), "Show Page scroll retains the original document origin modulo three")
        page = original; page.beginDrag(at: PixelPoint(x: 40, y: 50), constrained: false)
        page.drag(to: PixelPoint(x: 240, y: 550))
        try check(page.viewport == PixelRect(x: 54, y: 160, width: 138, height: 80)
                  && page.documentOrigin == PixelPoint(x: 160, y: 480), "Show Page scroll reaches the exact right and bottom edges")
        page.drag(to: PixelPoint(x: 140, y: 350))
        try check(page.documentOrigin == PixelPoint(x: 160, y: 480), "Show Page retains pointer overshoot when reversing a clamped drag")
        page.drag(to: PixelPoint(x: 65, y: 50))
        try check(page.documentOrigin == PixelPoint(x: 155, y: 120), "Show Page resumes scrolling after pointer returns from overshoot")
        page = original; page.beginDrag(at: PixelPoint(x: 40, y: 50), constrained: false)
        page.drag(to: .zero)
        try check(page.documentOrigin == .zero, "Show Page snaps the last two document pixels to the left and top edges")
        page = original; page.beginDrag(at: PixelPoint(x: 40, y: 50), constrained: true)
        page.drag(to: PixelPoint(x: 41, y: 50)); page.drag(to: PixelPoint(x: 43, y: 53))
        try check(page.viewport == original.viewport, "Show Page Shift waits for a direction beyond one pixel and ignores equal diagonals")
        page.drag(to: PixelPoint(x: 44, y: 51)); page.drag(to: PixelPoint(x: 45, y: 90))
        try check(page.documentOrigin == PixelPoint(x: 95, y: 120), "Show Page Shift keeps its first horizontal direction for the complete drag")
        page = original; page.beginDrag(at: PixelPoint(x: 40, y: 50), constrained: true)
        page.drag(to: PixelPoint(x: 40, y: 53)); page.drag(to: PixelPoint(x: 90, y: 55))
        try check(page.documentOrigin == PixelPoint(x: 80, y: 135), "Show Page Shift keeps its first vertical direction for the complete drag")
        page = original; page.beginDrag(at: PixelPoint(x: 180, y: 200), constrained: false)
        page.drag(to: PixelPoint(x: 181, y: 201)); page.endDrag()
        try check(page.imageShift == PixelPoint(x: 1, y: 1) && page.documentShift == .zero && !page.hasChanges,
                  "Show Page previews one small-image pixel but truncates document shifts below eight pixels")
        page.beginDrag(at: PixelPoint(x: 180, y: 200), constrained: false)
        page.drag(to: PixelPoint(x: 182, y: 196)); page.endDrag()
        try check(page.documentShift == PixelPoint(x: 8, y: -8) && page.image == original.image,
                  "Show Page accumulates image drags and truncates positive and negative shifts toward zero")
        let model = PaintModel(resources: resources)
        model.setOrigin(PixelPoint(x: 80, y: 120)); model.bitmap[0, 10] = true; model.bitmap[575, 719] = true
        model.markSaved(); let palette = model.patterns
        model.applyPageOverview(page)
        var shifted = Bitmap(); shifted[8, 2] = true
        try check(model.bitmap == shifted && model.isDirty && model.patterns == palette,
                  "Show Page applies the aligned full-page shift with white fill and clipping, retaining patterns")
        let accepted = model.bitmap; model.undo()
        try check(model.bitmap == accepted && model.undoState == nil,
                  "Show Page accepts the shifted document as the original Undo baseline")
        model.newDocument(); model.setOrigin(PixelPoint(x: 80, y: 120)); model.chooseTool(.pencil)
        model.begin(at: PixelPoint(x: 100, y: 150)); model.end(at: PixelPoint(x: 101, y: 150)); model.fatBits = true
        let entered = model.beginPageOverview(); let drawing = model.bitmap; model.undo()
        try check(!model.fatBits && model.undoState == nil && model.bitmap == drawing && entered.originalOrigin == model.origin,
                  "Entering Show Page accepts previous edits and exits FatBits")
        model.applyPageOverview(original)
        try check(model.fatCenter == PixelPoint(x: 288, y: 240), "Unchanged Show Page leaves the FatBits center intact")
        return checks
    }

    static func run(controller: AppController, output: URL) throws -> [String] {
        let model = controller.model!, view = controller.workspace!, window = controller.window!
        let originalFrame = window.frame
        defer { view.pageOverview = false; model.newDocument(); window.setFrame(originalFrame, display: true); view.refresh() }
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func reset() {
            view.pageOverview = false; view.helpID = nil; view.popup = nil
            model.newDocument(); model.chooseTool(.brush); model.markSaved(); view.refresh(); controller.perform("page")
        }
        func mouse(_ type: NSEvent.EventType, _ x: Int, _ y: Int, shift: Bool = false) {
            let event = NSEvent.mouseEvent(with: type, location: view.convert(view.viewPoint(PixelPoint(x: x, y: y)), to: nil),
                modifierFlags: shift ? .shift : [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        func click(_ x: Int, _ y: Int) { mouse(.leftMouseDown, x, y); mouse(.leftMouseUp, x, y) }
        func snapshot(_ name: String) throws {
            view.displayIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw Verification.Failure(description: "Show Page NSView snapshot unavailable")
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        }
        reset()
        let screen = view.renderWorkspace()
        try snapshot("Show-Page.png")
        guard screen[219, 89] else {
            throw Verification.Failure(description: "Show Page initial frame: expected black at (219,89) from QuickDraw MapRect rounding, actual white")
        }
        checks.append("Show Page maps the initial viewport with QuickDraw corner rounding")
        click(263, 10); click(50, 105)
        try check(view.pageOverview && view.popup == nil && model.tool == .brush, "Show Page ignores classic menus and tool clicks until OK or Cancel")
        controller.perform("fatbits")
        for (code, text) in [(UInt16(36), "\r"), (UInt16(53), "\u{1b}"), (UInt16(51), "\u{7f}")] {
            window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: code)!)
        }
        let scroll = NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 2, wheel1: 20, wheel2: 20, wheel3: 0)!)!
        view.scrollWheel(with: scroll)
        try check(view.pageOverview && !model.fatBits && model.origin == PixelPoint(x: 80, y: 120),
                  "Show Page ignores keyboard, wheel and native menu commands like the original modal loop")
        try check(!controller.windowShouldClose(window) && controller.applicationShouldTerminate(NSApp) == .terminateCancel,
                  "Show Page requires completion before native Close or Quit")
        try check(!controller.application(NSApp, openFile: output.appendingPathComponent("RoundTrip.mac").path) && view.pageOverview,
                  "Show Page retains the current document when an external Open arrives during its preview")
        click(440, 263)
        for scale in [2, 1] {
            window.setContentSize(NSSize(width: 512 * scale, height: 342 * scale)); window.makeFirstResponder(view)
            reset(); let drawing = model.bitmap
            mouse(.leftMouseDown, 232, 98); mouse(.leftMouseDragged, 237, 105); mouse(.leftMouseUp, 237, 105)
            try check(model.origin == PixelPoint(x: 80, y: 120) && model.bitmap == drawing && !model.isDirty,
                      "Show Page drag remains a preview before OK at \(scale)x")
            mouse(.leftMouseDown, 440, 229)
            try check(view.pageOverview, "Show Page OK waits for mouse release at \(scale)x")
            mouse(.leftMouseDragged, 490, 229); mouse(.leftMouseUp, 490, 229)
            try check(view.pageOverview, "Show Page cancels button activation when released outside at \(scale)x")
            click(440, 229)
            try check(!view.pageOverview && model.origin == PixelPoint(x: 95, y: 141) && model.bitmap == drawing && !model.isDirty
                      && model.fatCenter == PixelPoint(x: 303, y: 261), "Show Page OK applies scrolling and updates FatBits center at \(scale)x")
            reset(); mouse(.leftMouseDown, 232, 98); mouse(.leftMouseDragged, 450, 400); mouse(.leftMouseUp, 450, 400)
            try snapshot("Show-Page-Edges-\(scale)x.png")
            try check(view.renderWorkspace()[383, 209], "Show Page frame reaches the right page border at \(scale)x")
            click(440, 229)
            try check(model.origin == PixelPoint(x: 160, y: 480), "Show Page scroll reaches document corner at \(scale)x")
            reset(); mouse(.leftMouseDown, 232, 98, shift: true)
            mouse(.leftMouseDragged, 236, 99, shift: true); mouse(.leftMouseDragged, 237, 138); mouse(.leftMouseUp, 237, 138)
            click(440, 229)
            try check(model.origin == PixelPoint(x: 95, y: 120), "Show Page Shift latches the first axis and the mouse-down modifier at \(scale)x")
            reset(); mouse(.leftMouseDown, 232, 98); mouse(.leftMouseDragged, 237, 105, shift: true); mouse(.leftMouseUp, 237, 105, shift: true)
            click(440, 229)
            try check(model.origin == PixelPoint(x: 95, y: 141), "Show Page ignores Shift pressed after mouse-down at \(scale)x")
            view.pageOverview = false; model.newDocument(); model.bitmap[1, 10] = true; model.bitmap[575, 719] = true
            model.markSaved(); let before = model.bitmap; controller.perform("page")
            mouse(.leftMouseDown, 372, 248); mouse(.leftMouseDragged, 375, 245); mouse(.leftMouseUp, 375, 245)
            try check(view.renderWorkspace()[195, 48] && model.bitmap == before && !model.isDirty,
                      "Show Page translates the frozen reduced image while retaining full document pixels at \(scale)x")
            try snapshot("Show-Page-Shift-\(scale)x.png")
            click(440, 263)
            try check(model.bitmap == before && model.origin == PixelPoint(x: 80, y: 120) && !model.isDirty,
                      "Show Page Cancel discards image shift at \(scale)x")
            controller.perform("page"); mouse(.leftMouseDown, 372, 248); mouse(.leftMouseDragged, 375, 251); mouse(.leftMouseUp, 375, 251)
            click(440, 229)
            var expected = Bitmap(); expected[9, 18] = true
            try check(model.bitmap == expected && model.isDirty, "Show Page OK applies eight-pixel alignment and clips the far edge at \(scale)x")
            model.undo(); try check(model.bitmap == expected, "Show Page shift cannot restore the previous page through Undo at \(scale)x")
        }
        try JSONSerialization.data(withJSONObject: ["checks": checks, "count": checks.count,
            "scope": "Real NSWindow mouse/key events and cached NSView display at 1x and 2x; original-source expectations, not an executed classic reference."],
            options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Show-Page.json"))
        return checks
    }
}
