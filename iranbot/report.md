# Cattle, not pets: IranBot's disposable botnet

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-07-21**

> **Content warning:** This report quotes malware artifacts verbatim, including C2 strings, banners, and branding chosen by the operator. Some are crude or hateful. They are reproduced exactly as found in the samples so that defenders can match them precisely.

---

## Summary

IranBot is a DDoS botnet that runs the standard malware maturation story in reverse. Over six weeks and three builds, from an armv7l binary on 2026-06-08 to a self-spreading x86_64 worm on 2026-07-20, it shed its command encryption, stripped its polish, and discarded most of its branding. The first build carried a bespoke command cipher, seven attack methods, and a proper systemd service. The last hardcodes a plaintext C2 IP, keeps three attack methods, and prints a generic Chrome User-Agent.

What tracks in parallel is its reach. The same arc that eroded the encryption also added a persistent backdoor (build two) and then a self-replicating Mirai-derived scanner (build three). The build stripped of the most protection is the one now spreading on its own. As of 2026-07-21, the third build's C2 at `103.83.87[.]122:8060` is live.

The infrastructure tells the same story in a different register. No host, autonomous system, or C2 resolution mechanism is reused across the three builds. That fact is compiled into the binaries, not inferred from observed uptime. The operator also stood up a public "lite" tier on GitHub under the handle `t.me/flylegit` (offline as of 2026-07-21), which confirmed two build tracks from what the code indicates is one operation.

---

## The tape runs backward

Malware write-ups almost always tell a maturation story. Each version is stealthier than the last, better encrypted, more careful about hiding. The family invests, and the analysis follows the investment upward. IranBot does the opposite, and it does so on purpose.

