import Foundation
import AppKit

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var activities: [Activity] = []
    @Published private(set) var peeking = false


    private var peekTask: Task<Void, Never>?
    private var pruneTimer: Timer?

    init() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.prune() }
        }
    }

    var sorted: [Activity] {
        activities.sorted {
            $0.status.priority != $1.status.priority ? $0.status.priority < $1.status.priority : $0.updated > $1.updated
        }
    }

    /// Insert or merge by id. Returns the id.
    @discardableResult
    func upsert(_ dict: [String: Any]) -> String? {
        let id = dict["id"] as? String
        let existing = id.flatMap { id in activities.first { $0.id == id } }
        guard var a = Activity.parse(dict, existing: existing) else { return nil }
        a.updated = Date()
        let changed = existing == nil || existing?.status != a.status
        if let i = activities.firstIndex(where: { $0.id == a.id }) { activities[i] = a } else { activities.append(a) }
        if a.sound && changed { NSSound(named: "Pop")?.play() }
        if changed && !a.quiet { peek() }
        return a.id
    }

    func remove(id: String) { activities.removeAll { $0.id == id } }
    func clear() { activities.removeAll() }

    func peek(seconds: Double = 5) {
        peeking = true
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { self?.peeking = false }
        }
    }

    private func prune() {
        let now = Date()
        let kept = activities.filter { $0.expiresAt > now }
        if kept.count != activities.count { activities = kept }
    }
}
