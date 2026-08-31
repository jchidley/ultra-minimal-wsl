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

## Excluded Plan 9/DrvFs group

All seven symbols below are enabled in Stage 1 and the stock baseline, but disabled in mkroot and every completed reduced candidate.

| Symbol | Kconfig relationships | Fail-closed reachability | Classification |
|---|---|---|---|
| `CONFIG_9P_FS` | Depends on `NET_9P` and `NETWORK_FILESYSTEMS`; selects `NETFS_SUPPORT`. | The retained launch mounts one ext4 LUN. Initialization rejects DrvFs fields, forces Plan 9 off, and rejects remount requests. | `DEFERRED` |
| `CONFIG_9P_FSCACHE` | Refines `9P_FS` and depends on `FSCACHE`. | No 9P mount remains to cache. | `DEFERRED` |
| `CONFIG_9P_FS_POSIX_ACL` | Refines `9P_FS`; selects `FS_POSIX_ACL`. | No 9P mount remains to apply ACL policy to. | `DEFERRED` |
| `CONFIG_9P_FS_SECURITY` | Refines `9P_FS`. | No 9P mount remains to carry security labels. | `DEFERRED` |
| `CONFIG_NET_9P` | Depends on `NET`; selected by the 9P filesystem and parent of all 9P transports. | No retained guest 9P client operation exists. The remaining userspace Plan 9 server implementation does not select this kernel client protocol. | `DEFERRED` |
| `CONFIG_NET_9P_FD` | Depends on `NET_9P`; implies `INET` and `UNIX`. | Stock WSL can mount DrvFs over a VSOCK-connected file descriptor, but fail-closed policy removes that mount path. | `DEFERRED` |
| `CONFIG_NET_9P_VIRTIO` | Depends on `NET_9P` and `VIRTIO`. | Stock host-share/DrvFs virtio tags are outside the one-LUN ext4 contract. | `DEFERRED` |

Broad DrvFs and Plan 9 functions remain in the pinned source, but the policy and configuration gates reject their inbound requests and fields before dispatch. Shutdown's Plan 9 stop path returns immediately when the disabled server has no control channel. These are static reachability findings, not runtime proof; they classify an explicitly excluded scenario without changing a candidate config.

## Excluded Windows-interop binary handler

`CONFIG_BINFMT_MISC` is enabled in Stage 1 and stock, disabled in mkroot and every completed reduced candidate, and has no recorded incoming or outgoing Kconfig relationships. Its generic kernel facility supports arbitrary wrapper-driven binary formats, but pinned WSL uses it specifically to register the `WSLInterop` interpreter for `MZ` Windows executables.

Stock distro init calls `ConfigRegisterBinfmtInterpreter` only when it is not the utility VM and `Config.InteropEnabled` is true. The fail-closed configuration forces that flag off, and the reduced host clears the interop process flag. The preserved v2 mini-init nevertheless called `Initialize`, which unconditionally mounted `binfmt_misc` and wrote its `WSLInterop` registration, returning failure if either operation failed. This review classified that as a source-reduction gap rather than evidence to enable the kernel symbol or infer target necessity. The later `minimal-v3` source layer removes both operations and leaves the candidate config unchanged. The symbol remains `DEFERRED`.

## Excluded checkpoint/restore group

The enabled mkroot-to-Stage-1 additions are `CONFIG_CHECKPOINT_RESTORE`, `CONFIG_KCMP`, `CONFIG_PROC_CHILDREN`, and `CONFIG_MEM_SOFT_DIRTY`. `CONFIG_CHECKPOINT_RESTORE` depends on baseline procfs and selects `KCMP` and `PROC_CHILDREN`; `MEM_SOFT_DIRTY` depends on the checkpoint option and baseline architecture/procfs support. Its selected `CONFIG_PROC_PAGE_MONITOR` and prerequisite `CONFIG_HAVE_ARCH_SOFT_DIRTY` are already enabled in mkroot and are classified `BASE`, not Stage-1 additions. DRM's independent selection of `KCMP` belongs to the excluded GPU branch, and the `!CHECKPOINT_RESTORE` condition on `CONFIG_MSEAL_SYSTEM_MAPPINGS` is a negative alternative rather than part of this enabled closure.

Pinned WSL source contains no `kcmp` syscall, soft-dirty, or checkpoint/restore use. Stock mini-init does read `/proc/self/task/1/children`, but only from its `ErrorExit` cleanup. `K-OVERLAY-DIAG-001` recorded the missing-file error after the excluded GNS failure; the exception was caught and the guest continued detaching disks and powered down. That cleanup observation does not select the proc children interface. The four Stage-1 additions are therefore `DEFERRED`; no candidate config changed.

