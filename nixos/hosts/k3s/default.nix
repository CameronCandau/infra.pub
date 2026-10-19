{
  inventory,
  config,
  secretFiles,
  sops-nix,
  ...
}:
let
  machine = inventory.machines.k3s;
in
{
  imports = [
    sops-nix.nixosModules.sops
    ../../image.nix
  ];

  fileSystems = {
    "/var/lib/rancher/k3s/storage" = {
      device = "/dev/disk/by-id/virtio-k3s-storage";
      fsType = "ext4";
      options = [ "noatime" ];
      autoFormat = true;
      autoResize = true;
    };
  };

  networking = {
    hostName = "k3s";
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

    firewall = {
      allowedTCPPorts = [
        6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
      ];
      extraInputRules = ''
        ip saddr 10.42.0.0/16 tcp dport 10250 accept
        ip saddr ${inventory.machines.haproxy.address} tcp dport 80 accept
      '';
    };
  };

  sops = {
    defaultSopsFile = secretFiles.hosts.k3s;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.k3s-token = { };
  };

  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
    tokenFile = config.sops.secrets.k3s-token.path;
    extraFlags = [ "--secrets-encryption" ];
  };

}
