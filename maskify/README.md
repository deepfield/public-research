# Maskify

*Last updated: 2026-04-12*

## Overview

Maskify is a community-attributed name for a dual-purpose Android botnet: residential proxy and DDoS attack platform. The Earnify SDK (`io.earnify`) is a Rust-compiled native library distributed via IPFS and updated through the Ethereum Name Service (ENS). It bundles a TCP/UDP proxy relay, three DDoS flood modules, and Za Rodinu, a custom P2P mesh network not previously documented. The operator can push new capabilities to the fleet without modifying the APK.

The name comes from the operator's Cloudflare Workers staging domain (`maskify.workers[.]dev`), attributed by [Ben / Synthient](https://x.com/deobfuscately/status/2041151620486987898). First observed 2026-01-13 (v1 DGA domain registration). Maskify competes for ADB-exposed Android TV devices with families documented in the [Aisuru ecosystem report](../reports/2026-03-20-aisuru-ecosystem.md) and [Drifter](../drifter/).

## Report

See [`report.md`](report.md) for the full technical analysis, including ENS/IPFS update infrastructure, Za Rodinu mesh architecture, C2 protocol, DDoS attack methods, and proxyware model.

## Prior research

- Ben / Synthient ([@deobfuscately](https://x.com/deobfuscately/status/2041151620486987898)), "Earnify // Maskify Botnet" — community attribution linking Earnify SDK to the Maskify name, with loader domain and SDK infrastructure IOCs

Related prior work:
- [Aisuru ecosystem report](../reports/2026-03-20-aisuru-ecosystem.md) — the broader ADB TV box attack surface and competing families (Nokia Deepfield ERT, March 2026)
- [Drifter report](../drifter/report.md) — independent operator on the same attack surface, for architectural contrast (Nokia Deepfield ERT, March 2026)
- Synthient, ["A Broken System Fueling Botnets"](https://synthient.com/blog/a-broken-system-fueling-botnets) (Jan 2026) — residential proxy ADB exploitation vector

## Technical summary

- **Lineage:** Independent; Rust-compiled SDK with no code overlap with Mirai-derived families
- **Delivery:** ADB exploitation of Android TV boxes; v2 loader APK (`io.earnify`, 33 KB) downloads native SDK from IPFS
- **C2 protocol:** QUIC (UDP :4433) with TLS 1.3; 9 message types; length-prefixed binary framing
- **C2 resolution:** ENS text record on `russianaltushkawantsdickinside[.]eth`, ChaCha20-Poly1305 encrypted, Base64-encoded
- **C2 hosting:** QWINS (staging+C2), plus ENS-announced server
- **Architectures:** armeabi-v7a, arm64-v8a, x86_64
- **Crypto:** ChaCha20-Poly1305 (ENS record encryption), SHA3-256 (binary integrity), Ed25519 (mesh service announcements)
- **Update mechanism:** ENS → IPFS binary download → SHA3-256 verification → hot-reload via process kill; 60s poll interval
- **DDoS:** 3 flood methods (TCP, TLS, UDP) with server-pushed HTTP request templates (port 6969)
- **Proxy:** TCP/UDP relay with per-device bandwidth caps, port blocklist (10 ports), RFC1918/bogon filtering
- **Mesh network:** Za Rodinu — custom P2P overlay with QUIC transport, gossip discovery, Ed25519-signed service announcements, multi-hop routing (not yet active)
- **DGA:** v1 used a 10-domain DGA (not included in IoCs; v2 uses ENS for C2 resolution)

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [hashes.csv](iocs/hashes.csv) | v2 APK and native binary SHA-256 hashes |
| [domains.csv](iocs/domains.csv) | ENS name, staging domain |
| [ips.csv](iocs/ips.csv) | v2 C2 and staging IPs |
