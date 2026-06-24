# Vibenet: the DDoS bot that brings its own browser

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-06-23** | **Last updated: 2026-06-24**

---

> **Note:** Some domains and strings quoted below are slurs or otherwise offensive, chosen by the operators for branding and reproduced verbatim for detection.

## Executive summary

Most DDoS bots make no effort to hide what they are on the wire. They open a flood of connections, push as much traffic as they can, and let the packets fall where they may. The Vibenet build we pulled apart goes to real trouble to look like something else. It is a custom (non-Mirai) family, also tracked as Heilong after its 2026 Android rebrand, that spreads to Android TV boxes and IoT devices over ADB. We track it in two lines: v1, the original `libyahu`/`libkys` Android builds, and v2, a newer ground-up standalone-Linux rewrite still under active development. This sample is a v2 build: statically linked, stripped, and carrying no libc at all, with everything from its TLS stack to its syscalls written in-house. Two of its design choices are worth pulling apart, for opposite reasons.

The first is becoming routine, which is a finding in itself: the bot keeps its command-and-control on-chain. We track several families that read their C2 from an Ethereum dead drop, so the on-chain part is not the story; the specifics are. This build pulls its C2 from an ENS text record (`alextyler.eth`, key `description`) using JSON-RPC over HTTPS, after resolving provider hostnames with DNS-over-HTTPS. When we decoded the live record it pointed at `127.0.0[.]1`: this build's dead drop was aimed at localhost, the off position of the switch. That is not the whole botnet asleep. `alextyler.eth` is this build's own dead drop; the v1 line runs on separate channels, and those (the `meow.fuckmepls.eth` ENS record and the `femboy-e[.]date` DNS domains) were still resolving to live C2 at the time. So the likeliest reading is that the `alextyler.eth` build had not been switched on yet, or was idle between runs. Either way the record sits on a public ledger, so the next time the operator points it at a real host, we will see it.

The second is the unusual one: what the bot drags along to do its flooding, a complete, hand-written web client. TLS 1.2 and 1.3, QUIC version 1, HTTP/2, HTTP/3, with no third-party TLS library anywhere in the binary. Its Layer-7 floods complete real handshakes with a fixed, browser-shaped fingerprint, so the attack traffic looks like someone loading a website. For all that machinery, though, the bot never checks a certificate. It will shake hands with anything. The crypto is not there to keep the channel secure. It is there to help the bot blend in.

Strip the new transport away and the same Vibenet shows through. We have two v2 builds in hand, and they already disagree: this one shares its encrypted-string cipher and key with an earlier build (`f2671998`), marking the two as one codebase, yet they differ enough to read as a moving target (the earlier one even carried a post-quantum handshake step this one drops). The `meow` magic and the flood set underneath both are what tie v2 back to v1. The capability that is genuinely new in v2, beyond the web client, is a SOCKS-style proxy relay wired into the command channel, so a box running this build is not just a flood source but a rentable exit node.

## Key findings

- **The C2 lives on-chain.** The current C2 IP list is published in an Ethereum ENS text record and read over hardcoded RPC endpoints whose hostnames are resolved via DoH. No C2 domain or IP ships in the binary.
- **This build's dead drop was parked.** The `alextyler.eth` record decoded to `127.0.0[.]1` on 2026-06-23: this campaign's switch in the off position, most likely not yet live. The v1 line's separate C2 channels were still active at the time, so this is not the whole botnet going dark.
- **It brings its own browser.** A from-scratch TLS 1.2/1.3 + QUIC v1 + HTTP/2 + HTTP/3 stack, in a binary that links no libc at all, used both to reach the dead drop and to flood at Layer 7 while doing a convincing browser impression.
- **It validates nothing.** The TLS and QUIC handshakes accept any certificate. The encryption is camouflage, not authentication.
- **The fingerprint is fixed.** A deterministic, browser-like ClientHello (four cipher suites, x25519 only, ALPN `h2,http/1.1`, no GREASE) makes the family easy to spot on the wire.
- **Same codebase, same family.** The encrypted string tables, cipher, and key are shared with the earlier v2 build (`f2671998`), marking them one codebase; the `meow` C2 magic, the Layer-3/4 and game-query floods, the SSH-banner scanner, the competitor killer, and self-staging carry the v1 lineage forward.
- **It runs in a pack.** The bot reads C2 from the same public ENS resolver as [jackskid](../jackskid/) and other tracked families, each with its own encoding.

