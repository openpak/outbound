#!/usr/bin/env bash
# Sends a synthetic friend invitation to the JOINER dev account directly through
# nx-baas's invitation mailbox -- the documented on-demand trigger (see outbound-re
# NOTES.md): reliable for testing without needing the host's live GUI/MyPage flow.
#
# The application parameter is Outbound's real, live-captured invite format
# (HANDOFF.md 2026-08-30 follow-up 4):
#     u32_le(1) || u8(len) || ascii(room_code)     e.g. 01 00 00 00 06 "CNRXJE"
#
# Usage: scripts/send-test-invite.sh <ROOMCODE>
# Env:   OUTBOUND_HOST_TOKEN_FILE (default: host profile's dev openpak_account.txt)
#        OUTBOUND_JOINER_PID      (default: 1800000004 = OutboundJoiner)
#        OUTBOUND_BAAS_API        (default: http://127.0.0.1:20070, nx-baas game API)
set -euo pipefail

CODE="${1:?usage: $0 <ROOMCODE> (e.g. CNRXJE -- the room code shown on the host)}"
[[ "$CODE" =~ ^[A-Z0-9]{4,8}$ ]] || { echo "room code must be 4-8 chars [A-Z0-9]" >&2; exit 1; }

TOKEN_FILE="${OUTBOUND_HOST_TOKEN_FILE:-$HOME/.local/share/citron/host/user/config/openpak_account.txt}"
JOINER_PID="${OUTBOUND_JOINER_PID:-1800000004}"
API="${OUTBOUND_BAAS_API:-http://127.0.0.1:20070}"

[[ -f "$TOKEN_FILE" ]] || { echo "no host account file: $TOKEN_FILE" >&2; exit 1; }
TOKEN=$(sed -n 's/^token=//p' "$TOKEN_FILE")
[[ -n "$TOKEN" ]] || { echo "no token= line in $TOKEN_FILE" >&2; exit 1; }

# u32_le(1) || u8(len) || ascii(code)
APP_PARAM=$(python3 - "$CODE" <<'EOF'
import base64, struct, sys
code = sys.argv[1].encode()
print(base64.b64encode(struct.pack("<IB", 1, len(code)) + code).decode())
EOF
)

echo "sending invite: room '$CODE' -> pid $JOINER_PID"
curl -sS -X POST "$API/api/invitations" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"target_pids\":[$JOINER_PID],\"app_param_base64\":\"$APP_PARAM\"}"
echo
