# Next-session restart brief

## Bounded objective

The project objective is a reproducible Minimal Viable WSL containing only proven boot, host-channel, registered-ext4-distro, `wsl.exe` command relay, lifecycle, termination, and stock-recovery requirements; only afterward add requirements proved by Alpine, Arch, and Debian.

The verified runtime boundary remains `B3`. Source-ready reduced candidates cannot establish `B4`, `B5`, or `B6-T` until the Windows and Linux control-plane components are compiled and tested together. The immediate bounded action is to resolve the compiler-layout acquisition blocker and create a pinned, verified, reusable offline compiler layout without installing it. After that observable result, the following preparation boundary is to pin the exact offline package-build outputs and recovery procedure—not to provision or run the controlled environment.

## Context and checks

- Current state: `STATUS.md` — verified achieved boundary, current compiler blocker, cached-input state, and authorization boundary
- Work queue: `TASKS.md` — the single active acquisition action, blocked work, and immediate constraints
- Active plan: `MINIMAL-BOOT-PLAN.md` — durable proof order, runtime gates, stopping rules, and completion criteria
- Operating instructions: `AGENTS.md` — repository workflow, environment boundaries, validation commands, record discipline, and relay ownership
- Decisions: `WSL-CONTROL-PLANE-AUDIT.md` — retained host/guest contract and reason stock GNS/networking policy is excluded
- Evidence: `control-plane/deferred-runtime-plan.json` — exact product, catalog, licensing, bootstrapper, cache, prior-attempt, candidate, and execution-blocker evidence

From the repository root, run these lightweight checks in PowerShell before changing anything:

```powershell
git status --short --branch
git rev-parse HEAD
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
git fetch origin main
git rev-list --left-right --count 'HEAD...@{upstream}'
uv run python tools/inventory_records.py
$Plan = Get-Content -Raw control-plane/deferred-runtime-plan.json | ConvertFrom-Json
$Plan | Select-Object executable, approval_carried_forward, status, missing_before_plan_validation
```

Require a clean tree, configured upstream `origin/main`, ahead/behind `0/0`, push status verified by the fetch, inventory integrity `ok`, `executable:false`, and `approval_carried_forward:false`. Confirm that the compiler-layout gap remains in `missing_before_plan_validation`. Stop on an unexpected ref, dirty tree, divergence, changed approval state, missing candidate/evidence record, or inventory failure. Do not reset, clean, or rewrite completed records to conceal a mismatch.

## Execute bounded action

1. Read the exact `input_preparation.visual_studio_community`, existing `visual_studio_layout`, source-prerequisite, and cache records in `control-plane/deferred-runtime-plan.json`. Treat those records—not transcript text or overview documents—as the authority for identities, hashes, prior attempts, and rejected product substitutions.
2. Establish from official Microsoft documentation or signed Setup behavior which supported, non-installing acquisition mechanism can bind the recorded pinned Community channel manifest and catalog. Do not repeat the rejected invocation without new authoritative evidence, guess an undocumented add ID, silently follow the live channel, mutate the verified Build Tools layout, or substitute Professional.
3. Before invoking a new mechanism, record in the existing JSON plan its official evidence, exact command shape, pinned-input binding, staging destination, expected non-installing behavior, and stop conditions. Parse the JSON immediately after editing it.
4. Acquire only into a new staging directory under the configured reusable cache. Accept an existing object only after its recorded hash verifies; download a missing object atomically and verify it before use. Do not run an installer, request elevation, create or operate a Hyper-V VM, stop WSL, change `.wslconfig`, target the physical host package, or execute the deferred runtime sequence.
5. Stop if Setup attempts installation, moves to an unpinned/live catalog, resolves the wrong product, rejects the evidenced mechanism, leaves input identity ambiguous, or if a timeout leaves process state uncertain. Independently verify that any launched Setup/download process stopped before interpreting failure or cleaning staging state.
6. If acquisition succeeds, run the official layout verification and require success. Inspect the resulting response and catalog closure to confirm the recorded Community product and required prerequisite set. Generate a deterministic external relative-path SHA-256 manifest, using stable ordering and paths relative to the layout root; keep the manifest outside the layout so official verification is unaffected.
7. Record only the durable result in `control-plane/deferred-runtime-plan.json`: supported method evidence, layout path and verification result, catalog/channel/response identities, external manifest path and hash, file count, byte count, and any remaining missing inputs. Put detailed logs in the evidence location owned by that plan rather than copying them into Markdown.
8. Update `STATUS.md` with changed verified facts and `TASKS.md` with the new first incomplete action. Do not add acquisition detail to `README.md`, `PROJECT-MODEL.md`, or `MINIMAL-BOOT-PLAN.md`. Refresh this restart brief only if another relay is required.

Completion requires the separate Community layout, successful official verification, a matching external manifest and aggregate counts, and verified recorded identities. Another unsupported command or Setup support download is not completion.

## Validation and following boundary

For plan/document-only acquisition evidence changes, run:

```powershell
Get-Content -Raw control-plane/deferred-runtime-plan.json | ConvertFrom-Json | Out-Null
uv run python tools/inventory_records.py
git diff --check
```

If code, scripts, protocol fixtures, candidate source, manifests, tests, or inventory records changed, also run the corresponding unit suite, PSScriptAnalyzer, ShellCheck, protocol-fixture, build-host, and manifest gates from `AGENTS.md`. Do not repeat Linux builds or other expensive checks when their inputs are unchanged.

Relay assurance: inventory, unit, PSScriptAnalyzer, ShellCheck, patch-manifest, build-host, protocol-fixture, and whitespace gates passed; no disruptive operation ran. At handoff the tree is clean, `HEAD` is the pushed commit containing this brief, upstream is `origin/main`, ahead/behind is `0/0`, and push status was verified after fetch.

After the layout is verified, pin the exact offline controlled-package build commands, expected outputs, installation boundary, checkpoint inputs, and recovery procedure. Compilation or runtime still requires a fixed plan, canonical `safe:true`, and fresh explicit approval. Later acceptance remains controlled `B4/B5/B6-T`, relay/lifecycle/recovery proof, namespace comparison, kernel ablation, cold-start gates, Minimal Viable WSL freeze, then Alpine/Arch/Debian compatibility.

## Manual restart command

Shell: PowerShell

```powershell
Set-Location -LiteralPath 'C:\Users\jackc\git\ultra-minimal-wsl'
pi `
  --name 'Acquire Community Offline Compiler Layout' `
  --model 'openai-codex/gpt-5.6-luna' `
  --thinking 'high' `
  'Read and execute NEXT-SESSION.md'
```

## Provenance and fallback

Parent Pi session: 01a02bc6-6ee4-7044-9c38-ef2ca97299d2

The parent session is historical evidence only. Open it only to audit an ambiguous claim that cannot be resolved from the canonical project records; it is not needed during normal context rebuild and carries no current instruction or approval.
