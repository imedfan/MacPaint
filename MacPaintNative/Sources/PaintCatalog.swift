import Foundation

struct PaintCatalog {
    struct Item {
        let name: String
        let thumbnail: Bitmap
    }
    let items: [Item]
    let header: String
    let font: BitmapFont
    var pageCount: Int { (items.count + 24) / 25 }

    init(pictures: [(String, Bitmap)], folderName: String, resources: ClassicResources) {
        self.init(items: pictures.map { Item(name: $0.0, thumbnail: PrintRaster.catalog($0.1)) },
                  folderName: folderName, resources: resources)
    }
    private init(items: [Item], folderName: String, resources: ClassicResources) {
        self.items = items
        header = resources.catalogHeader + " " + folderName
        font = resources.font(named: "Geneva", size: 12).font
    }
    static func load(directory: URL, resources: ClassicResources) throws -> PaintCatalog {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var items = [Item]()
        for file in files {
            let name = file.lastPathComponent
            guard name != "Paint1", name != "Paint2",
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = try? Data(contentsOf: file), let document = try? MacPaintFile.decode(data) else { continue }
            items.append(Item(name: name, thumbnail: PrintRaster.catalog(document.bitmap)))
        }
        return PaintCatalog(items: items, folderName: directory.lastPathComponent, resources: resources)
    }
    func raster(page: Int) -> Bitmap {
        precondition((0..<pageCount).contains(page))
        var result = Bitmap()
        if page == 0 { font.draw(header, in: &result, at: PixelPoint(x: 28, y: 10)) }
        for index in (page * 25)..<min(items.count, (page + 1) * 25) {
            let slot = index - page * 25, x = 28 + slot % 5 * 112, y = 32 + slot / 5 * 144
            result.frame(PixelRect(x: x, y: y, width: 72, height: 90))
            result.copy(items[index].thumbnail, at: PixelPoint(x: x, y: y), transparent: true)
            font.draw(items[index].name, in: &result,
                      at: PixelPoint(x: x + 36 - font.width(of: items[index].name) / 2, y: y + 106))
        }
        return result
    }
}
