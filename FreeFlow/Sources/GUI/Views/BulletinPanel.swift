import SwiftUI

/// Signed broadcast bulletins from the Oracle
struct BulletinPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Bulletins")
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                    Text("Ed25519-signed broadcasts from the Oracle")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    state.fetchBulletin()
                } label: {
                    Label("Fetch Latest", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if state.bulletins.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "megaphone")
                        .font(.system(size: 50))
                        .foregroundStyle(.tertiary)
                    Text("No bulletins yet")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Tap \"Fetch Latest\" to check for broadcasts")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(state.bulletins) { bulletin in
                            BulletinCard(bulletin: bulletin)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct BulletinCard: View {
    let bulletin: Bulletin

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BULLETIN #\(bulletin.id)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.orange)

                Spacer()

                if bulletin.verified {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text("Verified")
                            .foregroundColor(.green)
                    }
                    .font(.system(.caption2, design: .monospaced))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.shield")
                            .foregroundColor(.red)
                        Text("Unverified")
                            .foregroundColor(.red)
                    }
                    .font(.system(.caption2, design: .monospaced))
                }

                Text(bulletin.timestamp, style: .relative)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(bulletin.content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            HStack {
                Text("Sig: \(bulletin.signatureHex)...")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(bulletin.timestamp.formatted(.dateTime.month().day().hour().minute()))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(bulletin.verified ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}
