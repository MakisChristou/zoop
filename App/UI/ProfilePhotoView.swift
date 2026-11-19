import PhotosUI
import SwiftUI

struct ProfilePhotoView: View {
    let scope: ProfilePhotoStore.Scope
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: PhotosPickerItem?
    @State private var draft: Data?
    @State private var preparing = false
    @State private var working = false
    @State private var error: String?
    @State private var confirmRemoval = false

    private var current: UIImage? { model.photo.image(for: scope) }
    private var valid: Bool { scope.device == model.strap.serial && scope.connection == Settings.connectionID }
    private var busy: Bool { preparing || working }
    private var compactHeight: CGFloat { draft != nil || current != nil ? 440 : 370 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    preview.padding(.top, 12)
                    VStack(spacing: 12) {
                        if draft != nil {
                            Button { Task { await save(remove: false) } } label: {
                                HStack(spacing: 8) {
                                    if working { ProgressView() }
                                    Text(working ? "Saving…" : "Save photo")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("saveProfilePhoto")
                            photoPicker.buttonStyle(.bordered).tint(ZoopStyle.text)
                        } else {
                            photoPicker.buttonStyle(.borderedProminent)
                        }
                        if current != nil && draft == nil {
                            Button("Remove photo", role: .destructive) { confirmRemoval = true }
                                .frame(minHeight: 44)
                        }
                    }
                    .controlSize(.large)
                    .buttonBorderShape(.roundedRectangle(radius: ZoopStyle.radius))
                    .disabled(busy || !valid)
                    if preparing { ProgressView("Preparing photo…") }
                    if let error { Text(error).font(.subheadline).foregroundStyle(ZoopStyle.unfavourable) }
                    if !valid { Text("Your profile changed. Close this screen and try again.").font(.subheadline) }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ZoopStyle.gutter)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zoopScreen()
            .tint(ZoopStyle.load)
            .navigationTitle("Profile photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.medium))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .tint(ZoopStyle.text)
                    .disabled(working)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("closeProfilePhoto")
                }
            }
            .task(id: selected) { await prepareSelection() }
            .confirmationDialog("Remove your profile photo?", isPresented: $confirmRemoval) {
                Button("Remove photo", role: .destructive) { Task { await save(remove: true) } }
                    .accessibilityIdentifier("confirmRemoveProfilePhoto")
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(compactHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(ZoopStyle.background)
        .interactiveDismissDisabled(working)
    }

    private var preview: some View {
        Group {
            if let image = draft.flatMap(UIImage.init(data:)) ?? current {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(ZoopStyle.secondary.opacity(0.6), ZoopStyle.surface)
            }
        }
        .frame(width: 144, height: 144)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder((colorScheme == .dark ? Color.white : Color.black).opacity(0.1), lineWidth: 0.5) }
        .accessibilityLabel("Profile photo preview")
    }

    private var photoPicker: some View {
        let title = draft == nil && current == nil ? "Choose photo" : "Choose another photo"
        let foreground = draft == nil ? (colorScheme == .dark ? Color.black : Color.white) : ZoopStyle.text
        return PhotosPicker(selection: $selected, matching: .images) {
            Label(title, systemImage: "photo.on.rectangle")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(foreground)
        }
        .accessibilityIdentifier("chooseProfilePhoto")
    }

    private func prepareSelection() async {
        guard let selected else { return }
        preparing = true
        error = nil
        do {
            guard let photo = try await selected.loadTransferable(type: PickedProfilePhoto.self) else {
                throw ProfilePhotoEncoding.Failure.invalid
            }
            try Task.checkCancellation()
            draft = photo.jpeg
        } catch {
            if !Task.isCancelled { self.error = "Couldn’t open this photo. Choose another image." }
        }
        if !Task.isCancelled { preparing = false }
    }

    private func save(remove: Bool) async {
        guard valid, !working, remove || draft != nil else { return }
        working = true
        error = nil
        do {
            try await model.photo.save(remove ? nil : draft, for: scope)
            dismiss()
        } catch {
            self.error = "Couldn’t save your photo. Try again."
        }
        working = false
    }
}
