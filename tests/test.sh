#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2154,SC2209
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary=$(mktemp -d)
test_domains=()

fail() {
  echo "$1" >&2
  exit 1
}

cleanup() {
  local test_domain

  for test_domain in "${test_domains[@]}"; do
    /usr/bin/defaults delete "$test_domain" >/dev/null 2>&1 || true
  done
  rm -rf "$temporary"
}
trap cleanup EXIT

bash -n "$repo_dir/browser-harden" "$repo_dir/install.sh" "$repo_dir/tests/validate-firefox-policy.sh"
/usr/bin/plutil -convert xml1 -o /dev/null -- "$repo_dir/firefox-policies.json"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$repo_dir/browser-harden" "$repo_dir/install.sh" "$repo_dir/tests/test.sh" \
    "$repo_dir/tests/validate-firefox-policy.sh"
fi
if command -v check-jsonschema >/dev/null 2>&1; then
  "$repo_dir/tests/validate-firefox-policy.sh"
fi

HOME="$temporary/home" "$repo_dir/install.sh" >/dev/null
[[ "$(readlink "$temporary/home/.local/bin/browser-harden")" == "$repo_dir/browser-harden" ]]
[[ "$(readlink "$temporary/home/.local/bin/brave-harden")" == "$repo_dir/browser-harden" ]]
[[ "$(readlink "$temporary/home/.local/share/browser-privacy-macos/firefox-policies.json")" == \
  "$repo_dir/firefox-policies.json" ]]
HOME="$temporary/home" "$repo_dir/install.sh" remove >/dev/null
[[ ! -e "$temporary/home/.local/bin/browser-harden" ]]

mkdir -p "$temporary/foreign-home/.local/bin"
printf 'keep\n' > "$temporary/foreign-home/.local/bin/browser-harden"
if HOME="$temporary/foreign-home" "$repo_dir/install.sh" >/dev/null 2>&1; then
  fail "installer unexpectedly replaced an unowned path"
fi
grep -q '^keep$' "$temporary/foreign-home/.local/bin/browser-harden"

mkdir -p "$temporary/late-collision-home/.local/share/browser-privacy-macos"
printf 'keep\n' > "$temporary/late-collision-home/.local/share/browser-privacy-macos/firefox-policies.json"
if HOME="$temporary/late-collision-home" "$repo_dir/install.sh" >/dev/null 2>&1; then
  fail "installer unexpectedly ignored a late target collision"
fi
[[ ! -e "$temporary/late-collision-home/.local/bin/browser-harden" ]]
[[ ! -e "$temporary/late-collision-home/.local/bin/brave-harden" ]]
grep -q '^keep$' "$temporary/late-collision-home/.local/share/browser-privacy-macos/firefox-policies.json"

export BROWSER_PRIVACY_STATE_HOME="$temporary/state"
export BROWSER_PRIVACY_FIREFOX_POLICY_SOURCE="$repo_dir/firefox-policies.json"
source "$repo_dir/browser-harden"

cat > "$temporary/defaults-wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == export && "${2:-}" == "${FAIL_DEFAULTS_EXPORT_FOR:-}" ]]; then
  exit 1
fi
if [[ "${1:-}" == write && "${2:-}" == "${FAIL_DEFAULTS_WRITE_FOR:-}" && \
  "${3:-}" == "${FAIL_DEFAULTS_WRITE_KEY:-}" ]]; then
  exit 1
fi
exec /usr/bin/defaults "$@"
EOF
chmod +x "$temporary/defaults-wrapper"

browser_id='test'
browser_name='Test'
domain='com.example.browser-privacy-macos-main'
test_domains+=("$domain")
chromium_backup_file="$state_root/test.plist"
policies=(
  'bool|ExistingBool|false'
  'int|ExistingInt|2'
  'string|ExistingString|after'
  'bool|MalformedBool|false'
  'bool|RemovedLater|true'
  'bool|PreviouslyAbsent|true'
)

