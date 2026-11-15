import SwiftUI

struct StepGoalProgress: View {
    let steps: Int?
    let target: Int
    private var reached: Bool { steps.map { $0 >= target } ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Goal \(target.formatted())").foregroundStyle(SnoopStyle.secondary)
                Spacer()
                if reached { Image(systemName: "checkmark.circle.fill").foregroundStyle(SnoopStyle.favourable) }
            }.font(.caption)
            if let steps {
                ProgressView(value: Double(max(0, min(steps, target))), total: Double(max(1, target)))
                    .tint(reached ? SnoopStyle.favourable : SnoopStyle.steps)
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily steps goal")
            .accessibilityValue(steps.map { "\($0.formatted()) of \(target.formatted()) steps\(reached ? ", goal reached" : "")" } ?? "\(target.formatted()) steps. No step data yet.")
            .accessibilityIdentifier("cutStepsProgress")
    }
}
