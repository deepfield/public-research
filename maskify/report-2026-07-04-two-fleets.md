# One `0x07`, two fleets: Maskify forks, and floods Ukraine

**Nokia Deepfield Emergency Response Team (ERT)**

**Published: 2026-07-04**

Follow-up to [Maskify: ENS, IPFS, and a custom mesh network walk into a botnet](report.md) (2026-04-12). That report described the Earnify SDK as a single, dual-purpose Android artifact: a residential proxy that could also flood, driven by a C2 protocol with a dedicated `Flood` command. Three months of live monitoring and reverse engineering say the SDK went the other way. Rather than growing teeth, it lost them: the operator stripped the flood code out of the Android SDK and moved the whole DDoS capability into a separate, purpose-built Linux binary. Same botnet, new floor plan. This report follows that fork, and supersedes the v2 protocol table we published in April. Our own monitor believed that table like gospel. For six weeks it read every `0x07` as a `Flood` and filed the live campaign as garbled `unknown_108` events, so the entire target list sat in our own logs the whole time, immaculately scrambled. We didn't get scooped by the threat actor; we got scooped by our own parser.

> **Content warning:** This report and its indicators reference an Ethereum Name Service (ENS) name, chosen by the threat actors, that contains crude and offensive language. It is reproduced exactly as found in samples to enable accurate detection and attribution.

---

## Summary

Since April the family has forked into two builds that share one codebase and one C2, and the flood engine moved out with the fork.

1. **The proxy SDK is now proxy-only, and the C2 protocol was renumbered.** The v3 SDK (`libearnify_sdk.so` 1.0.7) contains no flood code at all: the three flood modules from the April v2 SDK are gone. The C2 protocol also changed generation: the v2 wire map, with its `0x07 = Flood` opcode, gives way to a `relay1.0.0` map that reassigns every opcode and carries no dedicated flood command. We confirmed the full opcode set on a live QUIC session; none of it is a flood opcode.

2. **The DDoS is tasked through the proxy opcode, and it's a campaign, not a one-off.** With no flood opcode, the operator tasks attacks through the same `0x07 ServiceConnect` used for proxy work. The tell is the destination: a whole subnet, a DDoS-measurement site, or a game server instead of an ordinary proxy destination. Reconstructing the full command stream from our two monitors turns up 163 distinct `ServiceConnect` destinations, 68 of them CIDRs. A `/15` has no proxy reading, so those 68 are unambiguous on their own, but the classification doesn't rest on the address: our control-plane monitor caught the orders and Deepfield network telemetry caught the correlated volumetric UDP landing on those same subnets (native `flood_udp` from the DDoS build, per point 3, not proxied traffic). Shape flags the order; the traffic confirms it.

3. **The native flood engine lives in a new standalone Linux `earnify-client`.** It's a stripped Rust ELF dropped to IoT/Linux hosts, carrying five direct flood methods (UDP, TCP, TLS, SSH, CS2) plus a DNS/CLDAP/memcached amplification set. In practice the amplification set doesn't amplify; the floods we have measured are non-spoofed direct traffic, first plain UDP and, as of 2026-07-04, HTTP/HTTPS application-layer floods from the same fleet.

Same operator, same codebase (`earnify-core` / `relay1.0.0`), same ENS bootstrap, same crypto, same C2 and delivery infrastructure. Two packaging choices carry the attack surface: a proxy-only Android SDK and a standalone Linux client that holds the flood engine. A third artifact, the `guardian` root watchdog, keeps the Android proxy pinned to the device.

## Two builds, one codebase

| | Proxy build | DDoS build |
|---|---|---|
| Artifact | `libearnify_sdk.so` (Android JNI SDK), version 1.0.7 | `earnify-client` (standalone Linux ELF) |
| Delivered as | APK loader → IPFS-hosted `.so` | multi-arch `sh` dropper → raw binary over nc / HTTP |
| Targets | Android TV boxes (ADB) | IoT / Linux (aarch64, armv7/6/5, mips/mipsel, x86_64) |
| Native flood code | none; the v2 flood modules are absent from the 1.0.7 binary; role is proxy/mesh relay | five direct methods (`flood_udp/tcp/tls/ssh/cs2`) + a `flood_amp*` set (no observed amplification) |
| Role in the attack | actions `0x07` as a proxy exit; no flood code, so that is its only mode | actions `0x07` as a native flood on any target, subnet or single host (UDP and L7) |
| Codebase | `earnify-core` / `relay1.0.0`, QUIC (quinn), ENS bootstrap, ChaCha20-Poly1305 | identical |

