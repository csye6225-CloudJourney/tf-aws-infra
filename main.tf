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

# Create a DB Subnet Group
resource "aws_db_subnet_group" "mydb_subnet_group" {
  name       = "private-subnet-group"
  subnet_ids = module.vpc.private_subnets # Reference your private subnets

  tags = {
    Name = "csye6225-private-subnet-group"
  }
}

# Create an RDS Parameter Group for PostgreSQL 16.4
resource "aws_db_parameter_group" "mydb_pg" {
  name        = "custom-pg-postgres-16"
  family      = "postgres16"
  description = "Custom parameter group for PostgreSQL 16.4"

  parameter {
    name  = "log_min_duration_statement"
    value = "5000"
  }

  tags = {
    Name = "PostgresParameterGroup"
  }
}

# Create the RDS instance with the custom parameter group
resource "aws_db_instance" "mydb" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "16.4"
  instance_class         = "db.t4g.micro"
  db_subnet_group_name   = aws_db_subnet_group.mydb_subnet_group.name # Reference the newly created subnet group
  identifier             = "csye6225"
  username               = "csye6225"
  password               = var.db_password # Pass the strong password securely
  vpc_security_group_ids = [module.vpc.db_sg]
  publicly_accessible    = false
  multi_az               = false
  parameter_group_name   = aws_db_parameter_group.mydb_pg.name
  db_name                = "csye6225" # Corrected argument
  skip_final_snapshot    = true

  tags = {
    Name = "csye6225-RDS-Instance"
  }
}

# Create the EC2 instance with User Data to pass database credentials
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

  user_data = <<-EOF
    #!/bin/bash
    export DB_HOST="${aws_db_instance.mydb.address}"
    export DB_USERNAME="${aws_db_instance.mydb.username}"
    export DB_PASSWORD="${var.db_password}"
    export DB_NAME="${aws_db_instance.mydb.db_name}"

    # Save variables to /etc/environment for persistence
    echo "DB_HOST=${aws_db_instance.mydb.address}" >> /etc/environment
    echo "DB_USERNAME=${aws_db_instance.mydb.username}" >> /etc/environment
    echo "DB_PASSWORD=${var.db_password}" >> /etc/environment
    echo "DB_NAME=${aws_db_instance.mydb.db_name}" >> /etc/environment

    # Start the web app service (if using systemd)
    sudo systemctl start webapp.service
  EOF

  tags = {
    Name = "${module.vpc.vpc_name}-WebApp-${module.vpc.random_suffix}" # Reference from the module
  }
}