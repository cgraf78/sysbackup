# AGENTS.md

## About

`sysbackup` is a Linux-only Bash wrapper around Restic. It reads the effective
user's private configuration, so changes to parsing, installation, locking,
or success markers need tests that cannot reach a real repository.

## Layout

- `bin/sysbackup`: command dispatch, repository operations, locking, and the
  success marker.
- `lib/sysbackup/config-parser`: the project-owned parser for the trusted
  INI-style config.
- `install`: standalone checkout-backed installer for the effective user.
- `examples/`: generic config and environment templates; never add secrets.
- `test/`: parser tests plus root-isolated fake-Restic integration suites.

## Invariants

- The parser evaluates assignment values as shell code only after `sysbackup`
  verifies the config directory and files belong to the effective user and
  are protected from other users' writes. Preserve that trust boundary.
- Config and credentials belong under `~/.config/sysbackup`; the lock,
  temporary mount, and success marker belong under `~/.local/state/sysbackup`.
- Repository sections start at `repo0`, are contiguous, and name distinct
  locations. A malformed or omitted repo must not refresh the success marker.
- A backup writes the marker only after every configured repository succeeds
  through backup, forget, and prune; it records section names, never locations.
- Do not change retention or automatically delete media as incidental work.
- Keep `sysbackup.env` and machine-specific paths out of Git.

## Testing

- Run the config-parser, installer, and ordinary-user suites, then the three
  root suites named in the README, plus ShellCheck and `bash -n`.
- Root suites re-exec in a private mount namespace, overlay the effective
  user's home and test-only fake-Restic location with tmpfs, and refuse to run
  unless Restic resolves to a fake executable. Never weaken those guards.
- CI runs on Linux only because the root suites require mount namespaces.
  `.github/shellcheck-files.txt` lists shell programs; CI separately lints
  the sourced environment template, which has no executable shebang.
- `.github/cgraf78-actions.lock` owns all `cgraf78/actions` workflow pins;
  advance them together with that provider's `consumer-ci/sync.sh`.

## Release

There is no tagged release workflow. Install from a reviewed checkout of
`main` after running the host-appropriate tests.
