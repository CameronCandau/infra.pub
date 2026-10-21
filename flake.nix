{
  description = "Reusable NixOS, OpenTofu, and Flux building blocks for a small Proxmox homelab";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/1e8bc658fc985ef27ccd66d107d767b32bb7ef98";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/e7439b6b14ad3cc35d05608ebca9bce01a25f5f8";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      nixpkgs,
      nixpkgs-unstable,
      disko,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      infraLib = import ./lib {
        inherit
          nixpkgs
          nixpkgs-unstable
          disko
          sops-nix
          system
          ;
      };
      example = infraLib.mkSystems {
        inventory = builtins.fromJSON (builtins.readFile ./examples/inventory.json);
        site = {
          domain = infraLib.readDomainEnv ./examples/domain.env;
          acmeEmail = "admin@example.test";
          forgejoRunnerUuid = "00000000-0000-0000-0000-000000000001";
        };
        secretFiles = infraLib.singleSecretFile ./examples/secrets.yaml;
      };
    in
    {
      lib = infraLib;
      formatter.${system} = pkgs.nixfmt-tree;
      nixosConfigurations = example;
      packages.${system} = {
        default = example.image.config.system.build.VMA;
        proxmox-image = example.image.config.system.build.VMA;
        raw-image = example.image.config.system.build.cloudImage;
      };
      checks.${system} = {
        shellcheck = pkgs.runCommand "shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          shellcheck ${./scripts}/*.sh
          touch "$out"
        '';
        no-private-data = pkgs.runCommand "no-private-data" { nativeBuildInputs = [ pkgs.ripgrep ]; } ''
          if ! grep -qx 'DOMAIN=example\.test' ${./examples/domain.env}; then
            echo "examples/domain.env must contain exactly DOMAIN=example.test" >&2
            exit 1
          fi
          if rg -n '192\.168\.|BEGIN[[:space:]].*PRIVATE[[:space:]]KEY|ENC\[AES256_GCM' ${./.}; then
            echo "private data or production ciphertext found" >&2
            exit 1
          fi
          touch "$out"
        '';
      };
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          age
          fluxcd
          jq
          nixos-rebuild
          opentofu
          qemu
          sops
          ssh-to-age
        ];
      };
    };
}
