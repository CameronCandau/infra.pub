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
    secrets.zitadel-db-password.restartUnits = [ "postgresql-setup.service" ];
  };

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
}
