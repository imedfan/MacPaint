import AppKit

enum Macintosh128KVerification {
    static func model(resources: ClassicResources) throws -> [String] {
        let domain = "org.macpaintnative.128k-model." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let profile = Macintosh128K(preferences: defaults), model = PaintModel(resources: resources)
        model.macintosh128K = profile
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        try check(!profile.active && !profile.enabled && profile.operationTiming && !profile.mouseScaling,
                  "128K mode defaults off, with independent timing and mouse preferences")
        profile.enabled = true; profile.mouseScaling = true
        try check(!profile.active && profile.delay(for: "save") == 0, "Enable mods gates the entire 128K profile")
        profile.modsEnabled = true
        model.bitmap[100, 100] = true; model.markSaved()
        let drawing = model.displayBitmap
        let file = MacPaintFile.encode(drawing, patterns: model.patterns)
        var large = Bitmap(); large[0, 0] = true
        model.insert(large)
        try check(model.selection == nil && model.displayBitmap == drawing && !model.isDirty && model.undoState == nil,
                  "128K rejects a full-page clipboard allocation before changing pixels, dirty state or Undo")
        try check(model.memoryRefusal?.contains("Your drawing has been preserved") == true,
                  "memory refusal explains the operation, budget and preservation of the drawing")
        model.memoryRefusal = nil
        model.insert(Bitmap(width: 16, height: 16))
        try check(model.selection?.pixels.width == 16 && model.memoryRefusal == nil, "small picture fits the virtual heap")
        model.newDocument(); model.bitmap[100, 100] = true
        model.selectAll()
        let selectedDrawing = model.displayBitmap, oldSelection = model.selection!
        model.editSelection("rotate")
        try check(model.memoryRefusal != nil && model.displayBitmap == selectedDrawing
                  && model.selection?.rect == oldSelection.rect && model.undoState == nil,
                  "a large transform refuses additional working memory and preserves the selection and Undo")
        model.memoryRefusal = nil
        model.begin(at: PixelPoint(x: 100, y: 100)); model.end(at: PixelPoint(x: 100, y: 100))
        try check(model.memoryRefusal == nil && model.displayBitmap == selectedDrawing, "moving an existing large selection reuses its virtual mask")
        model.newDocument(); profile.modsEnabled = false
        model.insert(large)
        try check(model.selection != nil && model.memoryRefusal == nil, "disabling mods restores unrestricted original paste")
        model.newDocument(); model.bitmap = drawing
        try check(MacPaintFile.encode(model.displayBitmap, patterns: model.patterns) == file,
                  "128K preferences leave the standard MacPaint bytes and 576 by 720 page unchanged")
        let restored = Macintosh128K(preferences: UserDefaults(suiteName: domain)!)
        try check(restored.enabled && restored.operationTiming && restored.mouseScaling,
                  "a fresh profile restores mode, timing and mouse preferences")
        var mouse = Macintosh128KMouse()
        _ = mouse.move(to: PixelPoint(x: 100, y: 100), timestamp: 1)
        try check(mouse.move(to: PixelPoint(x: 102, y: 100), timestamp: 1.001) == PixelPoint(x: 102, y: 100),
                  "small logical mouse movements keep their distance")
        try check(mouse.move(to: PixelPoint(x: 110, y: 100), timestamp: 1.002) == PixelPoint(x: 118, y: 100),
                  "the approximate 60 Hz mouse threshold doubles faster movement")
        try check(mouse.move(to: PixelPoint(x: 120, y: 100), timestamp: 1.05) == PixelPoint(x: 120, y: 100),
                  "the mouse threshold resets on the next 60 Hz interval")
        try check(mouse.move(to: PixelPoint(x: 490, y: 280), timestamp: 1.051) == PixelPoint(x: 495, y: 287),
                  "accelerated cursor stays inside the canvas")
        mouse.reset()
        try check(mouse.move(to: PixelPoint(x: 200, y: 150), timestamp: 2) == PixelPoint(x: 200, y: 150),
                  "resetting classic input restores an absolute pointer baseline")
        return checks
    }

