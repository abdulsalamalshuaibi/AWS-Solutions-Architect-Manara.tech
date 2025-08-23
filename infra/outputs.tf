output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "Public URL of the ALB"
}

output "asg_name" {
  value       = aws_autoscaling_group.app.name
  description = "Auto Scaling Group name"
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID"
}
