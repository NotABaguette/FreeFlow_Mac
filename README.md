# FreeFlow for macOS

A native macOS client for the **FreeFlow** DNS-based covert messaging protocol — designed for last-resort text communication during total internet blackouts.

FreeFlow exploits a structural dependency: governments must keep domestic DNS operational for their own intranet. By encoding messages as natural-looking domain names and hiding data inside IPv6 (AAAA) DNS responses, FreeFlow enables text messaging that is indistinguishable from normal CDN traffic.

## Features

**Messenger UI**
- Full chat interface with conversation list, message bubbles, timestamps, and delivery status
- Contact management with key fingerprint verification
- Message history with search

**Covert DNS Transport**
- Messages encoded as natural-looking domain names via lexical steganography
- Data hidden in AAAA (IPv6) responses using real CDN prefixes (Cloudflare, Google, AWS)
- Adaptive rate limiting with Poisson-jittered timing
- Layered Domain Generation Algorithm (DGA) for domain rotation

**End-to-End Encryption**
- X25519 ECDH key agreement
- ChaCha20-Poly1305 authenticated encryption
- HKDF-SHA256 key derivation
- Ed25519 bulletin signature verification
- Per-query HMAC token rotation (zero session linkability)

**Connection Management**
- Multi-query HELLO handshake for session establishment
- Live connection log with DNS query monitoring
- Ping with latency measurement and clock synchronization
- DNS cache profiling
- Auto-reconnect

**CLI Tool**
- Full command-line interface for headless operation
- Self-test command for crypto verification
- Identity and contact management

## Screenshots

The app uses a native macOS design with four panels:

| Panel | Description |
|-------|-------------|
| **Chats** | Messenger-style conversation view with message bubbles |
| **Contacts** | Contact list with key management and add/remove |
| **Connection** | DNS connection status, ping, cache test, live log |
| **Identity** | Your X25519 keypair, fingerprint, and crypto details |

Settings are accessible via `Cmd+,` with Network, Security, and Advanced tabs.

## Build

### Requirements
- macOS 14+ (Sonoma)
- Xcode 15.4+
- Swift 5.9+

### Build & Run

```bash
# CLI
swift build
swift run freeflow help
swift run freeflow test

# Release build
swift build -c release
cp .build/release/freeflow /usr/local/bin/

# GUI app (requires Xcode)
open Package.swift  # Opens in Xcode
# Select FreeFlowGUI scheme → Run
```

### CLI Commands

```
freeflow signup <name>                    Create X25519 identity
freeflow whoami                           Show your identity + fingerprint
freeflow ping                             Ping Oracle (clock sync)
freeflow connect                          Establish encrypted session
freeflow send <contact> <message>         Send E2E encrypted message
freeflow inbox                            Check for messages
freeflow bulletin                         Fetch Ed25519-signed broadcast
freeflow contacts                         List contacts
freeflow add-contact <name> <pubkey-hex>  Add a contact by public key
freeflow test                             Run crypto self-test
```

## Architecture

```
FreeFlow/Sources/
├── Core/                    # Cross-platform protocol library
│   ├── Protocol/
│   │   ├── Commands.swift   # 8 protocol commands (HELLO, PING, SEND_MSG, etc.)
│   │   ├── Frame.swift      # Wire format: [cmd][seq][frag][token][data]
│   │   └── AAAAEncoder.swift # IPv6 response encoding with CDN prefixes
│   ├── Crypto/
│   │   ├── Keys.swift       # X25519 + Ed25519 key generation
│   │   ├── Session.swift    # HKDF derivation, ChaCha20-Poly1305, HELLO
│   │   ├── E2E.swift        # End-to-end encryption between users
│   │   └── Signing.swift    # Ed25519 bulletin verification
│   ├── Lexical/
│   │   ├── Profile.swift    # Steganographic profile structure
│   │   └── Encoder.swift    # Payload ↔ natural domain label encoding
│   ├── DGA/
│   │   └── DomainManager.swift # Layered domain generation algorithm
│   ├── Identity/
│   │   └── Identity.swift   # User identity, fingerprints, contact book
│   └── Client/
│       ├── Connection.swift # DNS transport, session management
│       └── RateLimiter.swift # Adaptive Poisson-jittered rate limiting
├── CLI/
│   └── main.swift           # Command-line interface
└── GUI/
    ├── FreeFlowApp.swift    # SwiftUI app entry point
    └── Views/
        ├── MainView.swift        # Three-column layout
        ├── ChatListView.swift    # Conversation list
        ├── ChatView.swift        # Message bubbles + input
        ├── ConnectionPanel.swift # Connect, ping, DNS test, log
        ├── IdentityPanel.swift   # Identity creation + display
        ├── ContactsPanel.swift   # Contact management
        └── SettingsPanel.swift   # Network, security, advanced settings
```

## Protocol

FreeFlow uses DNS AAAA queries as a bidirectional data channel:

```
Client                  Domestic Resolver           Proxy Shield            Oracle
  │                          │                          │                     │
  │ AAAA? season-london.cdn-static-eu.net              │                     │
  │─────────────────────────►│                          │                     │
  │                          │──────────────────────────►│                     │
  │                          │                          │────────────────────►│
  │                          │                          │◄────────────────────│
  │                          │◄──────────────────────────│   AAAA 2606:4700:: │
  │◄─────────────────────────│                          │   (8 bytes payload) │
  │                          │                          │                     │
```

- **Query**: Payload encoded as natural-looking domain labels (lexical steganography)
- **Response**: Data hidden in IPv6 addresses using real CDN prefixes
- **Session**: X25519 ECDH handshake → ChaCha20-Poly1305 encrypted channel
- **E2E**: Additional X25519 layer between sender and recipient

## Security

| Layer | Mechanism |
|-------|-----------|
| Key Exchange | X25519 ECDH (ephemeral per session) |
| Session Encryption | ChaCha20-Poly1305 (AEAD) |
| Key Derivation | HKDF-SHA256 |
| E2E Encryption | X25519 + ChaCha20-Poly1305 per contact |
| Bulletin Auth | Ed25519 signatures |
| Session Tokens | HMAC-SHA256 rotating per query |
| Steganography | Lexical encoding (natural domain names) |
| Traffic Analysis | Poisson-jittered timing, CDN IPv6 prefixes |
| Domain Rotation | Layered DGA (bootstrap + epoch seeds) |

## Data Storage

All data is stored locally in `~/.freeflow/`:

| File | Contents | Encrypted |
|------|----------|-----------|
| `identity.json` | X25519 keypair + display name | File protection |
| `contacts.json` | Contact public keys | No (public keys only) |
| `conversations.json` | Message history | No (encrypt at rest planned) |
| `settings.json` | App configuration | No |

## License

This project is part of the FreeFlow protocol suite. See the main FreeFlow repository for the complete specification and Oracle server implementation.

## Related

- [FreeFlow](https://github.com/NotABaguette/FreeFlow) — Protocol spec + Go Oracle server
- [FreeFlow_iOS](https://github.com/NotABaguette/FreeFlow_iOS) — iOS client
