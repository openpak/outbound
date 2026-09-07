#!/usr/bin/env bash
# Mints an account session token for a LOCAL dev account against the local container
# stack (the account container on :8099) and writes a profile's openpak_account.txt.
#
# Why this exists: the dev accounts' passwords aren't recorded anywhere. The account
# server's session tokens are HMAC-signed with OPENPAK_SECRET (legacy-local/.env,
# used as raw bytes by loadSecret()); the "legacy" token format (accountID.expiry,
# no session id) is still accepted by verifyTokenFull. So for LOCAL DEV testing we
# can re-derive a working token without knowing the password -- exactly what a
# re-login would produce.
#
# Usage: mint-host-token.sh [OUT_FILE]      (TARGET_PID=1800000004 for the joiner)
# This touches ONLY local dev accounts on the LOCAL stack. Never commit the output.
set -euo pipefail

LOCAL_DIR="${OUTBOUND_STACK_DIR:-$HOME/REPOS/legacy-local}"
ENV_FILE="$LOCAL_DIR/.env"
ACCOUNTS_FILE="$LOCAL_DIR/data/account/accounts.json"
OUT_FILE="${1:-$HOME/.local/share/citron/host/user/config/openpak_account.txt}"
TARGET_PID="${TARGET_PID:-1800000003}"   # OutboundHost; 1800000004 = OutboundJoiner
DAYS="${DAYS:-30}"

[ -f "$ENV_FILE" ] || { echo "no env file: $ENV_FILE (is legacy-local deployed?)" >&2; exit 1; }
[ -f "$ACCOUNTS_FILE" ] || { echo "no accounts file: $ACCOUNTS_FILE" >&2; exit 1; }
SECRET=$(sed -n 's/^OPENPAK_SECRET=//p' "$ENV_FILE" | tr -d '"' | head -1)
[ -n "$SECRET" ] || { echo "OPENPAK_SECRET not set in $ENV_FILE" >&2; exit 1; }

OPENPAK_SECRET="$SECRET" python3 - "$ACCOUNTS_FILE" "$OUT_FILE" "$TARGET_PID" "$DAYS" <<'PY'
import base64, hashlib, hmac, json, os, sys, time

accounts_file, out_file, target_pid, days = sys.argv[1:5]
secret = os.environ["OPENPAK_SECRET"].encode()   # raw bytes, like loadSecret()
accounts = json.load(open(accounts_file))["accounts"]

acct = next((a for a in accounts.values() if str(a.get("pid")) == target_pid), None)
if acct is None:
    sys.exit(f"pid {target_pid} not found in {accounts_file}")

expiry = int(time.time()) + int(days) * 24 * 3600
payload = f"{int(acct['id'])}.{expiry}".encode()
sig = base64.urlsafe_b64encode(hmac.new(secret, payload, hashlib.sha256).digest()).decode().rstrip("=")
token = base64.urlsafe_b64encode(payload).decode().rstrip("=") + "." + sig

os.makedirs(os.path.dirname(out_file), exist_ok=True)
with open(out_file, "w") as f:
    f.write(f"pid={acct['pid']}\nusername={acct['username']}\n"
            f"friend_code={acct.get('friend_code','')}\ntoken={token}\n")
os.chmod(out_file, 0o600)
print(f"wrote {out_file}: pid={acct['pid']} username={acct['username']} token=<masked>")
PY
