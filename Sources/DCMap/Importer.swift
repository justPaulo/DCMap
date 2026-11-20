import Foundation

/// One line of the spreadsheet: DataCenter Name | Country | City | DR site | Country | City
/// Optional extra columns 7–10: DC latitude, DC longitude, DR latitude, DR longitude.
struct ImportRow {
    var dcName: String
    var dcCountry: String
    var dcCity: String
    var drName: String
    var drCountry: String
    var drCity: String
    var dcLat: Double?
    var dcLon: Double?
    var drLat: Double?
    var drLon: Double?
}

struct ImportPreview: Identifiable {
    let id = UUID()
    var fileName: String
    var rows: [ImportRow]
    var blankSkipped: Int
    var uniqueSites: Int
    var uniqueLinks: Int
    var duplicateRows: Int
}

enum ImportError: LocalizedError {
    case unsupported(String)
    case unreadable(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .unsupported(let ext): return "Unsupported file type “.\(ext)”. Use .xlsx or .csv."
        case .unreadable(let why): return "The file could not be read: \(why)"
        case .empty: return "The file contains no data rows."
        }
    }
}

enum Importer {

    // MARK: Entry points

    static func preview(url: URL) throws -> ImportPreview {
        let grid = try readGrid(url: url)
        let parsed = rows(from: grid)
        guard !parsed.rows.isEmpty else { throw ImportError.empty }

        var siteKeys = Set<String>()
        var linkKeys = Set<String>()
        var dupes = 0
        for r in parsed.rows {
            let a = key(r.dcName, r.dcCity), b = key(r.drName, r.drCity)
            siteKeys.insert(a); siteKeys.insert(b)
            if !linkKeys.insert(a + ">" + b).inserted { dupes += 1 }
        }
        return ImportPreview(fileName: url.lastPathComponent, rows: parsed.rows, blankSkipped: parsed.skipped,
                             uniqueSites: siteKeys.count, uniqueLinks: linkKeys.count, duplicateRows: dupes)
    }

    static func key(_ name: String, _ city: String) -> String {
        normalize(name) + "|" + normalize(city)
    }

    static func readGrid(url: URL) throws -> [[String]] {
        switch url.pathExtension.lowercased() {
        case "xlsx", "xlsm":
            return try readXLSX(url)
        case "csv", "tsv", "txt":
            return try readCSV(url)
        default:
            throw ImportError.unsupported(url.pathExtension)
        }
    }

    // MARK: Grid -> rows

    static func rows(from grid: [[String]]) -> (rows: [ImportRow], skipped: Int) {
        var start = 0
        if let first = grid.first, looksLikeHeader(first) { start = 1 }
        var out: [ImportRow] = []
        var skipped = 0
        for raw in grid.dropFirst(start) {
            var c = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            while c.count < 10 { c.append("") }
            if c[0..<6].allSatisfy({ $0.isEmpty }) { continue }          // blank line
            if c[0].isEmpty || c[3].isEmpty { skipped += 1; continue }   // needs both site names
            out.append(ImportRow(dcName: c[0], dcCountry: c[1], dcCity: c[2],
                                 drName: c[3], drCountry: c[4], drCity: c[5],
                                 dcLat: number(c[6]), dcLon: number(c[7]), drLat: number(c[8]), drLon: number(c[9])))
        }
        return (out, skipped)
    }

    private static func looksLikeHeader(_ row: [String]) -> Bool {
        let cells = row.map { $0.lowercased() }
        return cells.contains { $0 == "country" || $0 == "city" || $0.contains("datacenter") || $0.contains("data center") || $0.contains("dr site") }
    }

