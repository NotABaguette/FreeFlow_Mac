import SwiftUI

/// Chat list + active conversation
struct ChatListView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedContact: Contact?

    var body: some View {
        HSplitView {
            // Conversation list
            VStack(spacing: 0) {
                HStack {
                    Text("Messages")
                        .font(.system(.headline, design: .monospaced))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

                if state.contacts.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("No conversations")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("Add contacts first")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                } else {
                    List(state.contacts, selection: $selectedContact) { contact in
                        ConversationRow(contact: contact)
                            .tag(contact)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 220, maxWidth: 300)

            // Active chat
            if let contact = selectedContact {
                ChatView(contact: contact)
                    .onChange(of: selectedContact) { _, newVal in
                        if let fp = newVal?.fingerprintHex {
                            state.markRead(fp)
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 50))
                        .foregroundStyle(.tertiary)
                    Text("FreeFlow")
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                    Text("Select a conversation")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("End-to-end encrypted via DNS")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct ConversationRow: View {
    @EnvironmentObject var state: AppState
    let contact: Contact

    var body: some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(.blue.gradient)
                    .frame(width: 36, height: 36)
                Text(String(contact.displayName.prefix(1)).uppercased())
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                if let lastMsg = state.conversations[contact.fingerprintHex]?.last {
                    Text(lastMsg.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No messages yet")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let count = state.unreadCounts[contact.fingerprintHex], count > 0 {
                Text("\(count)")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
