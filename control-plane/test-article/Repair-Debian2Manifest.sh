#!/usr/bin/env bash
set -euo pipefail

manifest=/var/lib/debian2-article/manifest.json
node_bin=/home/jack/.local/share/fnm/node-versions/v22.19.0/installation/bin
backup=$manifest.pre-repair
temporary=$manifest.tmp
success=0
cleanup() {
  rm -f "$temporary"
  if [[ $success != 1 && -f $backup ]]; then
    mv -f "$backup" "$manifest"
  else
    rm -f "$backup"
  fi
}
trap cleanup EXIT

[[ $(id -u) == 0 ]] || { echo 'Manifest repair must run as root.' >&2; exit 1; }
[[ ${WSL_DISTRO_NAME:-} == Debian2 ]] || { echo 'Manifest repair ran in the wrong distribution.' >&2; exit 1; }
[[ -r $manifest ]] || { echo 'Debian2 article manifest is missing.' >&2; exit 1; }
[[ -x $node_bin/node && -x $node_bin/npm && -x $node_bin/pi ]] || { echo 'Pinned Node/Pi installation is incomplete.' >&2; exit 1; }
cp -p "$manifest" "$backup"
export PATH="$node_bin:$PATH"
node_version=$(node --version)
npm_version=$(npm --version)
pi_version=$(pi --version)
[[ $node_version == v22.19.0 ]] || { echo "Unexpected Node version: $node_version" >&2; exit 1; }
[[ -n $npm_version && $pi_version == 0.84.4 ]] || { echo 'npm or Pi version verification failed.' >&2; exit 1; }
jq --arg npm "$npm_version" --arg pi "$pi_version" --arg corrected "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.npm=$npm | .pi=$pi | .manifestCorrectedUtc=$corrected' "$manifest" >"$temporary"
jq -e '.articleId=="debian2-stock-bootstrap-v10" and .defaultUser=="jack" and .node=="v22.19.0" and (.npm|length)>0 and .pi=="0.84.4" and .secrets=="none"' "$temporary" >/dev/null
chown root:root "$temporary"
chmod 0644 "$temporary"
mv -f "$temporary" "$manifest"
runuser -u jack -- env HOME=/home/jack XDG_RUNTIME_DIR=/run/user/1000 bash -lic 'test "$(pi --version)" = 0.84.4; pi list | tr -d "\r" | grep -F "$HOME/git/agent-skills"'
success=1
cat "$manifest"
