terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70.0"
    }
  }
}

# Default AWS provider configuration
provider "aws" {
  profile = var.aws_profile
  region  = var.region
}

# Generate a random string for each VPC to ensure uniqueness
resource "random_string" "vpc_suffix" {
  count   = var.number_of_vpcs  # Create one random string for each VPC
  length  = 4
  special = false
  upper   = false
}

# Create multiple VPCs dynamically using count
module "vpc" {
  source              = "./modules/vpc"
  count               = var.number_of_vpcs  # Dynamically create multiple VPCs

  vpc_name            = "${var.vpc_name_prefix}-${random_string.vpc_suffix[count.index].result}"
  vpc_cidr            = var.vpc_cidrs[count.index]  # Use the next CIDR block
  public_subnet_cidrs = var.public_subnet_cidrs_list[count.index]  # Pass unique public subnets for each VPC
  private_subnet_cidrs= var.private_subnet_cidrs_list[count.index]  # Pass unique private subnets for each VPC
  availability_zones  = var.availability_zones_list[var.region]
  random_suffix       = random_string.vpc_suffix[count.index].result  # Apply random suffix to other resources
}