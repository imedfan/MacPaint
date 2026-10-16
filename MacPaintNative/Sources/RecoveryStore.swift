import Foundation
import Darwin

struct RecoverySnapshot: Codable {
    var version = 1
    var current: Data
    var saved: Data
    var title: String
    var originX: Int
    var originY: Int

    init(model: PaintModel, title: String) {
        current = MacPaintFile.encode(model.displayBitmap, patterns: model.patterns)
        saved = MacPaintFile.encode(model.savedBitmap, patterns: model.savedPatterns)
        self.title = title
        originX = model.origin.x; originY = model.origin.y
    }

    func restore(into model: PaintModel) throws {
        let (document, baseline) = try decoded()
        model.load(document)
        model.savedBitmap = baseline.bitmap
        model.savedPatterns = baseline.patterns ?? model.resources.patterns
        model.setOrigin(PixelPoint(x: originX, y: originY))
    }
    func decoded() throws -> (MacPaintFile.Document, MacPaintFile.Document) {
        guard version == 1, (0...160).contains(originX), (0...480).contains(originY),
              current.count <= 1_000_000, saved.count <= 1_000_000 else {
            throw MacPaintFile.FormatError.invalid("invalid recovery snapshot")
        }
        return (try MacPaintFile.decode(current), try MacPaintFile.decode(saved))
    }
}

/// Each process owns a separate session and a kernel-held lock. A second
/// instance can recover abandoned work without reading a live instance's file.
final class RecoveryStore {
    let root: URL
    let session: URL
    private var lockFD: Int32 = -1
    private var lastEncoded: Data?
    private var snapshotURL: URL { session.appendingPathComponent("Snapshot.plist") }

    init(root: URL) throws {
        self.root = root
        session = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        lockFD = Darwin.open(session.appendingPathComponent("active.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            Darwin.close(lockFD); lockFD = -1; throw error
        }
    }
    deinit { if lockFD >= 0 { Darwin.close(lockFD) } }

    func write(_ snapshot: RecoverySnapshot) throws {
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let data = try encoder.encode(snapshot)
        guard data != lastEncoded else { return }
        try data.write(to: snapshotURL, options: .atomic)
        lastEncoded = data
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: snapshotURL.path) { try FileManager.default.removeItem(at: snapshotURL) }
        lastEncoded = nil
    }
    func close() throws {
        try clear()
        if lockFD >= 0 {
            // Keep the lock until the session directory no longer exists.
            try FileManager.default.removeItem(at: session)
            Darwin.close(lockFD); lockFD = -1
        }
    }
    func takeLatestAbandoned() throws -> RecoverySnapshot? {
        let files = FileManager.default
        let candidates = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])
            .filter { $0 != session && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted {
                let a = (try? $0.appendingPathComponent("Snapshot.plist").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.appendingPathComponent("Snapshot.plist").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
        for candidate in candidates {
            let fd = Darwin.open(candidate.appendingPathComponent("active.lock").path, O_RDWR)
            guard fd >= 0 else { continue }
            defer { Darwin.close(fd) }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { continue }
            let snapshotFile = candidate.appendingPathComponent("Snapshot.plist")
            guard files.fileExists(atPath: snapshotFile.path) else { continue }
            let size = try snapshotFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2_100_000 else { throw MacPaintFile.FormatError.invalid("oversized recovery file") }
            let snapshot = try PropertyListDecoder().decode(RecoverySnapshot.self, from: Data(contentsOf: snapshotFile))
            // Validate both MacPaint files before claiming or removing anything.
            _ = try snapshot.decoded()
            try write(snapshot)
            try files.removeItem(at: candidate)
            return snapshot
        }
        return nil
    }
}
