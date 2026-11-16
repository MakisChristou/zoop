import SwiftUI

struct StepGoalProgress: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var celebration = 0
    let steps: Int?
    let target: Int
    private var reached: Bool { steps.map { $0 >= target } ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Goal \(target.formatted())").foregroundStyle(SnoopStyle.secondary)
                Spacer()
                if reached { Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SnoopStyle.favourable)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : celebration) }
            }.font(.caption)
            if let steps {
                ProgressView(value: Double(max(0, min(steps, target))), total: Double(max(1, target)))
                    .tint(reached ? SnoopStyle.favourable : SnoopStyle.steps)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: reached)
        .onChange(of: steps) { old, new in
            guard celebration == 0, scenePhase == .active, let old, let new, old < target, new >= target else { return }
            celebration += 1
        }
        .sensoryFeedback(.success, trigger: celebration)
        .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily steps goal")
            .accessibilityValue(steps.map { "\($0.formatted()) of \(target.formatted()) steps\(reached ? ", goal reached" : "")" } ?? "\(target.formatted()) steps. No step data yet.")
            .accessibilityIdentifier("cutStepsProgress")
    }
}