    static func run(controller: AppController, output: URL) throws -> [String] {
        let domain = "org.macpaintnative.128k-ui." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let testing = AppController(preferences: defaults)
        let model = controller.model!, view = controller.workspace!, window = controller.window!
        let oldFrame = window.frame
        let pointer = CGEvent(source: nil)?.location
        testing.model = model; testing.workspace = view; testing.window = window; testing.verificationDirectory = output
        view.controller = testing
        defer {
            testing.cancel128KOperation(); defaults.removePersistentDomain(forName: domain)
            view.controller = controller; model.macintosh128K = controller.macintosh128K
            model.newDocument(); window.setFrame(oldFrame, display: true); view.reset128KMouse(); view.refresh()
            if let pointer { CGWarpMouseCursorPosition(pointer) }
        }
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func capture(_ content: NSView, _ name: String) throws {
            guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                throw Verification.Failure(description: "Cannot capture \(name)")
            }
            content.cacheDisplay(in: content.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        }
        func key(_ panel: NSWindow, code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: code)!
        }
        func pump(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
        testing.modsEnabled = true
        for scale in [1, 2] {
            window.setContentSize(NSSize(width: 512 * scale, height: 342 * scale)); window.makeKeyAndOrderFront(nil)
            model.newDocument(); model.bitmap[100, 100] = true; model.markSaved()
            let drawing = model.displayBitmap
            testing.macintosh128K.enabled = false; testing.macintosh128K.mouseScaling = false
            testing.macintosh128K.operationTiming = true; testing.update128KConfiguration()
            var stage = 0, observed = false, fits = false, timedOut = false
            var details = ""
            var captureError: Error?
            let deadline = Date().addingTimeInterval(4)
            let timer = Timer(timeInterval: 0.03, repeats: true) { _ in
                if Date() > deadline { timedOut = true; NSApp.abortModal(); return }
                guard let panel = NSApp.modalWindow, let content = panel.contentView as? Macintosh128KPanel else { return }
                let buttons = content.subviews.compactMap { $0 as? NSButton }
                details = buttons.map { "\($0.tag):\($0.title)=\($0.state.rawValue),enabled=\($0.isEnabled),frame=\($0.frame)" }.joined(separator: "; ")
                if stage == 1 && !testing.macintosh128K.enabled { return }
                if stage == 2 && !testing.macintosh128K.mouseScaling { return }
                if stage == 3 && testing.macintosh128K.operationTiming { return }
                if stage > 3 { return }
                if stage < 3 {
                    let tag = [0, 2, 1][stage]
                    guard let button = buttons.first(where: { $0.tag == tag && $0.title != "Done" }) else { return }
                    let location = button.convert(NSPoint(x: button.bounds.minX + 8, y: button.bounds.midY), to: nil)
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        NSApp.postEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!, atStart: false)
                    }
                    stage += 1
                } else {
                    observed = testing.macintosh128K.active && testing.macintosh128K.mouseScaling && !testing.macintosh128K.operationTiming
                    fits = content.frame.size == NSSize(width: 400 * scale, height: 264 * scale)
                        && content.subviews.allSatisfy { content.bounds.contains($0.frame) }
                    do { try capture(content, "128K-Settings-\(scale)x.png") } catch { captureError = error }
                    NSApp.postEvent(key(panel, code: 53), atStart: false)
                    stage += 1
                }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            testing.perform("macintosh128K"); timer.invalidate()
            if let captureError { throw captureError }
            try check(observed && fits && !timedOut, "128K panel handles native checkbox events, integer scaling and Escape at \(scale)x (stage=\(stage), observed=\(observed), fits=\(fits), timeout=\(timedOut); \(details))")
            try check(model.displayBitmap == drawing && !model.isDirty, "128K settings preserve the drawing at \(scale)x")
            try check(view.menus.last?.items.first?.checked == true && NSApp.mainMenu?.items.last?.submenu?.items.first?.state == .on,
                      "both Mods menus show the active 128K mode at \(scale)x")
            let reloaded = AppController(preferences: UserDefaults(suiteName: domain)!)
            try check(reloaded.macintosh128K.active && reloaded.macintosh128K.mouseScaling && !reloaded.macintosh128K.operationTiming,
                      "128K settings survive a fresh application controller at \(scale)x")

            model.newDocument(); model.setOrigin(.zero); model.chooseTool(.pencil); view.reset128KMouse()
            func mouse(_ type: NSEvent.EventType, _ x: Int) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: view.convert(view.viewPoint(PixelPoint(x: x, y: 100)), to: nil),
                    modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            view.mouseDown(with: mouse(.leftMouseDown, 100))
            view.mouseDragged(with: mouse(.leftMouseDragged, 108))
            view.mouseUp(with: mouse(.leftMouseUp, 120))
            try check((20...44).allSatisfy { model.bitmap[$0, 52] } && !model.bitmap[45, 52],
                      "accelerated drawing uses the visible pointer and retains the final mouse-up segment at \(scale)x")
            let expected = window.convertPoint(toScreen: view.convert(view.viewPoint(PixelPoint(x: 124, y: 100)), to: nil))
            let actual = CGEvent(source: nil)!.location
            try check(abs(actual.x - expected.x) < 2 && abs(actual.y - ((NSScreen.screens.first?.frame.maxY ?? 0) - expected.y)) < 2,
                      "the actual system cursor matches the accelerated brush endpoint at \(scale)x")
        }
        testing.macintosh128K.mouseScaling = false; testing.macintosh128K.operationTiming = true
        testing.update128KConfiguration(); model.newDocument(); model.setOrigin(.zero)
        model.insert(Bitmap(width: 16, height: 16))
        let before = model.displayBitmap
        testing.perform("fill")
        var runLoopResponsive = false
        let responseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in runLoopResponsive = true }
        try check(testing.pending128KOperation != nil && model.displayBitmap == before, "128K fill waits before changing pixels")
        try capture(view, "128K-Wait.png")
        pump(0.6)
        responseTimer.invalidate()
        try check(runLoopResponsive && testing.pending128KOperation == nil && model.displayBitmap != before,
                  "scheduled fill finishes while the main run loop remains responsive")
        let filled = model.displayBitmap
        testing.perform("rotate"); view.keyDown(with: key(window, code: 53)); pump(0.5)
        try check(testing.pending128KOperation == nil && model.displayBitmap == filled, "Escape cancels delayed work without changing the drawing")
        model.chooseTool(.hand); model.setOrigin(PixelPoint(x: 80, y: 120))
        func hand(_ type: NSEvent.EventType, x: Int, y: Int) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(view.viewPoint(PixelPoint(x: x, y: y)), to: nil),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: hand(.leftMouseDown, x: 200, y: 150))
        view.mouseDragged(with: hand(.leftMouseDragged, x: 180, y: 130))
        view.mouseUp(with: hand(.leftMouseUp, x: 180, y: 130))
        try check(testing.pending128KOperation != nil && model.origin == PixelPoint(x: 80, y: 120),
                  "hand scrolling waits for its simulated floppy read")
        pump(0.4)
        try check(model.origin == PixelPoint(x: 100, y: 140) && model.displayBitmap == filled,
                  "delayed hand scrolling changes the viewport and preserves page pixels")
        model.insert(Bitmap())
        view.refresh()
        guard let sheet = window.attachedSheet, let content = sheet.contentView else {
            throw Verification.Failure(description: "128K memory refusal did not display its alert sheet")
        }
        try capture(content, "128K-Memory-Refusal.png")
        try check(model.displayBitmap == filled, "a real memory refusal sheet explains the rejected operation without changing the drawing")
        NSApp.endSheet(sheet); sheet.orderOut(nil)
        var staleWorkRan = false
        _ = testing.schedule128KOperation("save", label: "Saving...") { staleWorkRan = true }
        testing.modsEnabled = false; pump(1.0)
        try check(!staleWorkRan && testing.pending128KOperation == nil && view.menus.last?.title == "Style",
                  "disabling mods cancels pending work and restores original menus")
        testing.modsEnabled = true
        model.newDocument(); model.bitmap[100, 100] = true
        let url = output.appendingPathComponent("128K-RoundTrip.mac")
        try testing.writeDocument(to: url)
        let document = try MacPaintFile.decode(Data(contentsOf: url))
        try check(document.bitmap == model.displayBitmap && !model.isDirty, "128K saves and reopens the unchanged standard MacPaint file format")
        try JSONSerialization.data(withJSONObject: ["checks": checks, "count": checks.count,
            "scope": "Real 1x/2x settings panels, native mouse events, visible cursor, scheduler, cancellation and standard document output; provisional memory/timing."], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("128K.json"))
        return checks
    }
}
