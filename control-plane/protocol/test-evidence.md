# Protocol test evidence

The fixture is compiler-extracted from the pinned shared header. `tools/control_plane_protocol.py` is the strict frame/policy validator used by the tests; tests call production validation rather than reimplementing it.

## Covered properties and boundaries

- Declared frame size must equal the received byte count across deterministic randomized sizes.
- Every message must meet its compiler-derived fixed-prefix size.
- Every excluded early and initial configuration field is mutated independently from a valid sibling fixture.
- All 64 combinations of defined low process-flag bits are enumerated; only the three console bits are accepted.
- Signed exit status round-trips across boundary values and 200 deterministic random values.
- Fixed exit/termination messages reject trailing bytes; all invalid one-byte force values are rejected.

## Focused mutation check

| Stable contract seam | Mutation | Expected catch | Result |
|---|---|---|---|
| Frame-size equality | `declared != received` → `declared < received` | randomized mismatch test | CAUGHT |
| Process flag allowlist | remove `flags & ~CONSOLE_FLAGS == 0` | exhaustive 0–63 flag test | CAUGHT |

Both semantic mutations were reverted and the full control-plane and inventory suites passed afterward.
