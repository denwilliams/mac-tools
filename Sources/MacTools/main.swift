import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ActivityStore()
    var notch: NotchWindowController!
    var inbox: InboxWatcher!
    let server = HTTPServer()
    let relay = RelayClient()
    var statusItem: NSStatusItem!
    let config = Config.load()

    func applicationDidFinishLaunching(_ n: Notification) {
        notch = NotchWindowController(store: store)
        inbox = InboxWatcher(store: store)
        startServer()
        if let url = config.relayURL { relay.start(url: url, token: config.relayToken, headers: config.relayHeaders, store: store) }
        buildMenu()
    }

    func startServer() {
        server.handler = { [weak self] req, reply in
            DispatchQueue.main.async {
                guard let self else { return }
                reply(self.route(req))
            }
        }
        do { try server.start(port: config.port) } catch { NSLog("HTTP server failed: \(error)") }
    }

    func route(_ r: HTTPRequest) -> HTTPResponse {
        // CSRF guard: browsers can't send these without a preflight we never grant.
        if r.headers["origin"] != nil { return HTTPResponse(status: 403, json: ["error": "origin not allowed"]) }
        let path = r.path.split(separator: "?").first.map(String.init) ?? r.path
        switch (r.method, path) {
        case ("GET", "/health"):
            return HTTPResponse()
        case ("POST", "/v1/events"):
            guard (r.headers["content-type"] ?? "").contains("application/json"),
                  let j = try? JSONSerialization.jsonObject(with: r.body) else {
                return HTTPResponse(status: 400, json: ["error": "send application/json"])
            }
            let ids = Ingest.apply(j, to: store)
            return HTTPResponse(json: ["ok": true, "ids": ids])
        case ("POST", "/v1/clear"):
            store.clear(); return HTTPResponse()
        case ("DELETE", _) where path.hasPrefix("/v1/events/"):
            store.remove(id: String(path.dropFirst("/v1/events/".count))); return HTTPResponse()
        default:
            return HTTPResponse(status: 404, json: ["error": "not found"])
        }
    }

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "Mac Tools")
        let menu = NSMenu()
        menu.addItem(withTitle: "Listening on 127.0.0.1:\(config.port)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear all", action: #selector(clearAll), keyEquivalent: "k"); clear.target = self
        let test = NSMenuItem(title: "Send test event", action: #selector(sendTest), keyEquivalent: "t"); test.target = self
        let folder = NSMenuItem(title: "Open config folder", action: #selector(openFolder), keyEquivalent: ""); folder.target = self
        [clear, test, folder].forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func clearAll() { store.clear() }
    @objc func openFolder() { NSWorkspace.shared.open(Config.dir) }
    @objc func sendTest() {
        store.upsert(["id": "test", "source": "test", "title": "Hello from Mac Tools", "subtitle": "Island is working", "status": "running", "progress": 0.4])
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
