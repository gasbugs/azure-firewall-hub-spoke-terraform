locals {
  spokes = {
    app = {
      address_space = "10.10.0.0/16"
      subnet        = "10.10.1.0/24"
      vm_ip         = "10.10.1.4"
    }
    workload = {
      address_space = "10.20.0.0/16"
      subnet        = "10.20.1.0/24"
      vm_ip         = "10.20.1.4"
    }
  }
  spoke_subnets = [for spoke in local.spokes : spoke.subnet]
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}
