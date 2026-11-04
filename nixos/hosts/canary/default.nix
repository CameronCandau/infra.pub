{
  config,
  inventory,
  pkgs,
  secretFiles,
  sops-nix,
  ...
}:
let
  machine = inventory.machines.canary;
in
{
  imports = [
    sops-nix.nixosModules.sops
    ../../image.nix
  ];

  networking = {
    hostName = "canary";
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
  };

  sops = {
    defaultSopsFile = secretFiles.hosts.canary;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.canary-proof = {
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

  systemd.services.canary-secret-proof = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      LoadCredential = "canary-proof:${config.sops.secrets.canary-proof.path}";
      ExecStart = "${pkgs.coreutils}/bin/test -s %d/canary-proof";
    };
  };
}
