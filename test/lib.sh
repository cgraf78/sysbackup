# shellcheck shell=bash
#
# lib.sh - Shared harness for the sysbackup tests.
#
# A test sources this file first. The harness re-execs the test inside a
# private mount namespace and mounts tmpfs over the effective user's home
# and /var/lib (which only holds the fake restic), then puts that fake first
# on PATH.
# The script under test therefore sees only throwaway config, state, and
# locks, and the host's real ones are never read or written.
#
# The fake restic logs each call as "<subcommand>:<repo>" in $CALLS, fails
# when that string equals $FAIL, sleeps $SLEEP seconds in `backup`, and logs
# each backup's --parent values as "<repo>:<ids>" in $PARENTS. `snapshots`
# lists the ID in $PARENT_<repo>, when set, as JSON.

set -u

repoDir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
declare -r repoDir

if [ $EUID -ne 0 ]; then
  echo "Error: must run as root" >&2
  exit 1
fi

# Always re-exec the test under a fresh mount namespace before mounting
# anything. The re-exec is marked by an explicit first argument, not an
# environment variable a caller could inherit (sudo -E, say), but the marker
# only says a re-exec was meant to happen; in_private_ns proves it did.
declare -r nsMarker="__sysbackup_test_in_private_ns"
if [ "${1:-}" != "$nsMarker" ]; then
  exec unshare -m --propagation private bash "$0" "$nsMarker" "$@"
fi
shift

# in_private_ns - Succeeds when this process's mount namespace differs from
# its parent's. unshare execs in place, so the parent is whatever launched the
# test, and the kernel, not a caller-supplied argument, names its namespace.
# Comparing against PID 1 instead would wrongly pass when the launcher (a
# sandboxed sshd, say) already runs in a shared non-host namespace. An
# unreadable namespace fails closed.
in_private_ns() {
  local self parent
  self=$(readlink /proc/self/ns/mnt) || return 1
  parent=$(readlink "/proc/$PPID/ns/mnt") || return 1
  [ -n "$self" ] && [ -n "$parent" ] && [ "$self" != "$parent" ]
}

if ! in_private_ns; then
  echo "Error: not in a private mount namespace; refusing to mount" >&2
  exit 1
fi

T=$(mktemp -d /run/sysbackup-test.XXXXXX) || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/lib/sysbackup"
cp "$repoDir/bin/sysbackup" "$T/bin/"
cp "$repoDir/lib/sysbackup/config-parser" "$T/lib/sysbackup/"

# Every mount point must already exist: a mount namespace does not isolate
# directory contents, so creating one here would change the real filesystem.
accountHome=$(getent passwd "$EUID" | cut -d: -f6) || exit 1
declare -r accountHome
in_private_ns || exit 1
for dir in "$accountHome" /var/lib; do
  if [ ! -d "$dir" ]; then
    echo "Error: $dir must exist to mount over it" >&2
    exit 1
  fi
  mount -t tmpfs sysbackup-test "$dir" || exit 1
done
chmod 0700 "$accountHome"
mkdir -p "$accountHome/.config/sysbackup" "$accountHome/.local/state"
chmod 700 "$accountHome/.config/sysbackup"
umask 077
: >"$accountHome/.config/sysbackup/sysbackup.env"
declare -r confDir="$accountHome/.config/sysbackup"
declare -r stateDir="$accountHome/.local/state/sysbackup"

# The fake restic lives on the /var/lib tmpfs, not in $T: /run is noexec on
# some hosts, and bash's PATH search skips a file it cannot execute and falls
# through to the real restic.
declare -r fakeBin=/var/lib/sysbackup-test-bin
mkdir "$fakeBin"
cat >"$fakeBin/restic" <<'EOF'
#!/bin/bash
sub=$1 repo= parents=
printf '%s\n' "$@" >"$ARGS"
while [ $# -gt 0 ]; do
  [ "$1" = -r ] && repo=$2
  [ "$1" = --parent ] && parents="$parents${parents:+,}$2"
  shift
done
echo "$sub:$repo" >>"$CALLS"
if [ "$sub" = snapshots ]; then
  var="PARENT_$repo"
  older="OLDER_$repo"
  if [ -n "${!var:-}" ]; then
    if [ -n "${!older:-}" ]; then
      printf '[{"id":"%s"},{"id":"%s"}]\n' "${!var}" "${!older}"
    else
      printf '[{"id":"%s"}]\n' "${!var}"
    fi
  else
    echo '[]'
  fi
fi
if [ "$sub" = backup ]; then
  echo "$repo:${parents:-none}" >>"$PARENTS"
  sleep "${SLEEP:-0}"
fi
[ -n "${FAIL:-}" ] && [ "$FAIL" = "$sub:$repo" ] && exit 1
exit 0
EOF
chmod 755 "$fakeBin/restic"
export PATH="$fakeBin:$PATH" CALLS="$T/calls" PARENTS="$T/parents" ARGS="$T/args"

# An exported restic function or a BASH_ENV startup file would run before
# PATH lookup in every sysbackup child shell, so drop both.
unset -f restic
unset BASH_ENV ENV

# Refuse to run any case unless bash resolves restic to the fake, so a
# mount option or PATH change can never send a test command to the real one.
if [ "$(type -P restic)" != "$fakeBin/restic" ]; then
  echo "Error: restic does not resolve to the fake; refusing to run" >&2
  exit 1
fi

fails=0

# config SECTION... - Writes sysbackup.conf from raw INI lines.
config() { printf '%s\n' "$@" >"$confDir/sysbackup.conf"; }

# two_repos - The usual layout: a local repo r0 and an offsite repo r1.
two_repos() {
  config '[global]' 'INCLUDES="/etc"' '' '[repo0]' 'REPO="r0"' '' '[repo1]' 'REPO="r1"'
}

# reset - Clears state between cases.
reset() {
  rm -rf "$stateDir"
  : >"$CALLS"
  : >"$PARENTS"
  : >"$ARGS"
  two_repos
}

# run FAIL_SPEC ARGS... - Runs sysbackup with the fake restic failing on
# FAIL_SPEC. Runs through bash so a noexec /run cannot fail every case.
run() { FAIL=$1 bash "$T/bin/sysbackup" "${@:2}" >"$T/out" 2>&1; }

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  sed 's/^/    /' "$T/out"
  fails=$((fails + 1))
}

# check NAME CONDITION... - Passes NAME when the test command succeeds.
check() {
  local name=$1
  shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

# hold_lock / release_lock - Hold sysbackup's own lock, as a running backup
# would.
hold_lock() {
  [ -d "$stateDir" ] || mkdir -m 0700 "$stateDir"
  exec 98>"$stateDir/sysbackup.lock"
  flock -x 98
}
release_lock() {
  flock -u 98
  exec 98>&-
}

# finish - Prints the summary and exits with the overall status.
finish() {
  echo
  if [ $fails = 0 ]; then echo "All tests passed"; else echo "$fails test(s) failed"; fi
  [ $fails = 0 ]
  exit
}
