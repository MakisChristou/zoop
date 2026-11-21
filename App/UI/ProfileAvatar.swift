import SwiftUI

struct ProfileAvatar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 44
    private var scope: ProfilePhotoStore.Scope { .init(device: model.dataDevice, connection: Settings.connectionID) }
    var body: some View {
        Group {
            if let image = model.photo.image(for: scope) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person").font(.system(size: size * 0.4, weight: .medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(ZoopStyle.surface)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay { Circle().strokeBorder((colorScheme == .dark ? Color.white : Color.black).opacity(0.1), lineWidth: 0.5) }
        .accessibilityHidden(true)
    }
}
