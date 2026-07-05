# DDoSia: the "botnet" that marks its own homework

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-07-05**

---

## Executive summary

You measure most DDoS botnets in bandwidth. You measure this one in points, because DDoSia literally keeps score. It is the DDoS client of a pro-Russian hacktivist group that has turned flooding websites into a paid competition, and the score is the whole point. None of this is recent: the group has been running DDoSia since 2022.

That group is NoName057(16). It is volunteer-run, one of the most-covered DDoS operations in Europe and one of the least interesting we track. Its reputation has always run well ahead of its capability.

The operation is crowdsourced: a volunteer runs a client from the group's Telegram channel that pulls the day's target list, floods it, and reports the results to a cryptocurrency-reward leaderboard. The traffic is the cost of entry. The score is the prize.

DDoSia is also one of the first families this team tracked, back when it was hammering European customers. It is still here, and it is still mostly a nuisance, and both have been true for years.

Two things in this build are worth a closer look. The first is that the client has kept up with the times without getting any better at its job. It is now packed with garble and two hand-applied tweaks to its Go headers that blind the usual reverse-engineering tools, and its flood engine gained a raw-packet worker (gopacket) and an HTTP/3-over-QUIC worker (quic-go). None of that is in the public record for DDoSia, and none of it is hard to do: the new flood workers are stock libraries dropped in. The extra attack types do not change what the operation actually does, which is run the same low-volume Layer-7 floods. The effort went into being hard to read, not hard to stop.

The second is the scoreboard. The reward leaderboard runs on the honor system: the client reports its own success counts and the C2 believes them. We reversed the session crypto, a formality keyed off the client's own cookie, and stood up a passive client that pulls the real target list and files whatever scores it likes, without sending a single packet of attack traffic. The C2 credits it anyway. The impact numbers the group publishes come from exactly this.

Writing about a group whose product is attention feels a little like feeding it, and we went back and forth on whether to write this at all. We did because the technical reality is deflating, and deflation is the one kind of coverage this group cannot turn into a trophy. The reporters who cover it will find specific guidance below. Treat this as an inoculation, not a feature.

## Key findings

- **The product is a leaderboard.** Volunteers flood targets from a Telegram-distributed client and report their own results for a crypto-reward scoreboard. The impact numbers are self-reported, and the server trusts them.
- **The software is an ordinary flooder.** A Go 1.22 client speaking DDoSia's long-standing C2 API over plaintext HTTP, an AES-256-GCM-encrypted target list, and a bcrypt string for a volunteer ID. Nothing here is new to the art of the DDoS.
- **The recent work went into being unreadable, not unstoppable.** garble `-literals`, plus two manual Go-header tampers (a clobbered `.gopclntab` magic and a wiped build version) that defeat off-the-shelf Go tooling. Both reverse with a 12-byte edit. Neither has been documented for DDoSia before.
- **It grew a raw-packet engine and a QUIC engine.** gopacket builds the Layer-3/4 floods and quic-go carries an HTTP/3 flood. Both are new to DDoSia here, and both come straight off the shelf.
- **The scoreboard is honor-system.** `set_attack_count` submits client-chosen `success`/`total` counts and the C2 accepts them. A passive monitor can register, pull live targets, and file fabricated perfect scores. We did, without sending any attack traffic.
- **The public "proof" is theater too.** The group screenshots check-host.net reachability results as evidence a target is down. That tool probes from scattered global nodes, so a victim that geo-fences or challenges foreign traffic (a defense working as intended) reads as offline, and the group claims the successful defense as a kill.
- **The session "encryption" is a formality.** The login body's AES-GCM key is the ASCII of the client's own `C` cookie, `(C + "0")[-32:]`, and the same key decrypts the target list. We validated the whole chain against a live C2 on 2026-07-05.
- **The DGA-style C2 domains are dead ends now.** A `<4char>.<16char>.{info,live}` scheme rotated across an IP pool in mid-2025, but those rendezvous domains are no longer the actor's and serve no targets. Live tasking comes straight from IP-based C2.

## A note for the newsroom

If you cover this group, we would ask you to hold onto one idea, because it will make your reporting more accurate and their operation less rewarding at the same time.

**The headline is the target, not the website.**

