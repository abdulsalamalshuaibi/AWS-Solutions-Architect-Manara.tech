flowchart TB
    User["User Browser"] -->|HTTP| ALB["Application Load Balancer (Public Subnets)"]
    ALB -->|Forward :80| TG["Target Group :8080"]
    subgraph VPC["VPC (2 AZs)"]
      subgraph Public["Public Subnets"]
        ALB
      end
      subgraph Private["Private Subnets"]
        ASG["Auto Scaling Group (EC2 Instances)"]
        RDS["Amazon RDS (Optional)"]
      end
    end
    ASG -->|HTTP :8080| TG
    ASG --> RDS
    CloudWatch["CloudWatch + Alarms + SNS"] --> DevOps["Admin/DevOps"]
