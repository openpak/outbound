# Deploy: outbound

Research and test rig for **Outbound** online support in the OpenPak stack. The
server it drives is [`photon`](../../photon) (OpenPak.Server); the account side is
whatever container stack `scripts/start-services.sh` is pointed at
(`OUTBOUND_STACK_DIR`, still a local container set until OpenPak has its own compose).
