import Foundation

struct PageOverview {
    let image: Bitmap
    let originalOrigin: PixelPoint
    let initialViewport: PixelRect
    private(set) var viewport: PixelRect
    private(set) var imageShift = PixelPoint.zero
    private enum Axis { case free, pending, horizontal, vertical }
    private enum Target { case viewport(PixelPoint), image(PixelPoint) }
    private struct Drag {
        let start: PixelPoint
        let target: Target
        var previous: PixelPoint
        var axis: Axis
    }
    private var drag: Drag?

    init(bitmap: Bitmap, origin: PixelPoint) {
        originalOrigin = origin
        // QuickDraw Pictures.a MapRect maps both corners, rounding to nearest.
        let left = (origin.x + 1) / 3, top = (origin.y + 1) / 3
        initialViewport = PixelRect(x: left, y: top,
            width: (origin.x + 417) / 3 - left, height: (origin.y + 241) / 3 - top)
        viewport = initialViewport
        image = Self.reduce(bitmap)
    }

    private static func reduce(_ bitmap: Bitmap) -> Bitmap {
        var result = Bitmap(width: 192, height: 240)
        // ReadWrite shrinks fifteen 48-row bands separately. Stretch.a ORs
        // source bits horizontally and rows vertically. Its vertical DDA starts
        // at -24: the first output merges rows 0...1, then groups of three.
        for band in 0..<15 { for y in 0..<16 { for x in 0..<192 {
            for sy in (band * 48 + max(0, y * 3 - 1))..<(band * 48 + y * 3 + 2) {
                for sx in (x * 3)..<(x * 3 + 3) where bitmap[sx, sy] { result[x, band * 16 + y] = true }
            }
        } } }
        return result
    }

    mutating func beginDrag(at point: PixelPoint, constrained: Bool) {
        let target: Target = viewport.contains(point)
            ? .viewport(PixelPoint(x: viewport.x, y: viewport.y)) : .image(imageShift)
        drag = Drag(start: point, target: target, previous: point, axis: constrained ? .pending : .free)
    }
    mutating func drag(to point: PixelPoint) {
        guard var drag else { return }
        var p = point
        if drag.axis == .pending {
            let dx = abs(p.x - drag.start.x), dy = abs(p.y - drag.start.y)
            if dx > dy && dx > 1 { drag.axis = .horizontal }
            if dy > dx && dy > 1 { drag.axis = .vertical }
        }
        switch drag.axis {
        case .pending: p = drag.start
        case .horizontal: p.y = drag.start.y
        case .vertical: p.x = drag.start.x
        case .free: break
        }
        if p != drag.previous {
            let delta = PixelPoint(x: p.x - drag.start.x, y: p.y - drag.start.y)
            switch drag.target {
            case .viewport(let start):
                viewport = PixelRect(x: max(0, min(54, start.x + delta.x)),
                    y: max(0, min(160, start.y + delta.y)), width: 138, height: 80)
            case .image(let start):
                imageShift = PixelPoint(x: start.x + delta.x, y: start.y + delta.y)
            }
            drag.previous = p
        }
        self.drag = drag
    }
    mutating func endDrag() { drag = nil }

    var documentShift: PixelPoint {
        PixelPoint(x: imageShift.x * 3 / 8 * 8, y: imageShift.y * 3 / 8 * 8)
    }
    var hasChanges: Bool {
        documentShift != .zero || viewport.x != initialViewport.x || viewport.y != initialViewport.y
    }
    var documentOrigin: PixelPoint {
        guard hasChanges else { return originalOrigin }
        var x = originalOrigin.x + 3 * (viewport.x - initialViewport.x)
        var y = originalOrigin.y + 3 * (viewport.y - initialViewport.y)
        if x < 3 { x = 0 }; if x > 157 { x = 160 }
        if y < 3 { y = 0 }; if y > 477 { y = 480 }
        return PixelPoint(x: x, y: y)
    }
}
