# Variables for the module
variable "vpc_name" {
  description = "Unique name for the VPC and its resources"
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
  description = "List of availability zones to use"
  type        = list(string)
}

# Add the random_suffix variable to ensure uniqueness
variable "random_suffix" {
  description = "Random string to append for uniqueness"
  type        = string
}