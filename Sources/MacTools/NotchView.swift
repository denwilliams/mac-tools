import SwiftUI
import AppKit

/// Per-display state: which screen, notch geometry, hover.
@MainActor
final class ScreenModel: ObservableObject {
    let screen: NSScreen
    @Published var hovering = false
    /// Distance from the screen's right edge to the left edge of the clock.
    @Published var rightInset: CGFloat = 130
    var islandSize: CGSize = .zero
    var expanded = false

    init(screen: NSScreen) { self.screen = screen }

    /// Room for the strip: from the clock leftwards to the notch (or 40% of the screen with no notch).
    var stripCapacity: CGFloat {
        let f = screen.frame
        if screen.safeAreaInsets.top > 0, let r = screen.auxiliaryTopRightArea {
            let notchRight = (r.minX >= f.minX && r.minX <= f.maxX) ? r.minX - f.minX : r.minX
            return max(16, f.width - rightInset - notchRight - 10)
        }
        return f.width * 0.4
    }

    /// Space the island leaves empty at its top (the physical notch, or a small gap).
    var topInset: CGFloat { screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 6 }
}

enum Layout {
    static let windowHeight: CGFloat = 420
    static let expandedWidth: CGFloat = 360
    static let rowHeight: CGFloat = 34
    static let stripHeight: CGFloat = 3
}

struct NotchView: View {
    @ObservedObject var store: ActivityStore
    @ObservedObject var model: ScreenModel
    let onState: (CGSize, Bool) -> Void

    var expanded: Bool { (model.hovering || store.peeking) && !store.activities.isEmpty }

    var size: CGSize {
        let rows = min(store.activities.count, 5)
        return CGSize(width: Layout.expandedWidth, height: model.topInset + CGFloat(rows) * Layout.rowHeight + 10)
    }

    var body: some View {
        let s = expanded ? size : CGSize(width: 220, height: 0)
        ZStack(alignment: .top) {
            StripView(activities: store.activities, capacity: model.stripCapacity)
                .padding(.trailing, model.rightInset)
                .animation(.easeInOut(duration: 0.3), value: model.rightInset)
                .opacity(store.activities.isEmpty ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: store.activities.isEmpty)
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18).fill(.black)
                expandedContent.opacity(expanded ? 1 : 0)
            }
            .frame(width: s.width, height: s.height, alignment: .top)
            .clipped()
            .opacity(expanded ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.activities.count)
        .onChange(of: expanded, initial: true) { _, e in onState(size, e) }
        .onChange(of: store.activities.count) { _, _ in onState(size, expanded) }
    }

    var expandedContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: model.topInset)
            VStack(spacing: 2) {
                ForEach(store.sorted.prefix(5)) { a in ActivityRow(a: a) { store.remove(id: a.id) } }
            }
            .padding(.horizontal, 14)
        }
        .frame(width: Layout.expandedWidth, alignment: .top)
    }
}

/// Thin full-width strip: one segment per activity, coloured by status, filled by progress.
struct StripView: View {
    let activities: [Activity]
    let capacity: CGFloat

    static let maxSegment: CGFloat = 44
    static let minSegment: CGFloat = 8
    static let gap: CGFloat = 2

    /// Fixed-size segments, shrunk to fit, and never wider in total than `capacity` (so they stay clear of the notch).
    var shown: [Activity] {
        let fit = max(1, Int((capacity + Self.gap) / (Self.minSegment + Self.gap)))
        if activities.count <= fit { return activities }
        let keep = Set(activities.sorted { $0.status.priority < $1.status.priority }.prefix(fit).map(\.id))
        return activities.filter { keep.contains($0.id) }
    }

    var body: some View {
        let list = shown
        let n = CGFloat(max(list.count, 1))
        let w = max(Self.minSegment, min(Self.maxSegment, (capacity - (n - 1) * Self.gap) / n))
        HStack(spacing: Self.gap) {
            // Right-to-left layout: first activity nearest the clock; newer ones stack leftwards.
            ForEach(list) { a in
                segmentView(a, w)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: list.map(\.id))
        .frame(height: Layout.stripHeight)
    }

    /// Pulse is driven by wall-clock time (no SwiftUI repeat animation), so it can't leak into other views.
    @ViewBuilder
    func segmentView(_ a: Activity, _ w: CGFloat) -> some View {
        if pulses(a) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                bar(a, w).opacity(pulseOpacity(a, ctx.date))
            }
        } else {
            bar(a, w)
        }
    }

    func bar(_ a: Activity, _ w: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(a.status.color.opacity(a.progress == nil ? 1 : 0.4))
            if let p = a.progress {
                Rectangle().fill(a.status.color).frame(width: w * max(0, min(1, p)))
            }
        }
        .frame(width: w)
        .environment(\.layoutDirection, .leftToRight)
    }

    func pulseOpacity(_ a: Activity, _ d: Date) -> Double {
        let period = a.status == .running ? 2.4 : 1.2
        return 0.725 + 0.275 * sin(d.timeIntervalSinceReferenceDate * 2 * .pi / period)
    }

    func pulses(_ a: Activity) -> Bool { a.status == .running || a.status == .waiting || a.status == .error }
}

struct ActivityRow: View {
    let a: Activity
    let dismiss: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: a.icon ?? a.status.defaultIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(a.status.color)
                .frame(width: 20, height: 20)
                .background(a.status.color.opacity(0.18), in: Circle())
            Text(a.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                .layoutPriority(1)
            if let sub = a.subtitle {
                Text(sub).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if hover {
                Button(action: dismiss) { Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)) }
                    .buttonStyle(.plain)
            } else if let s = a.source {
                Text(s).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 2)
        .frame(height: Layout.rowHeight - 2)
        .overlay(alignment: .bottomLeading) {
            if let p = a.progress {
                GeometryReader { g in
                    Capsule().fill(a.status.color).frame(width: g.size.width * max(0, min(1, p)), height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if let u = a.url, let url = URL(string: u) { NSWorkspace.shared.open(url) } }
    }
}
