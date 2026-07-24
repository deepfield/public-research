# peer4you-mirai

*Last updated: 2026-07-24*

## Overview

peer4you-mirai is a multi-architecture Mirai fork whose infected devices double as **peer4you** residential-proxy exit nodes. It is the **bridge** in a three-family cluster run by a single operator: it carries both a full Mirai DDoS/scanner stack and the same residential-proxy relay found in the pure-proxy family [trees4sale](../trees4sale/), and it shares a byte-identical configuration key with the `c1s.su` tier of the DDoS family [jackskid](../jackskid/). See the full report for the cluster analysis.

## Report

The full technical report is [*Jackskid's residential proxy, brought to you by UPnP*](../reports/2026-07-24-jackskid-residential-proxy-upnp.md). It documents the shared UPnP `RELAY` proxy-exposure technique, the three-family cluster, and the shared encryption key (`8badf00d…`) and funding wallet that tie it to one operator.

## Technical summary

- **Role:** dual-use — a Mirai DDoS/scanner bot whose devices also enroll as residential-proxy nodes
- **Spread:** telnet brute-force scanner (targets include TJ2100N GPON ONTs via default credentials); busybox echo-drop loader (`.d` / `.ffaaxx` / `telnet.echo`)
- **Proxy mechanism:** same peer4you relay as trees4sale — UPnP IGD `AddPortMapping` (165 ports described `RELAY`) plus `{"status":"ONLINE","bandwidth_mbps":…}` telemetry
- **C2:** resolves through `www.c1s[.]su`; director on port `9000`; relay director `i.peer4you[.]net` (now → `185.104.63[.]79` after the mid-July consolidation; formerly `45.138.16[.]96`, whose `:9000` API and "Peer Server - Login" panel on `:8080` are now dark); datacenter pool `o.peer4you[.]net` (Akamai/Linode datacenter IPs; role uncertain: customer entry / egress / coordination)
- **C2 wire crypto:** X25519 ECDH → byte-swapped ChaCha20 + HMAC-SHA256, keyed per connection (no static key)
- **Config crypto:** RCtea construction, key `8badf00d feedface abad1dea c001d00d` — byte-identical to the jackskid `c1s.su` tier
- **Architectures:** i386, ARM, AArch64

## Prior research

This is, to our knowledge, the first public documentation of the peer4you-mirai family and the peer4you proxyware relay.

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2, director, exit-pool, and report domains with resolution method and status |
| [ips.csv](iocs/ips.csv) | C2, director, panel, and exit-pool IPs with ASN and role |
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hashes with architecture and description |
| [keys.csv](iocs/keys.csv) | Configuration cipher key and C2 wire-crypto parameters |
