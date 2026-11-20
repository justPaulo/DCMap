import Foundation
import AppKit

/// Single source of truth for the UI. Owns the SQLite repository; every mutation writes to the
/// database first and then reloads, so what you see is always what is stored.
@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var sites: [Site] = []
    @Published private(set) var links: [Link] = []
    @Published var selection: MapSelection?
    @Published var importNotes: [String] = []
    @Published var geocodeProgress: GeocodeProgress?
    @Published var alert: AppAlert?
    @Published var pendingImport: ImportPreview?

    let dbURL: URL
    private let repo: Repository
    private var siteByID: [Int64: Site] = [:]

    private var geocodeQueue: [Int64] = []
    private var geocodeRunning = false
    private var geocodeTask: Task<Void, Never>?

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("DCMap", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("dcmap.sqlite")
        dbURL = url

        var startupAlert: AppAlert?
        if let r = try? Repository(path: url.path) {
            repo = r
        } else {
            startupAlert = AppAlert(title: "Database unavailable",
                                    message: "Could not open \(url.path). The app is running on a temporary in-memory database; changes will not be saved.")
            repo = try! Repository(path: ":memory:")
        }
        alert = startupAlert
        reload()
    }

    // MARK: Lookups

    func site(_ id: Int64) -> Site? { siteByID[id] }
    func link(_ id: Int64) -> Link? { links.first { $0.id == id } }

    /// Human-readable warnings shown in the "Data notes" card.
    var dataNotes: [String] {
        var notes = importNotes
        let unplotted = sites.filter { !$0.hasCoordinates }
        if !unplotted.isEmpty {
            let names = unplotted.prefix(4).map { "“\($0.name)”" }.joined(separator: ", ")
            notes.append("\(unplotted.count) site(s) have no coordinates and are not on the map: \(names)\(unplotted.count > 4 ? "…" : ""). Use “Look up coordinates” or edit them by hand.")
        }
        let grouped = Dictionary(grouping: sites.filter { $0.hasCoordinates }) { "\($0.latitude ?? 0),\($0.longitude ?? 0)" }
        for group in grouped.values where group.count > 1 {
            let names = group.map { "“\($0.name)”" }.joined(separator: " and ")
            notes.append("\(names) share the same coordinates (\(group[0].city)); they are drawn a few pixels apart so both stay visible. Zoom in to separate them.")
        }
        return notes
    }

    // MARK: Loading

    func reload() {
        do {
            var s = try repo.loadSites()
            let l = try repo.loadLinks()
            let dc = Set(l.map { $0.dcID })
            let dr = Set(l.map { $0.drID })
            for i in s.indices {
                s[i].asDC = dc.contains(s[i].id)
                s[i].asDR = dr.contains(s[i].id)
            }
            sites = s
            links = l
            siteByID = Dictionary(uniqueKeysWithValues: s.map { ($0.id, $0) })
            if let sel = selection {
                switch sel {
                case .site(let id): if siteByID[id] == nil { selection = nil }
                case .link(let id): if !l.contains(where: { $0.id == id }) { selection = nil }
                }
            }
        } catch {
            fail(error)
        }
    }

    func fail(_ error: Error, title: String = "Something went wrong") {
        alert = AppAlert(title: title, message: error.localizedDescription)
    }

    private func warn(_ title: String, _ message: String) {
        alert = AppAlert(title: title, message: message)
    }

    // MARK: Site CRUD

    @discardableResult
    func saveSite(_ d: SiteDraft) -> Bool {
        let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = d.country.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = d.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let latT = d.latText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lonT = d.lonText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { warn("Name required", "Give the site a name."); return false }
        guard !city.isEmpty else { warn("City required", "The city is used to look up the map position."); return false }
        if latT.isEmpty != lonT.isEmpty {
            warn("Coordinates incomplete", "Enter both latitude and longitude, or leave both empty to look them up online.")
            return false
        }

        var lat: Double?
        var lon: Double?
        if !latT.isEmpty {
            guard let la = Double(latT.replacingOccurrences(of: ",", with: ".")), (-90.0...90.0).contains(la),
                  let lo = Double(lonT.replacingOccurrences(of: ",", with: ".")), (-180.0...180.0).contains(lo) else {
                warn("Invalid coordinates", "Latitude must be between -90 and 90, and longitude between -180 and 180.")
                return false
            }
            lat = la; lon = lo
        }

        func same(_ a: Double?, _ b: Double?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case let (x?, y?): return abs(x - y) < 1e-6
            default: return false
            }
        }

        do {
            var needsLookup = false
            let savedID: Int64

            if let id = d.dbID, let old = siteByID[id] {
                var status = old.geoStatus
                let placeChanged = normalize(old.city) != normalize(city) || normalize(old.country) != normalize(country)
                if lat == nil {
                    status = .pending; needsLookup = true
                } else if !same(lat, old.latitude) || !same(lon, old.longitude) {
                    status = .manual                         // the user typed new coordinates
                } else if placeChanged {
                    lat = nil; lon = nil; status = .pending; needsLookup = true   // moved the site, so look it up again
                }
                try repo.updateSite(id: id, name: name, country: country, city: city, lat: lat, lon: lon, status: status)
                savedID = id
            } else {
                if lat == nil { needsLookup = true }
                savedID = try repo.insertSite(name: name, country: country, city: city, lat: lat, lon: lon,
                                              status: lat == nil ? .pending : .manual)
            }
            reload()
            if needsLookup { geocode(ids: [savedID]) }
            return true
        } catch {
            if error.localizedDescription.contains("UNIQUE") {
                warn("Site already exists", "A site named “\(name)” in “\(city)” is already in the database.")
            } else {
                fail(error)
            }
            return false
        }
    }

    func deleteSites(_ ids: Set<Int64>) {
        do {
            try repo.db.transaction { for id in ids { try repo.deleteSite(id: id) } }   // links cascade
            reload()
        } catch { fail(error) }
    }

    // MARK: Link CRUD

    @discardableResult
    func addLink(dc: Int64, dr: Int64) -> Bool {
        do {
            try repo.insertLink(dc: dc, dr: dr)
            reload()
            return true
        } catch {
            linkError(error)
            return false
        }
    }

    @discardableResult
    func updateLink(id: Int64, dc: Int64, dr: Int64) -> Bool {
        do {
            try repo.updateLink(id: id, dc: dc, dr: dr)
            reload()
            return true
        } catch {
            linkError(error)
            return false
        }
    }

    func deleteLinks(_ ids: Set<Int64>) {
        do {
            try repo.db.transaction { for id in ids { try repo.deleteLink(id: id) } }
            reload()
        } catch { fail(error) }
    }

    private func linkError(_ error: Error) {
        if error.localizedDescription.contains("UNIQUE") {
            warn("Link already exists", "That data center already replicates to that DR site.")
        } else {
            fail(error)
        }
    }

    func clearAll() {
        do {
            try repo.deleteAll()
            importNotes = []
            selection = nil
            reload()
        } catch { fail(error) }
    }

    // MARK: Import / export

    func beginImport(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingImport = try Importer.preview(url: url)
        } catch {
            fail(error, title: "Import failed")
        }
    }

    func commitImport(_ p: ImportPreview, replace: Bool, lookupOnline: Bool) {
        var newSites = 0
        var newLinks = 0
        var existingLinks = 0
        do {
            let repository = repo
            try repo.db.transaction {
                if replace { try repo.deleteAll() }

                func upsert(_ name: String, _ country: String, _ city: String, _ lat: Double?, _ lon: Double?) throws -> Int64 {
                    if let id = try repository.findSite(name: name, city: city) { return id }
                    newSites += 1
                    let hasCoords = lat != nil && lon != nil
                    return try repository.insertSite(name: name, country: country, city: city,
                                                     lat: hasCoords ? lat : nil, lon: hasCoords ? lon : nil,
                                                     status: hasCoords ? .manual : .pending)
                }

                for r in p.rows {
                    let a = try upsert(r.dcName, r.dcCountry, r.dcCity, r.dcLat, r.dcLon)
                    let b = try upsert(r.drName, r.drCountry, r.drCity, r.drLat, r.drLon)
                    if try repo.linkExists(dc: a, dr: b) { existingLinks += 1 } else {
                        try repo.insertLink(dc: a, dr: b)
                        newLinks += 1
                    }
                }
            }
        } catch {
            fail(error, title: "Import failed")
            return
        }

        var notes = ["Imported “\(p.fileName)”: \(newSites) new site(s), \(newLinks) new link(s)."]
        if existingLinks > 0 { notes.append("\(existingLinks) row(s) repeated a link that already existed and were ignored.") }
        if p.blankSkipped > 0 { notes.append("\(p.blankSkipped) row(s) without a data center or DR site name were skipped.") }
        importNotes = notes
        selection = nil
        reload()
        if lookupOnline { geocode() }
    }

    func csvText() -> String {
        func esc(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        func num(_ v: Double?) -> String { v.map { Fmt.coord($0) } ?? "" }
        var lines = ["DataCenter Name,Country,City,DR site,Country,City,DC Latitude,DC Longitude,DR Latitude,DR Longitude"]
        for l in links {
            guard let a = siteByID[l.dcID], let b = siteByID[l.drID] else { continue }
            let cols = [a.name, a.country, a.city, b.name, b.country, b.city, num(a.latitude), num(a.longitude), num(b.latitude), num(b.longitude)]
            lines.append(cols.map(esc).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func exportCSV(to url: URL) {
        do { try csvText().write(to: url, atomically: true, encoding: .utf8) }
        catch { fail(error, title: "Export failed") }
    }

    func exportHTML(to url: URL) {
        do {
            try HTMLExporter.write(snapshot: repo.exportSnapshot(), to: url)
        } catch {
            fail(error, title: "Map export failed")
        }
    }

    func revealDatabase() {
        NSWorkspace.shared.activateFileViewerSelecting([dbURL])
    }

    // MARK: Online coordinate lookup

    /// Queues sites for lookup. `ids == nil` means every site that has no coordinates yet (manual ones are left alone).
    func geocode(ids: [Int64]? = nil) {
        let targets: [Int64]
        if let ids = ids {
            targets = ids.filter { siteByID[$0] != nil }
        } else {
            targets = sites.filter { !$0.hasCoordinates && $0.geoStatus != .manual }.map { $0.id }
        }
        for t in targets where !geocodeQueue.contains(t) { geocodeQueue.append(t) }
        guard !geocodeQueue.isEmpty, !geocodeRunning else { return }
        geocodeRunning = true
        geocodeTask = Task { await self.processGeocodeQueue() }
    }

    func cancelGeocoding() {
        geocodeQueue.removeAll()
        geocodeTask?.cancel()
    }

    private func processGeocodeQueue() async {
        var done = 0
        var notFound: [String] = []
        var networkProblem: String?
        var consecutiveNetworkErrors = 0

        // Re-use coordinates already found for the same city so each city is looked up once.
        var cache: [String: GeoResult] = [:]
        let queued = Set(geocodeQueue)
        func cityKey(_ s: Site) -> String { normalize(s.city) + "|" + normalize(s.country) }
        for s in sites where s.geoStatus == .ok && !queued.contains(s.id) {
            if let la = s.latitude, let lo = s.longitude { cache[cityKey(s)] = GeoResult(latitude: la, longitude: lo, provider: "database") }
        }

        while !geocodeQueue.isEmpty && !Task.isCancelled {
            let id = geocodeQueue.removeFirst()
            guard let s = siteByID[id] else { continue }
            geocodeProgress = GeocodeProgress(done: done, total: done + geocodeQueue.count + 1, current: s.city.isEmpty ? s.name : s.city)

            var result = cache[cityKey(s)]
            if result == nil {
                do {
                    result = try await Geocoder.lookup(city: s.city, country: s.country, fallbackName: s.name)
                    consecutiveNetworkErrors = 0
                    if let r = result { cache[cityKey(s)] = r }
                } catch {
                    networkProblem = error.localizedDescription
                    consecutiveNetworkErrors += 1
                }
            }

            do {
                if let r = result {
                    try repo.setCoordinates(id: id, lat: r.latitude, lon: r.longitude, status: .ok)
                } else {
                    try repo.setCoordinates(id: id, lat: nil, lon: nil, status: .failed)
                    notFound.append("\(s.name) (\(s.locationLabel))")
                }
            } catch { fail(error) }
            done += 1
            reload()

            if consecutiveNetworkErrors >= 3 {          // offline: stop instead of timing out for every site
                geocodeQueue.removeAll()
                break
            }
        }

        geocodeRunning = false
        geocodeQueue.removeAll()
        geocodeProgress = nil

        if let problem = networkProblem, consecutiveNetworkErrors >= 3 {
            warn("Coordinates could not be looked up",
                 "The geocoding services could not be reached (\(problem)). Check your internet connection, then use “Look up missing coordinates”. You can also type coordinates in by hand.")
        } else if !notFound.isEmpty {
            warn("Some places were not found",
                 "No coordinates were found for: \(notFound.joined(separator: "; ")).\n\nEdit the site to correct the city/country spelling, or enter latitude and longitude manually.")
        }
    }
}
