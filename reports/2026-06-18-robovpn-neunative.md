# A free download and a botnet: RoboVPN, Neunative, and the Vo1d/Popa backend

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-06-18**

**Right of reply:** Ahead of publication, Nokia Deepfield ERT emailed RoboVPN a request for comment, summarizing the findings below and inviting correction of any factual errors. The site publishes no [`security.txt`](https://www.rfc-editor.org/rfc/rfc9116) and no dedicated security contact, so we wrote to its only published contact (a support address) and an abuse address. As of publication, we have not received a response.

---

## Summary

RoboVPN is a commercial VPN published by Cyberkick Ltd., distributed through its website at `robovpn[.]com`, with the Windows installer served from `download.robovpn[.]com`. The site's download page advertises clients for nearly everything: Windows, macOS, Android, iOS, Linux, routers, smart TVs, game consoles, browser extensions. As of this writing only one of them actually downloads. The Windows app is live; every other tile, Android included, reads "This device will be available soon." This analysis is therefore of the Windows client, the only one currently shipping. It is functional: it runs a WireGuard tunnel to `*.vpns.robovpn[.]com` (RoboVPN also advertises IKEv2), a country selector fetches server lists from an AWS API Gateway, and a Firebase Realtime Database handles remote config. There is a speed test. There are animated GIFs. If you squint past the WiX installer metadata, it looks like a product.

Bundled in the same installer, registered as a NuGet dependency, and activated whenever the VPN is *not* connected, is Neunative: a residential-proxy SDK that turns the user's machine into an exit node for third-party traffic. When the VPN disconnects, or the app simply sits idle after login, the SDK waits 30 to 90 minutes, connects to a load balancer at `lb.gmslb[.]net`, receives a list of relay servers on rotating front domains (`viki-play[.]com`, `star-layer[.]com`, and likely others), and starts accepting tunnel requests that resolve arbitrary public hostnames through the user's connection. Connecting the VPN shuts it back off, so the relay always exits through the user's own residential IP, never through RoboVPN's servers. The user gets a VPN; third parties get to route traffic through that same connection whenever the VPN is off.

RoboVPN's Terms & Conditions, shipped in the installer as the license RTF the setup wizard displays, *do* disclose a "peer" model: the user shares "your device's resources, mainly its IP address, in order to serve other members of the Company's network," with a stated "option to opt-out … at any time." The binary provides no such opt-out (see [Disclosure: terms vs. behavior](#disclosure-terms-vs-behavior) below), and what it does inverts what the terms imply. The exit node is live precisely when the user is *not* shielded by the VPN, and it forwards arbitrary third-party traffic to arbitrary public hosts, well past "sharing resources to serve other members of the network."

The analysis is entirely static: MSI unpacking, .NET single-file bundle extraction, ILSpy decompilation to near-original C#, and Ghidra disassembly of the native x64 proxy DLL. Live registration requests confirmed the response format and the relay server fleet. No malware was executed.

## Why a DDoS team is documenting a proxy SDK

Nokia Deepfield ERT tracks DDoS botnets, not residential-proxy software, and a commercial VPN that bundles a proxy SDK would normally fall outside our beat. It is here because the two categories have stopped being separate. As [Synthient documented](https://synthient.com/blog/a-broken-system-fueling-botnets), a vulnerable proxy SDK is itself an initial-access vector: a customer who tunnels to a node's own `0.0.0.0:5555` reaches the exit device's ADB daemon and recruits it into whatever the operator is building, DDoS botnets included (the mechanism, in our binary, is [Stage 2: relay](#stage-2-relay) below). The proxy node is not just an abuse surface for other people's traffic; it is a foothold on the device itself.

Synthient, with Infoblox, [publishes the loaders](https://synthient.com/blog/who-are-the-victims-of-residential-proxies) that LAN exploitation pushes through Popa nodes, and several are hosts we already track delivering botnets: `117.55.203[.]189/jewishgoldowner/arm7` ([Potassium](../potassium/report.md)), `195.178.110[.]204/adb` (a Gafgyt/NeTiS loader), and `83.168.110[.]191` serving `iran.*` (IranBot). The exit-node-to-foothold path is observed traffic on the network Neunative joins.

There is a direct DDoS angle too: Qurium Media Foundation [traces](https://www.qurium.org/forensics/the-future-of-residential-proxies/) the Layer-7 attacks on the independent-media outlets it protects back to commercial proxy/VPN providers, and argues residential-proxy markets, Android supply-chain malware, and DDoS botnets now feed one another. A proxy SDK shipped in a consumer VPN is a node in that economy.

Neunative sits on exactly that fault line, with one scoping caveat: we reverse-engineered the Windows client. The destination filter we dissect below, the `0.0.0.0/8` gap and the missing port block, is in the shared native SDK, but its high-impact form, where `0.0.0.0` maps to loopback and ADB answers on `:5555`, is an Android outcome. We have not analyzed RoboVPN's Android build directly; it is listed on the RoboVPN website but not currently downloadable. We do not need it to place the SDK on Android: the PDB path is rooted in a tree literally named `android-native-sdk` (below), and the same director (`gmslb[.]net`) already fronts the Vo1d/Popa proxy on its Android TV fleet (XLab counted ~1.6 million in March 2025, likely more now), the exact `0.0.0.0:5555` population. A proxy SDK with a weak destination filter, shipped at scale, is upstream of the botnets we do track.

## Components

The MSI contains a .NET 6 self-contained single-file bundle (57 Deflate-compressed assemblies) and four native x64 DLLs. The bundle packs the entire .NET runtime, the application, its dependencies, and the proxy SDK into a single 12 MB executable. Scanning the raw EXE for strings finds almost nothing; the assemblies must be decompressed first.

| Component | SHA-256 (prefix) | Role |
|-----------|-----------------|------|
| `RoboVPN.msi` | `ea40641a…` | Installer (Cyberkick Ltd., WiX 3.14, built 2024-03-31) |
| `RoboVPN.dll` | `d7d37ce6…` | WPF application (UI, connection lifecycle) |
| `RoboVPN.Connector.Core.dll` | `4098f6a4…` | VPN connectors, auth, `ProxyService` |
| `NeunativeNG.dll` | `74beab8a…` | .NET shim over native SDK (NuGet `NeunativeNG 8.0.36`) |
| `NeunativeWin.dll` | `6f686ba6…` | Native x64 C++ proxy SDK (598 functions) |
| WireGuard tunnel + wintun | — | The VPN that actually VPNs |

The Neunative SDK ships as a NuGet package (`NeunativeNG/8.0.36`), bundling its .NET wrapper and a platform-specific native binary under `runtimes/win-x64/native/NeunativeWin.dll`. The dependency is declared in `RoboVPN.deps.json` next to Newtonsoft.Json and the AWS SDK, listed with the same indifference: a name, a version, a hash. Nothing in the manifest marks it as the component that turns the user into an exit node; it is presented as routine plumbing, indistinguishable from a JSON library. Whether that placement was contemplated or accidental, Cyberkick's own Terms answer (see [Disclosure: terms vs. behavior](#disclosure-terms-vs-behavior) below).

## Activation

The .NET layer decompiles to near-original C# (the PDB ships with the app). In `RoboVPN.Connector.Core.Proxy`:

```csharp
public static void OpenPeer()
{
    int val = new Random().Next(30, 91) * 60;
    Neunative.setParameterInt("start_delay_sec", val);
    Neunative.startNeuNative("RoboVPN");
}
```

`OpenPeer()` is *not* called on connect. It is called from `DisconnectedDisplay()`, the idle "Quick connect to" screen (session timer off), which the app renders on Disconnect, on Cancel, and after login (`toMain()`). `ClosePeer()` → `stopNeuNative()` is called from `Connect()`, right after the tunnel state changes. So the mapping is the reverse of the intuitive one, [pure George Costanza](https://en.wikipedia.org/wiki/George_Costanza): connecting the VPN stops the proxy; disconnecting (or idling) starts it.

This is consistent with a deliberate design choice. The WireGuard tunnel is full-tunnel (`AllowedIPs = 0.0.0.0/0`), so a relay running while the VPN is up would exit through RoboVPN's own datacenter servers, which is useless as a *residential* proxy and self-attributing. Running the relay only while the VPN is down guarantees it exits through the user's real residential IP. The free VPN is, in effect, a switch that pauses the user's own exit-node duty.

The delay, a random interval between 30 and 90 minutes, is generated fresh each time the proxy starts (i.e., each time the VPN goes idle or disconnects). If you install RoboVPN, connect, and capture traffic for half an hour, you will see WireGuard and nothing else. The proxy is paused while you're connected. Disconnect and walk away, and 30 to 90 minutes later the relay comes up. Either way, a casual analysis window sees a clean VPN. Write "the application is clean" in your report at that point, and you will be wrong. Thirty minutes is longer than most people will stare at Wireshark before deciding nothing is happening.

The native `NeunativeWin.dll` exports six functions, surfaced through the `NeunativeNG.dll` shim as `DllImport`s:

```
startNeuNative(string publisherName)
stopNeuNative()
setParameterString(string key, string val)
setParameterInt(string key, int val)
setParameterBool(string key, bool val)
setParameterLong(string key, long val)
```

The publisher name is an affiliate tag, the kind of string you'd pass to an analytics SDK to attribute installs. A single SDK serving many publishers is the tell: this looks like a platform that rents proxy capacity to embedding publishers. RoboVPN is one such publisher. The question is how many others there are.

## Disclosure: terms vs. behavior

The proxy is not entirely undisclosed. The installer ships RoboVPN's Terms & Conditions as the license RTF the WiX setup wizard displays, and Section 3 ("The Services") describes a peer model:

> As part of the use of the Services, you may have the option to become a "peer" in the Company's network ("Peer"). This would basically mean that you will share your device's resources, mainly its IP address, in order to serve other members of the Company's network. You will have the option to opt-out from serving as a Peer at any time. However, please note that in such a case, you may not be able to access the full features of the Service.

So the existence of IP-sharing is disclosed, in the fine print. What the binary does diverges from the terms in three ways:

- **No opt-out.** As shown above, `OpenPeer()` fires unconditionally from the idle/disconnected paths and from `toMain()`; its body is only the 30–90 minute delay plus `startNeuNative("RoboVPN")`. The SDK is never passed a consent flag (the shim exposes `setParameterBool`, unused), and the Settings screen offers only language, account email, billing, sign-out, and exit. No peer/sharing toggle exists. The only code that stops relaying is `ClosePeer()`, from `Connect()`. That leaves an operator two ways to argue the promised "opt-out at any time" is real, and the wiring kills both. *"Just don't use the VPN"* is backwards: not using it is exactly when the device is an exit node, so idling is the on state. *"Connecting is the opt-out"* mistakes a pause for a choice: `OpenPeer()` re-arms the moment you disconnect, so the only way to hold it is to keep a full-tunnel VPN running around the clock; and Section 3 forecloses that reading anyway, since it says opting out "may" cost you "the full features of the Service," while connecting delivers them in full. The state that strips the VPN's protection (disconnecting) is the one that switches the proxy on. The control Section 3 promises is not in the build.
- **Scope.** "Share your device's resources … to serve other members of the Company's network" reads like a peer-to-peer arrangement among RoboVPN users. The relay actually resolves and connects to arbitrary public hostnames supplied by the server and forwards third-party traffic to whoever booked the route. Cyberkick could argue the paying proxy customers *are* those "other members," and that may even be the most accurate reading of the clause. It is just not the one anyone clicking "I agree" on a VPN installer would land on. "Members," in this telling, is doing the work of "paying customers who rent your residential IP."
- **Omissions.** The terms say nothing about the delayed activation, the relay fleet, the arbitrary-destination tunneling, or that the same director (`gmslb[.]net`) is a hardcoded C2 for the Vo1d/Popa botnet (below). They also never name the component doing the sharing: "Neunative" appears nowhere in the document, nor does any relay operator, proxy reseller, or affiliate. The IP-sharing is attributed only to "the Company's network," even though Section 11 lets Cyberkick assign its rights to unnamed third parties. The opt-in phrasing ("you *may have the option* to become a peer") is also at odds with on-by-default activation.

The disclosure exists; the implementation removes the control it promises and exceeds the purpose it describes.

## Native SDK architecture

`NeunativeWin.dll` is a 194 KB x64 C++ binary with 598 functions. TLS is via Windows Schannel; there is no bundled crypto library. There is one hardcoded server, no fallback hosts, no embedded keys. Confidentiality is TLS alone. The whole apparatus depends on one domain continuing to resolve.

### Stage 1: registration

The SDK contacts `lb.gmslb[.]net:443` (TLS) with an HTTP GET that reads like a browser doing its best impression of itself:

```http
GET /regdev?usr=<uuid>&userid=<uuid>&dev_ip=<ip>&sdkv=8.0.36&inst=<uuid> HTTP/1.1
User-Agent: SDK
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,
        image/avif,image/webp,image/apng,*/*;q=0.8,
        application/signed-exchange;v=b3;q=0.7
Connection: keep-alive
Host: lb.gmslb.net:443
```

The `Accept` header is pixel-perfect Chrome: the AVIF, the WebP, the quality factors, all correct. The `User-Agent` is `SDK`: [how do you do, fellow kids](https://knowyourmeme.com/memes/how-do-you-do-fellow-kids). Someone spent real effort getting the Accept header exactly right, then set the User-Agent to a three-character string that gives the disguise away to anyone who reads it. The two headers were written by people with different threat models, or by one person on two different days.

The `usr` and `userid` UUIDs are generated once with `UuidCreate` and persisted in the registry at `HKCU\Software\Neunative` under `_uuid`; the `inst` UUID identifies the install. The `dev_ip` field is sent but ignored by the server, which geolocates the source IP itself, a server-side decision that makes client-side IP spoofing pointless.

The response (nginx/1.20.1, Express):

```json
{
  "dev_asn": "39351",
  "dev_city": "FrankfurtamMain",
  "dev_country": "DE",
  "dev_state": "Hesse",
  "dev_ip": "<source IP>",
  "peer_servers": [
    "s1852.viki-play.com:6000",
    "s254.viki-play.com:6000",
    "s269.viki-play.com:6000",
    "..."
  ],
  "mng_extra": ""
}
```

The server determines the device's country, city, state, and ASN from its egress IP and returns this as the exit node's catalog entry: the "location" that proxy customers select when routing traffic. A user in Frankfurt becomes a German exit. The geolocation is not approximate; it is the product specification. (The sample above is from one of our probes, so its `dev_asn` reflects our datacenter egress, not a residential exit node.)

`peer_servers` lists several dozen relay hostnames; the count varies with the probe's source IP (35 in one, roughly 80 in another). Each call returns a geo-relevant subset; enumerating the `sN` pattern directly reveals the full fleet of ~360 relays (see [Relay fleet](#relay-fleet)). `mng_extra` is empty in every response we observed. A management field with no management yet is an invitation, not a reassurance.

### Stage 2: relay

For each peer server, the SDK opens a TLS connection on port 6000 and speaks a proprietary binary protocol. Each message is framed with a 4-byte big-endian type code, dispatched through a factory function; the fields inside carry 4-byte tags, with lengths implicit in the type class. The RTTI class names lay the scheme out: `SdkProtocolMessage{Long,Int,String,Byte,Blob}TLV` for the scalar fields, plus a `SdkProtocolMessageTLV<std::list<ISdkProtocolMessageTLV*>>` container that nests them. The message types, recovered from the factory and RTTI symbols:

| Opcode | Message | Payload |
|--------|---------|---------|
| `0x5060` | Register | Device registration |
| `0x7070` | RegisterResponse | Byte (`0x9080`) |
| `0x9010` | Ping | Long (`0xa020`), keepalive |
| `0xa070` | OpenTunnel | Long `0x70a1`=tunnel ID, String `0x70a2`=target host, Int `0x70a3`=target port |
| `0xc000` | TunnelMessage | Relayed payload bytes |
| `0xcccc` | CloseTunnel | Long `0xc111`=tunnel ID |
| `0xdddd` | Goodbye | — |

XLab named these message types from the Popa side as a numbered 1–8 taxonomy; the wire encoding above (exact opcodes and TLV tags) is the Windows build's, recovered from RTTI. Same backend (see [The Vo1d connection](#the-vo1d-connection)), documented here at the byte level.

Each `OpenTunnel` spawns a dedicated worker thread (`_beginthreadex`), logged as `Tunnel%llu`. The worker resolves the server-supplied target hostname with `getaddrinfo`, connects, and relays bytes bidirectionally between the peer server and the target. The proxy customer picks a destination. The user's machine dials it.

Before connecting, the resolved target IP is checked against RFC1918 (`10/8`, `172.16/12`, `192.168/16`), loopback (`127/8`), link-local (`169.254/16`), and multicast/reserved (`≥224`). If the target is private, the address is nulled and no connection is made. The filter keeps proxy customers out of the user's LAN; it does nothing to keep them off the user's public IP. The protection runs one direction only: it shields the local network, not the internet connection that is the whole point of the proxy.

The filter is a denylist, not an allowlist: everything it doesn't enumerate is permitted. The author enumerated six ranges and missed two that matter. The first is `0.0.0.0/8`, which on Linux and Android maps to the loopback interface, functionally identical to the `127.0.0.1` they *did* block. An `OpenTunnel("0.0.0.0", 5555)` request would pass every check and connect to the exit device's own ADB daemon: the exact exploitation path [Synthient documented](https://synthient.com/blog/a-broken-system-fueling-botnets), and on this network not a latent one: [their Popa telemetry](https://synthient.com/blog/who-are-the-victims-of-residential-proxies) ranks `:5555` the third-busiest outbound port across the fleet. The second miss is CGN shared space (`100.64.0.0/10`), which on carrier networks can reach other subscribers. And there is no port blocklist at all. By contrast, [another operator on the same device population](../maskify/report.md) blocks both `0.0.0.0/8` and port 5555 specifically. The gap is not ours alone to find: Plume reversed the Android build and hit the same `0.0.0.0`→loopback→ADB path (`isAnyLocalAddress` left permitted), and [Spur](https://spur.us/blog/residential-proxy-lateral-movement-risk) found it across "nearly every residential proxy service" it tested, an industry pattern of which Neunative's denylist is one instance.

### Bandwidth qualification

A `BandwidthManager` measures and limits throughput. On the .NET side, the app downloads a 5 MB test file (the `NSpeedTest` library) and passes the result to the SDK. A residential line that can't sustain throughput is worthless as a proxy. The SDK vets the node the way a job interview vets a candidate: before offering the position, not after.

### Telemetry

`StatusUpdate` messages report the publisher tag, SDK version, `timeSinceServerConnect`, and `timeSinceStart`: the uptime metrics of a workforce that doesn't know it's employed.

## What is (and isn't) in the binary

We swept the full binary: all 598 functions traced architecturally, plus a capability scan against the import table and decompiled output. The SDK cannot run commands (`CreateProcess`, `ShellExecute`, `WinExec`, and `system` are all absent), cannot inject into other processes, and cannot download anything on its own (raw Winsock and Schannel only, no WinINet, no WinHTTP). It does not install persistence; the VPN's own WireGuard service handles startup, and the SDK only stores a UUID in `HKCU\Software\Neunative`. There is no custom cryptography, just TLS. The two `IsDebuggerPresent` calls are CRT/ATL boilerplate, not anti-analysis. There is no inbound listener; the relay is entirely outbound.

The SDK's scope is narrow: it does [one thing, well](https://en.wikipedia.org/wiki/Unix_philosophy). It registers the device with a proxy director, receives tunnel requests from relay servers, resolves and connects to the requested targets, and relays the traffic. Nothing else is implemented. No sprawl, no dead code, no half-built features: just a tidy implementation of exactly the one thing you would not want it to do.

## Relay fleet

The hostnames in `peer_servers` are rotating front domains. For a single fleet the director returns both `sN.viki-play[.]com:6000` and `sN.star-layer[.]com:6000`; the server numbers overlap (`s269`, `s254`, `s1740`, `s1884`), and passive DNS confirms the IPs behind them are identical:

| Server | `viki-play[.]com` | `star-layer[.]com` |
|--------|------------------|-------------------|
| `s269` | `186.190.215[.]121` | `186.190.215[.]121` |
| `s254` | `172.99.188[.]236` | `172.99.188[.]236` |
| `s1884` | `51.178.118[.]130` | `51.178.118[.]130` |
| `s1740` | `51.77.236[.]134` | `51.77.236[.]134` |

The `sN` identifier and IP are the stable node identity. The domain is disposable. Blocking `viki-play[.]com` redirects traffic to `star-layer[.]com` or whatever the next front is. Durable detection requires matching on port 6000 and the relay IP set.

The domain rotation is deeper than two names. Reverse DNS on a single relay IP (`38.114.120[.]39`, server `s205`, GTHost) reveals 30 front domains all pointing at it:

```
byte-buff.com     swift-zip.com          yoursfind.com     sdkmob.org
novel-layer.com   zen-tava.com           house-spirit.com  byte-armor.com
link-flux.com     tera-home.com          pulse-vol.com     net-echo.com
shield-sky.com    world2trust.com        star-layer.com    pixellog.io
viki-play.com     cool-horizon.com       ginuary.com       fast-mob.com
litics-net.com    nova-lan.com           sky-borders.com   grid-push.com
nice-protect.com  flexible-networks.com  worker-net.com    gmslb.net
earth2trust.com   zync-stream.com
```

All 30 are on Cloudflare, spread across two accounts: `asa`/`david` (5 domains, including the director `gmslb[.]net` and the primary fronts `viki-play[.]com` and `star-layer[.]com`) and `ariella`/`jake` (25 domains). Splitting them this way is a takedown hedge: a single-account suspension removes either 5 of the 30 fronts or 25, never the whole set. The naming follows a pattern: compound English words suggesting legitimate tech products (`shield-sky`, `grid-push`, `flexible-networks`). Domain registrations are cheap. The operator bought 30 of them the way someone buys burner phones: in bulk, expecting to lose some.

The presence of `s205.gmslb[.]net` in this list is notable: `gmslb[.]net` serves double duty as both the director (`lb.gmslb[.]net:443` for `/regdev`) and a relay front (`sN.gmslb[.]net:6000`). The infrastructure is not as cleanly layered as the protocol suggests.

### Enumerating the fleet

The highest server label, `s1884`, suggests a fleet of nearly 1,800 relays. It isn't: the numbering is sparse, and counting the live nodes deflates that figure roughly fivefold. The count is clean because the front domains carry no wildcard record (a bogus label like `s999999.viki-play[.]com` returns NXDOMAIN), so only provisioned `sN` records resolve, and the space can be swept against the domains' authoritative Cloudflare nameservers with no recursive-resolver caching in the way. That sweep returns 359 live nodes across `s2`–`s1884`, about 19% of the range. The real fleet is roughly 360 relays, not the ~1,800 the top label implies. `s1884` is a high-water mark, not a census. `viki-play[.]com` and `star-layer[.]com` return byte-identical A records for every one of the 359 (the other fronts match on spot-checks), confirming they are aliases of a single fleet, not separate infrastructure.

Two wrinkles complicate the count. The operator's labels are inconsistently padded: most are bare (`s1740`), but a transitional batch is zero-padded (`s01687` resolves; `s1687` does not), so both spellings have to be probed or the sweep silently undercounts. And the 359 nodes resolve to 370 distinct relay IPs: 11 nodes in the `s1680`–`s1702` batch are dual-homed, returning two A records each. The full list is in [`popa/iocs/relays.csv`](../popa/iocs/relays.csv).

The fleet is entirely datacenter. Every one of the 370 relay IPs resolves to commercial hosting: OVH (259), GTHost/GLOBALTELEHOST (74), Hetzner (30), and Akamai/Linode (7), across France, Canada, the US, Germany, and the Netherlands. None are residential. This corrects the intuitive reading of the architecture: the `sN.*:6000` servers are the relay/coordination tier, not the exits. The residential exits are the enrolled devices themselves: RoboVPN installs, and the Vo1d Android TVs on the shared backend (below), which connect *outbound* to these datacenter relays and never appear in the `sN` namespace. (Take `s269` → `186.190.215[.]121`: a LACNIC-registered block that ipinfo geolocates to Zurich, reverse DNS `121-215-190-186.clients.gthost[.]com`, AS63023. Registry says Latin America, geolocation says Switzerland; either way it is GTHost datacenter, not a residential exit. The exits are the victims, not anything resolvable in DNS.)

This relay tier is independently corroborated. In June 2026 Synthient, with Infoblox, [published](https://synthient.com/blog/who-are-the-victims-of-residential-proxies) a sample of "Popa C2 servers" ([IoCs on GitHub](https://github.com/synthient/public-research/blob/main/2026/06/WhoAreTheVictimsOfResidentialProxies.md)) using the identical `sN.{byte-buff,house-spirit,novel-layer,star-layer}[.]com:6000` pattern over the same `s2`–`s1884` range. All 109 of their published server labels fall inside our enumerated 359, a 100% subset, tying this fleet to the Vo1d/Popa botnet from a second, independent vantage point (see [The Vo1d connection](#the-vo1d-connection)).

### Director infrastructure

`lb.gmslb[.]net` resolves to 10 IPs, all OVHcloud:

```
51.38.222.163   51.75.62.214    51.75.169.138   51.75.169.155
91.134.11.137   91.134.98.159   91.134.98.229   145.239.29.238
162.19.237.9    162.19.239.144
```

The hosts give up nothing else: no reverse DNS, no web interface. The director answers `/regdev` with a list of relays and does nothing more, a load balancer pared down to a single question and a single answer, with no surface left over to poke at.

## The Vo1d connection

`gmslb[.]net` is not new to public reporting. The Vo1d botnet was first disclosed by Dr.Web in September 2024 (~1.3 million infected Android TV boxes across ~200 countries; infection vector undetermined). In a March 2025 follow-up, XLab (Qianxin) [tracked it](https://blog.xlab.qianxin.com/long-live-the-vo1d_botnet/#popa-c2) to ~1.6 million devices across 226 countries and documented a residential-proxy plugin called Popa that hardcodes nine C2 domains. `gmslb[.]net` is one of them.

Underneath, the two are the same system. Popa contacts `lb.<C2>:5002/devicereg` (vs. Neunative's `lb.gmslb[.]net:443/regdev`), receives a `peer_servers` (or `servers`) list in the response, and speaks a TLS tunnel protocol with the same message taxonomy: Register, Register Reply, Ping/Pong, Open Tunnel, Tunnel Status, Tunnel Message, Close Tunnel. The port and path differ. The architecture does not.

| | Neunative (this report) | Popa (XLab/Vo1d) |
|---|---|---|
| Director endpoint | `lb.gmslb.net:443/regdev` | `lb.<C2>:5002/devicereg` |
| Response field | `peer_servers` | `servers` or `peer_servers` |
| Tunnel protocol | TLS, 7 message types | TLS, 8 message types |
| C2 domains | `gmslb.net` (sole hardcoded) | `gmslb.net` + 8 others |
| Distribution | NuGet SDK in commercial apps | Plugin in botnet malware |

This means the Neunative SDK that ships inside RoboVPN and the Popa plugin that runs on Vo1d's compromised Android TVs are different clients for the same proxy backend. The relay fleet (`sN.{viki-play,star-layer,...}[.]com:6000`) serves both. A RoboVPN user who installed a free VPN, and a compromised Android TV box whose owner has no idea it's infected, share the same proxy backend: same director, same relay fleet, same customers' traffic. It is one workforce recruited through two channels: a free download and a botnet.

The same backend has since been reached independently from three other directions. Plume Security Labs' May 2026 *SuperProxy* analysis reverse-engineered the Android build, Popanet (`io.popanet`), bundled in the Cyberflix TV app on SuperBox streaming devices, and found the same `lb.gmslb[.]net` director, port 6000, relay fronts, and TLV protocol; so Neunative (Windows), Popanet (Android), and Vo1d's Popa plugin are three builds of one SDK. Qurium Media Foundation [reaches the same RoboVPN/`gmslb[.]net` link](https://www.qurium.org/forensics/finding-popa) from the forensic side and attributes the network to the NetNut/Alarum proxy group that owns Cyberkick. And Synthient [reaches it from Popa's egress](https://synthient.com/blog/who-are-the-victims-of-residential-proxies), with a published relay list that falls inside the fleet we enumerated (see [Relay fleet](#relay-fleet)). Malware C2 (XLab), a bundled SDK (this report), Android RE (Plume), egress (Synthient), and forensics (Qurium) describe one network.

XLab notes that the relationship between Vo1d and the Mzmess plugin framework (which delivers Popa) "remains unclear — no direct ties have been found at the sample or infrastructure level." The Neunative SDK adds a data point: `gmslb[.]net` is not only used by malware; it is also shipped in a commercial VPN by a registered company, as a NuGet dependency. The organizational relationship between Cyberkick, the Neunative SDK provider, and the Vo1d/Popa operators is not established by this analysis. The infrastructure overlap is observable; the business relationship behind it is not.

Popa hardcodes eight C2 domains besides `gmslb[.]net`, and resolving them adds a wrinkle the protocol overlap alone does not. Seven of the eight are sinkholed: `phonemesh[.]org`, `linkmob[.]org`, `peercon[.]org`, `phonegrid[.]org`, `lbk-sol[.]com`, `sklstech[.]com`, and `kyc-holdings[.]com` now resolve into a sinkhole pool. The eighth, `safernetwork[.]io`, is plain NXDOMAIN. That the takedown community already identified these as botnet C2 and pointed them at a sink is independent confirmation they were malicious; legitimate VPN load balancers don't get sinkholed. What has *not* been sinkholed is `gmslb[.]net`: the one director domain that doubles as a commercial VPN's proxy backend is still live, still on OVH, still answering `/regdev`, while the malware-only C2s around it have been pulled.

## The PDB path that answers the Android question

The native DLL's PDB path is recorded in the PE debug directory (CodeView RSDS record; recover with `rabin2 -I`, `dumpbin /headers`, or peview):

```
\\VBOXSVR\shared\android-native-sdk\NeunativeWin\NeunativeWin\build\x64\Release\NeunativeWin.pdb
```

(CodeView signature `BA74BC3713F5473B9271F55A4377E6E53` as emitted by `rabin2`: the 32-hex-digit PDB GUID plus a trailing age digit, a usable pivot for sibling builds or a leaked matching PDB.)

The build environment is a VirtualBox guest with a shared folder. The shared folder is named `android-native-sdk`. The Windows DLL is built inside a directory tree designed for an Android native SDK. The Firebase database is named `robovpn-windows-default-rtdb`, which makes the existence of a `robovpn-android-default-rtdb` hard to doubt. Same build system, different platform targets.

When the Android RoboVPN APK is recovered, the first indicators to check are `lb.gmslb[.]net` in network traffic and a `libNeunative*.so` in the APK's native libraries. The protocol, the publisher tag, and the relay fleet should be identical.

## Connection chain

```
User's machine  (mutually exclusive states)
  │
  ├─ VPN CONNECTED ─ WireGuard full tunnel → *.vpns.robovpn[.]com   ← proxy PAUSED (ClosePeer)
  │
  └─ VPN OFF / IDLE ─ Neunative SDK starts after 30–90 min delay
       │
       │  TLS:443  GET /regdev?usr=…&sdkv=8.0.36
       ↓
     lb.gmslb[.]net                                         ← director (10× OVH)
       │
       │  { dev_country: "FR", peer_servers: [...] }
       ↓
     sN.{viki-play|star-layer|…}[.]com:6000                 ← relay fleet (~360 datacenter relays)
       │
       │  OpenTunnel(target_host, target_port)
       ↓
     Arbitrary public target                                ← user's real residential IP = exit node
```

The two never run together: connect the VPN and the proxy pauses; turn it off and the proxy takes over. The exit node is live in exactly the window the user reads as "off," and it always exits through their real residential IP, never through RoboVPN's servers.

Two front doors, one backend: Vo1d's Popa on the [AOSP](https://source.android.com/) devices that never had a say, and Neunative inside a free Windows VPN for the people who went looking for privacy. We took apart the Windows build; it dials the same director, on the same relay fleet, as Popa. The relays are datacenter; the exits are the people. The backend never asks how a device was enrolled, by a EULA or by malware, and serves it the same relay list either way. Consent is the line between a proxy service and a botnet, and it is the one thing this backend never checks. The protocol is documented and `gmslb[.]net` is still answering `/regdev`; the only thing left to measure is how big it is.

## Indicators of compromise

Full SHA-256 hashes are listed below, followed by network and host indicators. The complete relay fleet and the shared Popa/Vo1d backend indicators are published as CSVs in [`popa/iocs/`](../popa/iocs/).

### Hashes

| SHA-256 | Component |
|---------|-----------|
| `ea40641a086bfa4e077b066e2f2e92e6c5d777153aea2bb5405382b8b513ae0d` | `RoboVPN.msi` installer (Cyberkick Ltd.; WiX 3.14, built 2024-03-31) |
| `6f686ba628de3bf1ebfb8504e2e966334b02505c546bb9d2ad020f5f5d1d01b7` | `NeunativeWin.dll` native x64 proxy SDK (registration + tunnel relay) |
| `74beab8ae664958742f6c5d33c1a50bd06d4137147e42c0b94b7be2f8ec98ebb` | `NeunativeNG.dll` .NET P/Invoke shim (NuGet NeunativeNG 8.0.36) |
| `4098f6a407b7dd8ddb3a30b225255ba9e9035136e6eabfde208242d73c88ecb5` | `RoboVPN.Connector.Core.dll` (contains `ProxyService`) |
| `d7d37ce6f7bdaf6e7ddd6e3a89ff930b79672f30378367121fcee6cc61f2334c` | `RoboVPN.dll` main WPF application |

### Network indicators

| Indicator | Role |
|-----------|------|
| `lb.gmslb[.]net:443` | Director / load balancer (registration) |
| `GET /regdev?usr=…&sdkv=…&inst=…` | Registration request path |
| `User-Agent: SDK` | Registration UA |
| `sN.<front>[.]com:6000` | Relay fleet: ~360 datacenter relays, 30 front domains; full list in [`popa/iocs/relays.csv`](../popa/iocs/relays.csv) |
| Port 6000 (TLS) to datacenter IPs | Relay connections |

### Host indicators

| Indicator | Type |
|-----------|------|
| `HKCU\Software\Neunative` | Registry (UUID persistence) |
| `%AppData%\NeuNative.log` | Log file |
| `%AppData%\logNeunative.txt` | Log file |
| Service `RoboVPN_WG0` / `RoboVPN_WG` | WireGuard service (advertised VPN) |

### RoboVPN app infrastructure (not the proxy SDK)

| Domain | Role |
|--------|------|
| `api.vpns.robovpn[.]com` | Country/server list API |
| `vpn.uk1.vpns.robovpn[.]com` | VPN endpoint (WireGuard on Windows; IKEv2 advertised) |
| `download.robovpn[.]com` | Distribution (MSI, version.txt) |
| `hyfuydyut5.execute-api.us-west-2.amazonaws[.]com` | Login (AWS API Gateway) |
| `robovpn-windows-default-rtdb.firebaseio[.]com` | Firebase remote config |
| S3 bucket `robovpn-exe-logs` | Telemetry |

## Related public reporting

- **Dr.Web (Doctor Web), [*Void captures over a million Android TV boxes*](https://news.drweb.com/show/?i=14900&lng=en)** (September 2024). The original discovery of the Vo1d backdoor (~1.3M Android TV boxes, ~200 countries), predating the Popa proxy plugin that XLab named later. The first public account of the device population this SDK runs on.
- **XLab (Qianxin), [*Long Live the Vo1d Botnet*](https://blog.xlab.qianxin.com/long-live-the-vo1d_botnet/#popa-c2)** (March 2025). The Popa proxy plugin on ~1.6M Vo1d Android TVs; `gmslb[.]net` is one of its hardcoded C2 domains. The malware-side view of the same backend.
- **Synthient, [*A Broken System: Fueling Botnets*](https://synthient.com/blog/a-broken-system-fueling-botnets)** (January 2026). How weak proxy-SDK destination filters (the `0.0.0.0:5555` path) turn residential-proxy nodes into an initial-access vector.
- **Synthient + Infoblox, [*Who Are the Victims of Residential Proxies*](https://synthient.com/blog/who-are-the-victims-of-residential-proxies)** (June 2026). Outbound-traffic analysis of Popa, and the published Popa C2 list ([IoCs](https://github.com/synthient/public-research/blob/main/2026/06/WhoAreTheVictimsOfResidentialProxies.md)) we cross-checked against our enumerated relay fleet.
- **Synthient, [*Popa: From Sourcing to Distribution*](https://synthient.com/blog/popa-from-sourcing-to-distribution)** (June 2026). Traces Popa's supply chain, from how the SDK is sourced to how it reaches devices.
- **Plume Security Labs, [*SuperProxy: The Unhealthy Marriage of SuperBox and Residential Proxies*](https://cdn.plume.com/ca/69/b1c4a022451884c2c6124341c8f5/plumereserachpaper-superproxy-may2026.pdf)** (May 2026). The same backend from the Android side: the Popanet build (`io.popanet`) in the Cyberflix TV app on SuperBox devices, with the same `lb.gmslb[.]net` director, TLV protocol, and `0.0.0.0`→ADB filter gap. Confirms Popanet is the code shipped as Vo1d's Popa plugin.
- **Spur, [*How Residential Proxies Enable Lateral Movement Risk*](https://spur.us/blog/residential-proxy-lateral-movement-risk)** (January 2026). Across "nearly every residential proxy service" Spur tested, local-network access was permitted by default and filters "easily bypassed via DNS resolution behavior"; generalizes our `0.0.0.0` finding to an industry pattern.
- **Qurium Media Foundation, [*Finding 'Popa'*](https://www.qurium.org/forensics/finding-popa)** (2026). The forensic investigation from the receiving end of Popa's traffic; corroborates the same `gmslb[.]net` director, `lb.<front>`/`sN.<backend>:6000` pattern, and TLV protocol across a far larger sample (~5,000 binaries, 300+ backends), identifies the Neunative library in RoboVPN and MediaGet, and argues a NetNut/Alarum organizational link via Cyberkick's ownership by Alarum. Its broader [*The Future and Past of Residential Proxies*](https://www.qurium.org/forensics/the-future-of-residential-proxies/) (May 2026) and [forensic proxy/VPN reports](https://www.qurium.org/forensic-proxy/) trace Layer-7 DDoS on independent media back to commercial proxy/VPN providers.
- **KrebsOnSecurity, [*Popa botnet linked to publicly traded Israeli firm*](https://krebsonsecurity.com/2026/06/popa-botnet-linked-to-publicly-traded-israeli-firm/)** (June 2026). Investigative reporting that ties the Popa/Vo1d infrastructure to a publicly traded Israeli firm.
