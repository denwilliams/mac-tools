import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Only captures mouse events inside the visible island (when expanded).
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var islandSize: CGSize = .zero
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let x0 = (bounds.width - islandSize.width) / 2
        let y0 = isFlipped ? 0 : bounds.height - islandSize.height
        return NSRect(x: x0, y: y0, width: islandSize.width, height: islandSize.height).contains(p) ? super.hitTest(point) : nil
    }
}

/// One full-width, click-through window per display. Mouse position is polled so the strip never blocks the menu bar.
@MainActor
final class NotchWindowController {
    private struct Island { let panel: NotchPanel; let model: ScreenModel; let host: IslandHostingView<NotchView> }
    private var islands: [Island] = []
    private let store: ActivityStore
    private var timer: Timer?
    private var tickCount = 0
    private var dwell: [ObjectIdentifier: Int] = [:]   // ticks (50ms) mouse has been in the hover zone
    private var away: [ObjectIdentifier: Int] = [:]    // ticks mouse has been outside the island

    init(store: ActivityStore) {
        self.store = store
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func rebuild() {
        islands.forEach { $0.panel.orderOut(nil) }
        islands = NSScreen.screens.map { screen in
            let model = ScreenModel(screen: screen)
            let h = Layout.windowHeight
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - h, width: screen.frame.width, height: h)
            let p = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.isMovable = false
            p.ignoresMouseEvents = true

            var host: IslandHostingView<NotchView>!
            let view = NotchView(store: store, model: model) { [weak model] size, expanded in
                model?.islandSize = size
                model?.expanded = expanded
                host?.islandSize = size
                p.ignoresMouseEvents = !expanded
            }
            host = IslandHostingView(rootView: view)
            p.contentView = host
            p.setFrame(frame, display: true)
            p.orderFrontRegardless()
            return Island(panel: p, model: model, host: host)
        }
    }

    /// Left edge of the clock, found as the rightmost menu bar item window on each screen.
    private func updateClockInsets() {
        let fallback: CGFloat = 130
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let items: [CGRect] = list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 25,
                  let owner = w[kCGWindowOwnerName as String] as? String,
                  owner == "Control Center" || owner == "SystemUIServer",
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let wd = b["Width"], let h = b["Height"], wd > 0 else { return nil }
            return CGRect(x: x, y: y, width: wd, height: h)
        }
        for i in islands {
            let f = i.model.screen.frame
            let onScreen = items.filter { $0.minX >= f.minX && $0.maxX <= f.maxX + 1 }
            if let clock = onScreen.max(by: { $0.maxX < $1.maxX }) {
                let inset = f.maxX - clock.minX + 6
                if abs(inset - i.model.rightInset) > 0.5 { i.model.rightInset = inset }
            } else if i.model.rightInset != fallback { i.model.rightInset = fallback }
        }
    }

    private func tick() {
        tickCount += 1
        if tickCount % 40 == 1 { updateClockInsets() }   // every 2s
        let mouse = NSEvent.mouseLocation
        for i in islands {
            let id = ObjectIdentifier(i.model)
            let f = i.model.screen.frame
            let inZone = mouse.y >= f.maxY - 3 && mouse.x >= f.minX && mouse.x <= f.maxX && mouse.y <= f.maxY + 1
            let s = i.model.islandSize
            let island = NSRect(x: f.midX - s.width / 2 - 12, y: f.maxY - s.height - 12, width: s.width + 24, height: s.height + 12)
            let inIsland = i.model.expanded && island.contains(mouse)

            if i.model.hovering {
                away[id] = (inIsland || inZone) ? 0 : (away[id] ?? 0) + 1   // stay open while on the trigger edge too
                if (away[id] ?? 0) > 6 { i.model.hovering = false; away[id] = 0; dwell[id] = 0 }   // 300ms grace
            } else if !store.activities.isEmpty {
                // Hover trigger: dwell 250ms on the top edge, or move into an already-peeking island.
                dwell[id] = inZone ? (dwell[id] ?? 0) + 1 : 0
                if (dwell[id] ?? 0) >= 5 || inIsland { i.model.hovering = true; away[id] = 0 }
            }
        }
    }
}
