# Outbound Reference — development handoff

Last updated: 2026-08-28 (self-hosted server: GetRegions + encryption fix +
alt port implemented; cross-tested against Outbound on Steam — real Steam
auth succeeds cleanly, but a still-unidentified 13-byte packet to the Master
server blocks the connection on both Steam and Switch)

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

### Current blocker: unidentified packet to the Master server

Immediately after a successful `GetRegions` (within ~6ms), the client opens
a *separate* connection to the Master address we handed back and sends a
13-byte UDP packet: `7D 7D 7D 7D 7D 7D 7D 7D 7D 7D 7D 7D <varies>` — twelve
`0x7D` bytes then one differing trailing byte. This does **not** match the
real Photon `Connect` command seen everywhere else in this investigation
(`FF FF 00 01 ... 02 FF 01 04 ...`). Parsed through `PhotonHeader.ReadFrom`
it decodes to nonsense (`CommandCount=125`, `ServerTime=2105376125`) and
zero commands, so our server sends no reply at all.

The client **retries this exact packet 5 times, ~1.2s apart**, gets nothing
back either time, then goes silent (the connection is later evicted after
10s of inbound silence, on our side). This retry-then-give-up timing lines
up with when "A Photon error has occurred" appears, on both the Steam and
Switch clients. Confirmed reproducible: the same shape occurred both times
the Steam client was tested independently.

**Ruled out:** it isn't Steam-specific network noise unrelated to Photon —
the timing (6ms after `GetRegions` succeeds) is too tight to be coincidence.

**Not yet known:** what this packet actually is. Candidates considered but
unconfirmed: a lightweight NAT "punch"/reachability probe Photon's client
sends before a full connect (content is low-entropy/repeated, which fits a
throwaway probe better than real protocol data or ciphertext — real AES
output wouldn't repeat a byte 12 times); a CRC-enabled packet whose header
layout differs from the CRC-disabled one `PhotonHeader.ReadFrom` always
assumes (it's the *only* `crc=true` packet seen in the entire investigation,
every other exchange — all of which work — was `crc=false`); or something
from a different subsystem entirely. Web search turned up no public
documentation of this packet shape.

### Reproducing this investigation

- Server: `cd earlier-photon && DOTNET_ROLL_FORWARD=LatestMajor
  BLACKICE_Server__Ports__NameServerAlt=27000 dotnet run --project
  server/BlackIce.Server.Host -- 127.0.0.1 --trace` (`--trace` for full
  packet hex dumps, needed to see the Master-port packet's raw bytes).
- Switch (Citron): `OPENPAK_PHOTON_IP=127.0.0.1 ./build/use-nopgo/bin/citron`.
- Steam: `echo "127.0.0.1 ns.photonengine.io" | sudo tee -a /etc/hosts`,
  launch Outbound normally, **remove the hosts line afterward**.

### Next step

Identify the Master-port packet. Either: find independent documentation/
source of this exact shape, get the official Photon .NET SDK (needs a
Photon account login — `photonengine.com/en-US/Realtime/Download` — to run
this codebase's existing but never-yet-used oracle test harness in
`BlackIce.Photon.Tests`, which would validate the whole wire codec against
the real library, not just this one packet), or find a Photon Fusion/
Realtime PC game with source or a debug/verbose logging mode that shows
what this exchange is meant to accomplish. Only after this resolves does
real earlier identity verification become relevant (replacing the current
accept-all anonymous-LAN stance) — `authbridge`'s role would then either
get absorbed into this server or stay as a separate verification call it
makes internally.

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

