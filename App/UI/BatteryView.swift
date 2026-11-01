import Combine
import SnoopBattery
import SwiftUI
import UserNotifications

struct BatteryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView {
                    VStack(spacing: 20) {
                        batteries(now: context.date)
                        if model.battery.authorization == .denied {
                            Button("Notifications off · Settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary).frame(minHeight: 44)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Battery")
            .mainScreenChrome()
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await model.battery.refreshAuthorization()
                model.strap.requestBattery()
            }
            .onReceive(refresh) { _ in
                if scenePhase == .active { model.strap.requestBattery() }
            }
        }
    }

    private func batteries(now: Date) -> some View {
        let state = model.battery.state
        let current = model.strap.state == .ready && state.isFresh(at: now)
        let charging = current && state.chargingStatus(at: now) == true
        let full = current && state.percent == 100
        let transferring = charging && !full
        let inferred = charging && state.chargingEvidence == .risingLevel
        let strapColor = current ? BatteryColors.level(state.percent) : .secondary
        let pack = model.battery.pack
        let packCurrent = model.strap.state == .ready && pack.isLive(at: now)
        let packCharging = packCurrent && pack.flow == .charging && pack.percent != 100
        let packSupplying = packCurrent && !packCharging && (transferring || pack.flow == .discharging)
        let packColor = packCurrent ? BatteryColors.level(pack.percent) : .secondary
        let packStatus = pack.percent == nil ? "Waiting for pack" : pack.present == false ? "Detached"
            : !packCurrent ? "Last reading" : packCharging ? "Charging"
            : packSupplying ? "Supplying power" : pack.percent == 100 ? "Fully charged"
            : (pack.percent ?? 100) <= 20 ? "Low battery" : "Attached"
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 20))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 4))

        return VStack(spacing: 20) {
            layout {
                VStack(spacing: 12) {
                    Text("Battery pack").font(.subheadline.weight(.semibold))
                    BatteryGauge(percent: pack.percent, flow: packCharging ? .receiving : packSupplying ? .supplying : .none, color: packColor)
                        .frame(maxWidth: 180)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Battery pack")
                        .accessibilityValue(pack.percent.map { "\(Int($0.rounded(.down))) percent. \(packStatus)" } ?? "Waiting for pack")
                    Text(packStatus)
                        .font(.caption).foregroundStyle(packColor)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                BatteryPowerFlow(active: transferring)
                    .rotationEffect(.degrees(dynamicTypeSize.isAccessibilitySize ? 90 : 0))
                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 0 : 78)

                VStack(spacing: 12) {
                    Text("WHOOP").font(.subheadline.weight(.semibold))
                    BatteryGauge(percent: state.percent, flow: transferring ? .receiving : .none, color: strapColor)
                        .frame(maxWidth: 180)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("WHOOP battery")
                        .accessibilityValue(state.percent.map { "\(Int($0.rounded(.down))) percent\(full ? ", fully charged" : charging ? ", charging" : "")\(current ? "" : ", last known reading")" } ?? "Not available")
                    Text(full ? "Fully charged" : charging ? (inferred ? "Charging · estimated" : "Charging") : !current ? "Last reading" : (state.percent ?? 100) <= 5 ? "Critical" : (state.percent ?? 100) <= 20 ? "Low battery" : "")
                        .font(.caption).foregroundStyle(strapColor)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            if !current, let at = state.levelAt {
                Text("Updated \(at.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(20)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }
}
