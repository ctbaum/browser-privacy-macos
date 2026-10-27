#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
bin_dir="$HOME/.local/bin"
share_dir="$HOME/.local/share/browser-privacy-macos"

preflight_install_link() {
  local source=$1 target=$2

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
      return 0
    fi
    echo "Refusing to replace existing path: $target" >&2
    return 1
  fi
}

install_link() {
  local source=$1 target=$2

  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
    return 0
  fi
  ln -s "$source" "$target"
}

preflight_remove_link() {
  local source=$1 target=$2

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return 0
  fi
  if [[ ! -L "$target" || "$(readlink "$target")" != "$source" ]]; then
    echo "Refusing to remove unowned path: $target" >&2
    return 1
  fi
}

remove_link() {
  local target=$2

  if [[ -e "$target" || -L "$target" ]]; then
    rm "$target"
  fi
}

case "${1:-install}" in
  install)
    preflight_install_link "$repo_dir/browser-harden" "$bin_dir/browser-harden"
    preflight_install_link "$repo_dir/browser-harden" "$bin_dir/brave-harden"
    preflight_install_link "$repo_dir/firefox-policies.json" "$share_dir/firefox-policies.json"
    mkdir -p "$bin_dir" "$share_dir"
    install_link "$repo_dir/browser-harden" "$bin_dir/browser-harden"
    install_link "$repo_dir/browser-harden" "$bin_dir/brave-harden"
    install_link "$repo_dir/firefox-policies.json" "$share_dir/firefox-policies.json"
    echo "Installed browser-harden into $bin_dir."
    ;;
  remove)
    preflight_remove_link "$repo_dir/browser-harden" "$bin_dir/browser-harden"
    preflight_remove_link "$repo_dir/browser-harden" "$bin_dir/brave-harden"
    preflight_remove_link "$repo_dir/firefox-policies.json" "$share_dir/firefox-policies.json"
    remove_link "$repo_dir/browser-harden" "$bin_dir/browser-harden"
    remove_link "$repo_dir/browser-harden" "$bin_dir/brave-harden"
    remove_link "$repo_dir/firefox-policies.json" "$share_dir/firefox-policies.json"
    rmdir "$share_dir" 2>/dev/null || true
    echo "Removed browser-harden links. Browser policies and local backups were left untouched."
    ;;
  *)
    echo "Usage: ${0##*/} [install|remove]" >&2
    exit 2
    ;;
esac
