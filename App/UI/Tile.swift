import SwiftUI

/// A Today tile: label, headline number, one-line context and a fortnight sparkline.
/// `linked` adds the chevron that tells the reader the tile opens a screen.
struct Tile: View {
    let title: String
    let value: String
    let unit: String
    let caption: String
    let history: [Double]
    var linked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if linked {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
            }
            Text(caption).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            Sparkline(values: history)
                .frame(height: 22)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value) \(unit), \(caption)")
    }
}

/// Fourteen-day context under a tile. Draws nothing until there are two points.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let lo = values.min(), let hi = values.max() {
                let span = max(hi - lo, 0.0001)
                Path { path in
                    for (i, v) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((v - lo) / span))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            } else {
                Text(values.isEmpty ? " " : "1 day").font(.caption2).foregroundStyle(.quaternary)
            }
        }
    }
}
