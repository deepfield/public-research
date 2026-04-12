# Maskify: ENS, IPFS, and a custom mesh network walk into a botnet

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-04-12**

---

## Summary

Maskify is a community-attributed name for a dual-purpose Android botnet: residential proxy and DDoS attack platform. The name comes from the operator's Cloudflare Workers staging domain (`maskify.workers[.]dev`). The Earnify SDK (`io.earnify`) is a Rust-compiled native library distributed via IPFS and updated through the Ethereum Name Service. It bundles a TCP/UDP proxy relay, three DDoS flood modules, and Za Rodinu, a custom P2P mesh network we have not seen documented elsewhere. The operator can push new capabilities to the fleet without modifying the APK. The operator maintains ENS records, pins IPFS binaries across six gateways, and built a Tor-like relay mesh. The QUIC client connecting to all of it skips certificate validation.

## The proxyware model

The Earnify SDK is designed to embed in Android applications as a "monetization SDK." The public API surface (`EarnifySDK.java`) exposes JNI methods that read like any legitimate analytics library:

- `nativeSetConsent(int)` — the app developer calls this with `1` and the device becomes a proxy node
- `nativeGetBytesProxied()` — how much traffic the device has relayed
- `nativeGetSessionsHandled()` — how many proxy sessions it has served


The consent mechanism is architecturally real. Revoking it disconnects from C2 and stops proxying. In practice, `setConsent(1)` is called programmatically by the embedding app. On a device compromised via unauthenticated ADB, the concept of consent is purely syntactic.

The v2 APK (`io.earnify`, 33 KB) is a loader that contains no native code. It downloads `libearnify_sdk.so` from IPFS at runtime. The APK itself is essentially clean. The operator distributes it via ADB exploitation of Android TV boxes and through `maskify.workers[.]dev`.

## A decentralized app, except it's a botnet

The operator built what a Series A deck would call "decentralized edge infrastructure." In practice it is a DDoS botnet.

### ENS for service discovery

The C2 address is published as an Ethereum Name Service text record on `russianaltushkawantsdickinside[.]eth` (key: `proof`). The record value is Base64-encoded, then encrypted with ChaCha20-Poly1305 using the 32-byte key `am-yisrael-chai-from-the-river!!`. The first 12 bytes are the nonce; the remainder is ciphertext plus a 16-byte authentication tag. Decrypted, it contains a binary announcement: a server list (currently `158.94.208[.]131:4433`), the current SDK version (`0.1.7`), per-architecture IPFS CIDs for SDK binaries, and SHA3-256 integrity hashes. The ENS record is, functionally, a signed software update manifest hosted on a blockchain.

### IPFS for binary distribution

The operator hosts the SDK binary (`libearnify_sdk.so`) on IPFS with per-architecture CIDs:

| Architecture | CID | Size |
|-------------|-----|------|
| arm64-v8a | `QmWkJ8KHmAi1JwmWU59bdMsUyDVd9QVq4EUi4ZrqjRxEtu` | 3.6 MB |
| armeabi-v7a | `Qme7K1jXjUkWzP942Upw1YoTd3mp3YJdReXx6oAKb97KQB` | 2.4 MB |
| x86_64 | `Qmf75he7VqaEoUysbZEuKBqRqkTxvrUYD2w92wHghZk1Fi` | 1.4 MB |

The SDK tries 6 IPFS gateways (`ipfs.io`, `dweb.link`, `w3s.link`, `nftstorage.link`, `ipfs.filebase.io`, `gateway.pinata.cloud`), shuffled randomly per attempt, and verifies each download against the SHA3-256 hash from the ENS announcement. It tries three strategies in sequence: streaming with gzip decompression, streaming raw, and full download to memory.

### Ethereum RPC with round-robin failover

The Java layer resolves ENS via 7 public Ethereum RPC endpoints (the Rust SDK adds an 8th, `rpc.flashbots.net`), with an atomic round-robin counter:

