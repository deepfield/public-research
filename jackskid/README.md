# Jackskid

*Last updated: 2026-03-24*

## Overview

Jackskid (also reported as "RCtea" by CNCERT) is a Mirai-derivative DDoS botnet sharing a code lineage with Aisuru. It was first publicly documented by [Foresiet](https://foresiet.com/blog/mirai-botnet-jackskid-resurgence-nov-2025-iot-threats/) in November 2025. The family uses a custom RC4 cipher with LCG post-processing (seed `0xe0a4cbd6`), the same modification found in Aisuru gen2, establishing a shared development lineage.

## Report

The full technical report is available at [`report.md`](report.md). It covers reverse engineering of 80+ samples across 13 build generations, config decryption, DDoS handler analysis, C2 infrastructure tracking, and the post-disruption ENS pivot following the [March 19 law enforcement action](https://www.justice.gov/usao-ak/pr/authorities-disrupt-worlds-largest-iot-ddos-botnets-responsible-record-breaking-attacks).

## Prior research

- Foresiet — [Mirai Botnet Jackskid Resurgence](https://foresiet.com/blog/mirai-botnet-jackskid-resurgence-nov-2025-iot-threats/) (Nov 2025) — first public documentation of the family
- CNCERT — [RCtea botnet risk advisory](https://www.secrss.com/articles/87776) (Feb 2026) — named "RCtea" for the RC4+ChaCha20+TEA encryption stack

## Technical summary

- **Lineage:** Mirai fork sharing code with Aisuru gen2 (RC4+LCG fingerprint, shared constants, crossover builds)
- **C2:** DNS-over-HTTPS via mbedTLS; random port selection from pool of 60–84 ports
- **Crypto:** RC4+LCG (`DEADBEEF CAFEBABE E0A4CBD6 BADC0DE5`), XTEA (6 rounds), ChaCha20
- **Internal name:** `softbot` (from unstripped debug build)
- **Attack vectors:** 14 DDoS methods, telnet brute-force scanner (143+ credentials), ADB-based Android infection
- **Architectures:** ARM, x86, x86-64, MIPS

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 domains with resolution method, first-seen date, and current status |
| [ips.csv](iocs/ips.csv) | C2 and delivery IPs with ASN, role, and first-seen date |
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hashes with architecture and description |
| [keys.csv](iocs/keys.csv) | Cryptographic keys and protocol constants |
