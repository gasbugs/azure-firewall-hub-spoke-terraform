resource "azurerm_public_ip" "firewall" {
  for_each            = toset(["data", "management"])
  name                = "${var.prefix}-fw-${each.key}-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_firewall_policy" "hub" {
  name                     = "${var.prefix}-fw-policy"
  location                 = azurerm_resource_group.lab.location
  resource_group_name      = azurerm_resource_group.lab.name
  sku                      = "Basic"
  threat_intelligence_mode = "Alert"
  tags                     = var.tags
}

resource "azurerm_firewall" "hub" {
  name                = "${var.prefix}-fw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"
  firewall_policy_id  = azurerm_firewall_policy.hub.id
  tags                = var.tags

  ip_configuration {
    name                 = "data"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall["data"].id
  }
  management_ip_configuration {
    name                 = "management"
    subnet_id            = azurerm_subnet.management.id
    public_ip_address_id = azurerm_public_ip.firewall["management"].id
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "lab" {
  name               = "lab-allow-list"
  firewall_policy_id = azurerm_firewall_policy.hub.id
  priority           = 200

  network_rule_collection {
    name     = "allowed-network-traffic"
    priority = 200
    action   = "Allow"
    rule {
      name                  = "DNS-to-Google"
      protocols             = ["UDP", "TCP"]
      source_addresses      = local.spoke_subnets
      destination_addresses = ["8.8.8.8"]
      destination_ports     = ["53"]
    }
    rule {
      name                  = "ICMP-between-spokes"
      protocols             = ["ICMP"]
      source_addresses      = local.spoke_subnets
      destination_addresses = local.spoke_subnets
      destination_ports     = ["*"]
    }
  }
  application_rule_collection {
    name     = "allowed-web-traffic"
    priority = 300
    action   = "Allow"
    rule {
      name              = "HTTP-to-Naver"
      source_addresses  = local.spoke_subnets
      destination_fqdns = ["naver.com", "www.naver.com"]
      protocols {
        type = "Http"
        port = 80
      }
    }
  }
  dynamic "nat_rule_collection" {
    for_each = var.management_source_cidr == null ? [] : [1]
    content {
      name     = "restricted-admin-ssh"
      priority = 100
      action   = "Dnat"
      dynamic "rule" {
        for_each = local.spokes
        content {
          name                = "ssh-${rule.key}"
          protocols           = ["TCP"]
          source_addresses    = [var.management_source_cidr]
          destination_address = azurerm_public_ip.firewall["data"].ip_address
          destination_ports   = [rule.key == "app" ? "2221" : "2222"]
          translated_address  = rule.value.vm_ip
          translated_port     = "22"
        }
      }
    }
  }
}
