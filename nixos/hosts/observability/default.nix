{
  config,
  inventory,
  lib,
  secretFiles,
  site,
  sops-nix,
  ...
}:
let
  machine = inventory.machines.observability;

  lokiClients = lib.concatStringsSep ", " (
    lib.mapAttrsToList (_: machine: machine.address) inventory.machines
  );

in
{
  imports = [
    sops-nix.nixosModules.sops
    ../../image.nix
  ];

  networking = {
    hostName = "observability";
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

    firewall.extraInputRules = ''
      ip saddr ${inventory.machines.haproxy.address} tcp dport 3000 accept
      ip saddr { ${lokiClients} } tcp dport 3100 accept
    '';
  };

  sops = {
    defaultSopsFile = secretFiles.hosts.observability;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      grafana-admin-password.owner = "grafana";
      grafana-secret-key.owner = "grafana";
    };
  };

  services.grafana = {
    enable = true;

    provision = {
      enable = true;

      datasources.settings = {
        apiVersion = 1;
        prune = true;

        datasources = [
          {
            name = "Prometheus";
            uid = "prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:9090";
            isDefault = true;
            editable = false;
          }

          {
            name = "Loki";
            uid = "loki";
            type = "loki";
            access = "proxy";
            url = "http://127.0.0.1:3100";
            editable = false;
          }
        ];
      };
    };

    settings = {
      server = {
        http_addr = machine.address;
        domain = "grafana.${site.domain}";
        root_url = "https://grafana.${site.domain}/";
        enforce_domain = true;
      };

      security = {
        admin_password = "$__file{${config.sops.secrets.grafana-admin-password.path}}";
        secret_key = "$__file{${config.sops.secrets.grafana-secret-key.path}}";
        cookie_secure = true;
      };
    };
  };

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    retentionTime = "15d";
    extraFlags = [ "--storage.tsdb.retention.size=10GB" ];

    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [ "127.0.0.1:9090" ];
          }
        ];
      }

      {
        job_name = "node";
        static_configs = lib.mapAttrsToList (name: machine: {
          targets = [ "${machine.address}:9100" ];
          labels.instance = name;
        }) inventory.machines;
      }
    ];
  };

  services.loki = {
    enable = true;
    configuration = {
      auth_enabled = false;

      server = {
        http_listen_address = "0.0.0.0";
        http_listen_port = 3100;
      };

      common = {
        instance_addr = "127.0.0.1";
        path_prefix = "/var/lib/loki";
        replication_factor = 1;

        ring.kvstore.store = "inmemory";

        storage.filesystem = {
          chunks_directory = "/var/lib/loki/chunks";
          rules_directory = "/var/lib/loki/rules";
        };
      };

      schema_config.configs = [
        {
          from = "2026-01-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";

          index = {
            prefix = "index_";
            period = "24h";
          };
        }
      ];
      limits_config.retention_period = "336h";

      compactor = {
        working_directory = "/var/lib/loki/compactor";
        retention_enabled = true;
        delete_request_store = "filesystem";
      };

      analytics.reporting_enabled = false;
    };
  };

}
