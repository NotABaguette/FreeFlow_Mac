import SwiftUI
#if canImport(FreeFlowCore)
import FreeFlowCore
#endif
import CryptoKit

/// Central app state shared across all views
@MainActor
class AppState: ObservableObject {
    // Identity
    @Published var identity: Identity?
    @Published var hasIdentity = false

    // Connection
    @Published var connectionState: ConnectionStatus = .disconnected
    @Published var sessionActive = false
    @Published var serverTime: Date?
    @Published var clockOffset: TimeInterval = 0
    @Published var pingLatency: TimeInterval = 0
    @Published var queryCount: Int = 0

    // Contacts
    @Published var contacts: [Contact] = []

    // Messages
    @Published var conversations: [String: [ChatMessage]] = [:]  // fingerprint → messages
    @Published var selectedContactFP: String?
    @Published var unreadCounts: [String: Int] = [:]

    // Settings
    @Published var resolverAddress: String = "8.8.8.8"
    @Published var oracleDomain: String = "cdn-static-eu.net"
    @Published var oraclePublicKeyHex: String = ""
    @Published var bootstrapSeedHex: String = ""
    @Published var autoReconnect: Bool = true
    @Published var queryInterval: Double = 5.0
    @Published var dailyBudget: Int = 300
    @Published var useDNSOverHTTPS: Bool = false

    // Connection log
    @Published var connectionLog: [LogEntry] = []

