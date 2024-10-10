variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
}

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "number_of_vpcs" {
  description = "Number of VPCs to create"
  type        = number
}

variable "vpc_name_prefix" {
  description = "Prefix for VPC names"
  type        = string
}

variable "vpc_cidrs" {
  description = "List of CIDR blocks for each VPC"
  type        = list(string)
}

variable "public_subnet_cidrs_list" {
  description = "List of lists of CIDR blocks for public subnets for each VPC"
  type        = list(list(string))
}

variable "private_subnet_cidrs_list" {
  description = "List of lists of CIDR blocks for private subnets for each VPC"
  type        = list(list(string))
}

variable "availability_zones_list" {
  description = "Map of regions to lists of availability zones"
  type        = map(list(string))
}