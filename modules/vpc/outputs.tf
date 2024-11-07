# Output for Application Security Group
output "app_sg" {
  description = "The application security group"
  value       = aws_security_group.app_sg.id
}

# Output for Database Security Group
output "db_sg" {
  description = "The database security group"
  value       = aws_security_group.db_sg.id
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

output "vpc_id" {
  description = "The VPC ID"
  value       = aws_vpc.my_vpc.id
}

# Output the random suffix
output "random_suffix" {
  description = "Random suffix for naming uniqueness"
  value       = var.random_suffix
}

# Output for Private Subnets
output "private_subnets" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private_subnet[*].id
}

# Output for Load Balancer SG
output "load_balancer_sg" {
  description = "The load balancer security group"
  value       = aws_security_group.load_balancer_sg.id
}