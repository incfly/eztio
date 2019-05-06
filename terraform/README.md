# Performance Testing for Istio Mesh Expansion

`gce.tf` for the instance setup.

- Setup the gke cluster, with mesh expansion enabled, not integrating with Terraform first.
- Provision the GCE instance, using Terraform.
- GCE instance setup. Can be part of the istio-vm.py subcommands.
  - Unkonwn, the service account mapping.
  - Seems better to use py imperative for now, and do post setup independent of terraform.
- Mesh registration, istio-vm.py temporarily, istioctl finally.
- Run the config and simulate traffic.
- Gather the metrics of the promethus.

## Simplification

- Static service account
- No mTLS between service for simplicity. No policy is needed.
- No RBAC, not helpful. Just remove the `ServiceEntry`. Client side authentication requires RBAC or Cert Revocation List feature from Istio.