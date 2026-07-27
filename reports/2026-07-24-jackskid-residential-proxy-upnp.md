# Jackskid's residential proxy, brought to you by UPnP

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-07-24** · **Updated: 2026-07-27** (see [edit history](#edit-history))

## Summary

Most residential-proxy malware works hard to stay invisible. The infected device dials out to a director, holds the connection open, and tunnels customer traffic back through it. Nothing listens; nothing is reachable from the internet; the only footprint is one long-lived outbound connection that, from the network's side, looks like a device talking to a server.

The reticence is not only technical. The large commercial vendors that sell residential exits [legally](https://krebsonsecurity.com/2026/06/popa-botnet-linked-to-publicly-traded-israeli-firm/) have spent years learning to describe themselves as anything but a proxy service: web-data collection, content-indexing networks, [panels of users who opted in](https://conferences.computer.org/sp/pdfs/sp/2019/ResidentEvilUnderstandingResidentialIPProxyasa.pdf), for generous values of "opted in." On both sides of the law, "proxy" is the word this market would rather you did not say out loud.

The malware in this report puts the exit where anyone can see it. On startup the bot has the victim's own router open 165 ports, forwards them to the infected device, and labels every one `RELAY`. The residential exit is not hidden behind a tunnel; it is published on the home router's external interface, with a description field that says what it is.

Pulling on that one design choice, exposing the exit through UPnP instead of tunneling it out, led to three families run by one operator: trees4sale, a residential-proxy relay with no attack capability at all; peer4you-mirai, a Mirai bot whose infected devices moonlight as proxy nodes; and Jackskid, a DDoS botnet we and others have tracked since late 2025. The proxy side and one half of Jackskid share a byte-identical encryption key, the kind of shared secret that does not happen by accident. The operator worked to make the pieces look unrelated, rotating the names, the keys, the servers, even the blockchain wallets, and then tied them back together with one funding wallet and one reused key. This is the story of the technique, the families behind it, and the two things the operator did not think to change. It is also, in its newest builds, the story of the DDoS botnet and the proxy service collapsing back into the same code.

## 165 doors labelled RELAY

UPnP's Internet Gateway Device protocol exists so that a game console or a video-call app can ask the home router to open a port without the user ever learning what a port is. The router trusts anything on the local network to make that request, which is roughly why UPnP has spent the better part of two decades near the top of every ["things to turn off on your router"](https://www.rapid7.com/blog/post/2013/01/29/security-flaws-in-universal-plug-and-play-unplug-dont-play/) list. The protocol was built to spare users the indignity of manual port-forwarding. It turns out it spares malware the same indignity.

Reverse-engineered, the relay's startup is unremarkable UPnP right up to one field. It binds a local ingress, runs an SSDP discovery for the router's Internet Gateway Device, and asks the router to open 165 ports from a fixed table. The description attached to every one of those mappings is the tell:

```
NewPortMappingDescription=RELAY
```

That is the whole idea. A residential-proxy exit that would normally hide behind a backconnect tunnel is instead published on the home router's external interface, 165 ports wide, each one labelled with what it is. A client connects to a mapped port, the bot bridges it onward, and the line gets benchmarked first, the way a rideshare platform vets a car. Slow inventory does not sell.

None of this is quiet. Where a backconnect tunnel is a single outbound connection, this is an SSDP burst, then 165 SOAP calls to the gateway, then 165 external ports left open on a home router with `RELAY` typed into the description of each, a field the router's own admin page will read back to anyone who looks. The operator traded stealth for scale: exposing the exit through the router's own NAT traversal is lighter than a per-victim reverse tunnel and holds a large fleet without a director keeping a socket open for every node. Most proxy malware pays for that scale in stealth. This one declined to pay, and wrote `RELAY` on the receipt.

## The peer4you operation

The relay code that does all of the above is shared across the cluster. The two standalone proxy families, trees4sale and peer4you-mirai, match the full behavioural signature: UPnP `AddPortMapping` with `RELAY` descriptions plus `{"status":"ONLINE","bandwidth_mbps":…}` telemetry reported to the peer4you brand, whose director API and login panel front the operation. (A third carrier, the DDoS family Jackskid, embeds the same relay code in its newest builds but beacons differently; that is the next section.) What differs is what else the binary carries.

trees4sale is the pure case. We reverse-engineered it end to end, and not one function in it attacks anything: no raw sockets, no flood builders, no scanner, no credential list, no attack-command table. Its config is not even encrypted; the C2 domains sit in the binary as plaintext strings. Someone took a Mirai-lineage bot and carefully removed the Mirai. What is left is a tidy relay that resolves two hardcoded domains, opens the 165 doors, and bridges connections to a fixed operator backend. It is the rare botnet build that is all overhead and no menace, which is exactly what you want if your business is renting access to residential IPs rather than knocking targets offline.

The relay's control plane is minimal to match. The `ONLINE` telemetry is one-directional, so there is no director-to-bot command stream to intercept; the node advertises itself and waits for inbound connections on its mapped ports. Its directors:

- `login.trees4sale[.]net` → `185.104.63[.]79`, the director on tcp/`18702` (aarch64 builds) and tcp/`9000` (arm builds), with Apache on `:80` serving a 10 MB blob (the bandwidth-test and loader payload).
- `38.87.116[.]165` (Datalix, DE), a fully-exposed second director with `:18702`, `:9000`, `:8081`, `:80`, and `:443` all open: the same port set, unfiltered.
- `www.trees4sale[.]net` → `76.164.203[.]165`, an Apache open-directory loader host.

The apex domain has a backstory. `trees4sale[.]net` is not freshly coined: passive DNS traces it to 2011, when it lived at AT&T, through a stint on Amazon and DigitalOcean, and then years parked on Confluence Networks before the operator drafted it into service in May 2026. An aged domain with a dull past is worth money precisely because it reads as dull: a clean reputation and a registration date that predates the botnet by fifteen years. A reputation service flags it "newly registered," which is true of the recent WHOIS re-registration and misleading about everything else.

peer4you-mirai is the same relay bolted onto a live Mirai bot. These builds keep the residential-proxy relay, same UPnP `RELAY` mappings and `ONLINE` telemetry, but add back everything trees4sale removed: a telnet brute-force scanner (targeting, among others, TJ2100N GPON optical-network terminals via their default credentials), a busybox echo-drop loader (`.d` / `.ffaaxx` / `telnet.echo`), and a full Mirai C2 stack. Its C2 wire protocol is encrypted with standard primitives: X25519 key exchange, then a byte-swapped ChaCha20 with HMAC-SHA256, keyed per connection, with no static key to extract. The bot resolves its C2 through `www.c1s[.]su` and reports to a director on port `9000`. Running a Mirai bot and an open UPnP router on the same device is roughly two decades of IoT-security guidance ignored in one binary.

So peer4you-mirai is the bridge: an infected device that scans for and infects more devices *and* enrolls itself as a proxy node. In these builds the DDoS bot and the proxy relay are the same process. The residential-proxy business and the botnet are not two operations that happen to share infrastructure; they are two functions compiled into one file.

Three pieces of infrastructure show up in the binaries and at runtime:

- `i.peer4you[.]net` → `45.138.16[.]96` (1337 Services, PL): in mid-July it ran the relay director API on `:9000`, answering relay `POST` bodies with `Access-Control-Allow-Origin: *` and a 404 to browsers, alongside a "Peer Server - Login" panel on `:8080`. Even proxy directors have a brand. The peer4you directors then consolidated onto the shared node `185.104.63[.]79` (below).
- `185.104.63[.]79`: a second peer4you backconnect director, and the same physical host as the trees4sale director. One box, both proxy families.
- `o.peer4you[.]net`: a pool of five Akamai/Linode datacenter IPs, geolocated to India, Australia, Brazil, Canada, and France, that the relay resolves at runtime.

The obvious question is why a residential-proxy operation needs a datacenter pool at all, and here we can describe the parts with more confidence than the whole circuit. What the binary does is definite: it opens the 165 UPnP ports, reports `ONLINE` to a director, and, on an inbound connection to a mapped port, bridges it to a fixed backend rather than to a customer-supplied address. What we did not observe is a live customer session, because the director channel is fire-and-forget and the samples never fetch a routing assignment. So the residential node is reachable from the internet (not a classic backconnect tunnel) and it also phones home to a director (which is backconnect-like), and there is a separate datacenter tier, `o.peer4you[.]net`, whose exact role we cannot pin down: customer entry point, actual egress, or coordination. We would rather flag that gap than fill it with a guess. Residential-proxy operations run all three arrangements, and telling them apart needs the director's side of the conversation, which these samples do not give up.

The peer4you report and loader endpoints hide behind a theme. They live on `inhumanencounters[.]org`, and the two subdomains the binaries actually contact, `boblazar` and `roswell`, keep up a [UFO](https://en.wikipedia.org/wiki/Bob_Lazar) theme, fitting for a service whose job is making traffic look like it came from somewhere it didn't. (A third sibling, `cocoa`, we have only from passive DNS.)

## The DDoS arm that stocks the shelves

A residential-proxy service is only as large as its supply of residential devices. peer4you-mirai enrolls the devices it infects by telnet scanning, and it does not stand alone: it is wired into a much larger DDoS operation, Jackskid.

Jackskid is not new. It was [documented by Foresiet](https://foresiet.com/blog/mirai-botnet-jackskid-resurgence-nov-2025-iot-threats/) in November 2025, tracked by [CNCERT](https://www.secrss.com/articles/87776) as "RCtea," and known in the DDoS scene as "Mossad"; we placed it in the [Aisuru development lineage](2026-03-20-aisuru-ecosystem.md) via a custom RC4 modification (a 5-pass S-box scramble seeded with `0xe0a4cbd6`). One caveat on that nickname: "Mossad" here means Jackskid, not [MossadProxy](../mossadproxy/), a separate botnet we track with a different codebase and no shared lineage. Same word, different family. It was disrupted alongside the rest of the Aisuru cluster in the [March 2026 law-enforcement action](https://www.justice.gov/usao-ak/pr/authorities-disrupt-worlds-largest-iot-ddos-botnets-responsible-record-breaking-attacks) and regrouped. Today it resolves its C2 through Ethereum Name Service (ENS) and Solana Name Service (SNS) dead-drop records rather than DNS, and in its newest builds those records point at a director rather than at the C2 servers themselves.

What is new is that Jackskid now runs as two parallel sets of infrastructure that share almost nothing on the surface:

- One set resolves C2 through `ukranianhorseriding[.]eth` and `burrberry[.]eth`, uses the config keys `DEADBEEF CAFEBABE E0A4CBD6 BADC0DE5` and `08453CD1 …` (plus a 24-byte ARX variant in some builds), and points at an Akamai/Tencent/Alibaba C2 pool. Its on-chain name-owner wallet is `0x435c…`.
- The other resolves through `meower[.]eth` (registered with two Solana names in a single day) and points at the `www.c1s[.]su` pool. It uses the config key `8BADF00D FEEDFACE ABAD1DEA C001D00D`. Its name-owner wallet is `0x45c5…`. This is the tier that carries the garm telnet scanner and the i386 builds, and it delivers through `.ffaaxx` echo-drop loaders and TVT/NVMS9000 DVR shell exploitation.

Two ENS names, two key sets, two C2 pools, two blockchain wallets. Found separately, you would file them as two operators. That is the point of building them this way.

The first link between them is cryptographic. peer4you-mirai's config-deobfuscation key is `8badf00d feedface abad1dea c001d00d`, byte for byte the key used by Jackskid's `c1s[.]su` tier: rebuilding the S-box from `8badf00d` reproduces peer4you-mirai's hardcoded table exactly, down to the same `0xe0a4cbd6` LCG seed, `0xd800a4` LFSR polynomial, and output whitening. A reused key is not proof of one operator on its own, since both source and keys circulate; but this one is *absent* from the `ukranianhorseriding` tier, so whatever it binds, it binds to the `c1s[.]su` tier specifically and not to Jackskid as a whole.

The key is also a small act of self-expression. It reads like [hexspeak](https://en.wikipedia.org/wiki/Hexspeak): `8badf00d feedface abad1dea c001d00d`, four words of pronounceable hex. The third one is, if nothing else, an honest self-assessment.

The late-July builds remove even the need to infer it. On 23 July, a Jackskid Android APK (`com.android.s4protect`, `1a9a54eb…`) changed shape: where earlier builds dropped a single DDoS bot, this one drops two binaries side by side. The first is the familiar `inix` DDoS bot; the second, `lol2`, is the peer4you relay, identifiable at runtime by the same `127.0.0.1:40538` ingress and the same 165-port `RELAY` table. Its director is a new domain, `persistfromchicago[.]com` (with `n1.` for node registration and a `tractor.` subdomain that echoes `tractor.trees4sale[.]net`), on the same Cloudflare account as `peer4you[.]net`. Somewhere between `inhumanencounters` and `tractor.trees4sale`, the operator's domain naming gave up on a house style and settled for moods. The proxy relay is no longer merely tied to Jackskid by a shared key; it ships inside Jackskid's own Android payload, one process to flood targets and another to rent the device out. The tier it ships in is the original one: the APK's DDoS payload resolves through `burrberry[.]eth`, `ukranianhorseriding[.]eth`, and `24carnforth2merseyside[.]sol`, all Tier A dead-drops, rather than the Tier B set that shares the key with peer4you-mirai. Both tiers have now carried the relay.

That build did not last. On 27 July the same delivery node served a renamed APK, `com.android.wall.color.cinnamon` (`695ab309…`), that drops `lol2` and reverts to a single payload; the DDoS binary inside is byte-identical to the one shipped since 20 July. On Android, the dual-payload design looks like a four-day experiment. The rest of that rotation is anti-blocklist churn, new package name, new signing certificate, new campaign tag, and no new capability.

The Linux side goes further still. In the Tier B DDoS builds from late July, the relay is not even a separate module: it is compiled into the DDoS bot itself. The MIPS and ARM samples we examined (`06c4ddab`, `01d5fba3`) carry, alongside the usual flood handlers and the `.ffaaxx`/`telnet.echo` loader, the peer4you relay's exact SOAP `AddPortMapping` envelope (`NewPortMappingDescription>RELAY`), the SSDP `InternetGatewayDevice` discovery, and the `POST /heartbeat` telemetry with its `connections=…&bandwidth=…` body, reported to a localhost coordinator rather than the remote director the standalone proxy families beacon to. The same binary that floods a target will, on the same device, open the router and stand up a residential relay. At that point the line between the DDoS botnet and the proxy service is not architectural; it is just which thread you happen to be looking at.

### The bot's own residential mesh

The Android build's DDoS payload (`b4b1ace7`, the unpacked `inix` bot) sends `GET /nodes?key=meowmeowmeow` to a director on tcp/`9000`, gets back a JSON array of roughly two hundred residential IP addresses, and dials them on Jackskid's own C2 port pool. Those are C2 relay nodes, which makes this a third job for residential hardware in this cluster, after proxy exits and attack sources.

The bot finds the director on-chain. It reads the `node` text record of `burrberry[.]eth` and applies the same `0x80408454` per-octet transform Jackskid uses elsewhere, turning `2001:db8:ab9c:5da3::1` into `93.114.194[.]75`. That address already appears in this report: it is `tractor.persistfromchicago[.]com`, the peer4you relay director for the Android `lol2` module. One box, running the DDoS arm's C2 director and the proxy arm's relay director. The decompile also reverses the tier order we had assumed: `/nodes` is tried first, with the ENS `network` pool and the SNS record as fallbacks, so blocking the director buys about ten seconds before the bot falls through to the cloud pool. (One function called ahead of each tier is not fully reversed and may add a cache or anti-analysis gate; it does not change that.)

Sampling the director returned about 270 peers per snapshot, roughly half of them rotated out within ninety minutes, and 492 distinct addresses in total: CHINANET, Iran Telecom, BT, Safaricom, KT, the geography a residential-proxy catalogue advertises. These are compromised victims, so we are not publishing them as indicators; the list is held for CERT and law-enforcement sharing. The proxy arm rents such devices out; the DDoS arm routes its own control traffic through them.

The two tiers also share a delivery host, `162.249.125[.]141`, running the older tier's `inix` loader on `:2377` and the newer tier's garm scanner on `:80`, and a taste for the same corner of the address space. But the clearest evidence that one operator runs both is the funding.

## One operator

The operator did the hard part of compartmentalization well. Every attribute an analyst normally pivots on was rotated between the two Jackskid tiers and the two proxy families: the ENS and SNS names, the cipher keys, the C2 pools, the delivery domains, even the on-chain wallets that *own* the blockchain names. Pulled apart, the pieces look like a diverse threat landscape, several small operations that resemble each other only because everyone in this space [borrows from everyone else](https://krebsonsecurity.com/2016/10/source-code-for-iot-botnet-mirai-released/). None of it stays sealed for long. The DDoS scene leaks like a sieve: source gets resold, keys get copied between projects, and on-chain records are permanent by design. Compartmentalization here buys time, not secrecy.

Two things tie the tiers back together. The first is on-chain: both name-owner wallets, `0x435c…` (original tier) and `0x45c5…` (`c1s[.]su` tier), were funded from the same upstream wallet, `0xc70d…8371`, a small dedicated funder rather than an exchange or mixer. On-chain records are public and permanent, which is what makes the observation worth recording; we do not push the wallet analysis past that single link. The second is the key: `8badf00d…` is byte-identical between peer4you-mirai and the `c1s[.]su` tier, and because a config key is a one-line change, a reused one is worth noting mainly for what the builder did not bother to rotate.

Around those two anchors, the passive-DNS record agrees. A single host, `217.60.195[.]160` (SWISSNET LLC, AS209373, NL), has at various points co-hosted the `c1s[.]su` and `tvt.c1s[.]su` delivery infrastructure (Jackskid), `inhumanencounters[.]org` (peer4you), and `login.trees4sale[.]net` (trees4sale): all three families on one box. That same IP is also what the original Jackskid tier's `burrberry.eth` "node" record decoded to on 30 June, a binary-side anchor rather than a DNS one, so the box touches both Jackskid tiers and both proxy families. (That record has since rotated: by 27 July it pointed at `93.114.194[.]75`, the `/nodes` director above.) The `c1s[.]su` zone sits on the operator's recurring Cloudflare nameserver pair (`cleo` / `gabriella`), the pair we associate with the wider Jackskid/Aisuru operator cluster; `peer4you[.]net` is also on Cloudflare, on a different pair (`arushi` / `trace`). The proxy directors consolidated onto the shared node `185.104.63[.]79` (INTERKVM/ZetServers) in mid-July.

### Cluster map

```
                              one operator
  funder 0xc70d tops up both Jackskid name-owner wallets (0x435c / 0x45c5)
  shared host 217.60.195[.]160 (SWISSNET LLC) co-hosts all three families
  c1s[.]su on cleo / gabriella Cloudflare NS; peer4you[.]net on arushi / trace

     DDoS arm  ----------->  bridge (dual-use)  ----------->  proxy arm

  +----------------+      +----------------+      +----------------+
  |   jackskid     |      | peer4you-mirai |      |   trees4sale   |
  | DDoS (RCtea),  |      | Mirai + relay  |      |  relay only,   |
  | 2 tiers, both  |      | (the bridge)   |      | no attack code |
  | carrying relay |      |                |      |                |
  +----------------+      +----------------+      +----------------+

  ties
  - jackskid c1s[.]su tier <-> peer4you-mirai: byte-identical 8badf00d key,
    .ffaaxx loader, shared www.c1s[.]su pool
  - peer4you-mirai <-> trees4sale: same peer4you relay code, peer4you[.]net,
    shared node 185.104.63[.]79
  - jackskid tier B ELF compiles the peer4you relay in: UPnP AddPortMapping
    RELAY + SSDP + /heartbeat (verified 06c4ddab / 01d5fba3)
  - jackskid tier A shipped the relay as a second Android payload (lol2,
    07-23 build only; dropped again on 07-27)
  - jackskid tier A /nodes C2 director = 93.114.194[.]75 =
    tractor.persistfromchicago[.]com, the lol2 relay director
```

Every cluster like this eventually reaches [the red-string-and-corkboard stage](https://knowyourmeme.com/memes/pepe-silvia); we are aware of how the board looks.

### Attribute-by-family comparison

The same split, attribute by attribute. The cells that repeat give it away: the `8badf00d` key, the peer4you relay code, and the `0xc70d` funder.

| Attribute | Jackskid Tier A | Jackskid Tier B | peer4you-mirai | trees4sale |
|---|---|---|---|---|
| Role | DDoS botnet | DDoS botnet (now embeds relay) | Mirai DDoS + proxy relay (bridge) | proxy relay only |
| Config cipher | RCtea; keys `DEADBEEF` / `08453CD1` / ARX | RCtea; key `8badf00d…` | RCtea; key `8badf00d…` (= Tier B) | none (plaintext) |
| C2 resolution | ENS `node` → `/nodes` director (primary), then ENS + SNS dead-drops | ENS + SNS dead-drops, plus DNS | DNS (A record) | plaintext domains in binary |
| ENS / SNS dead-drops | `ukranianhorseriding[.]eth`, `burrberry[.]eth`; `24carnforth2merseyside[.]sol` | `meower[.]eth`; `roanoke[.]sol`, `telnet[.]sol` | n/a | n/a |
| C2 / director domains (DNS) | n/a | `c1s[.]su` (`www.`/`sc.`/`tvt.`), `nvms9000[.]online` | `www.c1s[.]su`, `i.`/`o.peer4you[.]net`, `inhumanencounters[.]org` | `trees4sale[.]net`, `peer4you[.]net` |
| C2 hosting | Akamai / Tencent / Alibaba pool | `c1s[.]su` pool (1337 Services / Akamai) | same `c1s[.]su` pool | `185.104.63[.]79` |
| Wire crypto | v3 78-byte plaintext frames | v3 78-byte plaintext frames | X25519 + ChaCha20 + HMAC-SHA256 | telemetry to director |
| Loader / spread | `inix` campaigns | `.ffaaxx` echo-drop + garm telnet scanner; TVT/NVMS9000 DVR | `.ffaaxx` echo-drop + telnet scanner (TJ2100N GPON) | none (relay only) |
| Attack engine | Jackskid v3 (opcodes 0-19) | Jackskid v3 (opcodes 0-19) | Mirai TLV (16 vectors) | none |
| Proxy relay | peer4you relay as a second Android payload (`lol2`; 07-23 build only, dropped 07-27) | peer4you relay compiled into the ELF | peer4you relay (UPnP `RELAY` + `ONLINE`) | peer4you relay (UPnP `RELAY` + `ONLINE`) |
| Name-owner wallet | `0x435c…` | `0x45c5…` | n/a | n/a |
| Funder wallet | `0xc70d…` | `0xc70d…` | n/a | n/a |

### Chronology (passive DNS + on-chain)

| Date (UTC) | Event |
|---|---|
| 2011–2017 | `trees4sale[.]net` lives at AT&T, then Amazon/DigitalOcean, then parks on Confluence Networks (an aged domain, years before the botnet) |
| 2026-03 | Aisuru cluster (including Jackskid) disrupted by law enforcement |
| 2026-05-15 | `trees4sale[.]net` operationalized (Namecheap) |
| 2026-06-13 | `c1s[.]su` apex goes live on INTERKVM, later moving to `217.60.195[.]160` (SWISSNET LLC, AS209373) |
| 2026-06-28 | earliest trees4sale builds compiled (arm5 / arm7) |
| 2026-06-30 | the original Jackskid tier's `burrberry.eth` "node" record decodes to `217.60.195[.]160`, the same box hosting `c1s[.]su` |
| 2026-07-04 | `inhumanencounters[.]org` (peer4you) appears on `217.60.195[.]160` |
| 2026-07-10 | `peer4you[.]net` live: `i.peer4you[.]net` on `45.138.16[.]96`, `o.peer4you[.]net` on Akamai exits |
| 2026-07-13 → 07-15 | proxy directors consolidate onto the shared node `185.104.63[.]79` |
| 2026-07-17 | Jackskid `c1s[.]su` tier's on-chain build-out: wallet `0x45c5` + `meower.eth` + two Solana names, all in one day |
| 2026-07-23 | a Jackskid Android APK (`com.android.s4protect`) ships the peer4you relay (`lol2`) beside its DDoS bot; new relay director `persistfromchicago[.]com` |
| 2026-07-27 | the Android line reverts to a single payload: `com.android.wall.color.cinnamon` (`695ab309…`) drops `lol2`, DDoS binary unchanged since 07-20 |
| 2026-07-27 | detonation of that DDoS payload (`b4b1ace7`) exposes the `/nodes` director tier and its residential C2 mesh; `burrberry.eth[node]` now decodes to `93.114.194[.]75` (= `tractor.persistfromchicago[.]com`) |

### Confidence

| Link | Evidence | Confidence |
|---|---|---|
| Jackskid `c1s[.]su` tier ↔ peer4you-mirai | Byte-identical `8badf00d` RCtea key (S-box reproduced exactly), shared `.ffaaxx` loader, shared `www.c1s[.]su` C2 pool | High |
| Jackskid original tier ↔ `c1s[.]su` tier | One operator, compartmentalized: shared funder wallet `0xc70d`, shared delivery host `162.249.125[.]141`, common RCtea construction | High (one operator) |
| peer4you-mirai ↔ trees4sale | Same peer4you relay code (UPnP `RELAY` + `ONLINE` telemetry), shared `peer4you[.]net`, co-hosted on `185.104.63[.]79` | High |
| Both Jackskid tiers have carried the peer4you relay | Tier B: UPnP `AddPortMapping` `RELAY` + SSDP IGD + `/heartbeat` compiled into ELF `06c4ddab`/`01d5fba3`. Tier A: the `lol2` module in the 07-23 Android build, whose DDoS payload resolves through Tier A dead-drops | High |
| Jackskid Tier A ↔ peer4you (infrastructure) | `burrberry.eth[node]` decodes to `93.114.194[.]75`, which is also `tractor.persistfromchicago[.]com`, the `lol2` relay director; verified by detonation | High |
| Jackskid ↔ trees4sale | Now share the peer4you relay code (Jackskid's Tier B ELFs compile it in and its Android build shipped it for one build; trees4sale is built on it), plus hosting (AS25198 INTERKVM) and the cross-tenant `tractor.trees4sale[.]net` → Jackskid delivery host | High (upgraded from transitive) |
| single operator | `c1s[.]su` on the Cloudflare `cleo`/`gabriella` nameserver pair, plus the shared crypto, loader, and hosting above | Observation |

## What this means

The interesting part of this cluster is not that it does both DDoS and residential proxying. Plenty of families do; we have documented dual-purpose botnets before, and the convergence of the two markets is by now a well-worn observation. What is interesting is the *shape* the operator chose.

The operator productized the two functions: a DDoS family, a pure-proxy family with the attack code deliberately removed, and a bridge build that does both, each with its own names, infrastructure, and branding but one back office behind them. That is a business decision more than an engineering one, and it lets the proxy side show a clean face to its customers while the DDoS operation carries the risk. The most recent builds complicate that separation, though unevenly. On Linux the relay is compiled straight into the Tier B DDoS bots and has stayed there. On Android it shipped as a second payload for exactly one build before being dropped again four days later, which reads more like an experiment than a direction. And the DDoS bot's own control traffic now runs over a mesh of residential victims, fronted by the same box that directs the proxy relay. The marketing stayed separate; the code keeps leaking across.

The operator also chose to expose the residential exit rather than hide it, which is the distinctive part and, for them, the costly one. The UPnP `RELAY` mechanism trades a quiet tunnel for a loud, self-labelling footprint a defender can catch on the router, on the LAN, and from outside. The scalability gain is a detection surface.

And for all the effort to look like a varied threat landscape, the cluster comes back to one operator on two things that cannot be unshipped: a funding wallet already written to the public ledger and a config key already compiled into binaries in the wild.

For defenders, the practical takeaways are short:

- **Watch the router.** IGD port-mappings described `RELAY`, and bursts of SOAP `AddPortMapping` following SSDP `M-SEARCH` from an end host, are high-fidelity indicators of these proxy nodes, observable on the LAN without touching the malware.
- **Block the directors, but know what that buys.** The peer4you and trees4sale director and loader hosts (below) are shared across both proxy families; blocking them degrades both. The DDoS side is not the same: its `/nodes` director is one of three resolution paths, and denying it alone just moves the bot to its cloud C2 pool within about ten seconds. That tier has to be cut at all three paths at once.
- **Treat flooding and proxying as one population.** The same device does both in the Tier B Linux builds, so a host flagged for DDoS is a candidate open proxy, and the reverse; clearing one function does not remove the other. A residential host being dialed by a Jackskid bot may also be neither target nor exit, but a C2 relay.

## Provenance and attribution

This analysis rests on reverse engineering of the malware, cryptographic comparison of config ciphers, public passive-DNS history, and read-only public-blockchain records (ENS and SNS registrations and Ethereum wallet funding are open ledgers). The `/nodes` findings additionally rest on a controlled detonation of the Android build's DDoS payload, run in an isolated environment with egress sinkholed so that no attack traffic left the sandbox, and on paced direct queries to the director. An anonymous tip in July 2026 pointed us at a Jackskid i386 sample and at infrastructure we were already tracking. Consistent with our attribution practice, we attribute on code, cryptography, and infrastructure, not on operator-identity claims from third parties; the on-chain wallets named here are addresses, not identities.

## Indicators of compromise

Full machine-readable indicators are published alongside this report:

- [trees4sale IoCs](../trees4sale/iocs): domains, IPs, sample hashes
- [peer4you-mirai IoCs](../peer4you-mirai/iocs): domains, IPs, sample hashes, keys
- [Jackskid IoCs](../jackskid/iocs): domains, IPs, sample hashes, keys

### Key network indicators

| Indicator | Role |
|---|---|
| IGD `AddPortMapping` description `RELAY` | Proxy-relay signature common to all carriers (both proxy families + Jackskid's embedded relay) |
| `{"status":"ONLINE",...}` JSON to tcp/`9000` or `18702` | Relay telemetry, standalone proxy families (trees4sale / peer4you-mirai) |
| `POST /heartbeat` (`connections=&bandwidth=`) to localhost | Relay telemetry, Jackskid-embedded relay (Tier B ELF + `lol2`); host-local, no network beacon |
| `login.trees4sale[.]net` → `185.104.63[.]79` | trees4sale director (`:18702` / `:9000`) |
| `38.87.116[.]165` | Second trees4sale director (`:18702`/`:9000`/`:8081`/`:80`/`:443` all open) |
| `www.trees4sale[.]net` → `76.164.203[.]165` | trees4sale loader (Apache open-dir) |
| `i.peer4you[.]net` → `185.104.63[.]79` (was `45.138.16[.]96`) | peer4you director; `:9000` API + "Peer Server" panel (`:8080`) on `45.138.16[.]96` now dark |
| `o.peer4you[.]net` | peer4you datacenter pool (Akamai/Linode) |
| `www.c1s[.]su` | peer4you-mirai / Jackskid `c1s[.]su` tier C2 pool |
| `inhumanencounters[.]org` (`boblazar`/`roswell`/`cocoa`) | peer4you HTTP report/loader endpoints |
| `217.60.195[.]160` | Shared host (SWISSNET LLC, AS209373) co-hosting all three families |
| `185.104.63[.]79` | Shared node: peer4you backconnect + trees4sale director |
| `meower[.]eth` / `ukranianhorseriding[.]eth` / `burrberry[.]eth` | Jackskid ENS C2 resolution |
| `persistfromchicago[.]com` (`n1.` / `tractor.`) | peer4you relay director for the Jackskid Android build (`lol2`) |
| `162.35.179[.]210` | `n1.persistfromchicago[.]com`, relay node-assignment |
| `93.114.194[.]75` | `tractor.persistfromchicago[.]com`: relay management, and Jackskid's `/nodes` C2 director on tcp/`9000` |
| `GET /nodes?key=meowmeowmeow` to tcp/`9000` | Jackskid director fetch returning the residential C2 relay mesh (peers are victims; not published as indicators) |
| `burrberry[.]eth` text `node` → `0x80408454` | On-chain derivation of the `/nodes` director IP |
| `com.android.s4protect` (APK `1a9a54eb…`) | Jackskid Android dual-payload build carrying DDoS bot + peer4you relay (07-23) |
| `com.android.wall.color.cinnamon` (APK `695ab309…`) | 07-27 rotation: same DDoS payload, relay dropped, package renamed |

### Key cryptographic indicator

| Value | Purpose |
|---|---|
| `8badf00d feedface abad1dea c001d00d` | RCtea config key, byte-identical across peer4you-mirai and Jackskid's `c1s[.]su` tier |

## References and related reporting

- Nokia Deepfield ERT, [Shared code, shared secrets: tracing four DDoS botnets to one ecosystem](2026-03-20-aisuru-ecosystem.md) (2026). The Aisuru/Jackskid RC4+LCG lineage this cluster extends.
- Nokia Deepfield ERT and Comcast, [Reverse-engineering Jackskid](../jackskid/report.md). Prior Jackskid analysis.
- Foresiet, [Mirai Botnet Jackskid Resurgence](https://foresiet.com/blog/mirai-botnet-jackskid-resurgence-nov-2025-iot-threats/) (Nov 2025). First public documentation of the Jackskid family.
- CNCERT / SecRSS, [RCtea botnet risk advisory](https://www.secrss.com/articles/87776) (Feb 2026). Jackskid documented as "RCtea".

## Edit history

- **2026-07-27:** Corrections and additions following reverse engineering of the Android build's DDoS payload (`b4b1ace7`) and a controlled detonation of it.
  1. The 07-23 Android dual-payload build (`1a9a54eb`) was attributed to Jackskid's Tier B, with Tier A recorded as carrying no proxy relay. Its DDoS payload resolves C2 through `burrberry[.]eth`, `ukranianhorseriding[.]eth`, and `24carnforth2merseyside[.]sol`, which makes it a Tier A build. Both tiers have therefore carried the peer4you relay. Corrected in the comparison table, the cluster map, and the confidence table.
  2. The Android dual-payload design was reverted. On 27 July the delivery node served `com.android.wall.color.cinnamon` (`695ab309…`), which drops the `lol2` relay and returns to a single payload; the DDoS binary is byte-identical to the 07-20 build. The original text described the DDoS and proxy code as converging in "the newest builds"; that holds for the Tier B Linux ELFs, which still compile the relay in, but on Android the dual-payload design lasted one build. Tempered in "The DDoS arm that stocks the shelves" and "What this means".
  3. Added "The bot's own residential mesh": the `GET /nodes?key=meowmeowmeow` director tier, its rotating mesh of compromised residential devices used as C2 relays, and the dual role of `93.114.194[.]75` as both the `lol2` relay director and Jackskid's `/nodes` C2 director. The `/nodes` tier is resolved first, ahead of the ENS and SNS dead-drops, which changes the "block the directors" advice for the DDoS side.
  4. `burrberry.eth`'s `node` record no longer decodes to `217.60.195[.]160`; it rotated to `93.114.194[.]75`. Fixed the tense in "One operator".

## Feedback

We welcome corrections, additional IoCs, and other feedback. Reach us on Mastodon at [@deepfield@infosec.exchange](https://infosec.exchange/@deepfield/).
