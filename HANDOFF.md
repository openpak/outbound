# Outbound Reference — development handoff

Last updated: 2026-08-28 (App ID recovered)

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
  init message.

The tracer deliberately does **not** log raw authentication payloads, parameter
values, debug strings, BAAS tokens or encryption material. Packet fingerprints
exist only to correlate retries.

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

## Next step: proof-of-concept

Move to the [proof-of-concept plan](#proof-of-concept-plan) below: stand up a
separate test Photon application, a Go custom-authentication bridge, and a
Citron-side App ID override so Outbound's client talks to the test app
instead of the retail one.

## Proof-of-concept plan

After identifying the client configuration:

1. Create a separate Photon test application. Never alter or depend on the
   retail owner's Photon dashboard/application.
2. Build a small Go custom-authentication endpoint that maps a valid Reference
   identity to a stable Photon user ID.
3. Do not forward a Nintendo or Reference token to the new Photon application.
   Use a scoped, newly issued test credential or a local-only identity during
   the first proof.
4. Add a title-scoped Citron runtime override, or a data-only mod, that replaces
   Outbound's Photon App ID with the test App ID.
5. Verify Name Server → Master Server → Game Server transitions.
6. Test room creation, listing/discovery, joining, leaving and reconnecting with
   two independently authenticated clients.
7. Only after gameplay is proven, decide whether Photon Cloud is acceptable for
   a proof of concept or whether Reference needs a fully self-hosted compatible
   transport. A self-hosted implementation is much larger than the Go auth
   bridge and should not be started before the client flow is demonstrated.

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

