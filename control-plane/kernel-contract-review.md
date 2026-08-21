# Retained kernel contract review

Static review performed against `inventory/kconfig-dependencies.sqlite` after the stock-init discovery freeze. Mkroot-supplied facilities are classified `BASE`; source use selects hypotheses only, so runtime ablation remains required for any `PROVEN_*` status.

| Symbol | mkroot | Host-channel | Storage | Current status | Contract observation |
|---|---:|---:|---:|---|---|
| `CONFIG_HYPERV` | n | y | y | reviewed, unresolved | Platform entry bundle; B1 evidence. |
| `CONFIG_HYPERV_VMBUS` | n | y | y | reviewed, transitive | Selected Hyper-V transport dependency. |
| `CONFIG_VSOCKETS` | n | y | y | reviewed, unresolved | Direct control-channel blocker evidence. |
| `CONFIG_HYPERV_VSOCKETS` | n | y | y | reviewed, unresolved | Hyper-V transport used by port 50000 and command sockets. |
| `CONFIG_HYPERV_STORAGE` | n | n | y | reviewed, unresolved | Added with the B3 storage bundle. |
| `CONFIG_SCSI` | y | y | y | reviewed, base | Already supplied by mkroot; not a WSL addition. |
| `CONFIG_EXT4_FS` | y | y | y | reviewed, base | Already supplied by mkroot and used by the registered distro VHDX. |
| `CONFIG_PROC_FS` | y | y | y | reviewed, base | Smoke contract reads `/proc/self/status`; mkroot floor already supplies it. |
| `CONFIG_SYSFS` | y | y | y | reviewed, base | Smoke contract requires `/sys`; mkroot floor already supplies it. |
| `CONFIG_DEVTMPFS` | y | y | y | reviewed, base | Supplies the minimal `/dev` floor, including `/dev/null`. |
| `CONFIG_UNIX98_PTYS` | y | y | y | reviewed, base | Current direct-command implementation uses `forkpty`; already in mkroot. |
| `CONFIG_SIGNALFD` | y | y | y | reviewed, base | Current relay/lifecycle code uses `signalfd`; already in mkroot. |
| `CONFIG_EPOLL` | y | y | y | reviewed, base | Event machinery floor; already in mkroot. |
| `CONFIG_NAMESPACES` | y | y | y | reviewed, base | Generic namespace support exists in mkroot. |
| `CONFIG_IPC_NS` | n | n | n | reviewed, unresolved | Stock launcher requests it, but no reduced-path evidence exists. |
| `CONFIG_PID_NS` | n | n | n | reviewed, unresolved | Stock launcher requests it, but no reduced-path evidence exists. |
| `CONFIG_UTS_NS` | n | n | n | reviewed, unresolved | Stock launcher requests it, but no reduced-path evidence exists. |

## Conclusions

- The retained Hyper-V/VSOCK/storage additions remain the only evidence-selected WSL kernel bundles.
- Ext4, SCSI core, procfs, sysfs, devtmpfs, PTYs, signalfd, epoll, and generic namespace support are now durably reviewed as `BASE`; they are not new WSL tax.
- The preserved stock-namespace sibling requests IPC, PID, and UTS namespaces while all completed reduced kernel candidates disable them; the mount-only sibling removes precisely those three requests.
- Do not add those namespace symbols now. Both `minimal-v2-stock-ns` and `minimal-v2-mount-ns` are reproducibly built from the exact fail-closed parent. Add back a coherent namespace bundle only if the deferred runtime comparison selects it.
- Networking remains excluded even though `CONFIG_HYPERV_VSOCKETS` has a Kconfig dependency on `CONFIG_NET`; that dependency is transport plumbing, not approval for IP networking, GNS, or DNS.
