#!/usr/bin/env bash
# Freeze watchdog for the Outbound HOST citron instance.
#
# Watches the instance's log; if the log stops growing for ~10s while the process
# is alive, auto-attaches gdb and dumps every thread's backtrace to a timestamped
# file under $OUTBOUND_RUN_DIR (pool, disk-backed). ptrace attach/detach resumes the
# process normally (this is NOT citron's own gdbstub, whose detach kills emulation),
# so a false positive on a quiet screen costs nothing but a paused second.
set -uo pipefail

LOG="$HOME/.local/share/citron/host/user/log/citron_log.txt"
OUT="${OUTBOUND_RUN_DIR:-/mnt/media/research/outbound/services}"   # disk-backed, never /tmp (tmpfs)
mkdir -p "$OUT"

same=0
last=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
echo "$(date +%T) watchdog started" >> "$OUT/freeze-watchdog.log"

while true; do
    sleep 2
    cur=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
    pid=""
    for p in $(pgrep -x citron); do
        cwd=$(readlink -f "/proc/$p/cwd" 2>/dev/null) || continue
        case "$cwd" in
            *citron-host*) pid=$p; break;;
        esac
    done
    if [ -z "$pid" ]; then
        same=0; last=$cur; continue
    fi
    if [ "$cur" = "$last" ]; then
        same=$((same + 1))
    else
        same=0; last=$cur
    fi
    if [ "$same" -ge 5 ]; then
        ts=$(date +%s)
        cpu=$(ps -o %cpu= -p "$pid" | tr -d ' ')
        mem=$(free -h | awk '/^Mem:/{print $7}')
        {
            echo "=== FREEZE BACKTRACE $(date +%T) pid=$pid cpu=${cpu}% mem_avail=$mem ==="
            timeout 120 gdb -p "$pid" --batch \
                -ex "set pagination off" \
                -ex "thread apply all bt 20" 2>&1
            echo "=== end ==="
        } > "$OUT/freeze-bt-$ts.txt" 2>&1
        echo "$(date +%T) freeze suspected (log static 10s) -- backtrace in $OUT/freeze-bt-$ts.txt" \
            >> "$OUT/freeze-watchdog.log"
        same=0
    fi
done
