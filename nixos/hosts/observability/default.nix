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

  mkMediaIntakeAlert =
    {
      uid,
      title,
      event,
      summary,
    }:
    {
      inherit uid title;
      condition = "C";
      data = [
        {
          refId = "A";
          datasourceUid = "loki";
          relativeTimeRange = {
            from = 300;
            to = 0;
          };
          model = {
            datasource = {
              type = "loki";
              uid = "loki";
            };
            editorMode = "code";
            expr = ''sum by (job_id) (count_over_time({host="den"} | json | __error__="" | service="media-intake" | event="${event}" [5m]))'';
            intervalMs = 1000;
            maxDataPoints = 43200;
            queryType = "range";
            refId = "A";
          };
        }
        {
          refId = "B";
          datasourceUid = "__expr__";
          relativeTimeRange = {
            from = 0;
            to = 0;
          };
          model = {
            conditions = [ ];
            datasource = {
              type = "__expr__";
              uid = "__expr__";
            };
            expression = "A";
            intervalMs = 1000;
            maxDataPoints = 43200;
            reducer = "last";
            refId = "B";
            type = "reduce";
          };
        }
        {
          refId = "C";
          datasourceUid = "__expr__";
          relativeTimeRange = {
            from = 0;
            to = 0;
          };
          model = {
            conditions = [
              {
                evaluator = {
                  params = [ 0 ];
                  type = "gt";
                };
                operator.type = "and";
                query.params = [ "C" ];
                reducer.type = "last";
                type = "query";
              }
            ];
            datasource = {
              type = "__expr__";
              uid = "__expr__";
            };
            expression = "B";
            intervalMs = 1000;
            maxDataPoints = 43200;
            refId = "C";
            type = "threshold";
          };
        }
      ];
      dashboardUid = "media-intake";
      panelId = 8;
      noDataState = "OK";
      executionErrorState = "Error";
      for = "0s";
      annotations = {
        inherit summary;
        description = "Media Intake job {{ $labels.job_id }} requires attention.";
      };
      labels = {
        severity = "error";
        service = "media-intake";
      };
      notification_settings = {
        receiver = "Media Intake Email";
        group_by = [
          "alertname"
          "grafana_folder"
          "job_id"
        ];
        group_wait = "0s";
        group_interval = "5m";
        repeat_interval = "4h";
      };
    };

in
{
  imports = [
    sops-nix.nixosModules.sops
    ../../image.nix
  ];

  environment.etc."grafana-dashboards/media-intake.json".source = ./media-intake-dashboard.json;

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
      grafana-smtp-password = {
        owner = "grafana";
        restartUnits = [ "grafana.service" ];
      };
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

      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "Homelab";
            folder = "Homelab";
            disableDeletion = true;
            editable = false;
            options.path = "/etc/grafana-dashboards";
          }
        ];
      };

      alerting = {
        contactPoints.settings.contactPoints = [
          {
            name = "Media Intake Email";
            receivers = [
              {
                uid = "media-intake-email";
                type = "email";
                settings = {
                  addresses = site.contactEmail;
                  singleEmail = true;
                };
                disableResolveMessage = false;
              }
            ];
          }
        ];

        rules.settings.groups = [
          {
            name = "Media Intake";
            folder = "Homelab";
            interval = "1m";
            rules = [
              (mkMediaIntakeAlert {
                uid = "media-intake-job-failed";
                title = "Media Intake job failed";
                event = "job_failed";
                summary = "Media Intake job {{ $labels.job_id }} failed.";
              })
              (mkMediaIntakeAlert {
                uid = "media-intake-cleanup-failed";
                title = "Media Intake cleanup failed";
                event = "job_cleanup_failed";
                summary = "Media Intake cleanup failed for job {{ $labels.job_id }}.";
              })
            ];
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

      smtp = {
        enabled = true;
        host = site.observability.smtpHost;
        user = site.observability.smtpUser;
        password = "$__file{${config.sops.secrets.grafana-smtp-password.path}}";
        from_address = "alerts@${site.domain}";
        from_name = "Grafana";
        startTLS_policy = "MandatoryStartTLS";
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
