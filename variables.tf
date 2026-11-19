variable "subscription_id" {
  description = "Azure subscription ID. Confirm the active subscription before applying."
  type        = string
}

variable "location" {
  description = "Deployment region. Defaults to East US."
  type        = string
  default     = "eastus"
}

variable "prefix" {
  description = "Unique prefix for this isolated lab."
  type        = string
  default     = "fwlab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,17}$", var.prefix))
    error_message = "Use 3-18 lowercase letters, numbers or hyphens, starting with a letter."
  }
}

variable "vm_size" {
  description = "VM size for each spoke. Confirm SKU availability and quota in your subscription."
  type        = string
  default     = "Standard_D2s_v7"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "ssh_public_key" {
  description = "Existing SSH public key; never supply or commit a private key."
  type        = string
  validation {
    condition     = can(regex("^ssh-(rsa|ed25519) ", trimspace(var.ssh_public_key)))
    error_message = "Supply an OpenSSH RSA or Ed25519 public key."
  }
}

variable "tags" {
  type    = map(string)
  default = { purpose = "firewall-hub-spoke-lab", managed_by = "terraform" }
}

variable "management_source_cidr" {
  description = "Optional single public IPv4 /32 allowed to SSH through firewall ports 2221/2222. Null disables inbound SSH."
  type        = string
  default     = null
  validation {
    condition     = var.management_source_cidr == null ? true : can(regex("^[0-9.]+/32$", var.management_source_cidr)) && can(cidrhost(var.management_source_cidr, 0))
    error_message = "Use your public IPv4 address with /32, or null."
  }
}