```
eth-protect.rpc.blxrbdn.com
eth-mainnet.public.blastapi.io
ethereum-rpc.publicnode.com
eth.merkle.io
1rpc.io/eth
eth.drpc.org
rpc.mevblocker.io
```

Each RPC call constructs a raw HTTP/1.1 POST over TLS with manual SNI configuration. If one endpoint fails, the next in rotation is tried. All seven must fail before resolution gives up.

### Auto-update loop

The `SdkLoader` class checks for updates every 60 seconds, though ENS results are cached for 3 minutes. When the `latestVersion` in the announcement changes: download the new SDK binary from IPFS for the device's ABI (e.g. `android-arm64-v8a`), verify the SHA3-256 hash, replace the `.so` file, and call `Process.killProcess(Process.myPid())` to force-restart and load the new binary. The operator can push new attack methods, protocol changes, or entirely new capabilities without touching the APK. The ENS record is a package registry. The bot polls it like `apt update`, except the registry is on a blockchain and the packages are DDoS tools.

### Country-aware DNS resolution

The SDK selects DNS servers by device locale: Cloudflare (`1.1.1.1`, `1.0.0.1`) as default, Yandex (`77.88.8.8`, `77.88.8.1`) for Russian devices, Tencent DNSPod (`119.29.29.29`, `119.28.28.28`) for Chinese devices. DNS in both countries may not return the record the operator published. The fallback resolvers are more likely to.

The QUIC implementation, meanwhile, sets `InsecureVerifier`, skipping all server certificate validation. The operator maintains an encrypted, authenticated, blockchain-hosted update manifest, and the QUIC client that reads it skips all certificate validation. The priorities are clear, if not entirely consistent. QUIC connections use SNI `earnify-server` for C2 and `zr` for mesh peers, currently sent in cleartext. The rustls build includes ECH support that could obscure them in a future SDK update.

## Za Rodinu mesh

Za Rodinu ("For the Motherland" in Russian) is a custom-built P2P overlay network embedded in the Earnify SDK, not previously documented in public reporting to our knowledge. It does not depend on any P2P framework we could identify in the binary. The `za-rodinu` source tree is a local crate with its own gossip, routing, and forwarding implementations. Source modules visible in the binary: `mesh.rs`, `node.rs`, `gossip.rs`, `routing.rs`, `forward.rs`, `stream.rs`, `protocol.rs`.

The architecture:

- **QUIC transport** between peers, with SNI set to `zr`
- **Gossip-based peer discovery** via seed peers defined in a separate ENS text record on the same domain. The config supports typed seed sources, including DNS TXT resolution. The record was empty when we queried it, suggesting the mesh is not yet active.
- **Peer exchange** messages carrying `node_id` values and `last_seen` timestamps
- **Ed25519-signed service announcements** — the C2 relay registers itself as a "service" within the mesh
- **Multi-hop routing** (`get_next_hop`) — traffic routes through intermediate bots to reach the C2 relay
- **MeshStream** for data transport over the mesh


This creates three independent layers of C2 resilience: blockchain-based discovery (ENS), decentralized payload hosting (IPFS), and a P2P mesh relay (Za Rodinu). Taking down any one layer leaves two intact. The operator built redundancy on the assumption that compute is free when it belongs to someone else. The Pied Piper architecture, realized on a fleet of Android TV boxes that did not opt in.

## The Rust SDK

The native library `libearnify_sdk.so` (3.6 MB arm64, 2.4 MB armv7) is compiled from Rust with Android NDK clang 18.0.3. We identified these crates in the binary: quinn 0.11.14 (QUIC), rustls (TLS), chacha20poly1305, ring (crypto), tokio 1.50 (async runtime), scc (concurrent data structures). The current version is `0.1.7`. In crypto parlance: still early. The binary still contains `"IPFS seed resolution not yet implemented"` — the operator shipped a custom P2P overlay network before finishing the backlog. Move fast, break other people's things.

## DDoS attack methods

Three flood modules — `flood_tcp`, `flood_tls`, `flood_udp` — compared to the 8-11 methods in other families we have documented ([CECbot](../cecbot/report.md): 11, [Drifter](../drifter/report.md): 8). The operator trades method breadth for template flexibility.

