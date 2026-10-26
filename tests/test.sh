#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2154,SC2209
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary=$(mktemp -d)
test_domain=com.example.browser-privacy-macos-test

cleanup() {
  /usr/bin/defaults delete "$test_domain" >/dev/null 2>&1 || true
  rm -rf "$temporary"
}
trap cleanup EXIT

bash -n "$repo_dir/browser-harden" "$repo_dir/install.sh"
/usr/bin/plutil -convert xml1 -o /dev/null -- "$repo_dir/firefox-policies.json"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$repo_dir/browser-harden" "$repo_dir/install.sh" "$repo_dir/tests/test.sh"
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
  echo "installer unexpectedly replaced an unowned path" >&2
  exit 1
fi
grep -q '^keep$' "$temporary/foreign-home/.local/bin/browser-harden"

export BROWSER_PRIVACY_STATE_HOME="$temporary/state"
export BROWSER_PRIVACY_FIREFOX_POLICY_SOURCE="$repo_dir/firefox-policies.json"
source "$repo_dir/browser-harden"

browser_id='test'
browser_name='Test'
domain=$test_domain
chromium_backup_file="$state_root/test.plist"
policies=(
  'bool|ExistingBool|false'
  'int|ExistingInt|2'
  'string|ExistingString|after'
  'bool|PreviouslyAbsent|true'
)

/usr/bin/defaults write "$domain" ExistingBool -bool true
/usr/bin/defaults write "$domain" ExistingInt -int 7
/usr/bin/defaults write "$domain" ExistingString -string before
apply_chromium_policies >/dev/null
apply_chromium_policies >/dev/null
[[ "$(stat -f '%Lp' "$chromium_backup_file")" == 600 ]]
[[ "$(stat -f '%Lp' "$state_root")" == 700 ]]
[[ "$(/usr/bin/defaults read "$domain" ExistingBool)" == 0 ]]
[[ "$(/usr/bin/defaults read "$domain" ExistingInt)" == 2 ]]
[[ "$(/usr/bin/defaults read "$domain" ExistingString)" == after ]]
[[ "$(/usr/bin/defaults read "$domain" PreviouslyAbsent)" == 1 ]]
show_chromium_status >/dev/null

remove_chromium_policies >/dev/null
[[ "$(/usr/bin/defaults read "$domain" ExistingBool)" == 1 ]]
[[ "$(/usr/bin/defaults read "$domain" ExistingInt)" == 7 ]]
[[ "$(/usr/bin/defaults read "$domain" ExistingString)" == before ]]
if /usr/bin/defaults read "$domain" PreviouslyAbsent >/dev/null 2>&1; then
  echo "previously absent policy was not removed" >&2
  exit 1
fi
[[ ! -e "$chromium_backup_file" ]]
if (remove_chromium_policies >/dev/null 2>&1); then
  echo "remove unexpectedly succeeded without a backup" >&2
  exit 1
fi

export BROWSER_PRIVACY_FIREFOX_APP="$temporary/Firefox.app"
firefox_resources="$BROWSER_PRIVACY_FIREFOX_APP/Contents/Resources"
mkdir -p "$firefox_resources/distribution"
original_policy="$temporary/original-firefox-policies.json"
printf '%s\n' '{"policies":{"Original":true}}' > "$original_policy"
cp "$original_policy" "$firefox_resources/distribution/policies.json"

apply_firefox_policy >/dev/null
owns_firefox_policy
show_firefox_status >/dev/null
apply_firefox_policy >/dev/null
remove_firefox_policy >/dev/null
cmp -s "$original_policy" "$firefox_resources/distribution/policies.json"

printf 'All tests passed.\n'
