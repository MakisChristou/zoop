import SwiftUI

/// A compact assessment with the measurements that explain it.
struct MorningOutlookView: View {
    let insights: MorningInsights
    var showsChanges = true
    var showsDisclosure = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var headlineSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Morning outlook").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 12)
                    if showsDisclosure {
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
                    }
                }.foregroundStyle(SnoopStyle.secondary)
                Text(insights.outlookTitle)
                    .font(.system(size: headlineSize, weight: .semibold))
                    .foregroundStyle(InsightTone.color(insights.outlook?.state))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("morningOutlookStatus")
                // Degree and incomplete-data explanations matter; "Average" already says usual.
                if !insights.isLearning && insights.outlook?.state != "average" {
                    Text(insights.outlookSubtitle).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if insights.isLearning {
                learningProgress
            } else if showsChanges && !insights.metrics.isEmpty {
                comparisons
            }
        }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
    }

    @ViewBuilder private var learningProgress: some View {
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
    }

    private var comparisons: some View {
        let layout = typeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
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
}
