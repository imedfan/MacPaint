import AppKit
import UniformTypeIdentifiers

enum ClipboardError: LocalizedError {
    case invalid(String)
    case unavailable
    var errorDescription: String? {
        switch self {
        case .invalid(let detail): return "Cannot paste this picture: \(detail)"
        case .unavailable: return "Cannot write to the clipboard. Your drawing has been preserved."
        }
    }
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let preferences: UserDefaults
    let macintosh128K: Macintosh128K
    private var delayed128KOperation: Timer?
    private var operation128KGeneration = 0
    private(set) var pending128KOperation: String?
    var aiListener: AIControlListener?
    var aiTimer: Timer?
    var aiBatch: AIDrawingBatch?
    var aiDocumentID = UUID().uuidString
    var aiParkedDocuments = [AIDocumentSession]()
    var aiControlStatus = "AI control is off."
    var aiControlEnabled: Bool {
        get { preferences.bool(forKey: "aiControl.enabled") }
        set { preferences.set(newValue, forKey: "aiControl.enabled"); updateAIControl() }
    }
    var modsEnabled: Bool {
        get { preferences.bool(forKey: "modsEnabled") }
        set {
            preferences.set(newValue, forKey: "modsEnabled")
            macintosh128K.modsEnabled = newValue
            update128KConfiguration()
            updateAIControl()
            workspace?.popup = nil; workspace?.popupHover = nil
            workspace?.refresh()
        }
    }
    var window: NSWindow!
    var model: PaintModel!
    var workspace: WorkspaceView!
    var documentURL: URL?
    var verificationDirectory: URL?
    var verificationReopenURL: URL?
    var verificationRecoveryMode: String?
    var verificationAIOnly = false
    var recovery: RecoveryStore?
    private var recoveryWork: DispatchWorkItem?
    private var recoveryGeneration = 0
    private var recoveryWarningShown = false
    private let selectionType = NSPasteboard.PasteboardType("org.macpaintnative.selection")
    private let lassoType = NSPasteboard.PasteboardType("org.macpaintnative.lasso")

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        macintosh128K = Macintosh128K(preferences: preferences)
        super.init()
        macintosh128K.modsEnabled = modsEnabled
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let resourcesURL = Bundle.main.resourceURL!.appendingPathComponent("Resources")
            model = PaintModel(resources: try ClassicResources(directory: resourcesURL))
            model.macintosh128K = macintosh128K
        } catch {
            let alert = NSAlert(error: error); alert.runModal(); NSApp.terminate(nil); return
        }
        workspace = WorkspaceView(model: model); workspace.controller = self
        var recoveryError: Error?
        if verificationDirectory == nil {
            do {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                          appropriateFor: nil, create: true)
                recovery = try RecoveryStore(root: support.appendingPathComponent("MacPaint Native/Recovery", isDirectory: true))
                if let snapshot = try recovery?.takeLatestAbandoned() {
                    try snapshot.restore(into: model)
                    workspace.documentTitle = "Rescue"
                }
            } catch { recoveryError = error }
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 684),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MacPaint"
        window.isReleasedWhenClosed = false
        window.contentView = workspace; window.delegate = self
        window.contentMinSize = NSSize(width: 512, height: 342)
        window.contentResizeIncrements = NSSize(width: 512, height: 342)
        window.appearance = NSAppearance(named: .aqua)
        window.center(); refreshMenus(); window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(workspace)
        NSApp.activate(ignoringOtherApps: true)
        if verificationDirectory == nil { updateAIControl() }
        if let recoveryError { showRecoveryError(recoveryError) }
        if let verificationDirectory {
            let runVerification = { [self] in
                do {
                    if verificationAIOnly {
                        let checks = try ModsVerification.run(controller: self, output: verificationDirectory)
                            + AIControlVerification.run(controller: self, output: verificationDirectory)
                        print("\(checks.count) mods and AI control checks passed.")
                    } else if verificationRecoveryMode == "write" {
                        try RecoveryVerification.writeAndExit(controller: self, output: verificationDirectory)
                    } else if verificationRecoveryMode == "read" {
                        try RecoveryVerification.readAfterExit(controller: self, output: verificationDirectory)
                    } else if let verificationReopenURL {
                        try Verification.reopen(controller: self, document: verificationReopenURL, output: verificationDirectory)
                    } else { try Verification.run(controller: self, output: verificationDirectory) }
                    print("VERIFICATION PASSED")
                    NSApp.terminate(nil)
                } catch {
                    fputs("VERIFICATION FAILED: \(error)\n", stderr)
                    exit(1)
                }
            }
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in runVerification() }
        }
    }
    func refreshMenus() {
        guard workspace != nil else { return }
        func item(_ title: String, _ command: String, _ shortcut: String = "", _ checked: Bool = false) -> ClassicMenuItem {
            ClassicMenuItem(title: title, command: command, shortcut: shortcut, checked: checked)
        }
        workspace.menus = [
            ClassicMenu(title: String(UnicodeScalar(20)), items: [item("About MacPaint...", "about")]),
            ClassicMenu(title: "File", items: [
                item("New", "new"), item("Open...", "open"), item("Close", "close"),
                item("Save", "save"), item("Save As...", "saveAs"), item("Revert", "revert"),
                item("Print Draft", "printDraft"), item("Print Final", "printFinal"), item("Print Catalog", "printCatalog"), item("Quit", "quit")]),
            ClassicMenu(title: "Edit", items: [
                item("Undo", "undo", "⌘Z"), item("-", ""), item("Cut", "cut", "⌘X"), item("Copy", "copy", "⌘C"),
                item("Paste", "paste", "⌘V"), item("Clear", "clear"), item("-", ""), item("Invert", "invert"), item("Fill", "fill"),
                item("Trace Edges", "edges", "⌘E"), item("Flip Horizontal", "horizontal"), item("Flip Vertical", "vertical"), item("Rotate", "rotate")]),
            ClassicMenu(title: "Goodies", items: [
                item("Grid", "grid", "", model.grid), item("FatBits", "fatbits", "", model.fatBits), item("Show Page", "page"),
                item("Edit Pattern", "pattern"), item("Brush Shape", "brush"), item("Brush Mirrors", "symmetry"),
                item("Introduction", "intro"), item("Short Cuts", "shortcuts")]),
            ClassicMenu(title: "Font", items: ["Chicago", "Geneva", "New York", "Monaco", "Times", "Helvetica", "Courier"].map {
                item($0, "font:\($0)", "", model.textFont == $0)
            }),
            ClassicMenu(title: "FontSize", items: [9, 10, 12, 14, 18, 24, 36, 48, 72].map {
                item($0 == 9 ? "9 point" : String($0), "size:\($0)", "", model.textSize == $0)
            }),
            ClassicMenu(title: "Style", items: [
                item("Plain", "style:0", "⌘P", model.textStyle == 0), item("Bold", "style:1", "⌘B", model.textStyle & 1 != 0),
                item("Italic", "style:2", "⌘I", model.textStyle & 2 != 0), item("Underline", "style:4", "⌘U", model.textStyle & 4 != 0),
                item("Outline", "style:8", "⌘O", model.textStyle & 8 != 0), item("Shadow", "style:16", "⌘S", model.textStyle & 16 != 0),
                item("-", ""), item("Align Left", "align:0", "⌘L", model.textAlignment == 0),
                item("Align Middle", "align:1", "⌘M", model.textAlignment == 1), item("Align Right", "align:2", "⌘R", model.textAlignment == 2)])
        ]
        if modsEnabled {
            var commands = [item("Macintosh 128K...", "macintosh128K", "", macintosh128K.active)]
            commands += [item("AI control", "aiControl", "", aiControlEnabled), item("AI Connection...", "aiConnection")]
            if !aiParkedDocuments.isEmpty { commands.append(item("Next Document", "nextAIDocument")) }
            if aiBatch != nil { commands.append(item("Stop AI Drawing", "stopAI")) }
            if pending128KOperation != nil { commands.append(item("Cancel Operation", "cancel128K")) }
            workspace.menus.append(ClassicMenu(title: "Mods", items: commands))
        }
        workspace.menus[1].items[5].enabled = workspace.documentOpen
        workspace.menus[1].items[0].enabled = !workspace.documentOpen
        workspace.menus[1].items[1].enabled = !workspace.documentOpen
        let selected = model.selection != nil
        for index in [2, 3, 5, 7, 8] { workspace.menus[2].items[index].enabled = selected }
        for index in 9...12 { workspace.menus[2].items[index].enabled = selected && model.selection?.isLasso == false }
        workspace.menus[2].items[4].enabled = workspace.documentOpen
        for index in [2, 6, 7] { workspace.menus[3].items[index].enabled = workspace.documentOpen }
        if selected && model.selection?.textScrap == nil {
            for menu in 4...6 { for index in workspace.menus[menu].items.indices { workspace.menus[menu].items[index].enabled = false } }
        }
        if !workspace.documentOpen {
            for index in 2...8 { workspace.menus[1].items[index].enabled = false }
            for index in workspace.menus[2].items.indices { workspace.menus[2].items[index].enabled = false }
        }
        workspace.menus[2].items[0].enabled = model.undoState != nil
        if workspace.pageOverview {
            for menu in workspace.menus.indices {
                for item in workspace.menus[menu].items.indices { workspace.menus[menu].items[item].enabled = false }
            }
        }
        if pending128KOperation != nil {
            for menu in workspace.menus.indices {
                for item in workspace.menus[menu].items.indices {
                    workspace.menus[menu].items[item].enabled = workspace.menus[menu].items[item].command == "cancel128K"
                }
            }
        }
        if aiBatch != nil {
            for menu in workspace.menus.indices {
                for item in workspace.menus[menu].items.indices {
                    workspace.menus[menu].items[item].enabled = ["stopAI", "aiControl"].contains(workspace.menus[menu].items[item].command)
                }
            }
        }
        // Native menus also expose keyboard commands and accessibility to macOS.
        let bar = NSMenu()
        for (index, classic) in workspace.menus.enumerated() {
            let parent = NSMenuItem(title: index == 0 ? "MacPaint" : classic.title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: parent.title)
            for item in classic.items {
                if item.isSeparator { menu.addItem(.separator()); continue }
                let shortcut: String = item.shortcut.hasPrefix("⌘") ? String(item.shortcut.dropFirst()).lowercased() : ""
                let native = NSMenuItem(title: item.title, action: #selector(menuAction(_:)), keyEquivalent: shortcut)
                native.target = self; native.representedObject = item.command
                native.state = item.checked ? .on : .off; native.isEnabled = item.enabled
                menu.addItem(native)
            }
            menu.autoenablesItems = false; parent.submenu = menu; bar.addItem(parent)
        }
        NSApp.mainMenu = bar
    }
    @objc private func menuAction(_ sender: NSMenuItem) {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        if let command = sender.representedObject as? String { perform(command, modifiers: flags.contains(.shift) ? .shift : []) }
    }
    func perform(_ command: String, modifiers: PaintModifiers = []) {
        if command == "stopAI" { cancelAIDrawing(); return }
        if command == "aiControl", modsEnabled { aiControlEnabled.toggle(); return }
        guard aiBatch == nil else { return }
        guard !workspace.pageOverview else { return }
        if command == "cancel128K" { cancel128KOperation(); return }
        guard pending128KOperation == nil else { return }
        if schedule128KOperation(command, label: command == "saveAs" ? "Saving..." : command.capitalized + "...",
                                action: { [weak self] in self?.performImmediately(command, modifiers: modifiers) }) { return }
        performImmediately(command, modifiers: modifiers)
    }
    private func performImmediately(_ command: String, modifiers: PaintModifiers) {
        do {
            switch command {
            case "nextAIDocument":
                if modsEnabled, let next = aiParkedDocuments.first { switchAIDocument(to: next.id) }
            case "aiConnection": if modsEnabled { showAIConnection() }
            case "macintosh128K": if modsEnabled { show128KPanel() }
            case "new":
                if shouldDiscard() {
                    model.newDocument(); documentURL = nil; workspace.documentTitle = "Untitled"; workspace.documentOpen = true
                    window.makeKeyAndOrderFront(nil)
                }
            case "open": try openDocument()
            case "close": if shouldDiscard() { closeCurrentDocument() }
            case "save": _ = try saveDocument(choose: false)
            case "saveAs": _ = try saveDocument(choose: true)
            case "revert": try revertDocument()
            case "quit": NSApp.terminate(nil)
            case "undo": model.undo()
            case "clear", "invert", "fill", "edges", "horizontal", "vertical", "rotate": model.editSelection(command, modifiers: modifiers)
            case "copy": try copySelection(cut: false)
            case "cut": try copySelection(cut: true)
            case "paste": try pasteSelection()
            case "grid": model.grid.toggle()
            case "fatbits": model.toggleFatBits()
            case "page": workspace.pageOverview = true
            case "intro": workspace.helpID = 2400
            case "shortcuts": workspace.helpID = 2401
            case "brush", "pattern", "symmetry", "about": showDialog(command)
            case "printDraft", "printFinal": printDocument(final: command == "printFinal")
            case "printCatalog": try printCatalog()
            default:
                if command.hasPrefix("font:") { model.textFont = String(command.dropFirst(5)); model.updateText(model.text) }
                if command.hasPrefix("size:"), let size = Int(command.dropFirst(5)) { model.textSize = size; model.updateText(model.text) }
                if command.hasPrefix("style:"), let style = Int(command.dropFirst(6)) {
                    model.textStyle = style == 0 ? 0 : model.textStyle ^ style; model.updateText(model.text)
                }
                if command.hasPrefix("align:"), let align = Int(command.dropFirst(6)) { model.textAlignment = align; model.updateText(model.text) }
            }
        } catch { NSAlert(error: error).runModal() }
        workspace.refresh()
    }
    func update128KConfiguration() {
        model?.macintosh128K = macintosh128K
        model?.memoryRefusal = nil
        cancel128KOperation()
        workspace?.reset128KMouse()
        workspace?.refresh()
    }
    @discardableResult func schedule128KOperation(_ command: String, label: String, action: @escaping () -> Void) -> Bool {
        guard macintosh128K.delay(for: command) > 0 else { return false }
        guard pending128KOperation == nil else { return true }
        operation128KGeneration += 1
        let generation = operation128KGeneration
        pending128KOperation = label
        let work = Timer(timeInterval: macintosh128K.delay(for: command), repeats: false) { [weak self] _ in
            guard let self, self.operation128KGeneration == generation else { return }
            self.delayed128KOperation = nil; self.pending128KOperation = nil
            action()
            self.workspace?.refresh()
        }
        delayed128KOperation = work
        RunLoop.main.add(work, forMode: .common)
        workspace?.reset128KMouse(); workspace?.refresh()
        return true
    }
    func cancel128KOperation() {
        delayed128KOperation?.invalidate(); delayed128KOperation = nil
        operation128KGeneration += 1; pending128KOperation = nil
        workspace?.refresh()
    }
    func show128KMemoryRefusal() {
        guard let message = model.memoryRefusal, window.attachedSheet == nil else { return }
        model.memoryRefusal = nil
        workspace.reset128KMouse()
        let alert = NSAlert(); alert.messageText = "Macintosh 128K: Not enough memory"
        alert.informativeText = message
        alert.beginSheetModal(for: window)
    }
    private func show128KPanel() {
        workspace.reset128KMouse()
        let size = workspace.viewPoint(PixelPoint(x: 1, y: 1)).x - workspace.viewPoint(.zero).x
        let content = Macintosh128KPanel(profile: macintosh128K, model: model, scale: size) { [weak self] in
            self?.update128KConfiguration()
        }
        let panel = ClassicPanel(contentRect: NSRect(origin: .zero, size: content.frame.size),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "Macintosh 128K"; panel.contentView = content; content.panel = panel
        let origin = workspace.viewPoint(PixelPoint(x: 56, y: 39))
        panel.setFrameTopLeftPoint(window.convertPoint(toScreen: workspace.convert(origin, to: nil)))
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(content)
        NSApp.runModal(for: panel); panel.orderOut(nil)
    }
    func windowDidResignKey(_ notification: Notification) {
        workspace?.reset128KMouse()
    }
    func shouldDiscard() -> Bool {
        guard let model, workspace != nil else { return true }
        guard model.isDirty, verificationDirectory == nil else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(workspace.documentTitle)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do { return try saveDocument(choose: false) } catch { NSAlert(error: error).runModal(); return false }
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    private func openDocument() throws {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.data]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let document = try documentForOpening(at: url) else { return }
        model.load(document); documentURL = url; workspace.documentTitle = url.deletingPathExtension().lastPathComponent
        workspace.documentOpen = true
        workspace.helpID = nil; workspace.pageOverview = false
        window.makeKeyAndOrderFront(nil)
    }
    private func documentForOpening(at url: URL) throws -> MacPaintFile.Document? {
        let document = try MacPaintFile.decode(Data(contentsOf: url))
        let hadUnsavedChanges = model.isDirty
        guard shouldDiscard() else { return nil }
        // Save may have just replaced the file being opened. Validate first
        // to preserve work on bad input, then read again after that prompt.
        return hadUnsavedChanges ? try MacPaintFile.decode(Data(contentsOf: url)) : document
    }
    @discardableResult func saveDocument(choose: Bool) throws -> Bool {
        model.commitText(); model.finishPolygon(); model.acceptSelection()
        var url = documentURL
        if choose || url == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "mac") ?? .data]
            panel.nameFieldStringValue = documentURL?.lastPathComponent ?? workspace.documentTitle + ".mac"
            guard panel.runModal() == .OK, let chosen = panel.url else { return false }
            url = chosen
        }
        guard let url else { return false }
        try writeDocument(to: url)
        return true
    }
    func writeDocument(to url: URL, overwrite: Bool = true) throws {
        let data = MacPaintFile.encode(model.displayBitmap, patterns: model.patterns)
        try data.write(to: url, options: overwrite ? .atomic : .withoutOverwriting)
        documentURL = url; model.markSaved(); workspace.documentTitle = url.deletingPathExtension().lastPathComponent
        flushRecovery()
        try? FileManager.default.setAttributes([.hfsTypeCode: 0x504E5447, .hfsCreatorCode: 0x4D504E54], ofItemAtPath: url.path)
    }
    private func revertDocument() throws {
        guard workspace.documentOpen else { return }
        let alert = NSAlert(); alert.messageText = "Revert to the last saved version?"
        alert.addButton(withTitle: "Revert"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let document = try documentURL.map { try MacPaintFile.decode(Data(contentsOf: $0)) }
        model.revert(to: document)
    }
    private func closeCurrentDocument() {
        if let next = aiParkedDocuments.first {
            let closingRecovery = recovery
            // The confirmed current drawing is closed, rather than parked again.
            workspace.documentOpen = false
            switchAIDocument(to: next.id)
            do { try closingRecovery?.close() } catch { showRecoveryError(error) }
            return
        }
        let patterns = model.patterns
        workspace.documentOpen = false; model.newDocument(); model.patterns = patterns; model.markSaved(); documentURL = nil
        aiDocumentID = UUID().uuidString
        workspace.helpID = nil; workspace.pageOverview = false
        flushRecovery()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelAIDrawing()
        guard !workspace.pageOverview else { return false }
        cancel128KOperation()
        guard shouldDiscard() else { return false }
        closeCurrentDocument(); return !workspace.documentOpen
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cancelAIDrawing()
        guard !workspace.pageOverview else { return .terminateCancel }
        cancel128KOperation()
        let originalID = aiDocumentID
        let documentIDs = (workspace.documentOpen ? [aiDocumentID] : []) + aiParkedDocuments.map(\.id)
        for id in documentIDs {
            switchAIDocument(to: id)
            guard shouldDiscard() else { switchAIDocument(to: originalID); return .terminateCancel }
        }
        recoveryWork?.cancel(); recoveryGeneration += 1
        do {
            try recovery?.close()
            for document in aiParkedDocuments { try document.recovery?.close() }
        }
        catch { showRecoveryError(error); return .terminateCancel }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { aiListener?.stop() }
    func applicationWillResignActive(_ notification: Notification) { flushRecovery() }
    func scheduleRecovery() {
        guard recovery != nil else { return }
        recoveryWork?.cancel(); recoveryGeneration += 1
        if !model.isDirty || !workspace.documentOpen { flushRecovery(); return }
        let generation = recoveryGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.recoveryGeneration else { return }
            self.flushRecovery()
        }
        recoveryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    func flushRecovery() {
        guard let recovery, let model, let workspace else { return }
        recoveryWork?.cancel(); recoveryWork = nil; recoveryGeneration += 1
        do {
            if workspace.documentOpen && model.isDirty { try recovery.write(RecoverySnapshot(model: model, title: workspace.documentTitle)) }
            else { try recovery.clear() }
        } catch { showRecoveryError(error) }
    }
    private func showRecoveryError(_ error: Error) {
        guard !recoveryWarningShown else { return }
        recoveryWarningShown = true
        let alert = NSAlert()
        alert.messageText = "MacPaint could not update its recovery file."
        alert.informativeText = error.localizedDescription + "\nYour drawing is still open. Use File > Save to keep a copy."
        alert.runModal()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil); return true
    }
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        guard model != nil, !workspace.pageOverview else { return false }
        do {
            let url = URL(fileURLWithPath: filename)
            guard let document = try documentForOpening(at: url) else { return false }
            model.load(document); documentURL = url; workspace.documentTitle = url.deletingPathExtension().lastPathComponent
            workspace.documentOpen = true
            workspace.refresh(); window.makeKeyAndOrderFront(nil); return true
        } catch { NSAlert(error: error).runModal(); return false }
    }
    func copySelection(cut: Bool, pasteboard: NSPasteboard = .general) throws {
        guard let selected = model.selection else { return }
        let bitmap = selected.pixels, mask = selected.mask
        var bytes = [UInt8(bitmap.width >> 8), UInt8(bitmap.width & 255), UInt8(bitmap.height >> 8), UInt8(bitmap.height & 255)]
        bytes.append(contentsOf: bitmap.bytes); bytes.append(contentsOf: mask.bytes)
        var exported = Bitmap(width: bitmap.width, height: bitmap.height)
        exported.copy(bitmap, at: .zero, mask: mask)
        let png = NSBitmapImageRep(cgImage: exported.cgImage()).representation(using: .png, properties: [:])!
        let item = NSPasteboardItem()
        item.setData(Data(bytes), forType: selectionType); item.setData(png, forType: .png)
        if selected.isLasso { item.setData(Data([1]), forType: lassoType) }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw ClipboardError.unavailable }
        if cut { model.editSelection("clear") }
    }
    func pasteSelection(pasteboard: NSPasteboard = .general) throws {
        guard workspace.documentOpen else { return }
        if let data = pasteboard.data(forType: selectionType) {
            let bytes = Array(data)
            guard bytes.count >= 4 else { throw ClipboardError.invalid("missing bitmap dimensions") }
            let width = Int(bytes[0]) * 256 + Int(bytes[1]), height = Int(bytes[2]) * 256 + Int(bytes[3])
            guard width > 0, height > 0, width <= 576, height <= 720 else { throw ClipboardError.invalid("invalid bitmap dimensions") }
            guard model.allowVirtualMemory("Paste picture", additional: ((width + 7) / 8) * height * 2) else { return }
            var bitmap = Bitmap(width: width, height: height), mask = bitmap
            guard bytes.count == 4 + bitmap.bytes.count * 2 else { throw ClipboardError.invalid("incomplete bitmap or mask") }
            bitmap.bytes = Array(bytes[4..<(4 + bitmap.bytes.count)]); mask.bytes = Array(bytes[(4 + bitmap.bytes.count)...])
            model.insert(bitmap, mask: mask, isLasso: pasteboard.data(forType: lassoType) == Data([1]))
        } else if let image = NSImage(pasteboard: pasteboard), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cg)
            let width = rep.pixelsWide, height = rep.pixelsHigh
            guard width > 0, height > 0, width <= 16384, height <= 16384, width <= 16_777_216 / height else {
                throw ClipboardError.invalid("picture dimensions are too large")
            }
            guard model.allowVirtualMemory("Paste picture", additional: ((width + 7) / 8) * height * 2) else { return }
            var bitmap = Bitmap(width: width, height: height)
            for y in 0..<height { for x in 0..<width {
                let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? .white
                let luminance = color.redComponent * 0.299 + color.greenComponent * 0.587 + color.blueComponent * 0.114
                bitmap[x, y] = luminance < 0.5 && color.alphaComponent > 0.5
            } }
            model.insert(bitmap)
        } else if let string = pasteboard.string(forType: .string), !string.isEmpty {
            guard let data = string.data(using: .macOSRoman, allowLossyConversion: true), data.count <= 32767 else {
                throw ClipboardError.invalid("text exceeds the original 32767-byte TextEdit limit or cannot use Macintosh encoding")
            }
            model.insertText(String(data: data, encoding: .macOSRoman)!)
        }
    }
    private func printDocument(final: Bool) {
        model.acceptEdits()
        let view = PrintBitmapView(bitmap: final ? PrintRaster.final(model.bitmap) : model.bitmap,
                                   logicalSize: NSSize(width: 576, height: 720))
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit; info.verticalPagination = .fit; info.isHorizontallyCentered = true
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.run()
    }
    private func printCatalog() throws {
        model.acceptEdits()
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let catalog = try PaintCatalog.load(directory: url, resources: model.resources)
        guard catalog.pageCount > 0 else { return }
        catalogPrintOperation(catalog).run()
    }
    func catalogPrintOperation(_ catalog: PaintCatalog) -> NSPrintOperation {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit; info.verticalPagination = .fit
        info.isHorizontallyCentered = true; info.isVerticallyCentered = true
        return NSPrintOperation(view: CatalogPrintView(catalog: catalog), printInfo: info)
    }
    private func showDialog(_ kind: String) {
        model.commitText(); model.acceptSelection()
        let dialog = ClassicDialogView(model: model, kind: kind, modsEnabled: modsEnabled) { [weak self] enabled in
            self?.modsEnabled = enabled
        }
        let rect = dialog.logicalRect
        let topLeft = workspace.viewPoint(PixelPoint(x: rect.x, y: rect.y))
        let bottomRight = workspace.viewPoint(PixelPoint(x: rect.right, y: rect.bottom))
        dialog.setFrameSize(NSSize(width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y))
        let panel = ClassicPanel(contentRect: NSRect(x: 0, y: 0, width: dialog.frame.width, height: dialog.frame.height),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = kind == "about" ? "About MacPaint" : kind == "brush" ? "Brush Shape" : kind == "pattern" ? "Edit Pattern" : "Brush Mirrors"
        panel.contentView = dialog; dialog.panel = panel
        let application = NSApp as! PaintApplication
        if kind == "pattern" {
            application.modalEventFilter = { [weak dialog, weak workspace] event in
                guard event.type == .leftMouseDown, let dialog, let workspace else { return false }
                return dialog.samplePattern(from: workspace, event: event)
            }
        }
        defer { if kind == "pattern" { application.modalEventFilter = nil } }
        panel.setFrameTopLeftPoint(window.convertPoint(toScreen: workspace.convert(topLeft, to: nil)))
        panel.makeKeyAndOrderFront(nil); NSApp.runModal(for: panel); panel.orderOut(nil)
    }
}

final class PrintBitmapView: NSView {
    let bitmap: Bitmap
    init(bitmap: Bitmap, logicalSize: NSSize? = nil) {
        self.bitmap = bitmap
        super.init(frame: NSRect(origin: .zero, size: logicalSize ?? NSSize(width: bitmap.width, height: bitmap.height)))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: bitmap.cgImage(), size: frame.size).draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
}

