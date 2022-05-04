provider "aviatrix" {
  username      = "admin"
  password      = var.avx_controller_admin_password
  controller_ip = var.controller_ip
}
provider "azurerm" {
  # subscription_id = var.subscription_id
  # client_id       = var.client_id
  # client_secret   = var.client_secret
  # tenant_id       = var.tenant_id
  features {}
}
provider "aws" {
  region = var.aws_region
}

provider "local" {}