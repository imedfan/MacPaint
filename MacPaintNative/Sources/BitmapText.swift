import Foundation

/// One-bit text layout using the recovered strikes. Style raster operations
/// follow QuickDraw DrawText.a; Font Manager style deltas are documented in
/// Executor's quickdraw/font.cpp. No Toolbox or emulator runs in this port.
struct BitmapText {
    let font: BitmapFont
    let scale: Double
    let style: Int
    private var shadow: Int { (style & 8 != 0 ? 1 : 0) + (style & 16 != 0 ? 2 : 0) }
    private var bold: Int { style & 1 != 0 ? 1 : 0 }
    private var extra: Int { bold + shadow }
    var ascent: Int { scaled(font.ascent + (shadow > 0 ? 1 : 0)) }
    var descent: Int { scaled(font.descent + shadow) }
    var leading: Int { scaled(font.leading) }
    var lineHeight: Int { max(1, ascent + descent + leading) }
    var maxWidth: Int { scaled(font.maxWidth + bold + shadow + (shadow > 0 ? 1 : 0)) }
    private func scaled(_ value: Int) -> Int { Int((Double(value) * scale).rounded()) }
    init(font: BitmapFont, scale: Double, style: Int) {
        self.font = font; self.scale = scale; self.style = style
    }
    init(resources: ClassicResources, name: String, size: Int, style: Int) {
        let chosen = resources.font(named: name, size: size)
        self.init(font: chosen.font, scale: chosen.scale, style: style)
    }
    private func bytes(_ text: String) -> [UInt8] {
        Array(text.data(using: .macOSRoman, allowLossyConversion: true) ?? Data())
    }
    func width(of text: String) -> Int {
        scaled(bytes(text).reduce(0) { $0 + font.advance($1) + extra })
    }
    func draw(_ text: String, in bitmap: inout Bitmap, at baseline: PixelPoint, clip: PixelRect) {
        let codes = bytes(text)
        guard !codes.isEmpty else { return }
        let advance = codes.reduce(0) { $0 + font.advance($1) + extra }
        let left = 4 + max(0, -font.kern), top = 4
        let slop = font.maxWidth + (style & 2 != 0 ? font.height / 2 : 0) + 8
        var layer = Bitmap(width: max(1, left + advance + slop), height: font.height + 12)
        let nativeBaseline = top + font.ascent
        var pen = left
        for code in codes {
            font.drawGlyph(code, in: &layer, at: PixelPoint(x: pen, y: nativeBaseline))
            pen += font.advance(code) + extra
        }
        if bold != 0 { let original = layer; layer.copy(original, at: PixelPoint(x: 1, y: 0), transparent: true) }
        if style & 2 != 0 {
            let original = layer; layer = Bitmap(width: layer.width, height: layer.height)
            for y in 0..<font.height {
                let shift = (font.height - y) / 2
                for x in 0..<original.width where original[x, top + y] { layer[x + shift, top + y] = true }
            }
        }
        if style & 4 != 0 && font.descent >= 2 {
            let original = layer
            for x in left..<(left + advance) {
                var blocked = false
                for dy in 0...(font.descent == 2 ? 1 : 2) {
                    for dx in -1...1 where original[x + dx, nativeBaseline + dy] { blocked = true }
                }
                if !blocked { layer[x, nativeBaseline + 1] = true }
            }
        }
        if shadow > 0 {
            let original = layer
            layer = Bitmap(width: layer.width, height: layer.height)
            for y in 0..<original.height { for x in 0..<original.width where original[x, y] {
                for dy in -1...shadow { for dx in -1...shadow { layer[x + dx, y + dy] = true } }
            } }
            for y in 0..<original.height { for x in 0..<original.width where original[x, y] { layer[x, y].toggle() } }
        }
        let raster = scale == 1 ? layer : layer.scaled(width: max(1, scaled(layer.width)), height: max(1, scaled(layer.height)))
        let origin = PixelPoint(x: baseline.x - scaled(left), y: baseline.y - scaled(nativeBaseline))
        let bounds = PixelRect(x: origin.x, y: origin.y, width: raster.width, height: raster.height).intersect(clip).intersect(bitmap.bounds)
        guard !bounds.isEmpty else { return }
        for y in bounds.y..<bounds.bottom { for x in bounds.x..<bounds.right where raster[x - origin.x, y - origin.y] { bitmap[x, y] = true } }
    }

    func wrappedLines(_ text: String, width: Int) -> [String] {
        let codes = bytes(text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r"))
        var lines = [String](), start = 0
        while start < codes.count {
            var end = start, nativeWidth = 0
            while end < codes.count && codes[end] != 13 && scaled(nativeWidth) <= width {
                nativeWidth += font.advance(codes[end]) + extra; end += 1
            }
            if scaled(nativeWidth) > width {
                let overflow = end - 1
                if codes[overflow] == 32 {
                    end = overflow
                    while end < codes.count && codes[end] == 32 { end += 1 }
                } else {
                    var boundary = overflow
                    while boundary > start && codes[boundary - 1] > 32 { boundary -= 1 }
                    end = boundary > start ? boundary : overflow
                }
            } else if end < codes.count && codes[end] == 13 { end += 1 }
            end = max(start + 1, end)
            let stop = codes[end - 1] == 13 ? end - 1 : end
            lines.append(String(data: Data(codes[start..<stop]), encoding: .macOSRoman)!)
            start = end
        }
        return lines
    }
    func box(_ text: String, width: Int, height: Int, alignment: Int) -> Bitmap {
        var bitmap = Bitmap(width: max(1, width), height: max(1, height))
        let available = max(maxWidth + 7, width - 4)
        for (index, line) in wrappedLines(text, width: available).enumerated() {
            let top = index * lineHeight
            if top >= height { break }
            let visible = line.replacingOccurrences(of: "[\\x00-\\x20]+$", with: "", options: .regularExpression)
            let textWidth = self.width(of: visible)
            let x = 2 + (alignment == 1 ? (available - textWidth) / 2 : alignment == 2 ? available - textWidth : 0)
            draw(line, in: &bitmap, at: PixelPoint(x: x, y: top + ascent), clip: bitmap.bounds)
        }
        return bitmap
    }
}
