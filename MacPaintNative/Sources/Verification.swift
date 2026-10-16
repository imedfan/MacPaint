import AppKit
import CryptoKit

enum Verification {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }
    static func run(controller: AppController, output: URL) throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output.appendingPathComponent("Verification.json"))
        var checks = [String]()
        func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw Failure(description: name) }
            checks.append(name)
        }
        let model = controller.model!, view = controller.workspace!
        func blankAtTopLeft() { model.newDocument(); model.setOrigin(.zero) }
        try check(model.origin == PixelPoint(x: 80, y: 120), "new document uses original page origin (80,120)")
        model.setOrigin(.zero)
        try check(model.resources.patterns.count == 38, "38 recovered patterns")
        try check(model.resources.paintFont.glyph(69).bitmap.bytes.contains(where: { $0 != 0 }), "original lasso glyph")
        try check(model.resources.help.count == 2, "both original help pictures")
        try check(NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("MacPaint.icns")) != nil, "native macOS decodes original application icon")
        checks.append(contentsOf: try RecoveryVerification.checkStore(resources: model.resources, output: output))
        checks.append(contentsOf: try ClipboardVerification.run(controller: controller, output: output))
        checks.append(contentsOf: try BitmapTextVerification.run(resources: model.resources, output: output))
        checks.append(contentsOf: try TextModelVerification.run(resources: model.resources))
        checks.append(contentsOf: try SelectionVerification.model(resources: model.resources))
        checks.append(contentsOf: try DocumentLifecycleVerification.model(resources: model.resources))
        checks.append(contentsOf: try PageOverviewVerification.model(resources: model.resources))
        checks.append(contentsOf: try FontVerification.model(resources: model.resources))
        checks.append(contentsOf: try CatalogVerification.model(resources: model.resources, output: output))
        checks.append(contentsOf: try TextVerification.run(controller: controller, output: output))
        model.brushIndex = 27 // PaintFont 147: a single pixel at (8,8).
        model.begin(at: PixelPoint(x: 100, y: 100)); model.end(at: PixelPoint(x: 100, y: 100))
        try check(model.bitmap[100, 100] && model.bitmap.bytes.reduce(0) { $0 + $1.nonzeroBitCount } == 1,
                  "original single-pixel brush keeps its glyph bearing and hotspot")
        blankAtTopLeft(); model.brushIndex = 7
        var asymmetric = Bitmap(width: 3, height: 2)
        asymmetric[0, 0] = true
        let rotated = asymmetric.rotated()
        try check(rotated.width == 2 && rotated.height == 3 && rotated[0, 2] && !rotated[1, 0], "Rotate follows original counterclockwise direction")
        var ring = Bitmap(width: 7, height: 7)
        ring.frame(PixelRect(x: 1, y: 1, width: 5, height: 5))
        let opaque = ring.opaqueMask()
        try check(opaque[3, 3] && opaque[1, 1] && !opaque[0, 0], "lasso mask retains enclosed white and excludes exterior white")
        var dots = Bitmap(width: 8, height: 8); dots[2, 2] = true; dots[3, 3] = true
        let finalDots = PrintRaster.final(dots)
        try check(finalDots[4, 4] && finalDots[5, 5] && finalDots[6, 6] && !finalDots[5, 4], "Print Final keeps original dots and interpolates the diagonal")
        blankAtTopLeft(); model.chooseTool(.brush); model.brushIndex = 27
        model.symmetryHorizontal = true; model.symmetryDiagonal = true
        model.begin(at: PixelPoint(x: 228, y: 130)); model.end(at: PixelPoint(x: 228, y: 130))
        try check(model.bitmap.bytes.reduce(0) { $0 + $1.nonzeroBitCount } == 8, "original MapSym table produces all eight images for combined mirrors")
        model.symmetryHorizontal = false; model.symmetryDiagonal = false; model.brushIndex = 7
        blankAtTopLeft(); model.chooseTool(.spray)
        model.begin(at: PixelPoint(x: 100, y: 100))
        let sprayStart = model.bitmap
        model.drag(to: PixelPoint(x: 101, y: 100)); model.drag(to: PixelPoint(x: 102, y: 100))
        try check(model.bitmap == sprayStart, "spray waits for original movement threshold")
        model.drag(to: PixelPoint(x: 103, y: 100)); model.end(at: PixelPoint(x: 103, y: 100))
        try check(model.bitmap != sprayStart, "small spray movements accumulate past threshold")
        blankAtTopLeft(); model.chooseTool(.line)
        model.begin(at: PixelPoint(x: 400, y: 10)); model.end(at: PixelPoint(x: 450, y: 10))
        try check(model.bitmap[415, 10] && !model.bitmap[416, 10], "drawing is clipped to the original visible document window")
        blankAtTopLeft(); model.chooseTool(.bucket)
        model.begin(at: PixelPoint(x: 10, y: 10)); model.end(at: PixelPoint(x: 10, y: 10))
        try check(model.bitmap[415, 239] && !model.bitmap[416, 239] && !model.bitmap[20, 240], "bucket affects current window without filling hidden page")
        blankAtTopLeft(); model.chooseTool(.text)
        model.begin(at: PixelPoint(x: 20, y: 40)); model.updateText(Array(repeating: String(repeating: "A", count: 100), count: 22).joined(separator: "\n"))
        let textLines = model.text.split(separator: "\n", omittingEmptySubsequences: false)
        try check(textLines.count == 20 && textLines.allSatisfy { $0.count == 80 }, "original text limit is twenty lines of eighty characters")
        blankAtTopLeft(); model.bitmap.fill(model.bitmap.bounds, pattern: .black); model.chooseTool(.text)
        model.begin(at: PixelPoint(x: 20, y: 40)); model.updateText(" ")
        try check(!model.bitmap[20, 39] && model.bitmap[0, 0], "text clears its background rectangle as original UpdateText does")
        blankAtTopLeft()
        let blank = Data([0, 0, 0, 2] + Array(repeating: UInt8(0), count: 508) + Array(repeating: [UInt8(185), 0], count: 720).flatMap { $0 })
        let blankDocument = try MacPaintFile.decode(blank)
        try check(blankDocument.bitmap == Bitmap(), "independent canonical blank PackBits fixture")
        do {
            _ = try MacPaintFile.decode(blank.dropLast())
            throw Failure(description: "truncated input accepted")
        } catch is MacPaintFile.FormatError { checks.append("truncated input rejected") }
        model.chooseTool(.pencil)
        model.begin(at: PixelPoint(x: 10, y: 10)); model.end(at: PixelPoint(x: 25, y: 10))
        try check((10...25).allSatisfy { model.bitmap[$0, 10] }, "pencil draws continuous black stroke")
        model.begin(at: PixelPoint(x: 10, y: 10)); model.end(at: PixelPoint(x: 25, y: 10))
        try check((10...25).allSatisfy { !model.bitmap[$0, 10] }, "pencil starting on black erases")
        model.undo()
        try check(model.bitmap[15, 10], "Undo restores previous image")
        model.undo()
        try check(!model.bitmap[15, 10], "second Undo toggles image")
        blankAtTopLeft()
        model.bitmap.frame(PixelRect(x: 5, y: 5, width: 20, height: 20))
        model.chooseTool(.bucket); model.begin(at: PixelPoint(x: 10, y: 10)); model.end(at: PixelPoint(x: 10, y: 10))
        try check(model.bitmap[10, 10] && !model.bitmap[4, 10], "bucket respects closed boundary")
        for tool in PaintTool.allCases where tool.isShape || [.line, .brush, .spray, .eraser, .curve, .filledCurve].contains(tool) {
            blankAtTopLeft(); model.chooseTool(tool)
            if tool == .eraser { model.bitmap.fill(model.bitmap.bounds, pattern: .black) }
            let before = model.bitmap
            model.begin(at: PixelPoint(x: 40, y: 40)); model.drag(to: PixelPoint(x: 80, y: 65)); model.end(at: PixelPoint(x: 95, y: 80))
            try check(model.bitmap != before, "\(tool.name) changes pixels")
        }
        blankAtTopLeft(); model.chooseTool(.filledPolygon)
        for p in [PixelPoint(x: 20, y: 20), PixelPoint(x: 70, y: 20), PixelPoint(x: 45, y: 70)] { model.begin(at: p) }
        model.finishPolygon(); try check(model.bitmap[45, 35], "filled polygon has interior")
        blankAtTopLeft(); model.chooseTool(.polygon)
        for p in [PixelPoint(x: 20, y: 20), PixelPoint(x: 70, y: 20), PixelPoint(x: 70, y: 70)] { model.begin(at: p) }
        model.finishPolygon()
        try check(model.bitmap[45, 20] && model.bitmap[70, 45] && !model.bitmap[45, 45], "hollow polygon stays open when finished away from start")
        blankAtTopLeft(); model.chooseTool(.filledPolygon)
        for p in [PixelPoint(x: 20, y: 20), PixelPoint(x: 70, y: 20), PixelPoint(x: 45, y: 70)] { model.begin(at: p) }
        model.finishPolygon()
        model.chooseTool(.selection)
        model.begin(at: PixelPoint(x: 15, y: 15)); model.end(at: PixelPoint(x: 75, y: 75))
        try check(model.selection != nil, "rectangle selection exists")
        let beforeMove = model.displayBitmap
        model.begin(at: PixelPoint(x: 45, y: 35)); model.end(at: PixelPoint(x: 75, y: 65))
        try check(!model.displayBitmap[45, 25] && model.displayBitmap[75, 65], "selection moves and clears original")
        model.undo(); try check(model.displayBitmap == beforeMove, "Undo restores moved selection")
        model.acceptSelection(); model.chooseTool(.text)
        model.begin(at: PixelPoint(x: 90, y: 100)); model.updateText("MacPaint")
        try check(model.bitmap != beforeMove, "recovered bitmap font writes text")
        blankAtTopLeft(); model.bitmap.fill(PixelRect(x: 20, y: 20, width: 30, height: 30), pattern: .black)
        model.chooseTool(.selection); model.begin(at: PixelPoint(x: 20, y: 20)); model.end(at: PixelPoint(x: 50, y: 50))
        model.begin(at: PixelPoint(x: 48, y: 48), modifiers: .command)
        model.end(at: PixelPoint(x: 63, y: 63), modifiers: .command)
        try check(model.selection?.pixels.width == 45 && model.selection?.pixels.height == 45, "Command drag stretches rectangular selection")
        model.acceptSelection(); blankAtTopLeft()
        model.bitmap.frame(PixelRect(x: 40, y: 40, width: 20, height: 20))
        model.chooseTool(.lasso)
        model.begin(at: PixelPoint(x: 30, y: 30))
        for point in [PixelPoint(x: 70, y: 30), PixelPoint(x: 70, y: 70), PixelPoint(x: 30, y: 70)] { model.drag(to: point) }
        model.end(at: PixelPoint(x: 30, y: 30))
        try check(model.selection?.rect == PixelRect(x: 40, y: 40, width: 20, height: 20), "lasso trims exterior to the selected object")
        try check(model.selection?.mask[10, 10] == true, "lasso includes the enclosed white center")
        model.acceptSelection()
        model.commitText(); model.markSaved()
        model.chooseTool(.pencil); model.begin(at: PixelPoint(x: 200, y: 200)); model.end(at: PixelPoint(x: 210, y: 200))
        try check(model.isDirty, "editing marks document dirty")
        let destination = output.appendingPathComponent("RoundTrip.mac")
        try controller.writeDocument(to: destination)
        try check(!model.isDirty, "successful atomic save marks document clean")
        let reopened = try MacPaintFile.decode(Data(contentsOf: destination))
        try check(reopened.bitmap == model.displayBitmap && reopened.patterns == model.patterns, "MacPaint save/reopen retains every pixel and pattern")
        let expected = SHA256.hash(data: Data(model.displayBitmap.bytes)).map { String(format: "%02x", $0) }.joined()
        try Data(expected.utf8).write(to: output.appendingPathComponent("RoundTrip.sha256"))
        model.begin(at: PixelPoint(x: 250, y: 210)); model.end(at: PixelPoint(x: 260, y: 210))
        let unsaved = model.displayBitmap
        do { try controller.writeDocument(to: output.appendingPathComponent("missing/subdir/file.mac")) }
        catch { checks.append("write to missing parent reports error") }
        try check(model.isDirty && model.displayBitmap == unsaved, "failed save retains dirty pixels")
        checks.append(contentsOf: try CursorVerification.run(controller: controller, output: output))
        checks.append(contentsOf: try TextVerification.keyboard(controller: controller))
        checks.append(contentsOf: try SelectionVerification.menus(controller: controller, output: output))
        checks.append(contentsOf: try ToolSettingsVerification.run(controller: controller, output: output))
        checks.append(contentsOf: try PatternVerification.run(controller: controller, output: output))
        checks.append(contentsOf: try DocumentLifecycleVerification.run(controller: controller, output: output))
        checks.append(contentsOf: try PageOverviewVerification.run(controller: controller, output: output))
        checks.append(contentsOf: try FontVerification.window(controller: controller, output: output))
        checks.append(contentsOf: try CatalogVerification.window(controller: controller, output: output))
        checks.append(contentsOf: try ModsVerification.run(controller: controller, output: output))
        checks.append(contentsOf: try Macintosh128KVerification.model(resources: model.resources))
        checks.append(contentsOf: try Macintosh128KVerification.run(controller: controller, output: output))
        // Exercise real NSView mouse routing at the view's current integer scale.
        blankAtTopLeft()
        view.documentOpen = true
        func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
            let local = NSPoint(x: x * 2, y: y * 2)
            let location = view.convert(local, to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        controller.window.sendEvent(event(.leftMouseDown, x: 55, y: 105))
        controller.window.sendEvent(event(.leftMouseUp, x: 55, y: 105))
        try check(model.tool == .pencil, "real view palette selects Pencil")
        controller.window.sendEvent(event(.leftMouseDown, x: 110, y: 80))
        controller.window.sendEvent(event(.leftMouseDragged, x: 200, y: 120))
        controller.window.sendEvent(event(.leftMouseUp, x: 200, y: 120))
        if !model.bitmap[30, 32] || !model.bitmap[120, 72] {
            throw Failure(description: "real view drag expected black (30,32) and (120,72), actual bounds \(String(describing: model.bitmap.blackBounds)), origin \(model.origin), view \(view.bounds), window \(controller.window.frame)")
        }
        checks.append("real view drag writes document coordinates")
        let shadowKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                        timestamp: 0, windowNumber: controller.window.windowNumber, context: nil,
                                        characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1)!
        try check(NSApp.mainMenu!.performKeyEquivalent(with: shadowKey), "original Command-S is handled by native menu")
        try check(model.textStyle & 16 != 0, "Command-S selects Shadow instead of Save")
        model.textStyle = 0
        view.helpID = 2401
        try check(view.renderWorkspace().cropped(to: PixelRect(x: 80, y: 48, width: 416, height: 240)) == model.resources.help[2401], "original Short Cuts picture renders unchanged in document window")
        view.helpID = nil
        model.chooseTool(.filledOval)
        model.patternIndex = 4
        model.begin(at: PixelPoint(x: 160, y: 50)); model.end(at: PixelPoint(x: 280, y: 150))
        model.chooseTool(.text); model.begin(at: PixelPoint(x: 40, y: 160)); model.updateText("MacPaint 1.3"); model.commitText()
        model.chooseTool(.brush); controller.documentURL = nil; view.documentTitle = "Untitled"
        view.refresh(); controller.window.displayIfNeeded(); view.displayIfNeeded()
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Workspace.png"))
        } else { throw Failure(description: "actual view snapshot unavailable") }
        try NSBitmapImageRep(cgImage: view.renderWorkspace().cgImage()).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Workspace-1x.png"))
        let draftPDF = PrintBitmapView(bitmap: model.displayBitmap).dataWithPDF(inside: NSRect(x: 0, y: 0, width: 576, height: 720))
        let finalPDF = PrintBitmapView(bitmap: PrintRaster.final(model.displayBitmap), logicalSize: NSSize(width: 576, height: 720))
            .dataWithPDF(inside: NSRect(x: 0, y: 0, width: 576, height: 720))
        try draftPDF.write(to: output.appendingPathComponent("Print-Draft.pdf"))
        try finalPDF.write(to: output.appendingPathComponent("Print-Final.pdf"))
        try check(draftPDF.starts(with: Data("%PDF".utf8)) && finalPDF != draftPDF, "native AppKit exports distinct Draft and Final print PDFs")
        model.toggleFatBits(at: PixelPoint(x: 210, y: 105)); view.refresh()
        try NSBitmapImageRep(cgImage: view.renderWorkspace().cgImage()).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("FatBits.png"))
        try check(!view.renderWorkspace()[400, 55], "FatBits leaves original white pixel grid lines")
        model.toggleFatBits()
        for kind in ["brush", "pattern", "symmetry", "about"] {
            let dialog = ClassicDialogView(model: model, kind: kind)
            try NSBitmapImageRep(cgImage: dialog.renderDialog().cgImage()).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Dialog-\(kind).png"))
        }
        let report: [String: Any] = ["checks": checks, "count": checks.count,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "scope": "Native resource, raster, document and NSView interaction checks; full original behavioral parity remains unproven."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Verification.json"))
        print("\(checks.count) behavior checks passed; snapshot and report at \(output.path)")
    }
    static func reopen(controller: AppController, document: URL, output: URL) throws {
        guard controller.application(NSApp, openFile: document.path) else { throw Failure(description: "separate launch cannot open saved document") }
        let bitmap = controller.model.displayBitmap
        let digest = SHA256.hash(data: Data(bitmap.bytes)).map { String(format: "%02x", $0) }.joined()
        let expected = try String(contentsOf: output.appendingPathComponent("RoundTrip.sha256"), encoding: .utf8)
        guard digest == expected else { throw Failure(description: "pixels differ after process restart") }
        guard !controller.model.isDirty else { throw Failure(description: "reopened document is dirty") }
        let report: [String: Any] = ["result": "passed", "document": document.lastPathComponent,
                                    "bitmapSHA256": digest, "processID": ProcessInfo.processInfo.processIdentifier,
                                    "os": ProcessInfo.processInfo.operatingSystemVersionString]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Reopen.json"))
        print("Separate process reopened \(document.lastPathComponent) with identical bitmap SHA-256 \(digest)")
    }
}