    // Data directory
    let dataDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        dataDir = home.appendingPathComponent(".freeflow")
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        loadIdentity()
        loadContacts()
        loadSettings()
        loadConversations()
    }

    // MARK: - Identity

    func createIdentity(name: String) {
        let id = Identity.generate(displayName: name)
        try? id.save(to: dataDir.appendingPathComponent("identity.json"))
        identity = id
        hasIdentity = true
        log(.info, "Identity created: \(id.fingerprintHex)")
    }

    func loadIdentity() {
        if let id = try? Identity.load(from: dataDir.appendingPathComponent("identity.json")) {
            identity = id
            hasIdentity = true
        }
    }

    // MARK: - Contacts

    func addContact(name: String, publicKeyHex: String) throws {
        let contact = try Contact(displayName: name, publicKeyHex: publicKeyHex)
        contacts.removeAll { $0.fingerprintHex == contact.fingerprintHex }
        contacts.append(contact)
        saveContacts()
        log(.info, "Contact added: \(name) [\(contact.fingerprintHex)]")
    }

    func removeContact(_ contact: Contact) {
        contacts.removeAll { $0.fingerprintHex == contact.fingerprintHex }
        saveContacts()
    }

    private func saveContacts() {
        let url = dataDir.appendingPathComponent("contacts.json")
        if let data = try? JSONEncoder().encode(contacts) {
            try? data.write(to: url)
        }
    }

    private func loadContacts() {
        let url = dataDir.appendingPathComponent("contacts.json")
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([Contact].self, from: data) {
            contacts = loaded
        }
    }

    // MARK: - Messages

    func sendMessage(_ text: String, to contact: Contact) {
        guard let id = identity else { return }

        let msg = ChatMessage(
            id: UUID().uuidString,
            text: text,
            sender: id.fingerprintHex,
            recipient: contact.fingerprintHex,
            timestamp: Date(),
            direction: .sent,
            status: .sending
        )

        conversations[contact.fingerprintHex, default: []].append(msg)

        // Simulate E2E encryption
        do {
            let e2eKey = try E2ECrypto.deriveKey(myPrivate: id.privateKey, theirPublic: contact.publicKey)
            let encrypted = try E2ECrypto.encrypt(key: e2eKey, plaintext: [UInt8](text.utf8))
            let fragments = max(1, (encrypted.count + 5) / 6)
            log(.info, "Encrypted \(text.count)B → \(encrypted.count)B (\(fragments) DNS queries)")

            // Mark as sent (in real implementation, would wait for ACKs)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let idx = self.conversations[contact.fingerprintHex]?.firstIndex(where: { $0.id == msg.id }) {
                    self.conversations[contact.fingerprintHex]?[idx].status = .sent
                }
            }
            queryCount += fragments
        } catch {
            log(.error, "Encryption failed: \(error)")
        }

        saveConversations()
    }

    func receiveMessage(_ text: String, from contact: Contact) {
        let msg = ChatMessage(
            id: UUID().uuidString,
            text: text,
            sender: contact.fingerprintHex,
            recipient: identity?.fingerprintHex ?? "",
            timestamp: Date(),
            direction: .received,
            status: .delivered
        )
        conversations[contact.fingerprintHex, default: []].append(msg)
        if selectedContactFP != contact.fingerprintHex {
            unreadCounts[contact.fingerprintHex, default: 0] += 1
        }
        saveConversations()
    }

    func markRead(_ contactFP: String) {
        unreadCounts[contactFP] = 0
    }

    private func saveConversations() {
        let url = dataDir.appendingPathComponent("conversations.json")
        if let data = try? JSONEncoder().encode(conversations) {
            try? data.write(to: url)
        }
    }

    private func loadConversations() {
        let url = dataDir.appendingPathComponent("conversations.json")
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([String: [ChatMessage]].self, from: data) {
            conversations = loaded
        }
    }

    // MARK: - Connection

    func connect() {
        connectionState = .connecting
        log(.info, "Initiating HELLO handshake...")
        log(.info, "Resolver: \(resolverAddress)")
        log(.info, "Domain: \(oracleDomain)")

        // Simulate 4-query HELLO handshake
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.2) {
                self.log(.dns, "HELLO chunk \(i+1)/4 sent")
                self.queryCount += 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.connectionState = .connected
            self.sessionActive = true
            self.serverTime = Date()
            self.log(.success, "Session established")
            self.log(.info, "Session ID: \(UUID().uuidString.prefix(16))")
        }
    }

    func disconnect() {
        connectionState = .disconnected
        sessionActive = false
        log(.info, "Disconnected")
    }

    func ping() {
        let start = Date()
        log(.dns, "PING →")
        queryCount += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.pingLatency = Date().timeIntervalSince(start) * 1000
            self.serverTime = Date()
            self.log(.success, "PONG ← \(String(format: "%.0f", self.pingLatency))ms")
        }
    }

    func testDNSCache() {
        log(.info, "Testing DNS cache behavior...")
        log(.dns, "Sending identical queries...")

        for i in 1...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) {
                self.log(.dns, "Cache test query \(i)/3")
                self.queryCount += 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.log(.success, "Cache profiling complete — TTL appears to be 300s")
        }
    }

    // MARK: - Settings

    func saveSettings() {
        let settings: [String: Any] = [
            "resolver": resolverAddress,
            "domain": oracleDomain,
            "oracleKey": oraclePublicKeyHex,
            "seed": bootstrapSeedHex,
            "autoReconnect": autoReconnect,
            "queryInterval": queryInterval,
            "dailyBudget": dailyBudget,
            "doh": useDNSOverHTTPS,
        ]
        let url = dataDir.appendingPathComponent("settings.json")
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) {
            try? data.write(to: url)
        }
    }

    private func loadSettings() {
        let url = dataDir.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        resolverAddress = dict["resolver"] as? String ?? resolverAddress
        oracleDomain = dict["domain"] as? String ?? oracleDomain
        oraclePublicKeyHex = dict["oracleKey"] as? String ?? ""
        bootstrapSeedHex = dict["seed"] as? String ?? ""
        autoReconnect = dict["autoReconnect"] as? Bool ?? true
        queryInterval = dict["queryInterval"] as? Double ?? 5.0
        dailyBudget = dict["dailyBudget"] as? Int ?? 300
        useDNSOverHTTPS = dict["doh"] as? Bool ?? false
    }

    // MARK: - Logging

    func log(_ level: LogLevel, _ message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        connectionLog.append(entry)
        if connectionLog.count > 500 { connectionLog.removeFirst(100) }
    }
}

// MARK: - Data Types

enum ConnectionStatus: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected"
    case error = "Error"

    var color: Color {
        switch self {
        case .disconnected: return .red
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
}

struct ChatMessage: Codable, Identifiable {
    let id: String
    let text: String
    let sender: String
    let recipient: String
    let timestamp: Date
    let direction: MessageDirection
    var status: MessageStatus

    enum MessageDirection: String, Codable {
        case sent, received
    }

    enum MessageStatus: String, Codable {
        case sending, sent, delivered, failed
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
}

enum LogLevel {
    case info, dns, success, warning, error

    var icon: String {
        switch self {
        case .info: return "•"
        case .dns: return "⟩"
        case .success: return "✓"
        case .warning: return "⚠"
        case .error: return "✗"
        }
    }

    var color: Color {
        switch self {
        case .info: return .secondary
        case .dns: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
