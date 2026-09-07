#!/usr/bin/env bash
# Outbound JOINER = the SHARED citron joiner persona + Outbound's Photon redirect.
# See shared-docs/scripts/launch-citron.sh for the generic engine.
# ponytail: OPENPAK_PHOTON_IP is earlier-citron's own env name (its redirect ABI) --
# not ours to rename here; rename only if citron ever renames it.
# OPENPAK_API points citron at nx-baas: it serves the invitation mailbox and forwards
# the rest of the account API onward. Loopback only -- citron refuses any other host.
exec env OPENPAK_PHOTON_IP="${OUTBOUND_PHOTON_IP:-127.0.0.1}" \
    OPENPAK_API="${OUTBOUND_BAAS_API:-http://127.0.0.1:20070}" \
    "$(dirname "$(readlink -f "$0")")/../shared-docs/scripts/launch-citron-joiner.sh" "$@"
