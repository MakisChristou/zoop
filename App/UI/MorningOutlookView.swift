import SwiftUI

/// The same neutral headline card on Today and in the comparison detail.
struct MorningOutlookView: View {
    let insights: MorningInsights
    var showsChanges = true
    var showsDisclosure = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 38

    var body: some View {
        if insights.isLearning { learning } else { assessed }
    }

    private var learning: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Morning outlook").font(.subheadline.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
                    Text("Learning").font(.title2.weight(.semibold)).accessibilityIdentifier("morningOutlookStatus")
                }
                Spacer(minLength: 0)
                if showsDisclosure {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(SnoopStyle.secondary).padding(.top, 6).accessibilityHidden(true)
                }
            }
            if let outlook = insights.outlook, outlook.baselineRequired > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(outlook.baselineCount) of \(outlook.baselineRequired) nights")
                        .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                    ProgressView(value: Double(min(outlook.baselineCount, outlook.baselineRequired)), total: Double(outlook.baselineRequired))
                        .tint(SnoopStyle.secondary).accessibilityHidden(true)
                }
            } else {
                Text("Building your personal comparison").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).snoopCard(padding: 20)
    }

    private var assessed: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Morning outlook").font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if !typeSize.isAccessibilitySize { Image(systemName: "sun.horizon").accessibilityHidden(true) }
                }.foregroundStyle(SnoopStyle.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(insights.outlookTitle)
                        .font(.system(size: headlineSize, weight: .bold))
                        .foregroundStyle(InsightTone.color(insights.outlook?.state))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("morningOutlookStatus")
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: insights.outlookSymbol)
                            .font(.title2).foregroundStyle(SnoopStyle.secondary).accessibilityHidden(true)
                    }
                }
                Text(insights.outlookSubtitle).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !typeSize.isAccessibilitySize, let level = insights.outlook?.level, (1...5).contains(level) {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { index in
                            Capsule().fill(index <= level ? SnoopStyle.secondary : SnoopStyle.track).frame(height: 5)
                        }
                    }
                    HStack {
                        Text("Low"); Spacer(); Text("Usual"); Spacer(); Text("Strong")
                    }.font(.caption2).foregroundStyle(SnoopStyle.secondary)
                }.accessibilityHidden(true)
            }
            if showsChanges {
                let layout = typeSize >= .xxxLarge
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                layout {
                    ForEach(insights.metrics) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.key == "resting_hr" ? "Resting HR" : metric.title)
                                .font(.caption).foregroundStyle(SnoopStyle.secondary)
                            Text(metric.deltaText).font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(InsightTone.color(metric.comparison?.signal))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(metric.title), \(metric.deltaText), \(metric.comparison == nil ? metric.status : metric.comparison?.signal == nil ? "early comparison" : "compared with your usual")")
                    }
                }
            }
            if showsDisclosure {
                HStack {
                    Text(insights.comparisonCaption).font(.caption)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }.foregroundStyle(SnoopStyle.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .snoopCard(padding: 20)
    }
}
