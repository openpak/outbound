# Outbound

OpenPak's Outbound Server.

| | |
| --- | --- |
| Game | [Outbound](https://openpak.org/titles#t-1) |
| Network | Nintendo Switch |
| Title ID | `0100ED9024EB8000` |
| Licence | AGPL-3.0-only |

## What it serves

| Host | What | Served by |
| --- | --- | --- |
| `ns.photonengine.io` | Photon Name Server hop used by Outbound | [`photon`](https://github.com/openpak/photon) |
| UDP `5058`, `27000` | Photon ports observed in Outbound traffic | [`photon`](https://github.com/openpak/photon) |

## Run

```sh
./scripts/start-services.sh
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `OUTBOUND_STACK_DIR` | `$HOME/REPOS/openpak-local` | Local container set that the script starts |

## Docs

- [Protocol](docs/protocol.md)
- [Evidence](docs/evidence.md)
- [Deploy](docs/deploy.md)
- [Notes](docs/notes.md)
- [Research](docs/research.md)

Live compatibility status: [openpak.org/titles#t-1](https://openpak.org/titles#t-1).

## Licence

AGPL-3.0-only. See [LICENSE](LICENSE).
