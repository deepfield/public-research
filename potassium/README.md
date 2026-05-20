# Potassium

*Last updated: 2026-05-20*

## Overview

Potassium is a Mirai-derived DDoS botnet first publicly identified by [@deobfuscately](https://x.com/deobfuscately/status/2033923869782712514) (Synthient) in March 2026 and named after the staging URL path `/1000mgofpotassiumaday/arm7`. We have since traced at least three campaigns to the same codebase: `vitacoco` (the original), `iambig` (a Dutch-themed C2 root from April), and `botlesscucks` (a third C2 root that appeared in May 2026). All three share byte-identical ChaCha20 key and nonce material, an 8-digit bot seed, a 19-byte registration header, and the C2 protocol.

What distinguishes Potassium from the dozens of Mirai forks we track is not the DDoS capability, which is standard, but the choices: ChaCha20 for the static config table (the first time we have seen ChaCha20 used this way in a Mirai variant), a single static byte (`0xED`) for everything on the wire, a named reverse-shell protocol (`SHELL` / `SHOUT`) on the same channel as attack commands, and a DNS misdirection scheme that swaps the two 16-bit halves of every resolved A record before `connect()`.

## Report

See [`report.md`](report.md) for the full technical analysis: campaign attribution, DNS word-swap mechanism, ChaCha20 config table and XOR wire encoding, 20-entry attack dispatch table, SHOUT reverse-shell protocol, 10-day attack telemetry, cross-family same-target observation, and operator linguistic artifacts.

## Prior research

- [@deobfuscately](https://x.com/deobfuscately/status/2033923869782712514) (Synthient), 2026-03-17 — first public identification of the installer and `vitacoco` C2 domain; named the family
- Nokia Deepfield ERT, [Mastodon update](https://infosec.exchange/@jmeyer), 2026-05-07 — confirmation of the `iambig` variant, sample hashes, byte-swap C2 mechanism. One framing in that update is corrected by this report: C2 protocol is raw TCP with `0xED` XOR, not HTTP. ADB delivery to Android devices is consistent with our observations; the config table additionally points at HiSilicon DVR/NVR/IP camera as a broader target class

## Technical summary

- **Lineage:** Mirai fork, statically linked ELF, Aboriginal Linux GCC 4.2.1 toolchain (shared with [Katana](../katana/) and Flameblox — common build environment, not shared code)
- **C2 transport:** Raw TCP, no TLS, no per-session key exchange; payloads XOR-encoded with `0xED`
- **C2 resolution:** Custom in-binary DNS client to `8.8.8.8:53`; bot swaps the two 16-bit halves of the resolved IP (`A.B.C.D → C.D.A.B`) before `connect()`. Public DNS A records are decoys in unrelated ASNs (Vermont University, NRC Canada, AWS, Telecom Italia, Kazakh broadband)
- **Crypto:** IETF ChaCha20 (counter=1) for the 222-entry static config table; static single-byte XOR (`0xED`) for all wire traffic. Same key and nonce across every analyzed sample
- **Attack vectors:** 20-entry dispatch table (UDP/TCP/HTTP/ICMP/GRE floods); IDs reassigned relative to reference Mirai, so handler name does not always match wire transport (e.g. `udp_raw` is DGRAM, `tcp_socket` is UDP)
- **Reverse shell:** `SHELL` command in (up to 1010 bytes), `SHOUT` response back (up to 4090 bytes), `/bin/sh -c` brokering; capability ships on every infected device
- **Port rotation:** 11 ports per build, two distinct pools — original samples through 2026-04 use one pool; the 2026-05-01 `iambig` rebuild and the entire `botlesscucks` campaign use a different pool. Detection guidance based on the original pool alone will miss the newer infrastructure
- **Single-instance lock:** TCP listener on port 1234 bound to the device's egress IP (not `0.0.0.0`); not a backdoor — accept handler closes, kills children, and exits
- **Architectures:** ARM, ARM7, MIPS, MIPSEL, x86, x86_64, i486, i686, PPC440, SH4 (10-arch rebuild batch on 2026-04-07)
- **Operator:** mostly English branding (Vita Coco enthusiasm, `botlesscucks`, the motto, staging paths), with the `iambig` campaign in idiomatically correct Dutch (using `kanker` as an intensifier) and a Dutch campaign tag `hoofdzak` — indicating at minimum Dutch fluency, not necessarily Dutch-first

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 roots and subdomain candidates across all three campaigns |
| [ips.csv](iocs/ips.csv) | C2 decoys, word-swapped real C2 IPs, staging IPs |
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hashes by architecture and campaign |
| [keys.csv](iocs/keys.csv) | ChaCha20 key/nonce/counter, XOR key, bot seed, killer port |
