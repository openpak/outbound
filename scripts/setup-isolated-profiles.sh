#!/usr/bin/env bash
# Builds two FULLY ISOLATED citron profiles for Outbound multiplayer testing, using
# citron's Linux portable mode (a `user/` directory in the launch cwd takes over ALL
# of citron's storage -- config, saves, keys, NAND, cache -- instead of
# ~/.config/citron + ~/.local/share/citron; see earlier-citron
# src/common/fs/path_util.cpp, PORTABLE_DIR="user").
#
# Isolation guarantees:
#  - host and joiner cannot see each other's config/saves/keys/NAND
#  - neither touches the main citron profile (~/.config/citron, ~/.local/share/citron),
#    so normal citron usage and any other *-legacy testing are unaffected
#  - qt-config.ini is patched so the persisted OpenPak server/NAT IPs point at
#    127.0.0.1 (the joiner source profile had REAL PRODUCTION IPs persisted -- a bare
#    relaunch without env vars would have reached production)
#  - NO LayeredFS mods are copied (the old legacy-test-app App ID override is
#    obsolete with the self-hosted Photon server and would corrupt App-ID tracking)
#  - the joiner's own log lives inside its own profile (user/log/)
#
# Only what Outbound needs is copied: keys, firmware (nand/system), the Outbound
# save, the six Outbound update/DLC NCAs from the installed-content cache (the base
# game itself stays at /mnt/media/Emulation/roms/switch, referenced by the copied
# game-dir config), and the dev-account login files.
#
# Idempotent: re-running re-copies everything (fresh state), EXCEPT it never
# overwrites an existing user/config/citron/openpak_account.txt unless --fresh is
# passed... actually simpler: everything is re-copied, tokens included. Pass
# --keep-tokens to preserve any existing openpak_account.txt in the profiles.
set -euo pipefail

BASE="$HOME/.local/share/citron"
HOST_DIR="$BASE/host"
JOINER_DIR="$BASE/joiner"

SRC_HOST_CONF="$HOME/.config/citron"
SRC_HOST_DATA="$HOME/.local/share/citron"
SRC_JOINER_CONF="$HOME/.citron-second/config/citron"
SRC_JOINER_DATA="$HOME/.citron-second/data/citron"

GAME_ROMS_DIR="/mnt/media/Emulation/roms/switch"

# The six installed-content NCAs Outbound needs (update 0.6.0 + DLC), identified from
# the registered-cache logs (see HANDOFF.md 2026-08-31). Content ids -> directory map
# is resolved automatically below.
OUTBOUND_NCAS=(
    ac5c1cabab53f81d8105f15f282024c1  # update meta (0100ED9024EB8800)
    885bc43f66c0569557c6741af1ce0941  # update program 0.6.0 (393216)
    30f1f9b8e45b65f88c6c0fa1a9d25285  # update control
    7fc5b6213b706777a5cdcbbbd808b62c  # update legal
    f07ed2cca5027d2a92d630a958828662  # DLC meta (0100ED9024EB9001)
    da1c7cfc5ca2182a11e69d843f616dd0  # DLC data (0100ED9024EB9001)
)

echo "building isolated profiles under $BASE ..."

