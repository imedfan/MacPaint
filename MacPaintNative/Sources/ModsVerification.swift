import AppKit

enum ModsVerification {
    static func run(controller: AppController, output: URL) throws -> [String] {
        let domain = "org.macpaintnative.mods-verification." + UUID().uuidString
        let preferences = UserDefaults(suiteName: domain)!
        let testing = AppController(preferences: preferences)
        let view = controller.workspace!, window = controller.window!, model = controller.model!
        let originalFrame = window.frame
        testing.model = model; testing.workspace = view; testing.window = window
        view.controller = testing
        defer {
            preferences.removePersistentDomain(forName: domain)
            view.controller = controller
            window.setFrame(originalFrame, display: true)
            model.newDocument(); view.refresh()
        }
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func capture(_ content: NSView, name: String) throws {
            guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                throw Verification.Failure(description: "Cannot capture \(name)")
            }
            content.cacheDisplay(in: content.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        }
        func key(_ panel: NSWindow, code: UInt16, characters: String) {
            NSApp.postEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!, atStart: false)
        }
        func toggle(enabled: Bool, keyboard: Bool, scale: Int) throws {
            var posted = false, observed = false, closing = false, timedOut = false
            var controlFits = false, hasCheckboxRole = false
            var controlDetails = ""
            var captureError: Error?
            let deadline = Date().addingTimeInterval(4)
            let timer = Timer(timeInterval: 0.02, repeats: true) { _ in
                if Date() > deadline { timedOut = true; NSApp.abortModal(); return }
                guard let panel = NSApp.modalWindow, let dialog = panel.contentView as? ClassicDialogView,
                      dialog.kind == "about" else { return }
                dialog.layoutSubtreeIfNeeded()
                guard let button = dialog.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Enable mods" }) else { return }
                if !posted {
                    posted = true
                    let height = CGFloat(dialog.logicalRect.height)
                    controlFits = button.frame.minY >= 108 * CGFloat(scale)
                        && button.frame.maxY <= (height - 2) * CGFloat(scale)
                    hasCheckboxRole = button.accessibilityRole() == .checkBox
                    controlDetails = "frame=\(button.frame), dialog=\(dialog.bounds), role=\(String(describing: button.accessibilityRole()))"
                    if keyboard {
                        panel.makeFirstResponder(button)
                        key(panel, code: 49, characters: " ")
                    } else {
                        let location = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                            NSApp.postEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!, atStart: false)
                        }
                    }
                } else if !closing && testing.modsEnabled == enabled && button.state == (enabled ? .on : .off) {
                    observed = true; closing = true
                    do {
                        try capture(dialog, name: "Mods-About-\(enabled ? "On" : "Off")-\(scale)x.png")
                        try capture(view, name: "Mods-Workspace-\(enabled ? "On" : "Off")-\(scale)x.png")
                    } catch { captureError = error }
                    key(panel, code: keyboard ? 36 : 53, characters: keyboard ? "\r" : "\u{1b}")
                }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            testing.perform("about")
            timer.invalidate()
            if let captureError { throw captureError }
            try check(posted && observed && !timedOut,
                      "About checkbox \(enabled ? "enables" : "disables") mods with \(keyboard ? "Space" : "native mouse events") at \(scale)x; Return/Escape closes About")
            try check(controlFits && hasCheckboxRole, "Enable mods is an accessible checkbox below Native ARM64 adaptation and fits About at \(scale)x; \(controlDetails)")
        }
        model.newDocument(); model.bitmap[100, 100] = true; model.markSaved()
        let drawing = model.displayBitmap, patterns = model.patterns
        view.refresh()
        let classicTitles = view.menus.map(\.title)
        let nativeTitles = NSApp.mainMenu!.items.map(\.title)
        try check(!testing.modsEnabled && classicTitles.last == "Style" && nativeTitles.last == "Style",
                  "mods default to off and both menu bars end with Style")
        for scale in [1, 2] {
            window.setContentSize(NSSize(width: 512 * scale, height: 342 * scale)); view.refresh()
            try toggle(enabled: true, keyboard: false, scale: scale)
            try check(view.menus.map(\.title) == classicTitles + ["Mods"], "classic Mods menu is last, immediately after Style at \(scale)x")
            try check(NSApp.mainMenu!.items.map(\.title) == nativeTitles + ["Mods"], "native Mods menu is last, immediately after Style at \(scale)x")
            try check(view.menus.last!.items.allSatisfy { !$0.enabled }, "Mods empty state has no active commands before mods are added")
            let reloaded = AppController(preferences: UserDefaults(suiteName: domain)!)
            try check(reloaded.modsEnabled, "a fresh application controller restores Enable mods from its preferences")
            view.popup = view.menus.count - 1; view.popupHover = 0
            try toggle(enabled: false, keyboard: true, scale: scale)
            try check(view.popup == nil && view.popupHover == nil, "disabling mods dismisses its open classic menu at \(scale)x")
            try check(view.menus.map(\.title) == classicTitles && NSApp.mainMenu!.items.map(\.title) == nativeTitles,
                      "disabling mods restores both original menu bars at \(scale)x")
            try check(model.displayBitmap == drawing && model.patterns == patterns && !model.isDirty,
                      "toggling mods preserves drawing, patterns and clean state at \(scale)x")
            try check(!AppController(preferences: UserDefaults(suiteName: domain)!).modsEnabled, "a fresh application controller restores the disabled preference")
        }
        try JSONSerialization.data(withJSONObject: ["checks": checks, "count": checks.count,
            "scope": "Real About panel, native checkbox mouse and Space events at 1x/2x; menu order, isolated preferences and document preservation."], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Mods.json"))
        return checks
    }
}
