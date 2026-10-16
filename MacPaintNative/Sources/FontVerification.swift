import AppKit

enum FontVerification {
    static func model(resources: ClassicResources) throws -> [String] {
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        let renderer = BitmapText(resources: resources, name: "Geneva", size: 36, style: 0)
        let actual = renderer.width(of: "MacPaint")
        guard actual == 160, renderer.font.bytes == resources.fonts["Geneva"]![18]!.bytes else {
            throw Verification.Failure(description: "Geneva 36 must double the 18-point strike: expected MacPaint width 160, actual \(actual), scale \(renderer.scale)")
        }
        checks.append("Geneva 36 doubles the 18-point strike and gives MacPaint a width of 160 pixels")
        let requests = [9, 10, 12, 14, 18, 24, 36, 48, 72]
        let expected = [
            ("Chicago", [12, 12, 12, 12, 12, 12, 12, 12, 12]),
            ("Geneva", [9, 10, 12, 14, 18, 24, 18, 24, 24]),
            ("New York", [9, 10, 12, 14, 18, 24, 18, 24, 24]),
            ("Monaco", [9, 12, 12, 12, 9, 12, 12, 12, 12]),
            ("Times", [9, 10, 12, 14, 18, 24, 18, 24, 24]),
            ("Helvetica", [9, 10, 12, 14, 18, 24, 18, 24, 24]),
            ("Courier", [9, 10, 12, 14, 18, 24, 18, 24, 24])]
        for (name, strikes) in expected {
            for (request, strike) in zip(requests, strikes) {
                let selected = resources.font(named: name, size: request)
                guard selected.font.bytes == resources.fonts[name]![strike]!.bytes,
                      selected.scale == Double(request) / Double(strike) else {
                    throw Verification.Failure(description: "\(name) \(request): expected \(strike)-point strike, actual scale \(selected.scale)")
                }
            }
            checks.append("\(name) uses the original Font Manager strike for all nine menu sizes")
        }
        var source = Bitmap(width: 200, height: 48)
        resources.fonts["Geneva"]![18]!.draw("MacPaint", in: &source, at: PixelPoint(x: 8, y: 24))
        let doubled = source.scaled(width: 400, height: 96)
        var rendered = Bitmap(width: 400, height: 96)
        renderer.draw("MacPaint", in: &rendered, at: PixelPoint(x: 16, y: 48), clip: rendered.bounds)
        try check(rendered == doubled, "Geneva 36 renders every glyph pixel as an exact 2x copy of the original 18-point strike")
        try check(renderer.wrappedLines("MacPaint MacPaint", width: 160) == ["MacPaint ", "MacPaint"],
                  "Geneva 36 wraps at the word boundary in a 160-pixel text box")
        try check(BitmapText(resources: resources, name: "Monaco", size: 18, style: 0).width(of: "ABC") == 36,
                  "Monaco 18 doubles the nine-point ABC advance to 36 pixels")
        try check(BitmapText(resources: resources, name: "Monaco", size: 10, style: 0).width(of: "ABC") == 18,
                  "Monaco 10 scales the next larger strike and rounds the text width to 18 pixels")
        try check(resources.font(named: "Monaco", size: 6).font.bytes == resources.fonts["Monaco"]![12]!.bytes,
                  "Font Manager prefers an available double-size strike before other nearby sizes")
        try check(resources.fonts["Geneva"]?.count == 12 && resources.font(named: "Geneva", size: 16).scale == 1,
                  "Font lookup includes every recovered Geneva strike, including the original 16-point font")
        try check(resources.font(named: "Unavailable", size: 36).font.bytes == resources.fonts["Geneva"]![18]!.bytes,
                  "An unavailable font falls back to the application font with the same original scaling search")
        return checks
    }

    static func window(controller: AppController, output: URL) throws -> [String] {
        let model = controller.model!, view = controller.workspace!, window = controller.window!
        let frame = window.frame
        defer {
            model.newDocument(); model.textFont = "Geneva"; model.textSize = 12; model.textStyle = 0
            model.chooseTool(.brush); window.setFrame(frame, display: true); view.refresh()
        }
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func mouse(_ type: NSEvent.EventType, _ x: Int, _ y: Int) {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: view.convert(view.viewPoint(PixelPoint(x: x, y: y)), to: nil),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        }
        func click(_ x: Int, _ y: Int) { mouse(.leftMouseDown, x, y); mouse(.leftMouseUp, x, y) }
        for scale in [2, 1] {
            window.setContentSize(NSSize(width: 512 * scale, height: 342 * scale))
            window.makeFirstResponder(view)
            view.pageOverview = false; view.popup = nil; view.helpID = nil
            model.newDocument(); model.setOrigin(.zero); model.textFont = "Geneva"; model.textSize = 12
            model.textStyle = 0; model.textAlignment = 0; model.grid = false
            view.refresh()
            click(55, 61); click(120, 108)
            for character in "MacPaint" {
                window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: String(character),
                    charactersIgnoringModifiers: String(character), isARepeat: false, keyCode: 0)!)
            }
            let menuX = 10 + view.menus.prefix(5).reduce(0) { $0 + model.resources.chicago.width(of: $1.title) + 14 }
            click(menuX + 5, 10); click(menuX + 10, 20 + 3 + 6 * 18 + 8)
            try check(model.textSize == 36 && model.text == "MacPaint", "Classic FontSize menu redraws typed text at 36 points at \(scale)x")
            var expected = Bitmap(width: 288, height: 360)
            model.resources.fonts["Geneva"]![18]!.draw("MacPaint", in: &expected, at: PixelPoint(x: 20, y: 30))
            try check(model.bitmap == expected.scaled(width: 576, height: 720),
                      "Native text input displays the doubled 18-point glyphs after FontSize change at \(scale)x")
            try check(model.textCaretRect == PixelRect(x: 200, y: 24, width: 1, height: 44),
                      "Geneva 36 caret follows the corrected 160-pixel advance and original metrics at \(scale)x")
            view.displayIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw Verification.Failure(description: "Scaled font view snapshot unavailable")
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Font-Geneva-36-\(scale)x.png"))
        }
        try JSONSerialization.data(withJSONObject: ["checks": checks, "count": checks.count,
            "scope": "Original FONT strike pixels, real NSWindow typing and classic menu clicks at 1x and 2x. Fractional glyph scaling still needs reference comparison."],
            options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Font-Sizes.json"))
        return checks
    }
}
