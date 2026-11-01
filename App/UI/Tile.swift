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
    var color = SnoopStyle.secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(SnoopStyle.secondary)
                Spacer()
                if linked {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
                }
            }
            MetricValue(value, unit: unit, size: 28)
            Text(caption).font(.caption).foregroundStyle(SnoopStyle.secondary)
            Sparkline(values: history, color: color)
                .frame(height: 22)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .snoopCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value) \(unit), \(caption)")
    }
}

/// Fourteen-day context under a tile. Draws nothing until there are two points.
struct Sparkline: View {
    let values: [Double]
    var color = SnoopStyle.secondary

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
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            } else {
                Text(values.isEmpty ? " " : "1 day").font(.caption2).foregroundStyle(.quaternary)
            }
        }
    }
}
