# Vibenet

*First published: 2026-06-23 | Last updated: 2026-06-24*

> **Note:** Some indicators in the [`iocs/`](iocs/) files are slurs or otherwise offensive, chosen by the operators for branding and reproduced verbatim for detection.

## Overview

Vibenet (also known as Heilong, the tag its 2026 Android rebrand adopted) is a custom (non-Mirai) DDoS botnet family that targets Android TV and IoT devices through ADB, tracked by Deepfield ERT across multiple builds and rebrands. Its latest Linux build inverts the usual priorities of a flooding bot. Where most DDoS malware floods in cleartext or links a stock TLS library, this build ships a complete, hand-written **TLS 1.2/1.3 + QUIC v1 + HTTP/2 + HTTP/3** client in a binary that carries no libc at all, a browser on the wire. Every Layer-7 flood completes a real TLS or QUIC handshake with a fixed, browser-like fingerprint, so the attack traffic reads as ordinary HTTPS or QUIC to Layer-7 mitigation. The tell that this is camouflage rather than security: the bot validates no certificates at all. It will complete a handshake with any server that answers.

The bot does not carry a C2 domain or a hardcoded C2 IP. Instead it reads its current C2 from an Ethereum ENS text record (the name `alextyler.eth`, record key `description`), queried over HTTPS JSON-RPC after resolving provider hostnames with DNS-over-HTTPS. The record holds the C2 address as an obfuscated IPv6 string; decoded with the bot's own routine on 2026-06-23 it resolved to `127.0.0[.]1`: this build's dead drop in the off position, most likely not yet switched on. The v1 line's separate C2 channels were still live at the time, so this is not the whole botnet going dark; and because the record sits on a public ledger, it can be re-read to catch the C2 the moment it goes live. On-chain C2 is common in this scene; what sets this build apart is the implementation: a namehash computed at runtime, the C2 tucked into the standard `description` profile field, a decoy-laden IPv6 encoding, and an eleven-endpoint RPC failover list whose hostnames are resolved with DoH.

Underneath the new transport, the same Vibenet shows through. This build is part of v2, the ground-up standalone rewrite of a family whose v1 generation is the `libyahu`/`libkys` Android line. v2 is still under active development: this build (`58f80286`) and an earlier v2 build (`f2671998`) share an encrypted-string-table cipher and key that mark them one codebase, yet differ in ways that read as work in progress (the earlier one carried a post-quantum handshake step this one drops). The `meow` magic, the Layer-3/4 and game-query flood set, an SSH-banner scanner, a competitor process-killer, and self-staging into writable mounts carry the v1 lineage forward. Beyond the flood engine it also wires a SOCKS-style proxy relay into the command channel, so each infected host can serve as an exit node. The ENS dead drop places it alongside [jackskid](../jackskid/) and other tracked families that read C2 from the same public ENS resolver contract using different per-family encodings.

## Report

See [`report.md`](report.md) for the full technical analysis: the ENS dead-drop resolution chain (Keccak-256 namehash, public-resolver `text()` call, RPC rotation, DoH, XOR-IPv6 config decode), the embedded TLS 1.2/1.3 and QUIC v1 stack and its deterministic JA3/JA4 fingerprint, the absent certificate validation, the X25519 session handshake and opcode protocol, the Layer-7 and Layer-3/4 flood engine and attack-job table, the encrypted string tables and shared Vibenet tradecraft, and the ENS dead-drop cluster.

## Related research

This is original Deepfield ERT analysis. The v1 Android builds ship in the **MuhHeilong** APK wrapper, staged from hosts like `apk.alextyler[.]st`; that wrapper is shared across otherwise-unrelated families, so its presence is not by itself evidence of a shared operator, though its primary authorship most likely sits with this same operator. "Heilong" here names the family (the 2026 rebrand of Vibenet), distinct from the shared MuhHeilong packaging. The ENS dead-drop technique and the shared public resolver contract also appear in our [jackskid](../jackskid/) research.

## Technical summary

