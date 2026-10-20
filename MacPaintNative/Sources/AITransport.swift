import Foundation
import Darwin

/// Private, same-user Unix socket. One length-prefixed JSON request per connection.
enum AITransport {
    static var defaultPath: String { "/private/tmp/macpaint-mcp-\(getuid())/control.sock" }
    static let maximumRequest = 262_144
    static let maximumResponse = 2_097_152

    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { throw AIControlError("Socket path is too long.") }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: Array(path.utf8) + [0])
        }
        return address
    }
    static func configure(_ descriptor: Int32) {
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) & ~O_NONBLOCK)
        var noPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout.size(ofValue: noPipe)))
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    }
    private static func readBytes(_ count: Int, from descriptor: Int32) throws -> Data {
        var data = Data(count: count), offset = 0
        try data.withUnsafeMutableBytes { buffer in
            while offset < count {
                let received = Darwin.read(descriptor, buffer.baseAddress!.advanced(by: offset), count - offset)
                if received < 0 && errno == EINTR { continue }
                guard received > 0 else { throw AIControlError("MacPaint connection closed or timed out. Read get_canvas before retrying a drawing.") }
                offset += received
            }
        }
        return data
    }
    static func readMessage(from descriptor: Int32, maximum: Int) throws -> [String: Any] {
        let header = try readBytes(4, from: descriptor)
        let count = header.reduce(0) { ($0 << 8) | Int($1) }
        guard count > 0 && count <= maximum else { throw AIControlError("Message exceeds the size limit.") }
        guard let object = try JSONSerialization.jsonObject(with: readBytes(count, from: descriptor)) as? [String: Any] else {
            throw AIControlError("Expected a JSON object.")
        }
        return object
    }
    static func writeMessage(_ message: [String: Any], to descriptor: Int32) throws {
        let body = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        var size = UInt32(body.count).bigEndian
        var data = withUnsafeBytes(of: &size) { Data($0) }; data.append(body)
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let sent = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if sent < 0 && errno == EINTR { continue }
                guard sent > 0 else { throw AIControlError("Cannot write to the MacPaint connection.") }
                offset += sent
            }
        }
    }
    static func call(_ request: [String: Any], path: String) throws -> [String: Any] {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw AIControlError("Cannot create a local socket.") }
        defer { Darwin.close(descriptor) }
        configure(descriptor)
        var address = try address(path)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw AIControlError("Open MacPaint, enable About → Enable mods, then Mods → AI control. Only one MacPaint instance can accept AI control.") }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(descriptor, &uid, &gid) == 0, uid == getuid() else { throw AIControlError("MacPaint socket belongs to another user.") }
        try writeMessage(request, to: descriptor)
        return try readMessage(from: descriptor, maximum: maximumResponse)
    }
    static func toolError(_ message: String) -> [String: Any] {
        ["isError": true, "content": [["type": "text", "text": message]]]
    }
}

final class AIControlListener {
    private var source: DispatchSourceRead?
    private var lockDescriptor: Int32 = -1
    private let path: String
    private var clients = 0
    private let handler: ([String: Any], @escaping ([String: Any]) -> Void) -> Void

    init(path: String, handler: @escaping ([String: Any], @escaping ([String: Any]) -> Void) -> Void) throws {
        self.path = path; self.handler = handler
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw AIControlError("Cannot create the AI control directory.") }
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw AIControlError("AI control requires a private directory owned by this user.") }
        let lock = Darwin.open(path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw AIControlError("Cannot open the AI control lock.") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(lock); throw AIControlError("AI control is already enabled in another MacPaint instance.") }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { Darwin.close(lock); throw AIControlError("Cannot create AI control socket.") }
        do {
            var address = try AITransport.address(path)
            unlink(path)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard result == 0, chmod(path, 0o600) == 0, listen(descriptor, 8) == 0 else { throw AIControlError("Cannot listen for AI control.") }
            _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        } catch { Darwin.close(descriptor); Darwin.close(lock); unlink(path); throw error }
        lockDescriptor = lock
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptClient(descriptor) }
        source.setCancelHandler { Darwin.close(descriptor) }
        self.source = source; source.resume()
    }
    private func acceptClient(_ listener: Int32) {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        var uid: uid_t = 0, gid: gid_t = 0
        guard clients < 8, getpeereid(client, &uid, &gid) == 0, uid == getuid() else { Darwin.close(client); return }
        clients += 1
        AITransport.configure(client)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let request = try AITransport.readMessage(from: client, maximum: AITransport.maximumRequest)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { Darwin.close(client); return }
                    guard self.source != nil else { self.reply(AITransport.toolError("AI control is disabled."), to: client); return }
                    self.handler(request) { [weak self] response in self?.reply(response, to: client) }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    if let self { self.reply(AITransport.toolError(error.localizedDescription), to: client) }
                    else { Darwin.close(client) }
                }
            }
        }
    }
    private func reply(_ response: [String: Any], to client: Int32) {
        clients -= 1
        DispatchQueue.global(qos: .userInitiated).async {
            defer { Darwin.close(client) }
            try? AITransport.writeMessage(response, to: client)
        }
    }
    func stop() {
        guard let source else { return }
        self.source = nil; source.cancel()
        unlink(path)
        Darwin.close(lockDescriptor); lockDescriptor = -1
    }
    deinit { stop() }
}
