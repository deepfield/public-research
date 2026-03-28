# Drifter

*Last updated: 2026-03-28*

## Overview

Drifter is a previously undocumented DDoS botnet targeting Android TV devices via ADB. It competes for ADB-exposed devices with [MossadProxy](../mossadproxy/), [Jackskid](../jackskid/), and [Kimwolf](../kimwolf/), families documented as part of the [Aisuru ecosystem](../reports/2026-03-20-aisuru-ecosystem.md). Drifter shares no code, infrastructure, or cryptographic material with any of them, suggesting an independent operator on the same contested attack surface.

Its C2 domains are named after IP camera brands (`hikvision-cctv[.]su`, `nvms9000[.]su`), chosen to blend with surveillance management traffic on network segments shared by its target devices. First observed 2026-03-28.

## Report

See [`report.md`](report.md) for the full technical analysis, including C2 protocol, DNS obfuscation, domain generation algorithm, attack methods, and host behavior.

## Prior research

No public reporting on Drifter has been identified as of 2026-03-28.

Related prior work:
- [Aisuru ecosystem report](../reports/2026-03-20-aisuru-ecosystem.md) — documents the broader ADB TV box attack surface and competing families (Nokia Deepfield ERT, March 2026)
- Synthient, ["A Broken System Fueling Botnets"](https://synthient.com/blog/a-broken-system-fueling-botnets) (Jan 2026) — Kimwolf infection mechanism via residential proxy ADB exploitation

## Technical summary

- **Lineage:** Independent; Mirai-inspired patterns (port lock, OOM protection, process masquerading) but no shared code
- **Delivery:** ADB exploitation of uncertified AOSP Android TV devices; APK wrapper (`com.siliconworks.android.update`)
- **C2 domains:** `daylightbomb[.]elite` (OpenNIC), `hikvision-cctv[.]su`, `nvms9000[.]su` — CCTV brand masquerading
- **C2 resolution:** Custom DNS resolver (`194.50.5[.]27`), 16-bit half-swap IP obfuscation in A records, DGA subdomains
- **C2 fallback:** Telegram dead-drop resolver (`t.me/disconnect`)
- **C2 hosting:** Linode/Akamai (16), DigitalOcean (4), GHOSTnet (4), Onidel (1) — 25 IPs total
- **Architecture:** ARM EABI4, 71 KB, statically linked, stripped
- **Crypto:** Custom stream cipher (RC4 KSA + AES MixColumns hybrid)
- **DDoS:** 8 attack methods (UDP, TCP SYN/ACK/PSH, ICMP, GRE floods); IP spoofing on 7 of 8
- **Anti-competition:** Port 2625 TCP bind lock + process scanning via `/proc/net/tcp`
- **Self-destruct:** Unconditional 7-day timer
- **Scale:** Attacks up to 2.6 Tbps from ~80,000 sources observed

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 domains, connectivity check, STUN server |
| [ips.csv](iocs/ips.csv) | C2 IP pool (25 IPs), custom DNS resolver, STUN, observed targets |
| [hashes.csv](iocs/hashes.csv) | APK and native binary SHA-256 hashes |
