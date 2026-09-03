#!/usr/bin/env bash
set -euo pipefail

input=/mnt/c/controlled-inputs/ultra-minimal-wsl/debian2/v1
article_id=debian2-stock-bootstrap-v10
home=/home/jack
snapshot=20260712T000000Z
expected_inrelease=98b25b5cd185c59d34aa6e4c3e9b5b8f01bbe9d104fe2dcfbcd30dc0a14a59ed
construction_dns=${1:-}

[[ $(id -u) == 0 ]] || { echo 'Debian2 bootstrap must run as root.' >&2; exit 1; }
[[ ${WSL_DISTRO_NAME:-} == Debian2 ]] || { echo 'Debian2 bootstrap ran in the wrong distribution.' >&2; exit 1; }
[[ -d $input ]] || { echo "Staged input directory is missing: $input" >&2; exit 1; }
[[ $construction_dns =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo 'A fixture IPv4 DNS server is required for stock construction.' >&2; exit 1; }
printf 'nameserver %s\n' "$construction_dns" >/etc/resolv.conf
getent ahosts snapshot.debian.org >/dev/null || { echo "Fixture DNS server $construction_dns cannot resolve snapshot.debian.org." >&2; exit 1; }

cat >/etc/apt/sources.list <<EOF
deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/$snapshot trixie main
EOF
rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources
export DEBIAN_FRONTEND=noninteractive
apt-get update
mapfile -t inrelease_files < <(find /var/lib/apt/lists -maxdepth 1 -type f -name '*_dists_trixie_InRelease' -print)
[[ ${#inrelease_files[@]} == 1 ]] || { echo 'Pinned Debian InRelease file was not uniquely resolved.' >&2; exit 1; }
printf '%s  %s\n' "$expected_inrelease" "${inrelease_files[0]}" | sha256sum -c -
apt-get install -y ca-certificates curl direnv dirmngr git gnupg2 jq openssh-client pinentry-curses restic shellcheck sqlite3 sudo tmux unzip xz-utils zoxide
chezmoi_tmp=$(mktemp -d)
tar -xzf "$input/chezmoi_2.69.4_linux_amd64.tar.gz" -C "$chezmoi_tmp"
install -m 0755 "$chezmoi_tmp/chezmoi" /usr/local/bin/chezmoi
rm -rf "$chezmoi_tmp"
chezmoi --version

if ! id jack >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --uid 1000 jack
fi
usermod -aG sudo jack
install -d -m 0755 /etc/sudoers.d
printf 'jack ALL=(ALL:ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/90-jack
chmod 0440 /etc/sudoers.d/90-jack
install -d -o jack -g jack -m 0700 /run/user/1000
export XDG_RUNTIME_DIR=/run/user/1000

install -d -o jack -g jack "$home/.local/share" "$home/.local/bin" "$home/git" "$home/work"
clone_bundle() {
  local bundle=$1 destination=$2 commit=$3 remote=$4
  [[ ! -e $destination ]] || { echo "Destination already exists: $destination" >&2; exit 1; }
  git clone --no-checkout "$input/$bundle" "$destination"
  git -C "$destination" checkout --detach "$commit"
  git -C "$destination" branch -f main "$commit"
  git -C "$destination" checkout main
  git -C "$destination" remote set-url origin "$remote"
  chown -R jack:jack "$destination"
}
clone_bundle dotfiles.bundle "$home/.local/share/chezmoi" 05710eae9b09e645f7ab63cb211c740f1aa75c8f https://github.com/jchidley/dotfiles.git
clone_bundle agent-skills.bundle "$home/git/agent-skills" 4dd2f4befbf41910967a41cc43b4e18916c8a262 https://github.com/jchidley/agent-skills.git
clone_bundle ak.bundle "$home/git/ak" 7c53208f1b48109d8db1b6ed191131d00872c18f https://github.com/jchidley/ak.git
clone_bundle tools.bundle "$home/tools" 42c10893f78ea81d2ad5b57248cbb864b73cc257 https://github.com/jchidley/tools.git

fnm_dir="$home/.local/share/fnm"
install -d -o jack -g jack "$fnm_dir"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -q "$input/fnm-linux-v1.38.1.zip" -d "$tmp/fnm"
install -o jack -g jack -m 0755 "$tmp/fnm/fnm" "$fnm_dir/fnm"
node_install="$fnm_dir/node-versions/v22.19.0/installation"
install -d -o jack -g jack "$node_install"
tar -xJf "$input/node-v22.19.0-linux-x64.tar.xz" --strip-components=1 -C "$node_install"
chown -R jack:jack "$fnm_dir"
runuser -u jack -- env HOME="$home" "$fnm_dir/fnm" default v22.19.0

tar -xzf "$input/mcfly-v0.9.4-x86_64-unknown-linux-musl.tar.gz" -C "$tmp"
install -o jack -g jack -m 0755 "$tmp/mcfly" "$home/.local/bin/mcfly"
chown -R jack:jack "$home"

mv "$fnm_dir/fnm" "$fnm_dir/fnm.real"
cat >"$fnm_dir/fnm" <<'EOF'
#!/usr/bin/env bash
if [[ $# == 1 && $1 == default ]]; then
  printf 'v22.19.0\n'
  exit 0
fi
exec "$(dirname -- "$0")/fnm.real" "$@"
EOF
chown jack:jack "$fnm_dir/fnm"
chmod 0755 "$fnm_dir/fnm"
if runuser -u jack -- env HOME="$home" bash -c '
  set -euo pipefail
  export PATH="$HOME/.local/share/fnm:$PATH"
  eval "$("$HOME/.local/share/fnm/fnm" env --shell bash)"
  "$HOME/.local/share/fnm/fnm" use v22.19.0
  npm install -g /mnt/c/controlled-inputs/ultra-minimal-wsl/debian2/v1/earendil-works-pi-coding-agent-0.84.4.tgz
  cd "$HOME/.local/share/chezmoi/scripts/bootstrap"
  BOOTSTRAP_MODE=core BOOTSTRAP_PROFILE=dev APPLY_CHEZMOI=1 ./debian-bootstrap-safe.sh
'; then
  mv "$fnm_dir/fnm.real" "$fnm_dir/fnm"
else
  status=$?
  mv "$fnm_dir/fnm.real" "$fnm_dir/fnm"
  exit "$status"
fi

# The committed dotfiles apply includes a personal-machine WSL integration
# script. Keep its Linux startup files, while the Windows controller removes
# the fixture-wide .wslconfig change. Retain only this article's default user.
cat >/etc/wsl.conf <<'EOF'
[user]
default=jack
EOF

for item in \
  "$home/.local/share/chezmoi:05710eae9b09e645f7ab63cb211c740f1aa75c8f" \
  "$home/git/agent-skills:4dd2f4befbf41910967a41cc43b4e18916c8a262" \
  "$home/git/ak:7c53208f1b48109d8db1b6ed191131d00872c18f" \
  "$home/tools:42c10893f78ea81d2ad5b57248cbb864b73cc257"; do
  path=${item%%:*}; expected=${item##*:}
  [[ $(runuser -u jack -- git -C "$path" rev-parse HEAD) == "$expected" ]] || { echo "Commit mismatch: $path" >&2; exit 1; }
done

runuser -u jack -- env HOME="$home" bash -lic '
  set -euo pipefail
  command -v chezmoi
  command -v pi
  test -r "$HOME/.bashrc"
  pi list | tr -d "\r" | grep -F "$HOME/git/agent-skills"
  pi --version
' | tee /tmp/debian2-shell-verification.log

install -d -m 0755 /var/lib/debian2-article
packages=$(dpkg-query -W -f='${binary:Package}=${Version}\n' | LC_ALL=C sort | jq -Rsc 'split("\n")[:-1]')
jq -n \
  --arg articleId "$article_id" \
  --arg distribution "$WSL_DISTRO_NAME" \
  --arg createdUtc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg kernel "$(uname -r)" \
  --arg node "$($node_install/bin/node --version)" \
  --arg npm "$($node_install/bin/npm --version)" \
  --arg pi "$($node_install/bin/pi --version)" \
  --arg fnm "$($fnm_dir/fnm --version)" \
  --arg mcfly "$($home/.local/bin/mcfly --version)" \
  --arg chezmoi "$(chezmoi --version)" \
  --argjson packages "$packages" \
  '{schema:1,articleId:$articleId,distribution:$distribution,defaultUser:"jack",createdUtc:$createdUtc,stockKernel:$kernel,node:$node,npm:$npm,pi:$pi,fnm:$fnm,mcfly:$mcfly,chezmoi:$chezmoi,packages:$packages,secrets:"none"}' \
  >/var/lib/debian2-article/manifest.json
chmod 0644 /var/lib/debian2-article/manifest.json
cat /var/lib/debian2-article/manifest.json
