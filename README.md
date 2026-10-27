# Browser Privacy for macOS

An opinionated, reversible privacy policy runner for Brave, Google Chrome, and Firefox on macOS.

It applies one strict preset, reports drift, and restores the browser policy values that existed before the first application.
Browser profiles remain untouched because they contain credentials, cookies, history, extensions, and machine-specific state.

> [!WARNING]
> This configuration intentionally trades compatibility and convenience for privacy. Expect persistent logins, federated sign-ins,
> HTTP-only sites, WebRTC calls, and some fingerprint-sensitive sites to break.

## Install

```sh
git clone git@github.com:ctbaum/browser-privacy-macos.git ~/dev/browser-privacy-macos
cd ~/dev/browser-privacy-macos
./install.sh
```

The installer creates these links:

- `~/.local/bin/browser-harden`
- `~/.local/bin/brave-harden`, a compatibility alias for Brave
- `~/.local/share/browser-privacy-macos/firefox-policies.json`

It refuses to replace paths it does not own.

## Usage

```sh
browser-harden brave apply
browser-harden brave status
browser-harden brave remove

browser-harden chrome apply
browser-harden firefox apply
```

Fully quit and reopen the affected browser after `apply` or `remove`.

Verify loaded policies at:

- Brave: `brave://policy`
- Chrome: `chrome://policy`
- Firefox: `about:policies`

## What it changes

### Shared Chromium settings

Brave and Chrome receive current-user macOS policies that:

- block third-party cookies;
- disable alternate error pages, prediction, search suggestions, cloud spellcheck, and URL-keyed data collection;
- restrict WebRTC to avoid non-proxied UDP;
- retain Standard Safe Browsing rather than Enhanced Protection.

Chromium reports these as **Recommended** policies, not root-enforced policies.

### Brave

The Brave set also:

- disables metrics, P3A, stats pings, Web Discovery, AI Chat, News, Rewards, Talk, VPN, and Wallet;
- enables GPC, De-AMP, debouncing, query-parameter filtering, and language reduction;
- enables Shields ad blocking and fingerprinting protection;
- requires HTTPS and forgets first-party storage when tabs close or navigate away.

### Chrome

The Chrome set also:

- requires HTTPS;
- makes first-party cookies session-only;
- disables Gemini integration.

Chrome blocks `MetricsReportingEnabled` at current-user policy scope. Metrics reporting therefore remains controlled through
Chrome's own Privacy and security settings.

### Firefox

Regular Firefox 158 or newer receives a tracked `policies.json` linked into its application bundle. Firefox ESR is refused because
it does not support the preset's `ClearOnShutdown` policy. The set:

- enables strict Enhanced Tracking Protection, GPC, fingerprint resistance, and letterboxing;
- blocks third-party cookies and clears cookies, storage, and cache on shutdown;
- disables telemetry, studies, sponsored surfaces, recommendations, search suggestions, prefetching, and generative AI;
- restricts WebRTC and requires HTTPS.

Firefox will display “Your browser is being managed by your organization.” In this case, the organization is this local policy
file.

## Safe rollback

Before changing each Chromium key for the first time, the tool saves its value and property-list type in a mode-`600` backup
under:

```text
~/.local/state/browser-privacy-macos/
```

The backup manifest retains every key managed by any applied version of the preset. `remove` restores from that manifest
rather than from the current preset, then deletes the backup. A failed `apply` restores the values changed by that invocation.

For Firefox, an existing `policies.json` file or symlink and the canonical application path are similarly saved and restored.
A backup cannot be reused for Firefox at another path. If an apply is interrupted after the backup is saved, a matching
original file can be resumed or safely removed.

Missing, unreadable, damaged, and older backup formats are refused rather than guessed. If you already have a backup created
by an older version of this project, remove its policies with that version before updating.

Remove browser settings before uninstalling the command:

```sh
browser-harden brave remove
browser-harden chrome remove
browser-harden firefox remove
./install.sh remove
```

## Limitations

- macOS only.
- Firefox application updates can remove the policy link. Run `browser-harden firefox status` after updating and reapply if
  needed.
- Firefox requires the regular release, version 158 or newer. Firefox ESR is not supported by this preset.
- The Firefox application bundle must be writable by the current user.
- There is one strict preset. Per-site exceptions and softer presets are intentionally out of scope for now.
- This is a privacy configuration, not an audited security baseline.

Tested with Brave 1.96.60, Google Chrome 155.0.8059.85, and Firefox 158.0.

## Development

```sh
./tests/test.sh
```

The test covers installer preflight, transactional Chromium changes, typed per-key rollback, Firefox path and interruption
recovery, minimum Firefox versions, shell syntax, and ShellCheck. In CI it also validates `firefox-policies.json` against the
Firefox 158 policy schema and rejects unknown policy names.

## License

MIT
