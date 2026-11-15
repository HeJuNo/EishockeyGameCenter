import SwiftUI

/// The detected changes, newest first, with exactly what is gone (red) and what is new (green) on the page.
struct ChangesView: View {
    @State private var store = WatchStore.shared

    var body: some View {
        List {
            if store.history.isEmpty {
                Text("No changes yet. They appear here when a watched page changes.").foregroundStyle(.secondary)
            }
            ForEach(store.history) { record in
                Section {
                    ForEach(Array(record.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(line.side == .added ? "+" : line.side == .removed ? "−" : "~").bold()
                            Text(line.text)
                        }
                        .font(.callout)
                        .foregroundStyle(line.side == .added ? Color.green : line.side == .removed ? Color.red : Color.orange)
                    }
                    if record.lines.isEmpty { Text("No details available.").foregroundStyle(.secondary) }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(record.pageTitle): \(record.summary)").font(.subheadline.bold()).textCase(nil)
                        Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Changes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.history.isEmpty { ToolbarItem { Button("Clear", role: .destructive) { store.clearHistory() } } }
        }
    }
}
