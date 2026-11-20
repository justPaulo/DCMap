import SwiftUI

/// Natural Earth I projection (same one the HTML version used through d3.geoNaturalEarth1).
/// Output is y-down so it can be used directly for drawing.
enum NaturalEarth {
    static func project(lon: Double, lat: Double) -> CGPoint {
        let l = lon * .pi / 180
        let p = lat * .pi / 180
        let p2 = p * p
        let p4 = p2 * p2
        let x = l * (0.8707 - 0.131979 * p2 + p4 * (-0.013791 + p4 * (0.003971 * p2 - 0.001529 * p4)))
        let y = p * (1.007226 + p2 * (0.015085 + p4 * (-0.044475 + 0.028874 * p2 - 0.005916 * p4)))
        return CGPoint(x: x, y: -y)
    }

    /// Bounding box of the whole projected sphere.
    static let bounds: CGRect = {
        let left = project(lon: -180, lat: 0).x
        let right = project(lon: 180, lat: 0).x
        let top = project(lon: 0, lat: 90).y
        let bottom = project(lon: 0, lat: -90).y
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }()
}

/// Country outlines, projected once and shared by every map view.
final class World {
    struct Shape {
        let name: String
        let path: Path                 // projected coordinates
        let polygons: [[[Double]]]     // lon/lat rings, kept for point-in-polygon tests
        let minLon: Double, maxLon: Double, minLat: Double, maxLat: Double
    }

    private struct Raw: Decodable {
        let n: String
        let p: [[[Double]]]
    }

    static let shared = World()

    let shapes: [Shape]
    let allLand: Path
    let sphere: Path
    let graticule: Path
    private let nameIndex: [String: Int]

    private init() {
        var shapes: [Shape] = []
        let raws = (try? JSONDecoder().decode([Raw].self, from: Data(WorldData.json.utf8))) ?? []
        var all = Path()
        for raw in raws {
            var path = Path()
            var minLon = 999.0, maxLon = -999.0, minLat = 999.0, maxLat = -999.0
            for polygon in raw.p {
                for ring in polygon {
                    var first = true
                    var i = 0
                    while i + 1 < ring.count {
                        let lon = ring[i], lat = ring[i + 1]
                        let pt = NaturalEarth.project(lon: lon, lat: lat)
                        if first { path.move(to: pt); first = false } else { path.addLine(to: pt) }
                        minLon = min(minLon, lon); maxLon = max(maxLon, lon)
                        minLat = min(minLat, lat); maxLat = max(maxLat, lat)
                        i += 2
                    }
                    path.closeSubpath()
                }
            }
            all.addPath(path)
            shapes.append(Shape(name: raw.n, path: path, polygons: raw.p,
                                minLon: minLon, maxLon: maxLon, minLat: minLat, maxLat: maxLat))
        }
        self.shapes = shapes
        self.allLand = all

        var index: [String: Int] = [:]
        for (i, s) in shapes.enumerated() { index[normalize(s.name)] = i }
        self.nameIndex = index

        // Sphere outline
        var sp = Path()
        var started = false
        for lat in stride(from: -90.0, through: 90.0, by: 2.0) {
            let pt = NaturalEarth.project(lon: -180, lat: lat)
            if started { sp.addLine(to: pt) } else { sp.move(to: pt); started = true }
        }
        for lat in stride(from: 90.0, through: -90.0, by: -2.0) {
            sp.addLine(to: NaturalEarth.project(lon: 180, lat: lat))
        }
        sp.closeSubpath()
        self.sphere = sp

        // Graticule every 30 degrees
        var gr = Path()
        for lon in stride(from: -180.0, through: 180.0, by: 30.0) {
            var first = true
            for lat in stride(from: -90.0, through: 90.0, by: 3.0) {
                let pt = NaturalEarth.project(lon: lon, lat: lat)
                if first { gr.move(to: pt); first = false } else { gr.addLine(to: pt) }
            }
        }
        for lat in stride(from: -60.0, through: 60.0, by: 30.0) {
            var first = true
            for lon in stride(from: -180.0, through: 180.0, by: 3.0) {
                let pt = NaturalEarth.project(lon: lon, lat: lat)
                if first { gr.move(to: pt); first = false } else { gr.addLine(to: pt) }
            }
        }
        self.graticule = gr
    }

    // MARK: Country matching

