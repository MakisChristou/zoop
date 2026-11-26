import SwiftUI
import WidgetKit
import XCTest

@MainActor final class WidgetRenderingTests: XCTestCase {
    func testWidgetsRenderAtHomeScreenSizes() throws {
        for kind in [ZoopWidgetKind.today, .recovery, .weight, .steps] {
            let width: CGFloat = kind.family == .systemSmall ? 158 : 338
            let panel = ZoopWidgetPanel(kind: kind, entry: .sample)
                .padding(16).frame(width: width, height: 158)
                .background(Color(white: 0.085)).clipShape(RoundedRectangle(cornerRadius: 20))
            let renderer = ImageRenderer(content: panel)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width)
            let attachment = XCTAttachment(image: image)
            attachment.name = kind.rawValue
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
