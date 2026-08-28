# Outbound Reference — development handoff

Last updated: 2026-08-28 (retail rejection reason decoded; test-app blocker open)

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

### Next step

Figure out what's different about Outbound's real `Authenticate` request
that a real Photon SDK client doesn't do. Leads, in rough order of promise:

- Whether Outbound sends its custom-auth token as binary
  `ClientAuthenticationData` vs. a string `ClientAuthenticationParams` —
  untested against a real compiled SDK (only tested via `photon-realtime`'s
  own possibly-imperfect binary serialization, which isn't conclusive).
- The client's `AppVersion` (looks empty in the shipped `PhotonAppSettings`
  asset) — try patching a non-empty value via `appidmod`-style same-length-or-
  offset-aware editing, or test whether an empty AppVersion trips anything
  via `photon-realtime`.
- Decrypting Outbound's actual encrypted failure response is **not possible
  from a passive capture** — Diffie-Hellman specifically prevents that. It
  would require hooking Outbound's own compiled Fusion code at runtime to
  read the AES key as generated, a materially more invasive step not
  attempted yet.

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