/usr/bin/defaults write "$domain" ExistingBool -bool true
/usr/bin/defaults write "$domain" ExistingInt -int 7
/usr/bin/defaults write "$domain" ExistingString -string before
/usr/bin/defaults write "$domain" MalformedBool -string true
/usr/bin/defaults write "$domain" RemovedLater -bool false
apply_chromium_policies >/dev/null
apply_chromium_policies >/dev/null
[[ "$(stat -f '%Lp' "$chromium_backup_file")" == 600 ]]
[[ "$(stat -f '%Lp' "$state_root")" == 700 ]]
[[ "$(/usr/bin/plutil -extract manifest raw -o - "$chromium_backup_file")" == 6 ]]
[[ "$(/usr/bin/defaults read "$domain" ExistingBool)" == 0 ]]
[[ "$(/usr/bin/defaults read "$domain" ExistingInt)" == 2 ]]
[[ "$(/usr/bin/defaults read "$domain" ExistingString)" == after ]]
[[ "$(/usr/bin/defaults read "$domain" MalformedBool)" == 0 ]]
[[ "$(/usr/bin/defaults read "$domain" RemovedLater)" == 1 ]]
[[ "$(/usr/bin/defaults read "$domain" PreviouslyAbsent)" == 1 ]]

/usr/bin/defaults write "$domain" AddedLater -string keep-added
policies=(
  'bool|ExistingBool|false'
  'int|ExistingInt|2'
  'string|ExistingString|after'
  'bool|MalformedBool|false'
  'bool|PreviouslyAbsent|true'
  'bool|AddedLater|true'
)
export FAIL_DEFAULTS_WRITE_FOR="$domain"
export FAIL_DEFAULTS_WRITE_KEY=AddedLater
defaults_bin="$temporary/defaults-wrapper"
if apply_chromium_policies >/dev/null 2>&1; then
  fail "Chromium policy update unexpectedly succeeded after a write failure"
fi
defaults_bin=/usr/bin/defaults
unset FAIL_DEFAULTS_WRITE_FOR FAIL_DEFAULTS_WRITE_KEY
[[ "$(/usr/bin/plutil -extract manifest raw -o - "$chromium_backup_file")" == 6 ]]
if /usr/bin/plutil -type entries.AddedLater "$chromium_backup_file" >/dev/null 2>&1; then
  fail "failed policy update left an unowned backup entry"
fi
apply_chromium_policies >/dev/null
[[ "$(/usr/bin/plutil -extract manifest raw -o - "$chromium_backup_file")" == 7 ]]
[[ "$(/usr/bin/plutil -extract entries.AddedLater.type raw -o - "$chromium_backup_file")" == string ]]
show_chromium_status >/dev/null

cp -p "$chromium_backup_file" "$temporary/good-chromium-backup.plist"
/usr/bin/plutil -create xml1 "$chromium_backup_file"
chmod 600 "$chromium_backup_file"
if remove_chromium_policies >/dev/null 2>&1; then
  fail "Chromium removal unexpectedly accepted a damaged backup"
fi
[[ "$(/usr/bin/defaults read "$domain" ExistingBool)" == 0 ]]
[[ -f "$chromium_backup_file" ]]
mv "$temporary/good-chromium-backup.plist" "$chromium_backup_file"

remove_chromium_policies >/dev/null
[[ "$(/usr/bin/defaults read "$domain" ExistingBool)" == 1 ]]
[[ "$(/usr/bin/defaults read "$domain" ExistingInt)" == 7 ]]
[[ "$(/usr/bin/defaults read "$domain" ExistingString)" == before ]]
[[ "$(/usr/bin/defaults read "$domain" MalformedBool)" == true ]]
[[ "$(/usr/bin/defaults read-type "$domain" MalformedBool)" == 'Type is string' ]]
[[ "$(/usr/bin/defaults read "$domain" RemovedLater)" == 0 ]]
[[ "$(/usr/bin/defaults read "$domain" AddedLater)" == keep-added ]]
[[ "$(/usr/bin/defaults read-type "$domain" AddedLater)" == 'Type is string' ]]
if /usr/bin/defaults read "$domain" PreviouslyAbsent >/dev/null 2>&1; then
  fail "previously absent policy was not removed"
fi
[[ ! -e "$chromium_backup_file" ]]
if remove_chromium_policies >/dev/null 2>&1; then
  fail "remove unexpectedly succeeded without a backup"
fi

