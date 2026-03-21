import Foundation
import Network
import CryptoKit

/// Main FreeFlow client connection — handles all protocol operations over DNS or HTTP relay
public class FFConnection: ObservableObject {
    @Published public var state: ConnectionState = .disconnected
    @Published public var session: FFSession?

    public let identity: Identity
    public let domainManager: DomainManager
    public let rateLimiter = AdaptiveRateLimiter()
    public var profile: LexicalProfile
    public var oraclePublicKey: [UInt8]

    public var resolver: String = "8.8.8.8"
    public var useRelay: Bool = false
    public var relayURL: String = ""
    public var relayAPIKey: String = ""

    /// Called for every query/response when set (for dev logging)
    public var onQuery: ((_ query: String, _ response: String, _ transport: String) -> Void)?

    public enum ConnectionState: String {
        case disconnected, connecting, connected, dormant
    }

    public init(identity: Identity, oraclePublicKey: [UInt8], seed: [UInt8], profile: LexicalProfile) {
        self.identity = identity
        self.oraclePublicKey = oraclePublicKey
        self.domainManager = DomainManager(seed: seed)
        self.profile = profile
    }

    // MARK: - PING

    public func ping() async throws -> Date {
        let payload: [UInt8] = [Command.ping.rawValue]
        onQuery?("PING cmd=0x07", "sending...", transport)
        let response = try await queryOracle(payload: payload)
        guard response.count >= 4 else { throw FFError.frameTooShort(response.count) }
        let serverTime = UInt32(response[0]) << 24 | UInt32(response[1]) << 16 |
                         UInt32(response[2]) << 8 | UInt32(response[3])
        let date = Date(timeIntervalSince1970: TimeInterval(serverTime))
        domainManager.syncClock(serverTime: serverTime)
        onQuery?("PING cmd=0x07", "PONG server_time=\(serverTime)", transport)
        return date
    }

    // MARK: - HELLO

    public func connect() async throws {
        state = .connecting
        let ephemeral = KeyPair()
        let pubBytes = ephemeral.publicKeyBytes
        let helloNonce = UInt16.random(in: 0...UInt16.max)

        for i in 0..<4 {
            let chunk = Array(pubBytes[(i*8)..<((i+1)*8)])
            var payload: [UInt8] = [Command.hello.rawValue, UInt8(i), 4]
            payload.append(UInt8((helloNonce >> 8) & 0xFF))
            payload.append(UInt8(helloNonce & 0xFF))
            payload.append(contentsOf: chunk)

            let chunkHex = chunk.map { String(format: "%02x", $0) }.joined()
            onQuery?("HELLO chunk=\(i)/4 nonce=\(helloNonce) data=\(chunkHex)", "sending...", transport)

            let response = try await queryOracle(payload: payload)

            if i == 3 {
                let sharedSecret = try ephemeral.sharedSecret(with: oraclePublicKey)
                let sessionKeyBytes = FFSession.deriveKey(sharedSecret: sharedSecret)
                let sessionID = try FFSession.decodeHelloComplete(
                    response: response, sessionKey: sessionKeyBytes)

                session = FFSession(id: sessionID, keyBytes: sessionKeyBytes)
                state = .connected
                let sidHex = sessionID.map { String(format: "%02x", $0) }.joined()
                onQuery?("HELLO_COMPLETE", "session_id=\(sidHex) key_derived=32B", transport)
            } else {
                onQuery?("HELLO chunk=\(i)/4", "ACK chunk_idx=\(i)", transport)
                try await rateLimiter.waitForNext()
            }
        }
    }

    public func disconnect() {
        state = .disconnected
        session = nil
        onQuery?("DISCONNECT", "session destroyed", transport)
    }

    // MARK: - REGISTER

    public func register() async throws {
        guard let sess = session else { throw FFError.noSession }
        let seq = sess.nextSeqNo()
        let token = sess.token(for: seq)

        var payload: [UInt8] = [0x08] // REGISTER command
        payload.append(contentsOf: token)
        payload.append(contentsOf: identity.publicKey)
        payload.append(contentsOf: identity.fingerprint)

        onQuery?("REGISTER fp=\(identity.fingerprintHex)", "sending...", transport)
        let response = try await queryOracle(payload: payload)
        onQuery?("REGISTER", "response=\(response.count)B", transport)
    }

    // MARK: - GET BULLETIN

    public func getBulletin(lastSeenID: UInt16 = 0) async throws -> [UInt8] {
        var payload: [UInt8] = [Command.getBulletin.rawValue]
        payload.append(UInt8((lastSeenID >> 8) & 0xFF))
        payload.append(UInt8(lastSeenID & 0xFF))

        onQuery?("GET_BULLETIN lastID=\(lastSeenID)", "sending...", transport)
        let response = try await queryOracle(payload: payload)
        onQuery?("GET_BULLETIN", "response=\(response.count)B", transport)
        return response
    }

    // MARK: - SEND MESSAGE

