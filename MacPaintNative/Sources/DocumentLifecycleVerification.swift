import AppKit

enum DocumentLifecycleVerification {
    enum Step {
        case button(String)
        case cancelFilePanel
    }

    static func model(resources: ClassicResources) throws -> [String] {
        let model = PaintModel(resources: resources)
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        var saved = Bitmap(); saved[50, 80] = true
        var patterns = resources.patterns; patterns[3] = Pattern([128, 64, 32, 16, 8, 4, 2, 1])
        model.bitmap[100, 100] = true; model.setOrigin(PixelPoint(x: 21, y: 37))
        model.toggleFatBits(at: PixelPoint(x: 200, y: 200))
        model.revert(to: MacPaintFile.Document(bitmap: saved, patterns: patterns))
        try check(model.bitmap == saved && model.patterns == patterns && !model.isDirty,
                  "named Revert restores saved pixels and patterns with clean state")
        try check(model.origin == PixelPoint(x: 21, y: 37), "named Revert retains the current scroll origin")
        try check(model.fatBits && model.fatCenter == PixelPoint(x: 200, y: 200), "named Revert retains FatBits and its center")
        model.undo(); try check(model.bitmap == saved, "Undo after Revert cannot restore discarded edits")
        model.bitmap[30, 30] = true
        model.revert(to: nil)
        try check(model.bitmap == Bitmap() && !model.isDirty, "unnamed Revert clears the drawing and dirty state")
        try check(model.patterns == patterns, "unnamed Revert retains current custom patterns as original BlankDoc does")
        try check(model.origin == PixelPoint(x: 80, y: 120) && !model.fatBits,
                  "unnamed Revert restores the original initial viewport and leaves FatBits")
        model.load(MacPaintFile.Document(bitmap: saved, patterns: nil))
        try check(model.patterns == patterns && model.bitmap == saved && !model.isDirty,
                  "opening a version-zero document retains current patterns as original ReadWrite does")
        return checks
    }

