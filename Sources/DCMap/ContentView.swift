import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum AppTab: String, CaseIterable, Identifiable {
    case map = "Map"
    case sites = "Sites"
    case links = "Links"
    var id: String { rawValue }
}

/// Native file dialogs.
@MainActor
enum Dialogs {
    static func importFile(_ store: DataStore) {
        let panel = NSOpenPanel()
        var types: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText]
        if let xlsx = UTType(filenameExtension: "xlsx") { types.insert(xlsx, at: 0) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the data center spreadsheet (.xlsx or .csv)"
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url { store.beginImport(url: url) }
    }

    static func exportCSV(_ store: DataStore) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "dc-dr-links.csv"
        panel.message = "Export every data center → DR link, with coordinates"
        if panel.runModal() == .OK, let url = panel.url { store.exportCSV(to: url) }
    }

    static func exportHTML(_ store: DataStore) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "dc-dr-map.html"
        panel.message = "Export a self-contained interactive map with the complete database snapshot"
        panel.prompt = "Export"
        if panel.runModal() == .OK, let url = panel.url { store.exportHTML(to: url) }
    }

    static func confirmClear(_ store: DataStore) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete all sites and links?"
        alert.informativeText = "This empties the database. It cannot be undone. Export a CSV first if you want a backup."
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.clearAll() }
    }
}

@MainActor
struct ContentView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @StateCompat private var tab: AppTab = .map

    private var palette: Palette { Palette(dark: scheme == .dark) }

    var body: some View {
        VStack(spacing: 12) {
            KPIRow()
            switch tab {
            case .map:
                HStack(alignment: .top, spacing: 12) {
                    MapView()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line, lineWidth: 1))
                    SidebarView()
                        .frame(width: 340)
                }
            case .sites:
                SitesView()
            case .links:
                LinksView()
            }
        }
        .padding(14)
        .background(palette.bg)
        .environment(\.palette, palette)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(AppTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Dialogs.importFile(store) } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .help("Import a .xlsx or .csv spreadsheet")
                Button { Dialogs.exportCSV(store) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .help("Export links as CSV")
                Button { Dialogs.exportHTML(store) } label: { Label("HTML map", systemImage: "map") }
                    .help("Export an offline interactive map with all database data")
                Button { store.geocode() } label: { Label("Look up coordinates", systemImage: "mappin.and.ellipse") }
                    .help("Look up coordinates online for sites that have none")
                    .disabled(store.geocodeProgress != nil)
            }
        }
        .sheet(item: $store.pendingImport) { preview in
            ImportSheet(preview: preview)
        }
        .alert(store.alert?.title ?? "",
               isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } }),
               presenting: store.alert) { _ in
            Button("OK", role: .cancel) {}
        } message: { a in
            Text(a.message)
        }
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}

// MARK: - KPI tiles

@MainActor
struct KPIRow: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.palette) private var p

    var body: some View {
        let sites = store.sites
        let real = store.links.filter { !$0.isSelf }.count
        let local = store.links.count - real
        let countries = Set(sites.map { normalize($0.country) }.filter { !$0.isEmpty }).count
        let cities = Set(sites.map { normalize($0.city) }.filter { !$0.isEmpty }).count

        HStack(spacing: 12) {
            tile("Data centers", "\(sites.filter { $0.asDC }.count)")
            tile("DR sites", "\(sites.filter { $0.asDR }.count)")
            tile("Replication links", "\(real)", extra: local > 0 ? "+\(local) local" : nil)
            tile("Countries", "\(countries)")
            tile("Cities", "\(cities)")
        }
    }

    private func tile(_ title: String, _ value: String, extra: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 26, weight: .semibold)).foregroundColor(p.text)
                if let extra = extra { Text(extra).font(.system(size: 12)).foregroundColor(p.muted) }
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .kerning(0.6)
                .foregroundColor(p.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(p.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.line, lineWidth: 1))
    }
}

// MARK: - Map sidebar

