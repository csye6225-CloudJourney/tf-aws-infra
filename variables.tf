variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
}

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "vpc_name_prefix" {
  description = "Prefix for VPC name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones to use in the region"
  type        = list(string)
}

variable "custom_ami_id" {
  description = "Custom AMI ID for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type to use for the EC2 instance"
  type        = string
}

variable "db_password" {
  description = "The master password for the RDS instance"
  type        = string
  sensitive   = true
}

variable "key_name" {
  description = "AWS Key Pair for SSH access"
  type        = string
}

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = 5
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_cooldown" {
  description = "Cooldown period for the Auto Scaling Group (in seconds)"
  type        = number
  default     = 60
}

variable "app_port" {
  description = "Port on which the web application listens"
  type        = number
  default     = 8080
}

#variable "hosted_zone_id" {
# description = "The hosted zone ID for Route 53."
#type        = string
#}

variable "sendgrid_api_key" {
  description = "SendGrid API key for sending emails"
  type        = string
  sensitive   = true
}

variable "lambda_zip_file" {
  description = "Path to the Lambda zip file"
  type        = string
}