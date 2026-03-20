# Shared code, shared secrets: tracing four DDoS botnets to one ecosystem

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-03-20**

> **Content warning:** This post quotes malware artifacts verbatim, including domain names, ENS records, and build strings chosen by the threat actors. Some contain racist, homophobic, or otherwise offensive language. These are reproduced exactly as found in samples to enable accurate detection and attribution.

> **Note:** Since this research was completed, four of the botnets described below have been [disrupted by law enforcement](https://www.justice.gov/usao-ak/pr/authorities-disrupt-worlds-largest-iot-ddos-botnets-responsible-record-breaking-attacks). We delayed publication until that process concluded.

## Summary

*Un train peut en cacher un autre*, warn the signs at French railway crossings: one train can hide another. What looked like one DDoS botnet turned out to be hiding three more — and led us, via a side quest, to a fifth we assess as adjacent rather than part of the core ecosystem. The four share source code, credential lists, and a cryptographic fingerprint that links them to a common development lineage. Together, they use five independent command-and-control channels: DNS TXT records, DNS-over-HTTPS, Ethereum blockchain (ENS), OpenNIC alternative TLDs, and ChaCha20-encrypted custom binary protocols. Catching one misses the rest.

This post traces the thread from a single custom RC4 modification, through binary decompilation and operational data, to an ecosystem map spanning Aisuru, Jackskid, Kimwolf, and MossadProxy, with a documented tangent through Cecilio, a CatDDoS derivative with operational links but no shared code. Along the way, we present the first public decryption of the Cecilio C2 scheme, document MossadProxy’s operational ties to the ecosystem — including a shared 15-port C2 configuration that amounts to a smoking gun — and reconstruct the Jackskid operator’s six-week timeline of C2 migrations, campaign evolution, and infrastructure burns. A compiled-in artifact from one crossover build suggests that at least one developer uses the Cursor AI-assisted IDE.

## The thread

We started where most Aisuru research starts: with a Mirai derivative responsible for record-setting DDoS attacks, documented by [XLab](https://blog.xlab.qianxin.com/super-large-scale-botnet-aisuru-en/), [Cloudflare](https://blog.cloudflare.com/ddos-threat-report-2025-q3/), and [KrebsOnSecurity](https://krebsonsecurity.com/2025/10/ddos-botnet-aisuru-blankets-us-isps-in-record-ddos/). Aisuru was already generating DDoS traffic across networks we protect. We started pulling samples to understand what was behind the volume. XLab had already documented a **custom modification to the RC4 key schedule** in Aisuru — a 5-pass S-box scramble using a Linear Congruential Generator seeded with `0xe0a4cbd6` — and provided a Go reimplementation. We recognized it when it surfaced, unexpectedly, in a completely different family.

That fingerprint became the thread. Pulling it led us through three more families, three more C2 channels, a cipher decode we believe to be new, and a port pool configuration that connected a family we had initially dismissed as unrelated.

Public reporting from [XLab](https://blog.xlab.qianxin.com/super-large-scale-botnet-aisuru-en/), [Synthient](https://synthient.com/blog/a-broken-system-fueling-botnets), [Protos Labs](https://www.protoslabs.io/resources/aisuru-botnet-deep-dive), [CNCERT](https://www.secrss.com/articles/87776), and [Cloudflare](https://blog.cloudflare.com/ddos-threat-report-2025-q3/) has documented individual families in isolation, sometimes grouping samples from distinct codebases under a single family name. Botnet taxonomy is a contact sport. Our analysis builds on that foundation and follows the evidence into the connections between them.

## Aisuru: the known threat

The Aisuru botnet, first reported by [XLab](https://blog.xlab.qianxin.com/super-large-scale-botnet-aisuru-en/) in 2024, is a Mirai derivative targeting Linux-based embedded devices. Samples in our collection span six architectures (x86, x86-64, ARM, AArch64, MIPS, ARC700). XLab has attributed its growth to exploitation of n-day vulnerabilities in routers and DVRs, and [Cloudflare](https://blog.cloudflare.com/ddos-threat-report-2025-q3/) has reported on its record-setting DDoS attack volumes; notably, the Aisuru bot binary itself contains no embedded credential dictionary or self-propagation module; distribution is handled by separate loader infrastructure shared across the ecosystem.

Aisuru encodes C2 IP addresses in DNS TXT records. The bot queries hardcoded domains (primarily `.su` TLD), receives base64-encoded TXT responses, and XORs the decoded bytes with the 4-byte key `CAFEBABE` to recover the C2 IP address. The operator rotates IPs by updating the DNS records; no binary rebuild required. Gen1 builds verify internet connectivity by issuing an HTTP GET to `motherfuckingwebsite[.]com`, a real, minimalist website that simply returns HTML. Gen2 switched to Google’s STUN server, a less editorially committed choice.

This method is effective but visible: any DNS monitor can see TXT queries to domains like `dvrxpert.tiananmensquare1989[.]su`. We currently track 11 resolver domains across 7 parent domains, all pointing to VPS infrastructure that rotates regularly — including a full C2 IP swap on March 19, the day before publication and law enforcement action.

We distinguish two generations based on cryptographic and protocol markers: gen1 (Aug 2024 – Mar 2025) uses a 16-byte cycling XOR key for string obfuscation, resolves C2 via DNS A records, and includes a SOCKS5 proxy module. Gen2 (Apr 2025 onward) introduced the `PJbiNbbeasddDfsc` table key (which XLab notes may be a nod to the [Fodcha botnet](https://blog.xlab.qianxin.com/super-large-scale-botnet-aisuru-en/)), switched to DNS TXT-based C2, and added the custom RC4 with LCG post-processing, the fingerprint that started this investigation.

The fingerprint parameters:

| Parameter | Standard RC4 | Aisuru gen2 |
|-----------|-------------|-------------|
| LCG post-processing | None | 5-pass S-box scramble |
| LCG seed | N/A | `0xe0a4cbd6` |
| LCG multiplier | N/A | `0x41c64e6d` (matches glibc `rand()`) |
| LCG addend | N/A | `0x3039` (matches glibc `rand()`) |

The multiplier and addend are well-known glibc `rand()` constants, and multi-pass S-box scrambling is a recognized hardening technique. XLab [documented](https://blog.xlab.qianxin.com/super-large-scale-botnet-aisuru-en/) this modification in their Aisuru analysis and provided a Go reimplementation. What we have not found elsewhere — in other malware families, leaked source, or open-source projects — is this specific combination: 5 post-KSA passes seeded with `0xe0a4cbd6`. That makes it a useful forensic fingerprint. We welcome corrections from researchers who may have observed it in other families.

The seed `0xe0a4cbd6` was already familiar when it turned up in our next sample.

## Following the fingerprint: Jackskid

The key was `DEADBEEF CAFEBABE E0A4CBD6 BADC0DE5` — a programmer's lorem ipsum with one real value smuggled in. The family using it, independently documented by [Foresiet](https://foresiet.com/blog/mirai-botnet-jackskid-resurgence-nov-2025-iot-threats/) as "Jackskid" and by [CNCERT](https://www.secrss.com/articles/87776) as "RCtea" (for its RC4+ChaCha20+TEA encryption stack), had our seed sitting in its RC4 key. Decompiling the RC4 implementation confirmed the match: the same 5-pass LCG scramble, the same seed, the same glibc constants. The code lineage was clear.

But the C2 method diverged entirely. Where Aisuru uses DNS TXT records (visible to any network monitor), Jackskid resolves domains via DNS-over-HTTPS using mbedTLS. DNS queries appear as standard HTTPS traffic, largely invisible to network monitoring. The bot randomly selects from a pool of ports per connection (60 in earlier builds, expanded to 84 in the most recent), further complicating detection.

An unstripped debug build captured in February 2026 reveals the internal project name **`softbot`** and a competitive malware-killing module named `0clKiller`, neither of which appear in any public reporting. The build was cross-compiled using Aboriginal Linux — a niche embedded cross-compilation toolkit — with default paths intact. The README was followed; the threat model was not.

Additional shared indicators reinforce the code lineage:
- The string `PJbiNbbeasddDfsc` used as table XOR key (Aisuru) and authentication key (Jackskid)
- The `CAFEBABE` constant used as DNS TXT XOR key (Aisuru) and TCP C2 handshake magic (Jackskid). Between the XOR key, the RC4 key, and the handshake magic, `CAFEBABE` is the hardest-working four bytes in the ecosystem.
- ChaCha20 transport encryption (different implementations for different architectures)
- **Crossover builds** (`42aea373`, `6039ff1c`, `3d0cf1d0`, Aug 2025–Dec 2025) that combine Aisuru’s table architecture with Jackskid’s credential brute-force module. One also contains a compiled-in developer artifact referencing a Windows user profile path and the Cursor AI-assisted IDE debug log, indicating that at least one person with access to the source code develops on Windows using Cursor. Not a surprising toolchain, but shipping your Windows username and IDE debug logs with your malware suggests OPSEC was not the vibe.

### The operator’s six weeks

Samples collected between January and March 2026 — 57 files, 33 unique hashes — filled in something binary analysis alone cannot: operational tempo.

Decrypted config tables reveal the C2 migration path. The operator migrated from `www.boatdealers[.]su` (8 backup domains including `gokart[.]su`, `plane[.]cat`, `cecilioc2[.]xyz`) to `www.ipmoyu[.]xyz` in late February 2026, with a config tag reading `here we are again part 2`, which saved us some analytical effort. By mid-March, the primary C2 had rotated through subdomain changes (`www` → `peer` → `nodes.ipmoyu[.]xyz`), and all backup domains were dropped in favor of fast-flux A records (40–50 IPs per domain). Additional domains observed in the fast-flux pool include `www.jacob-butler[.]gay`, `www.richylam[.]org`, and `www.plane[.]cat`. Notably, the `ipmoyu[.]xyz` domains resolve to IPs in the `203.188.174.x/24` range, the same /24 hosting payload delivery servers, meaning C2 resolution and malware delivery infrastructure are co-located.

The same collection reveals a five-phase ADB infection campaign spanning February 17 through March 16, 2026. The earliest scripts (from `192.206.117[.]19`) attempted SELinux bypass and `/system` remounting; later phases dropped those techniques in favor of ADB verification bypass, battery optimization whitelisting, and an increasingly aggressive fallback chain for app startup. APK package names progressed from `com.example.bootsync` (February 17) through `com.google.android.gms.update` (February 19) to `com.google.play` (March 9), showing deliberate evolution toward more convincing system-app impersonation. `com.example.bootsync` has the energy of a placeholder someone forgot to update. By `com.google.play`, they’d found the ambition. As package name glow-ups go, it’s respectable. Each stager executes the ELF binary with a campaign tag via `argv[1]`; tags like `gponfiber` and `uchttpd` identify the targeted device type, while `kieran` matches the C2 subdomain `kieranellison.cecilioc2[.]xyz`, providing an operational link between the ADB campaign and earlier Cecilio infrastructure. By mid-March, the scripts actively uninstall rival bot packages including `com.android.docks` (Snow), `com.oreo.mcflurry` (Lorikazz), `com.telnetd.telenet`, and `com.example.jewboot`. Naming your botnet after a McDonald’s menu item is a creative choice that, like the McFlurry itself, was probably not overthought.

The most recent build we analyzed (March 2026) has dropped all self-propagation: C2 is consolidated to a single domain (`nodes.ipmoyu[.]xyz`), delivery is fully externalized via ADB using a `komaru` stager and the `com.google.alarm` APK wrapper, and the binary is a pure DDoS engine.

Read end to end, the six-week timeline has the cadence of an agile project: biweekly infrastructure rotations, iterative package naming improvements, and config tags that read like commit messages. The operator is, for better or worse, shipping.

### Convergence, not divergence

A wave of 28 samples collected March 10–13, 2026 reveals that the two families are converging to the point where the family boundary is a philosophical question. Twenty-three of these are crossover builds combining Aisuru’s `PJbiNbbeasddDfsc` table key with Jackskid’s `DEADBEEF` RC4 cipher, sharing the same C2 IP (`185.196.41[.]180`) as the latest Aisuru gen2 build (`7500925a`). The remaining five use the C2 domain `ricocaseagainst.rebirth[.]st`, resolving to `158.94.210[.]71`, in the same /24 as the known shared C2 IP `158.94.210[.]88`. The `rebirth[.]st` domain and one sample named `rebirthstresswashere` tie these builds to the “Rebirth” stresser service. Scanner builds in this wave include IoT credentials (`Pon521`, `Zte521`, `telecomadmin`), and new persistence mechanisms include a systemd service (`dbus-kworker.service`) alongside cron. Several builds add anti-VM detection, checking for hypervisor, vfio, virtio, and virtblk strings to avoid analysis environments. Whether these are still two families or one is, at this point, the Ship of Theseus in ELF format.

This evidence — the RC4+LCG fingerprint, shared constants, crossover builds, and converging codebases — indicates that Aisuru gen2 and Jackskid share a common development lineage, with at least some overlap in the people involved. There is more to say about Jackskid's operational patterns than we can cover here; we expect to return to it in detail.

Between the backup domain list and the `kieran` campaign tag, Jackskid kept pointing at `cecilioc2[.]xyz`. So we looked.

## A different cipher, a familiar pattern: Cecilio

Cecilio is a side quest. It is not part of the core ecosystem, but the investigation led through it — and the cipher decode is, to our knowledge, new.

`cecilioc2[.]xyz` is a Jackskid C2 domain, but the name references a separate family: Cecilio, built from leaked CatDDoS source code. The connection is important context: CatDDoS was first documented by [QianXin TIC](https://ti.qianxin.com/blog/articles/new-botnet-catddos-continues-to-evolve-en/) in September 2023 as a Mirai-derived botnet using ChaCha20 for table encryption and OpenNIC domains for C2. After its original operator ("Aterna") shut down in December 2023, the source code was leaked on Telegram. Several derivative variants emerged, including RebirthLTD, Komaru, and Cecilio Network.

XLab [documented](https://blog.xlab.qianxin.com/catddos-derivative-en/) that at least three other families use the same ChaCha20 key and nonce as CatDDoS, evidence that operators adopt the leaked source without changing the keys. Changing the default password is, apparently, a universal struggle. This cross-pollination is common in the IoT botnet space: groups adopt leaked source code with minimal modification, resulting in families that share *default* encryption constants despite being operated independently. This is distinct from the Aisuru↔Jackskid link, where the shared RC4+LCG implementation is a custom modification not present in any known leaked source.

The Cecilio variant we analyzed diverged further from the CatDDoS template: its operator **replaced the ChaCha20 table encryption with a modified RC4 cipher**. Not our custom RC4 — a different modification entirely.

### Cracking the Cecilio C2

To understand how Cecilio relates to the ecosystem, we needed to decode its C2 scheme. To our knowledge, this has not been previously documented.

Standard RC4 resets the j index to 0 when transitioning from the Key Scheduling Algorithm (KSA) to the Pseudo-Random Generation Algorithm (PRGA). The Cecilio variant **carries j over**, producing a completely different keystream with the same key.

The 256-byte RC4 key is static across all observed builds (from May 2025 through February 2026):

```
c9 ba 3e 11 4f 2a 7d e0 e6 8d bb eb 9a 87 87 7e
c5 02 29 ef df 66 65 9f 95 12 df b3 8a d8 93 53
...
```

Using this key with the modified RC4 algorithm, we decrypted the complete configuration table from two builds (May 2025, February 2026):

| Entry | Content | Purpose |
|-------|---------|---------|
| C2 domains | `f93[.]oss`, `fm3[.]dyn`, `ryd[.]dyn`, `g86[.]oss` | OpenNIC C2 (Feb 2026 build) |
| C2 domain | `oceanic-node[.]su` | Public DNS C2 |
| Auth token | `xI7ht4Uyl9rFyk0GaTt8v2Fz7HrlZVA5` | DNS TXT XOR key (32 bytes) |
| Self-ID | `the cecilio botnet has been executed on your system!` | Banner (May 2025 build) |
| Build string | `hail china mainland` | Operator taunt (May 2025 build) |
| Download tools | `wget`, `curl`, `tftp`, `ftp`, `ftpget` | Payload delivery |
| Kill list | `telnetd`, `sshd`, `watchdog`, `systemd-resolved` | Process evasion |

The exclamation mark in the self-identification banner adds enthusiasm; the target’s experience of the event is, one imagines, more subdued.

The earlier May 2025 build used different OpenNIC domains (`hailbot[.]dyn`, `tbot[.]dyn`, `cecilio[.]geek`, `hitlerbot[.]geek`) alongside `kamru[.]su`. Subtlety is not a design goal. Notably, "Hailbot" is also the name of a separate CatDDoS derivative that XLab identified as sharing the original ChaCha20 key, suggesting this operator may have forked from that specific variant.

Cecilio uses OpenNIC alternative TLDs (`.dyn`, `.oss`, `.geek`) for its C2 domains. These TLDs only resolve via OpenNIC-compatible DNS servers; standard public resolvers like 1.1.1.1 and 8.8.8.8 return NXDOMAIN. This means the C2 domains are absent from most passive DNS databases and standard DNS monitoring. The operational advantage is somewhat offset by naming the domains `hitlerbot.geek` and `cecilio.geek`, the kind of names that get a Discord server banned within 48 hours. The DNS evasion itself is sound.

### DNS TXT decryption

The DNS TXT C2 records use a three-step encoding:

1. **Base64-encode** the payload (17 bytes raw)
2. **Skip the first 4 bytes** (purpose unknown, possibly a checksum)
3. **XOR the remaining 13 bytes** with the authentication token: `xI7ht4Uyl9rFyk0GaTt8v2Fz7HrlZVA5`

Multiple C2 IPs are pipe-delimited within a single TXT record.

Applying this decryption to the live DNS TXT records yields four active C2 IPs:

| Decoded C2 IP | ASN | Serves domains |
|--------------|-----|----------------|
| `185.242.3[.]251` | AS60223 | `oceanic-node[.]su`, `f93[.]oss`, `fm3[.]dyn`, `ryd[.]dyn`, `g86[.]oss`, `hailbot[.]dyn` |
| `64.89.161[.]164` | AS205759 | Same as above |
| `45.81.254[.]185` | AS212853 | `tbot[.]dyn`, `cecilio[.]geek`, `hitlerbot[.]geek` |
| `195.206.234[.]7` | AS214677 | `kamru[.]su` |

Notable: the older kamru-era OpenNIC domains (May 2025) now return the same TXT records as the newer oceanic-node domains (Feb 2026), suggesting infrastructure consolidation.

This contrasts with the Aisuru DNS TXT scheme (4-byte `CAFEBABE` XOR producing binary IPs) and is entirely distinct from Jackskid's DoH method.

### How Cecilio relates

**Cecilio does not share code with Aisuru or Jackskid.** It derives from the separately leaked CatDDoS source, a distinct codebase with different table encryption, different C2 encoding, and no shared cryptographic keys.

The operational similarities are real but limited:
- Jackskid and Cecilio share **111 brute-force credentials** in identical order (`Pon521`, `Zte521`, `root621`, etc.). Identical content suggests a shared list; identical ordering suggests Ctrl+C.
- Both use `.su` TLDs for C2 domains
- Both were active concurrently (2025–2026)
- The `kieran` campaign tag in Jackskid's ADB campaign directly references `kieranellison.cecilioc2[.]xyz`

The `.su` TLD — the Soviet Union's country code, still operational 35 years after the country it represented ceased to exist — is now a reliable indicator that a domain is not being used for tourism.

However, as XLab documented, template sharing is widespread among CatDDoS derivatives. Shared credentials and TLD preferences could indicate the same operator, or they could reflect common tooling circulating in the same communities. We note the overlap and leave attribution as an exercise for someone with more enthusiasm for it.

One detail worth holding onto: the `kamru[.]su` C2 domain from the May 2025 build.

## The proxy pipeline: Kimwolf

The thread from Aisuru to Kimwolf runs through a different kind of evidence: not shared code, but shared infrastructure.

**Transitional APKs** discovered on Koodous bundle Aisuru gen2 ELF payloads inside the Kimwolf APK packaging framework (`com.android.systemservice0644`), sharing the same Android debug signing certificate. [XLab independently documented](https://blog.xlab.qianxin.com/kimwolf-botnet-en/) the same connection, tracing APKs containing Aisuru binaries packaged with the Kimwolf framework and concluding that the two families belong to the same group. Since compiled Aisuru binaries are publicly available on malware repositories, these APKs primarily demonstrate access to the Kimwolf packaging infrastructure and an intent to distribute both families through the same channel.

Kimwolf itself is a C++ residential proxy and DDoS botnet targeting Android devices. Its primary infection vector exploits the residential proxy ecosystem: proxy software installed on consumer devices leaves the Android Debug Bridge (ADB) interface exposed, and the operator leverages that access to sideload the Kimwolf payload. Synthient documented this chain in their ["A Broken System Fueling Botnets"](https://synthient.com/blog/a-broken-system-fueling-botnets) research, tracing infections back through the proxy networks to exposed ADB interfaces on Android-based set-top boxes and smart TVs. Because these devices typically sit behind NAT or CGNAT on residential broadband networks, they are not discoverable through conventional internet-wide scanning, which makes the botnet difficult to measure from the outside. The sheer scale of the available pool — millions of unsecured residential proxy exit nodes, as Synthient documented — is what has enabled Kimwolf to reach a size previously unseen in IoT DDoS botnets.

Kimwolf resolves C2 addresses via the Ethereum Name Service (ENS). The bot makes JSON-RPC calls to public Ethereum endpoints, queries ENS `resolver()` and `text()` smart contract functions, and extracts the C2 IP from the ENS text record. DNS-over-TLS handles the initial RPC endpoint resolution. This is arguably the most takedown-resistant C2 method in the ecosystem: ENS records are stored on the Ethereum blockchain and cannot readily be seized by registrars or law enforcement without the operator's private key. Web3 evangelists promised unstoppable applications. A DDoS botnet resolving C2 through smart contracts was presumably not the pitch deck, but it qualifies. The operator has rotated through at least three ENS domains (`pawsatyou[.]eth`, `re6ce[.]eth`, `byniggasforniggas[.]eth`).

When ENS resolution fails, recent Kimwolf builds fall back to a **Tor hidden service** (`rwbxbmflwm7andgmxeo3my7mqqs6najhou7o6f7xnxjsiuirzcnab4yd[.]onion`) on hardcoded port 25001, the same port currently used by the ENS-resolved C2 servers. The APK bundles a complete Tor binary and connects via a local SOCKS5 proxy on `127.0.0.1:9050`. As of March 2026, the hidden service is registered but not accepting connections, the kind of infrastructure that gets built once, used briefly, and left in the codebase indefinitely — a pattern not unique to malware.

Kimwolf is architecturally distinct from Aisuru: C++ with Android NDK (vs. C with musl/uClibc), ENS blockchain C2 (vs. DNS TXT), and a dual proxy+DDoS design with C++ RTTI class names intact in the binary — the kind of detail a code reviewer appreciates more than the author intended. The proxy component operates as a SOCKS5 residential relay, while 10 DDoS attack handlers use raw sockets for IP-spoofed floods. Three additional utility handlers (proxy relay, STUN NAT traversal, external IP discovery) bring the total to 13 registered command handlers.

Despite separate codebases and independent C2 channels, the two families share significant infrastructure overlap. Both rely heavily on DigitalOcean (AS14061) — 42 Aisuru C2 IPs and 57 Kimwolf C2 IPs at the time of writing — and subnet analysis shows co-location within the same /20 allocation blocks in six cases (e.g., `206.189.96.0/20`: Aisuru `206.189.105[.]179`, Kimwolf `206.189.99[.]132`). No /24 overlap exists; the operator appears to procure from the same datacenter pools while keeping individual C2 nodes distinct. At 99 VPS instances, the operator may qualify for DigitalOcean’s enterprise tier, though the use case would complicate the sales call.

The Kimwolf proxy binary is called `libdevice.so`. That name will matter in a moment.

## The surprise: MossadProxy

MossadProxy is a DDoS botnet targeting Android TV and IoT devices via ADB, delivered through an APK wrapper named, with admirable directness, `com.android.door`. The earliest C2 domain registration dates to January 2026; our earliest collected samples are from March 2026, though earlier builds may exist. Despite its name and its native binary being called `libproxy.so`, the build we analyzed contains no proxy functionality; it is a DDoS bot. In fairness, `libddos.so` would have been less subtle. The binary references companion files `libdevice.so` and `libvpn.so` that are not present in this APK build, so other builds or deployment configurations may include additional components.

The binary uses standard RC4 for config string encryption (key: `6e7976666525a97639777d2d7f303177`) and ChaCha20 with xxHash integrity for the C2 wire protocol. C2 domains (`whitebluerights[.]com`, `blueblackside[.]com`, `blueblackside[.]store`) are registered at REG.RU, a Russian domain registrar. A custom DNS resolver queries five hardcoded nameservers (Cloudflare, Quad9, Level3, OpenDNS, Yandex) — a geopolitically diversified resolution strategy. For C2 discovery, the bot contacts a preconfigured list of peers over UDP with a 20-byte handshake; peers responding with command type `0x0200` provide the current C2 IP address. Separately, it queries public HTTP services (`checkip.amazonaws.com`, `icanhazip[.]com`) to determine its own external IP for C2 registration.

Delivery is multi-stage, starting from a 676-byte ARM ELF stager. This paragraph is longer than the stager. The final payload and its companion APK maintain mutual persistence: each restarts the other if it stops. They are, in effect, each other's emotional support binary.

The bot supports 8+ DDoS attack methods (UDP floods, TCP SYN, DNS amplification/reflection), a remote shell, and an aggressive competitor-killing watchdog. Process names masquerade as Android TV system processes (`android-tv-sysboot`, `android-tv-preboot`, etc.), and C2 connections use ports commonly associated with game servers and applications (Minecraft 25565, Source Engine 27015, TeamSpeak 9987, Redis 6379, PostgreSQL 5432, etc.), likely to blend in with legitimate traffic. The port selection — Minecraft, Source Engine, TeamSpeak — also reveals which services the developer could name from memory. An Android TV box initiating connections to PostgreSQL 5432 is not, in most network baselines, inconspicuous.

We had initially assessed MossadProxy as adjacent to but separate from the ecosystem. Then three findings changed that assessment.

### The allowlist

MossadProxy's process-killing watchdog explicitly allowlists `libdevice.so` and `libvpn.so`. As noted above, `libdevice.so` is the confirmed Kimwolf proxy binary name. The MossadProxy operator either runs proxy infrastructure alongside the DDoS bot, or has a coexistence arrangement with the Kimwolf operator, a notable detail given that the Aisuru→Kimwolf link also rests on shared distribution infrastructure.

### The domain

The binary embeds `stun.kamru[.]ru` as a STUN server. `kamru[.]su` surfaces again: WHOIS records show both domains were registered on the same day (2025-03-24) by the same "Private Person" registrant. `stun.kamru[.]ru` is stored in a separate configuration slot from MossadProxy's list of well-known public STUN servers (Google, Cloudflare, etc.), suggesting it may be operator-controlled infrastructure rather than a third-party service. The domain no longer resolves.

### The port pool

The allowlist and the domain are suggestive. The port pool is not.

MossadProxy's RC4 config slot 0x07 contains a secondary port pool: 15 ports in a specific order.

`37867, 37868, 18923, 27136, 29517, 31984, 36942, 24105, 41237, 16283, 38690, 20974, 35811, 18247, 40319`

This sequence is identical — same ports, same order — to the Aisuru gen2 C2 port pool extracted from build `7500925a`. We are not statisticians, but fifteen ordered ports matching exactly does not require a p-value. It implies either shared configuration generation tooling, a common operator, or direct access to the same deployment infrastructure.

MossadProxy also blocklists `158.94.209[.]198`, in the same /22 prefix as the known Aisuru↔Jackskid shared C2 IP `158.94.210[.]88`, consistent with an operator who is aware of ecosystem infrastructure. Its C2 is hosted on AS41745 (hip-hosting.com), the same ASN that hosted Aisuru gen1's fallback C2 IPs in August 2024.

MossadProxy does not share code with any other family in this ecosystem. Its codebase is independently developed, compiled with a modern Clang/LLD 19.0 toolchain (vs. GCC for every other family), and uses a completely different C2 protocol architecture. But the identical port pool configuration — a 15-element ordered sequence — goes beyond operational awareness to indicate shared configuration infrastructure or a common operator. Combined with the Kimwolf binary allowlisting, the `kamru` domain connection, the shared hosting provider, and the same ADB delivery vector, MossadProxy appears to be a purpose-built component within the broader ecosystem rather than an independent actor who merely operates nearby.

## Shared attack DNA

With all the families introduced, a wider comparison reveals shared attack code beneath the crypto layer.

Expanding the comparison to all three Mirai-lineage families — Aisuru (12 handlers), Kimwolf (10), and Jackskid (14 in the latest build) — reveals a core set of 6 attack types present in all three, plus partial overlaps that illuminate the development relationships:

| Attack type | Aisuru | Kimwolf | Jackskid | Notes |
|-------------|--------|---------|----------|-------|
| TCP SYN flood | `attacks_socket` | `tcp_syn` | `tcp_socket` (0x03) | All three: `SOCK_RAW` + `IP_HDRINCL` |
| TCP ACK flood | `attacks_ack` | `tcp_ack` | `tcp_ack` (0x04) | All three: spoofed ACK packets |
| TCP STOMP | `attacks_stomp` | `tcp_stomp` | `tcp_stomp` (0x05) | All three: two-socket handshake then burst |
| UDP volumetric | `attacks_std` | `udp_cidr` | `udp_plain` (0x00) | Aisuru/Kimwolf: CIDR source randomization |
| UDP generic | `attacks_udp` | `udp_generic` | `udp_vse` (0x02) | Kimwolf: `[a-z0-9]` payload; Jackskid name misleading |
| Valve Source Engine | `attacks_vse` | `udp_vse` | `udp_raknet` (0x07) | All target port 27015; Jackskid name misleading |
| ICMP flood | `attacks_icmp` | `icmp` | — | Aisuru + Kimwolf only |
| RakNet ping | `attacks_raknet` | — | `tcp_minecraft` (0x08) | Aisuru + Jackskid; Jackskid label says TCP but handler is UDP |
| GRE encapsulation | `attacks_gre` | — | `gre_flood` (0x0C) | Aisuru + Jackskid only; dual IP headers |
| Randomized UDP | `attacks_rand` | — | `udp_raw` (0x01) | Aisuru + Jackskid; small/random packets |
| TCP Handshake flood | — | `tcp_handshake` | `tcp_handshake` (0x0B) | Kimwolf + Jackskid; added to Jackskid Feb 2026 |
| TCP WRA | `attacks_wra` | — | — | Aisuru-only |
| TCP Fast Open | `attacks_tfo` | — | — | Aisuru-only |
| TCP PSH+ACK | — | `tcp_pshack` | — | Kimwolf-only |
| UDP Minecraft Bedrock | — | `udp_minecraft` | — | Kimwolf-only; port 19132 |
| Minecraft Java login | — | — | `app_http` (0x09) | Jackskid-only; port 25565 |
| FiveM getinfo | — | — | `udp_fivem` (0x0A) | Jackskid-only; port 30120 |
| NCP template | — | — | `udp_socks` (0x0D) | Jackskid-only; port 524 |
| TCP connect flood | — | — | `proxy` (0x06) | Jackskid-only; 256-connection pool |

The pattern of overlap is asymmetric. Jackskid shares 10 of its 14 attack types with Aisuru but only 7 with Kimwolf, consistent with the code-lineage evidence establishing Jackskid as an Aisuru derivative. Three attack types — RakNet, GRE, and randomized UDP — appear in Aisuru and Jackskid but not Kimwolf, further distinguishing the Mirai-derived lineage from Kimwolf's independent C++ codebase. Conversely, Kimwolf shares a TCP Handshake flood handler with Jackskid that Aisuru lacks, suggesting some cross-pollination of attack ideas even between architecturally distinct codebases.

A forensic detail reinforces the Aisuru→Jackskid lineage: Jackskid's handler names are systematically swapped relative to Aisuru's. Jackskid's `udp_raknet` (0x07) actually sends `TSource Engine Query` payloads (Aisuru's `attacks_vse`), while its `tcp_minecraft` (0x08) actually sends RakNet Unconnected Pings over UDP (Aisuru's `attacks_raknet`). The payloads match; only the labels were transposed. Renaming things is hard; we sympathize.

The implementations are independent between the Mirai-derived lineage (Aisuru/Jackskid) and Kimwolf: different languages (C vs. C++), different buffer management (`calloc(0x5e6, 1)` vs. C++ allocation), different PRNG (libc `rand()` vs. xoshiro256). TCP STOMP in particular is not a standard Mirai attack; all three families implement the same two-socket pattern (raw SYN, SYN-ACK detection via `(flags & 0x12) == 0x12`, then `SOCK_STREAM` burst), although the cross-family code analysis confirms Kimwolf does not share the `calloc(0x5e6, 1)` buffer allocation or the `*buf & 0x4f | 0x40` IP header idiom found in the Mirai-derived families.

MossadProxy's attack code is architecturally separate — an independent Clang/C codebase with its own dispatch protocol — but functionally overlapping. Its 8+ handlers cover UDP volumetric floods (three variants, including `SOCK_RAW` with IP spoofing), TCP SYN and connect floods, and DNS amplification/reflection. Four of these map directly to attack types shared across the Mirai-derived families above. The overlap is in capability, not code.

Notably, not a single attack handler across any of the families in this report supports IPv6. The only observed use of the protocol in the entire ecosystem is Kimwolf encoding obfuscated IPv4 C2 addresses inside fake IPv6 strings — not, presumably, what the IETF had in mind in 1998.

Below the handler level, the three Mirai-derived families (Aisuru, Jackskid, Cecilio) share additional attack code characteristics not present in the publicly available Mirai source:

- **Buffer allocation**: `calloc(0x5e6, 1)`, 1510 bytes, identical across all three. The choice is 10 bytes over standard Ethernet MTU; whether intentional or a rounding preference, it forces fragmentation on most paths.
- **IP header construction**: `*buf & 0x4f | 0x40` / `*buf & 0xf5 | 5`, same bit manipulation idiom
- **TCP STOMP**: Two raw sockets + handshake with `(flags & 0x12) == 0x12` SYN-ACK detection

For Aisuru and Jackskid, these shared patterns reinforce the code lineage established by the RC4+LCG fingerprint. For Cecilio, the shared attack code likely reflects modifications made after adopting the CatDDoS source, integrating a common credential set and attack patterns, whether from the same operator or from shared tooling.

## The ecosystem map

Pulling these threads together:

| Relationship | Type | Confidence | Key evidence |
|---|---|---|---|
| Aisuru ↔ Jackskid | Code lineage | **High** | RC4+LCG fingerprint, shared constants, crossover builds, converging codebases |
| Aisuru ↔ Kimwolf | Operational bridge | **Medium** | Transitional APKs, shared signing certs, overlapping VPS infrastructure |
| MossadProxy ↔ ecosystem | Operational coordination | **Medium-high** | Identical 15-port C2 pool, Kimwolf binary allowlist, `kamru` domain link, shared ASN, ADB vector |
| Cecilio ↔ ecosystem | Cross-pollination | **Low** | Shared credentials, `kamru` domain registrant, `kieran` campaign tag, .su TLD preference |

The operator — or operators — manage these families as complementary platforms: Aisuru targets Linux-based IoT via n-day exploitation (per [XLab](https://blog.xlab.qianxin.com/super-large-scale-botnet-aisuru-en/) reporting), Jackskid adds telnet/SSH credential brute-force with a self-contained scanner module absent from Aisuru, Kimwolf exploits the residential proxyware supply chain to reach Android devices via exposed ADB interfaces (documented by [Synthient](https://synthient.com/blog/a-broken-system-fueling-botnets)), and MossadProxy provides an additional DDoS capability on the same ADB-delivered device population with an independently developed codebase. Each feeds the same operation through independent C2 channels.

## What this means

Five C2 channels, one ecosystem. It's defense in depth, just not the kind we usually advocate for. DNS TXT, ENS blockchain, DNS-over-HTTPS, OpenNIC, and ChaCha20-encrypted custom protocols all serve C2 resolution across these families. Monitoring a single channel is insufficient. The OpenNIC domains are absent from standard resolvers and most passive DNS databases. The ENS domains are stored on the Ethereum blockchain, making them effectively immutable without the operator's private key. The DoH queries blend into normal HTTPS traffic. MossadProxy's encrypted binary protocol produces no DNS artifacts at all once the initial domain resolution succeeds.

The discovery of MossadProxy illustrates a recurring challenge in threat intelligence: misleading names. The binary called `libproxy.so`, delivered through an APK called `com.android.door`, turned out to be a DDoS bot. Only deep binary analysis — Ghidra decompilation of the native ELF — revealed the actual capability. Surface-level indicators pointed toward proxy functionality that was not present in this build. As a general principle, if a binary tells you what it does in its filename, verify.

The custom RC4 with LCG seed `0xe0a4cbd6` provides a forensic fingerprint for tracking this development lineage as it continues to evolve. The operational data covering Jackskid's tempo — C2 migrations every two weeks, five-phase ADB campaign evolution, campaign tags linking delivery infrastructure to earlier C2 domains — provides a window into how the operator adapts under pressure. And the CatDDoS template sharing pattern documented by XLab is visible here too: the Cecilio variant we decoded shares the broader CatDDoS heritage but diverges cryptographically, showing how leaked source code spreads and mutates across the IoT threat space.

We welcome feedback, corrections, and additional sample submissions from fellow researchers. Reach us on Mastodon at [@deepfield@infosec.exchange](https://infosec.exchange/@deepfield).

## References

This research builds on prior work by the following teams, whose public reporting provided the foundation for our ecosystem mapping. We particularly acknowledge XLab for their foundational Aisuru/Airashi research and their independent documentation of the Kimwolf-Aisuru connection, and Synthient for their Kimwolf infection chain research.

- Synthient, ["A Broken System Fueling Botnets"](https://synthient.com/blog/a-broken-system-fueling-botnets) (Jan 2026) — Kimwolf infection mechanism via residential proxy ADB exploitation; IoCs and samples at [synthient/public-research](https://github.com/synthient/public-research/tree/main/2026/01/kimwolf)
- XLab, ["The Most Powerful Ever? Inside the 11.5Tbps-Scale Mega Botnet AISURU"](https://blog.xlab.qianxin.com/super-large-scale-botnet-aisuru-en/) (Sep 2025) — first public documentation of the modified RC4 algorithm with LCG post-processing, Go reimplementation, and Aisuru family classification
- XLab, ["Botnets Never Die: An Analysis of the Large Scale Botnet AIRASHI"](https://blog.xlab.qianxin.com/large-scale-botnet-airashi-en/) (Jan 2025) — Airashi variant analysis and C2 protocol documentation
- XLab, ["CatDDoS-Related Gangs Have Seen a Recent Surge in Activity"](https://blog.xlab.qianxin.com/catddos-derivative-en/) (May 2024) — CatDDoS derivative ecosystem mapping and shared-key analysis
- XLab, ["Kimwolf Exposed: The Massive Android Botnet with 1.8 Million Infected Devices"](https://blog.xlab.qianxin.com/kimwolf-botnet-en/) (Dec 2025) — Kimwolf family analysis, scale measurement via C2 sinkhole, and independent documentation of the Aisuru-Kimwolf connection via shared APK packaging
- QianXin TIC, ["New Botnet CatDDoS Continues to Evolve"](https://ti.qianxin.com/blog/articles/new-botnet-catddos-continues-to-evolve-en/) (Sep 2023)
- KrebsOnSecurity, ["DDoS Botnet Aisuru Blankets US ISPs in Record DDoS"](https://krebsonsecurity.com/2025/10/ddos-botnet-aisuru-blankets-us-isps-in-record-ddos/) (Oct 2025)
- Cloudflare, ["DDoS Threat Report 2025 Q3 — Including Aisuru, the Apex Predator"](https://blog.cloudflare.com/ddos-threat-report-2025-q3/) (Dec 2025)
- Protos Labs, ["Aisuru Botnet Threat Report: Deep Dive & 29.7 Tbps DDoS"](https://www.protoslabs.io/resources/aisuru-botnet-deep-dive) (2025)
- CNCERT, ["关于RCtea僵尸网络大范围传播的风险提示"](https://www.secrss.com/articles/87776) (Feb 2026)
- Foresiet, ["Mirai Botnet Jackskid Resurgence"](https://foresiet.com/blog/mirai-botnet-jackskid-resurgence-nov-2025-iot-threats/) (Nov 2025) — first public documentation of the Jackskid family name and initial IoCs

## Indicators of compromise

Full IoC tables (domains, IPs, sample hashes, and cryptographic keys) are published alongside this post in the [deepfield/public-research](https://github.com/deepfield/public-research) repository:

- [Aisuru IoCs](https://github.com/deepfield/public-research/tree/main/aisuru/iocs)
- [Kimwolf IoCs](https://github.com/deepfield/public-research/tree/main/kimwolf/iocs)
- [Jackskid IoCs](https://github.com/deepfield/public-research/tree/main/jackskid/iocs)
- [Cecilio IoCs](https://github.com/deepfield/public-research/tree/main/cecilio/iocs)
- [MossadProxy IoCs](https://github.com/deepfield/public-research/tree/main/mossadproxy/iocs)
