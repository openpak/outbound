# Notes: outbound

Former README title: Outbound — OpenPak Photon compatibility service

## Client notice (former README header)

> **Current Switch client (2026-10-13): Harbor**, at
> `~/REPOS/Openpak/emulators/harbor`. Harbor is an independent
> OpenPak project based on Eden. Citron, Ryujinx (desktop and Android), and
> the former OpenPak Eden checkouts have been removed. References to those
> forks below record historical evidence only: do not run their commands,
> reinstall them, or select them for current work. Use Harbor's README and
> current handoff for builds and testing; old results do not establish Harbor parity.

## Status

Superseded research below; the live state is in [`HANDOFF.md`](../next-session.md).
In short: Photon Cloud's built-in `NintendoSwitch` auth provider can never
accept a replacement token, so the project runs Outbound against the
self-hosted [`photon`](../../photon) server (redirected by
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

See [`research.md`](research.md) for the evidence log.

## License

AGPL-3.0-only — see `LICENSE`.
