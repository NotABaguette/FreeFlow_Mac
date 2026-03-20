import SwiftUI

/// Messenger-style chat view for a single conversation
struct ChatView: View {
    @EnvironmentObject var state: AppState
    let contact: Contact
    @State private var messageText = ""
    @State private var showInfo = false

    private var messages: [ChatMessage] {
        state.conversations[contact.fingerprintHex] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Chat header
            chatHeader

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        // Encryption notice
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("Messages are end-to-end encrypted with X25519 + ChaCha20-Poly1305")
                        }
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)

                        ForEach(messages) { msg in
                            MessageBubble(message: msg, contactName: contact.displayName)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            inputBar
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.blue.gradient)
                    .frame(width: 32, height: 32)
                Text(String(contact.displayName.prefix(1)).uppercased())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(contact.displayName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                Text(contact.fingerprintHex)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showInfo) {
                contactInfoPopover
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1...5)
                .padding(8)
                .background(.quaternary.opacity(0.5))
                .cornerRadius(8)
                .onSubmit {
                    send()
                }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(messageText.isEmpty ? .tertiary : .blue)
            }
            .buttonStyle(.plain)
            .disabled(messageText.isEmpty)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var contactInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contact Info")
                .font(.system(.headline, design: .monospaced))

            LabeledContent("Name") {
                Text(contact.displayName)
                    .font(.system(.body, design: .monospaced))
            }
            LabeledContent("Fingerprint") {
                Text(contact.fingerprintHex)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent("Messages") {
                Text("\(messages.count)")
                    .font(.system(.body, design: .monospaced))
            }
            LabeledContent("Encryption") {
                Text("X25519 + ChaCha20")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func send() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state.sendMessage(text, to: contact)
        messageText = ""
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let contactName: String

    private var isSent: Bool { message.direction == .sent }

    var body: some View {
        HStack {
            if isSent { Spacer(minLength: 60) }

            VStack(alignment: isSent ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isSent ? Color.blue : Color(.controlBackgroundColor))
                    .foregroundStyle(isSent ? .white : .primary)
                    .cornerRadius(16)

                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                    if isSent {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                    }
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
            }

            if !isSent { Spacer(minLength: 60) }
        }
    }

    private var statusIcon: String {
        switch message.status {
        case .sending: return "clock"
        case .sent: return "checkmark"
        case .delivered: return "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        }
    }

    private var statusColor: Color {
        switch message.status {
        case .sending: return .secondary
        case .sent: return .secondary
        case .delivered: return .green
        case .failed: return .red
        }
    }
}
