# Outbound — Reference Photon compatibility service

Research and implementation workspace for adding **Outbound** online support to
earlier network.

Outbound does not use Nintendo NEX for its multiplayer transport. Live testing
confirmed that it uses Photon Realtime/Fusion: the client connects to Photon’s
Name Server, negotiates payload encryption, and submits Nintendo Switch custom
authentication. The existing provider rejects Citron’s replacement BAAS token.

## Confirmed game identity

- Base title ID: `0100ED9024EB8000`
- Update tested: `0.6.0` (raw version `393216`)
- Photon Name Server: `ns.photonengine.io`
- Photon UDP ports observed: `5058` and `27000`
- Authentication operation: `230` (`Authenticate`)
- Authentication result: `32755` (`CustomAuthenticationFailed`)
- Engine: Unity + **Photon Fusion**
- Photon App ID: `cffbe809-5036-43d8-84a1-7bf16c924721` (confirmed via wire
  trace + RomFS metadata, see [`docs/research.md`](docs/research.md#app-id-recovery))

## Status

Superseded research below; the live state is in [`HANDOFF.md`](HANDOFF.md).
In short: Photon Cloud's built-in `NintendoSwitch` auth provider can never
accept a replacement token, so the project runs Outbound against the
self-hosted [`earlier-photon`](../earlier-photon) server (citron redirect
`OPENPAK_PHOTON_IP`) plus the `legacy-local` account stack. That server
hosts Fusion's own Shared-mode `Simulation.Server` per room (headless, from
the game's exact Fusion 2.0.8 build). As of 2026-09-06 two citron players
share one world: fresh and returning joins both work, objects, RPCs and room
properties are relayed, and both players see each other (see the dated sections
at the end of `HANDOFF.md`; `restart-photon.sh` restarts the server reliably).
Testing scripts live in `scripts/` (start with `start-services.sh`, then the
two `launch-citron-*.sh` wrappers; `auto-invite.sh` sends the joiner an invite
for every room the host opens). We must not commit tokens, keys, account
data, copyrighted game material or production infrastructure.

## Initial workflow

1. Decode only the non-secret fields of Outbound’s Photon Authenticate request.
2. Create a test Photon application isolated from the retail application.
3. Implement a small Go authentication endpoint that maps a valid Reference
   identity to a stable Photon user ID.
4. Redirect or runtime-patch Outbound to the test App ID.
5. Verify Name Server → Master Server → Game Server transitions.
6. Test room creation, discovery, joining, leaving and reconnecting.
7. Evaluate a fully self-hosted Photon-compatible transport only after the
   proof of concept demonstrates that the game’s room/event logic works.

See [`docs/research.md`](docs/research.md) for the evidence log.

