import SwiftUI

/// Connection management: connect, ping, sync inbox, DNS cache test, transport toggle, logs
struct ConnectionPanel: View {
    @EnvironmentObject var state: AppState
    @State private var logTab = 0  // 0=connection log, 1=dev query log

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status card
                GroupBox {
                    VStack(spacing: 12) {
                        HStack {
                            Circle()
                                .fill(state.connectionState.color)
                                .frame(width: 12, height: 12)
                            Text(state.connectionState.rawValue)
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.semibold)
                            Spacer()
                            Text(state.useRelayHTTP ? "HTTP Relay" : "DNS Transport")
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(state.useRelayHTTP ? Color.orange.opacity(0.2) : Color.cyan.opacity(0.2))
                                .cornerRadius(4)
                        }

                        HStack(spacing: 20) {
                            StatBox(label: "Queries", value: "\(state.queryCount)")
                            StatBox(label: "Latency", value: state.pingLatency > 0 ? "\(Int(state.pingLatency))ms" : "—")
                            StatBox(label: "Session", value: state.sessionActive ? "Active" : "None")
                            if let time = state.serverTime {
                                StatBox(label: "Server Time", value: time.formatted(.dateTime.hour().minute().second()))
                            }
                        }
                    }
                } label: {
                    Label("Status", systemImage: "antenna.radiowaves.left.and.right")
                }

                // Actions
                GroupBox {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Button {
                                if state.connectionState == .connected {
                                    state.disconnect()
                                } else {
                                    state.connect()
                                }
                            } label: {
                                Label(
                                    state.connectionState == .connected ? "Disconnect" : "Connect",
                                    systemImage: state.connectionState == .connected ? "xmark.circle" : "bolt.circle"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                            .buttonStyle(.borderedProminent)
                            .tint(state.connectionState == .connected ? .red : .blue)

                            Button {
                                state.ping()
                            } label: {
                                Label("Ping", systemImage: "wave.3.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                            .buttonStyle(.bordered)

                            Button {
                                state.syncInbox()
                            } label: {
                                Label("Sync Inbox", systemImage: "envelope.arrow.triangle.branch")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                            .buttonStyle(.bordered)
                            .disabled(!state.sessionActive)

                            Button {
                                state.testDNSCache()
                            } label: {
                                Label("Cache Test", systemImage: "cylinder")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                            .buttonStyle(.bordered)
                        }

                        // Transport + config
                        HStack {
                            LabeledContent("Resolver") {
                                TextField("8.8.8.8", text: $state.resolverAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 150)
                            }
                            LabeledContent("Domain") {
                                TextField("cdn-static-eu.net", text: $state.oracleDomain)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 180)
                            }
                        }

                        // Transport toggle
                        HStack {
                            Picker("Transport", selection: $state.useRelayHTTP) {
                                Text("DNS AAAA").tag(false)
                                Text("HTTP Relay").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 250)

                            if state.useRelayHTTP {
                                TextField("Relay URL", text: $state.relayURL)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 250)
                            }
                        }
                    }
                } label: {
                    Label("Actions", systemImage: "play.circle")
                }

                // Session info
                if state.sessionActive {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            InfoRow(label: "State", value: "Established")
                            InfoRow(label: "Cipher", value: "ChaCha20-Poly1305")
                            InfoRow(label: "Key Exchange", value: "X25519 ECDH")
                            InfoRow(label: "Key Derivation", value: "HKDF-SHA256")
                            InfoRow(label: "Token Rotation", value: "HMAC-SHA256 per query")
                            InfoRow(label: "Transport", value: state.useRelayHTTP ? "HTTP Relay" : "DNS AAAA (IPv6)")
                        }
                    } label: {
                        Label("Session", systemImage: "lock.fill")
                    }
                }

                // Log tabs
                GroupBox {
                    VStack(spacing: 0) {
                        Picker("Log", selection: $logTab) {
                            Text("Connection Log").tag(0)
                            if state.devMode {
                                Text("Dev Query Log (\(state.devQueryLog.count))").tag(1)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)

                        if logTab == 0 {
                            connectionLogView
                        } else {
                            devQueryLogView
                        }
                    }
                } label: {
                    Label("Logs", systemImage: "text.justify.left")
                }
            }
            .padding()
        }
    }

    private var connectionLogView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(state.connectionLog) { entry in
                        HStack(spacing: 6) {
                            Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                .frame(width: 70, alignment: .leading)
                            Text(entry.level.icon)
                                .foregroundColor(entry.level.color)
                                .frame(width: 14)
                            Text(entry.message)
                                .foregroundColor(entry.level == .info ?
                                    Color(nsColor: .labelColor) : entry.level.color)
                        }
                        .font(.system(.caption, design: .monospaced))
                        .id(entry.id)
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 200, maxHeight: 400)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(6)
            .onChange(of: state.connectionLog.count) { _, _ in
                if let last = state.connectionLog.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var devQueryLogView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(state.devQueryLog) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            Text("[\(entry.transport)]")
                                .foregroundColor(.purple)
                            Text(entry.domain)
                                .foregroundColor(.cyan)
                        }
                        .font(.system(.caption2, design: .monospaced))

                        HStack(spacing: 4) {
                            Text("Q:")
                                .foregroundColor(.orange)
                            Text(entry.query)
                                .foregroundColor(Color(nsColor: .labelColor))
                        }
                        .font(.system(.caption, design: .monospaced))

                        HStack(spacing: 4) {
                            Text("R:")
                                .foregroundColor(.green)
                            Text(entry.response)
                                .foregroundColor(Color(nsColor: .labelColor))
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                }
            }
            .padding(8)
        }
        .frame(minHeight: 200, maxHeight: 400)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

struct StatBox: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.green)
        }
    }
}