browser_id='export-failure'
browser_name='Export failure test'
domain='com.example.browser-privacy-macos-export-failure'
test_domains+=("$domain")
chromium_backup_file="$state_root/export-failure.plist"
policies=('bool|Existing|false')
/usr/bin/defaults write "$domain" Existing -bool true
export FAIL_DEFAULTS_EXPORT_FOR="$domain"
defaults_bin="$temporary/defaults-wrapper"
if apply_chromium_policies >/dev/null 2>&1; then
  fail "Chromium apply unexpectedly accepted a failed export"
fi
defaults_bin=/usr/bin/defaults
unset FAIL_DEFAULTS_EXPORT_FOR
[[ ! -e "$chromium_backup_file" ]]
[[ "$(/usr/bin/defaults read "$domain" Existing)" == 1 ]]

browser_id='partial'
browser_name='Partial apply test'
domain='com.example.browser-privacy-macos-partial'
test_domains+=("$domain")
chromium_backup_file="$state_root/partial.plist"
policies=(
  'bool|First|false'
  'bool|Second|false'
)
/usr/bin/defaults write "$domain" First -bool true
/usr/bin/defaults write "$domain" Second -bool true
export FAIL_DEFAULTS_WRITE_FOR="$domain"
export FAIL_DEFAULTS_WRITE_KEY=Second
defaults_bin="$temporary/defaults-wrapper"
if apply_chromium_policies >/dev/null 2>&1; then
  fail "Chromium apply unexpectedly succeeded after a write failure"
fi
defaults_bin=/usr/bin/defaults
unset FAIL_DEFAULTS_WRITE_FOR FAIL_DEFAULTS_WRITE_KEY
[[ "$(/usr/bin/defaults read "$domain" First)" == 1 ]]
[[ "$(/usr/bin/defaults read-type "$domain" First)" == 'Type is boolean' ]]
[[ "$(/usr/bin/defaults read "$domain" Second)" == 1 ]]
[[ ! -e "$chromium_backup_file" ]]
/usr/bin/defaults write "$domain" First -string fresh
apply_chromium_policies >/dev/null
remove_chromium_policies >/dev/null
[[ "$(/usr/bin/defaults read "$domain" First)" == fresh ]]
[[ "$(/usr/bin/defaults read-type "$domain" First)" == 'Type is string' ]]

browser_id='absent-domain'
browser_name='Absent domain test'
domain='com.example.browser-privacy-macos-absent'
test_domains+=("$domain")
chromium_backup_file="$state_root/absent-domain.plist"
policies=('bool|OnlyPolicy|true')
/usr/bin/defaults delete "$domain" >/dev/null 2>&1 || true
apply_chromium_policies >/dev/null
remove_chromium_policies >/dev/null
if /usr/bin/defaults read "$domain" OnlyPolicy >/dev/null 2>&1; then
  fail "policy from an originally absent domain was not removed"
fi

make_firefox_app() {
  local app=$1 version=$2 remoting_name=$3

  mkdir -p "$app/Contents/Resources/distribution"
  /usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
  printf '[App]\nName=Firefox\nVersion=%s\nRemotingName=%s\n' "$version" "$remoting_name" > \
    "$app/Contents/Resources/application.ini"
}

firefox_app_one="$temporary/Firefox One.app"
make_firefox_app "$firefox_app_one" 158.0 firefox
export BROWSER_PRIVACY_FIREFOX_APP="$firefox_app_one"
firefox_resources="$firefox_app_one/Contents/Resources"
original_policy="$temporary/original-firefox-policies.json"
printf '%s\n' '{"policies":{"Original":true}}' > "$original_policy"
cp "$original_policy" "$firefox_resources/distribution/policies.json"

apply_firefox_policy >/dev/null
owns_firefox_policy
[[ "$(<"$firefox_backup_dir/app-path")" == "$(cd "$firefox_app_one" && pwd -P)" ]]
show_firefox_status >/dev/null
apply_firefox_policy >/dev/null
remove_firefox_policy >/dev/null
cmp -s "$original_policy" "$firefox_resources/distribution/policies.json"

