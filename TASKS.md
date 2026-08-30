# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Pin and hash-verify an offline PowerShell 7 fixture input, add its exact installation command and identity checks to `control-plane/deferred-runtime-plan.json`, and revalidate the non-runtime `minimal-v3-stock-ns` build packet. Then obtain fresh bundled approval for PowerShell and Visual Studio installation, verified input staging, `Build-MinimalV3StockNs.ps1 -Execute`, evidence extraction, and returning the fixture Off. The consumed first attempt stopped before staging or installation because the fixture has no `pwsh.exe`. Candidate package installation and the reserved runtime trial remain excluded.

## Comparison queue

1. stock WSL 2.7.12 calibration with `toybox-minimal-wsl-rootfs.tar.gz` — complete at `B6-T` in `CP-STOCK-2.7.12-003`;
2. `minimal-v3-stock-ns`;
3. `minimal-v3-mount-ns`;
4. evidence-selected namespace decision;
5. one evidence-selected kernel/configuration change or minimality ablation.

Every comparison uses the identical Toybox smoke command, timeouts, instrumentation, rootfs, classification rules, and recovery proof.

## Blocked

- `minimal-v3-stock-ns` package compilation is blocked on a pinned offline PowerShell 7 fixture input and fresh build approval.
- `minimal-v3-stock-ns` runtime classification is blocked until its pinned controlled package is compiled reproducibly, installation/recovery is plan-validated, and the complete operation is freshly approved.
- Namespace selection and Kconfig promotion are blocked on controlled runtime evidence.
- Alpine, Arch, and Debian compatibility testing is blocked until `minimal-viable-wsl-v1` passes Toybox and is frozen.
- No speculative Kconfig group, VM-control diagnostic, or replacement infrastructure packet is queued.

## Constraints

- Do not retry or extend historical VM-rebuild, baseline-installer, command-diagnostic, PowerShell Direct, or checkpoint-race work.
- A fixture start/transport/recovery failure is infrastructure failure and creates no candidate result.
- Preserve completed candidate and trial evidence; never rewrite terminal ledger rows.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Do not operate WSL, install a package, change `.wslconfig`, shut WSL down, or operate the fixture without the required fresh explicit approval.
