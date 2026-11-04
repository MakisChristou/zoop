import SwiftUI

/// First-run wizard. Explains Bluetooth before iOS asks for it, gets the strap connected,
/// and collects the server details. Runs once; revisit anything from Settings.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @AppStorage(Settings.serverURLKey) private var serverURL = ""
    @AppStorage(Settings.ingestTokenKey) private var ingestToken = ""

    private let pageCount = 6

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                bluetooth.tag(1)
                prepare.tag(2)
                connect.tag(3)
                server.tag(4)
                done.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            ProgressView(value: Double(page + 1), total: Double(pageCount))
                .padding(.horizontal, 40)
                .padding(.bottom, 8)

            HStack {
                if page > 0 {
                    Button("Back") { page -= 1 }
                }
                Spacer()
                Button(page == pageCount - 1 ? "Start" : "Continue") { advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func advance() {
        switch page {
        case 1: model.startStrap()
        case pageCount - 1: model.isOnboarded = true; return
        default: break
        }
        page += 1
    }

    private var canAdvance: Bool {
        switch page {
        case 4: serverURL.isEmpty || URL(string: serverURL) != nil
        default: true
        }
    }

    // MARK: - Pages

    private var welcome: some View {
        Page(symbol: "waveform.path.ecg", title: "Your strap, your data",
             body: "snoop reads your WHOOP 5.0 or MG directly over Bluetooth and sends the raw data to a server you run. No WHOOP account, no WHOOP cloud, no subscription.")
    }

    private var bluetooth: some View {
        Page(symbol: "antenna.radiowaves.left.and.right", title: "Bluetooth, locally",
             body: "Next, iOS will ask for Bluetooth access. snoop uses it only to talk to the strap. The strap already trusts this phone because the official app paired it, so there is no pairing step.")
    }

    private var prepare: some View {
        Page(symbol: "xmark.app", title: "Close the official app",
             body: "The strap talks to one app at a time. Swipe the WHOOP app away in the app switcher. Do not unpair the strap. Then put it on your wrist and keep it within a metre.")
    }

    private var connect: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 2).frame(width: 160, height: 160)
                if model.strap.state == .ready {
                    Image(systemName: "checkmark").font(.system(size: 64, weight: .semibold)).foregroundStyle(.green)
                } else {
                    ProgressView().controlSize(.large)
                }
            }
            Text(model.strap.state == .ready ? "Found your strap" : "Looking for your strap")
                .font(.title2.weight(.semibold))
            Text(connectDetail)
                .multilineTextAlignment(.center)
                .foregroundStyle(SnoopStyle.secondary)
                .padding(.horizontal, 32)
            if model.strap.state != .ready {
                Button("Try again") { model.strap.connect() }
            }
            Spacer()
        }
    }

    private var connectDetail: String {
        switch model.strap.state {
        case .ready:
            var parts: [String] = []
            if !model.strap.serial.isEmpty { parts.append("WHOOP \(model.strap.model) · \(model.strap.serial)") }
            if let battery = model.strap.batteryPercent { parts.append("Battery \(Int(battery)) %") }
            return parts.joined(separator: "\n")
        case .bluetoothOff:
            return "Bluetooth is off. Turn it on in Control Centre."
        case let .failed(reason):
            return "Could not connect: \(reason)"
        default:
            return "Keep your WHOOP nearby and close the WHOOP app."
        }
    }

    private var server: some View {
        Form {
            Section {
                TextField("Server URL", text: $serverURL, prompt: Text("http://192.168.1.10:8471"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Bearer token", text: $ingestToken)
            } header: {
                Text("Your snoop-api server")
            } footer: {
                Text("A server syncs and analyses your recordings. Until then, recordings stay on this iPhone.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var done: some View {
        Page(symbol: "checkmark.seal", title: "All set",
             body: "Wear your WHOOP tonight. Your sleep analysis will appear after syncing.")
    }
}

private struct Page: View {
    let symbol: String
    let title: String
    let text: String

    init(symbol: String, title: String, body: String) {
        self.symbol = symbol
        self.title = title
        text = body
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 64)).foregroundStyle(.tint)
            Text(title).font(.title.weight(.semibold))
            Text(text).multilineTextAlignment(.center).foregroundStyle(SnoopStyle.secondary).padding(.horizontal, 32)
            Spacer()
        }
    }
}
