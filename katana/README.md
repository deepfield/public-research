# Katana

*Last updated: 2026-03-17*

## Overview

Katana is a Mirai-derivative DDoS botnet targeting Android TV set-top boxes through ADB exploitation via residential proxy services. It packages a DDoS bot with an on-device compiled kernel rootkit inside an Android APK, giving it persistence and stealth unusual for this class of malware. At least 30,000 active bots have been observed, with attack volumes reaching 150 Gbps.

The name "Katana" is a community attribution tracked by ThreatFox and Malpedia under `elf.mirai`. The bot self-identifies as MIRAI via its Busybox probe strings.

## Report

See [`report.md`](report.md) for the full technical analysis, including delivery chain, C2 protocol, rootkit internals, attack methods, persistence mechanisms, and an assessment of AI-assisted development indicators.

## Prior research

- [**Malpedia**](https://malpedia.caad.fkie.fraunhofer.de/details/elf.mirai) — lists "Katana" as an alias under `elf.mirai`
- [**Avira**](https://www.darkreading.com/iot/avira-researchers-discover-a-new-variant-of-mirai) (October 2020) — earliest documented reference to Katana as a Mirai variant
- **ThreatFox** (abuse.ch) — tracks Katana IoCs under `elf.mirai` with alias `Katana` (first seen 2025-11-07)

## Technical summary

- **Lineage:** Mirai fork with substantial custom additions (rootkit, APK wrapper, custom domain encryption)
- **Delivery:** ADB exploitation of uncertified AOSP Android TV devices via residential proxy services; no built-in scanner
- **C2 resolution:** 3 encrypted domains (custom 5-step cipher) + runtime domain rotation via `0xFF85` command + hardcoded fallback IP
- **C2 hosting:** Omegatech (AS202412, Seychelles) and SIA GOOD (AS39900, Latvia)
- **Architectures:** ARM5, ARM7, AArch64, x86, x86-64 (APK bundles all five)
- **Crypto:** Single-byte XOR (`0x31`) for string table; 16-byte XOR key for domain cipher
- **Rootkit:** On-device compiled kernel module (`wlan_helper.ko`) via TinyCC; hooks 5 syscalls for process/file hiding
- **Persistence:** 5 layers (AlarmManager, 40+ broadcast receivers, Magisk module, system partition, SysVinit scripts)
- **DDoS:** 11 attack methods including protocol-specific floods (FiveM, SSH, MySQL, SMTP, IRC, FTP, LDAP, VSE, TeamSpeak 3, Discord)
- **Self-destruct:** 3-day dead-man's switch removes all persistence artifacts if C2 is unreachable

## Detection

The [`detection/`](detection/) directory contains detection rules and host-based indicators:

| File | Contents |
|------|----------|
| [katana.yar](detection/katana.yar) | YARA rule for ELF binary detection |
| [host_indicators.csv](detection/host_indicators.csv) | Filesystem paths, ports, and artifacts for host-based detection |

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 domains and scanner report domains |
| [ips.csv](iocs/ips.csv) | C2 IPs, staging servers, fallback infrastructure |
| [hashes.csv](iocs/hashes.csv) | SHA-256 hashes for APK, bot binaries, rootkit components, and TinyCC compilers |
| [keys.csv](iocs/keys.csv) | Cryptographic keys and APK certificate serial |
