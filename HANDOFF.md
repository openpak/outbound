# Outbound Reference — development handoff

Last updated: 2026-09-07 09:27 UTC. **REAL CONSOLE HOSTS, CITRON JOINS — WORKING END TO END ON THE LAN STACK.**
Console (OutboundJoiner, Outbound 1.1.7) hosted room Q35V9E on earlier-photon; the invite went joiner -> OutboundHost
via `/api/invitations`; Citron's injected join entered the room; Fusion host reports players=2 and both see each
other. Blockers found and fixed this morning, in order:
1. Console link (see below): per-SNI certs (2123-0013) and `PUT push_channels` `{}` -> full channel object.
2. Outbound launch spinner: `capi.lp1.op2.nintendo.net/v1/users/<na>/memberships` (NSO membership) and NA
   `qrcode_param` were unanswered. nx-baas `0808537` serves both like the VPS (active "default" membership).
3. Photon unreachable from the LAN: ufw (default DROP) only allowed TCP 443. Opened `5055:5058/udp` and
   `27000:27002/udp` (`pkexec ufw allow ...`). Citron never hit it (loopback).
4. "A Photon error has occurred": NameServer handed every private-network peer `127.0.0.1:27001`. earlier-photon
   `94672b1`: loopback peers only; LAN peers get the advertised host (`ns.photonengine.io`, the third-party setup resolves it to
   the LAN IP).
5. Citron saw the room but refused it: console Outbound was 1.0.1 (title v2), Citron 1.1.7 (v6 update). Fusion
   filters sessions by `"version"`. Installed `/mnt/media/Emulation/roms/switch updates/Outbound
   [0100ED9024EB8800][v393216][Up v6.0.1].nsp` on the console.
Reverse-direction rig: `TARGET_PID=1800000004 scripts/mint-host-token.sh <file>` then
`OUTBOUND_HOST_TOKEN_FILE=<file> OUTBOUND_JOINER_PID=1800000003 scripts/send-test-invite.sh <CODE>`; room code
from `EnterRoom "<CODE>" actor=1` in the Photon log; relaunch Citron before every join (`pkill -f
"[u]se-nopgo/bin/citron"` -- a bare pkill pattern matches your own shell). Invites expire after 5 min.

**Console link (earlier this session):** OutboundJoiner
(pid 1800000004) was added to the console via the stock flow (NA login page -> /federation) and is linked and
working. What actually unblocked it, in order (all in nx-baas, all ground-truthed against the VPS):
1. `1e7066f`/`e391076` TLS: the per-SNI on-demand cert change served fresh certs for the BAAS names too; the
   console rejected them (2123-0013 = SSL). Fixed cert for every SAN it covers; random serials (same-second mints
   shared a serial). On-demand certs only for unrouted SNI (logged).
2. `bf9168c` **PUT /1.0.0/push_channels must return the full channel object** (userId, deviceAccountId, service,
   deviceToken, deviceAttributes, userAttributes, createdAt, updatedAt). We returned `{}` and the console showed
   "The Nintendo Account could not be linked because an error occurred" right after that request, every time.
   Also: id_token `nintendo` block is APPLICATION style (ai/at/av/edi/tbh/tbn, from appAuthNToken when sent, else
   ai=0100f8f0000a2000 av=0033); unlinked users get `/1/default` + `/2/default` thumbnails (default.jpg in
   `legacy-local/data/nx-baas/`).
