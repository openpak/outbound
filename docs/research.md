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

## Retail rejection reason (confirmed)

Citron's plaintext `op230` (Authenticate) failure response carries more than
the 3-byte op/return-code header already decoded above: a GpBinaryV16 string
value (type `0x07`, length-prefixed) directly follows it — Photon's
`DebugMessage`. Decoded from a live capture:

```
op230_rest[29] = 07 1a "Nintendo validation failed" 00
                 ^^ ^^                                ^^
                 |  |                                 paramCount=0 (no further params)
                 |  length (26)
                 GpBinary type=String
```

**`"Nintendo validation failed"`.** This confirms the retail app's real
custom-authentication backend does receive and evaluate Citron's replacement
BAAS token — it's Nintendo's own account-service-side validation of that
token that rejects it, not Photon, not DNS/UDP, not the app configuration.
This matches the project's original assumption and is why the plan has
always been a OpenPak-controlled Photon app + auth bridge rather than
patching the retail flow. No crypto/decryption was needed for this — the
`CustomAuthenticationFailed` response is sent in plaintext by design; only
the first 3 bytes had previously been decoded.

## Test-app investigation (App ID override, proof-of-concept)

Two isolated Photon test apps were created to validate the proof-of-concept
plan (see HANDOFF.md): a Fusion 2 app (`17a9e6d7-594a-443b-9f1e-931da70c3b1c`)
and a Fusion 1 app (`74c7f0c0-7c70-4651-8bcd-420920c2dba4`), swapped in via
the `appidmod`-generated LayeredFS mod (`cmd/appidmod`).

Findings:

- Outbound's client, redirected to either test app, fails identically every
  time: an **encrypted** `op230` OperationResponse with the same body size
  (78 bytes), regardless of Fusion 1 vs Fusion 2, custom-auth
  enabled/disabled/anonymous, or region. `authbridge` never receives a
  request in any of these attempts (confirmed via ngrok's own request
  inspector, not just server-side logs) — the connection is rejected before
  Custom Authentication is ever invoked.
- The test apps and `authbridge` are independently confirmed fully healthy:
  the official `photon-realtime` npm package (Exit Games' own JS SDK,
  WSS transport) connects, authenticates, and joins the lobby against
  `17a9e6d7-...` successfully — both anonymously and with a large
  (~1.9KB) string-encoded custom-auth parameter that correctly invokes
  `authbridge`.
- A same-size (~1.4KB) **binary** `ClientAuthenticationData` payload sent via
  that same JS SDK reproduces the same `32755 CustomAuthenticationFailed`
  code with message `"Authentication data type not supported"` — but this
  is not confirmed to be Outbound's actual failure reason; it may be an
  artifact of this particular JS library's own serialization of a raw byte
  array rather than a genuine server-side rejection of well-formed binary
  auth data from a real compiled SDK. Flagged as a lead, not a conclusion.
- Since Outbound's failure response is encrypted (unlike retail's
  plaintext one), reading its actual DebugMessage would require the AES
  session key — which is derived via Diffie-Hellman and is **not**
  recoverable from a passive packet capture alone (that's the whole point
  of DH: only the two parties who each hold a private exponent, never
  transmitted, can derive it). Decrypting it would require hooking
  Outbound's own compiled Fusion code at runtime to read the key as
  generated, a materially more invasive step not yet attempted.

## Unknowns to resolve

All of the original unknowns were resolved by the self-hosted server work
(root cause: Photon Cloud's built-in `NintendoSwitch` auth provider; the
wire-level answers are in `HANDOFF.md`, "Root cause found" onward). The open
items now live in `HANDOFF.md`'s latest dated section.

## Evidence rules

- Record where every constant came from.
- Redact account/session tokens and personal identifiers from logs and fixtures.
- Do not commit production secrets, certificates, Nintendo code/data or assets.
- Never send Reference or Nintendo credentials to a newly created third-party app.
- Keep inferred values clearly marked until independently confirmed.

