# kbotne

*First published: 2026-06-04*

## Overview

kbotne is a Mirai-lineage DDoS botnet distinguished by one unusually careful transport choice: it runs its C2 channel over a standard RFC 6455 WebSocket connection on port 80, the only Mirai-lineage family we track that does this. The surrounding implementation is less careful: hex-encoded debug/config strings, a process killer whose binary-scoring path mostly recognizes kbotne-like binaries, and a broken Android APK that has been publicly served since April 2026 despite not installing.

First observed in April 2026, delivered via netcat from `185.231.155[.]250`. Full decompilation of later unpacked builds shows a 10-method dispatcher. A source archive or reconstruction observed circulating on Telegram in May 2026 is treated as corroborating context, not primary evidence.

## Report

See [`report.md`](report.md) for the full technical analysis: WebSocket C2 protocol, 10-method attack dispatch table, build-dependent hex encoding, kbotne-shaped killer, persistence mechanisms, update poller, broken APK, and operator artifacts.

## Technical summary

- **Lineage:** Mirai-derived, statically linked ELF, independently developed (no code overlap with tracked families)
- **C2 transport:** WebSocket (`GET /connectlol HTTP/1.1`, `Sec-WebSocket-Version: 13`) on port 80; no encryption
- **C2 domain:** `real.botnet[.]st` resolved by the bot via custom DNS client to `8.8.8.8:53`; public DNS observed resolving to `81.28.12[.]12` on 2026-06-04
- **Config obfuscation:** Build-dependent hex-encoded ASCII tags/config strings; no cipher, recoverable with `xxd -r`
- **Attack methods:** 10 (TCP SYN/ACK/RST/stomp, UDP generic/plain, HTTP GET/POST, HTTPS, GRE)
- **Process killer:** Scores binaries against kbotne's own hex-encoded tags; strongest as anti-self-reinfection or anti-close-fork logic
- **Persistence:** Build-dependent: earlier Linux persistence (`systemd`, init.d, crontab, rc.local, `/.kbotne/kbotne`); June/update path `/data/local/tmp/sdk`
- **Operator tag:** `ilovecatgirlsowouwugaysex1111` (earlier/source-lineage artifacts)
- **Source context:** Source archive/reconstruction observed circulating on Telegram in May 2026; used as corroborating context only

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 domain |
| [ips.csv](iocs/ips.csv) | Delivery and C2 IPs |
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hashes |
