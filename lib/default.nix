{
  nixpkgs,
  nixpkgs-unstable,
  disko,
  sops-nix,
  system,
}:
let
  lib = nixpkgs.lib;
  domainPattern = "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+";
  readDomainEnv =
    path:
    let
      line = lib.removeSuffix "\n" (builtins.readFile path);
      match = builtins.match "DOMAIN=(${domainPattern})" line;
    in
    if match == null || builtins.stringLength (builtins.head match) > 253 then
      throw "${toString path} must contain exactly DOMAIN=<lowercase-fqdn>"
    else
      builtins.head match;
  singleSecretFile = path: {
    backupStorage = path;
    acme = path;
    hosts = {
      canary = path;
      forgejo = path;
      forgejo-runner = path;
      identity = path;
      k3s = path;
      observability = path;
      openbao = path;
      postgres = path;
    };
  };
  mkSystems =
    {
      inventory,
      secretFiles,
      site,
    }:
    let
      machineAddresses = map (machine: machine.address) (builtins.attrValues inventory.machines);
      nixosLib = lib.extend (
        final: previous: {
          mkRenamedOptionModuleWith =
            args:
            if
              args.from == [
                "proxmox"
                "qemuConf"
                "diskSize"
              ]
            then
              previous.doRename {
                inherit (args) from to;
                visible = false;
                warn = true;
                use = final.id;
              }
            else
              previous.mkRenamedOptionModuleWith args;
        }
      );
      mkSystem =
        hostSystem: module:
        nixosLib.nixosSystem {
          system = hostSystem;
          specialArgs = {
            inherit
              disko
              inventory
              secretFiles
              site
              sops-nix
              ;
            openbaoPackage = nixpkgs-unstable.legacyPackages.${hostSystem}.openbao;
          };
          modules = [ module ];
        };
      mkDefaultSystem = mkSystem system;
    in
    assert builtins.match domainPattern site.domain != null;
    assert lib.assertMsg (
      inventory.serviceVips.user != inventory.serviceVips.admin
    ) "service VIPs must be distinct";
    assert lib.assertMsg (
      !builtins.elem inventory.serviceVips.user machineAddresses
      && !builtins.elem inventory.serviceVips.admin machineAddresses
    ) "service VIPs must not match a machine address";
    {
      image = mkDefaultSystem ../nixos/image.nix;
      canary = mkDefaultSystem ../nixos/hosts/canary;
      forgejo = mkDefaultSystem ../nixos/hosts/forgejo;
      haproxy = mkDefaultSystem ../nixos/hosts/haproxy;
      bind = mkDefaultSystem ../nixos/hosts/bind;
      forgejo-runner = mkDefaultSystem ../nixos/hosts/forgejo-runner;
      observability = mkDefaultSystem ../nixos/hosts/observability;
      postgres = mkDefaultSystem ../nixos/hosts/postgres;
      k3s = mkDefaultSystem ../nixos/hosts/k3s;
      openbao = mkDefaultSystem ../nixos/hosts/openbao;
      netbird-router = mkDefaultSystem ../nixos/hosts/netbird-router;
      identity = mkSystem "aarch64-linux" ../nixos/hosts/identity;
    };
in
{
  inherit mkSystems readDomainEnv singleSecretFile;
}
