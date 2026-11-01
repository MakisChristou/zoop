import SwiftUI
import SnoopHealth

struct WeightImportView: View {
    private struct PreviewKey: Hashable {
        let range: HealthJournal.Range
        let enabled: Bool
        let namespace: String
        let retry: Int
    }
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var all = true
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var preview: WeightImportPreview?
    @State private var loading = false
    @State private var importing = false
    @State private var result: Int?
    @State private var error: String?
    @State private var retry = 0
    @State private var showConnection = false
    private var health: HealthCoordinator { model.health }
    private var enabled: Bool { health.connected && health.journal.importWeight }
    private var range: HealthJournal.Range {
        let cal = Calendar.current
        return .init(from: all ? Date(timeIntervalSince1970: 0) : cal.startOfDay(for: from),
                     to: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: all ? Date() : to)) ?? Date())
    }
    private var key: PreviewKey { .init(range: range, enabled: enabled, namespace: health.journal.namespace, retry: retry) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let result {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(SnoopStyle.load)
                            Text(result == 0 ? "Already up to date" : "\(result) \(result == 1 ? "weigh-in" : "weigh-ins") added")
                                .font(.title2.weight(.semibold))
                            Text("Your weight chart is ready.").foregroundStyle(SnoopStyle.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Apple Health → Snoop", systemImage: "heart").font(.headline)
                            Text("Bring your past weigh-ins into your weight chart.")
                                .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                        }
                        if enabled {
                            HistoryRangePicker(all: $all, from: $from, to: $to).disabled(importing)
                            if importing {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Importing weigh-ins…").font(.headline)
                                    ProgressView(value: Double(health.importedWeightCount), total: Double(max(preview?.toImport ?? 1, health.importedWeightCount, 1)))
                                    Text("\(health.importedWeightCount) added").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
                            } else if loading {
                                HStack { ProgressView(); Text("Checking Apple Health…").font(.subheadline) }
                                    .frame(maxWidth: .infinity, alignment: .leading).snoopCard()
                            } else if let preview { previewCard(preview) }
                        } else {
                            Text("Enable weight imports in your Apple Health connection to get started.")
                                .font(.subheadline).foregroundStyle(SnoopStyle.secondary).snoopCard()
                        }
                        if let error {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(error).font(.subheadline).foregroundStyle(SnoopStyle.unfavourable)
                                if preview == nil { Button("Try again") { retry += 1 } }
                            }.snoopCard()
                        }
                        Text("Apple Health originals stay unchanged. This imports weight only.")
                            .font(.footnote).foregroundStyle(SnoopStyle.secondary)
                    }
                }.padding(SnoopStyle.gutter)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if result != nil { dismiss() }
                    else if !enabled { showConnection = true }
                    else { beginImport() }
                } label: {
                    Text(buttonTitle).font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                }
                .buttonStyle(.borderedProminent)
                .disabled(result == nil && enabled && (loading || importing || preview == nil || (preview?.toImport == 0 && error == nil)))
                .padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 12).background(SnoopStyle.background)
                .accessibilityIdentifier("confirmWeightImport")
            }
            .snoopScreen().tint(SnoopStyle.load)
            .navigationTitle("Import weight history").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(importing) } }
            .task(id: key) { await refreshPreview() }
            .interactiveDismissDisabled(importing)
            .sheet(isPresented: $showConnection, onDismiss: { retry += 1 }) {
                NavigationStack {
                    AppleHealthView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showConnection = false } } }
                }
            }
        }
    }
    private var buttonTitle: String {
        if result != nil { return "View weight chart" }
        if !enabled { return "Set up Apple Health" }
        if importing { return "Importing…" }
        if error != nil && preview != nil { return "Retry import" }
        guard let preview else { return loading ? "Checking history…" : "Import weigh-ins" }
        if preview.total == 0 { return "No weigh-ins to import" }
        return preview.toImport == 0 ? "Up to date" : "Import \(preview.toImport) \(preview.toImport == 1 ? "weigh-in" : "weigh-ins")"
    }
    private func previewCard(_ preview: WeightImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview.total == 0 ? "No weigh-ins found" : preview.toImport == 0 ? "All weigh-ins are already saved" : "\(preview.toImport) \(preview.toImport == 1 ? "weigh-in" : "weigh-ins") ready to import")
                .font(.headline)
            if let first = preview.first, let last = preview.last {
                Text(first.formatted(date: .abbreviated, time: .omitted) + " – " + last.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
            if preview.alreadySaved > 0 {
                Text("\(preview.alreadySaved) already saved · skipped").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
            if preview.total == 0 {
                Text("Try different dates. If you expect readings here, check Snoop’s weight access in Apple Health.")
                    .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).snoopCard().accessibilityIdentifier("weightImportPreview")
    }
    private func refreshPreview() async {
        guard !importing, result == nil else { return }
        let requested = key
        preview = nil; error = nil
        guard enabled else { loading = false; return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(200))
            let found = try await health.previewWeightImport(requested.range)
            try Task.checkCancellation()
            guard requested == key else { return }
            preview = found; loading = false
        } catch is CancellationError {
        } catch {
            guard requested == key, !Task.isCancelled else { return }
            self.error = error.localizedDescription; loading = false
        }
    }
    private func beginImport() {
        let selected = range
        importing = true; error = nil
        Task {
            do { result = try await health.importWeightHistory(selected) }
            catch {
                self.error = error.localizedDescription
                if let updated = try? await health.previewWeightImport(selected) { preview = updated }
            }
            importing = false
        }
    }
}
