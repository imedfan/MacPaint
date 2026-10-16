import Foundation

enum PrintRaster {
    /// PaintAsm.a SampleBits and HToneRow, with the exact GetCatPic levels.
    static func catalog(_ source: Bitmap) -> Bitmap {
        precondition(source.width == 576 && source.height == 720)
        func sample(_ band: Int) -> [Int] {
            (0..<72).map { x in
                let count = (0..<8).reduce(0) { $0 + source.bytes[(band * 8 + $1) * 72 + x].nonzeroBitCount }
                return min(255, count * 4)
            } + [0]
        }
        func clipped(_ value: Int) -> Int { max(8, min(64, value)) }
        var result = Bitmap(width: 72, height: 90), row = [Int]()
        for y in 0..<90 {
            var next = sample(y)
            if y == 0 { row = next }
            for x in 0..<72 {
                var error = row[x] - 8
                if error >= 28 { result[x, y] = true; error -= 56 }
                let quarter = error >> 2
                row[x + 1] = clipped(row[x + 1] + quarter)
                next[x] = clipped(next[x] + quarter)
                next[x + 1] = clipped(next[x + 1] + (quarter >> 1))
            }
            row = next
        }
        return result
    }

    /// Native pixel translation of PaintAsm.a:94 Stretch2x. The ImageWriter
    /// used these sparse dots at twice the document resolution for Print Final.
    static func final(_ source: Bitmap) -> Bitmap {
        var result = Bitmap(width: source.width * 2, height: source.height * 2)
        for y in 0..<source.height { for x in 0..<source.width {
            result[x * 2, y * 2] = source[x, y]
            result[x * 2 + 1, y * 2] = source[x, y] && source[x + 1, y]
            result[x * 2, y * 2 + 1] = source[x, y] && source[x, y + 1]
        } }
        // Stretch2x XORs the two diagonal interpolants into odd scanlines.
        for y in 0..<(source.height - 1) { for x in 0..<(source.width - 1) {
            let left = result[x * 2, y * 2] && result[x * 2 + 2, y * 2 + 2]
            let right = result[x * 2 + 2, y * 2] && result[x * 2, y * 2 + 2]
            result[x * 2 + 1, y * 2 + 1] = left != right
        } }
        // Preserve a white pixel surrounded by four black neighbours.
        if source.width > 2 && source.height > 2 {
            for y in 1..<(source.height - 1) { for x in 1..<(source.width - 1) {
                if !source[x, y] && source[x - 1, y] && source[x + 1, y] && source[x, y - 1] && source[x, y + 1] {
                    for dx in -1...1 { result[x * 2 + dx, y * 2 - 1] = false; result[x * 2 + dx, y * 2 + 1] = false }
                }
            } }
        }
        return result
    }
}
