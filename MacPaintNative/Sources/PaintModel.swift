import Foundation

enum PaintTool: Int, CaseIterable {
    case lasso, selection, hand, text, bucket, spray, brush, pencil, line, eraser
    case rectangle, filledRectangle, roundedRectangle, filledRoundedRectangle
    case oval, filledOval, curve, filledCurve, polygon, filledPolygon
    var name: String {
        ["Lasso", "Selection", "Hand", "Text", "Paint Bucket", "Spray Can", "Paintbrush", "Pencil", "Line", "Eraser",
         "Rectangle", "Filled Rectangle", "Rounded Rectangle", "Filled Rounded Rectangle", "Oval", "Filled Oval",
         "Freehand Shape", "Filled Freehand Shape", "Polygon", "Filled Polygon"][rawValue]
    }
    var isShape: Bool { rawValue >= 10 && rawValue <= 15 }
    var isFilled: Bool { rawValue >= 10 && rawValue % 2 == 1 }
}

struct PaintModifiers: OptionSet {
    let rawValue: Int
    static let shift = PaintModifiers(rawValue: 1)
    static let option = PaintModifiers(rawValue: 2)
    static let command = PaintModifiers(rawValue: 4)
}

enum SelectionKind: Equatable {
    case rectangle
    case lasso
    case text(String)
}

struct FloatingSelection {
    var pixels: Bitmap
    var mask: Bitmap
    var origin: PixelPoint
    var kind: SelectionKind = .rectangle
    var isLasso: Bool { kind == .lasso }
    var textScrap: String? { if case .text(let string) = kind { return string }; return nil }
    var rect: PixelRect { PixelRect(x: origin.x, y: origin.y, width: pixels.width, height: pixels.height) }
}

struct PaintState {
    var bitmap: Bitmap
    var selection: FloatingSelection?
}

/// Native translation of MacPaint.p's document operations. AppKit owns no pixels.
final class PaintModel {
    let resources: ClassicResources
    var bitmap = Bitmap()
    var selection: FloatingSelection?
    var undoState: PaintState?
    var patterns: [Pattern]
    var tool: PaintTool = .brush
    var previousTool: PaintTool = .brush
    var patternIndex = 0
    var brushIndex = 7
    var lineWidth = 1
    var border = true
    var grid = false
    var symmetryHorizontal = false
    var symmetryVertical = false
    var symmetryDiagonal = false
    var symmetryOtherDiagonal = false
    var origin = PixelPoint(x: 80, y: 120)
    var fatBits = false
    var fatCenter = PixelPoint(x: 288, y: 240)
    var polygonPoints = [PixelPoint]()
    private var polygonModifiers: PaintModifiers = []
    var textFont = "Geneva"
    var textSize = 12
    var textStyle = 0
    var textAlignment = 0
    var text = ""
    var textOrigin: PixelPoint?
    var textBase: Bitmap?
    private var textLeft = 0
    var savedBitmap = Bitmap()
    var savedPatterns: [Pattern]

    private enum StrokeAxis { case horizontal, vertical }
    private struct Gesture {
        var start: PixelPoint
        var last: PixelPoint
        var base: Bitmap
        var points: [PixelPoint]
        var pencilBlack: Bool
        var moving: Bool
        var selectionOrigin: PixelPoint?
        var selectionSource: FloatingSelection?
        var modifiers: PaintModifiers
        var axis: StrokeAxis?
    }
    private var gesture: Gesture?
    var pattern: Pattern { patterns[patternIndex] }
    var visibleRect: PixelRect { PixelRect(x: origin.x, y: origin.y, width: 416, height: 240) }
    var activeRect: PixelRect {
        fatBits ? PixelRect(x: fatCenter.x - 26, y: fatCenter.y - 15, width: 52, height: 30) : visibleRect
    }
    var displayBitmap: Bitmap {
        var result = bitmap
        if let s = selection { result.copy(s.pixels, at: s.origin, mask: s.mask) }
        return result
    }
    var isDirty: Bool { displayBitmap != savedBitmap || patterns != savedPatterns }
    var state: PaintState { PaintState(bitmap: bitmap, selection: selection) }

