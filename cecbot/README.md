# CECbot

*Last updated: 2026-03-21*

## Overview

CECbot is a purpose-built Android TV DDoS botnet and residential proxy platform, deployed alongside [Katana](../katana/) as its operational successor. It shares no code with Katana while reusing the same package name, target device population, and C2 server. First observed 2026-03-20.

CECbot is the first known botnet to weaponize HDMI Consumer Electronics Control (CEC) in the wild, giving the operator the ability to put the connected television to standby to hide activity from the user. CEC commands are not triggered automatically — each requires an explicit C2 instruction, and CEC support varies across Android versions.

## Report

See [`report.md`](report.md) for the full technical analysis, including C2 protocol, HDMI-CEC abuse, attack methods, persistence mechanisms, and comparison to Katana.

## Prior research

No public reporting on CECbot has been identified as of 2026-03-21.

Related prior work:
- [Katana report](../katana/report.md) — predecessor botnet on the same operator's infrastructure
- Puche Rondon (2021) — [doctoral dissertation on CEC as an IoT attack vector](https://digitalcommons.fiu.edu/record/13555/files/FIDC010451.pdf)

## Technical summary

- **Lineage:** Clean-sheet Android application (Java + JNI); no code overlap with Katana or Mirai
- **Delivery:** ADB exploitation of uncertified AOSP Android TV devices
- **C2 protocol:** Curve25519 ECDH + Ed25519 server auth + ChaCha20-Poly1305 AEAD; `0xBEEF` frame magic
- **C2 resolution:** 2 clearnet domains (fast-flux, source-IP filtered) + Tor .onion fallback + dynamic domain push
- **C2 hosting:** Omegatech (AS202412, Seychelles), shared with Katana C2
- **Architectures:** armeabi-v7a, arm64-v8a
- **Crypto:** Ed25519 server identity verification, HKDF-SHA256 key derivation, 8-byte XOR for string obfuscation
- **Persistence:** 9 layers (foreground service, AlarmManager, JobScheduler, broadcast receiver, native watchdog, shell watchdog, root boot scripts, OOM lock, ADB hijack)
- **DDoS:** 11 native attack methods via JNI; HTTP/HTTPS L7 with dynamic TLS, HTTP/2, 660+ referers
- **HDMI-CEC:** Standby, bus scan, and arbitrary CEC frame injection via cec-client
- **TV box takeover:** Home launcher hijack, SELinux bypass, OTA sabotage (6 chipset vendors), package verification bypass
- **Proxy:** SOCKS5 listener + reverse connect-back proxy with per-bot auth keys and geo-routing via external IP; architecture mirrors commercial residential proxy SDKs

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 domains including Tor fallback |
| [ips.csv](iocs/ips.csv) | C2 IPs and fast-flux relay nodes |
| [hashes.csv](iocs/hashes.csv) | APK SHA-256 hash |
| [keys.csv](iocs/keys.csv) | Ed25519 server public key, XOR key, Tor response key |
