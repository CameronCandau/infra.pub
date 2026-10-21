{
  config,
  disko,
  lib,
  pkgs,
  secretFiles,
  site,
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

      zitadel-masterkey.restartUnits = [ "podman-zitadel.service" ];
      zitadel-login-certificate.restartUnits = [ "podman-zitadel.service" ];
      zitadel-login-private-key.restartUnits = [ "podman-zitadel-login.service" ];
      zitadel-login-session-cookie.restartUnits = [ "podman-zitadel-login.service" ];

      backup_s3_endpoint.sopsFile = secretFiles.backupStorage;
      backup_s3_region.sopsFile = secretFiles.backupStorage;
      backup_s3_bucket.sopsFile = secretFiles.backupStorage;

      zitadel-db-password.restartUnits = [ "postgresql-setup.service" ];
    };

    templates = {
      "zitadel.env" = {
        restartUnits = [ "podman-zitadel.service" ];
        content = ''
          ZITADEL_DATABASE_POSTGRES_USER_PASSWORD=${config.sops.placeholder.zitadel-db-password}
          ZITADEL_MASTERKEY=${config.sops.placeholder.zitadel-masterkey}
        '';
      };

      "zitadel-login.env" = {
        restartUnits = [ "podman-zitadel-login.service" ];
        content = ''
          ZITADEL_SESSION_COOKIE_SECRET=${config.sops.placeholder.zitadel-login-session-cookie}
        '';
      };

      "pgbackrest-remote.conf" = {
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
  };

  environment.etc."pgbackrest/conf.d/remote.conf".source =
    config.sops.templates."pgbackrest-remote.conf".path;

  environment.etc."zitadel/config.yaml".text = ''
    ExternalDomain: auth.${site.domain}
    ExternalPort: 443
    ExternalSecure: true
    TLS:
      Enabled: false
    ServicePing:
      Enabled: false
    Database:
      postgres:
        Host: /run/postgresql
        Port: 5432
        Database: zitadel
        User:
          Username: zitadel
          SSL:
            Mode: disable
    SystemAPIUsers:
      login-client:
        Path: /secrets/login-client/tls.crt
        Memberships:
          - MemberType: System
            Roles:
              - IAM_LOGIN_CLIENT
  '';

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
      local zitadel zitadel scram-sha-256
      local all all peer
      host all all 127.0.0.1/32 scram-sha-256
      host all all ::1/128 scram-sha-256
    '';
  };

  virtualisation = {
    oci-containers = {
      backend = "podman";
      # Keep the empty database untouched until the migration explicitly starts both containers.
      containers = {
        zitadel = {
          autoStart = false;
          image = "ghcr.io/zitadel/zitadel@sha256:956a298405189a8f6cd4ec92e8828b1bd10caa7da8b139c39d251d7053e33784";
          cmd = [
            "start-from-setup"
            "--config"
            "/etc/zitadel/config.yaml"
            "--masterkeyFromEnv"
          ];
          environmentFiles = [ config.sops.templates."zitadel.env".path ];
          ports = [ "127.0.0.1:8080:8080" ];
          volumes = [
            "/etc/zitadel/config.yaml:/etc/zitadel/config.yaml:ro"
            "/run/postgresql:/run/postgresql:ro"
            "${config.sops.secrets.zitadel-login-certificate.path}:/secrets/login-client/tls.crt:ro"
          ];
        };

        zitadel-login = {
          autoStart = false;
          image = "ghcr.io/zitadel/zitadel-login@sha256:ee98f024ddbebce788a7faf5a4b5571d20cbddf3bca8d3923091c424f2855737";
          dependsOn = [ "zitadel" ];
          environment = {
            CUSTOM_REQUEST_HEADERS = "Host:auth.${site.domain},X-Forwarded-Proto:https";
            HOSTNAME = "0.0.0.0";
            NEXT_PUBLIC_BASE_PATH = "/ui/v2/login";
            ZITADEL_API_URL = "http://zitadel:8080";
            ZITADEL_LOGINCLIENT_KEYFILE = "/secrets/login-client/tls.key";
          };
          environmentFiles = [ config.sops.templates."zitadel-login.env".path ];
          ports = [ "127.0.0.1:3000:3000" ];
          user = "0";
          volumes = [
            "${config.sops.secrets.zitadel-login-private-key.path}:/secrets/login-client/tls.key:ro"
          ];
        };
      };
    };

    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
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
    podman-zitadel = {
      requires = [ "postgresql.service" ];
      after = [ "postgresql.service" ];
    };

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
