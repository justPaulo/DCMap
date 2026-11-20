import SwiftUI
import AppKit

@main
@MainActor
struct DCMapApp: App {
    @StateObject private var store = DataStore()

    init() {
        // Needed when launched as a bare SwiftPM executable (no .app bundle): show a Dock icon and menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
        // Decode the 1.2 MB world geometry in the background so the first map draw is instant.
        DispatchQueue.global(qos: .userInitiated).async { _ = World.shared }
    }

    var body: some Scene {
        WindowGroup("DC & DR Topology") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Spreadsheet…") { Dialogs.importFile(store) }
                    .keyboardShortcut("o")
                Button("Export Links as CSV…") { Dialogs.exportCSV(store) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export Interactive Map as HTML…") { Dialogs.exportHTML(store) }
                Divider()
                Button("Look Up Missing Coordinates") { store.geocode() }
                    .keyboardShortcut("l")
                Divider()
                Button("Show Database in Finder") { store.revealDatabase() }
                Button("Delete All Data…") { Dialogs.confirmClear(store) }
            }
        }
    }
}
