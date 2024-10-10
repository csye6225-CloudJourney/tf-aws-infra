# Default AWS provider configuration
provider "aws" {
  profile = var.aws_profile
  region  = var.region  # Use dynamic region from the variables
}

# Call the VPC module to create networking resources
module "vpc" {
  source = "./modules/vpc"

  vpc_name            = var.vpc_name
  vpc_cidr            = var.vpc_cidrs[var.region]  # Use dynamic region from variable
  public_subnet_cidrs = var.public_subnet_cidrs_list[var.region]  # Dynamic region
  private_subnet_cidrs= var.private_subnet_cidrs_list[var.region]  # Dynamic region
  availability_zones  = var.availability_zones_list[var.region]  # Dynamic region
}