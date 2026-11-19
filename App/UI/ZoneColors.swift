import SwiftUI

/// Five heart-rate zones, lowest first, in a cool-to-hot ramp shared by every chart.
enum ZoneColors {
    static let all: [Color] = [ZoopStyle.secondary, ZoopStyle.load, ZoopStyle.favourable, ZoopStyle.typical, ZoopStyle.unfavourable]

    static func color(_ zone: Int) -> Color {
        all[min(max(zone, 0), all.count - 1)]
    }

    static func label(_ zone: Int) -> String {
        ["50–60 %", "60–70 %", "70–80 %", "80–90 %", "90–100 %"][min(max(zone, 0), 4)]
    }
}
