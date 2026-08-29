# Outbound Reference — development handoff

Last updated: 2026-08-29 (classic Photon LoadBalancing AND Fusion's session
bootstrap (Join/Confirmation/NetworkConfigSync/Start/relay Connect-Accepted)
all now work end-to-end, ground-truth-verified byte-for-byte against a real
Photon Cloud capture. The full-freeze bug documented below (a second UDP
socket blocking forever in `recvfrom()`) is **fixed and confirmed live**:
the real cause was `SocketImpl` stripping Horizon's `SOCK_NONBLOCK` flag
without applying its semantics, turning Fusion's intended nonblocking poll
into a blocking call. A real Switch + Citron + OpenPak session now hosts
with no freeze. The current wall is the in-game **Invite Friends** flow —
three real citron HLE bugs found and fixed there today too (see "2026-08-29
live control: freeze confirmed fixed" below), but the native invite applet
itself needs an undocumented firmware-20.0.0 struct we don't have a
confirmed layout for; a presence-based join alternative that avoids it
entirely is scoped, not yet started.)

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
