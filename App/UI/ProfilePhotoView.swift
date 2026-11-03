import PhotosUI
import SwiftUI

struct ProfilePhotoView: View {
    let scope: ProfilePhotoStore.Scope
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: PhotosPickerItem?
    @State private var draft: Data?
    @State private var choosing = false
    @State private var preparing = false
    @State private var working = false
    @State private var error: String?
    @State private var confirmRemoval = false
    private var current: UIImage? { model.photo.image(for: scope) }
    private var valid: Bool { scope.device == model.strap.serial && scope.connection == Settings.connectionID }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Group {
                        if let image = draft.flatMap(UIImage.init(data:)) ?? current {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "person").font(.system(size: 64)).frame(maxWidth: .infinity, maxHeight: .infinity).background(SnoopStyle.surface)
                        }
                    }.frame(width: 180, height: 180).clipShape(Circle()).accessibilityLabel("Profile photo preview")
                    Button(draft == nil && current == nil ? "Choose photo" : "Choose another photo") { choosing = true }
                        .frame(minHeight: 44).accessibilityIdentifier("chooseProfilePhoto")
                    if preparing { ProgressView("Preparing photo…") }
                    if let error { Text(error).font(.subheadline).foregroundStyle(SnoopStyle.unfavourable) }
                    if !valid { Text("Your profile changed. Close this screen and try again.").font(.subheadline) }
                    if draft != nil {
                        Button { Task { await save(remove: false) } } label: {
                            HStack { if working { ProgressView() }; Text(working ? "Saving…" : "Save photo").font(.headline) }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("saveProfilePhoto")
                    }
                    if current != nil {
                        Button("Remove photo", role: .destructive) { confirmRemoval = true }.frame(minHeight: 44)
                    }
                    Text("Synced with your Snoop profile.").font(.footnote).foregroundStyle(SnoopStyle.secondary)
                }.padding(SnoopStyle.gutter).disabled(working || preparing || !valid)
            }.snoopScreen().tint(SnoopStyle.load)
            .navigationTitle("Profile photo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(working).accessibilityIdentifier("closeProfilePhoto") } }
            .photosPicker(isPresented: $choosing, selection: $selected, matching: .images)
            .task(id: selected) {
                guard let selected else { return }
                preparing = true; error = nil
                do {
                    guard let photo = try await selected.loadTransferable(type: PickedProfilePhoto.self) else { throw ProfilePhotoEncoding.Failure.invalid }
                    try Task.checkCancellation(); draft = photo.jpeg
                } catch { if !Task.isCancelled { self.error = "Couldn’t open this photo. Choose another image." } }
                if !Task.isCancelled { preparing = false }
            }
            .confirmationDialog("Remove your profile photo?", isPresented: $confirmRemoval) {
                Button("Remove photo", role: .destructive) { Task { await save(remove: true) } }.accessibilityIdentifier("confirmRemoveProfilePhoto")
            }
            .interactiveDismissDisabled(working)
        }
    }
    private func save(remove: Bool) async {
        guard valid, !working, remove || draft != nil else { return }
        working = true; error = nil
        do { try await model.photo.save(remove ? nil : draft, for: scope); dismiss() }
        catch { self.error = "Couldn’t save your photo. Try again." }
        working = false
    }
}
