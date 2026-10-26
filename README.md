# sysbackup

[![Tests](https://github.com/cgraf78/sysbackup/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/cgraf78/sysbackup/actions/workflows/test.yml?query=branch%3Amain)
[![License](https://img.shields.io/badge/license-MIT-67ac09)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue)](#requirements)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)](#requirements)

`sysbackup` runs [Restic](https://restic.net/) against each repository in the
effective user's configuration. A successful `backup` first finds a tagged parent
snapshot, then runs `restic backup`, `forget`, and `prune` for each repository.

## Requirements

Linux, Bash 4 or newer, a Restic version supporting `snapshots --json`
(including 0.18.x and 0.19.x), jq, GNU coreutils, util-linux `flock`, and
`getent`. Backups run with the invoking user's permissions; backing up system
files typically requires scheduling the command as root.

## Install and configure

Run `./install` from a checkout owned by the account that will run backups.
It links `bin/sysbackup` into that account's `~/.local/bin` and creates private
config templates under `~/.config/sysbackup`. Keep the checkout at its installed
path. Existing config and environment files are preserved, and the installer
does not schedule backups. A dependency manager can also expose the executable
directly from `bin/`; the bundled parser stays with the checkout under `lib/`.

Edit `~/.config/sysbackup/sysbackup.conf` to list the paths to include and at least
one repository. For example:

```ini
[global]
INCLUDES="/etc" "/home"
EXCLUDES="/home/*/.cache"

[repo0]
REPO="/srv/backups/this-host"

[repo1]
REPO="sftp:backup-user@backup-host:/backups/this-host"
```

Sections must start at `repo0` and be numbered without gaps. Repository
locations must be unique. `INCLUDES` and `EXCLUDES` accept shell-style quoted
word lists on one line; each repository section can add its own paths and
excludes. Use semicolons for comments. The bundled parser evaluates assignment
values as shell code. Keep the directory and files owned by the account running
the command, with no group or other write access. Both config files must have
mode `0600`; `sysbackup.env` contains shell exports such as Restic and backend
credentials. **Never put credentials in a repository URL or commit a filled-in
environment file.** Repository URLs are passed to Restic as command arguments.
The `examples/` files are templates; keep machine-specific copies out of Git.

`sysbackup backup` processes every configured repository. `init`,
`stats`, `snapshots`, `prune`, and `unlock` process all of them unless `-r` is
given. `mount` requires `-r` and uses a private directory in the account's
state tree.
A backup applies Restic retention with
`forget --keep-within-daily 0y1m0d0h --tag sysbackup --group-by host`, then
prunes. Review that policy before scheduling it, and never run `unlock` while
a Restic operation is active. Configure scheduling and logging separately.

## Success marker

When every configured repo backs up, forgets, and prunes successfully,
`sysbackup backup` writes `~/.local/state/sysbackup/last-success` when the run
finishes: one line per repo config section that ran (`repo0`, `repo1`, ...),
never the repo location, which can embed credentials. Monitoring should alert
when the marker is missing, older than a day plus slack for run-time swings
and DST, or lists fewer repos than an independently maintained expected count.
That catches failed, hung, and skipped runs, including a repository removed
from the configuration. The state directory has mode `0700`, while the marker
has mode `0644`; an external monitoring account needs explicit traversal access
to the account's home and state directories before it can read the marker.

## Tests

The backup integration tests in `test/` need root, mount namespaces, and
permission to mount tmpfs. They overlay the invoking user's home and put a fake
`restic` on PATH, so live config and repositories are never touched. The
standalone installer and per-user tests use fake account lookups and temporary
homes without root.

```sh
bash test/config-parser-test
bash test/install-test
bash test/per-user-test
sudo bash test/parent-snapshot-test
sudo bash test/success-marker-test
sudo bash test/mount-test
```

These tests check control flow with fake Restic. They do not verify real
backup contents or restorability; perform a separate restore test for that.

## License

MIT. See [LICENSE](LICENSE).
