import SwiftUI

/// Shared rendering for real setup and its isolated, sample-only preview.
struct SetupFlowView: View {
    @Bindable var flow: SetupFlow
    let band: SetupBandStatus
    let syncing: Bool
    var close: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showPassword = false
    @State private var showServerHelp = false
    @State private var showPairingHelp = false
    @FocusState private var field: Field?
    private enum Field { case server, email, password }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        content
                    }
                    .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 20)
                    .frame(maxWidth: 520)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("setupScroll")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .zoopScreen()
        .sheet(isPresented: $showServerHelp) { serverHelp }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Button { field = nil; flow.back() } label: {
                    Image(systemName: "arrow.left").font(.system(size: 22))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier("setupBack")
                .opacity(flow.step == .welcome ? 0 : 1)
                .disabled(flow.step == .welcome || flow.busy)
                .accessibilityHidden(flow.step == .welcome)
                Spacer()
                VStack(spacing: 2) {
                    Text("zoop").font(ZoopType.font(size: 25, weight: .semibold, relativeTo: .title2)).tracking(-1.5)
                    if flow.mode == .preview {
                        Text("Preview").font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                    }
                }
                Spacer()
                if let close {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 17)).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Close preview").accessibilityIdentifier("closeSetupPreview")
                } else { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }
            }
            HStack(spacing: 6) {
                ForEach(SetupFlow.Step.allCases, id: \.rawValue) { step in
                    Capsule().fill(step == flow.step ? ZoopStyle.text : ZoopStyle.separator)
                        .frame(width: 36, height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setup, step \(flow.step.rawValue + 1) of 4")
        }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .welcome: welcome
        case .server: server
        case .band: connect
        case .ready: ready
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(ZoopType.font(size: 32, weight: .semibold, relativeTo: .largeTitle))
            .tracking(-0.8).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var welcome: some View {
        VStack(spacing: 32) {
            heading("Your WHOOP.\nYour data.").multilineTextAlignment(.center)
            Spacer(minLength: 0)
            SetupRings().frame(height: textSize.isAccessibilitySize ? 160 : 230)
            Spacer(minLength: 0)
            Text("Sleep, recovery and activity.\nStored on your server.")
                .foregroundStyle(ZoopStyle.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var server: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                heading("Your server")
                Text(flow.signedIn ? "You’re signed in." : "Sign in to your Zoop instance.")
                    .foregroundStyle(ZoopStyle.secondary)
            }
            if flow.signedIn {
                statusRow("Server", detail: flow.server, symbol: "server.rack", connected: true)
            } else {
                VStack(spacing: 12) {
                    input("Server address") {
                        TextField("https://zoop.example.com", text: $flow.server)
                            .keyboardType(.URL).textContentType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($field, equals: .server).submitLabel(.next)
                            .onSubmit { field = .email }.accessibilityLabel("Server address").accessibilityIdentifier("setupServer")
                    }
                    input("Email") {
                        TextField("you@example.com", text: $flow.email)
                            .keyboardType(.emailAddress).textContentType(.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($field, equals: .email).submitLabel(.next)
                            .onSubmit { field = .password }.accessibilityLabel("Email").accessibilityIdentifier("setupEmail")
                    }
                    input("Password") {
                        HStack {
                            Group {
                                if showPassword { TextField("Password", text: $flow.password) }
                                else { SecureField("Password", text: $flow.password) }
                            }
                            .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($field, equals: .password).submitLabel(.go)
                            .onSubmit { signIn() }.accessibilityLabel("Password").accessibilityIdentifier("setupPassword")
                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye").frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(showPassword ? "Hide password" : "Show password")
                        }
                    }
                }.disabled(flow.busy || flow.mode == .preview)
            }
            if flow.server.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http://") {
                Text("HTTP is unencrypted. Use a trusted network or VPN.")
                    .font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
            }
            if let error = flow.error {
                Text(error).foregroundStyle(ZoopStyle.unfavourable).accessibilityIdentifier("setupError")
            }
            Button("Need a server?") { showServerHelp = true }
                .font(ZoopType.subheadline).underline().frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
        }
    }

    private func input<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(ZoopType.headline)
            content().foregroundStyle(ZoopStyle.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 76, alignment: .leading)
        .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ZoopStyle.separator, lineWidth: 0.5))
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Connect your\nWHOOP")
            SetupBandIllustration().frame(height: textSize.isAccessibilitySize ? 100 : 160)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Close the WHOOP app. Keep your band nearby.")
                Text("Keep it paired in iPhone Settings.").font(ZoopType.subheadline)
            }
            .foregroundStyle(ZoopStyle.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                Image(systemName: "sensor.tag.radiowaves.forward").font(.system(size: 22))
                Text(band.name).font(ZoopType.headline)
                Spacer()
                if band.isConnected { Image(systemName: "checkmark").foregroundStyle(ZoopStyle.favourable) }
                else if flow.requestedConnection, band == .searching {
                    ProgressView().accessibilityLabel("Looking for your WHOOP")
                } else {
                    Text(flow.mode == .preview ? "Nearby" : "Not connected").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                }
            }.zoopCard(padding: 16)
            if case .blocked(let message) = band {
                Text(message).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
            }
            DisclosureGroup("First time with this band?", isExpanded: $showPairingHelp) {
                Text("Pair it in the WHOOP app first, then close that app. Don’t unpair it.")
                    .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary).padding(.top, 8)
            }.font(ZoopType.footnote)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 28) {
            Image(systemName: "checkmark.circle").font(.system(size: 40, weight: .light))
                .foregroundStyle(ZoopStyle.favourable).accessibilityHidden(true)
            heading(band.isConnected ? "You’re connected" : "You’re signed in")
            VStack(spacing: 0) {
                statusRow("Server", symbol: "server.rack", connected: true)
                Divider().padding(.horizontal, 16)
                statusRow(band.name, symbol: "sensor.tag.radiowaves.forward", connected: band.isConnected)
            }
            .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            if band.isConnected {
                HStack(alignment: .top, spacing: 14) {
                    if syncing { ProgressView().padding(.top, 4).accessibilityLabel("Syncing") }
                    else { Image(systemName: "arrow.triangle.2.circlepath").padding(.top, 4).accessibilityHidden(true) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("First sync").font(ZoopType.headline)
                        Text("Your history will appear as it arrives.").font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).zoopCard(padding: 16)
            }
        }
    }

    private func statusRow(_ title: String, detail: String? = nil, symbol: String, connected: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(ZoopType.headline)
                if let detail { Text(detail).font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary) }
            }
            Spacer()
            if connected { Image(systemName: "checkmark").foregroundStyle(ZoopStyle.favourable).accessibilityLabel("Connected") }
            else { Text("Not connected").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
        }.padding(16)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    if flow.busy { ProgressView().tint(ZoopStyle.background) }
                    Text(primaryTitle).font(ZoopType.font(size: 17, weight: .semibold, relativeTo: .headline))
                }
                .foregroundStyle(ZoopStyle.background)
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(.vertical, 3)
                .background(ZoopStyle.text, in: RoundedRectangle(cornerRadius: 16))
            }
            .id(flow.step)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .buttonStyle(.plain).accessibilityIdentifier("setupPrimary")
            .disabled(flow.busy || (flow.step == .server && !flow.canSignIn))
            .opacity(flow.busy || (flow.step == .server && !flow.canSignIn) ? 0.5 : 1)
            if flow.step == .band {
                Button("Not now") { field = nil; flow.skipBand() }
                    .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                    .frame(minHeight: 44).buttonStyle(.plain).accessibilityIdentifier("setupSkipBand")
            }
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12)
        .frame(maxWidth: 568).frame(maxWidth: .infinity)
        .background(ZoopStyle.background)
    }

    private var primaryTitle: String {
        switch flow.step {
        case .welcome: "Get started"
        case .server: flow.busy ? "Signing in…" : flow.signedIn ? "Continue" : "Sign in"
        case .band: band.isConnected ? "Continue" : flow.requestedConnection ? "Try again" : "Connect"
        case .ready: flow.mode == .preview ? "Finish preview" : "Open Zoop"
        }
    }

    private func signIn() { field = nil; Task { await flow.signIn() } }
    private func primaryAction() {
        field = nil
        switch flow.step {
        case .welcome: flow.begin()
        case .server: signIn()
        case .band: flow.connect(alreadyConnected: band.isConnected)
        case .ready: flow.finish()
        }
    }

    private var serverHelp: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Zoop needs a server to store and analyse your recordings. Run your own with Docker Compose, or ask your administrator for an address and account.")
                Link("Setup guide", destination: URL(string: "https://zoop.health/docs/get-started/")!)
                Spacer()
            }.padding(24).zoopScreen().navigationTitle("Your Zoop server")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showServerHelp = false } } }
        }.presentationDetents([.medium, .large])
    }
}

private struct SetupRings: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                ring("moon", color: ZoopStyle.sleep, size: size * 0.57).offset(y: -size * 0.21)
                ring("heart", color: ZoopStyle.favourable, size: size * 0.57).offset(x: -size * 0.25, y: size * 0.21)
                ring("figure.run", color: ZoopStyle.load, size: size * 0.57).offset(x: size * 0.25, y: size * 0.21)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.accessibilityHidden(true)
    }
    private func ring(_ symbol: String, color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color, lineWidth: 3)
            Image(systemName: symbol).font(.system(size: size * 0.29, weight: .regular)).foregroundStyle(color)
        }.frame(width: size, height: size)
    }
}

private struct SetupBandIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42).stroke(ZoopStyle.secondary, lineWidth: 1.5).frame(width: 76, height: 145)
            RoundedRectangle(cornerRadius: 9).fill(ZoopStyle.surface)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(ZoopStyle.text, lineWidth: 1.5))
                .frame(width: 82, height: 52).offset(y: -12)
            Rectangle().fill(ZoopStyle.secondary.opacity(0.25)).frame(width: 68, height: 3).offset(y: 4)
        }.rotationEffect(.degrees(18))
    }
}
