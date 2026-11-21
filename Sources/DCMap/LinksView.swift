import SwiftUI

struct LinkDraft: Identifiable {
    let id = UUID()
    var linkID: Int64?       // nil while creating
    var dc: Int64
    var dr: Int64
}

private struct LinkRowModel: Identifiable {
    let id: Int64
    let dc: Site
    let dr: Site

    var dcLocation: String { dc.locationLabel }
    var drLocation: String { dr.locationLabel }
    var distanceSort: Double {
        if dc.id == dr.id { return 0 }
        return Fmt.km(dc, dr) ?? .infinity
    }
}

// MARK: - Links table (create / read / update / delete)

@MainActor
struct LinksView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.palette) private var p

    @StateCompat private var selection = Set<Int64>()
    @StateCompat private var query = ""
    @StateCompat private var editing: LinkDraft?
    @StateCompat private var confirmDelete = false
    @StateCompat private var sortOrder = [KeyPathComparator(\LinkRowModel.dc.name)]

    private var rows: [LinkRowModel] {
        let q = normalize(query)
        let matches = store.links.compactMap { l -> LinkRowModel? in
            guard let a = store.site(l.dcID), let b = store.site(l.drID) else { return nil }
            if !q.isEmpty {
                let hay = normalize([a.name, a.city, a.country, b.name, b.city, b.country].joined(separator: " "))
                if !hay.contains(q) { return nil }
            }
            return LinkRowModel(id: l.id, dc: a, dr: b)
        }
        return matches.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search links…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                Button { newLink() } label: { Label("Add Link", systemImage: "plus") }
                    .disabled(store.sites.isEmpty)
                Button { editSelected() } label: { Label("Edit", systemImage: "pencil") }
                    .disabled(selection.count != 1)
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selection.isEmpty)
            }

            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Data center", value: \.dc.name) { Text($0.dc.name).fontWeight(.semibold) }
                TableColumn("DC location", value: \.dcLocation) { Text($0.dc.locationLabel).foregroundColor(.secondary) }
                TableColumn("DR site", value: \.dr.name) { Text($0.dr.name).fontWeight(.semibold) }
                TableColumn("DR location", value: \.drLocation) { Text($0.dr.locationLabel).foregroundColor(.secondary) }
                TableColumn("Distance", value: \.distanceSort) { Text(Fmt.kmLabel($0.dc, $0.dr)) }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: Int64.self) { ids in
                if ids.count == 1, let id = ids.first {
                    Button("Edit…") { edit(id) }
                }
                if !ids.isEmpty {
                    Button("Show on Map") { if let id = ids.first { store.selection = .link(id) } }
                    Divider()
                    Button("Delete…", role: .destructive) { selection = ids; confirmDelete = true }
                }
            } primaryAction: { ids in
                if let id = ids.first { edit(id) }
            }

            HStack {
                Text("\(store.links.count) link(s)")
                if store.sites.isEmpty { Text("· add sites first, then link them").foregroundColor(p.warn) }
                Spacer()
                Text("A link means: this data center replicates to that DR site").foregroundColor(p.muted)
            }
            .font(.system(size: 12))
            .foregroundColor(p.muted)
        }
        .sheet(item: $editing) { draft in
            LinkEditor(draft: draft)
        }
        .confirmationDialog("Delete \(selection.count) link(s)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteLinks(selection)
                selection = []
            }
        } message: {
            Text("The sites themselves are kept.")
        }
    }

    private func newLink() {
        guard let first = store.sites.first else { return }
        editing = LinkDraft(linkID: nil, dc: first.id, dr: store.sites.count > 1 ? store.sites[1].id : first.id)
    }

    private func editSelected() {
        if let id = selection.first { edit(id) }
    }

    private func edit(_ id: Int64) {
        if let l = store.link(id) { editing = LinkDraft(linkID: l.id, dc: l.dcID, dr: l.drID) }
    }
}

// MARK: - Link editor sheet

@MainActor
struct LinkEditor: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @StateCompat private var draft: LinkDraft

    init(draft: LinkDraft) {
        _draft = StateCompat(wrappedValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.linkID == nil ? "Add link" : "Edit link").font(.title3.weight(.semibold))

            Form {
                Picker("Data center", selection: $draft.dc) {
                    ForEach(store.sites) { s in Text("\(s.name) — \(s.locationLabel)").tag(s.id) }
                }
                Picker("Replicates to (DR site)", selection: $draft.dr) {
                    ForEach(store.sites) { s in Text("\(s.name) — \(s.locationLabel)").tag(s.id) }
                }
            }

            if draft.dc == draft.dr {
                Text("Same site on both sides means the site hosts its own DR (shown as a dashed ring on the map).")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    let ok: Bool
                    if let id = draft.linkID {
                        ok = store.updateLink(id: id, dc: draft.dc, dr: draft.dr)
                    } else {
                        ok = store.addLink(dc: draft.dc, dr: draft.dr)
                    }
                    if ok { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
