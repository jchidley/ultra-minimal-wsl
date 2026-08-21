#!/usr/bin/env bash
# Reproducibly build WSL 2.7.12's Linux-side init on Debian/WSL without the
# unavailable Windows SDK. This reproduces the Linux target, not wslservice.exe.
set -euo pipefail
export LC_ALL=C

SOURCE=${SOURCE:-/root/src/WSL-2.7.12}
ROOT=${ROOT:-/root/experiments/minimal-wsl/control-plane-build}
LOCALIZATION_HEADER=${LOCALIZATION_HEADER:-$ROOT/Localization.h}
JOBS=${JOBS:-$(nproc)}
BUILD=${BUILD:-$ROOT/native-build}
CACHE=${CACHE:-$ROOT/cache}
OFFLINE=${OFFLINE:-0}
MINIMAL_LINK=${MINIMAL_LINK:-0}
DEPS=$ROOT/deps
OUT=$BUILD/out
OBJ=$BUILD/obj

base_commit=68f601bba8eac1df20a0bbd403c6c87c92369ade
expected_patch_sha=${EXPECTED_SOURCE_PATCH_SHA256:-}
linuxsdk_version=1.20.0
wsldeps_version=10.0.27820.1000-250318-1700.rs-base2-hyp
linuxsdk_sha=942d36f760446853b29c97f2ee689819bb9305d959342d21df537c1d6981491e
wsldeps_sha=893411830c3bbf58744c44da8d6361018bfee41f22923697b85033aebfc94c7b
gsl_sha=f0e32cb10654fea91ad56bde89170d78cfbf4363ee0b01d8f097de2ba49f6ce9
json_sha=42f6e95cad6ec532fd372391373363b62a14af6d771056dbfc86160e6dfff7aa
localization_sha=374fec04eeff025d2500ff2fcaf61b6f8421debb7d26df3030c24a01feaa8515
feed=https://pkgs.dev.azure.com/shine-oss/13eb32df-d33f-470f-b930-499535a958b4/_packaging/7925a3a1-b93c-4977-8a97-5b877bf2068b/nuget/v3/flat2

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "missing command: $1"; }
for command in git unzip tar clang clang++ llvm-ar llvm-strip llvm-objcopy sha256sum; do need "$command"; done
[[ $MINIMAL_LINK == 0 || $MINIMAL_LINK == 1 ]] || fail "MINIMAL_LINK must be 0 or 1"
source_commit=$(git -C "$SOURCE" rev-parse HEAD)
[[ -z $(git -C "$SOURCE" status --porcelain) ]] || fail "source worktree is dirty"
if [[ $source_commit != "$base_commit" ]]; then
    [[ $(git -C "$SOURCE" merge-base "$base_commit" "$source_commit") == "$base_commit" ]] || fail "source does not descend from pinned WSL 2.7.12"
    [[ -n $expected_patch_sha ]] || fail "EXPECTED_SOURCE_PATCH_SHA256 is required for patched source"
    actual_patch_sha=$(git -C "$SOURCE" diff --binary "$base_commit..$source_commit" | sha256sum | cut -d' ' -f1)
    [[ $actual_patch_sha == "$expected_patch_sha" ]] || fail "patched source hash mismatch: $actual_patch_sha"
else
    actual_patch_sha=none
fi
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$SOURCE" show -s --format=%ct "$base_commit")}
export SOURCE_DATE_EPOCH
[[ -f $LOCALIZATION_HEADER ]] || fail "missing generated Localization.h: $LOCALIZATION_HEADER"
printf '%s  %s\n' "$localization_sha" "$LOCALIZATION_HEADER" | sha256sum -c -

mkdir -p "$CACHE" "$DEPS" "$BUILD"
cache_artifact() {
    local artifact=$1 url=$2 sha=$3 path temporary
    path=$CACHE/$artifact
    if [[ -f $path ]] && printf '%s  %s\n' "$sha" "$path" | sha256sum -c - >/dev/null 2>&1; then
        printf 'cache hit: %s\n' "$artifact"
        return
    fi
    [[ $OFFLINE == 0 ]] || fail "artifact is absent or invalid in offline cache: $path"
    need curl
    temporary=$path.partial.$$
    rm -f "$temporary"
    printf 'cache miss: downloading %s\n' "$artifact"
    if ! curl -fL --retry 10 --retry-delay 2 --retry-all-errors -o "$temporary" "$url"; then
        rm -f "$temporary"
        fail "artifact download failed: $artifact"
    fi
    if ! printf '%s  %s\n' "$sha" "$temporary" | sha256sum -c -; then
        rm -f "$temporary"
        fail "downloaded artifact failed SHA-256 verification: $artifact"
    fi
    mv -f "$temporary" "$path"
}
cache_artifact "microsoft.wsl.linuxsdk.$linuxsdk_version.nupkg" \
    "$feed/microsoft.wsl.linuxsdk/$linuxsdk_version/microsoft.wsl.linuxsdk.$linuxsdk_version.nupkg" "$linuxsdk_sha"