- **Lineage:** Vibenet family, v2 (a ground-up standalone rewrite of the prior v1 libyahu line), still under active development; statically linked, stripped, no-libc x86-64 ELF built with clang/LLD, issuing its syscalls inline. Same encrypted-string-table cipher and key as the earlier v2 build (`f2671998`).
- **Delivery:** Placed on Android TV / IoT devices via ADB; cross-architecture builds (ARM, MIPS, x86, PPC, SH4 suffixes present in the string tables).
- **C2 locator:** Ethereum ENS text record `alextyler.eth` / key `description`, on the public ENS resolver `0xF29100983E058B709F3D539b0c765937B804AC15`, selector `0x59d1d43c` (`text(bytes32,string)`).
- **C2 resolution transport:** JSON-RPC `eth_call` over the embedded HTTPS client, against eleven hardcoded RPC endpoints (fixed order, failover); provider hostnames resolved over DoH (`1.1.1.1`, `8.8.8.8`, `9.9.9.9`).
- **Config decode:** comma-separated obfuscated-IPv6 tokens; the real IPv4 is the last two 16-bit groups combined and XORed with `0x4ab73ce1`, emitted least-significant-byte first. Live value 2026-06-23 decoded to `127.0.0[.]1` (parked).
- **Embedded transport:** hand-rolled TLS 1.2 + TLS 1.3 + QUIC v1 + DoH client; no OpenSSL/BoringSSL/WolfSSL. ChaCha20-Poly1305 and AES-128-GCM AEADs, X25519 key exchange, SHA-256/HKDF, Keccak-256 for the ENS namehash.
- **TLS fingerprint:** deterministic, browser-like. Cipher list `1301,1303,c02f,cca8`; x25519-only key share; ALPN `h2,http/1.1`; fixed 9-extension order; no GREASE.
- **Certificate validation:** none. Certificate and CertificateVerify messages are absorbed into the transcript hash but never parsed or verified; only the Finished MAC is checked.
- **C2 session:** custom X25519 ECDH + Poly1305 (`server_auth`) handshake (raw TCP, no TLS) over a shuffled set of common web ports (mostly Cloudflare's proxied set) plus 9443 (443, 80, 8080, 8443, 9443, 2053, 2083, 2087, 2096, 8880), a direct connection dressed up by port number; 24-byte-header AEAD frames; opcode dispatch (`0x00` ping, `0x01` start attack, plus control/configuration opcodes).
- **Proxy relay:** dual-use SOCKS-style relay on the same C2 channel; opcodes `0x20`/`0x21`/`0x22` open, feed, and close outbound connections to operator-supplied destinations; up to sixteen concurrent tunnels tracked in a connection table.
- **Attack methods:** Layer-7 HTTP/1.1, HTTP/2, and HTTP/3-over-QUIC floods, plus the inherited Layer-3/4 set (TCP flag floods, ICMP, a real protocol-47 GRE flood, Source Engine / Quake / SAMP game queries, SSDP, and a broad amplification content menu), each named in the command and resolved to a numeric method id.
- **String obfuscation:** three encrypted tables; RC4 keystream XORed with a Galois-LFSR keystream (polynomial `0x80200003`), key `a35fc8912d764eb0671af38439c25b0e`.
- **Host tradecraft:** self-staging into writable mounts (`.c.so`), process-name spoofing (`kworker` and an argv tag), competitor process-killer, watchdog-device handling, SSH-banner scanner.
- **Quirk:** an earlier v2 build (`f2671998`) carried an ML-KEM-768 (Kyber) key-encapsulation step in its C2 key-establishment path; this build drops it for a classical X25519 exchange, one of several differences that mark v2 as still under development; post-quantum primitives are presumably harder to carry across the constrained, varied IoT architectures the family builds for.

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hash |
| [domains.csv](iocs/domains.csv) | ENS C2 name and delivery host |
| [ips.csv](iocs/ips.csv) | C2 status (dead drop parked at analysis time) and port set |
| [keys.csv](iocs/keys.csv) | ENS name/resolver/selector, config XOR mask, string-table key, Infura project ID, owner wallet |
