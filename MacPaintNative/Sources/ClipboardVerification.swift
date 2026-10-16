import AppKit

enum ClipboardVerification {
    static func run(controller: AppController, output: URL) throws -> [String] {
        let model = controller.model!, view = controller.workspace!
        let board = NSPasteboard.withUniqueName()
        defer {
            board.releaseGlobally()
            model.newDocument(); model.setOrigin(.zero); model.grid = false; model.chooseTool(.brush)
            view.documentOpen = true
        }
        var checks = [String]()
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func reset() { model.newDocument(); model.setOrigin(.zero); model.grid = false }
        func image(_ bitmap: Bitmap, text: String? = nil) throws {
            let item = NSPasteboardItem()
            item.setData(NSBitmapImageRep(cgImage: bitmap.cgImage()).representation(using: .png, properties: [:])!, forType: .png)
            if let text { item.setString(text, forType: .string) }
            board.clearContents()
            try check(board.writeObjects([item]), "native pasteboard accepts image fixture")
        }
        reset(); model.chooseTool(.text); model.begin(at: PixelPoint(x: 20, y: 40)); model.updateText("still typing")
        board.setString("preserve clipboard", forType: .string)
        let count = board.changeCount
        try controller.copySelection(cut: false, pasteboard: board)
        try check(board.changeCount == count && board.string(forType: .string) == "preserve clipboard" && model.text == "still typing",
                  "Copy without selection must leave clipboard and live text untouched; pasteboard changed from \(count) to \(board.changeCount)")
        reset(); model.bitmap[5, 5] = true
        model.bitmap.fill(PixelRect(x: 20, y: 20, width: 8, height: 6), pattern: .gray)
        model.chooseTool(.selection); model.begin(at: PixelPoint(x: 20, y: 20)); model.end(at: PixelPoint(x: 28, y: 26))
        let original = model.displayBitmap, copied = model.selection!.pixels
        try controller.copySelection(cut: false, pasteboard: board)
        try check(model.displayBitmap == original && model.selection != nil && board.data(forType: .png) != nil,
                  "Copy publishes PNG without altering selected pixels")
        try controller.copySelection(cut: true, pasteboard: board)
        try check(model.selection == nil && model.bitmap.cropped(to: PixelRect(x: 20, y: 20, width: 8, height: 6)) == Bitmap(width: 8, height: 6) && model.bitmap[5, 5],
                  "Cut removes only selection after copying it")
        model.undo()
        try check(model.displayBitmap == original, "Undo restores cut selection")
        model.newDocument()
        try controller.pasteSelection(pasteboard: board)
        try check(model.selection?.pixels == copied && model.selection?.origin == PixelPoint(x: 284, y: 237),
                  "picture paste centers in scrolled window with original coordinates")
        reset(); model.bitmap[5, 5] = true
        model.chooseTool(.selection); model.begin(at: PixelPoint(x: 100, y: 80)); model.end(at: PixelPoint(x: 120, y: 90))
        let beforePaste = model.displayBitmap
        try controller.pasteSelection(pasteboard: board)
        try check(model.selection?.rect == PixelRect(x: 100, y: 80, width: 20, height: 10) && model.selection?.pixels == copied.scaled(width: 20, height: 10),
                  "picture paste stretches into existing rectangular selection")
        model.undo()
        try check(model.displayBitmap == beforePaste, "Undo restores image beneath pasted picture")
        reset()
        var pixels = Bitmap(width: 5, height: 5), mask = pixels
        pixels.fill(pixels.bounds, pattern: .black); pixels[2, 2] = false
        mask.fill(PixelRect(x: 1, y: 1, width: 3, height: 3), pattern: .black); mask[0, 2] = true
        model.selection = FloatingSelection(pixels: pixels, mask: mask, origin: .zero, kind: .lasso)
        try controller.copySelection(cut: false, pasteboard: board)
        let png = NSBitmapImageRep(data: board.data(forType: .png)!)!
        try check(png.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!.redComponent > 0.9,
                  "lasso PNG excludes black pixels outside its mask")
        reset(); try controller.pasteSelection(pasteboard: board)
        try check(model.selection?.isLasso == true && model.tool == .lasso && model.selection?.mask == mask,
                  "native clipboard preserves lasso kind and exact mask")
        try check(model.selection?.pixels[2, 2] == false && model.selection?.mask[2, 2] == true,
                  "lasso clipboard retains enclosed white pixels")
        reset()
        try image(copied, text: "image takes precedence")
        model.toggleFatBits(at: PixelPoint(x: 208, y: 120))
        try controller.pasteSelection(pasteboard: board)
        try check(model.fatBits && model.selection?.rect == PixelRect(x: 204, y: 117, width: 8, height: 6) && model.selection?.pixels == copied,
                  "picture wins over text and centers in FatBits without leaving zoom")
        reset(); try image(Bitmap(width: 49, height: 10))
        model.toggleFatBits(at: PixelPoint(x: 208, y: 120)); try controller.pasteSelection(pasteboard: board)
        try check(!model.fatBits && model.selection?.rect == PixelRect(x: 183, y: 115, width: 49, height: 10),
                  "picture wider than original 48-pixel FatBits limit exits zoom")
        model.newDocument(); model.grid = true; try image(Bitmap(width: 13, height: 9))
        try controller.pasteSelection(pasteboard: board)
        try check(model.selection?.origin == PixelPoint(x: 280, y: 232), "new picture center follows original eight-pixel grid rounding")
        model.newDocument(); model.grid = false; model.bitmap[20, 20] = true
        var fullPage = Bitmap(); fullPage.fill(fullPage.bounds, pattern: .gray)
        try image(fullPage); try controller.pasteSelection(pasteboard: board)
        try check(model.selection?.rect == model.visibleRect && model.selection?.pixels == fullPage.cropped(to: PixelRect(x: 80, y: 240, width: 416, height: 240)),
                  "oversized picture is centered then clipped to visible window")
        model.acceptSelection()
        try check(model.bitmap[20, 20] && !model.bitmap[79, 120] && !model.bitmap[496, 120],
                  "oversized picture never overwrites the hidden page")
        model.newDocument(); model.setOrigin(PixelPoint(x: 160, y: 480))
        var oddPicture = Bitmap(width: 577, height: 721)
        oddPicture[81, 241] = true
        try image(oddPicture); try controller.pasteSelection(pasteboard: board)
        try check(model.selection?.pixels == oddPicture.cropped(to: PixelRect(x: 81, y: 241, width: 416, height: 240)),
                  "odd oversized picture center: expected black pixel at (0,0), actual ink bounds \(String(describing: model.selection?.pixels.blackBounds))")
        let preserved = model.displayBitmap
        board.clearContents(); board.setData(Data([0, 0, 0, 0]), forType: NSPasteboard.PasteboardType("org.macpaintnative.selection"))
        do {
            try controller.pasteSelection(pasteboard: board)
            throw Verification.Failure(description: "malformed private clipboard payload was silently accepted")
        } catch is ClipboardError { checks.append("invalid clipboard dimensions report a format error") }
        try check(model.displayBitmap == preserved, "invalid clipboard payload preserves current drawing")
        try JSONSerialization.data(withJSONObject: ["checks": checks, "pasteboard": board.name.rawValue, "scope": "real named NSPasteboard; system general clipboard remains untouched"],
                                   options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Clipboard.json"))
        return checks
    }
}
