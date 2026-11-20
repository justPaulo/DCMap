import Foundation

/// All SQL lives here. Tables:
///   sites(id, name, country, city, latitude, longitude, geo_status, ...)  unique on (name, city) case-insensitively
///   links(id, dc_site_id -> sites, dr_site_id -> sites)                  unique pair, cascades on site delete
final class Repository {
    let db: SQLiteDB

    struct ExportSite: Encodable {
        let id: Int64
        let name: String
        let country: String
        let city: String
        let latitude: Double?
        let longitude: Double?
        let geoStatus: String
        let createdAt: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case id, name, country, city, latitude, longitude
            case geoStatus = "geo_status"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    struct ExportLink: Encodable {
        let id: Int64
        let dcSiteID: Int64
        let drSiteID: Int64
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case dcSiteID = "dc_site_id"
            case drSiteID = "dr_site_id"
            case createdAt = "created_at"
        }
    }

    struct ExportSnapshot: Encodable {
        let generatedAt: String
        let sites: [ExportSite]
        let links: [ExportLink]

        enum CodingKeys: String, CodingKey {
            case generatedAt = "generated_at"
            case sites, links
        }
    }

    init(path: String) throws {
        db = try SQLiteDB(path: path)
        try migrate()
    }

    private func migrate() throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS sites (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            name        TEXT NOT NULL,
            country     TEXT NOT NULL DEFAULT '',
            city        TEXT NOT NULL DEFAULT '',
            latitude    REAL,
            longitude   REAL,
            geo_status  TEXT NOT NULL DEFAULT 'pending',
            created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_sites_name_city ON sites(name COLLATE NOCASE, city COLLATE NOCASE);
        CREATE TABLE IF NOT EXISTS links (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            dc_site_id  INTEGER NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
            dr_site_id  INTEGER NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
            created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE (dc_site_id, dr_site_id)
        );
        """)
    }

    // MARK: Read

    func loadSites() throws -> [Site] {
        let rows = try db.query("SELECT id, name, country, city, latitude, longitude, geo_status FROM sites ORDER BY name COLLATE NOCASE, city COLLATE NOCASE")
        return rows.map { r in
            Site(id: r[0].int64 ?? 0,
                 name: r[1].string,
                 country: r[2].string,
                 city: r[3].string,
                 latitude: r[4].doubleValue,
                 longitude: r[5].doubleValue,
                 geoStatus: GeoStatus(rawValue: r[6].string) ?? .pending)
        }
    }

    func loadLinks() throws -> [Link] {
        let rows = try db.query("SELECT id, dc_site_id, dr_site_id FROM links ORDER BY id")
        return rows.map { Link(id: $0[0].int64 ?? 0, dcID: $0[1].int64 ?? 0, drID: $0[2].int64 ?? 0) }
    }

    func exportSnapshot() throws -> ExportSnapshot {
        try db.transaction {
            let siteRows = try db.query("""
                SELECT id, name, country, city, latitude, longitude, geo_status, created_at, updated_at
                FROM sites ORDER BY id
                """)
            let sites = try siteRows.map { row -> ExportSite in
                guard row.count == 9,
                      case let .int(id) = row[0],
                      case let .text(name) = row[1],
                      case let .text(country) = row[2],
                      case let .text(city) = row[3],
                      case let .text(geoStatus) = row[6],
                      case let .text(createdAt) = row[7],
                      case let .text(updatedAt) = row[8] else {
                    throw DBError(message: "Unexpected site data while exporting the map")
                }

                func coordinate(_ value: DBValue) throws -> Double? {
                    switch value {
                    case .null: return nil
                    case .double(let number): return number
                    case .int(let number): return Double(number)
                    case .text: throw DBError(message: "Unexpected coordinate value while exporting the map")
                    }
                }

                return ExportSite(
                    id: id,
                    name: name,
                    country: country,
                    city: city,
                    latitude: try coordinate(row[4]),
                    longitude: try coordinate(row[5]),
                    geoStatus: geoStatus,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            }

            let linkRows = try db.query("SELECT id, dc_site_id, dr_site_id, created_at FROM links ORDER BY id")
            let links = try linkRows.map { row -> ExportLink in
                guard row.count == 4,
                      case let .int(id) = row[0],
                      case let .int(dcSiteID) = row[1],
                      case let .int(drSiteID) = row[2],
                      case let .text(createdAt) = row[3] else {
                    throw DBError(message: "Unexpected link data while exporting the map")
                }
                return ExportLink(id: id, dcSiteID: dcSiteID, drSiteID: drSiteID, createdAt: createdAt)
            }

            return ExportSnapshot(
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                sites: sites,
                links: links
            )
        }
    }

    func findSite(name: String, city: String) throws -> Int64? {
        let rows = try db.query("SELECT id FROM sites WHERE name = ? COLLATE NOCASE AND city = ? COLLATE NOCASE", [.text(name), .text(city)])
        return rows.first?[0].int64
    }

    func linkExists(dc: Int64, dr: Int64) throws -> Bool {
        !(try db.query("SELECT id FROM links WHERE dc_site_id = ? AND dr_site_id = ?", [.int(dc), .int(dr)]).isEmpty)
    }

    // MARK: Sites

    @discardableResult
    func insertSite(name: String, country: String, city: String, lat: Double?, lon: Double?, status: GeoStatus) throws -> Int64 {
        try db.run("INSERT INTO sites (name, country, city, latitude, longitude, geo_status) VALUES (?, ?, ?, ?, ?, ?)",
                   [.text(name), .text(country), .text(city), .optional(lat), .optional(lon), .text(status.rawValue)])
        return db.lastInsertID
    }

    func updateSite(id: Int64, name: String, country: String, city: String, lat: Double?, lon: Double?, status: GeoStatus) throws {
        try db.run("UPDATE sites SET name = ?, country = ?, city = ?, latitude = ?, longitude = ?, geo_status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                   [.text(name), .text(country), .text(city), .optional(lat), .optional(lon), .text(status.rawValue), .int(id)])
    }

    func setCoordinates(id: Int64, lat: Double?, lon: Double?, status: GeoStatus) throws {
        try db.run("UPDATE sites SET latitude = ?, longitude = ?, geo_status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                   [.optional(lat), .optional(lon), .text(status.rawValue), .int(id)])
    }

    func deleteSite(id: Int64) throws {
        try db.run("DELETE FROM sites WHERE id = ?", [.int(id)])
    }

    // MARK: Links

    @discardableResult
    func insertLink(dc: Int64, dr: Int64) throws -> Int64 {
        try db.run("INSERT INTO links (dc_site_id, dr_site_id) VALUES (?, ?)", [.int(dc), .int(dr)])
        return db.lastInsertID
    }

    func updateLink(id: Int64, dc: Int64, dr: Int64) throws {
        try db.run("UPDATE links SET dc_site_id = ?, dr_site_id = ? WHERE id = ?", [.int(dc), .int(dr), .int(id)])
    }

    func deleteLink(id: Int64) throws {
        try db.run("DELETE FROM links WHERE id = ?", [.int(id)])
    }

    func deleteAll() throws {
        try db.run("DELETE FROM links")
        try db.run("DELETE FROM sites")
    }
}
