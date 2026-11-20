import SwiftUI
import AppKit

private struct HoverInfo: Equatable {
    var point: CGPoint
    var target: MapSelection
}

/// The interactive world map: animated replication links, role-coloured sites, zoom / pan / pinch,
/// hover tooltips, click-to-select, and role filters.
struct MapView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @StateCompat private var k: CGFloat = 1
    @StateCompat private var t: CGPoint = .zero
    @StateCompat private var dragOrigin: CGPoint?
    @StateCompat private var pinchStart: (k: CGFloat, t: CGPoint)?
    @StateCompat private var camTask: Task<Void, Never>?
    @StateCompat private var hover: HoverInfo?
    @StateCompat private var filter = RoleFilter()
    @StateCompat private var animate = true
    @StateCompat private var highlighted: Set<Int> = []

    private let nodeRadius: CGFloat = 7

    private var palette: Palette { Palette(dark: scheme == .dark) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let vp = Viewport(size: size, k: k, t: t)
            let layout = MapLayout(sites: store.sites, vp: vp)

            ZStack(alignment: .topLeading) {
                palette.ocean

                WorldLayer(size: size, k: k, t: t, palette: palette, highlighted: highlighted)
                    .equatable()

                TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: !animate)) { tl in
                    let time = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, _ in
                        drawOverlay(&ctx, layout: layout, time: time)
                    }
                }
                .allowsHitTesting(false)

                controls(size: size, layout: layout)
                tooltip(size: size)
                emptyState
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            .background(ScrollCatcher { event, loc in handleScroll(event, at: loc, size: size) })
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        if dragOrigin == nil { dragOrigin = t; camTask?.cancel() }
                        let o = dragOrigin ?? t
                        let c = Viewport.clamp(k: k, t: CGPoint(x: o.x + v.translation.width, y: o.y + v.translation.height), size: size)
                        t = c.t
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        if pinchStart == nil { pinchStart = (k, t); camTask?.cancel() }
                        guard let s = pinchStart else { return }
                        let nk = min(max(s.k * v.magnification, 1), 80)
                        let q = v.startLocation
                        let nt = CGPoint(x: q.x - (q.x - s.t.x) * (nk / s.k), y: q.y - (q.y - s.t.y) * (nk / s.k))
                        let c = Viewport.clamp(k: nk, t: nt, size: size)
                        k = c.k; t = c.t
                    }
                    .onEnded { _ in pinchStart = nil }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { v in
                        store.selection = layout.hit(at: v.location, links: store.links, filter: filter)
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    if let target = layout.hit(at: p, links: store.links, filter: filter) {
                        hover = HoverInfo(point: p, target: target)
                    } else {
                        hover = nil
                    }
                case .ended:
                    hover = nil
                }
            }
            .onChange(of: geo.size) { _, newSize in
                let c = Viewport.clamp(k: k, t: t, size: newSize)
                k = c.k; t = c.t
            }
            .onChange(of: store.selection) { _, new in
                guard let new = new else { return }
                focus(on: new, layout: layout, size: size)
            }
        }
        .onAppear { refreshHighlights() }
        .onChange(of: store.sites) { _, _ in refreshHighlights() }
        .environment(\.palette, palette)
    }

    private func refreshHighlights() {
        highlighted = World.shared.highlightedCountries(for: store.sites)
    }

    // MARK: Drawing

    private func relatedSets() -> (sites: Set<Int64>, links: Set<Int64>)? {
        guard let sel = store.selection else { return nil }
        switch sel {
        case .site(let id):
            var sites: Set<Int64> = [id]
            var links = Set<Int64>()
            for l in store.links where l.dcID == id || l.drID == id {
                links.insert(l.id); sites.insert(l.dcID); sites.insert(l.drID)
            }
            return (sites, links)
        case .link(let id):
            guard let l = store.link(id) else { return nil }
            return ([l.dcID, l.drID], [id])
        }
    }

    private func drawOverlay(_ ctx: inout GraphicsContext, layout: MapLayout, time: Double) {
        let p = palette
        let related = relatedSets()
        let hoveredLink: Int64? = { if case .link(let id)? = hover?.target { return id } else { return nil } }()
        let hoveredSite: Int64? = { if case .site(let id)? = hover?.target { return id } else { return nil } }()

        // Links
        if filter.linksVisible {
            for (idx, l) in store.links.enumerated() where !l.isSelf {
                guard let q = layout.curve(l) else { continue }
                let isRelated = related?.links.contains(l.id) ?? true
                let emphasised = (related != nil && isRelated) || hoveredLink == l.id
                let alpha: Double = isRelated ? (emphasised ? 1.0 : 0.85) : 0.12
                let color = p.link.opacity(alpha)

                var path = Path()
                path.move(to: q.p0)
                path.addQuadCurve(to: q.p1, control: q.c)
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: emphasised ? 3.2 : 2, lineCap: .butt, dash: [6, 6],
                                              dashPhase: animate ? CGFloat(-time * 12) : 0))

                // Direction arrow at the middle of the arc
                let mid = MapLayout.point(on: q, at: 0.5)
                let dx = q.p1.x - q.p0.x, dy = q.p1.y - q.p0.y
                let len = max(hypot(dx, dy), 0.0001)
                let d = CGPoint(x: dx / len, y: dy / len)
                let n = CGPoint(x: -d.y, y: d.x)
                var arrow = Path()
                arrow.move(to: CGPoint(x: mid.x + d.x * 5, y: mid.y + d.y * 5))
                arrow.addLine(to: CGPoint(x: mid.x - d.x * 4 + n.x * 4, y: mid.y - d.y * 4 + n.y * 4))
                arrow.addLine(to: CGPoint(x: mid.x - d.x * 4 - n.x * 4, y: mid.y - d.y * 4 - n.y * 4))
                arrow.closeSubpath()
                ctx.fill(arrow, with: .color(color))

                // Packet travelling from data center to DR site, with a short fading tail
                if animate && isRelated {
                    let u = (time / 3.2 + Double(idx) * 0.37).truncatingRemainder(dividingBy: 1)
                    for j in 0..<4 {
                        let uu = u - Double(j) * 0.016
                        if uu < 0 { continue }
                        let pt = MapLayout.point(on: q, at: CGFloat(uu))
                        let r = 3.4 - CGFloat(j) * 0.65
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(p.link.opacity(alpha * (1 - Double(j) * 0.25))))
                    }
                }
            }
        }

        // Sites
        let selfLinked = Set(store.links.filter { $0.isSelf }.map { $0.dcID })
        let visibleSites = layout.plotted.filter { filter.visible($0) }
        for s in visibleSites {
            guard let q = layout.pos(s.id) else { continue }
            let color = p.color(for: filter.role(s))
            let dim = related.map { !$0.sites.contains(s.id) } ?? false
            let a: Double = dim ? 0.12 : 1.0

            if animate && !dim {
                let phase = ((time + Double(s.id) * 0.37) / 2.4).truncatingRemainder(dividingBy: 1)
                let r = nodeRadius * CGFloat(0.8 + 1.8 * phase)
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(color.opacity(0.9 * (1 - phase))), lineWidth: 1.5)
            }
            if selfLinked.contains(s.id) {
                let r: CGFloat = 13
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(p.dr.opacity(a)),
                           style: StrokeStyle(lineWidth: 1.6, dash: [3, 3], dashPhase: animate ? CGFloat(time * 6) : 0))
            }
            let core = CGRect(x: q.x - nodeRadius, y: q.y - nodeRadius, width: 2 * nodeRadius, height: 2 * nodeRadius)
            ctx.fill(Path(ellipseIn: core), with: .color(color.opacity(a)))
            ctx.stroke(Path(ellipseIn: core), with: .color(p.ocean.opacity(a)), lineWidth: 2)

            if store.selection == .site(s.id) || hoveredSite == s.id {
                let r = nodeRadius + 4
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(p.text.opacity(0.85)), lineWidth: 1.5)
            }
        }

        // Labels, placed greedily so they never overlap
        let ordered = visibleSites.sorted { a, b in
            let pa = (store.selection == .site(a.id) ? 2 : 0) + (related?.sites.contains(a.id) == true ? 1 : 0)
            let pb = (store.selection == .site(b.id) ? 2 : 0) + (related?.sites.contains(b.id) == true ? 1 : 0)
            return pa != pb ? pa > pb : a.name < b.name
        }
        var placed: [CGRect] = []
        let halo: [(CGFloat, CGFloat)] = [(-1.5, 0), (1.5, 0), (0, -1.5), (0, 1.5), (-1, -1), (1, -1), (-1, 1), (1, 1)]
        for s in ordered {
            if let rel = related, !rel.sites.contains(s.id) { continue }
            guard let q = layout.pos(s.id) else { continue }
            let font = Font.system(size: 12, weight: .semibold)
            let main = ctx.resolve(Text(s.name).font(font).foregroundColor(p.text))
            let shadow = ctx.resolve(Text(s.name).font(font).foregroundColor(p.ocean))
            let sz = main.measure(in: CGSize(width: 400, height: 40))
            let rect = CGRect(x: q.x + 11, y: q.y - sz.height / 2, width: sz.width + 4, height: sz.height)
            if placed.contains(where: { $0.intersects(rect) }) { continue }
            placed.append(rect)
            let at = CGPoint(x: q.x + 12, y: q.y)
            for (ox, oy) in halo { ctx.draw(shadow, at: CGPoint(x: at.x + ox, y: at.y + oy), anchor: .leading) }
            ctx.draw(main, at: at, anchor: .leading)
        }
    }

    // MARK: Camera

    private func handleScroll(_ e: NSEvent, at loc: CGPoint, size: CGSize) {
        if e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.command) {
            // Trackpad two-finger scroll pans.
            camTask?.cancel()
            let c = Viewport.clamp(k: k, t: CGPoint(x: t.x + e.scrollingDeltaX, y: t.y + e.scrollingDeltaY), size: size)
            t = c.t
        } else {
            // Mouse wheel (or ⌘ + trackpad scroll) zooms around the cursor.
            let amount = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY * 0.01 : e.scrollingDeltaY * 0.06
            let factor = min(2, max(0.5, exp(amount)))
            camTask?.cancel()
            zoom(by: factor, around: loc, size: size)
        }
    }

    private func zoom(by f: CGFloat, around q: CGPoint, size: CGSize) {
        let nk = min(max(k * f, 1), 80)
        let nt = CGPoint(x: q.x - (q.x - t.x) * (nk / k), y: q.y - (q.y - t.y) * (nk / k))
        let c = Viewport.clamp(k: nk, t: nt, size: size)
        k = c.k; t = c.t
    }

    private func focus(on sel: MapSelection, layout: MapLayout, size: CGSize) {
        switch sel {
        case .site(let id): focus(ids: [id], layout: layout, size: size, maxK: 6)
        case .link(let id):
            if let l = store.link(id) { focus(ids: [l.dcID, l.drID], layout: layout, size: size, maxK: 30) }
        }
    }

    private func focus(ids: [Int64], layout: MapLayout, size: CGSize, maxK: CGFloat) {
        let pts = ids.compactMap { layout.basePos[$0] }
        guard !pts.isEmpty else { return }
        let x0 = pts.map { $0.x }.min() ?? 0, x1 = pts.map { $0.x }.max() ?? 0
        let y0 = pts.map { $0.y }.min() ?? 0, y1 = pts.map { $0.y }.max() ?? 0
        let span = max((x1 - x0) / size.width, (y1 - y0) / size.height, 0.03)
        let nk = max(1, min(maxK, 0.7 / span))
        animateCamera(toK: nk, center: CGPoint(x: (x0 + x1) / 2, y: (y0 + y1) / 2), size: size)
    }

    private func animateCamera(toK nk: CGFloat, center: CGPoint, size: CGSize) {
        let target = Viewport.clamp(k: nk, t: CGPoint(x: size.width / 2 - center.x * nk, y: size.height / 2 - center.y * nk), size: size)
        let startK = k
        let startC = CGPoint(x: (size.width / 2 - t.x) / k, y: (size.height / 2 - t.y) / k)
        let endC = CGPoint(x: (size.width / 2 - target.t.x) / target.k, y: (size.height / 2 - target.t.y) / target.k)

        camTask?.cancel()
        camTask = Task { @MainActor in
            let began = Date()
            while !Task.isCancelled {
                let p = min(1, Date().timeIntervalSince(began) / 0.65)
                let e = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2        // ease in-out
                let kk = CGFloat(exp(log(Double(startK)) + (log(Double(target.k)) - log(Double(startK))) * e))
                let cx = startC.x + (endC.x - startC.x) * CGFloat(e)
                let cy = startC.y + (endC.y - startC.y) * CGFloat(e)
                let c = Viewport.clamp(k: kk, t: CGPoint(x: size.width / 2 - cx * kk, y: size.height / 2 - cy * kk), size: size)
                k = c.k; t = c.t
                if p >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func currentCenter(size: CGSize) -> CGPoint {
        CGPoint(x: (size.width / 2 - t.x) / k, y: (size.height / 2 - t.y) / k)
    }

    // MARK: Overlays

    private func controls(size: CGSize, layout: MapLayout) -> some View {
        let p = palette
        return ZStack {
            VStack(spacing: 6) {
                MapButton(symbol: "plus", help: "Zoom in") {
                    animateCamera(toK: k * 1.7, center: currentCenter(size: size), size: size)
                }
                MapButton(symbol: "minus", help: "Zoom out") {
                    animateCamera(toK: k / 1.7, center: currentCenter(size: size), size: size)
                }
                MapButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Fit to sites") {
                    focus(ids: store.sites.filter { $0.hasCoordinates }.map { $0.id }, layout: layout, size: size, maxK: 12)
                }
                MapButton(symbol: "globe", help: "World view") {
                    animateCamera(toK: 1, center: CGPoint(x: size.width / 2, y: size.height / 2), size: size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(12)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $filter.dc) {
                    HStack(spacing: 7) { Circle().fill(p.dc).frame(width: 10, height: 10); Text("Data center") }
                }
                Toggle(isOn: $filter.dr) {
                    HStack(spacing: 7) { Circle().fill(p.dr).frame(width: 10, height: 10); Text("DR site") }
                }
                HStack(spacing: 7) {
                    Circle().fill(p.both).frame(width: 10, height: 10).padding(.leading, 20)
                    Text("Both roles").foregroundColor(p.muted)
                }
                HStack(spacing: 7) {
                    Rectangle().fill(p.link).frame(width: 18, height: 2).padding(.leading, 20)
                    Text("Replication (DC → DR)").foregroundColor(p.muted)
                }
                Divider()
                Toggle("Animate", isOn: $animate)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .foregroundColor(p.text)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(p.panel.opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.line, lineWidth: 1))
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(12)

            if let g = store.geocodeProgress {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Looking up coordinates… \(g.done)/\(g.total)  \(g.current)")
                        .font(.system(size: 12))
                        .foregroundColor(p.text)
                    Button("Cancel") { store.cancelGeocoding() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(p.panel.opacity(0.96)))
                .overlay(Capsule().stroke(p.line, lineWidth: 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(12)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func tooltip(size: CGSize) -> some View {
        if let h = hover {
            TooltipCard(target: h.target)
                .environment(\.palette, palette)
                .offset(x: min(h.point.x + 14, max(6, size.width - 280)), y: max(h.point.y - 10, 6))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.sites.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.questionmark").font(.system(size: 34)).foregroundColor(palette.muted)
                Text("No sites yet").font(.title3.weight(.semibold)).foregroundColor(palette.text)
                Text("Import your spreadsheet (⌘O) or add sites in the Sites tab.")
                    .foregroundColor(palette.muted)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 14).fill(palette.panel.opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.line, lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MapButton: View {
    @Environment(\.palette) private var p
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundColor(p.text)
                .background(RoundedRectangle(cornerRadius: 8).fill(p.panel.opacity(0.95)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct TooltipCard: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.palette) private var p
    let target: MapSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch target {
            case .site(let id):
                if let s = store.site(id) {
                    Text(s.name).font(.system(size: 13, weight: .bold))
                    Text(s.locationLabel).foregroundColor(p.muted)
                    Text(s.roleLabel)
                    Text("\(Fmt.coordShort(s.latitude)), \(Fmt.coordShort(s.longitude))  ·  \(s.geoStatus.label)")
                        .foregroundColor(p.muted)
                }
            case .link(let id):
                if let l = store.link(id), let a = store.site(l.dcID), let b = store.site(l.drID) {
                    Text("\(a.name) → \(b.name)").font(.system(size: 13, weight: .bold))
                    Text("\(a.locationLabel) → \(b.locationLabel)").foregroundColor(p.muted)
                    Text(Fmt.kmLabel(a, b))
                }
            }
        }
        .font(.system(size: 12))
        .foregroundColor(p.text)
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: 270, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(p.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }
}
