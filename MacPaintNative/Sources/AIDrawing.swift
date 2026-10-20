import Foundation
import CoreFoundation

struct AIControlError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum AIDrawingAction {
    case stroke([PixelPoint], Int, Pattern)
    case rectangle(PixelRect, Bool, Int, Pattern)
    case oval(PixelRect, Bool, Int, Pattern)
    case polygon([PixelPoint], Bool, Int, Pattern)
    case fill(PixelPoint, Pattern)
    case text(PixelPoint, String, String, Int)

    static let fonts = ["Chicago", "Geneva", "New York", "Monaco", "Times", "Helvetica", "Courier"]

    static func parseBatch(_ arguments: [String: Any]) throws -> [AIDrawingAction] {
        guard Set(arguments.keys).isSubset(of: ["actions"]), let rows = arguments["actions"] as? [[String: Any]],
              (1...128).contains(rows.count) else { throw AIControlError("Supply 1–128 actions.") }
        var pointsUsed = 0, work = 0
        let actions = try rows.map { row -> AIDrawingAction in
            func integer(_ key: String, _ range: ClosedRange<Int>, default fallback: Int? = nil) throws -> Int {
                if row[key] == nil, let fallback { return fallback }
                guard let value = row[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                      value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue,
                      value.doubleValue >= Double(range.lowerBound), value.doubleValue <= Double(range.upperBound)
                else { throw AIControlError("\(key) must be an integer in \(range).") }
                return value.intValue
            }
            func point() throws -> PixelPoint {
                try PixelPoint(x: integer("x", 0...575), y: integer("y", 0...719))
            }
            func points(_ minimum: Int) throws -> [PixelPoint] {
                guard let list = row["points"] as? [[String: Any]], (minimum...512).contains(list.count) else {
                    throw AIControlError("points must contain \(minimum)–512 {x,y} document pixels.")
                }
                pointsUsed += list.count
                return try list.map { value in
                    guard Set(value.keys) == ["x", "y"] else { throw AIControlError("Each point needs only x and y.") }
                    guard let x = value["x"] as? NSNumber, let y = value["y"] as? NSNumber,
                          CFGetTypeID(x) != CFBooleanGetTypeID(), CFGetTypeID(y) != CFBooleanGetTypeID(),
                          (0...575).contains(x.doubleValue), (0...719).contains(y.doubleValue),
                          x.doubleValue.rounded() == x.doubleValue, y.doubleValue.rounded() == y.doubleValue else {
                        throw AIControlError("Point coordinates must be integer document pixels: x 0–575, y 0–719.")
                    }
                    return PixelPoint(x: x.intValue, y: y.intValue)
                }
            }
            func rect() throws -> PixelRect {
                let p = try point()
                return try PixelRect(x: p.x, y: p.y, width: integer("width", 1...(576 - p.x)),
                                     height: integer("height", 1...(720 - p.y)))
            }
            func filled() throws -> Bool {
                guard let value = row["filled"] else { return false }
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                    throw AIControlError("filled must be a boolean.")
                }
                return number.boolValue
            }
            guard let type = row["type"] as? String else { throw AIControlError("Each action needs a type.") }
            let allowed: Set<String>
            switch type {
            case "stroke", "line", "polygon": allowed = ["type", "points", "line_width", "color", "filled"]
            case "rectangle", "oval": allowed = ["type", "x", "y", "width", "height", "line_width", "color", "filled"]
            case "fill": allowed = ["type", "x", "y", "color"]
            case "text": allowed = ["type", "x", "y", "text", "font", "size"]
            default: throw AIControlError("Unsupported action: \(type).")
            }
            guard Set(row.keys).isSubset(of: allowed) else { throw AIControlError("Unknown field in \(type).") }
            let color = row["color"] as? String ?? "black"
            guard ["black", "white", "gray"].contains(color), row["color"] == nil || row["color"] is String else {
                throw AIControlError("color must be black, white, or gray.")
            }
            let pattern: Pattern = color == "white" ? .white : color == "gray" ? .gray : .black
            let width = try integer("line_width", 1...16, default: 1)
            switch type {
            case "stroke", "line", "polygon":
                let vertices = try points(type == "polygon" ? 3 : type == "line" ? 2 : 1)
                if type == "line" && vertices.count != 2 { throw AIControlError("A line needs exactly two points.") }
                for (a, b) in zip(vertices, vertices.dropFirst()) {
                    work += (max(abs(a.x - b.x), abs(a.y - b.y)) + 1) * width * width
                }
                if type == "polygon" {
                    work += 576 * 720
                    return .polygon(vertices, try filled(), width, pattern)
                }
                return .stroke(vertices, width, pattern)
            case "rectangle", "oval":
                let r = try rect(); work += r.width * r.height
                return type == "rectangle" ? .rectangle(r, try filled(), width, pattern) : .oval(r, try filled(), width, pattern)
            case "fill": work += 576 * 720; return .fill(try point(), pattern)
            default:
                guard let text = row["text"] as? String, !text.isEmpty, text.utf8.count <= 1024,
                      text.split(separator: "\n", omittingEmptySubsequences: false).count <= 20,
                      text.split(separator: "\n").allSatisfy({ $0.count <= 80 }),
                      text.data(using: .macOSRoman, allowLossyConversion: false) != nil,
                      text.unicodeScalars.allSatisfy({ $0.value >= 32 || $0.value == 10 }) else {
                    throw AIControlError("text needs 1–1024 bytes, at most 20 lines of 80 Mac Roman characters. Use Latin text.")
                }
                let font = row["font"] as? String ?? "Geneva"
                guard fonts.contains(font), row["font"] == nil || row["font"] is String else { throw AIControlError("Unknown bitmap font.") }
                let size = try integer("size", 9...72, default: 12)
                work += 576 * 720
                return .text(try point(), text, font, size)
            }
        }
        guard pointsUsed <= 2048, work <= 8_000_000 else { throw AIControlError("Batch too large. Use fewer points, thinner lines, or smaller batches.") }
        return actions
    }

