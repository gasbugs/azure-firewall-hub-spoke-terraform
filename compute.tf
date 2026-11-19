resource "azurerm_network_interface" "vm" {
  for_each            = local.spokes
  name                = "${var.prefix}-${each.key}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
  ip_configuration {
    name                          = "private"
    subnet_id                     = azurerm_subnet.spoke[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.vm_ip
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = local.spokes
  name                            = "${var.prefix}-${each.key}-vm"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(var.ssh_public_key)
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  # No package installation: only the explicitly allowed egress is available.
  depends_on = [
    azurerm_subnet_route_table_association.spoke,
    azurerm_subnet_network_security_group_association.spoke,
    azurerm_virtual_network_peering.hub_to_spoke,
    azurerm_virtual_network_peering.spoke_to_hub,
    azurerm_firewall_policy_rule_collection_group.lab
  ]
}
