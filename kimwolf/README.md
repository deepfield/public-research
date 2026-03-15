# Kimwolf

*Last updated: 2026-03-15*

## Overview

Kimwolf is an Android-targeting botnet (3M+ active devices observed) that operates as a dual-purpose platform: residential proxy network (96.5% of activity) and DDoS. Kimwolf has operational links to the Aisuru DDoS botnet, including shared signing certificates and overlapping infrastructure, but represents a distinct operational focus — monetizing compromised devices as proxy nodes through commercial SDKs (ByteConnect, PacketStream) while retaining volumetric DDoS capability.

The botnet uses Ethereum Name Service (ENS) domains as a blockchain-based dead-drop for C2 address distribution, making traditional DNS takedowns ineffective. C2 addresses stored on-chain are obfuscated with per-variant XOR schemes and must be decoded by the bot at runtime.

## Prior research

- QiAnXin XLab — [Kimwolf Botnet](https://blog.xlab.qianxin.com/kimwolf-botnet-en/) — core analysis: infections, ByteConnect/PacketStream integration, ENS-based C2, link to Aisuru
- Synthient — [A Broken System Fueling Botnets](https://synthient.com/blog/a-broken-system-fueling-botnets) — Kimwolf infection mechanism via residential proxy ADB exploitation; IoCs and samples at [synthient/public-research](https://github.com/synthient/public-research/tree/main/2026/01/kimwolf)

## Technical summary

- **Lineage:** Mirai fork with substantial custom additions; operational links to Aisuru
- **Primary function:** Residential proxy network (SOCKS5/HTTP relay) monetized through ByteConnect and PacketStream SDKs
- **Secondary function:** Volumetric DDoS with 10+ attack handlers (TCP SYN/ACK/stomp/PSH, UDP with CIDR source randomization, ICMP, game-server targeting)
- **C2 resolution:** ENS blockchain dead-drop — queries Ethereum smart contracts for XOR-obfuscated C2 addresses stored in text records; falls back to hardcoded IPs or Tor hidden service
- **ENS domains:** `pawsatyou.eth`, `re6ce.eth`, `byniggasforniggas.eth` — each with distinct text record keys and XOR schemes
- **Architectures:** ARM32, AArch64, plus Android APK wrappers
- **Crypto:** Per-variant XOR keys for IP deobfuscation; custom RC4 with modified KSA for config encryption (key `PJbiNbbeasddDfsc`); stack-XOR for string obfuscation in binaries
- **Proxy SDKs:** ByteConnect (`new-endpoints.byteconnect.io`) and PacketStream integration
- **Evolution:** C/C++ with WolfSSL (Gen 1) → C++ with BoringSSL/AbcProxy SDK (Gen 2-3)
- **Android persistence:** Foreground service, boot receiver, wakelock, battery optimization bypass, bundled Tor for fallback C2
- **Tor fallback:** `rwbxbmflwm7andgmxeo3my7mqqs6najhou7o6f7xnxjsiuirzcnab4yd.onion` (dormant as of Mar 2026)

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 domains (ENS, .su, .st, .ru) with resolution method and status |
| [ips.csv](iocs/ips.csv) | C2 IP addresses from ENS record deobfuscation and hardcoded/dropper sources |
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hashes with architecture, generation, and variant info |
| [keys.csv](iocs/keys.csv) | XOR deobfuscation keys, ENS text record keys, protocol magic values |
