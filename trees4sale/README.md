# trees4sale

*Last updated: 2026-07-24*

## Overview

trees4sale is a residential-proxy relay bot — the **peer4you** proxyware carried in a Mirai-lineage binary with **the DDoS engine removed**. Reverse engineering of an ARM build (317 functions) found no attack engine, no scanner, no raw sockets, and no attack-command table: it is a pure relay. It is one of three families run by a single operator, alongside [peer4you-mirai](../peer4you-mirai/) (the dual-use bridge) and [jackskid](../jackskid/) (the DDoS arm). See the full report for how the three connect.

## Report

The full technical report is [*Jackskid's residential proxy, brought to you by UPnP*](../reports/2026-07-24-jackskid-residential-proxy-upnp.md). It documents the shared UPnP `RELAY` proxy-exposure technique, the three-family cluster, and the shared encryption key and funding wallet that tie it to one operator.

## Technical summary

- **Role:** residential-proxy relay only — no DDoS capability
- **Proxy mechanism:** UPnP IGD `AddPortMapping` exposes 165 ports on the victim's router, each described `RELAY`; the mapped port bridges to a fixed operator backend
- **Telemetry:** fire-and-forget `{"status":"ONLINE","bandwidth_mbps":…}` to a director on tcp/`18702` (aarch64) or tcp/`9000` (arm), after a 10 MB bandwidth self-test
- **Config:** plaintext C2 domains in the binary (no cipher)
- **Directors / loaders:** `login.trees4sale[.]net` → `185.104.63[.]79`; second full director `38.87.116[.]165`; loader `www.trees4sale[.]net` → `76.164.203[.]165`
- **Domain:** `trees4sale[.]net` is a repurposed aged domain (registered 2011; parked for years before operational use in May 2026)
- **Architectures:** ARMv5, ARMv7, AArch64, i386

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 director / loader domains with resolution method and status |
| [ips.csv](iocs/ips.csv) | Director, loader, and fleet IPs with ASN and role |
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hashes with architecture and description |
