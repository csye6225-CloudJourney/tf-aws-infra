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

#Allow cloud watch agent to invoke lambda
resource "aws_iam_policy" "invoke_lambda_policy" {
  name        = "InvokeLambdaPolicy-${local.environment}"
  description = "Policy to allow invoking the email-verification-handler Lambda function"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["lambda:InvokeFunction"],
        Resource = aws_lambda_function.email_verification_lambda.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_invoke_lambda_policy" {
  role       = aws_iam_role.cloudwatch_agent_role.name
  policy_arn = aws_iam_policy.invoke_lambda_policy.arn
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

# SNS Topic for Email Verification
resource "aws_sns_topic" "email_verification_topic" {
  name = "email-verification-topic"

  tags = {
    Name = "EmailVerificationTopic"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "email-verification-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_policy" "lambda_policy" {
  name = "email-verification-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["sns:Publish"],
        Resource = aws_sns_topic.email_verification_topic.arn
      },
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach Policy to Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda Function
resource "aws_lambda_function" "email_verification_lambda" {
  function_name = "email-verification-handler"
  role          = aws_iam_role.lambda_execution_role.arn
  runtime       = "python3.9"
  handler       = "lambda_function.lambda_handler"

  # Path to the Lambda function zip file 
  filename = var.lambda_zip_file

  environment {
    variables = {
      DB_HOST          = aws_db_instance.mydb.address
      DB_USERNAME      = aws_db_instance.mydb.username
      DB_PASSWORD      = var.db_password
      DB_NAME          = aws_db_instance.mydb.db_name
      SENDGRID_API_KEY = var.sendgrid_api_key
      ENV_PREFIX       = var.aws_profile
    }
  }

  tags = {
    Name = "EmailVerificationLambda"
  }
}

# SNS Subscription to Lambda
resource "aws_sns_topic_subscription" "lambda_sns_subscription" {
  topic_arn = aws_sns_topic.email_verification_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.email_verification_lambda.arn
}

# Allow SNS to Trigger Lambda
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_verification_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.email_verification_topic.arn
}


# Output for SNS Topic
output "sns_topic_arn" {
  description = "ARN of the SNS topic for email verification"
  value       = aws_sns_topic.email_verification_topic.arn
}

# Output for Lambda Function
output "lambda_function_name" {
  description = "Name of the Lambda function for email verification"
  value       = aws_lambda_function.email_verification_lambda.function_name
}

output "lambda_execution_role" {
  description = "IAM Role ARN for the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}