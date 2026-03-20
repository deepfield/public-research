# MossadProxy

*Last updated: 2026-03-20*

## Overview

MossadProxy is a DDoS botnet targeting Android TV and IoT devices via ADB, delivered through an APK wrapper named `com.android.door`. Despite its name and native binary being called `libproxy.so`, the analyzed build contains no proxy functionality — it is a DDoS bot. The binary references companion files `libdevice.so` (the confirmed Kimwolf proxy binary name) and `libvpn.so` that are not present in this build.

## Technical summary

- **Codebase:** Independently developed C codebase, compiled with Clang/LLD 19.0 (distinct from all other ecosystem families)
- **C2:** Custom DNS resolution via 5 hardcoded nameservers (Cloudflare, Quad9, Level3, OpenDNS, Yandex); UDP peer discovery; ChaCha20 + xxHash wire protocol
- **Attack methods:** 8+ DDoS handlers (UDP floods, TCP SYN, DNS amplification/reflection), remote shell, competitor-killing watchdog
- **Ecosystem links:** Identical 15-port C2 pool with Aisuru gen2, Kimwolf binary allowlist, `kamru` domain registrant overlap, shared ASN (AS41745)
- **Active period:** January 2026 through present

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 domains with registration and resolution details |
| [ips.csv](iocs/ips.csv) | Staging and C2 IP addresses with ASN and role |
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hashes (ELF binaries, APKs, stagers) |
| [keys.csv](iocs/keys.csv) | RC4 config key, ChaCha20 keys, APK signing certificate |
