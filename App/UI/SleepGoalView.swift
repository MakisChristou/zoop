import SwiftUI

struct SleepGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var minutes = SleepGoal.defaultMinutes
    @State private var initialized: SleepGoalStore.Scope?
    private var scope: SleepGoalStore.Scope { .init(device: model.dataDevice, connection: Settings.connectionID) }

    var body: some View {
        NavigationStack {
            VStack {
                if model.sleepGoal.loading { ZoopLoadingBar(label: "Loading sleep goal") }
                Picker("Sleep goal", selection: $minutes) {
                    ForEach(SleepGoal.choices, id: \.self) { value in
                        Text(SleepGoal(minutes: value).title).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .accessibilityIdentifier("sleepGoalPicker")
                .disabled(model.sleepGoal.loading || model.sleepGoal.value(for: scope) == nil)
                if let error = model.sleepGoal.error {
                    Text(error).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                    if model.sleepGoal.value(for: scope) == nil {
                        Button("Retry") { Task { await load() } }
                    }
                }
            }
            .frame(maxWidth: 380)
            .padding(.horizontal, ZoopStyle.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zoopScreen()
            .navigationTitle("Sleep goal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            let expected = scope
                            if await model.sleepGoal.save(minutes, scope: expected, isCurrent: { scope == expected }) { dismiss() }
                        }
                    }.disabled(model.sleepGoal.loading || model.sleepGoal.value(for: scope) == nil)
                }
            }
            .task(id: scope) { await load() }
            .onChange(of: model.sleepGoal.loading) { _, loading in
                if !loading, initialized != scope, let goal = model.sleepGoal.value(for: scope) {
                    minutes = goal.minutes; initialized = scope
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(ZoopStyle.background)
    }
    private func load() async {
        let expected = scope
        await model.sleepGoal.load(expected) { scope == expected }
        if scope == expected, let goal = model.sleepGoal.value(for: expected) { minutes = goal.minutes; initialized = expected }
    }
}
