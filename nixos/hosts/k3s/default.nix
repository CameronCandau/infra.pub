{
  inventory,
  config,
  lib,
  pkgs,
  secretFiles,
  sops-nix,
  ...
}:
let
  machine = inventory.machines.k3s;
in
{
  imports = [
    sops-nix.nixosModules.sops
    ../../image.nix
  ];

  fileSystems = {
    "/var/lib/rancher/k3s/storage" = {
      device = "/dev/disk/by-id/virtio-k3s-storage";
      fsType = "ext4";
      options = [ "noatime" ];
      autoFormat = true;
      autoResize = true;
    };
  };

  networking = {
    hostName = "k3s";
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

    firewall = {
      allowedTCPPorts = [
        6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
      ];
      extraInputRules = ''
        ip saddr 10.42.0.0/16 tcp dport 10250 accept
        ip saddr ${inventory.machines.haproxy.address} tcp dport 80 accept
      '';
    };
  };

  sops = {
    defaultSopsFile = secretFiles.hosts.k3s;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      k3s-token = { };
      backup_s3_access_key_id = { };
      backup_s3_secret_access_key = { };
      backup_restic_password = { };

      backup_s3_endpoint.sopsFile = secretFiles.backupStorage;
      backup_s3_region.sopsFile = secretFiles.backupStorage;
      backup_s3_bucket.sopsFile = secretFiles.backupStorage;
    };
  };

  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
    tokenFile = config.sops.secrets.k3s-token.path;
    extraFlags = [ "--secrets-encryption" ];
  };

  systemd.services.k3s-backup = {
    description = "Back up K3s storage and etcd snapshots to off-host object storage";
    path = [ pkgs.bash ];
    wants = [ "network-online.target" ];
    requires = [ "k3s.service" ];
    after = [
      "network-online.target"
      "k3s.service"
      "sops-nix.service"
    ];

    unitConfig.RequiresMountsFor = "/var/lib/rancher/k3s/storage";

    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/rancher/k3s/server/db/snapshots" ];
      NoNewPrivileges = true;
      TimeoutStartSec = "12h";
    };

    script = ''
      set -euo pipefail

      export AWS_ACCESS_KEY_ID="$(
        ${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.backup_s3_access_key_id.path}
      )"
      export AWS_SECRET_ACCESS_KEY="$(
        ${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.backup_s3_secret_access_key.path}
      )"
      export AWS_DEFAULT_REGION="$(
        ${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.backup_s3_region.path}
      )"
      export RESTIC_PASSWORD_FILE=${config.sops.secrets.backup_restic_password.path}

      backup_s3_endpoint="$(
        ${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.backup_s3_endpoint.path}
      )"
      backup_s3_bucket="$(
        ${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.backup_s3_bucket.path}
      )"
      export RESTIC_REPOSITORY="s3:$backup_s3_endpoint/$backup_s3_bucket/k3s"

      if ! ${lib.getExe pkgs.restic} cat config --no-cache >/dev/null 2>&1; then
        ${lib.getExe pkgs.restic} init
      fi

      ${lib.getExe config.services.k3s.package} etcd-snapshot save --name restic

      ${lib.getExe pkgs.restic} backup \
        --no-cache \
        --host k3s \
        --tag k3s \
        /var/lib/rancher/k3s/storage \
        /var/lib/rancher/k3s/server/db/snapshots

      ${lib.getExe pkgs.restic} forget \
        --no-cache \
        --host k3s \
        --tag k3s \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 12 \
        --prune

      ${lib.getExe config.services.k3s.package} etcd-snapshot prune \
        --name restic \
        --snapshot-retention 2
    '';
  };

  systemd.timers.k3s-backup = {
    description = "Daily K3s storage and etcd backup";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnCalendar = "*-*-* 06:00:00 America/Los_Angeles";
      Persistent = true;
      RandomizedDelaySec = "15m";
      Unit = "k3s-backup.service";
    };
  };

}
