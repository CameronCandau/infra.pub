{
  config,
  secretFiles,
  site,
  sops-nix,
  ...
}:
{
  imports = [
    sops-nix.nixosModules.sops
  ];

  sops.secrets.cloudflare_dns_api_key = {
    sopsFile = secretFiles.acme;
  };

  sops.templates."cloudflare.env".content = ''
    CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare_dns_api_key}
  '';

  security.acme = {
    acceptTerms = true;

    defaults = {
      email = site.contactEmail;
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      environmentFile = config.sops.templates."cloudflare.env".path;
    };
  };
}
