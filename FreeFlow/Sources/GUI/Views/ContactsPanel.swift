import SwiftUI

/// Contact management: add, view, remove contacts
struct ContactsPanel: View {
    @EnvironmentObject var state: AppState
    @State private var showAddSheet = false
    @State private var selectedContact: Contact?

    var body: some View {
        HSplitView {
            // Contact list
            VStack(spacing: 0) {
                HStack {
                    Text("Contacts")
                        .font(.system(.headline, design: .monospaced))
                    Spacer()
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

                if state.contacts.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "person.2")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("No contacts")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button("Add Contact") { showAddSheet = true }
                            .buttonStyle(.bordered)
                        Spacer()
                    }
                } else {
                    List(state.contacts, selection: $selectedContact) { contact in
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
                            VStack(alignment: .leading) {
                                Text(contact.displayName)
                                    .font(.system(.body, design: .monospaced))
                                Text(contact.fingerprintHex)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(contact)
                        .contextMenu {
                            Button("Copy Public Key") {
                                let hex = contact.publicKey.map { String(format: "%02x", $0) }.joined()
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(hex, forType: .string)
                            }
                            Divider()
                            Button("Remove", role: .destructive) {
                                state.removeContact(contact)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 220, maxWidth: 300)

            // Contact detail
            if let contact = selectedContact {
                ContactDetailView(contact: contact)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Select a contact")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddContactSheet()
        }
    }
}

struct ContactDetailView: View {
    @EnvironmentObject var state: AppState
    let contact: Contact

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(.blue.gradient)
                        .frame(width: 80, height: 80)
                    Text(String(contact.displayName.prefix(1)).uppercased())
                        .font(.system(size: 36, design: .monospaced))
                        .foregroundStyle(.white)
                        .fontWeight(.bold)
                }

                Text(contact.displayName)
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        IdentityField(label: "Fingerprint", value: contact.fingerprintHex, mono: true)
                        IdentityField(
                            label: "Public Key",
                            value: contact.publicKey.map { String(format: "%02x", $0) }.joined(),
                            mono: true
                        )
                    }
                } label: {
                    Label("Keys", systemImage: "key")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        let msgs = state.conversations[contact.fingerprintHex] ?? []
                        InfoRow(label: "Messages", value: "\(msgs.count)")
                        InfoRow(label: "Sent", value: "\(msgs.filter { $0.direction == .sent }.count)")
                        InfoRow(label: "Received", value: "\(msgs.filter { $0.direction == .received }.count)")
                        if let last = msgs.last {
                            InfoRow(label: "Last Activity", value: last.timestamp.formatted(.relative(presentation: .named)))
                        }
                    }
                } label: {
                    Label("Statistics", systemImage: "chart.bar")
                }

                HStack {
                    Button(role: .destructive) {
                        state.removeContact(contact)
                    } label: {
                        Label("Remove Contact", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }
}

struct AddContactSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var publicKeyHex = ""
    @State private var errorText = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Contact")
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            VStack(alignment: .leading, spacing: 4) {
                Text("Public Key (hex)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextEditor(text: $publicKeyHex)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 60)
                    .border(.quaternary)
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button("Add") {
                    do {
                        try state.addContact(name: name, publicKeyHex: publicKeyHex.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    } catch {
                        errorText = "Invalid public key. Must be 64 hex characters (32 bytes)."
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || publicKeyHex.count < 64)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
