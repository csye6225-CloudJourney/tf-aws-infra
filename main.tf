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

# Generate a random string for the VPC to ensure uniqueness
resource "random_string" "vpc_suffix" {
  length  = 4
  special = false
  upper   = false
}

# Create a VPC
module "vpc" {
  source               = "./modules/vpc"
  vpc_name             = "${var.vpc_name_prefix}-${random_string.vpc_suffix.result}"
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  random_suffix        = random_string.vpc_suffix.result
}

# Create the EC2 instance
resource "aws_instance" "web_app" {
  ami                    = var.custom_ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [module.vpc.app_sg]
  subnet_id              = module.vpc.public_subnets[0]

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  disable_api_termination = false

  tags = {
    Name = "${module.vpc.vpc_name}-WebApp-${module.vpc.random_suffix}" # Reference from the module
  }
}