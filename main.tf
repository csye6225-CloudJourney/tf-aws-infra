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

# Data source for AWS account information
data "aws_caller_identity" "current" {}

# Generate a random string for the VPC to ensure uniqueness
resource "random_string" "vpc_suffix" {
  length  = 4
  special = false
  upper   = false
}

# Generate a random string for secrets to ensure uniqueness
resource "random_string" "secret_suffix" {
  length  = 4
  special = false
  upper   = false
}

# Generate a random string for KMS aliases
resource "random_string" "kms_suffix" {
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

# Generate a random password for the database
resource "random_password" "db_password" {
  length  = 16
  special = true
}

# KMS Key for Secrets Manager
resource "aws_kms_key" "secrets_key" {
  description             = "KMS key for Secrets Manager"
  enable_key_rotation     = true
  rotation_period_in_days = 90
}

# Secrets Manager Secret for DB Password
resource "aws_secretsmanager_secret" "db_password_secret" {
  name       = "db_password_secret_${random_string.secret_suffix.result}"
  kms_key_id = aws_kms_key.secrets_key.arn
}

# Add the secret versions after the secrets are created
resource "aws_secretsmanager_secret_version" "db_password_secret_version" {
  secret_id     = aws_secretsmanager_secret.db_password_secret.id
  secret_string = random_password.db_password.result
}

resource "aws_db_instance" "mydb" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "16.4"
  instance_class         = "db.t4g.micro"
  db_subnet_group_name   = aws_db_subnet_group.mydb_subnet_group.name
  identifier             = "csye6225"
  username               = "csye6225"
  password               = random_password.db_password.result
  vpc_security_group_ids = [module.vpc.db_sg]
  publicly_accessible    = false
  multi_az               = false
  parameter_group_name   = aws_db_parameter_group.mydb_pg.name
  db_name                = "csye6225"
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds_key.arn
  skip_final_snapshot    = true

  tags = {
    Name = "csye6225-RDS-Instance"
  }
}

# IAM Role and Policies for EC2 Instances
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

# Allow EC2 instances to invoke Lambda
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

# Policy to allow EC2 instances to access Secrets Manager
resource "aws_iam_policy" "ec2_secretsmanager_policy" {
  name        = "EC2SecretsManagerPolicy-${local.environment}"
  description = "Policy for EC2 to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["secretsmanager:GetSecretValue"],
        Resource = [
          aws_secretsmanager_secret.db_password_secret.arn
        ]
      },
      {
        Effect   = "Allow",
        Action   = ["kms:Decrypt"],
        Resource = [aws_kms_key.secrets_key.arn]
      }
    ]
  })
}

# Attach the policy to the EC2 instance role
resource "aws_iam_role_policy_attachment" "attach_ec2_secretsmanager_policy" {
  role       = aws_iam_role.cloudwatch_agent_role.name
  policy_arn = aws_iam_policy.ec2_secretsmanager_policy.arn
}

# Attach S3 Access Policy to the CloudWatchAgentRole
resource "aws_iam_role_policy_attachment" "attach_s3_access_policy" {
  role       = aws_iam_role.cloudwatch_agent_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# KMS Key for EC2 EBS Volume Encryption
resource "aws_kms_key" "ec2_key" {
  description             = "KMS key for EC2 EBS volume encryption"
  enable_key_rotation     = true
  rotation_period_in_days = 90

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Id" : "key-default-1",
    "Statement" : [
      {
        "Sid" : "EnableIAMUserPermissions",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "arn:aws:iam::651706766149:root"
        },
        "Action" : "kms:*",
        "Resource" : "*"
      },
      {
        "Sid" : "AllowEC2InstanceRoleToUseTheKMSKey",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "arn:aws:iam::651706766149:role/CloudWatchAgentRole-dev"
        },
        "Action" : [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "AllowAutoScalingServiceLinkedRoleUseOfKMSKey",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "arn:aws:iam::651706766149:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        },
        "Action" : [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "AllowAutoScalingServiceLinkedRoleCreateGrant",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "arn:aws:iam::651706766149:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        },
        "Action" : "kms:CreateGrant",
        "Resource" : "*",
        "Condition" : {
          "Bool" : {
            "kms:GrantIsForAWSResource" : "true"
          }
        }
      }
    ]
  })
}

