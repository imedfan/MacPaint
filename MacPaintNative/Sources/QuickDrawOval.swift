import Foundation

/// Native scanline translation of CHM QuickDraw DrawArc.a:898 InitOval and
/// :1003 BumpOval. Fixed point arithmetic retains the original half-pixel bias.
enum QuickDrawOval {
    static func spans(in rect: PixelRect, ovalWidth: Int, ovalHeight: Int) -> [Range<Int>] {
        guard !rect.isEmpty else { return [] }
        let width = min(rect.width, max(0, ovalWidth)), height = min(rect.height, max(0, ovalHeight))
        guard width > 0, height > 0 else { return Array(repeating: rect.x..<rect.right, count: rect.height) }
        var left = Int64(rect.x) * 65536 + Int64(width) * 32768
        var right = Int64(rect.right) * 65536 - Int64(width) * 32768 + 32768
        var ovalY = 1 - height
        var radiusSquaredMinusY = Int64(2 * height - 1)
        var square: Int64 = 0
        let aspect = Int64(height) * 65536 / Int64(width)
        var odd = aspect * aspect
        let oddBump = odd * 2
        let skipTop = rect.y + ovalHeight / 2
        let skipBottom = skipTop + rect.height - ovalHeight
        var result = [Range<Int>]()
        for y in rect.y..<rect.bottom {
            if y < skipTop || y >= skipBottom {
                while square >> 32 < radiusSquaredMinusY {
                    right += 32768; left -= 32768; square += odd; odd += oddBump
                }
                while square >> 32 > radiusSquaredMinusY {
                    right -= 32768; left += 32768; odd -= oddBump; square -= odd
                }
                radiusSquaredMinusY -= Int64(4 * (ovalY + 1)); ovalY += 2
            }
            let lower = max(rect.x, Int(left >> 16)), upper = min(rect.right, Int(right >> 16))
            result.append(lower..<max(lower, upper))
        }
        return result
    }
}
