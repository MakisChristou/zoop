import SwiftUI

struct SleepNotice: View {
    @Environment(AppModel.self) private var model
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        if let notice = model.sleep.notice {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.sleep.refreshError ?? notice).font(.footnote)
                    Spacer()
                    if let id = model.sleep.undoId {
                        Button("Undo") { Task { saving = true; defer { saving = false }; do { try await model.sleep.undo(device: model.strap.serial, id: id); error = nil } catch { self.error = error.localizedDescription } } }.disabled(saving).frame(minWidth: 44, minHeight: 44)
                    }
                    Button { model.sleep.dismissNotice(); error = nil } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Dismiss message")
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding(.horizontal, ZoopStyle.gutter).background(ZoopStyle.surface)
        }
    }
}