## Excluded Unix-domain out-of-band messaging

`CONFIG_AF_UNIX_OOB` is enabled in Stage 1 and stock, disabled in mkroot and every completed reduced candidate, and has no incoming Kconfig relationship. The parsed graph records dependencies on `CONFIG_UNIX` and `CONFIG_NET`; these make OOB an optional refinement of Unix-domain sockets rather than a prerequisite for ordinary local streams. Kernel implementation guards cover `MSG_OOB` send/receive state and `EPOLLPRI` readiness for Unix sockets.

Pinned WSL product source contains no `MSG_OOB` or `SO_OOBINLINE` use. Its ordinary `AF_UNIX` `SOCK_STREAM` and `socketpair` calls never request OOB semantics. The only product-source priority-polling match is `POLLPRI` in `IpNeighborManager::PerformNeighborDiscovery`, which operates on an `AF_PACKET` raw socket in the excluded networking path and accepts the event only when `revents` is exactly `POLLIN`. Four `EPOLLPRI` matches are confined to generic Linux epoll unit tests. Therefore neither retained local streams nor unrelated priority-polling tokens select Unix OOB support. The symbol is `DEFERRED`; no candidate config changed.

## Excluded accessibility and Speakup group

`CONFIG_ACCESSIBILITY` is a code-free menu gate with no outgoing Kconfig relationship. Its broad incoming subtree narrows to only `CONFIG_SPEAKUP` and `CONFIG_SPEAKUP_SYNTH_SOFT` among symbols enabled in Stage 1 but disabled in mkroot; all hardware synthesizers, serial Speakup support, and braille-console support remain disabled. Stage 1 and stock enable the gate and build the two descendants as modules, while mkroot and every completed reduced candidate disable all three.

`CONFIG_SPEAKUP` depends on `CONFIG_VT` and the menu gate. It implements a text-console screen reader and speech core. `CONFIG_SPEAKUP_SYNTH_SOFT` depends on that core and exposes `/dev/softsynth` and `/dev/softsynthu` for userspace speech daemons. Pinned WSL product source has no Speakup, softsynth, speech-synthesis, or device-path match, and the reduced source adds none. The retained direct-command path instead uses ordinary console flags, `forkpty`, pipes, and stdio relay. Those generic console and PTY operations do not select a screen reader or speech output, and the smoke contract requires only procfs, sysfs, `/dev/null`, and direct command execution.

All three symbols are therefore `DEFERRED`. This is static exclusion evidence for accessibility policy outside the selected target; no candidate source or config changed.

## Excluded cgroup core/controller closure

A recursive incoming-dependency query starting at `CONFIG_CGROUPS`, limited to symbols enabled in Stage 1, disabled in mkroot, and previously unchecked, produced exactly 30 symbols. Both relationship directions were inspected for every symbol. The complete closure is classified `DEFERRED` in these subgroups:

| Subgroup | Symbols | Relationship and contract finding |
|---|---|---|
| Block I/O | `CONFIG_BLK_CGROUP`, `CONFIG_BFQ_GROUP_IOSCHED`, `CONFIG_BLK_CGROUP_IOLATENCY`, `CONFIG_BLK_DEV_THROTTLING`, `CONFIG_CGROUP_WRITEBACK` | The generic I/O controller feeds BFQ hierarchy, latency/rate throttling, and memory-controller writeback. Mounting the retained ext4 LUN does not require a cgroup I/O policy. |
| Scheduler | `CONFIG_CGROUP_SCHED`, `CONFIG_CGROUP_CPUACCT`, `CONFIG_FAIR_GROUP_SCHED`, `CONFIG_GROUP_SCHED_WEIGHT`, `CONFIG_GROUP_SCHED_BANDWIDTH`, `CONFIG_CFS_BANDWIDTH`, `CONFIG_SCHED_MM_CID` | These provide CPU task groups, accounting, weights, bandwidth limits, and the Stage-1 MM concurrency-ID refinement. Ordinary direct-process scheduling does not configure any of them. |
| Direct controllers | `CONFIG_CGROUP_DEVICE`, `CONFIG_CGROUP_HUGETLB`, `CONFIG_CGROUP_PERF`, `CONFIG_CGROUP_PIDS`, `CONFIG_CGROUP_RDMA`, `CONFIG_CPUSETS` | Device, huge-page, perf, process-count, RDMA, CPU, and memory-node resource policy is outside the retained launch/relay/lifecycle contract. |
| Memory | `CONFIG_MEMCG`, `CONFIG_PAGE_COUNTER` | The memory controller selects page counters and VM accounting support. The reduced host rejects memory-reclaim configuration and retains no per-cgroup memory policy. |
| Network | `CONFIG_CGROUP_NET_CLASSID`, `CONFIG_CGROUP_NET_PRIO`, `CONFIG_NET_CLS_CGROUP`, `CONFIG_NETFILTER_XT_MATCH_CGROUP`, `CONFIG_SOCK_CGROUP_DATA` | These form socket metadata, traffic-classification, priority, and netfilter policy. Hyper-V VSOCK transport does not require IP traffic or cgroup packet policy. |
| BPF | `CONFIG_CGROUP_BPF` | This attaches eBPF programs to cgroups and selects socket cgroup metadata. BPF workloads are explicitly excluded. |
| Legacy v1 | `CONFIG_CGROUP_FREEZER`, `CONFIG_CPUSETS_V1`, `CONFIG_PROC_PID_CPUSET`, `CONFIG_MEMCG_V1` | These are original/deprecated hierarchy behavior and compatibility refinements; the retained path admits no legacy hierarchy policy. |

