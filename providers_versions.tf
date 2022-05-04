terraform {
  cloud {
    organization = "CONIX"

    workspaces {
      name = "BLOG-5-EGRESS-AZ-FW"
    }
  }
  required_providers {

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.99"
    }

    aviatrix = {
      source  = "aviatrixsystems/aviatrix"
      version = "2.21.1-6.6.ga"
    }
    aws = {
      source = "hashicorp/aws"
      version = "~>3.0.0"
    }
  }
}