    static func run(controller: AppController, output: URL) throws -> [String] {
        let model = controller.model!, view = controller.workspace!, window = controller.window!
        let verificationDirectory = controller.verificationDirectory
        controller.verificationDirectory = nil // Exercise the production unsaved-change prompts.
        defer {
            controller.verificationDirectory = verificationDirectory
            model.newDocument(); controller.documentURL = nil
            view.documentOpen = true; view.documentTitle = "Untitled"
            window.makeKeyAndOrderFront(nil); view.refresh()
        }
        let fixtures = output.appendingPathComponent("Lifecycle", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        var checks = [String](), observedModals = [[String: String]]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func buttons(in root: NSView) -> [NSButton] {
            (root as? NSButton).map { [$0] } ?? root.subviews.flatMap { buttons(in: $0) }
        }
        func interact(_ name: String, _ steps: [Step], action: () throws -> Void) throws {
            var index = 0, previous: NSWindow?
            var deadline = Date().addingTimeInterval(10)
            let timer = Timer(timeInterval: 0.03, repeats: true) { _ in
                if Date() > deadline {
                    let files = NSApp.windows.compactMap { $0 as? NSSavePanel }.filter(\.isVisible).map {
                        ["URL": $0.url?.path ?? "nil", "directory": $0.directoryURL?.path ?? "nil", "name": $0.nameFieldStringValue]
                    }
                    fputs("VERIFICATION FAILED: \(name) waiting for modal step \(index + 1); filePanels=\(files)\n", stderr)
                    exit(1)
                }
                guard index < steps.count, let panel = NSApp.modalWindow, panel !== previous else { return }
                var fileAction: (() -> Void)?
                switch steps[index] {
                case .button(let title):
                    guard !(panel is NSSavePanel), let root = panel.contentView,
                          let button = buttons(in: root).first(where: { $0.title == title && $0.isEnabled }) else { return }
                    let location = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        NSApp.postEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!, atStart: false)
                    }
                case .cancelFilePanel:
                    guard let save = panel as? NSSavePanel else { return }
                    fileAction = { save.cancel(nil) }
                }
                observedModals.append(["scenario": name, "step": String(index + 1), "class": String(describing: type(of: panel))])
                if let root = panel.contentView, let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                    root.cacheDisplay(in: root.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("Lifecycle-\(name)-\(index).png"))
                }
                previous = panel; index += 1; deadline = Date().addingTimeInterval(10)
                if let fileAction {
                    // Record the step before a panel action can resume the
                    // caller reentrantly; wake a modal wait entered by a timer.
                    NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                        subtype: 0, data1: 0, data2: 0)!, atStart: false)
                    fileAction()
                }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            defer { timer.invalidate() }
            try action()
            try check(index == steps.count, "\(name) expected \(steps.count) native modal steps, observed \(index)")
        }
        func reset() {
            model.newDocument(); model.setOrigin(.zero); controller.documentURL = nil
            view.documentOpen = true; view.documentTitle = "Untitled"; window.makeKeyAndOrderFront(nil); view.refresh()
        }
        reset(); model.bitmap[20, 20] = true
        let saved = model.displayBitmap, file = fixtures.appendingPathComponent("Saved.mac")
        try controller.writeDocument(to: file)
        model.setOrigin(PixelPoint(x: 21, y: 37)); model.bitmap[110, 130] = true; view.refresh()
        let changed = model.displayBitmap
        try interact("Revert-Cancel", [.button("Cancel")]) { controller.perform("revert") }
        try check(model.displayBitmap == changed && model.isDirty && model.origin == PixelPoint(x: 21, y: 37),
                  "Cancel in Revert preserves every pixel, dirty state and viewport")
        try interact("Revert", [.button("Revert")]) { controller.perform("revert") }
        try check(model.displayBitmap == saved && !model.isDirty, "Revert restores the actual saved file")
        try check(model.origin == PixelPoint(x: 21, y: 37),
                  "Revert of a named document must retain viewport (21,37); actual (\(model.origin.x),\(model.origin.y))")
        reset(); model.bitmap[25, 30] = true; model.patterns[3] = .gray; view.refresh()
        let unnamed = model.displayBitmap
        try check(view.menus[1].items[5].enabled, "Revert is available for an open unnamed drawing")
        try interact("Untitled-Revert-Cancel", [.button("Cancel")]) { controller.perform("revert") }
        try check(model.displayBitmap == unnamed && model.patterns[3] == .gray && model.isDirty,
                  "Cancel preserves the unnamed drawing and its custom pattern")
        try interact("Untitled-Revert", [.button("Revert")]) { controller.perform("revert") }
        try check(model.displayBitmap == Bitmap() && model.patterns[3] == .gray && !model.isDirty && controller.documentURL == nil,
                  "confirmed unnamed Revert clears pixels, retains patterns and leaves the document unnamed")
        reset(); window.performClose(nil)
        try check(!view.documentOpen && !window.isVisible, "native close button closes a clean document and its host window")
        controller.perform("new")
        try check(view.documentOpen && window.isVisible,
                  "File New after native close must show the new drawing; documentOpen=\(view.documentOpen), visible=\(window.isVisible)")
        reset(); model.bitmap[33, 44] = true; model.patterns[4] = .gray; view.refresh()
        let unsaved = model.displayBitmap, unsavedPatterns = model.patterns
        try interact("Save-Cancel", [.cancelFilePanel]) { controller.perform("save") }
        try check(model.displayBitmap == unsaved && model.patterns == unsavedPatterns && model.isDirty && controller.documentURL == nil,
                  "Cancel in the real Save panel preserves unnamed pixels, patterns and dirty state")
        try interact("Close-Cancel", [.button("Cancel")]) { controller.perform("close") }
        try check(view.documentOpen && window.isVisible && model.displayBitmap == unsaved && model.isDirty,
                  "Cancel in the unsaved Close alert keeps the drawing open")
        var quit = NSApplication.TerminateReply.terminateNow
        try interact("Quit-Cancel", [.button("Cancel")]) { quit = controller.applicationShouldTerminate(NSApp) }
        try check(quit == .terminateCancel && view.documentOpen && model.displayBitmap == unsaved && model.isDirty,
                  "Cancel rejects native termination without discarding the drawing")
        try interact("Close-Save-Cancel", [.button("Save"), .cancelFilePanel]) { controller.perform("close") }
        try check(view.documentOpen && model.displayBitmap == unsaved && model.isDirty && controller.documentURL == nil,
                  "choosing Save then cancelling its panel cancels Close and preserves the drawing")
        try interact("Quit-Save-Cancel", [.button("Save"), .cancelFilePanel]) { quit = controller.applicationShouldTerminate(NSApp) }
        try check(quit == .terminateCancel && view.documentOpen && model.displayBitmap == unsaved && model.isDirty,
                  "Quit Save/Cancel: expected rejected termination and unchanged dirty drawing; reply=\(quit.rawValue), open=\(view.documentOpen), samePixels=\(model.displayBitmap == unsaved), dirty=\(model.isDirty), URL=\(controller.documentURL?.path ?? "nil")")
        let missing = fixtures.appendingPathComponent("missing/Failed.mac")
        controller.documentURL = missing
        try interact("Close-Save-Error", [.button("Save"), .button("OK")]) { controller.perform("close") }
        try check(view.documentOpen && model.displayBitmap == unsaved && model.isDirty && controller.documentURL == missing,
                  "save failure reports an error and cancels Close without losing pixels or filename")
        let onClose = fixtures.appendingPathComponent("Saved-On-Close.mac")
        try MacPaintFile.encode(Bitmap(), patterns: model.resources.patterns).write(to: onClose)
        controller.documentURL = onClose; view.documentTitle = "Saved-On-Close"
        try interact("Close-Save", [.button("Save")]) { controller.perform("close") }
        let closedFile = try MacPaintFile.decode(Data(contentsOf: onClose))
        try check(!view.documentOpen && closedFile.bitmap == unsaved && closedFile.patterns == unsavedPatterns,
                  "Save from the Close alert writes every pixel and pattern before closing")
        try interact("Open-Cancel", [.cancelFilePanel]) { controller.perform("open") }
        try check(!view.documentOpen && controller.documentURL == nil && model.displayBitmap == Bitmap(),
                  "Cancel in the real Open panel leaves the document closed")
        controller.perform("new"); model.bitmap[50, 50] = true
        model.patterns[3] = Pattern(model.resources.patterns[3].rows.map { ~$0 })
        let originalPatterns = model.patterns
        let original = fixtures.appendingPathComponent("Original.mac")
        try controller.writeDocument(to: original)
        let originalBytes = try Data(contentsOf: original)
        model.bitmap[60, 60] = true; view.refresh()
        let modified = model.displayBitmap
        try interact("Save-As-Cancel", [.cancelFilePanel]) { controller.perform("saveAs") }
        try check(controller.documentURL == original && model.displayBitmap == modified && model.isDirty && (try Data(contentsOf: original)) == originalBytes,
                  "Cancel in Save As preserves the original file, filename and unsaved edits")
        let corrupt = fixtures.appendingPathComponent("Corrupt.mac")
        try Data([1, 2, 3]).write(to: corrupt)
        var opened = true
        try interact("Invalid-Open", [.button("OK")]) { opened = controller.application(NSApp, openFile: corrupt.path) }
        try check(!opened && controller.documentURL == original && model.displayBitmap == modified && model.isDirty,
                  "a malformed external document reports an error without replacing unsaved work")
        controller.documentURL = corrupt; model.setOrigin(PixelPoint(x: 21, y: 37)); view.refresh()
        try interact("Revert-Error", [.button("Revert"), .button("OK")]) { controller.perform("revert") }
        try check(model.displayBitmap == modified && model.isDirty && model.origin == PixelPoint(x: 21, y: 37),
                  "failed Revert preserves pixels, dirty state and viewport")
        controller.documentURL = original
        try interact("Close-Discard", [.button("Don't Save")]) { controller.perform("close") }
        try check(!view.documentOpen && (try Data(contentsOf: original)) == originalBytes,
                  "Don't Save closes the document without altering its existing file")
        try check(model.patterns == originalPatterns,
                  "closing a document must retain its visible custom pattern palette; actual retained=\(model.patterns == originalPatterns)")
        var legacyPixels = Bitmap(); legacyPixels[70, 80] = true
        var legacyData = MacPaintFile.encode(legacyPixels, patterns: originalPatterns)
        legacyData.replaceSubrange(0..<512, with: Data(repeating: 0, count: 512))
        let legacy = fixtures.appendingPathComponent("Legacy-Version-Zero.mac")
        try legacyData.write(to: legacy)
        try check(controller.application(NSApp, openFile: legacy.path) && model.bitmap == legacyPixels && model.patterns == originalPatterns,
                  "opening an actual version-zero file after Close retains the session's custom patterns")
        window.performClose(nil)
        try check(controller.application(NSApp, openFile: original.path) && window.isVisible && view.documentOpen,
                  "opening a file after native window close makes the drawing visible")
        controller.perform("close"); controller.perform("new")
        try check(model.patterns == model.resources.patterns && model.bitmap == Bitmap() && controller.documentURL == nil,
                  "File New resets the pattern palette after Close retained it")
        model.bitmap[90, 100] = true
        let reopen = fixtures.appendingPathComponent("Reopen.mac")
        try controller.writeDocument(to: reopen)
        model.bitmap[91, 101] = true; model.patterns[3] = .gray; view.refresh()
        let latest = model.displayBitmap, latestPatterns = model.patterns
        try interact("Reopen-Save", [.button("Save")]) { opened = controller.application(NSApp, openFile: reopen.path) }
        let persisted = try MacPaintFile.decode(Data(contentsOf: reopen))
        try check(opened && model.displayBitmap == latest && model.patterns == latestPatterns && !model.isDirty,
                  "reopening after Save must display the just-saved drawing; currentMatches=\(model.displayBitmap == latest), diskMatches=\(persisted.bitmap == latest)")
        try JSONSerialization.data(withJSONObject: ["checks": checks, "count": checks.count, "modals": observedModals,
            "scope": "Actual NSAlert mouse events and NSSavePanel/NSOpenPanel cancellation via public actions; named-file saving, reopening and error preservation.",
            "manualPending": "Confirming a new filename in the system Save panel; macOS disallows programmatic NSSavePanel.ok."], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Document-Lifecycle.json"))
        return checks
    }
}
