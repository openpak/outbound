# Outbound Photon research

## Confirmed observations

| Item | Value |
| --- | --- |
| Base title ID | `0100ED9024EB8000` |
| Update tested | `0.6.0` (raw `393216`) |
| Name Server | `ns.photonengine.io` |
| UDP ports observed | `5058`, `27000` |
| Photon operation | `230` (`Authenticate`) |
| Return code | `32755` (`CustomAuthenticationFailed`) |
| Auth request size | `1474` bytes, two fragments (`1152` + `322`) |
| BAAS token supplied by Citron | `1398` bytes; value never logged |
| Photon App ID (Fusion) | `cffbe809-5036-43d8-84a1-7bf16c924721` |
| Engine | Unity + Photon Fusion (confirmed via `FusionAppId`/`PhotonAppSettings` symbols in `global-metadata.dat`) |

Citron successfully completes the UDP transport handshake, Photon init and key
exchange. The encrypted Authenticate request is then sent. Photon replies with
a plaintext operation response for operation 230 and return code 32755 before
disconnecting. This places the failure at the application’s configured custom
authentication provider, not DNS, UDP connectivity, graphics, save data, NEX,
or the initial Photon encryption exchange.

The two return-code bytes are `f3 7f`. GpBinaryV18 encodes the value little
endian (`0x7ff3` = `32755`); reading them as V16 big endian produces the misleading
signed value `-3201`.

## App ID recovery

Citron's plaintext Init message (`msg0`) carries the App ID in a fixed
32-byte field. A real Photon App ID GUID is 36 ASCII characters
(`8-4-4-4-12` hex groups), so the wire value is truncated by 4 trailing hex
digits and never matched the original ASCII-hex-only scanner (it also missed
the dashes). Captured truncated value: `cffbe809-5036-43d8-84a1-7bf16c92`.

The same connection's Init header is a constant 7 bytes
(`01 08 1e 41 08 10 00`) across both the Name Server hop (App ID field =
literal `"NameServer"`, Photon's documented sentinel for that hop) and the
game connection — confirming the 32-byte field position and that the Name
Server hop is expected, unrelated behavior.

The full App ID was recovered by extracting Outbound's RomFS via Citron's
"Dump RomFS" feature and searching the IL2CPP `global-metadata.dat` string
table for GUIDs beginning with the truncated prefix, plus the serialized
`PhotonAppSettings` asset in `Data/resources.assets`. Both independently
agree: `cffbe809-5036-43d8-84a1-7bf16c924721`. `resources.assets` shows no
other string value immediately after the App ID for the fields that would
hold `AppVersion`/`FixedRegion` in Photon's `AppSettings` struct, consistent
with those being left at their empty/default values in the project.

## Unknowns to resolve

- App Version sent by the client (likely empty/default `"1.0"` based on the
  serialized `PhotonAppSettings` asset — not yet confirmed on the wire)
- Authentication type and non-secret parameter names
- Whether a test App ID can be supplied through a data-only mod or needs a
  title-scoped Citron runtime override
- Required successful-auth response fields beyond a stable user ID/token
- Master/Game Server room and event behavior used by Outbound
- Whether Photon Cloud is acceptable for proof-of-concept only and what a fully
  self-hosted replacement would require

## Evidence rules

- Record where every constant came from.
- Redact account/session tokens and personal identifiers from logs and fixtures.
- Do not commit production secrets, certificates, Nintendo code/data or assets.
- Never send Reference or Nintendo credentials to a newly created third-party app.
- Keep inferred values clearly marked until independently confirmed.