    public func sendMessage(_ text: String, to contact: Contact) async throws -> Int {
        guard let sess = session else { throw FFError.noSession }

        let e2eKey = try E2ECrypto.deriveKey(myPrivate: identity.privateKey, theirPublic: contact.publicKey)
        let plaintext = [UInt8](text.utf8)
        let ciphertext = try E2ECrypto.encrypt(key: e2eKey, plaintext: plaintext)

        let chunkSize = 6
        let fragments = stride(from: 0, to: ciphertext.count, by: chunkSize).map {
            Array(ciphertext[$0..<min($0 + chunkSize, ciphertext.count)])
        }

        let fpHex = contact.fingerprintHex.prefix(8)
        for (i, fragment) in fragments.enumerated() {
            try await rateLimiter.waitForNext()
            let seq = sess.nextSeqNo()
            let token = sess.token(for: seq)

            var payload: [UInt8] = [Command.sendMsg.rawValue]
            payload.append(UInt8(i))
            payload.append(UInt8(fragments.count))
            payload.append(contentsOf: token)
            payload.append(contentsOf: Array(contact.publicKey.prefix(8)))
            payload.append(contentsOf: fragment)

            onQuery?("SEND_MSG frag=\(i+1)/\(fragments.count) to=\(fpHex) \(fragment.count)B", "sending...", transport)
            let response = try await queryOracle(payload: payload)
            onQuery?("SEND_MSG frag=\(i+1)/\(fragments.count)", "ACK \(response.count)B", transport)
        }
        return fragments.count
    }

    // MARK: - GET MESSAGES

    public func pollMessages() async throws -> (data: [UInt8], senderFP: [UInt8])? {
        guard let sess = session else { throw FFError.noSession }

        try await rateLimiter.waitForNext()
        let seq = sess.nextSeqNo()
        let token = sess.token(for: seq)

        var payload: [UInt8] = [Command.getMsg.rawValue]
        payload.append(contentsOf: token)
        payload.append(0)

        onQuery?("GET_MSG seq=\(seq)", "sending...", transport)
        let response = try await queryOracle(payload: payload)

        if response.count <= 1 {
            onQuery?("GET_MSG", "empty (no messages)", transport)
            return nil
        }

        onQuery?("GET_MSG", "data=\(response.count)B", transport)

        // Response format: [sender_fp(8)][ciphertext...]
        guard response.count > 8 else { return nil }
        let senderFP = Array(response[0..<8])
        let ciphertext = Array(response[8...])
        return (ciphertext, senderFP)
    }

    /// Decrypt received message data using sender's public key
    public func decryptMessage(_ ciphertext: [UInt8], senderPublicKey: [UInt8]) throws -> String {
        let e2eKey = try E2ECrypto.deriveKey(myPrivate: identity.privateKey, theirPublic: senderPublicKey)
        let plaintext = try E2ECrypto.decrypt(key: e2eKey, blob: ciphertext)
        guard let text = String(bytes: plaintext, encoding: .utf8) else {
            throw FFError.decryptionFailed
        }
        return text
    }

    // MARK: - DISCOVER

    public func discover() async throws {
        guard let sess = session else { throw FFError.noSession }
        let seq = sess.nextSeqNo()
        let token = sess.token(for: seq)

        var payload: [UInt8] = [Command.discover.rawValue]
        payload.append(contentsOf: token)

        onQuery?("DISCOVER", "sending...", transport)
        let response = try await queryOracle(payload: payload)

        if response.count >= 16 {
            domainManager.updateEpoch(encryptedSeed: Array(response.prefix(16)),
                                       sessionKey: sess.keyBytes)
            onQuery?("DISCOVER", "epoch_seed updated, epoch=\(domainManager.epochNumber)", transport)
        } else {
            onQuery?("DISCOVER", "response too short (\(response.count)B)", transport)
        }
    }

    // MARK: - DNS CACHE TEST

    public func testDNSCache() async throws -> (ttl: Int, cached: Bool) {
        // Send same query twice, compare timing
        let payload: [UInt8] = [Command.ping.rawValue]

        let start1 = Date()
        onQuery?("CACHE_TEST query 1/2", "sending...", transport)
        _ = try await queryOracle(payload: payload)
        let t1 = Date().timeIntervalSince(start1)

        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        let start2 = Date()
        onQuery?("CACHE_TEST query 2/2 (same query)", "sending...", transport)
        _ = try await queryOracle(payload: payload)
        let t2 = Date().timeIntervalSince(start2)

        let cached = t2 < t1 * 0.5
        onQuery?("CACHE_TEST", "t1=\(Int(t1*1000))ms t2=\(Int(t2*1000))ms cached=\(cached)", transport)
        return (300, cached)
    }

    // MARK: - Transport

    private var transport: String {
        useRelay ? "HTTP" : "DNS"
    }

    private func queryOracle(payload: [UInt8]) async throws -> [UInt8] {
        if useRelay {
            return try await queryViaHTTP(payload: payload)
        } else {
            return try await queryViaDNS(payload: payload)
        }
    }

