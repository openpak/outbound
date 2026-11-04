# Deploy: outbound

Research and test rig for **Outbound** online support in the OpenPak stack. The
server it drives is [`photon`](../../photon) (OpenPak.Server); the account side is
whatever container stack `scripts/start-services.sh` is pointed at
(`OUTBOUND_STACK_DIR`, still a local container set until OpenPak has its own compose).

## Architecture

Photon Cloud's built-in `NintendoSwitch` auth provider can never accept a replacement token, so
Outbound runs against the self-hosted [`photon`](../../photon) server (reached by DNS redirect)
plus the local account stack. That server hosts Fusion's own Shared-mode `Simulation.Server` per
room (headless, from the game's exact Fusion 2.0.8 build).

Testing scripts live in `scripts/`: `start-services.sh`, and `auto-invite.sh`, which sends the
joiner an invite for every room the host opens. Two players are two machines. Never commit
tokens, keys, account data, copyrighted game material or production infrastructure.

## Account erasure

`authbridge` serves `DELETE /internal/accounts/{account_id}/data` (`Authorization: Bearer $ACCOUNT_ERASE_KEY`, unset:
503). The bridge keeps no state, so it is a logged no-op returning `{"service":"outbound","rows":0}`.
