# Outbound Reference — development handoff

Last updated: 2026-08-29 (four real server-side bugs found and fixed this
session against the live Switch/Citron client — missing eNet fragment
reassembly, lobby-name scoping, ad-hoc room rejection, missing
MasterClientId — classic Photon LoadBalancing now completes end-to-end for a
real Switch client; new confirmed blocker is one layer up, in Fusion's own
proprietary session-bootstrap protocol)

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

### Current confirmed blocker: Fusion's own session-bootstrap protocol

Immediately after the Game-server `JoinGame` succeeds, the client sends its
first Fusion-layer message: `OpRaiseEvent` with event code `100` ("protocol
package" — see the `RegisterProtocolMsg` table above; a 28-byte
`CustomEventContent` payload, almost certainly a `Join` message given it's
sent right after entering the room). Our server has no logic that
understands or replies to this — `GameServerHandler` only does generic
classic-Photon event relay, and there's no other real peer in the room to
relay it to even if it tried. The client waits **~30 seconds**, gets no
response, then cleanly calls `OpLeave` and disconnects — Citron shows
**"connection interrupted (1020)"**, a new/different code from the earlier
failures, consistent with this being a distinct, later-stage wall.

This is the expected shape of the problem: a real Photon Server needs
Photon's separate, commercial **Fusion plugin** (not just the classic
LoadBalancing application) to understand and drive this session-bootstrap
exchange — we don't have that plugin's source, only the client-side
decompiled `Fusion.Runtime`/`Fusion.Sockets`. Implementing it will require
protocol inference rather than a spec.

### Next step

1. Implement enough server-side handling of `RegisterProtocolMsg` code `100`
   (`Join`, per the table above) to complete a **solo-host** bootstrap — no
   second real peer needed yet, just whatever handshake Fusion's own client
   logic is waiting to see before it stops blocking on `StartGameOperation`
   (`Fusion.Runtime`, decompiled, `StartGameModeCloud`). Two ways to get the
   exact expected byte layout, in order of reliability:
   - **Preferred:** repeat today's proven technique — cross-test against
     Outbound on Steam (same App ID, same Fusion protocol, much faster
     iteration than Citron) against **real, unredirected Photon Cloud**, and
     capture the actual server-side response bytes to compare against our
     own `--trace` output byte-for-byte. This is exactly how the port and
     lobby-scoping bugs were solved today — it beats blind protocol
     inference every time it's been tried.
   - Fallback: infer the minimal valid reply purely from the decompiled
     client logic (`AsyncOperationHandler<ShutdownReason>` /
     `StartGameOperation.Task` completion conditions in `Fusion.Runtime`,
     around `StartGameModeCloud`), without a real capture to verify against.
2. Once a solo host completes the bootstrap and reaches gameplay, then
   implement enough of `ReflexiveInfo`/`Start`/`PlayerRefMapping` for a
   **second** real client to actually join — this needs a genuine two-peer
   test (two Switches, or one Switch + one Steam client, both against our
   server).
3. Only after gameplay-level connectivity works for 2+ peers does real
   earlier identity verification become relevant (replacing the current
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

