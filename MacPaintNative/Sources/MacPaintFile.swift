import Foundation

enum MacPaintFile {
    enum FormatError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case .invalid(let detail) = self { return "Cannot open this MacPaint document: \(detail)" }
            return nil
        }
    }
    struct Document {
        var bitmap: Bitmap
        var patterns: [Pattern]?
    }
    static func decode(_ data: Data) throws -> Document {
        var bytes = Array(data)
        // MacBinary stores the data fork after its 128-byte file header.
        if bytes.count >= 640, bytes[0] == 0, (1...63).contains(bytes[1]),
           Array(bytes[65..<69]) == Array("PNTG".utf8) {
            let length = Int(bytes[83]) << 24 | Int(bytes[84]) << 16 | Int(bytes[85]) << 8 | Int(bytes[86])
            guard length >= 512, length <= bytes.count - 128 else { throw FormatError.invalid("truncated MacBinary data fork") }
            bytes = Array(bytes[128..<128 + length])
        }
        guard bytes.count >= 512 else { throw FormatError.invalid("missing 512-byte header") }
        let version = bytes[0..<4].reduce(0) { ($0 << 8) | Int($1) }
        guard version == 0 || version == 2 else { throw FormatError.invalid("unsupported header version \(version)") }
        var bitmap = Bitmap(), offset = 512
        for row in 0..<720 {
            var scanline = [UInt8]()
            while scanline.count < 72 {
                guard offset < bytes.count else { throw FormatError.invalid("truncated scanline \(row + 1)") }
                let control = Int(Int8(bitPattern: bytes[offset])); offset += 1
                if control >= 0 {
                    let count = control + 1
                    guard offset + count <= bytes.count, scanline.count + count <= 72 else {
                        throw FormatError.invalid("invalid literal run in scanline \(row + 1)")
                    }
                    scanline.append(contentsOf: bytes[offset..<offset + count]); offset += count
                } else if control != -128 {
                    let count = 1 - control
                    guard offset < bytes.count, scanline.count + count <= 72 else {
                        throw FormatError.invalid("invalid repeat run in scanline \(row + 1)")
                    }
                    scanline.append(contentsOf: repeatElement(bytes[offset], count: count)); offset += 1
                }
            }
            bitmap.bytes.replaceSubrange(row * 72..<(row + 1) * 72, with: scanline)
        }
        let patterns: [Pattern]? = version >= 2 ? (0..<38).map { Pattern(Array(bytes[4 + $0 * 8..<12 + $0 * 8])) } : nil
        return Document(bitmap: bitmap, patterns: patterns)
    }
    static func encode(_ bitmap: Bitmap, patterns: [Pattern]) -> Data {
        precondition(bitmap.width == 576 && bitmap.height == 720 && patterns.count == 38)
        var result: [UInt8] = [0, 0, 0, 2]
        result.append(contentsOf: patterns.flatMap(\.rows))
        result.append(contentsOf: repeatElement(0, count: 512 - result.count))
        for row in 0..<720 {
            let source = Array(bitmap.bytes[row * 72..<(row + 1) * 72])
            var i = 0
            while i < source.count {
                var run = 1
                while i + run < source.count && source[i + run] == source[i] && run < 128 { run += 1 }
                if run >= 3 {
                    result.append(UInt8(bitPattern: Int8(1 - run))); result.append(source[i]); i += run
                } else {
                    let start = i; i += run
                    while i < source.count && i - start < 128 {
                        var next = 1
                        while i + next < source.count && source[i + next] == source[i] && next < 3 { next += 1 }
                        if next >= 3 { break }
                        i += min(next, 128 - (i - start))
                    }
                    result.append(UInt8(i - start - 1)); result.append(contentsOf: source[start..<i])
                }
            }
        }
        return Data(result)
    }
}
