# Protocol: outbound

Outbound does not use Nintendo NEX for its multiplayer transport. Live testing
confirmed that it uses Photon Realtime/Fusion: the client connects to Photon’s
Name Server, negotiates payload encryption, and submits Nintendo Switch custom
authentication. The existing provider rejects Citron’s replacement BAAS token.
