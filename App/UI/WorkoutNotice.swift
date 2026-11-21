import SwiftUI

/// Undo remains available until dismissed; it does not disappear on a timer.
struct WorkoutNotice: View {
    @Environment(AppModel.self) private var model
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        if let notice = model.activity.notice {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(notice).font(ZoopType.subheadline)
                    Spacer()
                    if let id = model.activity.undoId {
                        Button {
                            Task {
                                saving = true
                                defer { saving = false }
                                do { try await model.activity.undo(device: model.dataDevice, id: id); error = nil }
                                catch { self.error = error.localizedDescription }
                            }
                        } label: {
                            if saving { ProgressView().controlSize(.small) }
                            else { Text("Undo") }
                        }.disabled(saving).frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(saving ? "Restoring workout" : "Undo")
                    }
                    Button { model.activity.dismissNotice(); error = nil } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("Dismiss workout message")
                }
                if let error { Text(error).font(ZoopType.footnote).foregroundStyle(.red) }
                if let error = model.activity.refreshError { Text(error).font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary) }
            }
            .padding(.horizontal, ZoopStyle.gutter)
            .background(ZoopStyle.surface)
        }
    }
}
