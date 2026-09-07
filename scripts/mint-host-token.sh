#!/usr/bin/env bash
# Mints an account bearer for a LOCAL dev account and writes a citron profile's
# openpak_account.txt.
#
# Why this exists: the dev accounts' passwords aren't recorded anywhere. nx-baas's
# /internal/mint-token signs the same "openpak" token a real login would produce, for any PID
# its account backend knows -- so no password and no reading the stack's secret. It is an
# internal endpoint on an internal port; guard it with NX_INTERNAL_KEY on anything but a
# private LAN.
#
# Usage: mint-host-token.sh [OUT_FILE]      (TARGET_PID=1800000004 for the joiner)
# Env:   OUTBOUND_BAAS_API (default: http://127.0.0.1:20070), NX_INTERNAL_KEY
# This touches ONLY local dev accounts on the LOCAL stack. Never commit the output.
set -euo pipefail

API="${OUTBOUND_BAAS_API:-http://127.0.0.1:20070}"
OUT_FILE="${1:-$HOME/.local/share/citron/host/user/config/openpak_account.txt}"
TARGET_PID="${TARGET_PID:-1800000003}"   # OutboundHost; 1800000004 = OutboundJoiner

RESPONSE=$(curl -sS -X POST "$API/internal/mint-token" \
    -H "Content-Type: application/json" \
    ${NX_INTERNAL_KEY:+-H "X-Internal-Key: $NX_INTERNAL_KEY"} \
    -d "{\"pid\":$TARGET_PID}")

mkdir -p "$(dirname "$OUT_FILE")"
OUT_FILE="$OUT_FILE" python3 - "$RESPONSE" <<'PY'
import json, os, sys
r = json.loads(sys.argv[1])
if not r.get("token"):
    sys.exit(f"mint failed: {sys.argv[1]}")
out = os.environ["OUT_FILE"]
with open(out, "w") as f:
    f.write(f"pid={r['pid']}\nusername={r['username']}\n"
            f"friend_code={r.get('friend_code','')}\ntoken={r['token']}\n")
os.chmod(out, 0o600)
print(f"wrote {out}: pid={r['pid']} username={r['username']} token=<masked>")
PY
