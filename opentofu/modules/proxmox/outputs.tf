output "ipv4_addresses" {
  description = "IPv4 addresses reported by the QEMU guest agent."
  value = {
    for name, machine in proxmox_virtual_environment_vm.machine :
    name => machine.ipv4_addresses
  }
}
