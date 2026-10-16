import Foundation
import CoreGraphics

enum ResourceError: LocalizedError {
    case missing(String)
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case .missing(let name): return "Missing original MacPaint resource: \(name)"
        case .invalid(let name): return "Invalid original MacPaint resource: \(name)"
        }
    }
}

struct BitmapFont {
    let bytes: [UInt8]
    let first: Int
    let last: Int
    let ascent: Int
    let descent: Int
    let leading: Int
    let maxWidth: Int
    let height: Int
    let rowBytes: Int
    let kern: Int
    let locations: Int
    let widths: Int
    init(data: Data) throws {
        let bytes = Array(data)
        func word(_ offset: Int) -> Int { Int(bytes[offset]) * 256 + Int(bytes[offset + 1]) }
        guard bytes.count >= 26 else { throw ResourceError.invalid("FONT header") }
        self.bytes = bytes
        first = word(2); last = word(4)
        kern = Int(Int16(bitPattern: UInt16(word(8))))
        maxWidth = word(6)
        height = word(14); ascent = word(18); descent = word(20); leading = word(22)
        rowBytes = word(24) * 2
        locations = 26 + height * rowBytes
        widths = 16 + word(16) * 2
        guard first <= last, last <= 255, height <= 256,
              locations + (last - first + 3) * 2 <= bytes.count,
              widths + (last - first + 2) * 2 <= bytes.count else { throw ResourceError.invalid("FONT tables") }
    }
    private func word(_ offset: Int) -> Int { Int(bytes[offset]) * 256 + Int(bytes[offset + 1]) }
    func advance(_ character: UInt8) -> Int {
        var i = Int(character) >= first && Int(character) <= last ? Int(character) - first : last - first + 1
        if word(widths + i * 2) == 65535 { i = last - first + 1 }
        return Int(bytes[widths + i * 2 + 1])
    }
    func glyph(_ character: UInt8) -> (bitmap: Bitmap, offset: Int, advance: Int) {
        var i = Int(character) >= first && Int(character) <= last ? Int(character) - first : last - first + 1
        if word(widths + i * 2) == 65535 { i = last - first + 1 }
        let left = word(locations + i * 2), right = word(locations + (i + 1) * 2)
        var bitmap = Bitmap(width: max(1, right - left), height: max(1, height))
        for y in 0..<height { for x in 0..<max(0, right - left) {
            bitmap[x, y] = bytes[26 + y * rowBytes + (x + left) / 8] & (0x80 >> ((x + left) & 7)) != 0
        } }
        return (bitmap, Int(bytes[widths + i * 2]) + kern, Int(bytes[widths + i * 2 + 1]))
    }
    func draw(_ text: String, in bitmap: inout Bitmap, at baseline: PixelPoint, scale: Double = 1) {
        let characters = Array(text.data(using: .macOSRoman, allowLossyConversion: true) ?? Data())
        var pen = baseline.x
        for code in characters {
            drawGlyph(code, in: &bitmap, at: PixelPoint(x: pen, y: baseline.y), scale: scale)
            pen += Int((Double(glyph(code).advance) * scale).rounded())
        }
    }
    func drawGlyph(_ code: UInt8, in bitmap: inout Bitmap, at baseline: PixelPoint, scale: Double = 1) {
        let glyph = glyph(code)
        let w = Int((Double(glyph.bitmap.width) * scale).rounded()), h = Int((Double(height) * scale).rounded())
        for y in 0..<h { for x in 0..<w {
            if glyph.bitmap[min(glyph.bitmap.width - 1, Int(Double(x) / scale)), min(height - 1, Int(Double(y) / scale))] {
                bitmap[baseline.x + Int(Double(glyph.offset) * scale) + x, baseline.y - Int(Double(ascent) * scale) + y] = true
            }
        } }
    }
    func cursorSprite(_ code: UInt8) -> Bitmap {
        var result = Bitmap(width: 16, height: 16)
        drawGlyph(code, in: &result, at: .zero)
        return result
    }
    func width(of text: String) -> Int {
        Array(text.data(using: .macOSRoman, allowLossyConversion: true) ?? Data()).reduce(0) { $0 + advance($1) }
    }
}

