#---------------------------------------------------------- Transit ----------------------------------------------------------
module "AZ_transit_1" {
  source          = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version         = "1.1.1"
  cloud           = "Azure"
  name            = "${local.env_prefix}-AZ-trans-1"
  region          = "West Europe"
  cidr            = "10.1.0.0/23"
  account         = var.avx_ctrl_account_azure
  ha_gw           = true
  local_as_number = "65101"
  tags = {
    Owner = "pkonitz"
  }
}


#------------------------------------ AZ spoke 1 ----------------------------------
resource "azurerm_resource_group" "spoke1_rg" {
  name     = "${local.env_prefix}-RG"
  location = "West Europe"
}

resource "azurerm_virtual_network" "vnet_spoke1" {
  name                = "${local.env_prefix}-vnet"
  location            = azurerm_resource_group.spoke1_rg.location
  resource_group_name = azurerm_resource_group.spoke1_rg.name
  address_space       = ["10.101.0.0/16"]
}
#-------- LB -----------
resource "azurerm_lb" "spoke1_LB" {
  name                = "${local.env_prefix}-LB"
  location            = azurerm_resource_group.spoke1_rg.location
  resource_group_name = azurerm_resource_group.spoke1_rg.name
  sku                 = "Standard"
  frontend_ip_configuration {
    name                          = "FEIP-AVX-SPOKE1-GWs"
    subnet_id                     = azurerm_subnet.avx_gw_subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.101.2.100"
  }
}

resource "azurerm_lb_backend_address_pool" "LB-avx-pool" {
  loadbalancer_id = azurerm_lb.spoke1_LB.id
  name            = "LB-POOL-AVX-GWs"
}

resource "azurerm_lb_backend_address_pool_address" "POOL_AVX_address_1" {
  name                    = "pool-avx-address-1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.LB-avx-pool.id
  virtual_network_id      = azurerm_virtual_network.vnet_spoke1.id
  ip_address              = aviatrix_spoke_gateway.spoke1_avx_gw.private_ip
  depends_on = [
    azurerm_lb.spoke1_LB,
    aviatrix_spoke_gateway.spoke1_avx_gw
  ]
}
resource "azurerm_lb_backend_address_pool_address" "POOL_AVX_address_2" {
  name                    = "pool-avx-address-2"
  backend_address_pool_id = azurerm_lb_backend_address_pool.LB-avx-pool.id
  virtual_network_id      = azurerm_virtual_network.vnet_spoke1.id
  ip_address              = aviatrix_spoke_gateway.spoke1_avx_gw.ha_private_ip
  depends_on = [
    azurerm_lb.spoke1_LB,
    aviatrix_spoke_gateway.spoke1_avx_gw
  ]
}

resource "azurerm_lb_rule" "spoke1_LB_rule1" {
  name                           = "LB_rule1_avx_haports"
  resource_group_name            = azurerm_resource_group.spoke1_rg.name
  loadbalancer_id                = azurerm_lb.spoke1_LB.id
  protocol                       = "All"
  frontend_port                  = "0"
  backend_port                   = "0"
  frontend_ip_configuration_name = "FEIP-AVX-SPOKE1-GWs"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.LB-avx-pool.id

}

#------------- dummy workload subnet ----------
# resource "azurerm_subnet" "spoke1_workload_subnet" {
#   name                 = "spoke1_workload_subnet"
#   resource_group_name  = azurerm_resource_group.spoke1_rg.name
#   virtual_network_name = azurerm_virtual_network.vnet_spoke1.name
#   address_prefixes     = ["10.101.3.0/24"]
# }


# resource "azurerm_route_table" "spoke1_workload_udr" {
#   name                          = "spoke1_workload_udr"
#   location                      = azurerm_resource_group.spoke1_rg.location
#   resource_group_name           = azurerm_resource_group.spoke1_rg.name
#   disable_bgp_route_propagation = false
# }

# resource "azurerm_subnet_route_table_association" "UDR_association_dummy_subnet" {
#   subnet_id      = azurerm_subnet.spoke1_workload_subnet.id
#   route_table_id = azurerm_route_table.spoke1_workload_udr.id
# }

#-------- FW ------------

resource "azurerm_subnet" "spoke1_AzureFirewallSubnet" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.spoke1_rg.name
  virtual_network_name = azurerm_virtual_network.vnet_spoke1.name
  address_prefixes     = ["10.101.1.0/24"]
}