for role in host joiner; do
    src_conf_var="SRC_${role^^}_CONF"; src_data_var="SRC_${role^^}_DATA"
    src_conf="${!src_conf_var}"; src_data="${!src_data_var}"
    dst="$BASE/$role/user"

    rm -rf "$dst"
    mkdir -p "$dst/config/citron" "$dst/keys" "$dst/sdmc" "$dst/nand/user" "$dst/nand/user/Contents"

    # 1. keys (tiny)
    cp -a "$src_data/keys/." "$dst/keys/"

    # 2. firmware (nand/system, ~326M) -- required for fonts/shader compilation
    cp -a "$src_data/nand/system" "$dst/nand/system"

    # 3. saves (small; whole user/save tree keeps the account dir layout intact)
    if [ -d "$src_data/nand/user/save" ]; then
        cp -a "$src_data/nand/user/save" "$dst/nand/user/save"
    fi

    # 4. only Outbound's installed-content NCAs (NOT the 25G/6G whole cache)
    mkdir -p "$dst/nand/user/Contents/registered"
    for id in "${OUTBOUND_NCAS[@]}"; do
        src_nca=$(find "$src_data/nand/user/Contents/registered" -name "$id.nca" 2>/dev/null | head -1)
        if [ -z "$src_nca" ]; then
            echo "error: NCA $id not found under $src_data" >&2
            exit 1
        fi
        rel="${src_nca#$src_data/}"
        mkdir -p "$dst/$(dirname "$rel")"
        cp -a "$src_nca" "$dst/$rel"
    done

    # 5. config tree (qt-config.ini, custom per-game config, input profiles) -- but
    #    never any multiplayer/lobby state or LayeredFS mods.
    #    NOTE: in portable mode citron's ConfigDir is user/config (NO citron/ subdir;
    #    that component only exists in the XDG layout), so the files land directly in
    #    user/config/.
    cp -a "$src_conf/qt-config.ini" "$dst/config/qt-config.ini"
    [ -d "$src_conf/custom" ] && cp -a "$src_conf/custom" "$dst/config/custom"
    [ -d "$src_conf/input" ] && cp -a "$src_conf/input" "$dst/config/input"
    [ -f "$src_conf/hotkey_profiles.json" ] && cp -a "$src_conf/hotkey_profiles.json" "$dst/config/"

    # 6. SAFETY: point the persisted OpenPak server/NAT IPs at localhost so even a
    #    bare relaunch with no env vars can never reach the real production servers.
    sed -i 's|^openpak_server_ip=.*|openpak_server_ip=127.0.0.1|' "$dst/config/qt-config.ini"
    sed -i 's|^openpak_nat_ip=.*|openpak_nat_ip=127.0.0.1|' "$dst/config/qt-config.ini"
    sed -i 's|^enable_legacy=.*|enable_legacy=true|' "$dst/config/qt-config.ini"
    # Source profiles often carry ABSOLUTE storage-path overrides (nand_directory/
    # sdmc_directory/external_content_dirs from the old XDG layouts) and sometimes a
    # leftover use_gdbstub=true (halts the game at boot waiting for a GDB client).
    # Redirect them into this profile's own user/ tree so isolation actually holds.
    sed -i "s|^nand_directory=.*|nand_directory=$dst/nand|" "$dst/config/qt-config.ini"
    sed -i "s|^sdmc_directory=.*|sdmc_directory=$dst/sdmc|" "$dst/config/qt-config.ini"
    sed -i 's|^use_gdbstub=.*|use_gdbstub=false|' "$dst/config/qt-config.ini"
    sed -i "s|^Paths\\\\external_content_dirs\\\\1\\\\path=.*|Paths\\\\external_content_dirs\\\\1\\\\path=$dst/sdmc/citron/content|" "$dst/config/qt-config.ini"
    if ! grep -q "^enable_legacy=true$" "$dst/config/qt-config.ini"; then
        echo "error: enable_legacy not found/set in $dst/config/qt-config.ini" >&2
        exit 1
    fi
    echo "built $dst ($(du -sh "$dst" | cut -f1))"
done

# 7. Account logins -- both minted against the legacy-local stack (see mint-host-token.sh).
mint="$HOME/REPOS/earlier-outbound/scripts/mint-host-token.sh"
if [ "${1:-}" != "--keep-tokens" ] || [ ! -f "$HOST_DIR/user/config/openpak_account.txt" ]; then
    "$mint" "$HOST_DIR/user/config/openpak_account.txt"
fi
if [ "${1:-}" != "--keep-tokens" ] || [ ! -f "$JOINER_DIR/user/config/openpak_account.txt" ]; then
    TARGET_PID=1800000004 "$mint" "$JOINER_DIR/user/config/openpak_account.txt"
fi

echo
echo "profiles ready:"
echo "  host:   $HOST_DIR/user"
echo "  joiner: $JOINER_DIR/user"
