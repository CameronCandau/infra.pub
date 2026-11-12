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

  security.unprivilegedUsernsClone = true;
  virtualisation.podman.enable = true;

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
    templates."forgejo-runner.yaml" = {
      restartUnits = [ "forgejo-runner.service" ];
      content = ''
        cache:
          enabled: false
        runner:
          capacity: 1
          timeout: 30m
          shutdown_timeout: 5m
          report_retry:
            max_retries: 10
            initial_delay: 1s
            max_delay: 30s
        host:
          workdir_parent: /var/lib/forgejo-runner/work
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
  };

  users.groups.forgejo-runner = { };
  users.users.forgejo-runner = {
    isSystemUser = true;
    group = "forgejo-runner";
    home = "/var/lib/forgejo-runner";
    autoSubUidGidRange = true;
  };

  systemd.services.forgejo-runner = {
    description = "Forgejo Actions Runner";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    path =
      (with pkgs; [
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
      ])
      ++ [ config.virtualisation.podman.package ];

    environment = {
      HOME = "/var/lib/forgejo-runner";
      XDG_CACHE_HOME = "/var/lib/forgejo-runner/.cache";
      XDG_CONFIG_HOME = "/var/lib/forgejo-runner/.config";
      XDG_DATA_HOME = "/var/lib/forgejo-runner/.local/share";
      XDG_RUNTIME_DIR = "/run/forgejo-runner";
    };

    serviceConfig = {
      User = "forgejo-runner";
      Group = "forgejo-runner";
      StateDirectory = "forgejo-runner";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "forgejo-runner";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      NoNewPrivileges = false;
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
