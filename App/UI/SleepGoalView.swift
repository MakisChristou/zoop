import SwiftUI

struct SleepGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SleepGoal.storageKey) private var minutes = SleepGoal.defaultMinutes

    var body: some View {
        NavigationStack {
            Picker("Sleep goal", selection: $minutes) {
                ForEach(SleepGoal.choices, id: \.self) { value in
                    Text(SleepGoal(minutes: value).title).tag(value)
                }
            }
            .pickerStyle(.wheel)
            .accessibilityIdentifier("sleepGoalPicker")
            .frame(maxWidth: 380)
            .padding(.horizontal, ZoopStyle.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zoopScreen()
            .navigationTitle("Sleep goal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { minutes = SleepGoal(minutes: minutes).minutes }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(ZoopStyle.background)
    }
}
