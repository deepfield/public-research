# ipmoyu (MoYu / BADBOX 2.0 residential proxy)

MoYu is one of the four threat-actor groups behind BADBOX 2.0. Per [HUMAN Security](https://www.humansecurity.com/learn/blog/satori-threat-intelligence-disruption-badbox-2-0/), MoYu is the group named for the IpMoYu residential-proxy service; the BADBOX 2.0 backdoor gives MoYu persistent privileged access to infected devices, which it can monetize through residential-proxy node creation among other fraud schemes. `ipmoyu.com` is a HUMAN-documented BADBOX 2.0 indicator. This directory documents a live MoYu delivery chain we reverse-engineered end to end: a set of clean, grey-market Android-TV IPTV apps (the `tigertv` family) that ship no malware of their own, fetch that residential-proxy module at runtime, and turn the television into a SOCKS5/HTTP exit node.

See the [full report](report.md) for the analysis. Machine-readable indicators are in [`iocs/`](iocs/).

## The chain

1. **Clean vehicle.** The `com.android.{tigertv,tigersport,mioplus,miosport,vo_vivo,vo_fixture}` apps are ordinary VLC-based IPTV players. There is no BADBOX code, no C2 URL, and no BADBOX loader baked into the APK. Static scanners see a clean app because it is one.
2. **Server-gated staging.** At startup the app calls a server-controlled `getDomainList` rotation pool, then the BADBOX `a1.`/`t1.` C2 serves an ad-fraud/proxy config over a plaintext `/cpc/api/xml` channel.
3. **Payload.** The config points to a JAR on a loader host; it is downloaded, dynamically loaded, and `com.miyc.transfer.Client` ("zhima") is invoked, a residential-proxy transfer engine that connects out to an operator relay and pumps third-party traffic through the device.

**Exposure model:** contact with a cover/apex domain means the device merely has the IPTV app installed; contact with an `a1.`/`t1.` C2 FQDN means the device has entered the MoYu/BADBOX payload path.

## Contents

| File | Description |
|------|-------------|
| [report.md](report.md) | Full analysis: the delivery chain, a method-level teardown of the zhima proxy, the build 65 to 66 change set, and live infrastructure |
| [iocs/domains.csv](iocs/domains.csv) | Seed/rotation domains, BADBOX C2, loader and first-stage-loader domains |
| [iocs/ips.csv](iocs/ips.csv) | C2, loader, and residential-proxy relay addresses |
| [iocs/hashes.csv](iocs/hashes.csv) | Vehicle APKs, the zhima modules (sh65/sh66), and the host.dex first stage |

## References

- HUMAN Security — [Satori Threat Intelligence Disruption: BADBOX 2.0](https://www.humansecurity.com/learn/blog/satori-threat-intelligence-disruption-badbox-2-0/)
- Nokia Deepfield ERT — [RoboVPN / Neunative](../reports/2026-06-18-robovpn-neunative.md) and [Pray4Bandwidth](../reports/2026-03-19-xiongmai-packetsdk-ipidea.md), on the residential-proxy-to-botnet economy