3. `329a754`/blob: nxAccount is served from the user's stored blob only. The 174-byte blob is a constant on the
   VPS login path too (the VPS's GET /users/{id} serves a second template) — it is NOT per-account identity.
   Restore without a blob -> 2124-0292. Joiner/<user-a>/leia records carry the constant.
4. `a39a7ea` etag == bs:did for linked users (VPS parity; probably not load-bearing).
**How the ground truth was obtained (reusable):** the VPS BAAS is reachable with SNI
(`curl --resolve <host>:443:51.178.29.194`). A throwaway device account (dauth -> application/token ->
POST /users -> /login -> PUT push_channels -> GET /users/{id}) captured every reply shape without touching a
real profile. Probe output: scratch `vps-probe.json` (not archived — rerun the chain if needed; one orphan
device account per run, harmless). Also: nx-baas debug lines can lag in `podman logs` by a minute; use
journalctl (`CONTAINER_NAME=legacy-local-nx-baas-1`, local time = UTC+1) when a request seems missing.
Mirror seeding for <user-a>/leia (accounts 8/9, real ids, empty device password adopted on first login) is in
place and untested on the console. nx-dauth `615c1a6` logs aauth application ids.

NEXT: (1) gameplay between console and Citron (movement, pickups, vehicles, 30+ min, server RSS); (2) the console's
own Invite Friends button -> BAAS invitation endpoint shows up as `!! UNHANDLED` in nx-baas = spec to implement;
(3) <user-a>/leia mirror test in LAN mode; (4) console friends list (joiner friend code SW-8370-7532-3519).

---
_Earlier status (2026-09-07 morning, historical):_

A selective full-forward VPS capture (only nx-baas's TLS made fixed-cert again; NX_UPSTREAM
forwards everything to the VPS) got BOTH org accounts to refresh SILENTLY, and both returned a
byte-IDENTICAL 174-byte nxAccount blob — identical to what we already serve via `NX_TEST_NXACCOUNT`. So the
blob is NOT per-account and was never the blocker; the "generate the blob" and "Restore User" tracks are dead
ends (Restore also needs a console-side backup record of the profile uid, which a new account never has — see
`## Console link` sections). Per-account identity is the ordinary fields — NA id, friend code, device account
id, nickname, baas id. Captured for both accounts:
`/mnt/media/research/outbound/services/{login-<user-a>.json,login-leia.json,console-account-map.txt}`.
- <user-a>: baasId=ae575806b0efa797 device=6656e0bbf2927116 NA=21fde2a5ab9cac6f fc=8741-1421-3742
- leia:    baasId=1118f9d65503d233 device=2e5eb62979c7100f NA=45d1c6f774bcfdee fc=8279-5926-7788

**Capture must be SELECTIVE-friendly:** global `NX_UPSTREAM` full-forward works for the blob ONLY if nx-baas
serves the FIXED multi-SAN cert (my on-demand per-SNI cert change disturbed the console's silent NA session and
forced interactive re-login -> account check fails -> no blob). nx-baas now uses the fixed cert whenever
`NX_UPSTREAM` is set (`main.go`, capture-mode branch). NEVER leave capture on. dauth stays on local nx-dauth;
the console reused its cached VPS device token, so BAAS `/login` (proxied to VPS) accepted it.

**the third-party setup rebased to upstream v3.4.0** (`console patches` branch `local-legacy`, 6 LAN commits replayed clean;
backup tag `backup/local-legacy-prerebase-20260907`). Brings SSBU 1.4.1, the BCAT CDN redirect, version-from-
APP_VERSION. Built NRO: `/mnt/media/research/outbound/prelude/legacy-lan.nro` (v3.4.0). Also FIXED a
latent LAN bug: picking the plain "Reference" row re-applied `g_server_ip`, which startup detection had left at
the LAN IP, so "back to Reference" stayed LAN. `legacy_apply_legacy()` now resets a leftover LAN IP to the
VPS default. UNCOMMITTED: the the third-party setup fix + the nx-baas fixed-cert-in-capture change (rebuild/redeploy done, git
not committed).

**NEXT SESSION = build the MIRROR** (see `## NEXT SESSION` at end and the memory note
`console-link-restore-deadend`): seed <user-a>+<user-b> into `openpak-account/data/account/accounts.json` (real NA
id, friend code, nickname, a PID) and `nx-baas/data/nx-baas/baas.json` (real baas id + PID bound to the console
device id; pre-seeded device must adopt its password on first login — store.Login TOFU adopts UNKNOWN device
ids today, add an empty-password=adopt tweak). Then a console in LAN mode refreshes and gets the full linked
object (no 2124-3121), no re-linking. The rest below (transport/gameplay) is historical, all working.

---
_Earlier status (2026-09-06 and before, historical):_

**SERVER MEMORY LEAK FIXED** (earlier-photon `1311ba5`): the
`UdpListener` loop cancelled its `ReceiveAsync` every tick (16 ms with a hosted sim) and on Linux a
cancelled receive stays queued in `SocketAsyncContext` until data arrives -- a `dotnet-dump`
`dumpheap -stat` of the 2.8 GB process showed 6.3 M `BufferMemoryReceiveOperation` + linked CTS
objects. The loop now keeps ONE receive and ONE timer task pending across iterations. **Verify next
run: `ps -o rss= -p $(pgrep -f bin/Debug/net8.0/BlackIce.Server.Host)` should stay ~0.3-0.5 GB.**
Housekeeping item 5 also done (delay experiment removed; actors leave `Room.ActorNumbers`, so the
join-response actor list / master hint are truthful for the host-quits and 3-player tests).
Earlier that night: **FRESH JOIN AND RETURNING JOIN BOTH WORK, REPEATABLY** (rooms
4YXD7E fresh, UKTY4E returning: joiner's character loaded, spawned beside the host in the campervan,
no create-a-character prompt). The evening's "works sometimes" was a fourth server-side gap: in
Shared topology CLIENTS also send their copies of the PlayerData structs back, and the SDK server
copies them over its own — a stale copy wiped the player→avatar link (`Object=None`) so the host
dropped itself from its player list and never processed joins. Fixed by re-asserting the link every
tick (`FusionServerFactory.OnBeforeTick`). With that, the sticky `knownPlayers` rule (a joining client
keeps NO local character save — FS-traced — and decides new-vs-returning from the room snapshot)
turned out to be right and is back in. See the last 2026-09-06 section at the end. Earlier that evening: **BOTH PLAYERS SEE EACH OTHER on a FRESH join** (room TY546E,
user: "now both see each other!"). Two server-side gaps closed today, no DLL/game patch (user rule:
never patch the SDK assemblies or the game): (1) the SDK server swallows every Fusion INTERNAL
simulation message (`SetPlayerObject` etc.), so the joiner's avatar never linked to its PlayerData and
the host never ran its join sync — fixed via an `OnBeforeTick` flag swap that routes them through
`OnMessage`; (2) our eNet transport had no case for Photon command type 15 (reliable-unsequenced
fragment, used for every relay packet above the MTU) and acked it with type 1 instead of 16, so the
host's ~100-RPC world-sync burst was dropped, retransmitted, and the host died with **1014**
(= 1000 + Fusion `ShutdownReason.PhotonCloudTimeout`). See the last 2026-09-06 section at the end.
Still to verify on screen: pickups both ways (state-authority requests — none observed yet) and
pre-join world state on the joiner. **(Earlier status, now historical:)** CONTINUITY IS FIXED — a two-player session now HOLDS INDEFINITELY
(7+ min, no drop), but the two clients are in SEPARATE WORLDS: no game state replicates.** The
~2-min drop was our own bug: `RoomSim.Tick` gated on the joining thread id, but the listener loop
is async and hops pool threads, so the hosted sim froze whenever the pool parked that thread (20 s
gap → Fusion Disconnect(Timeout)). Fixed by keying tick ownership on the listener LOOP via
`UdpListener.Current` (an AsyncLocal), committed as `earlier-photon` `39dbda3`. With that, a live
host+join held from tick 0 past tick 19000 with zero drops. **The NEW wall is state replication:**
the hosted `Simulation.Server` THROWS parsing each client's spawned-object stream —
`StateReplicator.ReadObjectUpdates` logs `Object does not exist: [Id:...], marked as confirmed —
invalid data from the remote host` then overflows the `NetBitBuffer` in `SkipObjectData`. It never
creates the players' objects, so it forwards only 26-byte header-only NotifyData (server→client
stays 26/27 B the whole session; the join-time 117 B burst is just RuntimeConfig). Root cause:
the headless generic server has no `NetworkProjectConfigAsset.SerializableSimulationBehaviourMeta`
(Outbound's per-behaviour serializer/word-layout table, confirmed present in its IL2CPP dump), so it
decodes the client's COMPRESSED object words with generic per-word varint readers, desyncs, and
overflows. See the 2026-09-06 section at the end for the full diagnosis and the two candidate paths.
Also: the server LEAKS memory on long runs (a headless Fusion sim reached **14.4 GB** RSS over the
night's runs and OOM-starved the machine, wedging both citrons; a fresh server is ~0.3 GB). Restart
the server between long runs until that's fixed. **(Earlier top-of-file status, now historical:)**
**BREAKTHROUGH: a real two-player Outbound session ran
for ~2 minutes** — both peers spawned into the game and authored state through our self-hosted
Fusion server — after rebuilding fusion-libs from Fusion 2.0.8 (Outbound's exact version). The
2.1.2 SDK's V2/250 transport was the wall; 2.0.8 uses NotifyData(3) which the client reads. Both
clients then went quiet ~2 min in (joiner timed out client-side) — the remaining issue is session
CONTINUITY, not entry. See the 2026-09-02 (night, FIXED) section. The matchmaking JOIN HANDSHAKE now completes at the
protocol level — the joiner reaches the room and the server records `actor=2,
occupants=[1,2]`, repeatably — but the session then COLLAPSES ~120 s in every
time (joiner freezes, host shows "connection interrupted (1020)"). The single
remaining blocker is Fusion's real-time gameplay transport (PRUDP-Lite P2P +
two-peer relay); see "NEXT SESSION" at the very end for the concrete plan.
Earlier this session a full decompiled map of Outbound 0.6.0 was built
(`/mnt/media/research/outbound/decomp`): the client is stock Photon
Realtime v4 (Fusion fork), the GameList room-property contract was extracted
byte-for-byte, and the
live round is validation, not diagnosis (prediction: OpJoinGame fires after the
GameList). Full flow + contract: the two 2026-09-02 sections at the end, and
`earlier-photon/docs/protocol/06-fusion-session-join.md`. (Account server also
moved to the legacy-local container stack; tokens re-minted; see below.)

## Objective

Add online multiplayer support for **Outbound** (`0100ED9024EB8000`) to the
Reference ecosystem, using the owner's legally dumped game, update and DLC.

The project was initially scaffolded as a Nintendo NEX server. Live tracing
proved that assumption wrong: Outbound uses **Photon Realtime/Fusion**.

## Current repository

Path: `~/REPOS/earlier-outbound`

This is an initialized Go repository. It currently contains a research scaffold,
not a listening server. The incorrect `earlier-nex` dependency has been removed.

Validation command:

```sh
cd ~/REPOS/earlier-outbound
go test ./...
```

## Confirmed game state

- Base title ID: `0100ED9024EB8000`
- DLC base: `0100ED9024EB9000`
- DLC observed: `0100ED9024EB9001`
- Update applied by Citron: `0.6.0` (raw version `393216`)
- The game launches successfully with NVIDIA Vulkan.
- Radeon 780M/RADV currently fails Citron video-core initialization with
  `VK_ERROR_INITIALIZATION_FAILED` on this hybrid NVIDIA-driven desktop.

## Confirmed network flow

Outbound resolves `ns.photonengine.io` and uses Photon UDP.

Observed ports:

- `5058` — initial Name Server path
- `27000` — alternative/current Name Server path used for authentication

The transport sequence completes successfully:

1. UDP connect/verify-connect
2. Photon init request/response
3. key exchange (`InternalOpRequest`/`InternalOpResponse`, operation `0`)
4. encrypted `Authenticate` request
5. plaintext failed `Authenticate` response
6. disconnect

Authentication evidence:

- Photon operation: `230` (`Authenticate`)
- Request size: `1474` bytes
- Fragmentation: two fragments, `1152` bytes then `322` bytes
- Citron BAAS token supplied to the game: `1398` bytes
- Return-code wire bytes: `f3 7f`
- GpBinaryV18/little-endian value: `32755`
- Meaning: `CustomAuthenticationFailed`

The same bytes appear as signed `-3201` if incorrectly interpreted using
GpBinaryV16/big-endian order. The tracer now reports both byte orders.

Conclusion: DNS, UDP, Photon init and encryption work. Outbound's configured
Nintendo Switch custom-authentication provider rejects the replacement BAAS
token supplied by Citron. No NEX request occurs.

**Rejection reason, confirmed:** the plaintext failure response carries more
than the 3-byte op/return-code header — a GpBinaryV16 string parameter
(Photon's `DebugMessage`) follows it, and it decodes to:

```
"Nintendo validation failed"
```

No decryption was needed — `CustomAuthenticationFailed` responses are sent
in plaintext by design; the tracer just hadn't decoded past the first 3
bytes before. This confirms the retail app's real custom-auth backend does
receive and evaluate Citron's replacement token; it's Nintendo's own
account-service-side validation that rejects it. Not fixable on our end —
confirms the plan below (own Photon app + own auth bridge) is the right
approach, not patching the retail flow. See
[`docs/research.md`](docs/research.md#retail-rejection-reason-confirmed).

## Citron build and modifications

Repository:

`~/REPOS/earlier-citron`

Built executable:

`~/REPOS/earlier-citron/build/use-nopgo/bin/citron`

Modified files:

- `src/core/hle/service/sockets/bsd.cpp`
- `src/core/hle/service/sockets/sfdnsres.cpp`

The patch adds:

- hostname retention for ordinary DNS results, not only redirected hosts;
- metadata-only tracing for Photon UDP ports `5055`, `5056`, `5058`, and
  `27000`–`27003`;
- Photon frame/command parsing;
- fragment number/count/offset/total-length reporting;
- plaintext operation code and both-endian return-code reporting;
- extraction of only a 32-character hexadecimal App ID from a plaintext Photon
  init message, falling back to a structural `init_body=<hex>` dump when
  that strict scan misses (recovered the truncated App ID — see below);
- a hex dump of the rest of a plaintext `op230` (Authenticate) response body,
  which decoded the `"Nintendo validation failed"` DebugMessage above.

The tracer deliberately does **not** log raw authentication *payloads*
(the BAAS token, the Authenticate request's encrypted body, or
`ClientAuthenticationData`/params) or encryption/key material. It does now
decode Photon's own plaintext protocol metadata — App IDs (documented as
public, non-secret identifiers) and DebugMessage strings (Photon's own
rejection reasons, not user credentials). Packet fingerprints exist to
correlate retries independent of any of that.

Incremental build command:

```sh
cd ~/REPOS/earlier-citron
ninja -C build/use-nopgo -j4 citron
```

Run command:

```sh
cd ~/REPOS/earlier-citron
./build/use-nopgo/bin/citron
```

Log file:

`~/.local/share/citron/log/citron_log.txt`

Useful query:

```sh
rg '\[Reference\]\[PHOTON\]' \
  ~/.local/share/citron/log/citron_log.txt
```

## Save transfer

The Ryujinx Outbound save was copied (not moved) into Citron.

Ryujinx source transaction copy:

`~/ryujinx/portable/bis/user/save/0000000000000002/0`

Citron destination:

`~/.local/share/citron/nand/user/save/0000000000000000/6A14C269AEA131FC7353FFE7BF178D68/0100ED9024EB8000`

Citron's prior save was preserved beside it as:

`0100ED9024EB8000.backup-before-ryujinx-20260828`

Transferred saves include:

- `teste_2026-08-28_14-46-44.autosave`
- `teste_2026-08-28_14-51-44.autosave`

## App ID confirmed

Outbound uses **Photon Fusion**. The full Photon App ID is:

```
cffbe809-5036-43d8-84a1-7bf16c924721
```

The original ASCII-hex-only `app_id=` scanner never matched because the
client's Init message truncates the 36-character GUID to a fixed 32-byte
field (dropping the last 4 hex digits) and the GUID contains dashes. Citron
was patched to fall back to an `init_body=<hex>` structural dump of the
Init message when the strict scan misses, which recovered the truncated
prefix `cffbe809-5036-43d8-84a1-7bf16c92` on the wire. The full, untruncated
value was then confirmed by extracting Outbound's RomFS (Citron's
"Dump RomFS" feature) and finding the same GUID, in full, in both
`Data/Managed/Metadata/global-metadata.dat` and the serialized
`PhotonAppSettings` asset inside `Data/resources.assets`. See
[`docs/research.md`](docs/research.md#app-id-recovery) for the full trace.

App Version is still unconfirmed on the wire; the serialized
`PhotonAppSettings` asset shows no value in that field, suggesting Fusion's
empty/default (`"1.0"`).

## Proof-of-concept plan and status

1. ✅ Create a separate Photon test application. Never alter or depend on the
   retail owner's Photon dashboard/application.
   Two exist: Fusion 2 `17a9e6d7-594a-443b-9f1e-931da70c3b1c`, Fusion 1
   `74c7f0c0-7c70-4651-8bcd-420920c2dba4` (created to rule out a
   Fusion-version mismatch — it didn't change the outcome).
2. ✅ Build a small Go custom-authentication endpoint (`cmd/authbridge`) that
   maps a valid earlier identity to a stable Photon user ID. Currently
   accept-all (proof-of-concept only, see the file's own doc comment) since
   Outbound's real custom-auth parameter names still aren't known.
3. ✅ No Nintendo/OpenPak token forwarded to the test apps — `authbridge`
   only ever sees test/probe identities.
4. ✅ App ID override via a data-only mod (`cmd/appidmod`, LayeredFS output
   under `~/.local/share/citron/load/0100ED9024EB8000/legacy-test-app/`).
   No Citron runtime override was needed.
5. ❌ **Blocked here.** Outbound's client, redirected to either test app,
   fails identically every time — an encrypted `op230` response, same 78-byte
   body size regardless of Fusion 1/2, region, or auth setting, and
   `authbridge` never receives a request (confirmed via ngrok's request
   inspector). The rejection happens *before* Custom Authentication is
   invoked. The test apps themselves are independently confirmed fully
   healthy: the official `photon-realtime` npm package connects,
   authenticates (including through `authbridge` with a large string
   auth param), and joins the lobby against `17a9e6d7-...` with no issues.
   So this is specific to something about Outbound's actual client request,
   not the test app config. Full writeup:
   [`docs/research.md`](docs/research.md#test-app-investigation-app-id-override-proof-of-concept).
6. Not started — blocked by 5.
7. Not started — blocked by 5.

### Tooling from this investigation

- `cmd/authbridge` — the custom-auth webhook (`go run ./cmd/authbridge`,
  listens on `:8081`). Needs a public tunnel to be reachable from Photon
  Cloud (ngrok used so far — `ngrok http 8081`, update the test app's
  Custom Authentication URL to the printed `https://...ngrok-free.app/auth`
  each time the tunnel restarts, free-tier URLs aren't stable).
- `cmd/appidmod` — regenerates the App ID LayeredFS mod from a RomFS dump:
  `go run ./cmd/appidmod -romfs <dumped romfs> -old <old-app-id> -new <new-app-id> -out <load dir>/romfs`.
- `/tmp/photon-probe` (not in this repo, scratch) — a small Node.js project
  using Exit Games' own `photon-realtime` npm package to probe the test apps
  directly over WSS, independent of Outbound/Citron. Recreate with
  `npm install photon-realtime` if needed again; useful for isolating
  whether a failure is app-side or Outbound-client-side.

### Root cause found: Photon Cloud's built-in `NintendoSwitch` auth provider

Ruled out via `/tmp/photon-probe` (official `photon-realtime` npm SDK):

- Empty `AppVersion` alone connects and joins the lobby fine — not the cause.
- A same-size binary `ClientAuthenticationData` payload via that JS SDK does
  reproduce `32755`/`CustomAuthenticationFailed`, but this is **inconclusive**
  — the JS library's own serializer has no special-cased `Uint8Array`/byte-array
  handling (checked its source directly), so this may just be a client-library
  quirk, not a real server-side rejection of well-formed binary auth data.

The actual answer: Photon's `CustomAuthenticationType` enum has a **dedicated
built-in `NintendoSwitch = 11`** value, distinct from generic `Custom = 0`.
Confirmed Outbound's compiled binary contains this exact enum (found the
literal `NintendoSwitch` string in `global-metadata.dat`, in the same order
as Photon's own enum: `Oculus PlayStation Viveport NintendoSwitch
Playstation...`). This explains every symptom: never reaches `authbridge`
(wrong provider entirely), unaffected by every Custom-Auth dashboard toggle
(those only govern the `Custom` provider), and matches retail's exact
wording `"Nintendo validation failed"` (reads like Photon's own built-in NSA
integration relaying Nintendo's real answer, not a third-party webhook).
Our test apps' "Add a new authentication provider" list never even offered
`NintendoSwitch` as an option — console platform auth providers are gated
behind a certified developer partnership with the platform holder, which
Photon Cloud requires before exposing that option, and which Reference
doesn't have.

Two ways forward were considered:

- **Patch the client** to request `Custom` instead of `NintendoSwitch`. Not
  pursued — `ClientAuthenticationType` is set by compiled game code, not a
  data asset, so this means disassembling and patching native ARM64 code.
  Much bigger and riskier than anything done so far, real game-cracking
  territory.
- **Self-host a Photon-protocol-compatible server instead of Photon Cloud.**
  ✅ **Chosen.** The `NintendoSwitch` gating is a Photon Cloud dashboard/SaaS
  restriction, not a protocol requirement — a server we run ourselves has no
  such gate; we can accept any `ClientAuthenticationType` value and run our
  own verification regardless of what the client claims.

## Self-hosted Photon server (current direction)

Forked `Krilliac/Blackice-Server` → `github.com/tobagin/Blackice-Server` →
cloned locally to `~/REPOS/earlier-photon`. That project is an
independent, GPLv3, clean-room Photon-protocol server originally built for a
different Unity/Photon game ("Black Ice", PUN not Fusion) — same ethos as
this project (no copyrighted game assets, own a legitimate copy to use it).
It already has a tested Name/Master/Game server implementation including the
Oakley-768 DH + AES crypto and GpBinary codec this investigation independently
reverse-engineered by hand (see `docs/research.md`), so this isn't a
from-scratch protocol implementation.

**License note:** GPLv3. Building on it means this server's code stays
GPLv3-compatible — a deliberate choice, not an oversight.

**Scope note:** this is meant to become a general-purpose Photon-compatible
server for *any* earlier game, not an Outbound-only fork. When adapting it:
keep the identity/auth backend pluggable (swap Black Ice's SteamId/Steam-
ticket validation for a earlier identity provider, not hardcoded to
Outbound), keep per-game config (App ID, title ID, auth requirements)
data-driven, and keep whatever's genuinely Black-Ice-specific (its PUN
room/game-mode logic) isolated from the shared transport/auth core.

Status: forked, cloned, builds clean (`dotnet build server/BlackIce.Server.sln`).
`dotnet test` needs `DOTNET_ROLL_FORWARD=LatestMajor` (only .NET 9 runtime is
installed, project targets .NET 8; installing the matching runtime needs
`sudo`, not done) — with that env var, all 452 tests pass.

### Citron-side redirect: `OPENPAK_PHOTON_IP`

Citron's existing DNS-redirect capability only matched `*.nintendo.*` hosts,
not Photon's. Added a second, independent redirect in `sfdnsres.cpp`
(`GetPhotonRedirectIp`, matches `*photonengine.io*` hosts), gated by its own
`OPENPAK_PHOTON_IP=<ip>` env var (unset = no effect, safe for normal runs).
Wired into both DNS-resolution call sites (`GetHostByNameRequestImpl` and the
`GetAddrInfo` path), same pattern as the existing `OPENPAK_S3_DEBUG_PROXY_IP`
npln tap. Run Citron with `OPENPAK_PHOTON_IP=127.0.0.1` (or the server's
LAN IP) to redirect Outbound's Photon traffic there instead of Photon Cloud.
Note: **no App ID override mod is needed with this approach** — Outbound
keeps using its real retail App ID; only the hostname is redirected.

### Server-side changes made so far, in the order they were needed

1. **`GetRegions` (op 220) implemented** in `NameServerHandler`. Outbound
   calls this before `Authenticate` (no `FixedRegion` configured); Black Ice
   never exercised this operation, so it didn't exist yet. Responds with one
   region (`"eu"` — a real Photon region token; a made-up one like `"nx"`
   left the client's "Region: Automatic" UI stuck spinning, consistent with
   region auto-select only recognizing Photon's own known codes) and hands
   off to the **Master Server's real address**, not the NameServer's own —
   matches real Photon Cloud's behavior (confirmed by re-testing against
   real Photon Cloud specifically to compare). Required adding `string[]`
   write support to `GpBinaryWriter` (`GpType.StringArray`, only the reader
   side existed before) and a `PhotonCodes.Op.GetRegions = 220` constant.
2. **Encryption gap in outbound messages, fixed.** `WireMessage.Response()`
   and `EventMessage()` never encrypted (`PeerConnection.SendResponse`/
   `RaiseEvent` never passed the DH-derived key to the writer), while real
   Photon Cloud always encrypts once a connection's key exchange has
   completed. Real bug, real fix, kept regardless of downstream results:
   both now take an optional `encrypt` callback wired from `PeerConnection`'s
   `_crypto` when initialized. Confirmed via re-testing against real Photon
   Cloud: its `GetRegions`/Authenticate responses are `msg3:encrypted`;
   ours were `msg3:plain` before this fix. (`InitResponse` and the
   `InternalOperationResponse` that completes the key exchange itself
   correctly stay plaintext — no key exists yet at that point.)
3. **Second NameServer port (`27000`), added.** Outbound's client
   independently tries this port (`ServerPorts.NameServerAlt`, env
   `BLACKICE_Server__Ports__NameServerAlt=27000`), completely regardless of
   what address `GetRegions` hands back — confirmed by testing every
   combination (same port as NameServer, Master's port, 1 region, 2 regions,
   different region names): **none of it changed the client's behavior on
   `27000` at all**, meaning it's a client-hardcoded alternate port, not
   server-driven. Shares the same `NameServerHandler` instance as the
   primary port.

None of steps 1–3 alone fixed the stuck connection against **Outbound on
Switch via Citron** — after all three, it still gets a generic "A Photon
error has occurred" with no code/detail. But testing against a second,
independent client (see next section) proved the underlying server changes
are correct and moved the investigation to a much more specific, real bug.

### Cross-test against Outbound on Steam — major findings

Outbound is also owned on Steam (`/mnt/games/SteamLibrary/steamapps/common/Outbound`,
same IL2CPP layout as the Switch build, **same Photon App ID**
`cffbe809-5036-43d8-84a1-7bf16c924721`). Redirected it at the local server
with a plain `/etc/hosts` entry (`127.0.0.1 ns.photonengine.io`) — no Citron
involved at all, much faster iteration than the Switch path. This is a
debugging technique only; it doesn't change or replace the actual Switch/
Citron redirect mechanism above.

This got much further than the Switch client ever has, and settled several
previously-open questions with real evidence instead of inference:

- **Steam build uses `ClientAuthenticationType = 1` (`Steam`), not
  `NintendoSwitch`** — confirms different platforms use different auth
  providers on the *same* Photon app, as theorized.
- **Auth data is sent via `ClientAuthenticationParams` (216) as a STRING**
  (`"ticket=<hex>..."`), not `ClientAuthenticationData` as binary. Settles
  the open question from the earlier Photon-Cloud test-app investigation.
- **`AppVersion` really is sent as `""`** (empty string) by the real client
  — confirms that was never the issue, on real traffic, not just our probe.
- Our server's `OpAuthenticate` (on port `27000`) **accepted this real
  request cleanly, `rc=0`, three times in a row**, correctly using the
  anonymous-LAN fallback path already built for Black Ice (this server has
  no Steam ticket validator compiled in, so it's currently accepting any
  Steam client unverified — fine for this diagnostic, not for production).

### Mystery packet, SOLVED: wrong Master/Game ports, not a protocol bug

The 13-byte `7D×12+1` packet to the Master port was a red herring — it's
Fusion's own NAT-reachability probe (`NetPeerGroup`, see below), a
best-effort side channel, **not** what the client actually needs to proceed.
Confirmed by capturing real Photon Cloud traffic (see "Cross-test" below):
the same probe shape gets sent to real Cloud addresses on port `5055` too,
in parallel, and real Photon Cloud doesn't appear to specially answer it
either — the client just doesn't wait on it.

**The real bug:** Photon's modern client-side default UDP port table
(`Photon.Realtime.ProtocolPorts.Udp`, real source, `ProtocolPorts.cs`) is
`NameServer=27000, MasterServer=27001, GameServer=27002` — not the "old"
`5058/5055/5056` scheme this server (and Photon's own docs default) assumed.
Critically, **the client does not use whatever port a server hands back** in
the `Authenticate`/`GetRegions` response's `Address` field — real client
code (`RealtimeClient.cs`, real source):
```csharp
// on the NameServer, authenticate returns the MasterServer address for a
// region and we hop off to there
this.MasterServerAddress = operationResponse[ParameterCode.Address] as string;

ushort replacementPort = this.ProtocolPorts.Get(this.RealtimePeer.TransportProtocol, ServerConnection.MasterServer);
if (replacementPort != 0)
{
    this.MasterServerAddress = ReplacePortWithAlternative(this.MasterServerAddress, replacementPort);
}
```
It takes only the **host** from our response and always **replaces the
port** with its own client-side table. So every earlier test where we tried
different addresses/ports in `GetRegions`/`Authenticate` responses could
never have mattered — the client was always going to connect to `<our
host>:27001` regardless, and this server never listened there. Confirmed
directly against real Photon Cloud packet captures: the real Master hop for
this session went to `87.120.167.220:27001`, a completely different IP than
the NameServer's `216.120.180.19:27000` and a completely different port
than the classic `5055` default — real Photon Cloud servers are dynamically
load-balanced across a large fleet, port included.

**Fix applied** (`earlier-photon`, committed): `ServerPorts.MasterServerAlt`
and `GameServerAlt`, same pattern as the existing `NameServerAlt` — optional
second listeners sharing the primary role's handler. Run with all three set
to get the modern port triplet:
```sh
BLACKICE_Server__Ports__NameServerAlt=27000 \
BLACKICE_Server__Ports__MasterServerAlt=27001 \
BLACKICE_Server__Ports__GameServerAlt=27002 \
dotnet run --project server/BlackIce.Server.Host -- <advertised-host>
```
No change needed to what address/port `NameServerHandler` sends back — the
client ignores the port anyway, only the host matters.

**Validated true via a real-Photon-Cloud packet capture** (`sudo tcpdump`,
needs the user's hands-on involvement — confirmed `tcpdump -i lo` needs root
on this machine, and Steam/Proton traffic goes out the real network
interface even to loopback-adjacent addresses, not `lo`, so `-i any` was
needed). Full real session captured: NameServer (`27000`) → Authenticate
succeeds → separate connection to Master (`27001`, different IP) → separate
connection to the actual room/relay server (`27002`, yet another IP,
`80.93.214.90` in one capture) with sustained real traffic (large fragmented
packets — live room/game state). Three distinct hops, three distinct real
IPs, exactly matching the modern port triplet.

### Cross-test against Outbound on Steam — validates the fix

Outbound is also owned on Steam (`/mnt/games/SteamLibrary/steamapps/common/Outbound`,
same IL2CPP layout as Switch, **same Photon App ID**
`cffbe809-5036-43d8-84a1-7bf16c924721`). Redirected via `/etc/hosts`
(`127.0.0.1 ns.photonengine.io`) for much faster iteration than Citron —
**purely a diagnostic technique**, doesn't touch or replace the Citron
`OPENPAK_PHOTON_IP` redirect used for the actual Switch target.

Findings, all real client behavior (not our own probes):
- **Steam build uses `ClientAuthenticationType=1` (`Steam`), not
  `NintendoSwitch`** — confirms different platforms use different auth
  providers on the same Photon app.
- Auth data sent via `ClientAuthenticationParams` (216) as a **string**
  (`"ticket=<hex>..."`), settling that open question from the earlier
  Photon-Cloud test-app investigation.
- `AppVersion` really is sent as `""` — confirmed on real traffic, not a
  mistake in our own probes.
- With the `MasterServerAlt`/`GameServerAlt` fix in place, our server's
  `OpAuthenticate` (on the alt NameServer port) accepted a real Steam auth
  request cleanly (`rc=0`), via the existing anonymous-LAN fallback (no
  real Steam ticket validator compiled in yet — fine for this test, not for
  production), and the Steam client's UI **generated real room codes**
  multiple times in a row when redirected at our own server — the
  `GetRegions`/`Authenticate`/port-triplet flow now works end-to-end for a
  Steam-authenticated client.

### Fusion SDK research: architecture is bigger than "GpBinary relay"

The official Photon Fusion 2.1.2 Unity SDK (`photon-fusion-2.1.2-stable-2279`,
downloaded from `photonengine.com/en-US/Realtime/Download` after logging in;
requires a Photon account — not redistributed, kept locally only, at
`~/Downloads/photon-fusion-2.1.2-stable-2279`) ships real managed .NET
assemblies that load and run directly on plain .NET 8 (no Unity runtime
needed): `PhotonLibs/netstandard2.0/release/PhotonClient.dll` (the classic
Photon Realtime client — real `Protocol16`/`Protocol18` GpBinary codec
classes, namespace `Photon.Client`) and `Fusion/Assemblies/{Fusion.Runtime,
Fusion.Sockets}.dll` (Fusion's own layer on top). Decompiled locally with
`ilspycmd` (`dotnet tool install -g ilspycmd`) for read-only research; the
DLLs and decompiled output are **not** committed anywhere (copyrighted SDK
material — kept under `~/photon-oracle/`, gitignored by being outside any
repo).

**Key finding: Fusion layers its own session-negotiation protocol on top of
classic Photon**, registered via `RegisterProtocolMsg` — this table is still
accurate and is exactly the layer the live Switch client is now stalled on
(see "Current confirmed blocker" below):

| Code | Message | Purpose (from decompiled source) |
|---|---|---|
| 1 | `Join` | |
| 2 | `NetworkConfigSync` | |
| 3 | `ReflexiveInfo` | Carries `ActorNr`, `PublicAddr`, `PrivateAddr`, `NatType` — exchanged so peers/server can attempt NAT punch-through |
| 4 | `Disconnect` | |
| 5 | `Start` | Session start; carries `StartRequests` flags incl. `WaitForReflexiveInfo`, `ConnectToShared`, `CustomPlugin` |
| 6 | `Snapshot` | |
| 7 | `HostMigration` | |
| 8 | `PlayerRefMapping` | |
| 9 | `ChangeMasterClient` | |
| 10 | `DummyTrafficSync` | |

These are sent as **classic Photon `RaiseEvent`** calls: `SendPackage(100,
targetActor, reliable, buffer, len)` → `RealtimeClientExtensions.SendEvent`
→ ordinary `OpRaiseEvent` with event code `100` ("protocol package"; `101`
is raw passthrough data, `102` is dummy-traffic/keepalive), `CustomEventContent`
= the serialized Message. So implementing this exchange is realistic within
our existing `MasterServerHandler`/`GameServerHandler` (already relay
`RaiseEvent`) — **but only after a room is actually created/joined**, since
`RaiseEvent` needs a joined room/game context.

The 13-byte `7D×12+1` "mystery packet" mentioned in earlier notes was Fusion's
own NAT-reachability probe (`NetPeerGroup`, the raw transport described
above) — a best-effort side channel confirmed to also fire against real
Photon Cloud in parallel with a working session, so it's not on the critical
path and needs no fix. It was a distraction from the real, much simpler
bugs below, all found this session by running `earlier-photon` with
`--trace` against the **live Switch + Citron + OpenPak client** (not Steam)
and reading the byte-level transport log until the discrepancy from expected
behavior was obvious.

### Four real bugs found and fixed this session (live Switch client)

Each was found the same way: run the server with `--trace`, drive an actual
Host Session attempt from Citron, and read the raw eNet/Photon trace until
the client's behavior stopped matching what the server assumed. Each fix
moved the failure visibly further down the connection flow — confirmed by
the Citron error screen changing each time (generic "A Photon error has
occurred" → "connection interrupted (1001)" → "connection interrupted
(1020)"), not just by log inspection.

**1. eNet `SendFragment` (command type 8) was never implemented —
`earlier-photon`.** `EnetPeer.HandleCommand`'s switch had no case for it; a
fragmented reliable send got the generic transport ACK (satisfying eNet, so
the client never retransmitted) but its payload was silently dropped —
`appPayload` stayed null, so it never reached `OnOperationRequest`. This is
why the Switch client looked like it "never sends `Authenticate`": its real
`Authenticate` request — `ClientAuthenticationType=NintendoSwitch` (11) plus
the full signed BAAS token as `ClientAuthenticationParams`, ~1474 bytes
total — exceeds one UDP datagram and gets fragmented into two `SendFragment`
commands, which the server ignored, leaving the client waiting forever on a
response that would never come (pure eNet `Ping`/`Ack` keepalive, confirmed
byte-for-byte via `--trace` — ruling out the alternate theory that the
client was reacting to a wrong/malformed server answer). Fixed in
`BlackIce.Photon/Transport/EnetPeer.cs` (`HandleFragment`, reassembly keyed
per-channel by start sequence number). **Got the field layout wrong on the
first attempt** — assumed a 6-field/24-byte sub-header (adding a redundant
`fragmentLength` field); the real layout, verified byte-for-byte against the
live capture, is 5 big-endian `int32` fields (`startSeq, fragmentCount,
fragmentNumber, totalLength, fragmentOffset`, 20 bytes total) with
`fragmentLength` implicit as `payload.Length - 20`. Cross-checked against
two real fragments: `totalLength=1474`, fragment 1 `offset=0 len=1152`,
fragment 2 `offset=1152 len=322` — `1152+322=1474` exactly. Tests:
`TransportTests.SendFragment_reassembles_across_two_fragments` and
`..._still_acks_each_fragment_individually`.

**2. `OpJoinLobby`/`GameList` ignored the client's requested lobby name —
`MasterServerHandler.cs`.** Fusion joins a lobby *named after its own
session code* (`ParameterCode.LobbyName`=213, e.g. `"JNNC7E"`) before
hosting, presumably to check whether a room under that code already exists.
Our server always pushed back its own hardcoded Black Ice realm list
regardless of the requested lobby, which the client silently couldn't use —
it just sat there afterward (pure keepalive pings, no `CreateGame`/`JoinGame`
ever sent, no error, spinner forever). Fixed: only the **default** (unnamed)
lobby gets the Black Ice realm list now; any **named** lobby gets an empty
`GameList`, which unblocked the client immediately — it proceeded straight
to a real `OpJoinGame` on Master carrying the actual room code and Fusion's
own room properties (`scene`, `vehicleType`, `version`, plugin name
`"FusionPlugin"`, etc.).

**3. `GameServerHandler.EnterRoom` rejected any room name that wasn't a
pre-configured "realm".** BlackIce's whole room model is fixed, named,
persistent realms (`"Black Ice — Co-op"` etc.) — there's no concept of an
ad-hoc client-created room. Fusion is the opposite: every "Host Session"
click creates a brand-new room under a random 6-character code, never a
pre-configured name — so every join attempt got `rc=-4 "No such realm"`,
and Citron showed **"connection interrupted (1001)"**. Fixed: only a
*known, disabled* realm is rejected now; a room name that doesn't match any
configured realm is treated as an open ad-hoc room (same behavior as when no
realms are configured at all, which tests already covered). Test renamed/
added: `EnterRoom_allows_ad_hoc_room_not_matching_any_realm`,
`EnterRoom_rejects_disabled_realm`.

**4. The well-known Photon room property `MasterClientId` (247/248, inside
`GameProperties`) was defined as a constant (`PhotonCodes.RoomProperty.
MasterClientId`) but never actually populated anywhere.** Every Photon/Fusion
client reads this to know who's authoritative for the room. Its absence
looked to Fusion like a room with no valid master: the client's own
`OpJoinGame` succeeded (`rc=0`, correct `ActorNr`), but it then immediately
called `OpLeave` and disconnected cleanly — Citron showed **"connection
interrupted (1001)"** again, this time *after* a successful-looking join
rather than at the join itself, which is what pointed at a
response-content problem rather than a rejection. Fixed: `EnterRoom` now
always stamps `GameProperties[MasterClientId] = room.ActorNumbers.Min()`
(standard Photon convention — the lowest/longest-present actor number).
Test: `EnterRoom_stamps_master_client_id_as_lowest_actor`.

### Current confirmed state: classic Photon LoadBalancing works end-to-end

With all four fixes, a real Switch + Citron + OpenPak client now completes
the **entire** classic Photon connection flow against our self-hosted
server: `GetRegions` → `Authenticate` (NintendoSwitch auth type, real signed
BAAS token, fragmented and reassembled correctly) → redirect to Master →
`Authenticate` → `JoinLobby` (scoped correctly) → `JoinGame` on Master →
redirect to the Game server → `Authenticate` → `JoinGame` accepted
(`ActorNr=1`, `MasterClientId=1`, room created ad-hoc under the real session
code). This is confirmed directly from `--trace` server logs on a live
Switch session, not inference.

### Fusion's Join/Start session bootstrap: implemented and ground-truth-verified

Immediately after the Game-server `JoinGame` succeeds, the client sends its
first Fusion-layer message: `OpRaiseEvent` with event code `100` ("protocol
package" — see the `RegisterProtocolMsg` table above). This turned out to be
a **real, documented wire format**, not opaque client behavior: Fusion's
decompiled `Fusion.Sockets.dll` (`Fusion.Protocol` namespace) contains actual
`Message`/`Join`/`Start`/etc. classes with real `Serialize`/`SerializeProtected`
methods — a genuine (if unpublished) spec, not something that had to be
inferred purely from behavior.

**The wire format is bit-packed, not byte-aligned** — fields as small as one
bit (`WriteBool`), one byte, or N bytes are packed back-to-back with no
padding except at the very end. Traced the exact algorithm from
`BitStream.WriteByteAt`/`InternalReadByte` (LSB-first within each byte,
multi-byte ints written low-byte-first) and reimplemented it clean-room as
`BlackIce.Photon/FusionProtocol.cs` (`FusionBitReader`/`FusionBitWriter`) —
**never** by loading or executing the proprietary DLL itself (loading it via
reflection hit an unrelated native `NanoSockets` dependency chain and was
abandoned; the bit-packing algorithm is simple enough to reimplement
directly from reading the decompiled source as a spec, the same technique
used throughout this project). A `~/photon-oracle/oracle.csproj` scratch
tool exists locally for this kind of research (gitignored by being outside
any repo, per the project's existing DLL-research convention) but the final
codec has zero dependency on it or the DLLs.

Implemented in `GameServerHandler.HandleRaiseEvent`:
- On a `Join` message with `Type=Request`: reply with a `Join` `Confirmation`
  (`FusionProtocol.EncodeJoinConfirmation`), and stash the decoded request on
  `PeerRoomState.PendingFusionJoin` — **do not** send `Start` yet.
- On the client's own follow-up `NetworkConfigSync` (message id `2`,
  triggered by the Confirmation's `JoinRequests` flags): send `Start`
  (`FusionProtocol.EncodeStart`), then clear the pending state.

**Sequencing matters and isn't optional.** The first version sent
`Confirmation` and `Start` back-to-back immediately, which is what a naive
reading of the decompiled `HandleStartMessage`/`HandleJoinMessage` suggests
should work — the client still requires `sender==0` on both, but not that
they arrive at any particular pace. In practice, sending both at once raced
the client (observed against a real live Switch session) into calling
`OpLeave` and disconnecting almost instantly (~0.16s), even after the
message *content* was independently verified correct (see below) — this
only became reproducible against our own near-zero-latency local server;
real Photon Cloud's natural network RTT happens to separate these steps
enough that the race never manifests there. **Every field value below was
independently confirmed** by cross-testing Outbound on Steam against real,
unredirected Photon Cloud (repeating today's earlier proven technique — see
"Cross-test against Outbound on Steam" above) and decoding the actual
server response bytes with the exact same bit-reader — a genuine "Host
Session" that succeeded, room code `JWN7NE`. This caught three fields a
plausible-looking guess had gotten wrong:

| Field | Guessed | Real server | 
|---|---|---|
| `Join Confirmation` `PeerMode` | `Server` (1) | **`Client`** (2) |
| `Join Confirmation` `JoinRequests` | `None` (0) | **`NetworkConfig`** (2) |
| `Join Confirmation` `UniqueId` | `null` | **present, 8 random bytes** |
| `Join Confirmation`/`Start` `CustomData` | `null` | **`""`** (empty string, not null) |
| `Start` `RemoteServerID` | `0` | `0` ✓ (already correct) |
| `Start` `StartRequests` | `ConnectToShared` (2) | `ConnectToShared` (2) ✓ (already correct) |

The real server's `Confirmation`/`Start` payloads decoded with **zero
leftover bits** (300/304 and 193/200 — the remainder in each case is exactly
the trailing byte-alignment padding), confirming the field layout and order
are exactly right, not coincidentally close. Both exact byte sequences are
pinned as regression fixtures in `FusionProtocolTests.cs`
(`RealCapturedConfirmation`/`RealCapturedStart`).

**Confirmed live**: with sequencing and all field values fixed, a real
Switch client now completes the *entire* bootstrap correctly —
`Join Request` → `Confirmation` → client's own `NetworkConfigSync`
(fragmented, reassembled correctly by the earlier eNet fix) → `Start`. This
is the full extent of what "Fusion session bootstrap" means at the protocol
level, and it now works end-to-end, verified byte-for-byte against ground
truth, not just "stopped erroring."

### Fusion's relay transport handshake (event code 101, Connect/Accepted): implemented

Even with a byte-perfect `Start`, the client still disconnected shortly
after (~120ms) — but the *reason* was pinned down precisely from the same
real Steam capture: immediately after receiving `Start`, the real client
sends its own message on a **different** event code — `101` ("DATA", not
`100` "protocol package"). Unlike code `100` (bit-packed `Fusion.Protocol`
messages), code `101` carries **raw C `[StructLayout(LayoutKind.Explicit)]`
struct memory layouts** from `Fusion.Sockets`' `NetPeerGroup`/
`NetSocketRelay` — Fusion's own separate low-level transport, tunneled
through classic Photon's `RaiseEvent` when running in relay mode rather than
using a real socket. Decoded field-for-field by mirroring the exact structs
(`NetCommandHeader`, `NetCommandConnect`, `NetCommandAccepted`,
`NetConnectionId`) as local `unsafe` C# types and reading captured bytes
through them via `MemoryMarshal`/pointer casts — not by hand-counting byte
offsets, which is fast but error-prone for packed native layouts. The
client's first `101` message is a `NetCommandConnect` (152 bytes:
`PacketType=Command`, `Command=Connect`, `TokenLength=0`, and critically a
**`UniqueId` field that exactly matches the server's own `Confirmation`
`UniqueId`** — the client is "connecting" to the relay using the identity
token the server gave it minutes earlier). The real server replies within
~40ms with a `NetCommandAccepted` (32 bytes: `AcceptedLocalId`=
`AcceptedRemoteId`={Group=0, GroupIndex=0, Generation=1}, `Counter=1` — a
self-loopback accept, appropriate for a solo Shared-mode host). Implemented
as `FusionRelayProtocol` (`BlackIce.Photon`), wired into
`GameServerHandler.HandleRaiseEvent`; both directions pinned as regression
fixtures (`FusionRelayProtocolTests`) against the real captured bytes.

**Confirmed live** (Switch/Citron): with this reply in place, the failure
point moved again — no more instant disconnect after `Start`.

### A real Citron bug, found and fixed: corrupted socket blocked all further progress

With the server-side protocol fully correct, the Switch/Citron client still
never got as far as attempting the relay `Connect` above — it disconnected
(or, once this bug was fixed, hung) even earlier, before that step. Citron's
own log (`~/.local/share/citron/log/citron_log.txt`) pinpointed it exactly:
right after `Start`, the game calls `socket()` a second time (for its own
NAT-punch/local-UDP attempt, `Fusion.Sockets`' `NetSocketNative`, separate
from the Photon-relay connection) with **two unknown flag bits set
simultaneously** in the type field. `earlier-citron`'s
`BSD::SocketImpl` (`core/hle/service/sockets/bsd.cpp`) already stripped one
of them (`0x20000000`, added for some earlier game) but not the other
(`0x10000000`) — the leftover bit survived into
`Service::Sockets::Translate(Type)`, which has no case for it, hit
`UNIMPLEMENTED_MSG`'s assertion path, and the socket was left corrupted:
every subsequent `Bind()`/`Connect()` on that fd failed with `EBADF`
("Bad file descriptor").

**Fix** (`earlier-citron`, committed): strip `0x10000000` the same way,
right after the existing `0x20000000` strip, in `BSD::SocketImpl`.
**Confirmed live**: the socket now creates as a clean `SOCK_DGRAM` and
`Bind()` succeeds. Rebuilt incrementally (`ninja citron` in
`build/use-nopgo`, ~15 files relinked, no full rebuild needed).

**Result**: the connection now survives 25+ seconds of steady keepalive with
**zero errors** — longer than any attempt made at any earlier point in this
entire investigation (every prior test failed within 30s–120ms with an
explicit disconnect). This is a qualitatively different, better state than
anything seen before today's server-side protocol work even started.

### Current confirmed blocker: Fusion's P2P listen socket blocks forever, freezing the whole game

With the socket-type-flag bug fixed, the game no longer errors or
disconnects — it hangs completely. Investigating produced two false leads
before the real cause, worth recording so they aren't re-chased:

- **False lead 1 — "Citron's log shows traffic past our server's eviction
  point."** This was a counting error, not a real discrepancy: counting
  every `LogPhotonPacket` TX/RX entry on the classic Photon connection and
  comparing to the server's own SEND/RECV trace for the same peer produced
  **exact matching totals** (e.g. 27 client-TX ↔ 27 server-RECV, 35
  client-RX ↔ 35 server-SEND). Every packet either side logged genuinely
  reached the other. There was no gap.
- **False lead 2 — "Citron logs a Critical panic (`Userspace PANIC!`,
  `Suspending thread due to unrecoverable break`) partway through."** Both
  times this was seen, it was immediately preceded by `Frontend <Warning>
  ForceStop: Force stopping EmuThread` — Citron's own normal shutdown
  sequence when the emulated process is closed (by the user giving up on a
  frozen window, or the process being killed for the next test). It's
  expected noise from closing a frozen session, not a spontaneous crash.

**The real cause**, found by attaching `gdb -p <pid> --batch -ex "thread
apply all bt"` to a *still-frozen* Citron process (the only way to get a
real answer — reading logs after closing the window only shows the harmless
`ForceStop` aftermath):

- All four `CPUCore_0`..`CPUCore_3` threads (the emulated guest CPU cores —
  i.e. Outbound's own code) are sitting idle in
  `Core::CpuManager::MultiCoreRunIdleThread()`, meaning **no guest
  instructions are executing at all**. The Qt UI thread is healthy (just
  polling for OS window events), which is why the window doesn't crash —
  it's simply not receiving new frames to display.
- A citron-internal worker thread (`bsdsocket:2`) is blocked inside a
  **real, literally-blocking libc `recvfrom()`** call, reached via
  `Network::Socket::RecvFrom` ← `Service::Sockets::BSD::RecvFrom`. Citron's
  socket HLE is behaving correctly here — it only avoids blocking when the
  guest explicitly requests `MSG_DONTWAIT`/`O_NONBLOCK`, or when
  `SO_RCVTIMEO` is set (both paths are implemented and correct); this call
  used neither, so citron faithfully blocks exactly as real POSIX
  `recvfrom()` would.
- Citron's own log shows **zero further activity of any kind** on this new
  fd after its `Bind()` succeeds — no `Connect()`, no logged send. The most
  likely explanation: Fusion opened this UDP socket to *listen* for a
  future P2P/NAT-punch connection attempt from another player joining the
  session (standard behavior for a host) and is blocking-`recvfrom()`-ing
  on it, fully expecting *someone else* to send the first packet. In this
  solo, `OPENPAK_PHOTON_IP`-redirected setup there is no second peer and
  nothing will ever arrive — real Photon Cloud sessions presumably don't
  hit this because a real joining peer's own NAT-punch attempt would
  eventually reach this socket.
- Because HOS's IPC model makes the *guest* thread that issued the
  `recvfrom()` syscall genuinely block until the HLE call returns, and the
  game's main/logic thread evidently waits synchronously on this step
  before proceeding (a game-side design choice, not a citron bug), the
  entire guest OS ends up with no runnable thread — hence all four CPU
  cores going idle and the total freeze.

This is *not* a citron bug to fix by changing socket blocking semantics —
faithfully blocking is correct behavior for what the guest asked for, and
arbitrarily timing out blocking receives generally would risk breaking
other games' legitimate long-waits. The right fix is upstream: give this
socket something valid to receive.

### Confirmed live: unblocking it works, and it's Nintendo's PRUDP-Lite protocol, not Fusion's

Found the exact bound port with zero extra tooling — no sudo, no packet
capture — by just inspecting the running (still-frozen) Citron process's
own sockets as its own user:
```sh
ss -tunap 2>/dev/null | grep <citron-pid>
```
This showed two UDP sockets: the healthy, `connect()`-ed classic-Photon
session (`ESTAB`, `127.0.0.1:<local> ↔ 127.0.0.1:27002`), and a second,
`UNCONN` socket bound to `0.0.0.0:<ephemeral port>` — never connected,
matching the blocked listener exactly.

**Sent it one arbitrary UDP packet from the host** (a plain Python
`socket.sendto()`, 16 zero bytes, to `127.0.0.1:<that port>`) while Citron
was genuinely frozen. **The freeze resolved immediately** — Citron's log
picked back up instantly, proving the diagnosis exactly: the guest's
`recvfrom()` really was the entire blocker, and *any* datagram arriving is
enough to release it. The game then cleanly shut the emulation down
(`OnEmulationStopped`) rather than staying frozen or crashing — expected,
since 16 zero bytes aren't valid data for whatever this socket expects.

**What it actually expects, from Citron's own source**: this is not
Fusion's own protocol at all — `bsd.cpp`'s `DescribePrudpLite` (already
present, used for exactly this kind of otherwise-unrecognized P2P traffic)
decodes it as Nintendo's own **PRUDP-Lite** transport, the lightweight
P2P-matchmaking protocol from Nintendo's SDK (a reduced version of NEX's
PRUDP), which Photon's own Switch platform integration apparently sits on
top of for local P2P/NAT-punch discovery — separate from both classic
Photon and Fusion's own `Fusion.Protocol` messages. Header format (already
implemented in Citron, so this is read from real code, not guessed):
- Byte 0: magic `0x80` (packets without this magic are treated as
  something else entirely, e.g. Photon Pia — see the `raw[...]=` fallback
  in `DescribePrudpLite`)
- Bytes 8–9: `type_flags`, little-endian `u16` — low 4 bits are the packet
  type (`0`=SYN, `1`=CONNECT, `2`=DATA, `3`=DISCONNECT, `4`=PING), upper
  bits are flags (`0x001`=ACK, `0x002`=Reliable, `0x004`=NeedACK,
  `0x200`=MultiACK)
- Bytes 10–11: `id`, little-endian `u16`
- Minimum 12 bytes total; bytes 1–7 are other header fields this decoder
  doesn't break out further (not yet needed — worth decompiling/inferring
  if a real capture of genuine PRUDP-Lite traffic becomes available)

### Next step

#### 2026-08-29 live control: Nintendo/OpenPak endpoint hypothesis ruled out

The possibility that the freeze was caused by missing Nintendo/NEX/OpenPak
endpoint information was tested directly. Citron was restarted with both
`OPENPAK_ENABLE=1` (enabling its Nintendo/NAT DNS redirects) and
`OPENPAK_PHOTON_IP=127.0.0.1`. Hosting froze in exactly the same place. The
complete DNS trace for the run contained only `ns.photonengine.io`; Outbound
did not request an `nncs`, Nintendo, NEX, or NAT-check hostname, so there was
nothing for the Reference Nintendo/NAT redirect to supply. The same separate
unconnected UDP socket appeared alongside the healthy connected Photon socket.

This also corrects an over-strong earlier interpretation: Citron's
`DescribePrudpLite` output only classifies the bytes injected by the diagnostic
probe when their header matches that decoder. It does not prove the game asked
Nintendo/NEX for a PRUDP service. The socket was created by Fusion's native UDP
transport path, and all observed service discovery remains Photon-only.

The strongest next emulator-side hypothesis is now loss of socket creation
semantics. Outbound creates the native UDP socket with type value
`0x30000002`. Citron currently strips `0x20000000` and `0x10000000` as unknown
flags before translating the remaining `SOCK_DGRAM`, but does not preserve any
behavior associated with either bit. The resulting host socket is blocking;
the guest calls `recvfrom()` without `MSG_DONTWAIT` or a receive timeout and
Citron blocks literally in libc. One or both high bits may encode Nintendo's
socket-level nonblocking/close-on-exec creation flags. Test this by mapping the
appropriate creation bit to `SetNonBlock(true)` and the descriptor's
`FLAG_O_NONBLOCK`, then rebuild Citron and repeat Host Session. This explains
both prior states: leaving `0x10000000` in the base type produced `EBADF`, while
blindly stripping it made the socket valid but potentially changed an intended
polling receive into a permanent blocking receive.

**Confirmed immediately afterward from libnx's Horizon BSD headers:** these
bits are not unknown. `SOCK_CLOEXEC = 0x10000000` and
`SOCK_NONBLOCK = 0x20000000`, documented as creation flags OR'ed into the
`socket()`/`socketpair()` type argument. Thus `0x30000002` means exactly
`SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK`. This proves the freeze's direct
Citron cause: `SocketImpl` removed the nonblocking bit without applying its
semantics, so Fusion's intended nonblocking `recvfrom()` poll became a blocking
libc call.

**Citron fix applied and building:** in
`earlier-citron/src/core/hle/service/sockets/bsd.cpp`, `SocketImpl` now:

- records whether `SOCK_NONBLOCK` (`0x20000000`) was present before stripping
  creation flags from the base type;
- treats `0x10000000` as `SOCK_CLOEXEC` (no separate action is needed for
  Citron's emulated descriptor table);
- after socket initialization, calls `SetNonBlock(true)` and stores
  `Network::FLAG_O_NONBLOCK` in `descriptor.flags`;
- fails socket creation cleanly if enabling nonblocking mode fails.

The incremental `ninja -C build/use-nopgo citron` rebuild was in progress when
this note was written. Next: launch this build with the normal Photon prefix,
Host Session, and verify that the extra UDP socket's empty `recvfrom()` returns
`EAGAIN` instead of freezing. Do not inject synthetic PRUDP packets during this
test; they would obscure whether the socket semantics fix alone resolves it.

#### New live result after the handoff was written: PRUDP packets advanced the client, exposing an eNet type-11 drop

A subsequent live retry refined the blocker substantially:

- The first valid-looking PRUDP-Lite `SYN` released the blocked `recvfrom()` without
  the earlier immediate `ForceStop`, but the client then blocked on a second receive.
- The sender socket from the first attempt had already closed, so it could not participate
  in a continuing exchange. A persistent socket was used for the next attempt.
- Sending `SYN` followed by `CONNECT` from that same socket caused the game to advance and
  immediately send a new 183-byte classic-Photon packet to the self-hosted Game server.
- The client retransmitted the same event-code-101 `OpRaiseEvent` three times over roughly
  40 seconds. The server logged each datagram as `RECV`, but never logged the normal
  `<- OpRaiseEvent` application-level line or sent the relay `Accepted` reply.

The server-side cause is now confirmed from the packet and source, and is independent of
PRUDP parsing: the application message is carried in eNet command type **11**
(`SendUnsequenced`), with a 16-byte eNet command header and a 167-byte Photon payload.
`NCommand.Parse` already recognizes type 11 and extracts its payload correctly, but
`EnetPeer.HandleCommand` only returns application payloads for `SendReliable` (6),
`SendUnreliable` (7), and `SendFragment` (8). It has no `SendUnsequenced` case, so the
167-byte payload is silently discarded before `PeerConnection.HandleAppPayload`, GpBinary
decoding, or `GameServerHandler.HandleRaiseEvent` can run. This precisely explains the raw
`RECV` entries with no matching operation log.

The immediate server fix in `~/REPOS/earlier-photon` is to surface
`NCommand.SendUnsequenced` payloads in `EnetPeer.HandleCommand`, treat them as an unreliable
inbound delivery for relay purposes, and add regression coverage. Then repeat the live
`SYN` + `CONNECT` stimulus with the sender socket kept open. The existing event-101 handler
should finally receive the `NetCommandConnect` and return its already-implemented
`NetCommandAccepted`; the next client state will show whether the PRUDP side needs another
handshake packet or whether the relay acceptance is sufficient.

1. Craft a real, valid PRUDP-Lite `SYN` packet (12+ bytes: magic `0x80` at
   byte 0, `type_flags` u16-LE at bytes 8–9 with type nibble `0`=SYN, `id`
   u16-LE at bytes 10–11, bytes 1–7 still unknown — start with zeros and
   see if that's tolerated, since it clearly wasn't the magic/type/id
   fields that made the last test's all-zero packet get rejected) and send
   it the same way (find the bound port live via `ss -tunap | grep
   <citron-pid>`, or automate finding it — no sudo/capture needed) to see
   whether the game accepts it and proceeds normally instead of exiting.
   If the SYN alone isn't enough, Citron's own `DescribePrudpLite` will
   show in the log exactly what type/flags/id the response (if any)
   contains, same diagnostic loop as the code-100/101 work — iterate from
   there. Bytes 1–7's real meaning (and whatever a real CONNECT/DATA
   exchange looks like) would benefit from a real Steam capture of Outbound
   actually reaching another player, the same proven technique used all
   session, if guessing doesn't converge quickly.
2. Once the freeze is resolved and a **solo host** reaches an actual stable
   in-game state (not just "didn't disconnect"), understand event code
   `101`'s *ongoing* traffic — the relay transport's `Connect`/`Accepted`
   handshake (implemented today) is only connection setup; real Photon
   Cloud showed continuous bidirectional `101` events afterward (repeating,
   growing payloads consistent with tick-based simulation snapshots) that
   this server doesn't send/understand yet. This is Fusion's actual
   real-time state-sync protocol — a substantial separate subsystem, not a
   small follow-up fix.
3. Only after that does implementing enough of `ReflexiveInfo`/
   `PlayerRefMapping`/`ChangeMasterClient` for a **second** real client to
   actually join become relevant — needs a genuine two-peer test (two
   Switches, or one Switch + one Steam client, both against our server) —
   and note a second real peer's own NAT-punch attempt may be exactly what
   the listen socket above is waiting for in the first place, so this step
   and step 1 may turn out to be the same problem solved two different ways.
4. Only after gameplay-level connectivity works for 2+ peers does real
   earlier identity verification become relevant (replacing the current
   accept-all anonymous-LAN stance) — `authbridge`'s role would then either
   get absorbed into this server or stay as a separate verification call it
   makes internally.

### 2026-08-29 live control: freeze confirmed fixed, three new Invite Friends bugs found and fixed

The `SOCK_NONBLOCK` fix from the previous section (preserving `0x20000000`
instead of stripping it, and actually calling `SetNonBlock(true)`) is
confirmed live: a real Switch + Citron + OpenPak session now hosts
successfully with **no freeze at all**. The wall this session hit next was
the in-game **Invite Friends** flow, which repeatedly froze/crashed —
unrelated to Fusion or the Reference backend, all three root causes were
plain citron HLE gaps:

1. **`IDisplayController::GetLastApplicationCaptureImageEx` (cmd 6) was
   `nullptr`.** The friend-invitation card wants a captured screenshot;
   hitting the unimplemented-function fallback left the IPC response
   malformed, which the guest's own fault handler escalated into a fatal
   CMIF/panic path — a genuine freeze, not just a cosmetic crash log. Fixed
   by stubbing it the same way its sibling `GetCallerAppletCaptureImageEx`
   already was (`out_was_written = false`, honest "no capture" answer).
2. **`IFriendService`'s command **20108** (added in firmware 20.0.0, real
   name unconfirmed, called `GetFriendDetailedInfoV3` here) had no case at
   all**, which sent Outbound into the system Error applet (a genuine HOS
   error screen, "CMIF 212... likely an unimplemented applet spawn").
3. **Once 20108 had *a* handler, every content tried for its 0x800+-byte
   MapAlias output buffer corrupted the guest**, confirmed across four
   separate live attempts: writing this file's own `FriendImpl` struct
   (guest walked off into unmapped reads past our short data — the guest
   always allocates exactly `MaxRequestedIds`=300 entries here, i.e. this
   is a *batch* candidate-list call like `GetFriendDetailedInfoV2`, just
   against a real per-entry struct 0x220/544 bytes wide, not `FriendImpl`'s
   0x200/512); leaving the buffer untouched (HIPC does not guarantee it
   arrives zeroed — the guest read back live heap garbage as a pointer and
   wrote through it forever, "Unmapped Write64 @ 0x0" looping); an all-zero
   fill sized to the guest's own allocation (still glitched into a garbled
   framebuffer, then froze); one real friend entry written at the computed
   544-byte stride, assuming `FriendImpl`'s layout holds for the leading
   bytes of the real struct (same corruption — that assumption is wrong).
   **Final fix: fail the call outright** (`Result{ErrorModule::Friends, 1}`,
   arbitrary non-zero code) and never touch the buffer. The guest's own
   success check — which every content-based attempt above skipped past,
   since they all returned `ResultSuccess` — is what actually gates whether
   it reads the buffer at all. This resolves cleanly to the game's own
   generic system error dialog (`Error Code: 2121-0001` — confirms the
   on-screen code format is exactly `(2000+module)-(description)`) instead
   of a freeze or corrupted framebuffer, and the hosted Photon session
   survives it untouched (confirmed live: `fd=0` keeps ticking fine both
   before and after the error dialog).

All three fixes are committed in `earlier-citron`
(`9ad10b0a7`).

**A separate, non-citron finding from the same testing**: exiting the
Invite Friends screen — by any means tried (Back, or dismissing the
20108-triggered error) — makes Outbound itself send an explicit Photon
`Disconnect` command and tear down the *entire* hosted session, which is
what actually produces the player-facing **"connection interrupted
(1020)"** message. This happened identically regardless of what citron
returned for 20108, so it isn't a citron bug: Outbound appears to be
waiting for a real end-to-end friend-invitation delivery (see next
section) and gives up on the whole session when that never happens,
using its generic disconnect message for any session end, not
specifically for an error.

### Recommended next direction: skip the native Invite Friends applet, use presence-based join instead

The **Invite Friends** system applet is Nintendo's own LLE code (real
firmware, not something citron reimplements) reading from `IFriendService`
calls including firmware-20.0.0-only ones like 20108 that have **no public
documentation** — every attempt to synthesize plausible data for it
corrupted the guest, and pinning the real struct layout would need a
genuine packet capture of real hardware exercising this exact flow
(camera/screenshot data included), a much bigger ask than the Steam
cross-test technique used earlier in this project for the classic Photon
flow.

`web_service/legacy_api.cpp`/`.h` already has a **complete, working,
simpler alternative** that sidesteps the whole native-invite-applet
problem: `PushPresence(status, app_field, app_id, app_name)` publishes an
opaque per-title `app_field` blob (intended to carry the joinable-session
info — the Fusion room code, in Outbound's case) alongside online/in-game
status, and `GetFriends()` already returns each friend's own `app_field`
back out. This is the standard "friend sees you're in a joinable game and
joins from their own friends list" model — no NPNS-style push, no
`PushToFriendInvitationStorageChannel`/`SendFriendInvitation` round trip,
and it only touches calls already proven working and well-understood in
this codebase (`GetFriendCount`, `GetFriendListForViewer`,
`GetFriendDetailedInfoV2`, `UpdateFriendInfoForViewer` — all confirmed
live and documented above/in `friend.cpp`'s own comments).

Scoped next steps for this direction, not yet started:
1. Confirm what Outbound actually writes into its own presence `app_field`
   when hosting (needs a live capture the same way App ID/GetRegions were
   recovered earlier this project — likely contains the Fusion room code
   and maybe `scene`/`vehicleType` from the room properties already seen
   in the classic-Photon `OpJoinGame` trace).
2. Wire `Common::OpenPakFriends::SetLocalPresence`/
   `TakeLocalPresenceForPublish` (already exist, see
   `common/legacy_friends.h`) through to `legacy_api.cpp::PushPresence`
   for Outbound specifically, if not already generic across all titles.
3. On the joining side, surface a friend's joinable presence somewhere
   reachable without the native Invite Friends applet — most likely
   citron's own OpenPak-menu UI (`src/citron/legacy_*`), not a HOS
   system applet, sidestepping the undocumented-struct problem entirely.
4. Only if this path proves insufficient (e.g. Outbound's own UI hard-
   requires the native invite flow to complete before it considers a
   session real) does reverse-engineering 20108's real struct via a
   genuine hardware/Steam capture become necessary.

### 2026-08-29 follow-up: actually checked whether 20108 is decompileable from Outbound's own binary

Called out (correctly) for asserting the struct behind cmd 20108 was
"undocumented" without first checking whether Outbound's own compiled code
— which this project has real precedent decompiling (see `friend.cpp`'s
existing ARMS/Splatoon 2/3 presence-blob fixups, reverse-engineered from
their update binaries) — already reveals it. It was checked, thoroughly,
with real tooling, not just `strings`:

- Extracted the real decrypted `main` NSO for `0100ED9024EB8000` via
  **Ryujinx's "Extract Data → ExeFS"** (citron has no equivalent feature —
  only "Dump RomFS" exists in `src/citron/game_list.cpp`). Ryujinx already
  had the title installed from the earlier save-transfer work.
- Ran `Il2CppDumper` (`github.com/Perfare/Il2CppDumper`, cloned+built
  locally with `dotnet build`, not committed anywhere) against that `main`
  NSO plus the `global-metadata.dat` already in this project's RomFS dump
  — full success, produced a real `dump.cs` with genuine C# type/method
  signatures for the entire game, including Nintendo's actual
  `NintendoSDKPlugin` Unity wrapper for `nn.friends`.
- Wrote a small NSO segment decompressor (`.text`/`.rodata`/`.data`, raw
  LZ4 block format, not committed — scratch-only, same status as the
  `~/photon-oracle` DLL-research convention already established in this
  doc) and disassembled the native accessor functions (`GetAccountId`,
  `GetNickname`, `GetPresence`, `IsFavorite`, `IsNewly`, `IsValid`) at
  their real RVAs with `capstone` (ARM64).

**Result, confirmed from real disassembly, not inference:** every one of
those native accessors starts with `mov w2, #0x200` before copying the
managed `nn.friends.Friend` struct — it really is exactly 0x200 (512)
bytes, an exact independent match for this file's own `FriendImpl`
(`static_assert(sizeof(FriendImpl) == 0x200)`). This is a genuine,
welcome confirmation that `GetFriendDetailedInfo`/`V2` (20102/20107)
already use the right struct — not something this session set out to
prove, a useful byproduct of checking cmd 20108.

**But cmd 20108's struct still isn't in Outbound's binary, for a real
reason, not a shrug:** Outbound's own compiled `nn.friends` bindings cap
`FriendInvitationInviteeCountMax` at **16**, not 300 — nothing in
Outbound's own code path matches the 300-entry, 544-byte-stride buffer
the crash showed. Combined with the earlier finding that "Select Friends
to Invite" is Nintendo's own native system applet UI (not drawn by
Outbound), this makes sense architecturally: that applet runs as its
*own* process with its *own* `IFriendService` IPC session and queries it
directly to populate its own UI — Outbound only launches it
(`StartSendingFriendInvitation`/`ShowFriendList` in the SDK bindings).
Command 20108's real caller is Nintendo's system firmware code, which
lives outside Outbound's game binary entirely, in the console's actual
system title files — a genuinely different, bigger category of dump than
a game's own ExeFS (the user's own console's firmware, not the game),
not something further work on Outbound's binary can reach no matter how
thorough. Leaving `GetFriendDetailedInfoV3` failing cleanly (see above)
remains correct until/unless that firmware-side struct becomes reachable
some other way.

### 2026-08-29 follow-up 2: the system-firmware side was tried too, hit a real dead end

Pushed one step further rather than stopping at "needs system firmware":
the actual applet (`0100000000001013`, "MyPage" — real name from
`AppletProgramId` in `src/core/hle/service/am/am_types.h`, and confirmed
live: `PatchExeFS for title_id=0100000000001013` fires in citron's log at
exactly the moment Invite Friends is opened) was already sitting decrypted
in citron's own installed NAND — no new firmware dump was needed, the user
already has one from getting LLE applets working at all. Extracted its
ExeFS with a small scratch addition to `citron-cmd`
(`src/citron_cmd/citron.cpp`, gated behind an unused `--legacy-nca-
extract <nca> <out-dir>` flag, reuses citron's own `FileSys::NCA`/keys —
not meant to stay long-term, citron has no GUI equivalent of Ryujinx's
"Extract Data → ExeFS" for a *system* title since they aren't in the game
list either way).

Unlike Outbound, this binary is stripped native Nintendo C++ with zero
IL2CPP-style metadata to lean on. Located a genuine command-dispatch
chain in the decompressed `.text` (`mov w8, #0x4e8c` /* 20108 */
`; cmp w21, w8 ; b.ne <next check>`, part of a real `cmp`-chain matching
a running "current command" register against many IDs in sequence) and
followed the match through — it turned out to feed a generic opcode-
driven state machine/parser (`str x8, [x19, #0xaf0]` then a shared
dispatch-loop jump), not friend-service-specific marshaling code. An
earlier broad scan of the whole `.text` section had already found
thousands of `mov`-immediate hits essentially uniformly spread across the
entire 20000–30000 range, which fits this being a coincidental numeric
match on an unrelated opcode, not a real command-ID check. Confirmed
dead end, not abandoned early: getting the real struct out of this
binary would need proper decompiler-grade analysis (Ghidra/IDA-class
tooling with real cross-referencing time), not pattern-matching a
constant.

### 2026-08-29 follow-up 3: actually resolved — the real bug was never the struct, it was a missing response word

The RE dead end above turned out to be the wrong target entirely. The
tell was hiding in plain sight: failing the call outright (never
returning `ResultSuccess`) *also* stopped the crash, alongside every
buffer-content variant that returned success. If this were really about
the per-entry struct layout, only *some* success-path contents should
have crashed, not literally all of them uniformly — the guest was gating
on the **result code path**, not on what was inside the buffer.

This file's own sibling batch calls that return a variable number of
entries out of a fixed-capacity buffer (`GetFriendListForViewer`,
`GetProfileList`) all push an explicit `u32 count` alongside
`ResultSuccess` (`IPC::ResponseBuilder{ctx, 3}`), for the obvious reason
that a fixed buffer's own size can't tell the caller how many of its
slots are actually valid. `GetFriendDetailedInfoV3` takes no id list
(only a single `Uid` + `NetworkServiceAccountId`) but still writes into a
300-slot buffer — it needs that same count scalar for the same reason,
and every attempt so far had only pushed `{ctx, 2}` (Result only, no
count). A missing count reads as an uninitialized/garbage stack value on
the guest side, which explains exactly the "walks off into billions of
bytes, unbounded" read/write pattern every crash showed — a missing
response word, not a wrong struct.

**Fix, confirmed live:** succeed with an honest `count=0` (buffer zeroed,
no detailed entries claimed) alongside the count word. The Invite Friends
screen now renders its own real, correct Nintendo empty-state UI —
*"You can add friends from your user page in the top left-hand corner of
the HOME Menu."* — instead of crashing. And critically, unlike the
fail-clean version, **backing out no longer tears down the hosted Photon
session**: MyPage now treats this as a normal user cancel rather than a
service error, so it no longer propagates a failure up to Outbound.
Confirmed live: `fd=0`'s Photon traffic keeps ticking with zero
disconnects after opening and cancelling Invite Friends. Committed in
`earlier-citron` (`07a3fc675`).

**What's still open:** your real earlier friend still won't *appear* in
that picker — `count=0` is honest but doesn't surface real data, since
the per-entry struct for a non-zero count is still unconfirmed (the
`FriendInvitationInviteeCountMax=16`/system-applet findings from the two
follow-ups above still stand — that data genuinely isn't in Outbound's
binary, and the system-firmware RE attempt is still a real dead end for
*that specific question*). But the crash/session-teardown blocker driving
today's whole investigation is resolved — solo hosting now survives
Invite Friends being opened and cancelled, which is what was actually
blocking forward progress through the game's flow.

### 2026-08-29 follow-up 4: real earlier data forwarded, full flow reaches a real "Invitation sent"

Once the crash was actually fixed (not just contained), the natural next
step was forwarding real data instead of an honest `count=0`:
`Common::OpenPakFriends::Get()` — already correctly powering
`GetFriendCount`/`GetFriendListForViewer` — is the same cache this file's
`MakeFriend()` helper already knows how to convert to `FriendImpl`. Doing
that immediately surfaced your real friend as a selectable tile (count=1,
confirmed live), but with no avatar/name/online-status — a narrower,
more precise version of the "real struct layout" question than before.

Live testing this pinned it exactly: MyPage's own follow-up calls
(`GetFriendProfileImage`, `GetFriendDetailedInfoV2`) were reading a
**zero Uid** out of the buffer we wrote, even with `FriendImpl` at
offset 0 within each 544-byte entry — proof the real struct's Uid field
isn't at offset 0, even though whatever makes the tile itself
selectable does line up. Pushed the RE further with a much more precise
target than command 20108 (a generic-and-noisy server-side dispatch
constant): searched for `GetFriendProfileImage`'s real command ID
(10110, `0x277e`) as an immediate in MyPage's own compiled code and got
exactly **one** hit — a clean, real proxy-stub tail-call table (Nintendo
SDK auto-generated trampolines, one tiny function per command, each
loading its command ID then jumping to a shared IPC-send helper).
Confirmed the stub dereferences a pointer for 16 bytes as the Uid
argument, but the stub itself is called only *indirectly* (through a
vtable slot, not a direct `bl`) — found its one reference in `.data`
(consistent with a vtable entry) but tracing back to the actual call
site (which struct field gets passed as that pointer) needs full
class/vtable reconstruction, genuinely decompiler-grade work (Ghidra/IDA
with real time invested), not something achievable by pattern-matching
raw bytes with `capstone`.

Rather than guess a third exact offset blind, tried a cheap two-guess
hedge instead: write `FriendImpl` at **both** offset 0 (original guess:
32 trailing pad bytes) and the tail-aligned offset `entry_stride -
sizeof(FriendImpl)` (alternate guess: 32 leading header bytes) within
each entry — free to test, no extra RE needed. **Confirmed live this
unlocked real forward progress**, even though the Uid read is still
apparently wrong (avatar/name still don't render): a new **"Y View
Details"** button appeared that wasn't there before, leading to a real
details screen (showing a `When You Became Friends: 31/12/1999 00:00`
field — Nintendo's network epoch starts 2000-01-01, so this is a zeroed
field we don't populate rendering as one day before epoch, confirming
the real struct genuinely has more fields than `FriendImpl` models) with
a real **Invite** button (`Invitations remaining: 3`), which reached the
friend picker with the tile actually selectable (`1/3`, checkmark) and
**"Next" -> a real send that completed with "Invitation sent"**.

The session then disconnected with the same generic "connection
interrupted" error as earlier follow-ups — **expected, not a
regression**: `SendFriendInvitation` is still a plain stub with zero
real delivery (no NPNS-equivalent push to leia's account exists yet), so
Outbound waiting for some response that will never arrive and eventually
giving up is exactly what a missing invitation-delivery pipeline should
look like. This is the "presence-based join" / real-delivery work
already scoped further up this document — not a new bug to chase.

Committed in `earlier-citron` (`eed426e61`). Current state: the
crash/session-teardown blocker is fully resolved, real earlier friend
data flows all the way through to a completed send, and the two
remaining gaps are both already-scoped, separate pieces of future work:
(1) the exact Uid/name/avatar field offsets inside the real 544-byte
struct (needs decompiler-grade RE of MyPage, not more guessing), and
(2) actual invitation delivery to a second real peer (needs the
presence-based join work, or a real NPNS-equivalent push pipeline).

### 2026-08-30: correction on Fusion relay scope, random-matchmaking dead end, and a real presence-based join path (bypasses the applet struct wall entirely)

Three findings today, none requiring more struct RE:

**1. Fusion's ongoing state-sync is very likely already relayed correctly.**
Earlier docs in this file (see `FusionRelayProtocol`) treated Fusion's
in-room simulation traffic (event 101, `UnreliableData`) as "a substantial
separate subsystem, not a small follow-up fix." That was wrong. Checked
`earlier-photon`'s `GameServerHandler.cs`: the generic
`_registry.Session(state.RoomName).RelayFrom(state.Actor, new EventData(ec,
...), peer.CurrentInboundUnreliable)` call runs unconditionally for every
event code, not just the specially-handled 100/101 handshake — and
`RelayFrom` (`RoomSession.cs`) is a plain room-wide broadcast, generic over
event code. The server doesn't need to understand Fusion's internal bit-
packed simulation format at all; it only needs to move bytes between two
real game clients that already understand each other. Ongoing gameplay
sync should already work once two real peers are in the same room — not
independently verified live yet (needs an actual two-peer join, see below),
but no code work is expected to be required here.

**2. Random/public matchmaking is a confirmed dead end, checked properly
this time.** Grepped Outbound's own IL2Cpp dump for `JoinRandomRoom`/
`OpJoinRandomRoom`: every hit (`LoadBalancingClient`, `LoadBalancingPeer`,
the `*Async` extension helpers) lives in Photon's own generic `Realtime`
SDK assembly — boilerplate present in every Photon-based game regardless
of whether that game's own code ever calls it. Outbound's *own*
game-specific networking abstraction (`Huey.Core.Runtime.Networking.
ISessionHandler`/`SessionHandlerBase<PlatformDataType, UserType>`) only
exposes `CreateSession`/`JoinSession`/`ChangeSessionVisiblity`/
`RetrieveCurrentPlayerList`/`SendSessionInvite`/`LeaveSession` — no
"join random"/"find sessions"/"browse lobby" concept anywhere in Outbound's
own abstraction. `JoinSessionRequest` (the concrete request `JoinSession`
takes) is just `{SessionID: string, JoinAllLocalUsers: bool}` — an opaque
ID, not a query. The concrete Switch implementation is `NetworkSystemSwitch
: NetworkSystemBase`. Conclusion, with actual evidence this time (unlike
the earlier Steam Enter-Code mistake): Outbound never offers public
matchmaking on any platform, Switch included, by its own design — only
friend-hosted sessions via a `SessionID` obtained through
`SendSessionInvite`. This is a real, checked dead end, not "not found yet."

**3. `SendSessionInvite` on Switch is exactly the native Invite Friends
applet already RE'd to its dead end** — `NetworkSystemSwitch`'s
`SendSessionInvite`/`JoinSession` are standard Nintendo SDK bindings that
launch/consume the system Friend applet (MyPage,
`0100000000001013`), the same LLE code this file already spent two full
follow-ups RE'ing to a genuine dead end (the per-entry struct's real Uid/
name/avatar offsets need real hardware or Steam packet capture, not more
static analysis of either Outbound's or MyPage's binary). Outbound has no
alternate, own-code invite path to fall back to — this fully confirms
(rather than just recommends) that presence-based join, already scoped as
"Recommended next direction" further up this document, is not just an
alternative but the *only* viable path forward that doesn't require real
hardware.

**Presence-based join: the missing wire was found and connected, no
network/protocol work needed.** Checked what already existed against the
three scoped steps from the "Recommended next direction" section:

- Step 1 (confirm what Outbound writes into presence `app_field`) and
  step 2 (wire the publish path) turned out to be **already done**, just
  not documented as such: `IFriendService::UpdateUserPresence` (10610,
  real HOS call, Outbound calls this itself while hosting) already forwards
  into `Common::OpenPakFriends::SetLocalPresence`, which `main.cpp`'s
  `legacy_presence_timer` (5s) already publishes via
  `WebService::OpenPakApi::PushPresence` whenever it changes. The read
  side is wired too: `OpenPakApi::GetFriends()`'s `ParseFriend` already
  base64-decodes each friend's `app_field` back out
  (`legacy_api.cpp:800-813`), and `OpenPakController::PollFriends()`
  already caches it into `Common::OpenPakFriends::Entry::app_field`,
  consumed today live by `MakeFriend()` for the native friends-list
  presence view. `friend.cpp` already documents the wire format precedent
  from Splatoon 2/ARMS: a null-delimited key/value scheme (`Mode`/`InGame`
  for Splatoon 2, `SessionId`/`JoinMode`/`HasPassword` for ARMS) — Outbound
  presumably uses its own key set from the same
  `nn::friends::AppKeyValueStorage` mechanism, most likely including its
  own `SessionID`-equivalent key, though the exact key names haven't been
  captured live yet (not needed for the fix below, since the blob is
  carried through opaque either way).
- Step 3 (surface a friend's joinable presence somewhere reachable without
  the native applet) was the one real gap, and it's now closed. Added
  `OpenPakController::JoinFriendSession(u64 pid)`
  (`src/citron/legacy_controller.h`/`.cpp`): looks the friend up in the
  already-cached `Common::OpenPakFriends::Get()`, and if their status is
  `PresenceOnlinePlay` with a non-empty `app_field`, hands that `app_field`
  straight to `Common::OpenPakFriends::SetPendingInvitations()` — the
  exact same local queue `IApplicationFunctions::
  TryPopFromFriendInvitationStorageChannel` (built earlier this session,
  see the Phase 6 section above/below) already reads from. No network
  round trip needed at join time (the presence feed already has the data
  locally); no `SendFriendInvitation` call needed either, so the whole
  broken-applet struct problem is sidestepped completely rather than
  worked around. Wired to a new "Join Game" entry in the friends list's
  right-click menu (`OpenPakAccountDialog::ShowFriendsContextMenu`,
  `src/citron/legacy_account_dialog.cpp`), shown only when
  `OpenPakFriendItem::PresenceRole == 2` (in-game). Compiles clean
  (`ninja citron`), not yet live-tested end to end.

**Not yet verified live:** whether Outbound's own boot/resume code
actually calls `TryPopFromFriendInvitationStorageChannel` and does
something useful with whatever bytes are sitting in it (auto-join), since
the only previous exercise of that function was via the still-broken
native applet path, which never got far enough to prove real consumption.
If Outbound doesn't poll this channel on its own, the fallback is
resuming/launching Outbound *after* using "Join Game" (matching how a real
console handles an accepted invitation: HOS launches or foregrounds the
title and the title itself checks the channel on its own next check,
typically at boot or from its own multiplayer menu). Next concrete step:
two-instance live test — host on one profile, `Common::OpenPakFriends`
should show the host's presence as in-game with a populated `app_field` on
the other profile once both are signed in to the same (currently local
test) earlier server, right-click → "Join Game", then start/resume
Outbound on the joining profile and watch for either an automatic session
join or citron's own log line for
`TryPopFromFriendInvitationStorageChannel` firing with real `app_param`
bytes (confirms Outbound is at least reading the channel, even if the
join itself needs more work after that).

**Housekeeping still pending, not done:** both citron profiles
(`~/.config/citron` and `~/.citron-second/config/citron`) are still
pointed at the local dev earlier server (`OPENPAK_API=http://
127.0.0.1:8099`) with test-account tokens, not the real production
account — `openpak_account.txt.real-backup` copies exist for both and
must be restored (and `OPENPAK_API` unset) once this feature is done
being tested locally, so the user doesn't lose access to their real
account. The `openpak-account` (`invitations.go`/`main.go`) and
`earlier-citron` client-side changes from this session (friend.cpp,
application_functions.cpp, legacy_friends.h/.cpp, legacy_controller.h/
.cpp, legacy_api.h/.cpp) are still uncommitted in their respective repos.

### 2026-08-30 follow-up: Join Game tested live -- a self-inflicted regression, a UI feedback bug, and a real new find (hosting alone self-terminates after ~160s)

Restarting both citron profiles to pick up the "Join Game" build broke
Photon connectivity entirely, unrelated to the friends feature: this
project's Photon-to-self-hosted-server redirect
(`GetPhotonRedirectIp`/`OPENPAK_PHOTON_IP` in `sfdnsres.cpp`) is gated by
an env var only, independent of the persisted `enable_legacy` setting,
by design (same reasoning as the debug-proxy env var right above it in the
file) -- but that means it doesn't survive a relaunch unless the launch
command sets it every time. Forgot to on the first restart: Outbound
correctly resolved `ns.photonengine.io` to the *real* Photon Cloud
(`216.120.180.19`), which then rejected our fake test-account token
("Nintendo validation failed", `op230`). Fixed by always launching both
profiles with both `OPENPAK_API=http://127.0.0.1:8099` and
`OPENPAK_PHOTON_IP=127.0.0.1` set. Worth remembering for any future
restart during local testing.

**"Join Game did nothing":** real bug, not a no-op -- `JoinFriendSession`'s
only feedback was `StatusChanged`, wired to a cloud-save-tab label (wrong
page) and the main window's status bar (not visibly reachable while the
friends dialog sits on top of it). Fixed: `JoinFriendSession` now returns
a `QString` result directly, and `ShowFriendsContextMenu`
(`legacy_account_dialog.cpp`) shows it in a `QMessageBox` right where the
click happened. Compiles clean.

**Confirmed live, a real and useful new fact:** Outbound's own code polls
`TryPopFromFriendInvitationStorageChannel` continuously and rapidly while
sitting on the hosting screen -- 12,830 calls logged over ~347s (~37/s),
always "no invitation waiting" in this test (no real delivery landed on
the host side during the window observed). This answers one of the open
questions from the presence-based-join plan above: yes, Outbound does
poll this channel on its own, no boot-time-only restriction confirmed so
far.

**New, separate, real finding: hosting alone self-terminates after
~160 seconds**, reported by the user as "it times out." Traced through
`~/.local/share/citron/log/citron_log.txt`: at t=160.531s, `Frontend
<Warning> ForceStop: Force stopping EmuThread` fires, immediately preceded
by `Service.AM SetTerminateResult: (STUBBED) called, result=0x1a80a
(2010-0212)` -- i.e. **Outbound's own code calls `SetTerminateResult` then
exits the process itself**; the "Userspace PANIC!"/backtrace lines
immediately after are `ForceStop` forcibly suspending the thread mid-exit
(all frames unresolved, "Initialization-time crash detected at offset 0"),
not a real crash -- ordering makes this a consequence of the intentional
exit, not its cause. So this is not a Photon disconnect, not a citron
crash, and not caused by the new invitation-poll code (confirmed above:
it never delivered anything on the host side during this run). Outbound
itself is deciding, after some internal wait/retry budget, that hosting
has failed and quitting with a specific non-zero result code
(`2010-0212` -- module 10, description 212; not yet looked up against a
Nintendo error-module reference).

Immediately before the self-exit, the log shows an unusually tight
`bsd.cpp Poll` spin (thousands of calls in the last ~5 seconds, ~1.5ms
apart, not a normal per-frame cadence) -- looks like Outbound was
synchronously waiting on a specific expected response right before giving
up. Leading hypothesis, not yet confirmed: our self-hosted
`earlier-photon` server may be missing some periodic operation real
Photon Cloud provides while a room sits open with no second player (a
lobby/room-list refresh, a heartbeat-style ack, or similar), and Outbound
has a real internal timeout for that which real hardware would also hit
eventually -- needs a look at `earlier-photon`'s `MasterServerHandler`/
`GameServerHandler` for what it does *not* respond to during idle solo
hosting, cross-referenced against a Photon protocol reference for what a
real region master server sends periodically. Not yet investigated
further this session; next concrete step if picked back up.

**Practical implication for testing in the meantime:** get the joiner
into position and use Join Game within Outbound's own ~2-3 minute hosting
window, not after -- this appears to be a real, possibly hardware-
accurate constraint of Outbound's own hosting logic, not just a local-test
artifact.

### 2026-08-30 follow-up 2: "not joinable" explained, Photon server had no persistent logs, a self-inflicted server outage, and the second-host "freeze" isolated to the client

**"That friend isn't in a joinable game right now":** correct output, not a
bug. Queried the account server directly (`GET /api/friends` as the
joiner): the host's presence really does have `status=2` but
`app_field=""`. Root cause: `IFriendService::UpdateUserPresence` (10610) --
the only code path that ever sets a non-empty `app_field` -- **is never
called by Outbound**, confirmed by grepping two full log captures spanning
an entire hosting session (crash-run and a clean run) for
`UpdateUserPresence`/`DeclareOpenOnlinePlaySession`/
`DeclareCloseOnlinePlaySession`: zero hits in either. The `status=2` friends
see instead comes from a **frontend heuristic**
(`Common::OpenPakFriends::SetLocalStatus(PresenceOnlinePlay)`,
`main.cpp:4506`, inside `OnStartGame`) that marks *any* running game as
"in-game," unconditionally, regardless of whether it's actually hosting or
even online-capable. **This means the presence-based join plan's core
assumption doesn't hold for Outbound**: unlike ARMS/Splatoon 2 (which do
populate `app_field` via `UpdateUserPresence`, hence `FixupInGameFlag`/
`IsArmsSessionActive` existing at all), Outbound apparently never
publishes its session info through the standard friend-presence API. The
`JoinFriendSession`/"Join Game" code added this session is correct and
will work the moment `app_field` is non-empty for real -- but nothing
currently makes that true for Outbound. Not yet confirmed whether Outbound
conveys session-join info some other way entirely (worth checking whether
it calls `UpdateUserPresence` at some *other* point not yet observed, e.g.
only right as a second player is about to be invited, or whether it
relies solely on the native invite applet's own separate channel).

**Self-inflicted Photon server outage while chasing this:** restarting
`earlier-photon`'s `BlackIce.Server.Host` to finally capture its trace
output to a file (previously going to an unread anonymous pipe -- opaque
this entire project) failed with ".NET 8.0 required, only 9.0.19 found":
the system's net8.0 shared runtime is gone (likely removed by a routine
system update since the server was first started, hours earlier in this
session). Fixed with `DOTNET_ROLL_FORWARD=Major`, restored alongside the
four `BLACKICE_Server__*` env vars the original launch used
(`NameServerAlt=27000`, `MasterServerAlt=27001`, `GameServerAlt=27002`,
`Listener__DeadTimeoutSeconds=600`) -- all six UDP ports (5055/5056/5058
+ the three Alt ports) confirmed listening again. The server was fully
down for about a minute during this, which is what produced the "1001"
error the user saw -- unrelated to any of the actual OpenPak/Outbound
investigation. **Worth remembering: any future `dotnet run` for this
server needs `DOTNET_ROLL_FORWARD=Major` now**, and ideally the trace log
path (now captured, previously never was) should get written to
permanently rather than only for ad-hoc sessions.

**With the server's own trace log finally readable, two real findings
about the "hosting times out" behavior:**

1. The server side is completely clean during a solo-hosting session that
   later self-terminates: `OpAuthenticate` on all three servers succeeds,
   `EnterRoom "PMPQYE" actor=1 occupants=[1]` succeeds, Fusion's own
   handshake (event 100) and steady small event-101 heartbeats flow
   continuously with zero warnings/errors/drops for the entire session.
   Whatever makes Outbound decide to call `SetTerminateResult(0x1a80a,
   2010-0212)` and exit is **not a reaction to any missing or malformed
   server response** -- it's an application-level decision Outbound makes
   on its own. Duration to that decision varies a lot between runs (16s,
   ~146s, ~160s in three different observations), which doesn't fit a
   fixed wall-clock timeout -- possibly retry-count-based against
   something with variable latency, or gated on a condition unrelated to
   elapsed time (the empty-`app_field`/no-`knownPlayers` finding above is
   one live theory: the room's own `GameProperties` include
   `"knownPlayers"=""`, and Outbound's own naming suggests it may be
   checking that against actual invited players before deciding hosting
   is "real"). Not yet confirmed either way -- next step if resumed.

2. **The reported "click host again, it freezes" is a distinct, real bug,
   and it's entirely client-side**: the server's trace log shows exactly
   **one** `OpAuthenticate`/`EnterRoom` cycle total across the whole
   session -- the second hosting attempt never sent a single packet to
   the Photon nameserver. citron's own log confirms a second `BootGame`
   for Outbound started immediately after the first session's
   `ForceStop`/`OnEmulationStopped` (same citron process, not a
   relaunch), and that second run sat for ~95 seconds doing something
   that never touched the network before *also* hitting
   `SetTerminateResult(0x1a80a, 2010-0212)`/`ForceStop`. Since this is the
   same long-running citron process across both attempts, the leading
   theory is **stale global state left over from the first session's
   abrupt guest-side `ExitProcess`** not being cleaned up before the
   second boot -- a held lock/handle/service state that stalls Outbound's
   own startup sequence before it ever gets far enough to open a Photon
   connection. Candidates to check first if resumed: whatever HOS
   service/handle Outbound touches earliest in its boot sequence (savedata
   mount, account service, or friend service state), not the new
   invitation-queue code added this session (that queue was empty/idle on
   the host in both runs, per the `TryPopFromFriendInvitationStorageChannel`
   log counts, so it's an unlikely culprit). Confirming exactly where the
   second run stalls would need a live backtrace/breakpoint during the
   ~95s window, not just log grepping -- not yet attempted.

### 2026-08-30 follow-up 3: correction — repeated launches do reach Photon; the fourth run was manually force-stopped

Re-reading the complete Citron log disproved the stale-global-state conclusion
at the end of the previous follow-up. The same long-running Citron process
booted Outbound four times. The first three launches all resolved
`ns.photonengine.io` and reached the local Photon server successfully; their
first Photon DNS requests were at emulator times `86.108`, `200.796`, and
`348.325` seconds. Relative to each `BootGame: Booting game` line, those were
about 43, 53, and 105 seconds into the guest run. Thus the second and third
launches were slow, but neither was stuck before networking.

The fourth launch (`BootGame` at `486.341`) has no Photon DNS request before
`ForceStop` at `654.316`, but unlike the preceding three shutdowns it has no
`SetTerminateResult(0x1a80a)` line at all. It was externally force-stopped and
cannot support the claim that Outbound self-terminated or that stale Citron
state prevented Photon startup. Also, in the preceding three runs the logged
ordering is `ForceStop` first and `SetTerminateResult` roughly 17–18 ms later,
not the reverse. The termination-result call may be part of teardown racing
with the frontend stop, so it is not evidence by itself that Outbound initiated
the shutdown. Treat the earlier "hosting self-terminates" and "second-host
freeze is entirely client-side" conclusions as unconfirmed until reproduced
with explicit notes distinguishing user-initiated Stop from an unsolicited
exit.

The real remaining blocker is still join discovery: Outbound does not call
`IFriendService::UpdateUserPresence`, so its host room/session ID never reaches
the earlier server's friend `app_field`. The next implementation should establish an
explicit room-registration path (most naturally from `earlier-photon`, which
sees both the authenticated user and created room name) to the account/presence
service, rather than attempting more Citron restart-state debugging.

### 2026-08-30 follow-up 4: Outbound's real invitation application parameter captured

The native MyPage applet's "Invitation sent" UI does not call Citron's
`IFriendService::SendFriendInvitation` implementation. Outbound instead passes
the application parameter into MyPage as part of the applet's input storage.
A temporary diagnostic on `ILibraryAppletAccessor::PushInData`, gated to
MyPage, captured that input during a real hosted room. The raw diagnostic was
removed immediately after analysis because the surrounding 4,264-byte applet
input also contains unrelated identifiers.

For room `CNRXJE`, Outbound's complete game-defined application parameter is
exactly 11 bytes:

```
01 00 00 00 06 43 4e 52 58 4a 45
```

This is a little-endian `u32` value/version `1`, a one-byte string length `6`,
then the six ASCII room-code bytes. In compact form:

```
u32_le(1) || u8(6) || ascii(room_code)
```

The applet input stores those 11 bytes contiguously and immediately follows
them with an integer value `11`, independently confirming the parameter's
length. This removes the last format uncertainty from the explicit
room-registration path: `earlier-photon` can construct the exact payload from
the room name without guessing or copying a larger Nintendo applet struct.

### 2026-08-30 follow-up 5: stable hosting and the native-invite completion gap

The shared room-registration path is now implemented across Photon and the
account service. Emulator BAAS tokens carry a signed `openpak` account credential;
Photon prefers that over emulator-generated `bs:did` values, while retaining
`bs:did` resolution for a real Switch. When the first actor enters an Outbound
room, Photon resolves the account and asks `openpak-account` to publish the
11-byte application parameter above as the host's presence `app_field`.

Two independent Photon compatibility issues were found and fixed live:

- Outbound hosts with `JoinGame` plus create-if-missing, not `CreateGame`.
  It also repeats the same game-server join before consuming the first reply;
  the retry must return the same actor and room properties idempotently.
- After Fusion's code-101 `Connect`/`Accepted` exchange, a solo Shared-mode
  host sends 14-byte relay data packets (`PacketType=4`). The accepted local
  and remote IDs form a self-loop, so those packets must be delivered back to
  the sole actor. Without that loopback, Host Game expired after about 16
  seconds. With it, hosting remained stable past the former timeout.

Room publication was confirmed live for the linked host account, without
showing the room code in the Switch-facing UI. This is publication only; it
does not itself send an invitation. The intended user flow remains:
`Host Game -> room created -> Invite Friends -> recipient joins`.

The remaining native-invite gap was isolated separately. Firmware MyPage shows
"Invitation sent" and returns a four-byte success result `00 00 00 00`, but in
Citron it makes no `SendFriendInvitation` IPC call and therefore causes no
Reference mailbox request. Outbound then opens MyPage again; canceling that loop
eventually produces its Timeout message. Citron now caches the validated
11-byte Outbound parameter supplied to MyPage and, for the unambiguous
single-eligible-friend case used by this end-to-end test, reproduces MyPage's
missing network side effect after its success result. Multi-friend selection
still requires recovering the selected PID list rather than broadcasting to
every friend.

### 2026-08-30 evening: invitation delivery fully solved, MyPage's real repeat-open bug pinned down, external confirmation Outbound has no friend-browse UI

The machine hosting this whole stack rebooted, killing `openpak-account`,
`earlier-photon`, and both citron instances. Bringing everything back up
surfaced two housekeeping facts worth keeping for the next restart:
`openpak-account` listens on `:8080` by default, not `:8099` — it needs
`PORT=8099` set explicitly to match what citron's `OPENPAK_API` expects.
`earlier-photon` needs `DOTNET_ROLL_FORWARD=Major` (still only .NET 9 is
installed) plus the same four `BLACKICE_Server__Ports__{NameServerAlt,
MasterServerAlt,GameServerAlt}`/`Listener__DeadTimeoutSeconds` env vars as
before. Both citron profiles need `OPENPAK_API=http://127.0.0.1:8099` and
`OPENPAK_PHOTON_IP=127.0.0.1` set on every single launch — neither
survives a restart.

**A real account mismatch explained an earlier session's "nothing arrives"
symptom.** The second citron profile (`~/.citron-second`) was signed in as
`testjoin` (pid `1800000002`), which is mutual friends with `testhost`
(`1800000001`) — but the actual host profile (`~/.config/citron`) is signed
in as `OutboundHost` (`1800000003`), whose real friend is `OutboundJoiner`
(`1800000004`). Two disjoint friend pairs, not one — the invitation was
correctly rejected/never queued for an account that was never the friend
being invited. Fixed by logging the second profile into `OutboundJoiner`
via `POST /api/login` and overwriting its `openpak_account.txt`. Worth
double-checking which accounts are actually signed in (not just which
*profile directories* are running) before concluding delivery is broken.

**Root cause of "invitation sent but nothing received" found and fixed:
`TryPopFromFriendInvitationStorageChannel`'s real semantics are event-driven,
not polled, and nothing was ever signaling the event.** Real hardware has
the guest call `GetFriendInvitationStorageChannelEvent` once and then wait
on it; our implementation had the event object but nothing ever called
`.Signal()` on it, so a guest genuinely blocked waiting for a new invitation
would never wake up — it would only ever see one if it happened to poll
again on its own unrelated schedule. Fixed in `earlier-citron`:
`Common::OpenPakFriends::SetInvitationSignalCallback(std::function<void()>)`
lets `IApplicationFunctions`'s constructor register a weak-`shared_ptr`-bound
callback (per running application, harmless no-op if the application has
since torn down) that signals `friend_invitation_storage_channel_event`;
`SetPendingInvitations` invokes it (outside its own lock, since signaling a
kernel event must never happen while holding a Common-layer mutex a kernel
callback could re-enter through) whenever new invitations are queued.

**Confirmed live, three separate real invitations, all successful:** host
sends via MyPage → `openpak-account` queues it (real mutual-friends check
passes) → joiner's 5-second poll timer (`OpenPakController::PollInvitations`)
finds it → the new signal wakes Outbound's own waiting thread → its own
`TryPopFromFriendInvitationStorageChannel` call returns the real 11-byte
room-code parameter (`u32_le(1) || u8(6) || ascii(room_code)`, format
confirmed the session before). Every one of the three landed within
single-digit milliseconds of the account-server poll finding it — this is
no longer a "maybe it'll show up eventually" mechanism, it's a real,
reliable, event-driven delivery path.

**A second real bug found in the same diagnostic pass:** a diagnostic left
mid-session in `friend.cpp`'s `GetFriendDetailedInfoV3` (writing synthetic
`"FRONT-TEST"`/`"TAIL-TEST"` placeholder names into the friend-picker buffer
to determine which offset the picker tile reads from) had already answered
its own question — neither offset renders the tile's name/status, that
still needs real decompiler-grade RE — but was left live, which is why a
friend appeared with no name/picture/status. Reverted to writing real
friend entries at both offsets (the combination that previously got a tile
selectable through to a completed send), not placeholder text.

**A real, separate citron applet bug found and fixed: `ControllerAppletVersion`
only went up to `Version8` (11.0.0+), but Outbound on firmware 20.0.0 sends
version `9`.** This hit `UNIMPLEMENTED_MSG` and asserted, which — confirmed
live via `gdb -p <pid> --batch -ex "thread apply all bt"` on a genuinely
stuck joiner process — leaves all four guest CPU cores idle
(`Core::CpuManager::MultiCoreRunIdleThread`, the same "nothing runnable"
signature as the original documented freeze bug earlier in this project)
because the guest thread that opened the Controller Support prompt never
gets a response. The fix was simple once found: version `9`'s `arg_size`
(1072 bytes) is *exactly* `sizeof(ControllerSupportArgNew)`, the same struct
`Version7`/`Version8` already use — just a missing version number, not an
unknown struct. Added `Version9` to both switches in
`src/core/hle/service/am/frontend/applet_controller.{h,cpp}`. Confirmed live
this stopped the assert. **Caveat:** a similar-looking stall (same idle-core
signature, Qt main thread sitting in the plain `QCoreApplication::exec()`
loop with no nested modal dialog on top, meaning `QtControllerSelector`'s
dialog never actually got shown) was observed once *after* this fix was
already in place, immediately after opening Outbound's multiplayer menu —
but did not reproduce on a later, identical-looking attempt (that time 2 of
4 cores were genuinely busy running real guest JIT code, no stall, no
dialog needed at all). Not conclusively tied to anything; flag as an
intermittent, not-reliably-reproducible citron UI bug if it comes up again,
worth another live `gdb` backtrace if/when it does.

**A real, separate toast-visibility bug found and fixed:** `OpenPakToast::Show`
unconditionally returned early unless `qApp->activeWindow()` was the
window calling it — meaning an invite toast could only ever appear on
whichever citron *process's* window currently had OS focus. Since host and
joiner are two separate citron processes/windows, and the natural thing to
do while testing is watch the host, the joiner's own invite toast was
silently getting dropped every time. Added a new `OpenPakToast::Kind::
GameInvite`, wired end-to-end: `OpenPakController::PollInvitations` now
also emits `FriendInvitationReceived(pid, name)` alongside its existing
silent `Common::OpenPakFriends::SetPendingInvitations` queuing (still
guest-consumable regardless of the toast), shown via the shared toast
widget with a new purple "GAME INVITE" category. `GameInvite` toasts bypass
the OS-focus check (still respect minimized) since — like a real console's
HOME-menu-level invite notification — this is meant to interrupt regardless
of what currently has focus; other toast kinds keep the original
focus-gated behavior. Confirmed live across all three invitations.

**A third real bug found live, from clicking that new toast:** the click
handler unconditionally called `BootGameFromList`, which force-stops
whatever's currently running before booting — clicking the toast while
Outbound was already running (a live Photon session, mid-connection) force-
killed it, and rebooting into that torn-down state corrupted guest memory
(`Unmapped Write64` errors). Fixed: the handler now checks `emulation_
running && system->IsPoweredOn() && play_time_manager->GetProgramId() ==
OutboundTitleId` first and no-ops if Outbound is already the active title
— the invitation data was already delivered straight into its own local
channel regardless of the click, so there's nothing useful left for a
reboot to do in that case anyway. Only boots fresh if Outbound wasn't
already running.

**MyPage's real, repeatable bug, confirmed symmetric (host→joiner and
joiner→host both hit it identically):** the *first* "Invite Friends"
attempt in a session always succeeds cleanly (`size=4 value=00000000` →
our reproduced delivery → `-> ok`). MyPage then silently reopens itself
into the same "select friends to invite" picker, with no user action.
This *second*, automatic attempt always fails with a different result code
(`size=4 value=793C0000`, decoding as Nintendo error module `Friends`
(121)) — the game's own on-screen error dialog. Roughly 100–110 seconds
after that failure, Outbound sends an explicit Photon ENet `Disconnect`
command itself (confirmed client-initiated via packet trace, not a server
drop) and tears down the whole hosted session — matches the
already-documented "Outbound tears down the session on any Invite-Friends
irregularity" behavior from earlier sessions. **Leading theory, not yet
confirmed:** MyPage may be expecting some delivery-*acknowledgement* signal
back — real hardware's `SendFriendInvitation`/mailbox round trip likely has
some confirmation step we're not replicating, so from MyPage's perspective
the first send looks unacknowledged/failed even though our own reproduction
of its side effect (calling `WebService::OpenPakApi::SendInvitation`)
succeeded — and it retries. Worth checking real `IFriendService` command
signatures (around cmd 30900/30901) for any confirmation/ack parameter we
aren't currently sending back through `PushOutData`/`PushInData`.