Over six weeks and three builds, from an ARM binary on 2026-06-08 to an x86_64 binary on 2026-07-20, each build shipped with less than the last. The first build carried a bespoke command cipher, seven attack methods, and a proper systemd service. The last build hardcodes a plaintext C2 IP address, keeps three attack methods, and prints a generic Chrome User-Agent. By the usual scorecard it [got worse at almost everything](https://en.wikipedia.org/wiki/Enshittification) a botnet is supposed to get better at.

Three things happen at once, and reading them together is the point of this report. First, the command encryption falls: a hand-built cipher becomes a single-byte XOR becomes nothing at all. Second, the reach rises: a drop-only bot grows a persistent backdoor, then a self-propagating scanner. Third, the infrastructure never repeats: every build hardcodes a different C2, on a different hosting network, resolved by a different mechanism. The crudest build, the one stripped of encryption and most of its branding, is the one that grafted on a Mirai spreader. It ships a taunt in its strings: `Not a mirai at all`. The self-propagation code says otherwise. The devolution is not decay; it is triage: to the operator, only what helps the bot spread [sparks joy](https://en.wikipedia.org/wiki/The_Life-Changing_Magic_of_Tidying_Up), and the rest gets cut. It is what a disposable operation looks like in code.

## Meet the family

IranBot signs its work, loudly. The samples print `Iranbot init: death to Israel`, tag their HTTP floods with an `IRAN-BOTNET` User-Agent, and one build even carries a mock copyright line, `Copyright: (7 oct 2023 7:00PM - GMT) Iran Botnet team`, next to the claim that it is `a Registered product under apache license`. None of that is evidence of anything. Branding is theater, and the louder it gets the less it means. A slogan in a binary tells you what the operator wants you to think, not who they are or what the code does.

So we attribute by code. What actually ties these three builds together is the attack engine and its option parser. Every build understands the same set of attack-command options (`psize=`, `srcport=`, `httpmode=`, `gport=`, `gre_proto=`, `msg=`, `usleep=`), parsed the same way, and the two x86_64 builds carry the same reduced method set (`http`, `icmp`, `udpplain`) that is a strict subset of the ARM build's seven. That shared engine, not the slogan, is the thread. The slogan is where we start ignoring the operator and start reading the binary.

A note on confidence: builds one and two are straightforward. Both carry the full IranBot branding block verbatim and were retrieved from documented drop points. Build three's branding is mostly stripped, and it first reached us via an anonymous community tip. We have since pulled the byte-identical binary (`iran.x86_64`) live from its loader at `103.83.87[.]122:80`, alongside thirteen other-architecture builds from the same `telnet.sh`, so the provenance is now firsthand. A cross-architecture decompile then settles the family question: its attack workers are the *same code* as the armv7l build, not merely the same option vocabulary. The HTTP flood, the `udpplain` packet builder, and the option parser share distinctive implementation across ARM and x86_64: the same 1024-socket pool and `0x4040`/`0x42` socket flags, the same 1500-byte MTU cap, the same `-1 << (0x20 - cidr)` wildcard source-spoof idiom, the same `data=random_data` payload literal. One source tree compiled twice. We are confident it is the same family and codebase; the same hands is a strong inference rather than a certainty, since a shared codebase does not by itself prove a shared operator.

## Two curves, crossing

The argument runs in two directions at once. The descending trend is encryption and polish: a bespoke command cipher in build one, a single-byte XOR in build two, nothing in build three. The ascending trend is propagation and danger: drop-only, then a persistent backdoor, then a self-spreading worm. The two cross between the second and third builds, which is exactly where the family stopped protecting its command channel and started replicating itself. The infrastructure underneath never repeats: a different network under a different autonomous system for every build, with the resolution mechanism changing each time. The operator spent less on secrecy and more on spread, and never sat still long enough for any single indicator to matter for long.

## Act I: the encrypted original (armv7l `62e424b2`, 2026-06-08)

The earliest build we captured is the most careful thing we have seen from this operator, though probably not the first they shipped: a bespoke command cipher and a seven-method engine are not where most families begin, so earlier iterations we never saw are plausible. It is a stripped, statically linked 32-bit ARM ELF, delivered on 2026-06-08 from a staging server at `31.56.209[.]125` that also served a raw sibling binary over TCP/4444 and an Android package (`Iranbott.apk`, `com.iranbot.load`). This is a bot built to be handed out and installed, not to spread on its own.

Its most distinctive feature is a real command cipher. The C2 does not send plaintext orders. It sends a framed, encrypted line that begins with the literal `#C `, followed by a seed token, a rounds token, and a hex-encoded payload. The bot accepts between two and seven rounds, decodes the hex, and caps the result at 4 KB of plaintext. Under the hood the decryption does two things, and both tell you how much the operator cared at this stage. It runs a seeded byte permutation, a Fisher-Yates-style shuffle keyed off the seed token, and then it recovers each plaintext byte by brute force, trying all 256 candidate values and checking the transformed output against a fixed mixing constant. (The constants themselves are in the published `iocs/keys.csv`; they do not need repeating here.)

That is more work than a botnet needs. Building a seeded-shuffle-plus-brute-force scheme, and using a separate seeded scheme to hide the C2 domain string inside the binary, is a choice. It is the kind of choice you make when you expect the sample to be pulled apart and you want the teardown to cost something. This is peak investment, and every later build spends less.

The rest of the build matches that posture:

- **Seven attack methods.** The dispatcher handles `http`, `icmp`, `gre`, `udpplain`, `udp`, `tcp`, and `syn`. The raw-socket methods (`icmp`, `udp`, `syn`, and the inner packets of `gre`) build their own IPv4 headers with `IP_HDRINCL` and support source spoofing. The `gre` method is the unusual one: it wraps an inner IPv4 packet in outer protocol 47, and in its inner-TCP mode it sets all six TCP flags at once, [every light on](https://en.wikipedia.org/wiki/Christmas_tree_packet). The `http` flood keeps up to 1024 sockets and tags every request with the `IRAN-BOTNET` User-Agent, which is a loud, easy detection surface for anyone watching outbound requests.
- **Real persistence.** The build installs itself as a systemd unit at `/etc/systemd/system/iranbot.service`. It also spoofs its process title to `[net-worker]` to blend into a `ps` listing.
- **A domain-based C2.** Commands come from `femboys.chloebulldog[.]online:44510`, which resolved to `45.205.1[.]36` (VPSVAULT.HOST, AS215925). Using a dynamic DNS domain rather than a hardcoded address means the backing IP can change without reshipping the binary, so the durable indicator here is the domain, not the address it resolves to.

Put together, Act I is a competent commodity DDoS bot with one genuinely bespoke part. If the family had continued the usual way, the next build would have added a second cipher layer and a few more attack methods. It went the other direction.

## Act II: the backdoor build (x86_64 `7e4d2b3b`, 2026-07-09)

A month later the operator recompiled for x86_64 and started subtracting. This build, first seen as a drop at `http://141.11.88[.]108:81/xpe.x86_64` (BANATSYNC, AS198364) on 2026-07-05 and analyzed on 2026-07-09, keeps the branding and the attack engine but strips the parts that cost effort.

The command cipher is the first thing to go. There is no `#C` frame here and none of the ARM build's cipher constants are present. Commands arrive as plaintext. The only obfuscation left is on the embedded C2 domain string, and it is now a single-byte XOR with the key `0x88` (after stripping a set of shell metacharacters used as padding). That is the difference between a scheme designed to slow down a reverse engineer and a scheme that stops a casual `strings` run and nothing more. The domain it hides is `mythickass.onthewifi[.]com`, on port 313.

How this build resolves that domain is a gift to defenders. The bot does not ask the system resolver. It carries its own small DNS client and sends a raw type-A query over UDP straight to a hardcoded resolver, Quad9 at `9.9.9[.]9:53`, bypassing `/etc/resolv.conf` entirely. If the C2 target already parses as an IP literal it skips DNS altogether; otherwise it talks to `9.9.9[.]9` directly and connects to the first A record it gets back. Whatever the operator intended by this (resilience against a poisoned local resolver, most likely), the behavior it produces is a clean signal: a process emitting DNS directly to `9.9.9[.]9` that the host's own resolver never issued. That is a behavior, not an indicator that ages out.

Now the capability. Having dropped its command encryption, this build adds something the ARM build never had: a way back in. Alongside the outbound C2 client it runs an inbound telnet bindshell. On startup it tries to bind and listen on one of ten candidate ports in shuffled order (a pool that mixes obvious choices like 22 and 23 with high ports like 22222 and 60023), and the first that succeeds becomes the backdoor. Each run generates a fresh 15-character username and 15-character password from `[a-zA-Z0-9]`; the password is kept only as a hash, never in cleartext on disk. Those credentials are then appended to the bot's registration line and sent to the C2, so the operator, and only the operator, learns how to log in. A login serves a branded console (`Welcome to IranBot, Multi-Utility Bot client!`), gates on the credentials, locks the port for 25 seconds after three failed attempts, and on success opens a pseudo-terminal and drops to an interactive `/bin/sh`.

The registration line grows to carry this. The ARM build reported only its architecture and a tag. This build reports architecture, tag, CPU count, RAM, disk size, a root-or-not flag, and, when the bindshell bound successfully, the backdoor port, username, and password. The operator gets a host inventory and a key to the front door in a single line.

The attack surface, meanwhile, shrinks to three methods (`http`, `icmp`, `udpplain`), and persistence gets cruder too: no systemd unit this time, just OOM hardening (setting the process to be spared by the out-of-memory killer), signal masking, the same `[net-worker]` title spoof, and a routine that walks the usual temp directories and kills competing files. Less structure, more digging in.

So the second build is smaller and less protected than the first, and more dangerous. It gave up its command secrecy and bought persistent, operator-only shell access with the savings. As of publication the domain is dormant, with no A record, which is consistent with the pattern in the next act: the infrastructure does not stay up.

## Act III: the worm (x86_64 self-replicating `b1a6dba6`, 2026-07-20)

The third build finishes the trade. It is a larger x86_64 binary (statically linked, non-PIE, stripped) sourced on 2026-07-20, and it is the first IranBot build that spreads on its own.

The command channel now has no protection at all. There is no cipher, no domain, and no DNS. The binary reports `crypto false`, carries none of the earlier cipher constants, and builds its C2 socket inline from a plaintext IP literal: `103.83.87[.]122`, port 8060. The address is compiled straight into the code. This is the end state of the descending curve. Where build one hid its C2 domain behind a seeded shuffle and build two behind an XOR, build three simply prints the address in the clear.

In exchange, this build can replicate. Two spreader modes are driven from the C2, and both are Mirai-derived:

- **`!selfrep telnet`** is a default-credential telnet scanner. It watches for the familiar login prompts and tries a short hardcoded credential list (`postgres`, `xc3511`, `888888`, `default`, `password`, `12345`, `klv1234`, `7ujMko0admin`, `dreambox`), the same kind of list Mirai has used since 2016. On a successful login it runs a one-liner that changes into a writable directory, pulls `telnet.sh` from the loader host over `wget` or `curl`, and executes it.
- **`!selfrep realtek`** is a Realtek SDK exploit spreader. Its staged payloads carry the argv marker `selfrep.realtek`, and it uses BusyBox `wget` to fetch architecture-specific loaders (`mipsel`, `mips`) from the same host.

Both spreaders pull their stagers from the loader host the operator formats in, which in the observed configuration is port 80 on the same IP as the C2. So one box (`103.83.87[.]122`) is C2, stager host, and the seed of the next generation of infections.

The build also adds an on-demand shell (`!openshell`) that serves a password-gated console over the existing C2 socket, distinct from the second build's always-listening bindshell, plus the standard housekeeping of a spreader: it disables the hardware watchdog through the usual device paths and walks `/proc` to hunt and kill rival binaries staged in the temp directories. Persistence moves again, this time to an init script at `/etc/init.d/xs.main` plus `/etc/rc.local`.

Finally, the branding. The verbose block from the earlier builds, the welcome banner, the fake apache license, the mock copyright, is gone. The HTTP flood no longer appends `IRAN-BOTNET`; it uses a generic desktop Chrome User-Agent that looks like every other flood on the internet. Two strings survive the cull. One is `Death to israel`. The other is `Not a mirai at all`.

That second string is the kicker, and it earns no exclamation point. It rides in a binary whose self-propagation is a Mirai default-credential scanner bolted to a Realtek exploit, the two most Mirai things a bot can do. The operator stripped the family's own identity down to a slogan and a denial, then shipped the denial on top of the most generic spreader code in the ecosystem. That is the disposable instinct made literal: do not brand it, do not encrypt it, just make it spread. As of 2026-07-21 this C2 is live, answering a roughly three-second ping keepalive on `103.83.87[.]122:8060`.

## Sidebar: two tiers, one operation

There is a public counterpart to these private builds, and it explains why they diverge. A GitHub repository, `NoSpacesFlies/Iranbot-Botnet`, run by an operator who signs as `t.me/flylegit`, published a plaintext, stripped-down "lite" version of the same family. Its command-and-control server prints the banner `ver: 1.0 - t.me/flylegit | target israel with this`, its admin login is `flies`, and its build script emits loaders named `iran.<arch>` across fourteen architectures. A deployed flylegit build was seen on `83.168.110[.]191:1336` (SkyPass, AS202520). As of 2026-07-21 the repository and the `NoSpacesFlies` account both return GitHub 404s and that C2 is unreachable; the tier described here is from when it was live.

We present the relationship as an observation, corroborated by code, not as an asserted identity. What the code shows is straightforward: the public flylegit repository is a genuine cut-down version of the private IranBot build, sharing the family lineage while dropping the encrypted command frame and the seven-method engine down to a plaintext protocol with a smaller feature set. Two build tiers, a private encrypted one and a public plaintext one, from what the code indicates is one operation. That framing matters for the thesis. If the operator maintains a public "skid" tier next to the private builds, then divergence between builds is not a puzzle to explain away. Shipping many cheap variants at different levels of polish is the operating model, and the private builds devolving toward the public one's plaintext simplicity is a natural consequence, not a mystery.

For the record, the third build analyzed above is not flylegit. Flylegit is not Mirai-derived, uses `method=` attack parameters and four rotating User-Agents, carries the `t.me/flylegit` taunt, and lives on a different C2. None of that is present in `b1a6dba6`. The `iran.<arch>` filename convention is shared, which is why we attribute on the code and not the filename.

## The logic of a disposable botnet

The obvious question is why. Why would an operator run the standard maturation story [in reverse](https://en.wikipedia.org/wiki/Tenet_(film)), abandoning a working command cipher and a proper service installer in favor of a hardcoded IP and an init script? The honest answer comes in two parts: what the binaries prove, and what we are only guessing.

One claim in this report is not open to interpretation: no host, no autonomous system, and no C2 resolution mechanism is reused across the three builds. This is not an inference from observed uptime; it is compiled into the binaries. Build one hardcodes a dynamic DNS domain that resolved on VPSVAULT (AS215925), staged from SWISSNET (AS209373). Build two hardcodes a No-IP dynamic DNS domain and resolves it through Quad9, dropped from BANATSYNC (AS198364). Build three hardcodes a raw IP on Fiba Cloud (AS44382). Counting the public flylegit tier on SkyPass (AS202520), that is five distinct networks across the operation, and the resolution mechanism itself changes every build: a DDNS domain, then a Quad9-resolved DDNS domain, then a bare IP literal. Because each binary carries its own infrastructure, the non-reuse is a hard fact, not a reading of the tea leaves.

The rest is only observation. Individual C2s go dark quickly. As of 2026-07-21 only the newest build's plaintext-IP C2 is live; the first build's C2 resolves but is unreachable, and the second build's domain has no A record. We report that as observed liveness. We do not claim to have watched a deliberate burn-and-rotate, and we do not claim the older C2s are filtering or gating who reaches them. Short lifespans are consistent with disposability, but uptime alone does not prove intent, and we will not dress an observation up as a plan.

With that split in hand, the "why devolve" question has several plausible answers, and all of them are hypotheses rather than conclusions. The simplest is that different hands compiled different builds. A public tier and a private tier, maybe even separate builds within a tier, working from a shared codebase, would produce divergence that reflects who shipped each binary rather than a single design trajectory. A second reading is that the operator just values reach over stealth: if the goal is raw bot count, a plaintext build that spreads on its own is worth more than a polished one that has to be hand-installed, even if a reverse engineer can read it in an afternoon. A third is camouflage. A generic Chrome User-Agent and a commodity Mirai scanner look like the thousands of other Mirai derivatives online, so stripping the `IRAN-BOTNET` tag and the bespoke cipher is its own kind of cover: the build gets by, like a more famous traveler, as [nobody in particular](https://en.wikipedia.org/wiki/Polyphemus). And the plainest possibility is that the targets never justified the polish: if the devices are low value, a hard-to-analyze command cipher buys almost nothing, and cheap wins.

We cannot rank these from the samples alone, and more than one can be true at once. What the evidence does support, without hedging, is the shape: encryption down, propagation up, infrastructure never reused. Disposability is the reading that fits all three at once.

## Detection and defense

The flip side of a disposable operation is a defensive opportunity. If the operator will not keep a C2 alive, then a blocklist of C2 IPs ages out almost as fast as you can write it. The three C2s in this report already tell that story: two of the three are down within weeks of first sighting. Chasing the addresses is a losing race. The behaviors last longer than any single indicator, so lead with those.

- **Hardcoded-resolver DNS.** The second build sends DNS queries straight to Quad9 at `9.9.9[.]9:53` over UDP, bypassing the host's configured resolver. A workload emitting DNS directly to `9.9.9[.]9` that your own resolver never issued is a strong, low-noise signal on hosts that should be using the system resolver. This survives any C2 rotation because it is in the resolution behavior, not the destination.
- **The `[net-worker]` process title.** The first two builds spoof their process name to `[net-worker]` to hide in `ps`. A process advertising that title, with no matching kernel worker, is worth an alert.
- **Default-credential and Realtek exposure.** The third build spreads through telnet default credentials and a Realtek SDK exploit. Neither is novel, and both are preventable. Devices reachable on telnet with vendor-default credentials, and unpatched Realtek-SDK gear, are the entire target set for its spreader. Closing telnet and patching those devices removes the propagation path regardless of which build is current.
- **The HTTP flood.** The reduced x86_64 builds flood with three methods, and the earlier builds tag every request with an `IRAN-BOTNET` User-Agent. Where that tag is present it is trivial to match. Where it is absent (the third build's generic Chrome string), fall back to the flood's shape rather than its label.
- **Backdoor and persistence artifacts.** A telnet listener that appeared on an odd high port with random credentials, an init script at `/etc/init.d/xs.main` wired into `/etc/rc.local`, and a disabled hardware watchdog are all host-forensic tells that outlive the C2 that installed them.

None of these depends on the C2 being up. That is the point. Against a family that treats its infrastructure as disposable, behavioral detection is not a nice-to-have; it is the only thing that keeps working after the IP goes dark.

## Indicators of compromise

The tables below are the compact set; machine-readable CSVs (full hashes, cipher constants, and the rest) are in [`iocs/`](iocs/).

### File hashes

| Build | SHA-256 (prefix) | Arch | First seen |
|---|---|---|---|
| Act I (armv7l) | `62e424b2...` | armv7l | 2026-06-08 |
| Act I (raw sibling) | `83e04563...` | armv7l | 2026-06-08 |
| Act II (backdoor) | `7e4d2b3b...` | x86_64 | 2026-07-09 |
| Act III (self-rep) | `b1a6dba6...` | x86_64 | 2026-07-20 |

### C2 and delivery infrastructure

| Indicator | Port | Role | Hosting | Status (2026-07-21) |
|---|---|---|---|---|
| `femboys.chloebulldog[.]online` -> `45.205.1[.]36` | 44510 | C2 (Act I) | AS215925 VPSVAULT.HOST | Resolves; host unreachable |
| `mythickass.onthewifi[.]com` | 313 | C2 (Act II) | No-IP DDNS | No A record (dormant) |
| `103.83.87[.]122` | 8060 | C2 (Act III) | AS44382 Fiba Cloud | Live |
| `103.83.87[.]122` | 80 | Self-rep stager host (Act III) | AS44382 Fiba Cloud | Live |
| `31.56.209[.]125` | 80, 4444 | Staging / drop (Act I) | AS209373 SWISSNET | Down |
| `141.11.88[.]108` | 81 | Drop point (Act II) | AS198364 BANATSYNC | Down |

### Related tier (observation)

| Indicator | Port | Role | Hosting |
|---|---|---|---|
| `83.168.110[.]191` | 1336 | flylegit public "lite" C2 (unreachable 2026-07-21) | AS202520 SkyPass |
| `NoSpacesFlies/Iranbot-Botnet` (GitHub, 404 as of 2026-07-21), `t.me/flylegit` | | flylegit public tier | |

## Less sophisticated is not less dangerous

It is tempting to read a botnet's crudeness as weakness. IranBot argues the opposite. Over six weeks it threw away the parts that would have slowed a reverse engineer, the command cipher and the polished install, and kept adding the parts that put more machines under the operator's control, a backdoor and then a self-spreading scanner. The build that is easiest to analyze is the one that spreads on its own and is live today.

That is the case for taking disposable operations seriously. They will not reward you with a clean, trackable set of indicators, because the operator does not intend to keep any of them alive. They will hand you a new C2 on a new network every few weeks and a binary that got simpler on the axis you were measuring. The danger did not go down with the sophistication. It moved to a different column. `Not a mirai at all`, the last build [insists](https://en.wikipedia.org/wiki/The_lady_doth_protest_too_much,_methinks), on top of a Mirai spreader. The strings lie; the syscalls don't.
