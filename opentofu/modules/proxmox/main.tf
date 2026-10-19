terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.114.0"
    }
  }
}

resource "proxmox_virtual_environment_vm" "machine" {
  for_each = var.machines

  name      = each.key
  node_name = var.template.node
  vm_id     = each.value.vmId

  clone {
    full      = true
    node_name = var.template.node
    vm_id     = var.template.vmId
  }

  agent {
    enabled = true
    timeout = "10m"
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.template.datastore
    interface    = "virtio0"
    size         = each.value.diskSize
  }

  dynamic "disk" {
    for_each = each.value.dataDisks

    content {
      datastore_id = var.template.datastore
      interface    = disk.value.interface
      size         = disk.value.size
      serial       = disk.value.serial
    }
  }

  network_device {
    bridge      = var.network_bridge
    mac_address = each.value.macAddress
  }

  on_boot = true
  started = true
}
