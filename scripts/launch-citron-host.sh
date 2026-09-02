#!/usr/bin/env bash
# Outbound HOST = the SHARED citron host persona + Outbound's Photon redirect.
# The generic engine (profile, launch-protocol guard, account safety) lives in
# shared-docs/scripts/launch-citron.sh. This only adds the title-specific redirect env.
exec env OPENPAK_PHOTON_IP="${OUTBOUND_PHOTON_IP:-127.0.0.1}" \
    "$(dirname "$(readlink -f "$0")")/../shared-docs/scripts/launch-citron-host.sh" "$@"
