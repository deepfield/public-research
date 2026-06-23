# Vibenet

*First published: 2026-06-23*

> **Note:** Some indicators in the [`iocs/`](iocs/) files are slurs or otherwise offensive, chosen by the operators for branding and reproduced verbatim for detection.

## Overview

Vibenet (also known as Heilong, the tag its 2026 Android rebrand adopted) is a custom (non-Mirai) DDoS botnet family that targets Android TV and IoT devices through ADB, tracked by Deepfield ERT across multiple builds and rebrands. Its latest Linux build inverts the usual priorities of a flooding bot. Where most DDoS malware floods in cleartext or links a stock TLS library, this build ships a complete, hand-written **TLS 1.2/1.3 + QUIC v1 + HTTP/2 + HTTP/3** client, a browser on the wire. Every Layer-7 flood completes a real TLS or QUIC handshake with a fixed, browser-like fingerprint over mostly Cloudflare-proxied web ports plus 9443, so the attack traffic reads as ordinary HTTPS or QUIC to Layer-7 mitigation. The tell that this is camouflage rather than security: the bot validates no certificates at all. It will complete a handshake with any server that answers.

The bot does not carry a C2 domain or a hardcoded C2 IP. Instead it reads its current C2 from an Ethereum ENS text record (the name `alextyler.eth`, record key `description`), queried over HTTPS JSON-RPC after resolving provider hostnames with DNS-over-HTTPS. The record holds the C2 address as an obfuscated IPv6 string; decoded with the bot's own routine on 2026-06-23 it resolved to `127.0.0[.]1`: this build's dead drop in the off position, most likely not yet switched on. The family's older C2 channels were still live at the time, so this is not the whole botnet going dark; and because the record sits on a public ledger, it can be re-read to catch the C2 the moment it goes live. On-chain C2 is common in this scene; what sets this build apart is the implementation: a namehash computed at runtime, the C2 tucked into the standard `description` profile field, a decoy-laden IPv6 encoding, and an eleven-endpoint RPC failover list whose hostnames are resolved with DoH.

Underneath the new transport, this is the same Vibenet codebase as the family's earlier standalone Linux build: identical encrypted-string-table cipher and key, the `meow` C2 framing magic, the Layer-3/4 and game-query flood set, an SSH-banner scanner, a competitor process-killer, and self-staging into writable mounts. The ENS dead drop places it alongside [jackskid](../jackskid/) and other tracked families that read C2 from the same public ENS resolver contract using different per-family encodings.

## Report

See [`report.md`](report.md) for the full technical analysis: the ENS dead-drop resolution chain (Keccak-256 namehash, public-resolver `text()` call, RPC rotation, DoH, XOR-IPv6 config decode), the embedded TLS 1.2/1.3 and QUIC v1 stack and its deterministic JA3/JA4 fingerprint, the absent certificate validation, the X25519 session handshake and opcode protocol, the Layer-7 and Layer-3/4 flood engine and attack-job table, the encrypted string tables and shared Vibenet tradecraft, and the ENS dead-drop cluster.

## Related research

This is original Deepfield ERT analysis. The build belongs to the broader "Heilong"/`libyahu` Android DDoS ecosystem, in which a shared APK wrapper and delivery infrastructure (including `apk.alextyler[.]st`) are reused by multiple operators; wrapper reuse is not by itself evidence of a shared operator. The ENS dead-drop technique and the shared public resolver contract also appear in our [jackskid](../jackskid/) research.

## Technical summary

- **Lineage:** Vibenet family; statically linked, stripped x86-64 ELF built with clang/LLD. Same encrypted-string-table cipher and key as the family's prior Linux build.
- **Delivery:** Placed on Android TV / IoT devices via ADB; cross-architecture builds (ARM, MIPS, x86, PPC, SH4 suffixes present in the string tables).
- **C2 locator:** Ethereum ENS text record `alextyler.eth` / key `description`, on the public ENS resolver `0xF29100983E058B709F3D539b0c765937B804AC15`, selector `0x59d1d43c` (`text(bytes32,string)`).
- **C2 resolution transport:** JSON-RPC `eth_call` over the embedded HTTPS client, against eleven hardcoded RPC endpoints (fixed order, failover); provider hostnames resolved over DoH (`1.1.1.1`, `8.8.8.8`, `9.9.9.9`).
- **Config decode:** comma-separated obfuscated-IPv6 tokens; the real IPv4 is the last two 16-bit groups combined and XORed with `0x4ab73ce1`, emitted least-significant-byte first. Live value 2026-06-23 decoded to `127.0.0[.]1` (parked).
- **Embedded transport:** hand-rolled TLS 1.2 + TLS 1.3 + QUIC v1 + DoH client; no OpenSSL/BoringSSL/WolfSSL. ChaCha20-Poly1305 and AES-128-GCM AEADs, X25519 key exchange, SHA-256/HKDF, Keccak-256 for the ENS namehash.
- **TLS fingerprint:** deterministic, browser-like. Cipher list `1301,1303,c02f,cca8`; x25519-only key share; ALPN `h2,http/1.1`; fixed 9-extension order; no GREASE.
- **Certificate validation:** none. Certificate and CertificateVerify messages are absorbed into the transcript hash but never parsed or verified; only the Finished MAC is checked.
- **C2 session:** custom X25519 ECDH + Poly1305 (`server_auth`) handshake over a shuffled set of mostly Cloudflare-proxied web ports plus 9443 (443, 80, 8080, 8443, 9443, 2053, 2083, 2087, 2096, 8880); 24-byte-header AEAD frames; opcode dispatch (`0x20` start attack, `0x21`/`0x22` stop).
- **Attack methods:** Layer-7 HTTP/1.1, HTTP/2, and HTTP/3-over-QUIC floods, plus the inherited Layer-3/4 set (TCP flag floods, ICMP, Source Engine / SAMP game queries, SSDP) selected by method name.
- **String obfuscation:** three encrypted tables; RC4 keystream XORed with a Galois-LFSR keystream (polynomial `0x80200003`), key `a35fc8912d764eb0671af38439c25b0e`.
- **Host tradecraft:** self-staging into writable mounts (`.c.so`), process-name spoofing (`kworker` and an argv tag), competitor process-killer, watchdog-device handling, SSH-banner scanner.
- **Quirk:** the prior Linux build carried an ML-KEM-768 (Kyber) key-encapsulation step in the C2 key-establishment path; this build uses a classical X25519 exchange only; post-quantum primitives are presumably harder to carry across the constrained, varied IoT architectures the family builds for.

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hash |
| [domains.csv](iocs/domains.csv) | ENS C2 name and delivery host |
| [ips.csv](iocs/ips.csv) | C2 status (dead drop parked at analysis time) and port set |
| [keys.csv](iocs/keys.csv) | ENS name/resolver/selector, config XOR mask, string-table key, Infura project ID, owner wallet |
