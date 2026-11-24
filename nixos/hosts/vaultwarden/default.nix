{
  config,
  inventory,
  lib,
  pkgs,
  secretFiles,
  site,
  sops-nix,
  vaultwardenPackage,
  ...
}:
let
  machine = inventory.machines.vaultwarden;
  fqdn = "vaultwarden.${site.domain}";
in
{
  imports = [
    sops-nix.nixosModules.sops
    ../../image.nix
  ];

  fileSystems."/var/lib/vaultwarden" = {
    device = "/dev/disk/by-id/virtio-vaultwarden-data";
    fsType = "ext4";
    options = [ "noatime" ];
    autoFormat = true;
    autoResize = true;
  };

  networking = {
    hostName = "vaultwarden";
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
      ip saddr ${inventory.machines.haproxy.address} tcp dport 8222 accept
    '';
  };

  sops = {
    defaultSopsFile = secretFiles.hosts.vaultwarden;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      vaultwarden-oidc-client-id.restartUnits = [ "vaultwarden.service" ];
      vaultwarden-oidc-client-secret.restartUnits = [ "vaultwarden.service" ];
      vaultwarden-oidc-project-id.restartUnits = [ "vaultwarden.service" ];
      vaultwarden-smtp-password.restartUnits = [ "vaultwarden.service" ];
      backup_s3_access_key_id = { };
      backup_s3_secret_access_key = { };
      backup_restic_password = { };

      backup_s3_endpoint.sopsFile = secretFiles.backupStorage;
      backup_s3_region.sopsFile = secretFiles.backupStorage;
      backup_s3_bucket.sopsFile = secretFiles.backupStorage;
    };
  };

  sops.templates."vaultwarden.env".content = ''
    SSO_CLIENT_ID=${config.sops.placeholder.vaultwarden-oidc-client-id}
    SSO_CLIENT_SECRET=${config.sops.placeholder.vaultwarden-oidc-client-secret}
    SSO_AUDIENCE_TRUSTED=^${config.sops.placeholder.vaultwarden-oidc-project-id}$
    SMTP_PASSWORD=${config.sops.placeholder.vaultwarden-smtp-password}
  '';

  services.vaultwarden = {
    enable = true;
    package = vaultwardenPackage;
    dbBackend = "sqlite";
    environmentFile = config.sops.templates."vaultwarden.env".path;
    config = {
      DOMAIN = "https://${fqdn}";
      ROCKET_ADDRESS = machine.address;
      ROCKET_PORT = 8222;
      IP_HEADER = "X-Forwarded-For";
      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = false;
      SSO_ENABLED = true;
      SSO_ONLY = true;
      SSO_SIGNUPS_ALLOWED = true;
      SSO_SIGNUPS_MATCH_EMAIL = false;
      SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION = false;
      SSO_AUTHORITY = "https://auth.${site.domain}";
      SSO_SCOPES = "email profile offline_access";
      SSO_PKCE = true;
      SMTP_HOST = site.vaultwarden.smtpHost;
      SMTP_PORT = 587;
      SMTP_SECURITY = "starttls";
      SMTP_FROM = "vaultwarden@${site.domain}";
      SMTP_FROM_NAME = "Vaultwarden";
      SMTP_USERNAME = site.vaultwarden.smtpUser;
    };
  };

  systemd.services.vaultwarden.unitConfig.RequiresMountsFor = "/var/lib/vaultwarden";

  systemd.services.vaultwarden-backup = {
    description = "Back up Vaultwarden data to off-host object storage";
    wants = [ "network-online.target" ];
    requires = [
      "vaultwarden.service"
    ];
    after = [
      "network-online.target"
      "vaultwarden.service"
      "sops-nix.service"
    ];
    unitConfig.RequiresMountsFor = "/var/lib/vaultwarden";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      CacheDirectory = "vaultwarden-backup";
      PrivateTmp = true;
      ProtectSystem = "strict";
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
      export RESTIC_REPOSITORY="s3:$backup_s3_endpoint/$backup_s3_bucket/vaultwarden"

      if ! ${lib.getExe pkgs.restic} cat config --no-cache >/dev/null 2>&1; then
        ${lib.getExe pkgs.restic} init
      fi

      cd /var/lib/vaultwarden
      stage=$(mktemp -d /var/cache/vaultwarden-backup/data.XXXXXXXX)
      trap 'rm -rf -- "$stage"' EXIT
      test -s db.sqlite3
      ${lib.getExe pkgs.sqlite} db.sqlite3 ".backup '$stage/db.sqlite3'"
      test "$(${lib.getExe pkgs.sqlite} "$stage/db.sqlite3" 'PRAGMA quick_check;')" = ok
      find . -mindepth 1 -maxdepth 1 ! -name db.sqlite3 ! -name "db.sqlite3-*" -exec cp -at "$stage" -- {} +

      ${lib.getExe pkgs.restic} backup --no-cache --host vaultwarden --tag vaultwarden "$stage"

      ${lib.getExe pkgs.restic} forget \
        --no-cache \
        --host vaultwarden \
        --tag vaultwarden \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 12 \
        --prune
    '';
  };

  systemd.timers.vaultwarden-backup = {
    description = "Daily Vaultwarden backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00 America/Los_Angeles";
      Persistent = true;
      RandomizedDelaySec = "15m";
      Unit = "vaultwarden-backup.service";
    };
  };
}
