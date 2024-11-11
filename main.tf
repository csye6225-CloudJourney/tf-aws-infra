terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.region
}

locals {
  environment = var.aws_profile
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

# RDS Resources
resource "aws_db_subnet_group" "mydb_subnet_group" {
  name       = "private-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "csye6225-private-subnet-group"
  }
}

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

resource "aws_db_instance" "mydb" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "16.4"
  instance_class         = "db.t4g.micro"
  db_subnet_group_name   = aws_db_subnet_group.mydb_subnet_group.name
  identifier             = "csye6225"
  username               = "csye6225"
  password               = var.db_password
  vpc_security_group_ids = [module.vpc.db_sg]
  publicly_accessible    = false
  multi_az               = false
  parameter_group_name   = aws_db_parameter_group.mydb_pg.name
  db_name                = "csye6225"
  skip_final_snapshot    = true

  tags = {
    Name = "csye6225-RDS-Instance"
  }
}

# IAM Role and Policies for CloudWatch Agent and S3 Access
resource "aws_iam_role" "cloudwatch_agent_role" {
  name = "CloudWatchAgentRole-${local.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Effect = "Allow",
      Sid    = ""
    }]
  })
}

# Attach CloudWatch Agent policy to the CloudWatchAgentRole
resource "aws_iam_role_policy_attachment" "attach_cloudwatch_agent_policy" {
  role       = aws_iam_role.cloudwatch_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# S3 Access Policy for CloudWatchAgentRole
resource "aws_iam_policy" "s3_access_policy" {
  name        = "S3AccessPolicy-${local.environment}"
  description = "Policy for EC2 to access and delete specific S3 bucket only"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = ["s3:ListBucket", "s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
        Effect = "Allow",
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.csye6225_s3.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.csye6225_s3.bucket}/*"
        ]
      }
    ]
  })
}

# Attach S3 Access Policy to the CloudWatchAgentRole
resource "aws_iam_role_policy_attachment" "attach_s3_access_policy" {
  role       = aws_iam_role.cloudwatch_agent_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

resource "aws_iam_instance_profile" "cloudwatch_agent_profile" {
  name = "CloudWatchAgentProfile-${local.environment}"
  role = aws_iam_role.cloudwatch_agent_role.name
}

# S3 Bucket and Configurations
resource "aws_s3_bucket" "csye6225_s3" {
  bucket        = "${uuid()}-csye6225-s3-${local.environment}"
  force_destroy = true

  tags = {
    Name = "csye6225-s3-bucket-${local.environment}"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption" {
  bucket = aws_s3_bucket.csye6225_s3.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "csye6225_s3_lifecycle" {
  bucket = aws_s3_bucket.csye6225_s3.bucket

  rule {
    id     = "TransitionToIA"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# EC2 Instance
resource "aws_instance" "web_app" {
  ami                    = var.custom_ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [module.vpc.app_sg]
  subnet_id              = module.vpc.public_subnets[0]
  iam_instance_profile   = aws_iam_instance_profile.cloudwatch_agent_profile.name

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
    export S3_BUCKET_NAME="${aws_s3_bucket.csye6225_s3.bucket}"

    echo "DB_HOST=${aws_db_instance.mydb.address}" >> /etc/environment
    echo "DB_USERNAME=${aws_db_instance.mydb.username}" >> /etc/environment
    echo "DB_PASSWORD=${var.db_password}" >> /etc/environment
    echo "DB_NAME=${aws_db_instance.mydb.db_name}" >> /etc/environment
    echo "S3_BUCKET_NAME=${aws_s3_bucket.csye6225_s3.bucket}" >> /etc/environment

    # Start the web application service
    sudo systemctl start webapp.service

    # Start and configure CloudWatch Agent
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
  EOF

  tags = {
    Name = "${module.vpc.vpc_name}-WebApp-${local.environment}-${module.vpc.random_suffix}"
  }
}

# Route 53 Zone Data Source
data "aws_route53_zone" "cloudjourney_zone" {
  name = "${var.aws_profile}.cloudjourney.me."
}

# Alias Record for Load Balancer
resource "aws_route53_record" "alias_record" {
  zone_id = data.aws_route53_zone.cloudjourney_zone.zone_id
  name    = "${var.aws_profile}.cloudjourney.me"
  type    = "A"
  alias {
    name                   = aws_lb.app_lb.dns_name
    zone_id                = aws_lb.app_lb.zone_id
    evaluate_target_health = true
  }
}