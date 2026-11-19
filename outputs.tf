output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}
output "firewall_public_ip" {
  value = azurerm_public_ip.firewall["data"].ip_address
}
output "firewall_private_ip" {
  value = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}
output "vm_private_ips" {
  value = { for key, vm in azurerm_linux_virtual_machine.vm : key => vm.private_ip_address }
}
output "ssh_commands" {
  value = var.management_source_cidr == null ? {} : {
    for key, spoke in local.spokes : key => "ssh -p ${key == "app" ? 2221 : 2222} ${var.admin_username}@${azurerm_public_ip.firewall["data"].ip_address}"
  }
}
