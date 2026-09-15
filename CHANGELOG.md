# Changelog — outbound

Generated from git history on 2026-09-15. `git log` stays the source
of truth; this file is the readable summary.

Note: the early history below is the upstream project (the pre-port earlier project);
OpenPak work starts at the port/fork commit.

## History — no releases tagged yet

- Go 1.26, the house version [cfaaab9]
- Go 1.25 like the rest of the servers; stop tracking the shared-docs symlink [4329153]
- docs: bring outbound's docs in line with what is deployed [e6c75e6]
- HANDOFF: name the QR endpoints in English [dd0b7e8]
- HANDOFF: drop the dev account password from the text [eccb3a2]
- Rig: wait 90s for the server to bind (a first-run rebuild outran the 30s check) [86f77e1]
- HANDOFF: rename server identifiers to OpenPak; rig sets OPENPAK_TITLE_ID [f7eb17c]
- Rig follows the server rename: OPENPAK_* env, OpenPak.Server.Host [485f52f]
- Layout: photon back under Openpak/servers [7aa7838]
- Layout: photon lives at Openpak/middleware/photon [cc0a8bd]
- OpenPak port: AGPL-3.0, openpak/outbound module, rig points at servers/photon [869ac8e]
- docs: frozen nx-baas clone for the earlier stack; OpenPak copy evolves [29d2ae8]
- docs: nx-baas moved to Openpak (AGPL); OpenPak migration decision [b78545c]
- docs: real console hosts, Citron joins -- working end to end; ufw UDP, NameServer LAN handoff, NSO membership, game version [411b599]
- docs: console link works on the LAN stack -- push_channels object + TLS cert fixes; VPS probe recipe [a962d76]
- docs: console-link mirror built and verified (<user-a>+<user-b> seeded in account + nx-baas); first LAN console test is next [b10cd0e]
- docs: console link -- Restore User flow ground-truthed against VPS captures; nxAccount blob, Penne/Vermillion/Beach routing; error-code map [49001ea]
- docs: console rig -- nx-baas (BAAS + Nintendo Account) built and deployed, dauth on, Traefik SNI routes, the third-party setup LAN option; first-console test plan [8849a8e]
- docs: hardware invite path corrected -- Outbound has no NPLN; friends sysmodule -> BAAS, endpoint undocumented; milestone plan [e220b0a]
- docs: server memory leak root-caused and fixed (cancelled UDP receives queue up); housekeeping done [a2c41a1]
- docs: real-hardware path -- invite is NPLN Messaging (gRPC stream, not NPNS), and the game's invite-consume dead wire; server scope + sources [74b91d5]
- docs: save decrypted (tool on pool), joiner record persisted and found on every join; beh=42 = NetworkSaveSync [2d7759d]
- docs: leave/rejoin chain fixed (sim disconnect + client despawn); pickups and pre-join state confirmed; fresh next-session plan [bf9370c]
- docs: fresh and returning joins work; four server gaps root-caused; restart + auto-invite scripts [3e46f38]
- docs: continuity fixed live (7+ min hold); new wall = state replication (server can't parse client objects); 14.4 GB server leak [51c15bb]
- docs: Fusion 2.0.8 rebuild, first two-player in-game session, continuity gap [4b29d42]
- Outbound: two-persona test rig, GameProperties join diagnosis, honest handoff [d8f5611]
- Add kill-targeting rule: kills target by game NSP, never binary path (shared-machine incident) [231fe44]
- Add family-wide Citron Launch Protocol (autonomous when only own instance; ask when other titles run) [8704196]
- docs: Invite Friends flow reaches a real completed send [2097163]
- docs: system-firmware side of cmd 20108 also tried, real dead end confirmed [fd5b6c6]
- docs: confirm FriendImpl layout via real decompile, explain why 20108 isn't in Outbound's binary [d1ac3f0]
- docs: freeze fix confirmed live, Invite Friends crash bugs fixed and scoped next step [ac6c7d1]
- docs: freeze root cause fully diagnosed and confirmed live via gdb [5b5ac44]
- docs: relay handshake implemented, real Citron socket bug fixed [6c0259e]
- docs: document Fusion session bootstrap solved, new wall at event 101 [0f406c1]
- docs: document today's four server fixes and the Fusion protocol wall [7c29747]
- Document Fusion SDK research: own protocol layer beyond classic Photon [67bca34]
- Document self-hosted server progress: GetRegions, encryption fix, Steam cross-test [d401165]
- Document root cause: Photon Cloud's built-in NintendoSwitch auth provider [6077df3]

- … 4 earlier commits omitted (see `git log`)
