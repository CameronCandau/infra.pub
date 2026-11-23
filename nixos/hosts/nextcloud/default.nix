{
  config,
  inventory,
  lib,
  pkgs,
  secretFiles,
  site,
  sops-nix,
  ...
}:
let
  machine = inventory.machines.nextcloud;
  fqdn = "cloud.${site.domain}";
  occ = config.services.nextcloud.occ;
in
{
  imports = [
    sops-nix.nixosModules.sops
    ../../image.nix
  ];

  fileSystems."/var/lib/nextcloud" = {
    device = "/dev/disk/by-id/virtio-nextcloud-data";
    fsType = "ext4";
    options = [ "noatime" ];
    autoFormat = true;
    autoResize = true;
  };

  networking = {
    hostName = "nextcloud";
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
      ip saddr ${inventory.machines.haproxy.address} tcp dport 80 accept
    '';
  };

  sops = {
    defaultSopsFile = secretFiles.hosts.nextcloud;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      nextcloud-admin-password = { };
      nextcloud-oidc-client-id.restartUnits = [ "nextcloud-oidc.service" ];
      nextcloud-oidc-client-secret.restartUnits = [ "nextcloud-oidc.service" ];
      backup_s3_access_key_id = { };
      backup_s3_secret_access_key = { };
      backup_restic_password = { };

      backup_s3_endpoint.sopsFile = secretFiles.backupStorage;
      backup_s3_region.sopsFile = secretFiles.backupStorage;
      backup_s3_bucket.sopsFile = secretFiles.backupStorage;
    };
  };

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud35;
    hostName = fqdn;
    home = "/var/lib/nextcloud";
    datadir = "/var/lib/nextcloud";
    https = true;
    maxUploadSize = "10G";
    appstoreEnable = false;

    database.createLocally = true;
    config = {
      dbtype = "pgsql";
      adminuser = "admin";
      adminpassFile = config.sops.secrets.nextcloud-admin-password.path;
    };

    extraApps = {
      inherit (pkgs.nextcloud35Packages.apps) user_oidc;
    };

    settings = {
      trusted_proxies = [ inventory.machines.haproxy.address ];
      overwriteprotocol = "https";
      "overwrite.cli.url" = "https://${fqdn}";
      log_type = "systemd";
      default_phone_region = "US";
      maintenance_window_start = 9;
      shareapi_allow_links = false;
      user_oidc = {
        auto_provision = true;
        soft_auto_provision = true;
        enrich_login_id_token_with_userinfo = true;
      };
    };
  };

  systemd.services.nextcloud-oidc = {
    description = "Configure the ZITADEL OpenID Connect provider";
    wantedBy = [ "multi-user.target" ];
    requires = [ "nextcloud-setup.service" ];
    after = [
      "nextcloud-setup.service"
      "sops-nix.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      Group = "nextcloud";
      LoadCredential = [
        "client-id:${config.sops.secrets.nextcloud-oidc-client-id.path}"
        "client-secret:${config.sops.secrets.nextcloud-oidc-client-secret.path}"
      ];
    };
    script = ''
      set -eu

      client_id="$(${pkgs.coreutils}/bin/tr -d '\n' < "$CREDENTIALS_DIRECTORY/client-id")"
      client_secret="$(${pkgs.coreutils}/bin/tr -d '\n' < "$CREDENTIALS_DIRECTORY/client-secret")"

      ${lib.getExe occ} user_oidc:provider zitadel \
        --clientid="$client_id" \
        --clientsecret="$client_secret" \
        --discoveryuri="https://auth.${site.domain}/.well-known/openid-configuration" \
        --scope="openid email profile" \
        --unique-uid=1 \
        --mapping-uid=sub \
        --mapping-display-name=name \
        --mapping-email=email \
        --no-interaction

      ${lib.getExe occ} background:cron
    '';
  };

  systemd.services.nextcloud-backup = {
    description = "Back up Nextcloud data and PostgreSQL to off-host object storage";
    wants = [ "network-online.target" ];
    requires = [
      "nextcloud-setup.service"
      "postgresql.service"
    ];
    after = [
      "network-online.target"
      "nextcloud-setup.service"
      "postgresql.service"
      "sops-nix.service"
    ];
    unitConfig.RequiresMountsFor = "/var/lib/nextcloud";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      RuntimeDirectory = "nextcloud-backup";
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/nextcloud" ];
      NoNewPrivileges = true;
      TimeoutStartSec = "12h";
    };
    script = ''
      set -euo pipefail

      export AWS_ACCESS_KEY_ID="$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.backup_s3_access_key_id.path})"
      export AWS_SECRET_ACCESS_KEY="$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.backup_s3_secret_access_key.path})"
      export AWS_DEFAULT_REGION="$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.backup_s3_region.path})"
      export RESTIC_PASSWORD_FILE=${config.sops.secrets.backup_restic_password.path}

      backup_s3_endpoint="$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.backup_s3_endpoint.path})"
      backup_s3_bucket="$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.backup_s3_bucket.path})"
      export RESTIC_REPOSITORY="s3:$backup_s3_endpoint/$backup_s3_bucket/nextcloud"

      if ! ${lib.getExe pkgs.restic} cat config --no-cache >/dev/null 2>&1; then
        ${lib.getExe pkgs.restic} init
      fi

      maintenance=0
      cleanup() {
        if [ "$maintenance" -eq 1 ]; then
          ${lib.getExe occ} maintenance:mode --off
        fi
      }
      trap cleanup EXIT

      ${lib.getExe occ} maintenance:mode --on
      maintenance=1

      ${lib.getExe' pkgs.util-linux "runuser"} --user=postgres -- \
        ${lib.getExe' config.services.postgresql.finalPackage "pg_dump"} \
        --format=custom \
        nextcloud > /run/nextcloud-backup/nextcloud.dump

      ${lib.getExe pkgs.restic} backup \
        --no-cache \
        --host nextcloud \
        --tag nextcloud \
        /var/lib/nextcloud \
        /run/nextcloud-backup/nextcloud.dump

      ${lib.getExe pkgs.restic} forget \
        --no-cache \
        --host nextcloud \
        --tag nextcloud \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 12 \
        --prune
    '';
  };

  systemd.timers.nextcloud-backup = {
    description = "Daily Nextcloud backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00 America/Los_Angeles";
      Persistent = true;
      RandomizedDelaySec = "15m";
      Unit = "nextcloud-backup.service";
    };
  };
}