### Template-push architecture

The C2 tells the bot what to hit and how hard (Flood command, port 4433). What the bot actually sends in each connection comes from port 6969, where the C2 pushes pre-built HTTP request templates via raw TCP. The operator can rotate payloads independently of attack commands. We observed five distinct templates:

| Template | Content |
|----------|---------|
| TLS+HTTP | TLS ClientHello followed by HTTP GET, Chrome 108 User-Agent |
| HTTP/1.1 GET | Chrome 108 UA, header `X-Nextjs-Request-Id: poop1234` |
| HTTP/1.0 GET | Chrome 108 UA |
| HTTP/1.1 | Empty User-Agent with TLS cipher suite blob |
| HTTP/1.0 | Chrome 108 UA (variant) |

The templates consistently use a Chrome 108 User-Agent, released December 2022. The botnet negotiates HTTP/3 via QUIC but presents a browser version from three and a half years ago. The templates also include a `X-Nextjs-Request-Id: poop1234` header, which narrows the operator demographic somewhat.

### Target blocklist

The `filter` module blocks proxy relay connections to 10 specific ports and all RFC1918/bogon IP ranges. DDoS floods bypass this filter entirely.

| Port | Service |
|------|---------|
| 22 | SSH |
| 23 | Telnet |
| 1386 | — |
| 1398 | — |
| 3222 | — |
| 5555 | ADB |
| 5858 | — |
| 12108 | — |
| 13589 | — |
| 63002 | — |

Port 5555 is ADB. Residential proxy services that expose ADB on their exit nodes are [how these devices get compromised in the first place](https://synthient.com/blog/a-broken-system-fueling-botnets) — a proxy customer connects to `0.0.0.0:5555` through the relay, which resolves to the exit device's own ADB. The port blocklist (5555) and the bogon IP blocklist (127.0.0.0/8, 0.0.0.0/8) work together to close this path. The operator is patching the vulnerability they rode in on.

The C2 assigns per-device daily bandwidth caps for proxy relay traffic (the `tunnel` module tracks bytes; the `flood` modules do not). The server sets the cap during registration, suggesting it may tune per-device or per-customer. The bot enforces it locally and disconnects when the limit is reached.

## C2 protocol

The v2 C2 protocol runs over QUIC (UDP port 4433) with TLS 1.3. We decoded nine control message types:

| Wire type | Name | Function |
|-----------|------|----------|
| `0x00` | Registration | GeoInfo (country, city, region), bandwidth cap, optional strings |
| `0x01` | Tunnel | Open TCP/UDP proxy relay to target host:port |
| `0x02` | Stop | Disconnect |
| `0x03` | Heartbeat | Keepalive |
| `0x04` | Config update | Key-value pair |
| `0x05` | DNS query | Domain name for resolution |
| `0x06` | Boolean flag | Single-byte toggle |
| `0x07` | Flood | Attack: method (0=TCP, 1=TLS, 2=UDP) + concurrency + duration + target + port |
| `0x08` | StopFlood | Cancel active flood by u32 attack ID |

Messages are length-prefixed (4-byte big-endian) with the wire type as the first payload byte. Strings are encoded as little-endian 16-bit length prefix followed by UTF-8 data. Optional fields use a presence byte (`0x00` = None, `0x01` = Some).


## Indicators of compromise

Hashes, IPs, domains, IPFS CIDs, and QUIC SNIs are in [`iocs/`](iocs/).

## References

- Ben / Synthient ([@deobfuscately](https://x.com/deobfuscately/status/2041151620486987898)), "Earnify // Maskify Botnet" — community attribution linking Earnify SDK to the Maskify name, with loader domain and SDK infrastructure IOCs
- [Aisuru ecosystem report](../reports/2026-03-20-aisuru-ecosystem.md) — the broader ADB TV box battlefield (Nokia Deepfield ERT, March 2026)
- [Drifter report](../drifter/report.md) — independent operator on the same attack surface, for architectural contrast (Nokia Deepfield ERT, March 2026)
