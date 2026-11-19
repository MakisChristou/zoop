import SwiftUI

struct StepGoalProgress: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var appeared = false
    @State private var celebration = 0
    let steps: Int?
    let target: Int
    private static let entranceDelay: Duration = .milliseconds(350)
    private var reached: Bool { steps.map { $0 >= target } ?? false }
    private var completion: StepGoalCompletion { model.stepsReminder.completion }
    private var pendingKey: String? { reached ? completion.celebrationKey : nil }
    private var presentationKey: String? {
        appeared && visible && scenePhase == .active ? pendingKey : nil
    }
    private var progress: Double {
        // The one-time fill is a celebration, not a change to the measured count.
        if pendingKey != nil && !reduceMotion { return 0 }
        return Double(max(0, min(steps ?? 0, target)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Goal \(target.formatted())").foregroundStyle(ZoopStyle.secondary)
                Spacer()
                // Keep the symbol mounted so its animation starts after layout.
                Image(systemName: "checkmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ZoopStyle.favourable)
                    .opacity(reached && (pendingKey == nil || reduceMotion) ? 1 : 0)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : celebration)
            }.font(.caption)
            if steps != nil {
                ProgressView(value: progress, total: Double(max(1, target)))
                    .tint(reached ? ZoopStyle.favourable : ZoopStyle.steps)
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            guard let viewport = proxy.bounds(of: .scrollView) else { return false }
            return viewport.contains(CGRect(origin: .zero, size: proxy.size))
        } action: { visible = $0 }
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
        .task(id: presentationKey) {
            guard let key = presentationKey else { return }
            do { try await Task.sleep(for: Self.entranceDelay) } catch { return }
            guard presentationKey == key, !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.65)) {
                if completion.claimCelebration(key) { celebration += 1 }
            }
        }
        .sensoryFeedback(.success, trigger: celebration)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily steps goal")
        .accessibilityValue(steps.map { "\($0.formatted()) of \(target.formatted()) steps\(reached ? ", goal reached" : "")" } ?? "\(target.formatted()) steps. No step data yet.")
        .accessibilityIdentifier("cutStepsProgress")
        // A simulator-only observable marker lets UI tests verify the trigger,
        // without pretending that a simulator can prove a physical haptic.
        .background {
            #if targetEnvironment(simulator)
            if celebration > 0 {
                Color.clear.accessibilityLabel("Goal celebration played")
                    .accessibilityIdentifier("stepGoalCelebrationPlayed")
            }
            #endif
        }
    }
}