apply_firefox_policy >/dev/null
firefox_app_two="$temporary/Firefox Two.app"
make_firefox_app "$firefox_app_two" 158.0 firefox
second_original="$temporary/second-firefox-policies.json"
printf '%s\n' '{"policies":{"Second":true}}' > "$second_original"
cp "$second_original" "$firefox_app_two/Contents/Resources/distribution/policies.json"
export BROWSER_PRIVACY_FIREFOX_APP="$firefox_app_two"
if apply_firefox_policy >/dev/null 2>&1; then
  fail "Firefox apply unexpectedly reused another application's backup"
fi
[[ "$(readlink "$firefox_resources/distribution/policies.json")" == "$firefox_policy_source" ]]
cmp -s "$second_original" "$firefox_app_two/Contents/Resources/distribution/policies.json"
[[ -d "$state_root/firefox" ]]
export BROWSER_PRIVACY_FIREFOX_APP="$firefox_app_one"
remove_firefox_policy >/dev/null
cmp -s "$original_policy" "$firefox_resources/distribution/policies.json"

firefox_interrupted="$temporary/Firefox Interrupted.app"
make_firefox_app "$firefox_interrupted" 158.0 firefox
interrupted_original="$temporary/interrupted-firefox-policies.json"
printf '%s\n' '{"policies":{"Interrupted":true}}' > "$interrupted_original"
cp "$interrupted_original" "$firefox_interrupted/Contents/Resources/distribution/policies.json"
export BROWSER_PRIVACY_FIREFOX_APP="$firefox_interrupted"
set_firefox_paths
backup_firefox_policy
cmp -s "$interrupted_original" "$firefox_policy_target"
apply_firefox_policy >/dev/null
owns_firefox_policy
remove_firefox_policy >/dev/null
cmp -s "$interrupted_original" "$firefox_policy_target"

firefox_unused="$temporary/Firefox Unused Backup.app"
make_firefox_app "$firefox_unused" 158.0 firefox
unused_original="$temporary/unused-firefox-policies.json"
printf '%s\n' '{"policies":{"Unused":true}}' > "$unused_original"
cp "$unused_original" "$firefox_unused/Contents/Resources/distribution/policies.json"
export BROWSER_PRIVACY_FIREFOX_APP="$firefox_unused"
set_firefox_paths
backup_firefox_policy
remove_firefox_policy >/dev/null
cmp -s "$unused_original" "$firefox_policy_target"
[[ ! -e "$state_root/firefox" ]]

firefox_absent="$temporary/Firefox Absent.app"
make_firefox_app "$firefox_absent" 158.0 firefox
export BROWSER_PRIVACY_FIREFOX_APP="$firefox_absent"
apply_firefox_policy >/dev/null
remove_firefox_policy >/dev/null
[[ ! -e "$firefox_absent/Contents/Resources/distribution/policies.json" ]]

firefox_symlink="$temporary/Firefox Symlink.app"
make_firefox_app "$firefox_symlink" 158.0 firefox
legacy_target="$temporary/legacy-firefox-policy.json"
printf '%s\n' '{"policies":{"Legacy":true}}' > "$legacy_target"
ln -s "$legacy_target" "$firefox_symlink/Contents/Resources/distribution/policies.json"
export BROWSER_PRIVACY_FIREFOX_APP="$firefox_symlink"
apply_firefox_policy >/dev/null
remove_firefox_policy >/dev/null
[[ "$(readlink "$firefox_symlink/Contents/Resources/distribution/policies.json")" == "$legacy_target" ]]

firefox_old="$temporary/Firefox Old.app"
make_firefox_app "$firefox_old" 157.0 firefox
export BROWSER_PRIVACY_FIREFOX_APP="$firefox_old"
if apply_firefox_policy >/dev/null 2>&1; then
  fail "Firefox apply unexpectedly accepted an unsupported version"
fi
[[ ! -e "$state_root/firefox" ]]
[[ ! -e "$firefox_old/Contents/Resources/distribution/policies.json" ]]

firefox_esr="$temporary/Firefox ESR.app"
make_firefox_app "$firefox_esr" 158.0 firefox-esr
export BROWSER_PRIVACY_FIREFOX_APP="$firefox_esr"
if apply_firefox_policy >/dev/null 2>&1; then
  fail "Firefox apply unexpectedly accepted Firefox ESR"
fi
[[ ! -e "$state_root/firefox" ]]
[[ ! -e "$firefox_esr/Contents/Resources/distribution/policies.json" ]]

printf 'All tests passed.\n'
