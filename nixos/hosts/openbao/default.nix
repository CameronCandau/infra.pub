{
  config,
  inventory,
  lib,
  openbaoPackage,
  pkgs,
  secretFiles,
  site,
  sops-nix,
  ...
}:
let
  machine = inventory.machines.openbao;
  serviceDomain = "bao.${site.domain}";
in
{
  imports = [
    sops-nix.nixosModules.sops
    ../../acme.nix
    ../../image.nix
  ];

  sops = {
    defaultSopsFile = secretFiles.hosts.openbao;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      backup_s3_access_key_id = { };
      backup_s3_secret_access_key = { };
      backup_restic_password = { };

      backup_s3_endpoint.sopsFile = secretFiles.backupStorage;
      backup_s3_region.sopsFile = secretFiles.backupStorage;
      backup_s3_bucket.sopsFile = secretFiles.backupStorage;

      backup_approle_role_id = { };
      backup_approle_secret_id = { };
    };
  };

  networking = {
    hostName = "openbao";
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
    firewall.extraInputRules = ''
      ip saddr ${inventory.machines.haproxy.address} tcp dport 8200 accept
    '';
  };

  users.groups.openbao-cert = { };

  security.acme.certs.${serviceDomain}.group = "openbao-cert";

  services.openbao = {
    enable = true;
    package = openbaoPackage;

    settings = {
      ui = true;
      api_addr = "https://${serviceDomain}";
      cluster_addr = "https://${machine.address}:8201";

      storage.raft = {
        path = "/var/lib/openbao";
        node_id = "openbao";
      };

      listener.default = {
        type = "tcp";
        address = "${machine.address}:8200";
        tls_cert_file = "/var/lib/acme/${serviceDomain}/fullchain.pem";
        tls_key_file = "/var/lib/acme/${serviceDomain}/key.pem";
        tls_auto_reload = true;
      };

      audit = [
        {
          file.journald = {
            description = "Write audit events to journald";
            options.file_path = "stdout";
          };
        }
      ];
    };
  };

  systemd.services.openbao = {
    wants = [ "acme-${serviceDomain}.service" ];
    after = [ "acme-${serviceDomain}.service" ];
    serviceConfig.SupplementaryGroups = [ "openbao-cert" ];
  };

  systemd.services.openbao-backup = {
    description = "Back up OpenBao Raft storage to off-host object storage";
    path = [ pkgs.bash ];
    wants = [ "network-online.target" ];
    requires = [ "openbao.service" ];
    after = [
      "network-online.target"
      "openbao.service"
      "sops-nix.service"
    ];

    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      RuntimeDirectory = "openbao-backup";
      RuntimeDirectoryMode = "0700";
      Environment = "HOME=/run/openbao-backup";
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      NoNewPrivileges = true;
      TimeoutStartSec = "1h";
    };

    script = ''
      set -euo pipefail

      snapshot=/run/openbao-backup/raft.snap
      trap 'rm -f "$snapshot"' EXIT

      export BAO_ADDR=https://${serviceDomain}
      BAO_TOKEN="$(
        ${lib.getExe openbaoPackage} write -field=token \
          auth/approle/login \
          role_id=@${config.sops.secrets.backup_approle_role_id.path} \
          secret_id=@${config.sops.secrets.backup_approle_secret_id.path}
      )"
      export BAO_TOKEN

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
      export RESTIC_REPOSITORY="s3:$backup_s3_endpoint/$backup_s3_bucket/openbao"

      if ! ${lib.getExe pkgs.restic} cat config --no-cache >/dev/null 2>&1; then
        ${lib.getExe pkgs.restic} init
      fi

      ${lib.getExe openbaoPackage} operator raft snapshot save "$snapshot"

      ${lib.getExe pkgs.restic} backup \
        --no-cache \
        --host openbao \
        --tag openbao \
        "$snapshot"

      ${lib.getExe pkgs.restic} forget \
        --no-cache \
        --host openbao \
        --tag openbao \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 12 \
        --prune
    '';
  };

  systemd.timers.openbao-backup = {
    description = "Daily OpenBao Raft backup";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnCalendar = "*-*-* 03:00:00 America/Los_Angeles";
      Persistent = true;
      RandomizedDelaySec = "15m";
      Unit = "openbao-backup.service";
    };
  };
}
