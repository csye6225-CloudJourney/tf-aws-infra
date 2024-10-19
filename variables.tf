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