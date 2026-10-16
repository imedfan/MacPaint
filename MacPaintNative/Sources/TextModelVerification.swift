import Foundation

/// Exercises only document state and one-bit raster output. No NSApplication,
/// NSWindow, pasteboard, or WindowServer is involved in these checks.
enum TextModelVerification {
    static func run(resources: ClassicResources) throws -> [String] {
        let model = PaintModel(resources: resources)
        var checks = [String]()
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func reset() {
            model.newDocument(); model.setOrigin(.zero)
            model.textFont = "Monaco"; model.textSize = 9; model.textStyle = 0; model.textAlignment = 0; model.grid = false
        }
        reset(); model.chooseTool(.text)
        let font = resources.font(named: "Monaco", size: 9).font
        model.begin(at: PixelPoint(x: 40, y: 60)); model.updateText("ABC")
        let width = font.width(of: "ABC")
        try check(model.textCaretRect == PixelRect(x: 40 + width, y: 60 - font.ascent, width: 1, height: font.ascent + font.descent),
                  "typing caret follows glyph advances and font height")
        model.textAlignment = 1; model.updateText(model.text)
        try check(model.textCaretRect?.x == 40 - width / 2 + width, "center-aligned caret follows the rendered line")
        model.textAlignment = 2; model.updateText(model.text)
        try check(model.textCaretRect?.x == 40, "right-aligned caret ends at the anchor")
        model.textAlignment = 0; model.updateText(model.text)
        let firstLine = model.bitmap
        model.continueText()
        try check(model.text.isEmpty && model.textOrigin == PixelPoint(x: 40 + width, y: 60) && model.bitmap == firstLine,
                  "keypad Enter commits the old run and places a new caret at its end")
        model.updateText("DEF\nG")
        try check(model.textCaretRect?.x == 40 + font.width(of: "G") && model.textCaretRect?.y == 60 + font.ascent + font.descent + font.leading - font.ascent,
                  "Return after keypad Enter preserves the original left margin")
        model.updateText("")
        try check(model.bitmap == firstLine, "deleting the continuation preserves the previous committed run")
        model.commitText(); try check(model.textCaretRect == nil, "committing text removes the typing caret")
        reset(); model.grid = true; model.chooseTool(.text)
        model.begin(at: PixelPoint(x: 40, y: 64)); model.updateText("A\nB")
        let gridHeight = (font.ascent + font.descent + font.leading + 7) & ~7
        try check(model.textCaretRect?.y == 64 + gridHeight - font.ascent, "typed line spacing rounds up to eight pixels on the grid")
        model.updateText("A"); model.continueText()
        let snappedEnd = (40 + font.width(of: "A") + 4) & ~7
        try check(model.textOrigin?.x == snappedEnd,
                  "keypad Enter on grid must snap continuation to x=\(snappedEnd), actual x=\(model.textOrigin?.x ?? -1)")
        reset(); model.bitmap[4, 4] = true
        let baseline = model.bitmap
        model.insertText("Native text scrap")
        guard let selected = model.selection else { throw Verification.Failure(description: "missing pasted text selection") }
        try check(selected.textScrap == "Native text scrap" && model.tool == .selection && model.textCaretRect == nil,
                  "pasted text is a floating text selection without a typing caret")
        let frame = selected.rect, pasted = model.displayBitmap
        model.textFont = "Geneva"; model.updateText("")
        try check(model.selection?.rect == frame && model.selection?.pixels != selected.pixels,
                  "font changes rerender text scrap inside the same frame")
        model.undo(); try check(model.displayBitmap == baseline, "Undo removes pasted text without losing the earlier drawing")
        model.undo(); try check(model.displayBitmap != baseline && model.selection?.textScrap == nil,
                                "toggle Undo restores text pixels without restoring editable text state")
        try check(pasted != baseline, "text scrap contains rendered ink")
        reset(); model.chooseTool(.selection)
        model.begin(at: PixelPoint(x: 100, y: 80)); model.end(at: PixelPoint(x: 220, y: 140))
        model.insertText("ONE TWO THREE FOUR FIVE SIX SEVEN")
        let wide = model.selection!.pixels
        model.begin(at: PixelPoint(x: 218, y: 138), modifiers: .command)
        model.end(at: PixelPoint(x: 150, y: 138), modifiers: .command)
        try check(model.selection?.rect == PixelRect(x: 100, y: 80, width: 52, height: 60) && model.selection?.pixels != wide.scaled(width: 52, height: 60),
                  "text selection stretch reflows words instead of scaling pixels")
        let reflowed = model.selection!, beforeMove = model.displayBitmap
        model.begin(at: PixelPoint(x: 120, y: 100)); model.end(at: PixelPoint(x: 140, y: 110))
        try check(model.selection?.origin == PixelPoint(x: 120, y: 90) && model.selection?.pixels == reflowed.pixels && model.selection?.textScrap != nil,
                  "moving text scrap retains its text and raster dimensions")
        model.undo(); try check(model.displayBitmap == beforeMove, "Undo of a moved text scrap restores its previous pixels")
        reset(); model.insertText(String(repeating: "A", count: 81) + "\n" + String(repeating: "B\n", count: 25))
        try check(model.selection?.textScrap?.count == 132, "pasted text is not truncated by the typed-text 80-character and 20-line limits")
        reset(); model.toggleFatBits(at: PixelPoint(x: 208, y: 120)); model.insertText("A")
        try check(model.fatBits && model.selection?.rect.intersect(model.activeRect) == model.selection?.rect,
                  "short text scrap remains clipped inside FatBits")
        reset(); model.toggleFatBits(at: PixelPoint(x: 208, y: 120)); model.insertText("This text is too wide for FatBits")
        try check(!model.fatBits, "wide text scrap leaves FatBits before centering")
        return checks
    }
}
