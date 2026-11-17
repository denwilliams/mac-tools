import Foundation

/// Config at ~/.mactools/config.json
struct Config {
    var port: UInt16 = 7878
    var relayURL: String?
    var relayToken: String?
    var relayHeaders: [String: String] = [:]   // extra headers, e.g. Cloudflare Access service token

    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mactools")
    static var inbox: URL { dir.appendingPathComponent("inbox") }

    static func load() -> Config {
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        var c = Config()
        let f = dir.appendingPathComponent("config.json")
        if let d = try? Data(contentsOf: f),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            if let p = j["port"] as? Int { c.port = UInt16(p) }
            if let r = j["relay"] as? [String: Any] {
                c.relayURL = r["url"] as? String
                c.relayToken = r["token"] as? String
                c.relayHeaders = (r["headers"] as? [String: String]) ?? [:]
            }
        }
        return c
    }
}

/// Routes any inbound message (HTTP, file, relay) into the store.
@MainActor
enum Ingest {
    /// Accepts an object, an array of objects, or {"op":"clear"[, "id":...]}.
    static func apply(_ json: Any, to store: ActivityStore) -> [String] {
        if let arr = json as? [Any] { return arr.flatMap { apply($0, to: store) } }
        guard let d = json as? [String: Any] else { return [] }
        if d["op"] as? String == "clear" {
            if let id = d["id"] as? String { store.remove(id: id) } else { store.clear() }
            return []
        }
        return store.upsert(d).map { [$0] } ?? []
    }
}

/// Polls ~/.mactools/inbox for *.json files, ingests and deletes them.
@MainActor
final class InboxWatcher {
    private var timer: Timer?
    init(store: ActivityStore) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                let fm = FileManager.default
                guard let files = try? fm.contentsOfDirectory(at: Config.inbox, includingPropertiesForKeys: nil) else { return }
                for f in files where f.pathExtension == "json" {
                    if let d = try? Data(contentsOf: f), let j = try? JSONSerialization.jsonObject(with: d) {
                        _ = Ingest.apply(j, to: store)
                    }
                    try? fm.removeItem(at: f)
                }
            }
        }
    }
}

/// Subscribes to a remote Server-Sent-Events stream so cloud systems can push via a server you host.
final class RelayClient {
    private var task: Task<Void, Never>?

    @MainActor
    func start(url: String, token: String?, headers: [String: String] = [:], store: ActivityStore) {
        guard let u = URL(string: url) else { return }
        task = Task {
            var backoff: UInt64 = 1
            while !Task.isCancelled {
                var req = URLRequest(url: u)
                req.timeoutInterval = .infinity
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
                if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    backoff = 1
                    for try await line in bytes.lines where line.hasPrefix("data:") {
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if let d = payload.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) {
                            await MainActor.run { _ = Ingest.apply(j, to: store) }
                        }
                    }
                } catch {}
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                backoff = min(backoff * 2, 30)
            }
        }
    }
}
