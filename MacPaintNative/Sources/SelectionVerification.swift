import AppKit

enum SelectionVerification {
    static func raster(_ rows: [String]) -> Bitmap {
        var bitmap = Bitmap(width: rows[0].count, height: rows.count)
        for (y, row) in rows.enumerated() {
            for (x, pixel) in row.enumerated() where pixel == "#" { bitmap[x, y] = true }
        }
        return bitmap
    }

    static func model(resources: ClassicResources) throws -> [String] {
        let model = PaintModel(resources: resources)
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func select(_ pixels: Bitmap) {
            model.newDocument(); model.setOrigin(.zero)
            model.bitmap[10, 10] = true
            model.bitmap.copy(pixels, at: PixelPoint(x: 40, y: 60))
            model.chooseTool(.selection)
            model.begin(at: PixelPoint(x: 40, y: 60))
            model.end(at: PixelPoint(x: 40 + pixels.width, y: 60 + pixels.height))
        }
        let dot = raster([".......", ".......", ".......", "...#...", ".......", ".......", "......."])
        let ring = raster([".......", ".......", "..###..", "..#.#..", "..###..", ".......", "......."])
        select(dot); let before = model.displayBitmap
        model.editSelection("edges")
        let tracedCount = model.selection?.pixels.bytes.reduce(0) { $0 + $1.nonzeroBitCount } ?? 0
        try check(model.selection?.pixels == ring, "Trace Edges: expected eight-pixel outer ring, actual \(tracedCount) black pixels")
        try check(model.selection?.origin == PixelPoint(x: 40, y: 60) && model.bitmap[10, 10],
                  "Trace Edges preserves selection placement and pixels outside it")
        let outlined = model.displayBitmap
        model.undo(); try check(model.displayBitmap == before, "Undo restores pixels before Trace Edges")
        model.undo(); try check(model.displayBitmap == outlined, "toggle Undo restores the traced outline")
        let block = raster([".......", ".#####.", ".#####.", ".#####.", ".#####.", ".#####.", "......."])
        select(block); model.editSelection("edges")
        try check(model.selection?.pixels == raster([".#####.", "#.....#", "#.....#", "#.....#", "#.....#", "#.....#", ".#####."]),
                  "Trace Edges follows the original inset source rectangle at selection corners")
        let borderDot = raster([".......", ".......", ".......", "#......", ".......", ".......", "......."])
        select(borderDot); model.editSelection("edges")
        try check(model.selection?.pixels == borderDot, "Trace Edges retains ink outside its inset source rectangle")
        select(raster(["#"])); model.editSelection("edges")
        try check(model.selection?.pixels == raster(["#"]), "Trace Edges leaves a one-pixel selection unchanged")
        select(dot); model.editSelection("edges", modifiers: .shift)
        try check(model.selection?.pixels == raster([".......", ".......", "..###..", "..#.##.", "..###..", "..###..", "......."]),
                  "Shift Trace Edges clips vertical smears to the original inset source width")
        let paddedDot = raster([".........", ".........", ".........", ".........", "....#....", ".........", ".........", ".........", "........."])
        select(paddedDot); model.editSelection("edges", modifiers: .shift)
        try check(model.selection?.pixels == raster([".........", ".........", ".........", "...####..", "...#.##..", "...####..", "...####..", ".........", "........."]),
                  "Shift Trace Edges makes the original asymmetric fifteen-pixel outline")
        select(borderDot); model.editSelection("edges", modifiers: .shift)
        try check(model.selection?.pixels == borderDot, "Shift Trace Edges retains ink outside its smaller source rectangle")
        let tiny = raster(["##", "##"])
        select(tiny); model.editSelection("edges", modifiers: .shift)
        try check(model.selection?.pixels == tiny, "Shift Trace Edges leaves a two-pixel selection unchanged")
        return checks
    }

    static func menus(controller: AppController, output: URL) throws -> [String] {
        let model = controller.model!, view = controller.workspace!, window = controller.window!
        defer { model.newDocument(); model.setOrigin(.zero); view.refresh() }
        let dot = raster([".........", ".........", ".........", ".........", "....#....", ".........", ".........", ".........", "........."])
        let ring = raster([".........", ".........", ".........", "...###...", "...#.#...", "...###...", ".........", ".........", "........."])
        let shadow = raster([".........", ".........", ".........", "...####..", "...#.##..", "...####..", "...####..", ".........", "........."])
        var checks = [String]()
        func select() {
            model.newDocument(); model.setOrigin(.zero); model.grid = false
            model.bitmap.copy(dot, at: PixelPoint(x: 40, y: 60)); model.chooseTool(.selection)
            model.begin(at: PixelPoint(x: 40, y: 60)); model.end(at: PixelPoint(x: 49, y: 69))
            view.refresh()
        }
        func check(_ expected: Bitmap, _ name: String) throws {
            guard model.selection?.pixels == expected else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func mouse(_ type: NSEvent.EventType, x: Int, y: Int, shift: Bool = false) {
            let scale = max(1, min(floor(view.bounds.width / 512), floor(view.bounds.height / 342)))
            let offset = NSPoint(x: floor((view.bounds.width - 512 * scale) / 2), y: floor((view.bounds.height - 342 * scale) / 2))
            let location = view.convert(NSPoint(x: offset.x + CGFloat(x) * scale, y: offset.y + CGFloat(y) * scale), to: nil)
            window.sendEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: shift ? .shift : [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        }
        let editX = 5 + view.menus.prefix(2).reduce(0) { $0 + model.resources.chicago.width(of: $1.title) + 14 }
        let edgesY = 19 + 3 + 9 * 18 + 9
        select()
        mouse(.leftMouseDown, x: editX + 10, y: 10)
        mouse(.leftMouseUp, x: editX + 20, y: edgesY)
        try check(ring, "classic Edit menu traces the original outer ring on mouse release")
        select()
        mouse(.leftMouseDown, x: editX + 10, y: 10)
        mouse(.leftMouseUp, x: editX + 10, y: 10)
        mouse(.leftMouseDown, x: editX + 20, y: edgesY, shift: true)
        mouse(.leftMouseUp, x: editX + 20, y: edgesY, shift: true)
        try check(shadow, "classic Edit menu retains Shift when Trace Edges is clicked")
        select()
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "e", charactersIgnoringModifiers: "e", isARepeat: false, keyCode: 14)!
        guard NSApp.mainMenu!.performKeyEquivalent(with: key) else { throw Verification.Failure(description: "native Command-E was not handled") }
        try check(ring, "native Command-E performs Trace Edges")
        select()
        let shifted = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "E", charactersIgnoringModifiers: "E", isARepeat: false, keyCode: 14)!
        guard window.performKeyEquivalent(with: shifted) else { throw Verification.Failure(description: "window Command-Shift-E was not handled") }
        try check(shadow, "window Command-Shift-E performs the asymmetric Trace Edges variant")
        try JSONSerialization.data(withJSONObject: ["checks": checks], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Selection-Menus.json"))
        return checks
    }
}