    private static let aliases: [String: String] = [
        "united states": "United States of America", "usa": "United States of America", "us": "United States of America",
        "u.s.": "United States of America", "u.s.a.": "United States of America", "america": "United States of America",
        "uk": "United Kingdom", "great britain": "United Kingdom", "england": "United Kingdom", "scotland": "United Kingdom", "wales": "United Kingdom",
        "czech republic": "Czechia", "holland": "Netherlands", "the netherlands": "Netherlands",
        "russian federation": "Russia", "korea, republic of": "South Korea", "republic of korea": "South Korea", "korea": "South Korea",
        "uae": "United Arab Emirates", "turkiye": "Turkey",
        "democratic republic of the congo": "Dem. Rep. Congo", "drc": "Dem. Rep. Congo",
        "ivory coast": "Côte d'Ivoire", "bosnia and herzegovina": "Bosnia and Herz.",
        "dominican republic": "Dominican Rep.", "central african republic": "Central African Rep.",
        "south sudan": "S. Sudan", "equatorial guinea": "Eq. Guinea", "swaziland": "eSwatini",
        "macedonia": "North Macedonia", "vietnam": "Vietnam", "viet nam": "Vietnam"
    ]

    func index(forCountryName name: String) -> Int? {
        let key = normalize(name)
        if key.isEmpty { return nil }
        if let i = nameIndex[key] { return i }
        if let alias = World.aliases[key], let i = nameIndex[normalize(alias)] { return i }
        return nil
    }

    /// Country polygon containing a coordinate (50 m data, so tiny city-states may be missed).
    func index(containingLon lon: Double, lat: Double) -> Int? {
        for (i, s) in shapes.enumerated() {
            if lon < s.minLon || lon > s.maxLon || lat < s.minLat || lat > s.maxLat { continue }
            for polygon in s.polygons {
                guard let outer = polygon.first, World.ring(outer, contains: lon, lat) else { continue }
                if polygon.dropFirst().contains(where: { World.ring($0, contains: lon, lat) }) { continue }
                return i
            }
        }
        return nil
    }

    private static func ring(_ r: [Double], contains x: Double, _ y: Double) -> Bool {
        var inside = false
        let n = r.count / 2
        guard n >= 3 else { return false }
        var j = n - 1
        for i in 0..<n {
            let xi = r[2 * i], yi = r[2 * i + 1]
            let xj = r[2 * j], yj = r[2 * j + 1]
            if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Countries that contain at least one site (by name or by position).
    func highlightedCountries(for sites: [Site]) -> Set<Int> {
        var out = Set<Int>()
        for s in sites {
            if let i = index(forCountryName: s.country) { out.insert(i) }
            if let la = s.latitude, let lo = s.longitude, let i = index(containingLon: lo, lat: la) { out.insert(i) }
        }
        return out
    }
}

/// Maps projected coordinates to the screen for the current zoom (k) and pan (t).
/// `base` is the un-zoomed fit of the whole world into the view; `screen` applies zoom and pan on top.
struct Viewport: Equatable {
    var size: CGSize
    var k: CGFloat
    var t: CGPoint

    private var fit: (scale: CGFloat, origin: CGPoint) {
        let b = NaturalEarth.bounds
        let inset: CGFloat = 8
        let sx = max(1, size.width - 2 * inset) / b.width
        let sy = max(1, size.height - 2 * inset) / b.height
        let s = min(sx, sy)
        return (s, CGPoint(x: (size.width - b.width * s) / 2 - b.minX * s,
                           y: (size.height - b.height * s) / 2 - b.minY * s))
    }

    var baseScale: CGFloat { fit.scale }
    var origin: CGPoint { fit.origin }

    func base(lon: Double, lat: Double) -> CGPoint {
        let p = NaturalEarth.project(lon: lon, lat: lat)
        let f = fit
        return CGPoint(x: p.x * f.scale + f.origin.x, y: p.y * f.scale + f.origin.y)
    }

    func screen(_ b: CGPoint) -> CGPoint {
        CGPoint(x: b.x * k + t.x, y: b.y * k + t.y)
    }

    /// Keeps the map covering the view (same behaviour as d3's translateExtent).
    static func clamp(k: CGFloat, t: CGPoint, size: CGSize) -> (k: CGFloat, t: CGPoint) {
        let kk = min(max(k, 1), 80)
        let tx = min(0, max(size.width - size.width * kk, t.x))
        let ty = min(0, max(size.height - size.height * kk, t.y))
        return (kk, CGPoint(x: tx, y: ty))
    }
}