The impact numbers come from the group. The claim of responsibility comes from the group. The verdict that a takedown failed comes from the group, usually while the group is quietly offline. This is an [unreliable narrator](https://en.wikipedia.org/wiki/The_Usual_Suspects) whose entire model is the manufacture of a scoreboard, and whose most successful product has always been the headline rather than the outage. Every figure it publishes is self-reported, and, as the rest of this report lays out, trivially faked by anyone with the client and a text editor.

It is worth being clear about what the coverage itself does. For an operation like this, the headline is not a byproduct of the attack. It is the return on the attack. The crypto leaderboard pays the volunteers; the press pays the group, in the currency it has always actually wanted, and it pays out far more reliably than the flooding does. A half-hour outage nobody writes about is, to NoName057(16), a failure. The same outage on a news site is a win, no matter how fast the target recovered. Repeat their unverified claim and you have handed them the oxygen the whole apparatus runs on.

None of which means ignore them. This is a report, after all, and awareness is not amplification. It means applying the ordinary rule you already use everywhere else: get a second source. If a hacktivist group tells you it took down a country's infrastructure, confirm it with the country. When the group's claim is the only evidence a thing happened, the safe assumption is that it happened to a leaderboard.

## The one we started with

DDoSia has a place in this team's history that its current capabilities do not quite earn. It was among the first families we set up active tracking for, years ago, for a simple reason: it kept turning up on our customers' doorsteps in Europe. The target lists read like a European news digest with a grudge. A national bank one week. A transport ministry the next. An airport or an election authority the week after that. If your organization was European, worked in a sector the group considered insufficiently pro-Russian, and had recently been in a headline, you had a decent chance of spending a morning watching your website field a few hours of Go-generated junk requests.

So we learned the family early, and we have watched it grow up. It even has a past life: DDoSia is the sequel to an earlier NoName flooder called Bobik, which is fitting for a group that lives and dies by its reviews. What is striking, looking back, is how little the growing up changed. The DDoSia of 2022 was a Python script that downloaded a plaintext list of targets and hit them. The DDoSia in front of us is a garble-obfuscated Go binary with a QUIC stack. Between those two points sit three years of steady, incremental engineering and the exact same operation underneath. It floods a list. It always has.

## The volunteer model

The thing that never changed, and the thing that actually explains the group's longevity, is the business model. DDoSia is crowdsourced. There is no worm, no self-propagation, no scanner grinding through the IPv4 space looking for default passwords. The "botnet" is a Telegram channel and a download link. A volunteer installs the client, pastes in an ID, and the client does the rest. It calls home, gets the day's encrypted target list, floods it, and reports its contribution for credit. [Recorded Future](https://www.recordedfuture.com/research/anatomy-of-ddosia) counted the target side at more than 3,700 hosts across Europe. The participant side is however many people felt like opening the app that day, though the group prefers to call them a "cyber army." It is a lot of uniform for installing a program and watching a scoreboard. It is also what keeps the operation going: there is nothing central to seize, only a channel and a scoreboard.

The credit is the clever part, and "clever" is doing some work in that sentence, because it is the only genuinely load-bearing idea in the operation. Contributions are gamified. Volunteers earn points for taking part, they get ranked on a leaderboard, and the top of the table gets paid in cryptocurrency. It is a piece of operational design with nothing to do with software. It turns a chore, leaving a flooding tool running, into a competition, [climbing the board](https://en.wikipedia.org/wiki/The_King_of_Kong), and competitions keep people coming back. Everything technical in this report exists to feed that leaderboard.

## The client

The sample is `d_lin_x64`: a Linux x86-64 ELF, dynamically linked against libc, stripped, about 18.8 MB, built with Go 1.22 and CGO. We first saw it on an analysis host on 2024-11-06. By any reasonable reading it is a normal Go program that happens to flood things.

The identification is not in question. It rests on signals that line up with years of public DDoSia research. The C2 API is the canonical one (`/client/login`, `/client/get_targets`, `POST …/client/set_attack_count`), documented by Sekoia back in 2023. The volunteer identifier is a bcrypt string of the form `$2a$16$…`, which Sekoia named the "User-Hash." The decrypted target list matches DDoSia's long-standing JSON schema. This is DDoSia. The only open questions are what changed and whether any of it matters.

### What changed: the locks

The most substantive change since the public record is defensive, and it is aimed at analysts rather than at defenders. The binary is packed with garble (the `-literals` option, which encrypts string constants), then hand-tampered in two small ways that break the tools people use to read Go binaries:

1. The `.gopclntab` magic is clobbered: the four bytes that let a tool find Go's function table are overwritten with `f3 33 18 d2`, and the rest of the header is left intact.
2. The build version is wiped to `"unknown"`, which is enough to make Ghidra's Go analyzer give up before it starts.

Both undo easily. A 12-byte edit restores the magic and the version to `go1.22`, after which the standard tooling parses the binary, recovers the moduledata, and initializes cleanly. We mention the fix to size the effort honestly: this is a speed bump, not a wall. The flagship engineering achievement of this build, then, is being tedious to open in Ghidra.

Once the headers are back, a manual parse recovers all 23,782 functions at their correct addresses. garble renamed every import path, so `crypto/tls` becomes `cm8m8K1h` and so on, but it left the exported type and method names alone, and those names are exactly the thread you pull to fingerprint the libraries. The JSON struct tags also stay in plaintext, because the program needs them at runtime. Obfuscation always stops where functionality begins.

### What changed: the engine

Underneath the locks, the flood engine rests on four libraries, which fingerprint cleanly from the surviving type and method names. Two of them, gopacket and quic-go, are new to DDoSia here, and both come off the shelf:

| Surviving type/method names | Library | Role |
|---|---|---|
| `LayerType`, `DecodeFromBytes`, `SerializeTo` (hundreds of refs) | gopacket | raw Layer-3/4 packet crafting (SYN, UDP) |
| `ClientHelloInfo`, `Config`, `QUICConn` | crypto/tls (standard library, not utls) | TLS for Layer-7 HTTPS |
| `(*Transport).RoundTrip`, HTTP/2 framer writes | net/http | Layer-7 HTTP/1.1 and HTTP/2 |
| `CongestionWindowAfterAck`, `OnCongestionEvent`, sent-packet handlers | quic-go | Layer-7 HTTP/3 over QUIC |

The raw-socket workers need root, which is why the binary carries the full `setuid`/`setgid` family and does its DNS through cgo. One thing is worth stating plainly, because the additions can read as more than they are. The HTTP/2 floods are ordinary HTTP/2 GETs, not the Rapid Reset attack (CVE-2023-44487) the label sometimes implies, and the HTTP/3 path is HTTP semantics over QUIC, not a raw QUIC flood. The bot brought a QUIC library to a flood fight. It works fine. It is also nothing you could not assemble from public packages in an afternoon.

The full method set, drawn from this build's config and the public corpus:

| `type` | `method` | notes |
|---|---|---|
| `http` | `GET` / `POST` | net/http; `$_N`/`$-N` cache-buster substitution |
| `http2` | `GET` | ordinary HTTP/2 GETs, not Rapid Reset |
| `http3` | `GET` | HTTP over QUIC (quic-go) |
| `tcp` | `syn` (also `syn_ack`/`ack`/`PING`→ICMP) | Layer-4 flood, raw packets via gopacket |
| `udp` | `udp_flood` | bare UDP payload flood |
| `nginx_loris` | (empty) | Slowloris-style socket exhaustion |

### What actually runs

The menu is longer than the operation. The target lists we pull are overwhelmingly Layer-7: HTTP and HTTPS `GET`/`POST` floods, with some `http2` and `http3`, all aimed at websites. That is application-layer traffic, not volumetric flooding, so by DDoS standards the volumes are small. The damage, when there is any, comes from requests that are cheap for the client and expensive for the origin, not from saturating anyone's uplink. A site behind a CDN or a competent WAF mostly does not notice, and neither does a network running DDoS mitigation at the edge, which is what Deepfield does.

The construction is where the thought went. Each target line names a method, a port, a path, and a body, and the client substitutes `$_N` (a fresh random value per request) and `$-N` (a per-target value) into the path and body, drawing each from a `randoms[]` spec that fixes its character set and length. These are cache-busters. A line that hits a site's search endpoint with `?query=$_1` is not trying to fill a pipe; it is trying to slip every request past the cache and onto the origin, where a search costs real work. The raw-packet methods (gopacket `syn` and `udp`, ICMP, `nginx_loris`) round out the builder, but they are not what the daily lists ask for.

### The C2 conversation

The client talks to its C2 in plaintext HTTP. It sets a rotating spoofed browser User-Agent, and then, on some reporting posts, leaks the default `Go-http-client/1.1` string, which rather undercuts the disguise. Authentication is by cookie:

```
U = <bcrypt client_id ($2a$16$…)>  # the volunteer ("User-Hash")
C = <uuid4>-<pid>                  # the install/run ("Client-Hash")
T = <int64 unix-nanos>             # timestamp (on POSTs)
K = <base32(RSA blob)>             # per-request key transport
```

A small chronological note for anyone dating samples: this cookie scheme was publicly attributed to DDoSia's 2025 generation, but this build was compiled in November 2024 and already had it.

The build also carries a domain scheme alongside its bare IPv4 C2: it can resolve `<4char>.<16char>.{info,live}` subdomains, for example `KDXA.gwYhHCOrybwjWuzh[.]info`, which we saw rotating across an IP pool in mid-2025. That layer looks to have since slipped out of the actor's hands. The rendezvous domains now delegate to what appears to be a third-party measurement operator and resolve to a single cloud host that speaks the DDoSia C2 API but hands back an empty target list. We would not over-read who did that or when. The operational point is simpler: those domains no longer carry live tasking, and the actor has fallen back to direct-IP C2 distributed out of band. The cohort we validated on 2026-07-05 pulled its 200 targets straight from `185.76.78[.]136`. A bot still calling the old names reaches something that talks like the C2 and gives it nothing to do.

The C2 hosts we have tied to this build are `151.236.18[.]179` (from a process core), `65.38.121.22` (from a November-2024 packet capture), and `153.75.85[.]190` (recorded, and down at capture). The live one at analysis time gets its own section next.

## The crypto, reversed

The target list is encrypted, which sounds like it should be the hard part. It is not. We reversed the whole scheme from the binary and a core dump, then validated it end to end against a live C2 on 2026-07-05 by standing up a client in Python, no binary involved, that registered, pulled the day's 200 targets, and decrypted them.

The punchline first: the session key is the client's own cookie. When the client logs in, it AES-256-GCM-encrypts the login body under a key that is just the ASCII of `(C + "0")[-32:]`. Take the `C` cookie, append a literal `"0"`, keep the last 32 characters. The server re-derives the same key from the same cookie the client just handed it. The "encryption" on the login is security theater. Both sides already share the secret, because the client mailed it in.

```
POST /client/login
cookies: U=<bcrypt client_id>   C=<uuid4>-<pid>
body:    {"body": base64( nonce(12) ‖ AES-256-GCM(ct) ‖ tag(16) )}
key:     ASCII of (C + "0")[-32:]
```

We confirmed the derivation on two independent sessions:

```
C = 2887204d-4360-046e-8bf8-16412dc8da2c-951  →  key 4360-046e-8bf8-16412dc8da2c-9510
C = c4b6c34b-a9d9-421b-959b-84c7057589a2-1816 →  key 9d9-421b-959b-84c7057589a2-18160
```

The same key decrypts the `get_targets` response. There is a real RSA step in the protocol, a `K` cookie carrying `base32(RSA-2048 PKCS#1 v1.5(server_pub, M))` where `M` is a two-byte prefix followed by 46 random bytes, and the embedded server public key is genuine and still accepted by the live C2. But the response is not keyed off `M`. It is keyed off the same `(C + "0")[-32:]` session value, with the GCM nonce prepended to the ciphertext. The RSA exchange happens; the target list decrypts without it. Somewhere in the protocol is a 2048-bit key doing no work at all. An earlier reading of ours had the response key derived from `M`, and it was wrong. We spent a while hunting for a secret the protocol never bothered to keep.

One thing will trip up anyone reimplementing this. Use `C[-32:]` instead of `(C + "0")[-32:]` and the C2 returns `403 Forbidden`, because the login body no longer authenticates under the key the server derived. Every downstream failure we chased came back to that missing `"0"`.

The live C2 serving this cohort at validation time was `185.76.78[.]136`, plaintext HTTP on port 80. The first target on the list it handed us was `ezamowienia.gov.pl`, the Polish government e-procurement portal. Business as usual.

## The scoreboard is honor-system

After a client attacks, it tells the C2 how it did, and the C2 believes it. The report is a `POST /client/set_attack_count` under the same session key, and per target the body carries `success`, `total`, and `request_len`: how many requests the client says it landed, out of how many it says it tried. Aggregate byte and request counters ride along in the outer envelope. This telemetry is what feeds the reward leaderboard.

```
POST /client/set_attack_count
cookies: U=<client_id>  C=<uuid4>-<pid>  T=-<unix ns>  K=<base64 128 bytes>
body:    {"data": base64(nonce ‖ AES-256-GCM(outer) ‖ tag)}
outer:   {"push_time", "result": <encrypted per-target stats>, "b": <bytes>, "l": <requests>, "key": ""}
stats:   [{"target_id","request_id","success","total","request_len"}, …]
```

Two details tell you how much checking goes on at the other end. The `T` cookie is `-(time.Now().UnixNano())`, the current clock, negated, which is a decorative amount of effort to put into a timestamp. The `K` cookie is a 128-byte blob the C2 does not validate at all. We sent reports with a foreign session's `K`, with a random `K`, and with no `K` cookie at all, and every one came back `200 OK`. This is not a server that checks its inputs.

And it does not check the input that matters. The success counts are whatever the client says they are. There is no independent measurement of whether the target actually fell over, and there cannot be, in a crowdsourced model where the sensors are the attackers. So the leaderboard is built entirely on self-reported statistics, submitted by people who are competing to rank high on it, for money. That is the honor system, wired to a cash prize.

We tested the obvious consequence. `ddosia_monitor.py` registers as an ordinary volunteer and pulls the real live target list, which is the genuinely useful thing, because it is how we see who is being hit today. Behind an explicit flag, it also files reports claiming `success == total` on every target, with plausible byte and request counts. It sends no attack traffic. The C2 accepts the reports, returns `200 OK`, and credits the ID as though it had done the work. A monitor that attacks nothing can sit on the leaderboard in good standing for as long as it likes, and climb it if it wanted to.

We are not interested in climbing it. We report this because it settles a question about the group's numbers. The impact figures NoName057(16) publishes come straight out of this telemetry: unverifiable claims, submitted by anonymous participants, about outages no neutral party measured. The scoreboard is honor-system, and so, it turns out, is the war.

## Claimed vs. real

Which brings us to the recurring theme, now with evidence.

In July 2025, Europol's [Operation Eastwood](https://www.europol.europa.eu/media-press/newsroom/news/global-operation-targets-noname05716-pro-russian-cybercrime-network) (twelve countries, run with Eurojust) took down more than a hundred DDoSia servers, put the group's central infrastructure offline, and produced two arrests and seven international arrest warrants. NoName057(16) responded within hours by dismissing the whole thing on Telegram and calling it a failure. Then, by [Imperva's](https://www.imperva.com/blog/operation-eastwood-measuring-the-real-impact-on-noname05716/) measurement of the aftermath, the group went quiet for about five days, with no target lists and no attack records. That is a strange way for an unaffected operation to behave. Imperva's verdict on the real impact is the most precise summary of this group we have read, so we will borrow it: the operation was "far from the 'harmless' disruption they tried to portray," and also "not devastating." That two-sided sentence is DDoSia in miniature. It is never nothing. It is never much.

The same lopsidedness runs through the attacks. When DDoSia lands, it lands like a nuisance. Imperva records a Spanish municipal portal, Vigo's, knocked offline "for about half an hour before defenses kicked in." Half an hour, and then mitigation caught up. A real outage, and also the kind a competent CDN eats before lunch. Meanwhile the group's public accounting inflates in every direction it can reach. After Eastwood it announced a retaliation campaign under the straight-faced banner "Time of Retribution" and claimed same-day hits on sixteen sites in Germany, eleven in Italy, and Interpol. The branding always outsizes the operation: a self-styled "cyber army fighting for truth," promising to come back "stronger than ever." It also stepped outside DDoS entirely, with thirteen separate claims of system intrusions: control of water facilities in Romania and Czechia, Lithuanian boiler systems, a Spanish desalination plant. None were independently verified, and several were routed through a coalition banner so the credit could be spread around. A group whose measurable capability is making a website slow for half an hour was, on the same channel, claiming the keys to a desalination plant.

There is a tell in how the group proves any of this. When it claims a target, it posts a screenshot from [check-host.net](https://check-host.net/), a public reachability checker, as the evidence. The trouble is what check-host.net measures. It pings the target from a scattered set of nodes around the world and reports which ones got an answer, which is not the same question as whether the site is down for the people who use it. A victim that answers an attack by geo-fencing the regions the traffic is coming from, or by dropping a challenge page in front of foreign visitors, fails from exactly the probe nodes sitting in those regions while serving its real audience the whole time. The board goes red, the group screenshots the red, and a defense doing its job gets filed as an attack that worked. The same screenshot appears when a site wobbles for thirty seconds and recovers, because a checker caught at the right moment freezes the wobble forever. It is proof of something. It is not proof of what it is presented as.

This is the behavior that defines DDoSia for us, more than any packet it sends. It will claim anything, and it will pile onto anyone. When someone else causes an outage, NoName057(16) is quick to fold it into the tally. The leaderboard mentality does not stop at the volunteers. The group marks its own homework, gives itself top marks, and reads the result out to the press.

## Detection

DDoSia is loud and consistent on the wire, and the disguise is thin.

### Network indicators

- **C2 API over plaintext HTTP.** Cleartext requests to `/client/login`, `/client/get_targets`, and `/client/set_attack_count` are the canonical DDoSia signature, whatever the destination IP.
- **The cookie scheme.** A `U` cookie holding a bcrypt string (`$2a$16$…`), a `C` cookie shaped `<uuid4>-<pid>`, and a negated-nanosecond `T` on POSTs.
- **DGA-style C2 domains.** `<4char>.<16char>.{info,live}` subdomains resolving to a rotating C2 pool, a behavioral pattern IP blocklists miss.
- **User-Agent tells.** A rotating spoofed-browser UA on most requests, with the default `Go-http-client/1.1` leaking onto some reporting posts.
- **The floods.** Ordinary HTTP/1.1, HTTP/2, and HTTP/3-over-QUIC GETs with `$_N`/`$-N` cache-buster query parameters; gopacket-crafted SYN and UDP floods; Slowloris (`nginx_loris`).

### Host indicators

- The `d_lin_x64` sample, SHA-256 `2aaf3c08da86d5d0f6f9c00d4011991fd2cd50fa0777d51d5552b98365b15774`.
- A Go ELF whose `.gopclntab` magic reads `f3 33 18 d2` and whose build version is `"unknown"`. The two header tampers are a static signature in their own right.
- The embedded RSA-2048 C2 public key (modulus `da982874adbe94fe…`, full value in [`iocs/keys.csv`](iocs/keys.csv)).
- A process running as root that opens raw sockets and pulls target lists over plaintext HTTP.

### Monitoring

Because a passive client can register and pull the live target list, the most useful defensive move is to watch the list. A read-only monitor sees each day's targets as the operators publish them, which is early warning for the organizations on it, and it does not require sending or faking a single attack. If you would rather not run your own, CIRCL publishes exactly this as a public feed at [witha.name](https://witha.name/) and on its [`@noname57bot`](https://social.circl.lu/@noname57bot) Mastodon account; subscribe and you get the decoded daily targets for free.

## Attribution and prior research

This is DDoSia, the DDoS client of NoName057(16). The attribution is not in doubt, and it is not ours to claim. It rests on years of public work, and the findings that are new here (garble and the header tampers, the gopacket and quic-go engines, the DGA C2 scheme, the reversed session crypto, the honor-system reporting) build on a well-developed public record.

The public analysis of this family is unusually good, and we leaned on it throughout. [Sekoia](https://www.sekoia.com/blog/noname05716-ddosia-project-2024-updates-and-behavioural-shifts) documented the client API, the bcrypt "User-Hash," the AES-GCM target-list encryption, and the substitution tokens across 2023 and 2024. [SentinelLABS](https://www.sentinelone.com/labs/noname05716-the-pro-russian-hacktivist-group-targeting-nato/) and Avast/Gen Digital published the first analyses of the [Python original](https://www.gendigital.com/blog/insights/research/ddosia-project-volunteers-carrying-out-noname05716s-dirty-work) and the [Go rewrite](https://www.gendigital.com/blog/insights/research/ddosia-project-how-noname05716-is-trying-to-improve-the-efficiency-of-ddos-attacks) in early 2023. [Recorded Future](https://www.recordedfuture.com/research/anatomy-of-ddosia) mapped the multi-tier C2 and the 3,700-plus European target hosts, and named the 2025 cookie identifiers. [AhnLab](https://asec.ahnlab.com/en/84531/), Team Cymru, [tgragnato](https://tgragnato.it/2025/02/23/ddosia-mitigations.html), [SOCRadar](https://socradar.io/blog/dark-web-profile-noname05716/) (whose group profile documents the check-host.net "proof" ritual), the community MISP DDoSia config feed, and [Censys](https://censys.com/blog/ddosia-infrastructure) all contributed pieces we relied on. Special credit goes to CIRCL (Computer Incident Response Center Luxembourg), whose [witha.name](https://witha.name/) DDoSia C2 configuration tracker and its `@noname57bot` feed publish the group's decoded daily target lists in near real time. It is one of the most useful public resources on this family, and it is exactly the watch-the-list monitoring we recommend above, run as a public service so you do not have to. [Europol](https://www.europol.europa.eu/media-press/newsroom/news/global-operation-targets-noname05716-pro-russian-cybercrime-network) ran Operation Eastwood. [Imperva](https://www.imperva.com/blog/operation-eastwood-measuring-the-real-impact-on-noname05716/) did the careful, unglamorous work of measuring what it actually accomplished, and landed on the honest "not harmless, not devastating" verdict this report keeps returning to.

Corrections and additional indicators are welcome.

### Evolution

| Date | Change |
|---|---|
| ~Jul 2022 | Python "DDoSia" appears; plaintext JSON target list |
| Late 2022 | Go rewrite ("Go-Stresser"), roughly 8× throughput |
| Jan 2023 | First public analyses; Go adds `http2` |
| Mar 2023 | Token auth; bcrypt-format User-Hash |
| Apr 2023 | AES-GCM target-list encryption |
| Nov 2023 | 32-bit and FreeBSD builds |
| Mar 2024 | POST bodies also AES-GCM; 7-field host fingerprint; "Go-Stresser v2.0" |
| Nov 2024 (this build) | Go 1.22; garble `-literals` + pclntab/buildinfo tamper; gopacket L3/L4; quic-go HTTP/3; `.info/.live` DGA C2 |
| 2025 | Cookie-based `U`/`C`/`K` identifiers (already present here in Nov 2024) |
| Jul 2025 | Operation Eastwood takedown (100+ servers) |
| H2 2025 | C2 server mean lifespan drops from ~9 days to ~2.5 days |

## Indicators of compromise

The full machine-readable set (hashes, C2 IPs, the legacy DGA domains, keys) is in the [`iocs/`](iocs/) directory. The handful worth carrying in your head:

| Indicator | Value |
|-----------|-------|
| SHA-256 | `2aaf3c08da86d5d0f6f9c00d4011991fd2cd50fa0777d51d5552b98365b15774` |
| Live C2 (2026-07-05) | `185.76.78[.]136` (plaintext HTTP/80) |
| C2 API paths | `/client/login`, `/client/get_targets`, `/client/set_attack_count` |
| Session key rule | `(C + "0")[-32:]` (ASCII), where `C = <uuid4>-<pid>` |
| Header-tamper signature | `.gopclntab` magic `f3 33 18 d2`; build version `"unknown"` |

## The bottom line

DDoSia is a durable nuisance with an unusually good [press operation](https://en.wikipedia.org/wiki/Wag_the_Dog). It keeps flooding sites that mostly shrug it off, and it keeps announcing wins it cannot show you. The defense is not exotic: the day's target list is public, down to the specific hosts and paths, and it rarely changes per target, so you can harden the exact endpoints in advance, absorb the flood at the edge, or let a WAF take it. Price the group's own numbers at what they are worth. The floods are real enough; the scoreboard is the fiction, and the coverage is the payout. Report it accordingly.

## Edit history

| Date | Change |
|------|--------|
| 2026-07-05 | Initial public release |