## The on-chain dead drop

On-chain command-and-control is not new, and it is not this family's invention. We track several botnets that hide their C2 on an Ethereum dead drop ([jackskid](../jackskid/) among them), and at this point it reads less like a clever trick than like a house style for this corner of the scene. If you have been waiting for a real-world use of on-chain text records, the DDoS scene beat you to it. So the question is not whether this build uses ENS; it is how, and where it diverges from its neighbors. There is no C2 address anywhere in its data, so it has to go fetch one, and the way it does that is more involved than it needs to be. That turns out to be the theme.

It starts by computing the ENS namehash of `alextyler.eth` in-binary, using Keccak-256 (the Ethereum flavor, with `0x01` padding, not NIST's SHA3-256 with `0x06`). Yes, that one-byte difference matters, and yes, plenty of people have shipped the wrong one. With the namehash in hand it builds an `eth_call` to the ENS public resolver contract `0xF29100983E058B709F3D539b0c765937B804AC15`, selector `0x59d1d43c`, which is `text(bytes32,string)`, asking for the record named `description`.

That call goes out as JSON-RPC over the bot's own HTTPS client, against a fixed list of eleven RPC endpoints, tried top to bottom until one answers:

```
eth-mainnet.public.blastapi.io   eth.drpc.org        1rpc.io/eth
cloudflare-eth.com               eth.public-rpc.com  rpc.gnosischain.com
rpc.ankr.com/eth                 rpc.flashbots.net   gateway.tenderly.co
mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161
eth-pokt.nodies.app
```

Note the sixth entry. `rpc.gnosischain.com` is the Gnosis Chain RPC, not Ethereum mainnet, so it cannot return the Ethereum ENS record. The bot does not appear to know this, and fails past it on every run. Someone copied a provider list and did not read it closely: a small human fingerprint in an otherwise careful program. The Infura URL is more of the same. Its project ID, `9aa3d95b3bc440fa88ea12eaa4456161`, is a public one copied across hundreds of repositories, lifted in here along with the rest of the list. It helps match copied provider lists across samples, not attribute one.

Each provider hostname is itself resolved over DNS-over-HTTPS, never the system resolver. The bot tries `1.1.1.1`, then `8.8.8.8`, then `9.9.9.9` with a Cloudflare-style JSON DoH request (`GET /dns-query?name=<host>&type=A`, `Accept: application/dns-json`) and reads the answers out of JSON when a resolver accepts it. So before it can ask the blockchain anything, it does its own DNS, over its own TLS, to avoid touching the host's resolver. A lookup inside a query inside a flood: we have to go deeper.

### Decoding the record

The record value is a list of comma-separated tokens, each one dressed up to look like an IPv6 address. That costume is the point. Only the last two 16-bit groups of each token carry anything real; the leading groups are decoys, there to make the value look like inert infrastructure to a passing eye. The bot takes those two groups, stitches them into a 32-bit number, XORs it with `0x4ab73ce1`, and prints the result as a dotted quad, least-significant byte first:

```
ipv4 = ((group[-2] << 16) | group[-1]) XOR 0x4ab73ce1   # printed LSB-first
```

We read the live record on 2026-06-23. It held a single token, `::4bb7:3c9e`, which works out to:

```
(0x4bb7 << 16 | 0x3c9e) XOR 0x4ab73ce1 = 0x0100007f  ->  127.0.0[.]1
```

There's no place like home. Pointing a dead drop at localhost is the off position of an on-chain switch: a bot running this build would connect to itself, find nothing, and wait. It does not mean Vibenet is down. The v1 line runs on its own channels: checked the same day, the earlier `meow.fuckmepls.eth` ENS record still resolved to a live C2 (`143.20.185[.]88`), so the likeliest reading is that the `alextyler.eth` build simply had not been switched on yet. A dead drop on a public ledger is resilient and completely public at the same time: the operator gets uptime that is hard to take down, and we get read access. We can re-read the record for the price of an RPC call, so the moment it points at a real host, the new C2 is right there.

So where does this version diverge from the others in the cluster? In four small ways, none of them revolutionary, that together make a recognizable dialect of a shared technique. It computes the namehash at runtime with its own Keccak-256, where the v1 Android builds bake the namehash in at compile time, so the operator can repoint this bot at a different name without rebuilding it. It calls the public resolver directly at a hardcoded address instead of looking the resolver up through the ENS registry first, trading a little flexibility for one fewer round trip. It hides the value in `description`, an ordinary ENS profile field, so the record reads as a real name's metadata rather than something bespoke; it is the dead-drop equivalent of writing your C2 in the About Me box. And it resolves the RPC-provider list with DoH before trying eleven endpoints, which is more plumbing than most of its neighbors bother with, and the reason the lookup keeps working even when a provider or a resolver is blocked.

## The browser it carries

Most bots that need TLS link WolfSSL or mbedTLS, or skip the encryption and flood in the clear. This one builds the entire stack itself, down to the primitives: TLS 1.2, TLS 1.3, QUIC version 1, HTTP/2, HTTP/3, a DoH client, ChaCha20-Poly1305, AES-128-GCM, X25519, SHA-256, HKDF, and Keccak-256. We went looking for the usual library tells. There are none. No OpenSSL, no BoringSSL, no WolfSSL strings or symbols. Somebody sat down and wrote a QUIC client for a DDoS bot, which is not a sentence we expected to write this year. For a flooding tool, this is doing the most.

And it's not a toy. The QUIC code derives Initial keys from the RFC 9001 version-1 salt, applies header protection, reconstructs packet numbers, handles Retry and key updates, and feeds CRYPTO frames into a real TLS state machine. The same code that fetches the ENS record over HTTPS also runs the floods. It speaks genuine HTTP/2 (connection preface, SETTINGS frame, HEADERS with HPACK static-table indices) and genuine HTTP/3, emitting one GET per connection with the target in the `:authority` field. It is a more complete QUIC client than some things you have installed on purpose.

The reason for all of this is disguise. The ClientHello is fixed and shaped like a browser's, and it negotiates ALPN `h2,http/1.1`. To a network sensor, and to a fair number of Layer-7 mitigation products, a flood from this thing reads as a browser fetching pages over HTTPS or QUIC. That is the whole point, and it mostly works.

### Crypto as camouflage, not security

Now the punchline. After all that work, the bot does no certificate validation at all.

In the TLS 1.3 handshake, the Certificate and CertificateVerify messages get fed into the transcript hash and then ignored. There is no X.509 parser, no ASN.1, no RSA or ECDSA verification, no name checking; none of it is in the binary. The only thing the bot confirms before it trusts the connection is the Finished MAC, which proves the other side completed the same X25519 exchange and nothing more. It confirms the peer can do arithmetic, and asks no further questions. The QUIC path behaves identically.

So the elaborate handshake exists to make the traffic look right, not to make it safe. It's a fake ID that every bouncer waves through. There is something almost honest about it: the author understood exactly which property mattered for their goal (looking legitimate to a sensor) and spent zero effort on the property that did not (actually verifying the peer). For defenders this cuts a useful way. Anyone on the path can complete the handshake using any certificate, so in a controlled environment the bot's RPC and DoH traffic are all yours to read.

## The post-quantum it left behind

The clearest sign that v2 is still in motion is a split between its two builds. The earlier v2 (`f2671998`) carried a post-quantum step: an ML-KEM-768 (Kyber) key encapsulation in its C2 key-establishment path. This build drops it. Its session is authenticated with a plain X25519 exchange and a Poly1305 tag over a fixed `server_auth` label, and there is no Kyber anywhere in it: no modulus-3329 arithmetic, no NTT, none of the SHA-3/SHAKE sponge a Kyber implementation needs. The only Keccak present is the `0x01`-padded Keccak-256 the bot uses for the ENS namehash.

We wouldn't read this as a deliberate downgrade. ML-KEM is heavier and fiddlier than a classical Diffie-Hellman exchange, and post-quantum primitives are presumably harder to carry across the cramped, mismatched IoT and embedded targets this family builds for. The simplest explanation is the boring one: as v2 matured toward those targets, it settled on the handshake that fits everywhere.

## The C2 channel

Finding a C2 address is only half the job; the bot still has to talk to it. Once the dead drop yields an IP, the bot opens a TCP socket straight to it, picking from a shuffled set of common web ports (mostly Cloudflare's proxied-port set, plus 9443: 443, 80, 8080, 8443, 9443, 2053, 2083, 2087, 2096, 8880) so the connection reads, by port number, as ordinary web traffic. The connection is direct, not fronted by any CDN; the port choice is the only camouflage, and the channel itself is not even TLS. It turns on keepalives (`SO_KEEPALIVE`, a ten-second idle timer, a thirty-second user timeout, so dead C2s drop quickly) and runs a short handshake of its own design. It generates an X25519 keypair, sends its 32-byte public key, reads 48 bytes back (the server's public key and a 16-byte tag), derives a session key, and verifies a Poly1305 tag computed over the label `server_auth`. There is no TLS and no certificate on this path. The handshake is a small Noise-style construction that proves both ends share the X25519 secret, and nothing else. Rolling a bespoke handshake here is a bold choice for a bot that already ships a full TLS stack it could have reused. It is also the step that, in the earlier v2 build (`f2671998`), carried the ML-KEM exchange.

After the handshake, the channel is framed and authenticated. Every message is a 24-byte header, a 16-byte tag, a 4-byte big-endian length, and up to 4 KB of AEAD-protected ciphertext. Decrypt it and the first byte is an opcode, the next two are a big-endian length, and the rest is the command body. A dispatch table routes fourteen opcodes across two bands. The low band is the command channel: `0x00` is a keepalive and `0x01` starts an attack (method, target, port, and duration in the body); the remaining low opcodes handle control and configuration. The high band is the part most flooders never ship. `0x20` opens a proxy connection, dialing an operator-supplied IP and port and holding the socket open; `0x21` pushes bytes through it; `0x22` closes it. Up to sixteen of these tunnels run at once, tracked in a small connection table; sixteen concurrent relays is either a sensible cap or an optimistic one, depending on how booked the operator expects to be. The same infected box that floods a target can be rented out as a relay, which is the quiet half of this bot's job.

Lined up across all three, the control channel tells the rest of the story. They share the same bones, a ChaCha20-Poly1305 channel over raw TCP, but v2 rebuilt the front of it: where v1 leans on a pre-shared key the server tops up, v2 negotiates a fresh X25519 secret each session. The two v2 builds then disagree on the details (the earlier one even wrapped that exchange in the post-quantum step covered above), the clearest sign the rewrite is still moving. The genuinely new pieces, the ENS locator and the proxy relay, arrive only in this build.

| Aspect | v1 (libyahu Android line) | Earlier v2 (`f2671998`) | This v2 build (`58f80286`) |
|---|---|---|---|
| Transport | raw TCP | raw TCP | raw TCP, tuned keepalives |
| C2 locator | DNS domains (later an ENS record) | `meow` hosts via DNS/DoT | ENS dead drop (`alextyler.eth`), DoH-fronted RPC |
| Key exchange | none; pre-shared key, server supplies the session key | ML-KEM-768 (Kyber) + X25519 | X25519 only |
| Peer authentication | implicit (shared key); later builds add an RSA key | KEM decapsulation check | Poly1305 MAC over `server_auth`, no certificate |
| Session AEAD | ChaCha20-Poly1305 (12-byte nonce, 16-byte tag) | ChaCha20-Poly1305 (same) | ChaCha20-Poly1305 (same); AES-128-GCM added for TLS/QUIC |
| String obfuscation | XOR-`0xAA` / XTEA | RC4 + Galois-LFSR (`a35fc89…`) | RC4 + Galois-LFSR (`a35fc89…`) |
| Record framing | `meow` magic, length-prefixed AEAD | `meow` magic, length-prefixed AEAD | length-prefixed AEAD, up to 4 KB |
| Proxy relay | none | none | SOCKS-style `0x20`/`0x21`/`0x22` |
| Post-quantum step | none | ML-KEM-768 present | dropped |

Underneath, all three are ChaCha20-Poly1305 frames over raw TCP. The changes are at the front: v1's `meow` magic and pre-shared key gave way, by this build, to a 24-byte-header frame and a negotiated X25519 handshake, and the on-chain locator and proxy are new here. One v1 capability did not make the jump at all: its remote-shell command has no slot in this build's dispatch table.

## The flood engine

An attack arrives on opcode `0x01`. The command names a method, the bot resolves the name to a numeric id (0 through 12), and that id indexes a table of worker functions; the chosen worker starts up and runs its flood against the target until the duration runs out. The Layer-7 workers ride the embedded TLS/QUIC client, and the Layer-3/4 workers build packets straight onto raw sockets. One worker, the TCP-flag flood, carries its own sub-menu: a second numeric id picks the flag combination, anything from a plain `syn` to randomized per-packet flags.

That structure is also where the v1-to-v2 story shows up. Lined up against the v1 line, this build keeps the older Layer-3/4 set and pushes hardest at Layer 7:

| Layer | Method | v1 (prior line) | This build (v2) |
|---|---|---|---|
| L7 | HTTP/1.1 GET flood (cleartext) | yes | yes |
| L7 | HTTPS GET flood | yes (WolfSSL, HTTP/1.1) | yes (own TLS stack) |
| L7 | HTTP/2 flood | no | **yes, new** |
| L7 | HTTP/3-over-QUIC flood | no | **yes, new** |
| L4 | TCP SYN flood | yes | yes |
| L4 | TCP flag matrix (ack, psh-ack, fin, rst, syn-rst, syn-ack, fin-ack, xmas, null) | SYN only | **full matrix, new** |
| L4 | TCP Fast Open and randomized mixed-flag floods | no | **yes, new** |
| L4 | TCP connect / handshake floods | yes | yes |
| L4 | UDP flood (plain and raw, spoofed source) | yes | yes |
| L4 | Game-query floods (Source Engine, Quake, SAMP) | yes | yes |
| L4 | SSDP M-SEARCH reflection | yes | yes |
| L4 | DNS query flood | yes | yes |
| L4 | Amplification / game-query content menu (~15 templates) | broad | broad (retained) |
| L3 | ICMP flood | yes | yes |
| L3 | GRE flood | yes (GRE bytes over UDP) | yes (real IP-proto-47 worker, plus the over-UDP payload) |

A few things stand out. The Layer-7 surface grew a real HTTP/2 and HTTP/3-over-QUIC capability; the v1 line's encrypted HTTP flood was HTTP/1.1 over WolfSSL and nothing newer. The TCP-flag flood went from a single SYN type to a twelve-way matrix that now includes TCP Fast Open and a randomized mixed-flag mode. The Layer-3/4 side did not shrink to pay for it: the content-template engine still carries a broad menu of game-query and amplification payloads, and this build adds a dedicated GRE flood the prior generation never had.

The Source Engine, Quake, and SAMP query floods mean the same binary that knocks over a website can also take down a Counter-Strike, Quake, or San Andreas Multiplayer server; the botnet and the LAN party share a target list.

The GRE flood says something about labels and lineage both. The v1 line never emitted real protocol-47 GRE; it only stuffed a fixed 19-byte GRE-shaped blob into a UDP datagram. This build does both: it carries that same blob byte-for-byte (one more thread tying the two codebases together) and adds a dedicated worker that builds genuine protocol-47 GRE packets on a raw IP socket. The Layer-7 flood's request paths cut the other way, worth less than they look: the `/wp-login.php` and `/admin` strings in the binary are canned filler for a raw-TCP payload template, not targets the Layer-7 client actually requests.

## The Vibenet body

Take the shiny new transport off and you're left with a bot you've met before. Almost every behavioral string is held in three encrypted tables, unpacked at runtime by an RC4 keystream XORed with a Galois-LFSR keystream (polynomial `0x80200003`) under the key `a35fc8912d764eb0671af38439c25b0e`. Decrypt them and the family's usual furniture falls out: the `meow` magic (the cat motif runs deep here: the stager is `meow.sh`, a v1 dead drop was `meow.fuckmepls.eth`), a DNS-over-TLS resolver pool, the SSH banners the scanner wears, a competitor killer that walks `/proc` and `/proc/net/*` and `kill`s rivals, architecture suffixes for cross-platform droppers, writable staging paths, and watchdog-device handling.

Buried in the killer table is the operator's one request: `dont call this mirai please`. Consider it noted. (Reader, it is a Mirai-adjacent bot.)

On startup it installs SIGPIPE and SIGCHLD handlers, scans the mount table for somewhere writable, stages a copy of itself as `.c.so`, renames its own process to `kworker` and an argv tag to hide in `ps`, and settles into the C2 loop, all without a single libc call: the binary issues its syscalls inline, by the hundred. The shared cipher and key place it in the same codebase as the earlier v2 build (`f2671998`), while the `meow` magic and flood set tie both back to the wider Vibenet family.

## Attribution and the dead-drop cluster

We put this build in the Vibenet family on the strength of its code, not its infrastructure. The encrypted-string cipher and key are identical to the earlier v2 build (`f2671998`), marking the two as one codebase, while the `meow` magic, self-staging, and flood set carry the Vibenet lineage. Shared source is the real evidence; everything else is context.

The ENS dead drop drops this build into a small group of families we track that read C2 from the same resolver contract, `0xF29100983E058B709F3D539b0c765937B804AC15`. Resist the urge to read that as a link between operators. It is an ENS Public Resolver deployment on Ethereum mainnet, and ordinary ENS names use public resolver contracts all the time. Sharing it is about as meaningful as two websites sharing a DNS registrar. What actually varies between families is how the record value is encoded: [jackskid](../jackskid/) XORs an IPv6-shaped value byte-wise, other tracked families use other schemes, and this Vibenet build uses the XOR-IPv6 trick above. The encoding here is closer in shape to jackskid's than to the base64 IPv4 lists the v1 Android builds use, which we record as an observation, not a finding. Techniques travel.

A word on the name. `alextyler.eth` is itself a handle from this scene, and naming your dead drop after another member of the DDoS community is, frankly, on brand for it. These crews reference each other constantly, in banners, in domains, in record keys, and which name shows up where tends to track whatever feud or alliance is live that week more than it tracks who actually wrote the bot. We read the name as scene social signaling, not as an operator fingerprint, and we'd caution anyone else to do the same. On delivery: the v1 Android builds ship inside the **MuhHeilong** APK wrapper, staged from hosts like `apk.alextyler[.]st`. That wrapper has been passed around between otherwise-unrelated families, so finding it on a sample is not by itself an operator signature; its primary authorship, though, most likely traces back to this same operator. The two ideas are worth keeping apart: "Heilong" is a name for this family (the 2026 rebrand of the line we track as Vibenet), while MuhHeilong is shared packaging that happens to come from the same hand. We attribute this build on its bot code, not on the wrapper it travels in.

## Detection

### Network indicators

- **TLS fingerprint.** A fixed, browser-like ClientHello: cipher suites `0x1301, 0x1303, 0xc02f, 0xcca8` in that order; supported group x25519 (`0x001d`) only; uncompressed EC point format only; ALPN `h2,http/1.1`; a fixed nine-extension order; no GREASE. The JA3/JA4 is stable across builds and hosts.
- **QUIC fingerprint.** QUIC version 1 only (RFC 9001 initial salt), the same ClientHello, Initial-space AES-128-GCM, and a single HTTP/3 GET using QPACK static-table literals.
- **DoH pattern.** Requests to `1.1.1.1`, `8.8.8.8`, and `9.9.9.9` of the form `GET /dns-query?name=<host>&type=A` with `Accept: application/dns-json` and no User-Agent header.
- **On-chain lookup.** `eth_call` requests to resolver `0xF291...AC15` with selector `0x59d1d43c` and record key `description`, a behavioral signature of this cluster whichever RPC provider answers.
- **C2 ports.** Outbound raw TCP to the web-port set above on hosts that are not CDNs. The C2 handshake is custom, not TLS, so a connection to one of these ports (443 especially) that never negotiates a TLS handshake is itself the tell.
- **Proxy relay.** Once tasked over `0x20`/`0x21`/`0x22`, the bot opens and holds outbound TCP connections to arbitrary operator-supplied destinations and shuttles bytes between them and the C2, a pattern distinct from its flood traffic.

### Host indicators

- A self-staged copy named `.c.so` in a writable mount.
- A process presenting as `kworker` that opens network sockets.
- The string-table key `a35fc8912d764eb0671af38439c25b0e` and the LFSR polynomial `0x80200003` as static signatures.
- The config XOR mask bytes `e1 3c b7 4a` sitting in `.rodata` next to the byte-shuffle masks `ff 00 ff ff` and `00 ff ff ff`.

### On-chain monitoring

Because the C2 list lives in an ENS text record, you can watch `alextyler.eth` / `description` directly and decode each new C2 address with the routine above the moment the operator rotates the record off `127.0.0[.]1`.

## Indicators of compromise

Machine-readable indicators are in the [`iocs/`](iocs/) directory. Summary:

| Indicator | Value |
|-----------|-------|
| SHA-256 | `58f80286ef454e9f12a9ab3e6b04512e8ff67bf02c3d162e3c28dcf3c4a06989` |
| ENS name | `alextyler.eth` (record key `description`) |
| ENS resolver | `0xF29100983E058B709F3D539b0c765937B804AC15` |
| ENS selector | `0x59d1d43c` (`text(bytes32,string)`) |
| Config XOR mask | `0x4ab73ce1` |
| String-table key | `a35fc8912d764eb0671af38439c25b0e` |
| Infura project ID | `9aa3d95b3bc440fa88ea12eaa4456161` (widely reused public ID) |
| C2 ports | 443, 80, 8080, 8443, 9443, 2053, 2083, 2087, 2096, 8880 |
| DoH resolvers | 1.1.1.1, 8.8.8.8, 9.9.9.9 |

The public RPC and DoH endpoints are legitimate third-party services the bot abuses as a resolution channel. We list them for behavioral fingerprinting, not as malicious hosts. No live external C2 IP was recoverable at analysis time, because the dead drop was parked at `127.0.0[.]1`.

## Related research

This is original Deepfield ERT analysis; we are not aware of prior public reporting on this build. The same ENS dead-drop technique and public resolver contract show up in our [jackskid](../jackskid/) writeup, and the delivery side runs through the MuhHeilong APK wrapper and the `libyahu` native payloads shared across this Android ecosystem. Corrections and additional indicators are welcome.

## Edit history

| Date | Change |
|------|--------|
| 2026-06-23 | Initial public release |
| 2026-06-24 | Revision driven by clarifying the family's two codebases: v1 (the `libyahu` Android line) versus v2 (the standalone rewrite, still under development, that this build and the earlier `f2671998` both belong to). Added v1-vs-v2 attack-method and C2 wire-protocol tables, and separated the "Heilong" family name from the shared "MuhHeilong" wrapper. The same deeper analysis corrected several specifics: C2 opcodes (`0x20`/`0x21`/`0x22` are a SOCKS proxy, not attack control; attack is `0x01`), the dual-use proxy / no-libc / numeric-method findings, a real protocol-47 GRE flood, and the web-port set as the C2 connection ports (direct, not Cloudflare-fronted). |
