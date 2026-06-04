# Datasurge

*First published: 2026-06-04*

## Overview

Datasurge is a Mirai-lineage DDoS botnet first seen on MalwareBazaar on 2026-05-31, distributed as a statically-linked ARM ELF placed on devices via ADB exploitation. It has no self-propagation — no telnet scanner, credential list, or exploit modules. Instead, the operator invests the engineering that other forks spend on spreading into retention: a competitor-killing scanner module larger and more complex than the DDoS attack engine, which finds and destroys rival malware, locks down writable directories, and watches the filesystem via inotify. The bot self-brands with the startup banner `Datasurge-owns-you!!!`.

Beyond DDoS, Datasurge grafts light RAT capabilities onto the Mirai base: a remote shell with output capture, a file browser that exfiltrates up to 1 MB per request, and process-name spoofing that rotates through 41 kernel thread names every 60 seconds. C2 infrastructure is minimal — one domain (`datasurge-bot.com`, no A record as of 2026-06-04) and one fallback IP (`5.175.223[.]69:8082`, NextHost, Germany).

## Report

See [`report.md`](report.md) for the full technical analysis: ROT13+XOR config table, cleartext length-prefixed C2 protocol, 10-method attack engine (incl. GRE/ESP floods, HTTP-inside-GRE, TCP STOMP), the five-pass competitor scanner and three-tier classifier, inotify watcher and directory lockdown, operator remote-access opcodes, stealth/persistence, and Mirai lineage.

## Prior research

- GHOST / Breakglass Intelligence, ["DataSurge Botnet — Mirai Variant IoT Dropper with DNS-Based Dynamic C2"](https://intel.breakglass.tech/post/datasurge-botnet-mirai-variant-iot-dropper-with-dns-based-dynamic-c2), 2026-03-13 — first public identification; documents the multi-stage dropper chain (`bbc` shell script → arch-specific ELF payloads), DNS TXT-based dynamic C2 resolution, payload distribution from `5.175.223[.]124`, and C2 at `130.12.180[.]151:25565`. Our sample (first seen 2026-05-31 on MalwareBazaar) is a later build from the same campaign, using a different host in the same /24 for C2 fallback

## Technical summary

- **Lineage:** Mirai fork, statically linked uClibc ELF, GCC 3.3.2/4.2.1 (Debian prerelease + Aboriginal Linux) toolchain; standard Mirai config-table and `attack_parse` TLV structure
- **Delivery:** Externally placed via ADB exploitation; no self-propagation
- **C2 domain:** `datasurge-bot.com` (registered 2026-02-03, IONOS, Cloudflare NS; no A record as of 2026-06-04)
- **C2 fallback:** `5.175.223[.]69:8082` (NextHost / GHOSTnet, DE)
- **C2 transport:** Cleartext TCP, length-prefixed framing (`[u16 BE length][opcode][payload]`); 10-byte registration
- **C2 resolution:** Custom DNS client to hardcoded `1.1.1.1:53` plus 8 fallback resolvers; DNS TXT record on C2 domain carries the current C2 IP (base64 + hex-escape + XOR `0x30`)
- **Config obfuscation:** ROT13 on letters then single-byte XOR `0x30` (folded from key `0xCAFEBABE`); 4-entry table
- **Attack methods:** 10 (UDP, TCP flag/connect, ICMP, GRE, ESP, HTTP-inside-GRE, TCP STOMP, DNS); IP spoofing supported
- **Scanner/killer:** Five-pass `/proc` scan every 10s, 125-pattern blacklist, three-tier classifier (pattern → backdoor → entropy), 25-path allowlist, 15-port allowlist, inotify watcher, `chmod 0`/`chown 0:0` directory lockdown; C2-toggleable
- **Operator access:** Remote shell with output (`0x12`), fire-and-forget exec (`0x14`), directory listing (`0x10`), file exfil up to 1 MB (`0x11`)
- **Stealth:** Process-name rotation across 41 kernel thread names every 60s (`prctl` + argv + `/proc/self/comm`); double-fork daemonization; single-instance `.d_lock` with self-healing re-exec
- **PRNG:** xoshiro128 seeded via ChaCha-like init from `/dev/urandom`
- **Quirk:** Debug build shipped to production — verbose `[DEBUG_MODE_ATTACK]` trace logging left in every attack function

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 domain and operator infrastructure |
| [ips.csv](iocs/ips.csv) | C2 and payload distribution IPs |
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hash |
| [keys.csv](iocs/keys.csv) | Config table XOR key |
