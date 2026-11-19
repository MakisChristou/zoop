import SwiftUI
import ZoopHealth

struct WeightImportView: View {
    private struct PreviewKey: Hashable {
        let range: HealthJournal.Range
        let enabled: Bool
        let namespace: String
        let retry: Int
    }
    @Environment(AppModel.self) private var model
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
                            Image(systemName: "checkmark.circle").font(ZoopType.largeTitle).foregroundStyle(ZoopStyle.load)
                            Text(result == 0 ? "Already up to date" : "\(result) \(result == 1 ? "weigh-in" : "weigh-ins") added")
                                .font(ZoopType.font(size: 20, weight: .semibold, relativeTo: .title2))
                            Text("Your weight chart is ready.").foregroundStyle(ZoopStyle.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).zoopCard()
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "heart").font(ZoopType.title).foregroundStyle(ZoopStyle.load)
                            Text("Apple Health").font(ZoopType.font(size: 20, weight: .semibold, relativeTo: .title2))
                        }
                        if enabled {
                            VStack(spacing: 16) {
                                Toggle("All available history", isOn: $all)
                                if !all {
                                    DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                                    DatePicker("Through", selection: $to, in: from...Date(), displayedComponents: .date)
                                }
                            }.zoopCard().disabled(importing)
                            if importing {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Importing weigh-ins…").font(ZoopType.headline)
                                    ProgressView(value: Double(health.importedWeightCount), total: Double(max(preview?.toImport ?? 1, health.importedWeightCount, 1)))
                                    Text("\(health.importedWeightCount) added").font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).zoopCard()
                            } else if loading {
                                HStack { ProgressView(); Text("Checking Apple Health…").font(ZoopType.subheadline) }
                                    .frame(maxWidth: .infinity, alignment: .leading).zoopCard()
                            } else if let preview { previewCard(preview) }
                        } else {
                            Text(health.connected ? "Weight imports are off." : "Connect Apple Health to import weigh-ins.")
                                .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary).zoopCard()
                        }
                        if let error {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(error).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.unfavourable)
                                if preview == nil { Button("Try again") { retry += 1 } }
                            }.zoopCard()
                        }
                        Label("Originals in Apple Health stay unchanged.", systemImage: "checkmark.shield")
                            .font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
                    }
                }.padding(ZoopStyle.gutter)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if result != nil { dismiss() }
                    else if !enabled { showConnection = true }
                    else { beginImport() }
                } label: {
                    Text(buttonTitle).font(ZoopType.headline).frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                }
                .buttonStyle(.borderedProminent)
                .disabled(result == nil && enabled && (loading || importing || preview == nil || (preview?.toImport == 0 && error == nil)))
                .padding(.horizontal, ZoopStyle.gutter).padding(.vertical, 12).background(ZoopStyle.background)
                .accessibilityIdentifier("confirmWeightImport")
            }
            .zoopScreen().tint(ZoopStyle.text)
            .navigationTitle("Import weight history").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(importing).accessibilityIdentifier("closeWeightImport") } }
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
        return preview.toImport == 0 ? "Up to date" : "Add \(preview.toImport) \(preview.toImport == 1 ? "weigh-in" : "weigh-ins")"
    }
    private func previewCard(_ preview: WeightImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if preview.toImport > 0 {
                MetricValue(String(preview.toImport), size: 32)
                Text(preview.toImport == 1 ? "weigh-in to add" : "weigh-ins to add").font(ZoopType.headline)
            } else {
                Text(preview.total == 0 ? "No weigh-ins found" : "All weigh-ins are already saved").font(ZoopType.headline)
            }
            if let first = preview.first, let last = preview.last {
                Text(first.formatted(date: .abbreviated, time: .omitted) + " – " + last.formatted(date: .abbreviated, time: .omitted))
                    .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
            }
            if preview.alreadySaved > 0 {
                Text("\(preview.alreadySaved) already saved · skipped").font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
            }
            if preview.total == 0 {
                Text("Try different dates. If you expect readings here, check Zoop’s weight access in Apple Health.")
                    .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).zoopCard().accessibilityIdentifier("weightImportPreview")
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
