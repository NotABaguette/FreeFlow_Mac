import SwiftUI

/// Identity creation and display
struct IdentityPanel: View {
    @EnvironmentObject var state: AppState
    @State private var newName = ""
    @State private var showCopied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let id = state.identity {
                    // Existing identity
                    GroupBox {
                        VStack(spacing: 16) {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(.blue.gradient)
                                    .frame(width: 80, height: 80)
                                Text(String(id.displayName.prefix(1)).uppercased())
                                    .font(.system(size: 36, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .fontWeight(.bold)
                            }

                            Text(id.displayName)
                                .font(.system(.title, design: .monospaced))
                                .fontWeight(.bold)

                            VStack(spacing: 8) {
                                IdentityField(label: "Fingerprint", value: id.fingerprintHex, mono: true)

                                IdentityField(
                                    label: "Public Key",
                                    value: id.publicKey.map { String(format: "%02x", $0) }.joined(),
                                    mono: true
                                )
                            }

                            HStack {
                                Button {
                                    let pk = id.publicKey.map { String(format: "%02x", $0) }.joined()
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(pk, forType: .string)
                                    showCopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopied = false }
                                } label: {
                                    Label(showCopied ? "Copied!" : "Copy Public Key", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                    } label: {
                        Label("Your Identity", systemImage: "person.crop.circle.fill")
                    }

                    // Crypto info
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            InfoRow(label: "Key Type", value: "X25519 (Curve25519)")
                            InfoRow(label: "Key Size", value: "256 bits")
                            InfoRow(label: "Fingerprint", value: "SHA-256(pubkey)[0:8]")
                            InfoRow(label: "E2E Cipher", value: "ChaCha20-Poly1305")
                            InfoRow(label: "Key Exchange", value: "ECDH + HKDF-SHA256")
                            InfoRow(label: "Signatures", value: "Ed25519")
                        }
                    } label: {
                        Label("Cryptographic Details", systemImage: "lock.shield")
                    }

                    // Storage info
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            InfoRow(label: "Data Directory", value: state.dataDir.path)
                            InfoRow(label: "Identity File", value: "identity.json")
                            InfoRow(label: "Contacts File", value: "contacts.json")
                            InfoRow(label: "Messages File", value: "conversations.json")
                        }
                    } label: {
                        Label("Storage", systemImage: "folder")
                    }

                } else {
                    // No identity — create one
                    GroupBox {
                        VStack(spacing: 20) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 60))
                                .foregroundStyle(.blue)

                            Text("Create Your Identity")
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.bold)

                            Text("Generate an X25519 key pair for encrypted messaging. Your private key stays on this device.")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            TextField("Your name", text: $newName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: 300)

                            Button {
                                let name = newName.isEmpty ? "Anonymous" : newName
                                state.createIdentity(name: name)
                            } label: {
                                Label("Generate Identity", systemImage: "key")
                                    .frame(maxWidth: 200)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .padding(30)
                    }
                }
            }
            .padding()
        }
    }
}

struct IdentityField: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(mono ? .caption : .body, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .background(.quaternary.opacity(0.3))
                .cornerRadius(4)
        }
    }
}
