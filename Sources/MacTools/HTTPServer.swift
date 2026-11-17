import Foundation
import Network

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}
struct HTTPResponse {
    var status: Int = 200
    var json: Any = ["ok": true]
}

/// Minimal loopback-only HTTP/1.1 server (no deps).
final class HTTPServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "mactools.http")
    var handler: ((HTTPRequest, @escaping (HTTPResponse) -> Void) -> Void)?

    func start(port: UInt16) throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: queue)
        listener = l
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        read(c, buffer: Data())
    }

    private func read(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if buf.count > 1_000_000 || err != nil { c.cancel(); return }
            if let req = Self.parse(buf) {
                self.handler?(req) { resp in self.send(c, resp) }
            } else if done {
                c.cancel()
            } else {
                self.read(c, buffer: buf)
            }
        }
    }

    /// Returns nil until the full request (headers + Content-Length body) has arrived.
    private static func parse(_ buf: Data) -> HTTPRequest? {
        guard let sep = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: buf[..<sep.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let reqLine = lines.removeFirst().split(separator: " ")
        guard reqLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for l in lines {
            if let i = l.firstIndex(of: ":") {
                headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let len = Int(headers["content-length"] ?? "0") ?? 0
        let body = buf[sep.upperBound...]
        guard body.count >= len else { return nil }
        return HTTPRequest(method: String(reqLine[0]), path: String(reqLine[1]), headers: headers, body: Data(body.prefix(len)))
    }

    private func send(_ c: NWConnection, _ r: HTTPResponse) {
        let body = (try? JSONSerialization.data(withJSONObject: r.json)) ?? Data("{}".utf8)
        let reason = r.status == 200 ? "OK" : "Error"
        let head = "HTTP/1.1 \(r.status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }
}