# IAM Policy for EC2 Instances to Use the KMS Key
resource "aws_iam_policy" "ec2_kms_policy" {
  name        = "EC2KMSPolicy-${local.environment}"
  description = "Policy for EC2 instances to use KMS key for EBS encryption"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowEC2InstancesToUseTheKMSKey",
        Effect = "Allow",
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = aws_kms_key.ec2_key.arn
      }
    ]
  })
}

# Attach the KMS Policy to the EC2 Instance Role
resource "aws_iam_role_policy_attachment" "attach_ec2_kms_policy" {
  role       = aws_iam_role.cloudwatch_agent_role.name
  policy_arn = aws_iam_policy.ec2_kms_policy.arn
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

# KMS Key for S3 Bucket Encryption
resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3 bucket encryption"
  enable_key_rotation     = true
  rotation_period_in_days = 90
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption" {
  bucket = aws_s3_bucket.csye6225_s3.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_key.arn
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

# Policy to allow Lambda to access Secrets Manager
resource "aws_iam_policy" "lambda_secretsmanager_policy" {
  name        = "LambdaSecretsManagerPolicy"
  description = "Policy for Lambda to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["secretsmanager:GetSecretValue"],
        Resource = [
          aws_secretsmanager_secret.sendgrid_api_key_secret.arn
        ]
      },
      {
        Effect   = "Allow",
        Action   = ["kms:Decrypt"],
        Resource = [aws_kms_key.secrets_key.arn]
      }
    ]
  })
}

# Attach the policy to the Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_secretsmanager_policy_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_secretsmanager_policy.arn
}

# Secrets Manager Secret for SendGrid API Key
resource "aws_secretsmanager_secret" "sendgrid_api_key_secret" {
  name       = "sendgrid_api_key_secret_${random_string.secret_suffix.result}"
  kms_key_id = aws_kms_key.secrets_key.arn
}

# Optionally, you can comment out the secret version resource if you're manually adding the API key
resource "aws_secretsmanager_secret_version" "sendgrid_api_key_secret_version" {
  secret_id     = aws_secretsmanager_secret.sendgrid_api_key_secret.id
  secret_string = var.sendgrid_api_key
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
      DB_HOST     = aws_db_instance.mydb.address
      DB_USERNAME = aws_db_instance.mydb.username
      DB_NAME     = aws_db_instance.mydb.db_name
      ENV_PREFIX  = var.aws_profile
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

# KMS Key for RDS Encryption
resource "aws_kms_key" "rds_key" {
  description             = "KMS key for RDS encryption"
  enable_key_rotation     = true
  rotation_period_in_days = 90
}

# Alias for EC2 KMS Key
resource "aws_kms_alias" "ec2_key_alias" {
  name          = "alias/ec2-key-${random_string.kms_suffix.result}"
  target_key_id = aws_kms_key.ec2_key.key_id
}

# Alias for RDS KMS Key
resource "aws_kms_alias" "rds_key_alias" {
  name          = "alias/rds-key-${random_string.kms_suffix.result}"
  target_key_id = aws_kms_key.rds_key.key_id
}

# Alias for S3 KMS Key
resource "aws_kms_alias" "s3_key_alias" {
  name          = "alias/s3-key-${random_string.kms_suffix.result}"
  target_key_id = aws_kms_key.s3_key.key_id
}

# Alias for Secrets Manager KMS Key
resource "aws_kms_alias" "secrets_key_alias" {
  name          = "alias/secrets-key-${random_string.kms_suffix.result}"
  target_key_id = aws_kms_key.secrets_key.key_id
}