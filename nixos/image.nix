{
  lib,
  modulesPath,
  inventory,
  ...
}:
{
  imports = [
    (modulesPath + "/virtualisation/proxmox-image.nix")
    ./base.nix
  ];

  networking.useDHCP = lib.mkDefault true;

  proxmox = {
    cloudInit.enable = false;
    filenameSuffix = "${toString inventory.template.vmId}-${inventory.template.name}";
    qemuConf = {
      name = inventory.template.name;
      cores = 2;
      memory = 4096;
      net0 = "virtio=00:00:00:00:00:00,bridge=${inventory.network.bridge}";
      virtio0 = "${inventory.template.datastore}:vm-${toString inventory.template.vmId}-disk-0";
    };
  };
  virtualisation.diskSize = 16 * 1024;
}
