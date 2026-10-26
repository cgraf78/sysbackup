# AGENTS.md

## About

`sysbackup` is a Linux-only Bash wrapper around Restic. It runs as root and
reads root-owned configuration, so changes to parsing, installation, locking,
or success markers need tests that cannot reach a real repository.

## Layout

- `sysbackup`: command dispatch, repository operations, locking, and the
  success marker.
- `config-parser`: the project-owned parser for the trusted INI-style config.
- `install` and `install.recipe`: root installer and its file manifest.
- `examples/`: generic config and environment templates; never add secrets.
- `test/`: parser tests plus root-isolated fake-Restic integration suites.

## Invariants

- The parser evaluates assignment values as shell code only after `sysbackup`
  verifies the config directory and files are root-owned and protected from
  non-root writes. Preserve that trust boundary.
- Repository sections start at `repo0`, are contiguous, and name distinct
  locations. A malformed or omitted repo must not refresh the success marker.
- A backup writes the marker only after every configured repository succeeds
  through backup, forget, and prune; it records section names, never locations.
- Do not change retention or automatically delete media as incidental work.
- Keep `sysbackup.env` and machine-specific paths out of Git.

## Testing

- Run `bash test/config-parser-test`, then all four root suites named in the
  README, plus ShellCheck and `bash -n` over the shell inventory.
- Root suites re-exec in a private mount namespace, overlay `/etc/sysbackup`,
  `/var/lib`, `/mnt`, and the lock directory with tmpfs, and refuse to run
  unless Restic resolves to a fake executable. Never weaken those guards.
- CI runs on Linux only because the root suites require mount namespaces.
  `.github/shellcheck-files.txt` lists shell programs; CI separately lints
  the sourced environment template, which has no executable shebang.
- `.github/cgraf78-actions.lock` owns all `cgraf78/actions` workflow pins;
  advance them together with that provider's `consumer-ci/sync.sh`.

## Release

There is no tagged release workflow. Install from a reviewed checkout of
`main` after running the host-appropriate tests.
