{ config, inventory, ... }: {
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  services.qemuGuest.enable = true;

  networking.nftables.enable = true;

  environment.etc."alloy/config.alloy".text = ''
    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label = "unit"

      }
    }

    loki.source.journal "system" {
      forward_to = [loki.write.local.receiver]
      relabel_rules = loki.relabel.journal.rules
      labels = {host = "${config.networking.hostName}" }
    }

    loki.write "local" {
      endpoint {
        url = "http://${inventory.machines.observability.address}:3100/loki/api/v1/push"
      }
    }
  '';

  services.alloy = {

    enable = true;
    extraFlags = [ "--disable-reporting" ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true;

    firewallRules = ''
      ip saddr ${inventory.machines.observability.address} tcp dport 9100 accept
    '';
  };

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ inventory.operatorSshPublicKey ];
  };
  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [ "@wheel" ];

  system.stateVersion = "26.05";
}
