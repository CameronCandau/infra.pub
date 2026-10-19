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
  machine = inventory.machines.postgres;
in
{
  imports = [
    sops-nix.nixosModules.sops
    ../../acme.nix
    ../../image.nix
  ];

  fileSystems = {
    "/var/lib/postgresql" = {
      device = "/dev/disk/by-id/virtio-postgres-data";
      fsType = "ext4";
      options = [ "noatime" ];
      autoFormat = true;
      autoResize = true;
    };

    "/var/lib/pgbackrest" = {
      device = "/dev/disk/by-id/virtio-postgres-backup";
      fsType = "ext4";
      options = [ "noatime" ];
      autoFormat = true;
      autoResize = true;
    };
  };

  networking = {
    hostName = "postgres";
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
      ip saddr ${inventory.machines.forgejo.address} tcp dport 5432 accept
      ip saddr ${inventory.machines.k3s.address} tcp dport 5432 accept
    '';
  };

  sops = {
    defaultSopsFile = secretFiles.hosts.postgres;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      pgbackrest_b2_key_id = { };
      pgbackrest_b2_application_key = { };
      pgbackrest_b2_cipher_pass = { };
      zitadel-db-password = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
        restartUnits = [ "postgresql-setup.service" ];
      };
      immich-db-password = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
        restartUnits = [ "postgresql-setup.service" ];
      };
    };

    templates."pgbackrest-b2.conf" = {
      owner = "postgres";
      group = "postgres";
      mode = "0400";
      content = ''
        [global]
        repo2-s3-key=${config.sops.placeholder.pgbackrest_b2_key_id}
        repo2-s3-key-secret=${config.sops.placeholder.pgbackrest_b2_application_key}
        repo2-cipher-pass=${config.sops.placeholder.pgbackrest_b2_cipher_pass}
      '';
    };
  };

  environment.etc."pgbackrest/conf.d/b2.conf".source =
    config.sops.templates."pgbackrest-b2.conf".path;

  security.acme.certs."postgres.${site.domain}" = {
    postRun = ''
      ${pkgs.systemd}/bin/systemctl restart postgresql-certificate.service
      ${pkgs.systemd}/bin/systemctl try-reload-or-restart postgresql.service
    '';
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    extensions =
      ps: with ps; [
        pgvector
        vectorchord
      ];
    enableTCPIP = true;

    settings = {
      ssl = true;
      ssl_cert_file = "/var/lib/postgresql/tls/fullchain.pem";
      ssl_key_file = "/var/lib/postgresql/tls/key.pem";
      password_encryption = "scram-sha-256";
      shared_preload_libraries = [ "vchord.so" ];
    };

    ensureDatabases = [
      "immich"
      "zitadel"
    ];

    ensureUsers = [
      {
        name = "immich";
        ensureDBOwnership = true;
      }
      {
        name = "zitadel";
        ensureDBOwnership = true;
      }
    ];

    authentication = ''
      hostssl postgres,template1 immich ${inventory.machines.k3s.address}/32 scram-sha-256
      hostssl immich immich ${inventory.machines.k3s.address}/32 scram-sha-256
      hostssl zitadel zitadel ${inventory.machines.k3s.address}/32 scram-sha-256
    '';
  };

  systemd.services.postgresql-setup.postStart = ''
    zitadel_password="$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.zitadel-db-password.path})"
    immich_password="$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.immich-db-password.path})"

    ${lib.getExe' config.services.postgresql.finalPackage "psql"} \
      --dbname=postgres \
      --set=ON_ERROR_STOP=1 \
      --set=zitadel_password="$zitadel_password" \
      --set=immich_password="$immich_password" <<'SQL'
    ALTER ROLE zitadel WITH LOGIN PASSWORD :'zitadel_password';
    ALTER ROLE immich WITH LOGIN PASSWORD :'immich_password';

    \connect immich
    CREATE EXTENSION IF NOT EXISTS vchord CASCADE;
    CREATE EXTENSION IF NOT EXISTS earthdistance CASCADE;
    SQL
  '';

  services.pgbackrest = {
    enable = true;
    settings = {
      archive-async = true;
      lock-path = "/run/pgbackrest";
      spool-path = "/var/spool/pgbackrest";
      start-fast = true;
    };
    repos = {
      # repo1
      localhost = {
        path = "/var/lib/pgbackrest";
        retention-diff = 7;
        retention-full = 2;
      };
      # repo2
      remote = {
        type = "s3";
        path = "/postgres";
        bundle = true;
        cipher-type = "aes-256-cbc";

        s3-bucket = "OversightConformDeflationUnderling";
        s3-endpoint = "s3.us-west-004.backblazeb2.com";
        s3-region = "us-west-004";
        s3-uri-style = "path";

        retention-diff = 30;
        retention-full = 8;
      };
    };
    stanzas.default.jobs = {
      daily = {
        schedule = "Mon..Sat *-*-* 02:00:00 America/Los_Angeles";
        type = "diff";
      };
      weekly = {
        schedule = "Sun *-*-* 02:00:00 America/Los_Angeles";
        type = "full";
      };

      remote-daily = {
        schedule = "Mon..Sat *-*-* 04:00:00 America/Los_Angeles";
        type = "diff";
      };
      remote-weekly = {
        schedule = "Sun *-*-* 04:00:00 America/Los_Angeles";
        type = "full";
      };
    };
  };

  users.users.pgbackrest.createHome = lib.mkForce false;

  systemd.tmpfiles.rules = [
    "d /var/lib/pgbackrest 0750 postgres postgres -"
    "d /var/spool/pgbackrest 0750 postgres postgres -"
    "d /run/pgbackrest 0750 postgres postgres -"
  ];

  systemd.services.pgbackrest-stanza-create = {
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

  systemd.services.pgbackrest-default-daily.serviceConfig = {
    User = lib.mkForce "postgres";
    Group = lib.mkForce "postgres";
  };

  systemd.services.pgbackrest-default-weekly.serviceConfig = {
    User = lib.mkForce "postgres";
    Group = lib.mkForce "postgres";
  };

  systemd.services."pgbackrest-default-remote-daily".serviceConfig = {
    User = lib.mkForce "postgres";
    Group = lib.mkForce "postgres";
    ExecStart = lib.mkForce ''
      ${pkgs.pgbackrest}/bin/pgbackrest \
        --stanza=default \
        --repo=2 \
        backup --type=diff
    '';
  };

  systemd.services."pgbackrest-default-remote-weekly".serviceConfig = {
    User = lib.mkForce "postgres";
    Group = lib.mkForce "postgres";
    ExecStart = lib.mkForce ''
      ${pkgs.pgbackrest}/bin/pgbackrest \
        --stanza=default \
        --repo=2 \
        backup --type=full
    '';
  };

  systemd.services.postgresql-certificate = {
    description = "Install ACME certificate for PostgreSQL";

    wants = [ "acme-postgres.${site.domain}.service" ];
    after = [
      "acme-postgres.${site.domain}.service"
      "var-lib-postgresql.mount"
    ];
    before = [ "postgresql.service" ];

    unitConfig.RequiresMountsFor = "/var/lib/postgresql";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      ${pkgs.coreutils}/bin/install \
        -d -m 0750 -o root -g postgres \
        /var/lib/postgresql/tls

      ${pkgs.coreutils}/bin/install \
        -m 0644 -o root -g postgres \
        /var/lib/acme/postgres.${site.domain}/fullchain.pem \
        /var/lib/postgresql/tls/fullchain.pem

      ${pkgs.coreutils}/bin/install \
        -m 0640 -o root -g postgres \
        /var/lib/acme/postgres.${site.domain}/key.pem \
        /var/lib/postgresql/tls/key.pem
    '';
  };

  systemd.services.postgresql = {
    wants = [ "postgresql-certificate.service" ];
    after = [ "postgresql-certificate.service" ];
    serviceConfig.ReadWritePaths = [
      "/run/pgbackrest"
      "/var/lib/pgbackrest"
      "/var/spool/pgbackrest"
    ];
  };

}
