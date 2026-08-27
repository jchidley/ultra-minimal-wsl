# Next-session restart brief

## Bounded objective

Produce a source-backed, non-executable design packet for diagnosing the disposable guest's unavailable `vmicvmsession` service path, and stop without operating the VM. Completion means `control-plane/deferred-runtime-plan.json` records one bounded, non-installing diagnostic route (or a precise evidence-backed blocker), its observations, preconditions, safe shutdown/recovery contract, exclusions, and approval state; a focused record test enforces the contract; and `STATUS.md` and `TASKS.md` agree with the result. The overarching objective is `minimal-viable-wsl-v1`; the immediate milestone gap is that PowerShell Direct guest control must be restored before the stock WSL baseline can be established. The controller-owned following boundary is deciding whether the resulting mechanics are sufficient to commission and review one fixed execution artifact or manual packet; do not enter that boundary.

## Context and checks

- Current state: `STATUS.md` — verified attempt-five consequence, final VM safety evidence, and current runtime blocker
- Work queue: `TASKS.md` — bounded non-installing diagnosis and blocked stock-install retry
- Active plan: `MINIMAL-BOOT-PLAN.md` — durable proof order, safety gates, and acceptance criteria
- Operating instructions: `AGENTS.md` — canonical ownership, preparation authority, and approval boundaries
- Decisions: `WSL-CONTROL-PLANE-AUDIT.md` — retained control-plane and disposable-environment constraints
- Evidence: `control-plane/deferred-runtime-plan.json` — attempt records, authoritative PowerShell Direct finding, fixed VM identity, and recovery requirements

1. Work only in `C:\Users\jackc\git\ultra-minimal-wsl`. Read `AGENTS.md`, then the role sources above progressively. In the evidence record, initially inspect only `recovery_install_contract.stock_baseline_approval_packet`, its attempt-five entry, `baseline_attempt.guest_control_selection`, and the missing/stop conditions; expand context only to resolve a specific ambiguity.
2. Run lightweight Git checks. Expect HEAD `0007879584f13c422fa8522493f5763d7d397010`, upstream `origin/main`, ahead/behind `0/0`, and the documented dirty tree. Do not reset, clean, commit, fetch, push, or alter preserved evidence.
3. Treat these as fixed prerequisites: attempt five established no guest session and no MSI installation; its in-artifact cleanup failed to prove Off; separately reviewed ordinary `Stop-VM` recovery evidence proves Off, zero host-attached disks, and only `clean-shell`. No approval carries forward. The stock-baseline artifact remains blocked and must not be retried.
4. Do not access credentials, elevate, query or operate Hyper-V/WSL, open VMConnect, mount a VHD, install software, create/restore checkpoints, compile, run `-Execute`, or change the existing stock-baseline artifact. Use existing recorded Microsoft sources first; consult only authoritative Microsoft material if a specific diagnostic-mechanics claim remains ambiguous.

## Execute bounded action

### Completion

Complete one bounded design-and-record attempt:

1. Determine from authoritative Microsoft evidence what can be observed or repaired when explicit-credential `New-PSSession -VMName` remains unavailable after guest boot. Distinguish host-observable Hyper-V integration-service state from guest-only `vmicvmsession` service inspection/restart. Do not infer that an enabled/healthy Hyper-V integration-service entry proves the guest service is usable.
2. Select only a Microsoft-supported, non-installing diagnostic route already implied by the recorded finding. Specify fixed target `ultra-minimal-wsl-dev`, required initial and final state `Off`, required existing checkpoint `clean-shell`, required absent checkpoint `controlled-package-baseline`, no host-attached disk, no MSI or WSL operation, no network dependency, exact observations to capture, bounded waits, and stop conditions. Any later operation that starts the VM must be represented as one reviewable artifact or manual packet with cleanup in a `finally`/equivalent path that requests graceful shutdown and independently requires Off/no attached disk; do not create or run that artifact in this session.
3. Add exactly one named design record at `recovery_install_contract.powershell_direct_diagnostic_packet` in `control-plane/deferred-runtime-plan.json`. Record `status`, `safe`, `executable:false`, `approval_carried_forward:false`, authoritative source URLs and findings, fixed scope, preconditions, proposed procedure, expected observations, cleanup/recovery, stop conditions, explicit exclusions, and unresolved manual or automation boundary. Do not reformat unrelated JSON.
4. Add one focused test named `test_powershell_direct_diagnostic_design_is_non_executable` in `tools/test_control_plane_records.py`. Enforce the non-executable/no-approval flags, fixed VM/checkpoints, non-installing exclusions, authoritative source presence, independent Off/no-disk recovery, and the legitimate manual-versus-host-observable distinction. Avoid brittle prose assertions beyond safety-critical terms.
5. Reconcile only affected canonical claims: update `STATUS.md` if the verified present blocker is narrowed, and update `TASKS.md` so its active action and following boundary match the design result. Do not duplicate detailed mechanics outside the evidence record.
6. Run `uv run python -m unittest tools.test_control_plane_records.ControlPlaneRecordTests.test_powershell_direct_diagnostic_design_is_non_executable` and `git diff --check`, then recheck Git state. Observable success is a tested, internally consistent, non-executable diagnostic design that lets the controller commission a fixed packet without repeating capability discovery. Stop without preparing approval or operating the VM.

