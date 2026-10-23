# Outbound — OpenPak Photon compatibility service

> **Current Switch client (2026-10-13): Harbor**, at
> `~/REPOS/Openpak/emulators/harbor`. Harbor is an independent
> OpenPak project based on Eden. Citron, Ryujinx (desktop and Android), and
> the former OpenPak Eden checkouts have been removed. References to those
> forks below record historical evidence only: do not run their commands,
> reinstall them, or select them for current work. Use Harbor's README and
> current handoff for builds and testing; old results do not establish Harbor parity.

Research and test rig for **Outbound** online support in the OpenPak stack. The
server it drives is [`photon`](../photon) (OpenPak.Server); the account side is
whatever container stack `scripts/start-services.sh` is pointed at
(`OUTBOUND_STACK_DIR`, still a local container set until OpenPak has its own compose).

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

Superseded research below; the live state is in [`HANDOFF.md`](next-session.md).
In short: Photon Cloud's built-in `NintendoSwitch` auth provider can never
accept a replacement token, so the project runs Outbound against the
self-hosted [`photon`](../photon) server (redirected by
the emulator's DNS override) plus the local account stack. That server
hosts Fusion's own Shared-mode `Simulation.Server` per room (headless, from
the game's exact Fusion 2.0.8 build). As of 2026-09-06 two citron players
share one world: fresh and returning joins, leaving (avatar removed) and
rejoining, pickups both ways and pre-join world state all work (see the dated sections
at the end of `HANDOFF.md`; `restart-photon.sh` restarts the server reliably).
Testing scripts live in `scripts/` (start with `start-services.sh`;
`auto-invite.sh` sends the joiner an invite for every room the host opens).
The two players are two machines — the persona launch wrappers were retired
2026-09-26. We must not commit tokens, keys, account
data, copyrighted game material or production infrastructure.

## Initial workflow

1. Decode only the non-secret fields of Outbound’s Photon Authenticate request.
2. Create a test Photon application isolated from the retail application.
3. Implement a small Go authentication endpoint that maps a valid OpenPak
   identity to a stable Photon user ID.
4. Redirect or runtime-patch Outbound to the test App ID.
5. Verify Name Server → Master Server → Game Server transitions.
6. Test room creation, discovery, joining, leaving and reconnecting.
7. Evaluate a fully self-hosted Photon-compatible transport only after the
   proof of concept demonstrates that the game’s room/event logic works.

See [`docs/research.md`](docs/research.md) for the evidence log.

## License

AGPL-3.0-only — see `LICENSE`.