    private static func number(_ s: String) -> Double? {
        guard !s.isEmpty else { return nil }
        return Double(s.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: CSV

    private static func readCSV(_ url: URL) throws -> [[String]] {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ImportError.unreadable(error.localizedDescription) }
        var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? ""
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        guard !text.isEmpty else { throw ImportError.empty }

        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" && $0 != "\r\n" }
        let candidates: [Character] = [",", ";", "\t"]
        let delimiter = candidates.max { a, b in
            firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count
        } ?? ","

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var it = text.makeIterator()
        var pending: Character? = nil

        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return it.next()
        }

        while let ch = next() {
            if inQuotes {
                if ch == "\"" {
                    if let n = next() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == delimiter {
                row.append(field); field = ""
            } else if ch == "\n" || ch == "\r\n" || ch == "\r" {
                // Swift treats "\r\n" as a single Character, so all three forms land here.
                row.append(field); field = ""
                rows.append(row); row = []
            } else {
                field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    // MARK: XLSX (zip of XML parts, read through /usr/bin/unzip which ships with macOS)

    private static func unzipEntry(_ file: URL, _ entry: String) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", file.path, entry]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()   // read before waiting to avoid a full-pipe deadlock
        p.waitUntilExit()
        return p.terminationStatus == 0 && !data.isEmpty ? data : nil
    }

    private static func readXLSX(_ url: URL) throws -> [[String]] {
        var sheetPath = "xl/worksheets/sheet1.xml"
        if let wbData = unzipEntry(url, "xl/workbook.xml"),
           let relsData = unzipEntry(url, "xl/_rels/workbook.xml.rels") {
            let wb = WorkbookParser()
            let xp = XMLParser(data: wbData); xp.delegate = wb; xp.parse()
            let rels = RelsParser()
            let rp = XMLParser(data: relsData); rp.delegate = rels; rp.parse()
            if let rid = wb.firstSheetRID, let target = rels.targets[rid] {
                sheetPath = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            }
        }
        guard let sheetData = unzipEntry(url, sheetPath) else {
            throw ImportError.unreadable("not a valid .xlsx workbook (worksheet not found)")
        }

        var shared: [String] = []
        if let ssData = unzipEntry(url, "xl/sharedStrings.xml") {
            let sp = SharedStringsParser()
            let x = XMLParser(data: ssData); x.delegate = sp; x.parse()
            shared = sp.strings
        }

        let sheet = SheetParser(shared: shared)
        let x = XMLParser(data: sheetData); x.delegate = sheet
        guard x.parse() else { throw ImportError.unreadable(x.parserError?.localizedDescription ?? "invalid sheet XML") }
        return sheet.rows
    }
}

// MARK: - XML helpers

private func localName(_ n: String) -> String {
    if let i = n.lastIndex(of: ":") { return String(n[n.index(after: i)...]) }
    return n
}

private final class WorkbookParser: NSObject, XMLParserDelegate {
    var firstSheetRID: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard firstSheetRID == nil, localName(elementName) == "sheet" else { return }
        firstSheetRID = attributeDict["r:id"] ?? attributeDict.first { $0.key.hasSuffix(":id") }?.value
    }
}

private final class RelsParser: NSObject, XMLParserDelegate {
    var targets: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard localName(elementName) == "Relationship", let id = attributeDict["Id"], let t = attributeDict["Target"] else { return }
        targets[id] = t
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inSI = false
    private var inT = false
    private var phonetic = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "si": inSI = true; current = ""
        case "t": inT = true
        case "rPh": phonetic += 1
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inSI && inT && phonetic == 0 { current += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch localName(elementName) {
        case "t": inT = false
        case "rPh": phonetic -= 1
        case "si": strings.append(current); inSI = false
        default: break
        }
    }
}

private final class SheetParser: NSObject, XMLParserDelegate {
    let shared: [String]
    var rows: [[String]] = []

    private var rowCells: [Int: String] = [:]
    private var cellCol = 0
    private var cellType = ""
    private var cellValue = ""
    private var inlineText = ""
    private var inV = false
    private var inT = false
    private var inCell = false

    init(shared: [String]) { self.shared = shared }

    private func columnIndex(_ ref: String) -> Int {
        var n = 0
        for u in ref.unicodeScalars {
            guard u.value >= 65 && u.value <= 90 || u.value >= 97 && u.value <= 122 else { break }
            n = n * 26 + Int(u.value & 0x1F)
        }
        return max(0, n - 1)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "row":
            rowCells = [:]
            if let r = attributeDict["r"], let n = Int(r) {
                while rows.count < n - 1 { rows.append([]) }     // keep blank rows so numbering stays aligned
            }
        case "c":
            inCell = true
            cellCol = columnIndex(attributeDict["r"] ?? "")
            cellType = attributeDict["t"] ?? ""
            cellValue = ""
            inlineText = ""
        case "v": inV = true
        case "t": inT = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inCell && inV { cellValue += string }
        else if inCell && inT { inlineText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch localName(elementName) {
        case "v": inV = false
        case "t": inT = false
        case "c":
            inCell = false
            var text: String
            switch cellType {
            case "s":
                text = Int(cellValue.trimmingCharacters(in: .whitespaces)).flatMap { $0 < shared.count ? shared[$0] : nil } ?? ""
            case "inlineStr":
                text = inlineText
            case "str", "e", "b":
                text = cellValue
            default:
                text = cellValue
                if let d = Double(cellValue), d == d.rounded(), abs(d) < 1e15 { text = String(Int64(d)) }
            }
            rowCells[cellCol] = text
        case "row":
            let width = (rowCells.keys.max() ?? -1) + 1
            var arr = [String](repeating: "", count: width)
            for (i, v) in rowCells { arr[i] = v }
            rows.append(arr)
        default: break
        }
    }
}
