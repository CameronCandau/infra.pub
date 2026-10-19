{
  inventory,
  site,
  ...
}:
let
  machine = inventory.machines.haproxy;

in
{
  imports = [
    ../../acme.nix
    ../../image.nix
  ];

  networking = {
    hostName = "haproxy";
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

    firewall.allowedTCPPorts = [
      80
      443
      2222
    ];
  };

  services.haproxy = {
    enable = true;
    config = ''
      global
              ssl-default-bind-options ssl-min-ver TLSv1.2

      defaults
              mode http
              timeout connect 5000ms
              timeout client 50000ms
              timeout server 50000ms

      frontend http-in
              bind *:80
              http-request redirect scheme https code 308

      frontend https-in
              bind *:443 ssl crt /var/lib/acme/${site.domain}/full.pem alpn h2,http/1.1
              http-request set-header X-Forwarded-Proto https
              http-request set-header X-Forwarded-For %[src]

              acl host_openbao hdr(host) -i bao.${site.domain}
              acl host_immich hdr(host) -i immich.${site.domain}
              acl source_lan src ${inventory.network.cidr}
              http-request deny deny_status 404 if host_openbao !source_lan
              http-request deny deny_status 404 if host_immich !source_lan

              acl host_forgejo hdr(host) -i forgejo.${site.domain}
              use_backend forgejo-web if host_forgejo

              acl host_grafana hdr(host) -i grafana.${site.domain}
              use_backend grafana if host_grafana

              acl host_zitadel hdr(host) -i auth.${site.domain}
              use_backend zitadel if host_zitadel

              use_backend immich if host_immich source_lan
              use_backend openbao if host_openbao source_lan

              default_backend unknown-host

      frontend ssh-in
              bind *:2222
              mode tcp
              timeout client 1h
              default_backend forgejo-ssh

      backend unknown-host
              http-request deny deny_status 404

      backend forgejo-web
              server forgejo-web ${inventory.machines.forgejo.address}:3000 check

      backend grafana
              server grafana ${inventory.machines.observability.address}:3000 check

      backend zitadel
              server zitadel ${inventory.machines.k3s.address}:80 check proto h2

      backend immich
              server immich ${inventory.machines.k3s.address}:80 check

      backend openbao
              server openbao ${inventory.machines.openbao.address}:8200 check ssl verify required ca-file /etc/ssl/certs/ca-bundle.crt sni str(bao.${site.domain}) verifyhost bao.${site.domain}

      backend forgejo-ssh
              mode tcp
              timeout server 1h
              server forgejo-ssh ${inventory.machines.forgejo.address}:2222 send-proxy-v2
    '';
  };

  security.acme.certs.${site.domain} = {
    extraDomainNames = [ "*.${site.domain}" ];
    group = "haproxy";
    reloadServices = [ "haproxy.service" ];
  };

  systemd.services.haproxy = {
    wants = [ "acme-${site.domain}.service" ];
    after = [ "acme-${site.domain}.service" ];
  };
}
