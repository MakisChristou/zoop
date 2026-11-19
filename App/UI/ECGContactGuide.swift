import SwiftUI

struct ECGContactGuide: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 22) {
            if !typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 48) {
                Label("Finger", systemImage: "minus")
                Label("Thumb", systemImage: "minus")
            }
            .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
            ZStack {
                Rectangle().fill(ZoopStyle.track).frame(width: 72, height: 150)
                RoundedRectangle(cornerRadius: 16).fill(ZoopStyle.background).frame(width: 98, height: 70)
                RoundedRectangle(cornerRadius: 16).stroke(ZoopStyle.secondary, lineWidth: 4).frame(width: 98, height: 70)
                Image(systemName: "waveform.path.ecg").font(.system(size: 24)).foregroundStyle(ZoopStyle.text)
                VStack {
                    Capsule().fill(ZoopStyle.load).frame(width: 28, height: 6)
                    Spacer()
                    Capsule().fill(ZoopStyle.load).frame(width: 28, height: 6)
                }.frame(height: 74)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: ZoopStyle.radius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Touch both metal clasp contacts lightly with your other hand’s thumb and index finger.")
    }
}