## The proxy build: SDK 1.0.7

### Delivery moved entirely to IPFS

The HTTP and nc stagers from the April report have gone dark (since roughly 2026-04-23): `84.21.189[.]244:6969` and `158.94.208[.]131:6969` stopped serving, and so did a later staging host, `45.194.92[.]2`. The QUIC C2 at `158.94.208[.]131:4433` is still live and still issuing proxy work. The current SDK is version 1.0.7, built 2026-06-24, distributed only as a gzip'd `libearnify_sdk.so` over IPFS: content-addressed, so it is retrievable from any gateway regardless of the dead origin servers. This is the first build for which we captured the x86_64 SDK. Per-architecture hashes and content identifiers are in [`iocs/`](iocs/).

The update path is otherwise as described in April: an ENS text record on `russianaltushka…[.]eth` (keys `proof` and `ZR`) announces the current version and the IPFS content identifiers; the SDK polls it like a package registry and hot-reloads. The operators still trust a blockchain to distribute their C2 address but not, as we noted last time, TLS certificate validation. Priorities.

### The hidden watchdog: `guardian`

That same ENS `proof` record hides a third artifact. The announcement carries two per-arch packages, not one, and the second is easy to sail past if you stop reading at the SDK. The operator names it `guardian`: an Android root watchdog, shipped for arm64, armv7, and x86_64 and built the same day as SDK 1.0.7. (It also closes an April loose end: the record's per-arch update hashes are SHA3-256 of the *decompressed* artifact, which is why, checking SHA-256 last time, we logged them as an unknown digest.)

Its whole job is to keep `com.android.connectivity.metrics` installed, whitelisted, and running, and to make removal painful. It remounts `/system` read-write to drop itself as `/system/bin/logd_helper` and a `/system/etc/init.d/99guardian` boot script; reinstalls and relaunches the app (`pm install -g -r`, `am start`, `BOOT_COMPLETED`) and exempts it from battery management (`dumpsys deviceidle` whitelist, `appops … RUN_ANY_IN_BACKGROUND allow`, active standby bucket); toggles ADB (`setprop persist.adb.tcp.port`, `adbd`) and firewalls off rival ports (`iptables … --dport 5555/5037/6969 -j DROP`); and re-pulls the APK from the `maskify.workers.dev` origin if it vanishes. A kernel rootkit on the Linux bot, a root watchdog on the Android one: on this family's devices, the legitimate owner is the adversary.

### The SDK dropped its flood code

The April v2 SDK carried three flood modules (`flood_tcp`, `flood_tls`, `flood_udp`). The v3 SDK 1.0.7 carries none: the captured 1.0.7 binary contains no `flood_*` source-path strings and no `earnify_core::flood` reference at all. The proxy SDK is now, by its own code, proxy-only. The flood engine didn't retire. It moved out and got its own place, the standalone `earnify-client` below. This is the botnet's Ship-of-Theseus moment: swap the flood planks out of the SDK, build a new hull around them, and it is somehow both a different program and the same botnet.

### The protocol, renumbered

The April report decoded nine v2 message types and listed `0x07 = Flood` and `0x08 = StopFlood`. That table was inferred from v2 strings before a v3 decompile existed, and the family has since moved on: the current `relay1.0.0` wire is a different protocol generation that reassigns every opcode and no longer carries a dedicated flood command. Reverse engineering the v3 control decoder and, as of 2026-07-03, watching the complete opcode set arrive on a live QUIC control stream, gives the current map:

| Wire | Name | Meaning |
|------|------|---------|
| `0x00` | Register | client → C2 registration (register id, version `1.0.0`, GeoInfo) |
| `0x01` | SessionAuthAck | C2 assigns the `client_id` |
| `0x02` | Ping | keepalive |
| `0x03` | Pong | keepalive |
| `0x04` | ConnectToServer | assign this bot to a mesh peer (`host:4433` + 32-hex service id) |
| `0x05` | AssignedTarget | target assignment |
| `0x06` | ToggleFlag | single-byte flag toggle |
| `0x07` | ServiceConnect | connect to a real destination; the attack-delivery path |
| `0x08` | ServiceStat | benign per-service byte/session counter (see below) |
| `0x09` | Forward | mesh forward (`za_rodinu::forward`) |

The relabeling is total, not confined to the flood commands: `0x01` moved from `Tunnel` to `SessionAuthAck`, `0x02` from `Stop` to `Ping`, and on down the table. This is a protocol generation change, not a corrected reading of the old one, and the dedicated flood command from v2 is simply gone. Messages are length-prefixed (4-byte big-endian) with the wire type as the first payload byte; strings are little-endian 16-bit length-prefixed UTF-8. None of `0x00`–`0x09` is a flood opcode.

`0x08 ServiceStat` earns a footnote because we first flagged it as the prime "unmodeled flood candidate," and it turned out to be the least threatening byte in the protocol. Fourteen live frames settled it: the wire shape is `[0x08][u16 service-name length]["relay-<hex>"][u32 counter]`, always 25 bytes, with no destination and no ports. The `u32` just increments per relay-service (for `relay-fa3e6ae6dace` we watched it climb 11, 12, 13, … 20–25). It is a per-service heartbeat, not a command.

## The attack: one `0x07`, two fleets

There is no `Flood` opcode. Rather than build one, the family aims the proxy's own `0x07 ServiceConnect` at the victim, so a flood of an entire `/15` crosses the wire labelled, with a straight face, as "connecting to a service." That thin disguise is also why the opcode alone gives nothing away. What reverse engineering settles is the attribution: the proxy SDK carries no flood code, so every flood is the `earnify-client` fleet's. Telling an individual order apart is analysis, not a decoded field: we read it from the order's shape (destination, `flags`-selected method, concurrency) and confirm it against the traffic. The destination gives one clean signal and one ambiguous one:

- **A subnet, or a known flood target, is unambiguously an attack.** No one proxies a customer to a `/15`, and DDoS canaries like `dstat[.]st` or game servers are flood targets by reputation. The proxy SDK cannot even act on such an order (no flood code); the standalone `earnify-client` does, with native floods.
- **A single ordinary host is ambiguous.** It might be a proxy exit, the SDK relaying a customer over the Za Rodinu mesh ("for the Motherland," in case the theming was ever subtle) on ports 80/443/22/21/1337. But the flood engine floods one IP as readily as a subnet, so a lone host carrying a real duration and concurrency is just as likely a single-target flood. Shape does not settle it; the traffic, the target's reputation, and the order's burst profile do.

We see this from two vantage points, and they line up. On our control-plane monitor (a node on the same C2) we captured the `0x07 ServiceConnect` orders whose destinations were whole CIDRs on Russian and Ukrainian ISP space (the full target set is reconstructed below). In Deepfield network telemetry we then observed volumetric UDP flooding those same CIDRs, correlated in time with the orders. Because the proxy SDK carries no flood code and would produce TCP relay traffic, the UDP is the `earnify-client` fleet's native `flood_udp`, tasked over the shared C2. The flood is non-spoofed: the victim sees UDP from each bot's real IP, which is exactly what the telemetry shows.

We have also decoded the order itself, the 700-plus-frame breakdown described below, down to which `flags` value drives which flood method. Both the tasking and the resulting flood are directly observed.

### The reconstructed campaign

One day is a keyhole. Re-parsing the full `relay1.0.0` control stream over 2026-05-08 → 2026-07-03 yields 163 distinct `ServiceConnect` destinations, 68 of them CIDRs. You cannot proxy a customer to a subnet, so the 68 CIDRs are flood orders on shape alone; the single-host targets take more than an address to call, and the telemetry below supplies it. (That total includes six weeks of orders our monitor had mangled into garbled `unknown_108` events while it still read `0x07` as `Flood`; the call, it turned out, was coming from inside the house.)

By network, the CIDR flood targets split 30 Russian / 30 Ukrainian, with eight elsewhere (4 DE, 2 NL, 1 CA, 1 KZ). They cluster by AS:

| Targeted network | ASN | Country | CIDRs |
|---|---|---|---|
| Triolan (Kharkiv) | `AS13188` | UA | 15 |
| RS-Media | `AS197309` | RU | 6 |
| ServicePipe (DDoS mitigation) | `AS201706` | RU | 6 |
| AntiDDoS Solutions (DDoS mitigation) | `AS206980` | RU | 5 |
| CYBERFIRST | `AS47122` | RU | 4 |
| VK | `AS47764` | RU | 3 |
| Kyivstar | `AS15895` | UA | 3 |

A Kharkiv consumer ISP tops the list, two Russian DDoS-mitigation providers are getting hit themselves, and the long tail runs through Ukrtelecom, Datagroup, Vodafone Ukraine, and even a Roblox range.

The order format is now decoded from more than 700 live frames. After the destination, each `0x07` carries a *port spec* (a 16-bit length, then a type tag: `0x00` a single port, `0x01` no ports, `0x02` a count followed by that many ports), then a 32-bit duration in seconds and a 32-bit concurrency (thread/connection count). Every order carries both a duration and a concurrency; there is no single-value short form. Target, ports, duration, concurrency: that is not an exotic C2 dialect, it is a stresser's order form serialized to the wire.

The `flags` byte selects the method, and its value tracks the flood family closely enough to read straight off the wire, even though we never byte-decoded the in-binary mapping (see below). `flags=0` carries a real TCP port list (80/443, sometimes 21/22/3389/8080) and high concurrency, tens to a few thousand connections: the connection-oriented `flood_tcp`/`flood_tls` family, which is HTTP/HTTPS L7 when the ports are 80/443. `flags=2` is mostly portless against whole CIDRs with low concurrency: the connectionless `flood_udp`. The `27015` (CS2) and `53` (DNS) orders also ride `flags=2`, which fits, both being UDP query floods, while the eight `flags=20` orders carry port 22 alone and read as `flood_ssh`. So the `27015` against the RS-Media ranges is not a one-off curiosity but one of roughly seven CS2 orders in late June: the method is tasked, not hypothetical.

Laid out in time, the campaign moved in waves, and it has not stopped. Late June it worked the RS-Media (RU) `/21` and its neighbouring `/23`–`/24` blocks with plain `flood_udp`; early July it swung to Triolan and the rest of the Ukrainian ranges, still UDP. Then on 2026-07-04 it changed both method and geography at once: a burst of `flags=0` HTTP/HTTPS floods, concurrency up to 3,200, against AS213229 (Mitelis Security, DE) `/24`s and web hosts like `play2go[.]cloud`. Same `0x07`, same order form, a different method and a different target set. UDP against Ukraine is the campaign's centre of mass; the L7 turn against Germany is its leading edge.

The single-host targets read like a booter's order history:

- **Game servers:** VimeWorld/Minecraft, Hypixel, `magicrust[.]gg` and `thisisrust[.]ru` (Rust), `blackrussia[.]online`
- **Betting:** `fon[.]bet`, `winline[.]ru`
- **DDoS measurement and mitigation:** `dstat[.]st`, `ddos-guard[.]net`, `stormwall[.]pro`
- **Rival stresser/proxy infra:** `nettify[.]xyz`, `piproxies[.]com`
- **One outlier:** `krebsonsecurity[.]com`, hit 2026-06-28 via the same `relay-2547b1fe7625` used on the RS-Media hosts. Nobody will [leave Krebs alone](https://www.youtube.com/watch?v=WqSTXuJeTks).

(Ordinary proxy-exit destinations, i.e. real customer traffic rather than victims, are excluded here and from the IoCs.)

And it is not inferred from the control channel alone: our DDoS detection has the matching samples. In one multi-hour event, Triolan absorbed roughly 60% of the flood by volume, the rest landing on Ukrtelecom, Vodafone Ukraine, `uar.net`, Datagroup, and Dataline (the carriers the tasking named), with tens of thousands of unique sources per network. The `0x07` orders are the plan; this is the plan landing.

On the mesh side, the `0x04 ConnectToServer` stream names six relay peers, split between `AS61254` (ESTOXY OU / pushpkt, EE) and the `AS204044` (Packet Star, GB) `130.78.216.0/22` block. `37.49.230[.]40`, which we first met as a VirusTotal co-communication endpoint, is in fact the busiest relay (6,087 assignments), and `130.78.217[.]194` served as a peer in May before its July turn as the dropper host. The full peer list is in the IoCs.

## The DDoS build: standalone `earnify-client`

The other half of the fork is a distinct Linux build line, `earnify-client`: same family, same Rust crate tree, same ENS/QUIC lineage, but built as a standalone bot for Linux/IoT hosts and carrying the flood engine the SDK dropped. Its branding gives it away. The binary calls itself the "Earnify bandwidth seller client" and carries the proxy-earner flags (`--account-token`, `--contribute` for "no earnings") beside `--install` (auto-start) and `--persist` ("advanced persistence… multi-layer install"). It understood the assignment, then packed the flood modules for the trip.

### Samples and build

Two builds analysed:

| SHA-256 | Arch | Note |
|---|---|---|
| `03d09c35…daa2dca` | ARM aarch64 | statically linked; full decompile; VirusTotal co-communicates with `37.49.230[.]40` |
| `a4e560c6…582600` | x86-64 | static-PIE, stripped; MalwareBazaar filename literally `bot.x86_64` |

Both are stripped Rust binaries built from the same source. Their embedded crate versions and source-path strings are identical across the two architectures: `chacha20poly1305 0.10.1`, `quinn 0.11.9`, `rustls 0.23.37`, `tokio 1.50.0`, `clap_builder 4.6.0`, `base64 0.22.1`, `bytes 1.11.1`, `socket2 0.6.3`, the same `earnify-core/src/*` module tree as the Android SDK. It is effectively a software bill of materials the author never meant to ship.

### Delivery

A small multi-arch `sh` dropper (`609ecf41…6cacc.sh`) reads `uname -m`, pulls the matching build from `130.78.217[.]194` (AS204044, the same `130.78.216.0/22` GB block as the mesh peers, and an ex-mesh-peer itself) over a per-arch `nc` port with an HTTP fallback, drops it into the first writable tmpfs, runs it, and deletes the file. The dropped instance runs with no consent gate and no account token; the earner persona stays in the closet on these IoT hosts. The armv5/armv7/mips/mipsel builds are advertised but not yet captured; the x86_64 build came from MalwareBazaar.

### Transport and command layer

The transport is the family's usual QUIC-over-`quinn` with ALPN `h3`/`relay1` and TLS certificate validation disabled [(of course)](https://docs.rs/rustls/latest/rustls/client/danger/index.html). Bootstrap is ENS-only. There is no `--server` command-line override; the binary carries a full on-chain resolver (JSON-RPC `eth_call` with "no TXT records" / "no resolver set for this ENS name" error strings) and constructs the `.eth` name and RPC endpoint at runtime, consistent with the SDK's `russianaltushka…[.]eth` bootstrap.

The command channel (`control.rs`) is a Rust async state machine over the QUIC control stream. The native flood code is present as discrete source modules under `earnify-core/src/`, all confirmed by source-path strings in both builds: a `flood.rs` dispatcher and a shared `flood_target.rs` target/port parser, driving five direct flood methods and an amplification set:

| Module | Method |
|---|---|
| `flood_udp` | direct UDP flood (the engine behind the observed CIDR floods) |
| `flood_tcp` | HTTP/L7 flood over TCP (GET/POST request templates); observed in the wild 2026-07-04 |
| `flood_tls` | HTTPS/L7 flood over TLS (same templates, wrapped in TLS); observed in the wild 2026-07-04 |
| `flood_ssh` | SSH flood; opens with an `SSH-2.0-` client banner; tasked (`flags=20`, port 22) but not confirmed landing |
| `flood_cs2` | Source-engine query flood; sends `TSource Engine Query` (A2S_INFO); tasked against RS-Media ranges in June |
| `flood_amp` (+ `_dns` / `_cldap` / `_memcached`) | amplification: a shared base, with thin per-protocol builders for DNS (an `ANY` query for `isc.org` with EDNS0, UDP/53), CLDAP (an `objectClass` search, UDP/389), and memcached (`stats`, UDP/11211) |

The `flood_tcp` and `flood_tls` methods are HTTP application-layer floods, not raw TCP/TLS: the binary carries `GET` and `POST` request templates (`GET <path> HTTP/1.1\r\nHost: <host>\r\nConnection: close\r\n`, plus a `POST` variant) with a `0xC0` marker where the per-target path and Host are substituted at send time. `flood_tls` wraps the same requests in a TLS session.

The `flood_amp*` modules build valid reflection request payloads (the CLDAP `objectclass` and memcached `stats` strings are in the binary), and no reflector list is hardcoded, so targets arrive with the task. In practice, though, the floods we have observed are non-spoofed, sent from the bots' real IPs, with no reflected-amplification behaviour. It's giving amplification; it is not, in fact, amplifying. For defenders, that means no reflection signature to hunt for. (The rest of the crate tree is the usual `ens`/`dns`/`quic`/`tunnel`/`updater` plumbing plus the `za-rodinu` mesh.)

Each flood method reads a common attack struct: a method selector, a target set (up to five entries), a port spec, a concurrency (thread/connection) count, a duration, and, for the packet methods, an attacker-supplied payload (empty ones are rejected with "packet payload is empty"). The on-wire `0x07` order that fills it, `flags` selector included, is decoded in the campaign section above.

### Persistence, a kernel rootkit, and a shell

Where the proxy SDK just wants to keep proxying, the standalone client digs in. `linux_persist.rs` lays down persistence in nearly every way a Linux host offers, each pointing back at a self-copy of the bot: a systemd service (`Description=System Service Handler`, `Restart=always`) installed both system-wide and per-user with `enable-linger` so it survives logout; a `@reboot` crontab line; `/etc/rc.local`; a `.bashrc` append; an XDG autostart `.desktop`; and copies of itself into `~/.local/bin/sys`, `~/.mozilla/sys`, and `~/.cache/thumbnails/sys`. At runtime it masquerades via `prctl(PR_SET_NAME)`, wearing names like [`systemd-udevd`](https://man7.org/linux/man-pages/man8/systemd-udevd.service.8.html), `dbus-daemon`, and `NetworkManager`, and it `chattr +i`'s its own files so a hurried cleanup bounces off. Belt, suspenders, and a second belt.

The part that graduates it from bot to implant is a kernel module, `syshandler.ko`. The client `insmod`s it (and wires `/etc/modules-load.d` so it reloads at boot), then drives it by writing `hide <pid>` to `/proc/sys_handler`, the signature of an LKM rootkit hiding the bot's process and files from the box's own operator; wave a hand and, as far as `ps` is concerned, these aren't the processes you're looking for. We can describe that interface exactly, because the userland half is in the binary; we cannot yet disassemble the module, because the `.ko` isn't shipped inside the client (no embedded module, no download URL). It arrives out-of-band, from the operator's kit, which is its own tell: this is tooling, not a hobby.

Two capabilities round the client out beyond flooding. `exec.rs` is a `/bin/sh` command runner: arbitrary command execution tasked over the same C2 (which opcode triggers it is lost in the async dispatch, like the flood methods). `updater.rs` hot-swaps `/proc/self/exe` after an SHA3 check, the Linux echo of the SDK's IPFS self-update. There is a `discovery.rs` too, but it reads as mesh-peer discovery, not host scanning: this build spreads by being dropped, not by hunting.

### Attribution and a scope note

This is the same operator and codebase as the Maskify/Earnify Android SDK: identical `earnify-core` crate tree, `relay1.0.0` build string, ENS bootstrap, ChaCha20-Poly1305, and shared infrastructure (VirusTotal co-communication with `37.49.230[.]40` on AS61254/pushpkt, which the reconstruction upgrades from co-comm endpoint to the fleet's busiest mesh peer; delivery from the AS204044 block that hosts the other peers). The material difference from the Android SDK is that this build is a standalone full DDoS bot, not a proxy.

The attack chain runs end to end: the `0x07 ServiceConnect` CIDR flood order on the control channel, matched to volumetric UDP against the same CIDRs in our detection telemetry, attributed to `earnify-client`'s native `flood_udp` by elimination, since the proxy SDK has no flood code. The attack itself, now UDP and HTTP/HTTPS alike, is observed and classified.

## "A legitimate residential proxy platform"

In a [public reply](https://x.com/earnifysu/status/2070293592979980711) to the [community attribution](https://x.com/deobfuscately/status/2041151620486987898), the operator's account (`@earnifysu`, verified) rejected the botnet label:

> This is false and reckless. Earnify is opt-in bandwidth sharing: ✅ Users consent before it runs (`set_consent(1)` SDK gate) ✅ Compensated for bandwidth ✅ Port + private IP filtering (blocks SSH/ADB/Telnet) ✅ Can stop anytime. Botnet = non-consensual malware. We're a legitimate residential proxy platform. We'll walk through the code with any serious researcher who asks.

Two of those claims are true in the code, which is more than most operators manage. Neither survives contact with how the software actually reaches devices.

The consent gate is real: `setConsent(1)` really does gate proxying in the code, and revoking it disconnects (we confirmed this in April). But it is called by the embedding app, not the person who owns the TV box, and April's report traced that app onto devices through ADB exploitation of exposed boxes. Nobody there consented to anything; the checkbox is checked from the outside.

The port and private-IP filter is real too, but it governs where the SDK will proxy *a customer's* traffic (blocking SSH/ADB/Telnet and RFC1918/bogon exits). It says nothing about how the *operator* aims the fleet, which is the whole ballgame: pointing `0x07 ServiceConnect` at a Ukrainian `/15`, `dstat[.]st`, and a Rust server is not something a filter on customer exits was ever going to stop.

And the "legitimate residential proxy platform" line is undercut by the operator's own second product. The standalone `earnify-client` wears the identical costume ("bandwidth seller client," account-token, contribute-mode) over native flood modules, a kernel rootkit, and a multi-layer persistence installer, dropped to IoT hosts that never saw a consent screen. The rootkit gives the game away: a platform that genuinely ran on consent would have no one to hide from. The offer to "walk through the code with any serious researcher" is generous but narrowly scoped: it invites you to admire the consenting proxy SDK while the DDoS build wearing the same logo ships to devices that were never asked. We accept the invitation, respectfully, in the form of this report.

Said without the usual snark: we would genuinely rather not be writing this one. The mesh, the on-chain bootstrap, and the compact wire protocol are real engineering, and there is a legitimate market for exactly these skills, residential bandwidth, protocol work, even the DDoS-mitigation industry that spends its days fighting floods like this one, none of which requires shipping a rootkit to a stranger's TV box. We are reading the "legitimate platform" claim as a statement of intent, and we would be glad to report, a year or two from now, that it turned out to be true. The way there stays open.

## Confidence

This report is built on direct observation. The `0x00`–`0x09` opcode map came off a live control stream; the flood orders are settled by the destination and the matching telemetry together, not by shape alone; and the UDP floods are measured (the receipts above). That the proxy SDK carries no flood code, and that the amplification modules cannot spoof, are read directly from the binaries.

The one genuinely open item is narrower than it first looked, and got narrower again this week. The `0x07` order format itself is decoded (target, method flag, port spec, duration, and concurrency, off more than 700 live frames), and the wire now maps `flags` to method family on its own: `flags=0` to the HTTP/HTTPS L7 floods observed on 07-04, `flags=2` to the UDP, `flags=20` to SSH. What we still cannot read is the exact in-binary constant behind that dispatch, because it runs through a merged async `Future` we could not byte-decode; at this point that is a formality, not an operational gap. The `za-rodinu` mesh data plane and the three rarely-seen control opcodes (`0x05` AssignedTarget, `0x06` ToggleFlag, `0x09` Forward) are identified but not fully specified. And the kernel module `syshandler.ko` is described from its userland control interface (`/proc/sys_handler`, `hide <pid>`) but not disassembled: the `.ko` isn't in the client binary, so its internals wait on recovering a copy.

## For defenders

The family no longer has a distinct `Flood` opcode, and the proxy SDK no longer carries flood code. The DDoS rides the same `0x07 ServiceConnect` as legitimate proxy work, told apart only by a subnet or canary destination, and the traffic is a non-spoofed native flood from real source IPs, the work of the standalone `earnify-client`, not the proxy SDK. Four takeaways:

1. On the C2 control channel, a `0x07` to a subnet (or to a DDoS canary) is an attack order, not a proxy exit. That is the alertable signal, and the decoded order yields the target, ports, duration, and concurrency to carry into the alert; the reconstruction shows it firing at scale, not as a curiosity.
2. Both builds bootstrap from the same ENS-resolved C2, so blocking it cuts tasking for the proxy fleet and the DDoS fleet at once.
3. Expect direct floods, not reflection: the traffic is non-spoofed, whether it's the volumetric UDP or the newly observed HTTP/HTTPS application-layer floods, and we've seen no reflected-amplification behaviour to hunt for.
4. On the host, the DDoS build persists hard and loads a kernel rootkit. Hunt for a systemd `earnify.service` (`Description=System Service Handler`), a `syshandler.ko` / `/proc/sys_handler`, `@reboot` cron entries, and self-copies at `~/.local/bin/sys` / `~/.mozilla/sys` / `~/.cache/thumbnails/sys`. The Android side has its own enforcer: hunt for `/system/bin/logd_helper`, `/system/etc/init.d/99guardian`, and repeated reinstalls of `com.android.connectivity.metrics`. And remember the Linux build also carries a command-execution path, so a compromised host is more than a flood source.

## The bottom line

Strip away the blockchain bootstrap and the mesh overlay and Maskify is doing something almost old-fashioned: renting out other people's devices, then pointing them at whoever paid to knock a Rust server, a Ukrainian ISP, or Brian Krebs offline. The mechanics changed since April: a split into a proxy SDK and a standalone DDoS bot, a renumbered protocol, content-addressed payloads that outlive their origin servers. The build quality outran the judgment behind it: a C2 address entrusted to a public blockchain while certificate validation is switched off, a DDoS bot still sold as a "bandwidth" app.

The family started with the bluntest tool in the box, plain UDP, and still knocks Ukrainian ISPs around at will. As of 2026-07-04 it has reached for the application layer too: HTTP and HTTPS floods (`flood_tcp`/`flood_tls`) alongside the UDP. SSH and CS2 show up in the tasking as well (`flags=20` on port 22, a run of `27015` orders), which leaves only the amplification that can't amplify still purely theoretical. Whether the operator ever leans on it is their call, but every build, proxy and DDoS alike, answers to the same ENS-resolved C2, and that is still the one wire worth cutting.

## Indicators of compromise

Full hashes, IPs, domains, IPFS content identifiers, and mesh-peer addresses are in [`iocs/`](iocs/). Indicators new since the April report:

- **SDK 1.0.7** (`libearnify_sdk.so`, built 2026-06-24): arm64-v8a `c077e545…`, armeabi-v7a `7a8b3a52…`, x86_64 `3728e40c…` (first x86_64 capture); IPFS CIDs `QmRvKTy11…`, `QmUa7oB9…`, `QmWZj57o1…`.
- **`guardian` Android root watchdog** (2nd ENS package, built 2026-06-24): arm64-v8a `eb3e217b…`, armeabi-v7a `76cd2ba2…`, x86_64 `c8910b76…`; IPFS CIDs `QmTDR9p4mS…`, `QmUiAnR1Dc…`, `QmbqW5ze6w…`. Host artefacts: `/system/bin/logd_helper`, `/system/etc/init.d/99guardian`, `/data/data/com.android.connectivity.metrics/files/guardian_config`.
- **Standalone Linux DDoS build** (`earnify-client`): aarch64 `03d09c35…`, x86-64 `a4e560c6…`; dropper `609ecf41…`.
- **Delivery host:** `130.78.217[.]194` (AS204044); also an early mesh peer.
- **Host persistence / rootkit:** systemd `earnify.service`; LKM `syshandler.ko` + `/proc/sys_handler` (`hide <pid>`) control; `/etc/modules-load.d/syshandler.conf` autoload; self-copies `~/.local/bin/sys`, `~/.mozilla/sys`, `~/.cache/thumbnails/sys`; `@reboot` cron; `chattr +i` on the above.
- **Mesh peers:** `37.49.230[.]40` (AS61254, busiest), `37.49.224[.]110` (AS61254), `45.139.197[.]242`, `130.78.218[.]202`, `130.78.219[.]74` (AS204044).

## References

- [Maskify: ENS, IPFS, and a custom mesh network walk into a botnet](report.md) — the April 2026 report this updates (Nokia Deepfield ERT)
- Ben / Synthient ([@deobfuscately](https://x.com/deobfuscately/status/2041151620486987898)), "Earnify // Maskify Botnet" — community attribution
- Earnify ([@earnifysu](https://x.com/earnifysu/status/2070293592979980711)), operator's public reply disputing the botnet attribution
- [Aisuru ecosystem report](../reports/2026-03-20-aisuru-ecosystem.md) — the broader ADB TV box attack surface (Nokia Deepfield ERT, March 2026)
