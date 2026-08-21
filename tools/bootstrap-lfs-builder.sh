#!/usr/bin/env bash
# Provision and verify the pinned Debian build host used by this project.
set -euo pipefail
export LC_ALL=C

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
profile_file=${PROFILE_FILE:-$project_dir/build-host/lfs-builder-profile.env}
package_file=${PACKAGE_FILE:-$project_dir/build-host/packages.tsv}
source_file=${APT_SOURCE_FILE:-$project_dir/build-host/debian-snapshot.list}
sums_file=${PROFILE_SUMS_FILE:-$project_dir/build-host/SHA256SUMS}
cache=${CACHE:-/root/cache/ultra-minimal-wsl/lfs-builder}
mode=install

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'EOF'
usage: bootstrap-lfs-builder.sh [--check | --offline]

  (default)  Install exact packages from the pinned Debian snapshot, cache and
             install pinned uv binaries, then verify the complete profile.
  --offline  Use installed packages and verified local cache entries only.
  --check    Make no changes or network requests; verify the complete profile.

Environment overrides: PROFILE_FILE, PACKAGE_FILE, APT_SOURCE_FILE,
PROFILE_SUMS_FILE, CACHE.
EOF
}

case ${1:-} in
    '') ;;
    --check) mode=check ;;
    --offline) mode=offline ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }

for path in "$profile_file" "$package_file" "$source_file" "$sums_file"; do
    [[ -r $path ]] || fail "missing build-host input: $path"
done
(
    cd -- "$(dirname -- "$sums_file")"
    sha256sum -c "$(basename -- "$sums_file")" >/dev/null
) || fail 'build-host profile file hash mismatch'
profile_bundle_sha=$(cat "$profile_file" "$source_file" "$package_file" | sha256sum | cut -d' ' -f1)
# shellcheck disable=SC1090 # The path is configurable for isolated profile tests.
source "$profile_file"
required_profile_values=(
    LFS_PROFILE_VERSION LFS_OS_ID LFS_OS_VERSION_ID LFS_OS_CODENAME
    LFS_ARCHITECTURE LFS_ROOT_FILESYSTEM LFS_APT_SNAPSHOT
    LFS_APT_INRELEASE_SHA256 LFS_UV_VERSION LFS_UV_ARCHIVE_SHA256
    LFS_UV_SHA256 LFS_UVX_SHA256 LFS_SHELLCHECK_VERSION
    LFS_SHELLCHECK_ARCHIVE_SHA256 LFS_SHELLCHECK_SHA256
)
for name in "${required_profile_values[@]}"; do
    [[ -n ${!name:-} ]] || fail "profile value is absent: $name"
done
[[ $LFS_PROFILE_VERSION == 1 ]] || fail "unsupported profile version: $LFS_PROFILE_VERSION"
grep -Fq "/debian/$LFS_APT_SNAPSHOT " "$source_file" || fail 'APT source does not match profile snapshot'

