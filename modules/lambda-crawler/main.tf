#------------------------------------------------------------------------------
# ECR Repository
#------------------------------------------------------------------------------
resource "aws_ecr_repository" "crawler" {
  name                 = "${var.project_name}-${var.environment}-crawler"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-crawler"
  }
}

# Keep only the last 10 images to save storage costs
resource "aws_ecr_lifecycle_policy" "crawler" {
  repository = aws_ecr_repository.crawler.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# IAM Role for Lambda
#------------------------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-${var.environment}-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-crawler-role"
  }
}

# Lambda execution role with VPC access + CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

#------------------------------------------------------------------------------
# Lambda Functions (Docker/ECR) — one per memory tier
#
# BOOTSTRAP: On first deploy, push an image to ECR before running terraform apply:
#   aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin <account>.dkr.ecr.ap-northeast-2.amazonaws.com
#   docker build -t <account>.dkr.ecr.ap-northeast-2.amazonaws.com/devport-<env>-crawler:latest .
#   docker push <account>.dkr.ecr.ap-northeast-2.amazonaws.com/devport-<env>-crawler:latest
#------------------------------------------------------------------------------
locals {
  # Flatten: source name → tier key
  source_to_tier = merge([
    for tier, cfg in var.crawler_tiers : {
      for source in cfg.sources : source => tier
    }
  ]...)
}

resource "aws_lambda_function" "crawler" {
  for_each = var.crawler_tiers

  function_name = "${var.project_name}-${var.environment}-${each.key}"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.crawler.repository_url}:latest"
  timeout       = var.timeout
  memory_size   = each.value.memory_size
  architectures = ["arm64"]

  environment {
    variables = merge(
      {
        # Database
        DATABASE_URL = "postgresql://${var.db_user}:${var.db_password}@${var.db_host}:${var.db_port}/${var.db_name}"

        # API Keys
        OPENAI_API_KEY              = var.openai_api_key
        GITHUB_TOKEN                = var.github_token
        ARTIFICIAL_ANALYSIS_API_KEY = var.artificial_analysis_api_key

        # Webhooks
        DISCORD_WEBHOOK_URL = var.discord_webhook_url
      },
      var.extra_env_vars
    )
  }

  # VPC configuration for private subnet access
  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  # CI/CD manages the image — don't revert on terraform apply
  lifecycle {
    ignore_changes = [image_uri]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups — one per tier
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "crawler" {
  for_each = var.crawler_tiers

  name              = "/aws/lambda/${aws_lambda_function.crawler[each.key].function_name}"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-logs"
  }
}

#------------------------------------------------------------------------------
# EventBridge — one rule per crawler source, routed to the correct Lambda tier
#------------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "crawler" {
  for_each = local.source_to_tier

  name                = "${var.project_name}-${var.environment}-crawler-${each.key}"
  description         = "Trigger crawler Lambda for source: ${each.key}"
  schedule_expression = var.schedule_expression

  tags = {
    Name = "${var.project_name}-${var.environment}-crawler-${each.key}"
  }
}

resource "aws_cloudwatch_event_target" "crawler" {
  for_each = local.source_to_tier

  rule      = aws_cloudwatch_event_rule.crawler[each.key].name
  target_id = "crawler-${each.key}"
  arn       = aws_lambda_function.crawler[each.value].arn

  input = jsonencode({
    source = each.key
  })
}

resource "aws_lambda_permission" "eventbridge" {
  for_each = local.source_to_tier

  statement_id  = "AllowEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crawler[each.value].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.crawler[each.key].arn
}

#------------------------------------------------------------------------------
# Lambda Function URLs (Optional — for manual invocation in dev)
#------------------------------------------------------------------------------
resource "aws_lambda_function_url" "crawler" {
  for_each = var.enable_function_url ? var.crawler_tiers : {}

  function_name      = aws_lambda_function.crawler[each.key].function_name
  authorization_type = "AWS_IAM"

  cors {
    allow_origins = ["https://${var.api_domain}"]
    allow_methods = ["POST"]
    max_age       = 3600
  }
}
