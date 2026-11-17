import Foundation
import SwiftUI

enum ActivityStatus: String {
    case info, running, waiting, success, warning, error

    var color: Color {
        switch self {
        case .info: return .blue
        case .running: return .orange
        case .waiting: return .yellow
        case .success: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }
    var defaultIcon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .running: return "gearshape.2.fill"
        case .waiting: return "hand.raised.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    /// Seconds before an activity disappears if the sender never updates/clears it.
    var defaultTTL: TimeInterval {
        switch self {
        case .running: return 30 * 60
        case .waiting: return 60 * 60
        case .error: return 300
        default: return 10
        }
    }
    var priority: Int {
        switch self {
        case .error: return 0
        case .waiting: return 1
        case .running: return 2
        case .warning: return 3
        case .success: return 4
        case .info: return 5
        }
    }
}

struct Activity: Identifiable, Equatable {
    var id: String
    var source: String?
    var title: String
    var subtitle: String?
    var status: ActivityStatus
    var icon: String?          // SF Symbol name
    var progress: Double?      // 0...1
    var url: String?           // opened on click
    var ttl: TimeInterval
    var quiet: Bool            // don't auto-expand the island
    var sound: Bool
    var updated: Date = Date()

    var expiresAt: Date { updated.addingTimeInterval(ttl) }

    /// Lenient parse from a JSON object. `existing` lets partial updates merge.
    static func parse(_ d: [String: Any], existing: Activity? = nil) -> Activity? {
        let id = (d["id"] as? String) ?? existing?.id ?? UUID().uuidString
        let title = (d["title"] as? String) ?? existing?.title
        guard let title else { return nil }
        let status = (d["status"] as? String).flatMap(ActivityStatus.init(rawValue:)) ?? existing?.status ?? .info
        let ttl = (d["ttl"] as? Double) ?? (d["ttl"] as? Int).map(Double.init) ?? status.defaultTTL
        return Activity(
            id: id,
            source: (d["source"] as? String) ?? existing?.source,
            title: title,
            subtitle: (d["subtitle"] as? String) ?? existing?.subtitle,
            status: status,
            icon: (d["icon"] as? String) ?? existing?.icon,
            progress: (d["progress"] as? Double) ?? (d["progress"] as? Int).map(Double.init) ?? existing?.progress,
            url: (d["url"] as? String) ?? existing?.url,
            ttl: ttl,
            quiet: (d["quiet"] as? Bool) ?? false,
            sound: (d["sound"] as? Bool) ?? false
        )
    }
}
