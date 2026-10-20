import Foundation

/// STDIO mode of the bundled executable. It never starts NSApplication.
enum MCPServer {
    static let instructions = "Control MacPaint documents. First call list_documents or get_canvas. new_document and open_document preserve the current document; switch_document uses IDs from list_documents. Save with save_document or save_as; export_png does not mark the document saved. Paths must be absolute. Coordinates are document pixels (576×720), top-left origin, independent of scrolling and zoom. draw_batch is one single-level Undo step. This is raster editing: erase old pixels with white before redrawing. Do not retry a mutation after a transport timeout without reading list_documents/get_canvas and checking the destination file. Enable mods and AI control in MacPaint first."
    static var tools: [[String: Any]] {
        func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
        }
        func integer(_ low: Int, _ high: Int) -> [String: Any] { ["type": "integer", "minimum": low, "maximum": high] }
        let point = object(["x": integer(0, 575), "y": integer(0, 719)], required: ["x", "y"])
        let color: [String: Any] = ["type": "string", "enum": ["black", "white", "gray"], "default": "black"]
        var actions = [[String: Any]]()
        for type in ["stroke", "line", "polygon", "rectangle", "oval", "fill", "text"] {
            var properties: [String: Any] = ["type": ["const": type, "type": "string"]]
            var required = ["type"]
            if ["stroke", "line", "polygon"].contains(type) {
                properties["points"] = ["type": "array", "items": point, "minItems": type == "polygon" ? 3 : type == "line" ? 2 : 1,
                                         "maxItems": type == "line" ? 2 : 512]
                required.append("points")
            } else {
                properties["x"] = integer(0, 575); properties["y"] = integer(0, 719)
                required += ["x", "y"]
            }
            if ["rectangle", "oval"].contains(type) {
                properties["width"] = integer(1, 576); properties["height"] = integer(1, 720)
                required += ["width", "height"]
            }
            if type == "text" {
                properties["text"] = ["type": "string", "minLength": 1, "maxLength": 1024,
                                       "description": "Mac Roman text, up to 20 lines of 80 characters. x,y is the top-left, black transparent bitmap text."]
                properties["font"] = ["type": "string", "enum": AIDrawingAction.fonts, "default": "Geneva"]
                properties["size"] = integer(9, 72); required.append("text")
            } else { properties["color"] = color }
            if !["fill", "text"].contains(type) { properties["line_width"] = integer(1, 16) }
            if ["rectangle", "oval", "polygon"].contains(type) { properties["filled"] = ["type": "boolean", "default": false] }
            actions.append(object(properties, required: required))
        }
        let empty = object([:], required: [])
        let path: [String: Any] = ["type": "string", "minLength": 1, "maxLength": 4096, "description": "Absolute local filesystem path."]
        let destination: [String: Any] = ["path": path, "overwrite": ["type": "boolean", "default": false]]
        return [
            ["name": "get_canvas", "description": "Read the complete page as PNG and document state, viewport, selection and 128K limits.",
             "inputSchema": empty, "annotations": ["readOnlyHint": true, "openWorldHint": false]],
            ["name": "draw_batch", "description": "Draw 1–128 actions in page pixels as one Undo step. Rectangles and ovals use an exact bounding box, width/height in pixels. All actions validate before drawing. Up to 2048 points total and a bounded raster workload. Stop in MacPaint preserves completed actions; Undo reverses the whole batch. 128K mode can refuse large batches and flood fills.",
             "inputSchema": object(["actions": ["type": "array", "minItems": 1, "maxItems": 128, "items": ["oneOf": actions]]], required: ["actions"]),
             "annotations": ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": false]],
            ["name": "undo", "description": "Use MacPaint's single-level Undo. A second undo toggles the same state, not an older history entry.",
             "inputSchema": empty, "annotations": ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": false]],
            ["name": "new_document", "description": "Create and activate a blank document, keeping the current document and its Undo in memory. At most 16 documents per app session.",
             "inputSchema": empty],
            ["name": "open_document", "description": "Open and activate a MacPaint file; keep the current document. An already open path switches to that document, preserving unsaved edits.",
             "inputSchema": object(["path": path], required: ["path"])],
            ["name": "save_document", "description": "Save the active document as MacPaint. Omit path to save back to its current file. A different existing destination needs overwrite:true. Updates title and dirty state.",
             "inputSchema": object(destination, required: [])],
            ["name": "save_as", "description": "Save the active document as MacPaint at an absolute path and adopt that filename. Existing destinations need overwrite:true.",
             "inputSchema": object(destination, required: ["path"])],
            ["name": "export_png", "description": "Export the full 576×720 page to PNG without changing the document filename, dirty state or Undo. Existing files need overwrite:true.",
             "inputSchema": object(destination, required: ["path"])],
            ["name": "list_documents", "description": "List open document IDs, titles, paths, dirty states and the active document. IDs last for this app session.",
             "inputSchema": empty, "annotations": ["readOnlyHint": true, "openWorldHint": false]],
            ["name": "switch_document", "description": "Activate a document by document_id from list_documents. Keeps pixels, patterns, Undo and viewport of both documents.",
             "inputSchema": object(["document_id": ["type": "string", "minLength": 1, "maxLength": 64]], required: ["document_id"])]
        ]
    }
    static func response(to request: [String: Any], path: String) -> [String: Any]? {
        guard let id = request["id"] else { return nil }
        func error(_ code: Int, _ message: String) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]] }
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else { return error(-32600, "Invalid JSON-RPC request.") }
        let params = request["params"] as? [String: Any] ?? [:]
        let result: [String: Any]
        switch method {
        case "initialize":
            let supported = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
            let requested = params["protocolVersion"] as? String ?? ""
            result = ["protocolVersion": supported.contains(requested) ? requested : "2025-11-25",
                  "capabilities": ["tools": ["listChanged": false]], "serverInfo": ["name": "MacPaint", "version": "0.2.0"], "instructions": instructions]
        case "ping": result = [:]
        case "tools/list": result = ["tools": tools]
        case "tools/call":
            guard let name = params["name"] as? String, tools.contains(where: { $0["name"] as? String == name }),
                  params["arguments"] == nil || params["arguments"] is [String: Any] else { return error(-32602, "Unknown tool or invalid arguments.") }
            do { result = try AITransport.call(["name": name, "arguments": params["arguments"] ?? [:]], path: path) }
            catch { result = AITransport.toolError(error.localizedDescription) }
        default: return error(-32601, "Method not found: \(method).")
        }
        return ["jsonrpc": "2.0", "id": id, "result": result]
    }
    static func run(path: String) -> Never {
        var buffer = Data()
        func write(_ response: [String: Any]) {
            guard var data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) else { return }
            data.append(10); FileHandle.standardOutput.write(data)
        }
        while true {
            let chunk = FileHandle.standardInput.availableData
            if chunk.isEmpty { exit(0) }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                guard line.count <= AITransport.maximumRequest else { fputs("MCP request too large.\n", stderr); exit(1) }
                do {
                    guard let request = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw AIControlError("Expected an object.") }
                    if let response = response(to: request, path: path) { write(response) }
                } catch { write(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Invalid JSON."]]) }
            }
            if buffer.count > AITransport.maximumRequest { fputs("MCP request too large.\n", stderr); exit(1) }
        }
    }
}