resource "azurerm_route_table" "spoke1_fw_udr" {
  name                          = "spoke1_fw_udr"
  location                      = azurerm_resource_group.spoke1_rg.location
  resource_group_name           = azurerm_resource_group.spoke1_rg.name
  disable_bgp_route_propagation = false

  route {
    name           = "default"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
  route {
    name                   = "RFC1918-10.0.0.0"
    address_prefix         = "10.0.0.0/8"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_lb.spoke1_LB.frontend_ip_configuration[0].private_ip_address
  }
  route {
    name                   = "RFC1918-172.16.0.0"
    address_prefix         = "172.16.0.0/12"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_lb.spoke1_LB.frontend_ip_configuration[0].private_ip_address
  }
  route {
    name                   = "RFC1918-192.168.0.0"
    address_prefix         = "192.168.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_lb.spoke1_LB.frontend_ip_configuration[0].private_ip_address
  }
  depends_on = [
    azurerm_lb.spoke1_LB
  ]
}

resource "azurerm_subnet_route_table_association" "UDR_association_FW" {
  subnet_id      = azurerm_subnet.spoke1_AzureFirewallSubnet.id
  route_table_id = azurerm_route_table.spoke1_fw_udr.id
}

resource "azurerm_public_ip" "PIP_FW" {
  name                = "${local.env_prefix}-PIP-FW"
  location            = azurerm_resource_group.spoke1_rg.location
  resource_group_name = azurerm_resource_group.spoke1_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "spoke1_azfw" {
  name                = "${local.env_prefix}-FW"
  location            = azurerm_resource_group.spoke1_rg.location
  resource_group_name = azurerm_resource_group.spoke1_rg.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.spoke1_AzureFirewallSubnet.id
    public_ip_address_id = azurerm_public_ip.PIP_FW.id
  }
}

resource "azurerm_firewall_network_rule_collection" "FW_net_rule_collection_1" {
  name                = "FW_net_rule_collection_1"
  azure_firewall_name = azurerm_firewall.spoke1_azfw.name
  resource_group_name = azurerm_resource_group.spoke1_rg.name
  priority            = 100
  action              = "Allow"

  rule {
    name                  = "DNS"
    source_addresses      = ["10.0.0.0/8"]
    destination_ports     = ["53"]
    destination_addresses = ["*"]
    protocols             = ["TCP", "UDP"]
  }
  # rule {
  #   name = "aws queue"
  #   source_addresses = ["10.0.0.0/8"]
  #   destination_ports = ["443"]
  #   destination_fqdns = ["queue.amazonaws.com"]
  #   protocols = ["TCP","UDP"]
  # }
}


resource "azurerm_firewall_application_rule_collection" "FW_app_rule2" {
  name                = "${local.env_prefix}-app-rule2"
  azure_firewall_name = azurerm_firewall.spoke1_azfw.name
  resource_group_name = azurerm_resource_group.spoke1_rg.name
  priority            = 110
  action              = "Allow"

  rule {
    name = "allow aws queue"
    source_addresses = ["10.0.0.0/8"]
    target_fqdns = ["*.amazonaws.com"]
    protocol {
      port = "443"
      type = "Https"
    }
    protocol {
      port = "80"
      type = "Http"
    }
  }

  rule {
    name = "allow wp.pl"
    source_addresses = ["10.0.0.0/8"]
    target_fqdns = ["*.wp.pl"]
    protocol {
      port = "443"
      type = "Https"
    }
    protocol {
      port = "80"
      type = "Http"
    }
  }
    rule {
    name = "allow - what is my IP"
    source_addresses = ["10.0.0.0/8"]
    target_fqdns = ["ifconfig.me"]
    protocol {
      port = "443"
      type = "Https"
    }
    protocol {
      port = "80"
      type = "Http"
    }
  }

}

resource "azurerm_firewall_application_rule_collection" "FW_app_rule1" {
  name                = "${local.env_prefix}-app-rule1"
  azure_firewall_name = azurerm_firewall.spoke1_azfw.name
  resource_group_name = azurerm_resource_group.spoke1_rg.name
  priority            = 100
  action              = "Deny"

  rule {
    name = "block google"
    source_addresses = ["10.0.0.0/16"]
    target_fqdns = ["*.google.com"]
    protocol {
      port = "443"
      type = "Https"
    }
    protocol {
      port = "80"
      type = "Http"
    }
  }

}

#-------- AVX -----------
resource "azurerm_subnet" "avx_gw_subnet" {
  name                 = "spoke1-avx-gw-subnet"
  resource_group_name  = azurerm_resource_group.spoke1_rg.name
  virtual_network_name = azurerm_virtual_network.vnet_spoke1.name
  address_prefixes     = ["10.101.2.0/24"]
}

resource "azurerm_route_table" "spoke1_avx_udr" {
  name                          = "spoke1_avx_udr"
  location                      = azurerm_resource_group.spoke1_rg.location
  resource_group_name           = azurerm_resource_group.spoke1_rg.name
  disable_bgp_route_propagation = false


  route {
    name           = "transit-primary"
    address_prefix = "${module.AZ_transit_1.transit_gateway.eip}/32"
    next_hop_type  = "Internet"
  }
  route {
    name           = "transit-ha"
    address_prefix = "${module.AZ_transit_1.transit_gateway.ha_eip}/32"
    next_hop_type  = "Internet"
  }
  route {
    name           = "spoke1-primary"
    address_prefix = "${aviatrix_spoke_gateway.spoke1_avx_gw.eip}/32"
    next_hop_type  = "Internet"
  }
  route {
    name           = "spoke1-ha"
    address_prefix = "${aviatrix_spoke_gateway.spoke1_avx_gw.ha_eip}/32"
    next_hop_type  = "Internet"
  }
  route {
    name           = "controller"
    address_prefix = "${var.controller_ip}/32"
    next_hop_type  = "Internet"
  }
  route {
    name                   = "default"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.spoke1_azfw.ip_configuration[0].private_ip_address
  }

  depends_on = [
    aviatrix_spoke_gateway.spoke1_avx_gw,
    module.AZ_transit_1
  ]
}

resource "azurerm_subnet_route_table_association" "UDR_association_AVX" {
  subnet_id      = azurerm_subnet.avx_gw_subnet.id
  route_table_id = azurerm_route_table.spoke1_avx_udr.id
}

resource "aviatrix_spoke_gateway" "spoke1_avx_gw" {
  cloud_type                            = 8
  account_name                          = var.avx_ctrl_account_azure
  gw_name                               = "${local.env_prefix}-avx-spoke1"
  vpc_id                                = "${azurerm_virtual_network.vnet_spoke1.name}:${azurerm_resource_group.spoke1_rg.name}:${azurerm_virtual_network.vnet_spoke1.guid}"
  vpc_reg                               = "West Europe"
  gw_size                               = "Standard_B1ms"
  ha_gw_size                            = "Standard_B1ms"
  subnet                                = "10.101.2.0/24"
  ha_subnet                             = "10.101.2.0/24"
  insane_mode                           = false
  manage_transit_gateway_attachment     = false
  single_az_ha                          = true
  single_ip_snat                        = false
  customized_spoke_vpc_routes           = ""
  filtered_spoke_vpc_routes             = ""
  included_advertised_spoke_routes      = "0.0.0.0/0"
  zone                                  = "az-1"
  ha_zone                               = "az-2"
  enable_private_vpc_default_route      = false
  enable_skip_public_route_table_update = false
  enable_auto_advertise_s2c_cidrs       = false
  tunnel_detection_time                 = null
  tags                                  = null
  depends_on = [
    azurerm_subnet.avx_gw_subnet
  ]
}

resource "aviatrix_spoke_transit_attachment" "spoke1_transit_attachment" {
  spoke_gw_name   = aviatrix_spoke_gateway.spoke1_avx_gw.gw_name
  transit_gw_name = module.AZ_transit_1.transit_gateway.gw_name
  
  # that is needed as if not there AVX will put its own UDR on spoke subnet and that will give us error. 
  depends_on = [
    azurerm_subnet_route_table_association.UDR_association_AVX
  ]
}

#------------------------------------ AWS spoke 2 - North Europe----------------------------------

module "aws_spoke_2" {
  source     = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  name       = "${local.env_prefix}-AWS-spoke-2"
  ha_gw      = false
  cloud      = "AWS"
  region     = var.aws_region
  cidr       = "10.102.0.0/16"
  transit_gw = module.AZ_transit_1.transit_gateway.gw_name
  account    = var.avx_ctrl_account_aws
  depends_on = [
    module.AZ_transit_1
  ]
}

module "aws_spoke2_vm1" {
  source = "git::https://github.com/fkhademi/terraform-aws-instance-module.git"

  name      = "${local.env_prefix}-spoke2-vm1"
  region    = var.aws_region
  vpc_id    = module.aws_spoke_2.vpc.vpc_id
  subnet_id = module.aws_spoke_2.vpc.private_subnets[1].subnet_id
  ssh_key   = var.ssh_key
  public_ip = false
  depends_on = [
    module.aws_spoke_2
  ]
}

module "aws_spoke2_vm2" {
  source    = "git::https://github.com/conip/terraform-aws-instance-module.git"
  name      = "${local.env_prefix}-spoke2-vm2"
  region    = var.aws_region
  vpc_id    = module.aws_spoke_2.vpc.vpc_id
  subnet_id = module.aws_spoke_2.vpc.public_subnets[1].subnet_id
  ssh_key   = var.ssh_key
  public_ip = true
  depends_on = [
    module.aws_spoke_2
  ]
}





