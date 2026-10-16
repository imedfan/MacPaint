import AppKit

final class CatalogPrintView: NSView {
    let catalog: PaintCatalog
    init(catalog: PaintCatalog) {
        self.catalog = catalog
        super.init(frame: NSRect(x: 0, y: 0, width: 576, height: catalog.pageCount * 720))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: catalog.pageCount)
        return true
    }
    override func rectForPage(_ page: Int) -> NSRect {
        guard (1...max(1, catalog.pageCount)).contains(page), catalog.pageCount > 0 else { return .zero }
        return NSRect(x: 0, y: (page - 1) * 720, width: 576, height: 720)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); dirtyRect.fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        for page in 0..<catalog.pageCount {
            let rect = NSRect(x: 0, y: page * 720, width: 576, height: 720)
            guard rect.intersects(dirtyRect) else { continue }
            let image = NSImage(cgImage: catalog.raster(page: page).cgImage(), size: rect.size)
            image.draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
