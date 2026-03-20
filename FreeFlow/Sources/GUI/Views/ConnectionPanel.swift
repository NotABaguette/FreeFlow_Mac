import SwiftUI

/// Connection management: connect, ping, DNS cache test, session info, live log
struct ConnectionPanel: View {
    @EnvironmentObject var state: AppState

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
                        HStack(spacing: 10) {
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
                                state.testDNSCache()
                            } label: {
                                Label("Cache Test", systemImage: "cylinder")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                            .buttonStyle(.bordered)
                        }

                        // Connection config
                        HStack {
                            LabeledContent("Resolver") {
                                TextField("8.8.8.8", text: $state.resolverAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 180)
                            }
                            LabeledContent("Domain") {
                                TextField("cdn-static-eu.net", text: $state.oracleDomain)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 200)
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
                            InfoRow(label: "Transport", value: "DNS AAAA (IPv6)")
                        }
                    } label: {
                        Label("Session", systemImage: "lock.fill")
                    }
                }

                // Connection log
                GroupBox {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(state.connectionLog) { entry in
                                    HStack(spacing: 6) {
                                        Text(entry.timestamp, style: .time)
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 70, alignment: .leading)
                                        Text(entry.level.icon)
                                            .foregroundStyle(entry.level.color)
                                            .frame(width: 14)
                                        Text(entry.message)
                                            .foregroundStyle(entry.level.color.opacity(0.8))
                                    }
                                    .font(.system(.caption, design: .monospaced))
                                    .id(entry.id)
                                }
                            }
                            .padding(8)
                        }
                        .frame(minHeight: 200, maxHeight: 400)
                        .onChange(of: state.connectionLog.count) { _, _ in
                            if let last = state.connectionLog.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .background(.black.opacity(0.3))
                    .cornerRadius(6)
                } label: {
                    Label("Connection Log", systemImage: "text.justify.left")
                }
            }
            .padding()
        }
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
        .background(.quaternary.opacity(0.3))
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
                .foregroundStyle(.green)
        }
    }
}
