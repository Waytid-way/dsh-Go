#!/usr/bin/env bash
# Issue #6: bounded memory telemetry for one disposable command.
set -uo pipefail
if (( $# < 2 )); then
  echo 'usage: measure-command.sh <log-dir> <command> [args...]' >&2
  exit 64
fi
out=$1; shift
if [[ ! -d "$out" || -e "$out/command.exit" || -e "$out/cgroup.tsv" ]]; then
  echo 'BLOCKED: existing log directory required, without previous telemetry files' >&2
  exit 73
fi
for f in /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.events; do
  if [[ ! -r "$f" ]]; then echo "BLOCKED: missing cgroup v2 telemetry: $f" >&2; exit 69; fi
done
printf 'timestamp_utc\tmemory_current_bytes\tmemory_max\toom\toom_kill\n' > "$out/cgroup.tsv"
cat /sys/fs/cgroup/memory.events > "$out/memory.events.before"
(
  while :; do
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    current=$(cat /sys/fs/cgroup/memory.current)
    max=$(cat /sys/fs/cgroup/memory.max)
    oom=$(awk '$1=="oom" {print $2}' /sys/fs/cgroup/memory.events)
    kills=$(awk '$1=="oom_kill" {print $2}' /sys/fs/cgroup/memory.events)
    printf '%s\t%s\t%s\t%s\t%s\n' "$now" "$current" "$max" "$oom" "$kills" >> "$out/cgroup.tsv"
    sleep 1
  done
) &
sampler=$!
"$@" > "$out/command.stdout" 2> "$out/command.stderr"
status=$?
kill "$sampler" 2>/dev/null || :
wait "$sampler" 2>/dev/null || :
cat /sys/fs/cgroup/memory.events > "$out/memory.events.after"
printf '%s\n' "$status" > "$out/command.exit"
echo "command exit: $status; telemetry: $out" >&2
exit "$status"
