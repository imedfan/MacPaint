import Foundation

struct PixelPoint: Equatable {
    var x: Int
    var y: Int
    static let zero = PixelPoint(x: 0, y: 0)
}

struct PixelRect: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var right: Int { x + width }
    var bottom: Int { y + height }
    var isEmpty: Bool { width <= 0 || height <= 0 }
    func contains(_ p: PixelPoint) -> Bool {
        p.x >= x && p.y >= y && p.x < right && p.y < bottom
    }
    func intersect(_ other: PixelRect) -> PixelRect {
        let left = max(x, other.x), top = max(y, other.y)
        return PixelRect(x: left, y: top, width: max(0, min(right, other.right) - left),
                         height: max(0, min(bottom, other.bottom) - top))
    }
    static func between(_ a: PixelPoint, _ b: PixelPoint) -> PixelRect {
        PixelRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

struct Pattern: Equatable {
    var rows: [UInt8]
    init(_ rows: [UInt8]) {
        precondition(rows.count == 8)
        self.rows = rows
    }
    func pixel(_ x: Int, _ y: Int) -> Bool { rows[y & 7] & (0x80 >> (x & 7)) != 0 }
    static let black = Pattern(Array(repeating: 255, count: 8))
    static let white = Pattern(Array(repeating: 0, count: 8))
    static let gray = Pattern([0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55])
}

/// QuickDraw's MSB-first, one-bit storage. Black is 1; white is 0.
struct Bitmap: Equatable {
    let width: Int
    let height: Int
    var bytes: [UInt8]
    var rowBytes: Int { (width + 7) / 8 }
    var bounds: PixelRect { PixelRect(x: 0, y: 0, width: width, height: height) }
    init(width: Int = 576, height: Int = 720) {
        precondition(width > 0 && height > 0)
        self.width = width; self.height = height
        bytes = Array(repeating: 0, count: ((width + 7) / 8) * height)
    }
    subscript(_ x: Int, _ y: Int) -> Bool {
        get {
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            return bytes[y * rowBytes + x / 8] & (0x80 >> (x & 7)) != 0
        }
        set {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let i = y * rowBytes + x / 8, mask = UInt8(0x80 >> (x & 7))
            if newValue { bytes[i] |= mask } else { bytes[i] &= ~mask }
        }
    }
    mutating func fill(_ rect: PixelRect, pattern: Pattern) {
        let r = rect.intersect(bounds)
        guard !r.isEmpty else { return }
        for y in r.y..<r.bottom { for x in r.x..<r.right { self[x, y] = pattern.pixel(x, y) } }
    }
    mutating func frame(_ r: PixelRect, width line: Int = 1, pattern: Pattern = .black) {
        fill(PixelRect(x: r.x, y: r.y, width: r.width, height: line), pattern: pattern)
        fill(PixelRect(x: r.x, y: r.bottom - line, width: r.width, height: line), pattern: pattern)
        fill(PixelRect(x: r.x, y: r.y, width: line, height: r.height), pattern: pattern)
        fill(PixelRect(x: r.right - line, y: r.y, width: line, height: r.height), pattern: pattern)
    }
    mutating func invert(_ rect: PixelRect) {
        let r = rect.intersect(bounds)
        guard !r.isEmpty else { return }
        for y in r.y..<r.bottom { for x in r.x..<r.right { self[x, y].toggle() } }
    }
    mutating func line(from a: PixelPoint, to b: PixelPoint, width: Int = 1, pattern: Pattern = .black,
                       clip: PixelRect? = nil, orMode: Bool = false) {
        var x = a.x, y = a.y
        let dx = abs(b.x - a.x), dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1, sy = a.y < b.y ? 1 : -1
        var error = dx + dy
        while true {
            let r = PixelRect(x: x - width / 2, y: y - width / 2, width: width, height: width).intersect(clip ?? bounds).intersect(bounds)
            if !r.isEmpty {
                for py in r.y..<r.bottom { for px in r.x..<r.right {
                    let black = pattern.pixel(px, py)
                    if !orMode || black { self[px, py] = black }
                } }
            }
            if x == b.x && y == b.y { break }
            let twice = 2 * error
            if twice >= dy { error += dy; x += sx }
            if twice <= dx { error += dx; y += sy }
        }
    }
    mutating func copy(_ source: Bitmap, at origin: PixelPoint, mask: Bitmap? = nil, transparent: Bool = false) {
        let destination = PixelRect(x: origin.x, y: origin.y, width: source.width, height: source.height).intersect(bounds)
        guard !destination.isEmpty else { return }
        for y in destination.y..<destination.bottom {
            for x in destination.x..<destination.right {
                let sx = x - origin.x, sy = y - origin.y
                if let mask, !mask[sx, sy] { continue }
                let black = source[sx, sy]
                if !transparent || black { self[x, y] = black }
            }
        }
    }
    func cropped(to r: PixelRect) -> Bitmap {
        var result = Bitmap(width: max(1, r.width), height: max(1, r.height))
        for y in 0..<result.height { for x in 0..<result.width { result[x, y] = self[x + r.x, y + r.y] } }
        return result
    }
    mutating func flood(at start: PixelPoint, pattern: Pattern) {
        guard bounds.contains(start) else { return }
        let target = self[start.x, start.y]
        var seen = Bitmap(width: width, height: height)
        var queue = [start], index = 0
        seen[start.x, start.y] = true
        while index < queue.count {
            let p = queue[index]; index += 1
            self[p.x, p.y] = pattern.pixel(p.x, p.y)
            for n in [PixelPoint(x: p.x - 1, y: p.y), PixelPoint(x: p.x + 1, y: p.y),
                      PixelPoint(x: p.x, y: p.y - 1), PixelPoint(x: p.x, y: p.y + 1)] {
                if bounds.contains(n) && !seen[n.x, n.y] && self[n.x, n.y] == target {
                    seen[n.x, n.y] = true; queue.append(n)
                }
            }
        }
    }
    func flipped(horizontal: Bool) -> Bitmap {
        var result = Bitmap(width: width, height: height)
        for y in 0..<height { for x in 0..<width {
            result[x, y] = self[horizontal ? width - 1 - x : x, horizontal ? y : height - 1 - y]
        } }
        return result
    }
    func rotated() -> Bitmap {
        var result = Bitmap(width: height, height: width)
        for y in 0..<height { for x in 0..<width { result[y, width - 1 - x] = self[x, y] } }
        return result
    }
    func scaled(width: Int, height: Int) -> Bitmap {
        var result = Bitmap(width: width, height: height)
        for y in 0..<height { for x in 0..<width {
            result[x, y] = self[x * self.width / width, y * self.height / height]
        } }
        return result
    }
    func opaqueMask() -> Bitmap {
        // CalcMask: exterior-connected white is transparent; enclosed holes move
        // with the object. The padded border supplies the original exterior seed.
        var padded = Bitmap(width: width + 2, height: height + 2)
        padded.copy(self, at: PixelPoint(x: 1, y: 1))
        var outside = Bitmap(width: width + 2, height: height + 2)
        var queue = [PixelPoint.zero], index = 0
        outside[0, 0] = true
        while index < queue.count {
            let p = queue[index]; index += 1
            for n in [PixelPoint(x: p.x - 1, y: p.y), PixelPoint(x: p.x + 1, y: p.y),
                      PixelPoint(x: p.x, y: p.y - 1), PixelPoint(x: p.x, y: p.y + 1)] {
                if padded.bounds.contains(n) && !outside[n.x, n.y] && !padded[n.x, n.y] {
                    outside[n.x, n.y] = true; queue.append(n)
                }
            }
        }
        var result = Bitmap(width: width, height: height)
        for y in 0..<height { for x in 0..<width { result[x, y] = !outside[x + 1, y + 1] } }
        return result
    }
    var blackBounds: PixelRect? {
        var left = width, top = height, right = 0, bottom = 0
        for y in 0..<height { for x in 0..<width where self[x, y] {
            left = min(left, x); top = min(top, y); right = max(right, x + 1); bottom = max(bottom, y + 1)
        } }
        return left < right ? PixelRect(x: left, y: top, width: right - left, height: bottom - top) : nil
    }
    func tracedEdges(shadow: Bool) -> Bitmap {
        // MacPaint.p:TraceEdges smears the current image in four successive
        // CopyBits operations, then punches out the saved original interior.
        let delta = shadow ? 3 : 2
        let sourceRect = PixelRect(x: 1, y: 1, width: width - delta, height: height - delta)
        guard !sourceRect.isEmpty else { return self }
        var result = self
        for offset in [PixelPoint(x: -1, y: 0), PixelPoint(x: delta - 1, y: 0),
                       PixelPoint(x: 0, y: -1), PixelPoint(x: 0, y: delta - 1)] {
            let source = result.cropped(to: sourceRect)
            result.copy(source, at: PixelPoint(x: sourceRect.x + offset.x, y: sourceRect.y + offset.y), transparent: true)
        }
        for y in sourceRect.y..<sourceRect.bottom { for x in sourceRect.x..<sourceRect.right where self[x, y] {
            result[x, y] = false
        } }
        return result
    }
    mutating func polygon(_ points: [PixelPoint], filled: Bool, width line: Int, pattern: Pattern, border: Bool,
                          closed: Bool = true, borderPattern: Pattern? = nil) {
        guard points.count > 1 else { return }
        if filled, points.count > 2 {
            let minY = max(0, points.map(\.y).min()!), maxY = min(height - 1, points.map(\.y).max()!)
            if minY <= maxY {
                for y in minY...maxY {
                    var intersections = [Int]()
                    for i in points.indices {
                        let a = points[i], b = points[(i + 1) % points.count]
                        if (a.y <= y && b.y > y) || (b.y <= y && a.y > y) {
                            intersections.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
                        }
                    }
                    intersections.sort()
                    for i in stride(from: 0, to: intersections.count - 1, by: 2) {
                        fill(PixelRect(x: intersections[i], y: y, width: intersections[i + 1] - intersections[i], height: 1), pattern: pattern)
                    }
                }
            }
        }
        if border || !filled {
            let count = closed || filled ? points.count : points.count - 1
            for i in 0..<count {
                self.line(from: points[i], to: points[(i + 1) % points.count], width: line,
                          pattern: borderPattern ?? (filled ? .black : pattern))
            }
        }
    }
}
