resource "azurerm_virtual_network" "hub" {
  name                = "${var.prefix}-firewall-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.0.0/26"]
}

resource "azurerm_subnet" "management" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.1.0/26"]
}

resource "azurerm_virtual_network" "spoke" {
  for_each            = local.spokes
  name                = "${var.prefix}-${each.key}-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [each.value.address_space]
  # Basic has no DNS proxy: send DNS directly through the firewall to Google DNS.
  dns_servers = ["8.8.8.8"]
  tags        = var.tags
}

resource "azurerm_subnet" "spoke" {
  for_each                        = local.spokes
  name                            = "vm-subnet"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.spoke[each.key].name
  address_prefixes                = [each.value.subnet]
  default_outbound_access_enabled = false
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each                     = local.spokes
  name                         = "hub-to-${each.key}"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each                     = local.spokes
  name                         = "${each.key}-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_route_table" "spoke" {
  for_each                      = local.spokes
  name                          = "${var.prefix}-${each.key}-routes"
  location                      = azurerm_resource_group.lab.location
  resource_group_name           = azurerm_resource_group.lab.name
  bgp_route_propagation_enabled = false
  tags                          = var.tags

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
  }
  route {
    name                   = "other-spoke-via-firewall"
    address_prefix         = local.spokes[each.key == "app" ? "workload" : "app"].address_space
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "spoke" {
  for_each       = local.spokes
  subnet_id      = azurerm_subnet.spoke[each.key].id
  route_table_id = azurerm_route_table.spoke[each.key].id
}

resource "azurerm_network_security_group" "spoke" {
  for_each            = local.spokes
  name                = "${var.prefix}-${each.key}-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags

  security_rule {
    name                       = "AllowSpokeICMP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = local.spoke_subnets
    destination_address_prefix = each.value.subnet
  }
  dynamic "security_rule" {
    for_each = var.management_source_cidr == null ? [] : [1]
    content {
      name                       = "AllowFirewallDNATSSH"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefixes    = ["10.0.0.0/26", var.management_source_cidr]
      destination_address_prefix = each.value.vm_ip
    }
  }
  security_rule {
    name                       = "DenyOtherInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # Azure platform DNS bypasses UDRs; block it so DNS must traverse the firewall.
  security_rule {
    name                       = "DenyAzurePlatformDNSBypass"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "AzurePlatformDNS"
  }
}

resource "azurerm_subnet_network_security_group_association" "spoke" {
  for_each                  = local.spokes
  subnet_id                 = azurerm_subnet.spoke[each.key].id
  network_security_group_id = azurerm_network_security_group.spoke[each.key].id
}
