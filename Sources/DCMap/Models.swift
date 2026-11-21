import Foundation

/// How a site's coordinates were obtained.
enum GeoStatus: String, Comparable {
    case pending   // not looked up yet
    case ok        // found online
    case manual    // typed in / imported with the file
    case failed    // online lookup found nothing or failed

    static func < (lhs: GeoStatus, rhs: GeoStatus) -> Bool {
        lhs.label < rhs.label
    }

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .ok: return "Online"
        case .manual: return "Manual"
        case .failed: return "Not found"
        }
    }
}

/// A physical location: a data center, a DR site, or both.
struct Site: Identifiable, Hashable {
    var id: Int64
    var name: String
    var country: String
    var city: String
    var latitude: Double?
    var longitude: Double?
    var geoStatus: GeoStatus
    /// Derived from the links table.
    var asDC = false
    var asDR = false

    var hasCoordinates: Bool { latitude != nil && longitude != nil }

    var roleLabel: String {
        switch (asDC, asDR) {
        case (true, true): return "Data center + DR"
        case (true, false): return "Data center"
        case (false, true): return "DR site"
        default: return "Unlinked"
        }
    }

    var locationLabel: String {
        [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var latitudeSort: Double { latitude ?? .infinity }
    var longitudeSort: Double { longitude ?? .infinity }
}

/// A replication relationship: data center -> DR site.
struct Link: Identifiable, Hashable {
    var id: Int64
    var dcID: Int64
    var drID: Int64
    var isSelf: Bool { dcID == drID }
}

enum MapSelection: Hashable {
    case site(Int64)
    case link(Int64)
}

/// Editable copy of a site used by the editor sheet.
struct SiteDraft: Identifiable {
    let id = UUID()          // identity for sheet presentation
    var dbID: Int64?         // nil while creating a new site
    var name = ""
    var country = ""
    var city = ""
    var latText = ""
    var lonText = ""

    init() {}

    init(site: Site) {
        dbID = site.id
        name = site.name
        country = site.country
        city = site.city
        latText = site.latitude.map { Fmt.coord($0) } ?? ""
        lonText = site.longitude.map { Fmt.coord($0) } ?? ""
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

struct GeocodeProgress {
    var done: Int
    var total: Int
    var current: String
}

enum Fmt {
    static func coord(_ v: Double) -> String { String(format: "%.5f", v) }
    static func coordShort(_ v: Double?) -> String { v.map { String(format: "%.4f", $0) } ?? "—" }

    static func km(_ a: Site, _ b: Site) -> Double? {
        guard let la1 = a.latitude, let lo1 = a.longitude, let la2 = b.latitude, let lo2 = b.longitude else { return nil }
        let r = 6371.0
        let p1 = la1 * .pi / 180, p2 = la2 * .pi / 180
        let dp = (la2 - la1) * .pi / 180, dl = (lo2 - lo1) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    static func kmLabel(_ a: Site, _ b: Site) -> String {
        if a.id == b.id { return "local DR" }
        guard let d = km(a, b) else { return "—" }
        if d < 1 { return "same city" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: d)) ?? "\(Int(d))") + " km"
    }
}

func normalize(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
}
