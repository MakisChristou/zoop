import SwiftUI
import WidgetKit
import XCTest

@MainActor final class WidgetRenderingTests: XCTestCase {
    func testWidgetsRenderAtHomeScreenSizes() throws {
        let variants: [(ZoopWidgetKind, WidgetFamily)] = [
            (.today, .systemMedium), (.recovery, .systemSmall), (.weight, .systemMedium),
            (.stages, .systemMedium), (.metrics, .systemMedium), (.workouts, .systemMedium),
            (.steps, .systemSmall), (.everyDay, .systemMedium), (.recovery, .systemMedium)
        ]
        for (kind, family) in variants {
            XCTAssertTrue(kind.families.contains(family))
            try capture(kind, family, entry: .sample, name: kind == .recovery && family == .systemMedium ? "Daily recovery" : kind.rawValue)
        }
    }

    func testSparseRecoveryAtBothSizes() throws {
        let sample = ZoopWidgetEntry.sample
        let days = WidgetHistory.calendarDays(ending: sample.date, count: 4, calendar: .current)
        for count in [0, 1, 3] {
            var data = sample.data
            data.recovery = Array(zip([days[0], days[2], days[3]], [54, 61, 78]).prefix(count)).map {
                .init(day: $0.0, score: $0.1, band: $0.1 >= 67 ? "high" : "moderate")
            }
            for family in ZoopWidgetKind.recovery.families {
                try capture(.recovery, family, entry: .init(date: sample.date, data: data), name: "Recovery-\(family.rawValue)-\(count)")
            }
        }
    }

    private func capture(_ kind: ZoopWidgetKind, _ family: WidgetFamily, entry: ZoopWidgetEntry, name: String) throws {
        let width: CGFloat = family == .systemSmall ? 158 : 338
        let panel = ZoopWidgetPanel(kind: kind, entry: entry, family: family)
            .padding(16).frame(width: width, height: 158)
            .background(Color(white: 0.085)).clipShape(RoundedRectangle(cornerRadius: 20))
        let renderer = ImageRenderer(content: panel)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, width)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
