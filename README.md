# Homelab infrastructure modules

This repository contains the reusable half of a small, single-host Proxmox homelab. NixOS configures the guests, OpenTofu owns VM and ZITADEL resources, Flux reconciles Kubernetes applications, and SOPS supplies runtime credentials from a separate private repository.

The complete example uses only `example.test`, TEST-NET addresses, and placeholder secrets. It mirrors the deployment shape without publishing a real domain, network, identity, certificate, encrypted payload, or repository coordinate.

## Private inputs

The private deployment pins this repository and supplies:

- an inventory matching `examples/inventory.json`;
- two HAProxy service VIPs for user and administrator remote-access policy;
- a validated domain read from a one-line `DOMAIN=<fqdn>` file;
- ACME contact and Forgejo runner settings;
- SOPS files for each host and ACME;
- provider credentials, state backends, production Kubernetes Secrets, and Flux bootstrap configuration.

`lib.mkSystems` returns all NixOS configurations from those inputs. The OpenTofu modules under `opentofu/modules` accept the same inventory and domain. Kubernetes manifests use strict Flux `${DOMAIN}` substitution.

## Checks

```sh
nix fmt -- --ci
nix flake check
tofu -chdir=examples/opentofu init -backend=false
tofu -chdir=examples/opentofu validate
git diff --check
```

This is intentionally opinionated infrastructure, not a general-purpose framework.
