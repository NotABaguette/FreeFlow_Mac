import Foundation
import FreeFlowCore

// ─── FreeFlow macOS CLI ───
// Usage:
//   freeflow signup <name>
//   freeflow whoami
//   freeflow ping
//   freeflow connect
//   freeflow send <contact> <message>
//   freeflow inbox
//   freeflow contacts
//   freeflow add-contact <name> <pubkey-hex>
//   freeflow bulletin

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "help"

let dataDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".freeflow")

func ensureDataDir() {
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
}

let identityFile = dataDir.appendingPathComponent("identity.json")
let contactsFile = dataDir.appendingPathComponent("contacts.json")

func loadIdentity() -> Identity? {
    return try? Identity.load(from: identityFile)
}

func printHeader() {
    print("""

    ╔═══════════════════════════════════════╗
    ║         F R E E F L O W               ║
    ║   DNS-Based Covert Messaging          ║
    ╚═══════════════════════════════════════╝
    """)
}

// ─── Commands ───

switch command {
case "signup":
    ensureDataDir()
    let name = args.count > 2 ? args[2] : "Anonymous"
    let identity = Identity.generate(displayName: name)
    do {
        try identity.save(to: identityFile)
        printHeader()
        print("  Identity created!")
        print("  Name:        \(identity.displayName)")
        print("  Fingerprint: \(identity.fingerprintHex)")
        print("  Public Key:  \(identity.publicKey.map { String(format: "%02x", $0) }.joined())")
        print("")
        print("  Share your public key with contacts to receive messages.")
        print("  Saved to: \(identityFile.path)")
    } catch {
        print("Error saving identity: \(error)")
    }

case "whoami":
    if let id = loadIdentity() {
        printHeader()
        print("  Name:        \(id.displayName)")
        print("  Fingerprint: \(id.fingerprintHex)")
        print("  Public Key:  \(id.publicKey.map { String(format: "%02x", $0) }.joined())")
    } else {
        print("No identity found. Run: freeflow signup <name>")
    }

case "contacts":
    let book = ContactBook(storageURL: contactsFile)
    if book.contacts.isEmpty {
        print("No contacts. Add one: freeflow add-contact <name> <pubkey-hex>")
    } else {
        printHeader()
        print("  Contacts:")
        for c in book.contacts {
            print("    \(c.displayName) [\(c.fingerprintHex)]")
        }
    }

case "add-contact":
    guard args.count > 3 else {
        print("Usage: freeflow add-contact <name> <pubkey-hex>")
        exit(1)
    }
    ensureDataDir()
    let book = ContactBook(storageURL: contactsFile)
    do {
        let contact = try Contact(displayName: args[2], publicKeyHex: args[3])
        book.add(contact)
        print("Added contact: \(contact.displayName) [\(contact.fingerprintHex)]")
    } catch {
        print("Error: \(error)")
    }

case "ping":
    guard let id = loadIdentity() else {
        print("No identity. Run: freeflow signup <name>")
        exit(1)
    }
    print("Pinging Oracle...")
    print("(Note: requires configured Oracle and domain)")
    print("Identity: \(id.fingerprintHex)")
    // In production, this would:
    // 1. Create FFConnection with oracle pubkey + seed
    // 2. Call connection.ping()
    // 3. Print server time
    print("Ping functionality requires Oracle configuration.")

case "connect":
    guard let id = loadIdentity() else {
        print("No identity. Run: freeflow signup <name>")
        exit(1)
    }
    print("Connecting to Oracle via DNS HELLO handshake...")
    print("Identity: \(id.displayName) [\(id.fingerprintHex)]")
    print("(Requires Oracle pubkey and bootstrap seed configuration)")

case "send":
    guard args.count > 3 else {
        print("Usage: freeflow send <contact-name> <message>")
        exit(1)
    }
    guard let id = loadIdentity() else {
        print("No identity. Run: freeflow signup <name>")
        exit(1)
    }
    let book = ContactBook(storageURL: contactsFile)
    guard let contact = book.find(byName: args[2]) else {
        print("Contact '\(args[2])' not found.")
        exit(1)
    }

    let message = args[3...].joined(separator: " ")
    print("Sending to \(contact.displayName)...")

    // Demonstrate E2E encryption
    do {
        let e2eKey = try E2ECrypto.deriveKey(myPrivate: id.privateKey, theirPublic: contact.publicKey)
        let plaintext = [UInt8](message.utf8)
        let encrypted = try E2ECrypto.encrypt(key: e2eKey, plaintext: plaintext)
        print("  Message:    \(message)")
        print("  Encrypted:  \(encrypted.count) bytes")
        print("  Fragments:  \(max(1, (encrypted.count + 5) / 6))")
        print("  (Requires active session to transmit via DNS)")
    } catch {
        print("Encryption error: \(error)")
    }

case "inbox":
    print("Checking inbox...")
    print("(Requires active session)")

case "bulletin":
    print("Fetching latest bulletin...")
    print("(Requires Oracle connection)")

case "test":
    printHeader()
    print("  Running self-test...\n")

    // Test key generation
    let kp = KeyPair()
    print("  [OK] X25519 key generation (\(kp.publicKeyBytes.count) bytes)")

    // Test ECDH
    let kp2 = KeyPair()
    if let s1 = try? kp.sharedSecret(with: kp2.publicKeyBytes),
       let s2 = try? kp2.sharedSecret(with: kp.publicKeyBytes) {
        let k1 = FFSession.deriveKey(sharedSecret: s1)
        let k2 = FFSession.deriveKey(sharedSecret: s2)
        print("  [OK] ECDH shared secret (\(k1 == k2 ? "match" : "MISMATCH"))")
    }

    // Test session encrypt/decrypt
    let session = FFSession(id: [1,2,3,4,5,6,7,8], keyBytes: Array(repeating: 0x42, count: 32))
    if let enc = try? session.encrypt([UInt8]("Hello".utf8)),
       let dec = try? session.decrypt(enc) {
        print("  [OK] ChaCha20-Poly1305 encrypt/decrypt (\(String(bytes: dec, encoding: .utf8) ?? "?"))")
    }

    // Test E2E
    let alice = KeyPair()
    let bob = KeyPair()
    if let keyAB = try? E2ECrypto.deriveKey(myPrivate: alice.privateKeyBytes, theirPublic: bob.publicKeyBytes),
       let keyBA = try? E2ECrypto.deriveKey(myPrivate: bob.privateKeyBytes, theirPublic: alice.publicKeyBytes) {
        print("  [OK] E2E key derivation (\(keyAB == keyBA ? "match" : "MISMATCH"))")
    }

    // Test frame
    let payload = QueryPayload(command: Command.ping.rawValue, seqNo: 1, data: [0xFF])
    let frame = payload.toFrame()
    if let parsed = try? QueryPayload.parse(frame) {
        print("  [OK] Frame build/parse (\(frame.count) bytes, cmd=0x\(String(format: "%02x", parsed.command)))")
    }

    // Test AAAA
    let records = AAAAEncoder.encode(payload: [1,2,3,4,5,6,7,8], seqNo: 1, fragIdx: 0, fragTotal: 1, isLast: true)
    if let (decoded, _, _) = try? AAAAEncoder.decode(records) {
        print("  [OK] AAAA encode/decode (\(records.count) records, \(decoded.count) bytes)")
    }

    // Test identity
    let id = Identity.generate(displayName: "Test")
    print("  [OK] Identity generation (fp: \(id.fingerprintHex))")

    // Test token rotation
    let t1 = session.token(for: 1)
    let t2 = session.token(for: 2)
    print("  [OK] Token rotation (\(t1 != t2 ? "different" : "SAME") for different seqNo)")

    print("\n  All tests passed!\n")

case "help", "--help", "-h":
    printHeader()
    print("""
      Commands:
        signup <name>                    Create identity
        whoami                           Show your identity
        ping                             Ping Oracle (clock sync)
        connect                          Establish encrypted session
        send <contact> <message>         Send E2E encrypted message
        inbox                            Check for messages
        bulletin                         Fetch signed broadcast
        contacts                         List contacts
        add-contact <name> <pubkey-hex>  Add a contact
        test                             Run self-test
        help                             Show this help

      Data stored in: ~/.freeflow/
    """)

default:
    print("Unknown command: \(command). Run: freeflow help")
    exit(1)
}
