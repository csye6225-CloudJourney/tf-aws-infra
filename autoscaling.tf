# Launch Template for Auto Scaling Group
resource "aws_launch_template" "csye6225_launch_template" {
  name = "csye6225_asg"

  image_id      = var.custom_ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = aws_kms_key.ec2_key.arn
      volume_size           = 8
      volume_type           = "gp2"
    }
  }

  # IAM Instance Profile
  iam_instance_profile {
    name = aws_iam_instance_profile.cloudwatch_agent_profile.name
  }

  # Security Group
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [module.vpc.app_sg] # Use output from vpc module
  }

  # User Data (Base64 Encoded)
  user_data = base64encode(<<-EOF
  #!/bin/bash
  exec > /var/log/user-data.log 2>&1
  set -x

  # Update package list and install necessary packages
  sudo apt-get update
  sudo apt-get install -y unzip curl

  # Install AWS CLI if not already installed
  if ! command -v aws &> /dev/null; then
    # Download and install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
  fi

  # Retrieve the DB password from Secrets Manager
  DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "${aws_secretsmanager_secret.db_password_secret.id}" --query SecretString --output text)

  # Export environment variables
  export DB_HOST="${aws_db_instance.mydb.address}"
  export DB_USERNAME="${aws_db_instance.mydb.username}"
  export DB_PASSWORD="$DB_PASSWORD"
  export DB_NAME="${aws_db_instance.mydb.db_name}"
  export S3_BUCKET_NAME="${aws_s3_bucket.csye6225_s3.bucket}"
  export SNS_TOPIC_ARN="${aws_sns_topic.email_verification_topic.arn}"

  # Write environment variables to /etc/environment
  echo "DB_HOST=${aws_db_instance.mydb.address}" >> /etc/environment
  echo "DB_USERNAME=${aws_db_instance.mydb.username}" >> /etc/environment
  echo "DB_PASSWORD=$DB_PASSWORD" >> /etc/environment
  echo "DB_NAME=${aws_db_instance.mydb.db_name}" >> /etc/environment
  echo "S3_BUCKET_NAME=${aws_s3_bucket.csye6225_s3.bucket}" >> /etc/environment
  echo "SNS_TOPIC_ARN=${aws_sns_topic.email_verification_topic.arn}" >> /etc/environment

  # Start the web application service
  sudo systemctl start webapp.service

  # Start and configure CloudWatch Agent
  sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
  EOF
  )
}

# Application Load Balancer
resource "aws_lb" "app_lb" {
  name               = "${var.vpc_name_prefix}-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.vpc.load_balancer_sg]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = {
    Name = "${var.vpc_name_prefix}-AppLoadBalancer"
  }
}

# Target Group for EC2 Instances
resource "aws_lb_target_group" "app_target_group" {
  name     = "${var.vpc_name_prefix}-app-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id # Use output from vpc module

  health_check {
    path                = "/healthz"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "${var.vpc_name_prefix}-AppTargetGroup"
  }
}

# Listener for Application Load Balancer
resource "aws_lb_listener" "app_lb_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_target_group.arn
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "csye6225_asg" {
  name                = "${var.vpc_name_prefix}-WebApp-ASG-${local.environment}"
  desired_capacity    = var.asg_desired_capacity
  max_size            = var.asg_max_size
  min_size            = var.asg_min_size
  health_check_type   = "ELB"
  vpc_zone_identifier = module.vpc.public_subnets
  launch_template {
    id      = aws_launch_template.csye6225_launch_template.id
    version = "$Latest"
  }

  # Associate instances with the target group
  target_group_arns = [aws_lb_target_group.app_target_group.arn]

  # Tagging instances in the Auto Scaling Group
  tag {
    key                 = "Name"
    value               = "${var.vpc_name_prefix}-WebApp-ASG-${local.environment}"
    propagate_at_launch = true
  }
}