packages=()
while IFS=$'\t' read -r package version role || [[ -n ${package:-} ]]; do
    [[ -z ${package:-} || $package == \#* ]] && continue
    [[ $package =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || fail "invalid package name: $package"
    [[ -n $version && -n $role ]] || fail "invalid package row: $package"
    packages+=("$package=$version")
done <"$package_file"
((${#packages[@]} > 0)) || fail 'package manifest is empty'

package_mismatches() {
    local item package expected actual
    for item in "${packages[@]}"; do
        package=${item%%=*}
        expected=${item#*=}
        actual=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)
        [[ $actual == "$expected" ]] || printf '%s\t%s\t%s\n' "$package" "$expected" "${actual:-missing}"
    done
}

verify_profile() {
    local actual command path mismatches
    command -v dpkg-query >/dev/null 2>&1 || fail 'missing command: dpkg-query'

    actual=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')
    [[ $actual == "$LFS_OS_ID" ]] || fail "OS ID mismatch: expected $LFS_OS_ID, got $actual"
    actual=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')
    [[ $actual == "$LFS_OS_VERSION_ID" ]] || fail "OS version mismatch: expected $LFS_OS_VERSION_ID, got $actual"
    actual=$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release | tr -d '"')
    [[ $actual == "$LFS_OS_CODENAME" ]] || fail "OS codename mismatch: expected $LFS_OS_CODENAME, got $actual"
    actual=$(dpkg --print-architecture)
    [[ $actual == "$LFS_ARCHITECTURE" ]] || fail "architecture mismatch: expected $LFS_ARCHITECTURE, got $actual"
    actual=$(findmnt -n -o FSTYPE /)
    [[ $actual == "$LFS_ROOT_FILESYSTEM" ]] || fail "root filesystem mismatch: expected $LFS_ROOT_FILESYSTEM, got $actual"

    mismatches=$(package_mismatches)
    [[ -z $mismatches ]] || fail $'package version mismatch (package\texpected\tactual):\n'"$mismatches"

    for command in rg fd jq shellcheck tree zip zstd less git curl make gcc g++ \
        clang clang++ ld.lld llvm-ar llvm-strip llvm-objcopy cmake ninja \
        qemu-system-x86_64 cpio pahole bc bison flex uv uvx; do
        path=$(command -v "$command" 2>/dev/null || true)
        [[ $path == /usr/* || $path == /bin/* ]] || fail "missing Linux command or inherited Windows command: $command (${path:-missing})"
    done
    [[ -x /usr/local/bin/fd ]] || fail 'missing conventional Linux fd at /usr/local/bin/fd'
    printf '%s  %s\n' "$LFS_UV_SHA256" /usr/local/bin/uv | sha256sum -c - >/dev/null
    printf '%s  %s\n' "$LFS_UVX_SHA256" /usr/local/bin/uvx | sha256sum -c - >/dev/null
    printf '%s  %s\n' "$LFS_SHELLCHECK_SHA256" /usr/local/bin/shellcheck | sha256sum -c - >/dev/null
    [[ $(uv --version) == "uv $LFS_UV_VERSION (x86_64-unknown-linux-gnu)" ]] || fail 'uv version mismatch'
    shellcheck --version | grep -qx "version: $LFS_SHELLCHECK_VERSION" || fail 'ShellCheck version mismatch'

    printf 'alpha\nbeta\n' | rg -q '^beta$'
    printf '{"ok":true}\n' | jq -e '.ok == true' >/dev/null
    fd -H '^os-release$' /etc | grep -qx '/etc/os-release'
    printf 'LFS-Builder profile %s verified: Debian %s %s on %s; bundle sha256 %s.\n' \
        "$LFS_PROFILE_VERSION" "$LFS_OS_VERSION_ID" "$LFS_ARCHITECTURE" \
        "$LFS_ROOT_FILESYSTEM" "$profile_bundle_sha"
}

if [[ $mode == check ]]; then
    verify_profile
    exit 0
fi

((EUID == 0)) || fail 'installation must run as root'
command -v apt-get >/dev/null 2>&1 || fail 'profile installation requires Debian APT'
mkdir -p "$cache/apt/partial"
apt_options=(
    -o "Dir::Etc::sourcelist=$source_file"
    -o 'Dir::Etc::sourceparts=-'
    -o 'Acquire::Check-Valid-Until=false'
    -o "Dir::Cache::archives=$cache/apt/"
    -o 'Binary::apt::APT::Keep-Downloaded-Packages=true'
)

if [[ $mode == install ]]; then
    command -v curl >/dev/null 2>&1 || fail 'curl is required to authenticate the pinned snapshot before provisioning'
    inrelease=$(mktemp)
    trap 'rm -f "$inrelease"' EXIT
    curl -fsSL --retry 5 \
        "https://snapshot.debian.org/archive/debian/$LFS_APT_SNAPSHOT/dists/$LFS_OS_CODENAME/InRelease" \
        -o "$inrelease"
    printf '%s  %s\n' "$LFS_APT_INRELEASE_SHA256" "$inrelease" | sha256sum -c - >/dev/null ||
        fail 'pinned Debian InRelease hash mismatch'
    apt-get "${apt_options[@]}" update
    apt-get "${apt_options[@]}" install -y --no-install-recommends "${packages[@]}"
else
    mismatches=$(package_mismatches)
    if [[ -n $mismatches ]]; then
        apt-get "${apt_options[@]}" install -y --no-install-recommends --no-download "${packages[@]}"
    fi
fi

# Debian names fd as fdfind. A fixed Linux path prevents WSL's inherited
# Windows PATH from silently satisfying the requirement with fd.exe.
if [[ ! -e /usr/local/bin/fd && ! -L /usr/local/bin/fd ]]; then
    ln -s /usr/bin/fdfind /usr/local/bin/fd
elif [[ ! -x /usr/local/bin/fd ]]; then
    fail '/usr/local/bin/fd exists but is not executable'
fi

uv_archive=$cache/uv-x86_64-unknown-linux-gnu-$LFS_UV_VERSION.tar.gz
uv_installed=false
if [[ -x /usr/local/bin/uv && -x /usr/local/bin/uvx ]] &&
    printf '%s  %s\n' "$LFS_UV_SHA256" /usr/local/bin/uv | sha256sum -c - >/dev/null 2>&1 &&
    printf '%s  %s\n' "$LFS_UVX_SHA256" /usr/local/bin/uvx | sha256sum -c - >/dev/null 2>&1; then
    uv_installed=true
fi
if [[ $uv_installed == false ]]; then
    if [[ ! -f $uv_archive ]] || ! printf '%s  %s\n' "$LFS_UV_ARCHIVE_SHA256" "$uv_archive" | sha256sum -c - >/dev/null 2>&1; then
        [[ $mode == install ]] || fail "uv is not installed and its offline cache entry is absent or invalid: $uv_archive"
        temporary=$uv_archive.partial.$$
        rm -f "$temporary"
        curl -fL --retry 5 -o "$temporary" \
            "https://github.com/astral-sh/uv/releases/download/$LFS_UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz"
        printf '%s  %s\n' "$LFS_UV_ARCHIVE_SHA256" "$temporary" | sha256sum -c - >/dev/null || {
            rm -f "$temporary"
            fail 'downloaded uv archive hash mismatch'
        }
        mv -f "$temporary" "$uv_archive"
    fi
    temporary_dir=$(mktemp -d)
    trap 'rm -rf "$temporary_dir"; rm -f "${inrelease:-}"' EXIT
    tar -xzf "$uv_archive" -C "$temporary_dir"
    uv_dir=$temporary_dir/uv-x86_64-unknown-linux-gnu
    printf '%s  %s\n' "$LFS_UV_SHA256" "$uv_dir/uv" | sha256sum -c - >/dev/null
    printf '%s  %s\n' "$LFS_UVX_SHA256" "$uv_dir/uvx" | sha256sum -c - >/dev/null
    install -m 0755 "$uv_dir/uv" "$uv_dir/uvx" /usr/local/bin/
    rm -rf "$temporary_dir"
    trap 'rm -f "${inrelease:-}"' EXIT
fi

shellcheck_archive=$cache/shellcheck-v$LFS_SHELLCHECK_VERSION.linux.x86_64.tar.xz
shellcheck_installed=false
if [[ -x /usr/local/bin/shellcheck ]] &&
    printf '%s  %s\n' "$LFS_SHELLCHECK_SHA256" /usr/local/bin/shellcheck | sha256sum -c - >/dev/null 2>&1; then
    shellcheck_installed=true
fi
if [[ $shellcheck_installed == false ]]; then
    if [[ ! -f $shellcheck_archive ]] ||
        ! printf '%s  %s\n' "$LFS_SHELLCHECK_ARCHIVE_SHA256" "$shellcheck_archive" | sha256sum -c - >/dev/null 2>&1; then
        [[ $mode == install ]] || fail "ShellCheck is not installed and its offline cache entry is absent or invalid: $shellcheck_archive"
        temporary=$shellcheck_archive.partial.$$
        rm -f "$temporary"
        curl -fL --retry 5 -o "$temporary" \
            "https://github.com/koalaman/shellcheck/releases/download/v$LFS_SHELLCHECK_VERSION/shellcheck-v$LFS_SHELLCHECK_VERSION.linux.x86_64.tar.xz"
        printf '%s  %s\n' "$LFS_SHELLCHECK_ARCHIVE_SHA256" "$temporary" | sha256sum -c - >/dev/null || {
            rm -f "$temporary"
            fail 'downloaded ShellCheck archive hash mismatch'
        }
        mv -f "$temporary" "$shellcheck_archive"
    fi
    temporary_dir=$(mktemp -d)
    trap 'rm -rf "$temporary_dir"; rm -f "${inrelease:-}"' EXIT
    tar -xJf "$shellcheck_archive" -C "$temporary_dir"
    shellcheck_binary=$temporary_dir/shellcheck-v$LFS_SHELLCHECK_VERSION/shellcheck
    printf '%s  %s\n' "$LFS_SHELLCHECK_SHA256" "$shellcheck_binary" | sha256sum -c - >/dev/null
    install -m 0755 "$shellcheck_binary" /usr/local/bin/shellcheck
    rm -rf "$temporary_dir"
    trap 'rm -f "${inrelease:-}"' EXIT
fi

verify_profile