The pinned stock distro init contains `ConfigInitializeCgroups`, `/proc/cgroups` parsing, and v1/v2 mount code. The fail-closed patch removes its only initialization call. Stock `mini_init` still attempts an unconditional cgroup2 mount, but the failure is ignored; `K-HOSTCHAN-001` advanced to B2 with `CONFIG_CGROUPS=n` after logging that failure. The reduced host also sends memory reclaim disabled, and fail-closed early configuration rejects any non-disabled reclaim request. Thus broad functions may remain compiled or a best-effort mount may remain reachable, but neither fact selects cgroup core or controllers. This is static exclusion evidence, not runtime necessity proof, and no candidate config changed.

## Excluded anonymous-VMA naming

`CONFIG_ANON_VMA_NAME` is enabled in Stage 1 and stock, disabled in mkroot and every completed reduced candidate, and has no incoming Kconfig relationship. It depends on `CONFIG_PROC_FS`, `CONFIG_ADVISE_SYSCALLS`, and `CONFIG_MMU`. The option implements `prctl(PR_SET_VMA, PR_SET_VMA_ANON_NAME, ...)`, stores user-supplied labels on anonymous VMAs, emits those labels through `/proc/<pid>/maps` and `smaps`, and may prevent otherwise-compatible VMAs from merging. It is diagnostic metadata rather than a prerequisite for anonymous mappings or ordinary `madvise` behavior.

Searches of pinned WSL 2.7.12 and all three preserved `minimal-v2` trees found no `PR_SET_VMA`, `PR_SET_VMA_ANON_NAME`, anonymous-map-label dependency, or product-source `maps`/`smaps` consumer. Retained command relay and lifecycle code use other proc interfaces, and the smoke contract reads only `/proc/self/status`. Therefore neither process creation, stdio/exit relay, lifecycle, nor the smoke contract selects this facility. The symbol is `DEFERRED`; no candidate source or config changed during this review, and static absence is not runtime necessity proof.

## Conclusions

- The retained Hyper-V/VSOCK/storage additions remain the only evidence-selected WSL kernel bundles.
- Ext4, SCSI core, procfs, sysfs, devtmpfs, PTYs, signalfd, epoll, and generic namespace support are now durably reviewed as `BASE`; they are not new WSL tax.
- The finalized runtime comparison selected namespace semantics: `minimal-v4-stock-ns` passed `B6-T`, while mount-only reached `B3`, unmounted the registered ext4 filesystem, and closed its control socket before `CreateInstanceResult`.
- Retain the coherent IPC, mount, PID, and UTS bundle as the passing baseline, but do not yet classify each optional namespace as individually required. The evidence-selected `minimal-v5-mount-pid-ns` ablation restores PID semantics while continuing to remove IPC and UTS; promote Kconfig requirements only after runtime isolates the retained subset.
- Networking remains excluded even though `CONFIG_HYPERV_VSOCKETS` has a Kconfig dependency on `CONFIG_NET`; that dependency is transport plumbing, not approval for IP networking, GNS, or DNS.
- Completed excluded-feature classifications and their supporting evidence are recorded in the sections above and in `inventory/annotations.csv`; none changed a candidate config.
