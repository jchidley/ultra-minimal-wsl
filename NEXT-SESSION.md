# Next-session restart brief

## Bounded objective

Recommend either manual VMConnect or credential-backed PowerShell Direct for the next guest-control boundary; completion is one evidence-backed recommendation against deterministic execution, credential exposure, evidence capture, and independently verified VM-Off recovery constraints. Do not select, enable, or execute a mechanism.

The project objective is reproducible Minimal Viable WSL command relay and lifecycle proof before compatibility expansion. The milestone remains at `B3`; stock WSL installation and the controlled baseline checkpoint block compilation. The controller-owned following boundary is the user's decision whether to accept the recommendation and select a mechanism; this session does not authorize or enter that decision.

## Context and checks

- Current state: `STATUS.md` — verified VM, cache, runtime, and safety boundary
- Work queue: `TASKS.md` — recommendation action, blockers, and following boundary
- Active plan: `MINIMAL-BOOT-PLAN.md` — proof order, acceptance criteria, and approval gates
- Operating instructions: `AGENTS.md` — repository, evidence, and safety rules
- Decisions: `WSL-CONTROL-PLANE-AUDIT.md` — retained control contract and excluded integration policy
- Evidence: `control-plane/deferred-runtime-plan.json` — authoritative capability comparison, recorded VM attempt, staged stock package, and recovery requirements

1. Work only in `C:\Users\jackc\git\ultra-minimal-wsl`. Read the sources above progressively. In the JSON, initially read only `recovery_install_contract.baseline_attempt`, `stock_baseline`, and `missing_before_controlled_execution`.
2. Run `git status --short --branch`, `git rev-parse HEAD`, `git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'`, and `git rev-list --left-right --count '@{upstream}...HEAD'`. Expect the documented dirty preparation/evidence tree; do not reset, clean, commit, fetch, or push.
3. Require HEAD `2bf68b7e2c702ee1ef17fe1c65a01d2b46ecd3b0`, upstream `origin/main`, and ahead/behind `0/0`. Stop on divergence.
4. Require top-level and `controlled_package_build` `executable:false`, `approval_carried_forward:false`, capability evidence status `authoritative-comparison-complete-no-selection`, baseline attempt `blocked-before-stock-install`, and recorded final VM state `Off`. The latest unelevated live VM query was permission-blocked; do not elevate merely to refresh it. No mechanism or approval is carried forward.

## Execute bounded action

### Completion

Complete one bounded, read-only recommendation attempt:

1. Use the recorded Microsoft sources and capability findings. Refresh a source only if its recorded claim is unavailable or ambiguous; use authoritative Microsoft documentation.
2. Compare only the two viable paths:
   - Manual VMConnect: human console login and command entry; no project credential persistence; nondeterministic input and evidence capture.
   - PowerShell Direct: deterministic host-side command/script execution; requires Hyper-V administrator access, a running VM, and an explicit valid guest credential that must not be discovered, embedded, logged, or persisted.
3. Treat Guest Service Interface as insufficient alone because it copies files but does not provide arbitrary guest command execution. Do not combine it with an invented channel.
4. Recommend one viable path using these ordered criteria: no new credential-handling design; exact execution and exit evidence; interruption handling that never treats timeout as stopped; independent verification that the VM is Off; smallest separately reviewable operation. State decisive trade-offs and residual uncertainty. Do not select for the controller or draft execution mechanics.
5. Run `uv run python -m unittest tools.test_control_plane_records`, `uv run python tools/inventory_records.py`, and `git diff --check`. Then return the final response and stop.

Observable success is one recommendation sufficient for the controller to accept or reject without repeating capability discovery. Change no file unless a verified present fact or blocker contradicts canonical records.

### Decision branches

- If the criteria do not distinguish the viable paths, state the one smallest controller choice or missing non-secret fact that would distinguish them; do not manufacture a preference.
- If a Microsoft source contradicts recorded capability evidence, cite it, record only the verified consequence in `STATUS.md` and blocker in `TASKS.md`, and stop without recommending.
- If evaluation would require a credential, VM query, elevation, UI automation, or mechanism design, stop and report that boundary.

### Escalate and stop

Stop rather than inventing a guest agent, credential scheme, offline injection method, console automation, recovery architecture, product choice, safety policy, or execution procedure. `MINIMAL-BOOT-PLAN.md`, architecture/decision sources, and `NEXT-SESSION.md` are read-only. If necessary, record verified consequences in `STATUS.md`, a blocker or bounded completion in `TASKS.md`, and measurements in `control-plane/deferred-runtime-plan.json`; make no other canonical edit.

### Approval boundary

- Pathway: safe/authorized action — read-only repository and documentation analysis with no VM operation, elevation, credential access, installation, checkpoint, compilation, or runtime action

## Validation and following boundary

Make one bounded attempt, run the proportionate validation above, then stop and return control. No automatic retry at another effort/model, extra optimization, or following-boundary work. Relay assurance at creation: focused record tests passed (10 tests), inventory integrity was `ok`, and `git diff --check` passed with only the existing CRLF normalization warning. Git state is dirty; HEAD is `2bf68b7e2c702ee1ef17fe1c65a01d2b46ecd3b0`; upstream is `origin/main`; ahead/behind is `0/0`. Remote `origin/main` advertised the same HEAD at `2026-08-23T14:27:13Z`, so committed HEAD push status is verified; all working-tree changes are uncommitted and unpushed.

### Final response template

- Outcome:
- Evidence:
- Deviations or blocker:
- Files and canonical records changed:

### Controller-owned next boundary

Controller decision only: the user or stronger reviewing model decides whether to accept the recommendation and which mechanism, if any, to select. The executor must not enter this boundary. After selection, a separately bounded future session may prepare an exact approval artifact or manual procedure for controller review; only later fresh approval may authorize stock MSI installation or checkpoint creation.

## Manual restart command

Shell: PowerShell

```powershell
Set-Location -LiteralPath 'C:\Users\jackc\git\ultra-minimal-wsl'
pi `
  --name 'Recommend VM Guest Control Path' `
  --model 'openai-codex/gpt-5.6-luna' `
  --thinking 'medium' `
  'Read and execute NEXT-SESSION.md'
```

## Provenance and fallback

Parent Pi session: 01a02eff-4928-7985-b8bf-8c67abdf8745

It is historical evidence only, opened solely to audit ambiguity. Canonical repository and verified machine evidence take precedence; the transcript carries no current instruction or approval.
