# IranBot

*Last updated: 2026-07-21*

## Overview

IranBot is a self-branded ("IRAN-BOTNET", "death to Israel") ARM/Linux and x86_64 DDoS botnet tracked across three distinct builds between June and July 2026. Attribution is by code, not the branding. Over six weeks the family shed its command encryption, its polish, and its branding while gaining a telnet backdoor and then self-propagation, and it never reused command-and-control infrastructure. It is a disposable operation: build cheap, burn fast, move on.

## Report

The full analysis is in [`report.md`](report.md): a build-by-build account of the family's devolving encryption, rising propagation capability, and throwaway infrastructure, plus detection guidance and indicators.

## Technical summary

- **Builds:** armv7l `62e424b2` (Jun 8), x86_64 `7e4d2b3b` (Jul 9), x86_64 self-replicating `b1a6dba6` (Jul 20)
- **Command channel:** bespoke `#C` cipher (armv7l) devolving to plain XOR then plaintext
- **Attack methods:** 7 (armv7l) reduced to 3 (`http`/`icmp`/`udpplain`) in the x86_64 builds
- **Self-propagation:** telnet default-credential scanner + Realtek SDK exploit (self-replicating build only)
- **Backdoors:** persistent telnet bindshell (`7e4d2b3b`); on-demand `!openshell` (`b1a6dba6`)
- **Infrastructure:** never reused; five distinct ASNs across the operation (VPSVAULT, SWISSNET, BANATSYNC, Fiba Cloud, SkyPass)
- **Related:** flylegit, the same operator's public plaintext "lite" release (observation)

## Indicators

The [`iocs/`](iocs/) directory contains machine-readable indicators in CSV format:

| File | Contents |
|------|----------|
| [domains.csv](iocs/domains.csv) | C2 domains with resolution method, first-seen date, and current status |
| [ips.csv](iocs/ips.csv) | C2 and delivery IPs with role, hosting, and first-seen date |
| [hashes.csv](iocs/hashes.csv) | Sample SHA-256 hashes with architecture and description |
| [keys.csv](iocs/keys.csv) | Cryptographic keys and protocol constants |
