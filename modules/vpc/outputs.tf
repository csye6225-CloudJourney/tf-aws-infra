# Output for Application Security Group
output "app_sg" {
  description = "The application security group"
  value       = aws_security_group.app_sg.id
}

# Output for Public Subnets
output "public_subnets" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public_subnet[*].id
}

# Output the VPC name
output "vpc_name" {
  description = "The VPC name"
  value       = var.vpc_name
}

# Output the random suffix
output "random_suffix" {
  description = "Random suffix for naming uniqueness"
  value       = var.random_suffix
}