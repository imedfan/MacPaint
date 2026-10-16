import AppKit

enum CursorVerification {
    static func run(controller: AppController, output: URL) throws -> [String] {
        let model = controller.model!, view = controller.workspace!, window = controller.window!
        let originalFrame = window.frame
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let activationDeadline = Date().addingTimeInterval(2)
        while (!NSApp.isActive || !window.isKeyWindow) && Date() < activationDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        guard NSApp.isActive && window.isKeyWindow else {
            let front = NSWorkspace.shared.frontmostApplication
            throw Verification.Failure(description: "Cannot activate verification window for native mouse routing: active=\(NSApp.isActive), key=\(window.isKeyWindow), visible=\(window.isVisible), miniaturized=\(window.isMiniaturized), modal=\(String(describing: NSApp.modalWindow)), front=\(front?.bundleIdentifier ?? "unknown"), frontPID=\(front?.processIdentifier ?? -1), ownPID=\(ProcessInfo.processInfo.processIdentifier)")
        }
        model.newDocument(); model.setOrigin(.zero); view.documentOpen = true
        model.brushIndex = 0
        defer {
            model.brushIndex = 7; model.lineWidth = 1
            view.helpID = nil; view.popup = nil; view.pageOverview = false
            window.setFrame(originalFrame, display: true)
            NSCursor.arrow.set()
        }
        func workspaceScale() -> CGFloat { max(1, min(floor(view.bounds.width / 512), floor(view.bounds.height / 342))) }
        func event(_ type: NSEvent.EventType, _ point: PixelPoint) -> NSEvent {
            let scale = workspaceScale()
            let offset = NSPoint(x: floor((view.bounds.width - 512 * scale) / 2),
                                 y: floor((view.bounds.height - 342 * scale) / 2))
            let location = view.convert(NSPoint(x: offset.x + CGFloat(point.x) * scale,
                                                y: offset.y + CGFloat(point.y) * scale), to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                     context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let palette = PixelPoint(x: 28, y: 105), point = PixelPoint(x: 200, y: 150)
        window.sendEvent(event(.leftMouseDown, palette)); window.sendEvent(event(.leftMouseUp, palette))
        view.mouseMoved(with: event(.mouseMoved, point))
        guard model.tool == .brush, NSCursor.current !== NSCursor.arrow else {
            throw Verification.Failure(description: "Paintbrush cursor was not selected on entering canvas: tool=\(model.tool.name), arrow=\(NSCursor.current === NSCursor.arrow), active=\(NSApp.isActive), key=\(window.isKeyWindow)")
        }
        if let data = NSCursor.current.image.tiffRepresentation, let rep = NSBitmapImageRep(data: data) {
            try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Cursor-AfterEntry.png"))
        }
        window.sendEvent(event(.leftMouseDown, point))
        window.sendEvent(event(.leftMouseDragged, point))
        window.sendEvent(event(.leftMouseUp, point))
        let contrast = try contrastingPixels(cursor: NSCursor.current, background: view.renderWorkspace(),
                                            point: point, viewScale: workspaceScale())
        guard contrast > 0 else {
            throw Verification.Failure(description: "Paintbrush cursor disappears after painting: 0 contrasting pixels against the new black stroke")
        }
        var checks = ["Paintbrush cursor stays visible against its stroke before the next mouse movement"]
        var observations = [[String: Any]]()
        var sheet = Bitmap(width: 320, height: 20 + PaintTool.allCases.count * 36)
        let font = model.resources.chicago
        for (label, x) in [("Tool", 8), ("White", 208), ("Black", 244), ("Grid", 280)] {
            font.draw(label, in: &sheet, at: PixelPoint(x: x, y: 14))
        }
        let backgrounds: [(String, Pattern)] = [("white", .white), ("black", .black), ("grid", .gray)]
        func select(_ tool: PaintTool) throws {
            let p = PixelPoint(x: tool.rawValue % 2 == 0 ? 28 : 55, y: 39 + tool.rawValue / 2 * 22)
            window.sendEvent(event(.leftMouseDown, p)); window.sendEvent(event(.leftMouseUp, p))
            guard model.tool == tool else { throw Verification.Failure(description: "Palette did not select \(tool.name)") }
        }
        func checkVisibility(_ label: String) throws {
            for (backgroundIndex, background) in backgrounds.enumerated() {
                model.bitmap.fill(model.bitmap.bounds, pattern: background.1)
                view.refresh()
                view.mouseMoved(with: event(.mouseMoved, point))
                let cursor = NSCursor.current
                guard cursor !== NSCursor.arrow else { throw Verification.Failure(description: "\(label) lost its tool cursor on the canvas") }
                let contrast = try contrastingPixels(cursor: cursor, background: view.renderWorkspace(), point: point, viewScale: workspaceScale())
                guard contrast > 0 else { throw Verification.Failure(description: "\(label) is invisible on \(background.0) at \(workspaceScale())x") }
                guard cursor.hotSpot.x >= 0, cursor.hotSpot.y >= 0,
                      cursor.hotSpot.x < cursor.image.size.width, cursor.hotSpot.y < cursor.image.size.height else {
                    throw Verification.Failure(description: "\(label) has a hotspot outside its image")
                }
                observations.append(["cursor": label, "background": background.0, "scale": Int(workspaceScale()), "contrastingPixels": contrast])
                if label == model.tool.name && workspaceScale() == 2 {
                    let patch = PixelRect(x: 208 + backgroundIndex * 36, y: 20 + model.tool.rawValue * 36, width: 28, height: 28)
                    sheet.fill(patch, pattern: background.1)
                    try drawCursor(cursor, into: &sheet, at: PixelPoint(x: patch.x + 4, y: patch.y + 4), viewScale: workspaceScale())
                }
            }
        }
        for scale in [1, 2] {
            window.setContentSize(NSSize(width: 512 * scale, height: 342 * scale))
            view.updateTrackingAreas()
            model.newDocument(); model.setOrigin(.zero)
            for tool in PaintTool.allCases {
                try select(tool)
                NSCursor.arrow.set()
                view.cursorUpdate(with: event(.mouseMoved, point))
                guard NSCursor.current !== NSCursor.arrow else {
                    throw Verification.Failure(description: "\(tool.name) was not restored by AppKit cursorUpdate")
                }
                try checkVisibility(tool.name)
                if scale == 2 { font.draw(tool.name, in: &sheet, at: PixelPoint(x: 8, y: 40 + tool.rawValue * 36)) }
            }
            try select(.brush)
            for index in 0..<32 { model.brushIndex = index; try checkVisibility("Brush \(index)") }
            try select(.line)
            for width in [1, 2, 4, 8] { model.lineWidth = width; try checkVisibility("Line width \(width)") }
        }
        checks.append("all twenty tool cursors stay visible on white, black and patterned canvases at 1x and 2x")
        checks.append("all thirty-two brush cursors and four line widths stay visible on all three backgrounds at both scales")
        checks.append("AppKit cursorUpdate restores each tool when entering the canvas without a mouseMoved event")
        view.mouseExited(with: event(.mouseMoved, palette))
        guard NSCursor.current === NSCursor.arrow else { throw Verification.Failure(description: "Arrow was not restored outside the view") }
        view.mouseEntered(with: event(.mouseMoved, point))
        guard NSCursor.current !== NSCursor.arrow else { throw Verification.Failure(description: "Tool cursor was not restored on re-entry") }
        view.mouseMoved(with: event(.mouseMoved, palette))
        guard NSCursor.current === NSCursor.arrow else { throw Verification.Failure(description: "Arrow was not restored over the palette") }
        view.mouseMoved(with: event(.mouseMoved, point))
        view.helpID = 2400; view.refresh()
        guard NSCursor.current === NSCursor.arrow else { throw Verification.Failure(description: "Help retained the drawing cursor") }
        view.helpID = nil; view.popup = 0; view.refresh()
        guard NSCursor.current === NSCursor.arrow else { throw Verification.Failure(description: "Menu retained the drawing cursor") }
        view.popup = nil; view.pageOverview = true; view.refresh()
        guard NSCursor.current === NSCursor.arrow else { throw Verification.Failure(description: "Page overview retained the drawing cursor") }
        view.pageOverview = false; model.newDocument(); model.setOrigin(.zero)
        model.chooseTool(.selection)
        model.begin(at: PixelPoint(x: 110, y: 90)); model.end(at: PixelPoint(x: 130, y: 110)); view.refresh()
        guard NSCursor.current === NSCursor.arrow else { throw Verification.Failure(description: "Selection did not use the move arrow") }
        model.acceptSelection(); model.chooseTool(.pencil); view.refresh()
        guard NSCursor.current !== NSCursor.arrow else { throw Verification.Failure(description: "Tool cursor was not restored after committing selection") }
        checks.append("cursor survives canvas re-entry and returns to the arrow over palette, selection, help, menu and page overview")
        try NSBitmapImageRep(cgImage: sheet.scaled(width: 640, height: sheet.height * 2).cgImage())
            .representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Cursors.png"))
        try JSONSerialization.data(withJSONObject: ["result": "passed", "cases": observations], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Cursors.json"))
        return checks
    }

    private static func contrastingPixels(cursor: NSCursor, background: Bitmap, point: PixelPoint,
                                         viewScale: CGFloat) throws -> Int {
        guard let data = cursor.image.tiffRepresentation, let rep = NSBitmapImageRep(data: data) else {
            throw Verification.Failure(description: "Cannot inspect actual AppKit cursor image")
        }
        var count = 0, opaque = 0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.99 else { continue }
            opaque += 1
            let bx = point.x + Int(floor((CGFloat(x) * cursor.image.size.width / CGFloat(rep.pixelsWide) - cursor.hotSpot.x) / viewScale))
            let by = point.y + Int(floor((CGFloat(y) * cursor.image.size.height / CGFloat(rep.pixelsHigh) - cursor.hotSpot.y) / viewScale))
            let value: CGFloat = background[bx, by] ? 0 : 1
            if abs(color.redComponent - value) > 0.8 { count += 1 }
        } }
        if count == 0 { print("Cursor has \(opaque) opaque pixels; \(count) contrast with the canvas") }
        return count
    }

    private static func drawCursor(_ cursor: NSCursor, into bitmap: inout Bitmap, at point: PixelPoint, viewScale: CGFloat) throws {
        guard let data = cursor.image.tiffRepresentation, let rep = NSBitmapImageRep(data: data) else {
            throw Verification.Failure(description: "Cannot render actual AppKit cursor image")
        }
        let width = Int(cursor.image.size.width / viewScale), height = Int(cursor.image.size.height / viewScale)
        for y in 0..<height { for x in 0..<width {
            let color = rep.colorAt(x: x * rep.pixelsWide / width, y: y * rep.pixelsHigh / height)!.usingColorSpace(.deviceRGB)!
            if color.alphaComponent > 0.99 { bitmap[point.x + x, point.y + y] = color.redComponent < 0.5 }
        } }
    }
}
