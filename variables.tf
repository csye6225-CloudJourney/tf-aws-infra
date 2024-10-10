variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
}

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-1"
}

variable "vpc_name" {
  description = "Unique name for the VPC"
  type        = string
}

variable "vpc_cidrs" {
  description = "Map of regions to VPC CIDR blocks"
  type        = map(string)
}

variable "public_subnet_cidrs_list" {
  description = "Map of regions to lists of CIDR blocks for public subnets"
  type        = map(list(string))
}

variable "private_subnet_cidrs_list" {
  description = "Map of regions to lists of CIDR blocks for private subnets"
  type        = map(list(string))
}

variable "availability_zones_list" {
  description = "Map of regions to lists of availability zones"
  type        = map(list(string))
}