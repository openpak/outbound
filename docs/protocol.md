# Protocol: outbound

Outbound does not use Nintendo NEX for its multiplayer transport. Live testing
confirmed that it uses Photon Realtime/Fusion: the client connects to Photon’s
Name Server, negotiates payload encryption, and submits Nintendo Switch custom
authentication. The existing provider rejects Citron’s replacement BAAS token.

## Confirmed game identity

- Base title ID `0100ED9024EB8000`; update tested `0.6.0` (raw version `393216`).
- Engine: Unity + Photon Fusion (Fusion 2.0.8, Shared mode).
- Photon Name Server `ns.photonengine.io`; UDP ports observed `5058` and `27000`.
- Authentication operation `230` (`Authenticate`); the stock provider answers `32755`
  (`CustomAuthenticationFailed`) to a replacement token.
- Photon App ID `cffbe809-5036-43d8-84a1-7bf16c924721` (wire trace + RomFS metadata, see
  [research.md](research.md#app-id-recovery)).
