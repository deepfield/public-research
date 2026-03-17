rule Katana_Mirai_ELF {
    meta:
        description = "Katana Mirai variant (DDoS bot with rootkit)"
        author = "Nokia Deepfield ERT"
        date = "2026-03-15"
        family = "Katana"

    strings:
        $mirai_id = "/bin/busybox MIRAI"
        $banner = "god will save us all"
        $greeting = "meow"
        $ipc_hb = "/data/local/tmp/.bot_hb"
        $ipc_ipc = "/data/local/tmp/.bot_ipc"
        $ipc_err = "/data/local/tmp/.bot_errors"
        $domain_path = "/var/.domains"
        $dns_cache = "/tmp/.dns_cache"
        $rootkit_ctl = "wlan_helper"
        $tcc_path = "/data/local/tmp/tcc"
        $com_update = "com.system.update"
        $citizenfx = "CitizenFX"
        $putty = "SSH-2.0-PuTTY_Release_0.8"
        $systemdd = "systemdd-worker"

    condition:
        uint32(0) == 0x464c457f and
        (
            ($mirai_id and ($banner or $greeting)) or
            (2 of ($ipc_hb, $ipc_ipc, $ipc_err)) or
            ($rootkit_ctl and $tcc_path) or
            ($com_update and $citizenfx and $putty) or
            ($systemdd and any of ($ipc_*)) or
            ($domain_path and $dns_cache)
        )
}