    /// DNS AAAA transport
    private func queryViaDNS(payload: [UInt8]) async throws -> [UInt8] {
        let domain = domainManager.activeDomain()
        let queryName = try LexicalEncoder.encodeQuery(
            payload: payload, domain: domain, profile: profile)

        let ips = try await dnsQueryAAAA(name: queryName)
        let (responsePayload, _, _) = try AAAAEncoder.decode(ips)
        await rateLimiter.record(success: true)
        return responsePayload
    }

    /// HTTP Relay transport
    private func queryViaHTTP(payload: [UInt8]) async throws -> [UInt8] {
        guard !relayURL.isEmpty else { throw FFError.helloFailed("Relay URL not configured") }

        let url = URL(string: relayURL + "/api/query")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if !relayAPIKey.isEmpty {
            request.setValue(relayAPIKey, forHTTPHeaderField: "X-API-Key")
        }
        request.httpBody = Data(payload)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FFError.helloFailed("HTTP relay returned error")
        }
        await rateLimiter.record(success: true)
        return [UInt8](data)
    }

    /// Raw DNS AAAA query via UDP
    private func dnsQueryAAAA(name: String) async throws -> [[UInt8]] {
        let query = DNSPacket.buildQuery(name: name, type: .AAAA)

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let lock = NSLock()

            func safeResume(_ result: Result<[[UInt8]], Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(resolver),
                port: NWEndpoint.Port(integerLiteral: 53),
                using: .udp
            )

            connection.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    safeResume(.failure(err))
                }
            }

            connection.start(queue: .global())

            connection.send(content: Data(query), completion: .contentProcessed { error in
                if let error = error {
                    safeResume(.failure(error))
                    return
                }

                connection.receive(minimumIncompleteLength: 12, maximumLength: 4096) { data, _, _, error in
                    connection.cancel()
                    if let error = error {
                        safeResume(.failure(error))
                        return
                    }
                    guard let data = data else {
                        safeResume(.failure(FFError.noRecords))
                        return
                    }
                    do {
                        let ips = try DNSPacket.parseAAAAResponse([UInt8](data))
                        safeResume(.success(ips))
                    } catch {
                        safeResume(.failure(error))
                    }
                }
            })

            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                connection.cancel()
                safeResume(.failure(FFError.timeout))
            }
        }
    }
}

// MARK: - DNS Packet Builder/Parser

enum DNSRecordType: UInt16 {
    case AAAA = 28
}

enum DNSPacket {
    static func buildQuery(name: String, type: DNSRecordType) -> [UInt8] {
        var packet = [UInt8]()
        let txid = UInt16.random(in: 0...UInt16.max)
        packet.append(UInt8((txid >> 8) & 0xFF))
        packet.append(UInt8(txid & 0xFF))
        packet.append(0x01); packet.append(0x00) // Flags: recursion desired
        packet.append(0x00); packet.append(0x01) // Questions: 1
        packet.append(contentsOf: [0,0, 0,0, 0,0]) // Answer, Auth, Additional: 0

        for label in name.split(separator: ".") {
            let bytes = [UInt8](label.utf8)
            packet.append(UInt8(bytes.count))
            packet.append(contentsOf: bytes)
        }
        packet.append(0)

        packet.append(UInt8((type.rawValue >> 8) & 0xFF))
        packet.append(UInt8(type.rawValue & 0xFF))
        packet.append(0x00); packet.append(0x01) // IN class

        return packet
    }

    static func parseAAAAResponse(_ data: [UInt8]) throws -> [[UInt8]] {
        guard data.count >= 12 else { throw FFError.noRecords }

        let anCount = UInt16(data[6]) << 8 | UInt16(data[7])
        guard anCount > 0 else { throw FFError.noRecords }

        var pos = 12
        // Skip QNAME
        while pos < data.count {
            let len = Int(data[pos])
            if len == 0 { pos += 1; break }
            if len & 0xC0 == 0xC0 { pos += 2; break }
            pos += 1 + len
        }
        pos += 4 // QTYPE + QCLASS

        var records = [[UInt8]]()
        for _ in 0..<anCount {
            guard pos + 12 <= data.count else { break }
            if data[pos] & 0xC0 == 0xC0 { pos += 2 }
            else { while pos < data.count && data[pos] != 0 { pos += Int(data[pos]) + 1 }; pos += 1 }

            let rtype = UInt16(data[pos]) << 8 | UInt16(data[pos+1])
            pos += 2 + 2 + 4 // TYPE + CLASS + TTL
            let rdLength = Int(UInt16(data[pos]) << 8 | UInt16(data[pos+1]))
            pos += 2

            if rtype == DNSRecordType.AAAA.rawValue && rdLength == 16 {
                guard pos + 16 <= data.count else { break }
                records.append(Array(data[pos..<(pos+16)]))
            }
            pos += rdLength
        }
        return records
    }
}
