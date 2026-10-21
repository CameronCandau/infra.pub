{
  config,
  disko,
  lib,
  pkgs,
  secretFiles,
  sops-nix,
  ...
}:
{
  imports = [
    disko.nixosModules.disko
    sops-nix.nixosModules.sops
    ../../cloud-base.nix
  ];

  networking.hostName = "identity";

  boot = {
    initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_scsi"
    ];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
        editor = false;
      };
    };
  };

  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };

  sops = {
    defaultSopsFile = secretFiles.hosts.identity;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      backup_s3_access_key_id = { };
      backup_s3_secret_access_key = { };
      pgbackrest_cipher_pass = { };

      backup_s3_endpoint.sopsFile = secretFiles.backupStorage;
      backup_s3_region.sopsFile = secretFiles.backupStorage;
      backup_s3_bucket.sopsFile = secretFiles.backupStorage;

      zitadel-db-password.restartUnits = [ "postgresql-setup.service" ];
    };

    templates."pgbackrest-remote.conf" = {
      owner = "postgres";
      group = "postgres";
      mode = "0400";
      content = ''
        [global]
        repo1-s3-key=${config.sops.placeholder.backup_s3_access_key_id}
        repo1-s3-key-secret=${config.sops.placeholder.backup_s3_secret_access_key}
        repo1-s3-bucket=${config.sops.placeholder.backup_s3_bucket}
        repo1-s3-endpoint=${config.sops.placeholder.backup_s3_endpoint}
        repo1-s3-region=${config.sops.placeholder.backup_s3_region}
        repo1-cipher-pass=${config.sops.placeholder.pgbackrest_cipher_pass}
      '';
    };
  };

  environment.etc."pgbackrest/conf.d/remote.conf".source =
    config.sops.templates."pgbackrest-remote.conf".path;

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = true;
    ensureDatabases = [ "zitadel" ];
    ensureUsers = [
      {
        name = "zitadel";
        ensureDBOwnership = true;
      }
    ];
    settings = {
      listen_addresses = lib.mkForce "127.0.0.1,::1";
      password_encryption = "scram-sha-256";
    };
    authentication = lib.mkForce ''
      local all all peer
      host all all 127.0.0.1/32 scram-sha-256
      host all all ::1/128 scram-sha-256
    '';
  };

  systemd.services.postgresql-setup = {
    serviceConfig.LoadCredential = "zitadel-db-password:${config.sops.secrets.zitadel-db-password.path}";
    postStart = ''
      export ZITADEL_DB_PASSWORD
      ZITADEL_DB_PASSWORD="$(${pkgs.coreutils}/bin/tr -d '\n' < "$CREDENTIALS_DIRECTORY/zitadel-db-password")"

      ${lib.getExe' config.services.postgresql.finalPackage "psql"} \
        --dbname=postgres \
        --set=ON_ERROR_STOP=1 <<'SQL'
      \getenv zitadel_password ZITADEL_DB_PASSWORD
      ALTER ROLE zitadel WITH LOGIN PASSWORD :'zitadel_password';
      SQL

      unset ZITADEL_DB_PASSWORD
    '';
  };

  services.pgbackrest = {
    enable = true;
    settings = {
      archive-async = true;
      lock-path = "/run/pgbackrest";
      spool-path = "/var/spool/pgbackrest";
      start-fast = true;
    };
    repos.remote = {
      type = "s3";
      path = "/identity";
      bundle = true;
      cipher-type = "aes-256-cbc";
      s3-uri-style = "path";
      retention-diff = 30;
      retention-full = 8;
    };
    stanzas.default.jobs = {
      daily = {
        schedule = "Mon..Sat *-*-* 04:00:00 America/Los_Angeles";
        type = "diff";
      };
      weekly = {
        schedule = "Sun *-*-* 04:00:00 America/Los_Angeles";
        type = "full";
      };
    };
  };

  users.users.pgbackrest.createHome = lib.mkForce false;

  systemd.tmpfiles.rules = [
    "d /var/spool/pgbackrest 0750 postgres postgres -"
    "d /run/pgbackrest 0750 postgres postgres -"
  ];

  systemd.services = {
    pgbackrest-stanza-create = {
      description = "Create pgBackRest stanza";
      wantedBy = [ "multi-user.target" ];
      requires = [ "postgresql.service" ];
      after = [ "postgresql.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
        ExecStart = "${pkgs.pgbackrest}/bin/pgbackrest --stanza=default stanza-create";
      };
    };

    pgbackrest-default-daily.serviceConfig = {
      User = lib.mkForce "postgres";
      Group = lib.mkForce "postgres";
    };

    pgbackrest-default-weekly.serviceConfig = {
      User = lib.mkForce "postgres";
      Group = lib.mkForce "postgres";
    };

    pgbackrest-check = {
      description = "Check pgBackRest repository";
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
        ExecStart = "${pkgs.pgbackrest}/bin/pgbackrest --stanza=default check";
      };
    };

    postgresql.serviceConfig.ReadWritePaths = [
      "/run/pgbackrest"
      "/var/spool/pgbackrest"
    ];
  };

  systemd.timers.pgbackrest-check = {
    description = "Check pgBackRest repository weekly";
    wantedBy = [ "timers.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    timerConfig = {
      OnCalendar = "Mon *-*-* 06:00:00 America/Los_Angeles";
      Persistent = true;
    };
  };
}
