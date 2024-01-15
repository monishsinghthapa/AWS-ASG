provider "aws" {
  region = "us-east-1"
}

variable "cidr" {
  default = "10.0.0.0/16"
}

resource "aws_vpc" "myvpc" {
  cidr_block = var.cidr
}

resource "aws_subnet" "sub1" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id
}

resource "aws_route_table" "RT" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta1" {
  subnet_id      = aws_subnet.sub1.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_security_group" "webSg" {
  name   = "web"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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
    Name = "Web-sg"
  }
}

resource "aws_launch_configuration" "test" {
  name = "test_config"
  image_id = "ami-0c7217cdde317cfec"
  instance_type = "t2.micro"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
  desired_capacity     = 2
  max_size             = 5
  min_size             = 2
  vpc_zone_identifier  = [aws_subnet.sub1.id]
  launch_configuration = aws_launch_configuration.test.id

  health_check_type          = "EC2"
  health_check_grace_period  = 300
  force_delete               = true
}

resource "aws_autoscaling_schedule" "daily_refresh" {
  scheduled_action_name  = "daily_refresh"
  min_size               = 0  
  max_size               = 0  
  desired_capacity       = 0 
  recurrence             = "0 0 * * *"  # Everyday at UTC 12am

  autoscaling_group_name = aws_autoscaling_group.example.name
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale_up"
  scaling_adjustment    = 1
  cooldown              = 300
  adjustment_type       = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.example.name

}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale_down"
  scaling_adjustment    = -1
  cooldown              = 300
  adjustment_type       = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.example.name

}

resource "aws_cloudwatch_metric_alarm" "high_load" {
  alarm_name          = "high_load"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "load_average_5min" # Custom metric name collected by CloudWatch Agent
  namespace           = "Custom"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  actions_enabled     = true

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "low_load" {
  alarm_name          = "low_load"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "load_average_5min"
  namespace           = "Custom"
  period              = 300
  statistic           = "Average"
  threshold           = 50
  actions_enabled     = true

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_down.arn]
}

resource "aws_ses_email_identity" "example" {
  email = "monishthapa123@gmail.com"
}

resource "aws_sns_topic" "example" {
  name = "autoscaling_alerts"
}

resource "aws_sns_topic_subscription" "scale_up_subscription" {
  topic_arn = aws_sns_topic.example.arn
  protocol  = "email"
  endpoint  = "monishthapa123@gmail.com"
}

resource "aws_sns_topic_subscription" "scale_down_subscription" {
  topic_arn = aws_sns_topic.example.arn
  protocol  = "email"
  endpoint  = "monishthapa123@gmail.com"
}

# Attach SES email to the AutoScalingGroup
resource "aws_autoscaling_notification" "scale_up_notification" {
  group_names = [aws_autoscaling_group.example.name]
  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
  ]
  topic_arn = aws_sns_topic.example.arn
}

resource "aws_autoscaling_notification" "scale_down_notification" {
  group_names = [aws_autoscaling_group.example.name]
  notifications = [
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]
  topic_arn = aws_sns_topic.example.arn
}