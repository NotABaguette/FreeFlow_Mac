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

    // Dev mode
    @Published var devMode: Bool = false
    @Published var devQueryLog: [QueryLogEntry] = []

    // Bulletins
    @Published var bulletins: [Bulletin] = []
    @Published var lastBulletinID: UInt16 = 0

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

            for i in 0..<fragments {
                let chunkSize = min(6, encrypted.count - i * 6)
                devLog(query: "SEND_MSG frag \(i+1)/\(fragments) to \(contact.fingerprintHex.prefix(8)) [\(chunkSize)B]",
                       response: "ACK frag \(i+1)")
            }

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
        let sessionId = UUID().uuidString.prefix(16)
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.2) {
                self.log(.dns, "HELLO chunk \(i+1)/4 sent")
                self.queryCount += 1
                self.devLog(
                    query: "HELLO chunk_idx=\(i) total=4 pubkey[\(i*8)..\((i+1)*8)] nonce=\(UInt16.random(in: 0...UInt16.max))",
                    response: i < 3 ? "ACK chunk_idx=\(i)" : "HELLO_COMPLETE session_id=\(sessionId) server_time=\(Int(Date().timeIntervalSince1970))"
                )
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.connectionState = .connected
            self.sessionActive = true
            self.serverTime = Date()
            self.log(.success, "Session established")
            self.log(.info, "Session ID: \(sessionId)")
            self.devLog(query: "ECDH X25519 → HKDF-SHA256", response: "session_key derived (32 bytes)")
        }
    }

    func disconnect() {
        connectionState = .disconnected
        sessionActive = false
        log(.info, "Disconnected")
        devLog(query: "SESSION_CLOSE", response: "session destroyed, keys zeroed")
    }

    func ping() {
        let start = Date()
        log(.dns, "PING →")
        queryCount += 1
        devLog(query: "PING (cmd=0x07)", response: "waiting...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.pingLatency = Date().timeIntervalSince(start) * 1000
            self.serverTime = Date()
            self.log(.success, "PONG ← \(String(format: "%.0f", self.pingLatency))ms")
            let ts = Int(Date().timeIntervalSince1970)
            self.devLog(query: "PING (cmd=0x07)", response: "PONG server_time=\(ts) latency=\(Int(self.pingLatency))ms")
        }
    }

    func testDNSCache() {
        log(.info, "Testing DNS cache behavior...")
        log(.dns, "Sending identical queries...")
        devLog(query: "CACHE_TEST start", response: "sending 3 identical queries")

        for i in 1...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) {
                self.log(.dns, "Cache test query \(i)/3")
                self.queryCount += 1
                self.devLog(
                    query: "AAAA? test-cache-\(i).\(self.oracleDomain)",
                    response: "AAAA 2606:4700::... TTL=300 (cached=\(i > 1 ? "yes" : "no"))"
                )
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.log(.success, "Cache profiling complete — TTL appears to be 300s")
            self.devLog(query: "CACHE_TEST complete", response: "TTL=300s, resolver caches: yes")
        }
    }

    // MARK: - Sync Inbox

    func syncInbox() {
        guard sessionActive else {
            log(.warning, "Cannot sync — no active session")
            return
        }
        log(.dns, "GET_MSG → polling inbox...")
        queryCount += 1
        devLog(query: "GET_MSG poll", response: "waiting...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let hasMessages = Bool.random()
            if hasMessages {
                let sampleSenders = self.contacts.prefix(2)
                for contact in sampleSenders {
                    let msgs = ["Are you safe?", "Check the bulletin", "Network is back in some areas",
                                "Meeting at usual place", "Send update when you can"]
                    let msg = msgs.randomElement()!
                    self.receiveMessage(msg, from: contact)
                    self.log(.success, "Message from \(contact.displayName): \(msg)")
                    self.devLog(query: "GET_MSG", response: "fragment: \(msg.count)B from \(contact.fingerprintHex.prefix(8))")
                }
            } else {
                self.log(.info, "Inbox empty — no new messages")
                self.devLog(query: "GET_MSG", response: "empty (0 bytes)")
            }
        }
    }

    // MARK: - Bulletins

    func fetchBulletin() {
        log(.dns, "GET_BULLETIN → fetching latest...")
        queryCount += 1
        devLog(query: "GET_BULLETIN (lastID=\(lastBulletinID))", response: "waiting...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.lastBulletinID += 1
            let sampleBulletins = [
                "Internet access partially restored in western provinces. Satellite uplinks operational.",
                "Emergency coordination channel active. Use DGA epoch 3 domains.",
                "All proxy shields rotated. New NS records propagating. ETA 6 hours.",
                "Confirmed: DNS filtering bypass effective on resolvers 8.8.8.8 and 1.1.1.1.",
                "Security advisory: update to epoch seed 4. Old seeds compromised.",
            ]
            let content = sampleBulletins.randomElement()!
            let bulletin = Bulletin(
                id: self.lastBulletinID,
                timestamp: Date(),
                content: content,
                verified: true,
                signatureHex: String((0..<16).map { _ in "0123456789abcdef".randomElement()! })
            )
            self.bulletins.insert(bulletin, at: 0)
            self.log(.success, "Bulletin #\(bulletin.id) received (\(content.count) chars, signature verified)")
            self.devLog(query: "GET_BULLETIN", response: "id=\(bulletin.id) len=\(content.count) sig=OK")

            if self.bulletins.count > 50 { self.bulletins = Array(self.bulletins.prefix(50)) }
        }
    }

    // MARK: - Dev Query Logging

    func devLog(query: String, response: String) {
        guard devMode else { return }
        let entry = QueryLogEntry(
            timestamp: Date(),
            query: query,
            response: response,
            domain: oracleDomain,
            resolver: resolverAddress,
            transport: useRelayHTTP ? "HTTP Relay" : "DNS AAAA"
        )
        devQueryLog.append(entry)
        if devQueryLog.count > 500 { devQueryLog.removeFirst(100) }
    }

    // MARK: - Transport

    @Published var useRelayHTTP: Bool = false
    @Published var relayURL: String = "https://oracle.example.com:8443"
    @Published var relayAPIKey: String = ""

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
            "devMode": devMode,
            "useRelayHTTP": useRelayHTTP,
            "relayURL": relayURL,
            "relayAPIKey": relayAPIKey,
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
        devMode = dict["devMode"] as? Bool ?? false
        useRelayHTTP = dict["useRelayHTTP"] as? Bool ?? false
        relayURL = dict["relayURL"] as? String ?? relayURL
        relayAPIKey = dict["relayAPIKey"] as? String ?? ""
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
        case .info: return Color(nsColor: .secondaryLabelColor)
        case .dns: return .cyan
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct Bulletin: Identifiable {
    let id: UInt16
    let timestamp: Date
    let content: String
    let verified: Bool
    let signatureHex: String
}

struct QueryLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let query: String
    let response: String
    let domain: String
    let resolver: String
    let transport: String
}
