{ inventory, ... }:
let
  machine = inventory.machines.netbird-router;
in
{
  imports = [ ../../image.nix ];

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking = {
    hostName = "netbird-router";
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
    firewall.extraForwardRules = ''
      iifname "wt0" oifname "ens18" ip daddr { ${inventory.serviceVips.user}, ${inventory.serviceVips.admin} } tcp dport 443 accept
    '';
  };
}
