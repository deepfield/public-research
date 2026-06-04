# Datasurge: a rogue EDR agent with a DDoS module

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-06-04**

---

## Executive summary

Most Mirai forks spread first and ask questions later. They brute-force telnet, chain CVEs, scan port ranges, and race to claim as many devices as possible before the next reboot clears them from memory. Datasurge does not. It has no propagation scanner, no credential list, and no exploit integration. The operator appears to place each bot via ADB exploitation and then invests the development effort that other forks spend on spreading into making sure nothing else can take the device away.

The scanner/killer module, the code that finds and destroys competing malware, is larger and more complex than the DDoS attack engine. It has a 125-pattern blacklist, a three-tier process classifier with an entropy heuristic, a recursive inotify watcher that deletes new executables on sight, and a directory permission lockdown that strips write permissions from writable paths after the bot settles in. The operator can toggle the entire system off via a C2 command, deploy new tools to the device, and re-enable it. This is territorial defense with an [HOA](https://en.wikipedia.org/wiki/Homeowner_association)'s enthusiasm for enforcement.

The bot also provides capabilities absent from stock Mirai: a remote shell with output capture, a file browser that can exfiltrate up to 1 MB per request, and process name spoofing that rotates through 41 kernel thread names every 60 seconds. The result is a light RAT that happens to come with a 10-method DDoS engine.

C2 infrastructure is minimal: one domain (`datasurge-bot.com`, registered February 2026, currently with no A record) and one fallback IP (`5.175.223[.]69:8082`, NextHost, Germany). The bot announces itself at startup with the banner `Datasurge-owns-you!!!`, which at least makes the operator's intentions clear.

## Key findings

- **No self-propagation.** The arch-suffix strings in the binary (`.arm7`, `.mips`, `.x86_64`, etc.) are in the scanner's *kill list*, not a download table. The bot kills things named `arm7`; it does not fetch things named `arm7`.
- **Scanner as centerpiece.** The competitor-killing module has more code than the DDoS attack engine. It blacklists 125 patterns, classifies processes through three tiers (including an entropy heuristic), watches the filesystem via inotify, and locks down directory permissions. The operator can toggle the whole thing off from the C2 to deploy new tools.
- **Operator remote access.** File browser (directory listing + exfil up to 1 MB) and remote shell with output capture. These are RAT capabilities grafted onto a Mirai base.
- **Process name rotation.** Picks a random kernel thread name from a table of 41 and rotates every 60 seconds via `prctl`, argv overwrite, and `/proc/self/comm`. An administrator running `ps` sees `kworker/0:1`; a minute later, `migration/2`.
- **10 attack vectors** including GRE flood, ESP flood, fabricated HTTP-inside-GRE, semi-structured UDP/53 flood, and TCP STOMP with a real three-way handshake.
- **Debug build shipped to production.** The binary includes verbose `[DEBUG_MODE_ATTACK]` trace logging in every attack function: format strings for duration, vector, target count, option parsing, process slot management, and error conditions. The operator compiled with debug output and never turned it off, joining a proud tradition of accidentally shipping instrumentation that was only supposed to exist on the developer's machine.

## Config table and C2

Datasurge uses the standard Mirai config-table mechanism: entries stored encrypted in `.rodata`, decrypted on use via `table_unlock` / `table_lock`, re-encrypted immediately after. The encryption is ROT13 on ASCII letters followed by a single-byte XOR. Neither operation should be mistaken for serious cryptography; together they mostly make casual string extraction less convenient. The XOR byte is derived by folding the 4-byte key `0xCAFEBABE` across all four bytes: `0xCA ^ 0xFE ^ 0xBA ^ 0xBE = 0x30`.

The table contains four entries:

| Entry | Length | Decoded | Role |
|-------|--------|---------|------|
| 1 | 17 | `datasurge-bot.com` | C2 domain |
| 2 | 12 | `5.175.223.69` | fallback C2 IP |
| 3 | 4 | `8082` | C2 port |
| 4 | 21 | `Datasurge-owns-you!!!` | startup banner |

At startup, the bot prints the banner to stdout (a practice that serves no operational purpose but does tell anyone watching a compromised device's console exactly what they're dealing with) then resolves the C2 domain via UDP DNS. The DNS resolver is hardcoded to nine public DNS servers, including Google (`8.8.8.8`), Cloudflare (`1.1.1.1`, `1.0.0.1`), Quad9 (`9.9.9.9`), and five others (`4.4.8.8`, `222.222.67.208`, `220.220.67.208`, `14.14.140.94`, `15.15.140.94`). Transaction IDs are randomized by the bot's PRNG.

As of 2026-06-04, the domain `datasurge-bot.com` is registered (since 2026-02-03 via IONOS, behind Cloudflare nameservers) but has no A record: `NOERROR` with zero answers, not `NXDOMAIN`. The domain does, however, serve a TXT record containing a base64-encoded, hex-escaped, XOR-obfuscated payload that decodes to the C2 IP `5.175.223[.]69` — using the same XOR byte (`0x30`) as the config table. Breakglass Intelligence [documented this DNS TXT-based dynamic C2 mechanism](https://intel.breakglass.tech/post/datasurge-botnet-mirai-variant-iot-dropper-with-dns-based-dynamic-c2) in their March 2026 report on the same campaign, noting that it allows the operator to rotate C2 infrastructure without rebuilding binaries. The fallback IP `5.175.223[.]69:8082` is live, hosted on NextHost/GHOSTnet infrastructure in Germany (`NXTR-NET-EU`). A bare TCP probe connects successfully and is closed after roughly 30 seconds if no bot registration follows.

### C2 wire protocol

The bot connects via TCP and sends a 10-byte registration:

```
\x00\x00\x00\x03   protocol identifier (BE u32 = 3)
\x04               arch string length
arm7               arch identifier
\x01               status flag
```

Commands from the C2 use length-prefixed framing: a 2-byte big-endian length followed by the payload. The first byte of the payload is the opcode. The bot handles opcodes 0x10–0x1b as control commands; anything else is passed to the standard Mirai `attack_parse` function.

The C2 sends periodic heartbeat pings (opcode `0x16`). The bot must respond with `\x00\x02\x15\x01` (length=2, opcode=0x15, value=1) to stay connected.

A background thread manages internal IPC: a local TCP listener on `127.0.0.1:30071` accepts scanner kill reports (opcode `0xF0 0xA1`) from the forked scanner child and forwards them to the C2 socket. The scanner and the C2 connection run in separate processes; the localhost relay bridges them.

## Attack methods

Ten DDoS methods are registered at startup. Nine use raw sockets with `IP_HDRINCL`; method 2 is a real `SOCK_STREAM` connect flood, and method 7 briefly uses real TCP sockets to learn sequence/acknowledgment state before switching to raw packets. Source IP spoofing is supported via option key `0x11`. Every method is instrumented with `[DEBUG_MODE_ATTACK]` trace logging that prints duration, vector ID, target addresses, and option values to stderr. Useful during development, less so in production, and yet here we are.

| ID | Method | Socket | Notes |
|----|--------|--------|-------|
| 0 | UDP flood | `SOCK_RAW` / `IPPROTO_UDP` | Random or fixed port, configurable payload |
| 1 | TCP flag flood | `SOCK_RAW` / `IPPROTO_TCP` | Full IP+TCP headers, configurable flags, randomized seq/ack/window |
| 2 | TCP connect flood | `SOCK_STREAM` | Real connections, port 80 default, reconnects on RST |
| 3 | ICMP flood | `SOCK_RAW` / `IPPROTO_ICMP` | Echo request, random ID |
| 4 | GRE flood | `SOCK_RAW` / `IPPROTO_GRE` | Optional checksum, key, and sequence fields |
| 5 | ESP flood | `SOCK_RAW` / `IPPROTO_ESP` | Configurable SPI and sequence number |
| 6 | HTTP flood | `SOCK_RAW` / `IPPROTO_GRE` | Fabricated TCP+HTTP payload inside GRE encapsulation, no handshake |
| 7 | TCP STOMP | `SOCK_STREAM` + `SOCK_RAW` / `IPPROTO_TCP` | Real SYN→SYN-ACK→ACK handshake, then raw ACK flood with captured seq/ack |
| 8 | DNS flood | `SOCK_RAW` / `IPPROTO_UDP` | Semi-structured UDP/53 payload with randomized tail bytes |
| 9 | ICMP variant | `SOCK_RAW` / `IPPROTO_ICMP` | Alternate entry point into the ICMP handler |

The HTTP flood (method 6) constructs a complete `GET/DELETE/OPTIONS %s HTTP/1.1` request with `Host`, `User-Agent` (7 Firefox 147.0 variants across Windows, macOS, and three Linux distributions), `Accept`, `Accept-Language`, `Accept-Encoding`, and `Priority` headers. The request is placed inside a fabricated TCP segment (randomized seq/ack, no handshake) which is then encapsulated in a GRE packet and sent via a raw socket. On the wire this is IP protocol 47, not 6, so L4 filters that only inspect TCP/UDP traffic never see the HTTP payload. There is no real TCP connection; the inner TCP header is window dressing. Unless something decapsulates and inspects the GRE payload, the "HTTP" part is just bytes riding inside protocol 47.

TCP STOMP (method 7) does a real three-way handshake (SYN, wait for SYN-ACK, capture the server's sequence and acknowledgment numbers) then floods with raw ACK packets carrying incrementing sequence numbers. Three retries, configurable timeout (default 10 seconds). SYN cookies don't help because the attack traffic consists of ACKs on a connection the server actually agreed to open.

The DNS flood (method 8) sends raw UDP/53 packets with a DNS-looking fixed payload and randomized bytes near the tail. The function does not appear to construct random subdomains under a fixed victim zone, so this is not a classic DNS water-torture attack. The payload has enough DNS structure to be recognizable, not enough to deserve a more elegant name.

## The scanner/killer

The scanner is the most complex module in the binary. It runs as a forked child process, looping every 10 seconds, and it is relentless about its job: anything on the device that is not the bot, not the operator's dropper, and not a system service gets killed and reported to the C2. The scanner's operating assumption is simple: there can be only one unauthorized process on the device.

Competitor killing is not new in this ecosystem. Jackskid's `0clKiller` module [scans `/proc` for rival binaries](../jackskid/report.md) via three methods (exe path, memory maps, stat analysis) and later added a NETLINK process monitor to kill new competitors within milliseconds. The Xiongmai proxyware campaign [documented in our Pray4Bandwidth report](../reports/2026-03-19-xiongmai-packetsdk-ipidea.md) goes further, patching BusyBox to remove `mount` after deployment. Every botnet wants the device to itself. Datasurge just put more engineering into the desire: five scan passes, a three-tier classifier, an entropy heuristic, an inotify filesystem watcher, and directory permission lockdown, all orchestrated through a C2-toggleable enable/disable mechanism. Detection, classification, response, reporting: the workflow is familiar. The consent model is not.

### Five scan passes

Each 10-second iteration runs five passes over `/proc`:

1. **cmdline + exe scan**: reads `/proc/*/cmdline` and `/proc/*/exe`, applies allowlist then classifier
2. **exe-only scan**: reads `/proc/*/exe` only, same allowlist and classifier
3. **cmdline + backdoor scan**: reads `/proc/*/cmdline`, runs backdoor detector first (immediate kill on match), then classifier
4. **memory-map scan**: reads `/proc/*/maps`, applies classifier against the full map contents
5. **port scan**: reads `/proc/net/tcp` and `/proc/net/tcp6`, resolves PIDs via inode→fd walk, kills processes on non-allowlisted ports

Five passes, every ten seconds, each approaching the same question ("should this process exist?") from a different angle. Redundancy through diversity.

### Three-tier classifier

Each process is evaluated through three stages. If any stage returns a positive match, the process is killed via `SIGKILL` and the kill is reported to the C2.

**Stage 1, pattern blacklist**: 125 string patterns checked via word-boundary-aware `strstr` (the implementation checks ctype `0x800` on adjacent characters to avoid partial matches; more care than most Mirai forks put into their entire codebase). The patterns cover:

- **Miners** (7): `xmrig`, `miner`, `xmr`, `kdevtmpfsi`, `xmr-stak`, `cpuminer`, `minerd`
- **Proxyware** (3): `earnfm_example`, `bitpingd`, `.h.report_system`
- **Competing botnets** (12): `kinsing`, `svcupdate`, `stink`, `fghgf`, `kWrY83g5`, `nUOF`, `yamaha`, `lorikaz`, `uhavenobotsxd`, `sahshasahssahsb`, `rdxr`, `ccmnr`
- **Arch-suffix dropper patterns** (38): `.arm4`–`.arm7`, `.aarch64`, `.mips`, `.mpsl`, `.mipsel`, `.x86_32`, `.x86_64`, `.i686`, `.i386`, `.m68k`, `.powerpc`, `.sh4`, `.sh2`, `.spc`, `.ppc`, `.arc`, and bare versions without dots, plus `xnxnxnxn`, `riscv32`, `riscv64`, `loongarch64`, `microblaze`, `or1k`
- **Shell/dropper activity** (14): `wget`, `curl`, `tftp`, `chmod +x`, `rm -rf`, `kill -9`, `reboot`, `bash -c trap`, `pkill -f`, `while true; do`, etc.
- **Persistence artifacts** (5): `.profile`, `.bashrc`, `systemd-helper`, `.javago`, `systemd-cached`
- **Regex heuristics** (2): `[a-z]{12,}` and `[A-Za-z]{15,}` . Flags processes with long random-looking names, which is a reasonable heuristic given the naming conventions of the average Mirai fork

**Stage 2, backdoor detector**: searches for `nc`, `netcat`, `ncat` commands and shell-pipe patterns (`|sh`, `;sh`) within a 50-byte context window around the match. Catches reverse shells.

**Stage 3, entropy classifier**: counts alphabetic vs. digit characters in process strings. If a string has more than 20 alphabetic characters and fewer than 5 digits (minimum 31 bytes total), it is flagged as `"Suspicious entropy"`. A heuristic for packed or encrypted payloads. Crude, but surprisingly effective against the kind of base64-encoded dropper scripts that populate the ADB exploitation ecosystem.

### Allowlist

Not everything gets killed. A process is spared if:

- Its PID is the bot itself, its parent, or an active attack child
- Its PID is a descendant of the bot (checked by walking the PPID chain up to 49 levels)
- Its exe path matches one of 25 safe paths, including standard system directories (`/bin/`, `/usr/bin/`, `/sbin/`, etc.), IoT device services (`device_433handler`, `device_core`, `device_log`, `BroadcastMsg`), `com.qihoo.daemon` (the Qihoo 360 security agent), `nginx`, and, revealingly, `bbc` and `bbc.sh`
- Its exe, cwd, or any mapped library resides on a read-only filesystem (`squashfs`, `cramfs`, `iso9660`) or in a system path, checked via `/proc/self/mountinfo` parsing with symlink resolution

The allowlist tells a story about the target environment. The IoT device services suggest cameras or similar embedded hardware. `com.qihoo.daemon` suggests Android devices in markets where Qihoo 360 is prevalent. And `bbc.sh`, allowlisted so the scanner won't kill it, is almost certainly the operator's own dropper script. You don't allowlist something you didn't put there.

### Port allowlist

The port scanner allows 15 listed listening ports: 22 (SSH), 23 (Telnet), 25 (SMTP), 53 (DNS), 80 (HTTP), 110 (POP3), 123 (NTP), 143 (IMAP), 443 (HTTPS), 993 (IMAPS), 995 (POP3S), 3306 (MySQL), 5432 (PostgreSQL), 5500, and 6379 (Redis). Any process listening on a port not on this list is killed. The list is generous enough to leave the device's legitimate services running but restrictive enough to catch anything a competitor might open.

### Kill reporting and deduplication

Each kill is reported to the C2 with opcode `0xF0 0xA1` in the format `"PID:%d %s (%s)"` (pid, description, reason). A 256-entry ring buffer deduplicates kills within a 10-second window. Without this, a respawning competitor would generate an infinite stream of kill reports, which is a problem the developer apparently encountered and solved.

### Inotify filesystem watcher

A forked child creates an `inotify` instance and recursively adds watches (up to 5,000, max depth 20) on 9 monitored directories including `/system/bin`, `/system/xbin`, `/vendor/bin`, and `/data/local/tmp`. The watch mask covers `IN_CREATE`, `IN_MOVED_TO`, `IN_CLOSE_WRITE`, and `IN_MODIFY`. When a new executable file appears, the watcher verifies it is not the bot's own binary, then removes it (`unlink` + `chmod 0` + `chown 0:0`). The scanner handles processes already running; the inotify watcher handles the future.

### Directory lockdown

After the scanner starts, the watchdog iterates all writable paths on the device and sets `chmod 0` / `chown 0:0` on each, preventing any other process from writing executables. It is a crude policy, but a legible one: nobody else gets to install software here. When the operator disables the scanner via opcode `0x1a`, the permissions are restored to `0755`. When re-enabled, they are locked down again. The operator has a key to the lockdown; everyone else gets a locked door.

## Operator access

Stock Mirai gives the operator one verb: attack. Datasurge gives the operator a workstation.

The remote shell (opcode `0x12`) executes a command string via `popen("%s 2>&1", "r")`, captures combined stdout/stderr, and sends the output back to the C2 with opcode `0x13`. A second variant (opcode `0x14`) forks, redirects stdout/stderr to `/dev/null`, and calls `execve()` without returning output. One is for looking around; the other is for running things. Anyone who has ever managed a fleet of Linux boxes over SSH will recognize the pattern. The difference is that these aren't the operator's Linux boxes.

The file browser (opcodes `0x10`/`0x11`) lets the operator list directories (up to 100 entries with filename, size, timestamps, and type flag) and read files (up to 1 MB, streamed in 4 KB chunks with a `0xFE` completion marker). This is not just data exfiltration; it is device management. The operator can check what's installed, verify the bot is running, and inspect logs, all without needing a second tool or a reverse shell.

Then there's the scanner toggle (opcodes `0x19`/`0x1a`). Disabling the scanner restores write permissions on all the directories it locked down. Re-enabling it locks them again. If that sounds like a maintenance window, it should. The operator disables protection, pushes an update or deploys a new tool, re-enables protection. A botnet with a maintenance mode is still a botnet, but it is a more revealing one.

## Stealth and persistence

The bot takes the kind of operational care with its own footprint that you might expect from a rootkit, not a Mirai fork.

### Process name spoofing

The bot picks a random name from a table of 41 kernel thread names (`kworker/0:0`, `ksoftirqd/0`, `migration/0`, `rcu_sched`, `kcompactd0`, `kswapd0`, `jbd2/sda1`, and 34 others) and applies it three ways: `prctl(PR_SET_NAME)`, direct overwrite of `argv[0]` in memory, and a write to `/proc/self/comm`. Any one of these would fool a casual `ps`; all three together fool anything short of checking `/proc/<pid>/exe`. The name rotates every 60 seconds. An administrator who spots something suspicious and runs `ps` again a minute later will see a different kernel thread name. The thing they were looking for is gone; something else has taken its place. Nothing to see here.

### Single-instance lock and self-healing

The bot tests 8 writable paths in order (`/data/data/com.android.shell`, `/data/local/tmp`, `/sdcard`, `/storage/emulated/0`, two others, `/data`, `/`) falling back to `/tmp`, creates `.d_lock`, and acquires a POSIX file lock via `fcntl(F_SETLK)`.

What happens next is the interesting part. If the lock is already held, the bot doesn't just exit. It walks the PID chain to check whether the holder is still alive. If the previous instance crashed, the new one takes over: re-acquires the lock, re-execs itself with a fresh random process name, and carries on. The old bot is dead; the new bot inherits the position under a different identity. It's succession planning for a process that isn't supposed to exist.

### The boring parts, done correctly

Daemonization is textbook: double-fork, `setsid()`, `chdir("/")`, close file descriptors 3 through 1024, redirect stdin/stdout/stderr to `/dev/null`. Signal handling is stubborn: ignores `SIGPIPE` and `SIGTERM`, auto-reaps children via `SIGCHLD = SIG_IGN`, installs crash handlers for `SIGSEGV` and `SIGBUS`. None of this is novel, but all of it is correct. Many Mirai forks skip half these steps.

### PRNG

The random number generator is where the developer's taste gets confusing. The PRNG is seeded from `/dev/urandom` via a ChaCha-like initialization routine (quarter-round rotations 16/12/8/7, golden-ratio constant `0x9e3779b9`, SplitMix fallback `0x7f4a7c15`). The runtime generator is xoshiro128, a non-cryptographic PRNG used for payload fills, IP spoofing, port randomization, and DNS transaction IDs. Stock Mirai uses a simple LCG; Datasurge uses a more elaborate generator.

And then the config table is encrypted with ROT13 and XOR.

The binary is picky about packet randomness and casual about hiding its own strings.

## No propagation, by design

We looked for a telnet scanner, an SSH brute-forcer, exploit modules, ADB self-spread code. None of it exists. The binary cannot propagate. The arch-suffix strings (`.arm7`, `.x86_64`, `.mips`, and 35 others) appear exclusively in the scanner's blacklist. They are patterns the bot kills, not architectures it downloads. The developer knows the Mirai dropper ecosystem well enough to enumerate every architecture suffix competitors use, and chose to weaponize that knowledge defensively rather than offensively.

Other Mirai forks dedicate hundreds of lines to credential tables and scanner threads. Datasurge puts that space into the inotify watcher and the three-tier classifier. The codebase is organized around retention, not acquisition: each device is individually compromised, then defended against reinfection or takeover.

The allowlisting of `bbc.sh` and the scanner toggle capability support this model: the operator manually places the bot, deploys via their own script (which the scanner knows not to touch), enables the scanner, and the bot handles the rest. The device is now defended against anything that is not the operator. It is an oddly conscientious approach to unauthorized access.

## Attribution and lineage

The Mirai lineage is visible throughout the binary:

- **Attack wire format**: the `attack_parse` function uses the standard Mirai TLV encoding: `[duration u32 BE][vector u8][target_count u8][targets (ip:4, prefix:1) x n][opt_count u8][options (key:u8, len:u8, val) x m]`.
- **Config table**: the decrypt-on-use `table_lock`/`table_unlock` mechanism is structurally identical to Mirai's, with ROT13+XOR replacing Mirai's single-byte XOR.
- **Toolchain**: GCC 3.3.2/4.2.1 (Debian prerelease + aboriginal Linux), the same cross-compiler chain used by most Mirai forks.
- **Architecture**: statically linked uClibc, process-slot attack management (8 slots), and the overall code structure (main → daemonize → resolve → connect → select loop) follow the Mirai template.

The config table key `0xCAFEBABE` overlaps with a substring of jackskid's 16-byte RC4 key (`DEADBEEF CAFEBABE E0A4CBD6 BADC0DE5`). This is not a meaningful link. Jackskid uses `CAFEBABE` as 4 bytes within a 16-byte RC4 key feeding a triple-layer encryption stack (RC4 + XXTEA + ChaCha20) with DNS-over-HTTPS resolution via statically linked mbedTLS. Datasurge uses bare `0xCAFEBABE` as a 4-byte XOR+ROT13 table key with plain UDP DNS resolution. The two crypto stacks share an aesthetic preference for well-known magic constants and nothing else.

## Detection

### Network indicators

- TCP connections to `datasurge-bot.com:8082` or `5.175.223[.]69:8082`.
- 10-byte registration packet: `\x00\x00\x00\x03` + 1-byte arch string length + arch identifier + `\x01`.
- Length-prefixed C2 framing: `[u16 BE length][opcode][payload]`, cleartext.
- Heartbeat response `\x00\x02\x15\x01` (length=2, opcode=0x15, value=1).
- Scanner kill reports forwarded via localhost relay on `127.0.0.1:30071`.
- DNS resolution to hardcoded `1.1.1.1:53` (plus 8 fallback resolvers including `8.8.8.8`, `9.9.9.9`, `4.4.8.8`); the system resolver is bypassed.
- DNS TXT query for `datasurge-bot.com` returning a base64-encoded, hex-escaped, XOR `0x30`-obfuscated C2 IP.

### Host indicators

- Startup banner `Datasurge-owns-you!!!` on stdout.
- Debug trace strings `[DEBUG_MODE_ATTACK]` in stderr output.
- Process names cycling through 41 kernel thread names every 60 seconds (`kworker/0:0`, `ksoftirqd/0`, `migration/0`, etc.).
- Lock file `.d_lock` in one of 8 writable paths (starting with `/data/data/com.android.shell`, `/data/local/tmp`, `/sdcard`).
- Writable directories set to `chmod 0` / `chown 0:0` when the scanner is active.
- Local TCP listener on `127.0.0.1:30071`.

## Indicators of compromise

Machine-readable IoC files are in [`iocs/`](iocs/):

| File | Contents |
|------|----------|
| [`domains.csv`](iocs/domains.csv) | C2 domain and operator infrastructure |
| [`ips.csv`](iocs/ips.csv) | C2 and payload distribution IPs |
| [`hashes.csv`](iocs/hashes.csv) | Sample SHA-256 hash |
| [`keys.csv`](iocs/keys.csv) | Config table XOR key |

## Prior research and acknowledgements

The Datasurge campaign was first publicly documented by **GHOST** ([Breakglass Intelligence](https://intel.breakglass.tech/post/datasurge-botnet-mirai-variant-iot-dropper-with-dns-based-dynamic-c2)) on 2026-03-13, covering the multi-stage dropper chain (`bbc` shell script → architecture-specific ELF payloads), DNS TXT-based dynamic C2 resolution, payload distribution from `5.175.223[.]124`, and C2 at `130.12.180[.]151:25565`. That report identified additional operator infrastructure (`datasurge.vip`, `report.datasurge.vip`, `pay.datasurge.vip`) and assessed the operation as a commercial DDoS-for-hire service. Our sample (first seen 2026-05-31 on MalwareBazaar) is a later build from the same campaign, using a different host in the same /24 for C2 fallback.

The scanner/killer analysis, config-table decryption, C2 wire protocol, attack-method decompilation, stealth mechanisms, and PRNG analysis in this report are original Nokia Deepfield ERT work. Errors are ours; corrections welcome.