@MainActor
struct SidebarView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.palette) private var p
    @StateCompat private var query = ""

    private var filteredLinks: [Link] {
        let q = normalize(query)
        return store.links.filter { l in
            guard let a = store.site(l.dcID), let b = store.site(l.drID) else { return false }
            if q.isEmpty { return true }
            let hay = normalize([a.name, a.city, a.country, b.name, b.city, b.country].joined(separator: " "))
            return hay.contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Card("Replication links") {
                    TextField("Filter sites, cities, countries…", text: $query)
                        .textFieldStyle(.roundedBorder)
                    if filteredLinks.isEmpty {
                        Text(store.links.isEmpty ? "No links yet." : "No match.").foregroundColor(p.muted).font(.system(size: 12))
                    } else {
                        VStack(spacing: 2) {
                            ForEach(filteredLinks) { linkRow($0) }
                        }
                    }
                }
                Card("Selection") { selectionBody }
                if !store.dataNotes.isEmpty {
                    Card("Data notes") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(store.dataNotes.enumerated()), id: \.offset) { _, note in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").foregroundColor(p.warn)
                                    Text(note).foregroundColor(p.muted)
                                }
                                .font(.system(size: 12))
                            }
                        }
                    }
                }
            }
        }
    }

    private func linkRow(_ l: Link) -> some View {
        let a = store.site(l.dcID)
        let b = store.site(l.drID)
        let selected = store.selection == .link(l.id)
        return Button {
            store.selection = .link(l.id)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(a?.name ?? "?").fontWeight(.semibold)
                        Text("→")
                        Text(l.isSelf ? "itself" : (b?.name ?? "?")).fontWeight(.semibold)
                    }
                    .lineLimit(1)
                    Text(l.isSelf ? (a?.locationLabel ?? "") : "\(a?.locationLabel ?? "") → \(b?.locationLabel ?? "")")
                        .font(.system(size: 11)).foregroundColor(p.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let a = a, let b = b {
                    Text(Fmt.kmLabel(a, b))
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .overlay(Capsule().stroke(l.isSelf ? p.dr : p.line, lineWidth: 1))
                        .foregroundColor(l.isSelf ? p.dr : p.muted)
                }
            }
            .font(.system(size: 13))
            .foregroundColor(p.text)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? p.panel2 : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? p.line : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectionBody: some View {
        switch store.selection {
        case .none:
            Text("Click a site or a link on the map.").foregroundColor(p.muted).font(.system(size: 13))
        case .site(let id)?:
            if let s = store.site(id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.name).font(.system(size: 14, weight: .bold))
                    Text(s.roleLabel).font(.system(size: 11)).foregroundColor(p.muted)
                    Text(s.locationLabel).foregroundColor(p.muted)
                    Text("\(Fmt.coordShort(s.latitude)), \(Fmt.coordShort(s.longitude))  ·  \(s.geoStatus.label)")
                        .font(.system(size: 12)).foregroundColor(p.muted)

                    let out = store.links.filter { $0.dcID == id }
                    let into = store.links.filter { $0.drID == id && !$0.isSelf }
                    if !out.isEmpty {
                        Text("Replicates to").font(.system(size: 11)).foregroundColor(p.muted).padding(.top, 6)
                        ForEach(out) { l in
                            Text(l.isSelf ? "itself (local DR)" : "\(store.site(l.drID)?.name ?? "?") (\(store.site(l.drID)?.city ?? ""))")
                        }
                    }
                    if !into.isEmpty {
                        Text("Is DR for").font(.system(size: 11)).foregroundColor(p.muted).padding(.top, 6)
                        ForEach(into) { l in
                            Text("\(store.site(l.dcID)?.name ?? "?") (\(store.site(l.dcID)?.city ?? ""))")
                        }
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(p.text)
            }
        case .link(let id)?:
            if let l = store.link(id), let a = store.site(l.dcID), let b = store.site(l.drID) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.isSelf ? "\(a.name) protects itself" : "\(a.name) → \(b.name)").font(.system(size: 14, weight: .bold))
                    Text(l.isSelf ? a.locationLabel : "\(a.locationLabel) → \(b.locationLabel)").foregroundColor(p.muted)
                    if !l.isSelf {
                        Text("Great-circle distance: \(Fmt.kmLabel(a, b))").font(.system(size: 12))
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(p.text)
            }
        }
    }
}

// MARK: - Import sheet

@MainActor
struct ImportSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let preview: ImportPreview
    @StateCompat private var replace = false
    @StateCompat private var lookup = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import “\(preview.fileName)”").font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("The file contains \(preview.rows.count) row(s): \(preview.uniqueSites) distinct site(s) and \(preview.uniqueLinks) distinct link(s).")
                if preview.duplicateRows > 0 { Text("\(preview.duplicateRows) duplicate row(s) will be ignored.").foregroundColor(.secondary) }
                if preview.blankSkipped > 0 { Text("\(preview.blankSkipped) row(s) without a data center or DR site name will be skipped.").foregroundColor(.secondary) }
                Text("The database currently holds \(store.sites.count) site(s) and \(store.links.count) link(s).").foregroundColor(.secondary)
            }
            .font(.system(size: 13))

            Picker("", selection: $replace) {
                Text("Merge into the existing data").tag(false)
                Text("Replace all existing data").tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Toggle("Look up coordinates online after importing", isOn: $lookup)
            Text("Cities are searched on OpenStreetMap (fallback: Open-Meteo), at most one request per second, and each city is only looked up once. Coordinates in optional columns 7–10 are used as they are.")
                .font(.system(size: 11)).foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { store.pendingImport = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button(replace ? "Replace and Import" : "Import") {
                    store.commitImport(preview, replace: replace, lookupOnline: lookup)
                    store.pendingImport = nil
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
