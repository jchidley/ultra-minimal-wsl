# Protocol and policy test evidence

The fixture is compiler-extracted from the pinned shared header. `tools/control_plane_protocol.py` is the strict frame/policy validator used by the tests; tests call production validation rather than reimplementing framing checks.

## Covered properties and boundaries

- All 52 init and mini-init control message families through resize response are enumerated on the mini-init, distro-control, and session channels; only the channel-specific fail-closed allowlist is accepted.
- Unknown negative, next-range, and maximum unsigned message identifiers are rejected on every channel.
- Declared frame size must equal the received byte count across deterministic randomized sizes.
- Every message must meet its compiler-derived fixed-prefix size.
- Every excluded early and initial configuration field is mutated independently from a valid sibling fixture.
- Distro launch requires an unflagged supplied LUN with `ext4`; PMEM, another filesystem, and every launch flag are rejected.
- All 64 combinations of defined low process-flag bits are enumerated; only the three console bits are accepted.
- Signed exit status round-trips across boundary values and 200 deterministic random values.
- Fixed exit/termination messages reject trailing bytes; all invalid one-byte force values are rejected, while clean and forced termination remain accepted.

## Focused mutation checks

Each `minimal-v2` dispatch mutation was applied independently to the validator and to the recorded shared C++ policy seam. The focused protocol/record suites were required to fail in both cases, and the originals were restored before the full verification run.

| Stable contract seam | Mutation | Catching test | Result |
|---|---|---|---|
| Mini-init dispatch allowlist | add `LxMiniInitMessageImport` | every-family/channel enumeration plus C++ policy semantic/embedding checks | CAUGHT in validator and shared policy |
| Distro-control dispatch allowlist | remove `LxInitMessageTerminateInstance` | every-family/channel enumeration plus C++ policy semantic/embedding checks | CAUGHT in validator and shared policy |
| Frame-size equality | change `declared != received` to `declared < received` | randomized mismatch test | CAUGHT (prior `minimal-v1` evidence) |
| Process flag allowlist | remove the unknown-flag mask | exhaustive 0–63 flag test | CAUGHT (prior `minimal-v1` evidence) |

The two `minimal-v2` dispatch mutations are semantic allowlist changes rather than syntax or crash mutations. Both were reverted.
