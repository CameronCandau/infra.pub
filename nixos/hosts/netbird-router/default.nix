{
  inventory,
  netbirdPackage,
  site,
  ...
}:
let
  machine = inventory.machines.netbird-router;
in
{
  imports = [ ../../image.nix ];

  services.netbird = {
    package = netbirdPackage;
    useRoutingFeatures = "server";
    clients.wt0 = {
      name = "netbird";
      interface = "wt0";
      port = 51820;
      environment.NB_MANAGEMENT_URL = "https://netbird.${site.domain}:443";
    };
  };

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
      iifname "wt0" oifname "ens18" ip daddr ${inventory.serviceVips.user} tcp dport 2222 accept
      iifname "wt0" oifname "ens18" ip daddr ${inventory.machines.bind.address} udp dport 53 accept
      iifname "wt0" oifname "ens18" ip daddr ${inventory.machines.bind.address} tcp dport 53 accept
    '';
  };
}
