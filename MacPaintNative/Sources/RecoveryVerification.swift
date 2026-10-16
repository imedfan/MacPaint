import AppKit
import CryptoKit
import Darwin

enum RecoveryVerification {
    static func checkStore(resources: ClassicResources, output: URL) throws -> [String] {
        let root = output.appendingPathComponent("RecoveryStore-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = PaintModel(resources: resources)
        model.setOrigin(.zero); model.chooseTool(.pencil)
        model.begin(at: PixelPoint(x: 100, y: 100)); model.end(at: PixelPoint(x: 110, y: 100))
        let snapshot = RecoverySnapshot(model: model, title: "Unsaved")
        var first: RecoveryStore? = try RecoveryStore(root: root)
        try first!.write(snapshot)
        let reader = try RecoveryStore(root: root)
        guard try reader.takeLatestAbandoned() == nil else { throw Verification.Failure(description: "recovery stole work from an active session") }
        let abandoned = first!.session
        first = nil // Kernel releases the lock, leaving the crash snapshot intact.
        guard let recovered = try reader.takeLatestAbandoned() else { throw Verification.Failure(description: "abandoned snapshot not recovered") }
        let restored = PaintModel(resources: resources)
        try recovered.restore(into: restored)
        guard restored.displayBitmap == model.displayBitmap, restored.isDirty, restored.origin == .zero else {
            throw Verification.Failure(description: "recovery lost pixels, dirty state or viewport")
        }
        guard !FileManager.default.fileExists(atPath: abandoned.path) else { throw Verification.Failure(description: "claimed crash session was not removed") }
        try reader.close()

        var corrupt: RecoveryStore? = try RecoveryStore(root: root)
        let corruptFile = corrupt!.session.appendingPathComponent("Snapshot.plist")
        try Data("damaged recovery file".utf8).write(to: corruptFile)
        corrupt = nil
        let next = try RecoveryStore(root: root)
        do {
            _ = try next.takeLatestAbandoned()
            throw Verification.Failure(description: "corrupt recovery accepted")
        } catch is DecodingError { }
        guard FileManager.default.fileExists(atPath: corruptFile.path) else { throw Verification.Failure(description: "corrupt recovery was deleted") }
        try next.close()
        return ["live recovery session is protected by kernel lock", "abandoned snapshot restores every pixel and dirty state",
                "recovery restores original viewport", "claimed recovery is copied before old session removal",
                "damaged recovery is reported and retained"]
    }
    static func writeAndExit(controller: AppController, output: URL) throws -> Never {
        let model = controller.model!
        model.setOrigin(.zero); model.chooseTool(.pencil)
        model.begin(at: PixelPoint(x: 100, y: 100)); model.end(at: PixelPoint(x: 135, y: 120))
        let store = try RecoveryStore(root: output.appendingPathComponent("RecoveryProcess", isDirectory: true))
        try store.write(RecoverySnapshot(model: model, title: "Crash fixture"))
        let report: [String: Any] = ["writerPID": ProcessInfo.processInfo.processIdentifier,
                                    "bitmapSHA256": hash(model.displayBitmap), "session": store.session.lastPathComponent]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Recovery-Writer.json"))
        FileHandle.standardOutput.write(Data("Saved unsaved drawing; exiting without application cleanup.\n".utf8))
        Darwin._exit(0)
    }
    static func readAfterExit(controller: AppController, output: URL) throws {
        let store = try RecoveryStore(root: output.appendingPathComponent("RecoveryProcess", isDirectory: true))
        guard let snapshot = try store.takeLatestAbandoned() else { throw Verification.Failure(description: "no recovery after abrupt process exit") }
        try snapshot.restore(into: controller.model)
        let writer = try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("Recovery-Writer.json"))) as! [String: Any]
        guard writer["writerPID"] as? Int != Int(ProcessInfo.processInfo.processIdentifier),
              hash(controller.model.displayBitmap) == writer["bitmapSHA256"] as? String,
              controller.model.isDirty, controller.documentURL == nil else {
            throw Verification.Failure(description: "cross-process recovery lost pixels or original document safety")
        }
        try store.close()
        let report: [String: Any] = ["result": "passed", "readerPID": ProcessInfo.processInfo.processIdentifier,
                                    "writerPID": writer["writerPID"]!, "bitmapSHA256": hash(controller.model.displayBitmap),
                                    "dirty": controller.model.isDirty, "originalFileOverwritten": false]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Recovery-Reader.json"))
        print("A separate process recovered the unsaved bitmap after abrupt exit; original file is untouched.")
    }
    private static func hash(_ bitmap: Bitmap) -> String {
        SHA256.hash(data: Data(bitmap.bytes)).map { String(format: "%02x", $0) }.joined()
    }
}