    init(resources: ClassicResources) {
        self.resources = resources
        patterns = resources.patterns; savedPatterns = resources.patterns
    }
    func checkpoint() { commitText(); undoState = state }
    func undo() {
        commitText()
        if var previous = undoState {
            let current = selection?.textScrap != nil ? PaintState(bitmap: displayBitmap, selection: nil) : state
            if previous.selection?.textScrap != nil { previous.selection?.kind = .rectangle }
            undoState = current; bitmap = previous.bitmap; selection = previous.selection
        }
    }
    func markSaved() { savedBitmap = displayBitmap; savedPatterns = patterns }
    func newDocument() {
        bitmap = Bitmap(); selection = nil; undoState = nil; origin = PixelPoint(x: 80, y: 120)
        fatCenter = PixelPoint(x: 288, y: 240)
        patterns = resources.patterns; text = ""; textOrigin = nil; textBase = nil; textLeft = 0
        fatBits = false; polygonPoints = []; markSaved()
    }
    func load(_ document: MacPaintFile.Document) {
        let loadedPatterns = document.patterns ?? patterns
        newDocument(); bitmap = document.bitmap
        patterns = loadedPatterns
        markSaved()
    }
    func revert(to document: MacPaintFile.Document?) {
        if let document {
            let viewport = origin, zoom = fatBits, center = fatCenter
            load(document)
            origin = viewport; fatBits = zoom; fatCenter = center
        } else {
            // RevertDoc calls NewDocInit/BlankDoc for an unnamed document;
            // BlankDoc retains the current patterns, unlike File > New.
            let currentPatterns = patterns
            newDocument(); patterns = currentPatterns; markSaved()
        }
    }
    func acceptSelection() {
        bitmap = displayBitmap; selection = nil
    }
    func chooseTool(_ tool: PaintTool) {
        commitText(); finishPolygon(); acceptSelection()
        if self.tool != .eraser { previousTool = self.tool }
        self.tool = tool
    }
    func setOrigin(_ point: PixelPoint) {
        origin = PixelPoint(x: min(160, max(0, point.x)), y: min(480, max(0, point.y)))
    }
    func beginPageOverview() -> PageOverview {
        acceptEdits(); fatBits = false
        return PageOverview(bitmap: bitmap, origin: origin)
    }
    func acceptEdits() {
        commitText(); finishPolygon(); acceptSelection(); undoState = nil
    }
    func applyPageOverview(_ overview: PageOverview) {
        guard overview.hasChanges else { return }
        if overview.documentShift != .zero {
            var shifted = Bitmap(); shifted.copy(bitmap, at: overview.documentShift); bitmap = shifted
        }
        setOrigin(overview.documentOrigin)
        fatCenter = PixelPoint(x: origin.x + 208, y: origin.y + 120)
        undoState = nil // The original accepts the shifted page as its new baseline.
    }
    func toggleFatBits(at point: PixelPoint? = nil) {
        commitText(); acceptSelection()
        if let point { fatCenter = point }
        fatCenter = PixelPoint(x: max(origin.x + 26, min(origin.x + 390, fatCenter.x)),
                               y: max(origin.y + 15, min(origin.y + 225, fatCenter.y)))
        fatBits.toggle()
    }
    private func snapped(_ p: PixelPoint, pin: Bool = true) -> PixelPoint {
        let isGridTool = [1, 3, 8, 10, 11, 12, 13, 14, 15, 18, 19].contains(tool.rawValue)
        var result = p
        if grid && isGridTool { result = PixelPoint(x: (p.x + 4) & ~7, y: (p.y + 4) & ~7) }
        if pin && (tool == .lasso || tool == .selection || tool == .pencil || tool.rawValue >= 8 && tool != .eraser) {
            let size = tool == .pencil || tool == .selection ? 1 : tool == .lasso ? 2 : lineWidth
            let half = size / 2
            var left = activeRect.x + half, top = activeRect.y + half
            var right = activeRect.right - size + half, bottom = activeRect.bottom - size + half
            if grid && isGridTool { left = (left + 7) & ~7; top = (top + 7) & ~7; right &= ~7; bottom &= ~7 }
            result.x = max(left, min(right, result.x)); result.y = max(top, min(bottom, result.y))
        }
        return result
    }
    private func constrained(_ p: PixelPoint, to start: PixelPoint, diagonal: Bool) -> PixelPoint {
        let dx = p.x - start.x, dy = p.y - start.y
        if !diagonal {
            return abs(dx) > abs(dy) ? PixelPoint(x: p.x, y: start.y) : PixelPoint(x: start.x, y: p.y)
        }
        // MacPaint.p:875 Constrain permits horizontal, vertical and 45° lines.
        if tool == .line {
            if abs(dx) > 2 * abs(dy) { return PixelPoint(x: p.x, y: start.y) }
            if abs(dy) > 2 * abs(dx) { return PixelPoint(x: start.x, y: p.y) }
        }
        let delta = min(abs(dx), abs(dy))
        return PixelPoint(x: start.x + (dx < 0 ? -delta : delta), y: start.y + (dy < 0 ? -delta : delta))
    }
    func begin(at point: PixelPoint, modifiers: PaintModifiers = [], clickCount: Int = 1) {
        let p = snapped(point)
        if tool == .polygon || tool == .filledPolygon {
            if polygonPoints.isEmpty { checkpoint(); acceptSelection(); polygonModifiers = modifiers }
            if polygonPoints.count > 2 && abs(p.x - polygonPoints[0].x) + abs(p.y - polygonPoints[0].y) < 4 * lineWidth {
                finishPolygon(closed: true); return
            }
            if clickCount > 1 { finishPolygon(); return }
            polygonPoints.append(p); return
        }
        if tool == .text {
            commitText(); acceptSelection(); checkpoint()
            textOrigin = p; textLeft = p.x; textBase = bitmap; text = ""; return
        }
        if tool == .hand { return }
        checkpoint()
        var moving = false
        var selectionOrigin: PixelPoint?
        if tool == .selection || tool == .lasso, let selected = selection, selected.rect.contains(p),
           selected.mask[p.x - selected.origin.x, p.y - selected.origin.y] {
            moving = true; selectionOrigin = selected.origin
            if modifiers.contains(.option) { bitmap.copy(selected.pixels, at: selected.origin, mask: selected.mask) }
        } else {
            acceptSelection()
        }
        gesture = Gesture(start: p, last: p, base: bitmap, points: [p], pencilBlack: !bitmap[p.x, p.y],
                          moving: moving, selectionOrigin: selectionOrigin, selectionSource: selection, modifiers: modifiers, axis: nil)
        if tool == .bucket {
            var visible = bitmap.cropped(to: activeRect)
            let localPattern = Pattern((0..<8).map { y in
                var row: UInt8 = 0
                for x in 0..<8 where pattern.pixel(x + activeRect.x, y + activeRect.y) { row |= 0x80 >> x }
                return row
            })
            visible.flood(at: PixelPoint(x: p.x - activeRect.x, y: p.y - activeRect.y), pattern: localPattern)
            bitmap.copy(visible, at: PixelPoint(x: activeRect.x, y: activeRect.y))
        } else if [.pencil, .brush, .spray, .eraser, .curve, .filledCurve].contains(tool) {
            stroke(from: p, to: p, modifiers: modifiers)
        }
    }
    func drag(to point: PixelPoint, modifiers: PaintModifiers = []) {
        guard var g = gesture else { return }
        var p = snapped(point, pin: !g.moving)
        let stretching = g.moving && g.modifiers.contains(.command) && !g.modifiers.contains(.option)
        if modifiers.contains(.shift) && !stretching {
            if tool.isShape || tool == .line { p = constrained(p, to: g.start, diagonal: true) }
            else {
                let dx = abs(p.x - g.start.x), dy = abs(p.y - g.start.y)
                if g.axis == nil {
                    if dx > dy && dx > 1 { g.axis = .horizontal }
                    else if dy > dx && dy > 1 { g.axis = .vertical }
                }
                if g.axis == .horizontal { p.y = g.start.y }
                else if g.axis == .vertical { p.x = g.start.x }
                else { p = g.start }
            }
        }
        if g.moving, let start = g.selectionOrigin {
            if g.modifiers.contains(.command) && !g.modifiers.contains(.option),
               let source = g.selectionSource, !source.isLasso {
                stretch(source, from: g.start, to: p, preserveAspect: modifiers.contains(.shift))
            } else {
                let dx = max(activeRect.x - start.x, min(activeRect.right - (g.selectionSource?.pixels.width ?? 0) - start.x, p.x - g.start.x))
                let dy = max(activeRect.y - start.y, min(activeRect.bottom - (g.selectionSource?.pixels.height ?? 0) - start.y, p.y - g.start.y))
                selection?.origin = PixelPoint(x: start.x + dx, y: start.y + dy)
                if g.modifiers.contains([.command, .option]), let s = selection { bitmap.copy(s.pixels, at: s.origin, mask: s.mask) }
            }
        } else if tool.isShape || tool == .line {
            bitmap = g.base
            if tool == .line {
                bitmap.line(from: g.start, to: p, width: lineWidth, pattern: modifiers.contains(.option) ? pattern : .black,
                            clip: activeRect, orMode: modifiers.contains(.command))
            } else { shape(from: g.start, to: p, modifiers: modifiers) }
        } else if [.brush, .pencil, .spray, .eraser, .curve, .filledCurve].contains(tool) {
            let distance = abs(p.x - g.last.x) + abs(p.y - g.last.y)
            let tolerance = tool == .spray ? 2 : tool == .brush ? 1 : 0
            if distance <= tolerance { gesture = g; return }
            stroke(from: g.last, to: p, modifiers: modifiers)
        }
        if g.points.last != p { g.points.append(p) }
        g.last = p; gesture = g
    }
    func end(at point: PixelPoint, modifiers: PaintModifiers = []) {
        drag(to: point, modifiers: modifiers)
        guard let g = gesture else { return }
        if !g.moving && (tool == .selection || tool == .lasso) {
            let dragRect: PixelRect
            if tool == .lasso {
                let left = g.points.map(\.x).min()!, right = g.points.map(\.x).max()!
                let top = g.points.map(\.y).min()!, bottom = g.points.map(\.y).max()!
                dragRect = PixelRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
            } else { dragRect = PixelRect.between(g.start, g.last) }
            let rect = dragRect.intersect(activeRect).intersect(bitmap.bounds)
            if !rect.isEmpty {
                var mask = Bitmap(width: rect.width, height: rect.height)
                if tool == .lasso {
                    let points = g.points.map { PixelPoint(x: $0.x - rect.x, y: $0.y - rect.y) }
                    mask.polygon(points, filled: true, width: 1, pattern: .black, border: false)
                    var enclosed = bitmap.cropped(to: rect)
                    for y in 0..<rect.height { for x in 0..<rect.width where !mask[x, y] { enclosed[x, y] = false } }
                    mask = enclosed.opaqueMask()
                    if let bounds = mask.blackBounds {
                        let trimmed = PixelRect(x: rect.x + bounds.x, y: rect.y + bounds.y, width: bounds.width, height: bounds.height)
                        liftSelection(rect: trimmed, mask: mask.cropped(to: bounds), isLasso: true)
                    }
                } else { mask.fill(mask.bounds, pattern: .black) }
                if tool != .lasso { liftSelection(rect: rect, mask: mask) }
            }
        }
        if tool == .filledCurve {
            bitmap = g.base
            bitmap.polygon(g.points, filled: true, width: lineWidth, pattern: pattern, border: border,
                           borderPattern: g.modifiers.contains(.option) ? pattern : .black)
        }
        gesture = nil
    }
    var selectionPreview: [PixelPoint]? {
        guard let g = gesture, !g.moving, tool == .selection || tool == .lasso else { return nil }
        if tool == .lasso { return g.points }
        let r = PixelRect.between(g.start, g.last)
        return [PixelPoint(x: r.x, y: r.y), PixelPoint(x: r.right, y: r.y),
                PixelPoint(x: r.right, y: r.bottom), PixelPoint(x: r.x, y: r.bottom), PixelPoint(x: r.x, y: r.y)]
    }
    func finishPolygon(closed: Bool = false) {
        guard !polygonPoints.isEmpty else { return }
        let filled = tool == .filledPolygon
        let outline = polygonModifiers.contains(.option) ? pattern : .black
        bitmap.polygon(polygonPoints, filled: filled, width: lineWidth, pattern: filled ? pattern : outline,
                       border: border, closed: closed, borderPattern: outline)
        polygonPoints = []
    }
    private func liftSelection(rect: PixelRect, mask: Bitmap, isLasso: Bool = false) {
        let pixels = bitmap.cropped(to: rect)
        for y in 0..<rect.height { for x in 0..<rect.width where mask[x, y] { bitmap[x + rect.x, y + rect.y] = false } }
        selection = FloatingSelection(pixels: pixels, mask: mask, origin: PixelPoint(x: rect.x, y: rect.y), kind: isLasso ? .lasso : .rectangle)
    }
    func selectAll() {
        commitText(); acceptSelection()
        var mask = Bitmap(width: activeRect.width, height: activeRect.height); mask.fill(mask.bounds, pattern: .black)
        liftSelection(rect: activeRect, mask: mask); tool = .selection
    }
    func insert(_ pixels: Bitmap, mask: Bitmap? = nil, isLasso: Bool = false) {
        // MacPaint.p:Paste uses an existing rectangle as the destination, and
        // CenterScrap otherwise. SetSelRect clips the result to the active view.
        let destination = selection.flatMap { $0.isLasso ? nil : $0.rect }
        checkpoint(); acceptSelection()
        let rect: PixelRect
        if let destination { rect = destination }
        else {
            if pixels.width > 48 || pixels.height > 30 { fatBits = false }
            var x = (activeRect.x + activeRect.right - pixels.width) / 2
            var y = (activeRect.y + activeRect.bottom - pixels.height) / 2
            if grid && !fatBits { x = (x + 4) & ~7; y = (y + 4) & ~7 }
            rect = PixelRect(x: x, y: y, width: pixels.width, height: pixels.height)
        }
        var sourceMask = mask ?? Bitmap(width: pixels.width, height: pixels.height)
        if mask == nil {
            if isLasso { sourceMask = pixels.opaqueMask() }
            else { sourceMask.fill(sourceMask.bounds, pattern: .black) }
        }
        let resizing = pixels.width != rect.width || pixels.height != rect.height
        let scaled = resizing ? pixels.scaled(width: rect.width, height: rect.height) : pixels
        let scaledMask = resizing ? sourceMask.scaled(width: rect.width, height: rect.height) : sourceMask
        let clipped = rect.intersect(activeRect).intersect(bitmap.bounds)
        guard !clipped.isEmpty else { return }
        let crop = PixelRect(x: clipped.x - rect.x, y: clipped.y - rect.y, width: clipped.width, height: clipped.height)
        selection = FloatingSelection(pixels: scaled.cropped(to: crop), mask: scaledMask.cropped(to: crop),
                                      origin: PixelPoint(x: clipped.x, y: clipped.y), kind: isLasso ? .lasso : .rectangle)
        if !fatBits { fatCenter = PixelPoint(x: clipped.x + clipped.width / 2, y: clipped.y + clipped.height / 2) }
        tool = isLasso ? .lasso : .selection
    }
    private var textRaster: BitmapText { BitmapText(resources: resources, name: textFont, size: textSize, style: textStyle) }
    private var textLineHeight: Int {
        let height = textRaster.lineHeight
        return grid ? (height + 7) & ~7 : height
    }
    var textCaretRect: PixelRect? {
        guard let start = textOrigin else { return nil }
        let renderer = textRaster
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let index = max(0, lines.count - 1), last = String(lines.last ?? "")
        let width = renderer.width(of: last) + (!last.isEmpty && textStyle & 2 != 0 ? 5 : 0)
        let anchor = index == 0 ? start.x : textLeft
        let x = anchor - (textAlignment == 1 ? width / 2 : textAlignment == 2 ? width : 0) + width
        return PixelRect(x: x, y: start.y + index * textLineHeight - renderer.ascent,
                         width: 1, height: max(1, renderer.ascent + renderer.descent))
    }
    func continueText() {
        guard let caret = textCaretRect else { return }
        var next = PixelPoint(x: caret.x, y: caret.y + textRaster.ascent)
        if grid { next = PixelPoint(x: (next.x + 4) & ~7, y: (next.y + 4) & ~7) }
        checkpoint()
        textOrigin = next; textBase = bitmap; text = ""
    }
    func insertText(_ string: String) {
        let previousFrame = selection.flatMap { $0.isLasso ? nil : $0.rect }
        checkpoint(); acceptSelection()
        let frame: PixelRect
        if let previousFrame { frame = previousFrame }
        else {
            // Paste first measures TextBox in the window inset by 50 pixels,
            // trims its ink, centers that size, then adds 6x4 padding.
            let measured = textRaster.box(string, width: visibleRect.width - 100, height: visibleRect.height, alignment: textAlignment)
            let ink = measured.blackBounds ?? PixelRect(x: 0, y: 0, width: 0, height: 0)
            if ink.width > 48 || ink.height > 30 { fatBits = false }
            var x = (activeRect.x + activeRect.right - ink.width) / 2
            var y = (activeRect.y + activeRect.bottom - ink.height) / 2
            if grid && !fatBits { x = (x + 4) & ~7; y = (y + 4) & ~7 }
            frame = PixelRect(x: x - 6, y: y - 4, width: ink.width + 12, height: ink.height + 8)
        }
        renderTextSelection(string, frame: frame)
        if !fatBits, let selection {
            fatCenter = PixelPoint(x: selection.rect.x + selection.rect.width / 2, y: selection.rect.y + selection.rect.height / 2)
        }
        tool = .selection
    }
    private func renderTextSelection(_ string: String, frame: PixelRect) {
        let clipped = frame.intersect(activeRect).intersect(bitmap.bounds)
        guard !clipped.isEmpty else { selection = nil; return }
        let rendered = textRaster.box(string, width: frame.width, height: frame.height, alignment: textAlignment)
        let crop = PixelRect(x: clipped.x - frame.x, y: clipped.y - frame.y, width: clipped.width, height: clipped.height)
        var mask = Bitmap(width: clipped.width, height: clipped.height); mask.fill(mask.bounds, pattern: .black)
        selection = FloatingSelection(pixels: rendered.cropped(to: crop), mask: mask, origin: PixelPoint(x: clipped.x, y: clipped.y), kind: .text(string))
    }
    func editSelection(_ operation: String, modifiers: PaintModifiers = []) {
        guard var s = selection else { return }
        checkpoint()
        if operation == "clear" { selection = nil; return }
            switch operation {
            case "invert": s.pixels.invert(s.pixels.bounds)
            case "fill":
                for y in 0..<s.pixels.height { for x in 0..<s.pixels.width where s.mask[x, y] {
                    s.pixels[x, y] = pattern.pixel(x + s.origin.x, y + s.origin.y)
                } }
            case "edges": s.pixels = s.pixels.tracedEdges(shadow: modifiers.contains(.shift))
            case "horizontal": s.pixels = s.pixels.flipped(horizontal: true); s.mask = s.mask.flipped(horizontal: true)
            case "vertical": s.pixels = s.pixels.flipped(horizontal: false); s.mask = s.mask.flipped(horizontal: false)
            case "rotate":
                let center = PixelPoint(x: s.origin.x + s.pixels.width / 2, y: s.origin.y + s.pixels.height / 2)
                s.pixels = s.pixels.rotated(); s.mask = s.mask.rotated()
                s.origin = PixelPoint(x: center.x - s.pixels.width / 2, y: center.y - s.pixels.height / 2)
            default: break
            }
            selection = s
    }
    func eraseWindow() {
        checkpoint(); acceptSelection(); bitmap.fill(activeRect, pattern: .white)
    }
    private func stroke(from a: PixelPoint, to b: PixelPoint, modifiers: PaintModifiers) {
        if tool == .pencil {
            bitmap.line(from: a, to: b, pattern: gesture?.pencilBlack == false ? .white : .black, clip: activeRect)
        } else if tool == .curve || tool == .filledCurve {
            bitmap.line(from: a, to: b, width: lineWidth, pattern: modifiers.contains(.option) ? pattern : .black,
                        clip: activeRect, orMode: modifiers.contains(.command))
        } else {
            let steps = max(abs(b.x - a.x), abs(b.y - a.y))
            if tool == .spray {
                if steps == 0 || abs(b.x - a.x) + abs(b.y - a.y) > 2 { stamp(at: b, modifiers: modifiers) }
            } else {
                if steps == 0 { stamp(at: a, modifiers: modifiers); return }
                let dx = Int64(b.x - a.x) * 65536 / Int64(steps), dy = Int64(b.y - a.y) * 65536 / Int64(steps)
                var x = Int64(a.x) * 65536 + 32768, y = Int64(a.y) * 65536 + 32768
                for _ in 1...steps {
                    x += dx; y += dy
                    stamp(at: PixelPoint(x: Int(x >> 16), y: Int(y >> 16)), modifiers: modifiers)
                }
            }
        }
    }
    private func stamp(at p: PixelPoint, modifiers: PaintModifiers) {
        let code = tool == .eraser ? 120 : tool == .spray ? 111 : 120 + brushIndex
        let brush = resources.paintFont.cursorSprite(UInt8(code))
        var points = [p]
        if tool == .brush && !fatBits {
            let cx = origin.x + 208, cy = origin.y + 120, x = p.x - cx, y = p.y - cy
            // PaintAsm.a:460: MapSym's exact flag-to-eight-positions table.
            let flags = (symmetryHorizontal ? 1 : 0) | (symmetryVertical ? 2 : 0)
                | (symmetryDiagonal ? 4 : 0) | (symmetryOtherDiagonal ? 8 : 0)
            let code = [0x80, 0xC0, 0xA0, 0xF0, 0x88, 0xFF, 0xFF, 0xFF, 0x81, 0xFF, 0xFF, 0xFF, 0x99, 0xFF, 0xFF, 0xFF][flags]
            let positions = [PixelPoint(x: -x, y: y), PixelPoint(x: x, y: -y), PixelPoint(x: -x, y: -y),
                             PixelPoint(x: y, y: x), PixelPoint(x: -y, y: x), PixelPoint(x: y, y: -x), PixelPoint(x: -y, y: -x)]
            for i in positions.indices where code & (0x40 >> i) != 0 { points.append(PixelPoint(x: cx + positions[i].x, y: cy + positions[i].y)) }
        }
        for point in points {
            for y in 0..<16 { for x in 0..<16 {
                let px = point.x + x - 8, py = point.y + y - 8
                let on = tool == .eraser && fatBits ? (x == 7 || x == 8) && (y == 7 || y == 8) : brush[x, y]
                if on && activeRect.contains(PixelPoint(x: px, y: py)) {
                    let black = tool == .eraser ? false : pattern.pixel(px, py)
                    if !modifiers.contains(.command) || black || tool == .eraser { bitmap[px, py] = black }
                }
            } }
        }
    }
    private func shape(from a: PixelPoint, to b: PixelPoint, modifiers: PaintModifiers) {
        let r = PixelRect.between(a, b)
        guard !r.isEmpty else { return }
        let outer = PixelRect(x: r.x - lineWidth / 2, y: r.y - lineWidth / 2,
                              width: r.width + lineWidth, height: r.height + lineWidth)
        let outline = modifiers.contains(.option) ? pattern : .black
        let isOval = tool == .oval || tool == .filledOval
        let isRounded = tool == .roundedRectangle || tool == .filledRoundedRectangle
        let outerSpans = isOval || isRounded ? QuickDrawOval.spans(in: outer, ovalWidth: isOval ? outer.width : 18,
                                                                  ovalHeight: isOval ? outer.height : 18) : []
        let innerRect = PixelRect(x: outer.x + lineWidth, y: outer.y + lineWidth,
                                  width: outer.width - 2 * lineWidth, height: outer.height - 2 * lineWidth)
        let innerSpans = isOval || isRounded ? QuickDrawOval.spans(in: innerRect,
            ovalWidth: (isOval ? outer.width : 18) - lineWidth * 2,
            ovalHeight: (isOval ? outer.height : 18) - lineWidth * 2) : []
        func inside(_ x: Int, _ y: Int, inset: Int) -> Bool {
            let w = Double(outer.width - inset * 2), h = Double(outer.height - inset * 2)
            guard w > 0, h > 0 else { return false }
            let px = Double(x - outer.x - inset) + 0.5, py = Double(y - outer.y - inset) + 0.5
            if px < 0 || py < 0 || px >= w || py >= h { return false }
            if isOval || isRounded {
                let spans = inset == 0 ? outerSpans : innerSpans
                let row = y - (inset == 0 ? outer.y : innerRect.y)
                return spans.indices.contains(row) && spans[row].contains(x)
            }
            return true
        }
        let clipped = outer.intersect(activeRect).intersect(bitmap.bounds)
        guard !clipped.isEmpty else { return }
        for y in clipped.y..<clipped.bottom { for x in clipped.x..<clipped.right where inside(x, y, inset: 0) {
            let isBorder = !inside(x, y, inset: lineWidth)
            if isBorder && (border || !tool.isFilled) {
                let black = outline.pixel(x, y)
                if !modifiers.contains(.command) || black { bitmap[x, y] = black }
            } else if tool.isFilled {
                let black = pattern.pixel(x, y)
                if !modifiers.contains(.command) || black { bitmap[x, y] = black }
            }
        } }
    }
    func updateText(_ newText: String) {
        if let selected = selection, let string = selected.textScrap {
            renderTextSelection(string, frame: selected.rect); return
        }
        guard let start = textOrigin, let base = textBase else { return }
        text = newText.split(separator: "\n", omittingEmptySubsequences: false).prefix(20).map { String($0.prefix(80)) }.joined(separator: "\n")
        bitmap = base
        let renderer = textRaster
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let lineHeight = textLineHeight
        for (index, line) in lines.enumerated() {
            let string = String(line)
            if string.isEmpty { continue }
            let width = renderer.width(of: string) + (textStyle & 2 != 0 ? 5 : 0)
            let anchor = index == 0 ? start.x : textLeft
            let x = anchor - (textAlignment == 1 ? width / 2 : textAlignment == 2 ? width : 0)
            bitmap.fill(PixelRect(x: x - 1, y: start.y + index * lineHeight - renderer.ascent,
                                  width: width + 2, height: renderer.ascent + renderer.descent).intersect(activeRect), pattern: .white)
            renderer.draw(string, in: &bitmap, at: PixelPoint(x: x, y: start.y + index * lineHeight), clip: activeRect)
        }
    }
    func commitText() { text = ""; textOrigin = nil; textBase = nil }

