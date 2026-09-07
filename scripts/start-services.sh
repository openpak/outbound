#!/usr/bin/env bash
# Starts the two local services Outbound multiplayer testing needs, if they are not
# already running. Idempotent -- safe to run before every test session.
#
# The account server is still the legacy-local container stack (account published
# on :8099) -- OpenPak has no local compose stack of its own yet; point
# OUTBOUND_STACK_DIR at one when it exists. Profile tokens are minted against that
# stack's secret (mint-host-token.sh). The photon server needs
# DOTNET_ROLL_FORWARD=Major (only .NET 9 installed) and the client-hardcoded modern
# port triplet (27000/27001/27002).
set -euo pipefail

LOCAL_DIR="${OUTBOUND_STACK_DIR:-$HOME/REPOS/legacy-local}"
PHOTON_DIR="${OUTBOUND_PHOTON_DIR:-$HOME/REPOS/Openpak/middleware/photon}"
LOG_DIR="${OUTBOUND_RUN_DIR:-/mnt/media/research/outbound/services}"   # disk-backed, never /tmp (tmpfs)
mkdir -p "$LOG_DIR"

# 1. account container on :8099
if ! curl -sf http://127.0.0.1:8099/api/health > /dev/null; then
    echo "starting account stack ($LOCAL_DIR, account on :8099)..."
    (cd "$LOCAL_DIR" && podman-compose up -d --no-build)
else
    echo "account stack already up on :8099"
fi

# 2. photon (Photon-protocol-compatible server)
if ! ss -lun 2>/dev/null | grep -q ":27000 "; then   # port check, not pgrep -f (which self-matches this shell)
    echo "starting photon (advertised host ns.photonengine.io)..."
    (cd "$PHOTON_DIR" && \
        DOTNET_ROLL_FORWARD=Major \
        BLACKICE_Server__Ports__NameServerAlt=27000 \
        BLACKICE_Server__Ports__MasterServerAlt=27001 \
        BLACKICE_Server__Ports__GameServerAlt=27002 \
        BLACKICE_Server__Listener__DeadTimeoutSeconds=600 \
        nohup dotnet run --project server/BlackIce.Server.Host -- \
            ns.photonengine.io --trace > "$LOG_DIR/photon.log" 2>&1 &)
else
    echo "photon already running"
fi

echo
echo "logs: $LOG_DIR/"
echo "waiting for ports..."
for i in $(seq 1 30); do
    ok=1
    ss -lun 2>/dev/null | grep -q ":27000 " || ok=0
    ss -ltn 2>/dev/null | grep -q ":8099 " || ok=0
    [ "$ok" = 1 ] && break
    sleep 1
done
if [ "$ok" = 1 ]; then
    echo "ready: account :8099 (tcp), photon :27000/udp (+ 5055/5056/5058/27001/27002)"
else
    echo "warning: ports not confirmed yet -- check $LOG_DIR/ before testing" >&2
fi