cache_artifact "microsoft.wsl.dependencies.amd64fre.$wsldeps_version.nupkg" \
    "$feed/microsoft.wsl.dependencies.amd64fre/$wsldeps_version/microsoft.wsl.dependencies.amd64fre.$wsldeps_version.nupkg" "$wsldeps_sha"
cache_artifact gsl-v4.0.0.tar.gz \
    https://github.com/microsoft/GSL/archive/refs/tags/v4.0.0.tar.gz "$gsl_sha"
cache_artifact json-v3.12.0.tar.xz \
    https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz "$json_sha"

if [[ ! -f $DEPS/.extracted-v1 ]]; then
    rm -rf "$DEPS"
    mkdir -p "$DEPS/linuxsdk" "$DEPS/wsldeps" "$DEPS/gsl" "$DEPS/json"
    unzip -q "$CACHE/microsoft.wsl.linuxsdk.$linuxsdk_version.nupkg" -d "$DEPS/linuxsdk"
    unzip -q "$CACHE/microsoft.wsl.dependencies.amd64fre.$wsldeps_version.nupkg" -d "$DEPS/wsldeps"
    tar -xzf "$CACHE/gsl-v4.0.0.tar.gz" -C "$DEPS/gsl" --strip-components=1
    tar -xJf "$CACHE/json-v3.12.0.tar.xz" -C "$DEPS/json" --strip-components=1
    touch "$DEPS/.extracted-v1"
fi

rm -rf "$OBJ" "$OUT"
mkdir -p "$OBJ" "$OUT/generated"
cp "$LOCALIZATION_HEADER" "$OUT/generated/Localization.h"

sdk=$DEPS/linuxsdk/x86_64
wsldeps=$DEPS/wsldeps/build/native
common=(
    --gcc-toolchain="$sdk" -fpic -B"$sdk" -isysroot "$sdk"
    -isystem "$sdk/include/c++/v1" -isystem "$sdk/include"
    -isystem "$DEPS/gsl/include" -isystem "$wsldeps/include/lxcore"
    -isystem "$wsldeps/include/schemas"
    -I "$SOURCE/src/linux/inc" -I "$SOURCE/src/linux/mountutil"
    -I "$SOURCE/src/linux/plan9" -I "$SOURCE/src/linux/netlinkutil"
    -I "$SOURCE/src/linux/init" -I "$SOURCE/src/shared/configfile"
    -I "$SOURCE/src/shared/inc" -I "$DEPS/json/include" -I "$(dirname "$LOCALIZATION_HEADER")"
    --no-standard-libraries -Werror -Wall -Wpointer-arith
    -D_POSIX_C_SOURCE=200809L -Dswprintf_s=swprintf -fms-extensions
    -target x86_64-unknown-linux-musl -D_GNU_SOURCE=1 -D_LARGEFILE64_SOURCE
    -DWSL_PACKAGE_VERSION='"2.7.12.0"' -DWSL_PACKAGE_VERSION_MAJOR=2
    -DWSL_PACKAGE_VERSION_MINOR=7 -DWSL_PACKAGE_VERSION_REVISION=12 -D_AMD64_
    -ffile-prefix-map="$SOURCE"=/usr/src/wsl -ffile-prefix-map="$BUILD"=/usr/src/build/candidate
    -ffile-prefix-map="$ROOT"=/usr/src/build
    -fdebug-compilation-dir=/usr/src/build -g -O2 -DNDEBUG
)
link_options=()
if [[ $MINIMAL_LINK == 1 ]]; then
    common+=(-ffunction-sections -fdata-sections)
    link_options+=(-Wl,--gc-sections)
fi

