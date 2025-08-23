variable "project_name" {
  description = "Project name used for tagging and naming"
  type        = string
  default     = "grad-ec2-alb-asg"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Public subnets CIDRs (2 AZs)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "Private subnets CIDRs (2 AZs)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "asg_min" {
  type        = number
  default     = 2
}

variable "asg_desired" {
  type        = number
  default     = 2
}

variable "asg_max" {
  type        = number
  default     = 4
}

variable "enable_rds" {
  description = "Toggle to create RDS (demo only)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {
    Project     = "GradProject"
    Environment = "dev"
    Owner       = "Student"
  }
}

variable "alarms_email" {
  description = "Email to subscribe to SNS for alarms (optional)"
  type        = string
  default     = ""
}
