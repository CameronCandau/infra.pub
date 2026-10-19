{
  nixpkgs,
  nixpkgs-unstable,
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
    acme = path;
    hosts = {
      canary = path;
      forgejo = path;
      forgejo-runner = path;
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
        module:
        nixosLib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              inventory
              secretFiles
              site
              sops-nix
              ;
            openbaoPackage = nixpkgs-unstable.legacyPackages.${system}.openbao;
          };
          modules = [ module ];
        };
    in
    assert builtins.match domainPattern site.domain != null;
    {
      image = mkSystem ../nixos/image.nix;
      canary = mkSystem ../nixos/hosts/canary;
      forgejo = mkSystem ../nixos/hosts/forgejo;
      haproxy = mkSystem ../nixos/hosts/haproxy;
      bind = mkSystem ../nixos/hosts/bind;
      forgejo-runner = mkSystem ../nixos/hosts/forgejo-runner;
      observability = mkSystem ../nixos/hosts/observability;
      postgres = mkSystem ../nixos/hosts/postgres;
      k3s = mkSystem ../nixos/hosts/k3s;
      openbao = mkSystem ../nixos/hosts/openbao;
    };
in
{
  inherit mkSystems readDomainEnv singleSecretFile;
}
