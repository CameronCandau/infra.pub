{
  inventory,
  pkgs,
  site,
  ...
}:
let
  machine = inventory.machines.bind;
  trustedNetworks = [
    "127.0.0.0/24"
    inventory.network.cidr
  ];

in
{
  imports = [
    ../../image.nix
  ];

  networking = {
    hostName = "bind";
    useDHCP = false;
    defaultGateway = {
      address = inventory.network.gateway;
      interface = "ens18";
    };

    nameservers = [ "127.0.0.1" ];
    interfaces.ens18.ipv4.addresses = [
      {
        address = machine.address;
        prefixLength = inventory.network.prefixLength;
      }
    ];

    firewall = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
  };

  services.bind = {
    enable = true;
    ipv4Only = true;
    listenOn = [
      "127.0.0.1"
      machine.address
    ];
    cacheNetworks = trustedNetworks;

    forwarders = [ ];

    zones.${site.domain} = {
      master = true;
      allowQuery = trustedNetworks;
      file = pkgs.writeText site.domain ''
        $TTL 300
        @ IN SOA ns1.${site.domain}. hostmaster.${site.domain}. (
                2026100601	;	serial
                3600	;	refresh
                900	;	retry
                604800	;	expire
                300	; negative cache TTL
        )

        @ 	IN	NS	ns1.${site.domain}.
        ns1	IN	A	${machine.address}
        postgres  IN  A ${inventory.machines.postgres.address}

        @	IN	A	${inventory.machines.haproxy.address}
        *	IN	A	${inventory.machines.haproxy.address}
        immich	IN	A	${inventory.serviceVips.user}
        forgejo	IN	A	${inventory.serviceVips.user}
        grafana	IN	A	${inventory.serviceVips.admin}
        bao	IN	A	${inventory.serviceVips.admin}

        pve01	IN	A	${inventory.network.gateway}
      '';
    };
  };

}
