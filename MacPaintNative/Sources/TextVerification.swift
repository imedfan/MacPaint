import AppKit

enum TextVerification {
    static func keyboard(controller: AppController) throws -> [String] {
        let model = controller.model!, window = controller.window!, view = controller.workspace!
        model.newDocument(); model.setOrigin(.zero); model.textFont = "Monaco"; model.textSize = 9
        model.textStyle = 0; model.textAlignment = 0; model.chooseTool(.text)
        defer { model.newDocument(); model.setOrigin(.zero); model.textFont = "Geneva"; model.textSize = 12; model.chooseTool(.brush) }
        window.makeFirstResponder(view)
        model.begin(at: PixelPoint(x: 40, y: 60)); view.refresh()
        func send(_ code: UInt16, _ characters: String) {
            window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, characters: characters,
                                             charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
        }
        send(0, "A"); send(11, "B"); send(8, "C")
        guard model.text == "ABC" else { throw Verification.Failure(description: "native keyboard routing lost typed characters: \(model.text)") }
        let committed = model.bitmap
        send(76, "\u{3}"); send(2, "D")
        guard model.text == "D", model.textOrigin?.x == 58 else {
            throw Verification.Failure(description: "keypad Enter must continue after ABC at x=58; actual \(String(describing: model.textOrigin)), \(model.text)")
        }
        send(51, "\u{8}")
        guard model.text.isEmpty && model.bitmap == committed else { throw Verification.Failure(description: "backspace damaged the committed run after keypad Enter") }
        send(123, "\u{F702}"); send(48, "\t"); send(53, "\u{1b}")
        guard model.text.isEmpty && model.textOrigin != nil else { throw Verification.Failure(description: "control keys inserted private glyphs or ended live text") }
        send(36, "\r"); send(5, "G")
        guard model.text == "\nG", model.textCaretRect?.x == 46 else { throw Verification.Failure(description: "Return after keypad Enter lost the original left margin") }
        return ["real window keyboard input supports typing, keypad Enter, backspace and Return with the original left margin",
                "arrow, Tab and Escape keys do not add control glyphs to live text"]
    }

    static func run(controller: AppController, output: URL) throws -> [String] {
        let model = controller.model!, board = NSPasteboard.withUniqueName()
        defer {
            board.releaseGlobally(); model.newDocument(); model.setOrigin(.zero)
            model.textFont = "Geneva"; model.textSize = 12; model.textStyle = 0; model.textAlignment = 0
            model.grid = false; model.chooseTool(.brush)
        }
        var checks = [String]()
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func reset() {
            model.newDocument(); model.setOrigin(.zero); model.textFont = "Geneva"; model.textSize = 12
            model.textStyle = 0; model.textAlignment = 0; model.grid = false
        }
        reset(); board.setString("MacPaint native text", forType: .string)
        try controller.pasteSelection(pasteboard: board)
        try check(model.tool == .selection && model.selection != nil && model.textOrigin == nil,
                  "text paste must be a floating selection without an insertion caret; actual tool=\(model.tool.name), selection=\(model.selection != nil)")
        let original = model.selection!, frame = original.rect
        controller.perform("font:Courier")
        try check(model.selection?.rect == frame && model.selection?.pixels != original.pixels,
                  "Font command redraws pasted text inside its existing frame")
        let beforeSize = model.selection!.pixels
        controller.perform("size:24")
        try check(model.selection?.rect == frame && model.selection?.pixels != beforeSize,
                  "FontSize command redraws text scrap without moving its frame")
        try check(controller.workspace.menus[4].items.allSatisfy(\.enabled) && controller.workspace.menus[5].items.allSatisfy(\.enabled),
                  "font and size menus remain enabled for pasted text selection")
        reset(); model.bitmap[10, 10] = true
        model.chooseTool(.selection); model.begin(at: PixelPoint(x: 100, y: 80)); model.end(at: PixelPoint(x: 220, y: 140))
        board.clearContents(); board.setString("ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT", forType: .string)
        try controller.pasteSelection(pasteboard: board)
        try check(model.selection?.rect == PixelRect(x: 100, y: 80, width: 120, height: 60),
                  "text paste uses existing rectangular selection as its text box")
        let wide = model.selection!.pixels
        model.begin(at: PixelPoint(x: 218, y: 138), modifiers: .command)
        model.end(at: PixelPoint(x: 150, y: 138), modifiers: .command)
        try check(model.selection?.pixels.width == 52 && model.selection?.pixels.height == 60 && model.selection?.pixels != wide.scaled(width: 52, height: 60),
                  "Command-stretch reflows text instead of scaling its old pixels")
        try check(model.bitmap[10, 10], "text box reflow preserves pixels outside its frame")
        try controller.copySelection(cut: false, pasteboard: board)
        try check(board.data(forType: .png) != nil && board.string(forType: .string) == nil,
                  "copying a text scrap publishes a picture as original CutOrCopy does")
        reset(); try controller.pasteSelection(pasteboard: board); controller.refreshMenus()
        try check(model.selection != nil && !controller.workspace.menus[4].items[0].enabled,
                  "copied text picture pastes as raster and disables font menus")
        reset(); model.bitmap[12, 12] = true
        let baseline = model.bitmap
        board.clearContents(); board.setString("Undo this text", forType: .string)
        try controller.pasteSelection(pasteboard: board)
        let pasted = model.displayBitmap
        model.undo()
        try check(model.displayBitmap == baseline, "Undo after text paste restores every previous pixel")
        model.undo()
        try check(model.displayBitmap == pasted && model.textOrigin == nil,
                  "toggle Undo restores pasted text pixels without a typing caret")
        reset(); model.textFont = "Monaco"; model.textSize = 9; model.chooseTool(.text)
        model.begin(at: PixelPoint(x: 40, y: 60)); model.updateText("ABC"); controller.workspace.refresh()
        let mono = model.resources.font(named: "Monaco", size: 9).font
        let caretX = 80 + 40 + mono.width(of: "ABC"), top = 48 + 60 - mono.ascent
        let screen = controller.workspace.renderWorkspace()
        let caretPixels = (top..<(top + mono.ascent + mono.descent)).filter { screen[caretX, $0] }.count
        try check(caretPixels == mono.ascent + mono.descent,
                  "caret after ABC expected \(mono.ascent + mono.descent) black pixels at advance end, actual \(caretPixels)")
        try JSONSerialization.data(withJSONObject: ["checks": checks, "scope": "native pasteboard and actual menu commands with bitmap selection assertions"], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Text.json"))
        return checks
    }
}
