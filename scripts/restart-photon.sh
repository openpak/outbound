#!/usr/bin/env bash
# Restart the photon server reliably. SIGTERM hangs its graceful shutdown (the process keeps the
# ports and start-services.sh then silently skips the start), so: SIGKILL whoever owns udp/27000,
# wait for the port, archive the log under a tag, start fresh. Extra env (OPENPAK_*, FUSION_*)
# passes through to the server.
#
# Usage: scripts/restart-photon.sh [archive-tag]     e.g. scripts/restart-photon.sh preinternal-DTS8AE
set -uo pipefail
LOG_DIR="${OUTBOUND_RUN_DIR:-/mnt/media/research/outbound/services}"
HERE="$(dirname "$(readlink -f "$0")")"
TAG="${1:-$(date +%H%M%S)}"

pids=$(pgrep -f 'OpenPak.Server.Host' | grep -v "^$$\$" | while read -r p; do
    grep -q 'OpenPak.Server.Host' "/proc/$p/cmdline" 2>/dev/null && [ "$(readlink -f "/proc/$p/exe" 2>/dev/null)" != "$(readlink -f /proc/$$/exe)" ] && echo "$p"; done)
[ -n "$pids" ] && { echo "killing: $pids"; kill -9 $pids 2>/dev/null; }
for _ in $(seq 1 15); do ss -lun | grep -q ':27000 ' || break; sleep 1; done
ss -lun | grep -q ':27000 ' && { echo "port 27000 still bound; aborting" >&2; exit 1; }

[ -f "$LOG_DIR/photon.log" ] && mv "$LOG_DIR/photon.log" "$LOG_DIR/photon-$(date +%m%d)-$TAG.log"
setsid nohup "$HERE/start-services.sh" > "$LOG_DIR/start-services.out" 2>&1 < /dev/null &
for _ in $(seq 1 30); do ss -lun | grep -q ':27000 ' && break; sleep 1; done
sleep 2
if ss -lun | grep -q ':27000 ' && [ -f "$LOG_DIR/photon.log" ]; then
    echo "photon up: pids $(pgrep -f 'bin/Debug/net8.0/OpenPak.Server.Host' | tr '\n' ' '), log $LOG_DIR/photon.log"
else
    echo "photon NOT up -- see $LOG_DIR/start-services.out" >&2; exit 1
fi
