import SwiftUI

// MARK: - Sites table (create / read / update / delete)

@MainActor
struct SitesView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.palette) private var p

    @StateCompat private var selection = Set<Site.ID>()
    @StateCompat private var query = ""
    @StateCompat private var editing: SiteDraft?
    @StateCompat private var confirmDelete = false
    @StateCompat private var sortOrder = [KeyPathComparator(\Site.name)]

    private var filtered: [Site] {
        let q = normalize(query)
        let matches: [Site]
        if q.isEmpty {
            matches = store.sites
        } else {
            matches = store.sites.filter {
                normalize([$0.name, $0.city, $0.country].joined(separator: " ")).contains(q)
            }
        }
        return matches.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search sites…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                Button { editing = SiteDraft() } label: { Label("Add Site", systemImage: "plus") }
                Button { editSelected() } label: { Label("Edit", systemImage: "pencil") }
                    .disabled(selection.count != 1)
                Button { store.geocode(ids: Array(selection)) } label: { Label("Look Up Coordinates", systemImage: "mappin.and.ellipse") }
                    .disabled(selection.isEmpty || store.geocodeProgress != nil)
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selection.isEmpty)
            }

            Table(filtered, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { Text($0.name).fontWeight(.semibold) }
                TableColumn("Country", value: \.country) { Text($0.country) }
                TableColumn("City", value: \.city) { Text($0.city) }
                TableColumn("Latitude", value: \.latitudeSort) { Text(Fmt.coordShort($0.latitude)).monospacedDigit() }
                TableColumn("Longitude", value: \.longitudeSort) { Text(Fmt.coordShort($0.longitude)).monospacedDigit() }
                TableColumn("Coordinates", value: \.geoStatus) { StatusBadge(status: $0.geoStatus) }
                TableColumn("Role", value: \.roleLabel) { Text($0.roleLabel).foregroundColor(.secondary) }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: Site.ID.self) { ids in
                if ids.count == 1, let id = ids.first {
                    Button("Edit…") { edit(id) }
                }
                if !ids.isEmpty {
                    Button("Look Up Coordinates") { store.geocode(ids: Array(ids)) }
                    Divider()
                    Button("Delete…", role: .destructive) { selection = ids; confirmDelete = true }
                }
            } primaryAction: { ids in
                if let id = ids.first { edit(id) }
            }

            HStack {
                Text("\(store.sites.count) site(s)")
                let missing = store.sites.filter { !$0.hasCoordinates }.count
                if missing > 0 { Text("· \(missing) without coordinates").foregroundColor(p.warn) }
                Spacer()
                Text("Double-click a row to edit").foregroundColor(p.muted)
            }
            .font(.system(size: 12))
            .foregroundColor(p.muted)
        }
        .sheet(item: $editing) { draft in
            SiteEditor(draft: draft)
        }
        .confirmationDialog("Delete \(selection.count) site(s)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteSites(selection)
                selection = []
            }
        } message: {
            Text("Replication links that use these sites are deleted as well.")
        }
    }

    private func editSelected() {
        if let id = selection.first { edit(id) }
    }

    private func edit(_ id: Site.ID) {
        if let s = store.site(id) { editing = SiteDraft(site: s) }
    }
}

struct StatusBadge: View {
    @Environment(\.palette) private var p
    let status: GeoStatus

    private var color: Color {
        switch status {
        case .ok: return p.dc
        case .manual: return p.both
        case .pending: return p.muted
        case .failed: return p.warn
        }
    }

    var body: some View {
        Text(status.label)
            .font(.system(size: 11))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundColor(color)
            .overlay(Capsule().stroke(color.opacity(0.7), lineWidth: 1))
    }
}

// MARK: - Site editor sheet

@MainActor
struct SiteEditor: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @StateCompat private var draft: SiteDraft
    @StateCompat private var looking = false
    @StateCompat private var message: String?

    init(draft: SiteDraft) {
        _draft = StateCompat(wrappedValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.dbID == nil ? "Add site" : "Edit site").font(.title3.weight(.semibold))

            Form {
                TextField("Name", text: $draft.name)
                TextField("Country", text: $draft.country)
                TextField("City", text: $draft.city)
                TextField("Latitude", text: $draft.latText)
                TextField("Longitude", text: $draft.lonText)
            }

            HStack(spacing: 10) {
                Button("Look Up Online") { lookup() }
                    .disabled(looking || draft.city.trimmingCharacters(in: .whitespaces).isEmpty)
                if looking { ProgressView().controlSize(.small) }
                if let m = message { Text(m).font(.system(size: 12)).foregroundColor(.secondary) }
            }

            Text("Leave latitude and longitude empty and they are looked up online automatically after saving.")
                .font(.system(size: 11)).foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { if store.saveSite(draft) { dismiss() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func lookup() {
        let city = draft.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = draft.country.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        looking = true
        message = nil
        Task {
            do {
                if let r = try await Geocoder.lookup(city: city, country: country, fallbackName: name) {
                    draft.latText = Fmt.coord(r.latitude)
                    draft.lonText = Fmt.coord(r.longitude)
                    message = "Found via \(r.provider)."
                } else {
                    message = "No match. Check the spelling of the city and country."
                }
            } catch {
                message = error.localizedDescription
            }
            looking = false
        }
    }
}
