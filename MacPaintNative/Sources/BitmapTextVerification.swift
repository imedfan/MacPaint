import AppKit

enum BitmapTextVerification {
    static func run(resources: ClassicResources, output: URL) throws -> [String] {
        // A and the missing-glyph box are one dot above the baseline. B is
        // explicitly absent. This tiny strike makes style output unambiguous.
        let words: [UInt16] = [0, 65, 66, 1, 0, 0, 1, 4, 13, 1, 3, 0, 1]
        var bytes = words.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] }
        bytes += [0xC0, 0, 0, 0, 0, 0, 0, 0]
        bytes += [0, 0, 0, 1, 0, 1, 0, 2]
        bytes += [0, 1, 255, 255, 0, 1]
        let font = try BitmapFont(data: Data(bytes))
        var checks = [String]()
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw Verification.Failure(description: name) }
            checks.append(name)
        }
        func render(_ string: String = "A", style: Int) -> Bitmap {
            var bitmap = Bitmap(width: 64, height: 40)
            let clip = bitmap.bounds
            BitmapText(font: font, scale: 1, style: style).draw(string, in: &bitmap, at: PixelPoint(x: 20, y: 20), clip: clip)
            return bitmap
        }
        func count(_ bitmap: Bitmap) -> Int { bitmap.bytes.reduce(0) { $0 + $1.nonzeroBitCount } }
        try check(render(style: 0).blackBounds == PixelRect(x: 20, y: 19, width: 1, height: 1), "plain strike preserves glyph bearing and baseline")
        let bold = render("AA", style: 1)
        try check(bold.blackBounds == PixelRect(x: 20, y: 19, width: 4, height: 1) && count(bold) == 4 && BitmapText(font: font, scale: 1, style: 1).width(of: "AA") == 4,
                  "Bold overstrikes right and advances each glyph by one extra pixel")
        try check(render(style: 2).blackBounds == PixelRect(x: 22, y: 19, width: 1, height: 1), "Italic uses QuickDraw half-pixel row shear from strike bottom")
        let underline = render(style: 4)
        try check(count(underline) == 2 && underline[20, 19] && underline[20, 21], "Underline is at baseline plus one and retains the glyph")
        let outline = render(style: 8)
        try check(outline.blackBounds == PixelRect(x: 19, y: 18, width: 3, height: 3) && count(outline) == 8 && !outline[20, 19],
                  "Outline forms the exact eight-pixel ring around a one-dot glyph")
        let shadow = render(style: 16)
        try check(shadow.blackBounds == PixelRect(x: 19, y: 18, width: 4, height: 4) && count(shadow) == 15 && !shadow[20, 19],
                  "Shadow forms the exact asymmetric fifteen-pixel shape and XORs the glyph")
        let combined = render(style: 24)
        try check(combined.blackBounds == PixelRect(x: 19, y: 18, width: 5, height: 5) && count(combined) == 24,
                  "Outline plus Shadow combines Font Manager shadow counts")
        let metrics = BitmapText(font: font, scale: 1, style: 16)
        try check(metrics.ascent == 2 && metrics.descent == 5 && metrics.width(of: "A") == 3,
                  "Shadow updates ascent, descent and advance consistently")
        try check(font.advance(66) == 1 && render("B", style: 0) == render(style: 0), "absent glyph uses missing-glyph pixels and advance")
        let mono = BitmapText(resources: resources, name: "Monaco", size: 9, style: 0)
        let width = mono.width(of: "MMM")
        try check(mono.wrappedLines("ONE TWO", width: width) == ["ONE ", "TWO"], "TextBox wraps at word boundaries and consumes separating spaces")
        try check(mono.wrappedLines("ABCDEFG", width: width) == ["ABC", "DEF", "G"], "TextBox splits an overlong word without losing characters")
        try check(mono.wrappedLines("ONE\r\nTWO\nTHREE", width: mono.width(of: "MMMMMM")) == ["ONE", "TWO", "THREE"],
                  "TextBox accepts classic and native line endings")
        var sheet = Bitmap(width: 416, height: 240)
        for (index, item) in [("Plain", 0), ("Bold", 1), ("Italic", 2), ("Underline", 4), ("Outline", 8), ("Shadow", 16), ("Combined", 31)].enumerated() {
            resources.chicago.draw(item.0, in: &sheet, at: PixelPoint(x: 8, y: 24 + index * 30))
            BitmapText(resources: resources, name: "Geneva", size: 18, style: item.1)
                .draw("MacPaint 1.3", in: &sheet, at: PixelPoint(x: 150, y: 24 + index * 30), clip: sheet.bounds)
        }
        try NSBitmapImageRep(cgImage: sheet.scaled(width: 832, height: 480).cgImage()).representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent("Text-Styles.png"))
        return checks
    }
}
