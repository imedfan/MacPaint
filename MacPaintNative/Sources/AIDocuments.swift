import AppKit
import CoreFoundation

/// Inactive documents retain their complete model, including single-level Undo.
struct AIDocumentSession {
    let id: String
    let model: PaintModel
    let url: URL?
    let title: String
    let recovery: RecoveryStore?

    var info: [String: Any] {
        ["document_id": id, "title": title, "path": url?.path as Any? ?? NSNull(),
         "dirty": model.isDirty, "can_undo": model.undoState != nil]
    }
}

extension AppController {
    var currentAIDocument: AIDocumentSession {
        AIDocumentSession(id: aiDocumentID, model: model, url: documentURL,
                          title: workspace.documentTitle, recovery: recovery)
    }
    func aiText(_ value: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return ["content": [["type": "text", "text": String(data: data, encoding: .utf8)!]]]
    }
    func aiDocumentList() -> [String: Any] {
        let documents = (workspace.documentOpen ? [currentAIDocument] : []) + aiParkedDocuments
        return ["active_document_id": workspace.documentOpen ? aiDocumentID as Any : NSNull(),
                "documents": documents.map { document -> [String: Any] in
                    var info = document.info; info["active"] = workspace.documentOpen && document.id == aiDocumentID
                    return info
                }]
    }
    private func activateAIDocument(_ document: AIDocumentSession) {
        model = document.model; model.macintosh128K = macintosh128K
        workspace.model = model; documentURL = document.url; workspace.documentTitle = document.title
        recovery = document.recovery; aiDocumentID = document.id; workspace.documentOpen = true
        workspace.helpID = nil; workspace.pageOverview = false; workspace.reset128KMouse()
        window.makeKeyAndOrderFront(nil); workspace.refresh()
    }
    func switchAIDocument(to id: String) {
        guard id != aiDocumentID, let index = aiParkedDocuments.firstIndex(where: { $0.id == id }) else { return }
        flushRecovery()
        let target = aiParkedDocuments.remove(at: index)
        if workspace.documentOpen { aiParkedDocuments.append(currentAIDocument) }
        activateAIDocument(target)
    }
    private func addAIDocument(_ document: MacPaintFile.Document?, url: URL?) throws {
        guard aiParkedDocuments.count + (workspace.documentOpen ? 1 : 0) < 16 else {
            throw AIControlError("At most 16 documents can be open. Close a document before creating another.")
        }
        let next = PaintModel(resources: model.resources)
        if let document { next.patterns = model.patterns; next.load(document) }
        let nextRecovery = try recovery.map { try RecoveryStore(root: $0.root) }
        flushRecovery()
        if workspace.documentOpen { aiParkedDocuments.append(currentAIDocument) }
        else { try recovery?.close() }
        activateAIDocument(AIDocumentSession(id: UUID().uuidString, model: next, url: url,
            title: url?.deletingPathExtension().lastPathComponent ?? "Untitled", recovery: nextRecovery))
    }
    func handleAIDocumentRequest(_ name: String, arguments: [String: Any], completion: ([String: Any]) -> Void) throws -> Bool {
        let allowed: Set<String>
        switch name {
        case "new_document": allowed = []
        case "open_document": allowed = ["path"]
        case "switch_document": allowed = ["document_id"]
        case "save_document", "save_as", "export_png": allowed = ["path", "overwrite"]
        default: return false
        }
        guard Set(arguments.keys).isSubset(of: allowed) else { throw AIControlError("Unknown argument for \(name).") }
        func path() throws -> URL {
            guard let value = arguments["path"] as? String, value.hasPrefix("/"), !value.contains("\0"),
                  value.utf8.count <= 4096 else { throw AIControlError("path must be an absolute local filesystem path of at most 4096 bytes.") }
            return URL(fileURLWithPath: value).standardizedFileURL.resolvingSymlinksInPath()
        }
        func overwrite() throws -> Bool {
            guard let value = arguments["overwrite"] else { return false }
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw AIControlError("overwrite must be a boolean.")
            }
            return number.boolValue
        }
        switch name {
        case "new_document": try addAIDocument(nil, url: nil)
        case "open_document":
            let url = try path()
            let documents = (workspace.documentOpen ? [currentAIDocument] : []) + aiParkedDocuments
            if let existing = documents.first(where: { $0.url?.resolvingSymlinksInPath() == url }) {
                switchAIDocument(to: existing.id)
            } else {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize, size <= 1_000_000 else {
                    throw AIControlError("Open a regular MacPaint file of at most 1 MB.")
                }
                let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                let data = try file.read(upToCount: 1_000_001) ?? Data()
                guard data.count <= 1_000_000 else { throw AIControlError("MacPaint input exceeds 1 MB.") }
                try addAIDocument(MacPaintFile.decode(data), url: url)
            }
        case "switch_document":
            guard let id = arguments["document_id"] as? String,
                  (workspace.documentOpen && id == aiDocumentID) || aiParkedDocuments.contains(where: { $0.id == id }) else {
                throw AIControlError("Unknown document_id. Call list_documents.")
            }
            switchAIDocument(to: id)
        case "save_document", "save_as", "export_png":
            guard workspace.documentOpen else { throw AIControlError("Open or create a drawing first.") }
            let explicitOverwrite = try overwrite()
            let url: URL
            if name == "save_document", arguments["path"] == nil {
                guard let current = documentURL else { throw AIControlError("This document has no path. Supply path or use save_as.") }
                url = current.resolvingSymlinksInPath()
            } else { url = try path() }
            let others = aiParkedDocuments.compactMap(\.url).map { $0.resolvingSymlinksInPath() }
            guard !others.contains(url) else { throw AIControlError("That path belongs to another open document. Switch to it first.") }
            if name == "export_png" {
                guard documentURL?.resolvingSymlinksInPath() != url else { throw AIControlError("PNG export cannot replace the active MacPaint file.") }
                guard let data = NSBitmapImageRep(cgImage: model.displayBitmap.cgImage()).representation(using: .png, properties: [:]) else {
                    throw AIControlError("Cannot export canvas PNG.")
                }
                try data.write(to: url, options: explicitOverwrite ? .atomic : .withoutOverwriting)
            } else {
                let savingBack = name == "save_document" && documentURL?.resolvingSymlinksInPath() == url
                try writeDocument(to: url, overwrite: explicitOverwrite || savingBack)
                workspace.refresh()
            }
            var info = currentAIDocument.info; info["written_path"] = url.path
            completion(try aiText(info)); return true
        default: break
        }
        completion(try aiText(currentAIDocument.info)); return true
    }
}
