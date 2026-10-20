import AppKit
import CryptoKit

final class AIDrawingBatch {
    let actions: [AIDrawingAction]
    let previousUndo: PaintState?
    let completion: ([String: Any]) -> Void
    var applied = 0
    init(actions: [AIDrawingAction], previousUndo: PaintState?, completion: @escaping ([String: Any]) -> Void) {
        self.actions = actions; self.previousUndo = previousUndo; self.completion = completion
    }
}

extension AppController {
    var aiControlActive: Bool { modsEnabled && aiControlEnabled }
    var aiProgress: String? {
        guard let batch = aiBatch else { return nil }
        return "Drawing \(batch.applied)/\(batch.actions.count)"
    }
    var aiSocketPath: String {
        verificationDirectory == nil ? AITransport.defaultPath : "/private/tmp/macpaint-ai-verify-\(ProcessInfo.processInfo.processIdentifier)/control.sock"
    }
    func updateAIControl() {
        guard model != nil, workspace != nil else { return }
        if !aiControlActive {
            cancelAIDrawing()
            aiListener?.stop(); aiListener = nil
            aiControlStatus = "AI control is off."
        } else if aiListener == nil {
            do {
                aiListener = try AIControlListener(path: aiSocketPath) { [weak self] request, reply in
                    guard let self else { reply(AITransport.toolError("MacPaint closed.")); return }
                    self.handleAIRequest(request, completion: reply)
                }
                aiControlStatus = "Ready for local MCP clients."
            } catch { aiControlStatus = error.localizedDescription }
        }
        workspace.refresh()
    }
    func showAIConnection() {
        let alert = NSAlert()
        alert.messageText = "MacPaint AI control"
        alert.informativeText = aiControlStatus + "\n\nMCP command:\n" + Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MacPaintMCP").path
            + "\n\nSocket:\n" + aiSocketPath
        alert.runModal()
    }
    func handleAIRequest(_ request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        do {
            guard aiControlActive else { throw AIControlError("Enable About → Enable mods and Mods → AI control first.") }
            guard let name = request["name"] as? String, let arguments = request["arguments"] as? [String: Any] else { throw AIControlError("Invalid AI request.") }
            if name == "list_documents" {
                guard arguments.isEmpty else { throw AIControlError("list_documents takes no arguments.") }
                completion(try aiText(aiDocumentList())); return
            }
            if name == "get_canvas" {
                guard workspace.documentOpen else { throw AIControlError("Open or create a drawing first.") }
                guard arguments.isEmpty else { throw AIControlError("get_canvas takes no arguments.") }
                completion(try aiCanvas()); return
            }
            guard aiBatch == nil, pending128KOperation == nil, workspace.allowsAICommands,
                  NSApp.modalWindow == nil, window.attachedSheet == nil, !model.hasActiveGesture else {
                throw AIControlError("MacPaint is busy. Finish the current gesture, dialog or operation first.")
            }
            if try handleAIDocumentRequest(name, arguments: arguments, completion: completion) { return }
            guard workspace.documentOpen else { throw AIControlError("Open or create a drawing first.") }
            switch name {
            case "undo":
                guard arguments.isEmpty else { throw AIControlError("undo takes no arguments.") }
                guard model.undoState != nil else { throw AIControlError("There is nothing to undo.") }
                model.undo(); workspace.refresh()
                completion(["content": [["type": "text", "text": "MacPaint single-level Undo applied. Call get_canvas to inspect."]]])
            case "draw_batch":
                let actions = try AIDrawingAction.parseBatch(arguments)
                let bytes = try JSONSerialization.data(withJSONObject: arguments).count
                let scratch = actions.map { $0.scratchBytes(resources: model.resources) }.max() ?? 0
                guard model.allowVirtualMemory("AI drawing batch", additional: bytes + scratch) else {
                    let reason = model.memoryRefusal!; model.memoryRefusal = nil
                    throw AIControlError(reason)
                }
                let previousUndo = model.undoState
                model.commitText(); model.finishPolygon(); model.checkpoint(); model.acceptSelection()
                aiBatch = AIDrawingBatch(actions: actions, previousUndo: previousUndo, completion: completion)
                workspace.popup = nil; workspace.popupHover = nil
                let timer = Timer(timeInterval: macintosh128K.timed ? 0.08 : 0.015, repeats: true) { [weak self] _ in self?.advanceAIDrawing() }
                aiTimer = timer; RunLoop.main.add(timer, forMode: .common)
                workspace.refresh()
            default: throw AIControlError("Unknown AI tool: \(name).")
            }
        } catch { completion(AITransport.toolError(error.localizedDescription)) }
    }
    private func advanceAIDrawing() {
        guard let batch = aiBatch else { return }
        guard aiControlActive else { cancelAIDrawing(); return }
        batch.actions[batch.applied].apply(to: model); batch.applied += 1
        workspace.refresh()
        if batch.applied == batch.actions.count { finishAIDrawing(cancelled: false) }
    }
    func cancelAIDrawing() { if aiBatch != nil { finishAIDrawing(cancelled: true) } }
    private func finishAIDrawing(cancelled: Bool) {
        guard let batch = aiBatch else { return }
        aiTimer?.invalidate(); aiTimer = nil; aiBatch = nil
        if batch.applied == 0 { model.undoState = batch.previousUndo }
        workspace.refresh()
        let state: [String: Any] = ["cancelled": cancelled, "applied": batch.applied, "total": batch.actions.count,
                                   "undo": "single-level; completed actions form one step"]
        let text = String(data: try! JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]), encoding: .utf8)!
        batch.completion(["content": [["type": "text", "text": text]], "isError": false])
    }
    func aiCanvas() throws -> [String: Any] {
        let bitmap = model.displayBitmap
        guard let png = NSBitmapImageRep(cgImage: bitmap.cgImage()).representation(using: .png, properties: [:]) else { throw AIControlError("Cannot export canvas PNG.") }
        func rect(_ value: PixelRect) -> [String: Int] { ["x": value.x, "y": value.y, "width": value.width, "height": value.height] }
        let state: [String: Any] = ["width": bitmap.width, "height": bitmap.height, "coordinate_system": "document pixels, top-left origin",
            "visible_rect": rect(model.activeRect), "fat_bits": model.fatBits,
            "selection": model.selection.map { rect($0.rect) } as Any? ?? NSNull(),
            "document_id": aiDocumentID, "document_path": documentURL?.path as Any? ?? NSNull(),
            "document_title": workspace.documentTitle, "dirty": model.isDirty, "can_undo": model.undoState != nil,
            "sha256": SHA256.hash(data: Data(bitmap.bytes)).map { String(format: "%02x", $0) }.joined(),
            "ai_control": aiControlActive, "drawing": aiProgress as Any? ?? NSNull(),
            "macintosh_128k": ["enabled": macintosh128K.active, "heap_free": max(0, Macintosh128K.heapBytes - model.virtualHeapUsed)]]
        let text = String(data: try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]), encoding: .utf8)!
        return ["content": [["type": "text", "text": text], ["type": "image", "mimeType": "image/png", "data": png.base64EncodedString()]]]
    }
}
