variable "template" {
  type = object({
    vmId      = number
    name      = string
    node      = string
    datastore = string
  })
}

variable "network_bridge" {
  type = string
}

variable "machines" {
  type = map(object({
    vmId       = number
    address    = string
    macAddress = string
    cores      = number
    memory     = number
    diskSize   = number
    dataDisks = optional(list(object({
      interface = string
      size      = number
      serial    = string
    })), [])
  }))
}
