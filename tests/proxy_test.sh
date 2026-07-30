#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

fixture_file="$temp_dir/scutil-output"
count_file="$temp_dir/scutil-count"
fake_scutil="$temp_dir/scutil"

cat >"$fake_scutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=0
if [[ -f "$AUTOPROXY_SCUTIL_COUNT_FILE" ]]; then
    count="$(<"$AUTOPROXY_SCUTIL_COUNT_FILE")"
fi
printf '%s\n' "$((count + 1))" >"$AUTOPROXY_SCUTIL_COUNT_FILE"
cat "$AUTOPROXY_SCUTIL_FIXTURE"
EOF
chmod +x "$fake_scutil"

cat >"$fixture_file" <<'EOF'
<dictionary> {
  ExceptionsList : <array> {
    0 : localhost
    1 : *.example.test
  }
  HTTPEnable : 1
  HTTPPort : 7890
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 7890
  HTTPSProxy : 127.0.0.1
}
EOF

AUTOPROXY_SCUTIL_BIN="$fake_scutil" \
AUTOPROXY_SCUTIL_FIXTURE="$fixture_file" \
AUTOPROXY_SCUTIL_COUNT_FILE="$count_file" \
AUTOPROXY_PLUGIN="$repo_dir/zsh-osx-autoproxy.plugin.zsh" \
FIXTURE_FILE="$fixture_file" \
/bin/zsh <<'EOF'
awk() {
    print -u2 "awk must not be called"
    return 97
}

sed() {
    print -u2 "sed must not be called"
    return 98
}

source "$AUTOPROXY_PLUGIN"

[[ "$http_proxy" == "http://127.0.0.1:7890" ]]
[[ "$https_proxy" == "http://127.0.0.1:7890" ]]
[[ "$no_proxy" == "localhost,*.example.test" ]]

print -r -- '<dictionary> {
  HTTPEnable : 0
  HTTPSEnable : 0
}' >"$FIXTURE_FILE"

proxy 1

[[ -z "${http_proxy:-}" ]]
[[ -z "${https_proxy:-}" ]]
[[ -z "${no_proxy:-}" ]]
EOF

if [[ "$(<"$count_file")" != "2" ]]; then
    printf 'expected scutil to be called twice, got %s\n' "$(<"$count_file")" >&2
    exit 1
fi

printf 'proxy tests passed\n'
