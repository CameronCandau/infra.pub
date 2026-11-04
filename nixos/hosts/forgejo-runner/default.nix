{
  config,
  inventory,
  pkgs,
  secretFiles,
  site,
  sops-nix,
  ...
}:
let
  machine = inventory.machines.forgejo-runner;
in
{
  imports = [
    sops-nix.nixosModules.sops
    ../../image.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking = {
    hostName = "forgejo-runner";
    useDHCP = false;
    defaultGateway = {
      address = inventory.network.gateway;
      interface = "ens18";
    };

    nameservers = inventory.network.nameservers;
    interfaces.ens18.ipv4.addresses = [
      {
        address = machine.address;
        prefixLength = inventory.network.prefixLength;
      }
    ];

    nftables.enable = true;

  };

  sops = {
    defaultSopsFile = secretFiles.hosts.forgejo-runner;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.forgejo-runner-token = { };
    templates."forgejo-runner.yaml".content = ''
      runner:
        capacity: 1
      server:
        connections:
          forgejo:
            url: https://forgejo.${site.domain}/
            uuid: ${site.forgejoRunnerUuid}
            token: ${config.sops.placeholder.forgejo-runner-token}
            labels:
              - nixos:host
    '';
  };

  users.groups.forgejo-runner = { };
  users.users.forgejo-runner = {
    isSystemUser = true;
    group = "forgejo-runner";
    home = "/var/lib/forgejo-runner";
  };

  systemd.services.forgejo-runner = {
    description = "Forgejo Actions Runner";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    path = with pkgs; [
      bash
      coreutils
      curl
      gawk
      gitMinimal
      gnused
      nodejs
      wget
      nix
      opentofu
    ];

    environment.HOME = "/var/lib/forgejo-runner";

    serviceConfig = {
      User = "forgejo-runner";
      Group = "forgejo-runner";
      StateDirectory = "forgejo-runner";
      StateDirectoryMode = "0700";
      UMask = "0077";
      NoNewPrivileges = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      PrivateDevices = true;
      RestrictSUIDSGID = true;

      WorkingDirectory = "/var/lib/forgejo-runner";
      LoadCredential = "config.yaml:${config.sops.templates."forgejo-runner.yaml".path}";
      ExecStart = "${pkgs.forgejo-runner}/bin/forgejo-runner daemon --config %d/config.yaml";
      Restart = "on-failure";
      RestartSec = "2s";
    };
  };

}
