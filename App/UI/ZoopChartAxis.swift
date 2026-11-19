import Charts
import SwiftUI

/// A shared axis treatment measured from the health dashboard reference.
func zoopChartYAxis(count: Int = 3) -> some AxisContent {
    AxisMarks(position: .leading, values: .automatic(desiredCount: count)) { _ in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(ZoopStyle.chartGrid)
        AxisValueLabel().font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
    }
}

func zoopTimeXAxis(_ dates: [Date]) -> some AxisContent {
    AxisMarks(values: dates) { mark in
        AxisValueLabel(anchor: mark.index == 0 ? .topLeading : mark.index == dates.count - 1 ? .topTrailing : .top) {
            if let date = mark.as(Date.self) {
                Text(date, format: .dateTime.hour().minute()).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
            }
        }
    }
}
