# Aisuru

*Last updated: 2026-03-11*

## Overview

Aisuru is a Mirai-derivative DDoS botnet active since at least August 2024. The botnet has evolved through two distinct generations — transitioning from DNS A record C2 resolution to a DNS TXT scheme using CAFEBABE XOR-encoded IP addresses, and most recently adopting HMAC-SHA256 authentication with a new 0x1CEB00DA protocol magic.

## Prior research

The following publications provide essential context. Aisuru has been well-covered by the research community, and this entry builds on their work.

- QiAnXin XLab — [Botnets Never Die: An Analysis of the Large Scale Botnet AIRASHI](https://blog.xlab.qianxin.com/large-scale-botnet-airashi-en/) — core technical analysis of the AIRASHI stage: lineage, propagation, protocol/encryption changes, exploit use
- QiAnXin XLab — [The Most Powerful Ever? Inside the 11.5Tbps-Scale Mega Botnet AISURU](https://blog.xlab.qianxin.com/super-large-scale-botnet-aisuru-en/) — operator claims, scale, growth trajectory, major attacks
- PolySwarm — [AIRASHI Botnet](https://blog.polyswarm.io/airashi-botnet) — independent corroboration; cnPilot 0-day propagation, distributed infrastructure

## Technical summary

- **Lineage:** Mirai fork with substantial custom additions across generations
- **C2 evolution:** DNS A + HTTP GET (Aug 2024) → DNS TXT with CAFEBABE XOR (Oct 2024) → 0x1CEB00DA magic + HMAC-SHA256 auth (Mar 2026)
- **Architectures:** x86, x86-64, ARM, AArch64, MIPS, ARC700
- **Crypto:** 16-byte table encryption keys (gen1: `DEADBEEF CAFEBABE 12345678 90ABCDEF`; gen2: `PJbiNbbeasddDfsc`), custom RC4 with 5-pass LCG S-box scramble
- **Connectivity check:** HTTP GET to a legitimate third-party site before C2 contact
- **Android vector:** Transitional APKs observed bundling native ELF payloads (Sep 2025)

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 domains with resolution method, first-seen date, and current status |
| [ips.csv](iocs/ips.csv) | C2 IP addresses with ASN, role, and first-seen date |
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hashes with architecture and generation |
| [keys.csv](iocs/keys.csv) | Cryptographic keys and protocol magic values |
