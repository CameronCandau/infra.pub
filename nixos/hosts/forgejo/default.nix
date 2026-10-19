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
  machine = inventory.machines.forgejo;
in
{
  imports = [
    sops-nix.nixosModules.sops
    ../../image.nix
  ];

  networking = {
    hostName = "forgejo";
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
      ip saddr ${inventory.machines.haproxy.address} tcp dport { 3000, 2222 } accept
    '';
  };

  sops = {
    defaultSopsFile = secretFiles.hosts.forgejo;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.forgejo-admin-password = {
      owner = "forgejo";
      group = "forgejo";
      mode = "0400";
    };
  };

  services.forgejo = {
    enable = true;
    database.type = "postgres";
    lfs.enable = false;
    settings = {
      server = {
        DOMAIN = "forgejo.${site.domain}";
        ROOT_URL = "https://forgejo.${site.domain}/";
        HTTP_PORT = 3000;
        SSH_DOMAIN = site.domain;
        START_SSH_SERVER = true;
        SSH_LISTEN_HOST = machine.address;
        SSH_LISTEN_PORT = 2222;
        SSH_PORT = 2222;
        SSH_SERVER_USE_PROXY_PROTOCOL = true;
        SSH_CREATE_AUTHORIZED_KEYS_FILE = false;
      };
      service.DISABLE_REGISTRATION = true;
      actions = {
        ENABLED = true;
      };

      security = {
        REVERSE_PROXY_LIMIT = 1;
        REVERSE_PROXY_TRUSTED_PROXIES = inventory.machines.haproxy.address;
      };
    };

  };

  services.openssh.settings.DenyUsers = [ "forgejo" ];

  systemd.services.forgejo.preStart =
    let
      adminCmd = "${lib.getExe config.services.forgejo.package} admin user";
      pwd = config.sops.secrets.forgejo-admin-password;
      user = "forgejo-admin";
    in
    ''
      password="$(tr -d '\n' < ${pwd.path})"

      ${adminCmd} create --admin --email "root@localhost" --username ${user} --password "$password" || ${adminCmd} change-password --username ${user} --password "$password"

    '';

}