    func scratchBytes(resources: ClassicResources) -> Int {
        switch self {
        case .fill: return 576 * 720 * 4 + 51_840
        case .text(_, let text, let font, let size):
            let raster = BitmapText(resources: resources, name: font, size: size, style: 0)
            return (text.split(separator: "\n").map { raster.width(of: String($0)) }.max() ?? 0) * raster.lineHeight / 4 + 2048
        default: return 2048
        }
    }

    func apply(to model: PaintModel) {
        switch self {
        case .stroke(let points, let width, let pattern):
            model.bitmap.line(from: points[0], to: points[0], width: width, pattern: pattern)
            for (a, b) in zip(points, points.dropFirst()) { model.bitmap.line(from: a, to: b, width: width, pattern: pattern) }
        case .rectangle(let rect, let filled, let width, let pattern):
            if filled { model.bitmap.fill(rect, pattern: pattern) }
            else { model.bitmap.frame(rect, width: min(width, min(rect.width, rect.height)), pattern: pattern) }
        case .oval(let rect, let filled, let width, let pattern):
            let outer = QuickDrawOval.spans(in: rect, ovalWidth: rect.width, ovalHeight: rect.height)
            let innerRect = PixelRect(x: rect.x + width, y: rect.y + width, width: rect.width - width * 2, height: rect.height - width * 2)
            let inner = innerRect.isEmpty ? [] : QuickDrawOval.spans(in: innerRect, ovalWidth: innerRect.width, ovalHeight: innerRect.height)
            for y in rect.y..<rect.bottom {
                for x in outer[y - rect.y] {
                    let index = y - innerRect.y
                    if filled || !inner.indices.contains(index) || !inner[index].contains(x) { model.bitmap[x, y] = pattern.pixel(x, y) }
                }
            }
        case .polygon(let points, let filled, let width, let pattern):
            model.bitmap.polygon(points, filled: filled, width: width, pattern: pattern, border: false)
        case .fill(let point, let pattern): model.bitmap.flood(at: point, pattern: pattern)
        case .text(let point, let text, let font, let size):
            let raster = BitmapText(resources: model.resources, name: font, size: size, style: 0)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                raster.draw(String(line), in: &model.bitmap, at: PixelPoint(x: point.x, y: point.y + raster.ascent + index * raster.lineHeight), clip: model.bitmap.bounds)
            }
        }
    }
}