sources=(
    src/shared/configfile/configfile.cpp
    src/linux/mountutil/mountflags.cpp src/linux/mountutil/mountutil.c
    src/linux/netlinkutil/Address.cpp src/linux/netlinkutil/Interface.cpp
    src/linux/netlinkutil/IpNeighborManager.cpp src/linux/netlinkutil/IpRuleManager.cpp
    src/linux/netlinkutil/Neighbor.cpp src/linux/netlinkutil/NetlinkError.cpp
    src/linux/netlinkutil/NetlinkParseException.cpp src/linux/netlinkutil/NetlinkResponse.cpp
    src/linux/netlinkutil/NetlinkTransaction.cpp src/linux/netlinkutil/NetlinkTransactionError.cpp
    src/linux/netlinkutil/Route.cpp src/linux/netlinkutil/RoutingTable.cpp
    src/linux/netlinkutil/Rule.cpp src/linux/netlinkutil/RuntimeErrorWithSourceLocation.cpp
    src/linux/netlinkutil/SyscallError.cpp src/linux/netlinkutil/Utils.cpp
    src/linux/plan9/p9fid.cpp src/linux/plan9/p9file.cpp src/linux/plan9/p9fs.cpp
    src/linux/plan9/p9handler.cpp src/linux/plan9/p9io.cpp src/linux/plan9/p9lx.cpp
    src/linux/plan9/p9readdir.cpp src/linux/plan9/p9scheduler.cpp
    src/linux/plan9/p9tracelogging.cpp src/linux/plan9/p9util.cpp src/linux/plan9/p9xattr.cpp
    src/linux/init/main.cpp src/linux/init/binfmt.cpp src/linux/init/config.cpp
    src/linux/init/DnsServer.cpp src/linux/init/DnsTunnelingChannel.cpp
    src/linux/init/DnsTunnelingManager.cpp src/linux/init/drvfs.cpp src/linux/init/escape.cpp
    src/linux/init/GnsEngine.cpp src/linux/init/GnsPortTracker.cpp src/linux/init/init.cpp
    src/linux/init/localhost.cpp src/linux/init/Localization.cpp src/linux/init/NetworkManager.cpp
    src/linux/init/plan9.cpp src/linux/init/telemetry.cpp src/linux/init/timezone.cpp
    src/linux/init/SecCompDispatcher.cpp src/linux/init/util.cpp
    src/linux/init/WslDistributionConfig.cpp src/linux/init/wslinfo.cpp src/linux/init/wslpath.cpp
)

compile_one() {
    local rel=$1 object=$2
    if [[ $rel == *.c ]]; then
        clang "${common[@]}" -frandom-seed="$rel" -std=c99 "$SOURCE/$rel" -c -o "$object"
    else
        clang++ "${common[@]}" -frandom-seed="$rel" -std=c++20 "$SOURCE/$rel" -c -o "$object"
    fi
}
export -f compile_one
export SOURCE
# Exporting bash arrays is impossible; use one shell and bounded background jobs.
objects=()
running=0
for rel in "${sources[@]}"; do
    object="$OBJ/${rel//\//_}.o"
    objects+=("$object")
    compile_one "$rel" "$object" &
    ((++running))
    if (( running >= JOBS )); then wait -n; ((--running)); fi
done
wait

clang++ -o "$OUT/init.debug" "$sdk/lib/crti.o" "$sdk/lib/crt1.o" \
    "${objects[@]}" "$sdk/lib/crtn.o" -target x86_64-unknown-linux-musl \
    --gcc-toolchain="$sdk" -B"$sdk" -isysroot "$sdk" -nostartfiles \
    --no-standard-libraries -fuse-ld=lld -L"$sdk/lib" -L"$sdk/lib/linux" \
    "${link_options[@]}" -lclang_rt.builtins-x86_64 -l:libc.a -static -lunwind -lc++abi -lc++
llvm-strip "$OUT/init.debug" -o "$OUT/init"
llvm-objcopy --add-gnu-debuglink="$OUT/init.debug" "$OUT/init"

# Deterministic newc archive: fixed inode and SOURCE_DATE_EPOCH-derived mtime.
export INIT_INPUT="$OUT/init" INITRD_OUTPUT="$OUT/initrd.img"
uv run python "$ROOT/create-initrd-repro.py"

(
    cd "$OUT"
    sha256sum init init.debug initrd.img generated/Localization.h
) > "$OUT/SHA256SUMS"
{
    printf 'source_base_commit=%s\n' "$base_commit"
    printf 'source_commit=%s\n' "$source_commit"
    printf 'source_patch_sha256=%s\n' "$actual_patch_sha"
    printf 'source_date_epoch=%s\n' "$SOURCE_DATE_EPOCH"
    printf 'minimal_link=%s\n' "$MINIMAL_LINK"
    printf 'clang=%s\n' "$(clang --version | head -1)"
    printf 'lld=%s\n' "$(ld.lld --version | head -1)"
    printf 'linuxsdk_sha256=%s\n' "$linuxsdk_sha"
    printf 'wsldeps_sha256=%s\n' "$wsldeps_sha"
    printf 'localization_sha256=%s\n' "$localization_sha"
} > "$OUT/build-metadata.txt"
file "$OUT/init" "$OUT/initrd.img"
cat "$OUT/SHA256SUMS"