final class ClassicResources {
    let paintFont: BitmapFont
    let chicago: BitmapFont
    let patterns: [Pattern]
    let help: [Int: Bitmap]
    let fonts: [String: [Int: BitmapFont]]
    let dialogs: [Int: PixelRect]
    let catalogHeader: String

    init(directory: URL) throws {
        func load(_ name: String) throws -> Data {
            let path = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: path.path) else { throw ResourceError.missing(name) }
            return try Data(contentsOf: path)
        }
        paintFont = try BitmapFont(data: load("FONT-31884.bin"))
        chicago = try BitmapFont(data: load("System-FONT-12.bin"))
        let header = Array(try load("STR-2203.bin"))
        guard let length = header.first, length > 0, header.count >= Int(length) + 1,
              let title = String(data: Data(header[1...Int(length)]), encoding: .macOSRoman) else {
            throw ResourceError.invalid("STR 2203")
        }
        catalogHeader = title
        let patternsData = Array(try load("System-PAT_-0.bin"))
        guard patternsData.count == 306, patternsData[1] == 38 else { throw ResourceError.invalid("PAT# 0") }
        patterns = (0..<38).map { Pattern(Array(patternsData[2 + $0 * 8..<10 + $0 * 8])) }
        var pictures = [Int: Bitmap]()
        for ident in [2400, 2401] {
            let bytes = Array(try load("Help-\(ident).bitmap"))
            guard bytes.count >= 4 else { throw ResourceError.invalid("help picture") }
            var bitmap = Bitmap(width: Int(bytes[0]) * 256 + Int(bytes[1]), height: Int(bytes[2]) * 256 + Int(bytes[3]))
            guard bytes.count == bitmap.bytes.count + 4 else { throw ResourceError.invalid("help bitmap") }
            bitmap.bytes = Array(bytes.dropFirst(4)); pictures[ident] = bitmap
        }
        help = pictures
        var dialogRects = [Int: PixelRect]()
        for ident in 2003...2006 {
            let bytes = Array(try load("DLOG-\(ident).bin"))
            guard bytes.count >= 8 else { throw ResourceError.invalid("DLOG header") }
            func word(_ offset: Int) -> Int { Int(Int16(bitPattern: UInt16(bytes[offset]) * 256 + UInt16(bytes[offset + 1]))) }
            let rect = PixelRect(x: word(2), y: word(0), width: word(6) - word(2), height: word(4) - word(0))
            guard !rect.isEmpty, rect.x >= 0, rect.y >= 0, rect.right <= 512, rect.bottom <= 342 else {
                throw ResourceError.invalid("DLOG bounds")
            }
            dialogRects[ident] = rect
        }
        dialogs = dialogRects
        var loadedFonts = [String: [Int: BitmapFont]]()
        for (name, family) in [("Chicago", 0), ("New York", 2), ("Geneva", 3), ("Monaco", 4),
                               ("Times", 20), ("Helvetica", 21), ("Courier", 22)] {
            var sizes = [Int: BitmapFont]()
            for size in 1..<128 {
                let path = directory.appendingPathComponent("System-FONT-\(family * 128 + size).bin")
                if FileManager.default.fileExists(atPath: path.path) { sizes[size] = try BitmapFont(data: Data(contentsOf: path)) }
            }
            loadedFonts[name] = sizes
        }
        fonts = loadedFonts
    }
    func font(named name: String, size: Int) -> (font: BitmapFont, scale: Double) {
        let sizes = fonts[name] ?? fonts["Geneva"]!
        // Inside Macintosh I, Font Scaling (I-220): exact, double, half,
        // next larger, then largest smaller. Dictionary order is irrelevant.
        let available: Int
        if sizes[size] != nil { available = size }
        else if sizes[size * 2] != nil { available = size * 2 }
        else if sizes[size / 2] != nil { available = size / 2 }
        else { available = sizes.keys.filter { $0 > size }.min() ?? sizes.keys.max()! }
        return (sizes[available]!, Double(size) / Double(available))
    }
}

extension Bitmap {
    func cgImage() -> CGImage {
        // A grayscale display image; the authoritative document remains one-bit.
        var gray = [UInt8](repeating: 255, count: width * height)
        for y in 0..<height { for x in 0..<width where self[x, y] { gray[y * width + x] = 0 } }
        let provider = CGDataProvider(data: Data(gray) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
