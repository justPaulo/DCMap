import SwiftUI
import AppKit

/// Which roles are currently shown (the Data center / DR site tick boxes).
/// A site that holds both roles stays visible while either box is ticked and changes colour to the role still shown.
/// A replication link needs both ends, so it is only drawn while both boxes are ticked.
struct RoleFilter: Equatable {
    var dc = true
    var dr = true

    func visible(_ s: Site) -> Bool {
        (s.asDC && dc) || (s.asDR && dr) || (!s.asDC && !s.asDR)
    }

    func role(_ s: Site) -> SiteRole {
        let d = s.asDC && dc
        let r = s.asDR && dr
        if d && r { return .both }
        if d { return .dc }
        if r { return .dr }
        return .none
    }

    var linksVisible: Bool { dc && dr }
}

/// Screen positions for sites and links at the current zoom. Used for both drawing and hit-testing,
/// so the two can never disagree.
struct MapLayout {
    let vp: Viewport
    let plotted: [Site]
    let basePos: [Int64: CGPoint]

    init(sites: [Site], vp: Viewport) {
        self.vp = vp
        let plotted = sites.filter { $0.hasCoordinates }
        var base: [Int64: CGPoint] = [:]
        var groups: [String: [Int64]] = [:]
        for s in plotted {
            guard let lat = s.latitude, let lon = s.longitude else { continue }
            base[s.id] = vp.base(lon: lon, lat: lat)
            groups["\(lat),\(lon)", default: []].append(s.id)
        }
        // Sites that share identical coordinates are fanned out a few pixels so each stays visible.
        for ids in groups.values where ids.count > 1 {
            for (i, id) in ids.enumerated() {
                let a = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(ids.count)
                if let p = base[id] {
                    base[id] = CGPoint(x: p.x + CGFloat(cos(a)) * 5, y: p.y + CGFloat(sin(a)) * 5)
                }
            }
        }
        self.plotted = plotted
        self.basePos = base
    }

    func pos(_ id: Int64) -> CGPoint? {
        basePos[id].map { vp.screen($0) }
    }

    /// Quadratic curve in screen coordinates, bulging to the left of the direction of travel,
    /// so a pair of opposite links (A→B and B→A) separates into two arcs.
    func curve(_ l: Link) -> (p0: CGPoint, c: CGPoint, p1: CGPoint)? {
        guard let a = basePos[l.dcID], let b = basePos[l.drID] else { return nil }
        let dx = b.x - a.x, dy = b.y - a.y
        let control = CGPoint(x: (a.x + b.x) / 2 - dy * 0.22, y: (a.y + b.y) / 2 + dx * 0.22)
        return (vp.screen(a), vp.screen(control), vp.screen(b))
    }

    static func point(on q: (p0: CGPoint, c: CGPoint, p1: CGPoint), at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * q.p0.x + 2 * u * t * q.c.x + t * t * q.p1.x,
                       y: u * u * q.p0.y + 2 * u * t * q.c.y + t * t * q.p1.y)
    }

    func hit(at p: CGPoint, links: [Link], filter: RoleFilter) -> MapSelection? {
        var bestSite: (id: Int64, d: CGFloat)?
        for s in plotted where filter.visible(s) {
            guard let q = pos(s.id) else { continue }
            let d = hypot(q.x - p.x, q.y - p.y)
            if d <= 11 && d < (bestSite?.d ?? .infinity) { bestSite = (s.id, d) }
        }
        if let b = bestSite { return .site(b.id) }

        guard filter.linksVisible else { return nil }
        var bestLink: (id: Int64, d: CGFloat)?
        for l in links where !l.isSelf {
            guard let q = curve(l) else { continue }
            var prev = q.p0
            for i in 1...24 {
                let cur = MapLayout.point(on: q, at: CGFloat(i) / 24)
                let d = MapLayout.distance(from: p, toSegment: prev, cur)
                if d <= 7 && d < (bestLink?.d ?? .infinity) { bestLink = (l.id, d) }
                prev = cur
            }
        }
        return bestLink.map { .link($0.id) }
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

/// Country fills, graticule and borders. Equatable so SwiftUI redraws it only when the camera,
/// theme or highlighted countries change — not on every hover or animation frame.
struct WorldLayer: View, Equatable {
    let size: CGSize
    let k: CGFloat
    let t: CGPoint
    let palette: Palette
    let highlighted: Set<Int>

    var body: some View {
        Canvas { ctx, _ in
            let world = World.shared
            let vp = Viewport(size: size, k: k, t: t)
            var c = ctx
            c.translateBy(x: t.x, y: t.y)
            c.scaleBy(x: k, y: k)
            c.translateBy(x: vp.origin.x, y: vp.origin.y)
            c.scaleBy(x: vp.baseScale, y: vp.baseScale)
            let lw = 1 / (k * vp.baseScale)    // keeps strokes a constant width on screen

            c.stroke(world.graticule, with: .color(palette.graticule), lineWidth: 0.6 * lw)
            c.fill(world.allLand, with: .color(palette.land))
            if !highlighted.isEmpty {
                var hp = Path()
                for i in highlighted where i < world.shapes.count { hp.addPath(world.shapes[i].path) }
                c.fill(hp, with: .color(palette.hasSite))
            }
            c.stroke(world.allLand, with: .color(palette.landStroke), lineWidth: 0.6 * lw)
        }
    }
}

/// Invisible NSView that turns mouse-wheel and trackpad scroll events over the map into callbacks.
/// (SwiftUI has no scroll-wheel gesture on macOS.)
struct ScrollCatcher: NSViewRepresentable {
    var handler: (NSEvent, CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.handler = handler
        return v
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.handler = handler
    }

    final class CatcherView: NSView {
        var handler: ((NSEvent, CGPoint) -> Void)?
        private var monitor: Any?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // never steal clicks

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self = self, event.window === self.window else { return event }
                let p = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(p) else { return event }
                self.handler?(event, p)
                return nil
            }
        }

        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }
    }
}
