# DDoSia

*First published: 2026-07-05*

## Overview

DDoSia is the DDoS client of **NoName057(16)**, a pro-Russian hacktivist group that has run its botnet as a crowdsourced, gamified operation since 2022. It is not a new or emerging threat. Volunteers install the client (distributed through the group's Telegram channel), paste in a provisioned identifier, and the client pulls an AES-256-GCM-encrypted list of targets from command-and-control, floods them, and reports its results back for a cryptocurrency-reward **leaderboard**. There is no self-propagation and no scanner: the "botnet" is a download link and a competition. Deepfield ERT has tracked the family for years, since it first began landing on European customers.

The build analyzed here (`d_lin_x64`, Linux x86-64, Go 1.22) is, underneath, an ordinary flooder. What is notable is the mismatch between the group's press profile, among the most-covered DDoS operations in Europe, and the software itself, which is unremarkable. The recent engineering has gone mostly into being harder to reverse-engineer rather than harder to defend against: the binary is obfuscated with **garble** (`-literals`) and carries two manual Go-header tampers (a clobbered `.gopclntab` magic and a wiped build version) that defeat off-the-shelf Go RE tooling, both reversible with a 12-byte edit. The flood engine quietly grew a raw-packet component (**gopacket**, for Layer-3/4 SYN and UDP floods) and an HTTP/3-over-QUIC component (**quic-go**); both are off-the-shelf and first-seen-for-DDoSia here. The `<4char>.<16char>.{info,live}` DGA-style rendezvous domains it used in mid-2025 now appear to be out of the actor's hands and serve no targets; live tasking is direct-IP.

The finding that matters most is about the numbers, not the packets. The reward leaderboard runs on the honor system: the client reports its own `success`/`total` counts via `set_attack_count`, and the C2 accepts them without verification (it does not even validate the `K` cookie). We reversed the session crypto (the login/response AES-256-GCM key is derived from the client's own cookie, `(C + "0")[-32:]`) and validated the full chain live against a serving C2 (`185.76.78[.]136`) on 2026-07-05, standing up a passive client that registers, pulls the live 200-target list, and can file fabricated perfect scores without sending any attack traffic. The group's published impact figures are downstream of exactly this self-reported, trivially fabricated telemetry. Their public "proof" is no sturdier: the group posts check-host.net reachability screenshots as evidence a target is down, which also flags sites that have merely geo-fenced or challenged foreign traffic, so a working defense can be paraded as a kill.

## Report

See [`report.md`](report.md) for the full analysis: the crowdsourced leaderboard model; the garble obfuscation and Go-header tampers and their reversal; the gopacket and quic-go flood engines; the plaintext-HTTP C2 API and cookie scheme; the DGA-style C2 domains; the reversed session crypto and the RSA key transport; the honor-system reporting path and the passive-monitor fabrication; the claimed-versus-real impact after Operation Eastwood; and a note for the newsroom on treating the group as the unreliable narrator it is.

## Related research

DDoSia is well documented, and this report credits that record generously (see the report's attribution section): Sekoia, SentinelLABS, Avast/Gen Digital, Recorded Future, AhnLab, Team Cymru, Censys, the community MISP DDoSia config feed, and tgragnato on the malware; CIRCL, whose witha.name tracker and `@noname57bot` feed publish the decoded daily target lists in near real time; Europol on the July 2025 Operation Eastwood takedown; and Imperva on the measured (as opposed to claimed) impact. The novel findings here (the garble/pclntab/buildinfo tampers, the gopacket and quic-go engines, the DGA C2 scheme, the reversed session crypto, and the honor-system reporting) are flagged as such against that record.

## Technical summary

- **Family / actor:** DDoSia (NoName057(16)). Crowdsourced, gamified DDoS; crypto-reward leaderboard; Telegram distribution; no self-propagation.
- **This sample:** `d_lin_x64`, Linux x86-64 ELF, dynamically linked (libc), stripped, ~18.8 MB, Go 1.22 (CGO). SHA-256 `2aaf3c08…`. First seen 2024-11-06.
- **C2 API (plaintext HTTP):** `/client/login`, `/client/get_targets`, `POST /client/set_attack_count`.
- **C2 hosts:** live `185.76.78[.]136` (2026-07-05); `151.236.18[.]179` (core), `65.38.121.22` (pcap), `153.75.85[.]190` (down).
- **C2 domain scheme (legacy):** `<4char>.<16char>.{info,live}` DGA-style subdomains, seen over a rotating IP pool in mid-2025; the rendezvous domains have since gone out of the actor's hands and serve no targets, and live tasking is direct-IP.
- **Identity:** per-volunteer `client_id` = provisioned bcrypt string (`$2a$16$…`); the bot does not compute bcrypt (no `OrpheanBeholderScryDoubt`), it presents a value supplied to it.
- **Cookies:** `U`=bcrypt client_id, `C`=`<uuid4>-<pid>`, `T`=`-<unix ns>` (POSTs), `K`=`base32(RSA blob)` (not validated by the C2).
- **Session crypto:** AES-256-GCM keyed on ASCII of `(C + "0")[-32:]`; the same key encrypts the login body and decrypts the `get_targets` response (nonce prepended). Reversed and validated live 2026-07-05.
- **Key transport:** `K` = `base32(RSA-2048 PKCS#1 v1.5(server_pub, M))`, `M` = 2-byte prefix ‖ 46 random bytes; server pubkey real and accepted, but the response key is the session key, not derived from `M`.
- **Config:** AES-256-GCM target list; schema `target_id/request_id/host/ip/type/method/port/use_ssl/path/body`; `randoms[]` drives `$_N` (random) / `$-N` (per-target) substitution tokens.
- **Attack methods:** `tcp` (`syn`/`syn_ack`/`ack`/`PING`→ICMP), `udp` (`udp_flood`), `http` (GET/POST), `http2` (ordinary GETs, not Rapid Reset), `http3` (HTTP over QUIC), `nginx_loris` (Slowloris). In practice the daily target lists are overwhelmingly Layer-7 HTTP(S) floods against websites, using `$_N`/`$-N` cache-buster substitution to push requests past caches onto the origin; the L3/4 methods sit in the builder but rarely in the lists. Application-layer, and low-volume by DDoS standards.
- **Libraries:** gopacket (raw L3/L4); crypto/tls (stdlib, not utls) + net/http (http/http2) + quic-go (http3) for L7. gopacket and quic-go/http3 are novel for DDoSia.
- **Obfuscation:** garble `-literals`, plus a clobbered `.gopclntab` magic (`f3 33 18 d2`) and a wiped `.go.buildinfo` version (`"unknown"`); both reverse with a 12-byte edit. Not previously documented for DDoSia.
- **Reporting:** `set_attack_count` reuses the session key; client-reported `success`/`total`/`request_len` accepted without verification; a passive monitor can file fabricated perfect scores with no attack traffic.
- **Privileges:** root required for the raw-socket L3/L4 methods (full `setuid`/`setgid` family present; cgo DNS).

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hash |
| [domains.csv](iocs/domains.csv) | DGA-style C2 subdomains |
| [ips.csv](iocs/ips.csv) | C2 IPs (live, core/pcap, and DGA-resolved) with status |
| [keys.csv](iocs/keys.csv) | RSA C2 public-key modulus, session-key derivation, and reporting-transport notes |
