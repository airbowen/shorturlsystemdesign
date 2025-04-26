# infrastructure/main.tf

provider "aws" {
  region = var.aws_region
}

# VPC and Network Setup
resource "aws_vpc" "url_shortener_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  
  tags = {
    Name = "url-shortener-vpc"
  }
}

# Create public subnets in different AZs
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.url_shortener_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "url-shortener-public-subnet-a"
  }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.url_shortener_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "url-shortener-public-subnet-b"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.url_shortener_vpc.id
  
  tags = {
    Name = "url-shortener-igw"
  }
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.url_shortener_vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  
  tags = {
    Name = "url-shortener-public-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "public_rta_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rta_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group for EC2 instances
resource "aws_security_group" "app_sg" {
  name        = "url-shortener-app-sg"
  description = "Security group for URL shortener app"
  vpc_id      = aws_vpc.url_shortener_vpc.id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "url-shortener-app-sg"
  }
}

# Security Group for Redis
resource "aws_security_group" "redis_sg" {
  name        = "url-shortener-redis-sg"
  description = "Security group for Redis cache"
  vpc_id      = aws_vpc.url_shortener_vpc.id
  
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "url-shortener-redis-sg"
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "url_mapping" {
  name           = "URLMapping"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "shortCode"
  
  attribute {
    name = "shortCode"
    type = "S"
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = {
    Name = "url-shortener-dynamodb"
  }
}

# Auto Scaling for DynamoDB
resource "aws_appautoscaling_target" "dynamodb_table_read_target" {
  max_capacity       = 100
  min_capacity       = 20
  resource_id        = "table/${aws_dynamodb_table.url_mapping.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_read_policy" {
  name               = "DynamoDBReadCapacityUtilization:${aws_appautoscaling_target.dynamodb_table_read_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_read_target.resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_read_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_read_target.service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    
    target_value = 70.0
  }
}

resource "aws_appautoscaling_target" "dynamodb_table_write_target" {
  max_capacity       = 100
  min_capacity       = 20
  resource_id        = "table/${aws_dynamodb_table.url_mapping.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_write_policy" {
  name               = "DynamoDBWriteCapacityUtilization:${aws_appautoscaling_target.dynamodb_table_write_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_write_target.resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_write_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_write_target.service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    
    target_value = 70.0
  }
}

# ElastiCache Redis Cluster
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "url-shortener-redis-subnet-group"
  subnet_ids = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
}

resource "aws_elasticache_replication_group" "redis_cluster" {
  replication_group_id          = "url-shortener-redis"
  replication_group_description = "Redis cluster for URL shortener"
  node_type                     = "cache.t3.small"
  number_cache_clusters         = 2
  parameter_group_name          = "default.redis6.x"
  engine_version                = "6.x"
  port                          = 6379
  multi_az_enabled              = true
  automatic_failover_enabled    = true
  subnet_group_name             = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids            = [aws_security_group.redis_sg.id]
  
  tags = {
    Name = "url-shortener-redis"
  }
}

# Application Load Balancer
resource "aws_lb" "app_lb" {
  name               = "url-shortener-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_sg.id]
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  
  enable_deletion_protection = false
  
  tags = {
    Name = "url-shortener-alb"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "url-shortener-target-group"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.url_shortener_vpc.id
  
  health_check {
    enabled             = true
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Launch Template for EC2 instances
resource "aws_launch_template" "app_launch_template" {
  name_prefix   = "url-shortener-"
  image_id      = var.ami_id
  instance_type = "t3.small"
  
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }
  
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "Starting URL Shortener app setup..."
    sudo apt-get update
    sudo apt-get install -y nodejs npm git
    
    # Clone repository
    git clone https://github.com/your-repo/url-shortener.git /home/ubuntu/url-shortener
    
    # Set environment variables
    cat > /home/ubuntu/url-shortener/.env << 'ENVFILE'
    PORT=3000
    AWS_REGION=${var.aws_region}
    DYNAMODB_TABLE=${aws_dynamodb_table.url_mapping.name}
    REDIS_HOST=${aws_elasticache_replication_group.redis_cluster.primary_endpoint_address}
    REDIS_PORT=6379
    ENVFILE
    
    # Install dependencies and start app
    cd /home/ubuntu/url-shortener
    npm install
    npm install pm2 -g
    pm2 start app.js
    pm2 startup
    pm2 save
  EOF
  )
  
  tag_specifications {
    resource_type = "instance"
    
    tags = {
      Name = "url-shortener-instance"
    }
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  name                = "url-shortener-asg"
  vpc_zone_identifier = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  desired_capacity    = 2
  min_size            = 2
  max_size            = 10
  
  launch_template {
    id      = aws_launch_template.app_launch_template.id
    version = "$Latest"
  }
  
  target_group_arns = [aws_lb_target_group.app_tg.arn]
  
  health_check_type         = "ELB"
  health_check_grace_period = 300
  
  tag {
    key                 = "Name"
    value               = "url-shortener-instance"
    propagate_at_launch = true
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "url-shortener-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
  
  alarm_description = "Scale up if CPU > 70% for 4 minutes"
  alarm_actions     = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "url-shortener-low-cpu"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 30
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
  
  alarm_description = "Scale down if CPU < 30% for 4 minutes"
  alarm_actions     = [aws_autoscaling_policy.scale_down.arn]
}

# IAM Role for EC2 to access DynamoDB and other AWS services
resource "aws_iam_role" "ec2_role" {
  name = "url-shortener-ec2-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "dynamodb_policy" {
  name        = "url-shortener-dynamodb-policy"
  description = "Policy for accessing DynamoDB"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.url_mapping.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dynamodb_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.dynamodb_policy.arn
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "url-shortener-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# Route53 Setup
resource "aws_route53_zone" "primary" {
  name = var.domain_name
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = var.domain_name
  type    = "A"
  
  alias {
    name                   = aws_lb.app_lb.dns_name
    zone_id                = aws_lb.app_lb.zone_id
    evaluate_target_health = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "url_shortener" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "URL Shortener Distribution"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  
  origin {
    domain_name = aws_lb.app_lb.dns_name
    origin_id   = "ALB"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB"
    
    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  
  aliases = [var.domain_name]
}

# Variables
variable "aws_region" {
  description = "The AWS region to deploy resources"
  default     = "us-east-1"
}

variable "ami_id" {
  description = "The AMI ID to use for EC2 instances"
  default     = "ami-0c55b159cbfafe1f0" # Ubuntu 20.04 LTS - update with latest AMI
}

variable "domain_name" {
  description = "The domain name for the URL shortener"
  default     = "shortenurl.org"
}

# Outputs
output "lb_dns_name" {
  value = aws_lb.app_lb.dns_name
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.url_shortener.domain_name
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.redis_cluster.primary_endpoint_address
}