### Decision branches

- If Microsoft documentation supports only guest-console inspection/restart through VMConnect once PowerShell Direct is unavailable, record that manual boundary explicitly, including what a human must observe and what a later host-side safety wrapper must guarantee; do not claim deterministic guest execution.
- If Microsoft documents a host-only, non-console diagnostic that works without an existing guest session, record its exact supported scope and limitations; do not broaden it into repair or execution mechanics.
- If authoritative evidence does not support either bounded route, record the exact missing fact as a blocker in the design record and `TASKS.md`; completion is the tested blocker, not an invented workaround.
- If current canonical evidence contradicts the fixed prerequisites, preserve the contradictory evidence, reconcile `STATUS.md`/`TASKS.md`, and stop without designing around it.

### Escalate and stop

Stop rather than inventing console automation, offline VHD/registry edits, a new guest agent, credential handling, force-off behavior, service-repair mechanics, package/install steps, architecture, product, safety, or operational policy. `MINIMAL-BOOT-PLAN.md`, `WSL-CONTROL-PLANE-AUDIT.md`, and `NEXT-SESSION.md` are read-only. This relay delegates only the named design-record edit under `recovery_install_contract.powershell_direct_diagnostic_packet`; no other active-plan, architecture, or decision edit is authorized. Record verified present consequences in `STATUS.md`, the bounded completion/blocker in `TASKS.md`, and detailed findings in the named evidence object only.

### Approval boundary

- Pathway: safe/authorized action — repository-only research, design recording, focused test work, and canonical reconciliation are authorized; VM/WSL operation, credentials, elevation, installation, checkpoint changes, and execution-artifact creation remain excluded

## Validation and following boundary

Make one bounded attempt with the focused test and `git diff --check`, then stop and return control. The relay currently assures a dirty tree containing `NEXT-SESSION.md`, `STATUS.md`, `TASKS.md`, `control-plane/deferred-runtime-plan.json`, `tools/test_control_plane_records.py`, and untracked `tools/Install-StockWslBaseline.ps1`; HEAD is `0007879584f13c422fa8522493f5763d7d397010`; upstream is `origin/main`; ahead/behind is `0/0`. A fresh read-only `git ls-remote origin refs/heads/main` advertised the same commit, so committed HEAD push status is verified current; all working-tree changes remain uncommitted and unpushed. Existing external attempt-five evidence was re-read and supports the recorded failed in-artifact Off proof plus subsequent Off/no-disk/`clean-shell` recovery; no live VM query was performed.

The forward-work limit is $100 and 480 minutes. When either is reached, begin no new work, preserve evidence, and report budget exhaustion. Safety restoration already encoded in any executing reviewed artifact remains mandatory and may be recorded as a justified overrun, but this action executes none. Do not retry automatically at another effort/model, optimize beyond the bounded design, or perform following-boundary work.

### Final response template

- Outcome:
- Evidence:
- Deviations or blocker:
- Files and canonical records changed:

### Controller-owned next boundary

The user or stronger reviewing model decides whether the recorded route and safety contract are sufficient to commission one exact diagnostic artifact or manual packet for separate plan validation and fresh explicit approval. It may instead require stronger evidence or keep VM operation blocked. This executor must not prepare approval, access credentials, operate the VM, retry stock installation, or begin compilation/runtime work.

## Manual restart command

Target session name: `Design PowerShell Direct Diagnosis`

Shell: PowerShell

```powershell
Set-Location -LiteralPath 'C:\Users\jackc\git\ultra-minimal-wsl'
pi `
  --model 'openai-codex/gpt-5.6-luna' `
  --thinking 'medium' `
  '--relay-run-id=99119c46-e226-4106-b7f6-0235363fa4e8' `
  'Read and execute NEXT-SESSION.md'
```

## Provenance and fallback

Parent Pi session: 01a033e1-298f-7def-8c85-ba2a7ff65b39

It is historical evidence only, opened solely to audit ambiguity. Canonical repository files and freshly verified evidence take precedence; it carries no current instruction or approval.
