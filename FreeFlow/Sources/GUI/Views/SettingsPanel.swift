import SwiftUI

/// Settings panel — accessible via Cmd+, or the Settings sidebar
struct SettingsPanel: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            networkSettings.tag(0).tabItem { Label("Network", systemImage: "network") }
            securitySettings.tag(1).tabItem { Label("Security", systemImage: "lock.shield") }
            advancedSettings.tag(2).tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .padding()
        .onDisappear {
            state.saveSettings()
        }
    }

    private var networkSettings: some View {
        Form {
            Section("DNS Resolver") {
                TextField("Resolver IP", text: $state.resolverAddress)
                    .font(.system(.body, design: .monospaced))
                Toggle("Use DNS-over-HTTPS", isOn: $state.useDNSOverHTTPS)
            }

            Section("Oracle") {
                TextField("Domain", text: $state.oracleDomain)
                    .font(.system(.body, design: .monospaced))
                LabeledContent("Oracle Public Key") {
                    TextEditor(text: $state.oraclePublicKeyHex)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 40)
                }
            }

            Section("DGA") {
                LabeledContent("Bootstrap Seed") {
                    TextEditor(text: $state.bootstrapSeedHex)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 40)
                }
            }

            Section("Transport") {
                Picker("Mode", selection: $state.useRelayHTTP) {
                    Text("DNS AAAA (covert)").tag(false)
                    Text("HTTP Relay (faster)").tag(true)
                }
                if state.useRelayHTTP {
                    TextField("Relay URL", text: $state.relayURL)
                        .font(.system(.body, design: .monospaced))
                    TextField("API Key", text: $state.relayAPIKey)
                        .font(.system(.body, design: .monospaced))
                    Toggle("Allow insecure HTTP (no TLS)", isOn: $state.relayAllowInsecure)
                    if state.relayAllowInsecure {
                        Text("WARNING: Traffic will not be encrypted in transit. Only use on trusted networks or for testing.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            Section("Connection") {
                Toggle("Auto-reconnect", isOn: $state.autoReconnect)
            }
        }
    }

    private var securitySettings: some View {
        Form {
            Section("Encryption") {
                InfoRow(label: "Key Agreement", value: "X25519 ECDH")
                InfoRow(label: "Symmetric Cipher", value: "ChaCha20-Poly1305")
                InfoRow(label: "Key Derivation", value: "HKDF-SHA256")
                InfoRow(label: "Signatures", value: "Ed25519")
                InfoRow(label: "Session Tokens", value: "HMAC-SHA256 rotating")
            }

            Section("Privacy") {
                InfoRow(label: "Steganography", value: "Lexical (natural domain names)")
                InfoRow(label: "DNS Transport", value: "AAAA records (IPv6)")
                InfoRow(label: "CDN Masquerade", value: "Cloudflare/Google/AWS prefixes")
                InfoRow(label: "Token Linkability", value: "None (per-query rotation)")
            }

            if let id = state.identity {
                Section("Your Keys") {
                    InfoRow(label: "Fingerprint", value: id.fingerprintHex)
                    LabeledContent("Public Key") {
                        Text(id.publicKey.map { String(format: "%02x", $0) }.joined())
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var advancedSettings: some View {
        Form {
            Section("Rate Limiting") {
                HStack {
                    Text("Query interval")
                    Spacer()
                    TextField("", value: $state.queryInterval, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text("sec")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Daily budget")
                    Spacer()
                    TextField("", value: $state.dailyBudget, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text("queries")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                LabeledContent("Data Directory") {
                    Text(state.dataDir.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                Button("Open Data Directory") {
                    NSWorkspace.shared.open(state.dataDir)
                }

                Button("Export Identity", role: .none) {
                    // Export to clipboard
                    if let id = state.identity {
                        let export = [
                            "name": id.displayName,
                            "fingerprint": id.fingerprintHex,
                            "publicKey": id.publicKey.map { String(format: "%02x", $0) }.joined()
                        ]
                        if let json = try? JSONSerialization.data(withJSONObject: export, options: .prettyPrinted),
                           let str = String(data: json, encoding: .utf8) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(str, forType: .string)
                        }
                    }
                }
            }

            Section("Developer") {
                Toggle("Dev Mode (log all queries)", isOn: $state.devMode)
                if state.devMode {
                    Text("Every DNS query and response will be logged in Connection → Dev Query Log tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                InfoRow(label: "Version", value: "1.0.0")
                InfoRow(label: "Protocol", value: "FreeFlow v2")
                InfoRow(label: "Transport", value: state.useRelayHTTP ? "HTTP Relay" : "DNS AAAA")
            }
        }
    }
}
