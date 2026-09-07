#!/usr/bin/env bash
# Auto-invite loop: every time the HOST opens a new room (photon log `EnterRoom "<code>" actor=1`),
# send the joiner a test invitation for it, once per code. Replaces re-arming a one-shot watcher
# after every re-host. Runs until killed; log in $OUTBOUND_RUN_DIR/auto-invite.log.
#
# Usage: scripts/auto-invite.sh            (foreground)
#        setsid nohup scripts/auto-invite.sh > /dev/null 2>&1 < /dev/null &   (detached)
set -uo pipefail
LOG_DIR="${OUTBOUND_RUN_DIR:-/mnt/media/research/outbound/services}"
PHOTON_LOG="$LOG_DIR/photon.log"
HERE="$(dirname "$(readlink -f "$0")")"
SENT=""   # space-separated codes already invited (reset when the log is replaced)
INODE=""

while true; do
    cur_inode=$(stat -c %i "$PHOTON_LOG" 2>/dev/null || echo none)
    if [ "$cur_inode" != "$INODE" ]; then INODE="$cur_inode"; SENT=""; fi   # server restarted -> fresh log
    code=$(grep -ao 'EnterRoom "[A-Z0-9]*" actor=1' "$PHOTON_LOG" 2>/dev/null | tail -1 | sed 's/EnterRoom "\([A-Z0-9]*\)".*/\1/')
    if [ -n "$code" ] && [[ " $SENT " != *" $code "* ]]; then
        SENT="$SENT $code"
        sleep 3
        echo "$(date +%T) room $code -> inviting joiner" | tee -a "$LOG_DIR/auto-invite.log"
        "$HERE/send-test-invite.sh" "$code" 2>&1 | tee -a "$LOG_DIR/auto-invite.log"
    fi
    sleep 2
done
