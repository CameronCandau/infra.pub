{
  config,
  disko,
  lib,
  secretFiles,
  site,
  sops-nix,
  ...
}:
let
  domain = "netbird.${site.domain}";
in
{
  imports = [
    disko.nixosModules.disko
    sops-nix.nixosModules.sops
    ../../cloud-base.nix
  ];

  networking = {
    hostName = "netbird";
    firewall = {
      allowedTCPPorts = [
        80
        443
      ];
      allowedUDPPorts = [ 3478 ];
    };
  };

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

  sops = lib.mkIf site.netbird.enable {
    defaultSopsFile = secretFiles.hosts.netbird;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      netbird-relay-auth-secret.restartUnits = [ "podman-netbird-server.service" ];
      netbird-store-encryption-key.restartUnits = [ "podman-netbird-server.service" ];
      netbird-session-cookie-encryption-key.restartUnits = [ "podman-netbird-server.service" ];
      netbird-initial-owner-password-hash.restartUnits = [ "podman-netbird-server.service" ];
    };

    templates."netbird-config.yaml" = {
      restartUnits = [ "podman-netbird-server.service" ];
      content = ''
        server:
          listenAddress: ":80"
          exposedAddress: "https://${domain}:443"
          stunPorts:
            - 3478
          metricsPort: 9090
          healthcheckAddress: ":9000"
          logLevel: "info"
          logFile: "console"
          authSecret: ${config.sops.placeholder.netbird-relay-auth-secret}
          dataDir: "/var/lib/netbird"
          disableAnonymousMetrics: true

          auth:
            issuer: "https://${domain}/oauth2"
            signKeyRefreshEnabled: true
            localAuthDisabled: ${lib.boolToString site.netbird.localAuthDisabled}
            sessionCookieEncryptionKey: ${config.sops.placeholder.netbird-session-cookie-encryption-key}
            dashboardRedirectURIs:
              - "https://${domain}/nb-auth"
              - "https://${domain}/nb-silent-auth"
            cliRedirectURIs:
              - "http://localhost:53000/"
            owner:
              email: ${builtins.toJSON site.contactEmail}
              password: ${config.sops.placeholder.netbird-initial-owner-password-hash}

          reverseProxy:
            # shortcut: this is Podman's default bridge gateway; use a dedicated network if it changes.
            trustedPeers:
              - "10.88.0.1/32"

          store:
            engine: "sqlite"
            encryptionKey: ${config.sops.placeholder.netbird-store-encryption-key}
      '';
    };
  };

  services.caddy = lib.mkIf site.netbird.enable {
    enable = true;
    globalConfig = ''
      admin 127.0.0.1:2019
      email ${site.contactEmail}
      metrics
    '';
    virtualHosts.${domain} = {
      extraConfig = ''
        @grpc header Content-Type application/grpc*
        reverse_proxy @grpc h2c://127.0.0.1:8081

        @backend path /relay* /ws-proxy/* /api/* /oauth2/*
        reverse_proxy @backend 127.0.0.1:8081

        reverse_proxy 127.0.0.1:8080
      '';
      logFormat = ''
        output stdout
        format filter {
          wrap json
          request>uri regexp \?.*$ ""
        }
      '';
    };
  };

  virtualisation = lib.mkIf site.netbird.enable {
    oci-containers = {
      backend = "podman";
      containers = {
        netbird-server = {
          image = "docker.io/netbirdio/netbird-server@sha256:541ecef7e98a66b17411d44e9d4dcfdb65913415f39b3b944b8e7e748f997f1d";
          cmd = [
            "--config"
            "/etc/netbird/config.yaml"
          ];
          ports = [
            "127.0.0.1:8081:80"
            "3478:3478/udp"
          ];
          volumes = [
            "${config.sops.templates."netbird-config.yaml".path}:/etc/netbird/config.yaml:ro"
            "/var/lib/netbird:/var/lib/netbird"
          ];
        };

        netbird-dashboard = {
          image = "docker.io/netbirdio/dashboard@sha256:70e0fc6dd3b7758148d182fb55ecd8d4f9ce01e9bba56c9389224e0b8354009d";
          environment = {
            NETBIRD_MGMT_API_ENDPOINT = "https://${domain}";
            NETBIRD_MGMT_GRPC_API_ENDPOINT = "https://${domain}";
            AUTH_AUDIENCE = "netbird-dashboard";
            AUTH_CLIENT_ID = "netbird-dashboard";
            AUTH_CLIENT_SECRET = "";
            AUTH_AUTHORITY = "https://${domain}/oauth2";
            USE_AUTH0 = "false";
            AUTH_SUPPORTED_SCOPES = "openid profile email groups";
            AUTH_REDIRECT_URI = "/nb-auth";
            AUTH_SILENT_REDIRECT_URI = "/nb-silent-auth";
            NGINX_SSL_PORT = "443";
            LETSENCRYPT_DOMAIN = "none";
          };
          ports = [ "127.0.0.1:8080:80" ];
        };
      };
    };

    podman.enable = true;
  };

  systemd.tmpfiles.rules = lib.mkIf site.netbird.enable [
    "d /var/lib/netbird 0700 root root -"
  ];
}
