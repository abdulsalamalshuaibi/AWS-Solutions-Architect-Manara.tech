terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  name = var.project_name
  tags = merge(var.tags, { Name = var.project_name })
}

# ========= VPC (module) =========
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.tags
}

data "aws_availability_zones" "available" {}

# ========= Security Groups =========
# ALB SG: يسمح HTTP من الإنترنت
resource "aws_security_group" "alb_sg" {
  name        = "${local.name}-alb-sg"
  description = "ALB security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# EC2 SG: يسمح 8080 من ALB فقط
resource "aws_security_group" "ec2_sg" {
  name        = "${local.name}-ec2-sg"
  description = "EC2 security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description      = "App traffic from ALB"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# ========= ALB & Target Group =========
resource "aws_lb" "this" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.alb_sg.id]
  idle_timeout       = 60
  enable_deletion_protection = false
  tags               = local.tags
}

resource "aws_lb_target_group" "app_tg" {
  name        = "${local.name}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    matcher             = "200-399"
    port                = "traffic-port"
    unhealthy_threshold = 3
    healthy_threshold   = 3
    timeout             = 5
  }

  tags = local.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# ========= IAM Role for EC2 (SSM + CloudWatch Agent) =========
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${local.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.tags
}

# سياسات مُدارة من AWS
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
  tags = local.tags
}

# ========= AMI (Amazon Linux 2 latest) =========
data "aws_ssm_parameter" "amzn2_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

# ========= Launch Template =========
resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-lt-"
  image_id      = data.aws_ssm_parameter.amzn2_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = filebase64("${path.module}/user_data.sh")

  network_interfaces {
    security_groups = [aws_security_group.ec2_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.tags, { Role = "app-server" })
  }

  tags = local.tags
}

# ========= Auto Scaling Group =========
resource "aws_autoscaling_group" "app" {
  name                      = "${local.name}-asg"
  max_size                  = var.asg_max
  min_size                  = var.asg_min
  desired_capacity          = var.asg_desired
  vpc_zone_identifier       = module.vpc.private_subnets
  health_check_type         = "ELB"
  health_check_grace_period = 120
  target_group_arns         = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  termination_policies = ["OldestInstance", "Default"]

  tag {
    key                 = "Name"
    value               = "${local.name}-ec2"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ========= Target Tracking Scaling (CPU 50%) =========
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${local.name}-cpu-target"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.app.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}

# ========= SNS (اختياري) + CloudWatch Alarms =========
resource "aws_sns_topic" "alarms" {
  count = length(var.alarms_email) > 0 ? 1 : 0
  name  = "${local.name}-alarms"
  tags  = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = length(var.alarms_email) > 0 ? 1 : 0
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarms_email
}

# CPU عالي على الـ ASG
resource "aws_cloudwatch_metric_alarm" "asg_cpu_high" {
  alarm_name          = "${local.name}-asg-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
  alarm_description = "High average ASG CPU"
  alarm_actions     = length(var.alarms_email) > 0 ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions        = length(var.alarms_email) > 0 ? [aws_sns_topic.alarms[0].arn] : []
  tags              = local.tags
}

# UnHealthyHostCount في Target Group
resource "aws_cloudwatch_metric_alarm" "tg_unhealthy" {
  alarm_name          = "${local.name}-tg-unhealthy"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = aws_lb_target_group.app_tg.arn_suffix
  }
  alarm_description = "Unhealthy targets detected"
  alarm_actions     = length(var.alarms_email) > 0 ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions        = length(var.alarms_email) > 0 ? [aws_sns_topic.alarms[0].arn] : []
  tags              = local.tags
}

# ========= (اختياري) RDS للشرح/الاختبار فقط =========
# ملاحظة: افتراضات مبسّطة؛ لا تستخدمه للإنتاج كما هو.
resource "aws_db_subnet_group" "this" {
  count      = var.enable_rds ? 1 : 0
  name       = "${local.name}-dbsubnets"
  subnet_ids = module.vpc.private_subnets
  tags       = local.tags
}

resource "aws_db_instance" "this" {
  count                        = var.enable_rds ? 1 : 0
  identifier                   = "${local.name}-db"
  engine                       = "mysql"
  engine_version               = "8.0"
  instance_class               = "db.t3.micro"
  allocated_storage            = 20
  username                     = "appuser"
  password                     = "ChangeMe12345!"
  db_subnet_group_name         = aws_db_subnet_group.this[0].name
  multi_az                     = false
  publicly_accessible          = false
  skip_final_snapshot          = true
  apply_immediately            = true
  deletion_protection          = false
  vpc_security_group_ids       = [aws_security_group.ec2_sg.id]
  storage_encrypted            = true
  backup_retention_period      = 0
  auto_minor_version_upgrade   = true
  copy_tags_to_snapshot        = true
  performance_insights_enabled = false
  tags                         = local.tags
}

