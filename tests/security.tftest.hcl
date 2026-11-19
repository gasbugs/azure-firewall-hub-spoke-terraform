mock_provider "azurerm" {}

variables {
  subscription_id        = "00000000-0000-0000-0000-000000000000"
  ssh_public_key         = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"
  management_source_cidr = null
}

run "isolated_hub_and_spokes" {
  command = plan

  assert {
    condition     = length(azurerm_linux_virtual_machine.vm) == 2 && alltrue([for vm in azurerm_linux_virtual_machine.vm : vm.size == "Standard_D2s_v7" && vm.source_image_reference[0].offer == "ubuntu-24_04-lts"])
    error_message = "Both spokes must have D2s_v7 Ubuntu 24.04 VMs."
  }
  assert {
    condition     = alltrue([for subnet in azurerm_subnet.spoke : subnet.default_outbound_access_enabled == false]) && alltrue([for nic in azurerm_network_interface.vm : nic.ip_configuration[0].public_ip_address_id == null])
    error_message = "VMs must have no public IP or default outbound bypass."
  }
  assert {
    condition     = alltrue([for vnet in azurerm_virtual_network.spoke : length(vnet.dns_servers) == 1 && contains(vnet.dns_servers, "8.8.8.8")])
    error_message = "DNS must use the resolver allowed through the firewall."
  }
  assert {
    condition     = length(azurerm_virtual_network_peering.hub_to_spoke) == 2 && length(azurerm_virtual_network_peering.spoke_to_hub) == 2
    error_message = "Both spokes need bidirectional hub peering."
  }
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.lab.nat_rule_collection) == 0
    error_message = "Inbound management must be disabled by default."
  }
  assert {
    condition     = azurerm_firewall.hub.sku_tier == "Basic" && length(azurerm_firewall.hub.management_ip_configuration) == 1
    error_message = "Basic Firewall requires its management interface."
  }
}

run "restricted_management" {
  command = plan
  variables {
    management_source_cidr = "192.0.2.10/32"
  }
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.lab.nat_rule_collection) == 1 && alltrue([for rule in one(azurerm_firewall_policy_rule_collection_group.lab.nat_rule_collection).rule : length(rule.source_addresses) == 1 && contains(rule.source_addresses, "192.0.2.10/32")])
    error_message = "Optional SSH must be restricted to the specified /32."
  }
}
