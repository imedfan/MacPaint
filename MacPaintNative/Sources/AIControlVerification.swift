import AppKit

enum AIControlVerification {
    static func run(controller: AppController, output: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let domain = "org.macpaintnative.ai-verification." + UUID().uuidString
        let preferences = UserDefaults(suiteName: domain)!
        let testing = AppController(preferences: preferences)
        let view = controller.workspace!, window = controller.window!, model = controller.model!
        let frame = window.frame
        let windowDelegate = window.delegate
        testing.model = model; testing.workspace = view; testing.window = window; testing.verificationDirectory = output
        view.controller = testing; window.delegate = testing; model.macintosh128K = testing.macintosh128K
        defer {
            testing.modsEnabled = false
            preferences.removePersistentDomain(forName: domain)
            view.controller = controller; model.macintosh128K = controller.macintosh128K
            window.delegate = windowDelegate
            view.model = model
            window.setFrame(frame, display: true); model.newDocument(); view.refresh()
        }
        var checks = [String]()
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { throw Verification.Failure(description: message) }
            checks.append(message)
        }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MacPaintMCP")
        func rpc(_ method: String, params: [String: Any] = [:]) throws -> [String: Any] {
            let process = Process(), input = Pipe(), outputPipe = Pipe(), errors = Pipe()
            process.executableURL = helper; process.arguments = ["--socket", testing.aiSocketPath]
            process.standardInput = input; process.standardOutput = outputPipe; process.standardError = errors
            try process.run()
            var received: Data?, diagnostic = Data()
            DispatchQueue.global(qos: .userInitiated).async {
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let error = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                DispatchQueue.main.async { received = data; diagnostic = error }
            }
            var request = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 7, "method": method, "params": params])
            request.append(10); input.fileHandleForWriting.write(request); try input.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(20)
            while received == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            guard let data = received else { process.terminate(); throw Verification.Failure(description: "MCP helper timed out: \(method) \(params["name"] ?? "")") }
            guard process.terminationStatus == 0, diagnostic.isEmpty,
                  let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = response["result"] as? [String: Any] else {
                throw Verification.Failure(description: "MCP helper response: \(String(data: data, encoding: .utf8) ?? "invalid"); \(String(data: diagnostic, encoding: .utf8) ?? "")")
            }
            return result
        }
        func call(_ name: String, _ arguments: [String: Any] = [:], error expectedError: Bool = false) throws -> [String: Any] {
            let result = try rpc("tools/call", params: ["name": name, "arguments": arguments])
            guard (result["isError"] as? Bool ?? false) == expectedError else {
                throw Verification.Failure(description: "Unexpected \(name) response: \(result)")
            }
            return result
        }
        func text(_ result: [String: Any]) -> [String: Any] {
            let content = result["content"] as! [[String: Any]]
            return try! JSONSerialization.jsonObject(with: (content[0]["text"] as! String).data(using: .utf8)!) as! [String: Any]
        }
        func canvas() throws -> [String: Any] {
            let result = try call("get_canvas")
            let content = result["content"] as! [[String: Any]]
            let png = Data(base64Encoded: content[1]["data"] as! String)!
            let image = NSBitmapImageRep(data: png)!
            guard image.pixelsWide == 576 && image.pixelsHigh == 720 else { throw Verification.Failure(description: "MCP canvas PNG dimensions") }
            let displayed = model.displayBitmap
            for y in stride(from: 0, to: 720, by: 7) { for x in stride(from: 0, to: 576, by: 7) {
                let black = image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent < 0.5
                guard black == displayed[x, y] else { throw Verification.Failure(description: "MCP PNG differs from document at \(x),\(y)") }
            } }
            try png.write(to: output.appendingPathComponent("AI-Canvas.png"))
            return text(result)
        }
        let house: [[String: Any]] = [
            ["type": "rectangle", "x": 160, "y": 210, "width": 180, "height": 140, "line_width": 2],
            ["type": "polygon", "points": [["x": 145, "y": 210], ["x": 250, "y": 145], ["x": 355, "y": 210]]],
            ["type": "rectangle", "x": 290, "y": 150, "width": 18, "height": 32],
            ["type": "rectangle", "x": 180, "y": 235, "width": 32, "height": 32],
            ["type": "rectangle", "x": 285, "y": 235, "width": 32, "height": 32],
            ["type": "rectangle", "x": 236, "y": 285, "width": 30, "height": 65],
            ["type": "line", "points": [["x": 405, "y": 260], ["x": 405, "y": 350]], "line_width": 4],
            ["type": "oval", "x": 370, "y": 195, "width": 70, "height": 85, "filled": true, "color": "gray"],
            ["type": "stroke", "points": [["x": 299, "y": 140], ["x": 292, "y": 127], ["x": 303, "y": 115]]],
            ["type": "text", "x": 220, "y": 365, "text": "HOME", "size": 18],
            ["type": "fill", "x": 240, "y": 300, "color": "gray"]
        ]
        let info = try rpc("initialize", params: ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "verification", "version": "1"]])
        try check(info["protocolVersion"] as? String == "2025-11-25", "Bundled helper negotiates MCP over clean STDIO without opening another window")
        let list = try rpc("tools/list")
        let toolNames = ["get_canvas", "draw_batch", "undo", "new_document", "open_document", "save_document", "save_as", "export_png", "list_documents", "switch_document"]
        try check((list["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } == toolNames, "All ten MCP tools are discoverable while AI control is off")
        _ = try call("get_canvas", error: true)
        for name in toolNames.dropFirst(3) { _ = try call(name, error: true) }
        try check(!testing.modsEnabled && !testing.aiControlEnabled && testing.aiListener == nil, "AI control defaults off and denies access")
        testing.modsEnabled = true; testing.perform("aiControl")
        try check(testing.aiListener != nil && testing.aiControlActive, "Mods command starts the real local AI listener")
        try check(AppController(preferences: UserDefaults(suiteName: domain)!).aiControlEnabled, "AI control preference is restored by a fresh controller")
        var reference: Bitmap?
        for scale in [1, 2] {
            model.newDocument(); model.setOrigin(scale == 1 ? .zero : PixelPoint(x: 160, y: 300))
            window.setContentSize(NSSize(width: 512 * scale, height: 342 * scale)); view.refresh()
            let result = try call("draw_batch", ["actions": house])
            try check(text(result)["applied"] as? Int == house.count && model.isDirty, "House with windows, tree, text and fill draws through helper at \(scale)x")
            try check(model.bitmap[160, 210] && !model.bitmap[200, 220] && model.bitmap[405, 340], "House has expected border, white interior and tree trunk pixels")
            if let reference { try check(model.displayBitmap == reference, "1x and 2x after scrolling produce identical page pixels") }
            else { reference = model.displayBitmap }
            let state = try canvas()
            try check(state["width"] as? Int == 576 && state["height"] as? Int == 720 && state["dirty"] as? Bool == true,
                      "MCP PNG matches displayed document pixels and reports state at \(scale)x")
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("AI-Workspace-\(scale)x.png"))
            }
            let before = model.displayBitmap
            _ = try call("draw_batch", ["actions": [["type": "rectangle", "x": 177, "y": 232, "width": 45, "height": 45, "filled": true, "color": "white"],
                                                    ["type": "rectangle", "x": 177, "y": 232, "width": 45, "height": 45]]])
            try check(model.displayBitmap != before && model.bitmap[221, 240], "Follow-up enlarges a window using document pixels at \(scale)x")
            _ = try call("undo")
            try check(model.displayBitmap == before, "One MCP Undo restores the whole window-change batch at \(scale)x")
        }
        let baseline = model.displayBitmap
        _ = try call("draw_batch", ["actions": [house[0], ["type": "line", "points": [["x": 10, "y": 10], ["x": 900, "y": 20]]]]], error: true)
        try check(model.displayBitmap == baseline, "Invalid final action rejects the entire batch before any drawing")
        model.fatBits = true
        _ = try call("draw_batch", ["actions": [["type": "line", "points": [["x": 2, "y": 700], ["x": 20, "y": 700]]]]])
        try check(model.bitmap[10, 700], "AI can draw beyond the visible FatBits viewport")
        _ = try call("undo"); model.fatBits = false
        let saveURL = output.appendingPathComponent("AI-RoundTrip.mac")
        try testing.writeDocument(to: saveURL)
        let reloaded = PaintModel(resources: model.resources); reloaded.load(try MacPaintFile.decode(Data(contentsOf: saveURL)))
        try check(reloaded.displayBitmap == baseline && !model.isDirty, "AI drawing saves and reopens as an ordinary MacPaint document")
        testing.macintosh128K.enabled = true; testing.macintosh128K.operationTiming = false; testing.update128KConfiguration()
        _ = try call("draw_batch", ["actions": [["type": "line", "points": [["x": 1, "y": 1], ["x": 10, "y": 1]]]]])
        try check(model.bitmap[5, 1], "Small AI commands fit the 128K virtual heap")
        _ = try call("undo")
        _ = try call("draw_batch", ["actions": [["type": "fill", "x": 0, "y": 0]]], error: true)
        try check(model.displayBitmap == baseline, "128K refuses a page flood-fill scratch buffer without changing the drawing")
        testing.macintosh128K.enabled = false; testing.update128KConfiguration()
        for stop in ["button", "control", "mods"] {
            model.newDocument()
            var fired = false
            let timer = Timer(timeInterval: 0.005, repeats: true) { timer in
                guard !fired, let batch = testing.aiBatch, batch.applied > 0 else { return }
                fired = true; timer.invalidate()
                if stop == "mods" { testing.modsEnabled = false }
                else if stop == "control" { testing.perform("aiControl") }
                else {
                    let location = view.convert(view.viewPoint(PixelPoint(x: 250, y: 195)), to: nil)
                    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    view.mouseDown(with: event)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            let result = try call("draw_batch", ["actions": Array(repeating: house[0], count: 100)])
            timer.invalidate()
            let state = text(result)
            try check(fired && state["cancelled"] as? Bool == true && (state["applied"] as? Int ?? 100) < 100 && testing.aiBatch == nil,
                      "Stopping via \(stop) cancels between actions and preserves a valid partial drawing")
            if stop != "button" { _ = try call("get_canvas", error: true) }
            testing.modsEnabled = true; testing.aiControlEnabled = true
            _ = try call("undo")
            try check(model.displayBitmap == Bitmap(), "Cancelled batch remains one Undo step after \(stop)")
        }
        // Exercise document tools through the same bundled helper and live window.
        let originalID = testing.aiDocumentID, originalURL = testing.documentURL, originalTitle = view.documentTitle
        let documents = output.appendingPathComponent("MCP Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        testing.recovery = try RecoveryStore(root: documents.appendingPathComponent("Recovery", isDirectory: true))
        defer {
            try? testing.recovery?.close()
            for document in testing.aiParkedDocuments { try? document.recovery?.close() }
            testing.recovery = nil
            testing.aiParkedDocuments = []; testing.aiDocumentID = originalID
            testing.model = model; view.model = model; testing.documentURL = originalURL
            view.documentTitle = originalTitle; view.documentOpen = true
        }
        func state() throws -> [String: Any] { text(try call("get_canvas")) }
        func entries() throws -> [[String: Any]] { text(try call("list_documents"))["documents"] as! [[String: Any]] }
        func mark(_ x: Int, _ y: Int) throws {
            _ = try call("draw_batch", ["actions": [["type": "rectangle", "x": x, "y": y, "width": 7, "height": 9, "filled": true]]])
        }
        for scale in [1, 2] {
            window.setContentSize(NSSize(width: 512 * scale, height: 342 * scale)); view.refresh()
            model.newDocument(); model.setOrigin(PixelPoint(x: 19, y: 31)); model.fatBits = true
            model.patterns[3] = .gray
            try mark(50, 70)
            let originalPixels = model.displayBitmap, originalPatterns = model.patterns
            let beforeCount = try entries().count
            let created = text(try call("new_document")), newID = text(try call("get_canvas"))["document_id"] as! String
            try check(created["document_id"] as? String == newID && testing.model !== model && view.model === testing.model
                      && testing.model.bitmap == Bitmap() && !testing.model.isDirty && testing.documentURL == nil,
                      "new_document opens a clean independent model in the real workspace at \(scale)x")
            try check(try entries().count == beforeCount + 1, "list_documents includes both documents at \(scale)x")
            let parked = testing.aiParkedDocuments.first(where: { $0.id == originalID })!
            let snapshotData = try Data(contentsOf: parked.recovery!.session.appendingPathComponent("Snapshot.plist"))
            let snapshot = try PropertyListDecoder().decode(RecoverySnapshot.self, from: snapshotData)
            let recovered = PaintModel(resources: model.resources); try snapshot.restore(into: recovered)
            try check(recovered.bitmap == originalPixels && recovered.patterns == originalPatterns && recovered.isDirty,
                      "Parking a dirty document writes its own recoverable pixels, palette and unsaved baseline at \(scale)x")
            try mark(120, 150)
            let pixels = testing.model.displayBitmap
            _ = try call("save_document", error: true)
            let mac = documents.appendingPathComponent("Drawing \(scale)x.mac"), png = documents.appendingPathComponent("Drawing \(scale)x.png")
            try? FileManager.default.removeItem(at: mac); try? FileManager.default.removeItem(at: png)
            _ = try call("save_as", ["path": documents.appendingPathComponent("missing/Failed.mac").path], error: true)
            try check(testing.documentURL == nil && testing.model.isDirty && testing.model.displayBitmap == pixels,
                      "failed save preserves unnamed document, pixels and dirty state at \(scale)x")
            let canonicalMacPath = URL(fileURLWithPath: mac.path).standardizedFileURL.resolvingSymlinksInPath().path
            _ = try call("save_as", ["path": mac.path])
            let decoded = try MacPaintFile.decode(Data(contentsOf: mac)), saved = try state()
            try check(decoded.bitmap == pixels && decoded.patterns == testing.model.patterns && !testing.model.isDirty
                      && saved["document_path"] as? String == canonicalMacPath && saved["document_title"] as? String == "Drawing \(scale)x",
                      "save_as writes real MacPaint pixels and patterns, adopts title/path and clears dirty at \(scale)x")
            _ = try call("save_as", ["path": mac.path], error: true)
            try mark(180, 220)
            _ = try call("save_document")
            let updated = try MacPaintFile.decode(Data(contentsOf: mac))
            try check(updated.bitmap[180, 220] && updated.bitmap[120, 150] && !testing.model.isDirty,
                      "save_document without path updates the named file at \(scale)x")
            try mark(240, 280)
            let beforeExport = try state()
            _ = try call("export_png", ["path": png.path])
            let exported = NSBitmapImageRep(data: try Data(contentsOf: png))!
            try check(exported.pixelsWide == 576 && exported.pixelsHigh == 720
                      && exported.colorAt(x: 240, y: 280)!.usingColorSpace(.deviceRGB)!.redComponent < 0.5
                      && exported.colorAt(x: 239, y: 280)!.usingColorSpace(.deviceRGB)!.redComponent > 0.5,
                      "export_png writes the full page with black and white expected pixels at \(scale)x")
            try check(try NSDictionary(dictionary: beforeExport).isEqual(to: state()), "export_png preserves filename, dirty state, Undo and canvas hash at \(scale)x")
            _ = try call("export_png", ["path": png.path], error: true)
            _ = try call("export_png", ["path": png.path, "overwrite": true])
            _ = try call("export_png", ["path": mac.path, "overwrite": true], error: true)
            _ = try call("switch_document", ["document_id": originalID])
            try check(testing.model === model && model.displayBitmap == originalPixels && model.patterns == originalPatterns
                      && model.origin == PixelPoint(x: 19, y: 31) && model.fatBits && model.isDirty,
                      "switch_document restores original pixels, patterns, viewport and dirty state at \(scale)x")
            _ = try call("undo")
            try check(model.displayBitmap == Bitmap(), "switch_document preserves the original document's own Undo at \(scale)x")
            _ = try call("undo")
            _ = try call("save_as", ["path": mac.path, "overwrite": true], error: true)
            _ = try call("export_png", ["path": mac.path, "overwrite": true], error: true)
            _ = try call("open_document", ["path": mac.path])
            try check(testing.aiDocumentID == newID && testing.model.bitmap[240, 280] && testing.model.isDirty,
                      "opening an already open file activates it without replacing unsaved edits at \(scale)x")
            // Close the temporary document through the public File command, returning to the original.
            if scale == 1 { window.performClose(nil) } else { testing.perform("close") }
            try check(testing.aiDocumentID == originalID && testing.model === model && window.isVisible,
                      "File/native window Close returns to the remaining visible document at \(scale)x")
        }
        var fixture = Bitmap(); fixture[11, 17] = true; fixture[575, 719] = true
        var fixturePatterns = model.resources.patterns; fixturePatterns[7] = .gray
        let source = documents.appendingPathComponent("Открыть файл.mac")
        try MacPaintFile.encode(fixture, patterns: fixturePatterns).write(to: source)
        let opened = text(try call("open_document", ["path": source.path]))
        let canonicalSource = URL(fileURLWithPath: source.path).standardizedFileURL.resolvingSymlinksInPath()
        try check(testing.model.bitmap == fixture && testing.model.patterns == fixturePatterns && !testing.model.isDirty
                  && testing.documentURL == canonicalSource && view.documentTitle == "Открыть файл",
                  "open_document decodes a real file with Unicode/spaces in its absolute path and activates the window")
        let openedID = opened["document_id"] as! String
        // A clean active document must not hide a dirty parked document on Quit.
        let verificationDirectory = testing.verificationDirectory
        testing.verificationDirectory = nil
        var sawQuitPrompt = false
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let quitDeadline = Date().addingTimeInterval(5)
        let quitTimer = Timer(timeInterval: 0.02, repeats: true) { timer in
            if Date() > quitDeadline { timer.invalidate(); NSApp.abortModal(); return }
            guard let panel = NSApp.modalWindow, let content = panel.contentView,
                  let cancel = buttons(in: content).first(where: { $0.title == "Cancel" }) else { return }
            sawQuitPrompt = true; timer.invalidate(); cancel.performClick(nil)
        }
        RunLoop.main.add(quitTimer, forMode: .modalPanel)
        let quitResult = testing.applicationShouldTerminate(NSApp)
        quitTimer.invalidate(); testing.verificationDirectory = verificationDirectory
        try check(sawQuitPrompt && quitResult == .terminateCancel && testing.aiDocumentID == openedID && model.isDirty,
                  "Quit prompts for a hidden dirty document; Cancel preserves all work and restores the originally active document")
        let initial = try state(), initialEntries = try entries()
        let bad = documents.appendingPathComponent("Invalid.mac"); try Data([1, 2, 3]).write(to: bad)
        let large = documents.appendingPathComponent("Large.mac"); try Data(repeating: 0, count: 1_000_001).write(to: large)
        let sentinel = documents.appendingPathComponent("Existing.mac"), sentinelBytes = Data("keep me".utf8)
        try sentinelBytes.write(to: sentinel)
        for (name, arguments) in [
            ("open_document", ["path": bad.path]), ("open_document", ["path": large.path]),
            ("open_document", ["path": documents.appendingPathComponent("Absent.mac").path]),
            ("open_document", ["path": "relative.mac"]), ("save_as", ["path": 123]),
            ("save_document", ["path": sentinel.path]), ("save_as", ["path": sentinel.path]),
            ("export_png", ["path": sentinel.path]), ("save_as", ["path": sentinel.path, "overwrite": 1]),
            ("new_document", ["unexpected": true]), ("list_documents", ["unexpected": true]),
            ("switch_document", ["document_id": "missing"]), ("switch_document", ["document_id": 7])
        ] as [(String, [String: Any])] { _ = try call(name, arguments, error: true) }
        let afterErrors = try state(), afterEntries = try entries(), sentinelAfter = try Data(contentsOf: sentinel)
        try check(NSDictionary(dictionary: initial).isEqual(to: afterErrors) && NSArray(array: initialEntries).isEqual(to: afterEntries)
                  && sentinelAfter == sentinelBytes, "Malformed paths, corrupt/oversized files, unknown IDs and overwrite refusals preserve document list, state and existing files")
        view.helpID = 2400
        for (name, args) in [("new_document", [:]), ("open_document", ["path": source.path]),
                             ("save_document", [:]), ("save_as", ["path": sentinel.path]),
                             ("export_png", ["path": sentinel.path]), ("switch_document", ["document_id": originalID])] {
            _ = try call(name, args, error: true)
        }
        view.helpID = nil
        _ = try call("save_as", ["path": sentinel.path, "overwrite": true])
        let overwritten = try MacPaintFile.decode(Data(contentsOf: sentinel))
        try check(overwritten.bitmap == fixture, "Explicit overwrite replaces the chosen file with valid MacPaint data")
        testing.modsEnabled = false
        _ = try call("list_documents", error: true); _ = try call("new_document", error: true)
        testing.modsEnabled = true
        _ = try call("switch_document", ["document_id": originalID])
        try check(try testing.model === model && entries().count == 2, "Toggling mods keeps both documents and restores document tools")
        testing.perform("nextAIDocument")
        try check(testing.aiDocumentID == openedID && view.menus.last?.title == "Mods" && NSApp.mainMenu?.items.last?.title == "Mods",
                  "Next Document is available in the final Mods menu and activates the other document")
        testing.perform("close"); testing.perform("close")
        try check(try entries().isEmpty && !view.documentOpen, "Closing every document leaves an empty MCP document list")
        _ = try call("get_canvas", error: true)
        _ = try call("new_document")
        try check(view.documentOpen && testing.model.bitmap == Bitmap(), "new_document works when the last drawing was closed")
        let named = documents.appendingPathComponent("Save document path.mac")
        try? FileManager.default.removeItem(at: named)
        try mark(7, 13)
        _ = try call("save_document", ["path": named.path])
        let namedPixels = try MacPaintFile.decode(Data(contentsOf: named)).bitmap
        try check(namedPixels[7, 13] && !testing.model.isDirty && view.documentTitle == "Save document path",
                  "save_document with path saves an unnamed document and adopts the name")
        let countBeforeLimit = try entries().count
        for _ in countBeforeLimit..<16 { _ = try call("new_document") }
        let limitID = testing.aiDocumentID
        _ = try call("new_document", error: true)
        _ = try call("open_document", ["path": source.path], error: true)
        try check(try entries().count == 16 && testing.aiDocumentID == limitID && testing.model.bitmap == Bitmap(),
                  "The 16-document limit rejects creation without replacing any document")
        while !testing.aiParkedDocuments.isEmpty { testing.perform("close") }
        try testing.recovery?.close(); testing.recovery = nil
        // Restore the shared verification fixture before subsequent checks and shutdown.
        testing.aiParkedDocuments = []; testing.model = model; view.model = model; testing.aiDocumentID = originalID
        testing.documentURL = originalURL; view.documentTitle = originalTitle; view.documentOpen = true
        testing.aiControlEnabled = false
        try check(!AppController(preferences: UserDefaults(suiteName: domain)!).aiControlEnabled, "Disabled AI control persists independently from the drawing")
        try JSONSerialization.data(withJSONObject: ["checks": checks, "count": checks.count,
            "scope": "Bundled STDIO helper → private Unix socket → real AppKit documents. Drawing, Undo, cancellation, 128K, new/open/save/save_as/export/list/switch, filesystem errors and preservation at 1x/2x."], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("AI-Control.json"))
        return checks
    }
}
