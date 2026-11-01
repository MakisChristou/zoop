import SwiftUI

struct MorningInsightsView: View {
    let day: Date
    @EnvironmentObject private var model: AppModel
    @State private var insights: MorningInsights?
    @State private var error = false
    @State private var loading = false
    @State private var requestID = UUID()
    @State private var showMethod = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                if error {
                    Button("Couldn’t update insights. Retry") { Task { await load() } }
                        .frame(minHeight: 44).accessibilityIdentifier("retryInsights")
                }
                if let insights {
                    if insights.state != "ready" {
                        Text(insights.status).foregroundStyle(SnoopStyle.secondary)
                    }
                    ForEach(insights.metrics) { InsightMetricView(metric: $0) }
                    weekly(insights)
                    timing(insights)
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity).accessibilityLabel("Loading morning insights")
                }
            }.padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 16)
        }
        .navigationTitle("Morning insights").navigationBarTitleDisplayMode(.inline).snoopScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMethod = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About morning insights")
            }
        }
        .sheet(isPresented: $showMethod) { InsightMethodView() }
        .task(id: "\(model.strap.serial)-\(day.timeIntervalSince1970)") { await load() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                if insights?.state != "ready" || error { await load() }
            }
        }
        .refreshable { await load() }
        .onChange(of: model.sleep.changeToken) { _, _ in Task { await load() } }
        .onChange(of: model.analysisRevision) { _, _ in Task { await load() } }
    }
    private func weekly(_ insights: MorningInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past 7 days").font(.headline)
            ForEach(insights.metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.title).font(.subheadline.weight(.medium))
                    if let average = metric.week.average {
                        Text("\(metric.formatted(average)) \(metric.unit) average · \(metric.week.count) nights").font(.subheadline)
                        if let previous = metric.week.previousAverage {
                            Text("Previous week: \(metric.formatted(previous)) \(metric.unit)").font(.caption).foregroundStyle(SnoopStyle.secondary)
                        }
                    } else {
                        Text("\(metric.week.count)/5 recorded nights").font(.caption).foregroundStyle(SnoopStyle.secondary)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
    }
    private func timing(_ insights: MorningInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep timing").font(.headline)
            if let asleep = insights.timing.asleepSdMin, let wake = insights.timing.wakeSdMin {
                Text("Falling asleep varied by about \(Int(asleep.rounded())) min; waking up by \(Int(wake.rounded())) min.")
                    .font(.subheadline)
                Text("Across \(insights.timing.count) nights this week").font(.caption).foregroundStyle(SnoopStyle.secondary)
            } else {
                Text("Needs five recorded nights in the same time zone.").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
    }
    private func load() async {
        guard Settings.isConfigured, !model.strap.serial.isEmpty else { return }
        let serial = model.strap.serial
        let token = UUID(); requestID = token; loading = true
        defer { if requestID == token { loading = false } }
        do {
            let value = try await SnoopAPI.morningInsights(deviceId: serial, day: day)
            guard !Task.isCancelled, requestID == token, serial == model.strap.serial else { return }
            insights = value; error = false
        } catch {
            guard !Task.isCancelled, requestID == token else { return }
            // Never present a previous result as a newly completed calculation.
            insights = nil; self.error = true
        }
    }
}
