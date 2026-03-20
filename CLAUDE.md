# FreeFlow macOS Client

macOS CLI + library for the FreeFlow DNS-based covert messaging protocol.

## Build & Run

```bash
swift build                    # Debug build
swift build -c release         # Release build
swift test                     # Run tests
swift run freeflow help        # Show CLI help
swift run freeflow test        # Run self-test
```

## CLI Commands

```
freeflow signup <name>                    Create identity
freeflow whoami                           Show your identity
freeflow ping                             Ping Oracle (clock sync)
freeflow connect                          Establish encrypted session
freeflow send <contact> <message>         Send E2E encrypted message
freeflow inbox                            Check for messages
freeflow bulletin                         Fetch signed broadcast
freeflow contacts                         List contacts
freeflow add-contact <name> <pubkey-hex>  Add a contact
freeflow test                             Run self-test
```

## Structure

```
FreeFlow/Sources/
├── Core/          — Protocol library (shared with iOS)
│   ├── Protocol/  — Frame, Commands, AAAA encoding
│   ├── Crypto/    — X25519, ChaCha20-Poly1305, Ed25519, HKDF
│   ├── Lexical/   — Steganographic encoding/decoding
│   ├── DGA/       — Domain generation algorithm
│   ├── Identity/  — Keypairs, fingerprints, contacts
│   └── Client/    — Connection manager, rate limiter
└── App/           — CLI executable
```

## Tech Stack

- Swift 5.9+, macOS 13+
- CryptoKit (native crypto)
- Network.framework (DNS transport)
- Swift Package Manager
