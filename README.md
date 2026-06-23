# Nokia Deepfield ERT — public research

Threat research from the Nokia Deepfield Emergency Response Team (ERT), focused on DDoS botnets and related infrastructure. Each directory covers a botnet family with a brief summary and machine-readable indicators of compromise (IoCs).

This repo consolidates prior community research with original Deepfield ERT analysis. See individual READMEs for references and attribution.

> **Note:**
> - Indicators are provided in their raw (not defanged) form so they can be consumed directly by detection tooling. Exercise caution when handling URLs and domains.
> - Some indicators contain offensive or vulgar language chosen by threat actors for branding or anti-analysis purposes. These are reproduced verbatim to facilitate detection and attribution.

## Contents

| Directory | Description |
|-----------|-------------|
| [aisuru](aisuru/) | Mirai-derivative DDoS botnet, active since August 2024 |
| [cecbot](cecbot/) | CECbot: Android TV botnet with HDMI-CEC abuse, successor to Katana |
| [cecilio](cecilio/) | CatDDoS derivative with modified RC4 cipher, OpenNIC C2 |
| [datasurge](datasurge/) | Mirai-lineage bot with no self-propagation; competitor-killing scanner larger than its DDoS engine, plus operator RAT features |
| [drifter](drifter/) | Independent DDoS botnet on ADB attack surface, CCTV-themed C2 domains |
| [jackskid](jackskid/) | Mirai variant sharing code lineage with Aisuru, DoH C2 via mbedTLS |
| [katana](katana/) | Mirai variant with on-device compiled rootkit, targeting Android TV set-top boxes |
| [kbotne](kbotne/) | Mirai-lineage DDoS botnet with WebSocket C2 on port 80, hex-encoded config strings, and a broken Android APK |
| [kimwolf](kimwolf/) | Dual-purpose residential proxy and DDoS botnet, 3M+ devices observed |
| [maskify](maskify/) | Dual-purpose proxy/DDoS botnet with ENS, IPFS, and custom P2P mesh |
| [mossadproxy](mossadproxy/) | Android TV/IoT DDoS botnet via ADB, operationally linked to ecosystem |
| [potassium](potassium/) | Mirai variant with SHELL/SHOUT reverse-shell protocol on the C2 channel, three rotating campaigns from one codebase |
| [vibenet](vibenet/) | Custom DDoS family whose latest Linux build ships its own TLS/QUIC/HTTP3 stack to flood at Layer 7 behind a browser fingerprint, with on-chain ENS command-and-control |

## Reports

Standalone analyses that don't map to a single botnet family.

| Date | Report | Description |
|------|--------|-------------|
| 2026-03-19 | [Pray4Bandwidth](reports/2026-03-19-xiongmai-packetsdk-ipidea.md) | Xiongmai DVR campaign deploying IPRoyal Pawns and IPIDEA PacketSDK via Mirai-derived downloader |
| 2026-03-20 | [Aisuru ecosystem](reports/2026-03-20-aisuru-ecosystem.md) | Four DDoS botnets traced to one ecosystem via shared code, crypto, and infrastructure |
| 2026-06-18 | [RoboVPN / Neunative](reports/2026-06-18-robovpn-neunative.md) | Commercial VPN bundling a residential-proxy SDK that shares the Vo1d/Popa C2 backend |

## Feedback

We welcome corrections, additional IoCs, and other feedback. Reach out to us on Mastodon at [@deepfield@infosec.exchange](https://infosec.exchange/@deepfield/).
