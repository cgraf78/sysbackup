# sysbackup

[![Tests](https://github.com/cgraf78/sysbackup/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/cgraf78/sysbackup/actions/workflows/test.yml?query=branch%3Amain)
[![License](https://img.shields.io/badge/license-MIT-67ac09)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue)](#requirements)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)](#requirements)

`sysbackup` runs [Restic](https://restic.net/) against each repository in a
root-owned configuration. A successful `backup` first finds a tagged parent
snapshot, then runs `restic backup`, `forget`, and `prune` for each repository.

## Requirements

Linux, Bash 4 or newer, a Restic version supporting `snapshots --json`
(including 0.18.x and 0.19.x), jq, GNU coreutils, and util-linux `flock`.
Installation and backup execution require root.

## Install and configure

Run `sudo ./install` from a trusted checkout. It installs the program in
`/usr/bin` and the parser and example configuration from `examples/` in
`/etc/sysbackup`.
Existing config and environment files are preserved. The installer refuses
symlink destination directories or files and incomplete recipes; it does not
schedule backups.
For upgrades, wait until any old `sysbackup` process and its Restic children
finish: this version uses a different lock path from earlier releases.

Edit `/etc/sysbackup/sysbackup.conf` to list the paths to include and at least
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
values as shell code. Keep the directory
and files root-owned, with no group or other write access. The environment
file must be mode `0600` and contains shell exports such as Restic and backend
credentials. **Never put credentials in a repository URL or commit a filled-in
environment file.** Repository URLs are passed to Restic as command arguments.
The `examples/` files are templates; keep machine-specific copies out of Git.

`sudo sysbackup backup` processes every configured repository. `init`,
`stats`, `snapshots`, `prune`, and `unlock` process all of them unless `-r` is
given. `mount` requires `-r` and exposes the mounted backup only to root.
A backup applies Restic retention with
`forget --keep-within-daily 0y1m0d0h --tag sysbackup --group-by host`, then
prunes. Review that policy before scheduling it, and never run `unlock` while
a Restic operation is active. Configure scheduling and logging separately.

## Success marker

When every configured repo backs up, forgets, and prunes successfully,
`sysbackup backup` writes `/var/lib/sysbackup/last-success` when the run
finishes: one line per repo config section that ran (`repo0`, `repo1`, ...),
never the repo location, which can embed credentials. Monitoring should alert
when the marker is missing, older than a day plus slack for run-time swings
and DST, or lists fewer repos than an independently maintained expected count.
That catches failed, hung, and skipped runs, including a repository removed
from the configuration. The directory
and file are world-readable so an unprivileged monitoring agent can check
them.

## Tests

The backup tests in `test/` need root, mount namespaces, permission to
mount tmpfs, and an existing `/etc/sysbackup` directory to mount over. They
use throwaway config, state, and lock directories and a fake
`restic`, so the host's real repositories are never touched. The installer
test uses a copied recipe whose targets are under a temporary `/run` directory.
It does not install to `/usr/bin` or `/etc/sysbackup`.

```sh
bash test/config-parser-test
sudo test/parent-snapshot-test
sudo test/success-marker-test
sudo test/install-test
sudo test/mount-test
```

These tests check control flow with fake Restic. They do not verify real
backup contents or restorability; perform a separate restore test for that.

## License

MIT. See [LICENSE](LICENSE).
