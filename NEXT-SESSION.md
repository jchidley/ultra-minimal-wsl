# Next-session restart brief

## Goal

Preserve the completed source-only `minimal-v2` control-plane reduction and continue only non-runtime review unless the user separately selects the large Windows controlled-package phase. Do not provision or run that environment from this brief.

## Verify before editing

1. Read `AGENTS.md`, `PROJECT-MODEL.md`, `STATUS.md`, `TASKS.md`, `MINIMAL-BOOT-PLAN.md`, `build-host/README.md`, `control-plane/README.md`, and `control-plane/minimal-v2-audit.md`.
2. Require a clean `main` matching `origin/main`; investigate rather than discard unexpected changes.
3. Run:

```bash
uv run python tools/inventory_records.py
uv run python -m unittest \
  tools.test_build_host_profile \
  tools.test_inventory_records \
  tools.test_control_plane_protocol \
  tools.test_control_plane_records
~/git/agent-skills/skills/windows-env/ps-lint \
  --offline --settings .PSScriptAnalyzerSettings.psd1 tools
git ls-files '*.sh' -z | xargs -0 shellcheck --severity=warning -x
```

4. On `LFS-Builder`, run `tools/bootstrap-lfs-builder.sh --check`, verify `/root/src/WSL-2.7.12` is clean at `68f601bba8eac1df20a0bbd403c6c87c92369ade`, and run `tools/extract-control-plane-protocol.sh check`.
5. Verify all patch and candidate manifests. Do not amend or replace `minimal-v1` or any `minimal-v2` record.
6. Require pinned PSScriptAnalyzer 1.25.0 and ShellCheck 0.11 or newer.

## Preserved result

- `minimal-v2-fail-closed` admits only the recorded contract through a shared policy seam.
- `minimal-v2-stock-ns` and `minimal-v2-mount-ns` share the exact fail-closed parent and differ only in the coherent namespace bundle.
- The parent and both siblings each have two byte-identical offline minimal-link builds.
- Protocol tests enumerate all 52 recorded message families; add-import and remove-termination semantic mutations were caught.
- No Windows build, B4/B5/B6 result, or namespace Kconfig requirement is proved.

## Safety boundary

- Do not download a Windows ISO or Visual Studio.
- Do not create, start, stop, or checkpoint a Hyper-V VM.
- Do not request elevation.
- Do not modify the host WSL package, installed initrd, `.wslconfig`, or running distributions.
- Do not execute `control-plane/deferred-runtime-plan.json`; it is non-executable and carries no approval.
- Do not promote `CONFIG_IPC_NS`, `CONFIG_PID_NS`, or `CONFIG_UTS_NS` from static evidence.

## Permitted next work

- Continue non-runtime Kconfig dependency review against the retained contract.
- Audit source/documentation consistency without changing recorded candidate hashes.
- If the user later selects the controlled-package phase, first replace every missing plan input with a pinned hash, independently review recovery/checkpoint preconditions, plan-validate a fixed operation, and obtain fresh explicit approval before elevation or execution.

## Completion checks

- Inventory, protocol, record, lint, patch-manifest, protocol-fixture, Markdown-link, and `git diff --check` gates pass.
- All candidate runtime fields remain `none`/`false`.
- No durable kernel annotation is promoted without runtime evidence.
- Commit and push only when the working tree is clean and `main` matches `origin/main`.

## Start a genuinely new Pi session

From PowerShell:

```powershell
Set-Location 'C:\Users\jackc\git\ultra-minimal-wsl'
pi --name 'post-minimal-v2 source review' `
  '@NEXT-SESSION.md' `
  'Execute this restart brief autonomously. Verify all recorded state before changing files.'
```
