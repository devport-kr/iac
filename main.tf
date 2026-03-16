#------------------------------------------------------------------------------
# DevPort Infrastructure - Root Module
#------------------------------------------------------------------------------

locals {
  api_domain = "${var.api_subdomain}.${var.domain_name}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#------------------------------------------------------------------------------
# Route 53 Zone ID Resolution
#------------------------------------------------------------------------------
locals {
  route53_zone_id = var.create_route53_zone ? aws_route53_zone.main[0].zone_id : var.route53_zone_id
}

# Create Route 53 Zone if needed
resource "aws_route53_zone" "main" {
  count = var.create_route53_zone ? 1 : 0

  name    = var.domain_name
  comment = "${var.project_name} ${var.environment} hosted zone"

  tags = {
    Name = "${var.project_name}-${var.environment}-zone"
  }
}

#------------------------------------------------------------------------------
# Networking Module
#------------------------------------------------------------------------------
module "networking" {
  source = "./modules/networking"

  project_name        = var.project_name
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone
  enable_flow_logs    = var.environment == "prod"
}

#------------------------------------------------------------------------------
# ACM Certificate Module (CloudFront - us-east-1)
#------------------------------------------------------------------------------
module "acm" {
  source = "./modules/acm"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project_name    = var.project_name
  environment     = var.environment
  domain_name     = var.domain_name
  route53_zone_id = local.route53_zone_id
  create_www_cert = true
}

#------------------------------------------------------------------------------
# S3 & CloudFront Module
#------------------------------------------------------------------------------
module "s3_cloudfront" {
  source = "./modules/s3-cloudfront"

  project_name           = var.project_name
  environment            = var.environment
  domain_name            = var.domain_name
  api_origin_domain_name = local.api_domain
  acm_certificate_arn    = module.acm.validated_certificate_arn
  price_class            = var.cloudfront_price_class
  enable_logging         = var.enable_cloudfront_logging
  enable_backup_bucket   = var.enable_backup_bucket
  backup_retention_days  = var.backup_retention_days

  depends_on = [module.acm]
}

#------------------------------------------------------------------------------
# EC2 Module
#------------------------------------------------------------------------------
module "ec2" {
  source = "./modules/ec2"

  project_name             = var.project_name
  environment              = var.environment
  instance_type            = var.instance_type
  ami_id                   = var.ec2_ami_id
  subnet_id                = module.networking.private_subnet_id
  security_group_id        = module.networking.ec2_security_group_id
  volume_size              = var.ec2_volume_size
  volume_type              = var.ec2_volume_type
  domain_name              = var.domain_name
  api_domain               = local.api_domain
  db_name                  = var.db_name
  db_user                  = var.db_user
  certbot_email            = var.certbot_email
  enable_backup            = var.enable_backup_bucket
  backup_bucket_arn        = var.enable_backup_bucket ? module.s3_cloudfront.backup_bucket_arn : ""
  backup_bucket_name       = var.enable_backup_bucket ? module.s3_cloudfront.backup_bucket_name : ""
  enable_cloudwatch_alarms = var.enable_cloudwatch_alarms
  cpu_alarm_threshold      = var.cpu_alarm_threshold
  sns_topic_arn            = var.alarm_email != "" ? aws_sns_topic.alarms[0].arn : ""

  depends_on = [module.networking, module.s3_cloudfront]
}

#------------------------------------------------------------------------------
# Public Proxy Module
#------------------------------------------------------------------------------
module "proxy" {
  source = "./modules/proxy"

  project_name      = var.project_name
  environment       = var.environment
  subnet_id         = module.networking.public_subnet_id
  security_group_id = module.networking.proxy_security_group_id
  api_domain        = local.api_domain
  backend_ip        = module.ec2.instance_private_ip
  certbot_email     = var.certbot_email

  depends_on = [module.ec2, module.networking]
}

#------------------------------------------------------------------------------
# Lambda Crawler Module
#------------------------------------------------------------------------------
module "lambda_crawler" {
  source = "./modules/lambda-crawler"

  project_name        = var.project_name
  environment         = var.environment
  api_domain          = local.api_domain
  schedule_expression = var.crawler_schedule
  timeout             = var.crawler_timeout
  memory_size         = var.crawler_memory_size
  enable_function_url = var.environment == "dev"

  # VPC configuration (private subnet with NAT Gateway)
  subnet_ids         = [module.networking.private_subnet_id]
  security_group_ids = [module.networking.lambda_security_group_id]

  # Database connection (via EC2 private IP)
  db_host            = module.ec2.instance_private_ip
  db_name            = var.db_name
  db_user            = var.db_user
  db_password        = var.db_password
  psycopg2_layer_arn = var.psycopg2_layer_arn

  depends_on = [module.ec2, module.networking]
}

#------------------------------------------------------------------------------
# Route 53 DNS Records
#------------------------------------------------------------------------------

# Frontend record (CloudFront)
resource "aws_route53_record" "frontend" {
  zone_id = local.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.s3_cloudfront.cloudfront_domain_name
    zone_id                = module.s3_cloudfront.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# WWW subdomain record
resource "aws_route53_record" "frontend_www" {
  zone_id = local.route53_zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.s3_cloudfront.cloudfront_domain_name
    zone_id                = module.s3_cloudfront.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# API record (Proxy Elastic IP)
resource "aws_route53_record" "api" {
  zone_id = local.route53_zone_id
  name    = local.api_domain
  type    = "A"
  ttl     = 300
  records = [module.proxy.elastic_ip]
}

#------------------------------------------------------------------------------
# SNS Topic for Alarms (Optional)
#------------------------------------------------------------------------------
resource "aws_sns_topic" "alarms" {
  count = var.alarm_email != "" ? 1 : 0

  name = "${var.project_name}-${var.environment}-alarms"

  tags = {
    Name = "${var.project_name}-${var.environment}-alarms"
  }
}

#------------------------------------------------------------------------------
# NAT Instance CloudWatch Alarm (SPOF mitigation — at least get alerted)
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "nat_status" {
  count = var.alarm_email != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-nat-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "NAT instance failed status check — EC2 and Lambda will lose internet access"

  dimensions = {
    InstanceId = module.networking.nat_instance_id
  }

  alarm_actions = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions    = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-alarm"
  }
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count = var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
