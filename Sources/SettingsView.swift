import SwiftUI
import UIKit

struct SettingsView: View {
    @Binding var stored: String
    @Environment(\.dismiss) private var dismiss
    @State private var store = WatchStore.shared
    @State private var checking = false
    @State private var checkResult: String?
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $stored) {
                        ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                watchedSection
                categorySection
                checkSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { notificationsDenied = await NotificationAccess.isDenied() }
        }
    }

    private var watchedSection: some View {
        Section("Notifications") {
            if store.pages.isEmpty {
                Text("Nothing watched yet. Tap the bell on a game, team or table page.").foregroundStyle(.secondary)
            }
            ForEach(store.pages) { page in
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                    Text(Self.label(page.kind)).font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions { Button("Stop watching", role: .destructive) { store.remove(page) } }
            }
        }
    }

    private var categorySection: some View {
        Section("Notify me about") {
            ForEach(NotificationCategory.allCases, id: \.self) { category in
                Toggle(Self.label(category), isOn: Binding(
                    get: { store.enabledCategories.contains(category) },
                    set: { store.setCategory(category, enabled: $0) }))
            }
        }
    }

    private var checkSection: some View {
        Section {
            Button {
                Task {
                    checking = true
                    let changes = await SiteChecker(notifier: SystemNotifier()).run(store: store)
                    checkResult = changes.isEmpty ? "No changes" : "\(changes.count) change\(changes.count == 1 ? "" : "s") found"
                    checking = false
                }
            } label: {
                if checking { ProgressView() } else { Text("Check now") }
            }
            .disabled(checking || store.pages.isEmpty)
            if let checkResult { Text(checkResult).foregroundStyle(.secondary) }
            if let last = store.lastCheck { Text("Last check: \(last.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary) }
            if notificationsDenied {
                Button("Notifications are off for this app. Open Settings.") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            if UIApplication.shared.backgroundRefreshStatus != .available {
                Text("Background App Refresh is off, so pages are only checked with \"Check now\".").foregroundStyle(.secondary)
            }
        } footer: {
            Text("iOS decides when pages are checked in the background, so changes can arrive late.")
        }
    }

    private static func label(_ kind: PageKind) -> String {
        switch kind {
        case .game: "Game"
        case .team: "Team"
        case .table: "Table"
        case .goalies: "Goalies"
        case .topscorers: "Top scorers"
        }
    }
    private static func label(_ category: NotificationCategory) -> String {
        switch category {
        case .score: "Scores and game start/end"
        case .lineup: "Lineups"
        case .statistics: "Statistics and tables"
        }
    }
}