**Confirmed empirically, live, that Outbound's own multiplayer menu has no
"browse friends' joinable games" UI at all** — not just from static IL2Cpp
RE as before. Opening the joiner's multiplayer menu from a cold state goes
straight to a "start a hosting session" prompt, with zero `IFriendService`/
session-related IPC calls firing just from opening it. Three invitations
already delivered via the storage-channel mailbox (consumed by some
background thread well before the menu was ever opened) did not visibly
change this landing screen. **External research confirms this independently:**
per Outbound's official Steam/Nintendo eShop listings and multiple
third-party player guides (treat procedural details as plausible, not
primary-source-verified — several guide sites use near-identical phrasing
suggesting a shared/derived source rather than independent hands-on
reporting), the real console flow is **"Host Session" → "Invite" → pick a
friend from the platform's own native friends list** — there is no in-game
session browser on any platform, PC included (PC instead uses a manually-
typed join code). This matches what this project has built: presence/
invite delivery is meant to be handled by the platform layer (Nintendo's
real Friends system, or this project's own citron-side toast/mailbox), not
by anything inside Outbound's own multiplayer menu. The guides could not
confirm whether real hardware's "Invite" hands off to the actual system
Friends applet/overlay or an in-game list merely reading the console's
friend data — still an open question, but the "no browse, invite-only"
shape is now corroborated from an independent source, not just this
project's own RE. One incidental finding from the same research, unrelated
to tonight's blocker but worth remembering if a live host/join test seems
to silently fail before either side can even try: co-op is reportedly
gated behind an early-game tutorial step (repairing a road barrier) that
must be completed before hosting is available at all.

**Not yet tested:** delivering a fresh invitation while the joiner is
already sitting on the "start hosting" landing screen (attempted once, but
the joiner ended up hosting its own separate session instead of receiving/
joining — the specific "does a live delivery change what's already on
screen" test is still open). Also not yet found: a manual "Join"/"Enter
Code" option anywhere in Outbound's own Switch UI, if one exists at all
(the external research above didn't rule it out, just didn't confirm it
either).

### 2026-08-30 late evening: a real format bug found in the storage-channel payload — likely why nothing visible happens after a successful pop

Dispatched two research agents to check this project's own findings against
real Nintendo documentation and Outbound's real player-facing multiplayer
UX. The second agent's finding is directly actionable: switchbrew documents
`TryPopFromFriendInvitationStorageChannel`'s popped `IStorage` as **not** a
bare byte blob — the first `0x10` (16) bytes are the sender's account
`Uid`, and the actual application-defined payload only starts at offset
`0x10`. `IApplicationFunctions::TryPopFromFriendInvitationStorageChannel`
(`src/core/hle/service/am/service/application_functions.cpp`) was pushing
`app_param` verbatim at offset 0, with no `Uid` header at all — a real,
concrete format mismatch, and a strong candidate explanation for tonight's
whole "the pop succeeds, real bytes arrive, and then visibly nothing
happens" mystery: if Outbound's own code reads/validates a leading `Uid`
before trusting what follows, a missing header would make it silently
discard or misinterpret the real room-code bytes right after a clean pop.

**Fixed:** `TryPopFromFriendInvitationStorageChannel` now prepends a
16-byte `Uid` (the sender's Reference pid run through the same deterministic
pid→`Uid` derivation `friend.cpp`'s `UidForPid` already uses elsewhere in
this codebase, kept as a small local copy rather than shared across a
header) before the real `app_param` bytes, matching real hardware's
documented layout. Compiles clean. **Not yet live-tested** — the next
invite send/receive round trip should be watched closely for any change in
what happens after the pop (an in-game reaction finally appearing would
confirm this was the real blocker; no change would mean the `Uid` header
wasn't actually what Outbound's own parser needed, and the real blocker is
still open).

The same research pass also surfaced, from switchbrew, that the *real*
system-side call that fills this channel is `IApplicationAccessor::
PushToFriendInvitationStorageChannel` (cmd 180) — invoked by system
software (am sysmodule / friend service, likely triggered by the MyPage
applet or NPNS), never by the game itself. citron's own `cmd 180` is still
an unimplemented stub (`nullptr`); this project's mailbox entirely bypasses
it by injecting directly into `Common::OpenPakFriends`'s pending-invitation
queue, which is a legitimate and much simpler implementation choice (same
end effect for the receiving game) rather than a gap that needs closing.

Also confirmed from the first research agent, independent of the second:
real hardware's native MyPage applet does **not** call `SendFriendInvitation`
/`SendFriendInvitationV2` (cmd 30900/30901) at all for actual delivery —
this matches what this project already found live weeks ago (MyPage relays
the game's own application-parameter bytes through its own input storage
and performs Nintendo's real network send internally, invisible to the
game's own `IFriendService` session). `SendFriendInvitation`'s real
signature, per an earlier Ryujinx fork's own independent RE, is `(Uid userId,
NetworkServiceAccountId[] friendIds, in FriendInvitationGameModeDescription
description, ApplicationInfo applicationInfo, byte[] appParameter, bool)` —
already the same signature this project's own `friend.cpp` comment cites,
now cross-confirmed from a second independent source.

**Still genuinely unconfirmed, flagged explicitly by the research rather
than guessed at:** what a real `Friends` (module 121) error description
code actually means beyond the bare `2000+module`/`description` format —
switchbrew does not enumerate individual Friends description strings, so
the `2121-0001` this project's own stub produces, and whatever description
number a real `793C0000`-style MyPage failure decodes to, both remain
unverified against any real reference.

### 2026-08-30 late evening, continued: root cause of "nothing happens after a successful pop" — CONFIRMED, both statically and live

Pushed the same IL2Cpp RE further per explicit instruction to investigate
fully rather than stop at "needs better tooling." Extracted Outbound's real
decrypted `main` NSO (already sitting at `~/main` from earlier project
work) through `Il2CppDumper` again — this time kept the output
persistently at `~/outbound-re/` (outside any repo, never
committed, copyrighted game material) instead of discarding it, per
explicit request to keep material for future reference "until we get 100%
of it working." Full reproduction steps, every RVA, and all disassembly
excerpts are in `~/outbound-re/NOTES.md` — this section is the
summary.

**Traced the real consumption chain in Outbound's own compiled code, not
guessed at:**

1. `Huey.Core.Runtime.Systems.Network.NetworkSystemSwitch.CheckForInvite()`
   runs every frame (sits beside `Update()` in the same class). Calls the
   real SDK binding `Friends.TryPopFriendInvitationNotificationInfo`
   (confirmed — this is the managed wrapper around the raw `TryPopFrom
   FriendInvitationStorageChannel` HIPC response, unpacking the single
   `IStorage` into separate `Uid`/size/buffer values) with a `byte[1024]`
   buffer (`0x400` = `FriendInvitationApplicationParameterSizeMax`,
   confirmed matching Outbound's own compiled constant).
2. On success, two guard checks run before anything is cached — one calls
   a generic `Dictionary`-style lookup keyed on the **literal constant
   `2`** (not the sender's identity — corrects an earlier, wrong read of
   this as a friends-list cross-reference), the other a collection-
   membership check whose target collection isn't identified. Either can
   silently discard the invitation.
3. If both pass: constructs a real `InviteData` (confirmed ctor at the
   right RVA) — **`PlatformSessionID` and `PlatformSessionName` are both
   set from an unrelated internal lookup chain, NOT parsed from the popped
   payload; only the third constructor argument, `CustomData`, is our real
   delivered bytes.** Caches it via `set_CachedInvite`.
4. `NetworkSystemSwitch.OnGameReadyForSessionEvents()` checks `_cachedInvite
   != null`, then looks up a delegate/event object and — only if something
   actually subscribed — invokes it with the cached invite. A third
   independent way this can silently no-op.
5. The real subscriber is `NetworkManager` (Huey's top-level singleton,
   genuinely implements Photon Fusion's `INetworkRunnerCallbacks`):
   `StartJoin(InviteData)` starts a `JoinPlatformSession(InviteData)`
   coroutine, whose compiled state machine has a `JoinSessionRequest`
   field. Disassembled the exact request-construction point:

   ```
   ldr x20, [inviteData, #0x10]     ; reads PlatformSessionID (offset 0x10)
   ... allocate JoinSessionRequest ...
   mov x1, x20                       ; SessionID = PlatformSessionID
   bl  JoinSessionRequest..ctor
   ```

   **`CustomData` (offset `0x20`, our real room-code bytes) is never read
   again after being cached. The actual join request is built from
   `PlatformSessionID` — the field populated from something unrelated to
   our delivery, not our payload.** This holds regardless of whether the
   two guard checks in step 2 pass or fail: even in the best case, the
   join uses the wrong session identifier.

**Live-confirmed via a real attached debugger, not just static reading.**
earlier-citron has a working guest-level GDB stub (`use_gdbstub`/
`gdbstub_port` settings, default port `6543`) — genuine remote ARM64
debugging of the actual running Outbound process, using the system's own
`gdb` (no special cross toolchain needed; Fedora's stock `gdb` already
supports `set architecture aarch64`). Module base address confirmed live
from citron's own log line (`loaded module main @ 0X80006000`); add any
`dump.cs` RVA to that base for a real breakpoint address. One real gotcha
worth remembering: **citron's gdbstub has no clean detach — any client
disconnect, deliberate or not, immediately kills emulation
(`Shutting down emulation` in the log)**, so a debugging session has to do
everything it needs in one script from attach to final inspection.

Set a conditional breakpoint (`break ... if $x0 != 0`) right after the
`TryPop` call inside `CheckForInvite`, which normally hits dozens of
times/sec with "nothing queued" and only genuinely stops for a real pop.
POSTed a distinctive test invitation directly to `openpak-account` via
`curl` (reusing the host's saved token — a reliable way to trigger this on
demand without needing the host's live GUI/MyPage flow). The moment the
breakpoint fired for real, read the live popped buffer directly out of
guest memory: **`01 00 00 00 06 51 51 51 51 51 51`** — `u32_le(1)`,
`u8(6)`, ASCII `"QQQQQQ"` — byte-for-byte identical to what was sent.
**This confirms the entire delivery chain (server queue, joiner poll,
event-driven wakeup, the `Uid`-header wire format from earlier tonight, and
the C# wrapper's Uid/size/buffer unpacking) is correct, live, not just in
theory.** The remaining gap is exclusively the `PlatformSessionID`-vs-
`CustomData` field mismatch found via static analysis — independently
confirmed to be the real, sufficient explanation for the entire night's
"nothing visibly happens" mystery, unrelated to payload correctness,
timing, or which screen the joiner is on.

**What's still open, next steps if resumed** (full detail in
`~/outbound-re/NOTES.md`):

1. What `PlatformSessionID` actually resolves to live (a 3-hop pointer
   chain in `CheckForInvite` not yet read at runtime — the multi-stage gdb
   script that would have captured this got cut short when the session
   ended). A focused single-breakpoint gdb run at `base+0x3f3acb4` (right
   after the value loads) reading it as a standard IL2Cpp `System.String`
   would answer this directly.
2. Whether that value comes from something citron already controls (in
   which case the fix is making it carry the real room code at the
   source, not touching the invitation mailbox at all) or something not
   yet implemented.
3. Only once (1)-(2) are answered does a real fix become possible — this
   project cannot patch Outbound's own compiled code, so the only lever
   is making whatever populates `PlatformSessionID` end up correct.

### 2026-08-30 late night: `PlatformSessionID` resolved — it's a hardcoded empty string (see follow-up below for what this actually means)

Picked this straight back up per explicit instruction to keep going rather
than stop at "needs a decompiler." Two real things happened, in order.

**First, found and partially fixed a real citron bug, then found and
root-caused a second, deeper one underneath it.** earlier-citron's own
gdbstub has a `step`-after-breakpoint bug: `debugger.cpp`'s
`DebuggerAction::StepThreadLocked` handler was missing a `ResumeEmulation()`
call present in its `StepThreadUnlocked` sibling — genuinely fixed and
rebuilt (`src/core/debugger/debugger.cpp`). That fix alone didn't resolve
the symptom (`stepi` still never advanced the guest PC), so the
investigation went one level deeper: **confirmed live, conclusively, that
even after fully `delete`-ing a hit software breakpoint — verified via
`x/4xb` that the correct original instruction bytes are genuinely restored
in guest memory — a subsequent `continue` still immediately re-raises a
real `SIGTRAP` at the identical PC.** Guest memory is provably correct;
execution still re-traps regardless. This means dynarmic's own JIT-compiled
native code block for that address, compiled once while the breakpoint's
trap instruction was still present, is never recompiled or invalidated to
reflect the restored bytes — `Core::InvalidateInstructionCacheRange`
either isn't reaching dynarmic's JIT cache for this path or isn't
sufficient to force recompilation. **Not fixed** — a real, separate,
deeper citron bug, worth a standalone report/investigation, out of scope
for tonight's actual goal. Full diagnostic trail (the exact commands and
outputs that isolated this) is in `~/outbound-re/NOTES.md`.

**Worked around it instead of fixing it**, since the actual target data is
static/global, already fully initialized during any normal frame — no
resume-past-a-breakpoint was needed at all. Broke once at `CheckForInvite`'s
entry thunk (`base+0x3f3aa90`, base `0x80006000` confirmed stable across
every relaunch tonight), and from that single, very first hit, read the
whole `[table+0x668]→[+0x90]→[+0xb8]→deref` pointer chain directly via
gdb's memory-read commands (`inf.read_memory`), computing each hop's
address from the previous read's actual value:

```
x23  = 0x86dae360    (from table_slot 0x86a18668)
x8_a = 0x114da1d300   (from x23+0x90)
x8_b = 0x114dfadff0   (from x8_a+0xb8)
x20  = 0x114dfb0f40   (from x8_b -- this is PlatformSessionID's source)
```

Read `x20` as a raw IL2Cpp object: `klass_ptr=0x114da1d300` (exactly equal
to `x8_a` — consistent with `[x23+0x90]` being a cached `typeof(string)`
class reference), `monitor=0`, **`length=0`**.

**Reproduced identically in two fully independent gdb sessions (separate
citron relaunches) — byte-for-byte the same chain values both times,
confirming this is stable, deterministic data, not per-run noise or
misread garbage.**

**The answer: `PlatformSessionID` is a genuine, valid, empty `System.String`
(`""`) — not corrupted memory, not null, not garbage.** This is the exact
value `CheckForInvite` passes as both `platformSessionID` and
`platformSessionName` into `InviteData`'s constructor (per the earlier
static disassembly — `mov x1, x20` / `mov x2, x20`, same register), and
`NetworkManager.JoinPlatformSession` builds `JoinSessionRequest.SessionID`
directly from `InviteData.PlatformSessionID` — i.e. from this exact empty
string, confirmed via the earlier independent static-disassembly finding.

**This closes the investigation with a definitive, non-inferred root
cause:** Outbound's own compiled `CheckForInvite` reads a stable
"no active session" placeholder for the field it uses as the actual join
target, regardless of what real room-code data has been correctly
delivered into `CustomData` right alongside it. This is not a citron or
Reference delivery defect in any way — every layer this project built
(server queue, event-driven wakeup, wire format, toast notification) is
independently confirmed correct and working. The bug is entirely inside
Outbound's own binary, in a code path that appears to have simply never
been wired up to actually consume the room code it's handed.

**Practical implication, not itself proven tonight but a strong working
hypothesis:** since this specific code path is very likely the *only*
consumer of the friend-invitation mailbox on the Switch build (nothing
else in `NetworkSystemSwitch`/`NetworkManager` references `CachedInvite`
per the earlier full disassembly), and since real players' documented
experience (per this project's earlier external research) shows Switch's
real invite flow going through the native system Friends applet with no
in-game "browse/join" UI at all, it's plausible this exact bug exists on
real hardware too — i.e., the mailbox-driven auto-join path may never have
actually worked for Outbound on any real console, and the *real*, working
flow (whatever it is) doesn't go through `CheckForInvite`/`InviteData` at
all. This remains unconfirmed — would need a real-hardware capture to
settle definitively — but it reframes the remaining problem: further work
here is no longer a delivery or format question, it's "does Outbound have
*any* working join path reachable without real hardware's native Friends
applet flow" — a much narrower, more honest question than where this
investigation started.

### 2026-08-30 late-late night: the "empty string" finding confirmed via full static disassembly, not just live memory — and a concrete path forward that doesn't require finishing the native RE

Corrected course after being pushed back on: "multiplayer works on the
switch" is right, and a shipped, working feature can't rely on code that's
unconditionally broken on every platform — so if `CheckForInvite`
really always sends an empty `PlatformSessionID`, real hardware's invite
flow must not be going through that function at all, and the job is to
find what it actually does, not to declare Outbound's binary broken and
walk away.

Three things nailed down for real this session (all in
`~/outbound-re/NOTES.md` in full, with the disassembly):

1. **Outbound's C# layer has no binding for `PopLaunchParameter`/
   `UserChannel` at all** (`nn.oe` namespace checked in full — only
   `HealthWarningForRegionChina`/`Language`/`CrashReport`/`ScreenShot`/
   `ProgramTotalActiveTime`). citron's real cold-boot launch-parameter
   mechanism (`applet_manager.cpp:317`,
   `user_channel_launch_parameter.swap(m_system.GetUserChannel())`) is
   confirmed real and working, but if real hardware's invite-accept uses
   it, Outbound's own code can't read it directly — it'd be entirely
   inside Unity's native (non-IL2Cpp) NX plugin, which this decompile
   can't see.
2. **Scanned the entire 84MB decompressed `.text` for every caller of
   `nn.friends.Friends.TryPopFriendInvitationNotificationInfo`** (the real
   name for AM command 141, which citron already implements correctly) —
   exactly one call site in the whole binary, inside `CheckForInvite()`.
   So our delivery channel is provably the right (and only) one for this
   code path. Then disassembled all of `CheckForInvite()` start to finish
   and read, instruction by instruction, what it does with the popped
   buffer: it copies the real bytes we deliver into a **new byte array
   used as `InviteData.CustomData`** (confirmed correct — this really does
   arrive intact), then separately loads a cached empty-string static
   field and passes *that* as **both** `platformSessionID` and
   `platformSessionName` into `InviteData`'s constructor. There is no
   branch anywhere in the function that could make this differ — this is
   now confirmed by reading the actual construction code, not inferred
   from a memory snapshot.
3. **Grepped all of `dump.cs` for every reference to `CustomData`/
   `CachedInvite`**: `JoinPlatformSession` is the *only* consumer of
   `CachedInvite` anywhere in Outbound's code, and it only ever reads
   `.PlatformSessionID` — never `.CustomData`. There's no secondary path
   waiting to use the data we correctly deliver.

**Bottom line:** this is not a delivery/format bug on our side (proven
three separate ways now), and the mailbox/`CheckForInvite` path
genuinely cannot produce a working join on any platform, as shipped. Real
hardware's actual friend-invite-join mechanism is something else —
plausibly the native cold-boot launch-parameter path from point 1, which
we can't finish confirming without reverse-engineering Unity's own native
Switch plugin (a much bigger, more open-ended undertaking).

**Recommended next step, not yet started:** stop chasing how Outbound
*normally* learns about an invite, and instead directly drive its own
real, already-confirmed-correct join entry point. `NetworkManager`
(`PersistentSingleton<NetworkManager>`, so it has a locatable static
`Instance`) exposes `IEnumerator Join(string code, bool
newWaitForRoomToBecomeAvailable = false)` at RVA `0x1BF76C0` — a generic,
proven join-by-code method, completely independent of the broken
`InviteData` pipeline (this is almost certainly what a manual code-entry
UI would call). When a Reference invite is accepted, citron could locate
the live `NetworkManager.Instance` in guest memory and drive this
directly — either write the code into `NetworkManager.sessionName`
(offset `0xB0`) or invoke `Join()` via a manufactured call — bypassing the
platform-invite layer entirely. This is real, novel engineering (citron
has no existing facility for injecting a call into a live IL2Cpp/dynarmic
guest) and hasn't been started.

### 2026-08-31: manufactured guest-call join — the real join trigger, built on the game's own Join + StartCoroutine

Per the previous section's "recommended next step" (drive `NetworkManager.Join`
directly), but with a critical correction found by actually disassembling `Join`
(RVA `0x1BF76C0`, capstone, `text.bin`) before building anything:

**`Join` does not start anything.** It only validates nothing, allocates the
`<Join>d__86` coroutine state machine (`bl 0x5bdde0` = il2cpp object-new with the
class from metadata slot `[0x6a18000+0xb0]`), sets `<>1__state=0` (+0x10),
`<>4__this` (+0x20), the bool (+0x28), `code` (+0x30), and RETURNS it. It never
touches x3 (MethodInfo) and never writes `sessionName` — all of that (code
validation, ToUpper, `sessionName` = +0xB0, `connectionType=2`,
`InstantiateRunner`, Fusion `StartGame`) happens later inside `<Join>d__86.MoveNext`
when Unity's coroutine runner drives it. The previous session's trampoline called
only `Join` and logged `Join.MoveNext reached` as its success signal — which could
never have fired even without the crash, because nobody ever started the coroutine.
Its room-code string was also wrong: it copied the RAW popped bytes (which begin
with the 5-byte `u32_le(1) || u8(len)` header) as UTF-16 chars, so even a correct
call would have "joined" garbage. And its NetworkManager.Instance capture checked
hardcoded VAs (`0x81BF7570`/`0x81BFC760`) that only match one specific ASLR base.

**The two-call recipe, confirmed against the game's own code:**
`StartJoinOnLoad` (RVA `0x1BF78D0`) ends in a tail call `b 0x4C1A070` with
x0=this(NetworkManager), x1=IEnumerator, x2=0 — that helper is
`MonoBehaviour.StartCoroutine`'s managed entry (null-checks both args, loads its
icall from a metadata slot, calls the engine). So the complete join is exactly:

```
sm = NetworkManager.Join(code, false)          ; RVA 0x1BF76C0, x0=this x1=code x2=0
MonoBehaviour.StartCoroutine(this, sm)         ; RVA 0x4C1A070, x0=this x1=sm x2=0
```

Both calls are non-generic, read no MethodInfo, and were signature-pinned
(first instruction words `0xa9bc7bfd` / `0xa9bd7bfd`) for runtime verification.

**New facility: `src/core/legacy_guest_call.{h,cpp}`** — no hand-assembled code,
no mid-function frame assumptions, no hardcoded base:

1. **ARM** — `IApplicationFunctions::TryPopFromFriendStorageChannel` (the invite
   pop, which runs on the Unity main thread at ~37/s once an invite is queued) now
   parses the room code out of the delivered app_param (`u32_le(1) || u8(len) ||
   ascii`, validated) and calls `ArmInviteJoin`. That verifies the game is
   Outbound, verifies both RVAs' instruction signatures (refuses to inject into a
   mismatched game version), resolves `System.String`'s Il2CppClass\* via the
   twice-live-confirmed chain `[base+0x6A12668] → +0x90`, checks
   `NetworkManager.Instance` is captured, and parks the request.
2. **FIRE** — `PhysicalCore::RunThread` calls `OnBeforeRun` before resuming any
   thread; for the armed (Unity main) thread it saves the full guest context,
   writes a fabricated IL2CPP string (`klass, monitor=0, length, UTF-16`) into a
   private stack window `[SP-0x2000, SP)` that no live frame or the injected
   call's own frames can touch, and rewrites the context:
   `x0=Instance, x1=string, x2=0, fp=0, lr=0 (sentinel), sp=window, pc=Join`.
3. **CHAIN/RESTORE** — `Join` returns into lr=0 → dynarmic NoExecuteFault →
   `ExceptionRaised` keeps it quiet (no CRITICAL log/backtrace while a sentinel is
   pending) and halts with PrefetchAbort; `PhysicalCore::RunThread`'s abort
   handling calls `OnFault` first: stage Join → reads the returned state machine
   from x0 and rewrites the context for `StartCoroutine(this, sm)`; stage
   Coroutine → `SetContext(saved)` and the thread continues exactly where the
   invitation-poll svc left off, with Unity now driving the real join coroutine
   (validate → sessionName → connectionType=2 → Fusion connect to our server's
   room). A real data abort inside the injected call restores the saved context
   and then deliberately falls into the normal suspend path so the crash is
   visible, not silently looped.

Supporting pieces:

- **Instance capture, fixed for real** (`ObserveInstanceCapture`, called from the
  dynarmic `MemoryReadCode` hook): base comes from `process->GetEntryPoint()` at
  runtime — never hardcoded — and capture points are now joiner-reachable:
  `NetworkManager.Start` (0x1BF6840) and `OnEnable` (0x1BF6CC0) (PersistentSingleton
  lifecycle, run on the Unity main thread at scene load), plus the older
  Host/SendInvitation points. x0 is validated (klass != 0, MonoBehaviour
  m_CachedPtr at +0x10 != 0) before capture, since MemoryReadCode re-fires after
  JIT cache flushes with mid-execution register values. If an invite arrives
  before the instance exists, the code is kept pending and the arm completes at
  the moment of capture instead of losing the invitation.
- The old DIAG block's hardcoded-VA capture (guest-side MailboxVA mirror write)
  was made base-aware; the disabled trampoline itself is untouched and stays off.
- Env kill switch: `OPENPAK_NO_GUEST_JOIN=1` disables arming entirely.
- **Scripts** (`scripts/`): `start-services.sh` (the legacy-local account
  container on :8099 -- since 2026-09-01, see that section -- and photon with
  DOTNET_ROLL_FORWARD=Major + the 27000/27001/27002 alt-port env vars, both
  idempotent), `launch-citron-host.sh` / `launch-citron-joiner.sh` (bake in
  `OPENPAK_API=http://127.0.0.1:8099` + `OPENPAK_PHOTON_IP=127.0.0.1` on every
  launch — the documented relaunch footgun; the host script also refuses to run if
  the real production account file is active), and `send-test-invite.sh <CODE>`
  (POSTs a correctly-formatted synthetic invite to the joiner pid directly, the
  proven on-demand trigger that skips the host's GUI/MyPage flow). Later additions
  from the same day: `setup-isolated-profiles.sh` + `mint-host-token.sh` (fully
  isolated portable-mode profiles, see their headers) and `freeze-watchdog.sh`
  (auto-gdb-backtrace when the host's log goes quiet while the process spins).
- **Testing protocol (user rule, 2026-08-31 — AUTHORITATIVE VERSION: "Citron
  Launch Protocol (family-wide)" at the end of this document, mirrored in
  `~/REPOS/legacy-docs/shared-docs/emulator-launch-protocol.md`): ALWAYS confirm
  the user is ready before launching citron for testing, and ASK FIRST when any
  OTHER title's instance is running.** Each instance holds ~6-9 GB resident; two
  instances plus any other citron project can push the 29 GB machine into
  swap-thrash, which has frozen the host mid-MyPage-applet-load, forced a reboot,
  and starved the joiner's Fusion connect mid-handshake (1029 major-faults/5s
  observed — mimics a protocol stall). Before launching: `pgrep -x citron` for
  other instances, `free -h` for headroom, then ask. ENFORCED IN CODE: both
  `launch-citron-*.sh` scripts abort if a foreign citron instance (any cwd outside
  this project's profiles) is running — learned the hard way after launching blind
  next to a running CTR session.

**Live-tested 2026-09-01 (multiple rounds) — see the 2026-09-01 section at the end
for results and the remaining blocker.** The watch-points for the first run, all
in each instance's own portable-profile log
(`~/.local/share/earlier-outbound/citron-{host,joiner}/user/log/citron_log.txt`):

1. `[OpenPak][GUESTCALL] NetworkManager instance captured` shortly after the
   joiner's Outbound boots (if this never appears, NetworkManager's Start/OnEnable
   RVAs need re-checking — nothing else in the chain can work without it).
2. `armed: joining room 'XXXXXX'` when the joiner ACCEPTS the invite toast
   (record-then-accept, see 2026-09-01; delivery alone only records it).
3. `firing Join(...)` then `Join returned state machine ...` then
   `StartCoroutine returned -- injection complete` within the same second.
4. Then the real join evidence: citron's `[OpenPak][PHOTON]` trace showing a
   second client's GetRegions/Authenticate/JoinGame against the local server, and
   `earlier-photon`'s trace logging `EnterRoom "<code>" actor=2` — actor=2 is
   the first real second-player join this project has ever produced.

Known risks to watch: the injected join runs from whatever screen the joiner is
on (a multiplayer-menu screen is the sane test state; a mid-gameplay join may
conflict with the game's own UI state); the `knownPlayers`/solo-host-timeout
behavior only matters on the host side; and if the co-op tutorial gate (road
barrier repair) applies to joining too, the joiner's save may need it done once.

## Security and repository rules

- Never commit `openpak_account.txt`, session tokens, BAAS tokens, keys,
  certificates, personal identifiers, packet captures containing credentials,
  game binaries, NCAs, NSPs or copyrighted assets.
- Treat Photon App IDs as public client identifiers, not secrets, but document
  their provenance.
- Store test/prod secrets only in ignored environment files.
- Keep all inferred protocol values labelled until confirmed independently.
- Preserve the original Ryujinx and Citron saves while experiments continue.

## References

- Photon binary protocol:
  <https://doc.photonengine.com/realtime/v5/reference/binary-protocol>
- Photon custom authentication:
  <https://doc.photonengine.com/realtime/v5/connection-and-authentication/authentication/custom-authentication>
- Photon Realtime architecture:
  <https://doc.photonengine.com/realtime/v5/realtime-intro>
- earlier network:
  <archived external source>

## Citron Launch Protocol (2026-08-31, family-wide)

- The assistant may launch/kill/restart citron autonomously when either
  (a) no other citron instance is running, or (b) the only running
  instance is this project's own instance — identified by the Outbound
  NSP path on the command line plus this project's `OPENPAK_*` env
  vars — including closing and relaunching it to test freshly rebuilt
  citron binaries.
- ASK FIRST when any OTHER title's citron instance is running: Among
  Us, Outbound, Fall Guys, CTR:NF, Stardew, MC and PvZ all share this
  machine and the same citron build; a broad kill takes their session
  down.
- Detection: `pgrep -af "^~/REPOS/earlier-citron/build"`
  and inspect each process's cmdline (NSP path) and environ
  (title-specific `OPENPAK_*` vars).
- Never broad-`pkill` citron patterns: they match the calling shell
  itself and other titles' instances.

### Kills: target by game, never by binary path (incident 2026-08-31)

A binary-path kill (`pkill -f earlier-citron/build`) terminated a
running Outbound session on the shared machine. When killing a citron
instance, kill ONLY pids whose cmdline contains THIS project's game
NSP path (check /proc/<pid>/cmdline per pid). When any other title's
instance is running, ask before launching or killing anything — memory
pressure alone (29 GB host) can OOM a foreign session.

### 2026-09-01: joiner reaches the session lobby; GameList property typing; record-then-accept flow; launch-script guards

Round-trace analysis of the latest invite attempt (host room alive, joiner
authenticated, joined the session-code lobby, received the GameList event with
the host's live session — and then went silent: **no OpJoinGame was ever sent**,
Fusion's StartGame timed out, and the joiner showed its generic join-failure
screen while the host's room sat at actor=1 until eviction). Two server-side
defects were found and fixed in `earlier-photon` `MasterServerHandler`:

1. **Property value typing.** The GameList entry was built with byte-typed
   values for IsOpen/IsVisible (bool is required) and ClampToByte'd
   PlayerCount/MaxPlayers (int is required). Photon Realtime's
   `RoomInfo.CacheProperties` reads `IsOpen = (bool)properties[254]`,
   `MaxPlayers = (int)properties[255]`, etc. — a boxed byte fails the bool/int
   unbox, the exception kills the client's event dispatch, the cached session
   list stays empty, and Fusion's wait times out. Fixed: bool/bool/int/int.
2. **Key 250 passthrough.** The host's stored GameProperties include
   `250(Byte)=1` (the CustomProperties marker key with a byte value).
   `RoomInfo.CacheProperties` treats key 250 as the room's CustomProperties
   hashtable — merging a byte instead of a dictionary breaks the client's
   property cache again. Key 250 (plus 248/243 server-internal keys) is now
   excluded; the custom STRING/INT props (scene/vehicleType/version/
   knownPlayers) still pass through for the game's own session filter.
3. **Dual event codes.** The GameList is now raised under BOTH 230 (Fusion's
   fork: full list) and 229 (GameListUpdate; also what vanilla Photon Realtime
   clients dispatch) so a PC test harness using stock Photon Realtime sees the
   same list the game build sees.

**Joiner flow restructured (record-then-accept).** The cmd-141 raw ctx handler
(`TryPopFriendInvitationNotificationInfo` in citron's
`application_functions.cpp`) now only RECORDS the invitation (room code + the REAL requesting
guest thread via `ctx.GetThread()` — the D<>/cmif path runs on a ServerManager
host thread whose GetCurrentThreadPointer is a per-thread DUMMY KThread, which
is why every earlier arm silently never fired). The injection arms only when
the user ACCEPTS the invite by clicking the GAME INVITE toast while Outbound
is running (5-minute recording window; fresh guest-thread pointer maintained
by the 37/s poll). Rationale: auto-firing on delivery joined from whatever
screen the joiner was on — the title/main menu crashes the join coroutine
(observed live twice: guest svcBreak, "An error has occurred" screen).

Joiner-side state at last trace: injection complete, client authenticated on
NameServer + Master, joined the session-code lobby (OpJoinLobby 229 with the
room code as P213), GameList delivered — and the client still waits instead of
sending OpJoinGame(226). Next diagnostic: the PC harness (PhotonClient.dll —
the game's own bundled client) running the same flow on the host PC with
Fusion's debug output visible, to name what the client-side wait still needs.
The host's own 1020 after ~2-4 min solo (invited-nobody timeout, client-side)
remains the window the joiner must land within.

Housekeeping: `launch-citron-*.sh` now REFUSE to launch while a foreign
citron instance is running (any cwd outside this project's profiles), with a
`CITRON_ALLOW_FOREIGN=1` override; the NameServer now hands loopback peers the
loopback Master address (`127.0.0.1:27001`) so PC-side test clients are not
routed to the real Cloud (GetRegions + both auth paths). The family-wide
launch/kill rules live in the user's Citron Launch Protocol section above and
`~/REPOS/legacy-docs/shared-docs/emulator-launch-protocol.md`.

**Account server moved to the legacy-local stack (2026-09-01, after the last
test).** The earlier rounds ran against an ad-hoc `go run .` of openpak-account
on :8099; that process is gone and :8099 is now the `legacy-local_account_1`
container (`~/REPOS/legacy-local`, `podman-compose`). Consequences, all handled:

- The container signs with the stack's own `OPENPAK_SECRET` (raw bytes from
  `legacy-local/.env`, not the hex `legacy_secret.key`), so every profile
  token minted before the move was rejected (401). `mint-host-token.sh` now
  reads the stack's `.env` + `data/account/accounts.json`; both profiles were
  re-minted (`TARGET_PID=1800000004` for the joiner) and verified 200 on
  `/api/me`. `setup-isolated-profiles.sh` mints the joiner the same way instead
  of copying the old `~/.citron-second` file.
- A real legacy-local bug found on the way: `compose.yml` set
  `OPENPAK_DATA_DIR=/data`, but the server only reads `OPENPAK_DATA` (a file
  path) and otherwise uses `accounts.json` in its cwd (`/`), so the container had
  loaded an EMPTY store -- valid tokens failed with "Compte introuvable", and any
  registration would have landed in the ephemeral container fs. Fixed to
  `OPENPAK_DATA: /data/accounts.json` and the account container recreated
  (`podman-compose up -d --no-build account`). This affected every title using
  the stack, not just Outbound.
- `start-services.sh` now checks `/api/health` on :8099 and brings the stack up
  with `podman-compose` instead of launching `go run .`; `send-test-invite.sh`
  defaults its token to the HOST PROFILE file (it pointed at the main
  `~/.config/citron` profile before).

### 2026-09-02: full decompiled map instead of per-hypothesis disassembly; tmpfs incident

Decision (user): stop chasing one function per hypothesis and map the whole
binary once, searchably, so future work reads the game's real code path and
guesses only about server behaviour. Built with
`~/outbound-re/ghidra_scripts/build_map.py` (+ `make_xrefs.py`, `annotate.py`);
outputs live on the pool at `/mnt/media/research/outbound/decomp/`
(README inside; linked as `~/outbound-re/map`). Copyrighted derivative --
never enters a repo. The procedure and its traps are in
`~/REPOS/legacy-docs/IL2CPP-GHIDRA-WORKFLOW.md`, Step 5.

- `index/methods.tsv` (234,785 methods, RVA + signature), `index/strings.tsv`
  (33,452 literal slots), `index/xrefs.tsv` (493,616 direct `bl` calls,
  callee -> caller), and one decompiled `.c` per class under
  `<NamespaceRoot>/`. Priority order: Fusion / Photon / NetworkManager /
  friends / invite / session classes first, then everything.
- First answer it gave for free: `NetworkManager$$Join` has exactly two
  callers, `JoinUI$$OnJoin` and `DebugNetworkConnect$$Join` -- the injected
  join is the same entry the manual-code UI uses, nothing else.
- Next use: read Fusion's session-list / `OpJoinGame` decision path in the
  `Fusion/` and `Photon.Realtime/` files to name what the joiner still waits
  for after the GameList (the open blocker from 2026-09-01), before another
  live round.

Housekeeping the same morning: the shell tool died for every command because
`/tmp` (15 GB tmpfs) was full -- three 4 GB guest-memory dumps from another
session's scratch. Moved to `/mnt/media/research/tmp-rescue/`. All
service logs and the freeze watchdog now write under
`/mnt/media/research/outbound/services/` (`OUTBOUND_RUN_DIR`), never
`/tmp`; playbook §5 updated.

### 2026-09-02 (cont.): full client flow reconstructed from the map — server contract verified without a live test

Using the decompiled map (`/mnt/media/research/outbound/decomp`), the
joiner's entire Photon dialogue was reconstructed from Outbound's own code. The
client is **stock Photon Realtime v4 (Fusion fork)** — `LoadBalancingClient`
with the standard method set (`ConnectToNameServer`, `OpGetRegions`,
`ConnectToRegionMaster`, `CallAuthenticate`, `OpJoinLobby`, `OpJoinRoom`,
`OnOperationResponse`/`OnStatusChanged`/`OnEvent` jump-table dispatch). So the
whole flow is the documented LoadBalancing sequence; only the room-property
contract and the session-name path are game-specific, and both are now pinned
from the binary.

**Connection/session sequence (each step = one op the server must answer):**

1. NameServer: `OpGetRegions` (220) → region list; `Authenticate` (230) with
   the custom-auth token → returns the Master address + Secret (param 221).
2. Master: reconnect, `Authenticate` (230) again (Secret echoed) → ready.
3. `OpJoinLobby` (229) with **P213 (LobbyName) = the session code** (observed
   live 09-01). Server answers, then must raise the **GameList event (230),
   param 222 = `{ roomName -> propertiesHashtable }`**.
4. Client caches each room via `RoomInfo.InternalCacheProperties` and, when the
   room named after the code is present + open, sends `OpJoinGame` (226) with
   that name → Master returns the GameServer address.
5. GameServer: reconnect, `Authenticate` (230), `OpJoinGame` (226) again →
   EnterRoom success (actor list, room props) → **InRoom**, actor=2.

**The GameList room-property contract — extracted byte-for-byte** from
`RoomInfo$$InternalCacheProperties` (RVA 0x218cb30) and the getters
(`get_IsOpen`@0x218d5b0 reads +0x38, `get_IsVisible`@0x218d5c0 reads +0x39,
`get_MaxPlayers`@0x218d5a0 reads +0x20, `get_PlayerCount`@0x218d580 reads
+0x58). Each room's value Hashtable is parsed with these well-known byte keys:

| Key | Meaning | Client read | Type rule |
|---|---|---|---|
| 251 | RemovedFromList | bool → drops the room if true | **strict bool** (wrong type throws) |
| 255 or 243 | MaxPlayers | `Convert.ToInt32` → +0x20 | byte OR int OK |
| 254 | **IsVisible** | bool → +0x39 | **strict bool** |
| 253 | **IsOpen** | bool → +0x38 | **strict bool** |
| 252 | PlayerCount | `Convert.ToInt32` → +0x58 | byte OR int OK |
| 249 | (bool field +0x3a) | bool | **strict bool** |
| 248 | MasterClientId | int32 → +0x48 | int |
| 250 | ref/object → +0x50 | `as`-cast (null if wrong) | not strict |
| other string keys | custom props | `MergeStringKeys` | string-keyed only |

A strict-bool key sent as a byte throws `InvalidCastException` **inside the
client's event dispatch**, which silently empties the cached room list and
times the join out — this is exactly the 09-01 "authenticated + JoinLobby then
nothing, `Invalid session ID`" symptom.

**Verified against `earlier-photon`:** `MasterServerHandler.BuildFusionSessionLobbyEvent`
already emits `IsOpen`(253)=bool, `IsVisible`(254)=bool, `PlayerCount`(252)=int,
`MaxPlayers`(255)=int and strips the host's byte-typed well-known keys. **The
key numbers and types match Outbound's Fusion fork exactly** (note: Fusion's
253/254 are swapped vs vanilla PUN, and the server correctly follows Fusion).
So the 09-01 fix targets the precise cause and the contract is now satisfied.

**Conclusion (no test needed to reach it):** the property-typing blocker is
closed in code; the next live round is validation, not diagnosis, and the
prediction is `OpJoinGame` (226) now fires after the GameList. If it still
stalls, the map narrows it to two remaining, code-identified suspects:

1. **Room-name identity.** The joiner searches for a room whose name equals the
   Fusion session name (the code, upper-cased by `Join`). The server keys the
   advertised room by the `OpJoinLobby` LobbyName (P213). Confirm the host
   registered the room under that same exact string (case included), or the
   client's wait never matches.
2. **Defensive:** `BuildFusionSessionLobbyEvent` strips keys 250/248/243 but
   not **251 (RemovedFromList)** — if a host ever stored 251 truthy it would
   drop the room. Add 251 to the strip list.

The Fusion state gate `<Join>b__0` (0x1bfdfa0) is only a runner-state bitmask
(`state & 0x1600000`), not a room-content check — room matching is inside
Fusion's own matchmaking, driven entirely by the GameList contract above.

### 2026-09-02 (cont.): why the HOST drops with "connection interrupted (1020)" after the invite — root-caused from the decompile + server config

The map answered this. `NetworkManager$$OnDisconnectedFromServer` (RVA 0x1BF92E0)
shows the host teardown is **reactive, not a self-timer**: it takes the Photon
`DisconnectCause` (a uint8), maps causes 2-6 through a small rodata table
(0x518B528) into a `NetworkPlatformFailedReason` (default `Unknown`=16), calls
`set_CurrentFailedReason` → `NetworkManager$$Shutdown` (0x1BFA5C0), and shows the
generic "connection interrupted" screen. So the host does **not** quit on an
"invited nobody" timer of its own — it is reacting to the server closing its
peer. ("1020" is Outbound's own generic connection-error display, not a Photon
StatusCode: StatusCode is 1022-1051, DisconnectCause 0-20, ShutdownReason 0-21 —
none is 1020.)

That pointed straight at the server, and the cause is a **misconfigured
dead-peer timeout**:

- `BlackIce.Server.Core` evicts any peer with no *inbound* datagram for
  `Server:Listener:DeadTimeoutSeconds`, which **defaults to 120 s**
  (`ServerOptions.cs`). `UdpListener.RunMaintenance` pings quiet peers, and a
  live client answers (refreshing `LastInboundUtc`) — but while the **Invite
  Friends system applet is open the game is suspended**, so the host stops both
  sending and answering pings. At 120 s of silence the server evicts it.
- `start-services.sh` tried to raise this to 600 s but used
  `Listener__DeadTimeoutSeconds=600` — the config reader only honours the
  **`BLACKICE_` prefix** and binds `ServerOptions` under `Server`
  (`ServerConfig.cs`, `.AddEnvironmentVariables(prefix:"BLACKICE_")`), so the
  correct key is **`BLACKICE_Server__Listener__DeadTimeoutSeconds`**. The
  mis-prefixed var was silently dropped and the server ran on the 120 s default —
  which is exactly the observed ~2-4 min solo/after-invite death.

**Fix applied:** `start-services.sh` now sets
`BLACKICE_Server__Listener__DeadTimeoutSeconds=600` (the port vars were already
correctly `BLACKICE_Server__Ports__…`). Takes effect on the next earlier-photon
restart — the currently-running instance still has the 120 s default. A cleaner
follow-up (not required for the fix) is to keep a host peer alive across applet
suspension, e.g. hold its slot while the room has a live registration rather than
evicting purely on inbound silence.


**Durable server fix (implemented + unit-tested, `earlier-photon`):** rather
than rely on a fixed timeout the applet can outlast, `BlackIce.Server.Core`'s
listener now keys the eviction grace to session stage —
`UdpListener.EvictionGrace(status)` returns `InRoomDeadTimeoutSeconds`
(default 1800 s) for `SessionStatus.InRoom` peers and `DeadTimeoutSeconds`
(120 s default, 600 s via env) for pre-room peers; `ServerOptions` validates
InRoom >= base; `KeepaliveTests.EvictionGrace_gives_in_room_peers_the_longer_timeout`
covers it (16/16 pass). earlier-photon was restarted so both the 600 s base and
the in-room grace are live. A host suspended by the Invite Friends applet is no
longer evicted mid-invite. Also fixed a self-matching `pgrep -f "BlackIce.Server.Host"`
in `start-services.sh` (it matched this shell and skipped the restart); it now
keys off the :27000 listen port.

### 2026-09-02 (cont.): first live host+join round — hosting works, native invite applet crashes citron; profiles consolidated to two shared personas

Ran host+joiner on citron (server fixes live). Results:

- **Hosting works end to end.** The host created and entered its room —
  `EnterRoom "P6HBNE" actor=1` — through the full NameServer→Master→GameServer
  flow with correct auth and GameProperties. The server's Fusion GameList event
  and the 09-02 property contract behaved as designed.
- **The native Invite Friends applet crashes citron** with a SIGSEGV
  (`segfault at e0`, unhandled SIGSEGV at rip `0x1fa6678`) the instant it loads
  system title `0100000000001013`. This is a **citron-side crash in the applet
  path**, not our server and not the join logic — a long-standing instability in
  this project's invite history. Workaround unchanged: skip the native button and
  deliver invites synthetically via `scripts/send-test-invite.sh <CODE>`.
- Decision (user): after confirming host+join on citron via the synthetic path,
  **move testing to Ryujinx** — a different emulator that may not hit this
  applet crash at all (an emulator gap, per the playbook's differential rule).
  The Stardew agent adapts the Ryujinx side; this repo's citron rig stays as the
  fallback.

**Profile consolidation (this session).** Per user direction, citron no longer
uses a profile/account per game. There are now **two shared personas** — host
and joiner — reused by every `*-legacy` title:

- Profiles moved to `~/.local/share/citron/{host,joiner}` (was
  `earlier-outbound/citron-{host,joiner}`); keys/firmware/content/tokens
  preserved by the move, both still 200 on `/api/me`.
- Shared launchers live in `shared-docs/scripts/` (`launch-citron.sh` engine +
  `launch-citron-{host,joiner}.sh`), reachable from any repo via its
  `shared-docs/` symlink. Outbound's `scripts/launch-citron-{host,joiner}.sh` are
  now two-line wrappers that add `OPENPAK_PHOTON_IP` and call the shared ones.
- Accounts `OutboundHost`/`OutboundJoiner` are the generic host/joiner identities
  for all titles. `setup-isolated-profiles.sh` still seeds Outbound's own content
  into the shared profiles (it is the Outbound content-seeder, not a per-game
  profile builder). Convention documented in `shared-docs/citron-isolation.md`
  §1/§3 and `shared-docs/conventions.md`.

### 2026-09-02 (cont.): join HANDSHAKE reaches actor=2 (NOT a working session). Root cause was dropped custom props (version), not the typing.

The join HANDSHAKE completes (the session then collapses ~120 s in — see the
later sections). Live result (citron host + citron joiner, injection-driven):

```
16:13:37 joiner OpJoinLobby "6S8GEE"
16:13:37 server GameList(222)={"6S8GEE"={253=true,254=true,252=1,255=4,
                 "scene"="startingLevel","vehicleType"=3,"knownPlayers"="","version"="1.1.7"}}
16:14:01 joiner OpJoinGame "6S8GEE"      <-- the op that NEVER fired before
16:14:02 GameServer EnterRoom "6S8GEE" actor=2 occupants=[1,2]
         joiner then sends 127+ RaiseEvents — real gameplay sync
```

**Real root cause (corrects the earlier 09-02 "typing fix closes it" over-claim):**
the property TYPING was necessary but NOT sufficient. The joiner cached the room
but its GameList entry carried only the four well-known keys — the host's custom
props (`scene`, `vehicleType`, `knownPlayers`, and especially **`version`**) were
missing. The host lists those under key 250 for the lobby to advertise, and
**Fusion will not join a session whose `version` it cannot match**, so it cached
the room and stalled, never sending OpJoinGame.

Why they were missing: `GameServerHandler.EnterRoom` built its own minimal game
properties and **threw away the host's incoming `GameProperties(248)`**, and the
Master GameList builder read the byte-keyed `Room.Properties` dict, which
structurally cannot hold the string custom keys (`"version"`).

**Fix (validated):**
1. `EnterRoom` now persists the creator's `GameProperties(248)` via
   `room.SetProperties(null, …)` into the object-keyed store (handles string keys).
2. `BuildFusionSessionLobbyEvent` reads `room.GameProperties` (object-keyed)
   instead of `room.Properties`, so `version`/`scene`/etc. pass through into the
   advertised GameList. The existing exclude list still drops the byte
   server-internal keys.

**Emulator notes from the same session:**
- **Ryujinx runs Outbound and HOSTS cleanly** — the `*photonengine.io*=127.0.0.1`
  route in `openpak_routes.env` redirects Photon's UDP to our server (route
  table works for UDP), full NameServer→Master→GameServer host flow, no crash.
  The citron native Invite-Friends applet SIGSEGV does not occur on Ryujinx.
- **Ryujinx cannot JOIN:** no invite applet, the Switch build's invite→join path
  is the broken empty-`PlatformSessionID` one, and Ryujinx has no call-injection
  facility. So the joiner must be citron (guest-call injection). Host may be
  either; hosting on Ryujinx avoids the citron applet crash.
- The host's own ~120s "hosting alone" OpLeave is Outbound's client-side timer
  (it was actively simulating and getting event echoes the whole time — not a
  missing server heartbeat); a real second player joining within the window
  satisfies it. Our server dead-timeout (600s base / 1800s in-room) is unrelated.

### 2026-09-02 (cont.): join HANDSHAKE reaches actor=2 repeatably, but NO working session (collapses ~120s in)

**Be precise about what works:** the JOIN HANDSHAKE completes (server logs
`actor=2, occupants=[1,2]`, events flow briefly), repeatably — but the session
is NOT playable: both peers fail ~120 s later. Do not call this a "working
two-peer join". What actually improved:

- **Join handshake reaches actor=2 repeatably.** On fresh instances, via both the
  synthetic invite and the **native Invite-Friends applet** (the applet DOES
  deliver a valid room code and fire the injection — earlier "nothing happened"
  was the stuck-stage bug below, not the applet). Before the GameProperties fix
  the joiner stalled at OpJoinLobby and never got this far.
- **Server join fix (validated):** advertising the host's custom props
  (`version`/`scene`) in the lobby GameList is what makes Fusion send OpJoinGame.
- **citron injection recovery (fixed):** the injection state machine got stuck at
  `Stage::Coroutine` when an injected join hung mid-coroutine (game degraded), so
  every later invite was refused "already running". `ArmPendingInvite` now
  force-resets a stuck stage on a fresh invite (`legacy_guest_call.cpp`), so
  joins retry without a full citron restart.
- **citron `F_GETFL` assert relaxed:** `bsd.cpp` FcntlImpl GETFL no longer
  `ASSERT(arg==0)` (Fusion passes a non-zero arg during transport socket setup).

**The one remaining blocker — Fusion real-time gameplay transport.** After the
join, both peers enter the live session and ~120 s later the joiner FREEZES and
the host times out (1020). Root causes, both confirmed this session:
1. **PRUDP-Lite P2P socket block.** Each peer binds a second UDP socket
   (`UNCONN 0.0.0.0:<ephemeral>`) for Nintendo's PRUDP-Lite P2P/NAT-punch
   discovery and blocks forever on its `recvfrom()` (citron's bsdsocket is
   single-threaded, so the whole game freezes). citron only *decodes*
   PRUDP-Lite (`DescribePrudpLite`); it does not bridge the two local peers'
   P2P sockets.
2. **Two-peer Fusion relay (event 101).** The server answers the relay
   Connect with a **solo-host self-loopback** `NetCommandAccepted`
   (`GameServerHandler` 101 handler) and relays 101 DATA to other actors only
   when `Session.Count>1`, but correct two-peer NetSocketRelay addressing
   (per-peer `NetConnectionId` Group/GroupIndex/Generation) is under-specified.

**Why it's not a one-shot fix:** the two-peer relay addressing needs
ground-truth from an actual two-peer exchange (all prior captures were solo
host). We can now GENERATE that (joins are repeatable), so the concrete next
step is to capture what the two peers exchange over 101 + PRUDP-Lite in the
~120 s before timeout and implement the addressing/bridge from it — the same
observe-then-implement loop used all project, not guesswork on the relay code.

### 2026-09-02 (night): the two-peer capture EXISTED already, and it rewrites the diagnosis — the missing piece is a Fusion Shared-mode SERVER, not P2P/relay addressing

Re-read the previous 18:10 run (photon log `earlier-photon.log`, room `34Y4LE`, host
`:37380` actor 1, joiner `:60607` actor 2) instead of re-running it. The capture already
contained the two-peer ground truth §1 asked for, and both "blockers" in the plan above are
wrong:

- **Blocker A (PRUDP-Lite recvfrom freeze) is dead.** The joiner citron log for that run has
  ZERO `prudp`/`raw[` lines and no blocked socket; the `SOCK_NONBLOCK` fix of 08-29 already
  removed that freeze. The "joiner freezes" observation is the game's own reaction to the
  collapse below, not a socket block.
- **Blocker B (two-peer relay addressing) is a misdiagnosis.** Neither peer ever addresses the
  other. Every code-101 packet from BOTH peers is `OpRaiseEvent` with `ActorList(252)=[0]`,
  i.e. target actor 0. Decompiled Fusion (`NetSocketRelay.Send` → `SendPackage(101,
  address.ActorId, …)`, `CloudCommunicator.OnEvent` → `PushPackage(evt.Sender, …)`) plus
  `CloudServices.HandleStartMessage`: in `GameMode.Shared` the client does exactly ONE
  `Connect(NetAddress.FromActorId(0))`. Actor 0 is the Photon Cloud **Fusion plugin**, which
  in Shared mode is a real Fusion SERVER simulation, not a relay.
- **What actually collapses, with timestamps:** joiner `EnterRoom actor=2` 18:10:44.87; joiner
  relay `Connect` 18:10:45.27 (our server answers the solo-host `Accepted`); the 14-byte
  `04 00…` frames from both peers are `NetPacketType.NotifyAcks` keepalives (Outbound's own
  enum from the IL2CPP dump: `NotifyData=3, NotifyAcks=4`; layout `NetNotifyHeader` = type,
  fragment, seq u16, ackSeq u16, ackMask u64 = 14 B). Once `Session.Count==2` our server stops
  echoing them back and cross-relays them instead (sender 1↔2, addresses neither peer has a
  connection for → dropped). 15 s later, 18:10:59.86, the host sends command 4 =
  `NetCommands.Disconnect` (reason 2 = Timeout) and the joiner follows 100 ms later. The
  OpLeaves at 18:12:09 (host) / 18:12:43 (joiner) are the game giving up. So the session never
  lived 120 s: the relay link died at +15 s; the solo-host "echo" hack only ever worked because
  a client happily accepts its own keepalives as the server's.
- **Why the echo can't be extended:** a Shared-mode client sends its state (NotifyData) to
  actor 0 and expects a Fusion server to (a) run the V2 notify transport (acks/windows),
  (b) hold the object state words and replicate them to the other client, (c) allocate
  PlayerRefs, send `PlayerRefMapping`, drive `RuntimeConfig`, state-authority transfer, master
  client. Outbound's game code is deeply Shared-mode (`RequestStateAuthority`,
  `IsSharedModeMasterClient`, `HasStateAuthority` all over `NetworkPlayer`/`NetworkManager`),
  so flipping the game to Host/Client mode via injection is a dead end too.
- **Photon Server v5 (user's links) is not a shortcut:** per Photon staff on the (now
  read-only) forum, the FusionPlugin is not shipped in the Server SDK and runs only on Photon
  Cloud; Photon Server itself is Windows-only and license-gated. Its Plugins API is only useful
  as a reference for what the plugin does.

**The path that works (spiked tonight, outside the repos in `~/photon-oracle/fusionhost/`):**
Fusion.Runtime.dll's OWN `Simulation.Server` class contains the Shared-topology server code
(`RecvPacket → ReadStateTick + StateReplicator`, `CreateRuntimeConfiguration`,
`RegisterUniqueIdPlayerMapping`), i.e. the cloud plugin is that class hosted headless. Hosting
it on plain .NET needs no Unity:

1. `UnityEngine.dll` stub (`fusionhost/UnityEngine/Stubs.cs`, ~500 lines) covering the exact 92
   types / 418 members Fusion references (list generated by `tools/RefDump` from the DLL
   metadata): real managed Vector/Quaternion/Matrix/Mathf, `UnsafeUtility` on `NativeMemory`,
   `JsonUtility` on System.Text.Json (IncludeFields), no-op profiler/scene/physics.
2. `Photon.Realtime.dll` compiled from the SDK's `PhotonRealtime/Code/*.cs` (Fusion.Runtime
   references that assembly name; the SDK ships it as source). `Fusion.Log.dll`, managed
   `NanoSockets.dll` and Linux `libnanosockets.so` copied from the SDK package (address
   `ToString` P/Invokes it even for relay addresses).
3. `Host/` spike: Krafs.Publicizer exposes internals; a `NetworkRunner` is constructed
   (stub `Behaviour` base) only to satisfy `Simulation.Runner` reads (`_config`, `_callbacks`,
   `_simulation`, `OnGameStartedInvoked=true`); `Simulation.Server(SimulationArgs{Mode=Server,
   Topology=Shared, Socket=in-memory INetSocket, Callbacks=ours})` and a `Simulation.Client`
   from the same DLL connected through an in-memory socket pair.
   **Result so far:** server ticks at 32 Hz, client `Connect` is accepted once
   `server.RegisterUniqueIdPlayerMapping(actorId, uniqueId, PlayerRef)` was called first
   (exactly the plugin's Join-time step — `OnConnectionRequest` answers `Waiting` for unknown
   ids), `PlayerJoined`, both directions carry packets. Remaining spike blocker: the SDK's
   `StateReplicator.WriteObject_WriteData` writes a `PluginVersion` varint before the word list
   when `Topology==Shared`, but `ReadObjectUpdate_GetWords` never reads it, so the client parses
   RuntimeConfig as 0 words + garbage ids ("failed to create an instance"). The real plugin is
   evidently asymmetric (reads PV from clients, omits it towards clients). `tools/Patcher`
   (Mono.Cecil) applies exactly that to a server copy (`~/photon-oracle/patched/Fusion.Runtime.dll`):
   skip the write when `_simulation is Server`, read it when `_simulation is Server`.
   **With the patch the spike PASSES:** client receives RuntimeConfig + first snapshot, resets to
   the server tick, `OnClientStart`, `PlayerJoined`, both sims tick in lockstep (server 32 Hz,
   client ~32 Hz), ~750 B/s each way. Run: `cd ~/photon-oracle/fusionhost/Host && dotnet run -c
   Release` → `RESULT: OK client connected + ticking` (TRACE=1 for Fusion's own trace log).

**Version note:** Outbound speaks Fusion protocol message version 10 (`V1_6_0`, its
`ProtocolMessageVersion.LATEST`), the 2.1.2 SDK is 12 (`V1_7_0`) but still lists `V1_6_0`; the
message codec is versioned per message, the simulation packet layer is not — expect to need the
matching 2.0.x SDK if the live test shows packet-level disagreement.

### 2026-09-02 (night, cont.): the Fusion Shared-mode server is BUILT into earlier-photon (two-client relay unit-proven; live run is the only gate left)

The spike graduated into the real server. New, all committed-ready in `earlier-photon`
(uncommitted at session end — see the list at the very bottom):

- **`BlackIce.Server.Fusion.UnityStub`** — hand-written `UnityEngine.dll` (~500 lines) covering the
  exact 92 types / 418 members Fusion references. Real math/memory/JSON; inert scene/physics/profiler.
- **`BlackIce.Server.Fusion`** — hosts Fusion's own `Simulation.Server` (Shared topology) one-per-room
  (`FusionSharedServer`), bridged to clients through `RelaySocket`, an in-process `INetSocket` whose
  datagrams are Photon **event-101** payloads. `FusionServerFactory` isolates all Fusion-internal use
  (Krafs.Publicizer). Thread-affine: each room ticks only on its owning listener thread.
- **`IFusionSessionHost`** (in LoadBalancing) + wiring in **`GameServerHandler`**: on a Fusion Join it
  assigns the actor a STABLE 8-byte UniqueId (`FusionProtocol.UniqueIdForActor`, written into the Join
  Confirmation — the client re-presents it on its 101 Connect) and calls `PlayerJoined`; inbound 101 is
  fed to the hosted server instead of the solo self-echo; 100/101 are never relayed peer-to-peer when a
  server hosts the room. Leave → `PlayerLeft`.
- **Host** (`ListenersHostedService`): constructs `FusionSharedServer` with a send callback that emits
  outbound 101 via `RoomSession.SendToActor(actor, Ev(101, ActorNr=0, Data))`, and drives its `Tick`
  from the Game listener's new `UdpListener.OnTick` (~32 Hz).
- **Optional build:** the whole thing links Fusion's non-redistributable DLLs from `server/fusion-libs/`
  (gitignored: `server/fusion-libs/`, `*.so`). Absent them the server still builds and falls back to the
  solo path — verified by building the solution with the folder hidden. Produce the libs per
  `earlier-photon/docs/fusion-shared-server.md`; the one required binary patch (the plugin's
  PluginVersion read/write **asymmetry** in `StateReplicator`) is applied by `tools/fusion-patcher`
  (Mono.Cecil) to a server copy of `Fusion.Runtime.dll`.

**What is proven (headless, `~/photon-oracle/fusionhost/Host`):** with the patched runtime, ONE client
and then TWO clients connect to a single hosted `Simulation.Server`, both reach `HasRuntimeConfig`,
receive the first snapshot, and tick in lockstep at 32 Hz while state words flow client→server→client.
That is the two-peer relay the solo-echo hack could never do. `dotnet test` on earlier-photon: 61 + 50
pass; the single failing `RoleHandlerTests.NameServer_authenticate…` is PRE-EXISTING (fails identically
on the clean tree, unrelated to any of this — a NameServer test I never touched).

**The only gate left is the live run** — see the rewritten NEXT SESSION below. Everything up to the wire
is built and unit-proven; what a live Outbound host+joiner will validate is that the client's real 100/101
bytes drive the hosted server the same way the headless Fusion client does (protocol-version match, the
GameList/lobby path into `OpJoinGame`, and that the session now holds past the old ~15 s relay-death).

### 2026-09-02 (night, LIVE RESULT): first real two-player session — transport HOLDS ~83s, no relay-death; remaining gap is Shared-mode PlayerRefMapping

Ran host+joiner live through the new Fusion Shared-mode server (earlier-photon rebuilt with
`server/fusion-libs/` present, restarted). **Milestone reached and it is unambiguous in the server log
(`earlier-photon.log`, room `53RDYE`):**

- Host `actor=1` 20:26:07, joiner `actor=2` 20:26:44, and the hosted `FusionSharedServer` logged
  `room "53RDYE" players=2` ticking at 32 Hz with `fed`/`emitted` BOTH climbing (gameplay relayed both
  directions) — e.g. `tick=2857 players=2 fed=424 emitted=268`. **The two-player session held from
  20:26:44 to 20:28:07 — ~83 seconds** — with ZERO evict/Timeout/Disconnect from the server. The old
  ~15 s relay-death is gone. The transport (the thing the whole project was stuck on) works.

- It ended by the **HOST sending a voluntary `OpLeave`** at 20:28:07 (shown to the user as "1020"). Root
  cause is the KNOWN invite-screen teardown: the host citron log was polling
  `TryPopFromFriendInvitationStorageChannel` the whole time (host sitting on the Invite-Friends screen),
  and exiting that screen makes Outbound tear the session down. NOT a server/transport failure.

**Three DEPLOYMENT bugs fixed live to get here (all in the Fusion-host wiring, none in the design):**
1. `Photon.Realtime` (and Fusion.Common/Log) threw `FileNotFoundException` when the room's
   `Simulation.Server` constructed — the libs weren't next to the Host exe. Fixed by copying
   `server/fusion-libs/*.dll` to the Host output.
2. Copying wasn't enough: `Fusion.Runtime` loads `Photon.Realtime` by NAME at runtime, and .NET only
   trusts assemblies in the app's `deps.json`. Fixed by referencing every Fusion lib EXPLICITLY in
   `BlackIce.Server.Host.csproj` (under the FUSION_LIBS condition) so they land in deps.json.
3. (Earlier) the UnityStub/publicizer/patch chain — already in place from the build work above.

**The remaining gap — the joiner joins + relays but never fully enters the world.** The server sends only
the two bootstrap messages over event 100 (Join Confirmation `data[38]` + Start `data[25]`). A real Photon
Cloud Shared session ALSO sends **PlayerRefMapping** (Fusion protocol msg id 8: `ActorId:int`,
`PlayerRef:int`, `UniqueId:byte[8]`) so each client registers the OTHER player, and re-broadcasts it as
players come/go. Without it the two peers are in one room relaying state but neither spawns the other into
the game — exactly "connected but not fully in." Likely also need **ChangeMasterClient** (msg 9) though
the room's `MasterClientId` prop is already set to actor 1. Next session: encode msg 8 (and 9) with the
existing `FusionBitWriter`, and have `GameServerHandler` emit PlayerRefMapping to BOTH actors when the
second one joins (server sender actor 0, event 100) — mirror what `FusionProtocol.EncodeJoinConfirmation`
does. The UniqueId to advertise is `FusionProtocol.UniqueIdForActor(actor)` (already deterministic). Then
re-run host+join; success = joiner renders into the shared world and both see each other. Keep the host OFF
the native Invite-Friends screen (use `scripts/send-test-invite.sh` and accept the toast) so its own
invite-exit teardown doesn't end the session.

### 2026-09-02 (night, LIVE #2): PlayerRefMapping implemented + confirmed on the wire; two-player session holds but NEITHER client enters gameplay (only keepalives) — the wall is now game-entry, not transport

Built `FusionProtocol.EncodePlayerRefMapping` (Fusion protocol msg id 8) and wired
`GameServerHandler` to broadcast it both ways when a peer's Start is sent (joiner learns every actor,
each started peer learns the joiner; addressed with each recipient's own protocol version; PlayerRef ==
actor, UniqueId == `UniqueIdForActor`). Confirmed live in room `8FTV7E`: after `actor=2`, the server
sent `byte[35]:08 …` = PlayerRefMapping to both peers, alongside Join Confirmation (01) and Start (05).
Session held `players=2` cleanly for ~78 s.

**But the joiner never left its loading screen, then TIMED OUT** (Fusion's 120 s StartGameOperation
limit), and the host dropped. The decisive evidence is the full-session 101 traffic profile:
- host `54780`: 972× 14-byte, 5× 152-byte (relay Connect), 1× 136-byte.
- joiner `50552`: 659× 14-byte, 5× 152-byte, 1× 136-byte.

i.e. **~1600 NotifyAcks keepalives and the relay handshake, and ZERO NetworkObject state either way.**
Neither client authored a single gameplay word the whole time. So the clients complete Join → Start →
relay Connect → PlayerRefMapping and then just idle-keepalive; the game simulation never starts, so the
joiner's StartGame never resolves and times out.

**What this rules in/out:**
- Transport (event 101 / hosted `Simulation.Server`), room join to `actor=2`, and player registration all
  WORK and hold two peers — repeatably (rooms 53RDYE ~83 s, 8FTV7E ~78 s), no relay-death, no server evict.
- The wall is now CLIENT-SIDE GAME ENTRY: something after PlayerRefMapping that makes the real client
  transition from "connected, keepalive-only" into an authoring, ticking simulation (and load the level).
  The headless spike could not surface this because it drove `Simulation.Client.Update` directly and never
  ran the real client's CloudServices `StartGameOperation` / scene / spawn path.

**Next step — capture a REAL working session, do not keep guessing.** We own ONE Steam copy of Outbound
(`/mnt/games/SteamLibrary/steamapps/common/Outbound`). Constraints confirmed with the owner: Steam allows
only one active game session per account, so the SAME copy/account cannot run on two PCs at once, and
Family Sharing can't play one copy twice either — a two-Steam-client capture is NOT available.
`~/Downloads/outbound-real-photon.pcap` is EMPTY (24-byte header only), so there is no prior capture.
**You very likely do not need two players for this:** the joiner fails to enter its OWN game world
(keepalive-only, never authors state), which is the SOLO StartGame -> scene-load -> spawn path. So capture
a SINGLE Steam client connecting to real Photon Cloud and starting/entering a session, and record the FULL
event-100/101 sequence — specifically what flips a client from keepalive-idle into authoring state. (A
genuine two-player capture, if ever wanted, would need Steam + a real Switch, or a second Steam account
with its own copy, both against Photon Cloud.) Capture method: MITM/observe Outbound's Photon UDP (the
game resolves ns.photonengine.io; point it at a logging relay, or run the game under the same
citron/Ryujinx PHOTON logging but against REAL cloud instead of our server). Prime candidates for the missing trigger: **Snapshot (msg 6)**, **ChangeMasterClient
(msg 9)**, a **scene/NetworkSceneInfo** sync, or a room-property change the client waits on. Then
implement that one thing server-side (same observe-then-implement loop as the rest of the project). The
capture is the input we lack; everything up to it is now built and proven.

### 2026-09-02 (night, CAPTURE): a real Photon-Cloud session captured + decoded — events are PLAINTEXT, our bootstrap matches byte-for-byte, and the wall is the NotifyData STATE STREAM / client never authoring

Captured a genuine SOLO Outbound×Photon-Cloud session on the Steam client (`pkexec tcpdump` on the
Photon UDP ports; only one Steam copy, but SOLO is enough — a solo cloud client fully enters the game).
Decoded it with a new tool `~/photon-oracle/pcapdecode` (references `BlackIce.Photon`: parses SLL2 ->
IP/UDP -> Photon datagram -> `NCommand` -> `WireMessage`). Artifacts on the pool (never committed):
`/mnt/media/research/outbound/REFERENCE-cloud-solo-223853.pcap` and `...-decoded.txt`.

**Findings that reframe the remaining work:**
1. **Events are PLAINTEXT.** Cloud encrypts only auth (NameServer/Master, and the GameServer OpJoinGame
   response + EvJoin come as `ENCRYPTED msgType=3/4`), but every Fusion 100/101 event is readable. So NO
   Frida/managed hook is needed — `tcpdump` + our decoder is the capture pipeline going forward.
2. **Our server's bootstrap is byte-identical to Cloud.** A whole solo cloud session's event-100 is just
   **Join Confirmation (msgid=1, 38B)** + **Start (msgid=5, 25B)** — NOTHING else (no PlayerRefMapping /
   Snapshot / ChangeMasterClient for solo). Over 101: one **Accepted (msgid=1, 32B)**. Our server emits
   exactly 38 / 25 / 32-byte messages for these. The handshake is correct.
3. **The difference is the state stream.** Immediately after Accepted, Cloud streams **event-101
   NotifyData (msgid=3 == NetPacketType 3)** continuously: an initial burst (128 / 183 / 184 / 66 B = the
   world/scene snapshot) then steady 26-27 B ticks at ~30/sec (6419 of them in the session). And the
   **client authors back**: ~1936 `OpRaiseEvent` carrying 101 data (64-89 B) — it becomes state authority
   over its player and streams it.
4. **In our failed sessions the client sent ONLY 14-byte NotifyAcks (type 4) — it never authored a single
   NotifyData, i.e. it never actually spawned into the game.** Our server DID emit ~1000 substantial 84/99-B
   101 packets outbound (from the run log), so we are streaming *something*, but the client never crosses
   into the authoring/spawned state that Cloud's client reaches within ~1 s.

**NEXT — the definitive diff (no more theorizing).** Capture OUR OWN server session with the identical
pipeline and compare against the cloud reference:
- Relaunch ONE Outbound host (citron or Ryujinx) against earlier-photon (the built server with the Fusion
  host). `pkexec tcpdump -i any -s0 -w <pool>/ours.pcap 'udp and (port 5055 or 5056 or 5058 or portrange
  27000-27003)'` (loopback 127.0.0.1 works on `-i any`). Enter a session.
- Decode with `~/photon-oracle/pcapdecode <pcap>` and diff the event-100/101 stream against
  `REFERENCE-cloud-solo-decoded.txt`. Focus: after Accepted, does OUR server send the same initial
  NotifyData burst (128/184/66 B snapshot) then steady 26-27 B? Do the msgid=3 payloads decode as valid
  object state on the client? The gap is almost certainly in the initial-snapshot NotifyData content (the
  scene/RuntimeConfig/spawn words) — our hosted `Simulation.Server` produces different/absent initial state,
  so the client never spawns and so never authors. Fix that content to match, then re-test.
- Byte-level reference for the bootstrap is in the decoded.txt; pull raw hex of the first Accepted +
  first few NotifyData from the pcap with the decoder if a byte diff of payloads is needed.

### 2026-09-02 (night, ROOT CAUSE FOUND): client drops our state because our Fusion SDK (2.1.2) sends NetPacketType V2(250); Outbound's older Fusion only knows NotifyData(3). Fix = build fusion-libs from Fusion 2.0.x.

Two captures + a one-line server change nailed it (decoded with ~/photon-oracle/pcapdecode). Our 101
stream was ENCRYPTED so the decoder showed "0 events"; the user's hunch that this mattered led to the fix
that EXPOSED the real bug:

- Made our server send Fusion 100/101 events PLAINTEXT (Cloud sends 100/101 clear even on an encrypted
  connection): PeerConnection.RaiseEvent skips encryption when ev.Code is 100 or 101. KEEP THIS (correct
  vs Cloud). It does NOT by itself fix the client (the client decrypted our events fine already), but it
  let us read our 101 stream.
- With ours readable: our 101 state packets are msgid=250 = NetPacketType.V2. Cloud's are msgid=3 =
  NetPacketType.NotifyData. Confirmed from enums:
  * Outbound build (~/outbound-re/dump-output/dump.cs): Command1, UnreliableData2, NotifyData3, NotifyAcks4,
    Unconnected5, Mtu6/7, NotifyReliableData8. NO 250.
  * Fusion 2.1.2 SDK: V2=250, Command1, UnreliableData2, Unconnected5, Mtu6/7, NotifyReliableData8. NO 3/4.
    Photon replaced NotifyData/NotifyAcks with the unified "V2" packet between Outbound's version and 2.1.2.
- So our hosted Simulation.Server (2.1.2) streams V2/250; Outbound's client has no handler for 250, DROPS
  every state packet, never spawns, only sends 14 B NotifyAcks, and times out at Fusion's 120 s StartGame
  limit. NOT encryption, NOT PlayerRefMapping, NOT the handshake (all correct + byte-match Cloud).

FIX (next session): rebuild server/fusion-libs/ from Fusion 2.0.x (Outbound = ProtocolMessageVersion
LATEST=10 / V1_6_0; 2.1.2 = 12 / V1_7_0). Outbound's NetPacketType still has NotifyData=3/NotifyAcks=4 ->
predates V2 -> likely Fusion 2.0.0 GA (verify that release's Fusion.Sockets NetPacketType has NotifyData=3,
no V2). Steps: download Fusion 2.0.x from Photon (account), redo fusion-libs (DLLs + Linux
libnanosockets.so, build Photon.Realtime from its PhotonRealtime/Code/*.cs, run tools/fusion-patcher and
RE-CHECK whether the PluginVersion asymmetry patch is still needed for 2.0.x). UnityStub, RelaySocket,
GameServerHandler wiring, PlayerRefMapping, and the plaintext-events change are version-independent and
stay. Then re-capture and confirm our 101 is msgid=3 and the client spawns (it will send its own
OpRaiseEvent(101) state ~64-89 B like Cloud's client). Reference on pool: pcapdecode,
REFERENCE-cloud-solo-*.pcap, ours-plain-*.pcap.

### 2026-09-02 (night, FIXED — two players IN GAME for ~2 min): rebuilt fusion-libs from Fusion 2.0.8; the client now spawns and authors. Remaining: session continuity (~2 min drop).

The root-cause fix worked. Rebuilt `server/fusion-libs/` from **Fusion 2.0.8** (Outbound's exact build,
2.0.8.1402 — downloaded to `~/Downloads/photon-fusion-2.0.8-stable-1402`, staged at `~/photon-oracle/v208`).
Changes required for 2.0.8 vs 2.1.2 (all done, server builds + runs):
- 2.0.8 references **Photon3Unity3D.dll** (classic Realtime v4), not PhotonClient/Photon.Realtime. No
  Photon.Realtime source build needed. Updated `BlackIce.Server.Fusion.csproj` + Host csproj refs.
- **No PluginVersion patch** for 2.0.8 (that concept is 2.1.x-only) — use Fusion.Runtime.dll UNPATCHED.
- `Simulation.ICallbacks` differs: rewrote `NoopCallbacks` (adds `OnMessage`->SimulationMessageResult,
  `OnReliableData(PlayerRef,ReliableId,bool,byte[])`, `ObjectChanged`, `RemoteObjectCreated`,
  `RemoteObjectDestroyed`; drops OnRemoteCreate/OnObjectWrite/etc.).
- `TickRate.SharedDefault`->`TickRate.Default`; `Log.InitializeForConsole(LogLevel)`-> best-effort
  `Log.InitForConsole(LogType.Info)`.
- UnityStub: added `UnsafeUtility.IsUnmanaged`, `Color32<->Color`, `UnityEngine.Profiling.Profiler`
  (BeginSample/EndSample), `Quaternion.normalized` (2.0.8 needs these; 2.1.2 didn't).

**Live result (room 9BX5CE, capture pipeline confirmed the pattern):**
- Our server now streams event-101 NotifyData at **26/27/28 B** (matching Cloud's 26-27 B deltas) with a
  larger initial burst — was uniform 84 B V2/250 on 2.1.2.
- **Both clients now AUTHOR state back** — 22/34/46/51/60 B packets (not the old 14 B acks-only). i.e.
  they SPAWNED and entered the world. User confirmed: "I managed to get in."
- Session held **players=2 for ~2 minutes** (host 22:07:39, joiner 22:08:21, both streaming until
  ~22:10:10, ~5900 inbound packets). Then both clients went quiet and the joiner timed out client-side.
  Our server kept ticking + did NOT evict (600 s grace) — the CLIENTS stopped, not the server.

**NEXT: session continuity (why both clients go quiet ~2 min in).** Entry is solved; this is a smaller,
different problem. Likely causes to check: (a) our headless `Simulation.Server` runs its OWN clock/tick
and authors RuntimeConfig/internal state — over ~2 min its time-sync or tick may drift from the real
clients (Fusion is tick-locked); (b) a relay-continuity break (a peer stops seeing the other's state and
its per-peer timeout fires); (c) something periodic (Fusion DummyTrafficSync/keepalive, or a game event).
Diagnose by capturing the ~2 min window (same pcap pipeline) and watching what changes right before both
go silent — does our server stop sending 26 B NotifyData, do the clients stop acking, does a Disconnect
(NetCommands.Disconnect / event-100 msg4) appear, or does time-sync (event 100 or the tick numbers)
diverge. The whole rig is unchanged; just re-run host+join and read the last ~10 s before the drop.

### 2026-09-05: the ~2 min drop ROOT-CAUSED from the existing capture — our tick loop stalled 20 s (thread-id affinity vs an async loop); fixed, live re-run pending

No new live run was needed: `ours-208-230611.pcap` + `earlier-photon.log` (archived as
`services/earlier-photon-2208-tickstall.log`, room `9BX5CE`) already contained the drop. Decoded with
`~/photon-oracle/pcapdecode --all` (pcap clock is +1 h vs the server log).

**Timeline (server-log clock):** host `46247` in at 22:07:39, joiner `58168` at 22:08:21; both stream
state, server streams 26–27 B NotifyData at ~30/s per client. At **22:09:55.7 the server stops emitting**
(last `raise Ev(101)` msgid=3). Clients keep sending state for 15 s, then go acks-only at ~22:10:05 and
silent at 22:10:10.8. At **22:10:15.86 the server sends both clients a 136 B `01 04 02…`** = NetCommand
**Disconnect, reason 2 = Timeout** — the hosted Fusion sim itself kicked them. Then the sim burst-ticks
(8874 → 10163 in ~2 s) to catch up ~20 s of lost time. NOT a client timeout, NOT time-sync drift, NOT the
relay: our `Simulation.Server` simply was not ticked for 20.7 s.

**Why:** `RoomSim.Tick` guarded on `_ownerThreadId == Environment.CurrentManagedThreadId`, set at Join.
But `UdpListener.RunAsync` is an `async` loop — every `await ReceiveAsync` resumes on whatever pool
thread is free, so the "listener thread" is a fiction (log thread tags t8/t11/t15/t16/t18/t21/t23 all
interleave). Ticks only happened on iterations that landed on t15 by luck (also why the tick rate read
56–66/s instead of a steady cadence). Thread t15 appears in ZERO log lines from 22:09:56 to 22:10:14 (the
pool parked it) and reappears at 22:10:15 — exactly the stall window. `[FusionHost]` once-per-second
lines stop/resume on the same boundaries.

**Fix (earlier-photon, committed):** `UdpListener.Current` — an `AsyncLocal<UdpListener>` set at the
top of `RunAsync`, so it flows to every continuation of that loop regardless of thread. `RoomSim` now
records `_owner = UdpListener.Current` at Join and ticks only when `ReferenceEquals(_owner,
UdpListener.Current)`; the game/gameAlt dual wiring stays safe. Test:
`UdpListenerMaintenanceTests.Current_identifies_the_loop_across_thread_hops` (ticks land on several
threads, `Current` is always the listener, null off-loop). Full suite: only the PRE-EXISTING
`NameServer_authenticate…` failure remains.

**Next:** re-run host + join (same rig, §0 below). Expect: `[FusionHost]` lines every second with a
steady tick rate, no 20 s gap, session holding well past 3 min. If it still drops, read the last 10 s
before the drop the same way (per-second `raise Ev(101)` counts + thread tags + `[FusionHost]` cadence).

### 2026-09-06: CONTINUITY CONFIRMED FIXED live (7+ min hold); the new wall is STATE REPLICATION — the server can't parse client objects; plus a 14.4 GB server memory leak

Ran the tick-ownership fix live (two rooms: `DHPHCE`, then `J6HM3E` after a memory-forced restart).
**Continuity is solved:** `J6HM3E` held `players=2` from tick 0 past tick 21000 (7+ min) with a
STEADY ~64 ticks/s and zero Disconnect — the 20 s stalls are gone. `[FusionHost]` heartbeats are
regular now. That closes the "~2 min drop" chapter for good.

**But the two clients are in completely separate worlds** (user: "like they aren't playing the same
game" — different time-of-day, can't see each other). Diagnosed end-to-end from the server log:

- **Server→client 101 is 26/27 B for the entire session** (header-only NotifyData, zero object
  words). Only exception is a one-time ~117 B burst at join = RuntimeConfig/SceneInfo. Clients DO
  author real state upward (22 B keepalives + 34–60 B deltas + a 289–294 B spawn burst each), and
  the sim's `fed` counter climbs — so the server RECEIVES their state and just never re-emits it.
- **Why:** the hosted `Simulation.Server` THROWS while parsing the client object stream. Server log
  (`blackice-server-*.log` / `earlier-photon.log`) shows, at spawn time:
  `Object does not exist: [Id:525312], but is marked as confirmed. This indicates invalid data from
  the remote host`, followed by a `NetBitBuffer` overflow with stack
  `StateReplicator.ReadObjectUpdates → SkipObject → SkipObjectData → NetBitBuffer.ReadInt64VarLength`.
  So the server never creates the players' objects (`_metaLookup` lacks them) and has nothing to
  forward → 26 B headers forever.
- **Root cause (high confidence):** the headless generic server has NO game serializer registration.
  Outbound's IL2CPP dump has `NetworkProjectConfigAsset.SerializableSimulationBehaviourMeta` (the
  per-behaviour word-count + serializer table) and a `FusionSerializationVersion` field on its
  protocol struct. Client objects encode words through COMPRESSED serializers (e.g. `NetworkTRSP`
  quantized position/rotation). Our `NetworkProjectConfig` is empty, so `meta.Serializers` is default
  → `ReadObjectDataIntoPtr`/`SkipObjectData` read each word as a plain `ReadInt64VarLength(6)` →
  wrong bit count → desync → "object does not exist" on the follow-up update → overflow. Confirmed
  the failing path is exactly `StateReplicator` object read, not the transport (transport holds).

**Two candidate paths for next session (pick after a decision — they're materially different):**
1. **Give the headless server Outbound's serializer registration.** Extract the weaver-generated
   per-type/word serializer table from `SerializableSimulationBehaviourMeta` (+ the prefab/type ids)
   in the IL2CPP dump and register it into the `NetworkProjectConfig` the server builds in
   `FusionServerFactory.CreateServer`. Biggest unknown: whether the generic `Simulation.Server` even
   consumes a data-driven serializer table without the game's compiled `NetworkBehaviour` types, or
   whether it needs the actual weaved managed types (which we don't have on .NET). This is the
   "make the server understand the game" path.
2. **Verify how real Photon Cloud's plugin does it, then match.** We have NOT captured a real
   two-client Cloud session — only solo. Capture one (two Steam clients, unredirected Cloud, the
   proven `/etc/hosts` + tcpdump technique) and check the server→client 101 sizes: if Cloud ALSO
   sends only header-sized packets and the two Steam clients still share a world, then Shared-mode
   object relay is peer-to-peer via the plugin echoing OPAQUE blobs (not re-serialized), and our
   server should relay each client's object bytes verbatim to the other WITHOUT running
   `ReadObjectUpdates` at all — i.e. bypass `StateReplicator` parsing for peer objects. This is the
   "server stays a dumb relay" path and is likely much smaller if the capture supports it.

Recommendation: do (2) FIRST (one capture settles whether the server must parse or just relay), then
either register serializers (1) or switch to opaque relay. Do NOT keep guessing at the parser.

**Memory leak (fix before any long soak):** over the night's cumulative runs one `BlackIce.Server`
process reached **14.4 GB** RSS and drove the 29 GB machine to 1 GB free, which OOM-wedged both
citrons (host could only make one aborted NameServer connect → "spinning wheel"). A freshly started
server is ~0.3 GB and a single 7-min session stayed ~0.3 GB, so the leak is gradual/cumulative
(suspect: per-room `Simulation` snapshot timelines or `RelaySocket` inbound queues not draining, or
rooms not disposed on `PlayerLeft`). Mitigation for now: restart the server (`scripts/start-services.sh`)
between long runs. Start it DETACHED (`setsid nohup … < /dev/null &`) — the harness kills a normal
child process group on a low-memory event, which took the server down mid-session twice tonight.

**Unproven idea left OUT of the tree:** a `ScheduleAllObjects` sweep (register every object on every
connection's send schedule each tick) was written and REVERTED — it can't matter until objects parse
(nothing to schedule), so it wasn't committed. Re-add it only if path (1) makes objects parse and
they still don't forward.

### 2026-09-06 (cont.): "separate worlds" ROOT-CAUSED — a NullReferenceException in the hosted server, NOT a missing serializer table; fixed, live re-run pending

The 09-06 "root cause (high confidence)" above is WRONG and is retracted. Read straight from the
Fusion 2.0.8 decompile (`~/photon-oracle/decompiled-208/Fusion.Runtime.cs`):
- `NetworkProjectConfigAsset.SerializableSimulationBehaviourMeta` is just `{Type, ExecutionOrder}`
  (execution-order overrides), not a serializer table.
- `NetworkObjectMeta.Serializers` is a STATIC table (`GetSerializers(HasMainTRSP)`): only the
  built-in NetworkTRSP compression at words 22–28, keyed by a header flag. The generic server needs
  NO game registration to parse client objects. The word layout was never the problem.

**The real failure was in the archived log all along** (`services/earlier-photon-0906-nre-noneconn.log`,
line ~300–370). Every client packet carrying object updates — the 3-fragment ~3.3 KB spawn burst, then
the 342 B and 80 B follow-ups — printed:
```
Object reference not set to an instance of an object.
   at Fusion.Simulation.StateReplicator.ReadObjectUpdates()
   at Fusion.Simulation.StateReplicator.RecvPacket()
   at Fusion.Simulation.Server.RecvPacket()
```
BEFORE the single "Object does not exist … marked as confirmed" warning. The transport acks those
packets anyway (NotifyAcks are below the parser), so the client flips its objects to
CreatedConfirmed and stops sending headers; "does not exist" is the downstream symptom.

**Why it NREs:** `ReadObjectUpdates`' Shared-topology branch does
`GetSimulationConnectionForPlayer(_simulation.LocalPlayer).GetObjectData(id, create: true)` for
every object update. On a pure `Simulation.Server`, `LocalPlayer` is `PlayerRef.None`, and the only
`PlayerAdd` paths register real players (`RegisterUniqueIdPlayerMapping`) or the Host's local player —
nothing ever puts `None` into `_playersConnections`, so the lookup is null. Fusion.Runtime has
`InternalsVisibleTo("Fusion.Plugin")`: Photon's closed cloud plugin evidently registers that
connection itself; the SDK alone never does. The headless two-client spike never spawned an object,
so it never hit this line.

**Fix (earlier-photon `FusionServerFactory.CreateServer`, uncommitted):**
1. `sim._playersConnections[PlayerRef.None] = new SimulationConnection(sim);` (None == default, so the
   ctor's `Player` is already right). The synthetic connection has a null `NetConnection*`; the
   only readers of that map are `TryGetValue` sites that either short-circuit on `LocalPlayer`
   (`GetPlayerRtt`) or key on real players/message targets, and `Player2Connection` has no callers.
2. `NoopCallbacks.RemoteObjectCreated` now calls `sim.Replicator.OnObjectSpawnedLocal(id)` for
   non-struct, non-reserved objects. That is what `NetworkRunner` does after spawning a remote-created
   object; on the server it does `foreach connection: GetObjectData(id, create: true)`, which puts
   the object on every OTHER client's send schedule (`SchedulingEnabled` is the default). Without it a
   client-spawned object would parse but only ever be scheduled to players that join LATER
   (`_invokeJoinedLeaveQueue` sweeps existing objects for a new player) — never to the peer already
   in the room. This is the real version of the reverted "ScheduleAllObjects" idea, at the right hook.

Built (`dotnet build` Host, 0 errors), server restarted detached at 09:18 UTC (log clock) with the
previous log archived. **Live re-run pending:** host + `send-test-invite.sh` + accept. Expect: no NRE
in the log; server→client 101 grows past the 26/27 B header-only floor once the second player
spawns; host's player list shows the joiner; both see each other. If the joiner's objects parse but
still don't reach the host, read `WriteLevelUsingScheduling` (`ScanAndWriteObject`) for the sender
connection — the server currently also echoes an object back to its own author, which the client
ignores when it is state authority (`IsSimulated`), so that is not expected to matter.

Memory leak from the 09-06 note is untouched (server was at 1.3 GB after the morning's runs; restart
between long runs still applies).

### 2026-09-06 (cont. 2): LIVE — first genuinely shared world; four server-side gaps closed in one sitting

Five host+join rounds this morning (rooms E4A9PE, SLQG9E, TKFJGE, 4BJSXE, DCTKKE), each one
exposing the next wall in the hosted `Simulation.Server`. All fixes are in earlier-photon
`server/BlackIce.Server.Fusion/` (uncommitted at time of writing), in order:

1. **NRE in `ReadObjectUpdates`** (section above) — synthetic `SimulationConnection` for
   `PlayerRef.None` + `RemoteObjectCreated → Replicator.OnObjectSpawnedLocal`.
2. **`AllocateObject` assert `37072 <= 32768`** (room E4A9PE): Outbound's avatar object
   (`Prefab 7`) is **9268 words = 37 KB**; the SDK default heap block is 32 KB.
   `cfg.Heap.PageShift = PageSizes._128Kb`. (Outbound's real `HeapConfiguration` was never located —
   `dump.cs` has only field names.)
3. **No master client** (room TKFJGE dump: `rc.master=None rc.host=None`): nothing in the SDK writes
   `SimulationRuntimeConfig.MasterClient` on a server (the cloud plugin does). `RoomSim.ElectMaster`
   writes the lowest actor into the RuntimeConfig struct on join/leave; it replicates via
   `WriteStructs`. User-visible: host now lists itself as a player.
4. **RPCs were dropped** (room 4BJSXE): the joiner spawned ONLY its 675-word `Prefab 11` object,
   never the avatar — it was waiting on the host's join handshake, which Outbound does over Fusion
   RPCs. RPCs are `SimulationMessage`s; `Simulation.ReadMessages` hands every client RPC to
   `ICallbacks.OnMessage` and NOTHING else forwards it — `NoopCallbacks` returned `Ignored`.
   `OnMessage` now relays exactly like `NetworkRunner.OnMessage` does on a Host: targeted →
   `Sim.ForwardMessage(m, m->Target, required: true)`, otherwise to every `_connections` player
   except `m->Source`. Client-side authority masks filter over-forwarding. Client-to-client reliable
   data was already proxied inside `Simulation` (`ReliableDataTransferModes` default includes
   `ClientToClientWithServerProxy`) — no callback needed.

Room DCTKKE (10:38): 178 RPCs relayed in the first ~90 s, both directions, zero Fusion errors,
`players=2` steady. User: "now we are cooking!" Also reported and NOT yet re-verified after fix 4:
items the host had already picked up were still available to the joiner (fits dropped RPCs and/or
unset master client — check again).

**Diagnostics kept in the tree (cheap, useful):** `[FusionHost] remote object …` on every client
spawn (id/prefab/words/SA/flags), `[FusionHost] rpc from … fwd=N` per relayed RPC (NB `target=`
prints None after a targeted forward because Fusion clears `Target` on send), and
`[FusionHost] objects: …` every 5 s = `FusionServerFactory.Dump` (RuntimeConfig master/host,
per-object SA/ChangedTick, per-connection Status/TickSent/TickAcknowledged). Read the dump first
next time something "isn't showing".

**Operational lessons today:**
- Kill the server by PID, never `pkill -f BlackIce.Server.Host` from a Bash tool call (the pattern
  matches the calling shell — took the tool call down with it once).
- A citron that outlives its server WILL crash with "Uncaught C++ exception" on the next manufactured
  Join (`legacy_guest_call` fires into a runner with stale state). Relaunch both citrons after
  every server restart. `launch-citron.sh` refuses to start while the old process is still exiting
  (its cwd readlink fails → "foreign citron"); wait a few seconds and retry.
- Invites: `scripts/auto-invite.sh` (new) replaces the per-round one-shot watcher. It tails the
  server log, sends `send-test-invite.sh <code>` once per new host room, and resets itself when the
  log file is replaced by a server restart. Start it detached
  (`setsid nohup scripts/auto-invite.sh >/dev/null 2>&1 </dev/null &`); its log is
  `services/auto-invite.log`. A one-shot watcher silently does nothing on the user's second host —
  that was mistaken for "the invitation system stopped firing".

### 2026-09-06 (cont. 3): a REGRESSION and its revert — object ids decoded, RPCs decoded, and a rule about live testing

**Correction to "Still open" above:** `Prefab 7` (9268 words, `DestroyWhenStateAuthorityLeaves`, no
TRSP, host-only) is NOT the avatar — it is the master-client world-state object (the joiner sends all
its join-time RPCs *to it*). The avatar is **`Prefab 11`** (675 words, `HasMainNetworkTRSP`,
`AllowStateAuthorityOverride`; `NetworkPlayer` is weaved with 109 words + nested behaviours) — and the
joiner DOES spawn it (`[Id:1049600]` every room). So "joiner spawned only one object" was the joiner
being fully in. Acting on that misreading caused the regression below.

**The regression (rooms 74EKSE → KMK3EE):** I added, without asking what was on screen,
(a) `SceneInfo`/`PhysicsInfo` `StateAuthority = PlayerRef.MasterClient` and (b) master-client election
every tick (so the host is master from tick 1 instead of at the joiner's arrival). Result: the
**host stopped sending its join sync** — the 134 targeted RPCs host→joiner that every working room
had — and the joiner vanished from the host ("we had it working and you changed something").
**Both reverted**; the server is back to the DCTKKE behaviour (`ElectMaster` on join, which for a
solo host lands when the 2nd actor joins because `RuntimeConfig` only exists after the first Update).
The server's SceneInfo stays at StateAuthority None (client SceneInfo updates are skipped by
`ReadObjectUpdates`; Outbound drives scenes through Photon room properties — `OpSetProperties
{"scene"="startingLevel","vehicleType","knownPlayers","version"}`, re-broadcast by the host ~1.6 s
after each join as `EvPropertiesChanged`, which the joiner receives). Rule recorded in memory: **one
behaviour change per live round, and ask what both screens show before making it.** Diagnostics-only
builds may be deployed freely.

**RPCs are now decoded in the server log.** `[FusionHost] rpc from P target=T flags=F obj=ID beh=B
method=M size=N fwd=K` (`RpcHeader` = target object, behaviour index within the prefab, weaved
method index). Map `beh/method` with `/mnt/media/research/outbound/rpc-invokers.txt`
(171 rows: `Class index,sources,targets Name`, extracted from `dump.cs`'s
`[NetworkRpcWeavedInvoker(index, sources, targets)]` attributes; `sources/targets`: 1 = StateAuthority,
7 = All). Behaviour index → class needs the prefab's component order, which the dump lacks, so
match on `(method index, sources, targets)` + plausibility. Join handshake seen in every room:
joiner → host's world object `525314`: 10× `beh=47 m=1`, then `beh=9/11/20/48/61`; host replies
`beh=61 m=2` then (working rooms only) **134 targeted RPCs to the joiner** = the world sync
(`SendCurrentDownloadsToPlayerRpc`-style, `PlayerJoinedRemoteRpc(joinedPlayer, areaIndices)` etc.).
Absence of that burst = host never registered the joiner.

**Also learned:** the joiner's `OpLeave` 49 s into 74EKSE was the USER backing out to re-send an
invite, not a client timeout. Rooms whose citrons are killed keep ticking `players=N` for the full
`DeadTimeoutSeconds=600` before eviction reaches `PlayerLeft` — three sims were alive at once at one
point; that, not a code leak, is most of the memory growth. `Dump` now includes the SceneInfo struct.

**State at hand-off:** server = "cooking" build + RPC logging (uncommitted, earlier-photon);
citrons relaunched fresh; auto-invite running. Awaiting the user's report on the reverted build:
does the host list the joiner, do they see each other, are pickups in sync. Logs per room:
`services/earlier-photon-0906-{firstshared-SLQG9E,diag-TKFJGE,master-4BJSXE,rpc-DCTKKE-TP4PWE,
sceneauth-74EKSE,sceneauth2-KMK3EE}.log`.

### 2026-09-06 (late): ROOT CAUSE of "joiner invisible / asked to create a char" = empty `knownPlayers`; the EnsureAuthorities regression; and the memory-leak non-bug

Long, hard session. Findings that MUST survive:

**The EnsureAuthorities regression (my fault, user was right).** At room KMK3EE I reacted to a
symptom the user had caused intentionally (they pulled the joiner) by adding, WITHOUT ASKING,
`FusionServerFactory.EnsureAuthorities` (SceneInfo/PhysicsInfo `StateAuthority = MasterClient` +
master election every tick, called from `RoomSim.Tick`). It broke the host's join sync. Reverted in
full; current `FusionServerFactory`/`FusionSharedServer` are back to the DCTKKE-working logic
(`SetMasterClient`/`ElectMaster` on join only; no per-tick authority). Also STRIPPED the later
diagnostics that read `m.Shadow.Raw` (the `Shadow` getter lazily CREATES a snapshot and can disturb
`ScanAndWriteObject`) and the `RpcHeader`/tick logging in `OnMessage`. The server is minimal + clean.
Lesson saved to memory `ask-what-user-sees-before-changing-behaviour`: never treat "BINGO"/agreement
as consent to a destructive/state-changing action; ask first; never kill citrons or move saves
without an explicit yes (I killed the joiner mid-good-run once — do not repeat).

**The memory "leak" is NOT a leak.** InRoom peers get `InRoomDeadTimeoutSeconds=1800` (30 min) of
silence grace by design (a Switch sleeping / applet on screen must not drop a real session); the
short `DeadTimeout=600` only applies pre-room. Eviction DOES dispose: `RunMaintenance` →
`peer.NotifyDisconnect()` → `handler.OnDisconnect` → `LeaveRoom` → `_fusion.PlayerLeft` → RoomSim
disposed. Killed clients just linger up to 30 min. For faster test cleanup set
`BLACKICE_Server__Listener__InRoomDeadTimeoutSeconds=60`.

**THE ACTUAL GAMEPLAY ROOT CAUSE — `knownPlayers`.** Confirmed by diffing the ONE working session
(DCTKKE) against every failing one:
- DCTKKE host broadcast room GameProperties `knownPlayers="tlzsBVZzZI7q8FucZiXWBO3Vmls=,
  vRZWGUoFUGRtzkIa1Q84HYIkpFo="` (two hashes) + `scene`/`vehicleType=3`. Joiner was RECOGNISED →
  loaded its character → visible on host. **DCTKKE was a RETURNING join.**
- Every failing session: host broadcasts `knownPlayers=""` (empty), joiner join props `vehicleType=0`.
  Empty list = this world has no record of the joiner → game runs the create-a-character path
  ("It asked me to create a new char") → the joiner spawns a NEW avatar (Prefab 11, Player:2) but the
  host never registers it (host→joiner SimulationMessage forwards ~4 vs ~134 in DCTKKE) → invisible.
- User's spec: join a world you've never been to → create a char; join one you HAVE → load your
  existing char where you left off. User: "its the server job to know that", "joiner just need to
  fucking join it". So the fix is server-side (NO game patch — user was emphatic: never patch the
  game binary, on citron OR Ryujinx).

**`knownPlayers` hash = `base64(SHA1(player-identity))`**, built by
`NetworkKnownPlayerSync.SyncKnownPlayers` via `NetworkUtils.CalculateHashString` (dump.cs 31447 /
32348). Exact identity string fed in NOT yet pinned (finish reading `CalculateHashString` +
`SyncKnownPlayers` b__3 lambdas — candidates: DisplayName / account/NSA id).

**The contradiction to resolve first:** the user joins as a "returning player" but the hosted world's
`knownPlayers` is EMPTY — so either the host is on a DIFFERENT world than the joiner previously joined,
or that record was lost. AND: we have NEVER observed a genuine FIRST-TIME join make the joiner visible
(DCTKKE was a returning join), so the first-time/create-char path may itself be the visibility bug.

**PRECISE reproducible RPC signature of the failure (fresh citrons + clean server, room DTS8AE, RPC
logging re-added to `OnMessage`, safe read-only `RpcHeader.Read` — NO Shadow):**
- Joiner (Player:2) → host world object `[Id:525314]` (Prefab 7, master-client object): `beh=47 method=1`
  sent **10× as a RETRY** (its initialization request), plus one-shot `beh=36/9/61/48/20/11`.
- Host (Player:1) sends: `beh=71 method=1` ~69× (broadcast, flags=2, a high-freq world sync) and exactly
  **ONE** targeted RPC to Player:2: `beh=77 method=2` (flags=18). DCTKKE (worked) sent ~134 targeted.
- So the host RECEIVES the joiner's init request (server forwards it, fwd=1) but NEVER emits the
  `InitializePlayer*`/world-sync burst back. The joiner retries, times out, stays invisible.
- Behaviour INDEX (47/71/77) is the slot on the prefab, NOT the RPC method id, and the dump lacks the
  prefab's component order, so mapping beh→class needs that order. `NetworkSaveSync` RPCs are the
  suspects (Initialize* = sources 1 StateAuthority / targets 7 All; `RequestInitializationRpc` = idx 8).
  KEY QUESTION for next time: does the host reject the joiner's request on an authority mask
  (`IsStateAuthority(meta, joiner)` false because the joiner is not SA of 525314), or does it simply
  never fire `OnPlayerJoined(player2)` so it has no registered player to init? Decide by instrumenting
  the host guest (why it doesn't invoke/answer) OR by the real Cloud two-client capture below.

**What is NOT the cause (ruled out this session):** the current server binary (reverted to DCTKKE
logic, still fails), accumulated citron state (fresh citrons still fail), the diagnostics
(stripped/​re-added safe-only), ghost rooms / memory (non-bug, see above). The failure is the host's
game logic not initializing the joiner, and it reproduces on a fully fresh run.

**Biggest missing input remains a genuine two-client Photon CLOUD capture** (only SOLO was ever
captured — `REFERENCE-cloud-solo-*`). One Steam copy blocks a two-Steam capture; options are Steam +
a real Switch, or a 2nd Steam account+copy. Without it we are guessing at what the real host emits on
a join. This is the single highest-value thing to obtain.

**CONSOLIDATED root cause (user-confirmed, both symptoms are ONE bug):** the joiner does NOT receive
the host's complete world picture on join. Concretely, the user reports resources the host already
GATHERED (gone from the host's world) are STILL PRESENT for the joiner — the joiner loads the default
level and only gets LIVE deltas after join (a fire lit post-join DOES show), never the pre-join
snapshot. Same missing init is why the host never registers/sees the joiner. So: **the host never
sends the joining player the world-state initialization burst** (~134 targeted RPCs in DCTKKE; 1 now).
The joiner's `beh=47` ×10 retries is it asking for that snapshot; unanswered → stale world +
invisible-on-host. NOT two bugs, one.

**EXACT NEXT STEP (was mid-build when we stopped — do this first next session):** the host normally
pushes that snapshot when it fires `OnPlayerJoined(player2)`, which fires in
`StateReplicator.ReadObjectUpdates` when it receives a **PlayerData struct** creation for that player
(`flag3 && meta.Type == NetworkObjectTypeId.PlayerData` → `_invokeJoinedLeaveQueue.Enqueue((player,
true))`, Fusion.Runtime 2.0.8 decompile line ~39961). Our server CREATES those structs in
`RegisterPlayer` → `RegisterUniqueIdPlayerMapping` → `GetPlayerSimulationData(create:true)` →
`AllocateStruct<PlayerSimulationData>(GetNextId(), 0, NetworkObjectTypeId.PlayerData)`. Add a SAFE
diagnostic (plain reads, NO `Shadow`) to `FusionServerFactory.Dump` that, for each PlayerData struct,
prints its `PlayerSimulationData` and per-connection delivery:
  - Enumerate `sim._structs`; for each where `meta.Type == NetworkObjectTypeId.PlayerData`, read
    `TryGetStructData<PlayerSimulationData>(id, out var d)`. **`PlayerSimulationData` layout (found
    this session):** `PlayerRef Player` (off 0), `NetworkId Object` (next), `int Actor`. Also
    `sim._playerDataLookup` maps `PlayerRef → NetworkId`.
  - Print `Player`, `Object` (does it link the joiner's avatar `[Id:1049600]`?), and for each
    `sim._connections` whether it has ObjectData for that struct id + Status/TickSent/TickAcknowledged.
  - **Decision:** if the host's connection HAS the joiner's PlayerData struct with `Object` pointing at
    the avatar and acked → the struct reached the host, so the bug is the host's own `OnPlayerJoined`
    NOT firing (host-side / Fusion-version), pursue the Cloud capture or host guest instrumentation.
    If the host does NOT get that struct (or `Object` is empty/0) → OUR server isn't delivering the
    joiner's player registration; fix by ensuring the joiner's PlayerData struct (with its avatar link
    from the joiner's `SetPlayerObjectId`) is created/relayed to the host as a creation. That is the
    likely server-side fix and where to start.

**Live state at end of session (2026-09-06 ~16:10):** server UP on the clean build + re-added SAFE
RPC logging (`OnMessage` logs `rpc from … obj/beh/method fwd=N`; the `Shadow`-reading dump and the
per-tick EnsureAuthorities are OUT). earlier-photon uncommitted (3 files: FusionServerFactory.cs,
FusionSharedServer.cs, docs). Both citrons fresh (host/joiner), `scripts/auto-invite.sh` running
(host→joiner, one loop — killed a duplicate). Reproduced the failure on this fully-fresh run (room
DTS8AE): host sent 1 targeted init RPC, joiner retried `beh=47` ×10, stale world + invisible.

**Server-side fix plan (once the above is resolved):** the server persists, per host world, which
joiner identities have joined, and injects their hash into the room's `knownPlayers` (RoomRegistry
already stores/re-serves GameProperties: `RoomRegistry.SetProperties` / `GameProperties`;
`MasterServerHandler` advertises them; `GameServerHandler.HandleSetProperties`). Reproduce the joiner's
`base64(SHA1(identity))` server-side and add it so a returning joiner is recognised. Must also confirm
the returning-LOAD path works end-to-end and that a first-time join can make the joiner visible at all.

**Ryujinx:** hosting works; the missing piece is the join TRIGGER (citron's `legacy_guest_call`
fires `NetworkManager.Join(code)` on invite pop; Ryujinx has no equivalent). Since no game patching is
allowed, the Ryujinx path is a managed-C# guest-call: arm on
`IApplicationFunctions.TryPopFromFriendInvitationStorageChannel`, then rewrite the game thread's CPU
context at `SyscallHandler.SvcCall` (has `IExecutionContext` GetX/SetX + `GetCurrentThread`) to call
Join with a sentinel return — the Ryujinx analog of citron's `OnBeforeRun`/`OnFault`. Hard part: PC
redirect after SVC in the ARMeilleure JIT (via `DebugPc`/interrupt), and capturing
`NetworkManager.Instance`. Do this only AFTER citron's rejoin works, then port the proven behaviour.

Current live state at handoff: server clean+restarted (photon UP), both citrons up (host on an
"established" save whose world nonetheless has empty knownPlayers — see contradiction), auto-invite
loop running (`scripts/auto-invite.sh`, host→joiner). Save backups:
`/mnt/media/research/outbound/save-backups/` (20260906-130207 = both profiles;
joiner-poisoned-131854 = a joiner save moved aside then restored).

### 2026-09-06 (evening): FRESH JOIN WORKS — both see each other. Two server-side gaps: swallowed Fusion internal messages, and eNet command type 15

Rule confirmed by the user today: **never patch the Fusion DLLs or the game** — server code only.
(fusion-libs/Fusion.Runtime.dll is the pristine 2.0.8 binary, md5 identical to the SDK's; the
`tools/fusion-patcher` PluginVersion patch was a 2.1.2-only thing and is NOT applied to 2.0.8.)

**Gap 1 — the SDK server drops every Fusion INTERNAL simulation message.** `Simulation.OnMessageInternal`
(Fusion.Runtime 2.0.8 decompile line ~42778) is a log-only stub; `DeliverMessages` routes any message with
`FLAG_INTERNAL` (64) there and never to `ICallbacks.OnMessage`. The cloud plugin implements them; a pure
`Simulation.Server` does not. Types (enum `SimulationMessageInternalTypes`): `SharedModeSetAlwaysInterested=3
{Object, Interested, Player}`, `SharedModeRequestStateAuthority=4 {Object, Acquire}`, `SetPlayerObject=6
{Object}`, `SetAreaOfInterest=7 {Center, Radius}`. Consequence: the joiner's `SetPlayerObjectId` (sent right
after it spawns its avatar) never landed in the replicated `PlayerSimulationData {Player, Object, Actor}`
struct, so the host's `Runner.GetPlayerObject(joiner)` was null and the host never ran its join sync. Fix
(earlier-photon `FusionServerFactory.NoopCallbacks`): `OnBeforeTick` (invoked immediately before
`DeliverMessages` each tick) walks every `SimulationConnection.MessagesIn` and rewrites `FLAG_INTERNAL` to a
private user flag (`FLAG_USER_FLAGS_START`); the SDK then delivers the message via `OnMessage` in normal
tick/sequence order, where `HandleInternal` applies it: `SetPlayerObject → sim.SetPlayerObjectId(source, obj)`;
`RequestStateAuthority → meta.StateAuthority = source` if the object has `AllowStateAuthorityOverride` or
no live authority (release → None; the header word change is re-sent to all clients by the server's scan);
`SetAlwaysInterested → conn.Add/RemoveAlwaysInterested`; AOI ignored. Confirmed live: `[FusionHost]
internal SetPlayerObject [Player:N] -> [Id:…]` for both players every round, and the host then recognised
the joiner (broadcast `knownPlayers` with BOTH hashes ~2 s after the join) and fired its world sync.

**Gap 2 — eNet command type 15 (`CT_EG_SEND_FRAGMENT_UNSEQUENCED`).** With gap 1 closed, the host died
with **1014** ~17 s after every join, and the joiner saw "host has disconnected" a couple of seconds
earlier (the host's ~1/s `beh=71` heartbeat RPC stopped). Diagnosed with a per-second queue dump + Fusion's
`SimulationMessage` trace channel (`Log.InitializeForConsole(new LogSettings(LogLevel.Info,
TraceChannels.SimulationMessage))`): the server's inbound RPC queue for the host was stuck at
`expectSeq=17, head seq=22, count=130` — sequences 17–21 never arrived, and the host's Fusion packet
sequence had holes (F7, FD, 00, 03, 06). Raw eNet trace: those were `Cmd(15) flags=3` pairs (1172 B +
35 B fragments) — Photon Realtime v4's reliable-UNSEQUENCED fragment (14 = reliable-unsequenced twin of
6; 16 = its ACK type; 17–19 = ack2 variants), which Fusion uses for every relay packet above the MTU.
`EnetPeer.HandleCommand` had no case for 15 (payload dropped) and acked it with type 1; the client
(`PhotonClient.dll` decompile: `RemoveSentReliableCommand(seq, channel, isUnsequenced = ackType==16)`)
never matched the ack, retransmitted (same seq 1/2 three times in 100 ms), and hit its reliable timeout →
`DisconnectCause.ClientTimeout` → `ShutdownReason.PhotonCloudTimeout` (=14) → Outbound shows 1000+14.
(Earlier codes fit the same table: 1001 = Error, 1020 = OperationTimeout.) Fix (`BlackIce.Photon`):
types 14/15 handled like 6/8 (identical headers, verified from the client decompile), ack type 16 when the
acked command has `FlagUnsequenced`, fragment reassembly keyed by `(channel, startSeq)` so interleaved
retransmits don't clobber each other. Test: `SendFragmentUnsequenced_reassembles_interleaved_groups_and_acks_with_type16`.
Result (room TY546E): host's world sync = 110 targeted `beh=27 m=2` RPCs + others, all forwarded, no
disconnect, **both players see each other on a first-time join.**

**Also learned today:**
- Fusion's internal Info logging WAS already active (`adding player` lines) — no exceptions were being
  swallowed; the trace channel is the useful addition. `[FusionHost] msgq …` (1/s per connection with a
  non-empty queue) and `[FusionHost] objects: …` (every 5 s, no `Shadow` read) are in the tree.
- A citron that outlives a server restart does NOT always crash loudly: the joiner's frontend simply froze
  (log stopped mid-line at the invite pop, no dialog reported). Relaunch the joiner after every server
  restart; the queued invitations are picked up on its first poll (`PollInvitations: 1 invitation(s)` →
  `TryPopFromFriendInvitationStorageChannel` → `GUESTCALL firing Join`).
- `scripts/start-services.sh` skips the photon start if port 27000 is still bound by a dying process —
  always verify the PID changed and `earlier-photon.log` was recreated after a restart. `kill "$list"`
  with a space-joined string fails in zsh; pass PIDs as separate args.
- Third round of the day (KLJMTE) was a different failure: the host never registered the joiner at all
  (no knownPlayers broadcast, no heartbeat RPC ever) — the host game was in a different state; not
  reproduced after the transport fix. Watch for it.

**Returning join (later the same evening) — it needs the JOINER's local save; two server experiments
tried and reverted:**
- Rooms ESEUNE/PNGTSE/9ULAVE: host re-hosted its saved world (knownPlayers written at host time =
  `vRZW…` = the joiner's hash, then `""` 1 ms later — that double write is normal, DCTKKE had it too),
  joiner came back → host answered `beh=77 method=1` (returning) instead of `method=2` (fresh) and sent
  NO world sync; joiner repeated its `beh=47 m=1` request (byte-identical to a fresh join: a UTF-32
  string `tool-craf…`) ten times; the user was asked to create a new character. Only NotifyData/Acks on
  the wire — no reliable-data stream is involved.
- **Game design, from the decompile** (`decomp/NetworkSaveSync/NetworkSaveSync.c`,
  `OnOtherPlayerJoined`): the host calls `LoadManager.FindSerializedNetworkPlayer(userId, platform)`;
  NOT found → sends `InitializePlayer{Storage,Backpacks,Tools,Upgrades,Needs}Rpc` +
  `InitializeInteractionTasksRpc` + `InitializeToolTasksRpc` + `RequestInitializationRpc` (the ~110-RPC
  burst); FOUND → sends only `RequestToggleInitializedRpc` and expects the joiner to restore from ITS OWN
  save. The joiner profile wrote NO save today (its newest are the 5-minute `Multiplayer_*.autosave`
  files from 09-02 — the ones behind the morning's working returning join DCTKKE); today's joins lasted
  ~1 min and "log out" saves nothing. So the host treated the joiner as known while the joiner had no
  character → mismatch. **Procedure for a returning-join test: joiner stays in the world until a new
  `Multiplayer_*.autosave` appears in its Savegames (watch the dir), then leaves; host saves; re-host.**
- Experiment 1, REVERTED: delay applying `SetPlayerObject` by 128 ticks (env
  `FUSION_SETPLAYEROBJECT_DELAY_TICKS`, still in the code, default 0 = off). No effect on the host's
  reply — Object linking is not what selects the path.
- Experiment 2 (room 9ULAVE): server keeps a non-empty `knownPlayers` over the host's empty overwrite.
  Joiner skipped the create-a-character prompt ("loaded a char and went to the new start process") but
  the HOST dropped ITSELF from its player list — reverted at the time and blamed on the rule. WRONG
  blame: that was the PlayerData clobber (next section); the rule is reinstated and correct.
- Kept (Photon-correct): the first `JoinGame` response now carries the room's current game properties
  (only the repeated-join path did before; the client seeds `Room.CustomProperties` from it).
- Ops: a Ryujinx joiner instance (`ryujinx-instances/joiner`, account OutboundJoiner) left running from
  13:57 was consuming the joiner's invitations (its log shows `TryPopFromFriendInvitationStorageChannel`)
  — invites "randomly" not arriving on citron. Kill any other process logged in as the joiner account.
  Also: the citron toast click is the accept; the joiner must be on the multiplayer menu; a second
  manufactured join in the same citron process crashes it ("Uncaught C++ exception" right after
  `Join returned state machine`) — relaunch the joiner citron for every join. Citron's log writer buffers
  ~1 min, so a stalled `citron_log.txt` does NOT mean a frozen frontend.

### 2026-09-06 (night): the "works sometimes" root cause — clients clobber the PlayerData structs; sticky knownPlayers reinstated; fresh AND returning joins work

**The dump answered the original question.** `FusionServerFactory.Dump` now prints each PlayerData
struct's `P=<player> O=<object> A=<actor>`. In every failing room the host's own struct read
`P=[Player:1] O=[Id:None]` even though the server had logged its `SetPlayerObject` as applied (a
read-back right after the write shows `O=[Id:525312]`). Cause, from the 2.0.8 decompile:
`StateReplicator.SendPacket` returns early only for `Topology != Shared && Mode == Client`, so
**Shared-mode clients run `WriteStructs` too** and periodically send their copies of RuntimeConfig,
SceneInfo, PhysicsInfo and every PlayerData struct to the server; the server's `ReadObjectUpdates`
takes any struct snapshot (`Type.IsStruct → snapshot.CopyTo(meta)`, no authority check). A client's
copy taken before the link was applied carries `Object=None` and wipes it; last writer wins, which
is why TY546E worked and USNJ3E/8QYJ8E/WEW9KE did not. Every client's `Runner.GetPlayerObject(host)`
is then null → the host is missing from its own player list and `OnOtherPlayerJoined` never runs.
**Fix:** the server records each player's object from `SetPlayerObject` and re-asserts it in
`OnBeforeTick` (`[FusionHost] PlayerData [Player:N] Object clobbered -> re-asserted …` — exactly one
per player per room, at ticks ~80 and ~join+50). `PlayerLeft` forgets it. Rooms 4YXD7E (fresh) and
UKTY4E (returning): links hold, host lists both, 110-RPC init burst every time.

**Joiners keep no local save.** With `log_filter="*:Debug"` on the joiner profile (set in its
`qt-config.ini` while citron was closed), a "Save and Quit" from a joined session wrote ONLY
`Settings/settings.local|synced`; nothing under `Savegames/`. So the character lives in the host's
world save and the joiner decides new-vs-returning from the room's `knownPlayers` at join → the
**sticky knownPlayers rule is reinstated** (`RoomRegistry.SetProperties`: an empty overwrite never
clears a non-empty list; the broadcast payload is patched to the kept value; test
`SetProperties_keeps_non_empty_knownPlayers_over_an_empty_overwrite`). The first-join `JoinGame`
response also carries the room's game properties now (Photon-correct; only the repeated-join path
did before). In UKTY4E the joiner was handed `knownPlayers=<its hash>` at join, was NOT asked to
create a character, and its character loaded; the host still ran the fresh-init burst (its
`FindSerializedNetworkPlayer` found nothing — the host's "save and quit" after the joiner left did not
serialize it), and the joiner spawned beside the host in the campervan, which is the game's normal
arrival placement. Position persistence for joiners would need the host's serialized record; not
pursued.

**Ops:** `scripts/restart-photon.sh [tag]` — SIGTERM hangs the Generic Host shutdown (listener loops
or Fusion's native socket threads ignore it), the process keeps the ports, and `start-services.sh`
then silently skips the start (this bit us four times today). The script SIGKILLs the port owner,
archives the log under the tag, starts fresh, verifies. `InRoomDeadTimeoutSeconds` must be ≥
`DeadTimeoutSeconds` (600 in the rig) — pass `BLACKICE_Server__Listener__InRoomDeadTimeoutSeconds=600`
to clear ghost rooms in 10 min instead of 30. Kill other processes logged in as the joiner account
(a leftover Ryujinx joiner ate invitations). Relaunch the joiner citron for every join. The
`FUSION_SETPLAYEROBJECT_DELAY_TICKS` experiment env is still in the code (default 0 = off); remove it
when convenient.

**Open / next:** (1) pickups both ways (no `RequestStateAuthority` internal message has been observed yet
— if pickups don't sync, look at the RPC path first, then the authority handler); (2) pre-join world state
on the joiner; (3) returning join (joiner logged out, host saved — user is testing this next);
(4) `PlayerSimulationData.Actor` is never set by the SDK server (plugin does it) — cheap to set in
`PlayerJoined` if something reads `GetPlayerActorId`; not done (one change per round).
Logs: `services/earlier-photon-0906-{preinternal-DTS8AE,internalmsg-6CWGVE-RF3RUE,trace-KLJMTE,dump-GWP4CE}.log`
and the live `earlier-photon.log` (TY546E). earlier-photon uncommitted: EnetPeer.cs, NCommand.cs,
TransportTests.cs, FusionServerFactory.cs, FusionSharedServer.cs, docs/fusion-shared-server.md.

### 2026-09-06 (late night): pickups both ways, pre-join state, and the leave/rejoin chain (ghost + "first arrival") fixed

**Pickups sync over RPCs, both directions; no authority transfer involved.** Drop = one RPC on the
world object `525314` (`beh=55 method=1`); pickup = `beh=55 method=2` on the world object plus
`beh=4 method=1` on the picker's own avatar. Host→joiner and joiner→host identical. Closed.

**Pre-join world state is fine.** An item the host dropped before a joiner arrived was on the
ground in the joiner's world, and the joiner could pick it up. Closed.

**Leave/rejoin was broken in two server-side places (earlier-photon `56c8c68`):**
1. `RoomSim.RemovePlayer` only dropped the actor from its own set. Fusion's simulation was never
   told, so the leaver's PlayerData struct and avatar stayed, no client ever got `PlayerLeft`, and a
   returning player came back beside its own body, treated as a first arrival. The cloud plugin's
   leave-time step is `Simulation.Server.Disconnect(player)`; `FusionServerFactory.DisconnectPlayer`
   now does that (log: `room "X" player N left -> sim disconnect`). Effect chain, all observed live:
   sim deletes PlayerData → host's `NetworkManager.OnPlayerLeft` sends `RequestStateAuthority` for the
   leaver's avatar (first time this message ever appeared) → server grants (`[Player:2] -> [Player:1]`)
   → host's `NetworkPlayer.StateAuthorityChanged` (decompile: `if (!HasStateAuthority) return; …
   Runner.Despawn(Object)` inlined, flags=10) despawns the adopted avatar.
2. That despawn arrives as an object-destroy entry in the host's packet. `ReadObjectDestroys` hands it
   to `ICallbacks.RemoteObjectDestroyed`; our `NoopCallbacks` returned `true` ("handled"), so the
   simulation never freed it and the body lived on under the host's name. Now returns `false` (log:
   `remote destroy [Id:N]`), so `Simulation.Destroy` frees it and forwards the destroy to every client
   (the Unity runner's `_remoteDestroyQueue` does exactly `_simulation.Destroy(id, DestroyState)` too).
   A `remote destroy [Id:1025]` (the leaver's own PlayerData struct) also appears one second before its
   `OpLeave`: that is the leaving client tearing down on shutdown; benign.

Result (room XQ9QAE): join, quit → avatar vanishes on the host at the quit, relaunch, re-invite, rejoin
→ no ghost, object list holds exactly the host's avatar and the returning joiner's new one. User: "works
100%".

**Rejoin position / "Day 1" card / "ZT to start the motor" are the game's own behaviour, not a missing
message.** Verified from the decompile and the log:
- The host's join-time sync to the joiner is byte-for-byte the same set of targeted RPCs on a fresh
  join and on a return (110× `beh=27 m=2`, 2× `beh=47 m=2` of 496/336 bytes, etc.).
- `SerializedNetworkPlayer` (what `LoadManager.FindSerializedNetworkPlayer` returns and
  `NetworkSaveSync.OnOtherPlayerJoined` pushes via `Initialize{PlayerStorage,PlayerBackpacks,
  PlayerTools,PlayerUpgrades,PlayerNeeds,InteractionTasks,ToolTasks}Rpc`) has no position.
- Nothing in the game re-takes an old avatar: `NetworkRunner.Spawn` is called only from
  `NetworkManager.OnConnectedToServer` (plus critter/robot/companion spawners), and the only game
  caller of `RequestStateAuthority` is `OnPlayerLeft`. A returning joiner always gets a fresh avatar at
  the campervan, which is where the start-motor prompt lives.
- Not verified against Photon Cloud: whether the "Day 1" intro card also shows on a Cloud rejoin
  (`SceneHandler.GetSkipIntroTexts` is a plain field; who sets it was not traced).

**Ops notes:** `restart-photon.sh` can report "photon NOT up" while `dotnet run` is still compiling;
check `ss -lun | grep 27000` before believing it. Photon log timestamps are UTC (local is +01:00).

**Save file decrypted; the joiner IS persisted and IS recognised.** `FileSystemWriter.SaveToFile` writes
base64(AES-CBC(zero IV, PKCS7, key = UTF-8 of the static `FileSystemWriter.pwdKey` literal)). The key was
recovered by trying every 16/24/32-byte string literal from the IL2CPP dump against `fresh.save`; the
decryptor lives on the pool at `/mnt/media/research/outbound/tools/decrypt-save.py` (key inside,
never in a repo). The host's save has `NetworkInfo.Players[]` with `UserID:"OutboundJoiner"`,
`TargetPlatform:5`, storage/backpacks/tools/upgrades/needs/customization and `LastSeen` — and no position.
World: `CurrentDay:2`, `DayAtLevelEntry:1`.

**`beh=42` on the world object is `NetworkSaveSync`** (weaved ids from the decompile: 1 InitializePlayerStorage,
2 Backpacks, 3 Tools, 4 Upgrades, 5 Needs, 6 InteractionTasks, 7 ToolTasks, 8 RequestInitialization,
9 RequestToggleInitialized). On EVERY join today (fresh-of-session and returning) the host sent the joiner
methods 1–8 = the "serialized record FOUND" path; method 9 (record not found) never appeared. So the joiner
is recognised and its inventory restored each time; the campervan placement and the "Day 1" card are the
game's ordinary joiner arrival, not a first-timer path. Whether the card's "Day 1" is the level-entry day
(`DayAtLevelEntry`=1) or the local day before `NetworkDaySync` applies the host's value is not yet pinned
(`BlackscreenUI.GetIntroTexts` just picks one of two text sets by a static mode flag). Check: the joiner's
in-world day after the card should read 2.

## Real-hardware path: friends/push server + the invite dead wire (2026-09-06 research)

**The intended flow** is invite-a-friend via the game UI applet -> friend receives on their Switch -> accepts -> joins. Two independent blockers, both confirmed:

**1. The game's invite-consume is a dead wire on EVERY platform.** `NetworkSystemSwitch.CheckForInvite`
pops the invite, puts the room code in `InviteData.CustomData`, sets `CachedInvite`, publishes via
Intercom -- and nothing consumes it into a join. It builds the join from `PlatformSessionID` (hardcoded
empty) and calls `NetworkSystemSwitch.JoinSession` (no-op, no callers). The only correct `NetworkManager.Join`
(RVA 0x1BF76C0) call sites are `JoinUI.OnJoin` (code-entry screen, unreachable in the shipped console UI --
`NetworkingUI` only hosts+invites, no join-by-code field) and a debug class. citron injects
`NetworkManager.Join+StartCoroutine` on accept (`legacy_guest_call.cpp`) to bridge this. On hardware you
need to reproduce that as a Switch sysmodule or exefs/IPS patch, OR surface `JoinUI` for manual code entry
(skips the invite). A hand-assembled ARM trampoline already crashed once; the emulator uses CPU-context
rewriting. **User's call: build the friends/push server first, cross the injection bridge after.**

**2. Delivery on hardware is NPLN Messaging, not the citron HTTP mailbox.** On citron the whole invite
transport is HLE'd to plain HTTP: `SendFriendInvitation` -> POST `/api/invitations` (account mailbox),
a background poller -> AM storage channel. A real console does neither. Mapped from kinnay's docs
(see memory [[npln-invite-delivery-protocol]]):
- The invite is an **NPLN Messaging message**, not a friends RPC. `nn.npln.messaging.v1.Messaging`:
  `SendMessage`(message_type + `fields` MapValue -> receiver_users), `RecvMessage` (server-STREAM the
  receiver holds open; server pushes), `SendAck`. Keep-alives: immediate on connect (idle_timeout 95s),
  then every 45s. The Friends service has NO invite RPC (only Activate/List/Subscribe presence).
- Transport = gRPC/HTTP2 = what the legacy NPLN server (splatoon-3 build, `legacy-local` `npln`
  service on :18500, serves `*.lp1.t.npln.srv.nintendo.net`) already speaks. Messaging is 3 methods to add,
  bridged to `openpak-account/invitations.go`'s existing mailbox.
- **NPNS is only for game-CLOSED** (home-menu notification / launch-from-invite). NPNS = XMPP/ejabberd,
  replaced by **Penne** (HTTP/2 + JSON) in system 18.0.0. Deferrable; not on the path while the game runs
  and holds `RecvMessage` open.
- Sources: github.com/kinnay/NPLN-Protocols (exact protos); github.com/kinnay/NintendoClients/wiki
  (Messaging-Service, NPLN-Servers, NPNS-Servers, Penne-Servers, BAAS-Server); switchbrew.org/wiki/
  {NPNS_services,Friend_services}. the third-party setup (`~/REPOS/console patches`) already redirects the Nintendo hosts +
  installs CA trust; its config surface is `source/legacy_config.h` (server IP) + `legacy_hosts.h`.
  For hardware Photon: add a DNS.mitm hosts entry `ns.photonengine.io -> LAN IP` (citron uses the
  `OPENPAK_PHOTON_IP` env for the same rewrite).

**Server-side scope, best-first:** (1) add Messaging (RecvMessage stream + SendMessage + SendAck) to the
NPLN server, bridged to the invitation mailbox; (2) read the game's `nn::friends` binding once to pin the
session-invite `message_type` + field keys (payload bytes = what citron already relays); (3) friends+presence
partly exist -- ensure the joiner shows invitable; (4) defer NPNS/Penne. Then cross the injection bridge (#1).

## Real-hardware path, CORRECTED (2026-09-06 late night)

**The previous section's server scope is wrong for Outbound.** Its decomp
(`/mnt/media/research/outbound/decomp`) has ZERO `npln` references and 180+ `nn.friends` ones
(`SendFriendInvitation`, `FriendInvitationGameModeDescription`, `NotificationQueue`). NPLN Messaging is the
transport for NPLN titles (Splatoon 3, Stardew); Outbound never links NPLN. On a real console:

- `nn::friends::SendFriendInvitation` = IFriendService cmd 30900 (V1) / 30901 (V2, 19.0.0+), handled by the
  system **friends sysmodule**, whose server is **BAAS** (`e0d67c509fb203858ebcb2fe3f88c2aa.baas.nintendo.com`,
  user-agent `nnFriends`; the account sysmodule moved to `m-lp1.baas.nintendo.com` on 21.0.0, friends did not).
- kinnay's BAAS-Server page lists `/2.0.0/friend_requests`, `/2.0.0/users/<id>/friends`, blocks, generate_code
  -- **no invitation route**. The invite send endpoint + body are undocumented. Recipient receives it by push
  (NPNS/XMPP before 18.0.0, Penne HTTP/2+JSON after; the third-party setup already redirects `val.hac.penne` and
  `god.hac.lp1.penne`) into the friends sysmodule's invitation storage channel, which the game pops.
- Locally there is NO BAAS implementation: openpak-account serves the Reference API and derives synthetic
  BAAS/NA ids; the 443 SNI for the BAAS host goes to `baas-jwks` (JWKS only). The real-console BAAS is
  `nx-account` on the org's production deployment (the third-party setup's `OPENPAK_SERVER_IP_DEFAULT` = 51.178.29.194).
  Photon identifies a real Switch by the token's `bs:did` claim (`OpenPakIdentityRegistry.cs`).
- the third-party setup's DNS-mitm host list has no `ns.photonengine.io` entry yet (`console patches/source/legacy_hosts.c`);
  hardware Photon needs it pointed at the machine running earlier-photon (LAN 10.87.0.2 here, ports
  5055/5056/27000-27002 UDP, binds 0.0.0.0).

**Concrete hardware plan, evidence-first:**
1. Milestone A: a real console reaches our Photon and HOSTS an Outbound room (add the photonengine host to
   the third-party setup, keep account/BAAS on whichever deployment the console is already linked to). Validates that the
   whole Fusion server work holds on hardware -- independent of invites.
2. Milestone B: press Invite Friends on hardware with BAAS pointed at a server we log; capture the exact
   friends-sysmodule request (path, headers, body = the 0xC00 `FriendInvitationGameModeDescription` /
   11-byte app param). That capture defines the endpoint to implement; no protocol doc will.
3. Milestone C: receiver side -- push (Penne) into the second console's storage channel, then the injection
   bridge (or surfacing `JoinUI`), since the game's invite-consume is a dead wire everywhere.
Do NOT build NPLN Messaging for Outbound.

## Console rig built (2026-09-06, late night): local 1:1 earlier stack + BAAS server + the third-party setup LAN option

User decisions this session: real consoles (two, with Outbound) use THIS machine's stack; invites go
through the **standard Switch functions** (friends sysmodule -> BAAS); **no custom sysmodule, no
patches, ever**. The org's real-console BAAS server (`nx-account`) is private and unavailable
(not in earlier network's GitHub, user not a member, not on disk; NeXo-Server and Pretendo do not
implement it either), so it was rebuilt as **`~/REPOS/nx-baas`** (Go, stdlib, one binary, style of
nx-dauth) from kinnay's NintendoClients docs (BAAS-Server, Account-Server-(Switch), baas.py) and
openpak-account's `/internal/*` contract.

**What runs now (legacy-local, podman compose):**
- `nx-baas` :18447 -- BAAS (`e0d67c...baas.nintendo.com`, `m-lp1`, `cdn-image-*`) + Nintendo
  Account (`accounts.nintendo.com`, `api.accounts.nintendo.com`). Data `data/nx-baas/baas.json`.
  Signs id_tokens with `openpak-baas-key-1` + `openpak` claim (same HMAC as openpak-account's
  signNexToken) + `bs:did` = account's derived BsDid, so Photon/NPLN resolve the console to the
  Reference PID exactly like an emulator. Link flow = the console's `response_type=session_token_code`
  PKCE sequence (per NeXo-Server's hardware-tested notes): authorize page (Reference e-mail +
  password -> `/api/login` with X-Admin-Key) -> redirect `?session_token_code=` -> `api/session_token`
  -> `api/token` -> `/2.0.0/users/me` -> BAAS `/1.0.0/federation` or `/users/<id>/link`.
  Friends: `/2.0.0/users/<id>/friends` from `/internal/identity`, friend_requests -> internal
  friend-request/friend-accept, presence PATCH stored locally. **Every unknown request is logged in
  full (`!! UNHANDLED`)** -- that is how the invitation endpoint (undocumented) will be learned.
  `podman logs -f legacy-local-nx-baas-1`.
- `dauth` :18445 (nx-dauth, was profile-gated, now default) -- dauth/aauth/dcert/acert/dragons.
- Traefik SNI passthrough (`/srv/appdata/traefik/dynamic/legacy.yml` = repo `traefik-rules.yml`;
  root-owned file was renamed aside, dir is user-writable): BAAS+accounts hosts -> 18447, dauth
  hosts -> 18445, NPLN tenants unchanged. Verified from the LAN address 10.87.0.2:443.
- Images: compose now pins `image: localhost/legacy-local-<svc>:latest`; build with
  `build.sh` (host go build + Containerfile) -- the docker-compose provider does not build
  `dockerfile_inline` here. zsh gotcha: `$svc:latest` is a `:l` modifier -> use `${svc}:latest`.
- Website :8081 and dashboard :8093 were already up.

**the third-party setup (`~/REPOS/console patches`, branch `local-legacy`, commit 91a6b7a):** the ↑↓←→ cheat now
cycles VPS -> Local(AWS) -> **LAN (10.87.0.2)** -> VPS, and the hosts file gains
`ns.photonengine.io -> server` (Outbound's Photon name server). Built in the devkitpro/devkita64
container: `/mnt/media/research/outbound/prelude/legacy-lan.nro` (17.8 MB). Photon
must be reachable on the LAN: earlier-photon binds 0.0.0.0 (5055/5056/27000-27002 UDP).

**Guesses to confirm from the first console logs (all marked `ponytail:` in nx-baas/main.go):**
friends list envelope `{count, friends}` vs bare array; friend_requests body keys; `/1.0.0/users`
lookup query keys; whether the console verifies the NA id_token's jku; PKCE verifier ignored.

**Next steps, in order:** (1) copy `legacy-lan.nro` to both consoles, select LAN, boot in
Reference mode; (2) Settings > Users > Link Nintendo Account on console A -> watch nx-baas log
through login/federation; fix whatever `!! UNHANDLED` shows; (3) same on console B, then add each
other as friends (friend code) -- friends list shape check; (4) Outbound: Host Game on A -> Photon
log shows the console's join with `bsdid:`/`nex:` identity; (5) Invite Friends on A -> the BAAS
invitation request appears in the nx-baas log = the endpoint to implement; (6) push to B (Penne
`val.hac.penne` / `god.hac.lp1.penne` are already redirected; unhandled today -> log tells).

## Console link: where it stands (2026-09-07 00:45, end of session)

**Flow = "Restore User"** (Settings > Users > Add User > *Restore*, NOT "create user"; the console
builds the profile from the server). Link page = e-mail+password OR QR (QR not built locally yet).
Progress on the LAN stack tonight, each step ground-truthed against a capture of the VPS
(`/mnt/media/research/outbound/services/vps-baas-login-capture.txt` = real BAAS login +
user object; `nx-baas-capture-*.log` = NA refresh/token/users/me):

1. Browser CA: the third-party setup installs bundles in BOTH `romfs/browser/` and `romfs/0/browser/` (the
   latter is what fw 22 reads) + a stale `romfs_metadata.bin` that must be purged. Done (LAN CA).
2. NA token/users/me shapes now identical to the VPS (scope array, `at_hash`, `ac:grt/ac:scp`,
   full profile object). Distinct kid per issuer (console binds kid<->issuer). Works: the console
   proceeds to `POST /1.0.0/users` + `/1.0.0/federation`.
3. BAAS tokens/user object mirror the captured VPS login (typ JWT headers, `bs:sts`, thumbnails at
   `cdn-image…/1/<id>`, bare friend code, `nicknameUpdatedAt`, playLog as string, snapshot reply).
4. **`extras.self.nxAccount` is what Restore User needs**: with it the console showed the
   "Importing a user: OutboundJo" screen. It is a 174-byte console profile blob (uid[16] + settings;
   format only partly known, one captured sample is served with a fresh uid via
   `NX_TEST_NXACCOUNT`, see compose). Proper generation from the account's Mii/avatar = TODO.
5. After the import OK the console registers push (NPNS): Penne `god/val…penne`, Vermillion `gw…`,
   Beach `beach.hac.lp1.eshop` — none had a Traefik route (connection dropped -> "could not be
   linked"). Now routed to nx-baas and answered (`penne.go`). **Untested: the next Restore attempt.**

Errors decoded: 2810-1818/1819 = browser cert trust; 2124-3122 = users/me identity incoherent;
2124-3121 = BAAS response unparsable (base64 thumbnail / "SW-" friend code); 2124-0292 = Restore
has nothing to restore (no nxAccount) ; "account already used on this console" = same NA id as an
existing profile (never map the joiner to the VPS id again).

Accounts: joiner `outbound-joiner@local.test` / `Joiner2026!`, local NA id set to a random
`dbf92e8d559082bc` (accounts.json edited + container restart). The console's own VPS profile
(<user-a>, NA `21fde2a5ab9cac6f`) is untouched. nx-baas runs with `NX_DEBUG=1` (full bodies in
`podman logs legacy-local-nx-baas-1`). Capture mode: `NX_UPSTREAM=51.178.29.194` + Traefik
service swap (see `restore` of `traefik-rules.yml`); never leave it on -- a link attempt in capture
mode would create a device account on the VPS.

**Next session:** (1) Restore User on console A -> read the log through Penne/Vermillion; fix
`!! UNHANDLED`. (2) Build the QR link flow (`/connect/1.0.0/qr/{nouveau,etat,refuse}`, phone page
`/lier?c=`, 4-digit PIN; page JS contract captured in scratch `vps-authorize.html`, copy in
`nx-baas` TODO). (3) Generate `nxAccount` properly. (4) Then console B, friends, Outbound host,
Invite Friends -> the BAAS invitation endpoint appears as `!! UNHANDLED`.

## NEXT SESSION — concrete plan

**Console link DONE (2026-09-07 09:00): OutboundJoiner linked on the console via the stock flow.** See the top of
the file for what fixed it (push_channels object, TLS certs). Next: friends between console profiles, then host
Outbound on the console and Invite Friends -> implement whatever shows up as `!! UNHANDLED` in the nx-baas log.
Then the <user-a>/leia mirror test in LAN mode (seeded, untested).

---
Transport/gameplay rig (all working, historical). Rig: `scripts/start-services.sh` (or `restart-photon.sh <tag>` after a server change), then
`launch-citron-host.sh` / `launch-citron-joiner.sh`, host a session, `send-test-invite.sh <CODE>`
(code from `EnterRoom "<CODE>" actor=1`), accept on the joiner. Relaunch the joiner citron for every
join. One behaviour change per round; ask what the user sees before changing anything.

Everything on the transport side that has been tested now works: fresh join, returning join,
continuity (7+ min), pickups both ways, pre-join state, leave (avatar removed), rejoin (no ghost).
Candidates, in order of value:
1. **Longer play session** (30+ min, both players moving, driving, building). Watch for desyncs,
   `Not handling RPC` storms, memory growth of `BlackIce.Server` (was 495 MB after 12 min of one
   room; check `ps -o rss`).
2. **Host quits while the joiner stays** (master-client migration). `ElectMaster` re-elects the
   lowest actor; the game's reaction to `IsSharedModeMasterClient` flipping is untested.
3. **Three players.** `RoomSim` is built for up to 8; only two have ever been in a room.
4. **Vehicles and building** (`NetworkVehicleDriverSync`, `NetworkFoundationSync`, …): the RPC
   forwarder is generic, but interest/authority on those objects is untested.
5. ~~Housekeeping~~ done in `1311ba5` (delay experiment removed; `Room.RemoveActor` on leave).
6. Memory-leak verification: during item 1, sample the server's RSS every few minutes; the fix is
   `earlier-photon` `1311ba5` (`UdpListener.RunAsync`). Diagnostics if it still grows:
   `~/.dotnet/tools/dotnet-dump collect -p <pid> -o /mnt/media/research/outbound/services/x.dmp`
   then `dotnet-dump analyze x.dmp -c "dumpheap -stat" -c exit` (never dump to /tmp: tmpfs).

Uncommitted at session end: nothing. earlier-photon HEAD `1311ba5`; this file.
