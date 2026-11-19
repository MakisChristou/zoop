import SwiftUI

struct SleepHeatmapDetail: View {
    let night: ZoopAPI.Night
    let open: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SleepDuration(seconds: night.metrics.window.asleepS, size: 32).foregroundStyle(ZoopStyle.sleep)
                    Text("\(night.startTs.formatted(date: .omitted, time: .shortened)) – \(night.endTs.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline).foregroundStyle(ZoopStyle.secondary)
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
                    layout {
                        metric("Efficiency", "\(Int((night.metrics.window.efficiency * 100).rounded()))%")
                        metric("HRV", night.metrics.physiology.hrvRmssdMs.map { "\(Int($0.rounded())) ms" } ?? "—")
                        metric("Resting HR", night.metrics.physiology.restingHr.map { "\(Int($0.rounded())) bpm" } ?? "—")
                    }
                    Button(action: open) { Text("View sleep").font(.headline).frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(.borderedProminent).tint(ZoopStyle.text).accessibilityIdentifier("heatmapOpenSleep")
                }.padding(ZoopStyle.gutter)
            }.zoopScreen()
                .navigationTitle(night.endTs.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(340), .medium])
        .presentationDragIndicator(.visible).presentationBackground(ZoopStyle.background)
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(ZoopStyle.secondary)
            Text(value).font(.headline).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
