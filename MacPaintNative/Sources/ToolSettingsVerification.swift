import AppKit

enum ToolSettingsVerification {
    static func run(controller: AppController, output: URL) throws -> [String] {
        let model = controller.model!, view = controller.workspace!, window = controller.window!
        defer {
            model.newDocument(); model.setOrigin(.zero); model.lineWidth = 1; model.brushIndex = 7
            model.border = true; model.chooseTool(.brush)
        }
        func event(_ type: NSEvent.EventType, x: Int, y: Int) -> NSEvent {
            let scale = max(1, min(floor(view.bounds.width / 512), floor(view.bounds.height / 342)))
            let offset = NSPoint(x: floor((view.bounds.width - 512 * scale) / 2), y: floor((view.bounds.height - 342 * scale) / 2))
            return NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: offset.x + CGFloat(x) * scale, y: offset.y + CGFloat(y) * scale), to: nil),
                                     modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                     context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func click(x: Int, y: Int) {
            window.sendEvent(event(.leftMouseDown, x: x, y: y)); window.sendEvent(event(.leftMouseUp, x: x, y: y))
        }
        var checks = [String](), measurements = [[String: Int]]()
        for (width, y) in [(1, 281), (2, 292), (4, 303), (8, 319)] {
            model.newDocument(); model.setOrigin(.zero)
            click(x: 28, y: 127); click(x: 45, y: y)
            window.sendEvent(event(.leftMouseDown, x: 120, y: 128))
            window.sendEvent(event(.leftMouseDragged, x: 200, y: 128))
            window.sendEvent(event(.leftMouseUp, x: 200, y: 128))
            let height = model.bitmap.blackBounds?.height ?? 0
            guard model.lineWidth == width, height == width else {
                throw Verification.Failure(description: "Thickness palette chose \(model.lineWidth); expected stroke \(width) pixels, actual \(height)")
            }
            measurements.append(["lineSetting": width, "linePixels": height])
        }
        checks.append("mouse-selected line settings draw strokes of exactly 1, 2, 4 and 8 document pixels")
        model.newDocument(); model.setOrigin(.zero)
        click(x: 55, y: 105); click(x: 45, y: 319)
        window.sendEvent(event(.leftMouseDown, x: 120, y: 128)); window.sendEvent(event(.leftMouseUp, x: 200, y: 128))
        guard model.tool == .pencil, model.lineWidth == 8, model.bitmap.blackBounds?.height == 1 else {
            throw Verification.Failure(description: "Pencil must remain one pixel with line width 8; actual \(String(describing: model.bitmap.blackBounds))")
        }
        checks.append("Pencil remains one pixel when thickness palette is set to eight, as in original PencilPaint")
        for (index, expectedSize) in [(0, 16), (3, 4), (27, 1)] {
            model.newDocument(); model.setOrigin(.zero); model.chooseTool(.brush)
            var selected = false
            var target = "No brush click posted"
            let deadline = Date().addingTimeInterval(2)
            let timer = Timer(timeInterval: 0.02, repeats: true) { timer in
                if let panel = NSApp.modalWindow, let dialog = panel.contentView as? ClassicDialogView, dialog.kind == "brush" {
                    let point = NSPoint(x: CGFloat(32 + index / 4 * 32) * dialog.bounds.width / CGFloat(dialog.logicalRect.width),
                                        y: CGFloat(32 + index % 4 * 32) * dialog.bounds.height / CGFloat(dialog.logicalRect.height))
                    let location = dialog.convert(point, to: nil)
                    target = "point=\(point), bounds=\(dialog.bounds), frame=\(dialog.frame), window=\(panel.windowNumber)"
                    let click = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    NSApp.postEvent(click, atStart: false); selected = true; timer.invalidate()
                } else if Date() > deadline { timer.invalidate(); NSApp.abortModal() }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            controller.perform("brush")
            timer.invalidate()
            guard selected, model.brushIndex == index else {
                throw Verification.Failure(description: "Brush Shape dialog failed to select brush \(index); actual \(model.brushIndex), posted=\(selected), \(target)")
            }
            model.begin(at: PixelPoint(x: 100, y: 100)); model.end(at: PixelPoint(x: 100, y: 100))
            guard let bounds = model.bitmap.blackBounds, bounds.width == expectedSize, bounds.height == expectedSize else {
                throw Verification.Failure(description: "Brush \(index) should stamp \(expectedSize)x\(expectedSize); actual \(String(describing: model.bitmap.blackBounds))")
            }
            checks.append("real Brush Shape dialog selects \(expectedSize)x\(expectedSize) brush independently of line width")
        }
        try JSONSerialization.data(withJSONObject: ["checks": checks, "lineMeasurements": measurements], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("ToolSettings.json"))
        return checks
    }
}
