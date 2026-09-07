#!/usr/bin/env bash
# Outbound JOINER = the SHARED citron joiner persona + Outbound's Photon redirect.
# See shared-docs/scripts/launch-citron.sh for the generic engine.
# ponytail: OPENPAK_PHOTON_IP is earlier-citron's own env name (its redirect ABI) --
# not ours to rename here; rename only if citron ever renames it.
exec env OPENPAK_PHOTON_IP="${OUTBOUND_PHOTON_IP:-127.0.0.1}" \
    "$(dirname "$(readlink -f "$0")")/../shared-docs/scripts/launch-citron-joiner.sh" "$@"
