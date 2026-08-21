#!/usr/bin/env bash
# Extract or verify the retained WSL wire ABI against the pinned 2.7.12 source.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT=${PROJECT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}
SOURCE=${SOURCE:-/root/src/WSL-2.7.12}
ROOT=${ROOT:-/root/experiments/minimal-wsl/control-plane-build}
OUTPUT=${OUTPUT:-$PROJECT/control-plane/protocol/wsl-2.7.12.json}
MODE=${1:-write}
EXPECTED_COMMIT=68f601bba8eac1df20a0bbd403c6c87c92369ade
EXPECTED_HEADER_SHA=50ccb4e6aab4d6f422e41c6003717d8eacb926ab657a61fdb9b62f6298bb8b93

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
[[ $MODE == write || $MODE == check ]] || fail 'usage: extract-control-plane-protocol.sh [write|check]'
bash "$PROJECT/tools/bootstrap-lfs-builder.sh" --check
[[ $(git -C "$SOURCE" rev-parse HEAD) == "$EXPECTED_COMMIT" ]] || fail 'source is not pinned WSL 2.7.12'
[[ -z $(git -C "$SOURCE" status --porcelain) ]] || fail 'source worktree is dirty'
printf '%s  %s\n' "$EXPECTED_HEADER_SHA" "$SOURCE/src/shared/inc/lxinitshared.h" | sha256sum -c - >/dev/null

sdk=$ROOT/deps/linuxsdk/x86_64
wsldeps=$ROOT/deps/wsldeps/build/native
for path in "$sdk" "$wsldeps" "$PROJECT/control-plane/protocol/extract.cpp"; do
    [[ -e $path ]] || fail "missing input: $path"
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
clang++ "$PROJECT/control-plane/protocol/extract.cpp" -o "$tmp/extract" \
    --gcc-toolchain="$sdk" -B"$sdk" -isysroot "$sdk" \
    -isystem "$sdk/include/c++/v1" -isystem "$sdk/include" \
    -isystem "$ROOT/deps/gsl/include" -isystem "$wsldeps/include/lxcore" \
    -isystem "$wsldeps/include/schemas" -I "$SOURCE/src/shared/inc" \
    -I "$SOURCE/src/linux/inc" \
    -target x86_64-unknown-linux-musl -std=c++20 -fms-extensions \
    -D_GNU_SOURCE=1 -D_AMD64_ \
    -DWSL_PACKAGE_VERSION_MAJOR=2 -DWSL_PACKAGE_VERSION_MINOR=7 \
    -DWSL_PACKAGE_VERSION_REVISION=12 \
    --no-standard-libraries -fuse-ld=lld -L"$sdk/lib" -L"$sdk/lib/linux" \
    "$sdk/lib/crti.o" "$sdk/lib/crt1.o" "$sdk/lib/crtn.o" \
    -lclang_rt.builtins-x86_64 -l:libc.a -static -lunwind -lc++abi -lc++
"$tmp/extract" >"$tmp/protocol.json"
uv run python -m json.tool "$tmp/protocol.json" >/dev/null

if [[ $MODE == check ]]; then
    cmp --silent "$tmp/protocol.json" "$OUTPUT" || {
        diff -u "$OUTPUT" "$tmp/protocol.json" || true
        fail 'protocol fixture differs from pinned source ABI'
    }
    printf 'protocol fixture ok: %s\n' "$OUTPUT"
else
    install -D -m 0644 "$tmp/protocol.json" "$OUTPUT"
    printf 'wrote protocol fixture: %s\n' "$OUTPUT"
fi
