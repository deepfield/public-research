# Cecilio

*Last updated: 2026-03-20*

## Overview

Cecilio is a CatDDoS derivative that replaced the original ChaCha20 table encryption with a modified RC4 cipher. It is operationally adjacent to the Aisuru/Jackskid ecosystem (shared credentials, domain registrant overlap, campaign tags) but does not share code with either family.

## Prior research

- QianXin TIC — [New Botnet CatDDoS Continues to Evolve](https://ti.qianxin.com/blog/articles/new-botnet-catddos-continues-to-evolve-en/) (Sep 2023) — original CatDDoS documentation
- XLab — [CatDDoS-Related Gangs Have Seen a Recent Surge in Activity](https://blog.xlab.qianxin.com/catddos-derivative-en/) (May 2024) — derivative ecosystem and shared-key analysis

## Technical summary

- **Lineage:** CatDDoS fork with modified RC4 replacing ChaCha20 for table encryption
- **C2:** OpenNIC alternative TLDs (`.dyn`, `.oss`, `.geek`) + public DNS (`.su`); DNS TXT encoding with 32-byte XOR key
- **Crypto:** Modified RC4 (j-carryover from KSA to PRGA), static 256-byte key across all observed builds
- **Active period:** May 2025 through present

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 domains with resolution method and status |
| [ips.csv](iocs/ips.csv) | C2 IP addresses with hosting and role |
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hashes with architecture and description |
| [keys.csv](iocs/keys.csv) | Cryptographic keys including RC4 key and DNS TXT XOR key |
