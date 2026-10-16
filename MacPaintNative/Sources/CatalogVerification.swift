import AppKit
import PDFKit

enum CatalogVerification {
    static func model(resources: ClassicResources, output: URL) throws -> [String] {
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        let blank = Bitmap(), whiteThumbnail = Bitmap(width: 72, height: 90)
        try check(PrintRaster.catalog(blank) == whiteThumbnail, "Catalog halftone keeps an empty document white")
        var black = Bitmap(); black.fill(black.bounds, pattern: .black)
        var blackThumbnail = whiteThumbnail; blackThumbnail.fill(blackThumbnail.bounds, pattern: .black)
        try check(PrintRaster.catalog(black) == blackThumbnail, "Catalog halftone keeps a solid document black")
        var block = Bitmap(); block.fill(PixelRect(x: 16, y: 24, width: 8, height: 8), pattern: .black)
        var dot = whiteThumbnail; dot[2, 4] = true
        try check(PrintRaster.catalog(block) == dot, "Catalog uses the original delayed sample row rather than nearest-pixel scaling")
        block = Bitmap(); block.fill(PixelRect(x: 0, y: 0, width: 8, height: 8), pattern: .black)
        var corner = whiteThumbnail; corner[0, 0] = true; corner[1, 0] = true; corner[0, 1] = true
        try check(PrintRaster.catalog(block) == corner, "Catalog diffuses the signed first-row error with the original clipping and arithmetic shifts")
        block = Bitmap(); block.fill(PixelRect(x: 0, y: 712, width: 8, height: 8), pattern: .black)
        try check(PrintRaster.catalog(block) == whiteThumbnail, "Catalog retains GetCatPic's final sample-row phase")
        let fixtures = output.appendingPathComponent("Catalog-Fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        let valid = MacPaintFile.encode(blank, patterns: resources.patterns)
        for name in ["A.mac", "B", "Paint1", "Paint2"] { try valid.write(to: fixtures.appendingPathComponent(name)) }
        try Data("Not a drawing".utf8).write(to: fixtures.appendingPathComponent("Invalid.mac"))
        try FileManager.default.createDirectory(at: fixtures.appendingPathComponent("Folder.mac"), withIntermediateDirectories: true)
        let loaded = try PaintCatalog.load(directory: fixtures, resources: resources)
        try check(loaded.items.map(\.name) == ["A.mac", "B"], "Catalog reads valid MacPaint files without requiring extensions and excludes work files and directories")
        let snapshot = try Data(contentsOf: fixtures.appendingPathComponent("A.mac"))
        try check(snapshot == valid && loaded.header == "MacPaint documents on disk Catalog-Fixtures",
                  "Catalog reads the original heading resource and leaves the source document unchanged")
        let empty = PaintCatalog(pictures: [], folderName: "Disk", resources: resources)
        try check(empty.pageCount == 0, "An empty catalog generates no blank printed page")
        let one = PaintCatalog(pictures: [("A", blank)], folderName: "Disk", resources: resources)
        let page = one.raster(page: 0)
        try check(page[28, 32] && page[99, 121] && !page[29, 33], "Catalog's first thumbnail is framed at the original 28,32 position with 72x90 dimensions")
        var caption = Bitmap(width: 112, height: 22)
        resources.fonts["Geneva"]![12]!.draw("A", in: &caption, at: PixelPoint(x: 64 - resources.fonts["Geneva"]![12]!.width(of: "A") / 2, y: 16))
        try check(page.cropped(to: PixelRect(x: 0, y: 122, width: 112, height: 22)) == caption,
                  "Catalog centers each filename in original Geneva 12 at baseline 138")
        let many = PaintCatalog(pictures: Array(repeating: ("", blank), count: 26), folderName: "Disk", resources: resources)
        let first = many.raster(page: 0), second = many.raster(page: 1)
        try check(many.pageCount == 2 && first[476, 32] && first[28, 608] && first[476, 608] && !first[100, 33],
                  "Catalog fits five columns and five 144-pixel rows on each 576x720 page")
        var last = Bitmap(); last.frame(PixelRect(x: 28, y: 32, width: 72, height: 90))
        try check(second == last, "Catalog places drawing 26 on page two without repeating the first-page heading")
        for (count, pages) in [(5, 1), (25, 1), (50, 2), (51, 3)] {
            try check(PaintCatalog(pictures: Array(repeating: ("", blank), count: count), folderName: "Disk", resources: resources).pageCount == pages,
                      "Catalog of \(count) drawings occupies exactly \(pages) original pages")
        }
        return checks
    }

    static func window(controller: AppController, output: URL) throws -> [String] {
        let resources = controller.model.resources
        defer { controller.model.newDocument(); controller.model.chooseTool(.brush); controller.workspace.refresh() }
        var source = Bitmap(); source.frame(PixelRect(x: 48, y: 48, width: 480, height: 624))
        source.fill(PixelRect(x: 120, y: 160, width: 168, height: 120), pattern: .gray)
        let pictures = (1...26).map { (String(format: "Drawing %02d", $0), source) }
        let catalog = PaintCatalog(pictures: pictures, folderName: "Test Disk", resources: resources)
        let operation = controller.catalogPrintOperation(catalog)
        let view = operation.view as! CatalogPrintView
        var checks = [String]()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        guard view.frame.height == 1440 else {
            throw Verification.Failure(description: "Catalog with 26 drawings: expected two 720-pixel pages (1440 total), actual height \(view.frame.height)")
        }
        checks.append("Catalog places 26 drawings on two original five-by-five pages")
        var range = NSRange()
        try check(view.knowsPageRange(&range) && range == NSRange(location: 1, length: 2)
                  && view.rectForPage(2) == NSRect(x: 0, y: 720, width: 576, height: 720),
                  "AppKit receives explicit catalog page boundaries")
        let before = controller.model.displayBitmap, origin = controller.model.origin, palette = controller.model.patterns
        let destination = output.appendingPathComponent("Print-Catalog.pdf")
        let info = operation.printInfo
        info.paperSize = NSSize(width: 576, height: 720)
        info.leftMargin = 0; info.rightMargin = 0; info.topMargin = 0; info.bottomMargin = 0
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = destination
        operation.showsPrintPanel = false; operation.showsProgressPanel = false
        try check(operation.run(), "Native NSPrintOperation saves the catalog as a PDF job")
        guard let pdf = PDFDocument(url: destination), pdf.pageCount == 2 else {
            throw Verification.Failure(description: "Native catalog PDF must contain two pages")
        }
        try check(pdf.page(at: 0)!.bounds(for: .mediaBox).size == NSSize(width: 576, height: 720)
                  && pdf.page(at: 1)!.bounds(for: .mediaBox).size == NSSize(width: 576, height: 720),
                  "Native catalog PDF retains the exact original page size on both pages")
        for page in 0..<2 {
            let bitmap = catalog.raster(page: page)
            try NSBitmapImageRep(cgImage: bitmap.cgImage()).representation(using: .png, properties: [:])!
                .write(to: output.appendingPathComponent("Catalog-Page-\(page + 1).png"))
        }
        try check(controller.model.displayBitmap == before && controller.model.origin == origin && controller.model.patterns == palette,
                  "Catalog PDF generation leaves current drawing, viewport and palette unchanged")
        controller.model.newDocument(); controller.model.setOrigin(PixelPoint(x: 21, y: 37))
        controller.model.chooseTool(.text); controller.model.begin(at: PixelPoint(x: 100, y: 100)); controller.model.updateText("Catalog")
        let typed = controller.model.displayBitmap, url = controller.documentURL
        var cancelled = false, folderPicker = false
        let deadline = Date().addingTimeInterval(6)
        let timer = Timer(timeInterval: 0.03, repeats: true) { timer in
            if let panel = NSApp.modalWindow as? NSOpenPanel {
                folderPicker = panel.canChooseDirectories && !panel.canChooseFiles
                cancelled = true; timer.invalidate(); panel.cancel(nil)
                if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: controller.window.windowNumber, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(wake, atStart: false) }
            } else if Date() > deadline { timer.invalidate(); NSApp.abortModal() }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        controller.perform("printCatalog"); timer.invalidate()
        try check(cancelled && folderPicker, "Print Catalog presents a native folder picker whose public Cancel action works")
        try check(controller.model.displayBitmap == typed && controller.model.isDirty && controller.model.origin == PixelPoint(x: 21, y: 37)
                  && controller.documentURL == url && controller.model.textOrigin == nil && controller.model.undoState == nil,
                  "Catalog cancellation retains drawing, filename and viewport, accepting live edits as the original File menu does")
        try JSONSerialization.data(withJSONObject: ["checks": checks, "count": checks.count,
            "scope": "Original source raster and native NSPrintOperation PDF job; physical printer output is not tested."],
            options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Catalog.json"))
        return checks
    }
}
