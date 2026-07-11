# Open sesame: inside MoYu's "zhima" proxy and the TV it runs on

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-07-11**

---

## Summary

Somewhere a cheap Android TV box is running `tigertv`, a free IPTV app someone sideloaded to get the channels they would otherwise pay for. It is also, at that moment, moonlighting: taking tunnel requests from strangers and connecting out to whatever address they name, on the household's own IP, at whatever hour the work comes in. Nobody sold them a botnet. They installed a way to skip the cable bill.

This is a walk through how that happens, on one specific and currently live example. The `tigertv` apps and their siblings are grey-market Android-TV IPTV players: VLC under the hood, a channel list, some banner ads. We found them acting as a delivery vehicle for MoYu, the group [HUMAN](https://www.humansecurity.com/learn/blog/satori-threat-intelligence-disruption-badbox-2-0/) associates with the IpMoYu residential-proxy service in the BADBOX 2.0 operation. (HUMAN identifies four groups involved in BADBOX 2.0 and describes evidence of collaboration and overlap. It says the backdoor gives MoYu persistent privileged access, including residential-proxy node creation. The proxy is the part we follow here; it is not the whole of BADBOX 2.0, or even the whole of MoYu.) What makes it interesting is that the APKs we analyzed contain no payload code. The malicious code arrives later, over the network, only after the app has phoned a server and asked for it.

We reverse-engineered the clean vehicle, the staged server-gated direct path to the residential-proxy module that the operator's own config names `zhima`, and a first-stage loader the vehicle also drops. Two builds of that module show a real weakness getting a partial fix: done on one path, skipped on the others. The analysis is static and dynamic: jadx decompilation of the vehicle APK and of the sh65 and sh66 modules, the module descriptor recovered from the live plaintext C2 channel, a sandbox detonation of the vehicle to capture its first-stage loader, and infrastructure enumerated through passive DNS and direct probing; we did not proxy third-party traffic or run the exit node. What follows is the tour.

BADBOX 2.0 is not under-reported. It is, if anything, hard to see whole: four collaborating groups, shared and rotating infrastructure, several fraud schemes running at once, and a scatter of adjacent Android proxy botnets it overlaps but does not cleanly map to. That is the honest reason we go narrow rather than wide. HUMAN's Satori team and the [FBI's June 2025 advisory](https://www.ic3.gov/PSA/2025/PSA250605) document BADBOX 2.0; [Bitsight](https://www.bitsight.com/blog/badbox-botnet-back) documented the resurgent BADBOX infrastructure that preceded it; [WhoisXML/CircleID](https://circleid.com/posts/unlocking-the-dns-strongbox-of-badbox-2.0) analyzed HUMAN's published corpus of 109 C2 domains; and Palo Alto's [Unit 42](https://github.com/PaloAltoNetworks/Unit42-timely-threat-intel/blob/main/2026-04-13-LORIKAZZ-ANDROID-IOT.txt) has flagged the `tigertv` APK itself as a suspected piracy-IPTV vector. So this is not another attempt to draw the whole map. It is one thread pulled end to end: a command-and-control rotation we caught in subscriber traffic that matched none of those published indicators, the delivery chain that arms the clean vehicle, and a method-level teardown of the residential-proxy module at the end of that chain, with a before-and-after of the operator patching it between builds. We found no prior public analysis of that module.

## Why a DDoS team is documenting an IPTV app

Nokia Deepfield ERT tracks DDoS botnets, not IPTV apps, and a grey-market streaming player would normally be outside our scope. It is here because the residential-proxy engine it delivers belongs to the same market that supplies the DDoS families we track, a connection we set out in full in our [RoboVPN / Neunative](../reports/2026-06-18-robovpn-neunative.md) report and will not repeat. Two points are particular to MoYu. The proxy is not something the user opts into: they install a way to watch free channels, and the exit node arrives afterward. And the monetization is concrete: HUMAN observed MoYu selling this access at $13.64 per 5 GB routed, sourced from the home connections of infected devices. It is an oddly exact sticker price for other people's bandwidth. The device-level exposure this creates, a proxy customer reaching into the network the exit node itself sits on, we take up in [the patch section](#watching-moyu-patch-build-65-to-66).

## Where this started

This did not begin with a malware sample. It began in traffic. A botnet DNS hunt across networks we protect flagged subscriber devices beaconing to a control rotation we subsequently attributed to BADBOX 2.0 / MoYu, and pivoting through passive DNS on Zenlayer-hosted IPs (AS21859) surfaced roughly two dozen client-pull domains that, at the time, matched no published BADBOX indicator list. We selected them by the subdomains that actually resolved to those IPs, not by scraping a broad communicating-files field; the less glamorous method is, inconveniently, the one that supports the attribution. The names were new; the IPs were not. The same Zenlayer boxes already carried published BADBOX apexes, `ad3g[.]com`, `moyu88[.]xyz`, and `ziyemy[.]shop`, all in the HUMAN/WhoisXML corpus, and that shared, dedicated C2 anchors the rotation as a whole, even where an individual new name is not separately confirmed. Only then did we look at what those domains were talking to: a communicating file on one of them, `edisajalsjfdfh[.]shop`, turned out to be the tigertv APK, and that is where the television enters the story.

## The vehicle

The apps are `com.android.tigertv`, `com.android.tigersport`, `com.android.mioplus`, `com.android.miosport`, `com.android.vo_vivo`, and `com.android.vo_fixture`. They are the kind of software you sideload onto a cheap Android TV box because a forum post promised you every channel [for free](https://en.wikipedia.org/wiki/There_ain%27t_no_such_thing_as_a_free_lunch). We reversed them from `8226f445…` and three sibling builds. That hash is already on the record: Palo Alto's Unit 42 flagged it as a suspected piracy-IPTV infection vector in their Lorikazz work, a Tor-based proxy botnet that overlaps Kimwolf/AISURU, and noted no known payload inside the APK. We looked at the same file from a different angle. We make no claim that Lorikazz and MoYu are one operator; we traced the delivery path this APK runs, and it leads to MoYu's zhima.

Static inspection of the APKs found no BADBOX strings, C2 URLs, or embedded second-stage loader. The only dynamic class-loading we identified was within Huawei Mobile Services. A scanner that sees only those APKs reaches the correct conclusion: it has found a slightly junky IPTV app. The payload arrives later.

This is not sloppiness on the attacker's part. It is the design. A clean APK can evade static analysis in a sideload bundle, while the server retains a kill switch: the payload is fetched only for devices the server chooses to arm. The cost is one network round trip at startup, which nobody watching a channel guide is going to notice.

## The clean-vehicle model

So where does the malware come from? The app fetches it. The observed direct route is staged and server-gated, which is a fancy way of saying the app never carries the incriminating part and asks permission before each escalation.

```
  clean IPTV APK
        │  1. getDomainList  (signed JSON POST to seed servers)
        ▼
  rotating pool of IPTV/CMS cover hosts
        │  2. BADBOX a1./t1. config request
        ▼
  cpc module descriptor  (plaintext JSON: url2, md5, class, params)
        │  3. fetch JAR from loader host, md5-verify, DexClassLoad
        ▼
  com.miyc.transfer.Client  ("zhima" residential-proxy engine)
        │  4. dial operator relay, become an exit node
        ▼
  your TV is now for rent
```

### getDomainList: the bootstrap

At startup the app makes a signed JSON POST to a small set of seed servers, asking for the current list of live hosts. The signature is a home-rolled scheme: an AES-CBC token keyed off an MD5 of the device UID, the timestamp, and a hardcoded salt, rendered as uppercase hex. It is not cryptographically interesting so much as it is a [shibboleth](https://en.wikipedia.org/wiki/Shibboleth), a way for the server to ignore anyone who is not a real client, us included, until we reimplemented it.

The seeds hardcoded in the APK we analyzed are `newsvxc.shopstoreboutique[.]com`, `appdload.mpfcms[.]com`, and `mpfcms.mio-tvplus[.]com` on port 2052, plus `miotvtop.hdwcam[.]com`, `testcf114.bookabcgames[.]com`, and `mtvp.hdwcam[.]com` on port 8080. When we ran the request live on 2026-07-09 the pool answered with more than it started with, handing back rotated-in hosts such as `tigertvdli1.jopstop[.]com`, `xc.mpfcms[.]com`, and `mcm5566.bookabcgames[.]com` that appear nowhere in the APK. The indirection makes the pool durable: retire a host, publish a replacement, and installed clients collect it at their next launch. No rebuild is required, which is the sort of operational convenience malware authors tend to appreciate.

These are cover domains, dressed up as IPTV portals and CMS backends, and the distinction matters for triage. The registrable domain is often shared: the same name can carry an IPTV portal on its apex and a BADBOX C2 on an `a1.`/`t1.` subdomain, as `edisajalsjfdfh[.]shop` did.

- In our passive-DNS review, the cover/apex hosts were generally separate bulk-registered infrastructure, not observed on the C2 IPs. An apex match alone does not attribute BADBOX activity; it is consistent with a device merely having the app installed.
- The `a1.`/`t1.` client-pull FQDN is the discriminating indicator: it resolved to the operator's dedicated C2 boxes. A hit shows a device reached the payload-config stage, though not by itself that a payload downloaded or ran.

### The BADBOX config channel

Once bootstrapped, the app reaches the BADBOX `a1.`/`t1.` command-and-control nodes for its real marching orders. There are two channels. One is encrypted; the other makes this part of the investigation a reading assignment.

The `a1. /api/init?…&rsa=1` channel returns an RSA-encrypted config, a 512-byte blob we captured but did not decrypt (the decryption key material lives in a stage we could not fetch; see the coverage note below). The `t1. /cpc/api/xml?productId=…` channel, on the other hand, returns plaintext JSON. This is a runtime-module descriptor, and because it is unencrypted, we recovered the entire thing without ever touching the client-side crypto. The live descriptor for the current campaign reads, in part:

```json
{
  "loadType": 1, "method": "start",
  "url2": "http://144.217.243[.]201/vr34der34/sh65.io",
  "md52": "de77c3303e93c9450424759f1741441c",
  "name": "zhima", "className": "com.miyc.transfer.Client",
  "params": [ {"type":"Context"}, {"type":"String","value":"165.154.202[.]29"},
              {"type":"String","value":"1002"}, {"type":"int","value":9999},
              {"type":"int","value":7777} ]
}
```

The app downloads the JAR at `url2`, verifies it against `md52`, loads it with a `DexClassLoader`, and calls `com.miyc.transfer.Client.start(…)` with the relay address and ports from `params`. The `name` field, `zhima`, is the operator's own label for what comes next.

### host.dex: the first stage

The direct descriptor is the runtime story. We also observed a first-stage loader: when we detonated the vehicle, it wrote `files/Download/host.dex`, a JAR in package `com.xgw.f` (sha256 `ccce124a…`) dated June 2025. host.dex is a bootstrapper. It fetches a `dex_api.txt` descriptor from a set of rotating loader domains (or an Alibaba OSS bucket as fallback), pulls down a `sdk.jar` as a lightly-obfuscated XOR stream, decodes it to the app's files directory, class-loads it, and calls into it. It also pings `task.mymoyu[.]shop/cpc/api/client/active`, and three things place this first stage in the same cluster. The name carries "moyu" (HUMAN's MoYu Group). The `/cpc/api/` endpoint is the same channel family as the live cpc descriptor we recovered. And passive DNS puts `task.mymoyu[.]shop` on `128.14.207[.]14` and `128.14.202[.]210` through 2024-2025, the same Zenlayer boxes that served our `t1` C2. (Its registrable domain `mymoyu[.]shop` is in HUMAN's published BADBOX 2.0 corpus, and ThreatFox separately classifies it as a botnet C2 tagged to XLab's [Vo1d](https://blog.xlab.qianxin.com/long-live-the-vo1d_botnet/) research, one of the overlapping labels noted earlier.)

These observations show two related routes, not one fully observed linear chain:

> **Direct route observed:** vehicle APK → `getDomainList` → `t1` cpc descriptor → `com.miyc.transfer` (the zhima proxy)
>
> **Loader route observed through host.dex:** vehicle APK → host.dex (`com.xgw.f`) → `sdk.jar` (interface `frh`, entry `xrb()`; referenced but not retrieved)

The `sdk.jar` continuation is unresolved. Its loader domains are dead (NXDOMAIN as of our checks), so we describe that stage from host.dex's references, not its own bytes, and cannot independently verify its contents or claim that it delivered zhima. We do have the zhima module in full through the live `t1` descriptor path, and that is the part that repays reading.

## Open sesame: inside the zhima exit node

The dropped module calls itself `zhima` (`芝麻`, Chinese for sesame), the operator's own label, and it is the final boss of the whole staged sequence: everything upstream exists to deliver it, from the clean app through the bootstrap, the config channel, and the loader. We kept the name in the title for one reason only: it is grimly literal. The module's whole job is to [open a door](https://en.wikipedia.org/wiki/Ali_Baba_and_the_Forty_Thieves) into the network it runs on for whatever stranger the relay sends its way.

Mechanically, `com.miyc.transfer` (sha256 `84d16756…`) is a multi-tier SOCKS5/HTTP residential-proxy exit node. The shape is deliberate, and it is why these nodes are hard to see: the infected TV always dials out. It opens the connection to the operator's relay; the paying customer only ever talks to the relay; the TV then connects onward to the real target and shuttles bytes in both directions. There is no externally reachable listening port on the television for a scanner to find. From the outside it looks like a TV making outbound connections, which is the least suspicious thing a TV can do.

### Logical roles and ports

Time flows downward. `═══` is bulk proxied traffic; `───` is control and framing.

```
   CUSTOMER                 OPERATOR RELAY                 INFECTED TV
  (proxy buyer)          165.154.202[.]29               com.miyc.transfer
       │                        │                              │
       │                        │      1. REGISTRATION         │
       │                        │◀──────── TCP :9999 ──────────┤  dials out, sends
       │                        │◀── [type][build][len][uid] ──┤  register frame
       │                        │                              │
       │                        │   2. CONTROL PLANE (:9999)   │
       │                        │──── job / lease / exit ─────▶│  reads 1 opcode byte
       │                        │◀───────── heartbeat ─────────┤  every N ms
       │      3. AUTH           │                              │
       ├── proxy user / pass ──▶│  checked at the relay,       │
       │                        │  never on the TV             │
       │                        │  4. DATA PLANE (per session) │
       │                        │◀──── TCP :7777 (+ :5555) ────┤  worker dials out
       │                        │═ SOCKS5 / HTTP CONNECT req ═▶│  no auth on this leg
       │                        │                              ├──▶  REAL TARGET
       │◀════════ customer traffic, tunnelled both ways ═══════┤
       │                        │                              │

   on-device, loopback only (never exposed to the relay):
      IPC coordinator   127.0.0.1:10121   one engine per device; build self-replacement
      helper RPC        127.0.0.1:12101   uid resolve, DNS, debug flag
```

Three ports face the relay: `:9999` carries registration and the control plane, `:7777` carries the bulk data plane, and `:5555` is a per-job bridge for heavier sessions. Two more, `:10121` and `:12101`, bind to loopback only and coordinate the engine with itself and with the host app. No service binds an externally reachable local interface.

### The control plane

On startup a persistent thread dials the relay's `:9999` and sends a registration frame: a one-byte type, the four-byte build number, a length, and the device UID. Then it settles into a loop, reading a single opcode byte at a time and acting on it, and emitting a heartbeat on a timer so the relay knows the node is alive (go quiet for a few intervals and it reconnects). The opcodes are a small table: set a lease duration, start a new proxy job (four flavors, differing mostly in whether a dedicated `:5555` bridge gets spun up), tear down, and a couple of keepalive markers. It is legible rather than obfuscated at this layer, which, for defenders, is a small mercy.

### The data plane, and the part where your TV says yes

Each proxy job opens a fresh outbound connection to the relay's `:7777`, writes a session id, and then wraps the pipe in either a SOCKS5 or an HTTP CONNECT handler depending on the job type. Both are complete implementations, with connection pooling, non-blocking IO, backpressure, and idle-session reaping, and that matters for one reason: it is built to carry real traffic at volume, so the threat to a victim's connection is not incidental.

The detail that matters most is that the SOCKS5 and HTTP handlers on the TV perform no authentication. They start straight in the command state and service whatever comes down the pipe. Customer authentication happens upstream, at the relay, before the traffic is ever handed to the exit node. From the device's point of view, anything that reaches it over the relay-bridged connection is already trusted and gets served. The television is not deciding who to work for. It said yes when it loaded the JAR.

### String obfuscation

Every string literal in the module is run through a per-character Caesar shift (subtract a per-string key), which is the cryptographic equivalent of a "Beware of Dog" sign on an unlocked gate. It stops `strings` and slows a first read; [it stops nothing else](https://en.wikipedia.org/wiki/ROT13). `a.a("FGDWI", 2)` is `DEBUG`; `a.a("wkf", 2)` is `uid`; `a.a("45:131314", 3)` is `127.0.0.1`. Once you spot the helper, the whole module decodes on sight.

## Watching MoYu patch: build 65 to 66

The module carries exactly one target filter, a host blocklist that is checked before name resolution, on the requested host string, on every proxied request. Its evident purpose is not to protect the internet; it is to stop paying customers from turning the exit node around and rummaging through the *device's own* local network. It blocks the obvious literals (`127.0.0.1`, `localhost`, `::1`, `0.0.0.0`), `*.local`, and the RFC 1918 private ranges by string prefix.

As a security control it is weak, in ways that are structural rather than incidental: it matches host strings rather than resolved addresses, it checks no ports, and its list of what counts as "internal" is incomplete in categories that matter, including cloud metadata endpoints, carrier-grade NAT space, and several IPv6 internal ranges. We are describing the *class* of weakness here on purpose. These are live nodes carrying real traffic, and a copy-paste bypass would do nothing for defenders except widen the blast radius, so the weaponizable specifics stay out of this report. The defensive takeaway is sufficient on its own: the filter cannot be treated as a reliable local-network boundary. We do not rely on nonstandard numeric IPv4 encodings in this assessment: Android's modern [`InetAddresses`](https://developer.android.com/reference/android/net/InetAddresses) API documents only four-part decimal IPv4 as numeric, while parser behavior can vary by API and OS version.

This concern is not hypothetical as a class, but the end-to-end demonstration is from a different botnet. In January 2026 [Synthient documented](https://synthient.com/blog/a-broken-system-fueling-botnets) Kimwolf, which it assesses as the Android variant of Aisuru (a separate family from MoYu). The report assesses Kimwolf's infected-device population at more than two million, observed a hostname resolving to `0.0.0.0` in traffic from an IPIDEA proxy network, and advised proxy providers to block high-risk ports and restrict access to the local network. That establishes the risk posed when a proxy provider evaluates only a requested hostname; it does not establish a shared operator or an end-to-end compromise against MoYu.

By static analysis, zhima has the same control-design concern. This is a design finding, not an exploitation claim: we did not run a MoYu exit node or attempt end-to-end validation.

The sh65-to-sh66 diff is almost entirely a targeted but incomplete fix to this filter. In sh66 the operator added an off-thread resolver to the `SOCKS5 TCP` path that re-checks the blocklist against the *resolved* address before connecting. `HTTP CONNECT` and `UDP` do not get the same check. The gap is not academic: the highest-impact local-network target, the exit device's own ADB daemon on TCP `:5555`, needs only a TCP tunnel to reach, and HTTP CONNECT supplies one to any port (the filter checks none), so sh66's resolved-address re-check never runs on the route that matters most. The patch is real; its coverage is merely selective.

The blocklist's contents were not touched, so every category it failed to cover in sh65 it still fails to cover in sh66, on every path. No authentication was added to the exit leg. No TLS, no rate limiting, no logging of targets. The remaining observed differences are the version integer, a re-keyed obfuscation pass, and a rename of internal packages.

There is also a self-replacement mechanism, unchanged across both builds: the loopback IPC coordinator lets a *newer* build tell a running *older* build to shut down and [hand over](https://en.wikipedia.org/wiki/Highlander_%28film%29). A pushed update can therefore retire its predecessor on-device with no user-visible event, which is convenient for the operator and less so for anyone trying to preserve evidence.

Read together, sh65 and sh66 show a maintained codebase: a weakness spotted, a fix attempted, left unfinished. sh66 is the newest build we pulled; for defenders, the takeaway is not to treat any one build as final.

## Live infrastructure

As of 2026-07-11, the campaign endpoints below were live. The operator rotates both the FQDN labels and the Zenlayer IPs behind them, all within AS21859: the `a1.`/`t1.` names moved off the `128.14.x` boxes to fresh addresses in the same network, while the older boxes stayed reachable.

| Host | Role | Notes |
|------|------|-------|
| `172.96.114[.]6` | BADBOX `a1` config node (current) | resolves `a1.{ishano456,xmsae,xshaon123}[.]sbs` |
| `98.98.71[.]19`, `98.98.71[.]20` | BADBOX `t1` cpc/proxy nodes (current) | resolve `t1.*[.]sbs`; serve the module descriptor |
| `128.14.207[.]34` | prior `a1` node | fronted `a1.*[.]sbs`; still reachable |
| `128.14.207[.]14`, `128.14.202[.]210` | prior `t1` nodes | fronted `t1.*[.]sbs`; served the descriptor at first capture; still reachable |
| `128.14.181[.]46`, `128.14.210[.]58` | additional BADBOX C2 (passive DNS) | Zenlayer AS21859; not in the analyzed bin's cpc descriptor |
| `144.217.243[.]201` | module loader | OVH; `/vr34der34/{sh65.io, sh66.io}` |
| `165.154.202[.]29` | residential-proxy relay | Scloud Pte Ltd (AS142002); `:9999` control, `:5555` per-job, `:7777` data |

The observed BADBOX C2 IPs are assigned to Zenlayer (AS21859). As of the July checks, the module loader exposed sh60, sh61, sh63, sh65, and sh66; sh67 and above returned 404. The rollout was staged by product id, with most observed ids still pointed at sh65 and a couple moved to sh66.

At the time we observed them, we did not find the `a1.`/`t1.` names on the Zenlayer boxes above, or the first-stage-loader domains `ty4523[.]space`, `ty54fgd435[.]my`, `vrr8345[.]site`, and `ue886578433[.]online`, in the public indicator lists we reviewed. They were surfaced through passive DNS on the shared C2 boxes, not lifted from an existing list. The loader path `/vr34der34/`, and names like `ty54fgd435[.]my` and `ishano456[.]sbs`, share one design goal, and it was not memorability.
We run an observation-only monitor against the `getDomainList` and update channels that diffs the rotation pool, alerts on change, and verifies and pulls pushed modules by hash; it is how we track the staged sh65-to-sh66 rollout.

## What we covered, and what we didn't

In the interest of not overclaiming:

- Covered in full: the vehicle APK; the zhima module at builds sh65 and sh66, class by class; the plaintext cpc descriptor from the live C2; the host.dex first-stage loader, captured by detonation; and the live infrastructure, enumerated by passive DNS and direct probing.
- Captured but not decrypted: the `a1. /api/init` RSA config. We have the 512-byte blob; the decryption key material is not in anything we hold, and the app-side key material sits in a stage we could not fetch.
- Referenced but not retrieved: the `sdk.jar` stage loaded by host.dex. Its loader domains are dead, so we describe it from host.dex's use of it rather than from its own bytes; we cannot place it as a confirmed predecessor of zhima.
- Out of scope here: the Xtream/IPTV content side of the operation (the actual pirated streams), a side quest for another day that needs account credentials we did not pursue; and a full historical DNS dump of the C2 boxes, which is a follow-up.

The gaps do not change the observed direct `t1`-to-zhima route, the module analysis, or the infrastructure observations. They do limit what we can claim about the unresolved `sdk.jar` continuation of the host.dex route.

## The bottom line

None of this was sold as a botnet. Somebody wanted the channels without the bill, sideloaded a clean app, and got a tenant: a residential-proxy exit node on the household's own IP, working whatever hours the relay keeps, for whoever is paying. The incriminating code was never in the APK a scanner would flag; it shows up only after the app phones home, which is the whole trick and the whole tell. Watch the file and you see a junky IPTV player; watch the traffic and you see a household IP for hire.

For defenders the shape is simple even when the names are not. A hit on a cover domain means the app is installed; a hit on an `a1.`/`t1.` FQDN means the device reached the payload path. The one guardrail on the exit node, the target filter the operator half-fixed between builds, is not a local-network boundary and was never going to hold as one. The vehicle stays clean, the infrastructure keeps rotating, and, true to the name, the door still opens on request.

Corrections and additional indicators are welcome.

## Indicators of compromise

Indicators are listed defanged in this prose and raw in [`iocs/`](iocs/) for tooling. The cover-domain-versus-C2-FQDN distinction from the exposure model above governs what a given hit means.

### Hashes

| SHA-256 | Type | Description |
|---------|------|-------------|
| `8226f445…8427` | APK | tigertv vehicle (`com.android.tigertv` v1.1.2), VLC-based IPTV with no embedded proxy payload observed |
| `84d16756…d08` | JAR | zhima proxy module `sh65.io` (`com.miyc.transfer.Client`) |
| `906734eb…963` | JAR | zhima proxy module `sh66.io` |
| `ccce124a…640` | JAR | `host.dex` first-stage loader (`com.xgw.f`) |

Three further vehicle APKs are listed in [`iocs/hashes.csv`](iocs/hashes.csv).

### Network

- Seed / rotated cover domains: `newsvxc.shopstoreboutique[.]com`, `appdload.mpfcms[.]com`, `mpfcms.mio-tvplus[.]com` (:2052); `miotvtop.hdwcam[.]com`, `testcf114.bookabcgames[.]com`, `xc.mpfcms[.]com`, `mcm5566.bookabcgames[.]com` (:8080); `tigertvdli1.jopstop[.]com`
- BADBOX C2: `a1.` / `t1.` on `ishano456[.]sbs`, `xmsae[.]sbs`, `xshaon123[.]sbs` → current `172.96.114[.]6` (a1), `98.98.71[.]19` / `98.98.71[.]20` (t1); prior `128.14.207[.]34`, `128.14.207[.]14`, `128.14.202[.]210` (all Zenlayer AS21859)
- Additional Zenlayer BADBOX C2 (passive DNS, not in the analyzed cpc descriptor): `128.14.181[.]46`, `128.14.210[.]58`
- Module loader: `144.217.243[.]201/vr34der34/`
- Residential-proxy relay: `165.154.202[.]29` (:9999 / :5555 / :7777)
- First-stage-loader domains (dead): `a1.ty54fgd435[.]my`, `a1.vrr8345[.]site`, `a1.ue886578433[.]online`, `a1.ty4523[.]space`; OSS fallback `terrtest.oss-cn-hangzhou.aliyuncs.com`
- Activation: `task.mymoyu[.]shop/cpc/api/client/active`

### Host / on-device

- Vehicle packages: `com.android.{tigertv, tigersport, mioplus, miosport, vo_vivo, vo_fixture}`
- Dropped first stage: `files/Download/host.dex` (package `com.xgw.f`)
- Loopback services while the payload runs: `127.0.0.1:10121` (IPC coordinator), `127.0.0.1:12101` (helper RPC)

Full machine-readable indicators: [`iocs/domains.csv`](iocs/domains.csv), [`iocs/ips.csv`](iocs/ips.csv), [`iocs/hashes.csv`](iocs/hashes.csv).

## Related public reporting

- HUMAN Security, ["Satori Threat Intelligence Disruption: BADBOX 2.0"](https://www.humansecurity.com/learn/blog/satori-threat-intelligence-disruption-badbox-2-0/): the operation, the MoYu group, and the published domain corpus; lists `ipmoyu.com` as a BADBOX 2.0 indicator. The "MoYu" naming and four-group breakdown are HUMAN's.
- Google, ["Google takes legal action against Badbox 2.0 cyberattack"](https://blog.google/innovation-and-ai/technology/safety-security/google-taking-legal-action-against-the-badbox-20-botnet/) (July 2025): Google says its researchers partnered with HUMAN and Trend Micro, filed a New York federal lawsuit, and says BADBOX 2.0 compromised more than 10M uncertified AOSP devices; it does not adopt HUMAN's "MoYu" naming.
- Bitsight, ["BADBOX Botnet Is Back"](https://www.bitsight.com/blog/badbox-botnet-back): infrastructure and scale of the resurgent operation.
- WhoisXML API / CircleID, ["Unlocking the DNS Strongbox of BADBOX 2.0"](https://circleid.com/posts/unlocking-the-dns-strongbox-of-badbox-2.0): the DNS indicator corpus this rotation was checked against.
- FBI IC3, ["Home Internet Connected Devices Facilitate Criminal Activity"](https://www.ic3.gov/PSA/2025/PSA250605) (June 2025): advisory on the compromised-device population.
- Palo Alto Unit 42, [Lorikazz Android/IoT indicators](https://github.com/PaloAltoNetworks/Unit42-timely-threat-intel/blob/main/2026-04-13-LORIKAZZ-ANDROID-IOT.txt) (April 2026): lists the `tigertv` APK (`com.android.tigertv`) as a suspected piracy-IPTV infection vector under the Tor-based Lorikazz cluster; does not analyze the zhima payload.
- Trend Micro, ["Lemon Group's Cybercriminal Businesses Built on Preinfected Devices"](https://www.trendmicro.com/en_us/research/23/e/lemon-group-cybercriminal-businesses-built-on-preinfected-devices.html) (2023): independent documentation of the preinstalled-Android → runtime-plugin → reverse-proxy-business model (their "DoveProxy"); Lemon Group is one of the four groups HUMAN folds into BADBOX 2.0.
- XLab (QiAnXin), ["Long Live the Vo1d Botnet"](https://blog.xlab.qianxin.com/long-live-the-vo1d_botnet/): the Vo1d Android botnet and its proxy plugins; ThreatFox cites it as the source classifying `task.mymoyu[.]shop` (tag `spirit`) as a botnet C2.
- Nokia Deepfield ERT, ["RoboVPN / Neunative"](../reports/2026-06-18-robovpn-neunative.md) and ["Pray4Bandwidth"](../reports/2026-03-19-xiongmai-packetsdk-ipidea.md): the residential-proxy-to-botnet economy.
- Synthient, ["A Broken System Fueling Botnets"](https://synthient.com/blog/a-broken-system-fueling-botnets) (Jan 2026): reports Kimwolf's 2M+ infected-device estimate, a hostname resolving to `0.0.0.0` in residential-proxy traffic, and the recommendation to block high-risk ports and restrict local-network access; the separate-family comparison informs the proxy-filter analysis above.
- Qurium Media Foundation, ["The Future and Past of Residential Proxies"](https://www.qurium.org/forensics/the-future-of-residential-proxies/): the proxy/DDoS overlap.