    private func stretch(_ source: FloatingSelection, from start: PixelPoint, to point: PixelPoint, preserveAspect: Bool) {
        let r = source.rect
        let horizontal = start.x < r.x + r.width / 3 ? -1 : start.x > r.right - r.width / 3 ? 1 : 0
        let vertical = start.y < r.y + r.height / 3 ? -1 : start.y > r.bottom - r.height / 3 ? 1 : 0
        guard horizontal != 0 || vertical != 0 else {
            selection?.origin = PixelPoint(x: r.x + point.x - start.x, y: r.y + point.y - start.y); return
        }
        var width = max(1, r.width + (point.x - start.x) * horizontal)
        var height = max(1, r.height + (point.y - start.y) * vertical)
        if preserveAspect {
            let factor = min(Double(width) / Double(r.width), Double(height) / Double(r.height))
            width = max(1, Int(Double(r.width) * factor)); height = max(1, Int(Double(r.height) * factor))
        }
        width = min(576, width); height = min(720, height)
        let x = horizontal < 0 ? r.right - width : r.x, y = vertical < 0 ? r.bottom - height : r.y
        if let string = source.textScrap {
            renderTextSelection(string, frame: PixelRect(x: x, y: y, width: width, height: height)); return
        }
        selection = FloatingSelection(pixels: source.pixels.scaled(width: width, height: height),
                                      mask: source.mask.scaled(width: width, height: height), origin: PixelPoint(x: x, y: y))
    }
}
