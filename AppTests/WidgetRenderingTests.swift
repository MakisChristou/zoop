import SwiftUI
import WidgetKit
import XCTest

@MainActor final class WidgetRenderingTests: XCTestCase {
    func testWidgetsRenderAtHomeScreenSizes() throws {
        let variants: [(ZoopWidgetKind, WidgetFamily)] = [
            (.today, .systemMedium), (.recovery, .systemSmall), (.weight, .systemMedium),
            (.steps, .systemSmall), (.everyDay, .systemMedium), (.recovery, .systemMedium)
        ]
        for (kind, family) in variants {
            XCTAssertTrue(kind.families.contains(family))
            let width: CGFloat = family == .systemSmall ? 158 : 338
            let panel = ZoopWidgetPanel(kind: kind, entry: .sample, family: family)
                .padding(16).frame(width: width, height: 158)
                .background(Color(white: 0.085)).clipShape(RoundedRectangle(cornerRadius: 20))
            let renderer = ImageRenderer(content: panel)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width)
            let attachment = XCTAttachment(image: image)
            attachment.name = kind == .recovery && family == .systemMedium ? "Daily recovery" : kind.rawValue
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
